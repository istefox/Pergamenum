import Foundation
import Testing
@testable import Pergamenum

// ADR-0079 §D5/§D6 (PG-369), plan docs/plans/pg-369-pratiche-timeline-rail-and-excluded.md, Task 6 -
// R-08, R-09, R-10, R-13. The pure half of the rail: which piece each drawn row carries, and where
// the line and the hook go in the row's own arithmetic. The hosted half (a real `List`, pixels)
// is `PraticaTimelineRailHostedTests`.

@Suite struct PraticaTimelineRailTests {
    /// 2026-06-10 10:00:00 UTC.
    private static let start = Date(timeIntervalSince1970: 1_781_085_600)

    private static func at(_ minute: Int) -> Date {
        start.addingTimeInterval(TimeInterval(60 * minute))
    }

    fileprivate static func message(
        _ id: String, _ minute: Int, messageID: String?, direction: MessageDocument.Direction = .received,
        sender: String = "mario@rossi.it", attachments: Bool = false
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: .message, date: at(minute), direction: direction, senderDisplayName: sender,
            senderAddress: sender, subject: "Oggetto \(id)", bodyPreview: "", hasAttachments: attachments,
            messageID: messageID, isInMail: true
        )
    }

    fileprivate static func entry(
        _ id: String, _ minute: Int, ordinal: Int, anchor: String? = nil, text: String = "voce"
    ) -> PraticaTimelineEntry {
        PraticaTimelineEntry(
            id: id, kind: .note, date: at(minute), direction: nil, senderDisplayName: "Mario Rossi",
            subject: "Nota · Mario Rossi", bodyPreview: text, hasAttachments: false, messageID: nil,
            isInMail: true, anchor: anchor, fileOrdinal: ordinal
        )
    }

    private static func pieces(
        _ rows: [PraticaTimelineEntry], excluded: Set<String> = []
    ) -> [String: PraticaRailPiece] {
        PraticaTimelineModel.railPieces(in: PraticaTimelineModel.ordered(rows, excluded: excluded))
    }

    /// The piece `id` draws, an absent row reading as `.none`.
    private static func piece(_ id: String, in pieces: [String: PraticaRailPiece]) -> PraticaRailPiece {
        pieces[id] ?? .none
    }

    // MARK: - Which piece each row draws

    @Test func aMessageWithTwoAnchoredEntriesGivesStartThroughLast() {
        let pieces = Self.pieces([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E1", 5, ordinal: 0, anchor: "<m>"),
            Self.entry("E2", 6, ordinal: 1, anchor: "<m>"),
        ])
        #expect(Self.piece("M", in: pieces) == .start)
        #expect(Self.piece("E1", in: pieces) == .through)
        #expect(Self.piece("E2", in: pieces) == .last)
    }

    @Test func aMessageWithOneAnchoredEntryGivesStartThenLast() {
        let pieces = Self.pieces([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E", 5, ordinal: 0, anchor: "<m>"),
        ])
        #expect(Self.piece("M", in: pieces) == .start)
        #expect(Self.piece("E", in: pieces) == .last)
    }

    @Test func threeAnchoredEntriesGiveOneThroughPerMiddleEntry() {
        let pieces = Self.pieces([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E1", 1, ordinal: 0, anchor: "<m>"),
            Self.entry("E2", 2, ordinal: 1, anchor: "<m>"),
            Self.entry("E3", 3, ordinal: 2, anchor: "<m>"),
        ])
        #expect(["M", "E1", "E2", "E3"].map { Self.piece($0, in: pieces) } == [.start, .through, .through, .last])
    }

    @Test func aMessageWithNoAnchoredEntryAFreeEntryAndAnOrphanedEntryDrawNoRail() {
        let pieces = Self.pieces([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("FREE", 5, ordinal: 0),
            Self.entry("ORPH", 6, ordinal: 1, anchor: "<gone>"),
            Self.message("N", 10, messageID: "<n>"),
        ])
        for id in ["M", "FREE", "ORPH", "N"] {
            #expect(Self.piece(id, in: pieces) == .none, "\(id)")
        }
    }

    @Test func aFreeEntryDatedInsideAGroupDrawsNoRailAndDoesNotBreakTheGroup() {
        // The free entry sorts after the group (ADR-0076 §D2), so the group stays contiguous.
        let pieces = Self.pieces([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E1", 2, ordinal: 0, anchor: "<m>"),
            Self.entry("E2", 6, ordinal: 1, anchor: "<m>"),
            Self.entry("FREE", 4, ordinal: 2),
        ])
        #expect(["M", "E1", "E2", "FREE"].map { Self.piece($0, in: pieces) } == [.start, .through, .last, .none])
    }

    @Test func twoGroupsBackToBackKeepTheirRailsApart() {
        let pieces = Self.pieces([
            Self.message("A", 0, messageID: "<a>"),
            Self.entry("A1", 1, ordinal: 0, anchor: "<a>"),
            Self.entry("A2", 2, ordinal: 1, anchor: "<a>"),
            Self.message("B", 10, messageID: "<b>"),
            Self.entry("B1", 11, ordinal: 2, anchor: "<b>"),
        ])
        #expect(["A", "A1", "A2", "B", "B1"].map { Self.piece($0, in: pieces) }
            == [.start, .through, .last, .start, .last])
    }

    @Test func aSecondMessageCarryingAnOwnedIDDrawsNoRail() {
        let pieces = Self.pieces([
            Self.message("FIRST", 0, messageID: "<m>"),
            Self.entry("E", 5, ordinal: 0, anchor: "<m>"),
            Self.message("SECOND", 10, messageID: "<m>"),
        ])
        #expect(Self.piece("FIRST", in: pieces) == .start)
        #expect(Self.piece("E", in: pieces) == .last)
        #expect(Self.piece("SECOND", in: pieces) == .none, "the first message owns the entries")
    }

    @Test func aMessageWithNoMessageIDOwnsNoRail() {
        let pieces = Self.pieces([
            Self.message("M", 0, messageID: nil),
            Self.entry("E", 5, ordinal: 0, anchor: ""),
        ])
        #expect(pieces.isEmpty)
    }

    @Test func aMessageWithNothingAnchoredUnderItDrawsNoRailNextToAnotherMessage() {
        // What a filter that hid every anchored entry would leave: two messages in a row.
        #expect(Self.pieces([
            Self.message("M", 0, messageID: "<m>"), Self.message("N", 10, messageID: "<n>"),
        ]).isEmpty)
    }

    @Test func anAnchoredEntryHandedInWithoutItsMessageDrawsNothing() {
        let rows = PraticaTimelineModel.ordered([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E1", 1, ordinal: 0, anchor: "<m>"),
            Self.entry("E2", 2, ordinal: 1, anchor: "<m>"),
        ])
        let withoutMessage = Array(rows.dropFirst())
        #expect(PraticaTimelineModel.railPieces(in: withoutMessage).isEmpty, "no rail hangs from a missing message")
    }

    @Test func anAnchoredEntryUnderAnotherMessageThanItsOwnDrawsNothing() {
        var rows = PraticaTimelineModel.ordered([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("E", 1, ordinal: 0, anchor: "<m>"),
        ])
        rows[1].placement = .anchored(messageID: "<other>")
        #expect(PraticaTimelineModel.railPieces(in: rows).isEmpty)
    }

    // MARK: - After the filters (the pieces are read off `filteredTimeline`)

    private static let timeline = PraticaTimelineModel.ordered([
        message("M", 0, messageID: "<m>", sender: "mario@rossi.it", attachments: true),
        entry("E1", 10, ordinal: 0, anchor: "<m>", text: "sopralluogo"),
        entry("E2", 20, ordinal: 1, anchor: "<m>", text: "altro"),
        message("N", 50, messageID: "<n>", sender: "luigi@verdi.it"),
        entry("N1", 51, ordinal: 2, anchor: "<n>", text: "conferma"),
    ])

    @Test func aMessageHiddenByTheSenderFilterLeavesItsEntriesWithoutAnyPiece() {
        let shown = PraticaTimelineModel.filtered(Self.timeline, by: PraticaTimelineFilter(sender: "luigi@verdi.it"))
        #expect(shown.map(\.id) == ["N", "N1"])
        let pieces = PraticaTimelineModel.railPieces(in: shown)
        #expect(pieces["M"] == nil && pieces["E1"] == nil && pieces["E2"] == nil, "no rail without its message")
        #expect(pieces["N"] == .start && pieces["N1"] == .last)
    }

    @Test func anEntryMatchingTheTextFilterBringsItsWholeGroupAndItsRail() {
        let shown = PraticaTimelineModel.filtered(Self.timeline, by: PraticaTimelineFilter(text: "sopralluogo"))
        #expect(shown.map(\.id) == ["M", "E1", "E2"])
        let pieces = PraticaTimelineModel.railPieces(in: shown)
        #expect(["M", "E1", "E2"].map { Self.piece($0, in: pieces) } == [.start, .through, .last])
    }

    @Test func aGroupIsNeverSplitByADaySectionSoItsPiecesAreTheSameInWholeAndInSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        // The message at 23:30, its entries written the next morning.
        let rows = PraticaTimelineModel.ordered([
            Self.message("M", 13 * 60 + 30, messageID: "<m>"),
            Self.entry("E1", 14 * 60 + 30, ordinal: 0, anchor: "<m>"),
            Self.entry("E2", 15 * 60, ordinal: 1, anchor: "<m>"),
        ])
        let sections = PraticaTimelineModel.daySections(of: rows, calendar: calendar)
        #expect(sections.count == 1)
        let whole = PraticaTimelineModel.railPieces(in: rows)
        let inSection = try #require(sections.first).entries
        #expect(PraticaTimelineModel.railPieces(in: inSection) == whole)
        #expect(whole.count == 3)
    }

    @Test func anExcludedMessagesEntriesAreHiddenBeforeThePiecesAreComputed() {
        // ADR-0079 §D3: `timeline` never holds the row, so the message above draws no rail from it.
        let placed = PraticaTimelineModel.ordered([
            Self.message("M", 0, messageID: "<m>"),
            Self.entry("EXC", 5, ordinal: 0, anchor: "<out>"),
        ], excluded: ["<out>"])
        let pieces = PraticaTimelineModel.railPieces(in: PraticaTimelineModel.hidingExcluded(placed))
        #expect(pieces.isEmpty)
    }
}

// MARK: - railGeometry (R-08, R-09)

@Suite struct PraticaRailGeometryTests {
    private static let gutter = Theme.emergency.spacing(.m)
    private static let step = Theme.emergency.spacing(.l)
    private static let readable = Theme.emergency.spacing(.readable)

    private static func columns(row: CGFloat, lane: PraticaLane) -> PraticaRowColumns {
        PraticaTimelineModel.rowColumns(
            container: PraticaTimelineModel.columnWidth(row: row, readable: readable),
            lane: lane, reservesSlot: true, gutter: gutter
        )
    }

    /// The columns the timeline lays out in: 379 and 396 pt are the 428 pt timeline without and with
    /// the legacy scroller's width taken out, 720 the readable column, the rest a wide window.
    static let rowWidths: [CGFloat] = [379, 396, 428, 720, 800, 1000, 1600]

    @Test(arguments: [PraticaLane.received, .sent], rowWidths)
    func theLineLiesInsideTheIndentOnTheLanesOwnEdge(lane: PraticaLane, width: CGFloat) {
        let columns = Self.columns(row: width, lane: lane)
        let geometry = PraticaTimelineModel.railGeometry(columns: columns, lane: lane, step: Self.step)
        switch lane {
        case .received:
            #expect(geometry.x >= columns.cardX && geometry.x <= columns.cardX + Self.step, "\(width)")
            #expect(geometry.hookEnd == columns.cardX + Self.step, "the anchored card's leading edge")
        case .sent:
            let edge = columns.cardX + columns.cardWidth
            #expect(geometry.x >= edge - Self.step && geometry.x <= edge, "\(width)")
            #expect(geometry.hookEnd == edge - Self.step, "the anchored card's trailing edge")
        case .entry:
            Issue.record("not a message lane")
        }
        #expect(geometry.x >= 0 && geometry.x <= width)
    }

    @Test(arguments: [PraticaLane.received, .sent], rowWidths)
    func theLineTakesNothingFromTheAnchoredCardOrTheNoteColumn(lane: PraticaLane, width: CGFloat) {
        let columns = Self.columns(row: width, lane: lane)
        let geometry = PraticaTimelineModel.railGeometry(columns: columns, lane: lane, step: Self.step)
        let halfLine = PraticaTimelineModel.railLineWidth / 2
        let line = (geometry.x - halfLine)...(geometry.x + halfLine)
        let indent = PraticaTimelineModel.anchoredIndent(lane: lane, isAnchored: true, step: Self.step)
        // The anchored card: the message's card inset by the indent.
        let card = (columns.cardX + indent.leading)...(columns.cardX + columns.cardWidth - indent.trailing)
        let overCard = line.lowerBound < card.upperBound && line.upperBound > card.lowerBound
        #expect(!overCard, "line \(line) over card \(card)")
        let slotX = columns.slotX ?? 0
        let slot = slotX...(slotX + columns.slotWidth)
        let overSlot = line.lowerBound < slot.upperBound && line.upperBound > slot.lowerBound
        #expect(!overSlot, "line \(line) over slot \(slot)")
    }

    @Test(arguments: [PraticaLane.received, .sent], rowWidths)
    func aMessageRowAndItsAnchoredRowsShareOneLineX(lane: PraticaLane, width: CGFloat) {
        let direction: MessageDocument.Direction = lane == .sent ? .sent : .received
        var message = PraticaTimelineRailTests.message("M", 0, messageID: "<m>", direction: direction)
        message.placement = .message
        var anchored = PraticaTimelineRailTests.entry("E", 5, ordinal: 0, anchor: "<m>")
        anchored.placement = .anchored(messageID: "<m>")
        anchored.hostDirection = message.direction
        let messageLane = PraticaTimelineModel.hostLane(for: message)
        let entryLane = PraticaTimelineModel.hostLane(for: anchored)
        #expect(messageLane == lane && entryLane == lane)

        let first = PraticaTimelineModel.railGeometry(
            columns: Self.columns(row: width, lane: messageLane), lane: messageLane, step: Self.step
        )
        let second = PraticaTimelineModel.railGeometry(
            columns: Self.columns(row: width, lane: entryLane), lane: entryLane, step: Self.step
        )
        #expect(first == second)
    }

    @Test(arguments: [PraticaLane.received, .sent])
    func fromEightHundredPointsUpTheGeometryIsTheReadableColumnsOwn(lane: PraticaLane) {
        let reference = PraticaTimelineModel.railGeometry(
            columns: Self.columns(row: Self.readable, lane: lane), lane: lane, step: Self.step
        )
        for width: CGFloat in [800, 1000, 1600, 3000] {
            let columns = Self.columns(row: width, lane: lane)
            #expect(
                PraticaTimelineModel.railGeometry(columns: columns, lane: lane, step: Self.step) == reference,
                "\(width)"
            )
        }
    }

    @Test func theMirrorsAreMirrors() {
        let width: CGFloat = 396
        let received = Self.columns(row: width, lane: .received)
        let sent = Self.columns(row: width, lane: .sent)
        let left = PraticaTimelineModel.railGeometry(columns: received, lane: .received, step: Self.step)
        let right = PraticaTimelineModel.railGeometry(columns: sent, lane: .sent, step: Self.step)
        let container = PraticaTimelineModel.columnWidth(row: width, readable: Self.readable)
        #expect(abs((container - right.x) - left.x) < 0.001, "the sent line is the received one mirrored in the column")
        #expect(abs((container - right.hookEnd) - left.hookEnd) < 0.001)
    }

    @Test func theLineIsHalfAStepInAndTheHookEndsOneStepInOnTheLeadingEdge() {
        let columns = Self.columns(row: 396, lane: .received)
        let geometry = PraticaTimelineModel.railGeometry(columns: columns, lane: .received, step: 40)
        #expect(geometry == PraticaRailGeometry(x: columns.cardX + 20, hookEnd: columns.cardX + 40))
    }

    // MARK: - The constants the drawing reads

    @Test func theLineIsAsWideAsTheSelectionOutlineAndTheRowInsetIsTheMeasuredFourPoints() {
        #expect(PraticaTimelineModel.railLineWidth == 2)
        #expect(PraticaTimelineModel.railRowInset == 4)
        #expect(PraticaTimelineModel.railLineWidth < Self.step, "the line fits in the indent")
    }
}
