import Foundation
import Testing
@testable import Pergamenum

// ADR-0022: Creating, renaming and deleting a workspace is a folder operation,
// performed outside the journal.
// Plan: docs/superpowers/plans/2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md,
// Task 7.
//
// Task 7 wires three verbs into `WorkspaceView` (create, rename, delete) and adds a
// delete `.confirmationDialog` - none of that is a pure function, so R-02 (create),
// R-05 (rename on disk) and R-10 (delete confirmation) are not unit-tested here; they
// are the coder's GREEN-section view wiring, per this task's dispatch brief. The two
// navigation rules the wiring calls into ARE pure, so they live on
// `WorkspaceFolderActions` as static functions and are exactly what this file tests
// (R-08, R-12).
//
// RED: `WorkspaceFolderActions.folderAfterRename`/`folderAfterDelete` are placeholders
// that return `open` unchanged (`Sources/Features/Workspace/WorkspaceFolderActions.swift`),
// so every assertion below that expects a rewritten path fails on its `#expect`, not on
// a build error.

// MARK: - folderAfterRename(open:renamed:to:) (R-08)

@Test func folderAfterRenameSubstitutesThePrefixForAnOpenFolderInsideTheRenamedOne() {
    let result = WorkspaceFolderActions.folderAfterRename(
        open: "01 Progetti/a/sub", renamed: "01 Progetti/a", to: "01 Progetti/z"
    )

    #expect(result == "01 Progetti/z/sub")
}

@Test func folderAfterRenameLeavesAnUnrelatedOpenFolderAlone() {
    let result = WorkspaceFolderActions.folderAfterRename(
        open: "01 Progetti/b", renamed: "01 Progetti/a", to: "01 Progetti/z"
    )

    #expect(result == "01 Progetti/b")
}

@Test func folderAfterRenameHandlesTheExactMatchCase() {
    // The open board IS the folder being renamed, not merely inside it.
    let result = WorkspaceFolderActions.folderAfterRename(
        open: "01 Progetti/a", renamed: "01 Progetti/a", to: "01 Progetti/z"
    )

    #expect(result == "01 Progetti/z")
}

// MARK: - folderAfterDelete(open:deleted:) (R-12)

@Test func folderAfterDeleteReturnsTheDeletedFoldersParentWhenTheOpenBoardIsIt() {
    let result = WorkspaceFolderActions.folderAfterDelete(open: "01 Progetti/a", deleted: "01 Progetti/a")

    #expect(result == "01 Progetti")
}

@Test func folderAfterDeleteReturnsTheDeletedFoldersParentWhenTheOpenBoardIsUnderIt() {
    let result = WorkspaceFolderActions.folderAfterDelete(open: "01 Progetti/a/sub", deleted: "01 Progetti/a")

    #expect(result == "01 Progetti")
}

@Test func folderAfterDeleteLeavesAnUnrelatedOpenFolderUnchanged() {
    let result = WorkspaceFolderActions.folderAfterDelete(open: "01 Progetti/b", deleted: "01 Progetti/a")

    #expect(result == "01 Progetti/b")
}

@Test func folderAfterDeleteHandlesTheRootParentCase() {
    // Deleting a folder directly under the vault root, while it is open, must land on
    // the root itself ("") - the vault root always survives.
    let result = WorkspaceFolderActions.folderAfterDelete(open: "Ricerca", deleted: "Ricerca")

    #expect(result == "")
}
