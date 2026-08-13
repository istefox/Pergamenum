import AppKit
import Foundation

/// Folder pickers for the vault and for the harness-system checkout.
///
/// Kept out of the views so the commands and the empty state can both open the same
/// panel without duplicating its configuration.
@MainActor
enum VaultOpenPanel {
    static func chooseVault(into controller: VaultController) {
        guard let url = pickDirectory(
            title: "Scegli la cartella delle note",
            message: "Seleziona la cartella che contiene le note (per esempio Labs)."
        ) else { return }
        // The recents list is written by `VaultController.open` itself, so a vault
        // opened from the menu, from a link or from this panel is recorded once, in
        // one place.
        Task { await controller.open(url) }
    }

    static func chooseHarnessRepository(into controller: VaultController) {
        guard let url = pickDirectory(
            title: "Importa convenzioni",
            message: "Seleziona la cartella della repo harness-system."
        ) else { return }
        controller.importConventions(from: url)
    }

    /// Picks one or more files to import onto a board.
    static func chooseFiles(title: String, message: String) -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.title = title
        panel.message = message
        return panel.runModal() == .OK ? panel.urls : nil
    }

    private static func pickDirectory(title: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.title = title
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}
