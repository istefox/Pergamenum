import Foundation

/// One saved view, as the Viste pane lists it.
///
/// Richer than `VaultAPI.ViewSummary`, which is what a connector prints: this one knows
/// the heading the view sits under and the line it is written on, because in a window a
/// list of views is only useful if the rows have names a person chose and if clicking one
/// lands on it.
struct ViewEntry: Identifiable, Equatable {
    let path: String
    let noteTitle: String
    /// Which block in the note, counting from zero.
    let ordinal: Int
    /// The line the opening fence is on, in the whole file: what the jump needs.
    let lineIndex: Int
    /// The nearest heading above the block. This is a view's name in practice - the
    /// grammar has no `title` key, and adding one would be a schema decision (§D1).
    let heading: String?
    let block: ViewBlock?
    let error: String?
    /// How many notes it finds right now. Nil when the block does not parse, because a
    /// view that cannot run has no count, and printing "0 note" would read as an empty
    /// vault rather than as a typo in the query.
    let matches: Int?

    var id: String { "\(path)#\(ordinal)" }

    /// What the row is called: the heading if the note gave the view one, the note's
    /// title otherwise - and then the ordinal, so two unnamed views in one note are two
    /// distinguishable rows rather than the same word twice.
    var name: String {
        if let heading, !heading.isEmpty { return heading }
        return ordinal == 0 ? noteTitle : "\(noteTitle) · vista \(ordinal + 1)"
    }
}

/// Where the views of a note are, in lines.
///
/// `ViewBlock.blocks(in:)` answers *what* they are and drops their position on the way,
/// which is fine for running one and useless for pointing at it. This walks the file
/// once, tracking fences so a `pergamenum-view` opener quoted inside another code block
/// is not counted, and keeps the heading in force at that point.
enum ViewCatalogue {
    struct Location: Equatable {
        let lineIndex: Int
        let heading: String?
    }

    /// What a renderer is called in the interface.
    ///
    /// Here rather than on `ViewBlock.Renderer`, which lives in `Core` and is compiled
    /// into both connectors: `perg` prints the grammar's own word, and an Italian label
    /// in `Core` would be interface leaking into the vocabulary a script parses. Here
    /// rather than on `ViewsPane` too - a `View` is main-actor isolated, and the slash
    /// menu's catalogue is a `static let` that is not.
    static func rendererName(_ render: ViewBlock.Renderer) -> String {
        switch render {
        case .table: "tabella"
        case .list: "elenco"
        case .gallery: "galleria"
        case .calendar: "calendario"
        case .board: "board"
        }
    }

    /// The fenced views of a whole file, in order, with the line each one opens on.
    static func locations(in text: String) -> [Location] {
        var found: [Location] = []
        var heading: String?
        var isInsideFence = false

        // The walk skips exactly the block `NoteDocument.parse` recognises, through the same
        // test (PG-276): `scan` pairs these locations by ordinal with the views of that body,
        // so a block read any other way - a CRLF one kept, an unterminated one skipped - would
        // pair a view with another view's line, or name it after a frontmatter comment.
        let lines = text.components(separatedBy: "\n")
        let bodyStart = FrontmatterSource.closingDelimiterIndex(in: lines).map { $0 + 1 } ?? 0

        for (index, line) in lines.enumerated() where index >= bodyStart {
            // One trailing `\r` goes, as the parser's `.newlines` split drops it, so a CRLF
            // note's fences are found and its headings carry no `\r` (ADR-0065 §D1.2, PG-276).
            // Not `isFirst`: the parser keeps a U+FEFF on a body's first line, so this does too.
            let trimmed = FrontmatterSource.interpreted(line).trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                // **Exactly what `MarkdownBlockParser` does**, deliberately: any line
                // opening with three backticks closes an open fence, whatever follows
                // them. It is not CommonMark to the letter, and it does not need to be -
                // what it needs is to count the same blocks the parser counts, because
                // the ordinals of the two lists are matched to each other. A walk that
                // was more correct than the parser would pair a view with another view's
                // line, which is worse than both being lenient in the same way.
                if isInsideFence {
                    isInsideFence = false
                } else {
                    isInsideFence = true
                    if CodeFence.language(declaredBy: trimmed) == ViewBlock.language {
                        found.append(Location(lineIndex: index, heading: heading))
                    }
                }
                continue
            }

            if !isInsideFence, trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if (1...6).contains(hashes) {
                    heading = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return found
    }
}

// MARK: - The scan

extension ViewCatalogue {
    /// Every view in the vault, in path order: reads each note once, parses the views in it,
    /// and runs each one for its count - the same scan `VaultAPI.views` does for the connector.
    ///
    /// On the main actor, where `VaultSession`'s reads stay (ADR-0041 §D12), and cooperative
    /// (PG-260): one note is one step, and after every `chunkSize` notes, when more remain, it
    /// awaits `pause` and checks for cancellation, so the pane's spinner draws and a newer scan
    /// or a day change stops this one. A cancelled scan throws and returns nothing.
    ///
    /// One step can still be long: `ViewEvaluator.evaluate` is synchronous and shared with the
    /// connectors, so a view with a `text()` filter reads the whole vault inside its note's step.
    @MainActor
    static func scan(
        _ session: VaultSession, today: CalendarDate = .today,
        chunkSize: Int = CooperativeLoop.chunkSize,
        pause: @MainActor () async -> Void = CooperativeLoop.pause
    ) async throws -> [ViewEntry] {
        try Task.checkCancellation()
        let records = session.index.allNotes.sorted { $0.relativePath < $1.relativePath }
        let chunkSize = max(chunkSize, 1)
        let body = { (candidate: NoteRecord) in try? session.read(candidate.relativePath).text }

        var entries: [ViewEntry] = []
        for (offset, record) in records.enumerated() {
            if offset > 0, offset.isMultiple(of: chunkSize) {
                await pause()
                try Task.checkCancellation()
            }
            guard let text = try? session.read(record.relativePath).text else { continue }
            let placed = Self.locations(in: text)
            let blocks = ViewBlock.blocks(in: NoteDocument.parse(text).body)
            for (ordinal, parsed) in blocks.enumerated() {
                entries.append(entry(
                    record, ordinal: ordinal, parsed: parsed,
                    location: ordinal < placed.count ? placed[ordinal] : nil,
                    corpus: session.index, today: today, text: body
                ))
            }
        }
        return entries
    }

    /// One catalogued view: a parsed block evaluated for its count, or a broken one listed
    /// with its error rather than hidden - a query with a typo in it is exactly the one
    /// somebody is looking for.
    static func entry(
        _ record: NoteRecord, ordinal: Int, parsed: Result<ViewBlock, ViewBlockError>,
        location: Location?, corpus: some ViewCorpus, today: CalendarDate = .today,
        text: (NoteRecord) -> String?
    ) -> ViewEntry {
        switch parsed {
        case .success(let block):
            let result = ViewEvaluator.evaluate(block, over: corpus, today: today, body: text)
            return ViewEntry(
                path: record.relativePath, noteTitle: record.title, ordinal: ordinal,
                lineIndex: location?.lineIndex ?? 0, heading: location?.heading,
                block: block, error: nil, matches: result.total
            )
        case .failure(let failure):
            return ViewEntry(
                path: record.relativePath, noteTitle: record.title, ordinal: ordinal,
                lineIndex: location?.lineIndex ?? 0, heading: location?.heading,
                block: nil, error: failure.description, matches: nil
            )
        }
    }
}
