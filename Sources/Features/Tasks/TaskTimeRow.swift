import SwiftUI

/// The hour on a date marker (ADR-0004), in the shape both panels use it.
///
/// Absent until it is asked for: most tasks are due on a day rather than at a time, and
/// a panel that always shows a clock invites an hour nobody meant to set.
struct TaskTimeRow: View {
    @Environment(\.theme) private var theme

    @Binding var time: TaskTime?
    /// False while there is no date to hang the hour on.
    var isEnabled = true

    /// Nine in the morning, the hour the reminder page starts from too.
    static let defaultTime = TaskTime(hour: 9, minute: 0)

    var body: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "clock").foregroundStyle(theme.color(.textTertiary))
            Text("Orario").themedText(.body, color: isEnabled ? .textPrimary : .textTertiary)
            Spacer(minLength: theme.spacing(.s))

            if let time {
                DatePicker("", selection: moment(of: time), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("time-row-picker")
                Button {
                    self.time = nil
                } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("time-row-clear")
                .help("Togli l'orario")
            } else {
                Button("Aggiungi") { time = Self.defaultTime }
                    .buttonStyle(.plain)
                    .themedText(.caption, color: isEnabled ? .accentPrimary : .textTertiary)
                    .accessibilityIdentifier("time-row-add")
                    .disabled(!isEnabled)
            }
        }
        .padding(.horizontal, theme.spacing(.s))
        .padding(.vertical, theme.spacing(.s))
        .help(isEnabled ? "Ora del giorno" : "Scegli prima la data")
    }

    /// The picker speaks `Date`; the marker speaks hour and minute. The day is
    /// arbitrary and never read back.
    private func moment(of time: TaskTime) -> Binding<Date> {
        Binding(
            get: {
                EventKitStore.date(.today, hour: time.hour, minute: time.minute) ?? Date()
            },
            set: { now in
                let clock = Calendar.current.dateComponents([.hour, .minute], from: now)
                self.time = TaskTime(hour: clock.hour ?? time.hour, minute: clock.minute ?? time.minute)
            }
        )
    }
}
