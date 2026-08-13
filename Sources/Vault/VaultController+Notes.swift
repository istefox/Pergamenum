import Foundation

/// Creating a note, bringing a file into the vault, and linking two notes to each
/// other. The three writes that add something rather than change something.
extension VaultController {
    /// Creates a note with a conformant frontmatter block already in place.
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
        topics: [Tag] = []
    ) throws -> String {
        guard let store else { throw CreationError.alreadyExists("nessuna cartella note aperta") }

        let violations = category == .daily
            ? NoteName.validateDaily(title)
            : NoteName.validate(title)
        guard violations.isEmpty else { throw CreationError.invalidTitle(violations) }

        let fileName = NoteName.fileName(for: title)
        let relativePath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        guard !FileManager.default.fileExists(
            atPath: store.url(for: relativePath).path(percentEncoded: false)
        ) else { throw CreationError.alreadyExists(relativePath) }

        var frontmatter = Frontmatter.empty
        frontmatter.date = date
        frontmatter.tags = TagRules.ordered([Tag(namespace: .type, value: "note")] + topics + (
            category == .capture ? [Tag(namespace: .status, value: "inbox")] : []
        ))

        let text = FrontmatterSerializer.render(frontmatter) + "\n"
        let hash = try store.write(text, to: relativePath)
        selfWrittenHashes[relativePath] = hash

        index.update(try store.read(relativePath).record, at: relativePath)
        openNote(at: relativePath)
        return relativePath
    }

    /// Copies a dropped file into the folder of the note being edited and returns its
    /// name for the embed (SPEC §5).
    ///
    /// Copied, not referenced in place: an embed that pointed outside the vault would
    /// break the day the file moves or the volume is not mounted, and the vault would
    /// stop being self-contained.
    func importFileIntoVault(_ source: URL, near notePath: String) -> String? {
        guard let store else { return nil }
        let folder = (notePath as NSString).deletingLastPathComponent
        let directory = folder.isEmpty
            ? store.root
            : store.root.appending(path: folder, directoryHint: .isDirectory)

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

    /// Creates a structural link in both directions (wikilink.md W-05).
    ///
    /// Atomic by construction: both files are rendered in memory first and neither is
    /// written unless both can be. A half-created link is worse than none, because the
    /// linter would then report a discrepancy the app itself caused.
    @discardableResult
    func addStructuralLink(
        from sourcePath: String,
        to targetTitle: String,
        reason: String,
        reverseReason: String
    ) -> Bool {
        guard let store else { return false }
        guard let targetPath = index.resolve(title: targetTitle).first else {
            recordProblem("nessuna nota si chiama «\(targetTitle)»")
            return false
        }
        guard targetPath != sourcePath else {
            recordProblem("\(RelatedLink.Error.linkingToItself)")
            return false
        }

        do {
            let source = try store.read(sourcePath)
            let target = try store.read(targetPath)

            // Both renders happen before either write.
            let updatedSource = try RelatedLink.add(
                target: target.record.title, reason: reason,
                to: source.text, selfTitle: source.record.title
            )
            let updatedTarget = try RelatedLink.add(
                target: source.record.title, reason: reverseReason,
                to: target.text, selfTitle: target.record.title
            )

            selfWrittenHashes[sourcePath] = try store.write(updatedSource, to: sourcePath)
            selfWrittenHashes[targetPath] = try store.write(updatedTarget, to: targetPath)

            index.update(try store.read(sourcePath).record, at: sourcePath)
            index.update(try store.read(targetPath).record, at: targetPath)

            if openNote?.relativePath == sourcePath { openNote(at: sourcePath) }
            return true
        } catch {
            recordProblem("legame strutturale: \(error)")
            return false
        }
    }
}
