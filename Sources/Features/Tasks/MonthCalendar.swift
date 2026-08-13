import SwiftUI

/// A month, drawn the way the task panels show it: `agosto` with a back, a today and a
/// forward control, the Italian weekday initials starting on Monday, and the days of
/// the neighbouring months dimmed rather than hidden.
///
/// Its own view rather than SwiftUI's graphical `DatePicker`, which draws its month
/// name and weekday row from the system region: on this machine that gives `Aug 2026`
/// and `Mo Tu We` inside an interface that is Italian everywhere else.
struct MonthCalendar: View {
    @Environment(\.theme) private var theme

    @Binding var selection: CalendarDate?
    /// The day drawn with the marker, normally today.
    var today: CalendarDate = .today
    var onPick: (CalendarDate) -> Void = { _ in }

    @State private var page = CalendarDate.today

    private static let weekdays = ["lu", "ma", "me", "gi", "ve", "sa", "do"]
    private static let columns = Array(repeating: GridItem(.flexible(minimum: 34), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.s)) {
            header
            weekdayRow
            grid
        }
        .onAppear { page = selection ?? today }
        // A date typed into the field above moves the page to it, or the calendar shows
        // a month with nothing selected in it.
        .onChange(of: selection) { _, now in
            if let now { page = now }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(DateEntry.monthName(month: page.month, year: page.year))
                .themedText(.heading)
            Spacer()
            control("chevron.left", identifier: "month-back") { page = DateEntry.adding(months: -1, to: page) }
            control("smallcircle.filled.circle", identifier: "month-today") { page = today }
            control("chevron.right", identifier: "month-forward") { page = DateEntry.adding(months: 1, to: page) }
        }
    }

    private func control(_ symbol: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(theme.color(.textSecondary))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: Self.columns, spacing: 4) {
            ForEach(Self.weekdays, id: \.self) { day in
                Text(day).themedText(.caption, color: .textTertiary)
            }
        }
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(columns: Self.columns, spacing: 4) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: CalendarDate) -> some View {
        let isSelected = day == selection
        let isToday = day == today
        let isThisMonth = day.month == page.month && day.year == page.year
        return Button {
            selection = day
            onPick(day)
        } label: {
            Text("\(day.day)")
                .themedText(.body, color: isSelected ? .textInverted : (isThisMonth ? .textPrimary : .textTertiary))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(background(isSelected: isSelected, isToday: isToday))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("day-\(day)")
    }

    @ViewBuilder
    private func background(isSelected: Bool, isToday: Bool) -> some View {
        if isSelected {
            Circle().fill(theme.color(.accentPrimary))
        } else if isToday {
            Circle().fill(theme.color(.accentMuted))
        } else {
            Color.clear
        }
    }

    /// Six weeks from the Monday on or before the first of the month, so the grid does
    /// not change height as the user pages through the year.
    private var days: [CalendarDate] {
        guard let first = CalendarDate(year: page.year, month: page.month, day: 1) else { return [] }
        // `weekday` is 1 for Sunday, so Monday-first means shifting by two.
        let offset = (DateEntry.weekday(of: first) + 5) % 7
        let start = first.adding(days: -offset)
        return (0..<42).map { start.adding(days: $0) }
    }
}
