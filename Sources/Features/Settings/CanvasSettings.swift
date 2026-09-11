import SwiftUI

/// The canvas tab of the settings window (SPEC §12).
///
/// Lifted out of `SettingsView` when the editor tab arrived and the struct went one line
/// past the body length SwiftLint stops at - which the header of that file had been
/// predicting since the design system pane was added. Every tab it still holds inline is
/// a candidate for the same treatment.
struct CanvasSettings: View {
    @Environment(VaultController.self) private var vault

    var body: some View {
        Form {
            Toggle("Mostra la griglia", isOn: Binding(
                get: { vault.settings.boardShowsGrid },
                set: { value in vault.updateSettings { $0.boardShowsGrid = value } }
            ))
            Toggle("Aggancia alla griglia", isOn: Binding(
                get: { vault.settings.boardSnapsToGrid },
                set: { value in vault.updateSettings { $0.boardSnapsToGrid = value } }
            ))
            Text("Le guide di allineamento con le altre card restano attive comunque: hanno la precedenza sulla griglia.")
                .themedText(.caption, color: .textTertiary)

            Section("Import") {
                Picker("File trascinati", selection: Binding(
                    get: { vault.settings.copyDroppedFiles },
                    set: { value in vault.updateSettings { $0.copyDroppedFiles = value } }
                )) {
                    Text("Copia nella cartella note").tag(true)
                    Text("Riferimento dove sono").tag(false)
                }
                .pickerStyle(.radioGroup)
                Text("Un riferimento fuori dalla cartella note si rompe il giorno in cui il file viene spostato o il volume non è montato.")
                    .themedText(.caption, color: .textTertiary)
            }
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }
}
