import Foundation
import Testing
@testable import Pergamenum

// ADR-0025: A folder is a container, a board is a file, and neither is named after the
// other.
// Plan: docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 5.
//
// This pass drops every test in this file that pinned ADR-0024's fold model - the
// synthesized root row, the `.workspace`/`.foreignBoard` `Kind` cases and the
// `WorkspaceSelection.board(folder:)` bridge constructor all go with it. Their
// replacement coverage under the new two-row model (`WorkspaceTree.folders(in:)`,
// `identifier(for:)`, `selection(for:)`, `WorkspaceSelection`) already lives in
// `Tests/WorkspaceTreeTests.swift` (Task 2) - keeping a second, stale copy of it here
// would pin behaviour ADR-0025 §D2 explicitly cancels (no root-row synthesis).
// `Tests/WorkspaceOpenStateTests.swift` (Task 3) is the same story for
// `WorkspaceController`. `WorkspaceNameField.state(...)` and
// `WorkspaceFolderSheets.parentOptions(from:)` below are untouched: they are ADR-0022
// Task 6 concerns this task does not reopen (`parentOptions`'s own behaviour change -
// fed from `allFolders()` rather than from board paths - is this chain's own Task 6,
// with its own new test file).
//
// RED: `WorkspaceBrowserToolbar.canMutate(_:)` is a **new** overload (the existing
// `canMutate(folder:)` above it is untouched, so the toolbar's own body and
// `WorkspaceRow.menu` keep compiling against it until the coder rewires them) with a
// placeholder body that always returns `false` - so `canMutate(nil)`,
// `canMutate(.folder(""))` and `canMutate(.folder("/"))` pass by accident while
// `canMutate(.board(path:))` and `canMutate(.folder("A"))` are red on their `#expect`,
// never on a build error. `WorkspaceBrowser.target(for:)` needed no placeholder: Task 3
// already gave it its real, ADR-0025-correct body (`selection?.folder ?? ""`), so the
// three assertions below are a coverage pin, not expected to go red.
// `WorkspaceBrowser.rows(matching:in:)` needed no signature change either - its
// `nonisolated` keyword and shape stay exactly as `WorkspaceBrowser.swift:456-463`
// documents (a `@MainActor` static passing a closure to `compactMap` traps the whole
// test process, not just the test) - but its body still guards on
// `case .workspace = row.node.kind`, so every assertion below is red: a tree built
// through `WorkspaceTree.build(folders:boards:)` (Task 2's builder) carries only
// `.folder`/`.board` nodes and the guard matches neither.

// MARK: - WorkspaceBrowserToolbar.canMutate(_:) (R-08, R-11)

@Test func canMutateIsFalseWithNothingSelected() {
    #expect(!WorkspaceBrowserToolbar.canMutate(nil))
}

@Test func canMutateIsTrueForABoardSelectionIncludingARootLevelOne() {
    // "x.canvas" carries no folder prefix - a root-level board, R-11's "no
    // special-cased root synthesis" read as "mutable exactly like any other board".
    #expect(WorkspaceBrowserToolbar.canMutate(.board(path: "x.canvas")))
}

@Test func canMutateIsTrueForAnOrdinaryFolderSelection() {
    #expect(WorkspaceBrowserToolbar.canMutate(.folder("A")))
}

@Test func canMutateIsFalseForTheVaultRootFolderSelection() {
    #expect(!WorkspaceBrowserToolbar.canMutate(.folder("")))
}

@Test func canMutateStaysFalseForTheRootSpelledAsASlash() {
    // ADR-0022 §D9's root exemption, relocated onto the selection-typed overload and
    // kept even though §D2 makes the root unselectable by construction - a guard whose
    // precondition is "this state is unreachable" is a guard that stops being true the
    // first time somebody makes it reachable (ADR-0025 §D8).
    #expect(!WorkspaceBrowserToolbar.canMutate(.folder("/")))
}

// MARK: - WorkspaceBrowser.target(for:) (ADR-0025 §D7)
//
// A coverage pin, not expected to go red (see the header RED paragraph): all three
// cases in one test, because a version that special-cased `.board` (or `.folder`)
// would still make each assertion pass on its own - it is the shared expression that
// "the toolbar cannot aim anywhere the visible row is not" is actually about.

@Test func targetForReadsTheSelectionFolderAsOneExpressionRegardlessOfCase() {
    #expect(WorkspaceBrowser.target(for: nil) == "")
    #expect(WorkspaceBrowser.target(for: .folder("A")) == "A")
    // A **board** selected means the new board or folder is created beside it, in its
    // containing folder - this is the assertion that proves the read is
    // `WorkspaceSelection.folder`, never `.path` (`"A/x.canvas"` would fail this if it
    // read `.path`).
    #expect(WorkspaceBrowser.target(for: .board(path: "A/x.canvas")) == "A")
}

// MARK: - WorkspaceBrowser.rows(matching:in:) (R-01, R-03)

// ADR-0026, Task 5: not `private` any more. `Tests/WorkspaceMultiSelectionTests.swift`
// builds its `opening(from:to:currently:in:)`/`canDrop(_:onFolder:)` fixtures out of the
// same folder/board layout rather than a second, drifting copy of these two arrays - one
// vault shape, read by both files.
let workspaceFolders = ["01 Progetti", "01 Progetti/a", "01 Progetti/b"]
let workspaceBoards = [
    "Pergamena.canvas",
    "01 Progetti/a/a.canvas",
    "01 Progetti/b/b.canvas",
    "01 Progetti/b/altro.canvas",
]

@Test func rowsMatchingReturnsBothFolderAndBoardRowsDetached() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    let matches = WorkspaceBrowser.rows(matching: "01 Progetti/b", in: tree)

    // The folder row "01 Progetti/b" and the two board rows beneath it all carry the
    // filter in their own `id` - both kinds are candidates now, never `.workspace`
    // only (R-01's row model read through the filter).
    #expect(Set(matches.map(\.id)) == [
        "01 Progetti/b", "01 Progetti/b/b.canvas", "01 Progetti/b/altro.canvas",
    ])
    // Detached: every match arrives with no children, so the filtered list draws each
    // one flat, at depth 0, with nothing nested under it.
    #expect(matches.allSatisfy { $0.children.isEmpty })
}

@Test func rowsMatchingMatchesABoardByItsNameAndByItsID() {
    let tree = WorkspaceTree.build(folders: workspaceFolders, boards: workspaceBoards)

    // By name: "altro" is the board's file name without its extension, and nothing
    // else in the fixture's id or name contains it (R-03: independently openable
    // board rows found by what they are called).
    let byName = WorkspaceBrowser.rows(matching: "altro", in: tree)
    #expect(byName.map(\.id) == ["01 Progetti/b/altro.canvas"])

    // By id: "01 Progetti/a/a" is contained in the board's own vault-relative path
    // but not in its bare name ("a"), so a match here can only come from `id`.
    let byID = WorkspaceBrowser.rows(matching: "01 Progetti/a/a", in: tree)
    #expect(byID.map(\.id) == ["01 Progetti/a/a.canvas"])
}

// MARK: - Task 6 (ADR-0022): WorkspaceNameField.state(name:parent:available:) (R-02, R-03, R-04)

@Test func nameFieldStateIsInvalidForANameFailingNoteNameValidate() {
    let state = WorkspaceNameField.state(name: "Progetto/uno", parent: "", available: { _, _ in true })

    #expect(state == .invalid([.containsForbiddenCharacter("/")]))
}

@Test func nameFieldStateIsTakenWhenTheCollisionPredicateSaysSo() {
    let state = WorkspaceNameField.state(name: "Nuova", parent: "01 Progetti", available: { _, _ in false })

    #expect(state == .taken)
}

@Test func nameFieldStateIsOkWhenValidAndAvailable() {
    let state = WorkspaceNameField.state(name: "Nuova", parent: "01 Progetti", available: { _, _ in true })

    #expect(state == .ok)
}

