import SwiftUI

// PG-387 (N4), ADR-0086 §D2, plan docs/plans/pg-387-n4-birth-of-note.md, Task 6 - R-06.

/// «Modello della nota del giorno» in Convenzioni, beside the daily folder: the vault's templates
/// plus «Nessuno», written through `VaultController.setDailyTemplate(_:)`. A stored path that no
/// longer names a template stays listed under its path, so the picker never shows a value it
/// cannot select; `dailyNoteBirth` already records the problem when it reads it.
struct DailyTemplateField: View {
    @Environment(VaultController.self) private var vault

    private var stored: String { vault.settings.dailyTemplate ?? "" }

    var body: some View {
        Picker("Modello della nota del giorno", selection: Binding(
            get: { stored },
            set: { vault.setDailyTemplate($0) }
        )) {
            Text("Nessuno").tag("")
            ForEach(vault.templates, id: \.relativePath) { record in
                Text(record.title).tag(record.relativePath)
            }
            if !stored.isEmpty, !vault.templates.contains(where: { $0.relativePath == stored }) {
                Text(stored).tag(stored)
            }
        }
        .disabled(vault.root == nil)
        .accessibilityIdentifier("settings-daily-template")
    }
}
