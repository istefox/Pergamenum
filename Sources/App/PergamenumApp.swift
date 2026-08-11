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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themeEngine)
                .environment(vault)
                .environment(calendar)
                .themed(by: themeEngine)
                .onAppear { appDelegate.vault = vault }
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
            VaultCommands(vault: vault)
            LinkCommands(vault: vault)
            ThemeCommands(engine: themeEngine)
        }

        // After the WindowGroup on purpose: the first scene in the body is the app's
        // primary one, and declaring Settings first made the app open its preferences
        // window instead of the vault.
        Settings {
            SettingsView()
                .environment(themeEngine)
                .environment(vault)
                .environment(calendar)
                .themed(by: themeEngine)
        }
    }
}

/// The Inserisci-menu entry for a structural link (SPEC §10, §4.5).
struct LinkCommands: Commands {
    let vault: VaultController

    var body: some Commands {
        CommandMenu("Inserisci") {
            Button("Nota correlata…") { vault.isAddingRelatedLink = true }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(vault.openNote == nil)
        }
    }
}

/// The File-menu entries that need the vault (SPEC §10).
struct VaultCommands: Commands {
    let vault: VaultController

    /// Puts a `pergamenum://` link to the open note on the pasteboard, for pasting
    /// into Obsidian, DEVONthink, Mail or Calendar (SPEC §9).
    private func copyLinkToOpenNote() {
        guard let note = vault.openNote, let url = PergamenumLink.note(path: note.relativePath) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func revealOpenNote() {
        guard let note = vault.openNote, let root = vault.root else { return }
        NSWorkspace.shared.activateFileViewerSelecting([
            root.appending(path: note.relativePath, directoryHint: .notDirectory),
        ])
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Nuova nota") { vault.isCreatingNote = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(vault.root == nil)
            Button("Oggi") { try? vault.openDailyNote(for: .today) }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(vault.root == nil)
            Button("Nuovo task rapido") { vault.isCapturingTask = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(vault.root == nil)
            Button("Anteprima rapida") { vault.isShowingQuickLook = true }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(vault.root == nil)
            Button("Ricerca globale…") { vault.isShowingGlobalSearch = true }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(vault.root == nil)
            Button("Vai alla nota…") { vault.isShowingQuickSwitcher = true }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(vault.root == nil)
            Button("Salva") { vault.saveOpenNote() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(vault.openNote?.hasUnsavedChanges != true)
            Divider()
            Button("Apri vault…") { VaultOpenPanel.chooseVault(into: vault) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Importa convenzioni…") { VaultOpenPanel.chooseHarnessRepository(into: vault) }
                .disabled(vault.root == nil)
            Divider()
            Button("Rigenera indice") { Task { await vault.rescan() } }
                .disabled(vault.root == nil)
            Divider()
            Button("Copia link Pergamenum") { copyLinkToOpenNote() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(vault.openNote == nil)
            Button("Rivela nel Finder") { revealOpenNote() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
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
