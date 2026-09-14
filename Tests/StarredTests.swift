import Foundation
import Testing
@testable import Pergamenum

// The starred notes of ADR-0012 D6: a set of relative paths in `.pergamenum/starred.json`,
// and what has to happen to it when the note underneath moves.
//
// The store is tested through `VaultSession` wherever the session is what a caller touches,
// because the file and the in-memory set drifting apart is the failure worth catching, and it
// can only happen between the two.

private let note = """
---
date: 2026-08-19
tags:
  - type-note
---

## Premessa

Testo.
"""

@MainActor
private func session(_ vault: borrowing TemporaryVault) async throws -> VaultSession {
    try vault.write(note, to: "Nexion.md")
    try vault.write(note, to: "Progetti/Sospensione.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: The store on its own

@Test func aVaultWithNoStarredFileHasNoStars() throws {
    let vault = try TemporaryVault()

    #expect(StarredStore(root: vault.root).load().isEmpty)
}

@Test func whatIsSavedIsWhatComesBack() throws {
    let vault = try TemporaryVault()
    let store = StarredStore(root: vault.root)

    #expect(store.save(["Nexion.md", "Progetti/Sospensione.md"]) == nil)

    #expect(store.load() == ["Nexion.md", "Progetti/Sospensione.md"])
}

@Test func aFileThatWillNotDecodeReadsAsEmptyRatherThanFailing() throws {
    let vault = try TemporaryVault()
    let store = StarredStore(root: vault.root)
    try FileManager.default.createDirectory(
        at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try "non è json".write(to: store.file, atomically: true, encoding: .utf8)

    // A convenience that cannot be read is not a reason to refuse the vault.
    #expect(store.load().isEmpty)
}

@Test func theFileIsWrittenSortedSoItDiffsCleanly() throws {
    let vault = try TemporaryVault()
    let store = StarredStore(root: vault.root)

    store.save(["Zulu.md", "Alfa.md", "Mike.md"])

    let written = try String(contentsOf: store.file, encoding: .utf8)
    #expect(written.range(of: "Alfa.md")!.lowerBound < written.range(of: "Mike.md")!.lowerBound)
    #expect(written.range(of: "Mike.md")!.lowerBound < written.range(of: "Zulu.md")!.lowerBound)
}

// MARK: Through the session

@MainActor
@Test func starringSurvivesReopeningTheVault() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    session.toggleStar("Nexion.md")

    // A second session over the same root is what the next launch is.
    let reopened = VaultSession(root: vault.root, stateBase: vault.stateBase)
    #expect(reopened.isStarred("Nexion.md"))
    #expect(!reopened.isStarred("Progetti/Sospensione.md"))
}

@MainActor
@Test func starringTwiceLeavesTheNoteUnstarred() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    session.toggleStar("Nexion.md")
    session.toggleStar("Nexion.md")

    #expect(!session.isStarred("Nexion.md"))
    #expect(StarredStore(root: vault.root).load().isEmpty)
}

@MainActor
@Test func renamingANoteTakesItsStarWithIt() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    session.toggleStar("Nexion.md")

    let outcome = try await session.renameNote(at: "Nexion.md", to: "Nexion 2026")

    #expect(!session.isStarred("Nexion.md"))
    #expect(session.isStarred(outcome.newPath))
    // And on disk, not only in memory: the next launch reads the file, not this set.
    #expect(StarredStore(root: vault.root).load() == [outcome.newPath])
}

@MainActor
@Test func movingANoteToAFolderTakesItsStarWithIt() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    session.toggleStar("Nexion.md")

    let outcome = try await session.moveNote(at: "Nexion.md", toFolder: "Clienti")

    #expect(session.isStarred(outcome.newPath))
    #expect(!session.isStarred("Nexion.md"))
}

@MainActor
@Test func trashingANoteDropsItsStar() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)
    session.toggleStar("Progetti/Sospensione.md")

    _ = try await session.trashNote(at: "Progetti/Sospensione.md")

    #expect(!session.isStarred("Progetti/Sospensione.md"))
    #expect(StarredStore(root: vault.root).load().isEmpty)
}

@MainActor
@Test func aStarLeftOnANoteTheVaultNoLongerHasShowsNoRow() async throws {
    let vault = try TemporaryVault()
    let session = try await session(vault)

    // What a vault edited outside the app leaves behind: a path with no file under it.
    session.starredStore.save(["Sparita.md", "Nexion.md"])
    let reopened = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await reopened.rescan()

    #expect(reopened.starredNotes.map(\.relativePath) == ["Nexion.md"])
}

@MainActor
@Test func starredNotesComeBackSortedByTitle() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Zulu.md")
    let session = try await session(vault)
    await session.rescan()

    session.toggleStar("Zulu.md")
    session.toggleStar("Nexion.md")

    #expect(session.starredNotes.map(\.title) == ["Nexion", "Zulu"])
}
