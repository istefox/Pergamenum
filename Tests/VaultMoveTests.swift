import Foundation
import Testing
@testable import Pergamenum

// ADR-0026: A row is dragged into a folder, and several rows are chosen first. §D2/§D6/
// §D8 - one move verb for three kinds of thing, dispatched through the operations that
// already exist for each (no reimplementation of `moveNote`), an all-or-nothing batch,
// and one `UndoManager` step for the whole batch, redoable and refusing cleanly when the
// inverse's target has moved on since.
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 3.
//
// What is tested here is the **dispatch** layer only: `VaultMoveBatch`'s own five rules
// are `Tests/VaultMoveBatchTests.swift`'s (Task 1), and `BoardFileOperations.moveBoard`/
// `FolderFileOperations.moveFolder`'s own on-disk mechanics (collision, cycle, the
// board-card repoint) are `Tests/BoardFileOperationsTests.swift`/
// `Tests/FolderFileOperationTests.swift`'s (Task 2). This file asks only whether
// `VaultSession.moveItems`/`VaultController.moveItems` call those correctly, share one
// gesture, and register (and reverse) one `UndoManager` step.
//
// RED: `VaultSession.moveItems` and `VaultController.moveItems` are placeholders - the
// session returns an empty `MoveBatchOutcome` and the controller returns `false` without
// moving anything - so every assertion below that expects a move, a journal entry or an
// `UndoManager` state fails on its own `#expect`, not on a build error.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-27\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private let board = """
{"nodes":[{"id":"a","type":"file","file":"Nota.md","x":0,"y":0,"width":260,"height":180}],"edges":[]}
"""

@MainActor
private func armedSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    // The app arms none of this (ADR-0007 §D6); a test that wants to read the journal
    // has to arm it exactly as a connector does.
    session.journal = session.journalOnDisk
    return session
}

// MARK: - VaultSession.moveItems: dispatch, not reimplementation (R-01, R-02, R-03, R-04)

@MainActor
@Test func movingANoteDispatchesToTheExistingJournalledMoveNotePath() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/x.md")
    let session = try await armedSession(vault)

    let outcome = try session.moveItems([VaultItemRef(path: "A/x.md", kind: .note)], into: "B")

    #expect(outcome.moves.count == 1)
    #expect(session.exists("B/x.md"))
    #expect(!session.exists("A/x.md"))
    // Proves Task 3 did not reimplement `moveNote`: the write must have gone through
    // `VaultSession+Journal`'s `moveFile`, the same journalled primitive
    // `VaultSession.moveNote` (`VaultSession+Files.swift`) already uses - a second
    // spelling of that verb would leave no entry here even though the file moved.
    let entry = try #require(session.journalOnDisk.entries().last { $0.path == "B/x.md" })
    #expect(entry.kind == .move)
    #expect(entry.pathBefore == "A/x.md")
}

@MainActor
@Test func movingAFolderAndABoardInOneCallMovesBothAndReturnsBothInMoves() async throws {
    let vault = try TemporaryVault()
    try vault.write(board, to: "X.canvas")
    try vault.write(note(), to: "F/inside.md")
    let session = try await armedSession(vault)

    let outcome = try session.moveItems(
        [
            VaultItemRef(path: "X.canvas", kind: .board),
            VaultItemRef(path: "F", kind: .folder),
        ],
        into: "Dest"
    )

    #expect(outcome.moves.count == 2)
    #expect(session.exists("Dest/X.canvas"))
    #expect(!session.exists("X.canvas"))
    #expect(session.exists("Dest/F/inside.md"))
    #expect(!session.exists("F"))
}

// MARK: - All-or-nothing (ADR-0026 §D6)

@MainActor
@Test func aBatchWhereOneItemCollidesCommitsNothingAndNamesTheConflict() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A/x.md")
    // Already occupies where "A/x.md" would land inside "B".
    try vault.write(note(), to: "B/x.md")
    try vault.write(note(), to: "C/keep/y.md")
    let session = try await armedSession(vault)

    let outcome = try session.moveItems(
        [
            VaultItemRef(path: "A/x.md", kind: .note),
            VaultItemRef(path: "C/keep", kind: .folder),
        ],
        into: "B"
    )

    #expect(outcome.moves.isEmpty, "un batch con un conflitto non deve spostare nulla")
    #expect(!outcome.refusals.isEmpty)
    #expect(
        outcome.refusals.contains { $0.contains("B/x.md") },
        "il rifiuto deve nominare il nome che collide"
    )
    // Nothing moved, including the item that had nowhere to collide.
    #expect(session.exists("A/x.md"))
    #expect(!session.exists("B/A"))
    #expect(session.exists("C/keep"))
    #expect(session.exists("C/keep/y.md"))
    #expect(!session.exists("B/keep"))
}

// MARK: - VaultController.moveItems: one UndoManager step for the whole batch (R-12)

@MainActor
@Test func undoingAMoveRestoresEveryPathInOneStepAndRedoMovesThemAgain() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(note(), to: "A/x.md")
    try vault.write(board, to: "A/y.canvas")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)
    let manager = UndoManager()
    let items = [
        VaultItemRef(path: "A/x.md", kind: .note),
        VaultItemRef(path: "A/y.canvas", kind: .board),
    ]

    let moved = controller.moveItems(items, into: "B", undo: manager)

    #expect(moved)
    #expect(exists("B/x.md", at: root))
    #expect(exists("B/y.canvas", at: root))
    #expect(manager.canUndo, "una mossa completata deve registrarsi sull'UndoManager")

    manager.undo()

    #expect(exists("A/x.md", at: root))
    #expect(exists("A/y.canvas", at: root))
    #expect(!exists("B/x.md", at: root))
    #expect(!exists("B/y.canvas", at: root))
    #expect(manager.canRedo, "l'undo deve registrarsi di nuovo con gli argomenti scambiati")

    manager.redo()

    #expect(exists("B/x.md", at: root))
    #expect(exists("B/y.canvas", at: root))

    controller.close()
}

@MainActor
@Test func undoRefusesAndRecordsAProblemWhenTheMovedItemHasBeenRenamedSince() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(note(), to: "A/x.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)
    let manager = UndoManager()

    let moved = controller.moveItems([VaultItemRef(path: "A/x.md", kind: .note)], into: "B", undo: manager)
    #expect(moved)

    // The moved note is renamed out from under the undo before Cmd+Z ever runs - the
    // exact race ADR-0026 §D8 names ("a later rename moved it").
    _ = controller.renameNote(at: "B/x.md", to: "y")

    manager.undo()

    #expect(!exists("A/x.md", at: root), "l'undo non deve scrivere nulla se il target si è spostato")
    #expect(exists("B/y.md", at: root), "il file rinominato deve restare dov'è, non essere toccato")
    #expect(
        !controller.problems.isEmpty,
        "un target spostato deve registrare un problema, non fallire in silenzio"
    )
    #expect(
        !manager.canRedo,
        "un redo di un undo che non è avvenuto sarebbe peggio di nessun redo (ADR-0026 §D8)"
    )

    controller.close()
}

// MARK: - `undo: nil` still moves, and degrades visibly (ADR-0026 §D8)

@MainActor
@Test func movingWithoutAnUndoManagerStillMovesAndRecordsOneProblemLine() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(note(), to: "A/x.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)

    let moved = controller.moveItems([VaultItemRef(path: "A/x.md", kind: .note)], into: "B", undo: nil)

    #expect(moved)
    #expect(exists("B/x.md", at: root))
    #expect(
        controller.problems.count == 1,
        "senza UndoManager deve comparire esattamente una riga di problema, non un fallimento silenzioso"
    )

    controller.close()
}

// MARK: - Support

// `TemporaryVault` is `~Copyable`, and `#expect`'s macro expansion needs to capture its
// arguments to print them on failure - it cannot capture a noncopyable value passed by
// name. Every controller-level test below reads `vault.root` (a plain `URL`, `Copyable`)
// into a local once, and `exists(_:at:)` takes that instead of the vault itself.
private func exists(_ relativePath: String, at root: URL) -> Bool {
    FileManager.default.fileExists(
        atPath: root.appending(path: relativePath).path(percentEncoded: false)
    )
}
