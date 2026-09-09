import AppKit
import SwiftUI

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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let route = PergamenumRoute(url) else { continue }
            // No explicit `NSApp.activate` here: opening the URL already brings the
            // app forward when it should, and calling it from a non-user-triggered
            // path is exactly the case the AppKit guidance warns about.
            vault?.handle(route)
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
    /// markers parsed correctly and no notification was ever scheduled.
    @State private var reminders = ReminderScheduler()
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
        _diary = State(initialValue: DiaryController(vault: vault))
        _recordings = State(initialValue: recordings)
        _pratiche = State(initialValue: PraticheController.live(vault: vault))

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
            onToday: { vault.handle(.today) },
            onInbox: { vault.handle(.note(path: VaultSession.TaskDestination.inboxPath)) }
        )
        commandActions = CommandActions(
            navigation: navigation,
            vault: vault,
            day: day,
            calendar: calendar,
            capturePanel: panel,
            history: history,
            recordings: recordings
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
                .environment(shortcuts)
                .environment(commandActions)
                .themed(by: themeEngine)
                // The window keeps its name for Mission Control and the Finestra menu; the
                // toolbar does not show it. macOS draws the title between the leading and the
                // trailing toolbar groups, which with a split editor puts the word
                // «Pergamenum» exactly on the seam between the two columns - and the note you
                // are looking at is named on its tab, one row below, where it belongs.
                .toolbar(removing: .title)
                .onAppear { appDelegate.vault = vault }
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
                // Rescheduled on every completed scan and on every task the app writes,
                // against the whole vault: the tasks on disk are the source of truth, so
                // the scheduler replaces its pending notifications wholesale rather than
                // trying to diff them.
                .task(id: vault.taskGeneration) {
                    await reminders.refreshAccessStatus()
                    await reminders.reschedule(for: vault.index.allTasks)
                    await reminders.refreshPending()
                }
                .task {
                    // Reopens the notes folder the app was last in (SPEC §10,
                    // "Cartelle recenti"). Guarded on `root` so a link that already opened one
                    // is not overridden by the previous session's vault.
                    guard vault.root == nil, let recent = RecentVaults().mostRecent else { return }
                    await vault.open(recent)
                }
                // Kept alongside the delegate: SwiftUI consumes the Apple Event
                // itself, so `application(_:open:)` is never called in a SwiftUI app
                // that has a WindowGroup. The delegate stays as the path for a link
                // that arrives before any window exists.
                .onOpenURL { url in
                    guard let route = PergamenumRoute(url) else { return }
                    vault.handle(route)
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
            Button("Completa o riapri") { actions.run(.taskToggle) }
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
            Button("Pianifica oggi") { actions.run(.taskToday) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskToday))
            Button("Domani") { actions.run(.taskTomorrow) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskTomorrow))
            Button("+2 giorni") { actions.run(.taskPlusTwo) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskPlusTwo))
            Button("Settimana prossima") { actions.run(.taskNextWeek) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskNextWeek))
            Button("Togli la data") { vault.rescheduleSelectedTask(daysFromToday: nil) }
                .disabled(vault.selectedTask == nil)

            Divider()
            Button("Collega nota o board…") { vault.isLinkingSelectedTask = true }
                .disabled(vault.selectedTask == nil)
            Button("Vai alla nota di origine") {
                if let task = vault.selectedTask { vault.openNote(at: task.sourcePath) }
            }
            .disabled(vault.selectedTask == nil)
        }
    }
}
