import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D3 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 3 -
// R-04, R-05, R-06, R-07. The app's timeline model reads `PraticaTimelineOrder` and follows
// the message: placement, the host lane, the filters as one unit, day sections, «Inserisci
// qui»'s neighbours and midpoint, the orphan caption.

@Suite struct PraticaAnchoredTimelineTests {
    /// 2026-06-10 10:00:00 UTC.
    private static let start = Date(timeIntervalSince1970: 1_781_085_600)

    private static func at(_ minute: Int) -> Date {
        start.addingTimeInterval(TimeInterval(60 * minute))
    }

    private static func message(
        _ id: String, _ minute: Int, messageID: String, direction: MessageDocument.Direction = .received,
        sender: String = "mario@rossi.it", attachments: Bool = false, subject: String = "Oggetto"
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: .message, date: at(minute), direction: direction, senderDisplayName: sender,
            senderAddress: sender, subject: subject, bodyPreview: "", hasAttachments: attachments,
            messageID: messageID, isInMail: true
        )
    }

    private static func entry(
        _ id: String, _ minute: Int, ordinal: Int, anchor: String? = nil, text: String = "voce"
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: .note, date: at(minute), direction: nil, senderDisplayName: "Mario Rossi",
            subject: "Nota · Mario Rossi", bodyPreview: text, hasAttachments: false,
            messageID: nil, isInMail: true, anchor: anchor, fileOrdinal: ordinal
        )
    }

    private static func row(_ id: String, in entries: [PraticaTimelineEntry]) throws -> PraticaTimelineEntry {
        try #require(entries.first { $0.id == id })
    }

    // MARK: - ordered fills the placement

    @Test func orderedFillsPlacementPlacementDateAndHostDirection() throws {
        let ordered = PraticaTimelineModel.ordered([
            Self.entry("free", 30, ordinal: 1),
            Self.entry("anchored", 60, ordinal: 0, anchor: "<a>"),
            Self.entry("orphan", 45, ordinal: 2, anchor: "<gone>"),
            Self.message("m", 0, messageID: "<a>", direction: .sent),
        ])
        #expect(ordered.map(\.id) == ["m", "anchored", "free", "orphan"])

        let message = try Self.row("m", in: ordered)
        #expect(message.placement == .message)
        #expect(message.placementDate == Self.at(0))

        let anchored = try Self.row("anchored", in: ordered)
        #expect(anchored.placement == .anchored(messageID: "<a>"))
        #expect(anchored.placementDate == Self.at(0))
        #expect(anchored.placedAt == Self.at(0))
        #expect(anchored.date == Self.at(60), "the heading date itself is untouched")
        #expect(anchored.hostDirection == .sent)
        #expect(PraticaTimelineModel.hostLane(for: anchored) == .sent)
        #expect(PraticaTimelineModel.lane(for: anchored) == .entry, "colour and glyph stay the entry's")

        let free = try Self.row("free", in: ordered)
        #expect(free.placement == .free)
        #expect(free.placedAt == Self.at(30))
        #expect(free.hostDirection == nil)
        #expect(PraticaTimelineModel.hostLane(for: free) == .entry)

        let orphan = try Self.row("orphan", in: ordered)
        #expect(orphan.placement == .orphaned(messageID: "<gone>"))
        #expect(PraticaTimelineModel.hostLane(for: orphan) == .entry)
    }

    @Test func aReceivedHostGivesTheReceivedLane() throws {
        let ordered = PraticaTimelineModel.ordered([
            Self.message("m", 0, messageID: "<a>", direction: .received),
            Self.entry("e", 5, ordinal: 0, anchor: "<a>"),
        ])
        #expect(PraticaTimelineModel.hostLane(for: try Self.row("e", in: ordered)) == .received)
    }

    @Test func atAnEqualInstantTheMessageSortsBeforeAFreeEntry() {
        // R-08: the old id tie-break (`#` before `/`) put the entry first (ADR-0076 F2).
        let ordered = PraticaTimelineModel.ordered([
            Self.entry("P#entry-202606101000", 0, ordinal: 0),
            Self.message("P/email/20260610_offerta.md", 0, messageID: "<a>"),
        ])
        #expect(ordered.map(\.id) == ["P/email/20260610_offerta.md", "P#entry-202606101000"])
    }

    // MARK: - R-06: filters treat a message and its anchored entries as one unit

    private static let unitTimeline = PraticaTimelineModel.ordered([
        message("M", 0, messageID: "<m>", sender: "mario@rossi.it", attachments: true, subject: "Offerta"),
        entry("E1", 10, ordinal: 0, anchor: "<m>", text: "sopralluogo"),
        entry("E2", 20, ordinal: 1, anchor: "<m>", text: "altro"),
        entry("F", 30, ordinal: 2, text: "libera"),
        entry("O", 40, ordinal: 3, anchor: "<gone>", text: "orfana"),
        message("N", 50, messageID: "<n>", sender: "luigi@verdi.it", subject: "Conferma"),
    ])

    struct FilterCase: Sendable, CustomTestStringConvertible {
        var label: String
        var filter: PraticaTimelineFilter
        var visible: [String]

        var testDescription: String { label }
    }

    @Test(arguments: [
        FilterCase(label: "no filter", filter: .none, visible: ["M", "E1", "E2", "F", "O", "N"]),
        FilterCase(label: "the message's sender", filter: PraticaTimelineFilter(sender: "mario@rossi.it"),
                   visible: ["M", "E1", "E2", "F", "O"]),
        FilterCase(label: "another sender hides the group", filter: PraticaTimelineFilter(sender: "luigi@verdi.it"),
                   visible: ["F", "O", "N"]),
        FilterCase(label: "attachments only", filter: PraticaTimelineFilter(attachmentsOnly: true),
                   visible: ["M", "E1", "E2", "F", "O"]),
        FilterCase(label: "a matching entry brings its message, and a non-matching sibling still shows",
                   filter: PraticaTimelineFilter(text: "sopralluogo"), visible: ["M", "E1", "E2"]),
        FilterCase(label: "a matching message brings its entries",
                   filter: PraticaTimelineFilter(text: "Offerta"), visible: ["M", "E1", "E2"]),
        FilterCase(label: "an orphaned entry keeps today's rule",
                   filter: PraticaTimelineFilter(text: "orfana"), visible: ["O"]),
        FilterCase(label: "a free entry keeps today's rule",
                   filter: PraticaTimelineFilter(text: "libera"), visible: ["F"]),
        FilterCase(label: "an entry cannot bring a message the sender filter hides",
                   filter: PraticaTimelineFilter(text: "sopralluogo", sender: "luigi@verdi.it"), visible: []),
        FilterCase(label: "text through an entry, attachments through the message",
                   filter: PraticaTimelineFilter(text: "sopralluogo", attachmentsOnly: true),
                   visible: ["M", "E1", "E2"]),
    ])
    func theFiltersTreatAMessageAndItsAnchoredEntriesAsOneUnit(_ filterCase: FilterCase) {
        let visible = PraticaTimelineModel.filtered(Self.unitTimeline, by: filterCase.filter).map(\.id)
        #expect(visible == filterCase.visible)
    }

    // MARK: - Day sections by placement

    @Test func daySectionsKeepAGroupUnderAMessageDatedTheDayBefore() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // The message at 23:30 on the 10th, its entries written the next morning.
        let ordered = PraticaTimelineModel.ordered([
            Self.message("M", 13 * 60 + 30, messageID: "<m>"),
            Self.entry("E1", 23 * 60, ordinal: 0, anchor: "<m>"),
            Self.entry("E2", 23 * 60 + 30, ordinal: 1, anchor: "<m>"),
            Self.entry("F", 24 * 60, ordinal: 2),
        ])
        let sections = PraticaTimelineModel.daySections(of: ordered, calendar: calendar)
        #expect(sections.map { $0.entries.map(\.id) } == [["M", "E1", "E2"], ["F"]])
        #expect(sections.first?.day == calendar.startOfDay(for: Self.at(0)))
    }

    // MARK: - R-07: «Inserisci qui» counts an anchored entry at its message's time

    @Test func insertionDateNextToAnAnchoredEntryUsesItsMessagesTime() throws {
        let ordered = PraticaTimelineModel.ordered([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E", 300, ordinal: 0, anchor: "<m>"),
            Self.message("N", 120, messageID: "<n>"),
        ])
        #expect(ordered.map(\.id) == ["M", "E", "N"])
        let anchored = try Self.row("E", in: ordered)
        let next = try Self.row("N", in: ordered)
        #expect(PraticaTimelineModel.insertionDate(between: anchored, and: next) == Self.at(60))
    }

    @Test func insertionDateBetweenTwoFreeRowsIsTodaysMidpoint() {
        let first = Self.entry("A", 0, ordinal: 0)
        let second = Self.entry("B", 10, ordinal: 1)
        #expect(
            PraticaTimelineModel.insertionDate(between: first, and: second)
                == PraticaEntry.midpoint(between: first.date, and: second.date)
        )
    }

    // MARK: - «Inserisci qui»'s neighbours skip inside a group

    @Test func nextRowsGivesNoSuccessorInsideAGroupAndTheNextSpineRowAfterIt() {
        let next = PraticaTimelineModel.nextRows(in: Self.unitTimeline)
        #expect(next["M"] == nil, "the gap between a message and its first anchored entry is not offered")
        #expect(next["E1"] == nil, "nor the gap between two anchored entries")
        #expect(next["E2"]?.id == "F", "the group's last row offers the gap after the group")
        #expect(next["F"]?.id == "O")
        #expect(next["O"]?.id == "N")
        #expect(next["N"] == nil)
    }

    @Test func nextRowsWithNoAnchoredEntryEqualsTodaysMap() {
        let ordered = PraticaTimelineModel.ordered([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("F", 5, ordinal: 0),
            Self.entry("O", 6, ordinal: 1, anchor: "<gone>"),
            Self.message("N", 10, messageID: "<n>"),
        ])
        var reference: [String: PraticaTimelineEntry] = [:]
        for index in ordered.indices.dropLast() { reference[ordered[index].id] = ordered[index + 1] }
        #expect(PraticaTimelineModel.nextRows(in: ordered) == reference)
    }

    // MARK: - R-05: the orphan caption

    @Test func theOrphanCaptionIsShownForAnOrphanedEntryOnly() throws {
        for id in ["M", "E1", "E2", "F", "N"] {
            #expect(PraticaTimelineModel.orphanCaption(for: try Self.row(id, in: Self.unitTimeline)) == nil, "\(id)")
        }
        let caption = PraticaTimelineModel.orphanCaption(for: try Self.row("O", in: Self.unitTimeline))
        #expect(caption?.isEmpty == false)
    }
}
