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

    /// Every note open in the editor, by column, and which column has focus (ADR-0012 D2).
    ///
    /// `private(set)` for the same reason `openNote` was: everything outside this file reads
    /// the tabs and changes them only through the doors below, so a view cannot quietly swap
    /// the buffer. One column until the split-view slice.
    private(set) var columns: [EditorColumn] = [EditorColumn()]
    private(set) var focusedColumnIndex = 0

    /// The tab the person is looking at.
    var focusedTab: NoteTab? {
        guard columns.indices.contains(focusedColumnIndex) else { return nil }
        return columns[focusedColumnIndex].active
    }

    /// The note currently open in the editor.
    ///
    /// **A facade over the focused tab, and deliberately still called this** (ADR-0012 D2):
    /// eighty-two places across the app read it, and every one of them means "the note the
    /// person is looking at", which is exactly what it still returns. The type changed shape
    /// underneath; its published surface did not.
    var openNote: OpenNote? { focusedTab?.note }
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
    /// Notes whose tab was closed, newest last, for «riapri l'ultima tab chiusa».
    /// Paths and not buffers: a closed tab was saved or explicitly discarded (ADR-0012 D3),
    /// so there is nothing left to keep that the file does not already have.
    var closedTabPaths: [String] = []
    /// Set by Cmd+T, read by the quick switcher: the note chosen next opens beside the
    /// others rather than over the focused one.
    var opensNextNoteInNewTab = false
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
    /// (SPEC §9). The type is declared beside the extension that uses it.
    var routeState = RouteState()

    /// Where opened vaults are remembered, injected so a test never writes into the list
    /// the app reads at launch.
    private let recents: RecentVaults
    /// Where the open tabs are remembered, per vault (ADR-0012 D10). Injected against the
    /// same mistake as `recents`, and not private so its two methods can live with the tabs.
    let openTabs: OpenTabsStore

    init(recents: RecentVaults = RecentVaults(), openTabs: OpenTabsStore = OpenTabsStore()) {
        self.recents = recents
        self.openTabs = openTabs
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
        restoreTabs()

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
        columns = [EditorColumn()]
        focusedColumnIndex = 0
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

    func updateOpenNoteText(_ text: String) {
        // Typing in a preview tab makes it stay, without being asked: having written in a
        // note is a stronger statement of intent than any double click.
        updateFocusedTab {
            $0.note.text = text
            $0.isPreview = false
        }
    }

    // MARK: The doors onto the tabs
    //
    // `columns` is `private(set)`, so these four are the only way anything changes. They
    // are internal rather than private because the extensions that need them are in other
    // files - the same trade `replaceOpenNote` has always made, documented rather than
    // enforced by the compiler.

    /// Shows a note in the column's preview tab, opening one if there is none.
    ///
    /// **This is the single click, and it deliberately does not touch a stable tab.** Before
    /// tabs it replaced the one open note, which was the only thing it could do; doing that
    /// now would mean browsing the list destroys whatever the person had in front of them. So
    /// one tab per column is the preview, every single click lands there, and a double click
    /// makes it stable (`makeStable`).
    ///
    /// A reused tab keeps its identity and loses everything that described the note it was
    /// showing - folds, index entry, reading mode. That reset used to be an `onChange` in
    /// `VaultBrowser` watching the open note's path, which is the same rule written where it
    /// could not survive a second tab.
    func show(_ note: OpenNote) {
        guard columns.indices.contains(focusedColumnIndex) else { return }
        if let index = columns[focusedColumnIndex].tabs.firstIndex(where: \.isPreview) {
            let tab = columns[focusedColumnIndex].tabs[index]
            columns[focusedColumnIndex].tabs[index] = tab.showing(note)
            columns[focusedColumnIndex].activeID = tab.id
            rememberTabs()
        } else {
            var tab = NoteTab(note: note)
            tab.isPreview = true
            let after = columns[focusedColumnIndex].tabs.firstIndex { $0.id == focusedTab?.id }
            let at = after.map { $0 + 1 } ?? columns[focusedColumnIndex].tabs.count
            columns[focusedColumnIndex].tabs.insert(tab, at: at)
            columns[focusedColumnIndex].activeID = tab.id
        }
        rememberTabs()
    }

    /// Turns a preview tab into one that stays: the double click on a row or on the tab.
    func makeStable(_ id: NoteTab.ID) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        columns[focusedColumnIndex].tabs[index].isPreview = false
        rememberTabs()
    }

    /// Opens a note in a tab of its own, after the focused one, and focuses it.
    func openTab(showing note: OpenNote) {
        guard columns.indices.contains(focusedColumnIndex) else { return }
        let tab = NoteTab(note: note)
        let after = columns[focusedColumnIndex].tabs.firstIndex { $0.id == focusedTab?.id }
        columns[focusedColumnIndex].tabs.insert(tab, at: after.map { $0 + 1 } ?? columns[focusedColumnIndex].tabs.count)
        columns[focusedColumnIndex].activeID = tab.id
        rememberTabs()
    }

    /// Brings a tab to the front of its column. Unknown ids are ignored rather than
    /// clearing the selection, which would blank the editor on a stale click.
    func focusTab(_ id: NoteTab.ID) {
        guard columns.indices.contains(focusedColumnIndex),
              columns[focusedColumnIndex].tabs.contains(where: { $0.id == id })
        else { return }
        columns[focusedColumnIndex].activeID = id
        isComposingNote = false
        rememberTabs()
    }

    /// Closes one tab by id, whether or not it is the focused one.
    ///
    /// Closing the focused tab moves focus to the one before it, which is where the eye
    /// already is; closing any other leaves focus alone. Unsaved changes are not this
    /// method's business - ADR-0012 D3's dialog asks before it gets here.
    func closeTab(_ id: NoteTab.ID) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        let wasFocused = columns[focusedColumnIndex].activeID == id
        closedTabPaths.append(columns[focusedColumnIndex].tabs[index].note.relativePath)
        columns[focusedColumnIndex].tabs.remove(at: index)
        guard wasFocused else { return }
        let neighbour = columns[focusedColumnIndex].tabs.indices.contains(index - 1) ? index - 1 : 0
        columns[focusedColumnIndex].activeID = columns[focusedColumnIndex].tabs.indices.contains(neighbour)
            ? columns[focusedColumnIndex].tabs[neighbour].id
            : nil
        rememberTabs()
    }

    /// Changes the focused tab in place, leaving its identity and view state alone.
    func updateFocusedTab(_ change: (inout NoteTab) -> Void) {
        guard let id = focusedTab?.id else { return }
        updateTab(id, change)
    }

    /// Changes any tab of the focused column by id, focused or not.
    ///
    /// A rename reaches a tab nobody is looking at, which is exactly the case the
    /// one-open-note version of this app could not have.
    func updateTab(_ id: NoteTab.ID, _ change: (inout NoteTab) -> Void) {
        guard columns.indices.contains(focusedColumnIndex),
              let index = columns[focusedColumnIndex].tabs.firstIndex(where: { $0.id == id })
        else { return }
        change(&columns[focusedColumnIndex].tabs[index])
    }

    /// Closes the note in the editor, for when the file it shows is no longer there.
    func closeOpenNote() {
        guard columns.indices.contains(focusedColumnIndex), let tab = focusedTab else { return }
        columns[focusedColumnIndex].tabs.removeAll { $0.id == tab.id }
        columns[focusedColumnIndex].activeID = columns[focusedColumnIndex].tabs.last?.id
    }

    /// Replaces the open note wholesale, keeping the tab and everything it knows.
    ///
    /// The one door for code outside this file: `openNote` reads the focused tab and cannot
    /// be assigned, so a view cannot quietly swap the buffer under the editor.
    func replaceOpenNote(_ note: OpenNote) {
        updateFocusedTab { $0.note = note }
    }

    /// Opens today's daily note, creating it if it does not exist (SPEC §8.1).
    @discardableResult
    func openDailyNote(for date: CalendarDate) throws -> String {
        guard let session else { throw CreationError.alreadyExists("nessun vault aperto") }
        let relativePath = try session.dailyNote(for: date)
        openNote(at: relativePath)
        return relativePath
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
