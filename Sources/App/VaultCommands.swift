import SwiftUI

/// The File-menu entries that need an open notes folder (SPEC §10).
///
/// Split out of `PergamenumApp.swift` (PG-035 — pure code motion, that file had drifted
/// past `file_length`'s warning threshold): fully self-contained, no access-level changes.
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
            Button("Nuova board") { actions.run(.newBoard) }
                .keyboardShortcut(shortcuts.shortcut(for: .newBoard))
                .disabled(!actions.canRun(.newBoard))
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
            Button("Importa file…") {
                if let urls = VaultOpenPanel.chooseFiles(
                    title: "Importa file",
                    message: "I file vengono copiati in 00 Inbox, con proposta di nome."
                ) {
                    vault.fileImportProposals = vault.proposeImport(urls)
                }
            }
            .disabled(vault.root == nil)
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
