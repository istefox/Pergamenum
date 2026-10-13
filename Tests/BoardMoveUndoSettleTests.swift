import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0091 implementation notes: the undo of a batch move rebuilds a `.board` ref that
// no Workspace browser row built, so `WorkspaceView+FolderVerbs`' `settleForVerb()` never ran for
// it. `VaultController.attemptInverse` runs that settle itself, before the file moves back: a
// pending edit on the open board is written into the file first, and a conflicted board refuses
// the step with ADR-0060's line and moves nothing.

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

private func exists(_ root: URL, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

/// «Bacheca» created in `Progetti`, moved into `Archivio` with `manager` registered, then opened
/// at the path it landed on, as `WorkspaceView+FolderVerbs`' `followMove` would. Answers the
/// path it came from and the path it sits at.
@MainActor
private func movedBoard(
    _ root: URL, in controller: VaultController, undo manager: UndoManager
) async throws -> (from: String, to: String) {
    try FileManager.default.createDirectory(
        at: root.appending(path: "Archivio", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    let from = try CanvasStore(root: root).createBoard(named: "Bacheca", in: "Progetti")
    let outcome = await controller.moveItems(
        [VaultItemRef(path: from, kind: .board)], into: "Archivio", undo: manager
    )
    try #require(outcome.didMove)
    let to = "Archivio/Bacheca.canvas"
    controller.openBoard.open(board: to)
    return (from, to)
}

@MainActor
@Test func undoingABoardMoveWritesTheOpenBoardsPendingEditBeforeTheFileMoves() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let manager = UndoManager()
    let (from, to) = try await movedBoard(root, in: controller, undo: manager)
    let board = controller.openBoard
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)

    manager.undo()

    // The settle is synchronous, inside `undo()`, before the move's own task runs.
    #expect(board.saveState == .saved)
    try await waitUntil { exists(root, from) && !exists(root, to) && manager.canRedo }
    let restored = try CanvasStore(root: root).load(board: from)
    #expect(restored.node(id: id) != nil)
    board.detach()
    controller.close()
}

@MainActor
@Test func undoingABoardMoveIsRefusedWhileTheOpenBoardIsConflicted() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let manager = UndoManager()
    let (from, to) = try await movedBoard(root, in: controller, undo: manager)
    let board = controller.openBoard
    _ = board.addStickyNote("nota", at: .zero)
    let externalStore = CanvasStore(root: root)
    var diverged = try externalStore.load(board: to)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: to)
    board.flushPendingSave()
    #expect(isConflicted(board))
    let problems = controller.problems.count

    manager.undo()

    // Refused before anything is registered or moved: no redo is offered for an undo that
    // never happened (ADR-0026 §D8), and the conflict stays readable where it is.
    #expect(!manager.canRedo)
    #expect(exists(root, to))
    #expect(!exists(root, from))
    #expect(isConflicted(board))
    #expect(controller.problems.dropFirst(problems).contains {
        $0.contains("ha un conflitto di salvataggio non risolto: resta aperta")
    })
    board.detach()
    controller.close()
}

// Review sweep (2026-10-10): the settle is asked of the board the step carries, a flush that
// fails refuses the step, and the undo follows the open board back as the forward door does.

/// G2's frozen board sentence (2026-10-08), the one `folderRefusal` gives, spelled out once.
private let boardRefusal =
    "risolvi le modifiche non salvate della board «Bacheca» nel Workspace prima di rinominare o eliminare la cartella"

@MainActor
@Test func undoingABoardMoveIsRefusedWhenTheOpenBoardsFlushFails() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let manager = UndoManager()
    let (from, to) = try await movedBoard(root, in: controller, undo: manager)
    let board = controller.openBoard
    _ = board.addStickyNote("pendente", at: .zero)

    try await withReadOnlyFolder(root, "Archivio") {
        manager.undo()

        // The settle lets a failed write through, leaving the board pending; the step is then
        // refused with the board's sentence before anything is registered or moved.
        #expect(board.saveState == .pending)
        #expect(!manager.canRedo)
        #expect(controller.problems.contains(boardRefusal))
    }
    #expect(exists(root, to))
    #expect(!exists(root, from))
    #expect(!controller.problems.contains { $0.hasPrefix("annulla spostamento") })
    board.detach()
    controller.close()
}

@MainActor
@Test func undoingAFolderMoveFlushesTheOpenBoardInsideItAndFollowsItBack() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let manager = UndoManager()
    try FileManager.default.createDirectory(
        at: root.appending(path: "Archivio", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    _ = try CanvasStore(root: root).createBoard(named: "Bacheca", in: "Progetti")
    let outcome = await controller.moveItems(
        [VaultItemRef(path: "Progetti", kind: .folder)], into: "Archivio", undo: manager
    )
    try #require(outcome.didMove)
    let board = controller.openBoard
    board.open(board: "Archivio/Progetti/Bacheca.canvas")
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)

    manager.undo()

    // Flushed by the settle rather than refused by the folder guard.
    #expect(board.saveState == .saved)
    #expect(!controller.problems.contains(boardRefusal))
    try await waitUntil {
        exists(root, "Progetti/Bacheca.canvas") && !exists(root, "Archivio/Progetti") && manager.canRedo
    }
    let restored = try CanvasStore(root: root).load(board: "Progetti/Bacheca.canvas")
    #expect(restored.node(id: id) != nil)
    try await waitUntil { board.board == "Progetti/Bacheca.canvas" }
    #expect(board.isShowingBoard)
    board.detach()
    controller.close()
}

@MainActor
@Test func anUnrelatedConflictedBoardDoesNotConsumeTheUndoOfABoardMove() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let manager = UndoManager()
    let (from, to) = try await movedBoard(root, in: controller, undo: manager)
    // Another board, «Altra» at the vault root, opened and refused into `.conflicted`.
    let other = try CanvasStore(root: root).createBoard(named: "Altra", in: "")
    let board = controller.openBoard
    board.open(board: other)
    _ = board.addStickyNote("nota", at: .zero)
    let externalStore = CanvasStore(root: root)
    var diverged = try externalStore.load(board: other)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: other)
    board.flushPendingSave()
    #expect(isConflicted(board))
    let problems = controller.problems.count

    manager.undo()

    // «Bacheca» goes back; «Altra» is not asked, stays conflicted and on screen.
    try await waitUntil { exists(root, from) && !exists(root, to) && manager.canRedo }
    #expect(isConflicted(board))
    #expect(board.board == other)
    #expect(!controller.problems.dropFirst(problems).contains {
        $0.contains("ha un conflitto di salvataggio non risolto")
    })
    board.detach()
    controller.close()
}

@MainActor
@Test func undoAndRedoOfABoardMoveFollowTheOpenBoard() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let manager = UndoManager()
    let (from, to) = try await movedBoard(root, in: controller, undo: manager)
    let board = controller.openBoard

    manager.undo()
    try await waitUntil { exists(root, from) && manager.canRedo && board.board == from }
    #expect(board.isShowingBoard)

    manager.redo()
    try await waitUntil { exists(root, to) && manager.canUndo && board.board == to }
    #expect(board.isShowingBoard)
    board.detach()
    controller.close()
}
