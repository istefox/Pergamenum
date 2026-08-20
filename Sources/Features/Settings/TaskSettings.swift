import SwiftUI

/// The task tab of the settings window (SPEC §12).
///
/// Its own type because `SettingsView` is one tab away from the size SwiftLint stops
/// at, and a tab is a self-contained piece of it.
struct TaskSettings: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    var body: some View {
        tasksTab
    }

    /// The task side of SPEC §12. Per-vault rather than per-user: a time block is a
    /// line in a daily note, so how long one lasts belongs with the notes.
    private var tasksTab: some View {
        Form {
            Picker("Durata predefinita del blocco tempo", selection: Binding(
                get: { vault.settings.blockMinutes },
                set: { value in vault.updateSettings { $0.blockMinutes = value } }
            )) {
                ForEach(VaultSettings.blockDurations, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .accessibilityIdentifier("settings-block-duration")
            Text(
                "Vale per «Inserisci Blocco Tempo», per un task trascinato su un'ora "
                    + "e per i blocchi creati da un task con orario."
            )
                .themedText(.caption, color: .textTertiary)
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }
}
