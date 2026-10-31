import Foundation
import Testing
@testable import Pergamenum

// PG-437: a leave that flushes a pending edit can itself be refused by a diverged file and enter
// `.conflicted`. `load(board:)` and `select(_:)`'s folder/nil branch used to check
// `refusesToLeaveConflictedBoard()` only before that flush, so the conflict the flush raised was
// dropped on the spot: `board == ""`, the document replaced, `.conflicted` stranded with nothing
// to resolve. Each leave path below starts from a board whose edit is still *pending* (not yet
// flushed) over a file another writer has already diverged, so only the leave's own flush can
// raise the conflict. Contrast `quitConflictedBoard`, which flushes by hand first.

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

/// «Bacheca» opened on `controller.openBoard` with one unflushed sticky note, over a file another
/// store has since diverged. Answers the board, its path, the sticky's id and the document as it
/// stood in memory. `saveState` is `.pending` on return: the conflict has not happened yet.
@MainActor
private func pendingOverDivergedFile(
    _ vault: borrowing TemporaryVault, in controller: VaultController
) throws -> (board: WorkspaceController, path: String, sticky: String, document: CanvasDocument) {
    let path = try CanvasStore(root: vault.root).createBoard(named: "Bacheca", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let sticky = board.addStickyNote("mia", at: .zero)

    let external = CanvasStore(root: vault.root)
    var diverged = try external.load(board: path)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try external.save(diverged, board: path)

    #expect(board.saveState == .pending)
    return (board, path, sticky, board.document)
}

/// Everything a refused leave must leave exactly where it was.
@MainActor
private func expectBoardKept(
    _ board: WorkspaceController, path: String, document: CanvasDocument, problems: [String]
) {
    #expect(isConflicted(board))
    #expect(board.board == path)
    #expect(board.current == .board(path: path))
    #expect(board.document == document)
    // The refusal is reported, not silent: the conflict's own line plus the leave's.
    #expect(problems.contains { $0.contains("ha un conflitto di salvataggio non risolto: resta aperta") })
}

@MainActor
@Test func selectingAFolderWhoseFlushRaisesAConflictKeepsTheBoardOnScreen() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let (board, path, _, document) = try pendingOverDivergedFile(a, in: controller)
    let before = controller.problems.count

    board.select(.folder("Progetti"))

    expectBoardKept(
        board, path: path, document: document, problems: Array(controller.problems.dropFirst(before))
    )
    board.detach()
    controller.close()
}

@MainActor
@Test func selectingNothingWhoseFlushRaisesAConflictKeepsTheBoardOnScreen() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let (board, path, _, document) = try pendingOverDivergedFile(a, in: controller)
    let before = controller.problems.count

    board.select(nil)

    expectBoardKept(
        board, path: path, document: document, problems: Array(controller.problems.dropFirst(before))
    )
    board.detach()
    controller.close()
}

@MainActor
@Test func openingAnotherBoardWhoseLeaveFlushRaisesAConflictKeepsTheFirstOne() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path, _, document) = try pendingOverDivergedFile(a, in: controller)
    let other = try CanvasStore(root: rootA).createBoard(named: "Altra", in: "")
    let before = controller.problems.count

    board.open(board: other)

    expectBoardKept(
        board, path: path, document: document, problems: Array(controller.problems.dropFirst(before))
    )
    board.detach()
    controller.close()
}

@MainActor
@Test func selectingAnotherBoardWhoseLeaveFlushRaisesAConflictKeepsTheFirstOne() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path, _, document) = try pendingOverDivergedFile(a, in: controller)
    let other = try CanvasStore(root: rootA).createBoard(named: "Altra", in: "")

    board.select(.board(path: other))

    #expect(isConflicted(board))
    #expect(board.board == path)
    #expect(board.current == .board(path: path))
    #expect(board.document == document)
    board.detach()
    controller.close()
}

// MARK: The conflict a refused leave keeps is still resolvable

@MainActor
@Test func keepingTheLocalBoardAfterARefusedLeaveWritesItAndUnblocksTheLeave() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path, sticky, _) = try pendingOverDivergedFile(a, in: controller)

    board.select(.folder("Progetti"))
    #expect(isConflicted(board))
    board.keepLocalBoard()

    // «Mantieni»: the person's version wins on disk and the board is saved again.
    #expect(board.saveState == .saved)
    #expect(board.board == path)
    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: sticky) != nil)
    #expect(onDisk.node(id: "external") == nil)

    board.select(.folder("Progetti"))
    #expect(board.board == "")
    #expect(board.current == .folder("Progetti"))
    #expect(board.saveState == .saved)
    controller.close()
}

@MainActor
@Test func reloadingFromDiskAfterARefusedLeaveAdoptsTheFileAndUnblocksTheLeave() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let (board, path, sticky, _) = try pendingOverDivergedFile(a, in: controller)

    board.select(nil)
    #expect(isConflicted(board))
    board.reloadBoardFromDisk()

    // «Ricarica»: the other writer's version replaces the local edit.
    #expect(board.saveState == .saved)
    #expect(board.board == path)
    #expect(board.document.node(id: "external") != nil)
    #expect(board.document.node(id: sticky) == nil)

    board.select(nil)
    #expect(board.board == "")
    #expect(board.current == nil)
    #expect(board.saveState == .saved)
    controller.close()
}

// MARK: (coverage) the unchanged leaves still go through

@MainActor
@Test func aPendingEditThatFlushesCleanlyIsStillWrittenAndTheLeaveStillHappens() async throws {
    // (coverage) The re-check after the flush must not refuse a leave whose flush succeeded.
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Bacheca", in: "")
    let other = try CanvasStore(root: rootA).createBoard(named: "Altra", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let sticky = board.addStickyNote("mia", at: .zero)
    #expect(board.saveState == .pending)

    board.open(board: other)

    #expect(board.board == other)
    #expect(board.current == .board(path: other))
    #expect(board.saveState == .saved)
    #expect(try CanvasStore(root: rootA).load(board: path).node(id: sticky) != nil)

    board.select(.folder("Progetti"))
    #expect(board.board == "")
    #expect(board.current == .folder("Progetti"))
    #expect(board.saveState == .saved)
    controller.close()
}
