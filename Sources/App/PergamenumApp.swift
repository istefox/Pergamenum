import AppKit
import OSLog
import SwiftUI
import UserNotifications

/// Handles `pergamenum://` links at the application level.
///
/// SwiftUI's `onOpenURL` is attached to a window, and on macOS a link with no window
/// willing to claim it opens a NEW one - six links produced six windows, each with a
/// vault still opening, so every route failed silently. `application(_:open:)` is
/// called once, on the app, before any of that.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the App at launch; the delegate is created before it exists.
    weak var vault: VaultController?
    /// Set beside `vault`, for the same reason: the quit path below waits on it.
    weak var diary: DiaryController?
    weak var contenitore: ContenitoreController?

    /// Logs who holds the notification delegate once launch finishes, so a cold-launch tap
    /// reaching `ReminderScheduler` is a fact read in the log, not an inference (PG-243).
    func applicationDidFinishLaunching(_ notification: Notification) {
        let delegate = UNUserNotificationCenter.current().delegate.map { String(describing: type(of: $0)) }
        Logger(subsystem: AppInfo.bundleIdentifier, category: "reminders")
            .notice("delegate notifiche al lancio: \(delegate ?? "nessuno", privacy: .public)")
    }

    /// Set beside `vault`: a cancelled quit brings the Note pane back (ADR-0073 §D7).
    weak var navigation: Navigation?

    /// Whether this process hosts the unit suite (`VaultState.isRunningUnderTest`, the
    /// `XCTestConfigurationFilePath` check of ADR-0017). PG-363: a Quit AppleEvent reaching
    /// the Debug test host (Quit from the Dock on the running `it.stefer.pergamenum.debug`)
    /// ended a unit run with «The test runner exited with code 0 before finishing running
    /// tests», which read as a flaky test twice (PG-308, PG-309). The host refuses it instead.
    /// Safe because XCTest never ends its host through `NSApp.terminate`: `XCTestCore`
    /// carries no `terminate:` selector and finishes through
    /// `flushIDEConnectionAndExitWithCode:timeout:` and `_exit` (checked against Xcode 27.0,
    /// 27A266a). Not set in the app the UI suite launches - that variable reaches the
    /// `xctrunner` process only (`VaultState.processDefaultBase()`) - so `QuitReviewUITests`'
    /// real Cmd+Q still goes through the review. A `var` so a test sets it explicitly
    /// (`TerminationSupportTests`) rather than relying on where it runs.
    /// The accepted trade-off: while a unit run is active, the test host cancels a logout,
    /// restart or shutdown, and an orphaned host cannot be quit from the Dock or with Cmd+Q
    /// (kill it instead) - acceptable for a Debug-only process that lives for one run.
    var isTestHost = VaultState.isRunningUnderTest

    /// The one door every termination goes through (ADR-0073 §D1): an open field editor
    /// ends (a table cell reaches its note), the board settles, the
    /// dirty note tabs are reviewed - asked about app-modally, before anything replies - and
    /// then the Diario's owed writes are waited for, capped at two seconds (ADR-0057 §D8,
    /// ADR-0060 §D2). `willTerminateNotification` fires after the decision to exit, so
    /// nothing that must be asked or awaited can live there. The order, the caps and the
    /// one-reply guarantee are `QuitCoordinator`'s; this keeps only AppKit's spelling, plus
    /// one exception that is deliberately outside the coordinator: the unit-test host
    /// refuses every termination before the coordinator is asked (`isTestHost` above,
    /// PG-363), since the coordinator knows nothing of the process environment.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isTestHost {
            Logger(subsystem: AppInfo.bundleIdentifier, category: "quit")
                .notice("uscita rifiutata: processo ospite dei test unitari (PG-363)")
            return .terminateCancel
        }
        return switch quit.shouldTerminate() {
        case .now: .terminateNow
        case .later: .terminateLater
        case .cancel: .terminateCancel
        }
    }

    /// Built on first use rather than as a `lazy var`: a lazy initializer is not a main-actor
    /// context, and the compiler refuses the async `sleep` closure there.
    private var quitCoordinator: QuitCoordinator?
    private let quitFocus = QuitFocus()

    private var quit: QuitCoordinator {
        if let quitCoordinator { return quitCoordinator }
        let made = QuitCoordinator(
            vault: { [weak self] in self?.vault },
            diary: { [weak self] in self?.diary },
            contenitore: { [weak self] in self?.contenitore },
            // Ends an open field editor - a table cell reaches its note only when its editing
            // ends. The main window too: a sheet in front of it is key, and the cell behind
            // keeps its field editor. No window at all (the red button) has nothing open.
            commitEditing: { [weak self] in
                var windows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
                if windows.count == 2, windows[0] === windows[1] { windows.removeLast() }
                self?.quitFocus.resign(in: windows)
            },
            ask: { QuitReviewAlert.ask($0) },
            reply: { NSApp.reply(toApplicationShouldTerminate: $0) },
            reveal: { [weak self] in self?.revealAfterCancelledQuit($0) },
            revealContenitore: { [weak self] in self?.revealContenitoreAfterCancelledQuit($0) },
            sleep: { try? await Task.sleep(for: $0) }
        )
        quitCoordinator = made
        return made
    }

    /// What a cancelled quit shows (ADR-0073 §D7): the main window, reopened if the red
    /// button had closed it, the Note pane, and the first unresolved tab in front of its
    /// column.
    private func revealAfterCancelledQuit(_ id: NoteTab.ID?) {
        vault?.reopenMainWindow?()
        navigation?.pane = .notes
        // The keyboard goes back where `commitEditing` took it from (departure 14), and only
        // then is the tab revealed: the other order lets the restore pull the focus back to
        // the column the reveal had just left (`QuitFocus.restore(thenReveal:in:)`).
        quitFocus.restore(thenReveal: id, in: vault)
    }

    /// A quit cancelled by a scheda edit that could not be written brings the Contenitore back
    /// on that scheda (ADR-0073 §D7's twin for the pane).
    private func revealContenitoreAfterCancelledQuit(_ schedaPath: String?) {
        vault?.reopenMainWindow?()
        navigation?.pane = .contenitore
        if let schedaPath { contenitore?.selection = schedaPath }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let routes = urls.compactMap(PergamenumRoute.init)
        guard !routes.isEmpty else { return }
        // One task for the whole batch rather than one per link (ADR-0043 §D2): the
        // delegate method is synchronous and routing is not any more, and six links
        // handed to six tasks would race each other into the same window.
        //
        // No explicit `NSApp.activate` here: opening the URL already brings the app
        // forward when it should, and calling it from a non-user-triggered path is
        // exactly the case the AppKit guidance warns about.
        Task { @MainActor [vault] in
            for route in routes { await vault?.handle(route) }
        }
    }
}

@main
struct PergamenumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeEngine: ThemeEngine
    @State private var vault = VaultController()
    @State private var calendar = EventKitStore()
    /// Built in `init` rather than inline, because `CommandActions` is assembled there
    /// and needs it: a `@State` property with an inline default is not readable from the
    /// initialiser that would use it.
    @State private var navigation: Navigation
    /// The places the window has been (ADR-0015). Built in `init` for the same reason
    /// `navigation` is: `CommandActions` is assembled there and «Indietro» is one of its
    /// commands. One history because there is one `Window`, and it does not outlive it (§D6).
    @State private var history: NavigationHistory
    /// The keyboard shortcuts in force. Held at app level because the menu bar is
    /// built here and the settings window that edits them is a separate scene.
    @State private var shortcuts = ShortcutStore()
    /// Local notifications for `@remind(...)` (SPEC §7.1). Held here so it outlives
    /// any one view: it was written, unit-tested and never instantiated, so the
    /// markers parsed correctly and no notification was ever scheduled. Built in `init`,
    /// where its tap sink is wired (PG-243).
    @State private var reminders: ReminderScheduler
    /// Sparkle (ADR-0031). A plain inline default, unlike `navigation`/`history`: nothing in
    /// `init` needs it, and `init` is precisely where the updater must not be touched - the
    /// object is allocated here but only `start()`, called from `armCapture()`, builds and
    /// starts the real `SPUStandardUpdaterController` (ADR-0031 §D3).
    @State private var updater = SparkleUpdateController()
    /// The day view's controller, created here rather than inside the view so the
    /// Calendario menu can act on the day being shown (SPEC §10).
    @State private var day: DayController
    /// The Diario pane's controller. At app level so a day being written survives a
    /// switch to another pane and back: as view state it would be rebuilt, and the
    /// unsaved end of a sentence would go with it.
    @State private var diary: DiaryController
    /// The Registrazioni pane's controller (ADR-0032). Built in `init` beside `day` and
    /// `diary`, for the same two reasons: `CommandActions` is assembled there and «Aggiorna
    /// registrazioni» is one of its commands, and a poll started from the pane must outlive
    /// a switch to another pane rather than being cancelled by the view going away.
    ///
    /// Nothing in the constructor opens a socket: `PlaudHTTPClient` holds one ephemeral HTTP
    /// session and issues nothing until asked, and under `-disablePlaud YES` (or the unit
    /// suite's own host) the controller refuses every request outright. The client's type is
    /// named here and its transport is not, deliberately - `Tests/PlaudIsolationTests.swift`
    /// matches the transport type's name as a plain string, comments included.
    @State private var recordings: RecordingsController
    /// The Pratiche pane's controller (ADR-0036, R-17/R-18). At app level for the same
    /// reason `recordings` is: a sync started from the pane must outlive a switch to
    /// another pane, and the window-key trigger is a fact about the app rather than
    /// about the view that happens to be on screen.
    ///
    /// Nothing in the constructor reads Mail: `PraticheController.live` only builds the
    /// probe and the sync closures, and both triggers are armed later, by the pane's
    /// own `startWatching(_:)`. Full Disk Access is probed per trigger, never at launch
    /// (ADR §D10).
    @State private var pratiche: PraticheController
    /// The Contenitore pane's controller (ADR-0071 §D11), at app level for `pratiche`'s reason:
    /// the drop folder keeps being watched while another pane is on screen. Nothing in the
    /// constructor touches the disk; `RootView` starts it once a vault is open.
    @State private var contenitore: ContenitoreController
    /// Global capture (ADR-0008). All three live at app level because the panel has to
    /// work with no window in front of the user - it is the whole point of the feature -
    /// and because the hot key is registered with the system once, not per window.
    @State private var capture = CaptureController()
    @State private var hotkey = GlobalHotkey()
    /// Built in `init` rather than when the window appears, so the File menu can carry
    /// "Cattura rapida" from the first frame. Nothing in the constructor touches AppKit:
    /// the `NSPanel` itself is made the first time the panel is shown.
    private let capturePanel: CapturePanel
    private let menuBarItem: MenuBarItem
    /// Every command in the catalogue, in one callable place, so the menu bar and the
    /// slash menu of M8 run the same code rather than two copies of it.
    private let commandActions: CommandActions
    /// Whether the menu-bar icon is shown. In `UserDefaults` and not in the vault: it is
    /// a fact about this Mac, not about these notes.
    @AppStorage("showsMenuBarItem") private var showsMenuBarItem = true

    init() {
        let engine = ThemeEngine()
        let vault = VaultController()
        let calendar = EventKitStore()
        let capture = CaptureController()
        let hotkey = GlobalHotkey()
        let navigation = Navigation()
        let day = DayController(store: calendar, vault: vault)
        let history = NavigationHistory()
        let recordings = RecordingsController(service: PlaudHTTPClient(), vault: vault)

        _themeEngine = State(initialValue: engine)
        _vault = State(initialValue: vault)
        _calendar = State(initialValue: calendar)
        _navigation = State(initialValue: navigation)
        _history = State(initialValue: history)
        _capture = State(initialValue: capture)
        _hotkey = State(initialValue: hotkey)
        _day = State(initialValue: day)
        let diary = DiaryController(vault: vault)
        _diary = State(initialValue: diary)
        _recordings = State(initialValue: recordings)

        // ADR-0057 §D8: a clean pane's file changing under another process's hand should
        // reload it rather than wait to be reopened - `weak` since the controller, not
        // this closure, owns the lifetime.
        vault.didChangeExternally = { [weak diary] path in diary?.externalChange(at: path) }

        // PG-243. Here and not in `armCapture()`: Apple requires the notification delegate
        // (set by this constructor) before launch finishes, and a tap that cold-launches the
        // app is delivered then. Wired to `vault`, not `appDelegate.vault`, which stays nil
        // until the window appears; `handle` holds the route until the vault is open.
        let reminders = ReminderScheduler()
        reminders.openRoute = { route in await vault.handle(route) }
        _reminders = State(initialValue: reminders)

        let pratiche = PraticheController.live(vault: vault)
        // ADR-0026 §D7: the choke point for every folder move and rename, forward and
        // through undo/redo, hands its relocations here so the ledger (and the other
        // path-keyed state `followFolderRelocations` covers) never orphans - `weak` since
        // the controller, not this closure, owns the lifetime.
        vault.didRelocateFolders = { [weak pratiche] moved in
            pratiche?.followFolderRelocations(moved, in: vault)
        }
        // PG-169, the deletion twin: state keyed by a trashed folder is forgotten, not followed.
        vault.didTrashFolder = { [weak pratiche] in pratiche?.followFolderTrashing($0, in: vault) }
        _pratiche = State(initialValue: pratiche)
        let contenitore = ContenitoreController.live(vault: vault)
        _contenitore = State(initialValue: contenitore)

        let panel = CapturePanel(
            controller: capture,
            // Read when the panel is shown, not now: the vault is opened after launch
            // and the theme changes while the app runs.
            session: { vault.session },
            theme: { engine.current },
            shortcutCaption: {
                guard case .registered(let binding) = hotkey.state else { return nil }
                return "\(binding.displayString) da qualsiasi app"
            }
        )
        capturePanel = panel
        // The menu-bar entries go through the URL routes rather than through the
        // controller directly: they have to raise the window, and the routes already
        // know how to do that from any state, including a vault still opening.
        menuBarItem = MenuBarItem(
            onCapture: { panel.toggle() },
            onToday: { Task { @MainActor in await vault.handle(.today) } },
            onInbox: {
                Task { @MainActor in
                    await vault.handle(.note(path: VaultSession.TaskDestination.inboxPath))
                }
            }
        )
        commandActions = CommandActions(
            navigation: navigation,
            vault: vault,
            day: day,
            calendar: calendar,
            capturePanel: panel,
            history: history,
            recordings: recordings,
            contenitore: contenitore
        )
    }

    /// Registers the shortcut with the system, once the app is up.
    ///
    /// From `.task` on the window rather than from `init`: registering a hot key is
    /// `NSApp`-adjacent work and does not belong in a scene's constructor.
    @MainActor
    private func armCapture() {
        hotkey.onPress = { [capturePanel] in capturePanel.toggle() }
        hotkey.register(shortcuts.binding(for: .globalCapture))
        menuBarItem.setShown(showsMenuBarItem)
        // Here and not in `init` (ADR-0031 §D3): `startUpdater()` is `NSApp`-adjacent work
        // that can put a modal alert on screen, and a scene's constructor is the one place
        // it must never run from. A no-op under `-disableUpdater YES`.
        updater.start()
    }

    // Internal, not private: read by `Tests/ReminderRescheduleKeyTests.swift`.
    /// What reminders are rescheduled on (PG-270). Two parts, because each moves where the
    /// other does not: `indexGeneration` moves when the index takes in a change - an editor
    /// save, an external edit, a scan - so a `@remind` typed in the editor is scheduled once the
    /// note is saved, not at the next rescan, as it was while this keyed on `taskGeneration`
    /// alone (the PG-324 shape); `taskGeneration` keeps the in-app task writes and the cache
    /// clear that move it, a board-sourced task write among them. Neither moves per keystroke:
    /// the index changes only when a write lands. A type rather than a sum so a reset of one
    /// part can never cancel a move of the other.
    struct ReminderKey: Equatable {
        let index: Int
        let tasks: Int
    }

    /// Pure, so a test can check it without rendering (the shape of `TodayView.reloadKey`).
    @MainActor
    static func reminderKey(for vault: VaultController) -> ReminderKey {
        ReminderKey(index: vault.indexGeneration, tasks: vault.taskGeneration)
    }

    /// Whether a change of `reminderKey(for:)` may reschedule. Not with no vault open, nor while
    /// a scan is rebuilding the index: `reschedule` replaces the pending notifications
    /// wholesale, so run against a missing session or a half-built index it would cancel every
    /// reminder. `indexGeneration` moves at `close()` and at `open(_:)` before the scan, which
    /// `taskGeneration` never did; the scan's own end still moves `taskGeneration` once the
    /// index is whole (`rescan()`, `clearCache()`), so a skipped run is always followed by one.
    @MainActor
    static func shouldReschedule(_ vault: VaultController) -> Bool {
        vault.session != nil && !vault.isScanning
    }

    var body: some Scene {
        // `Window`, not `WindowGroup`: on macOS a `pergamenum://` link with no window
        // willing to claim it makes the group open a NEW one, so every link from
        // Obsidian or DEVONthink left another empty window behind. A single-window
        // scene cannot do that, and this app has never had a reason for a second
        // window (SPEC §9, §10).
        Window("Pergamenum", id: "main") {
            RootView()
                .environment(themeEngine)
                .environment(vault)
                .environment(calendar)
                .environment(navigation)
                .environment(history)
                .environment(reminders)
                .environment(day)
                .environment(diary)
                .environment(recordings)
                .environment(pratiche)
                .environment(contenitore)
                .environment(shortcuts)
                .environment(commandActions)
                .themed(by: themeEngine)
                // The window keeps its name for Mission Control and the Finestra menu; the
                // toolbar does not show it. macOS draws the title between the leading and the
                // trailing toolbar groups, which with a split editor puts the word
                // «Pergamenum» exactly on the seam between the two columns - and the note you
                // are looking at is named on its tab, one row below, where it belongs.
                .toolbar(removing: .title)
                .onAppear {
                    appDelegate.vault = vault
                    appDelegate.diary = diary
                    appDelegate.contenitore = contenitore
                    appDelegate.navigation = navigation
                }
                // Not in `init`: window work and `NSApp` must not happen while the app
                // is still coming up, and neither the theme nor the vault the panel
                // reads exists there yet.
                .task { armCapture() }
                // The user changed the shortcut in Settings: register the new one and
                // let the state say whether the system agreed (ADR-0008 §D2).
                .onChange(of: shortcuts.binding(for: .globalCapture)) { _, binding in
                    hotkey.register(binding)
                }
                .onChange(of: showsMenuBarItem) { _, shown in
                    menuBarItem.setShown(shown)
                }
                // Rescheduled on every completed scan, on every index change and on every
                // task the app writes, against the whole vault: the tasks on disk are the
                // source of truth, so the scheduler replaces its pending notifications
                // wholesale rather than trying to diff them. See `reminderKey(for:)`.
                .task(id: Self.reminderKey(for: vault)) {
                    guard Self.shouldReschedule(vault) else { return }
                    // A burst of landed changes (a Pratiche sync writes one message after
                    // another) moves the key once per write: the next move cancels this task
                    // during the pause, so only the last of the burst reschedules.
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await reminders.refreshAccessStatus()
                    await reminders.reschedule(for: vault.index.allTasks, session: vault.session)
                    await reminders.refreshPending()
                }
                .task {
                    // Reopens the notes folder the app was last in (SPEC §10,
                    // "Cartelle recenti"). Guarded on `root` so a link that already opened one
                    // is not overridden by the previous session's vault.
                    // Through the switch door like every other opening (PG-334); with no
                    // folder open it asks nothing.
                    guard vault.root == nil, let recent = RecentVaults().mostRecent else { return }
                    await vault.switchVault(to: recent)
                }
                // Kept alongside the delegate: SwiftUI consumes the Apple Event
                // itself, so `application(_:open:)` is never called in a SwiftUI app
                // that has a WindowGroup. The delegate stays as the path for a link
                // that arrives before any window exists.
                .onOpenURL { url in
                    guard let route = PergamenumRoute(url) else { return }
                    Task { @MainActor in await vault.handle(route) }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            VaultCommands(
                vault: vault, navigation: navigation, shortcuts: shortcuts,
                capturePanel: capturePanel, actions: commandActions
            )
            EditCommands(navigation: navigation, shortcuts: shortcuts, actions: commandActions)
            InsertCommands(
                navigation: navigation, vault: vault, shortcuts: shortcuts, actions: commandActions
            )
            ViewCommands(
                navigation: navigation, vault: vault, shortcuts: shortcuts, actions: commandActions
            )
            // ADR-0071 §D11 (G2): between Inserisci and Task, active only with the pane.
            DocumentoCommands(navigation: navigation, vault: vault, contenitore: contenitore)
            TaskCommands(vault: vault, shortcuts: shortcuts, actions: commandActions)
            CalendarCommands(
                day: day, calendar: calendar, navigation: navigation,
                shortcuts: shortcuts, actions: commandActions
            )
            ThemeCommands(engine: themeEngine)
            HelpCommands(navigation: navigation)
            UpdateCommands(updater: updater)
        }

        // After the WindowGroup on purpose: the first scene in the body is the app's
        // primary one, and declaring Settings first made the app open its preferences
        // window instead of the vault.
        Settings {
            SettingsView()
                .environment(themeEngine)
                .environment(vault)
                .environment(calendar)
                .environment(shortcuts)
                // A separate scene with its own environment: an object injected into
                // the main window is not visible here, and reading one that is missing
                // is a trap at run time, not a compile error.
                .environment(reminders)
                .environment(hotkey)
                // Generali's «Giorni registrazioni Plaud» writes through this controller and
                // not through `vault.updateSettings` (ADR §D12), so this scene needs it too:
                // an object injected into the main window is invisible here.
                .environment(recordings)
                // Impostazioni › Pratiche (Task 9) reads the Full Disk Access state and
                // «Aggiorna tutte le pratiche ora» from this controller, and a scene
                // that is missing it is a run-time trap rather than a compile error.
                .environment(pratiche)
                // Impostazioni › Contenitore validates and stores both folders through it.
                .environment(contenitore)
                .themed(by: themeEngine)
        }
    }
}

/// The Task menu of SPEC §10, with the quick rescheduling of §7.3.
struct TaskCommands: Commands {
    let vault: VaultController
    let shortcuts: ShortcutStore
    let actions: CommandActions

    var body: some Commands {
        CommandMenu("Task") {
            // The composer's destination picker in one command, for the case it is
            // always used for: a task about the note you are looking at.
            Button("Nuovo task in questa nota") {
                guard let note = vault.openNote else { return }
                vault.beginTaskCapture(into: .note(note.relativePath))
            }
            .disabled(vault.openNote == nil)

            Divider()
            Button(ShortcutCommand.taskToggle.title) { actions.run(.taskToggle) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskToggle))
                .disabled(!actions.canRun(.taskToggle))
            // The menu is the whole point of this entry as much as the key is: the UX
            // blueprint asks for «Aggiungi sotto-task» to be reachable with no mouse and
            // no toolbar, and a command that only exists as a keystroke is a command
            // nobody discovers. The binding comes from the store, never from a literal
            // (ADR-0002).
            Button("Aggiungi sotto-task") { actions.run(.taskAddSubtask) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskAddSubtask))
                .disabled(!actions.canRun(.taskAddSubtask))

            Divider()
            Button(ShortcutCommand.taskToday.title) { actions.run(.taskToday) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskToday))
            Button(ShortcutCommand.taskTomorrow.title) { actions.run(.taskTomorrow) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskTomorrow))
            Button(ShortcutCommand.taskPlusTwo.title) { actions.run(.taskPlusTwo) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskPlusTwo))
            Button(ShortcutCommand.taskNextWeek.title) { actions.run(.taskNextWeek) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskNextWeek))
            Button("Togli la data") {
                Task { @MainActor in await vault.rescheduleSelectedTask(daysFromToday: nil) }
            }
                .disabled(vault.selectedTask == nil)

            Divider()
            if let task = vault.selectedTask {
                ForEach(TaskCommand.available(for: task), id: \.self) { command in
                    Button(command.title) { actions.run(command, on: task) }
                }
            } else {
                // Disabled rather than omitted, matching every other Task menu entry
                // above: a command that vanishes with nothing selected teaches nobody
                // that it exists.
                ForEach([TaskCommand.linkBoard, .goToNote], id: \.self) { command in
                    Button(command.title) {}.disabled(true)
                }
            }
        }
    }
}
