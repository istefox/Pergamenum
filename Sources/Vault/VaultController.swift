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
    /// **Written only by the doors in `VaultController+Tabs.swift`**, which is where they all
    /// live and is the whole of the convention: a view calls `show`, `focusTab`, `closeTab`,
    /// and never assigns here. `private(set)` said the same thing to the compiler until the
    /// doors outgrew this file; it is documented now rather than enforced, the trade
    /// `replaceOpenNote` has always made.
    var columns: [EditorColumn] = [EditorColumn()]
    var focusedColumnIndex = 0

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
    /// Notes opened in this window, newest first, for the quick switcher's RECENTI
    /// (ADR-0012, slice 4).
    ///
    /// In memory and not on disk, unlike the open tabs of D10: the tabs are restored at
    /// launch and already say what this machine was working on, and a second persisted
    /// list of paths would be a second thing every rename has to keep in step with.
    var recentNotePaths: [String] = []
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
    /// The template chooser for the note already open (ADR-0011 D5). Its own flag rather
    /// than the composer's: that one starts a note, this one writes into one.
    var isChoosingTemplate = false

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
    /// Where the pinned tags are remembered, per vault. Injected for the same reason, and read
    /// through the three doors in `VaultController+Files`.
    let pinnedTagsStore: PinnedTagsStore

    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "vault-state")

    /// The pinned tags of the open vault, kept here so a view watching the controller redraws
    /// when one is added. The store is the record; this is what the browser reads.
    ///
    /// Not `private(set)`: the one door onto it, `togglePin`, is in `VaultController+Files.swift`
    /// and cannot write through a private setter from another file. Same documented trade as
    /// `columns` and `replaceOpenNote`.
    var pinnedTags: [Tag] = []

    init(
        recents: RecentVaults = RecentVaults(),
        openTabs: OpenTabsStore = OpenTabsStore(),
        pinnedTags: PinnedTagsStore = PinnedTagsStore()
    ) {
        self.recents = recents
        self.openTabs = openTabs
        self.pinnedTagsStore = pinnedTags
    }

    // MARK: Opening

    func open(_ url: URL) async {
        watcher?.stop()
        watcher = nil

        // Resolved once, ahead of the session: `VaultSession` and `ThumbnailStore`
        // both need it, and a failure here means neither can be built - there is no
        // silent fallback location to write derived state into instead (ADR-0017).
        guard let stateBase = try? VaultState.applicationSupportBase() else {
            Self.log.fault("impossibile risolvere Application Support: apertura del vault annullata")
            return
        }

        // The session reads settings and vocabulary as it is built, which is why this
        // is one statement rather than the four it replaced.
        let newSession = VaultSession(
            root: url,
            stateBase: stateBase,
            bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
        )
        session = newSession
        // Owned here, not by the Workspace that used to create it: the cache belongs
        // to the vault, and reading mode needs the same renderer to draw a picture
        // embedded in a note. The cache directory comes from the same resolved state
        // the session just built, so both land in the same place (ADR-0017).
        thumbnails = ThumbnailStore(root: url, directory: newSession.state.thumbnails)
        // Recorded on open rather than on close, so a crash still leaves the vault
        // reachable from the recents menu next launch.
        recents.remember(url)
        await rescan()
        startWatching(url)
        restoreTabs()
        pinnedTags = pinnedTagsStore.tags(for: url)

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
}
