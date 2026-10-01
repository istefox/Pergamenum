import Foundation

/// Where a timed entry sits across the day grid's width when others overlap it (PG-339).
///
/// Every event used to be drawn the full width of the column, so two that overlapped
/// were stacked one on the other and the one drawn first disappeared under the second: a
/// shift from 07:00 to 13:00 hid the whole morning of a multi-day event on its last day.
/// Overlapping entries now share the width the way a calendar lays out a day: side by
/// side, each group of mutually overlapping entries split into as many columns as it
/// needs at its busiest, and an entry that overlaps nothing keeps the full width.
struct TimelineLane: Equatable, Sendable {
    /// The column the entry is drawn in, from the left.
    var index: Int
    /// How many columns its group of overlapping entries uses.
    var count: Int

    static let full = TimelineLane(index: 0, count: 1)

    /// One lane per span, in the order the spans were given.
    ///
    /// A span is `[start, end)` in minutes: one ending at 10:00 and one starting at 10:00
    /// touch but do not overlap, and both keep the full width. Spans are placed longest
    /// first among those starting together, each in the leftmost column free by its
    /// start, and a group closes once a span starts at or after everything in it has ended.
    ///
    /// `nonisolated` and pure, so the layout is held by a unit test rather than by eye.
    nonisolated static func assign(_ spans: [(start: Int, end: Int)]) -> [TimelineLane] {
        var lanes = Array(repeating: TimelineLane.full, count: spans.count)
        let order = spans.indices.sorted { lhs, rhs in
            spans[lhs].start != spans[rhs].start
                ? spans[lhs].start < spans[rhs].start
                : spans[lhs].end > spans[rhs].end
        }

        var group: [Int] = []
        var columnEnds: [Int] = []
        var groupEnd = Int.min

        for position in order {
            let span = spans[position]
            if !group.isEmpty, span.start >= groupEnd {
                for member in group { lanes[member].count = columnEnds.count }
                group = []
                columnEnds = []
                groupEnd = Int.min
            }
            if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
                columnEnds[free] = span.end
                lanes[position].index = free
            } else {
                lanes[position].index = columnEnds.count
                columnEnds.append(span.end)
            }
            group.append(position)
            groupEnd = max(groupEnd, span.end)
        }
        for member in group { lanes[member].count = columnEnds.count }
        return lanes
    }
}
