import SwiftUI

/// The month scale of the day view (ADR-0013 §D4): the same week, seen from further
/// away.
///
/// It shares the week's column arithmetic (`WeekPlan`), which is why the two line up
/// when you switch between them, and it keeps the neighbouring months visible in grey
/// rather than blanking them: the last days of the previous month are days things
/// happen on, and this is a scale of the calendar rather than a date picker. The date
/// picker is `MiniCalendar`, in the day scale's own column, and it still pads with
/// holes for the opposite reason - an empty cell there is a cell nobody can click.
struct MonthView: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault
    @Environment(Navigation.self) private var navigation

    let controller: DayController

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            weekdayRow
            ForEach(weeks, id: \.first?.id) { week in
                HStack(alignment: .top, spacing: 4) {
                    ForEach(week) { column in
                        cell(column)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(theme.spacing(.m))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.color(.backgroundPrimary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("month-grid")
    }

    /// The columns as weeks of seven, in the order the controller built them.
    private var weeks: [[DayColumn]] {
        stride(from: 0, to: controller.columns.count, by: 7).map { start in
            Array(controller.columns[start..<min(start + 7, controller.columns.count)])
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 4) {
            ForEach(Self.weekdays, id: \.self) { name in
                Text(name)
                    .themedText(.caption, color: .textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: A day

    private func cell(_ column: DayColumn) -> some View {
        let split = WeekPlan.split(column.entries, limit: Self.entryLimit)
        let isAnchor = column.day == controller.day
        let isOtherMonth = column.day.month != controller.day.month
        let body = VStack(alignment: .leading, spacing: 1) {
            header(column, isOtherMonth: isOtherMonth)
            ForEach(split.shown) { entry in
                MonthEntryRow(entry: entry) { reveal(entry, on: column.day) }
            }
            if split.hidden > 0 { HiddenEntriesRow(count: split.hidden) }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.color(isOtherMonth ? .backgroundPrimary : .backgroundSecondary))
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .stroke(isAnchor ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { controller.show(column.day) }
        .contextMenu { menu(for: column) }
        .accessibilityIdentifier("month-cell-\(column.day.compactForm)")

        return TaskDropTarget(
            cornerRadius: theme.radius(.control),
            onDrop: { await controller.drop($0, on: column.day) },
            content: { body }
        )
    }

    /// The number carries the red; the holiday's name is the tooltip. A cell sixty
    /// points tall that tries to write "Immacolata" writes nothing else.
    private func header(_ column: DayColumn, isOtherMonth: Bool) -> some View {
        let name = ItalianHolidays.name(of: column.day, patron: vault.settings.patronSaint)
        return HStack(spacing: 3) {
            Button {
                controller.show(column.day)
                controller.scale = .day
            } label: {
                Text("\(column.day.day)")
                    .themedText(.caption, color: numberColor(column.day, isOtherMonth: isOtherMonth))
            }
            .buttonStyle(.plain)
            .help(name ?? "Apri il \(column.day.italianForm)")
            .accessibilityIdentifier("month-open-day-\(column.day.compactForm)")

            if column.hasNote {
                Circle()
                    .fill(theme.color(.textTertiary))
                    .frame(width: 4, height: 4)
                    .help("Ha una nota del giorno")
            }
            Spacer(minLength: 0)
        }
    }

    /// Today keeps the accent, a red day takes its shade, and a day of the month next
    /// door stays grey whatever it is: in the month, "not this month" is the first
    /// thing the eye has to be able to skip.
    private func numberColor(_ day: CalendarDate, isOtherMonth: Bool) -> ColorToken {
        if day == .today { return .accentPrimary }
        if isOtherMonth { return .textTertiary }
        return ItalianHolidays.kind(of: day, patron: vault.settings.patronSaint).token ?? .textSecondary
    }

    /// The same menu the week grid draws, once (`DayColumnMenu`).
    private func menu(for column: DayColumn) -> some View {
        DayColumnMenu(column: column, controller: controller)
    }

    /// The same four destinations as the week: a cell is smaller, not different.
    private var reveal: DayEntryReveal {
        DayEntryReveal(vault: vault, navigation: navigation, controller: controller)
    }

    /// Two rows and then a number. A cell tall enough for three on a large display
    /// would be a cell that shows two on every other one, and a month whose contents
    /// change with the window is a month nobody can learn to read.
    private static let entryLimit = 2

    /// Monday first, as the Italian week is read.
    private static let weekdays = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]
}
