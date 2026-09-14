import Foundation
import Testing
@testable import Pergamenum

// The transaction and the two shape changes (ADR-0016 §D6). Two claims carry the weight here and
// both are the kind that look true until somebody checks: that everything written inside a
// transaction really carries the same id, and that a dry run really stops short of the disk for
// a move and a removal - the two operations a dry run would otherwise perform while calling
// itself a rehearsal.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n  - topic-prove\n---\n\n\(body)\n"
}

@MainActor
private func armedSession(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note(), to: "Uno.md")
    try vault.write(note(), to: "Due.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    // The app arms none of this (ADR-0007 §D6); a test that wants to read the journal has to
    // arm it exactly as a connector does.
    session.journal = session.journalOnDisk
    return session
}

// MARK: - The gesture

@MainActor
@Test func everythingWrittenInsideATransactionCarriesTheSameID() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)

    // `transaction`'s own closure parameter is a plain synchronous `() throws -> T`
    // (ADR-0016 §D6, unrelated to this chain) - `await` cannot appear inside it without
    // widening that signature, which is out of this task's scope. These two calls
    // therefore keep resolving to the untouched synchronous `write(_:to:)` overload,
    // exactly as before ADR-0041 Task 8 added the async one; only a call site directly
    // inside an `async` function or closure needs `await` added (see below).
    await session.transaction("note rename") {
        try? await session.write(note("Uno, riscritta."), to: "Uno.md")
        try? await session.write(note("Due, riscritta."), to: "Due.md")
    }

    let entries = session.journalOnDisk.entries()
    #expect(entries.count == 2)
    let ids = Set(entries.compactMap(\.operation))
    #expect(ids.count == 1, "due scritture di un solo gesto hanno preso due id")
    #expect(session.journalOnDisk.entries(operation: ids.first ?? "").count == 2)
}

@MainActor
@Test func aWriteOutsideATransactionBelongsToNoGesture() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.journalCommand = "note append"

    // ADR-0041 Task 8: `VaultSession.write` gained an async overload; this call is
    // directly inside an `async throws` test (not inside a synchronous closure), so it
    // resolves there.
    try await session.write(note("Da sola."), to: "Uno.md")

    #expect(session.journalOnDisk.entries().first?.operation == nil)
}

@MainActor
@Test func theCommandIsBorrowedAndGivenBack() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.journalCommand = "quello di prima"

    await session.transaction("note rename") {
        #expect(session.journalCommand == "note rename")
    }

    // A caller with its own command gets it back: the transaction borrows, it does not take.
    #expect(session.journalCommand == "quello di prima")
    #expect(session.currentOperation == nil, "la transazione non si è chiusa")
}

// MARK: - The move

@MainActor
@Test func aMoveIsRecordedWithWhereItCameFrom() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.journalCommand = "note move"

    try await session.moveFile(from: "Uno.md", to: "Archivio/Uno.md")

    #expect(!session.exists("Uno.md"))
    #expect(session.exists("Archivio/Uno.md"))

    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.kind == .move)
    #expect(entry.pathBefore == "Uno.md")
    #expect(entry.path == "Archivio/Uno.md")
    // The bytes did not change, so what makes this reversible is the path, never the text.
    #expect(entry.textBefore == nil)
    #expect(entry.hashBefore == entry.hashAfter)
}

@MainActor
@Test func theIndexFollowsAMove() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)

    try await session.moveFile(from: "Uno.md", to: "Archivio/Uno.md")

    let paths = session.index.allNotes.map(\.relativePath)
    #expect(!paths.contains("Uno.md"), "l'indice tiene ancora il percorso vecchio")
    #expect(paths.contains("Archivio/Uno.md"))
}

@MainActor
@Test func aMoveOntoSomethingThatExistsIsRefused() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)

    await #expect(throws: FileOperationError.self) {
        try await session.moveFile(from: "Uno.md", to: "Due.md")
    }
    #expect(session.exists("Uno.md"), "il rifiuto ha spostato il file lo stesso")
}

// MARK: - The removal

@MainActor
@Test func aRemovalKeepsTheWholeTextSoUndoHasSomethingToWriteBack() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.journalCommand = "note trash"

    try await session.trashFile(at: "Uno.md")

    #expect(!session.exists("Uno.md"))
    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.kind == .removal)
    #expect(entry.textBefore?.contains("Corpo.") == true)
    // There is no file after this, and an empty hash says so rather than pretending.
    #expect(entry.hashAfter.isEmpty)
    #expect(!session.index.allNotes.map(\.relativePath).contains("Uno.md"))
}

// MARK: - The dry run (§D6)

@MainActor
@Test func aDryRunMovesNothingAndTrashesNothing() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.isDryRun = true

    await session.transaction("note rename") {
        try? await session.moveFile(from: "Uno.md", to: "Archivio/Uno.md")
        try? await session.trashFile(at: "Due.md")
        try? await session.write(note("Non deve arrivare su disco."), to: "Due.md")
    }

    // The whole claim of §D6 in three lines: a rehearsal that really moved the file would be
    // worse than no rehearsal at all, because it looks like the safe one.
    #expect(session.exists("Uno.md"))
    #expect(!session.exists("Archivio/Uno.md"))
    #expect(session.exists("Due.md"))
    #expect(session.journalOnDisk.entries().isEmpty, "una prova a vuoto ha scritto nel journal")
}

@MainActor
@Test func aDryRunStillRefusesWhatTheRealThingRefuses() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    session.isDryRun = true

    // Stops one line short of the disk, not one line short of the rules: a rehearsal that said
    // yes to a move the real thing would refuse is a rehearsal of a different operation.
    await #expect(throws: FileOperationError.self) {
        try await session.moveFile(from: "Uno.md", to: "Due.md")
    }
    await #expect(throws: FileOperationError.self) {
        try await session.trashFile(at: "Mai-esistita.md")
    }
}

// MARK: - A file that is not a note

@MainActor
@Test func aBoardIsWrittenAndJournalledWithoutReachingTheIndex() async throws {
    let vault = try TemporaryVault()
    let session = try await armedSession(vault)
    try vault.write("{\"nodes\":[],\"edges\":[]}", to: "Lavagna.canvas")
    session.journalCommand = "note rename"

    try await session.writeFile("{\"nodes\":[],\"edges\":[],\"x\":1}", to: "Lavagna.canvas")

    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.path == "Lavagna.canvas")
    #expect(entry.kind == .textReplacement)
    #expect(entry.textBefore == "{\"nodes\":[],\"edges\":[]}")
    // A board is not a note: it is journalled like any write and it never reaches the index.
    #expect(!session.index.allNotes.map(\.relativePath).contains("Lavagna.canvas"))
}
