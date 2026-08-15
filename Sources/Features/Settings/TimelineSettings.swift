import SwiftUI

/// Impostazioni › Giornata: how much of a day each timeline draws.
///
/// Two windows, one per section, because the two answer different questions. The Oggi
/// pane is a plan for a working day; the Diario is the day as it was lived, and it is
/// written in the evening, about the evening. One shared setting would make one of them
/// wrong.
///
/// Neither window hides anything: both timelines widen themselves to reach a block or
/// an event outside the hours set here. The setting says which hours are always drawn,
/// not which hours may exist.
struct TimelineSettings: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    var body: some View {
        Form {
            Section("Oggi") {
                window(
                    vault.settings.dayHours,
                    identifier: "day",
                    set: { new in vault.updateSettings { $0.dayHours = new } }
                )
                Text("Le ore della timeline accanto alla nota del giorno.")
                    .themedText(.caption, color: .textTertiary)
            }

            Section("Diario") {
                window(
                    vault.settings.diaryHours,
                    identifier: "diary",
                    set: { new in vault.updateSettings { $0.diaryHours = new } }
                )
                Text("Le ore della giornata nella sezione Diario.")
                    .themedText(.caption, color: .textTertiary)
            }

            Text("""
                Un blocco fuori da queste ore resta visibile: la griglia si allarga da \
                sola per raggiungerlo. 24:00 è la fine del giorno.
                """)
                .themedText(.caption, color: .textTertiary)
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }

    /// The two ends of one window. Each picker offers only hours that keep the window
    /// the right way round, so there is no way to set an end before its beginning.
    private func window(
        _ current: HourWindow,
        identifier: String,
        set: @escaping (HourWindow) -> Void
    ) -> some View {
        HStack(spacing: theme.spacing(.m)) {
            Picker("Dalle", selection: Binding(
                get: { current.first },
                set: { set(HourWindow.clamped(first: $0, last: current.last)) }
            )) {
                ForEach(HourWindow.firstChoices, id: \.self) { hour in
                    Text(HourWindow.label(hour)).tag(hour)
                }
            }
            .frame(width: 150)
            .accessibilityIdentifier("hours-\(identifier)-first")

            Picker("alle", selection: Binding(
                get: { current.last },
                set: { set(HourWindow.clamped(first: current.first, last: $0)) }
            )) {
                ForEach(HourWindow.lastChoices.filter { $0 > current.first }, id: \.self) { hour in
                    Text(HourWindow.label(hour)).tag(hour)
                }
            }
            .frame(width: 150)
            .accessibilityIdentifier("hours-\(identifier)-last")

            Text("\(current.hours) ore")
                .themedText(.caption, color: .textTertiary)
            Spacer(minLength: 0)
        }
    }
}
