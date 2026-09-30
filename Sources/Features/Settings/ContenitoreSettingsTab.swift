import AppKit
import SwiftUI

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D13, plan
// docs/plans/contenitore.md, Task 6 - R-26; mockup 1g.
//
// The twelfth Settings tab. Both folders are validated and stored through
// `ContenitoreController`, which the `Settings` scene injects for exactly this; a refusal is
// shown in the controller's own sentence and the setting stays as it was.
struct ContenitoreSettingsTab: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(ContenitoreController.self) private var contenitore

    @State private var dropFolderRefusal: String?
    @State private var rootRefusal: String?

    var body: some View {
        Form {
            dropFolderRow
            rootRow
            statusRow
            LabeledContent("Testo estratto") {
                Text("Il testo estratto vive nella cache dell'app, fuori dalla vault. «Svuota cache» lo rigenera; nessun file della vault cambia.")
                    .themedText(.caption, color: .textSecondary)
                    .frame(maxWidth: 420, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }

    // MARK: - Cartella di raccolta

    private var dropFolderRow: some View {
        LabeledContent("Cartella di raccolta") {
            VStack(alignment: .trailing, spacing: theme.spacing(.xs)) {
                HStack {
                    Text(contenitore.dropFolderDisplay)
                        .themedText(.body, color: .textSecondary)
                        .accessibilityIdentifier("settings-contenitore-drop-folder-label")
                    Button("Scegli…") { chooseDropFolder() }
                        .accessibilityIdentifier("settings-contenitore-drop-folder-choose")
                    Button("Rivela nel Finder") {
                        if let folder = contenitore.resolvedDropFolder { contenitore.revealFiles([folder]) }
                    }
                }
                Text("I file che metti qui vengono spostati nel Contenitore appena smettono di cambiare. "
                    + "Deve stare fuori dalla vault; non può essere la cartella Inizio né /. Sotto Scrivania, "
                    + "Documenti o Download macOS chiede il permesso alla prima lettura.")
                    .themedText(.caption, color: .textSecondary)
                    .frame(maxWidth: 420, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                if let dropFolderRefusal {
                    Text(dropFolderRefusal)
                        .themedText(.caption, color: .taskOverdue)
                        .accessibilityIdentifier("settings-contenitore-drop-folder-refused")
                }
            }
        }
    }

    private func chooseDropFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = contenitore.resolvedDropFolder?.deletingLastPathComponent()
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        dropFolderRefusal = contenitore.setDropFolder(chosen)?.sentence
    }

    // MARK: - Cartella radice

    private var rootRow: some View {
        LabeledContent("Cartella radice") {
            VStack(alignment: .trailing, spacing: theme.spacing(.xs)) {
                HStack {
                    Text(vault.settings.contenitore.root)
                        .themedText(.body, color: .textSecondary)
                        .accessibilityIdentifier("settings-contenitore-root-label")
                    Button("Scegli…") { chooseRoot() }
                        .accessibilityIdentifier("settings-contenitore-root-choose")
                }
                Text("Una cartella dentro la vault, non la vault stessa, non dentro Pratiche. "
                    + "Cambiare la radice non sposta nulla: le schede sotto la vecchia radice smettono di essere documenti.")
                    .themedText(.caption, color: .textSecondary)
                    .frame(maxWidth: 420, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                if let rootRefusal {
                    Text(rootRefusal)
                        .themedText(.caption, color: .taskOverdue)
                        .accessibilityIdentifier("settings-contenitore-root-refused")
                }
            }
        }
    }

    private func chooseRoot() {
        guard let root = vault.root else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = root
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        guard let relative = PraticheSettingsTab.relativeRootFolder(chosen: chosen, vaultRoot: root) else {
            rootRefusal = ContenitoreSettings.RootRefusal.outsideVault.sentence
            return
        }
        rootRefusal = contenitore.setRoot(relative)?.sentence
    }

    // MARK: - Stato

    private var statusRow: some View {
        LabeledContent("Stato") {
            VStack(alignment: .trailing, spacing: theme.spacing(.xs)) {
                Text(statusLine)
                    .themedText(.body, color: .textSecondary)
                    .accessibilityIdentifier("settings-contenitore-status")
                if let extraction = extractionLine {
                    Text(extraction).themedText(.caption, color: .textSecondary)
                }
                Button("Importa ora") { Task { await contenitore.observe() } }
                    .disabled(contenitore.isIsolated || !contenitore.isDropFolderReadable)
            }
        }
    }

    private var statusLine: String {
        if contenitore.isIsolated { return "Disattivato per questa sessione" }
        let listening = contenitore.isDropFolderReadable ? "In ascolto" : "Cartella di raccolta illeggibile"
        guard let session = vault.session else { return listening }
        let documents = session.index.schede(underRoot: contenitore.root).count
        let inbox = ContenitoreListModel.inboxCount(index: session.index, root: contenitore.root)
        return "\(listening) · \(documents) documenti · \(inbox) da classificare"
    }

    private var extractionLine: String? {
        guard let progress = contenitore.queue?.progress, let current = progress.values.first else { return nil }
        let page = current.total > 0 ? " (pagina \(current.done) di \(current.total))" : ""
        return "Estrazione del testo: 1 in corso\(page)."
    }
}
