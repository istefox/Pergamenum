import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0095 §D1-§D4, plan Task 1 (R-01, R-02, R-03, R-04, R-07, R-08): the Workspace
// board controller is created with the `VaultController` and owned by it, bound to the open
// vault whether or not the Workspace pane is mounted, and a pane leave settles it by state:
// saved is released, pending is flushed and then judged, conflicted is kept.
//
// Not hosted tests: they work on `controller.openBoard` directly and stand for the pane's
// appearance and disappearance with `enterPane()` and `leavePane()`, so `addStickyNote` is
// allowed. The hosted counterparts are in `QuitBoardLifetimeHostedTests`.

/// Saves a document with one more node through a second store, the way another writer would.
private func divergeOnDisk(_ root: URL, board path: String) throws {
    let externalStore = CanvasStore(root: root)
    var diverged = try externalStore.load(board: path)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: path)
}

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

// MARK: R-01: one owner

@MainActor
@Test func theBoardControllerIsCreatedWithTheVaultControllerAndNeverReplaced() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    let first = controller.openBoard

    await controller.open(rootA)
    #expect(controller.openBoard === first)
    controller.openBoard.enterPane()
    controller.openBoard.leavePane()
    controller.openBoard.enterPane()
    #expect(controller.openBoard === first)
    await controller.open(rootB)
    #expect(controller.openBoard === first)
    controller.close()
    #expect(controller.openBoard === first)
}

// MARK: R-07: bound to the vault, pane or no pane

@MainActor
@Test func openingAVaultBindsTheBoardToItsStoreWithNoBoardOpen() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let board = controller.openBoard

    // `enterPane()` is never called: the pane was never mounted.
    #expect(board.store?.root.vaultKey == rootA.vaultKey)
    #expect(board.board == "")
    #expect(board.saveState == .saved)
    #expect(controller.openBoardPath == nil)
    controller.close()
}

@MainActor
@Test func openingAnotherVaultRebindsWithNoBoardAndNothingFromTheOld() async throws {
    let a = try TemporaryVault()
    let b = try TemporaryVault()
    let rootA = a.root
    let rootB = b.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)

    // The mechanism, not `switchVault`: this isolates §D2 from the question.
    await controller.open(rootB)

    #expect(board.store?.root.vaultKey == rootB.vaultKey)
    #expect(board.board == "")
    #expect(board.document == CanvasDocument.empty)
    #expect(board.saveState == .saved)
    #expect(!board.canUndo)
    #expect(controller.openBoardPath == nil)
    // A's file holds the card: the rebind flushed it before letting the board go.
    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: id) != nil)
    // Nothing named after A's board exists in B.
    #expect(!FileManager.default.fileExists(atPath: rootB.appending(path: path).path(percentEncoded: false)))
    controller.close()
}

@MainActor
@Test func reopeningTheOpenVaultLeavesTheBoardUntouched() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    let storeRoot = board.store?.root

    await controller.open(rootA)

    #expect(isConflicted(board))
    #expect(board.board == path)
    // `CanvasStore` is a value: the same store is the one still rooted where it was, not rebuilt.
    #expect(board.store?.root == storeRoot)
    #expect(board.quitConflict != nil)
    board.detach()
    controller.close()
}

@MainActor
@Test func closeDetachesTheBoard() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    controller.openBoard.open(board: path)
    #expect(controller.openBoard.board == path)

    controller.close()

    #expect(controller.openBoard.store == nil)
    #expect(controller.openBoard.board == "")
}

// MARK: R-03: a pane leave settles by state

@MainActor
@Test func aSavedBoardIsReleasedOnLeave() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    board.enterPane()
    #expect(board.isShowingBoard)
    let problems = controller.problems.count

    board.leavePane()

    #expect(board.board == "")
    #expect(board.current == nil)
    #expect(!board.isShowingBoard)
    #expect(board.store != nil)
    #expect(controller.problems.count == problems)
    controller.close()
}

@MainActor
@Test func aLockedToolDoesNotSurviveAReleasingLeave() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    board.enterPane()
    board.tool = .drawing
    board.isToolLocked = true

    board.leavePane()

    #expect(board.board == "")
    #expect(board.tool == .select)
    #expect(!board.isToolLocked)
    controller.close()
}

@MainActor
@Test func aKeptBoardKeepsItsLockedToolOnLeave() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    board.enterPane()
    board.tool = .drawing
    board.isToolLocked = true

    board.leavePane()

    #expect(board.board == path)
    #expect(board.tool == .drawing)
    #expect(board.isToolLocked)
    board.detach()
    controller.close()
}

@MainActor
@Test func aPendingBoardIsFlushedOnLeaveAndThenReleased() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)
    board.enterPane()

    board.leavePane()

    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: id) != nil)
    #expect(board.board == "")
    #expect(board.saveState == .saved)
    controller.close()
}

@MainActor
@Test func aPendingBoardWhoseFlushIsRefusedOnLeaveIsKeptConflicted() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    try divergeOnDisk(rootA, board: path)
    board.enterPane()

    board.leavePane()

    #expect(isConflicted(board))
    #expect(board.board == path)
    #expect(board.document.node(id: id) != nil)
    board.detach()
    controller.close()
}

@MainActor
@Test func aPendingBoardWhoseWriteFailsIsKeptOnLeave() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "Progetti")
    let board = controller.openBoard
    board.open(board: path)
    _ = board.addStickyNote("pendente", at: .zero)
    board.enterPane()

    try await withReadOnlyFolder(rootA, "Progetti") {
        board.leavePane()

        // The write really was attempted and failed: it left its line, and the state is the
        // truth (an indicator still showing unsaved changes), not a conflict.
        #expect(controller.problems.contains { $0.contains("salvataggio di \(path)") })
        #expect(board.saveState == .pending)
        #expect(board.board == path)
    }
    board.detach()
    controller.close()
}

// MARK: R-02: a conflicted board is kept

@MainActor
@Test func aConflictedBoardKeepsItsDocumentOriginAndStateAcrossALeave() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let (board, path) = try quitConflictedBoard(a, in: controller)
    let document = board.document
    let origin = board.origin
    let state = board.saveState
    let problems = controller.problems.count

    board.enterPane()
    board.leavePane()
    board.enterPane()

    #expect(board.board == path)
    #expect(board.document == document)
    #expect(board.origin == origin)
    #expect(board.saveState == state)
    #expect(board.quitConflict != nil)
    #expect(controller.problems.count == problems)
    board.detach()
    controller.close()
}

// MARK: R-04: the presenter count

@MainActor
@Test func aReentryBeforeTheLeaveDoesNotReleaseTheBoard() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    board.enterPane()
    // The new appearance arrives before the old one disappears.
    board.enterPane()

    board.leavePane()

    let onDisk = try CanvasStore(root: rootA).load(board: path)
    #expect(onDisk.node(id: id) != nil)
    #expect(board.board == path)

    board.leavePane()

    #expect(board.board == "")
    controller.close()
}

@MainActor
@Test func aLeaveWithNoAppearanceLeftNeverCountsBelowZero() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard

    // A leave with no enter, and no board open to release.
    board.leavePane()

    board.open(board: path)
    #expect(board.isShowingBoard)
    board.enterPane()
    board.leavePane()

    // Released, so the count was clamped at zero by the first leave.
    #expect(board.board == "")
    #expect(!board.isShowingBoard)
    controller.close()
}

// MARK: ADR-0095 §D2: detach is idempotent and reports a loss once

@MainActor
@Test func aSecondDetachRecordsNothing() async throws {
    let a = try TemporaryVault()
    let controller = try await quitController(a)
    let (board, _) = try quitConflictedBoard(a, in: controller)
    let before = controller.problems.count

    board.detach()

    #expect(controller.problems.count == before + 1)
    #expect(board.saveState == .saved)

    board.detach()

    #expect(controller.problems.count == before + 1)
    controller.close()
}

@MainActor
@Test func detachRecordsTheLossWhenItsOwnFlushIsRefused() async throws {
    let a = try TemporaryVault()
    let rootA = a.root
    let controller = try await quitController(a)
    let path = try CanvasStore(root: rootA).createBoard(named: "Piano", in: "")
    let board = controller.openBoard
    board.open(board: path)
    _ = board.addStickyNote("pendente", at: .zero)
    try divergeOnDisk(rootA, board: path)
    let before = controller.problems.count

    board.detach()

    let added = Array(controller.problems.dropFirst(before))
    #expect(added.contains { $0.contains(VaultWriteRefusal.movedOn(path).description) })
    #expect(added.contains { $0.contains("aveva un conflitto di salvataggio non risolto") })
    controller.close()
}
