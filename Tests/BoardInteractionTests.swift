import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// MARK: - Resize handles (SPEC §6.3)

private func card(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: y, width: width, height: height)
}

@Test func aCornerGripMovesBothEdgesItTouches() {
    let resized = BoardGeometry.resized(
        card(100, 100, 200, 100), handle: .bottomRight, by: CGSize(width: 40, height: 20)
    )
    #expect(resized == card(100, 100, 240, 120))
}

@Test func aGripOnTheTopLeftMovesTheOriginRatherThanTheFarEdge() {
    let resized = BoardGeometry.resized(
        card(100, 100, 200, 100), handle: .topLeft, by: CGSize(width: 20, height: 10)
    )
    // The bottom-right corner is the anchor: it must not move.
    #expect(resized == card(120, 110, 180, 90))
}

@Test func aSideGripLeavesTheOtherDimensionAlone() {
    let resized = BoardGeometry.resized(
        card(0, 0, 200, 100), handle: .right, by: CGSize(width: 50, height: 999)
    )
    #expect(resized == card(0, 0, 250, 100))
}

@Test func shiftKeepsTheProportions() {
    // A 2:1 card widened by 100 must become 400x200, not 400x100.
    let resized = BoardGeometry.resized(
        card(0, 0, 200, 100), handle: .right, by: CGSize(width: 200, height: 0), lockAspect: true
    )
    #expect(resized == card(0, 0, 400, 200))
}

@Test func shiftOnATopGripStillHoldsTheBottomEdge() {
    let resized = BoardGeometry.resized(
        card(0, 0, 200, 100), handle: .top, by: CGSize(width: 0, height: -100), lockAspect: true
    )
    #expect(resized.maxY == 100)
    #expect(resized.width / resized.height == 2)
}

@Test func aCardCannotBeShrunkBelowItsGrips() {
    let resized = BoardGeometry.resized(
        card(0, 0, 200, 100), handle: .bottomRight, by: CGSize(width: -500, height: -500)
    )
    // Otherwise the grips overlap and the card can never be grabbed again.
    #expect(resized.width == BoardGeometry.minimumSize.width)
    #expect(resized.height == BoardGeometry.minimumSize.height)
}

// MARK: - Marquee and selection

private func node(
    _ id: String, _ x: CGFloat, _ y: CGFloat,
    _ width: CGFloat = 100, _ height: CGFloat = 100,
    kind: CanvasNode.Kind = .text("x")
) -> CanvasNode {
    CanvasNode(id: id, kind: kind, x: x, y: y, width: width, height: height)
}

@Test func aMarqueeCatchesEveryCardItTouches() {
    let nodes = [node("a", 0, 0), node("b", 300, 0), node("c", 50, 50)]
    let caught = BoardGeometry.nodeIDs(in: card(-10, -10, 120, 120), among: nodes)
    // "b" is 300 away and must stay out; "c" only overlaps and must come in.
    #expect(caught == ["a", "c"])
}

@Test func aMarqueeDraggedUpAndLeftIsStillARectangle() {
    let rect = BoardGeometry.rect(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 100, y: 50))
    #expect(rect == card(100, 50, 100, 150))
}

@Test func shiftClickAddsAndRemoves() {
    var selection: Set<String> = ["a"]
    selection = BoardGeometry.toggling("b", in: selection)
    #expect(selection == ["a", "b"])
    selection = BoardGeometry.toggling("a", in: selection)
    #expect(selection == ["b"])
}

// MARK: - Groups (SPEC §6.5)

@Test func aGroupHoldsTheCardsInsideIt() {
    let group = node("g", 0, 0, 400, 400, kind: .group(label: "Progetto"))
    let inside = node("in", 20, 20, 100, 100)
    let straddling = node("edge", 380, 380, 100, 100)
    let outside = node("out", 900, 900)

    let held = BoardGeometry.nodeIDs(inside: group, among: [group, inside, straddling, outside])
    // Contained, not merely touching: a card the user never put in the group must not
    // be dragged along by it.
    #expect(held == ["in"])
}

@Test func movingAGroupMovesWhatItHolds() {
    let group = node("g", 0, 0, 400, 400, kind: .group(label: nil))
    let inside = node("in", 20, 20)
    let expanded = BoardGeometry.expandingGroups(["g"], among: [group, inside])
    #expect(expanded == ["g", "in"])
}

@Test func anOrdinaryCardHoldsNothing() {
    let plain = node("plain", 0, 0, 400, 400)
    let inside = node("in", 20, 20)
    #expect(BoardGeometry.nodeIDs(inside: plain, among: [plain, inside]).isEmpty)
}

// MARK: - Alignment guides and grid

@Test func aCardSnapsToTheLeftEdgeOfAnother() {
    let (frame, guides) = BoardGeometry.snapped(
        card(103, 300, 100, 100), to: [card(100, 0, 100, 100)], threshold: 6
    )
    #expect(frame.minX == 100)
    #expect(guides == [BoardGeometry.Guide(axis: .vertical, position: 100)])
}

@Test func aCardSnapsByItsCentreToo() {
    // A wide neighbour whose centre is 148: its own edges (48 and 248) are far from
    // this card's, so the centre is the only thing within reach.
    let (frame, guides) = BoardGeometry.snapped(
        card(100, 500, 100, 100), to: [card(48, 0, 200, 100)], threshold: 6
    )
    #expect(frame.midX == 148)
    #expect(guides == [BoardGeometry.Guide(axis: .vertical, position: 148)])
}

@Test func whenSeveralEdgesTieTheGuideMarksTheOneItAlignedTo() {
    // Two cards of the same width, offset by 2: left edges, centres and right edges
    // are all 2 apart. The first candidate wins, and the guide has to name the edge
    // that was actually aligned - a guide drawn through the centre while the left
    // edges are what lined up would point at nothing.
    let (frame, guides) = BoardGeometry.snapped(
        card(100, 500, 100, 100), to: [card(98, 0, 100, 100)], threshold: 6
    )
    #expect(frame.minX == 98)
    #expect(guides == [BoardGeometry.Guide(axis: .vertical, position: 98)])
}

@Test func aDistantCardDoesNotPull() {
    let (frame, guides) = BoardGeometry.snapped(
        card(300, 300, 100, 100), to: [card(100, 100, 100, 100)], threshold: 6
    )
    #expect(frame == card(300, 300, 100, 100))
    #expect(guides.isEmpty)
}

@Test func theGridActsOnlyWhereNothingAlignsTo() {
    // Aligns horizontally with the neighbour, so the grid must not also pull x.
    let (frame, guides) = BoardGeometry.snapped(
        card(102, 307, 100, 100), to: [card(100, 0, 100, 100)], threshold: 6, gridStep: 20
    )
    #expect(frame.minX == 100)
    #expect(frame.minY == 300)
    #expect(guides.count == 1)
}

@Test func theGridRoundsBothAxesWhenThereIsNothingToAlignTo() {
    let (frame, guides) = BoardGeometry.snapped(
        card(107, 313, 100, 100), to: [], threshold: 6, gridStep: 20
    )
    #expect(frame.origin == CGPoint(x: 100, y: 320))
    #expect(guides.isEmpty)
}

@Test func withoutAGridAnUnalignedCardStaysExactlyWhereItWasDropped() {
    let (frame, _) = BoardGeometry.snapped(card(107, 313, 100, 100), to: [], threshold: 6)
    #expect(frame == card(107, 313, 100, 100))
}

// MARK: - Culling (SPEC §6.3)

@Test func theVisibleRectangleFollowsPanAndZoom() {
    let visible = BoardGeometry.visibleRect(
        viewport: CGSize(width: 800, height: 600), pan: CGSize(width: -100, height: -50), zoom: 2
    )
    #expect(visible == card(50, 25, 400, 300))
}

@Test func onlyTheCardsNearTheViewportAreDrawn() {
    let nodes = [node("near", 0, 0), node("far", 5000, 5000)]
    let visible = BoardGeometry.visibleRect(
        viewport: CGSize(width: 800, height: 600), pan: .zero, zoom: 1
    )
    #expect(BoardGeometry.visibleNodes(nodes, in: visible).map(\.id) == ["near"])
}

@Test func aCardJustOffScreenIsStillDrawnSoItDoesNotPopIn() {
    let nodes = [node("justOff", 850, 0)]
    let visible = BoardGeometry.visibleRect(
        viewport: CGSize(width: 800, height: 600), pan: .zero, zoom: 1
    )
    #expect(BoardGeometry.visibleNodes(nodes, in: visible).count == 1)
}

@Test(arguments: [(0.1, true), (0.24, true), (0.25, false), (1.0, false)])
func complexCardsDegradeBelowAQuarterZoom(zoom: Double, isPlaceholder: Bool) {
    #expect(BoardGeometry.drawsPlaceholder(at: CGFloat(zoom)) == isPlaceholder)
}

// MARK: - Undo and redo (SPEC §6.1)

private func document(_ ids: [String]) -> CanvasDocument {
    var document = CanvasDocument.empty
    document.nodes = ids.map { node($0, 0, 0) }
    return document
}

@Test func undoRestoresTheBoardAsItWas() {
    var history = BoardHistory()
    let before = document(["a"])
    history.record(before: before)
    let after = document(["a", "b"])

    #expect(history.canUndo)
    #expect(history.undo(current: after) == .restored(before))
}

@Test func redoPutsTheChangeBack() {
    var history = BoardHistory()
    let before = document(["a"])
    let after = document(["a", "b"])
    history.record(before: before)
    _ = history.undo(current: after)

    #expect(history.canRedo)
    #expect(history.redo(current: before) == .restored(after))
}

@Test func aNewChangeMakesTheRedoBranchUnreachable() {
    var history = BoardHistory()
    history.record(before: document(["a"]))
    _ = history.undo(current: document(["a", "b"]))
    #expect(history.canRedo)

    history.record(before: document(["a"]))
    // Redoing to a board that never existed is worse than not redoing at all.
    #expect(!history.canRedo)
}

@Test func undoRefusesToStepPastSomethingCreatedInTheVault() {
    var history = BoardHistory()
    history.record(before: document(["a"]), creatingOnDisk: "01 Progetti/vibrofer-emea")

    // Undoing would remove the card and leave the folder, so the board would stop
    // being a view of the folder it shows.
    #expect(!history.canUndo)
    #expect(history.undo(current: document(["a", "b"])) == .blocked("01 Progetti/vibrofer-emea"))
    #expect(history.blockedBy == "01 Progetti/vibrofer-emea")
}

@Test func undoOnAnUntouchedBoardDoesNothing() {
    var history = BoardHistory()
    #expect(!history.canUndo)
    #expect(history.undo(current: .empty) == .nothingToDo)
    #expect(history.redo(current: .empty) == .nothingToDo)
}

@Test func theHistoryDoesNotGrowWithoutBound() {
    var history = BoardHistory()
    for index in 0...(BoardHistory.limit + 10) {
        history.record(before: document(["node-\(index)"]))
    }
    #expect(history.undoStack.count == BoardHistory.limit)
    // The oldest steps are the ones dropped, so the most recent are still undoable.
    #expect(history.undoStack.last?.document.nodes.first?.id == "node-\(BoardHistory.limit + 10)")
}

@Test func openingAnotherBoardClearsTheHistory() {
    var history = BoardHistory()
    history.record(before: document(["a"]))
    history.reset()
    // Undoing on one board must never reach back into another one's changes.
    #expect(!history.canUndo)
    #expect(!history.canRedo)
}
