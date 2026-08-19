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
    /// The keyboard shortcuts in force. Held at app level because the menu bar is
    /// built here and the settings window that edits them is a separate scene.
    @State private var shortcuts = ShortcutStore()
    /// Local notifications for `@remind(...)` (SPEC §7.1). Held here so it outlives
    /// any one view: it was written, unit-tested and never instantiated, so the
    /// markers parsed correctly and no notification was ever scheduled.
    @State private var reminders = ReminderScheduler()
    /// The day view's controller, created here rather than inside the view so the
    /// Calendario menu can act on the day being shown (SPEC §10).
    @State private var day: DayController
    /// The Diario pane's controller. At app level so a day being written survives a
    /// switch to another pane and back: as view state it would be rebuilt, and the
    /// unsaved end of a sentence would go with it.
    @State private var diary: DiaryController
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

        _themeEngine = State(initialValue: engine)
        _vault = State(initialValue: vault)
        _calendar = State(initialValue: calendar)
        _navigation = State(initialValue: navigation)
        _capture = State(initialValue: capture)
        _hotkey = State(initialValue: hotkey)
        _day = State(initialValue: day)
        _diary = State(initialValue: DiaryController(vault: vault))

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
            capturePanel: panel
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
                .environment(reminders)
                .environment(day)
                .environment(diary)
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

/// The File-menu entries that need an open notes folder (SPEC §10).
struct VaultCommands: Commands {
    let vault: VaultController
    let navigation: Navigation
    let shortcuts: ShortcutStore
    let capturePanel: CapturePanel
    let actions: CommandActions

    /// Exports the open note without its frontmatter or its "Note correlate"
    /// section (SPEC §10).
    private func export(as format: NoteExporter.Format) {
        guard let note = vault.openNote else { return }
        if let problem = NoteExporter.export(title: note.title, text: note.text, as: format) {
            vault.recordProblem(problem)
        }
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nuova nota") { actions.run(.newNote) }
                .keyboardShortcut(shortcuts.shortcut(for: .newNote))
                .disabled(!actions.canRun(.newNote))
            Button("Oggi") { actions.run(.dailyNote) }
                .keyboardShortcut(shortcuts.shortcut(for: .dailyNote))
                .disabled(!actions.canRun(.dailyNote))
            Button("Nuovo task rapido") { actions.run(.quickTask) }
                .keyboardShortcut(shortcuts.shortcut(for: .quickTask))
                .disabled(!actions.canRun(.quickTask))
            Divider()
            Button("Nuova tab") { actions.run(.newTab) }
                .keyboardShortcut(shortcuts.shortcut(for: .newTab))
                .disabled(!actions.canRun(.newTab))
            Button("Chiudi tab") { actions.run(.closeTab) }
                .keyboardShortcut(shortcuts.shortcut(for: .closeTab))
                .disabled(!actions.canRun(.closeTab))
            Button("Riapri l'ultima tab chiusa") { actions.run(.reopenTab) }
                .keyboardShortcut(shortcuts.shortcut(for: .reopenTab))
                .disabled(!actions.canRun(.reopenTab))
            // Cmd+1…Cmd+9, positional and therefore not in the remappable catalogue
            // (ADR-0012 D5). Nine is the last tab, whatever its position, as in Safari.
            ForEach(1...9, id: \.self) { number in
                Button("Vai alla tab \(number)") { vault.selectTab(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Divider()
            // No `.keyboardShortcut`: this one is registered with the system and fires
            // whether or not Pergamenum is in front (ADR-0008 §D1). A menu equivalent
            // here as well, because a hot key the system refused leaves the command
            // reachable, and because a command with no menu entry cannot be discovered.
            Button("Cattura rapida") { actions.run(.globalCapture) }
                .disabled(!actions.canRun(.globalCapture))
            Button("Anteprima rapida") { actions.run(.quickLook) }
                .keyboardShortcut(shortcuts.shortcut(for: .quickLook))
                .disabled(!actions.canRun(.quickLook))
            Button("Ricerca globale…") { actions.run(.globalSearch) }
                .keyboardShortcut(shortcuts.shortcut(for: .globalSearch))
                .disabled(!actions.canRun(.globalSearch))
            Button("Vai alla nota…") { actions.run(.quickSwitcher) }
                .keyboardShortcut(shortcuts.shortcut(for: .quickSwitcher))
                .disabled(!actions.canRun(.quickSwitcher))
            Button("Salva") { actions.run(.save) }
                .keyboardShortcut(shortcuts.shortcut(for: .save))
                .disabled(!actions.canRun(.save))
            Button("Cronologia…") { actions.run(.noteHistory) }
                .keyboardShortcut(shortcuts.shortcut(for: .noteHistory))
                .disabled(!actions.canRun(.noteHistory))
            Divider()
            Button("Apri cartella note…") { actions.run(.openVault) }
                .keyboardShortcut(shortcuts.shortcut(for: .openVault))
            Menu("Cartelle recenti") {
                // Read at build time of the menu, so a vault deleted since the last
                // launch is simply not offered.
                let recents = RecentVaults().urls
                if recents.isEmpty {
                    Text("Nessuno")
                } else {
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            Task { await vault.open(url) }
                        }
                        .disabled(url.standardizedFileURL == vault.root?.standardizedFileURL)
                    }
                    Divider()
                    Button("Svuota elenco") { RecentVaults().forgetAll() }
                }
            }
            Button("Importa convenzioni…") { VaultOpenPanel.chooseHarnessRepository(into: vault) }
                .disabled(vault.root == nil)
            Menu("Esporta nota") {
                ForEach(NoteExporter.Format.allCases) { format in
                    Button(format.title) { export(as: format) }
                }
            }
            .disabled(vault.openNote == nil)
            Divider()
            Button("Rigenera indice") { Task { await vault.rescan() } }
                .disabled(vault.root == nil)
            Divider()
            Button("Copia link Pergamenum") { actions.run(.copyLink) }
                .keyboardShortcut(shortcuts.shortcut(for: .copyLink))
                .disabled(!actions.canRun(.copyLink))
            Button("Rivela nel Finder") { actions.run(.revealInFinder) }
                .keyboardShortcut(shortcuts.shortcut(for: .revealInFinder))
                .disabled(!actions.canRun(.revealInFinder))
        }
    }
}

/// The Vista > Tema section of the menu bar (SPEC §10). Lives here rather than in
/// the gallery because the menu belongs to the app, not to a feature.
struct ThemeCommands: Commands {
    @Bindable var engine: ThemeEngine

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Tema") {
                Picker("Tema", selection: $engine.selection) {
                    Text("Sistema").tag(ThemeEngine.Selection.followSystem)
                    Text("Chiaro").tag(ThemeEngine.Selection.light)
                    Text("Scuro").tag(ThemeEngine.Selection.dark)
                    ForEach(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }) { theme in
                        Text(theme.name).tag(ThemeEngine.Selection.named(theme.id))
                    }
                }
                .pickerStyle(.inline)
            }
        }
    }
}
