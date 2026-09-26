import Foundation

/// Creating a note, bringing a file into the vault, and linking two notes to each
/// other. The three writes that add something rather than change something.
///
/// None of it touches the editor: creating a note and showing it are separate acts,
/// and only the facade knows there is an editor at all (ADR-0007 §D3).
extension VaultSession {
    enum CreationError: Error, CustomStringConvertible {
        case invalidTitle([NoteName.Violation])
        case alreadyExists(String)

        var description: String {
            switch self {
            // Each violation described on its own rather than the array interpolated:
            // interpolating a collection describes its elements the way a debugger
            // would, module name and all, and this sentence is read by a person.
            case .invalidTitle(let violations):
                "titolo non conforme: " + violations.map { "\($0)" }.joined(separator: ", ")
            case .alreadyExists(let path): "esiste già: \(path)"
            }
        }
    }

    /// Creates a note with a conformant frontmatter block already in place, and
    /// returns its path.
    ///
    /// The generated block is the closed four-key schema in fixed order, with the tag
    /// set the note's category requires (SPEC §4.3, tag.md 5.1): a daily note gets
    /// `type-note` alone, an inbox capture adds `status-inbox`, and an ordinary note
    /// gets `type-note` plus whatever topic the caller supplies.
    ///
    /// Refuses rather than sanitising silently: a title the rules reject is a decision
    /// for the user, and quietly renaming their note is how a vault fills with titles
    /// nobody chose.
    @discardableResult
    func createNote(
        title: String,
        in folder: String = "",
        date: CalendarDate,
        category: NoteCategory = .note,
        topics: [Tag] = [],
        body: String = ""
    ) async throws -> WriteResult {
        let violations = category == .daily
            ? NoteName.validateDaily(title)
            : NoteName.validate(title)
        guard violations.isEmpty else { throw CreationError.invalidTitle(violations) }

        let fileName = NoteName.fileName(for: title)
        let relativePath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        guard !exists(relativePath) else { throw CreationError.alreadyExists(relativePath) }

        var frontmatter = Frontmatter.empty
        frontmatter.date = date
        frontmatter.tags = TagRules.initialTags(for: category, topics: topics)

        // `render` already ends in `---\n`, so the added newline is the blank line every
        // note has had between its frontmatter and its text. With `body` empty - which is
        // every caller that does not pass a template - the bytes are exactly what this
        // wrote before templates existed, and a test pins that rather than trusting it.
        return try await write(
            FrontmatterSerializer.render(frontmatter) + "\n" + body, to: relativePath
        )
    }

    // MARK: Boards

    /// Creates an empty board and returns its path (ADR-0063 §D4): the connector's door,
    /// so a board creation honours `isDryRun` and is journalled like every other write.
    ///
    /// The name answers to the Workspace sheet's rule, the path is spelled by
    /// `CanvasStore.boardFilePath` and the bytes are `CanvasDocument.empty`, so neither can
    /// drift from the store's own creation. The taken-name check before the `await` is a
    /// filter, there so a rehearsal refuses what the real run would (ADR-0043 §D7); the
    /// guard is `expectingAbsent`, decided inside the actor. Nothing is rescanned: a board
    /// is not a note, and the caller decides whether the index needs to hear of it.
    ///
    /// Two differences from `CanvasStore.createBoard`, both deliberate:
    /// - a missing parent folder is **created** (§D4.7), as `createNote` creates one: a
    ///   connector's folder is typed text, where the store's is picked from a tree and a
    ///   vanished one must fail loudly (ADR-0025 §D1);
    /// - the app's own two board creations stay on the store (§D5): it arms no journal and
    ///   no dry run, so this door buys it nothing, and routing two synchronous UI closures
    ///   through an `async` door is the cascade ADR-0043's notes measured. Two paths, on
    ///   purpose - read §D5 before unifying them.
    ///
    /// The journal never deletes: undoing this creation is declined, as for a note.
    func createBoard(named name: String, in parent: String) async throws -> String {
        let violations = FolderName.validate(name)
        guard violations.isEmpty else { throw CreationError.invalidTitle(violations) }

        let relativePath = CanvasStore.boardFilePath(named: name, in: parent)
        // An escaping parent is refused here, before anything else and on a rehearsal too.
        _ = try store.url(for: relativePath)
        guard !exists(relativePath) else { throw CreationError.alreadyExists(relativePath) }

        try await writeFile(
            String(decoding: try CanvasDocument.empty.encoded(), as: UTF8.self),
            to: relativePath,
            expectingAbsent: true
        )
        return relativePath
    }

    // MARK: Daily notes

    /// Where the daily note of a day lives, whether or not it exists yet.
    func dailyNotePath(for day: CalendarDate) -> String {
        let fileName = NoteName.dailyFileName(for: day)
        return settings.dailyFolder.isEmpty ? fileName : "\(settings.dailyFolder)/\(fileName)"
    }

    /// The path of a day's note, created from the template when it is not there yet
    /// (SPEC §8.1).
    @discardableResult
    func dailyNote(for date: CalendarDate) async throws -> String {
        let relativePath = dailyNotePath(for: date)
        if exists(relativePath) { return relativePath }
        return try await createNote(
            title: date.compactForm,
            in: settings.dailyFolder,
            date: date,
            category: .daily
        ).path
    }

    // MARK: Files brought in

    /// Copies a dropped file into the folder of the note being edited and returns its
    /// name for the embed (SPEC §5).
    ///
    /// Copied, not referenced in place: an embed that pointed outside the vault would
    /// break the day the file moves or the volume is not mounted, and the vault would
    /// stop being self-contained.
    func importFile(_ source: URL, near notePath: String) -> String? {
        let folder = (notePath as NSString).deletingLastPathComponent
        // Through the boundary before `uniqueFileName` probes the folder (ADR-0063 §D7): a
        // note path escaping the vault copied the file outside it. An empty folder is the
        // root itself, which the resolver refuses by design and no caller input spells.
        let directory: URL
        do {
            directory = folder.isEmpty ? store.root : try store.url(for: folder)
        } catch {
            recordProblem("copia di \(source.lastPathComponent): \(error)")
            return nil
        }

        let name = ImportNaming.uniqueFileName(source.lastPathComponent, in: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: source, to: directory.appending(path: name, directoryHint: .notDirectory)
            )
            return name
        } catch {
            recordProblem("copia di \(source.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes an image from the clipboard into the vault beside a note and returns its
    /// file name for the embed.
    ///
    /// A screenshot has no file to drop, so without this it could not enter a note at
    /// all. It goes through a temporary file because the import path copies files, and
    /// one code path for both means a pasted picture is named and placed exactly like a
    /// dropped one.
    func importPastedImage(_ data: Data, near notePath: String) -> String? {
        let temporary = FileManager.default.temporaryDirectory
            .appending(path: ImportNaming.pastedImageFileName(on: .today), directoryHint: .notDirectory)
        do {
            try data.write(to: temporary, options: .atomic)
        } catch {
            recordProblem("immagine incollata: \(error.localizedDescription)")
            return nil
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        return importFile(temporary, near: notePath)
    }

    // MARK: Tags

    /// The tags the editor offers after a `#`, most useful first.
    ///
    /// Values already in the vault come first (SPEC §4.4, open families), then the
    /// closed vocabulary so a value outside it is never suggested. Here rather than in
    /// one view because two editors need the same list, and a second copy of this is a
    /// copy that drifts.
    var tagSuggestions: [String] {
        let used = index.tagUsage().map { "#\($0.tag.description)" }
        let closed = vocabulary.type.map { "#type-\($0)" }
            + vocabulary.status.map { "#status-\($0)" }
            + vocabulary.area.map { "#area-\($0)" }
            + vocabulary.source.map { "#source-\($0)" }
        // Registered, non-archived categories (ADR-0047 §D5, SPEC "UI flows": "typing
        // `#project-` in the editor offers the registered slugs") - a category with no
        // task tagged yet is still absent from `used`, so it needs its own source
        // rather than riding along with it.
        let registeredCategories = categories.entries.filter { !$0.archived }.map { "#project-\($0.slug)" }
        var seen = Set<String>()
        return (used + closed.sorted() + registeredCategories.sorted()).filter { seen.insert($0).inserted }
    }

    // MARK: Structural links

    /// Creates a structural link in both directions (wikilink.md W-05).
    ///
    /// Both files are rendered in memory first, so a link neither side can take - an
    /// unreadable file, a render that refuses - writes nothing. A half-created link is worse
    /// than none, because the linter would then report a discrepancy the app itself caused.
    ///
    /// **Not atomic across the two writes** (ADR-0057 §D8, #496). Each write carries
    /// `expecting:` its own file's read hash, so a writer landing between a read and its
    /// write is refused rather than overwritten. A refusal on the first write leaves both
    /// files untouched; a refusal on the second leaves the source already linked and the
    /// target not - named in the problem list, not rolled back, since the rollback would be
    /// one more guarded write that can itself be refused. `written` still holds whatever
    /// landed before the refusal, so the editor's tab catch-up sees it (ADR-0058 §D5).
    @discardableResult
    func addStructuralLink(
        from sourcePath: String,
        to targetTitle: String,
        reason: String,
        reverseReason: String
    ) async -> (created: Bool, written: [WriteResult]) {
        guard let targetPath = index.resolve(title: targetTitle).first else {
            recordProblem("nessuna nota si chiama «\(targetTitle)»")
            return (false, [])
        }
        guard targetPath != sourcePath else {
            recordProblem("\(RelatedLink.Error.linkingToItself)")
            return (false, [])
        }

        // Every write that reached disk, in order, even when a later one fails: the editor
        // catches up with the half that landed, or a stale buffer's next save undoes it
        // (ADR-0058 §D5).
        var written: [WriteResult] = []
        do {
            let source = try read(sourcePath)
            let target = try read(targetPath)

            // Both renders happen before either write.
            let updatedSource = try RelatedLink.add(
                target: target.record.title, reason: reason,
                to: source.text, selfTitle: source.record.title
            )
            let updatedTarget = try RelatedLink.add(
                target: source.record.title, reason: reverseReason,
                to: target.text, selfTitle: target.record.title
            )

            do {
                written.append(try await write(updatedSource, to: sourcePath, expecting: source.record.contentHash))
            } catch let refusal as VaultSession.WriteRefusal {
                recordProblem("legame strutturale non scritto: \(refusal)")
                return (false, written)
            }
            do {
                written.append(try await write(updatedTarget, to: targetPath, expecting: target.record.contentHash))
            } catch let refusal as VaultSession.WriteRefusal {
                recordProblem(
                    "legame strutturale scritto a metà: «\(sourcePath)» punta a «\(targetPath)», "
                        + "ma il ritorno no - \(refusal)"
                )
                return (false, written)
            }
            return (true, written)
        } catch {
            recordProblem("legame strutturale: \(error)")
            return (false, written)
        }
    }
}
