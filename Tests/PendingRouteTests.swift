import Foundation
import Testing
@testable import Pergamenum

// PG-243, `docs/plans/pg-243-reminder-notification-tap.md`, Task 5 (R-02): a route that
// arrives while `open(_:)` is between installing the session and restoring the tabs must
// wait, not act during the rescan and clobber the saved tab session (F7).

private let note = """
---
date: 2026-09-25
tags:
  - type-note
---

Corpo.
"""

// MARK: T5.1 - a route handled while `isOpeningVault` is true is held, not acted on

@MainActor
@Test func aRouteHandledWhileTheVaultIsOpeningIsHeldRatherThanActedOn() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "a.md")
    try vault.write(note, to: "b.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let sessionBefore = controller.openTabs.session(for: vault.root)

    controller.routeState.isOpeningVault = true
    let outcome = await controller.handle(.note(path: "b.md"))

    #expect(!outcome)
    #expect(controller.routeState.pending == [.note(path: "b.md")])
    #expect(controller.openNote == nil)
    #expect(controller.openTabs.session(for: vault.root) == sessionBefore)

    controller.routeState.isOpeningVault = false
    controller.close()
}

// MARK: T5.2 - a route pending before `open` is replayed only after the tabs are restored

@MainActor
@Test func aRoutePendingBeforeOpenIsReplayedAfterTheSavedTabsAreRestored() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "a.md")
    try vault.write(note, to: "b.md")

    let openTabs = OpenTabsStore.volatile()
    openTabs.remember(
        OpenTabsStore.Session(
            columns: [.init(entries: [.init(path: "a.md", isPreview: false)], activePath: "a.md")],
            focusedColumn: 0
        ),
        for: vault.root
    )

    let controller = VaultController(recents: .volatile(), openTabs: openTabs)

    let outcomeBeforeOpen = await controller.handle(.note(path: "b.md"))
    #expect(!outcomeBeforeOpen)
    #expect(controller.routeState.pending == [.note(path: "b.md")])

    await controller.open(vault.root)

    let paths = controller.tabs.map(\.note.relativePath)
    #expect(paths.contains("a.md"))
    #expect(paths.contains("b.md"))
    #expect(controller.openNote?.relativePath == "b.md")
    #expect(controller.routeState.pending.isEmpty)
    #expect(!controller.routeState.isOpeningVault)

    controller.close()
}

// MARK: T5.3 - a `.noteID` route pending before `open` is replayed the same way

@MainActor
@Test func aPendingIDRouteIsReplayedAfterOpenFindsTheMintedNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "b.md")

    let a = VaultController(recents: .volatile(), openTabs: .volatile())
    await a.open(vault.root)
    let id = try #require(a.session?.mintNoteID(for: "b.md"))
    a.close()

    let b = VaultController(recents: .volatile(), openTabs: .volatile())

    let outcomeBeforeOpen = await b.handle(.noteID(id))
    #expect(!outcomeBeforeOpen)
    #expect(b.routeState.pending == [.noteID(id)])

    await b.open(vault.root)

    #expect(b.openNote?.relativePath == "b.md")
    b.close()
}

// MARK: R-09 (S01-03) - every route parked before `open` is replayed, in arrival order

/// A batch of links that launched the app parked in one slot, so only the last survived: two
/// captures from a Raycast script left one. Three routes parked before the vault opens all run,
/// in the order they arrived: RECENTI, newest first, reads them back reversed, and the last one
/// is the note in front.
@MainActor
@Test func everyRouteParkedBeforeOpenIsReplayedInArrivalOrder() async throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "a.md")
    try vault.write(note, to: "b.md")
    try vault.write(note, to: "c.md")

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    for path in ["a.md", "b.md", "c.md"] {
        #expect(await !controller.handle(.note(path: path)))
    }
    #expect(controller.routeState.pending == [.note(path: "a.md"), .note(path: "b.md"), .note(path: "c.md")])

    await controller.open(vault.root)

    #expect(controller.routeState.pending.isEmpty)
    #expect(Array(controller.recentNotePaths.prefix(3)) == ["c.md", "b.md", "a.md"])
    #expect(controller.openNote?.relativePath == "c.md")
    controller.close()
}
