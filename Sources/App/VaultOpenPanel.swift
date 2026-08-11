import AppKit
import Foundation

/// Folder pickers for the vault and for the harness-system checkout.
///
/// Kept out of the views so the commands and the empty state can both open the same
/// panel without duplicating its configuration.
@MainActor
enum VaultOpenPanel {
    private static let lastVaultKey = "vault.lastOpened"

    static func chooseVault(into controller: VaultController) {
        guard let url = pickDirectory(
            title: "Scegli il vault",
            message: "Seleziona la cartella del vault (per esempio Labs)."
        ) else { return }

        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: lastVaultKey)
        Task { await controller.open(url) }
    }

    static func chooseHarnessRepository(into controller: VaultController) {
        guard let url = pickDirectory(
            title: "Importa convenzioni",
            message: "Seleziona la cartella della repo harness-system."
        ) else { return }
        controller.importConventions(from: url)
    }

    /// Reopens the vault used last, if it is still there.
    ///
    /// The path is stored rather than a security-scoped bookmark because the app is
    /// not sandboxed in v1 (SPEC §3). A bookmark becomes necessary the day it is.
    static func reopenLastVault(into controller: VaultController) {
        guard let path = UserDefaults.standard.string(forKey: lastVaultKey) else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return }
        Task { await controller.open(URL(fileURLWithPath: path, isDirectory: true)) }
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
