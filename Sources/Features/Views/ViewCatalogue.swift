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
        var isInFrontmatter = false

        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // The frontmatter's own `---` delimiters are not a horizontal rule and its
            // keys are not headings; skipping it here keeps both out of the walk.
            if index == 0, trimmed == "---" {
                isInFrontmatter = true
                continue
            }
            if isInFrontmatter {
                if trimmed == "---" { isInFrontmatter = false }
                continue
            }

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
