import Foundation

// ADR-0076 §D2 (PG-338): the one rule that decides where every row of a pratica's timeline
// goes, for the app and for both connectors (R-04, R-05, R-08, R-21). Before it, the app and
// the connector each sorted on their own and broke an equal instant in opposite directions
// (ADR-0076 F2), and both lost file order past nine same-minute entries (F3).
//
// Foundation-only on purpose: it compiles into `perg` and `pergamenum-mcp` through the
// `Sources/Core/**` glob. Placement is recomputed on every read and nothing is cached, so a
// message leaving or returning re-anchors its entries with no write (R-05, R-13).

enum PraticaTimelineOrder {
    /// Where a row sits. The spine holds messages, free entries and orphaned entries; an
    /// anchored entry sits directly under the message that carries its anchor.
    enum Placement: Equatable, Sendable {
        case message
        case free
        case anchored(messageID: String)
        /// The anchor names no message of this pratica: placed on the spine by its own date.
        case orphaned(messageID: String)
    }

    /// One input row.
    struct Item: Sendable {
        enum Kind: Equatable, Sendable {
            /// `tieKey` orders two messages at one instant: the file name, or anything that
            /// sorts like it (the app passes its row id, `<pratica>/email/<file>`). An empty
            /// `messageID` owns no entry.
            case message(messageID: String, tieKey: String)
            /// `ordinal` is the entry's index in `pratica.md`, in file order.
            case entry(anchor: String?, ordinal: Int)
        }

        var kind: Kind
        /// A message's `PraticaTimelineModel.sortDate`, an entry's heading time.
        var date: Date
    }

    /// One output row: which input it is, where it sits, and the date it is placed at (its
    /// message's date for an anchored entry, its own date otherwise).
    struct Placed: Equatable, Sendable {
        var index: Int
        var placement: Placement
        var placementDate: Date
    }

    /// Every item of `items`, in timeline order.
    ///
    /// - The spine (messages, free and orphaned entries) is sorted by date. At an equal date a
    ///   message sorts before an entry (R-08), two messages by `tieKey`, two entries by
    ///   `ordinal` - an integer, so the tenth same-minute entry follows the ninth (F3).
    /// - A Message-ID carried by two messages is owned by the first in spine order.
    /// - An entry whose anchor a message owns follows that message, after the message's other
    ///   anchored entries, by heading date and then ordinal (R-04). Nothing else sits between a
    ///   message and its anchored entries. An anchor no message owns is orphaned (R-05).
    static func arrange(_ items: [Item]) -> [Placed] {
        let spineOrder = items.indices.sorted { precedes($0, $1, in: items) }

        // Ownership in spine order: messages only enter the spine, so the first message met
        // here with a given id is the first in spine order.
        var owners: [String: Int] = [:]
        for index in spineOrder {
            guard case let .message(messageID, _) = items[index].kind, !messageID.isEmpty,
                  owners[messageID] == nil
            else { continue }
            owners[messageID] = index
        }

        var anchoredByOwner: [Int: [Int]] = [:]
        var spine: [Placed] = []
        for index in spineOrder {
            let item = items[index]
            switch item.kind {
            case .message:
                spine.append(Placed(index: index, placement: .message, placementDate: item.date))
            case let .entry(anchor, _):
                if let anchor, let owner = owners[anchor] {
                    anchoredByOwner[owner, default: []].append(index)
                } else if let anchor {
                    spine.append(Placed(
                        index: index, placement: .orphaned(messageID: anchor), placementDate: item.date
                    ))
                } else {
                    spine.append(Placed(index: index, placement: .free, placementDate: item.date))
                }
            }
        }

        var placed: [Placed] = []
        placed.reserveCapacity(items.count)
        for row in spine {
            placed.append(row)
            guard row.placement == .message,
                  case let .message(messageID, _) = items[row.index].kind,
                  let group = anchoredByOwner[row.index]
            else { continue }
            // `spineOrder` already visited the group in date-then-ordinal order: an entry
            // never wins a tie against another entry except by ordinal.
            placed.append(contentsOf: group.map {
                Placed(index: $0, placement: .anchored(messageID: messageID), placementDate: row.placementDate)
            })
        }
        return placed
    }

    /// The spine's order, applied to every item (anchored entries are only ever compared with
    /// each other through it, which gives R-04's date-then-ordinal order).
    private static func precedes(_ left: Int, _ right: Int, in items: [Item]) -> Bool {
        let first = items[left], second = items[right]
        if first.date != second.date { return first.date < second.date }
        switch (first.kind, second.kind) {
        case let (.message(_, firstKey), .message(_, secondKey)):
            if firstKey != secondKey { return firstKey < secondKey }
        case (.message, .entry):
            return true
        case (.entry, .message):
            return false
        case let (.entry(_, firstOrdinal), .entry(_, secondOrdinal)):
            if firstOrdinal != secondOrdinal { return firstOrdinal < secondOrdinal }
        }
        // Input order last, so equal keys keep one stable order across reloads.
        return left < right
    }
}
