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
    /// Renders and caches previews of the vault's files: the Workspace's cards, and the
    /// pictures reading mode draws inside a note. Nil while no vault is open.
    private(set) var thumbnails: ThumbnailStore?

    private(set) var isScanning = false
    /// Problems worth showing: an unreadable note, a settings file that would not
    /// parse, a vocabulary that could not be loaded.
    private(set) var problems: [String] = []

    /// The note currently open in the editor.
    private(set) var openNote: OpenNote?
    /// The note being created, while it is still only a name being typed.
    ///
    /// Held here rather than in the browser because the New Note command is in the menu
    /// bar and has to work from any pane. Nil means nothing is being created.
    var newNote: NoteDraft?
    /// Set by the Anteprima rapida command (SPEC §10, Vista menu). The Workspace
    /// watches it so the panel can be opened from the menu as well as the spacebar.
    var isShowingQuickLook = false
    /// Set by the "Nota correlata…" command.
    var isAddingRelatedLink = false
    /// Set by the "Verifica conformità" command; the Conformità pane runs the linter
    /// when it sees it. The check is on request and never automatic (SPEC §4.7), so
    /// this is a request and not a schedule.
    var isCheckingConformance = false
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
    var selfWrittenHashes: [String: String] = [:]

    var watcher: VaultWatcher?
    var store: NoteStore?

    /// Everything the `pergamenum://` routes hold between arriving and being acted on
    /// (SPEC §9). One value rather than four properties, so the routing extension owns
    /// its own state instead of reaching into the controller's.
    struct RouteState {
        /// A route that arrived before the vault was open, replayed once it is.
        var pending: PergamenumRoute?
        /// A canvas the Workspace should open when it next appears.
        var pendingCanvas: (path: String, nodeID: String?)?
        /// A query the quick switcher should start from.
        var pendingSearch: String?
        /// Stable ids for `pergamenum://note?id=`, held here rather than in the files.
        var noteIDs: [String: String] = [:]
    }

    var routeState = RouteState()

    /// Where opened vaults are remembered. Injected so a test never writes into the
    /// list the app reads at launch.
    private let recents: RecentVaults

    init(recents: RecentVaults = RecentVaults()) {
        self.recents = recents
    }

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
        // Owned here, not by the Workspace that used to create it: the cache in
        // `.pergamenum/thumbnails` belongs to the vault, and reading mode needs the same
        // renderer to draw a picture embedded in a note.
        thumbnails = ThumbnailStore(root: url)
        // Recorded on open rather than on close, so a crash still leaves the vault
        // reachable from the recents menu next launch.
        recents.remember(url)
        loadSettings(from: url)
        loadVocabulary(from: url)
        await rescan()
        startWatching(url)

        if let route = routeState.pending {
            routeState.pending = nil
            handle(route)
        }
    }

    func close() {
        watcher?.stop()
        watcher = nil
        root = nil
        store = nil
        thumbnails = nil
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
        let cacheURL = privateDirectory(in: root).appending(path: VaultLayout.cacheFile)
        let cached = IndexCache(url: cacheURL).load()

        let outcome = await Task.detached(priority: .userInitiated) {
            var scanner = VaultScanner(root: root)
            scanner.cached = cached
            return scanner.scan()
        }.value
        index.replaceAll(with: outcome, duration: clock.now - start)

        // Written after the index is in place: the cache is an optimisation, and the
        // app must be usable whether or not it can be saved (SPEC §12).
        let records = outcome.records
        let problem: String = await Task.detached(priority: .utility) {
            IndexCache(url: cacheURL).save(records)
        }.value
        if !problem.isEmpty { problems.append("cache: \(problem)") }

        // Bumped last, once the index is whole. Anything that has to react to the
        // vault's contents watches this rather than the task array itself, which is
        // rebuilt on every scan and would fire on identical content.
        scanGeneration += 1
        taskGeneration += 1
    }

    /// Incremented at the end of every completed scan. See `rescan()`.
    private(set) var scanGeneration = 0

    /// Records that a task line was written, which is what reschedules reminders.
    /// The one door for the tasks extension, since the counter stays read-only.
    func recordTaskWrite() {
        taskGeneration += 1
    }

    /// Incremented by every completed scan and by every task line the app writes.
    ///
    /// Separate from `scanGeneration` because reminders have to be rescheduled when a
    /// `@remind` is captured in the app, not only when a scan finds one on disk: a task
    /// composed with a reminder used to notify nothing until the next full rescan.
    private(set) var taskGeneration = 0

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

    /// A note that does not exist yet: the name being typed, and where it will go.
    struct NoteDraft: Equatable, Sendable {
        var folder = ""
        var title = ""
        var topic = ""
    }

    /// Starts a new note in a folder, empty meaning the vault root.
    ///
    /// The naming used to happen in a sheet floating over the window; it now happens in
    /// the editor pane itself, so a new note is composed where it will be edited.
    func beginNewNote(in folder: String = "") {
        newNote = NoteDraft(folder: folder)
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

    /// Closes the note in the editor, for when the file it shows is no longer there.
    func closeOpenNote() {
        openNote = nil
    }

    /// Replaces the open note wholesale.
    ///
    /// The one door for code outside this file: `openNote` stays read-only everywhere
    /// else, so a view cannot quietly swap the buffer under the editor.
    func replaceOpenNote(_ note: OpenNote) {
        openNote = note
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
    //
    // The behaviour is in VaultController+Tasks.swift; only the state an extension
    // cannot declare lives here.

    /// Set by the Task menu; the Attività view opens the quick switcher (SPEC §7.2).
    var isLinkingSelectedTask = false

    /// The task the task views and the Task menu act on.
    ///
    /// Held here so the menu commands of SPEC §7.3 (Cmd+0/1/2/3) work wherever the
    /// user is: a shortcut that only fires when a particular view holds focus is not
    /// a shortcut for rescheduling, it is a shortcut for rescheduling sometimes.
    var selectedTask: TaskItem?

    /// The task being composed (SPEC §7.4, Cattura rapida). Nil means the composer is
    /// closed; it lives here so the command works from any pane.
    var taskDraft: TaskDraft?

    /// The last task the composer wrote, until a view has reacted to it. Written by
    /// `captureTask` and read once through `consumeLastCapture`.
    var lastCapture: TaskDraft?

    /// Puts the open note on its folder's board and switches to the Workspace
    /// (SPEC §5, "Apri nel canvas").
    func openCurrentNoteInWorkspace() {
        guard let note = openNote else { return }
        pendingWorkspacePlacement = note.relativePath
    }

    /// A note the Workspace should place on the current board when it next appears.
    private(set) var pendingWorkspacePlacement: String?

    func consumePendingWorkspacePlacement() -> String? {
        defer { pendingWorkspacePlacement = nil }
        return pendingWorkspacePlacement
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

    /// Applies a settings change and writes `settings.json` back.
    ///
    /// Written immediately rather than on close: a setting that survives only a clean
    /// quit is a setting the user cannot rely on.
    func updateSettings(_ change: (inout VaultSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated

        guard let root else { return }
        let directory = privateDirectory(in: root)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(updated)
                .write(to: directory.appending(path: VaultLayout.settingsFile), options: .atomic)
        } catch {
            problems.append("\(VaultLayout.settingsFile): \(error.localizedDescription)")
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
    /// Empties `.pergamenum/cache.db` and rebuilds the index from the vault
    /// (SPEC §12, Avanzate › svuota cache).
    func clearCache() async {
        guard let root else { return }
        IndexCache(url: privateDirectory(in: root).appending(path: VaultLayout.cacheFile)).clear()
        await rescan()
    }

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

        var imported = result.vocabulary
        // Says where the tables came from and when, and that this file is a replica.
        // Without it the first import silently deleted the only warning against
        // hand-editing what harness-system owns (SPEC §1, principle 5).
        imported.note = """
            Replica of the closed tables of harness-system, imported from \
            \(repository.path(percentEncoded: false)) on \(CalendarDate.today). \
            The repo is the source of truth: when a convention changes, re-run \
            "Importa convenzioni…" rather than editing this file.
            """
        vocabulary = imported
        guard let root else { return }
        let url = privateDirectory(in: root).appending(path: VaultLayout.vocabularyFile)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(imported).write(to: url, options: .atomic)
        } catch {
            problems.append("vocabolari.json could not be written: \(error.localizedDescription)")
        }
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
