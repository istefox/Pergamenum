import Foundation
import Testing
@testable import Pergamenum

// PG-354, PG-355: the timeline row's arithmetic (`PraticaTimelineModel+Layout.swift`) - which
// side a lane sits on, the readable column, how wide the lane and the note slot beside the card
// are, where a card and its slot go, an anchored entry's indent and the selected card's token.
// The production layout itself, in a real `List`, is `PraticaTimelineLaneHostedTests`.

@Suite struct PraticaTimelineLayoutTests {
    /// `theme.spacing(.m)` in both bundled themes, the gutter the row passes.
    private static let gutter: CGFloat = 16

    private static func close(_ value: CGFloat, _ expected: CGFloat) -> Bool {
        abs(value - expected) < 0.001
    }

    private static func lane(_ container: CGFloat, _ lane: PraticaLane = .received) -> CGFloat {
        PraticaTimelineModel.laneWidth(container: container, lane: lane, reservesSlot: true, gutter: gutter)
    }

    private static func slot(_ container: CGFloat) -> CGFloat {
        PraticaTimelineModel.noteSlotWidth(container: container, gutter: gutter)
    }

    // MARK: - PG-354: the side

    @Test func aReceivedLaneSitsLeadingAndASentLaneTrailing() {
        #expect(PraticaTimelineModel.laneAlignment(.received) == .leading)
        #expect(PraticaTimelineModel.laneAlignment(.sent) == .trailing)
    }

    @Test func aFullWidthEntryStartsOnTheLeadingSide() {
        #expect(PraticaTimelineModel.laneAlignment(.entry) == .leading)
    }

    @Test func theNoteSlotMirrorsTheLaneTrailingAReceivedOneAndLeadingASentOne() {
        // `[lane][gutter][slot]......` received, `......[slot][gutter][lane]` sent.
        #expect(PraticaTimelineModel.slotSide(.received) == .trailing)
        #expect(PraticaTimelineModel.slotSide(.sent) == .leading)
    }

    @Test(arguments: [PraticaLane.received, .sent, .entry])
    func theNoteSlotIsAlwaysOnTheSideAwayFromTheLanesEdge(lane: PraticaLane) {
        #expect(PraticaTimelineModel.slotSide(lane) != PraticaTimelineModel.laneAlignment(lane))
    }

    // MARK: - PG-355: the widths
    //
    // `container` is the column width, never the timeline's own width: measured in
    // `PraticaTimelineLaneHostedTests`, a 360/428/800 pt timeline gives a 328/396/768 pt row, and
    // 311/379/751 beside a legacy scroller, and the timeline caps the row at the 720 pt readable
    // column (`columnWidth`) before handing it here. A container wider than 720 pt is the pure
    // arithmetic alone, which production never reaches.

    @Test func aRowOf768PointsReachesTheFullSlot() {
        // The uncapped arithmetic on a 768 pt container: the full 200 pt slot and a 70 % lane,
        // (768 - 16 - 200) * 0.7. In the timeline that row is capped at 720 pt first.
        #expect(Self.slot(768) == 200)
        #expect(Self.close(Self.lane(768), 552 * 0.7))
        #expect(Self.close(Self.lane(768, .sent), 552 * 0.7))
    }

    @Test(arguments: [396.0, 379.0])
    func aDefaultTimelineKeepsAMessageLaneOfAtLeast240Points(container: Double) {
        // 396 pt with no scroller, 379 pt beside a legacy one. Before PG-355 the lane was
        // (row - 216) * 0.7: about 126 and 114 pt.
        let width = CGFloat(container)
        let column = (width - Self.gutter) * 0.27
        #expect(Self.close(Self.slot(width), column))
        #expect(Self.close(Self.lane(width), (width - Self.gutter - column) * 0.91))
        #expect(Self.lane(width) >= 240, "\(Self.lane(width)) pt at a \(width) pt row")
        #expect(Self.lane(width, .sent) >= 240)
    }

    @Test(arguments: [328.0, 311.0])
    func atThePanesMinimumNothingOverlaps(container: Double) {
        // A 360 pt timeline, the pane's minimum: its row is 328 pt, or 311 pt with a scroller.
        let width = CGFloat(container)
        let column = (width - Self.gutter) * 0.27
        #expect(Self.close(Self.slot(width), column))
        #expect(Self.close(Self.lane(width), (width - Self.gutter - column) * 0.91))
        #expect(Self.lane(width) + Self.gutter + Self.slot(width) <= width)
    }

    /// The row widths measured in `PraticaTimelineLaneHostedTests` for a 360, 428 and 800 pt
    /// timeline, with no scroller (32 pt of row inset) and with a legacy one (49 pt), plus the
    /// timeline widths themselves as rows a wider pane could hand out.
    @Test(arguments: [328.0, 311.0, 396.0, 379.0, 768.0, 751.0, 360.0, 428.0, 800.0])
    func theLaneTheGutterAndTheColumnNeverExceedTheRow(container: Double) {
        let width = CGFloat(container)
        for lane in [PraticaLane.received, .sent] {
            #expect(Self.lane(width, lane) + Self.gutter + Self.slot(width) <= width)
            #expect(Self.lane(width, lane) > 0)
        }
    }

    @Test func aFreeEntryTakesTheWholeRow() {
        #expect(PraticaTimelineModel.laneWidth(container: 396, lane: .entry, reservesSlot: false, gutter: 16) == 396)
        #expect(PraticaTimelineModel.laneWidth(container: 768, lane: .entry, reservesSlot: false, gutter: 16) == 768)
    }

    @Test func theUncappedSlotStopsAt200AndNeverGoesNegative() {
        // A 2000 pt container is the pure function alone: the timeline passes at most 720 pt.
        #expect(Self.slot(2000) == 200)
        #expect(Self.slot(0) == 0)
        #expect(Self.lane(0) == 0)
    }

    @Test func theLaneShareMovesInAStraightLineBetweenTheTwoThresholds() {
        #expect(PraticaTimelineModel.laneShare(of: 600) == 0.7)
        #expect(PraticaTimelineModel.laneShare(of: 500) == 0.7)
        #expect(Self.close(PraticaTimelineModel.laneShare(of: 400), 0.805))
        #expect(PraticaTimelineModel.laneShare(of: 300) == 0.91)
        #expect(PraticaTimelineModel.laneShare(of: 200) == 0.91)
    }

    // MARK: - The readable column (hand check round 4)

    /// `spacing.readable` in both bundled themes (ADR-0030 §D7).
    private static let readable: CGFloat = 720

    @Test func theColumnIsTheRowCappedAtTheReadableWidth() {
        #expect(PraticaTimelineModel.columnWidth(row: 396, readable: Self.readable) == 396, "all column")
        #expect(PraticaTimelineModel.columnWidth(row: 720, readable: Self.readable) == 720)
        #expect(PraticaTimelineModel.columnWidth(row: 1168, readable: Self.readable) == 720, "a wide row is capped")
        #expect(PraticaTimelineModel.columnWidth(row: -4, readable: Self.readable) == 0)
    }

    /// A wide row (1200 and 1600 pt timelines, with and without the scroller) lays out in the
    /// 720 pt column: the sent card's trailing edge is the column's, and nothing goes past it.
    @Test(arguments: [1168.0, 1151.0, 1568.0, 1551.0])
    func aWideRowLaysOutEverythingInsideTheReadableColumn(row: Double) throws {
        let container = PraticaTimelineModel.columnWidth(row: row, readable: Self.readable)
        #expect(container == Self.readable)
        for lane in [PraticaLane.received, .sent] {
            let columns = PraticaTimelineModel.rowColumns(
                container: container, lane: lane, reservesSlot: true, gutter: Self.gutter
            )
            let slotX = try #require(columns.slotX)
            #expect(columns.cardX + columns.cardWidth <= Self.readable + 0.001)
            #expect(slotX + columns.slotWidth <= Self.readable + 0.001)
            if lane == .sent {
                #expect(Self.close(columns.cardX + columns.cardWidth, Self.readable))
            }
        }
    }

    // MARK: - Uniform widths

    @Test func aReceivedCardIsTheWholeLaneFlushLeadingWithItsSlotRightAfterIt() {
        let columns = PraticaTimelineModel.rowColumns(
            container: 720, lane: .received, reservesSlot: true, gutter: Self.gutter
        )
        // The 720 pt column: a (720 - 16) * 0.27 = 190.08 pt slot, a 70 % lane of the 513.92 left.
        let lane = (720 - 16 - 190.08) * 0.7
        #expect(Self.close(columns.cardX, 0) && Self.close(columns.cardWidth, lane))
        #expect(Self.close(columns.slotX ?? -1, lane + 16) && Self.close(columns.slotWidth, 190.08))
    }

    @Test func aSentCardIsTheWholeLaneFlushTrailingWithItsSlotRightBeforeIt() {
        let columns = PraticaTimelineModel.rowColumns(
            container: 720, lane: .sent, reservesSlot: true, gutter: Self.gutter
        )
        // `......[slot][gutter][card]`, up to the column's trailing edge.
        let lane = (720 - 16 - 190.08) * 0.7
        #expect(Self.close(columns.cardX, 720 - lane) && Self.close(columns.cardWidth, lane))
        #expect(Self.close(columns.slotX ?? -1, 720 - lane - 16 - 190.08))
    }

    @Test(arguments: [PraticaLane.received, .sent], [328.0, 311.0, 396.0, 379.0, 720.0, 768.0, 751.0])
    func everyMessageCardIsTheWholeLaneAndNeverTheSlotOrTheColumnsEdges(lane: PraticaLane, container: Double) throws {
        let width = CGFloat(container)
        let columns = PraticaTimelineModel.rowColumns(
            container: width, lane: lane, reservesSlot: true, gutter: Self.gutter
        )
        let slotX = try #require(columns.slotX)
        #expect(Self.close(columns.cardWidth, Self.lane(width, lane)))
        #expect(columns.cardX >= -0.001 && columns.cardX + columns.cardWidth <= width + 0.001)
        #expect(slotX >= -0.001 && slotX + columns.slotWidth <= width + 0.001)
        let gap = lane == .sent
            ? columns.cardX - (slotX + columns.slotWidth)
            : slotX - (columns.cardX + columns.cardWidth)
        #expect(Self.close(gap, Self.gutter), "the gutter between card and slot is \(gap)")
    }

    @Test(arguments: [396.0, 720.0])
    func aFreeEntryTakesTheWholeColumn(container: Double) {
        let columns = PraticaTimelineModel.rowColumns(
            container: container, lane: .entry, reservesSlot: false, gutter: Self.gutter
        )
        #expect(columns == PraticaRowColumns(cardX: 0, cardWidth: container, slotX: nil, slotWidth: 0))
    }

    @Test func theLaneNeverNarrowsAsTheTimelineWidens() {
        var previous: CGFloat = 0
        for container in stride(from: CGFloat(300), through: 1200, by: 4) {
            let width = Self.lane(container)
            #expect(width >= previous, "the lane shrank at \(container) pt")
            previous = width
        }
    }

    // MARK: - An anchored entry's indent (R-09)

    @Test func anAnchoredEntryIndentsFromItsLanesOwnEdge() {
        let received = PraticaTimelineModel.anchoredIndent(lane: .received, isAnchored: true, step: 24)
        #expect(received.leading == 24 && received.trailing == 0, "under a received message: leading")
        let sent = PraticaTimelineModel.anchoredIndent(lane: .sent, isAnchored: true, step: 24)
        #expect(sent.leading == 0 && sent.trailing == 24, "under a sent message: trailing, its flush edge")
    }

    @Test func aRowThatIsNotAnchoredIsNotIndented() {
        for lane in [PraticaLane.received, .sent, .entry] {
            let indent = PraticaTimelineModel.anchoredIndent(lane: lane, isAnchored: false, step: 24)
            #expect(indent.leading == 0 && indent.trailing == 0, "\(lane)")
        }
    }

    /// An anchored entry's box is its message's lane less the indent, inset on the lane's own
    /// edge: received `[0, L]` gives `[indent, L]`, sent `[C-L, C]` gives `[C-L, C-indent]`, so its
    /// far edge lines up with the message's inner edge.
    @Test(arguments: [328.0, 396.0, 379.0, 720.0])
    func anAnchoredEntrysBoxLinesUpWithItsMessagesInnerEdge(container: Double) {
        let indent: CGFloat = 24
        for lane in [PraticaLane.received, .sent] {
            let message = PraticaTimelineModel.rowColumns(
                container: container, lane: lane, reservesSlot: true, gutter: Self.gutter
            )
            let padding = PraticaTimelineModel.anchoredIndent(lane: lane, isAnchored: true, step: indent)
            // The entry's card takes the same columns (it reserves the slot too); the padding
            // insets the box inside it.
            let boxMinX = message.cardX + padding.leading
            let boxMaxX = message.cardX + message.cardWidth - padding.trailing
            let lw = message.cardWidth
            if lane == .received {
                #expect(Self.close(boxMinX, indent) && Self.close(boxMaxX, lw), "received box [\(boxMinX), \(boxMaxX)]")
            } else {
                let width = CGFloat(container)
                #expect(Self.close(boxMinX, width - lw) && Self.close(boxMaxX, width - indent), "sent box")
            }
            #expect(Self.close(boxMaxX - boxMinX, lw - indent))
        }
    }

    // MARK: - Selection on the card

    @Test func aSelectedCardIsOutlinedInTheAccentTokenAndAnUnselectedOneIsNot() {
        #expect(PraticaTimelineModel.selectionBorder(isSelected: true) == .accentPrimary)
        #expect(PraticaTimelineModel.selectionBorder(isSelected: false) == nil)
    }
}
