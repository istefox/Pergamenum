import Foundation
import Testing
@testable import Pergamenum

// ADR-0026: A row is dragged into a folder, and several rows are chosen first.
// Plan: docs/superpowers/plans/2026-08-27-drag-and-drop-board-files-into-workspace.md,
// Task 5.
//
// This file owns the two "rules that decide everything" §D4/§D5 describe:
// `WorkspaceBrowser.opening(from:to:currently:in:)` (the `Set<String>` selection
// binding's collapse rule, ADR-0026 §D4's four-row table) and
// `WorkspaceBrowser.canDrop(_:onFolder:)` (the cycle refusal a folder row's own drop
// highlight is asked, ADR-0026 §D5). Both are pure functions and both are declared,
// with a RED placeholder body, on `WorkspaceBrowser` itself (Sources/Features/Workspace/
// WorkspaceBrowser.swift, beside `selection(for:)`/`rows(matching:in:)`/`identifier(for:)`)
// by this test step, per Task 5's dispatch brief - the code step wires the real bodies
// into the `Binding<Set<String>>` `treeSelection` becomes and into the folder row's
// `.dropDestination`.
//
// The fixture (`workspaceFolders`/`workspaceBoards`) is `Tests/WorkspaceBrowserToolbarTests
// .swift`'s own, widened from `private` for exactly this reuse - see that file's note
// beside the declaration.
//
// RED: `opening(from:to:currently:in:)`'s placeholder returns `.none` unconditionally -
// "leave `currently` alone" - which is the *correct* answer for ADR-0026 §D4's rows 2 and
// 3 (a re-clicked single id, two-or-more ids/R-10), so
// `openingLeavesTheOpenValueAloneWhenTheSameSingleRowIsReclicked_R04Row2`,
// `openingLeavesTheOpenValueAloneForTwoOrMoreSelectedIds_R04Row3` and
// `openingLeavesTheOpenBoardOpenWhenTwoRowsAreSelected_R10` pass by accident, while the
// two "opens a different row" tests (row 1) and the "deselects on empty" test (row 4) are
// red on their `#expect`, never on a build error.
// `canDrop(_:onFolder:)`'s placeholder refuses every folder unconditionally - `false` is
// also §D5's own answer for a cycle, so the two refusal tests pass by accident while the
// three acceptance tests are red on their `#expect`.

// MARK: - WorkspaceBrowser.opening(from:to:currently:in:) (ADR-0026 §D4)

// Row 1: exactly one id, different from what is open - that row opens, resolved against
// `tree` the way a click resolves one today (`WorkspaceBrowser.selection(for:)`).

@Test func openingOpensADifferentSingleBoardRow_R04Row1() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    let result = WorkspaceBrowser.opening(
        from: [], to: ["01 Progetti/a/a.canvas"], currently: nil, in: tree
    )

    let expected: WorkspaceSelection?? = .some(.some(.board(path: "01 Progetti/a/a.canvas")))
    #expect(result == expected)
}

@Test func openingOpensADifferentSingleFolderRow_R04Row1() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    // Something else is already open ("Pergamena.canvas") - the row clicked is neither
    // empty nor the same id, so it replaces it as the one thing open.
    let result = WorkspaceBrowser.opening(
        from: ["Pergamena.canvas"], to: ["01 Progetti/b"],
        currently: .board(path: "Pergamena.canvas"), in: tree
    )

    let expected: WorkspaceSelection?? = .some(.some(.folder("01 Progetti/b")))
    #expect(result == expected)
}

// Row 2: exactly one id, the same one already open - nothing (the Note pane's
// `leaveComposer()` case, preserved verbatim in shape though this tree has no composer).

@Test func openingLeavesTheOpenValueAloneWhenTheSameSingleRowIsReclicked_R04Row2() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    let result = WorkspaceBrowser.opening(
        from: ["01 Progetti/b/b.canvas"], to: ["01 Progetti/b/b.canvas"],
        currently: .board(path: "01 Progetti/b/b.canvas"), in: tree
    )

    #expect(result == nil)
}

// Row 3: two or more ids - nothing. The open board stays open, the open note stays open
// (R-10), tested here as the general rule and again below as R-10's own scenario.

@Test func openingLeavesTheOpenValueAloneForTwoOrMoreSelectedIds_R04Row3() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    let result = WorkspaceBrowser.opening(
        from: ["01 Progetti/a"], to: ["01 Progetti/a", "01 Progetti/b"],
        currently: nil, in: tree
    )

    #expect(result == nil)
}

@Test func openingLeavesTheOpenBoardOpenWhenTwoRowsAreSelected_R10() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    // A board is open ("Pergamena.canvas") and a Shift-click extends the selection to
    // two rows that are neither of them the open board - the setter must not call
    // `onSelect` at all, which is what the outer `.none` means: `currently` is left for
    // the caller to keep reading, open, untouched.
    let result = WorkspaceBrowser.opening(
        from: ["01 Progetti/a/a.canvas"],
        to: ["01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas"],
        currently: .board(path: "Pergamena.canvas"), in: tree
    )

    #expect(result == nil)
}

// Row 4: empty - deselect, the same thing clicking the blank area below the rows already
// means (ADR-0024 §D7).

@Test func openingDeselectsOnAnEmptySet_R04Row4() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    let result = WorkspaceBrowser.opening(
        from: ["01 Progetti/b"], to: [],
        currently: .board(path: "01 Progetti/b/b.canvas"), in: tree
    )

    let expected: WorkspaceSelection?? = .some(nil)
    #expect(result == expected)
}

// MARK: - WorkspaceBrowser.canDrop(_:onFolder:) (ADR-0026 §D5, R-06)

@Test func canDropRefusesTheDraggedFolderItself_R06() {
    let dragging = [VaultItemRef(path: "01 Progetti/b", kind: .folder)]

    #expect(!WorkspaceBrowser.canDrop(dragging, onFolder: "01 Progetti/b"))
}

@Test func canDropRefusesADescendantOfTheDraggedFolder_R06() {
    let dragging = [VaultItemRef(path: "01 Progetti", kind: .folder)]

    #expect(!WorkspaceBrowser.canDrop(dragging, onFolder: "01 Progetti/b"))
}

@Test func canDropAcceptsAnUnrelatedSiblingFolder_R06() {
    let dragging = [VaultItemRef(path: "01 Progetti/a", kind: .folder)]

    #expect(WorkspaceBrowser.canDrop(dragging, onFolder: "01 Progetti/b"))
}

@Test func canDropAcceptsASiblingWhoseNameMerelyStartsWithTheDraggedFolderName_R06() {
    // ADR-0026 §D5's own stated trap: a sibling called "01 Progetti-altro" is not
    // inside "01 Progetti" even though the bare string is a prefix of it. The rule is
    // `dest == folder || dest.hasPrefix("\(folder)/")` - the `/`-suffixed prefix
    // `FolderFileOperations.repointing` already follows - never a bare `hasPrefix`.
    let dragging = [VaultItemRef(path: "01 Progetti", kind: .folder)]

    #expect(WorkspaceBrowser.canDrop(dragging, onFolder: "01 Progetti-altro"))
}

@Test func canDropIgnoresANonFolderItemInTheDragSet() {
    // Only a folder can contain a destination (`VaultMoveBatch.plan`'s own step-3
    // comment) - a board dragged onto its own containing folder is a no-op move, not a
    // cycle, and `canDrop` is not asked to catch a no-op.
    let dragging = [VaultItemRef(path: "01 Progetti/b/b.canvas", kind: .board)]

    #expect(WorkspaceBrowser.canDrop(dragging, onFolder: "01 Progetti/b"))
}

// MARK: - WorkspaceBrowser.canMove(_:to:from:) (ADR-0053 §D2 #7)
//
// The «Sposta in ▸» disable rule, unified out of `WorkspaceRow+Move.swift:141` and
// `NoteTreeRow.swift:204` - two copies of `destination != parentFolder &&
// canDrop(items, onFolder:)`, one asked over a row's multi-selection
// (`effectiveItems`), one over a folder row's own single reference (`[reference]`).
// Converts `UITests/SidebarMoveUITests.swift:168`
// (`testAFoldersOwnMoveMenuDisablesItselfAndItsDescendants_R06`): a folder's own move
// menu disables itself and every descendant, keeps a sibling enabled. The GUI test
// stays in place until `--affected` has proved the collapse (SPEC R-10) - deleting it
// is a later step, not part of landing the seam.
//
// RED: before the collapse, `WorkspaceBrowser.canMove` did not exist at all, so a test
// calling it failed to build rather than failing on an assertion; the seam landed with
// its declaration and the test together, the same shape `DiaryGeometryTests.swift`
// documents for seam #8.

@Test func canMoveRefusesAFoldersOwnRow_R06() {
    #expect(!WorkspaceBrowser.canMove(
        [VaultItemRef(path: "Parent", kind: .folder)], to: "Parent", from: ""
    ))
}

@Test func canMoveRefusesAFoldersOwnDescendant_R06() {
    #expect(!WorkspaceBrowser.canMove(
        [VaultItemRef(path: "Parent", kind: .folder)], to: "Parent/Child", from: ""
    ))
}

@Test func canMoveAcceptsASiblingFolder_R06() {
    #expect(WorkspaceBrowser.canMove(
        [VaultItemRef(path: "Parent", kind: .folder)], to: "Target", from: ""
    ))
}

// `destination != parentFolder`: the half `canDrop` alone does not cover - a move into
// the folder an item already sits in is a no-op, whatever `canDrop` would answer.

@Test func canMoveRefusesTheFolderAnItemAlreadySitsIn() {
    #expect(!WorkspaceBrowser.canMove(
        [VaultItemRef(path: "01 Progetti/a.canvas", kind: .board)], to: "01 Progetti", from: "01 Progetti"
    ))
}

@Test func canMoveAcceptsARootDestinationDifferentFromTheItemsParent() {
    #expect(WorkspaceBrowser.canMove(
        [VaultItemRef(path: "01 Progetti/a.canvas", kind: .board)], to: "", from: "01 Progetti"
    ))
}

// Multi-selection: `WorkspaceRow.effectiveItems` carries the whole lit set, so one
// refusing member refuses the destination for all of them.

@Test func canMoveRefusesAMultiSelectionWhenOneMemberIsTheDestinationItself() {
    let items = [
        VaultItemRef(path: "01 Progetti/a.canvas", kind: .board),
        VaultItemRef(path: "Target", kind: .folder),
    ]

    #expect(!WorkspaceBrowser.canMove(items, to: "Target", from: "01 Progetti"))
}

@Test func canMoveAcceptsAMultiSelectionWithNoRefusingMember() {
    let items = [
        VaultItemRef(path: "01 Progetti/a.canvas", kind: .board),
        VaultItemRef(path: "01 Progetti/b.canvas", kind: .board),
    ]

    #expect(WorkspaceBrowser.canMove(items, to: "Target", from: "01 Progetti"))
}
