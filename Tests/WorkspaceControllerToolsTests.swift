import Foundation
import Testing
@testable import Pergamenum

// `WorkspaceController` dragging, the Freccia tool (SPEC §6.4 tool 11) and crop mode
// transitions (ADR-0020 Task 3) tests (PG-088 — pure code motion off `CanvasTests.swift`).
// MARK: - Dragging

@MainActor
@Test func aDragMovesByTheTotalTranslationNotByEachStep() throws {
    // Found by dragging a card with a real mouse: the drag state lived in view
    // `@State`, which a gesture callback cannot reliably read back, so every event
    // restarted from the already-moved position and a 100-point drag threw the card
    // thousands of units away.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let id = controller.addStickyNote("a", at: CGPoint(x: 100, y: 100))
    controller.selection = [id]
    controller.beginDrag(nodeIDs: [id])

    // A gesture reports the translation from its own start, so these are cumulative
    // reports of one 60x30 drag, not three separate moves.
    controller.updateDrag(translation: CGSize(width: 20, height: 10))
    controller.updateDrag(translation: CGSize(width: 40, height: 20))
    controller.updateDrag(translation: CGSize(width: 60, height: 30))
    controller.endDrag()

    let node = try #require(controller.document.node(id: id))
    #expect(node.x == 160)
    #expect(node.y == 130)
    controller.detach()
}

@MainActor
@Test func aDragMovesEverySelectedCardTogether() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let first = controller.addStickyNote("a", at: .zero)
    let second = controller.addStickyNote("b", at: CGPoint(x: 300, y: 0))
    let untouched = controller.addStickyNote("c", at: CGPoint(x: 600, y: 0))

    controller.selection = [first, second]
    controller.beginDrag(nodeIDs: controller.selection)
    controller.updateDrag(translation: CGSize(width: 50, height: 50))
    controller.endDrag()

    #expect(controller.document.node(id: first)?.x == 50)
    #expect(controller.document.node(id: second)?.x == 350)
    #expect(controller.document.node(id: untouched)?.x == 600)
    controller.detach()
}

@MainActor
@Test func updatingADragOutsideOneDoesNothing() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.addStickyNote("a", at: CGPoint(x: 10, y: 10))

    // A stray callback after the gesture ended must not move anything.
    controller.updateDrag(translation: CGSize(width: 999, height: 999))
    #expect(controller.document.node(id: id)?.x == 10)
    controller.detach()
}

@MainActor
@Test func beginningADragTwiceKeepsTheOriginalOrigins() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.addStickyNote("a", at: .zero)

    controller.beginDrag(nodeIDs: [id])
    controller.updateDrag(translation: CGSize(width: 100, height: 0))
    // A second begin mid-gesture must not re-anchor to the moved position.
    controller.beginDrag(nodeIDs: [id])
    controller.updateDrag(translation: CGSize(width: 100, height: 0))
    controller.endDrag()

    #expect(controller.document.node(id: id)?.x == 100)
    controller.detach()
}

// MARK: - The Freccia tool (SPEC §6.4, tool 11)

@MainActor
@Test func theArrowToolConnectsTheCardItIsReleasedOn() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let a = controller.addStickyNote("a", at: .zero)
    let b = controller.addStickyNote("b", at: CGPoint(x: 400, y: 0))
    let source = try #require(controller.document.node(id: a))
    let target = try #require(controller.document.node(id: b))

    controller.tool = .arrow
    controller.beginArrow(from: a)
    controller.updateArrow(translation: CGSize(
        width: target.frame.midX - source.frame.midX,
        height: target.frame.midY - source.frame.midY
    ))
    #expect(controller.endArrow() != nil)
    #expect(controller.document.edges.count == 1)
    #expect(controller.document.edges.first?.fromNode == a)
    #expect(controller.document.edges.first?.toNode == b)
    // One-shot, like every other tool: back to Seleziona once the arrow is drawn.
    #expect(controller.tool == .select)
    controller.detach()
}

@MainActor
@Test func anArrowReleasedOverEmptyBoardDrawsNothing() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let a = controller.addStickyNote("a", at: .zero)
    controller.tool = .arrow
    controller.beginArrow(from: a)
    controller.updateArrow(translation: CGSize(width: 4000, height: 4000))

    // JSON Canvas has no dangling edge, so an arrow to nowhere is not written.
    #expect(controller.endArrow() == nil)
    #expect(controller.document.edges.isEmpty)
    #expect(controller.arrowSourceID == nil)
    controller.detach()
}

@MainActor
@Test func anArrowInFlightTracksThePointerWithoutTouchingTheDocument() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    let a = controller.addStickyNote("a", at: CGPoint(x: 100, y: 100))
    let source = try #require(controller.document.node(id: a))
    controller.beginArrow(from: a)
    controller.updateArrow(translation: CGSize(width: 60, height: 30))

    #expect(controller.arrowEndPoint == CGPoint(x: source.frame.midX + 60, y: source.frame.midY + 30))
    // Nothing is committed until the gesture ends, the same rule the drag follows.
    #expect(controller.document.edges.isEmpty)
    controller.endArrow()
    controller.detach()
}

@MainActor
@Test func anArrowFromACardThatIsGoneNeverStarts() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)

    controller.beginArrow(from: "inesistente")
    #expect(controller.arrowSourceID == nil)
    #expect(controller.arrowEndPoint == nil)
    controller.detach()
}

// MARK: - ADR-0020, Task 3: crop mode transitions

@MainActor
@Test func confirmingACropWritesExactlyOneKeyAndOneHistoryStep() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("foto.png", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)

    let node = try #require(controller.document.node(id: id))
    #expect(CanvasCrop.read(from: node) != nil)
    #expect(controller.canUndo)
    // Exactly one history step for the crop: undoing once removes the crop and nothing
    // else - the node itself, placed by `placeFile` before the crop, is still there.
    controller.undo()
    let afterUndo = try #require(controller.document.node(id: id))
    #expect(CanvasCrop.read(from: afterUndo) == nil)
    #expect(afterUndo.id == id)
    controller.detach()
}

@MainActor
@Test func cancellingACropWritesNothingAndLeavesUnsavedChangesAlone() throws {
    let root = try CanvasTemporaryRoot()
    let store = CanvasStore(root: root.url)
    let controller = WorkspaceController()
    controller.attach(to: store)
    // ADR-0025 §D4: `attach` opens nothing, so the root board must be created and
    // opened explicitly before `flushPendingSave` below has anywhere to write to.
    let board = try store.createBoard(named: root.url.lastPathComponent, in: "")
    controller.open(board: board)
    let id = controller.placeFile("foto.png", at: .zero)
    controller.flushPendingSave()
    #expect(!controller.hasUnsavedChanges)
    let undoDepthBefore = controller.canUndo

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: false)

    #expect(!controller.hasUnsavedChanges)
    #expect(controller.canUndo == undoDepthBefore)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) == nil)
    #expect(controller.croppingNodeID == nil)
    controller.detach()
}

@MainActor
@Test func croppingBackToTheWholeImageRemovesTheKeyRatherThanWritingAWholeRectangle() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("foto.png", at: .zero)

    // First crop it, confirmed, then drag every grip back out to the full image.
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) != nil)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .topLeft, translation: CGSize(width: -800, height: -400), lockAspect: false)
    controller.endCrop(confirm: true)

    let node = try #require(controller.document.node(id: id))
    #expect(CanvasCrop.read(from: node) == nil)
    #expect(node.unknown[CanvasCrop.key] == nil)
    controller.detach()
}

@MainActor
@Test func undoRestoresTheUncroppedNodeAndCancelsAnInFlightCrop() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("foto.png", at: .zero)
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) != nil)

    // A second, still-open crop gesture on the same node when undo fires - undo must
    // cancel it rather than let its stale draft overwrite the just-restored document.
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    #expect(controller.croppingNodeID == id)

    controller.undo()

    #expect(controller.croppingNodeID == nil)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) == nil)
    controller.detach()
}

@MainActor
@Test func navigatingAwayEndsAnOpenCropMode() throws {
    let root = try CanvasTemporaryRoot()
    try root.makeDirectory("Altra")
    let store = CanvasStore(root: root.url)
    let boardPath = try store.createBoard(named: "Altra", in: "Altra")
    let controller = WorkspaceController()
    controller.attach(to: store)
    // ADR-0025 §D4: `attach` opens nothing, so the root board must be created and
    // opened explicitly before `placeFile` below has anywhere to write to (PG-062).
    let rootBoard = try store.createBoard(named: root.url.lastPathComponent, in: "")
    controller.open(board: rootBoard)
    let id = controller.placeFile("foto.png", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    #expect(controller.croppingNodeID == id)

    controller.open(board: boardPath)
    #expect(controller.croppingNodeID == nil)
    controller.detach()
}

@MainActor
@Test func removingACropOutsideTheModeClearsTheKeyInOneMutation() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("foto.png", at: .zero)
    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    controller.updateCrop(handle: .bottomRight, translation: CGSize(width: -400, height: -200), lockAspect: false)
    controller.endCrop(confirm: true)
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) != nil)

    controller.removeCrop(nodeIDs: [id])
    #expect(CanvasCrop.read(from: try #require(controller.document.node(id: id))) == nil)

    // A no-op removal on a node that carries no crop must not touch history.
    let historyDepthBefore = controller.canUndo
    controller.removeCrop(nodeIDs: [id])
    #expect(controller.canUndo == historyDepthBefore)
    controller.detach()
}

@MainActor
@Test func aNonCroppableFileNeverEntersCropMode() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let id = controller.placeFile("documento.pdf", at: .zero)

    controller.beginCrop(nodeID: id, drawnSize: CGSize(width: 800, height: 400))
    #expect(controller.croppingNodeID == nil)
    controller.detach()
}
