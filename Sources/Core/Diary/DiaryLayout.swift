import Foundation

/// Where each entry is drawn when two of them share an hour.
///
/// A day that is written down as it was lived has overlaps in it - a call during a
/// meeting, a note taken while something else was still running - so the timeline
/// places them side by side instead of refusing the second one. That is the difference
/// between this and the Oggi pane's time blocks, which are a plan and may not overlap.
enum DiaryLayout {
    /// One entry and the column it was given, out of how many the timeline needs there.
    struct Placement: Equatable, Identifiable {
        var entry: DiaryEntry
        /// Zero-based, left to right.
        var column: Int
        /// How many columns the cluster this entry belongs to is wide.
        var columns: Int

        var id: UUID { entry.id }
    }

    /// Places every entry of a day.
    ///
    /// Entries are grouped into clusters of things that touch, directly or through a
    /// chain, and each cluster is laid out on its own: two meetings in the morning do
    /// not make the afternoon half as wide.
    static func place(_ entries: [DiaryEntry]) -> [Placement] {
        let ordered = entries.sorted {
            $0.startMinutes == $1.startMinutes
                ? $0.durationMinutes > $1.durationMinutes
                : $0.startMinutes < $1.startMinutes
        }

        var result: [Placement] = []
        var cluster: [DiaryEntry] = []
        var clusterEnd = Int.min

        func flush() {
            result.append(contentsOf: layout(cluster))
            cluster = []
            clusterEnd = Int.min
        }

        for entry in ordered {
            // Against the whole cluster's reach, not against the last entry: A 9-11,
            // B 9:30-10 and C 10:30-11 all belong together, and comparing C with B
            // alone would put C back in A's column.
            if !cluster.isEmpty, entry.startMinutes >= clusterEnd { flush() }
            cluster.append(entry)
            clusterEnd = max(clusterEnd, entry.endMinutes)
        }
        flush()

        return result
    }

    /// Greedy left-most free column, which is what a calendar does and what reads
    /// correctly: an entry keeps the leftmost lane nothing else is occupying.
    private static func layout(_ cluster: [DiaryEntry]) -> [Placement] {
        guard !cluster.isEmpty else { return [] }

        /// The end minute of the entry currently occupying each column.
        var columnEnds: [Int] = []
        var assigned: [(entry: DiaryEntry, column: Int)] = []

        for entry in cluster {
            if let free = columnEnds.firstIndex(where: { $0 <= entry.startMinutes }) {
                columnEnds[free] = entry.endMinutes
                assigned.append((entry, free))
            } else {
                columnEnds.append(entry.endMinutes)
                assigned.append((entry, columnEnds.count - 1))
            }
        }

        let width = columnEnds.count
        return assigned.map { Placement(entry: $0.entry, column: $0.column, columns: width) }
    }
}
