import AppKit
import SwiftUI

/// The month at the top of the day view, at whatever size the user has left it.
///
/// It used to fill the column, which on a wide window stretched the cells into
/// rectangles a month tall. Now it has a width the user drags and a chevron that puts
/// it away, and both choices are remembered.
///
/// Its own type because `TodayView` is at SwiftLint's limit for a view body, and
/// because a section that owns two preferences is a thing rather than a fragment.
struct DayMonthSection: View {
    @Environment(\.theme) private var theme

    let day: CalendarDate
    let onSelect: (CalendarDate) -> Void
    let onOpenDailyNote: (CalendarDate) -> Void

    @AppStorage("todayShowsMonth") private var isShowing = true
    @AppStorage("todayMonthWidth") private var width = 300.0

    private static let narrowest = 220.0
    private static let widest = 520.0

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.xs)) {
            header
            if isShowing {
                HStack(alignment: .top, spacing: 0) {
                    MiniCalendar(day: day, onSelect: onSelect, onOpenDailyNote: onOpenDailyNote)
                        .frame(width: width)
                    handle
                    Spacer(minLength: 0)
                }
            }
        }
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

    /// The grip that sets the width. Dragging is the only way to say "this much": a
    /// menu of three sizes is a guess about which three.
    private var handle: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(theme.color(.borderSubtle))
            .frame(width: 4, height: 44)
            .padding(.horizontal, theme.spacing(.xs))
            .contentShape(Rectangle())
            .accessibilityIdentifier("month-resize")
            .accessibilityLabel("Larghezza del mese")
            .help("Trascina per cambiare la larghezza del mese")
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        width = min(Self.widest, max(Self.narrowest, width + drag.translation.width))
                    }
            )
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }
}
