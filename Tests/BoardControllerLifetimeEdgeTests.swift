import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0092 §D2, §D3 and §D9: the edges of the vault-owned board controller found in
// review, moved out of `BoardControllerLifetimeTests` (file_length) with their bodies unchanged:
// a reopened vault re-points the kept board's thumbnails, a vault switch disarms the drawing
// tool, a draft open at a pane leave is written, and a canvas route is refused while a kept board
// is conflicted.
//
// Not hosted tests, like `BoardControllerLifetimeTests`: they work on `controller.openBoard`
// directly and stand for the pane with `enterPane()` and `leavePane()`.

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

// MARK: §D2: what a reopen and a switch do to the kept controller

@MainActor
@Test func reopeningTheOpenVaultPointsTheKeptBoardAtTheNewThumbnailCache() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    let previous = try #require(controller.thumbnails)
    #expect(board.thumbnails === previous)

    await controller.open(rootA)

    #expect(controller.thumbnails !== previous)
    #expect(board.thumbnails === controller.thumbnails)
    #expect(isConflicted(board))
    #expect(board.board == path)
    board.detach()
    controller.close()
}

@MainActor
@Test func aVaultSwitchDisarmsTheDrawingTool() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    board.tool = .drawing
    board.isToolLocked = true

    let switched = await controller.switchVault(to: rootB) { _ in .cancel }

    #expect(switched)
    #expect(board.store?.root.vaultKey == rootB.vaultKey)
    #expect(board.tool == .select)
    #expect(!board.isToolLocked)
    controller.close()
}

// MARK: §D3: a draft open at a leave

@MainActor
@Test func aTextDraftOpenAtALeaveIsCommittedAndWritten() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("prima", at: .zero)
    board.flushPendingSave()
    board.beginTextEdit(nodeID: id)
    board.editingTextDraft = "scritta al cambio di pane"
    // A second appearance keeps the board, so `select(nil)`'s own settle never runs: only
    // `leavePane()`'s settle and flush can carry the draft to the file.
    board.enterPane()
    board.enterPane()

    board.leavePane()

    #expect(board.board == path)
    #expect(board.editingTextNodeID == nil)
    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: id)?.kind == .text("scritta al cambio di pane"))
    board.leavePane()
    controller.close()
}

// MARK: §D9: a route while a kept board is conflicted

@MainActor
@Test func aCanvasRouteToAnotherBoardWhileAKeptBoardIsConflictedIsRefusedWithItsLine() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    let other = try CanvasStore(root: rootA).createBoard(named: "Altra", in: "")
    board.enterPane()
    board.leavePane()
    // A card the kept board has, named by a route to the other board.
    let keptCard = try #require(board.document.nodes.first?.id)
    board.selection = []
    let problems = controller.problems.count

    let missingKept = board.openRoute((path: other, nodeID: keptCard), viewport: .zero)
    let missingAbsent = board.openRoute((path: other, nodeID: "assente"), viewport: .zero)

    // ADR-0092 §D9: refused with ADR-0060's line, and nothing is resolved on the kept board.
    #expect(missingKept == nil)
    #expect(missingAbsent == nil)
    #expect(board.selection.isEmpty)
    #expect(board.current == .board(path: path))
    #expect(isConflicted(board))
    let added = Array(controller.problems.dropFirst(problems))
    #expect(added.count == 2)
    #expect(added.allSatisfy { $0.contains("ha un conflitto di salvataggio non risolto: resta aperta") })
    board.detach()
    controller.close()
}
