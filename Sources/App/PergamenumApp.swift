import SwiftUI

@main
struct PergamenumApp: App {
    @State private var themeEngine = ThemeEngine()
    @State private var vault = VaultController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(themeEngine)
                .environment(vault)
                .themed(by: themeEngine)
        }
        .windowResizability(.contentMinSize)
        .commands {
            VaultCommands(vault: vault)
            ThemeCommands(engine: themeEngine)
        }
    }
}

/// The File-menu entries that need the vault (SPEC §10).
struct VaultCommands: Commands {
    let vault: VaultController

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
