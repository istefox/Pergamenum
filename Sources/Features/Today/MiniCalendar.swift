import SwiftUI

/// The month grid beside the day view, and the context menu SPEC §10 asks for on a
/// day ("apri daily note").
///
/// The grid is built from `CalendarDate` arithmetic rather than from `DateComponents`
/// on the fly, so a month boundary behaves the same here as everywhere else in the
/// app: one date type, one set of rules.
struct MiniCalendar: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    let day: CalendarDate
    let onSelect: (CalendarDate) -> Void
    let onOpenDailyNote: (CalendarDate) -> Void
    /// Set by the day view from the width it has, so the grid keeps its proportions
    /// instead of drawing cells four times wider than tall.
    var cellHeight: CGFloat = 22
    /// Days an open task is due on. A deadline is the one date whose whole purpose is
    /// to be seen before it arrives, so the month carries it.
    var dueDays: Set<CalendarDate> = []

    /// The month being shown, which follows the day unless the user pages away.
    @State private var visibleMonth: CalendarDate?

    private var month: CalendarDate { visibleMonth ?? day }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header
            weekdayRow
            grid
        }
        .onChange(of: day) { _, newDay in
            // Following the day is what makes the grid feel attached to it; paging
            // away is a deliberate act and survives until the day changes.
            visibleMonth = newDay
        }
        // A container element, so the grid can be found and measured from outside the
        // app without giving every one of its 42 cells an identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mini-calendar")
    }

    private var header: some View {
        HStack {
            Button { page(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).themedText(.caption, color: .textSecondary)
            Spacer()
            Button { page(by: 1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.color(.textTertiary))
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdayInitials, id: \.self) { initial in
                Text(initial)
                    .themedText(.caption, color: .textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        VStack(spacing: 2) {
            ForEach(weeks, id: \.first) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { date in
                        cell(date)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ date: CalendarDate?) -> some View {
        if let date {
            let isChosen = date == day
            let isToday = date == .today
            Text("\(date.day)")
                .themedText(.caption, color: numberColor(date, isChosen: isChosen))
                .frame(maxWidth: .infinity, minHeight: cellHeight)
                .background(isChosen ? theme.color(.accentPrimary) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
                .overlay(alignment: .bottom) {
                    // One dot for a day that already has a daily note, so the month
                    // shows where the record is rather than only where the cursor is;
                    // one for a day something is due on, in the colour a deadline is
                    // drawn in everywhere else.
                    HStack(spacing: 2) {
                        if hasDailyNote(date) {
                            Circle()
                                .fill(theme.color(isChosen ? .onAccent : .accentPrimary))
                                .frame(width: 3, height: 3)
                        }
                        if dueDays.contains(date) {
                            Circle()
                                .fill(theme.color(isChosen ? .onAccent : .taskOverdue))
                                .frame(width: 3, height: 3)
                                .accessibilityIdentifier("due-dot-\(date)")
                        }
                    }
                    .offset(y: -1)
                }
                .overlay {
                    if isToday, !isChosen {
                        RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                            .strokeBorder(theme.color(.accentPrimary), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
                .help(ItalianHolidays.name(of: date, patron: vault.settings.patronSaint) ?? "")
                .onTapGesture { onSelect(date) }
                .contextMenu {
                    Button("Vai a questo giorno") { onSelect(date) }
                    Button(hasDailyNote(date) ? "Apri la daily note" : "Crea la daily note") {
                        onOpenDailyNote(date)
                    }
                }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: cellHeight)
        }
    }

    /// A Saturday, a Sunday and a holiday in their three shades of red, and a day of
    /// another month grey before anything else - a date picker's first job is to say
    /// which month you are in. The chosen day sits on the accent and takes the colour
    /// that reads on it.
    private func numberColor(_ date: CalendarDate, isChosen: Bool) -> ColorToken {
        if isChosen { return .onAccent }
        guard date.month == month.month else { return .textTertiary }
        return ItalianHolidays.kind(of: date, patron: vault.settings.patronSaint).token ?? .textPrimary
    }

    /// Whether the vault already holds the note for a day.
    private func hasDailyNote(_ date: CalendarDate) -> Bool {
        let fileName = NoteName.dailyFileName(for: date)
        let path = vault.settings.dailyFolder.isEmpty
            ? fileName
            : "\(vault.settings.dailyFolder)/\(fileName)"
        return vault.index.allNotes.contains { $0.relativePath == path }
    }

    private func page(by months: Int) {
        visibleMonth = MonthGrid.month(month, offsetBy: months)
    }

    private var monthTitle: String {
        guard let date = EventKitStore.date(month, hour: 12, minute: 0) else { return "" }
        return date
            .formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "it_IT")))
            .capitalized
    }

    /// Monday first, as the Italian week is read.
    private static let weekdayInitials = ["L", "M", "M", "G", "V", "S", "D"]

    private var weeks: [[CalendarDate?]] { MonthGrid.weeks(of: month) }
}

/// The month grid's arithmetic, apart from the view so it can be checked directly:
/// a calendar that is wrong on one month in twelve is not something to notice by
/// looking at it.
enum MonthGrid {
    /// The month laid out in weeks, Monday first, padded with nil where the grid runs
    /// past the month at either end.
    static func weeks(of month: CalendarDate) -> [[CalendarDate?]] {
        guard let first = CalendarDate(year: month.year, month: month.month, day: 1) else { return [] }
        let leading = (weekdayIndex(of: first) + 5) % 7   // Monday = 0

        var cells: [CalendarDate?] = Array(repeating: nil, count: leading)
        var cursor = first
        while cursor.month == month.month {
            cells.append(cursor)
            cursor = cursor.adding(days: 1)
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// The same day some months away, clamped to the last day of the target month.
    ///
    /// Paging from the 31st into a 30-day month must not produce a date that does not
    /// exist, and must not skip the month either.
    static func month(_ date: CalendarDate, offsetBy months: Int) -> CalendarDate {
        var year = date.year
        var month = date.month + months
        while month > 12 {
            month -= 12
            year += 1
        }
        while month < 1 {
            month += 12
            year -= 1
        }

        var day = date.day
        while day > 28 {
            if let clamped = CalendarDate(year: year, month: month, day: day) { return clamped }
            day -= 1
        }
        return CalendarDate(year: year, month: month, day: day) ?? date
    }

    /// 1 for Sunday, as `Calendar` numbers weekdays.
    private static func weekdayIndex(of date: CalendarDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let converted = DateComponents(
            calendar: calendar, year: date.year, month: date.month, day: date.day
        ).date else { return 1 }
        return calendar.component(.weekday, from: converted)
    }
}
