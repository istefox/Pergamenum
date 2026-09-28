import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0066 §D6 point 9 (PG-287): note creation and sidebar moves read the open board before
// their `await` and act after it only if that board is still the one on screen (ADR-0043 §D7).
// The views keep the "read before"; `placeCreatedNote` and `followMove` are the "ask again
// after", driven here directly. Each test that switches the board first is red without the
// `isStillShowing` guard: the card lands on the other board, or the move drags the person back.

/// Two boards in `root`, `A/A.canvas` and `B/B.canvas`, and a controller attached to their store
/// with A open. `root` stays with the caller: `CanvasTemporaryRoot` is noncopyable.
@MainActor
private struct TwoBoards {
    let store: CanvasStore
    let controller: WorkspaceController
    let a: String
    let b: String
}

@MainActor
private func twoBoards(in root: borrowing CanvasTemporaryRoot) throws -> TwoBoards {
    try root.makeDirectory("A")
    try root.makeDirectory("B")
    let store = CanvasStore(root: root.url)
    let a = try store.createBoard(named: "A", in: "A")
    let b = try store.createBoard(named: "B", in: "B")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: a)
    return TwoBoards(store: store, controller: controller, a: a, b: b)
}

@MainActor
struct WorkspaceAfterAwaitTests {
    // MARK: - placeCreatedNote

    @Test func aNoteCreatedOnTheBoardStillOpenGetsItsCard() throws {
        let root = try CanvasTemporaryRoot()
        let fixture = try twoBoards(in: root)
        let controller = fixture.controller
        defer { controller.detach() }

        let id = controller.placeCreatedNote("A/Nota.md", title: "Nota", at: .zero, openedOn: fixture.a)

        let node = try #require(id.flatMap { controller.document.node(id: $0) })
        guard case .file(let path, _) = node.kind else {
            Issue.record("expected a file card")
            return
        }
        #expect(path == "A/Nota.md")
    }

    @Test func aNoteCreatedBeforeAnotherBoardOpenedIsNotPlacedOnIt() throws {
        let root = try CanvasTemporaryRoot()
        let fixture = try twoBoards(in: root)
        let controller = fixture.controller
        defer { controller.detach() }

        controller.open(board: fixture.b)
        let id = controller.placeCreatedNote("A/Nota.md", title: "Nota", at: .zero, openedOn: fixture.a)

        #expect(id == nil)
        #expect(controller.board == fixture.b)
        #expect(controller.document.nodes.isEmpty)
        #expect(try fixture.store.load(board: fixture.a).nodes.isEmpty)
    }

    @Test func aNoteCreatedBeforeTheBoardWasLeftForAFolderIsNotPlaced() throws {
        let root = try CanvasTemporaryRoot()
        let fixture = try twoBoards(in: root)
        let controller = fixture.controller
        defer { controller.detach() }

        controller.select(nil)
        let id = controller.placeCreatedNote("A/Nota.md", title: "Nota", at: .zero, openedOn: fixture.a)

        #expect(id == nil)
        #expect(!controller.isShowingBoard)
        #expect(try fixture.store.load(board: fixture.a).nodes.isEmpty)
    }

    // MARK: - followMove

    @Test func aMoveCarryingTheOpenBoardReopensItWhereItLanded() throws {
        let root = try CanvasTemporaryRoot()
        let fixture = try twoBoards(in: root)
        let controller = fixture.controller
        defer { controller.detach() }
        try root.makeDirectory("Z")
        try FileManager.default.moveItem(
            at: root.url.appending(path: "A", directoryHint: .isDirectory),
            to: root.url.appending(path: "Z/A", directoryHint: .isDirectory)
        )
        let move = VaultMove(item: VaultItemRef(path: "A", kind: .folder), from: "", to: "Z")

        let opened = controller.followMove(from: fixture.a, moves: [move])

        #expect(opened == "Z/A/A.canvas")
        #expect(controller.board == "Z/A/A.canvas")
        #expect(controller.isShowingBoard)
    }

    @Test func aMoveFinishingAfterAnotherBoardOpenedLeavesThePersonWhereTheyWent() throws {
        let root = try CanvasTemporaryRoot()
        let fixture = try twoBoards(in: root)
        let controller = fixture.controller
        defer { controller.detach() }
        try root.makeDirectory("Z")
        try FileManager.default.moveItem(
            at: root.url.appending(path: "A", directoryHint: .isDirectory),
            to: root.url.appending(path: "Z/A", directoryHint: .isDirectory)
        )
        let move = VaultMove(item: VaultItemRef(path: "A", kind: .folder), from: "", to: "Z")

        controller.open(board: fixture.b)
        let opened = controller.followMove(from: fixture.a, moves: [move])

        #expect(opened == nil)
        #expect(controller.board == fixture.b)
    }

    @Test func aMoveNotCarryingTheOpenBoardReopensNothing() throws {
        let root = try CanvasTemporaryRoot()
        let fixture = try twoBoards(in: root)
        let controller = fixture.controller
        defer { controller.detach() }
        try root.makeDirectory("Z")
        let move = VaultMove(item: VaultItemRef(path: "B", kind: .folder), from: "", to: "Z")

        let opened = controller.followMove(from: fixture.a, moves: [move])

        #expect(opened == nil)
        #expect(controller.board == fixture.a)
    }
}
