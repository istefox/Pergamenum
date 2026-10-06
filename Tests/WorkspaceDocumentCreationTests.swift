import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// The Workspace «Documento» sheet creates a note and its card, and opens no tab (n1-seams R-10,
// R-18): `WorkspaceController.createDocument(titled:at:through:)` answers `.created(path:)` or
// `.failed(sentence)`.
//
// The plan also asks that «the pane stays `.workspace`»; `createDocument` takes no `Navigation`,
// so there is no pane at this seam to observe, and that clause is left to the wiring task rather
// than asserted vacuously here.

private let existing = """
---
date: 2026-10-01
tags:
  - type-note
---

Corpo.
"""

/// A vault with a board `A/A.canvas` open on a `WorkspaceController`, a second board
/// `B/B.canvas`, and one note already open in a tab so "no tab opened" is measurable.
@MainActor
private struct Fixture {
    let vault: VaultController
    let workspace: WorkspaceController
    let store: CanvasStore
    let a: String
    let b: String
}

@MainActor
private func fixture(_ root: borrowing TemporaryVault) async throws -> Fixture {
    try root.write(existing, to: "Prova.md")
    try FileManager.default.createDirectory(
        at: root.root.appending(path: "A", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: root.root.appending(path: "B", directoryHint: .isDirectory), withIntermediateDirectories: true
    )
    let vault = VaultController(recents: .volatile(), openTabs: .volatile())
    await vault.open(root.root)
    vault.openNote(at: "Prova.md")
    let store = CanvasStore(root: root.root)
    let a = try store.createBoard(named: "A", in: "A")
    let b = try store.createBoard(named: "B", in: "B")
    let workspace = WorkspaceController()
    workspace.attach(to: store)
    workspace.open(board: a)
    return Fixture(vault: vault, workspace: workspace, store: store, a: a, b: b)
}

@MainActor
private func tabCount(_ vault: VaultController) -> Int { vault.columns.flatMap(\.tabs).count }

@MainActor
@Test func aDocumentOnTheOpenBoardIsCreatedAndGetsItsCard() async throws {
    let root = try TemporaryVault()
    let f = try await fixture(root)
    defer { f.workspace.detach(); f.vault.close() }

    let result = await f.workspace.createDocument(titled: "Verbale", at: .zero, through: f.vault)

    guard case .created(let path) = result else {
        Issue.record("expected .created, got \(result)")
        return
    }
    #expect(path.hasSuffix("Verbale.md")) // (n1-seams R-10)
    #expect(FileManager.default.fileExists(
        atPath: root.root.appending(path: path).path(percentEncoded: false)
    )) // (n1-seams R-10)
    let cards = f.workspace.document.nodes.compactMap { node -> String? in
        if case .file(let filePath, _) = node.kind { return filePath }
        return nil
    }
    #expect(cards == [path]) // (n1-seams R-10)
}

@MainActor
@Test func creatingADocumentOpensNoTabAndMovesNoFocus() async throws {
    let root = try TemporaryVault()
    let f = try await fixture(root)
    defer { f.workspace.detach(); f.vault.close() }
    let tabsBefore = tabCount(f.vault)
    let columnBefore = f.vault.focusedColumnIndex
    let focusedBefore = f.vault.openNote?.relativePath

    let result = await f.workspace.createDocument(titled: "Verbale", at: .zero, through: f.vault)

    guard case .created = result else {
        Issue.record("expected .created, got \(result)")
        return
    }
    #expect(tabCount(f.vault) == tabsBefore) // (n1-seams R-10)
    #expect(f.vault.focusedColumnIndex == columnBefore) // (n1-seams R-10)
    #expect(f.vault.openNote?.relativePath == focusedBefore) // (n1-seams R-10)
    #expect(f.vault.openNote?.relativePath == "Prova.md") // (n1-seams R-10)
}

@MainActor
@Test func theDocumentNoteIsACaptureAndCarriesStatusInbox() async throws {
    let root = try TemporaryVault()
    let f = try await fixture(root)
    defer { f.workspace.detach(); f.vault.close() }

    let result = await f.workspace.createDocument(titled: "Verbale", at: .zero, through: f.vault)

    guard case .created(let path) = result else {
        Issue.record("expected .created, got \(result)")
        return
    }
    let text = try String(contentsOf: root.root.appending(path: path), encoding: .utf8)
    #expect(text.contains("  - status-inbox\n")) // (n1-seams R-10)
}

@MainActor
@Test func aTakenTitleFailsWithTheSentenceAndPlacesNoCard() async throws {
    let root = try TemporaryVault()
    let f = try await fixture(root)
    defer { f.workspace.detach(); f.vault.close() }
    // The board is on `A`, so the note would go to `A/`: take that name first.
    try root.write(existing, to: "A/Verbale.md")
    await f.vault.rescan()
    let nodesBefore = f.workspace.document.nodes.count
    let tabsBefore = tabCount(f.vault)

    var expected = ""
    do {
        try await f.vault.createNote(title: "Verbale", in: "A", date: .today, opening: false)
        Issue.record("creating a note whose title is taken should have thrown")
    } catch {
        expected = ConformanceText.creationFailure(error)
    }
    #expect(!expected.isEmpty)

    let result = await f.workspace.createDocument(titled: "Verbale", at: .zero, through: f.vault)

    #expect(result == .failed(expected)) // (n1-seams R-18)
    #expect(f.workspace.document.nodes.count == nodesBefore) // (n1-seams R-18)
    #expect(tabCount(f.vault) == tabsBefore) // (n1-seams R-18)
}

@MainActor
@Test func aBoardSwitchedDuringTheAwaitGetsNoCard() async throws {
    let root = try TemporaryVault()
    let f = try await fixture(root)
    defer { f.workspace.detach(); f.vault.close() }

    let creation = Task { @MainActor in
        await f.workspace.createDocument(titled: "Verbale", at: .zero, through: f.vault)
    }
    // Lets `createDocument` run up to its first suspension, then moves the person to board B.
    // The assertions below hold whichever side of the suspension the switch lands on: the note
    // is written either way, and board B never receives a card for a note made in A's folder
    // (ADR-0043 §D7, `placeCreatedNote`'s guard).
    await Task.yield()
    f.workspace.open(board: f.b)
    _ = await creation.value

    let written = FileManager.default.fileExists(
        atPath: root.root.appending(path: "A/Verbale.md").path(percentEncoded: false)
    )
    #expect(written) // (n1-seams R-10)
    #expect(f.workspace.board == f.b) // (n1-seams R-10)
    #expect(f.workspace.document.nodes.isEmpty) // (n1-seams R-10)
    #expect(try f.store.load(board: f.b).nodes.isEmpty) // (n1-seams R-10)
}
