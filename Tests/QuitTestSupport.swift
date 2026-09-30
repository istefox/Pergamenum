import Foundation
import Testing
@testable import Pergamenum

// Shared by `TabSaveTests`, `QuitSaveTests`, `QuitCoordinatorTests` and
// `CloseTabRequestTests` (ADR-0073, plan Tasks 2, 3 and 5): the `NoteTabTests` scaffolding -
// a real vault, a real `VaultController` - with three notes, two of them in one folder so the
// folder can be made read-only.

func quitNote(_ body: String) -> String {
    """
    ---
    date: 2026-09-29
    tags:
      - type-note
    ---

    \(body)
    """
}

@MainActor
func quitController(_ vault: borrowing TemporaryVault) async throws -> VaultController {
    try vault.write(quitNote("Nexion."), to: "Nexion.md")
    try vault.write(quitNote("Sospensione."), to: "Progetti/Sospensione.md")
    try vault.write(quitNote("Pressa."), to: "Progetti/Pressa.md")
    // Outside `Progetti`, and written before the vault opens: a file created afterwards
    // reaches the watcher late and can raise the banner on a tab already dirty.
    try vault.write(quitNote("Dopo."), to: "Dopo.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    return controller
}

/// Opens `path` in a tab of its own in column `column`, adding the second column when needed,
/// appends `addition` to its text and returns the tab's id. The column is left focused.
@MainActor
func openDirty(
    _ path: String, adding addition: String, inColumn column: Int, of controller: VaultController
) throws -> NoteTab.ID {
    if column == 1, controller.columns.count == 1 { controller.addColumn() }
    controller.focusColumn(column)
    controller.openNoteInNewTab(at: path)
    let id = try #require(controller.focusedTab?.id)
    #expect(controller.openNote?.relativePath == path)
    controller.updateOpenNoteText((controller.openNote?.text ?? "") + addition)
    return id
}

/// The file's text, or nil. Takes the root rather than the vault: `TemporaryVault` is
/// noncopyable and `#expect` wants a copy.
func quitOnDisk(_ root: URL, _ path: String) -> String? {
    try? String(contentsOf: root.appending(path: path), encoding: .utf8)
}

/// Makes a folder of the vault read-only for the duration of `body`, so a write into it fails
/// (the precedent is `Tests/RecordingsControllerTests.swift`); restored whatever happens.
@MainActor
func withReadOnlyFolder<T>(
    _ root: URL, _ folder: String, _ body: () async throws -> T
) async throws -> T {
    let path = root.appending(path: folder, directoryHint: .isDirectory).path(percentEncoded: false)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path) }
    return try await body()
}
