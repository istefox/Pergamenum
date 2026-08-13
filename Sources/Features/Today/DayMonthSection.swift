import SwiftUI

/// The month at the top of the day view, sized by the column it sits in.
///
/// It used to fill the column, which on a wide window stretched the cells into
/// rectangles a month tall; then it had a grip of its own, which was one handle too
/// many in a view that already has a divider. Now it follows the split between the
/// note column and the timeline: drag that, and the month grows or shrinks with the
/// column. The chevron still puts it away, and that choice is remembered.
struct DayMonthSection: View {
    @Environment(\.theme) private var theme

    let day: CalendarDate
    let onSelect: (CalendarDate) -> Void
    let onOpenDailyNote: (CalendarDate) -> Void

    /// The width of the column the section sits in, measured by the day view: the
    /// content around it is capped for readability, so measuring here would see a
    /// constant and the month would stop following the divider on a wide window.
    let columnWidth: CGFloat

    @AppStorage("todayShowsMonth") private var isShowing = true

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header
            if isShowing {
                MiniCalendar(
                    day: day,
                    onSelect: onSelect,
                    onOpenDailyNote: onOpenDailyNote,
                    cellHeight: Self.cellHeight(forWidth: Self.calendarWidth(inColumnOf: columnWidth))
                )
                .frame(width: Self.calendarWidth(inColumnOf: columnWidth))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Button { isShowing.toggle() } label: {
                Image(systemName: isShowing ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(theme.color(.textTertiary))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("month-disclosure")
            .help(isShowing ? "Nascondi il mese" : "Mostra il mese")

            Text("MESE").themedText(.caption, color: .textTertiary)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { isShowing.toggle() }
    }

    // MARK: Sizing
    //
    // Static and pure, so what the month does at every column width can be checked
    // without a window: the whole point is that it tracks the divider, and "it looked
    // right on my screen" is not that.

    /// Half the column, within bounds.
    ///
    /// Not the whole column: a seven-column grid given 900 points draws cells 128 wide
    /// and 22 tall, which is the stretched look this replaces. Not a fixed width
    /// either, or dragging the divider would leave it alone. Half keeps it tracking
    /// across the widths the window actually takes.
    static func calendarWidth(inColumnOf available: CGFloat) -> CGFloat {
        guard available > 0 else { return narrowest }
        return min(widest, max(narrowest, available * 0.5))
    }

    /// Cell height from cell width, so the grid keeps its proportions as it grows.
    static func cellHeight(forWidth width: CGFloat) -> CGFloat {
        min(34, max(22, (width / 7) * 0.62))
    }

    static let narrowest: CGFloat = 210
    static let widest: CGFloat = 460
}
