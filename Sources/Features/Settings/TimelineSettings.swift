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

            patron
        }
        .formStyle(.grouped)
        .disabled(vault.root == nil)
    }

    // MARK: The patron saint

    /// The one red day no algorithm knows.
    ///
    /// The twelve national holidays are computed from the year (`ItalianHolidays`) and
    /// need no setting; the local patron is a name and a date that depend on where you
    /// live, and guessing it would put a wrong red day in the calendar every year.
    /// Empty means no patron, which is what a vault outside Italy wants too.
    private var patron: some View {
        Section("Santo patrono") {
            HStack(spacing: theme.spacing(.m)) {
                TextField("Nome", text: Binding(
                    get: { vault.settings.patronSaint?.name ?? "" },
                    set: { name in setPatron(name: name) }
                ))
                .frame(width: 220)
                .accessibilityIdentifier("patron-name")

                Picker("il", selection: Binding(
                    get: { vault.settings.patronSaint?.day ?? 1 },
                    set: { day in setPatron(day: day) }
                )) {
                    ForEach(1...31, id: \.self) { day in Text("\(day)").tag(day) }
                }
                .frame(width: 90)
                .accessibilityIdentifier("patron-day")

                Picker("", selection: Binding(
                    get: { vault.settings.patronSaint?.month ?? 1 },
                    set: { month in setPatron(month: month) }
                )) {
                    ForEach(1...12, id: \.self) { month in
                        Text(DateEntry.monthName(month: month, year: 2000)).tag(month)
                    }
                }
                .frame(width: 140)
                .accessibilityIdentifier("patron-month")

                Spacer(minLength: 0)
            }

            Text("""
                Le feste nazionali sono calcolate, Pasqua compresa, e non vanno importate \
                da nessuna parte. Questa è l'unica che dipende da dove vivi: senza nome \
                resta un giorno qualunque.
                """)
                .themedText(.caption, color: .textTertiary)
        }
    }

    /// Writes the three fields as one value, and clears it when the name is emptied:
    /// a patron with no name is a red day with nothing to say.
    private func setPatron(name: String? = nil, day: Int? = nil, month: Int? = nil) {
        let current = vault.settings.patronSaint
        let newName = (name ?? current?.name ?? "").trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty else {
            vault.updateSettings { $0.patronSaint = nil }
            return
        }
        let newMonth = month ?? current?.month ?? 1
        let newDay = day ?? current?.day ?? 1
        // The 31st of February is a typo, not a holiday: the last valid day of that
        // month is what the picker settles on rather than a date the calendar refuses.
        let clamped = (1...31).reversed().first { candidate in
            candidate <= newDay && CalendarDate(year: 2001, month: newMonth, day: candidate) != nil
        } ?? 1
        vault.updateSettings {
            $0.patronSaint = PatronSaint(month: newMonth, day: clamped, name: newName)
        }
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
