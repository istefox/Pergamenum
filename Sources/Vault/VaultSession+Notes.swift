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
        topics: [Tag] = []
    ) throws -> WriteResult {
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

        return try write(FrontmatterSerializer.render(frontmatter) + "\n", to: relativePath)
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
    func dailyNote(for date: CalendarDate) throws -> String {
        let relativePath = dailyNotePath(for: date)
        if exists(relativePath) { return relativePath }
        return try createNote(
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
        var seen = Set<String>()
        return (used + closed.sorted()).filter { seen.insert($0).inserted }
    }

    // MARK: Structural links

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
        guard let targetPath = index.resolve(title: targetTitle).first else {
            recordProblem("nessuna nota si chiama «\(targetTitle)»")
            return false
        }
        guard targetPath != sourcePath else {
            recordProblem("\(RelatedLink.Error.linkingToItself)")
            return false
        }

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

            try write(updatedSource, to: sourcePath)
            try write(updatedTarget, to: targetPath)
            return true
        } catch {
            recordProblem("legame strutturale: \(error)")
            return false
        }
    }
}
