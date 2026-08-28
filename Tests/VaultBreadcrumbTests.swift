import Foundation
import Testing
@testable import Pergamenum

// `VaultController.breadcrumb` (2026-08-28, Note-pane breadcrumb parity chain): the trail
// `VaultTopBar` draws, mirroring `WorkspaceController.breadcrumb`'s own coverage in
// `Tests/WorkspaceOpenStateTests.swift:221-260` - same shape, "Note" as the root instead of
// "Workspace", the open note instead of the open board.

private let noteBody = """
---
date: 2026-08-19
tags:
  - type-note
---

Testo.
"""

@MainActor
private func controller(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(noteBody, to: "Nexion.md")
    try vault.write(noteBody, to: "01 Progetti/Vibrofer/Brief.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

@MainActor
@Test func breadcrumbWithNoNoteOpenIsExactlyTheRootAndNothingMore() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    #expect(controller.openNote == nil)
    let trail = controller.breadcrumb
    #expect(trail.count == 1)
    #expect(trail.map(\.title) == ["Note"])
    #expect(trail.map(\.folder) == [""])
    controller.close()
}

@MainActor
@Test func breadcrumbForARootLevelNoteIsTheRootPlusTheNoteAlone() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.openNote(at: "Nexion.md")

    let trail = controller.breadcrumb
    #expect(trail.map(\.title) == ["Note", "Nexion"])
    #expect(trail.map(\.folder) == ["", ""])
    controller.close()
}

@MainActor
@Test func breadcrumbForANestedNoteWalksEveryFolderThenTheNotesOwnTitle() async throws {
    let vault = try TemporaryVault()
    let controller = try await controller(vault)

    controller.openNote(at: "01 Progetti/Vibrofer/Brief.md")

    let trail = controller.breadcrumb
    #expect(trail.map(\.title) == ["Note", "01 Progetti", "Vibrofer", "Brief"])
    #expect(trail.map(\.folder) == ["", "01 Progetti", "01 Progetti/Vibrofer", "01 Progetti/Vibrofer"])
    // The last segment carries its containing folder, not its own path - `VaultTopBar`
    // never renders it as a link (it is always the last, "you are here" segment), but a
    // future reader following `BoardTopBar`'s own convention needs this to hold.
    controller.close()
}
