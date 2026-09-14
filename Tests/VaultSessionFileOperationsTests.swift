import Foundation
import Testing
@testable import Pergamenum

// Slice 3 of ADR-0016: `renameNote`, `moveNote` and `trashNote` no longer write through
// `NoteFileOperations` directly. They read a plan from it - `renamePlan`/`movePlan`/
// `danglingLinks`, none of which touch disk - and perform it inside `transaction`, using
// `moveFile`/`write`/`writeFile`. Two claims are worth pinning: that the writes a rename makes
// share one gesture id when the journal is armed, and that `isDryRun` really stops all three
// verbs one line short of the disk rather than being a flag each one has to remember.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private let board = """
{"nodes":[{"id":"a","type":"file","file":"Vecchio titolo.md","x":0,"y":0,"width":260,"height":180}],\
"edges":[]}
"""

@MainActor
private func armedSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    // The app arms none of this (ADR-0007 §D6); a test that wants to read the journal has to
    // arm it exactly as a connector does.
    session.journal = session.journalOnDisk
    return session
}

// MARK: - A rename performed for real

@MainActor
@Test func renamingANoteMovesItRewritesALinkAndRepointsABoardAsOneGesture() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    try vault.write(board, to: "Labs.canvas")
    let session = try await armedSession(vault)

    let outcome = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")

    #expect(outcome.newPath == "Nuovo titolo.md")
    #expect(outcome.failures.isEmpty)
    #expect(session.exists("Nuovo titolo.md"))
    #expect(!session.exists("Vecchio titolo.md"))

    let altra = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(altra.contains("[[Nuovo titolo]]"))
    let canvas = try String(contentsOf: vault.root.appending(path: "Labs.canvas"), encoding: .utf8)
    #expect(canvas.contains("Nuovo titolo.md"))

    // Move + link rewrite + board rewrite: three writes, one gesture.
    let entries = session.journalOnDisk.entries()
    #expect(entries.count == 3)
    let ids = Set(entries.compactMap(\.operation))
    #expect(ids.count == 1, "la rinomina non ha condiviso un solo id di gesto")
    #expect(session.journalOnDisk.entries(operation: ids.first ?? "").count == 3)
}

// MARK: - The dry run (ADR-0016 §D6)

@MainActor
@Test func aDryRunLeavesRenameMoveAndTrashCompletelyOffDisk() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    try vault.write(board, to: "Labs.canvas")
    try vault.write(note(), to: "Da spostare.md")
    try vault.write(note(), to: "Da eliminare.md")
    let session = try await armedSession(vault)
    session.isDryRun = true

    let renameOutcome = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")
    #expect(renameOutcome.newPath == "Nuovo titolo.md")
    #expect(session.exists("Vecchio titolo.md"))
    #expect(!session.exists("Nuovo titolo.md"))
    let altra = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(altra.contains("[[Vecchio titolo]]"), "la nota collegata è stata riscritta lo stesso")
    let canvas = try String(contentsOf: vault.root.appending(path: "Labs.canvas"), encoding: .utf8)
    #expect(canvas.contains("Vecchio titolo.md"), "la lavagna è stata ripuntata lo stesso")

    _ = try await session.moveNote(at: "Da spostare.md", toFolder: "Archivio")
    #expect(session.exists("Da spostare.md"))
    #expect(!session.exists("Archivio/Da spostare.md"))

    _ = try await session.trashNote(at: "Da eliminare.md")
    #expect(session.exists("Da eliminare.md"))

    #expect(
        session.journalOnDisk.entries().isEmpty,
        "una prova a vuoto ha scritto nel journal"
    )
}

// MARK: - Trashing still reports the dangling links

@MainActor
@Test func trashingANoteInsideItsOwnTransactionStillReportsDanglingLinks() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Sparita.md")
    try vault.write(note("Vedi [[Sparita]]."), to: "Rimasta.md")
    let session = try await armedSession(vault)

    let dangling = try await session.trashNote(at: "Sparita.md")

    #expect(dangling == ["Rimasta.md"])
    #expect(!session.exists("Sparita.md"))
    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.kind == .removal)
    #expect(entry.operation != nil, "la rimozione non è passata dentro una transazione")
}

// MARK: - Undo of a gesture (ADR-0016 §D5, slice 4)

@MainActor
@Test func undoOfARenamePutsTheFileTheLinkAndTheBoardBack() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    try vault.write(board, to: "Labs.canvas")
    let session = try await armedSession(vault)

    _ = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)

    let undone = await session.undo(operation: operationID)

    #expect(undone.failures.isEmpty)
    #expect(session.exists("Vecchio titolo.md"))
    #expect(!session.exists("Nuovo titolo.md"))
    let altra = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(altra.contains("[[Vecchio titolo]]"))
    let canvas = try String(contentsOf: vault.root.appending(path: "Labs.canvas"), encoding: .utf8)
    #expect(canvas.contains("Vecchio titolo.md"))
    #expect(!canvas.contains("Nuovo titolo.md"))
}

@MainActor
@Test func aLinkedNoteEditedAfterARenameRefusesTheWholeUndo() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    let session = try await armedSession(vault)

    let outcome = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")
    let operationID = try #require(session.journalOnDisk.entries().first?.operation)

    // Somebody edits the rewritten link afterwards.
    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write(note("Vedi [[Nuovo titolo]]. Aggiunta a mano."), to: "Altra.md")

    let undone = await session.undo(operation: operationID)

    #expect(undone.changed.isEmpty)
    #expect(undone.failures.contains { $0.contains("Altra.md") })
    // Nothing moved: the rename stands exactly where it left things.
    #expect(session.exists(outcome.newPath))
    #expect(!session.exists("Vecchio titolo.md"))
    #expect(try session.read("Altra.md").text.contains("Aggiunta a mano."))
}

@MainActor
@Test func undoOfATrashRefusesWhenSomethingNowOccupiesThePath() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Sparita.md")
    let session = try await armedSession(vault)

    _ = try await session.trashNote(at: "Sparita.md")
    let operationID = try #require(
        session.journalOnDisk.entries().last { $0.kind == .removal }?.operation
    )

    // Restored by hand from the Finder, or simply a new note created at the same path: either
    // way, something is there now that the journal knows nothing about.
    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write(note("Nota nuova, non quella di prima."), to: "Sparita.md")

    let undone = await session.undo(operation: operationID)

    #expect(undone.changed.isEmpty)
    #expect(undone.failures.contains { $0.contains("Sparita.md") })
    #expect(try session.read("Sparita.md").text.contains("Nota nuova, non quella di prima."))
}
