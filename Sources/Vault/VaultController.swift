import Foundation
import Observation
import OSLog
import SwiftUI

/// Owns the open vault: settings, index, watcher, and the read/write path the editor
/// goes through.
@MainActor
@Observable
final class VaultController {
    private(set) var root: URL?
    private(set) var settings = VaultSettings.default
    private(set) var vocabulary = Vocabulary.empty
    let index = NoteIndex()

    private(set) var isScanning = false
    /// Problems worth showing: an unreadable note, a settings file that would not
    /// parse, a vocabulary that could not be loaded.
    private(set) var problems: [String] = []

    /// The note currently open in the editor.
    private(set) var openNote: OpenNote?
    /// Set by the New Note command; the browser shows the naming sheet when true.
    var isCreatingNote = false
    /// Set by the Anteprima rapida command (SPEC §10, Vista menu). The Workspace
    /// watches it so the panel can be opened from the menu as well as the spacebar.
    var isShowingQuickLook = false
    /// Set by the Cattura rapida command (SPEC §7.4, Cmd+Shift+N).
    var isCapturingTask = false
    /// Set by the "Nota correlata…" command.
    var isAddingRelatedLink = false
    /// Set by the global search command (Cmd+Shift+F).
    var isShowingGlobalSearch = false
    /// Set by the quick switcher command.
    ///
    /// Both live here rather than as view state because their shortcuts are menu
    /// commands: `onKeyPress` only fires when the view holds focus, so Cmd+O did
    /// nothing while the cursor was in the editor, which is exactly when it is wanted.
    var isShowingQuickSwitcher = false

    /// Hashes the app itself wrote, keyed by path. A watcher event whose file hashes
    /// to the recorded value is the app's own write coming back and is ignored.
    private var selfWrittenHashes: [String: String] = [:]

    private var watcher: VaultWatcher?
    private var store: NoteStore?

    struct OpenNote: Equatable, Sendable {
        var relativePath: String
        var title: String
        /// The text as the editor has it, which may differ from disk while editing.
        var text: String
        /// The text as last read from or written to disk.
        var savedText: String
        /// An external change arrived while this note had unsaved edits. The editor
        /// must ask rather than merging or discarding either side (ADR-0001 §D3.4).
        var externalChangePending: String?

        var hasUnsavedChanges: Bool { text != savedText }
    }

    // MARK: Opening

    func open(_ url: URL) async {
        watcher?.stop()
        watcher = nil
        problems = []

        root = url
        store = NoteStore(root: url)
        loadSettings(from: url)
        loadVocabulary(from: url)
        await rescan()
        startWatching(url)

        if let route = pendingRoute {
            pendingRoute = nil
            handle(route)
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        root = nil
        store = nil
        openNote = nil
        selfWrittenHashes.removeAll()
        index.replaceAll(with: .init(records: [], failures: []), duration: .zero)
    }

    /// Full rebuild from disk. Cheap by design, and the answer to any doubt about the
    /// index being stale (SPEC §12, "rigenera indice").
    func rescan() async {
        guard let root else { return }
        isScanning = true
        defer { isScanning = false }

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await Task.detached(priority: .userInitiated) {
            VaultScanner(root: root).scan()
        }.value
        index.replaceAll(with: outcome, duration: clock.now - start)
    }

    // MARK: Notes

    func openNote(at relativePath: String) {
        guard let store else { return }
        do {
            let (record, text) = try store.read(relativePath)
            openNote = OpenNote(
                relativePath: relativePath,
                title: record.title,
                text: text,
                savedText: text,
                externalChangePending: nil
            )
            index.update(record, at: relativePath)
        } catch {
            problems.append("\(relativePath): \(error)")
        }
    }

    func updateOpenNoteText(_ text: String) {
        openNote?.text = text
    }

    enum CreationError: Error, CustomStringConvertible {
        case invalidTitle([NoteName.Violation])
        case alreadyExists(String)

        var description: String {
            switch self {
            case .invalidTitle(let violations): "titolo non conforme: \(violations)"
            case .alreadyExists(let path): "esiste già: \(path)"
            }
        }
    }

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
        guard let store else { throw CreationError.alreadyExists("nessun vault aperto") }

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

    /// Opens today's daily note, creating it if it does not exist (SPEC §8.1).
    @discardableResult
    func openDailyNote(for date: CalendarDate) throws -> String {
        guard let store else { throw CreationError.alreadyExists("nessun vault aperto") }
        let relativePath = settings.dailyFolder.isEmpty
            ? NoteName.dailyFileName(for: date)
            : "\(settings.dailyFolder)/\(NoteName.dailyFileName(for: date))"

        if FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false)) {
            openNote(at: relativePath)
            return relativePath
        }
        return try createNote(
            title: date.compactForm,
            in: settings.dailyFolder,
            date: date,
            category: .daily
        )
    }

    /// Writes the open note. Files first, index second: a crash between the two must
    /// leave the file correct, never the cache (ADR-0001 §D2.3).
    func saveOpenNote() {
        guard let store, var note = openNote, note.hasUnsavedChanges else { return }
        do {
            let hash = try store.write(note.text, to: note.relativePath)
            selfWrittenHashes[note.relativePath] = hash
            note.savedText = note.text
            note.externalChangePending = nil
            openNote = note

            let record = try store.read(note.relativePath).record
            index.update(record, at: note.relativePath)
        } catch {
            problems.append("\(note.relativePath): \(error)")
        }
    }

    /// Resolves an external change the user chose to accept, replacing the buffer.
    func acceptExternalChange() {
        guard var note = openNote, let incoming = note.externalChangePending else { return }
        note.text = incoming
        note.savedText = incoming
        note.externalChangePending = nil
        openNote = note
    }

    /// Keeps the in-app version and clears the prompt. The next save overwrites disk.
    func keepLocalVersion() {
        openNote?.externalChangePending = nil
    }

    /// Records a problem for the UI to show without interrupting what the user is
    /// doing. Used where the failure is recoverable by retrying.
    func recordProblem(_ message: String) {
        problems.append(message)
    }

    // MARK: Tasks

    /// Completes, reopens, cancels or reschedules a task by rewriting its source line.
    ///
    /// Writes the markdown file, never an index row: the file is the truth, and a task
    /// completed from any view has to change the note it lives in (SPEC §7.3).
    @discardableResult
    func apply(_ change: TaskChange, to task: TaskItem) -> Bool {
        guard let store else { return false }
        do {
            let (_, text) = try store.read(task.sourcePath)
            let newLine: String = switch change {
            case .state(let state):
                TaskParser.line(for: task, settingState: state, today: .today)
            case .schedule(let date):
                TaskParser.line(for: task, scheduledOn: date)
            case .link(let target):
                TaskParser.line(for: task, addingLinkTo: target)
            }

            guard let updated = TaskParser.rewrite(
                text, at: task.lineIndex, expecting: task.rawLine, with: newLine
            ) else {
                // The line moved or changed under us. Rescanning and asking again is
                // the only safe answer; rewriting by line number alone would edit
                // whatever now sits there.
                problems.append("il task non è più dove risultava: \(task.sourcePath)")
                Task { await rescan() }
                return false
            }

            let hash = try store.write(updated, to: task.sourcePath)
            selfWrittenHashes[task.sourcePath] = hash
            index.update(try store.read(task.sourcePath).record, at: task.sourcePath)

            // Keep an open editor in step rather than leaving it showing the old line.
            if var note = openNote, note.relativePath == task.sourcePath, !note.hasUnsavedChanges {
                note.text = updated
                note.savedText = updated
                openNote = note
            }
            return true
        } catch {
            problems.append("\(task.sourcePath): \(error)")
            return false
        }
    }

    enum TaskChange: Sendable {
        case state(TaskItem.State)
        case schedule(CalendarDate?)
        case link(String)
    }

    /// Toggles between open and done, which is what a checkbox click means.
    @discardableResult
    func toggle(_ task: TaskItem) -> Bool {
        apply(.state(task.state == .done ? .open : .done), to: task)
    }

    /// Quick capture (SPEC §7.4): appends a task to the inbox note, creating it if
    /// needed. Inbox tasks carry no date and no project, which is what puts them in
    /// the Inbox view.
    @discardableResult
    func captureTask(_ text: String) -> Bool {
        guard let store else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let relativePath = "00 Inbox/Capture.md"
        do {
            let existing = try? store.read(relativePath)
            let body = existing?.text ?? {
                var frontmatter = Frontmatter.empty
                frontmatter.date = .today
                frontmatter.tags = TagRules.ordered([
                    Tag(namespace: .type, value: "note"),
                    Tag(namespace: .status, value: "inbox"),
                ])
                return FrontmatterSerializer.render(frontmatter) + "\n"
            }()

            let separator = body.hasSuffix("\n") ? "" : "\n"
            let updated = body + separator + "- [ ] " + trimmed + "\n"
            let hash = try store.write(updated, to: relativePath)
            selfWrittenHashes[relativePath] = hash
            index.update(try store.read(relativePath).record, at: relativePath)
            return true
        } catch {
            problems.append("cattura rapida: \(error)")
            return false
        }
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
        guard let store else { return false }
        guard let targetPath = index.resolve(title: targetTitle).first else {
            problems.append("nessuna nota si chiama «\(targetTitle)»")
            return false
        }
        guard targetPath != sourcePath else {
            problems.append("\(RelatedLink.Error.linkingToItself)")
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
            problems.append("legame strutturale: \(error)")
            return false
        }
    }

    // MARK: Search

    struct SearchResult: Identifiable, Sendable {
        var id: String { path }
        var path: String
        var title: String
        /// The first matching line, for context in the result list.
        var excerpt: String
    }

    /// Full-text search across the vault (SPEC §12).
    ///
    /// Reads each note from disk rather than searching a cached copy of its text: the
    /// index holds structure, not content, and returning a hit for text that is no
    /// longer there is worse than taking a moment longer.
    func search(_ query: SearchQuery, limit: Int = 200) -> [SearchResult] {
        guard let store, !query.isEmpty else { return [] }

        var results: [SearchResult] = []
        for record in index.allNotes {
            guard let (_, text) = try? store.read(record.relativePath) else { continue }
            guard query.matches(record: record, text: text) else { continue }

            results.append(SearchResult(
                path: record.relativePath,
                title: record.title,
                excerpt: Self.excerpt(for: query, in: text)
            ))
            if results.count >= limit { break }
        }
        return results
    }

    /// The first line containing a searched word or phrase.
    private static func excerpt(for query: SearchQuery, in text: String) -> String {
        let needles = query.phrases + query.words
        guard !needles.isEmpty else { return "" }

        for line in text.components(separatedBy: "\n") {
            let folded = SearchQuery.fold(line)
            if needles.contains(where: { folded.contains(SearchQuery.fold($0)) }) {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    // MARK: URL scheme

    /// Handles a `pergamenum://` link (SPEC §9).
    ///
    /// Returns false when the route names something that is not there, so the caller
    /// can say so rather than silently doing nothing: a link from DEVONthink that
    /// quietly fails is worse than one that reports the note has moved.
    /// Traces URL handling.
    ///
    /// A link that silently does nothing is indistinguishable from a broken scheme
    /// registration, and that ambiguity cost real time to diagnose; every route now
    /// says what it did.
    private static let routeLog = Logger(subsystem: AppInfo.bundleIdentifier, category: "url-scheme")

    @discardableResult
    func handle(_ route: PergamenumRoute) -> Bool {
        Self.routeLog.notice("route ricevuta: \(String(describing: route), privacy: .public)")
        let outcome = perform(route)
        Self.routeLog.notice("route esito: \(outcome, privacy: .public)")
        return outcome
    }

    private func perform(_ route: PergamenumRoute) -> Bool {
        // A link can arrive before the vault has finished opening - the app may have
        // been launched *by* the link. Holding the route and replaying it is the
        // difference between a link that works from cold and one that only works when
        // the app happened to be running.
        guard let store else {
            pendingRoute = route
            return false
        }

        switch route {
        case .note(let path):
            guard FileManager.default.fileExists(
                atPath: store.url(for: path).path(percentEncoded: false)
            ) else {
                problems.append("il link punta a una nota che non esiste: \(path)")
                return false
            }
            openNote(at: path)
            return true

        case .noteID(let id):
            // IDs live in the index, not in the frontmatter (SPEC §9), so an unknown
            // one means the note was renamed outside the app.
            guard let path = noteIDs[id] else {
                problems.append("nessuna nota con id \(id)")
                return false
            }
            openNote(at: path)
            return true

        case .canvas(let path, let nodeID):
            pendingCanvasRoute = (path, nodeID)
            return true

        case .day(let date):
            return openDaily(date)

        case .today:
            return openDaily(.today)

        case .search(let query):
            pendingSearch = query
            isShowingQuickSwitcher = true
            return true

        case .capture(let text, let notePath):
            return append(text: text, to: notePath)

        case .addTask(let text):
            return captureTask(text)
        }
    }

    /// Opens the daily note for a route, reporting why when it cannot.
    ///
    /// `try?` here swallowed the reason and left a link that did nothing with no way
    /// to find out why.
    private func openDaily(_ date: CalendarDate) -> Bool {
        do {
            _ = try openDailyNote(for: date)
            return true
        } catch {
            Self.routeLog.error("daily note fallita: \(String(describing: error), privacy: .public)")
            problems.append("nota giornaliera: \(error)")
            return false
        }
    }

    /// A route that arrived before the vault was open, replayed once it is.
    private var pendingRoute: PergamenumRoute?

    /// A canvas the Workspace should open when it next appears.
    private(set) var pendingCanvasRoute: (path: String, nodeID: String?)?
    /// A query the quick switcher should start from.
    private(set) var pendingSearch: String?
    /// Stable ids for `pergamenum://note?id=`, held here rather than in the files.
    private var noteIDs: [String: String] = [:]

    func consumePendingCanvasRoute() -> (path: String, nodeID: String?)? {
        defer { pendingCanvasRoute = nil }
        return pendingCanvasRoute
    }

    func consumePendingSearch() -> String? {
        defer { pendingSearch = nil }
        return pendingSearch
    }

    /// Appends text to a note without opening it, for the capture route.
    private func append(text: String, to notePath: String?) -> Bool {
        guard let store else { return false }
        let path = notePath ?? {
            settings.dailyFolder.isEmpty
                ? NoteName.dailyFileName(for: .today)
                : "\(settings.dailyFolder)/\(NoteName.dailyFileName(for: .today))"
        }()

        do {
            if !FileManager.default.fileExists(atPath: store.url(for: path).path(percentEncoded: false)) {
                _ = try openDailyNote(for: .today)
            }
            let existing = try store.read(path).text
            let separator = existing.hasSuffix("\n") ? "" : "\n"
            let hash = try store.write(existing + separator + text + "\n", to: path)
            selfWrittenHashes[path] = hash
            index.update(try store.read(path).record, at: path)
            return true
        } catch {
            problems.append("capture: \(error)")
            return false
        }
    }

    // MARK: Watching

    private func startWatching(_ url: URL) {
        let watcher = VaultWatcher(root: url) { [weak self] paths in
            Task { @MainActor [weak self] in
                self?.reconcile(paths)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Applies external changes, one path at a time.
    private func reconcile(_ paths: [String]) {
        guard let store else { return }

        for path in paths {
            let fileURL = store.url(for: path)
            guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                index.update(nil, at: path)
                continue
            }
            guard let (record, text) = try? store.read(path) else { continue }

            // The app's own write coming back. Compared by content hash rather than
            // by a time window, so a real external edit is never mistaken for it.
            if selfWrittenHashes[path] == record.contentHash {
                selfWrittenHashes.removeValue(forKey: path)
                continue
            }

            index.update(record, at: path)

            guard var note = openNote, note.relativePath == path else { continue }
            if note.hasUnsavedChanges {
                // Never merge, never discard: ask.
                note.externalChangePending = text
                openNote = note
            } else {
                note.text = text
                note.savedText = text
                openNote = note
            }
        }
    }

    // MARK: Vault-private files

    private func privateDirectory(in root: URL) -> URL {
        root.appending(path: VaultLayout.privateDirectory, directoryHint: .isDirectory)
    }

    private func loadSettings(from root: URL) {
        let url = privateDirectory(in: root).appending(path: VaultLayout.settingsFile)
        guard let data = try? Data(contentsOf: url) else {
            settings = .default
            return
        }
        do {
            settings = try JSONDecoder().decode(VaultSettings.self, from: data)
        } catch {
            // Defaults rather than a failure to open: a damaged settings file must not
            // make the vault unreachable. It is not overwritten either, so the user
            // can repair it by hand.
            settings = .default
            problems.append("\(VaultLayout.settingsFile): \(error.localizedDescription); using defaults")
        }
    }

    /// Loads the vocabulary replica from the vault, seeding it from the bundled copy
    /// the first time (SPEC §4.6).
    private func loadVocabulary(from root: URL) {
        let directory = privateDirectory(in: root)
        let url = directory.appending(path: VaultLayout.vocabularyFile)

        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            guard let bundled = Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json") else {
                problems.append("the bundled vocabolari.json is missing")
                return
            }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: bundled, to: url)
            } catch {
                problems.append("vocabolari.json could not be created: \(error.localizedDescription)")
                return
            }
        }

        do {
            vocabulary = try JSONDecoder().decode(Vocabulary.self, from: try Data(contentsOf: url))
        } catch {
            vocabulary = .empty
            problems.append("\(VaultLayout.vocabularyFile): \(error.localizedDescription)")
        }
    }

    /// Re-imports the closed vocabularies from the harness-system checkout and writes
    /// the replica back into the vault.
    func importConventions(from repository: URL) {
        let conventions = repository.appending(path: "convenzioni", directoryHint: .isDirectory)
        let tagURL = conventions.appending(path: "tag.md")
        let namingURL = conventions.appending(path: "naming.md")

        guard let tagDocument = try? String(contentsOf: tagURL, encoding: .utf8),
              let namingDocument = try? String(contentsOf: namingURL, encoding: .utf8)
        else {
            problems.append("convenzioni/tag.md or naming.md could not be read at \(repository.path(percentEncoded: false))")
            return
        }

        let result = HarnessImporter.parse(tagDocument: tagDocument, namingDocument: namingDocument)
        problems.append(contentsOf: result.problems.map { "import: \($0)" })
        guard result.problems.isEmpty else { return }

        vocabulary = result.vocabulary
        guard let root else { return }
        let url = privateDirectory(in: root).appending(path: VaultLayout.vocabularyFile)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result.vocabulary).write(to: url, options: .atomic)
        } catch {
            problems.append("vocabolari.json could not be written: \(error.localizedDescription)")
        }
    }

    /// Validates any note in the vault by path, for the vault-wide conformance view.
    ///
    /// Reads the file rather than trusting the index: the linter's whole job is to
    /// report what is on disk, and a stale index row would report a note as clean
    /// after someone edited it in Obsidian.
    func violations(forRecordAt relativePath: String) -> NoteViolations? {
        guard let store, let (_, text) = try? store.read(relativePath) else { return nil }
        return violations(
            path: relativePath,
            title: NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent),
            text: text
        )
    }

    /// Validates the open note against every convention rule, for the conformance view.
    func violations(for note: OpenNote) -> NoteViolations {
        violations(path: note.relativePath, title: note.title, text: note.text)
    }

    private func violations(path: String, title: String, text: String) -> NoteViolations {
        let document = NoteDocument.parse(text)
        let category = NoteName.category(
            forFileName: (path as NSString).lastPathComponent,
            dailyFolder: settings.dailyFolder,
            path: path
        )
        let discrepancies = RelatedSection.discrepancies(
            frontmatterRelated: document.frontmatter.related,
            sectionLinks: RelatedSection.parse(from: document.body)
        )
        // A daily note is judged by its own naming rule: `20260811` would fail the
        // ordinary title check for looking like a version-less date, and passing it
        // through `validate` would report every daily note as non-conformant.
        let nameViolations = category == .daily
            ? NoteName.validateDaily(title)
            : NoteName.validate(title)

        return NoteViolations(
            name: nameViolations,
            frontmatter: FrontmatterRules.validate(document),
            tags: TagRules.validate(document.frontmatter.tags, category: category, vocabulary: vocabulary),
            relatedMissingInSection: discrepancies.missingInSection,
            relatedMissingInFrontmatter: discrepancies.missingInFrontmatter
        )
    }
}

struct NoteViolations: Equatable, Sendable {
    var name: [NoteName.Violation]
    var frontmatter: [FrontmatterViolation]
    var tags: [TagViolation]
    var relatedMissingInSection: [String]
    var relatedMissingInFrontmatter: [String]

    var isEmpty: Bool {
        name.isEmpty && frontmatter.isEmpty && tags.isEmpty
            && relatedMissingInSection.isEmpty && relatedMissingInFrontmatter.isEmpty
    }

    var count: Int {
        name.count + frontmatter.count + tags.count
            + relatedMissingInSection.count + relatedMissingInFrontmatter.count
    }
}
