import Foundation
import Testing
@testable import Pergamenum

// PG-392, ADR-0092 §D8 (gate G1, approved 2026-10-08), plan Task 6 (R-02): a rename, a trash or
// a move of the folder that holds a *kept* conflicted board - one the vault controller still
// owns after the Workspace pane was left - is refused, naming the board, because the verb would
// move the file out from under a conflict `Mantieni`/`Ricarica` could then no longer read. The
// Workspace's own verbs go through `settleForVerb()` and are not refused twice, unless the flush
// fails and leaves the board pending, which the folder guard then refuses.

/// G2's frozen folder refusal (2026-10-08), spelled out once.
private let boardRefusal =
    "risolvi le modifiche non salvate della board «Bacheca» nel Workspace prima di rinominare o eliminare la cartella"

@MainActor
private func isConflicted(_ board: WorkspaceController) -> Bool {
    if case .conflicted = board.saveState { return true }
    return false
}

private func exists(_ root: URL, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
}

/// The board «Bacheca» in `folder`, opened on `controller.openBoard`, refused into `.conflicted`
/// by another writer, and left with `enterPane()`/`leavePane()` - which keeps it. Answers its path.
@MainActor
private func keptConflictedBoard(
    _ root: URL, in controller: VaultController, folder: String
) throws -> String {
    let path = try CanvasStore(root: root).createBoard(named: "Bacheca", in: folder)
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
@Test func renamingTheFolderOfAKeptConflictedBoardIsRefusedNamingTheBoard() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try keptConflictedBoard(root, in: controller, folder: "Progetti")
    let before = try Data(contentsOf: root.appending(path: path))
    #expect(VaultController.unsavedBoardInFolderRefusal(named: "Bacheca") == boardRefusal)

    let renamed = controller.renameFolder(at: "Progetti", to: "Altri")

    #expect(renamed == nil)
    #expect(exists(root, path))
    #expect(!exists(root, "Altri"))
    #expect(controller.problems.contains(boardRefusal))
    #expect(try Data(contentsOf: root.appending(path: path)) == before)
    #expect(isConflicted(controller.openBoard))
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func trashingTheFolderOfAKeptConflictedBoardIsRefused() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try keptConflictedBoard(root, in: controller, folder: "Progetti")

    let trashed = controller.trashFolder(at: "Progetti")

    #expect(!trashed)
    #expect(exists(root, path))
    #expect(exists(root, "Progetti/Sospensione.md"))
    #expect(controller.problems.contains(boardRefusal))
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func movingTheFolderOfAKeptConflictedBoardIsRefusedWithTheBoardsSentence() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try keptConflictedBoard(root, in: controller, folder: "Progetti")
    try FileManager.default.createDirectory(
        at: root.appending(path: "Archivio", directoryHint: .isDirectory), withIntermediateDirectories: true
    )

    let outcome = await controller.moveItems(
        [VaultItemRef(path: "Progetti", kind: .folder)], into: "Archivio", undo: nil
    )

    #expect(!outcome.didMove)
    // The board's sentence, not the note's.
    #expect(outcome.refusals == [boardRefusal])
    #expect(outcome.refusals != [VaultController.unsavedNoteInFolderRefusal])
    #expect(exists(root, path))
    #expect(!exists(root, "Archivio/Progetti"))
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func aConflictedBoardOutsideTheFolderDoesNotRefuse() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    // The board sits at the vault root, outside `Progetti`.
    let path = try keptConflictedBoard(root, in: controller, folder: "")

    let renamed = controller.renameFolder(at: "Progetti", to: "Altri")

    #expect(renamed != nil)
    #expect(exists(root, "Altri"))
    #expect(!exists(root, "Progetti"))
    #expect(!controller.problems.contains(boardRefusal))
    #expect(exists(root, path))
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func aDirtyNoteInTheFolderStillGivesTheNotesSentence() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    _ = try keptConflictedBoard(root, in: controller, folder: "Progetti")
    _ = try openDirty("Progetti/Sospensione.md", adding: "\nNon salvata.\n", inColumn: 0, of: controller)

    let renamed = controller.renameFolder(at: "Progetti", to: "Altri")

    #expect(renamed == nil)
    // The note's check runs first and its sentence is unchanged.
    #expect(controller.problems.contains(VaultController.unsavedNoteInFolderRefusal))
    #expect(VaultController.unsavedNoteInFolderRefusal == "salva la nota prima di rinominare o eliminare la cartella")
    #expect(!controller.problems.contains(boardRefusal))
    #expect(exists(root, "Progetti"))
    controller.openBoard.detach()
    controller.close()
}

@MainActor
@Test func theWorkspacesOwnVerbIsNotRefusedTwice() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try CanvasStore(root: root).createBoard(named: "Bacheca", in: "Progetti")
    let board = controller.openBoard
    board.open(board: path)
    let id = board.addStickyNote("pendente", at: .zero)
    #expect(board.saveState == .pending)
    // On screen: the pane is entered and not left.
    board.enterPane()
    let problems = controller.problems.count

    // What `WorkspaceView+FolderVerbs` does first: settle and flush the open board.
    #expect(board.settleForVerb())
    #expect(board.saveState == .saved)
    let renamed = controller.renameFolder(at: "Progetti", to: "Altri")

    #expect(renamed == "Altri")
    #expect(exists(root, "Altri/Bacheca.canvas"))
    #expect(!controller.problems.contains(boardRefusal))
    // Only the verb's own lines: the refusal is not among them.
    #expect(!controller.problems.dropFirst(problems).contains { $0.contains("risolvi le modifiche") })
    let moved = try CanvasStore(root: root).load(board: "Altri/Bacheca.canvas")
    #expect(moved.node(id: id) != nil)
    board.leavePane()
    controller.close()
}

@MainActor
@Test func theWorkspacesOwnVerbIsRefusedWhenItsFlushFails() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let controller = try await quitController(vault)
    let path = try CanvasStore(root: root).createBoard(named: "Bacheca", in: "Progetti")
    let board = controller.openBoard
    board.open(board: path)
    _ = board.addStickyNote("pendente", at: .zero)
    board.enterPane()

    try await withReadOnlyFolder(root, "Progetti") {
        // `settleForVerb()` refuses only a conflict: a write that fails leaves the board
        // pending, and the settle lets the verb through.
        #expect(board.settleForVerb())
        #expect(board.saveState == .pending)

        let renamed = controller.renameFolder(at: "Progetti", to: "Altri")

        // The folder guard then refuses it with the board's sentence: the safe direction, since
        // moving the file would leave the unsaved edits naming a path that has gone.
        #expect(renamed == nil)
        #expect(controller.problems.contains(boardRefusal))
    }
    #expect(exists(root, path))
    #expect(!exists(root, "Altri"))
    board.detach()
    controller.close()
}
