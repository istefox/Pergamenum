import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0095 §D8 - (coverage). `BoardFolderVerbGuardTests` pins what the folder verbs do
// to a kept conflicted board. These pin how `folderRefusal(_:)` decides a board is *inside* a
// folder, which no scenario there reaches: a sibling folder whose name merely starts with the
// same letters, a deeper folder, a board file name with a dot, a pending board whose write
// failed, a saved board, and the empty-board guard. They assert the documented contract only:
// the board's path equals the trimmed folder or starts with `folder + "/"`, the board has
// unsaved edits, and the name is the file name without `.canvas`.

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

private func makeFolder(_ root: URL, _ folder: String) throws {
    try FileManager.default.createDirectory(
        at: root.appending(path: folder, directoryHint: .isDirectory), withIntermediateDirectories: true
    )
}

/// `name` in `folder`, opened on `controller.openBoard`, refused into `.conflicted` by another
/// writer, then left with `enterPane()`/`leavePane()`, which keeps it. Answers its path.
@MainActor
private func keptConflicted(
    _ root: URL, in controller: VaultController, named name: String, folder: String
) throws -> String {
    try makeFolder(root, folder)
    let path = try CanvasStore(root: root).createBoard(named: name, in: folder)
    let board = controller.openBoard
    board.open(board: path)
    _ = board.addStickyNote("nota", at: .zero)
    let externalStore = CanvasStore(root: root)
    var diverged = try externalStore.load(board: path)
    diverged.nodes.append(CanvasNode(
        id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
    ))
    try externalStore.save(diverged, board: path)
    board.flushPendingSave()
    guard isConflicted(board) else {
        throw QuitSupportError.notConflicted("board: \(board.saveState)")
    }
    board.enterPane()
    board.leavePane()
    return path
}

@MainActor
@Test func aSiblingFolderWhoseNameStartsWithTheSamePrefixIsNotRefused() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    // The board lives in `Progetti2`; `Progetti` merely shares its first letters.
    let path = try keptConflicted(root, in: controller, named: "Bacheca", folder: "Progetti2")

    #expect(controller.folderRefusal("Progetti") == nil)
    #expect(controller.canOperateOnFolder("Progetti"))
    let renamed = controller.renameFolder(at: "Progetti", to: "Altri")
    #expect(renamed == "Altri")
    #expect(FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false)))
    // The folder that does hold it is still refused, naming the board.
    #expect(
        controller.folderRefusal("Progetti2") == VaultController.unsavedBoardInFolderRefusal(named: "Bacheca")
    )
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func aBoardInANestedFolderIsRefusedByEveryFolderAboveItAndByNoNeighbour() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try keptConflicted(root, in: controller, named: "Bacheca", folder: "Progetti/Sub")
    let refusal = VaultController.unsavedBoardInFolderRefusal(named: "Bacheca")

    #expect(controller.folderRefusal("Progetti") == refusal)
    #expect(controller.folderRefusal("Progetti/Sub") == refusal)
    // Slashes around the path are trimmed before the comparison.
    #expect(controller.folderRefusal("Progetti/") == refusal)
    #expect(controller.folderRefusal("/Progetti/Sub/") == refusal)
    // A name that is only the start of a component is not the folder.
    #expect(controller.folderRefusal("Progetti/Su") == nil)
    #expect(controller.folderRefusal("Progett") == nil)
    #expect(controller.folderRefusal("Altro") == nil)
    // Asking never records anything; `canOperateOnFolder` is what records.
    let before = controller.problems.count
    #expect(controller.folderRefusal("Progetti") == refusal)
    #expect(controller.problems.count == before)
    #expect(!controller.canOperateOnFolder("Progetti"))
    #expect(controller.problems.count == before + 1)
    #expect(controller.problems.last == refusal)
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func theRefusalNamesTheBoardByItsWholeFileNameWithoutCanvas() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try keptConflicted(root, in: controller, named: "Piano 2.0", folder: "Progetti")
    try #require(path.hasSuffix("Piano 2.0.canvas"))
    let named = try #require(controller.openBoard.quitConflict).name

    #expect(named == "Piano 2.0")
    #expect(controller.folderRefusal("Progetti") == VaultController.unsavedBoardInFolderRefusal(named: "Piano 2.0"))
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func aKeptPendingBoardWhoseWriteFailedIsRefusedToo() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try CanvasStore(root: root).createBoard(named: "Piano", in: "Progetti")
    let board = controller.openBoard
    board.open(board: path)
    _ = board.addStickyNote("pendente", at: .zero)
    board.enterPane()

    try await withReadOnlyFolder(root, "Progetti") {
        board.leavePane()
        // Kept, and not conflicted: the refusal is about unsaved edits, whichever kind.
        #expect(board.saveState == .pending)
        #expect(controller.folderRefusal("Progetti") == VaultController.unsavedBoardInFolderRefusal(named: "Piano"))
        #expect(controller.folderRefusal("Dopo") == nil)
    }
    board.detach()
    controller.close()
}

@MainActor
@Test func aSavedBoardInsideTheFolderDoesNotRefuse() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try CanvasStore(root: root).createBoard(named: "Piano", in: "Progetti")
    let board = controller.openBoard
    board.open(board: path)
    board.enterPane()
    #expect(board.saveState == .saved)
    #expect(board.board == path)

    #expect(controller.folderRefusal("Progetti") == nil)
    #expect(controller.canOperateOnFolder("Progetti"))
    board.leavePane()
    controller.close()
}

@MainActor
@Test func withNoBoardOpenNothingIsRefusedEvenIfTheStateReadsUnsaved() async throws {
    let vault = try TemporaryVault()
    let controller = try await quitController(vault)
    let board = controller.openBoard
    #expect(board.board == "")
    // An empty path would otherwise equal the vault root's trimmed folder name, "".
    board.saveState = .pending

    #expect(controller.folderRefusal("") == nil)
    #expect(controller.folderRefusal("Progetti") == nil)
    #expect(controller.canOperateOnFolder("Progetti"))

    board.saveState = .saved
    controller.close()
}
