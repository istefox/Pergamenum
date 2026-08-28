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
//
// ADR-0025: A folder is a container, a board is a file, and neither is named after the
// other.
// Plan: docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 7.
//
// Task 7 adds `renameBoard`/`deleteBoard` verbs (not pure - not unit-tested here, per
// this task's dispatch brief) and the two landing rules they call into, which mirror
// `folderAfterRename`/`folderAfterDelete` above but for a board file path instead of a
// folder path (R-08, R-09). `WorkspaceFolderActions.boardAfterRename`/`boardAfterDelete`
// are placeholders that return `.board(path: open)` unchanged, so every assertion below
// that expects a redirected selection fails on its `#expect`, not on a build error.

// MARK: - boardAfterRename(open:renamed:to:) (R-08)

@Test func boardAfterRenameRedirectsToTheNewPathWhenTheOpenBoardIsTheRenamedOne() {
    let result = WorkspaceFolderActions.boardAfterRename(
        open: "A/vecchio.canvas", renamed: "A/vecchio.canvas", to: "A/nuovo.canvas"
    )

    #expect(result == .board(path: "A/nuovo.canvas"))
}

@Test func boardAfterRenameLeavesAnUnrelatedOpenBoardAlone() {
    let result = WorkspaceFolderActions.boardAfterRename(
        open: "A/altro.canvas", renamed: "A/vecchio.canvas", to: "A/nuovo.canvas"
    )

    #expect(result == .board(path: "A/altro.canvas"))
}

// MARK: - boardAfterDelete(open:deleted:) (R-09)

@Test func boardAfterDeleteSelectsTheContainingFolderWhenTheOpenBoardWasDeleted() {
    let result = WorkspaceFolderActions.boardAfterDelete(open: "A/x.canvas", deleted: "A/x.canvas")

    #expect(result == .folder("A"))
}

@Test func boardAfterDeleteLeavesAnUnrelatedOpenBoardAlone() {
    let result = WorkspaceFolderActions.boardAfterDelete(open: "A/y.canvas", deleted: "A/x.canvas")

    #expect(result == .board(path: "A/y.canvas"))
}

@Test func boardAfterDeleteHandlesTheRootParentCase() {
    // Deleting a board directly under the vault root, while it is open, must land on the
    // root's own folder ("") - the vault root always survives.
    let result = WorkspaceFolderActions.boardAfterDelete(open: "vault.canvas", deleted: "vault.canvas")

    #expect(result == .folder(""))
}

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

// ADR-0026: A row is dragged into a folder, and several rows are chosen first. §D10 -
// where the open board lands once a drag-move batch has committed is a pure function
// over the batch's own `[VaultMove]`, beside the four rules above.
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 3.
//
// RED: `WorkspaceFolderActions.boardAfterMove` is a placeholder that returns `open`
// unchanged, so every assertion below that expects a rewritten path fails on its
// `#expect`, not on a build error.

// MARK: - boardAfterMove(open:moves:) (R-13)

@Test func boardAfterMoveSubstitutesTheExactPathWhenTheOpenBoardIsAMovedItem() {
    let moves = [
        VaultMove(item: VaultItemRef(path: "A/x.canvas", kind: .board), from: "A", to: "B"),
    ]

    let result = WorkspaceFolderActions.boardAfterMove(open: "A/x.canvas", moves: moves)

    #expect(result == "B/x.canvas")
}

@Test func boardAfterMoveSubstitutesThePrefixWhenTheOpenBoardSitsInsideAMovedFolder() {
    let moves = [
        VaultMove(item: VaultItemRef(path: "A", kind: .folder), from: "", to: "B"),
    ]

    let result = WorkspaceFolderActions.boardAfterMove(open: "A/sub/x.canvas", moves: moves)

    #expect(result == "B/A/sub/x.canvas")
}

@Test func boardAfterMoveLeavesASiblingFolderWithASimilarNameAlone() {
    // The prefix tested is "A/", never bare "A" - a sibling called "A-altro" is not a
    // descendant of "A" (the same rule `FolderFileOperations.repointing` and
    // `folderAfterRename` follow, and for the same reason).
    let moves = [
        VaultMove(item: VaultItemRef(path: "A", kind: .folder), from: "", to: "B"),
    ]

    let result = WorkspaceFolderActions.boardAfterMove(open: "A-altro/x.canvas", moves: moves)

    #expect(result == "A-altro/x.canvas")
}

@Test func boardAfterMoveLeavesAnUnrelatedOpenBoardAlone() {
    let moves = [
        VaultMove(item: VaultItemRef(path: "A", kind: .folder), from: "", to: "B"),
    ]

    let result = WorkspaceFolderActions.boardAfterMove(open: "C/y.canvas", moves: moves)

    #expect(result == "C/y.canvas")
}

@Test func boardAfterMoveLeavesTheOpenBoardAloneWhenTheBatchIsEmpty() {
    let result = WorkspaceFolderActions.boardAfterMove(open: "A/x.canvas", moves: [])

    #expect(result == "A/x.canvas")
}
