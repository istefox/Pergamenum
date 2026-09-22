import Foundation
import Testing
@testable import Pergamenum

// ADR-0022: Creating, renaming and deleting a workspace is a folder operation,
// performed outside the journal.
// Plan: docs/superpowers/plans/2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md,
// Task 4.
//
// The session/facade half of a folder rename and a folder delete: stars follow a
// moved note and are forgotten for a trashed one, neither verb touches the journal
// even when it is armed (ADR-0022 §D6), and the facade refuses while a note under the
// target folder has unsaved edits - the folder-scoped twin of `canOperate(on:)`.
//
// Built on `TemporaryVault` and `VaultSession(root:stateBase:)`
// (`Tests/VaultSessionFileOperationsTests.swift:21-28`) - always a temporary state
// base, never the real Application Support directory (`CLAUDE.md` principle 3).
//
// RED: `VaultSession.renameFolder`/`trashFolder` and `VaultController.renameFolder`
// are signatures only (Task 4). Every test below fails - either on its own assertion,
// or because the still-throwing session method propagates
// `FileOperationError.notImplementedYet` uncaught.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-25\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func armedSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    // The app arms none of this (ADR-0007 §D6); a test that wants to read the journal
    // has to arm it exactly as a connector does.
    session.journal = session.journalOnDisk
    return session
}

// MARK: - The star follows a moved note, and is forgotten for a trashed one (R-05, R-11)

@MainActor
@Test func renamingAFolderCarriesTheStarOfANoteInsideItToItsNewPath() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let session = try await armedSession(vault)
    session.setStar(true, for: "01 Progetti/vecchio/Nota.md")

    let outcome = try session.renameFolder(at: "01 Progetti/vecchio", to: "nuovo")

    #expect(outcome.newPath == "01 Progetti/nuovo")
    #expect(session.isStarred("01 Progetti/nuovo/Nota.md"))
    #expect(!session.isStarred("01 Progetti/vecchio/Nota.md"))
}

@MainActor
@Test func trashingAFolderForgetsTheStarsOfEveryNoteItRemoved() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Uno.md")
    try vault.write(note(), to: "01 Progetti/vecchio/Due.md")
    let session = try await armedSession(vault)
    session.setStar(true, for: "01 Progetti/vecchio/Uno.md")
    session.setStar(true, for: "01 Progetti/vecchio/Due.md")

    _ = try session.trashFolder(at: "01 Progetti/vecchio")

    #expect(!session.isStarred("01 Progetti/vecchio/Uno.md"))
    #expect(!session.isStarred("01 Progetti/vecchio/Due.md"))
}

// MARK: - Both return the moved/trashed note path lists the facade needs

@MainActor
@Test func renameFolderReturnsTheMovedNotePathList() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Uno.md")
    try vault.write(note(), to: "01 Progetti/vecchio/Due.md")
    let session = try await armedSession(vault)

    let outcome = try session.renameFolder(at: "01 Progetti/vecchio", to: "nuovo")

    #expect(Set(outcome.movedNotes.map(\.old)) == ["01 Progetti/vecchio/Uno.md", "01 Progetti/vecchio/Due.md"])
    #expect(Set(outcome.movedNotes.map(\.new)) == ["01 Progetti/nuovo/Uno.md", "01 Progetti/nuovo/Due.md"])
}

@MainActor
@Test func trashFolderReturnsTheTrashedNotePathList() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Uno.md")
    let session = try await armedSession(vault)

    let result = try session.trashFolder(at: "01 Progetti/vecchio")

    #expect(result.trashedNotePaths == ["01 Progetti/vecchio/Uno.md"])
}

// MARK: - Neither is journalled, even armed (ADR-0022 §D6, R-13)

@MainActor
@Test func renamingAFolderProducesNoJournalEntryEvenWithTheJournalArmed() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let session = try await armedSession(vault)

    _ = try session.renameFolder(at: "01 Progetti/vecchio", to: "nuovo")

    #expect(session.journalOnDisk.entries().isEmpty)
}

@MainActor
@Test func trashingAFolderProducesNoJournalEntryEvenWithTheJournalArmed() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let session = try await armedSession(vault)

    _ = try session.trashFolder(at: "01 Progetti/vecchio")

    #expect(session.journalOnDisk.entries().isEmpty)
}

// ADR-0054 §D6 (plan `docs/plans/pg-213-workspace-autosave-race.md`, Task 6, R-07): the
// two tests above only exercise a folder with no `.canvas` referencing it, so they never
// reach `canvas.writeRepoint` - Task 2/6's new write door. A folder rename that *does*
// carry a board repoint (the same fixture shape as
// `Tests/FolderFileOperationTests.swift`'s `renamePlanRepointsCanvasNodesByPrefix…`) must
// stay just as unjournalled: ADR-0025 §D6 says board writes never touch the journal, the
// index or either connector, and that has to remain true of the new door, not only of the
// old direct `Data.write` it replaced.
@MainActor
@Test func renamingAFolderWithABoardReferencingItRepointsTheBoardWithNoJournalEntry() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let canvas = CanvasStore(root: vault.root)
    _ = try canvas.save(
        CanvasDocument(nodes: [
            CanvasNode(
                id: "a", kind: .file(path: "01 Progetti/vecchio/Nota.md", subpath: nil),
                x: 0, y: 0, width: 260, height: 180
            ),
        ]),
        board: "Labs.canvas"
    )
    let session = try await armedSession(vault)

    let outcome = try session.renameFolder(at: "01 Progetti/vecchio", to: "nuovo")

    // The repoint actually ran through `writeRepoint` - not a vacuous pass because the
    // board never changed.
    let onDisk = try canvas.load(board: "Labs.canvas")
    guard case .file(let path, _) = onDisk.node(id: "a")?.kind else {
        Issue.record("expected node a to stay a .file node")
        return
    }
    #expect(path == "01 Progetti/nuovo/Nota.md")
    #expect(outcome.newPath == "01 Progetti/nuovo")
    #expect(
        session.journalOnDisk.entries().isEmpty,
        "a board repoint through the new writeRepoint door must never touch the journal (ADR-0025 §D6, R-07)"
    )
}

// MARK: - The facade refuses while a note under the folder has unsaved edits

@MainActor
@Test func vaultControllerRefusesToRenameAFolderWithAnUnsavedNoteUnderIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "01 Progetti/vecchio/Nota.md")
    controller.updateOpenNoteText(note("Modifica non salvata."))

    let renamed = controller.renameFolder(at: "01 Progetti/vecchio", to: "nuovo")

    #expect(renamed == nil)
    #expect(!controller.problems.isEmpty, "la rinomina rifiutata deve registrare un problema")
    controller.close()
}

// MARK: - The facade's success path (VaultController.trashFolder)

@MainActor
@Test func vaultControllerTrashesAFolderAndForgetsTheNoteItRemoved() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let trashed = controller.trashFolder(at: "01 Progetti/vecchio")

    #expect(trashed == true)
    #expect(controller.problems.isEmpty)
    controller.close()
}

// MARK: - The deletion twin of `didRelocateFolders` (ADR-0026 §D7, 2026-09-19 amendment, PG-169)
//
// R-04 is proved at the DOOR, not at a caller: `VaultController.trashFolder(at:)` is the one
// entry point the pratica command, the note list and the Workspace browser all share, and
// `VaultSession.trashFolder` has exactly one caller in `Sources/` - this method.

@MainActor
@Test func trashingAFolderPublishesItsPathExactlyOnce() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    var published: [String] = []
    controller.didTrashFolder = { published.append($0) }

    let trashed = controller.trashFolder(at: "01 Progetti/vecchio")

    #expect(trashed == true)
    #expect(published == ["01 Progetti/vecchio"], "one trash, one publication, carrying the trashed folder's path")
    controller.close()
}

@MainActor
@Test func trashingAFolderPublishesTheTrimmedPath() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    var published: [String] = []
    controller.didTrashFolder = { published.append($0) }

    let trashed = controller.trashFolder(at: "01 Progetti/vecchio/")

    #expect(trashed == true)
    #expect(
        published == ["01 Progetti/vecchio"],
        "`canOperateOnFolder` trims the slash, so what is published must be trimmed too or a ledger key is left behind"
    )
    controller.close()
}

// R-05: a refusal publishes nothing, so a folder that is still on disk never has its state
// forgotten. The setup is `vaultControllerRefusesToRenameAFolderWithAnUnsavedNoteUnderIt`'s.
@MainActor
@Test func aRefusedTrashPublishesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "01 Progetti/vecchio/Nota.md")
    controller.updateOpenNoteText(note("Modifica non salvata."))
    var published: [String] = []
    controller.didTrashFolder = { published.append($0) }

    let trashed = controller.trashFolder(at: "01 Progetti/vecchio")

    #expect(trashed == false)
    #expect(!controller.problems.isEmpty, "l'eliminazione rifiutata deve registrare un problema")
    #expect(published.isEmpty, "a refused trash leaves the folder where it is, so nothing may be forgotten")
    controller.close()
}

// R-05: a trash that throws in the session publishes nothing either - a folder that does not
// exist, and the vault root, which `FolderFileOperations.trashFolder` refuses outright.
@MainActor
@Test func aFailedTrashPublishesNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    var published: [String] = []
    controller.didTrashFolder = { published.append($0) }

    let missing = controller.trashFolder(at: "01 Progetti/mai-esistita")
    let root = controller.trashFolder(at: "")

    #expect(missing == false)
    #expect(root == false)
    #expect(!controller.problems.isEmpty, "each failed trash records its problem")
    #expect(published.isEmpty, "fired implies the folder really went to the Trash; a throw never gets that far")
    controller.close()
}

// MARK: - The read-only pair (PG-051): WorkspaceBrowser/NoteListPane read these through
// VaultController instead of constructing their own FolderFileOperations.

@MainActor
@Test func sessionNameIsAvailableAsksTheFileSystemTheSameWayFolderFileOperationsDoes() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/Esistente/Nota.md")
    let session = try await armedSession(vault)

    #expect(session.nameIsAvailable("Nuova", in: "01 Progetti"))
    #expect(!session.nameIsAvailable("Esistente", in: "01 Progetti"))
}

@MainActor
@Test func sessionContentCountsCountsNotesAndSubfoldersInsideAFolder() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Uno.md")
    try vault.write(note(), to: "01 Progetti/vecchio/Sub/Due.md")
    let session = try await armedSession(vault)

    let counts = session.contentCounts(at: "01 Progetti/vecchio")

    #expect(counts?.notes == 2)
    #expect(counts?.subfolders == 1)
}

@MainActor
@Test func vaultControllerNameIsAvailableDefaultsToTrueWithNoVaultOpen() {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())

    #expect(controller.nameIsAvailable("Qualsiasi", in: ""))
}

@MainActor
@Test func vaultControllerContentCountsReadsThroughToTheSession() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let counts = controller.contentCounts(at: "01 Progetti/vecchio")

    #expect(counts?.notes == 1)
    controller.close()
}

// MARK: - Rename answers with the outcome's destination, not a bare Bool (PG-052)

@MainActor
@Test func vaultControllerRenameFolderAnswersWithTheOutcomesNewPath() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "01 Progetti/vecchio/Nota.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let newPath = controller.renameFolder(at: "01 Progetti/vecchio", to: "nuovo")

    #expect(newPath == "01 Progetti/nuovo")
    controller.close()
}

@MainActor
@Test func vaultControllerRenameBoardAnswersWithTheOutcomesNewPath() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    _ = try CanvasStore(root: vault.root).createBoard(named: "vecchio", in: "")

    let newPath = controller.renameBoard(at: "vecchio.canvas", to: "nuovo")

    #expect(newPath == "nuovo.canvas")
    controller.close()
}
