import SwiftUI

/// The week scale of the day view (ADR-0013 §D4): seven lists, four sources, the daily
/// note in the header.
///
/// Not an hour grid. Hours are the day view's job (SPEC §8.3) and it already draws them
/// well; seven columns of hours inside one window give each event about ninety points
/// of width and a shape nobody reads. Seven lists show what the day cannot - what the
/// days weigh against each other.
///
/// The whole column is one target: a click anchors the week on that day without leaving
/// the scale, and the number in the header is the button that opens it. That split is
/// what keeps the anchor movable while the week stays on screen, and in the next slice
/// it is what keeps a dropped task from also changing the scale.
struct WeekView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    let controller: DayController

    /// Measured rather than assumed: how many rows fit is what decides when a column
    /// starts saying "altri 3" instead of showing them.
    @State private var gridHeight: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(controller.columns) { column in
                dayColumn(column)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            gridHeight = height
        }
        .padding(theme.spacing(.m))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("week-grid")
    }

    // MARK: A day

    private func dayColumn(_ column: DayColumn) -> some View {
        let split = WeekPlan.split(column.entries, limit: entryLimit)
        let isAnchor = column.day == controller.day
        return VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header(column, isAnchor: isAnchor)
            ForEach(split.shown) { entry in
                WeekEntryRow(entry: entry) { reveal(entry, on: column.day) }
            }
            if split.hidden > 0 { HiddenEntriesRow(count: split.hidden) }
            Spacer(minLength: 0)
        }
        .padding(theme.spacing(.xs))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(.backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .stroke(isAnchor ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.show(column.day) }
        .contextMenu { menu(for: column) }
        .accessibilityIdentifier("week-column-\(column.day.compactForm)")
    }

    /// The day, and whether it has a daily note - a dot rather than a row, because the
    /// note is the column's subject and not one of the things in it.
    ///
    /// A Saturday, a Sunday and a holiday are three shades of red on the weekday and on
    /// the number, and the holiday says its name underneath, where a column has the
    /// vertical room a month cell does not.
    private func header(_ column: DayColumn, isAnchor: Bool) -> some View {
        let kind = ItalianHolidays.kind(of: column.day, patron: vault.settings.patronSaint)
        let name = ItalianHolidays.name(of: column.day, patron: vault.settings.patronSaint)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Text(Self.weekdayAbbreviation(column.day))
                    .themedText(.caption, color: kind.token ?? (isAnchor ? .accentPrimary : .textSecondary))
                    .lineLimit(1)

                Button {
                    controller.show(column.day)
                    controller.scale = .day
                } label: {
                    Text("\(column.day.day)")
                        .themedText(.caption, color: numberColor(column.day, kind: kind))
                }
                .buttonStyle(.plain)
                .help("Apri il \(column.day.italianForm)")
                .accessibilityIdentifier("week-open-day-\(column.day.compactForm)")

                if column.hasNote {
                    Circle()
                        .fill(theme.color(.textTertiary))
                        .frame(width: 4, height: 4)
                        .help("Ha una nota del giorno")
                }
                Spacer(minLength: 0)
            }

            if let name {
                Text(name)
                    .themedText(.caption, color: .calendarHoliday)
                    .lineLimit(1)
                    .help(name)
            }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.color(.borderSubtle)).frame(height: 1)
        }
    }

    /// The anchor and today keep the accent even on a red day: they say where you are,
    /// and losing that is worse than losing which shade of red a Sunday is.
    private func numberColor(_ day: CalendarDate, kind: ItalianHolidays.DayKind) -> ColorToken {
        if day == .today { return .accentPrimary }
        return kind.token ?? .textPrimary
    }

    @ViewBuilder
    private func menu(for column: DayColumn) -> some View {
        Button("Vai a questo giorno") { controller.show(column.day) }
        Button("Apri nella scala Giorno") {
            controller.show(column.day)
            controller.scale = .day
        }
        Button(column.hasNote ? "Apri la daily note" : "Crea la daily note") {
            controller.show(column.day)
            controller.openDailyNote()
        }
    }

    // MARK: Rows

    /// Every row goes somewhere: a task to its line, a block or an event to the day
    /// they sit on. `DayEntryReveal` says which and why.
    private var reveal: DayEntryReveal {
        DayEntryReveal(vault: vault, navigation: navigation, controller: controller)
    }

    /// How many rows a column can hold before it starts counting the rest.
    ///
    /// At least one: a window short enough to fit none would otherwise show a column
    /// that says only "altri 7", which is a count of things the user can no longer
    /// reach.
    private var entryLimit: Int {
        max(1, Int((gridHeight - Self.headerHeight) / Self.rowHeight))
    }

    /// `gio`. The whole name is what the day view's own header shows; a column ninety
    /// points wide takes the three letters an Italian calendar prints.
    private static func weekdayAbbreviation(_ day: CalendarDate) -> String {
        String(DateEntry.weekdayName(of: day).prefix(3))
    }

    private static let headerHeight: CGFloat = 26
    private static let rowHeight: CGFloat = 28
}
