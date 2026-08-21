import SwiftUI

/// One thing drawn on the day's timeline: an event from the calendar or a block from the
/// daily note (SPEC §8.3).
struct TimelineEntry: Equatable {
    var title: String
    var subtitle: String
    /// Minutes from midnight, as everything on this grid is.
    var start: Int
    var duration: Int
    var token: ColorToken
    /// Events come from EventKit and blocks from the note; only one of them is something
    /// this app owns, and the box says which at a glance.
    var isEvent: Bool
}

/// The box itself, placed on the grid by the minute it starts at.
///
/// Its own view rather than a method on `DayTimeline`, and the reason is a defect: the
/// hover and the drag of a single block used to live on the timeline, so moving one box
/// redrew the whole grid - seventeen hour rows and every other box - on every frame of
/// the gesture. What that looked like was the block arriving before its colour did.
struct TimelineEntryBox<Accessory: View, Footer: View>: View {
    @Environment(\.theme) private var theme

    let entry: TimelineEntry
    let firstHour: Int
    let hourHeight: CGFloat
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let footer: () -> Footer

    init(
        entry: TimelineEntry,
        firstHour: Int,
        hourHeight: CGFloat,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() },
        @ViewBuilder footer: @escaping () -> Footer = { EmptyView() }
    ) {
        self.entry = entry
        self.firstHour = firstHour
        self.hourHeight = hourHeight
        self.accessory = accessory
        self.footer = footer
    }

    private var offset: CGFloat { CGFloat(entry.start - firstHour * 60) / 60 * hourHeight }
    private var height: CGFloat { max(18, CGFloat(entry.duration) / 60 * hourHeight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(entry.title).themedText(.caption).lineLimit(1)
            if height > 30 {
                Text(entry.subtitle).themedText(.caption, color: .textTertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, theme.spacing(.xs))
        .padding(.vertical, 2)
        // As wide as the column leaves it, never a fixed 236: the timeline can be
        // squeezed to 220 points by the split, and a box wider than its column is drawn
        // half outside the scroll view, which clips it in and out while the window is
        // being dragged.
        .frame(height: height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        // One shape draws the fill and the corner, rather than a colour behind the frame
        // and a clip over it: two layers resized on every frame of a drag arrive one
        // frame apart.
        .background(
            RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous)
                .fill(theme.color(entry.token))
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.radius(.control), style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.color(entry.isEvent ? .accentPrimary : .taskScheduled))
                .frame(width: 2)
        }
        // Both accessories are applied **before** the offset, and that order is the whole
        // of it: `offset` moves what is drawn and not the frame it is laid out in, so an
        // overlay attached outside it lands where the box would have been - at the top of
        // the grid, an hour of nothing away from the block it belongs to.
        .overlay(alignment: .topTrailing) { accessory() }
        .overlay(alignment: .bottom) { footer() }
        .padding(.leading, 52)
        .padding(.trailing, theme.spacing(.s))
        // No `geometryGroup()` here, and it is worth the line: it was tried, and grouping
        // a subtree that changes size on every frame of a drag inside a `ScrollView` left
        // a composited copy of the old box behind, fading out under the new one. What it
        // was added to fix - the box arriving before its colour - was the whole grid being
        // redrawn by a hover, and that is fixed where it belonged, in `TimelineBlockBox`.
        .offset(y: offset)
    }
}
