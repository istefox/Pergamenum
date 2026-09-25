import Foundation
import Testing
@testable import Pergamenum

// ADR-0059 (stable note ids live in `.pergamenum/note-ids.json`, not the index),
// Acceptance tests 12-25: minting through `VaultSession`, and keeping the registry in
// step at every door a note or a folder can move or leave through.
//
// RED at Task 1 (tester/coder split, plan `docs/plans/pg-130-stable-note-id.md`):
// `mintNoteID`/`lookUpNote` are stubs and `relocateNoteIDs`/`forgetNoteIDs` are empty
// bodies, so nothing below writes or reads the registry for real yet - except the four
// negative controls (13, 14, 22) a stub cannot fail.
//
// Tests 15-25 seed the registry by writing the JSON file directly and assert on the
// file itself, decoded with `JSONDecoder` - never through `NoteIDStore.load()` or
// `lookUpNote`, both of which answer "empty"/"unknown" as stubs (plan, "Test-specific
// notes").

private let seedID = "3f2c9a4e-8b1d-4c67-9e2a-5d1b7c0e4f13"
private let seedID2 = "7c1a2f3e-9d4b-4a67-8e1a-0d3b7c9e4f22"

private let note = """
---
date: 2026-09-25
tags:
  - type-note
---

Corpo.
"""

private func registryFile(root: URL) -> URL {
    root.appending(path: ".pergamenum/note-ids.json", directoryHint: .notDirectory)
}

private func decodeRegistry(root: URL) throws -> NoteIDRegistry {
    try JSONDecoder().decode(NoteIDRegistry.self, from: Data(contentsOf: registryFile(root: root)))
}

private func seedRegistry(root: URL, _ notes: [String: String]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(NoteIDRegistry(version: 1, notes: notes))
    try FileManager.default.createDirectory(
        at: registryFile(root: root).deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: registryFile(root: root))
}

private func registryFileExists(root: URL) -> Bool {
    FileManager.default.fileExists(atPath: registryFile(root: root).path(percentEncoded: false))
}

// `NoteIDRegistry.path(forID:)`/`id(forPath:)` are themselves stubs at Task 1 (always
// `nil`), so asserting through them on a registry just decoded from disk would pass a
// "the trash forgets" test by coincidence rather than for the right reason - the exact
// trap the plan names for test 17. These two read the real, non-stub `Codable` storage
// directly instead.
private func rawPath(forID id: String, in registry: NoteIDRegistry) -> String? {
    registry.notes[id.lowercased()]
}

private func rawID(forPath path: String, in registry: NoteIDRegistry) -> String? {
    registry.notes.first { $0.value == path }?.key
}

@MainActor
private func openSession(_ vault: borrowing TemporaryVault, notes paths: [String] = ["a.md"]) async throws -> VaultSession {
    for path in paths { try vault.write(note, to: path) }
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: 12. `mintNoteID(for:)` mints once, and answers the same id after

@MainActor
@Test func mintNoteIDReturnsAnIdAndStoresItASecondCallReturnsTheSameOne() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)

    let id = try #require(session.mintNoteID(for: "a.md"))
    let registry = try decodeRegistry(root: vault.root)
    #expect(rawID(forPath: "a.md", in: registry) == id)

    #expect(session.mintNoteID(for: "a.md") == id)
}

// MARK: 13. `mintNoteID(for:)` refuses three shapes, and writes nothing (GREEN: a stub cannot fail this)

@MainActor
@Test func mintNoteIDRefusesAMissingPathACanvasPathAndAPathOutsideTheVaultAndCreatesNoFile() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)

    #expect(session.mintNoteID(for: "missing.md") == nil)
    #expect(session.mintNoteID(for: "a.canvas") == nil)
    #expect(session.mintNoteID(for: "/etc/passwd.md") == nil)

    #expect(!registryFileExists(root: vault.root))
}

// MARK: 14. A rename in a vault with no registry creates no `note-ids.json` (GREEN)

@MainActor
@Test func aRenameInAVaultWithNoRegistryCreatesNoRegistryFile() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)

    _ = try await session.renameNote(at: "a.md", to: "A rinominata")

    #expect(!registryFileExists(root: vault.root))
}

// MARK: 15-16. `renameNote`/`moveNote` carry the id

@MainActor
@Test func renameNoteCarriesTheIdToTheNewPath() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    try seedRegistry(root: vault.root, [seedID: "a.md"])

    let outcome = try await session.renameNote(at: "a.md", to: "A rinominata")

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registry) == outcome.newPath)
}

@MainActor
@Test func moveNoteCarriesTheId() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    try seedRegistry(root: vault.root, [seedID: "a.md"])

    let outcome = try await session.moveNote(at: "a.md", toFolder: "Clienti")

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registry) == outcome.newPath)
}

// MARK: 17. `trashNote` forgets the id

@MainActor
@Test func trashNoteForgetsTheId() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    try seedRegistry(root: vault.root, [seedID: "a.md"])

    _ = try await session.trashNote(at: "a.md")

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registry) == nil)
}

// MARK: 18-19. The folder doors

@MainActor
@Test func renameFolderCarriesEveryIdUnderItIncludingOneWithNoFileBehindIt() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault, notes: ["Progetti/a.md"])
    // `Progetti/gone.md` stands in for an evicted note: an entry with no file behind
    // it, which must still move with the folder (ADR-0059 §D4, last bullet).
    try seedRegistry(root: vault.root, [seedID: "Progetti/a.md", seedID2: "Progetti/gone.md"])

    _ = try session.renameFolder(at: "Progetti", to: "Clienti")

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registry) == "Clienti/a.md")
    #expect(rawPath(forID: seedID2, in: registry) == "Clienti/gone.md")
}

@MainActor
@Test func trashFolderForgetsEveryIdUnderIt() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault, notes: ["Progetti/a.md"])
    try seedRegistry(root: vault.root, [seedID: "Progetti/a.md"])

    _ = try session.trashFolder(at: "Progetti")

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registry) == nil)
}

// MARK: 20. `moveItems` with one note and one folder carries both

@MainActor
@Test func moveItemsWithOneNoteAndOneFolderCarriesBoth() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault, notes: ["a.md", "Progetti/b.md"])
    try seedRegistry(root: vault.root, [seedID: "a.md", seedID2: "Progetti/b.md"])

    let outcome = await session.moveItems(
        [
            VaultItemRef(path: "a.md", kind: .note),
            VaultItemRef(path: "Progetti", kind: .folder),
        ],
        into: "Archivio"
    )
    #expect(outcome.refusals.isEmpty)

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registry) == "Archivio/a.md")
    #expect(rawPath(forID: seedID2, in: registry) == "Archivio/Progetti/b.md")
}

// MARK: 21. A connector rename, then `VaultAPI.undo`, carries the id there and back

@MainActor
@Test func aConnectorRenameFollowedByUndoCarriesTheIdThereAndBack() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault, notes: ["Nota.md"])
    try seedRegistry(root: vault.root, [seedID: "Nota.md"])

    VaultAPI.arm(session, command: "rename_note", dryRun: false)
    let summary = try await VaultAPI.renameNote(session, at: "Nota.md", to: "Nota rinominata")

    let registryAfterRename = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registryAfterRename) == summary.newPath)

    // The rename's own gesture id, not a single entry's id: `renameNote` runs inside
    // `transaction("note rename")`, and undoing the whole gesture (not one write in it)
    // is what `session.undo(operation:)` - the path `VaultAPI.undo` takes first - answers.
    let operation = try #require(session.journalOnDisk.entries().last?.operation)
    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    _ = try await VaultAPI.undo(session, id: operation)

    let registryAfterUndo = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registryAfterUndo) == "Nota.md")
}

// MARK: 21b. A connector trash, then `VaultAPI.undo`, puts the same id back (#523)

@MainActor
@Test func aConnectorTrashFollowedByUndoRestoresTheSameId() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault, notes: ["Nota.md", "Altra.md"])
    try seedRegistry(root: vault.root, [seedID: "Nota.md", seedID2: "Altra.md"])

    VaultAPI.arm(session, command: "trash_note", dryRun: false)
    _ = try await VaultAPI.trashNote(session, at: "Nota.md")

    let registryAfterTrash = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registryAfterTrash) == nil)

    let operation = try #require(session.journalOnDisk.entries().last?.operation)
    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    _ = try await VaultAPI.undo(session, id: operation)

    let registryAfterUndo = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: registryAfterUndo) == "Nota.md")
    #expect(rawPath(forID: seedID2, in: registryAfterUndo) == "Altra.md")
    #expect(registryAfterUndo.notes.count == 2)
}

// MARK: 21c. Undoing the trash of a note that never had an id mints none

@MainActor
@Test func undoingTheTrashOfANoteWithNoIdLeavesItWithoutOne() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault, notes: ["Nota.md", "Altra.md"])
    try seedRegistry(root: vault.root, [seedID2: "Altra.md"])

    VaultAPI.arm(session, command: "trash_note", dryRun: false)
    _ = try await VaultAPI.trashNote(session, at: "Nota.md")
    let operation = try #require(session.journalOnDisk.entries().last?.operation)
    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    _ = try await VaultAPI.undo(session, id: operation)

    let registry = try decodeRegistry(root: vault.root)
    #expect(rawID(forPath: "Nota.md", in: registry) == nil)
    #expect(registry.notes == [seedID2: "Altra.md"])
}

// MARK: 22. A dry run leaves the registry bytes as they were (GREEN: nothing writes yet)

@MainActor
@Test func aDryRunRenameLeavesTheRegistryBytesUnchanged() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    try seedRegistry(root: vault.root, [seedID: "a.md"])
    let before = try Data(contentsOf: registryFile(root: vault.root))

    session.isDryRun = true
    _ = try await session.renameNote(at: "a.md", to: "A rinominata")

    let after = try Data(contentsOf: registryFile(root: vault.root))
    #expect(after == before)
}

// MARK: 23. A malformed registry: the rename still succeeds, and the registry is never
// overwritten with a fresh one

@MainActor
@Test func withAMalformedRegistryARenameStillSucceedsAndReportsAProblemWithoutTouchingTheFile() async throws {
    let vault = try TemporaryVault()
    let session = try await openSession(vault)
    try vault.write("non è json", to: ".pergamenum/note-ids.json")
    let before = try Data(contentsOf: registryFile(root: vault.root))

    let outcome = try await session.renameNote(at: "a.md", to: "A rinominata")
    #expect(outcome.newPath == "A rinominata.md")

    let after = try Data(contentsOf: registryFile(root: vault.root))
    #expect(after == before)
    #expect(session.problems.contains { $0.contains("note-ids.json") })
    #expect(session.mintNoteID(for: "A rinominata.md") == nil)
}

// MARK: 24. Two sessions on one vault: no lost update (ADR-0059 §D3)

@MainActor
@Test func twoSessionsOnOneVaultDoNotLoseEachOthersUpdate() async throws {
    let vault = try TemporaryVault()
    let sessionA = try await openSession(vault, notes: ["a.md", "c.md"])
    let sessionB = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await sessionB.rescan()

    let idA = try #require(sessionA.mintNoteID(for: "a.md"))

    _ = try await sessionB.renameNote(at: "a.md", to: "A rinominata")

    #expect(sessionA.lookUpNote(id: idA) == .found("A rinominata.md"))

    _ = try #require(sessionB.mintNoteID(for: "c.md"))

    #expect(sessionA.lookUpNote(id: idA) == .found("A rinominata.md"))
}

// MARK: 25. Pratiche «Sposta in…» and its undo carry a message note's id (gate C: in this chain)

private func praticaDetail(notePath: String) -> PraticaRowDetail {
    PraticaRowDetail(
        notePath: notePath, body: "", quotedHistory: nil, signature: nil, attachments: [],
        storeReferences: [], isPending: false, senderAddress: nil, linkedNote: nil
    )
}

@MainActor
@Test func moveFilesCarriesAMessageNotesIdToItsDestinationAndMoveBackCarriesItHome() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Rossi/email/msg.md")
    try vault.write("da: a@b.it", to: "Rossi/email/msg.eml")
    try seedRegistry(root: vault.root, [seedID: "Rossi/email/msg.md"])

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
    let ops = PraticaFileOperations(vault: controller, pratiche: pratiche)

    let (moved, _) = ops.moveFiles(of: praticaDetail(notePath: "Rossi/email/msg.md"), to: "Bianchi")
    let movedMD = try #require(moved.first { $0.to.pathExtension == "md" })
    let newRelativePath = VaultScanner.relativePath(of: movedMD.to, under: vault.root)

    let afterMove = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: afterMove) == newRelativePath)

    ops.moveBack(moved)

    let afterMoveBack = try decodeRegistry(root: vault.root)
    #expect(rawPath(forID: seedID, in: afterMoveBack) == "Rossi/email/msg.md")
    controller.close()
}
