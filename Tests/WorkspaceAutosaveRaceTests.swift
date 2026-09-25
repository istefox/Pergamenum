import Foundation
import Testing
@testable import Pergamenum

// ADR-0054 (plan `docs/plans/pg-213-workspace-autosave-race.md`, Tasks 4 and 5): the
// autosave refuses on a stale write, reconciles against the base it kept, retries once,
// and - when reconciliation cannot decide - says so on the board instead of clobbering or
// discarding either side. Every race here is produced by literally being the second
// writer in a synchronous test body (ADR-0046 §D11), never a sleep and never a competing
// `Task`.

/// Forces a `.conflicted` board with a known sticky note in memory and a known external
/// node on disk, so the Task 5 tests below do not each repeat the same five lines.
@MainActor
private func conflictedBoard(
    vaultController: VaultController, root: URL
) throws -> (controller: WorkspaceController, store: CanvasStore, board: String, stickyID: String) {
    let store = CanvasStore(root: root)
    let boardPath = try store.createBoard(named: "board", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store, vault: vaultController)
    controller.open(board: boardPath)

    let stickyID = controller.addStickyNote("nota", at: .zero)

    // A diverged external change: a node added, not a pure `.file` repoint - the one
    // shape `CanvasDocument.reconcile` cannot adopt automatically.
    let externalStore = CanvasStore(root: root)
    var diverged = try externalStore.load(board: boardPath)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: boardPath)

    controller.flushPendingSave()
    guard case .conflicted = controller.saveState else {
        Issue.record("setup expected .conflicted, got \(controller.saveState)")
        throw CanvasStore.StoreError.missing(boardPath)
    }
    return (controller, store, boardPath, stickyID)
}

// MARK: - Task 4 (R-01, R-02, R-06)

@MainActor
@Test func directionARepointThenEditReconcilesBothOntoTheFile() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let externalStore = CanvasStore(root: root.url)

    let fileNodeID = controller.placeFile("old.md", at: .zero)
    controller.flushPendingSave()

    let stickyID = controller.addStickyNote("nota", at: CGPoint(x: 200, y: 0))
    #expect(controller.saveState == .pending)

    // Exactly the bytes `BoardFileOperations.renameBoard` would have written: the file
    // node repointed, nothing else.
    var repointed = try externalStore.load(board: boardPath)
    let index = try #require(repointed.nodes.firstIndex(where: { $0.id == fileNodeID }))
    repointed.nodes[index].kind = .file(path: "new.md", subpath: nil)
    try externalStore.save(repointed, board: boardPath)

    controller.flushPendingSave()

    #expect(controller.saveState == .saved)
    let onDisk = try externalStore.load(board: boardPath)
    guard case .file(let path, _) = onDisk.node(id: fileNodeID)?.kind else {
        Issue.record("expected the file node to survive with its repointed path")
        return
    }
    #expect(path == "new.md")
    #expect(onDisk.node(id: stickyID) != nil)
    controller.detach()
}

@MainActor
@Test func directionARepointBeforeTheEditIsStillReconciledOnTheNextSave() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let externalStore = CanvasStore(root: root.url)

    let fileNodeID = controller.placeFile("old.md", at: .zero)
    controller.flushPendingSave()

    // The external write lands before the next edit, the "stale forever" case §D1.1
    // names: nothing tells the open board its file moved on.
    var repointed = try externalStore.load(board: boardPath)
    let index = try #require(repointed.nodes.firstIndex(where: { $0.id == fileNodeID }))
    repointed.nodes[index].kind = .file(path: "new.md", subpath: nil)
    try externalStore.save(repointed, board: boardPath)

    let stickyID = controller.addStickyNote("nota", at: CGPoint(x: 200, y: 0))
    controller.flushPendingSave()

    #expect(controller.saveState == .saved)
    let onDisk = try externalStore.load(board: boardPath)
    guard case .file(let path, _) = onDisk.node(id: fileNodeID)?.kind else {
        Issue.record("expected the file node to survive with its repointed path")
        return
    }
    #expect(path == "new.md")
    #expect(onDisk.node(id: stickyID) != nil)
    controller.detach()
}

@MainActor
@Test func anExternalWriteThatAddsANodeLeavesTheFileByteIdenticalAndDocumentIntact() throws {
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let externalStore = CanvasStore(root: root.url)

    let stickyID = controller.addStickyNote("nota", at: .zero)
    #expect(controller.saveState == .pending)

    var withAddedNode = try externalStore.load(board: boardPath)
    withAddedNode.nodes.append(CanvasNode(
        id: "external", kind: .text("aggiunto da fuori"), x: 500, y: 500, width: 200, height: 100
    ))
    try externalStore.save(withAddedNode, board: boardPath)
    let diskBytesBefore = try Data(contentsOf: externalStore.url(forBoard: boardPath))

    controller.flushPendingSave()

    let diskBytesAfter = try Data(contentsOf: externalStore.url(forBoard: boardPath))
    #expect(diskBytesAfter == diskBytesBefore)
    #expect(controller.document.node(id: stickyID) != nil)
    guard case .conflicted = controller.saveState else {
        Issue.record("expected .conflicted")
        return
    }
    controller.detach()
}

@MainActor
@Test func expectingIsNotPassedWhenOriginIsNone() throws {
    // `attach()` alone leaves `origin == .none` with nothing open; reproduced here with
    // a board already open by handing `replaceDocument` the same origin `attach()`
    // itself would - `replaceDocument` is the module-wide door ADR-0054 §D5's conflict
    // verbs already use from a different file, not a test-only backdoor.
    let root = try CanvasTemporaryRoot()
    let controller = try openedWorkspaceController(rootURL: root.url)
    let boardPath = controller.board
    let externalStore = CanvasStore(root: root.url)

    controller.replaceDocument(controller.document, origin: .none)

    let stickyID = controller.addStickyNote("nota", at: .zero)

    // If `expecting` were still passed, this concurrent-looking external write would
    // make the save below refuse.
    var external = try externalStore.load(board: boardPath)
    external.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(external, board: boardPath)

    controller.flushPendingSave()

    #expect(controller.saveState == .saved)
    let onDisk = try externalStore.load(board: boardPath)
    #expect(onDisk.node(id: stickyID) != nil)
    controller.detach()
}

// Not implemented: "the retry happens at most once: a second external write between the
// reconcile and the retry leaves the board conflicted, not looping." `attemptSave`'s
// retry reads its `expecting` hash and performs the guarded write with no `await` in
// between (ADR-0054 §D3's in-process atomicity argument, `save()` itself is not `async`
// either) - there is no suspension point a synchronous, non-concurrent test body can land
// a second writer inside, and R-10/ADR-0046 §D11 rule out a competing `Task` or a sleep to
// force one. The guarded branch (`guard allowingRetry else { enterConflicted(...) }` in
// `WorkspaceController.swift`) is inspectable by reading the code; it is not independently
// exercised by a test in this file.

// MARK: - Task 5 (R-04)

@MainActor
@Test func aDivergedSaveSetsConflictedAndRecordsExactlyOneProblemNotOnePerEdit() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, _, _, stickyID) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    #expect(vaultController.problems.count == 1)

    // A further edit while conflicted must not add a second problem.
    _ = controller.addStickyNote("altra", at: CGPoint(x: 50, y: 50))
    controller.flushPendingSave()
    #expect(vaultController.problems.count == 1)
    #expect(controller.document.node(id: stickyID) != nil)

    controller.detach()
    vaultController.close()
}

@MainActor
@Test func whileConflictedAnEditDoesNotWriteToDisk() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, store, boardPath, _) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    let diskBytesAtConflict = try Data(contentsOf: store.url(forBoard: boardPath))

    _ = controller.addStickyNote("altra", at: CGPoint(x: 50, y: 50))
    controller.flushPendingSave()

    let diskBytesAfter = try Data(contentsOf: store.url(forBoard: boardPath))
    #expect(diskBytesAfter == diskBytesAtConflict)

    controller.detach()
    vaultController.close()
}

@MainActor
@Test func keepLocalBoardWritesTheInMemoryDocumentAndReturnsToSaved() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, store, boardPath, stickyID) = try conflictedBoard(
        vaultController: vaultController, root: vault.root
    )

    controller.keepLocalBoard()

    #expect(controller.saveState == .saved)
    let onDisk = try store.load(board: boardPath)
    #expect(onDisk.node(id: stickyID) != nil)
    // Mine wins deliberately: the external node never entered `document`, so it is not
    // in what `keepLocalBoard` writes.
    #expect(onDisk.node(id: "external") == nil)

    controller.detach()
    vaultController.close()
}

@MainActor
@Test func reloadBoardFromDiskReplacesTheDocumentReturnsToSavedAndDropsDeadSelection() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, _, _, stickyID) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    controller.selection = [stickyID]

    controller.reloadBoardFromDisk()

    #expect(controller.saveState == .saved)
    #expect(controller.document.node(id: stickyID) == nil)
    #expect(controller.document.node(id: "external") != nil)
    #expect(controller.selection.isEmpty)

    controller.detach()
    vaultController.close()
}

@MainActor
@Test func detachOnAConflictedBoardRecordsAProblem() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, _, _, _) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    let countBefore = vaultController.problems.count

    controller.detach()

    #expect(vaultController.problems.count == countBefore + 1)
    vaultController.close()
}

// MARK: - #498: `load(board:)`/`select(_:)` refuse to leave a conflicted board

/// `open(board:)` on a different board while the current one is conflicted: neither the
/// board name, the document, the origin, nor the save state moves, and the refusal is
/// reported like every other conflict-guard refusal in this file.
@MainActor
@Test func openingADifferentBoardWhileConflictedRefusesAndReportsAProblem() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, store, boardPath, stickyID) = try conflictedBoard(
        vaultController: vaultController, root: vault.root
    )
    let otherBoardPath = try store.createBoard(named: "altra", in: "")
    let boardBefore = controller.board
    let documentBefore = controller.document
    let originBefore = controller.origin
    let problemsBefore = vaultController.problems.count

    controller.open(board: otherBoardPath)

    #expect(controller.board == boardBefore)
    #expect(controller.document == documentBefore)
    #expect(controller.origin == originBefore)
    #expect(controller.document.node(id: stickyID) != nil)
    guard case .conflicted = controller.saveState else {
        Issue.record("expected to remain .conflicted, got \(controller.saveState)")
        return
    }
    #expect(vaultController.problems.count == problemsBefore + 1)
    #expect(vaultController.problems.last?.contains(boardPath) == true)

    controller.detach()
    vaultController.close()
}

/// The second defect the plan named: `select(nil)` while conflicted used to wipe
/// `document`/`origin` while leaving `saveState == .conflicted`, stranding the conflict
/// unrecoverably (neither `keepLocalBoard()` nor `reloadBoardFromDisk()` had anything left
/// to act on). All four must now stay exactly as they were.
@MainActor
@Test func selectingNilWhileConflictedLeavesBoardDocumentOriginAndSaveStateUntouched() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, _, _, stickyID) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    let boardBefore = controller.board
    let documentBefore = controller.document
    let originBefore = controller.origin

    controller.select(nil)

    #expect(controller.board == boardBefore)
    #expect(controller.document == documentBefore)
    #expect(controller.origin == originBefore)
    #expect(controller.document.node(id: stickyID) != nil)
    guard case .conflicted = controller.saveState else {
        Issue.record("expected to remain .conflicted, got \(controller.saveState)")
        return
    }

    controller.detach()
    vaultController.close()
}

/// Selecting a board-less folder while conflicted is the same refusal, exercised through
/// the other branch `select(_:)` takes for a non-`.board` selection.
@MainActor
@Test func selectingAFolderWhileConflictedIsAlsoRefused() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, _, _, stickyID) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    let documentBefore = controller.document

    controller.select(.folder(""))

    #expect(controller.document == documentBefore)
    #expect(controller.document.node(id: stickyID) != nil)
    guard case .conflicted = controller.saveState else {
        Issue.record("expected to remain .conflicted, got \(controller.saveState)")
        return
    }

    controller.detach()
    vaultController.close()
}

/// Resolution un-pins navigation, mirroring `DiaryConflictTests.swift`'s
/// `afterEitherVerbShowWorksAgain`: once `keepLocalBoard()` clears the conflict,
/// `open(board:)`/`select(_:)` work again and `saveState` is back to `.saved`.
@MainActor
@Test func afterKeepLocalBoardNavigationWorksAgain() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, store, _, _) = try conflictedBoard(vaultController: vaultController, root: vault.root)
    let otherBoardPath = try store.createBoard(named: "altra", in: "")

    controller.keepLocalBoard()
    #expect(controller.saveState == .saved)

    controller.open(board: otherBoardPath)

    #expect(controller.board == otherBoardPath)
    #expect(controller.saveState == .saved)

    controller.detach()
    vaultController.close()
}

/// Same resolution path through `reloadBoardFromDisk()` instead of `keepLocalBoard()`.
@MainActor
@Test func afterReloadBoardFromDiskNavigationWorksAgain() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let (controller, _, _, _) = try conflictedBoard(vaultController: vaultController, root: vault.root)

    controller.reloadBoardFromDisk()
    #expect(controller.saveState == .saved)

    controller.select(.folder(""))

    #expect(controller.board == "")
    #expect(controller.saveState == .saved)

    controller.detach()
    vaultController.close()
}
