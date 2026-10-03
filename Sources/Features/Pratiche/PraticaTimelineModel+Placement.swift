import Foundation

// ADR-0076 §D3 (PG-338): the parts of the timeline's pure model that read an entry's
// placement rather than its own date - the order itself, the lane an anchored entry aligns
// to, the day sections, «Inserisci qui»'s midpoint and the orphan caption. ADR-0079 §D1/§D3
// (PG-369) adds the exclusion set to the order and the one place excluded rows are hidden. A sibling of
// `PraticaTimelineModel.swift` (`Type+Aspect.swift`, ADR-0045) so neither file outgrows
// SwiftLint's size limits.

/// One day of the timeline: its start, and its rows in the timeline's own order.
struct PraticaTimelineDay: Equatable {
    var day: Date
    var entries: [PraticaTimelineEntry]
}

extension PraticaTimelineModel {
    /// Interleaves messages and manual entries by `date`, ascending (R-23): the
    /// oldest entry first, so a view scrolls to the *end* of this array to land on
    /// the newest, matching SPEC "Timeline model"'s "the view scrolls to the bottom
    /// (newest) on open".
    ///
    /// ADR-0076 §D3: the order is `PraticaTimelineOrder.arrange`'s, the one rule the
    /// connectors share. An anchored entry follows its message (R-04); at an equal instant
    /// a message sorts before an entry (R-08, the old id tie-break put the entry first,
    /// ADR-0076 F2); two messages at one instant sort by id, so an Exchange conversation
    /// sent to several mailboxes at once keeps one stable order across reloads.
    ///
    /// ADR-0079 §D1 (PG-369): `excluded` is the pratica's `pergamenum-dossier-excluded`, read
    /// from the same bytes as the entries; an empty set is the rule as it was before.
    static func ordered(
        _ entries: [PraticaTimelineEntry], excluded: Set<String> = []
    ) -> [PraticaTimelineEntry] {
        let items = entries.map { entry in
            PraticaTimelineOrder.Item(
                kind: entry.kind == .message
                    ? .message(messageID: entry.messageID ?? "", tieKey: entry.id)
                    : .entry(anchor: entry.anchor, ordinal: entry.fileOrdinal),
                date: entry.date
            )
        }
        var hostDirections: [String: MessageDocument.Direction] = [:]
        return PraticaTimelineOrder.arrange(items, excluded: excluded).map { placed in
            var entry = entries[placed.index]
            entry.placement = placed.placement
            entry.placementDate = placed.placementDate
            switch placed.placement {
            case .message:
                // The first message carrying an id owns it (ADR-0076 §D2), and it is also
                // the first one met in this order.
                if let messageID = entry.messageID, hostDirections[messageID] == nil {
                    hostDirections[messageID] = entry.direction
                }
            case let .anchored(messageID):
                entry.hostDirection = hostDirections[messageID]
            case .free, .orphaned, .excluded:
                break
            }
            return entry
        }
    }

    /// ADR-0079 §D3 (PG-369): the timeline the app stores, without the rows the shared rule
    /// placed `.excluded`. Applied once, where `reloadTimeline` stores `timeline`, so every
    /// consumer (filters, day sections, «Inserisci qui», the counts, Backspace) starts from
    /// rows that cannot include one.
    static func hidingExcluded(_ entries: [PraticaTimelineEntry]) -> [PraticaTimelineEntry] {
        entries.filter {
            if case .excluded = $0.placement { return false }
            return true
        }
    }

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
    /// sorting it again: the order is `ordered(_:excluded:)`'s, exclusion set included, and must
    /// not be re-derived.
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

    /// ADR-0079 §D7 (R-11): the SF Symbols a manual entry's heading draws - its kind's alone,
    /// anchored or not. The rail carries the link now, so `arrow.turn.down.right` is gone; the
    /// accessibility text still says «collegata al messaggio».
    static func entryHeadingSymbols(for entry: PraticaTimelineEntry) -> [String] {
        [entry.kind == .call ? "phone" : "square.and.pencil"]
    }

    /// ADR-0079 §D7 (R-12): whether an entry's heading shows its day beside its time - true
    /// exactly for an anchored entry whose own instant and its message's (`placedAt`) fall on
    /// different days of `calendar`, the calendar that draws the day headers. A free or orphaned
    /// entry already sits under its own day's header.
    static func headingShowsDay(_ entry: PraticaTimelineEntry, calendar: Calendar) -> Bool {
        guard case .anchored = entry.placement else { return false }
        return !calendar.isDate(entry.date, inSameDayAs: entry.placedAt)
    }
}
