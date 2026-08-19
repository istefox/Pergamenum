import Foundation
import Observation
import OSLog
import SwiftUI

/// Owns the open vault: settings, index, watcher, and the read/write path the editor
/// goes through.
@MainActor
@Observable
final class VaultController {
    /// The open vault. Nil means none is (ADR-0007 §D3).
    ///
    /// Everything this type used to own about the vault now lives here, and the
    /// properties below read straight through: one copy of the state, held by the
    /// object that a headless process holds too.
    private(set) var session: VaultSession?

    var root: URL? { session?.root }
    var settings: VaultSettings { session?.settings ?? .default }
    var vocabulary: Vocabulary { session?.vocabulary ?? .empty }
    var index: IndexSnapshot { session?.index ?? IndexSnapshot() }
    /// Renders and caches previews of the vault's files: the Workspace's cards, and the
    /// pictures reading mode draws inside a note. Nil while no vault is open.
    private(set) var thumbnails: ThumbnailStore?

    private(set) var isScanning = false
    /// Problems worth showing: an unreadable note, a settings file that would not
    /// parse, a vocabulary that could not be loaded.
    var problems: [String] { session?.problems ?? [] }

    /// The note currently open in the editor.
    private(set) var openNote: OpenNote?
    /// The note being created, while it is still only a name being typed.
    ///
    /// Held here rather than in the browser because the New Note command is in the menu
    /// bar and has to work from any pane. Nil means there is no draft at all.
    ///
    /// **Unlike `taskDraft`, non-nil does not mean the composer is on screen**: stepping
    /// out of the composer to read a note parks the draft here, and `isComposingNote`
    /// says whether it is being shown (PG-027, PG-028). The two used to be one property,
    /// which is how a note came to open underneath the composer.
    var noteDraft: NoteDraft?
    /// Whether the new-note composer occupies the editor column.
    var isComposingNote = false
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
    /// Set by the "Cronologia…" command and by the inspector's own button, both of
    /// which open the same sheet over the open note (ADR-0011, M9).
    var isShowingHistory = false

    /// Hashes the app itself wrote, keyed by path. A watcher event whose file hashes
    /// to the recorded value is the app's own write coming back and is ignored.
    var selfWrittenHashes: [String: String] {
        get { session?.selfWrittenHashes ?? [:] }
        set { session?.selfWrittenHashes = newValue }
    }

    var watcher: VaultWatcher?
    var store: NoteStore? { session?.store }

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

        // The session reads settings and vocabulary as it is built, which is why this
        // is one statement rather than the four it replaced.
        session = VaultSession(
            root: url,
            bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
        )
        // Owned here, not by the Workspace that used to create it: the cache in
        // `.pergamenum/thumbnails` belongs to the vault, and reading mode needs the same
        // renderer to draw a picture embedded in a note.
        thumbnails = ThumbnailStore(root: url)
        // Recorded on open rather than on close, so a crash still leaves the vault
        // reachable from the recents menu next launch.
        recents.remember(url)
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
        session = nil
        thumbnails = nil
        openNote = nil
        // A draft names a folder in the vault being closed, and the composer would
        // otherwise still be sitting in the editor column of a vault that is gone.
        endNewNote()
    }

    /// Full rebuild from disk. Cheap by design, and the answer to any doubt about the
    /// index being stale (SPEC §12, "rigenera indice").
    func rescan() async {
        guard let session else { return }
        isScanning = true
        defer { isScanning = false }

        await session.rescan()

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
        guard let session else { return }
        do {
            let (record, text) = try session.read(relativePath)
            openNote = OpenNote(
                relativePath: relativePath,
                title: record.title,
                text: text,
                savedText: text,
                externalChangePending: nil
            )
            session.updateIndex(record, at: relativePath)
            // The composer covers the editor column, so a note opened while it is up
            // would open underneath it (PG-027). Inside the `do`, after the read: a note
            // that could not be read is no reason to take the composer away.
            isComposingNote = false
        } catch {
            recordProblem("\(relativePath): \(error)")
        }
    }

    func updateOpenNoteText(_ text: String) {
        openNote?.text = text
    }

    /// A note that does not exist yet: the name being typed, where it will go, and the
    /// template it starts from.
    struct NoteDraft: Equatable, Sendable {
        var folder = ""
        var title = ""
        var topic = ""
        /// The chosen template's relative path, empty for none (ADR-0011 D6).
        var template = ""
    }

    /// Opens today's daily note, creating it if it does not exist (SPEC §8.1).
    @discardableResult
    func openDailyNote(for date: CalendarDate) throws -> String {
        guard let session else { throw CreationError.alreadyExists("nessun vault aperto") }
        let relativePath = try session.dailyNote(for: date)
        openNote(at: relativePath)
        return relativePath
    }

    /// Writes the open note.
    func saveOpenNote() {
        guard let session, var note = openNote, note.hasUnsavedChanges else { return }
        do {
            try session.write(note.text, to: note.relativePath)
            note.savedText = note.text
            note.externalChangePending = nil
            openNote = note
        } catch {
            recordProblem("\(note.relativePath): \(error)")
        }
    }

    /// Writes a past version back over the open note (ADR-0011, M9).
    ///
    /// **Saves the buffer first, and that is the point rather than tidiness.**
    /// `NoteHistory` records the text being *written*, so the note's current text is in
    /// the list only because an earlier write put it there; unsaved edits are in no
    /// snapshot at all. Restoring straight over them would discard work with nothing to
    /// go back to, which is precisely what ADR-0001 §D3.4 refuses to do. Saving first
    /// puts the buffer in the history, and the restore's own write adds itself on the
    /// way past - so the sheet's promise that restoring keeps the current version is
    /// literally true, in the one case where it would otherwise be a lie.
    func restoreVersion(_ text: String) {
        guard let session, openNote != nil else { return }
        saveOpenNote()
        // Re-read: the save above replaced `openNote` wholesale.
        guard var note = openNote else { return }
        do {
            let result = try session.write(text, to: note.relativePath)
            note.text = result.text
            note.savedText = result.text
            note.externalChangePending = nil
            replaceOpenNote(note)
        } catch {
            recordProblem("\(note.relativePath): \(error)")
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

    /// Puts the editor back in step after a write the session made underneath it.
    ///
    /// This is the fourth of the four things every write in this app used to do by
    /// hand, and the only one that is the facade's business: the session writes the
    /// file, records the hash and updates the index, and then this decides whether the
    /// editor should notice.
    ///
    /// A buffer with unsaved changes is left alone. It is the user's work, and
    /// ADR-0001 §D3.4 says to ask rather than to merge; the watcher will raise the
    /// question when the write comes back round.
    func syncOpenNote(with result: VaultSession.WriteResult) {
        guard var note = openNote,
              note.relativePath == result.path,
              !note.hasUnsavedChanges
        else { return }
        note.text = result.text
        note.savedText = result.text
        replaceOpenNote(note)
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
        session?.recordProblem(message)
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
    //
    // Settings, vocabulary and the cache all live on the session now (ADR-0007 §D3).
    // What stays here is the door the menus and the settings window already knock on.

    /// Applies a settings change and writes `settings.json` back.
    func updateSettings(_ change: (inout VaultSettings) -> Void) {
        session?.updateSettings(change)
    }

    /// Empties `.pergamenum/cache.db` and rebuilds the index from the vault
    /// (SPEC §12, Avanzate › svuota cache).
    func clearCache() async {
        guard let session else { return }
        isScanning = true
        defer { isScanning = false }
        await session.clearCache()
        scanGeneration += 1
        taskGeneration += 1
    }

    /// Re-imports the closed vocabularies from the harness-system checkout and writes
    /// the replica back into the vault.
    func importConventions(from repository: URL) {
        session?.importConventions(from: repository)
    }
}
