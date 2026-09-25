import Foundation
import Testing
@testable import Pergamenum

// ADR-0059 (stable note ids live in `.pergamenum/note-ids.json`, not the index),
// Acceptance tests 26-31: the `pergamenum://note?id=` route, through
// `VaultController.handle(_:)`.
//
// RED at Task 1 (tester/coder split, plan `docs/plans/pg-130-stable-note-id.md`):
// `.noteID` still reads `RouteState.noteIDs`, which nothing ever populates, so every
// lookup answers "unknown" until Task 5 reads through the session instead. The
// exception is test 29, the negative control the current code already gets right.
//
// Tests 27-31 obtain their id from a seeded registry file or from
// `controller.session?.mintNoteID(for:)`, never from `pergamenumLink(toNoteAt:)`
// (still a path-form stub at Task 1). Only test 26 goes through that builder, and it
// will not turn green until Task 5/6 both land.

private let seedID = "3f2c9a4e-8b1d-4c67-9e2a-5d1b7c0e4f13"

private let routableNote = """
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

private func seedRegistry(root: URL, _ notes: [String: String]) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(NoteIDRegistry(version: 1, notes: notes))
    try FileManager.default.createDirectory(
        at: registryFile(root: root).deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try data.write(to: registryFile(root: root))
}

// MARK: 26. A link from `pergamenumLink(toNoteAt:)` opens the note through its id form

@MainActor
@Test func aLinkFromPergamenumLinkParsesToAnIdFormRouteAndOpensTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(routableNote, to: "a.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    let url = try #require(controller.pergamenumLink(toNoteAt: "a.md"))
    let route = try #require(PergamenumRoute(url))
    guard case .noteID = route else {
        Issue.record("expected an id-form route, got \(route)")
        return
    }

    #expect(await controller.handle(route))
    #expect(controller.openNote?.relativePath == "a.md")
    controller.close()
}

// MARK: 27. After a rename and an explicit rescan, the same id opens the renamed note

@MainActor
@Test func idOpensTheRenamedNoteAfterAnInAppRenameAndAnExplicitRescan() async throws {
    let vault = try TemporaryVault()
    try vault.write(routableNote, to: "a.md")
    try seedRegistry(root: vault.root, [seedID: "a.md"])
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    #expect(await controller.renameNote(at: "a.md", to: "A rinominata"))
    await controller.rescan()

    #expect(await controller.handle(.noteID(seedID)))
    #expect(controller.openNote?.relativePath == "A rinominata.md")
    controller.close()
}

// MARK: 28. The id still opens the note after `clearCache()`, and in a fresh controller

@MainActor
@Test func idOpensTheNoteAfterClearingCacheAndAfterReopeningInANewController() async throws {
    let vault = try TemporaryVault()
    try vault.write(routableNote, to: "a.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let id = try #require(controller.session?.mintNoteID(for: "a.md"))

    await controller.clearCache()
    #expect(await controller.handle(.noteID(id)))
    #expect(controller.openNote?.relativePath == "a.md")
    controller.close()

    let reopened = VaultController(recents: .volatile(), openTabs: .volatile())
    await reopened.open(vault.root)
    #expect(await reopened.handle(.noteID(id)))
    #expect(reopened.openNote?.relativePath == "a.md")
    reopened.close()
}

// MARK: 29. An unknown id returns false, records a problem, opens nothing (GREEN)

@MainActor
@Test func anUnknownIdReturnsFalseRecordsAProblemAndOpensNothing() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)

    #expect(await !controller.handle(.noteID("nessuno-id")))
    #expect(controller.problems.contains { $0.contains("nessuno-id") })
    #expect(controller.openNote == nil)
    controller.close()
}

// MARK: 30. An id whose file moved with `FileManager` directly reports it and opens nothing

@MainActor
@Test func anIdWhoseFileWasMovedOutsideTheAppReportsItAndOpensNothing() async throws {
    let vault = try TemporaryVault()
    try vault.write(routableNote, to: "a.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let id = try #require(controller.session?.mintNoteID(for: "a.md"))

    try FileManager.default.moveItem(
        at: vault.root.appending(path: "a.md"), to: vault.root.appending(path: "moved-outside.md")
    )

    #expect(await !controller.handle(.noteID(id)))
    #expect(controller.problems.contains { $0.contains(id) && $0.contains("a.md") })
    #expect(controller.openNote == nil)
    controller.close()
}

// MARK: 31. A `.noteID` route that arrives before `open` is replayed after it

@MainActor
@Test func aNoteIDRouteHandledBeforeOpenIsReplayedAfterItAndOpensTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(routableNote, to: "a.md")
    try seedRegistry(root: vault.root, [seedID: "a.md"])
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())

    #expect(await !controller.handle(.noteID(seedID)))

    await controller.open(vault.root)

    #expect(controller.openNote?.relativePath == "a.md")
    controller.close()
}
