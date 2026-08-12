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

    /// Set by the Task menu; the Attività view opens the quick switcher (SPEC §7.2).
    var isLinkingSelectedTask = false

    /// The task the task views and the Task menu act on.
    ///
    /// Held here so the menu commands of SPEC §7.3 (Cmd+0/1/2/3) work wherever the
    /// user is: a shortcut that only fires when a particular view holds focus is not
    /// a shortcut for rescheduling, it is a shortcut for rescheduling sometimes.
    var selectedTask: TaskItem?

    /// Reschedules the selected task by whole days from today, or clears its date.
    @discardableResult
    func rescheduleSelectedTask(daysFromToday: Int?) -> Bool {
        guard let task = selectedTask else { return false }
        let date = daysFromToday.map { CalendarDate.today.adding(days: $0) }
        let changed = apply(.schedule(date), to: task)
        if changed {
            // Re-resolve the task so a second shortcut acts on the rewritten line
            // rather than the stale one it replaced.
            selectedTask = index.allTasks.first { $0.sourcePath == task.sourcePath && $0.text == task.text }
        }
        return changed
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
