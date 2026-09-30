import Foundation

// ADR-0076 §D3 (PG-338): the parts of the timeline's pure model that read an entry's
// placement rather than its own date - the lane an anchored entry aligns to, the day
// sections, «Inserisci qui»'s midpoint and the orphan caption. A sibling of
// `PraticaTimelineModel.swift` (`Type+Aspect.swift`, ADR-0045) so neither file outgrows
// SwiftLint's size limits.

/// One day of the timeline: its start, and its rows in the timeline's own order.
struct PraticaTimelineDay: Equatable {
    var day: Date
    var entries: [PraticaTimelineEntry]
}

extension PraticaTimelineModel {
    /// The lane a row aligns to (R-09): an anchored entry takes its message's `.received` or
    /// `.sent`; every other row answers `lane(for:)`. `lane(for:)` itself still answers
    /// `.entry` for an anchored entry, which keeps its colour and glyph.
    static func hostLane(for entry: PraticaTimelineEntry) -> PraticaLane {
        guard case .anchored = entry.placement, let direction = entry.hostDirection else {
            return lane(for: entry)
        }
        return direction == .sent ? .sent : .received
    }

    /// Day sections in the timeline's own ascending order (R-23), keyed on `placedAt`, so a
    /// day header never separates a message from the entries anchored to it. Built by
    /// walking the already-ordered array rather than by grouping into a dictionary and
    /// sorting it again: the order is `ordered(_:)`'s and must not be re-derived.
    static func daySections(
        of entries: [PraticaTimelineEntry], calendar: Calendar
    ) -> [PraticaTimelineDay] {
        var sections: [PraticaTimelineDay] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.placedAt)
            if sections.last?.day == day {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(PraticaTimelineDay(day: day, entries: [entry]))
            }
        }
        return sections
    }

    /// «Inserisci qui»'s timestamp (R-07): the midpoint of the two neighbours' placement
    /// times, an anchored entry counting at its message's time. `PraticaEntry.midpoint` owns
    /// the arithmetic.
    static func insertionDate(
        between first: PraticaTimelineEntry, and second: PraticaTimelineEntry
    ) -> Date {
        PraticaEntry.midpoint(between: first.placedAt, and: second.placedAt)
    }

    /// The caption of an entry whose anchor names no message of this pratica (R-05); nil
    /// for every other row. The wording follows the SPEC's R-05 ("its message is no longer in
    /// this pratica") until gate G1's mockup settles it.
    static func orphanCaption(for entry: PraticaTimelineEntry) -> String? {
        guard case .orphaned = entry.placement else { return nil }
        return orphanCaptionText
    }

    /// Named once so the row and the tests read the same string.
    static let orphanCaptionText = "Il messaggio non è più in questa pratica"
}
