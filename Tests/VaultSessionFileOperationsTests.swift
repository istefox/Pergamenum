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

// MARK: - Task 4 (R-01, R-03, R-05, R-08): `renameNote`/`moveNote` adopt the guard
//
// `renamePlan`'s own read is synchronous and immediately followed by the write with no
// controllable in-process window (ADR-0046 §D2's own Context), so a refusal is forced the way
// §D11 prescribes: at the writer seam, by driving `session.writeGuarded`/`writeFileGuarded`
// directly with a hand-built `VaultFileChange`, composed with the same real primitives
// (`moveFile`, `moveStar`) `renameNote` itself calls - not a re-spelling of it, the production
// writer under test.

@MainActor
@Test func aLinkRewriteNoteWhoseBytesMovedOnIsRefusedButTheRenameStillMovesTheFile() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    try vault.write(note("Vedi anche [[Vecchio titolo]]."), to: "Terza.md")
    let session = try await armedSession(vault)

    let plan = try NoteFileOperations(store: session.store).renamePlan(
        "Vecchio titolo.md", to: "Nuovo titolo", knownPaths: session.index.allNotes.map(\.relativePath)
    )
    // "Altra.md"'s `before` deliberately disagrees with what is really on disk.
    let changes = plan.noteChanges.map { change in
        change.path == "Altra.md"
            ? VaultFileChange(path: change.path, before: "questo non è quello che c'è su disco", after: change.after)
            : change
    }

    try await session.moveFile(from: "Vecchio titolo.md", to: plan.newPath)
    let result = await VaultPlanApplication.apply(changes, writing: session.writeGuarded)

    #expect(result.refusals == ["Altra.md"])
    #expect(result.rewrittenPaths == ["Terza.md"])
    #expect(session.exists("Nuovo titolo.md"))
    #expect(!session.exists("Vecchio titolo.md"))
    // The refused note keeps its own text.
    #expect(try session.read("Altra.md").text.contains("[[Vecchio titolo]]"))
    // Every other link was rewritten.
    #expect(try session.read("Terza.md").text.contains("[[Nuovo titolo]]"))
}

@MainActor
@Test func aBoardWhoseBytesMovedOnIsRefusedThroughWriteFileGuarded() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(board, to: "Labs.canvas")
    let session = try await armedSession(vault)

    let plan = try NoteFileOperations(store: session.store).renamePlan(
        "Vecchio titolo.md", to: "Nuovo titolo", knownPaths: session.index.allNotes.map(\.relativePath)
    )
    let staleChanges = plan.boardChanges.map {
        VaultFileChange(path: $0.path, before: "{\"nodes\":[],\"stale\":true}", after: $0.after)
    }
    let originalBoard = try String(contentsOf: vault.root.appending(path: "Labs.canvas"), encoding: .utf8)

    let result = await VaultPlanApplication.apply(staleChanges, writing: session.writeFileGuarded)

    #expect(result.refusals == ["Labs.canvas"])
    #expect(result.rewrittenPaths.isEmpty)
    // Byte-identical: this is Task 2's parameter reaching its real caller.
    let canvas = try String(contentsOf: vault.root.appending(path: "Labs.canvas"), encoding: .utf8)
    #expect(canvas == originalBoard)
}

@MainActor
@Test func renameNoteWithNothingConcurrentLeavesRefusalsEmpty() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    try vault.write(board, to: "Labs.canvas")
    let session = try await armedSession(vault)

    let outcome = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")

    #expect(outcome.newPath == "Nuovo titolo.md")
    #expect(outcome.rewrittenPaths.sorted() == ["Altra.md", "Labs.canvas"])
    #expect(outcome.failures.isEmpty)
    #expect(outcome.refusals.isEmpty)
}

@MainActor
@Test func theStarStillFollowsTheNoteOnAPartiallyRefusedRename() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    try vault.write(note("Vedi [[Vecchio titolo]]."), to: "Altra.md")
    let session = try await armedSession(vault)
    session.toggleStar("Vecchio titolo.md")

    let plan = try NoteFileOperations(store: session.store).renamePlan(
        "Vecchio titolo.md", to: "Nuovo titolo", knownPaths: session.index.allNotes.map(\.relativePath)
    )
    let changes = plan.noteChanges.map { change in
        VaultFileChange(path: change.path, before: "questo non è quello che c'è su disco", after: change.after)
    }

    try await session.moveFile(from: "Vecchio titolo.md", to: plan.newPath)
    let result = await VaultPlanApplication.apply(changes, writing: session.writeGuarded)
    // `moveStar` runs off `plan.newPath`, exactly as `renameNote` calls it - a refusal among
    // the link rewrites does not change what path the star follows to.
    session.moveStar(from: "Vecchio titolo.md", to: plan.newPath)

    #expect(result.refusals == ["Altra.md"])
    #expect(!session.isStarred("Vecchio titolo.md"))
    #expect(session.isStarred(plan.newPath))
}

// MARK: - PG-238/#526: a connector undo of a move carries the star back too

@MainActor
@Test func undoingAConnectorRenameMovesTheStarBack() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "Vecchio titolo.md")
    let session = try await armedSession(vault)
    session.toggleStar("Vecchio titolo.md")

    let outcome = try await session.renameNote(at: "Vecchio titolo.md", to: "Nuovo titolo")
    #expect(!session.isStarred("Vecchio titolo.md"))
    #expect(session.isStarred(outcome.newPath))

    let operation = try #require(session.journalOnDisk.entries().last?.operation)
    _ = await session.undo(operation: operation)

    #expect(session.isStarred("Vecchio titolo.md"), "l'undo di un move deve riportare la stella sul path originale")
    #expect(!session.isStarred(outcome.newPath))
}

// MARK: - Re-pointed from the deleted `NoteFileOperations.move` (ADR-0055 §D6)
//
// `NoteFileOperations.move`'s own performer is deleted; the app's one mover is
// `VaultSession.moveNote`, which reads a plan from `NoteFileOperations.movePlan` (pinned in
// `Tests/NoteFileOperationTests.swift`'s `movePlanRepointsTheCardsToo`) and performs it here.
// This is the disk half: the file really moved, an unrelated wikilink really was left alone
// (wikilink.md W-01), and the board card really was repointed.

@MainActor
@Test func movingANoteViaTheSessionLeavesLinksAloneAndRepointsTheBoards() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "00 Inbox/Nota.md")
    try vault.write(note("Vedi [[Nota]]."), to: "Altra.md")
    let board = """
    {"nodes":[{"id":"a","type":"file","file":"00 Inbox/Nota.md","x":0,"y":0,"width":260,"height":180}],\
    "edges":[]}
    """
    try vault.write(board, to: "Labs.canvas")
    let session = try await armedSession(vault)

    let outcome = try await session.moveNote(at: "00 Inbox/Nota.md", toFolder: "01 Progetti/vibrofer-emea")

    #expect(outcome.newPath == "01 Progetti/vibrofer-emea/Nota.md")
    #expect(outcome.failures.isEmpty)
    #expect(session.exists("01 Progetti/vibrofer-emea/Nota.md"))
    #expect(!session.exists("00 Inbox/Nota.md"))
    // A wikilink names a note by title, not by path: rewriting here would be wrong.
    let altra = try String(contentsOf: vault.root.appending(path: "Altra.md"), encoding: .utf8)
    #expect(altra.contains("[[Nota]]"))
    let canvas = try String(contentsOf: vault.root.appending(path: "Labs.canvas"), encoding: .utf8)
    #expect(canvas.contains("01 Progetti/vibrofer-emea/Nota.md"))
}

// MARK: - Re-pointed from `Tests/NoteRenameCharacterizationTests.swift` (ADR-0055 §D6)
//
// The one case that asserted `rewrittenPaths` order *and* the final on-disk bytes of every
// note a rename touches, moved here because a real performer exists here now -
// `NoteFileOperations.rename`'s own loop is deleted. The read-failure case ("C.md: non
// leggibile") stays a pure plan assertion in `Tests/NoteFileOperationTests.swift`'s
// `renamePlanReportsAnUnreadableKnownPathAsAFailureRatherThanThrowing`: a real rename derives
// its `knownPaths` from the index, and an unreadable note never joins the index, so C.md here
// is simply never touched rather than reported.

@MainActor
@Test func renameCharacterization_completeOutcomeAndFinalBytesOfAllThreeNotes() async throws {
    let vault = try TemporaryVault()
    // A links to B by title.
    try vault.write(note("Vedi [[Nota B]] per il dettaglio."), to: "A.md")
    // B links to itself.
    try vault.write(note("Questa è [[Nota B]], vedi anche [[Nota B]] più sotto."), to: "Nota B.md")
    // C is unreadable: not valid UTF-8, so it never joins the index and stays exactly as it
    // is regardless of what the rename does elsewhere in the vault.
    let invalidUTF8 = Data([0xFF, 0xFE, 0xFD, 0x00, 0x01])
    try invalidUTF8.write(to: vault.root.appending(path: "C.md"))
    let cBefore = try Data(contentsOf: vault.root.appending(path: "C.md"))
    let session = try await armedSession(vault)

    let outcome = try await session.renameNote(at: "Nota B.md", to: "Nota B rinominata")

    #expect(outcome.newPath == "Nota B rinominata.md")
    // Order follows the index's title order: A, then B - found at its new path, since B is
    // the note being renamed.
    #expect(outcome.rewrittenPaths == ["A.md", "Nota B rinominata.md"])
    #expect(outcome.failures.isEmpty)

    #expect(session.exists("Nota B rinominata.md"))
    #expect(!session.exists("Nota B.md"))

    let a = try String(contentsOf: vault.root.appending(path: "A.md"), encoding: .utf8)
    #expect(a == note("Vedi [[Nota B rinominata]] per il dettaglio."))
    let renamed = try String(contentsOf: vault.root.appending(path: "Nota B rinominata.md"), encoding: .utf8)
    #expect(renamed == note("Questa è [[Nota B rinominata]], vedi anche [[Nota B rinominata]] più sotto."))
    // C was never touched: still unreadable, still exactly the same bytes.
    #expect(try Data(contentsOf: vault.root.appending(path: "C.md")) == cBefore)
}
