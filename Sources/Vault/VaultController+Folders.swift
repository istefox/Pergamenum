import Foundation

/// Renaming a folder from the sidebar - the facade half (ADR-0022 §D1, §D10).
///
/// The file work is on `VaultSession` (ADR-0007 §D3), the same split
/// `VaultController+Files` makes for a note. What belongs here: refusing while a note
/// under the target folder has unsaved edits (the folder-scoped twin of
/// `canOperate(on:)`, `VaultController+Files.swift:14-19`), following the open board's
/// path and rescanning - the last two are Task 7's, not this one's.
///
/// **RED boundary** (plan `2026-08-25-workspace-ui-creazione-board-toolbar-e-r`, Task
/// 4): the refusal below is a signature only - it always refuses and records nothing,
/// so `Tests/VaultSessionFolderOperationsTests.swift`'s check that a problem is
/// actually recorded stays red until the coder writes the real body.
extension VaultController {
    @discardableResult
    func renameFolder(at relativePath: String, to newName: String) -> Bool {
        false
    }
}
