import SwiftUI

// The rows the week and the month are drawn out of, apart for the reason
// `TagBrowserMockupPieces` gives: the scenes say what is being asked, the pieces say what it
// looks like.

/// What a day can hold (ADR-0013 §D4). Four kinds and no fifth, each recognisable without a
/// legend: the colour is the one the rest of the app already uses for that thing.
enum WeekEntryKind {
    case event
    case block
    case task
    case deadline

    var symbol: String {
        switch self {
        case .event: "calendar"
        case .block: "rectangle.fill"
        case .task: "square"
        case .deadline: "exclamationmark.circle"
        }
    }

    var token: ColorToken {
        switch self {
        case .event: .accentPrimary
        case .block: .taskScheduled
        case .task: .taskOpen
        case .deadline: .taskOverdue
        }
    }
}

/// One line in a day of the week. The hour is a prefix rather than a position: a list ordered by
/// time says the same thing a grid does about *when*, and says it in a ninety-point column.
struct WeekEntryMockup: View {
    @Environment(\.theme) private var theme

    let kind: WeekEntryKind
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: kind.symbol)
                .font(.system(size: 7))
                .foregroundStyle(theme.color(kind.token))
            VStack(alignment: .leading, spacing: 0) {
                if let detail {
                    Text(detail).themedText(.caption, color: .textTertiary)
                }
                Text(title).themedText(.caption).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

/// A month cell has room for a word, so it gets one: the colour carries the kind and the text
/// carries which one it is. A cell that tried to show the hour as well would show neither.
struct MonthEntryMockup: View {
    @Environment(\.theme) private var theme

    let text: String
    let kind: WeekEntryKind

    var body: some View {
        Text(text)
            .themedText(.caption, color: kind.token)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
