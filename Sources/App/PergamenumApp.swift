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
    @State private var themeEngine = ThemeEngine()
    @State private var vault = VaultController()
    @State private var calendar = EventKitStore()
    @State private var navigation = Navigation()
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

    init() {
        let vault = VaultController()
        let calendar = EventKitStore()
        _vault = State(initialValue: vault)
        _calendar = State(initialValue: calendar)
        _day = State(initialValue: DayController(store: calendar, vault: vault))
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
                .environment(shortcuts)
                .themed(by: themeEngine)
                .onAppear { appDelegate.vault = vault }
                // Rescheduled on every completed scan, against the whole vault: the
                // tasks on disk are the source of truth, so the scheduler replaces its
                // pending notifications wholesale rather than trying to diff them.
                .task(id: vault.scanGeneration) {
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
            VaultCommands(vault: vault, shortcuts: shortcuts)
            EditCommands(navigation: navigation, shortcuts: shortcuts)
            InsertCommands(navigation: navigation, vault: vault, shortcuts: shortcuts)
            ViewCommands(navigation: navigation, vault: vault, shortcuts: shortcuts)
            TaskCommands(vault: vault, shortcuts: shortcuts)
            CalendarCommands(day: day, calendar: calendar, navigation: navigation, shortcuts: shortcuts)
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
                .themed(by: themeEngine)
        }
    }
}

/// The Task menu of SPEC §10, with the quick rescheduling of §7.3.
struct TaskCommands: Commands {
    let vault: VaultController
    let shortcuts: ShortcutStore

    var body: some Commands {
        CommandMenu("Task") {
            Button("Completa o riapri") {
                if let task = vault.selectedTask { vault.toggle(task) }
            }
            .keyboardShortcut(shortcuts.shortcut(for: .taskToggle))
            .disabled(vault.selectedTask == nil)

            Divider()
            Button("Pianifica oggi") { vault.rescheduleSelectedTask(daysFromToday: 0) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskToday))
            Button("Domani") { vault.rescheduleSelectedTask(daysFromToday: 1) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskTomorrow))
            Button("+2 giorni") { vault.rescheduleSelectedTask(daysFromToday: 2) }
                .keyboardShortcut(shortcuts.shortcut(for: .taskPlusTwo))
            Button("Settimana prossima") { vault.rescheduleSelectedTask(daysFromToday: 7) }
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
    let shortcuts: ShortcutStore

    /// Puts a `pergamenum://` link to the open note on the pasteboard, for pasting
    /// into Obsidian, DEVONthink, Mail or Calendar (SPEC §9).
    private func copyLinkToOpenNote() {
        guard let note = vault.openNote, let url = PergamenumLink.note(path: note.relativePath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    /// Exports the open note without its frontmatter or its "Note correlate"
    /// section (SPEC §10).
    private func export(as format: NoteExporter.Format) {
        guard let note = vault.openNote else { return }
        if let problem = NoteExporter.export(title: note.title, text: note.text, as: format) {
            vault.recordProblem(problem)
        }
    }

    private func revealOpenNote() {
        guard let note = vault.openNote, let root = vault.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            root.appending(path: note.relativePath, directoryHint: .notDirectory),
        ])
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nuova nota") {
                vault.newNoteFolder = ""
                vault.isCreatingNote = true
            }
                .keyboardShortcut(shortcuts.shortcut(for: .newNote))
                .disabled(vault.root == nil)
            // Reported rather than swallowed: Cmd+T doing nothing at all, with no
            // reason given, is the worst outcome when the daily note cannot be created.
            Button("Oggi") {
                do {
                    _ = try vault.openDailyNote(for: .today)
                } catch {
                    vault.recordProblem("nota del giorno: \(error)")
                }
            }
                .keyboardShortcut(shortcuts.shortcut(for: .dailyNote))
                .disabled(vault.root == nil)
            Button("Nuovo task rapido") { vault.isCapturingTask = true }
                .keyboardShortcut(shortcuts.shortcut(for: .quickTask))
                .disabled(vault.root == nil)
            Button("Anteprima rapida") { vault.isShowingQuickLook = true }
                .keyboardShortcut(shortcuts.shortcut(for: .quickLook))
                .disabled(vault.root == nil)
            Button("Ricerca globale…") { vault.isShowingGlobalSearch = true }
                .keyboardShortcut(shortcuts.shortcut(for: .globalSearch))
                .disabled(vault.root == nil)
            Button("Vai alla nota…") { vault.isShowingQuickSwitcher = true }
                .keyboardShortcut(shortcuts.shortcut(for: .quickSwitcher))
                .disabled(vault.root == nil)
            Button("Salva") { vault.saveOpenNote() }
                .keyboardShortcut(shortcuts.shortcut(for: .save))
                .disabled(vault.openNote?.hasUnsavedChanges != true)
            Divider()
            Button("Apri cartella note…") { VaultOpenPanel.chooseVault(into: vault) }
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
            Button("Copia link Pergamenum") { copyLinkToOpenNote() }
                .keyboardShortcut(shortcuts.shortcut(for: .copyLink))
                .disabled(vault.openNote == nil)
            Button("Rivela nel Finder") { revealOpenNote() }
                .keyboardShortcut(shortcuts.shortcut(for: .revealInFinder))
                .disabled(vault.openNote == nil)
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
