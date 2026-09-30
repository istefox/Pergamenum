import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D2 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 3 -
// R-04, R-05, R-08. The one ordering and placement rule the app and both connectors share.

@Suite struct PraticaTimelineOrderTests {
    private static let start = Date(timeIntervalSince1970: 1_780_000_000)

    private static func at(_ minute: Int) -> Date {
        start.addingTimeInterval(TimeInterval(60 * minute))
    }

    private typealias Item = PraticaTimelineOrder.Item

    private static func message(_ messageID: String, _ minute: Int, tieKey: String? = nil) -> Item {
        Item(kind: .message(messageID: messageID, tieKey: tieKey ?? messageID), date: at(minute))
    }

    private static func entry(_ ordinal: Int, _ minute: Int, anchor: String? = nil) -> Item {
        Item(kind: .entry(anchor: anchor, ordinal: ordinal), date: at(minute))
    }

    /// The arranged rows as input indices, in output order.
    private static func order(_ items: [Item]) -> [Int] {
        PraticaTimelineOrder.arrange(items).map(\.index)
    }

    private static func placement(of index: Int, in items: [Item]) -> PraticaTimelineOrder.Placed? {
        PraticaTimelineOrder.arrange(items).first { $0.index == index }
    }

    // MARK: - R-04: an anchored entry follows its message

    @Test func twoEntriesOnOneMessageFollowItByHeadingDateThenOrdinal() {
        let items = [
            Self.message("<a>", 0),      // 0
            Self.message("<b>", 10),     // 1
            Self.entry(0, 5, anchor: "<a>"),  // 2
            Self.entry(1, 3, anchor: "<a>"),  // 3
            Self.entry(2, 3, anchor: "<a>"),  // 4
        ]
        #expect(Self.order(items) == [0, 3, 4, 2, 1], "by heading date, then by ordinal on a tie")
    }

    @Test func aFreeEntryDatedInsideAGroupSitsAfterTheGroupNeverInsideIt() {
        let items = [
            Self.message("<a>", 0),      // 0
            Self.entry(0, 2, anchor: "<a>"),  // 1
            Self.entry(1, 6, anchor: "<a>"),  // 2
            Self.entry(2, 4),                 // 3, free, dated between the two anchored entries
            Self.message("<b>", 10),     // 4
        ]
        #expect(Self.order(items) == [0, 1, 2, 3, 4])
    }

    @Test func theLastMessagesEntriesCloseTheList() {
        let items = [
            Self.message("<a>", 0),      // 0
            Self.message("<b>", 10),     // 1
            Self.entry(0, 12, anchor: "<b>"), // 2
            Self.entry(1, 1, anchor: "<b>"),  // 3, dated before its own message
            Self.entry(2, 5),                 // 4, free
        ]
        #expect(Self.order(items) == [0, 4, 1, 3, 2])
    }

    // MARK: - R-05: an anchor naming no message

    @Test func anAnchorNamingNoMessageIsOrphanedAtItsHeadingDate() throws {
        let items = [
            Self.message("<a>", 0),           // 0
            Self.entry(0, 5, anchor: "<gone>"),    // 1
            Self.message("<b>", 10),          // 2
        ]
        #expect(Self.order(items) == [0, 1, 2])
        let placed = try #require(Self.placement(of: 1, in: items))
        #expect(placed.placement == .orphaned(messageID: "<gone>"))
        #expect(placed.placementDate == Self.at(5))
    }

    @Test func theSameEntryIsAnchoredAsSoonAsItsMessageIsPresent() throws {
        let items = [
            Self.message("<a>", 0),           // 0
            Self.entry(0, 5, anchor: "<gone>"),    // 1
            Self.message("<b>", 10),          // 2
            Self.message("<gone>", 20),       // 3
        ]
        #expect(Self.order(items) == [0, 2, 3, 1])
        let placed = try #require(Self.placement(of: 1, in: items))
        #expect(placed.placement == .anchored(messageID: "<gone>"))
    }

    // MARK: - R-08: an equal instant

    @Test func atOneInstantTheMessageThenTheEntriesByOrdinal() {
        let items = [
            Self.entry(2, 5, anchor: "<gone>"),  // 0, orphaned
            Self.entry(1, 5),                    // 1, free
            Self.message("<a>", 5),              // 2
        ]
        #expect(Self.order(items) == [2, 1, 0], "message, then free entry, then orphaned entry by ordinal")
        #expect(Self.placement(of: 0, in: items)?.placement == .orphaned(messageID: "<gone>"))
        #expect(Self.placement(of: 1, in: items)?.placement == .free)
    }

    @Test func twoMessagesAtOneInstantSortByTieKey() {
        let items = [
            Self.message("<b>", 5, tieKey: "P/email/20260610_b.md"),
            Self.message("<a>", 5, tieKey: "P/email/20260610_a.md"),
        ]
        #expect(Self.order(items) == [1, 0])
    }

    @Test func entriesAtOneInstantSortByOrdinalPastNine() {
        // ADR-0076 F3: as strings, `-10` sorts before `-2`. Ordinals are integers.
        let ordinals = [10, 2, 7, 0, 9, 1, 3, 8, 4, 6, 5]
        let items = ordinals.map { Self.entry($0, 5) }
        let arranged = Self.order(items).map { ordinals[$0] }
        #expect(arranged == Array(0...10))
    }

    // MARK: - Ownership and placement date

    @Test func aMessageIDCarriedTwiceIsOwnedByTheFirstMessage() throws {
        let items = [
            Self.message("<a>", 8, tieKey: "second"),  // 0
            Self.message("<a>", 2, tieKey: "first"),   // 1
            Self.entry(0, 20, anchor: "<a>"),          // 2
        ]
        #expect(Self.order(items) == [1, 2, 0])
        let placed = try #require(Self.placement(of: 2, in: items))
        #expect(placed.placement == .anchored(messageID: "<a>"))
        #expect(placed.placementDate == Self.at(2), "an anchored entry is placed at its message's date")
        #expect(Self.placement(of: 0, in: items)?.placement == .message)
    }

    @Test func anEmptyMessageIDOwnsNothing() {
        let items = [
            Self.message("", 0),
            Self.entry(0, 5, anchor: ""),
        ]
        #expect(Self.placement(of: 1, in: items)?.placement == .orphaned(messageID: ""))
    }

    @Test func everyItemIsPlacedExactlyOnce() {
        let items = [
            Self.message("<a>", 0), Self.entry(0, 1, anchor: "<a>"), Self.entry(1, 2),
            Self.entry(2, 3, anchor: "<x>"), Self.message("<a>", 4), Self.entry(3, 5, anchor: "<a>"),
        ]
        #expect(Self.order(items).sorted() == Array(items.indices))
    }
}
