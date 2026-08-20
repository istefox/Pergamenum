import SwiftUI

// The rows the week and the month are drawn out of, apart from the two grids for the
// reason the mockup gave when it drew them: the grids say what a scale is, the rows say
// what one thing in it looks like.

/// One line in a day of the week.
///
/// The hour is a prefix rather than a position: a list ordered by time says the same
/// thing a grid does about *when*, and says it in a column ninety points wide.
struct WeekEntryRow: View {
    @Environment(\.theme) private var theme

    let entry: WeekEntry
    /// What a click does, when the row has somewhere to go. An EventKit row has no file
    /// behind it, so it has none.
    var onOpen: (() -> Void)?

    @ViewBuilder
    var body: some View {
        // Draggable only when the row is a task line with a `>` marker to rewrite
        // (§D5, and `dragPayload` carries the argument for the two it refuses).
        if let payload = entry.dragPayload {
            row.draggable(payload.text)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: entry.kind.symbol)
                .font(.system(size: 7))
                .foregroundStyle(theme.color(entry.kind.token))
            VStack(alignment: .leading, spacing: 0) {
                if let timeText = entry.timeText {
                    Text(timeText).themedText(.caption, color: .textTertiary)
                }
                Text(entry.title).themedText(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        // The whole row, not the glyph: a `.clear` background is not a hit target, which
        // this app has already paid for once (PG-009, the format bar's buttons).
        .contentShape(Rectangle())
        .help(entry.title)
        .onTapGesture { onOpen?() }
    }
}

/// A month cell has room for a word, so it gets one: the colour carries the kind and
/// the text carries which one it is. A cell that tried to show the hour as well would
/// show neither.
struct MonthEntryRow: View {
    @Environment(\.theme) private var theme

    let entry: WeekEntry
    var onOpen: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let payload = entry.dragPayload {
            row.draggable(payload.text)
        } else {
            row
        }
    }

    private var row: some View {
        Text(entry.title)
            .themedText(.caption, color: entry.kind.token)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help(entry.title)
            .onTapGesture { onOpen?() }
    }
}

/// What a column could not show. Never a silent truncation: a week that quietly showed
/// four of eleven would be a week that lies about how full it is.
struct HiddenEntriesRow: View {
    @Environment(\.theme) private var theme

    let count: Int

    var body: some View {
        Text("altri \(count)")
            .themedText(.caption, color: .textTertiary)
            .padding(.top, 1)
    }
}
