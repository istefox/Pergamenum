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
// `FolderFileOperations.OperationError.notImplementedYet` uncaught.

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

    #expect(renamed == false)
    #expect(!controller.problems.isEmpty, "la rinomina rifiutata deve registrare un problema")
    controller.close()
}
