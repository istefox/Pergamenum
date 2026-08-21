import SwiftUI

// MARK: - La settimana e il mese (M12)

/// The two new scales of the day view (ADR-0013 §D4), drawn before they are built.
///
/// Four choices are put here for approval.
///
/// 1. **A week is seven lists, not an hour grid.** Hours are the day view's job (SPEC §8.3) and
///    it already draws them well. Seven columns of hours inside a reading column give each event
///    about ninety points of width and a shape nobody reads; seven lists give the week the thing
///    the day cannot show - what the days weigh against each other.
/// 2. **Four sources and no fifth**, in one order everywhere: events with their hour, then time
///    blocks, then tasks scheduled that day, then deadlines. The daily note is the column's
///    header rather than a row in it - a day is not a note that has a week, it is a day that has
///    a note, and the note is one click away.
/// 3. **A column that overflows says how many are left**, and never truncates silently. A week
///    that quietly showed four of eleven would be a week that lies about how full it is.
/// 4. **The drop target is the whole column**, outlined in the accent while a task is over it,
///    with the hour strip appearing only when the day is the one under the cursor. Dropping on
///    the day writes `>data`; dropping on an hour writes the time and makes the block (§D5).
///
/// Everything here is literal. No EventKit, no index, no vault.
struct WeekMockup: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing(.l)) {
                scene("La settimana: sette liste, quattro sorgenti, la nota del giorno "
                    + "nell'intestazione. Giovedì è il giorno ancorato, quello su cui si torna "
                    + "passando alla scala giorno.") {
                    WeekGridMockup()
                }
                scene("Un task trascinato: la colonna di destinazione si accende e mostra la "
                    + "striscia delle ore, che compare solo lì. Lasciarlo sul giorno riscrive "
                    + "`>data`; lasciarlo su un'ora scrive anche l'ora e crea il blocco.") {
                    WeekGridMockup(dropTarget: 4)
                }
                scene("Una colonna piena non tronca in silenzio: dice quante ne restano.") {
                    WeekGridMockup(crowded: true)
                }
                scene("Il mese: la stessa settimana vista da lontano. Ogni giorno porta al "
                    + "massimo due righe e poi un numero, un punto se ha una daily note, e i "
                    + "giorni dei mesi vicini restano visibili in grigio invece che sparire.") {
                    MonthGridMockup()
                }
            }
            .padding(theme.spacing(.l))
            .frame(maxWidth: MockupGalleryView.contentWidth, alignment: .leading)
        }
        .background(theme.color(.backgroundPrimary))
    }

    private func scene(_ caption: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            Text(caption).themedText(.caption, color: .textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }
}

// MARK: - La griglia della settimana

/// Seven columns and six 4-point gaps: 7 × 92 + 24 = 668 of the 672 a mockup paints in.
struct WeekGridMockup: View {
    @Environment(\.theme) private var theme

    /// Which column is under a dragged task, if any.
    var dropTarget: Int?
    /// Draws the day that has more than it can show.
    var crowded = false

    private static let column: CGFloat = 92
    private static let days = ["lun 24", "mar 25", "mer 26", "gio 27", "ven 28", "sab 29", "dom 30"]

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(Self.days.enumerated()), id: \.offset) { index, label in
                column(index: index, label: label)
            }
        }
    }

    private func column(index: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header(label, isAnchor: index == 3, hasNote: index != 5 && index != 6)
            if dropTarget == index {
                hours
            } else {
                entries(for: index)
            }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.xs))
        .frame(width: Self.column, height: 210, alignment: .topLeading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .stroke(dropTarget == index ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
        )
    }

    /// The day, and whether it has a daily note - a dot rather than a row, because the note is
    /// the column's subject and not one of the things in it.
    private func header(_ label: String, isAnchor: Bool, hasNote: Bool) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .themedText(.caption, color: isAnchor ? .accentPrimary : .textSecondary)
                .lineLimit(1)
            if hasNote {
                Circle()
                    .fill(theme.color(.textTertiary))
                    .frame(width: 4, height: 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.color(.borderSubtle)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func entries(for index: Int) -> some View {
        switch index {
        case 0:
            WeekEntryMockup(kind: .event, title: "Riunione tecnica", detail: "09:30")
            WeekEntryMockup(kind: .task, title: "Sopralluogo pressa 4", detail: nil)
        case 1:
            WeekEntryMockup(kind: .block, title: "Calcolo trasmissibilità", detail: "14:00")
        case 3:
            WeekEntryMockup(kind: .event, title: "Vibrofer, sopralluogo", detail: "11:00")
            WeekEntryMockup(kind: .block, title: "Disegno presse", detail: "15:00")
            if crowded {
                WeekEntryMockup(kind: .task, title: "Rivedere capitolato", detail: nil)
                WeekEntryMockup(kind: .task, title: "Chiamare Ceramiche", detail: nil)
                Text("altri 6")
                    .themedText(.caption, color: .textTertiary)
                    .padding(.top, 1)
            } else {
                WeekEntryMockup(kind: .deadline, title: "Capitolato", detail: nil)
            }
        case 4:
            WeekEntryMockup(kind: .deadline, title: "Consegna disegni", detail: nil)
        default:
            EmptyView()
        }
    }

    /// Shown on the targeted column only. A strip of hours on all seven at once would turn the
    /// week into the grid choice 1 refuses.
    private var hours: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach([9, 11, 14, 16], id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .themedText(.caption, color: .textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                    .background(theme.color(.surfaceSunken))
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
        }
    }
}

// MARK: - Il mese

/// Five weeks of seven days: 7 × 92 + 24 = 668, the same arithmetic the week uses, so the two
/// scales line up when you switch between them.
struct MonthGridMockup: View {
    @Environment(\.theme) private var theme

    private static let column: CGFloat = 92
    private static let weekdays = ["lu", "ma", "me", "gi", "ve", "sa", "do"]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                ForEach(Self.weekdays, id: \.self) { name in
                    Text(name).themedText(.caption, color: .textTertiary)
                        .frame(width: Self.column, alignment: .leading)
                }
            }
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { column in
                        day(row: row, column: column)
                    }
                }
            }
        }
    }

    private func day(row: Int, column: Int) -> some View {
        let number = row * 7 + column + 20
        let isOtherMonth = number > 31
        let shown = isOtherMonth ? number - 31 : number
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text("\(shown)")
                    .themedText(.caption, color: isOtherMonth ? .textTertiary : .textSecondary)
                if !isOtherMonth, shown % 3 != 0 {
                    Circle().fill(theme.color(.textTertiary)).frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
            }
            if shown == 27, !isOtherMonth {
                MonthEntryMockup(text: "Vibrofer", kind: .event)
                MonthEntryMockup(text: "Disegno", kind: .block)
                Text("altri 3").themedText(.caption, color: .textTertiary)
            } else if shown == 30, !isOtherMonth {
                MonthEntryMockup(text: "Consegna", kind: .deadline)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(width: Self.column, height: 62, alignment: .topLeading)
        .background(theme.color(isOtherMonth ? .backgroundPrimary : .backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
    }
}
