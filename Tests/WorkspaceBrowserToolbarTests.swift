import Foundation
import Testing
@testable import Pergamenum

// ADR-0022: Creating, renaming and deleting a workspace is a folder operation,
// performed outside the journal.
// Plan: docs/superpowers/plans/2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md,
// Tasks 5-6.
//
// ADR-0024: One selection, one row, one meaning - the toolbar's target is the
// selection, with no fallback (R-06).
// Plan: docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md,
// Task 4. This file now serves two chains.
//
// The sidebar toolbar's enablement (Task 5) and the two sheets' decision logic
// (Task 6), kept as pure functions so they are testable without a view.
//
// RED (Task 5): `WorkspaceBrowserToolbar.canMutate(folder:)` is a placeholder that
// always returns `false`, so the root-exemption test passes for `""` but fails its
// second assertion for `"01 Progetti"`, on an assertion rather than on a build error.
// The expand-all set behind "Espandi tutto" is pre-existing, already-correct logic and
// its tests are coverage pins, not expected to fail. They read it through
// `WorkspaceTree.folders(in:)`, which is what the button asks: the view's own
// `allFolders(in:)` is gone, and with it the `private`-to-internal widening that
// existed only so this file could reach it.
//
// RED (Task 6): `WorkspaceNameField.state` is a placeholder that always returns
// `.ok`, so the `.invalid` and `.taken` cases fail their assertions.
// `WorkspaceFolderSheets.parentOptions` is a placeholder that always returns `[]`,
// so its test fails its assertion. Neither throws, neither force-unwraps.
//
// RED (ADR-0024 Task 4): `WorkspaceBrowser.target(for:)` is a placeholder that
// always returns `""`, so the `nil` case of
// `targetForReadsTheSelectionFolderAsOneExpressionRegardlessOfCase` passes by
// accident while its `.folder`/`.board` cases fail their expectation of `"A"` - on
// an assertion, not a build error. The other two new tests below are coverage pins
// over logic that already exists (`canMutate(folder:)`, `WorkspaceTree.folders(in:)`,
// `WorkspaceBrowser.allFolders(in:)`), not expected to fail: what they pin down is the
// decision itself (no-fallback disables the verbs) and the gap that made Task 3's
// coder flag `rebuild()`'s stale-selection check (a `NoteTree` walk has no node for
// the root).

// MARK: - Task 5: WorkspaceBrowserToolbar.canMutate(folder:) (R-09)

@Test func canMutateIsFalseForTheVaultRootAndTrueForAnOrdinaryFolder() {
    #expect(!WorkspaceBrowserToolbar.canMutate(folder: ""))
    #expect(WorkspaceBrowserToolbar.canMutate(folder: "01 Progetti"))
}

// MARK: - Task 5: the "Espandi tutto" folder set (R-01)

// The toolbar's "Espandi tutto" button drives the same `expanded` binding the tree's
// context menu already does (ADR-0022 §D8) - this pins the fixture shape the button
// will read, not new behaviour.
// MARK: - ADR-0023 Task 4: WorkspaceTree.folders(in:) fed by the real board paths (R-01, R-02)
//
// ADR-0023: A command is named once and rendered twice.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 4.
//
// R-02 as a property of the tree, not of a guard: the vault root is not a folder any path
// component names, so there is no ordinary folder row for a context menu to hide
// Rinomina/Elimina from in the first place - the root's own row is synthesised, and
// `canMutate(folder:)` refuses it by id. Both `WorkspaceTree.folders(in:)` and
// `WorkspaceBrowserToolbar.canMutate(folder:)` already exist and are already correct
// (ADR-0022/ADR-0024); these two tests are coverage pins over the real board-path builder
// rather than new logic, so they are not expected to go red on their assertions - the
// SPEC correction they back (SPEC "Three things ... false" table) is what makes them
// worth pinning down here, ahead of Task 4's context-menu GREEN.
//
// Read through `WorkspaceTree.folders(in:)`, which is the function the button itself
// asks: the view's `allFolders(in:)`, an internal-only-for-this-file copy of the same
// walk over the `NoteTree` the view no longer keeps, is gone.

/// `CanvasStore.boardPath(forFolder:)`'s rule for a vault rooted at «Labs», restated for
/// a test that has no store on disk - the same stub the root-selection test below uses.
private func testBoardPath(forFolder folder: String) -> String {
    folder.isEmpty ? "Labs.canvas" : "\(folder)/\((folder as NSString).lastPathComponent).canvas"
}

@Test func expandAllFoldersOfATreeBuiltFromRealBoardPathsAreTheRootPlusEveryMutableFolder() {
    let tree = WorkspaceTree.build(
        boards: ["Labs.canvas", "01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas"],
        boardPath: testBoardPath(forFolder:)
    )

    let folders = Set(WorkspaceTree.folders(in: tree))

    #expect(folders == ["", "01 Progetti", "01 Progetti/a", "01 Progetti/b"])
    // The root is in the set the button expands (its row draws no children, so opening it
    // shows nothing) and out of the set the toolbar's verbs may act on - R-02 read as two
    // different questions about the same id.
    #expect(!WorkspaceBrowserToolbar.canMutate(folder: ""))
    for folder in folders where !folder.isEmpty {
        #expect(WorkspaceBrowserToolbar.canMutate(folder: folder), "«\(folder)» dovrebbe essere mutabile")
    }
}

@Test func canMutateStaysFalseForTheRootSpelledAsASlash() {
    #expect(!WorkspaceBrowserToolbar.canMutate(folder: "/"))
}

@Test func expandAllFoldersReturnsEveryFolderIdOfAFixtureTree() {
    let tree = WorkspaceTree.build(
        boards: ["01 Progetti/vibrofer/vibrofer.canvas", "Labs.canvas"],
        boardPath: testBoardPath(forFolder:)
    )

    let folders = Set(WorkspaceTree.folders(in: tree))

    #expect(folders == ["", "01 Progetti", "01 Progetti/vibrofer"])
}

// MARK: - ADR-0024 Task 4: WorkspaceBrowser.target(for:) (R-06)
//
// R-06's whole content, read as code: the toolbar cannot aim anywhere but the
// visible row, so the read has to be one expression that never branches on which
// case the selection is. All three cases in one test, because a version that
// special-cased `.board` (or `.folder`) would still make each assertion pass on its
// own - it is the shared expression that R-06 is actually about.

@Test func targetForReadsTheSelectionFolderAsOneExpressionRegardlessOfCase() {
    #expect(WorkspaceBrowser.target(for: nil) == "")
    #expect(WorkspaceBrowser.target(for: .folder("A")) == "A")
    #expect(WorkspaceBrowser.target(for: .board(folder: "A")) == "A")
}

// ADR-0024 §D7: withdraws ADR-0022 §D9's fallback onto the open board's folder - with
// nothing selected, "Rinomina"/"Elimina" are disabled rather than aiming at a row
// nobody can see. This is what makes the reversal a decision on the record rather
// than a regression the next reviewer trips over. A coverage pin, not expected to go
// red: `canMutate(folder: "")` is already `false` (see
// `canMutateIsFalseForTheVaultRootAndTrueForAnOrdinaryFolder` above) and
// `target(for: nil)` reads `""` under both the placeholder above and the real
// one-expression logic Task 4's coder writes.
@Test func toolbarCannotMutateWhenNothingIsSelected() {
    #expect(!WorkspaceBrowserToolbar.canMutate(folder: WorkspaceBrowser.target(for: nil)))
}

// ADR-0024 §D7: `rebuild()`'s stale-selection drop must test a selection's path
// against the set that actually contains the root (`""`) - `WorkspaceTree
// .folders(in:)` - and not against a walk of the `NoteTree` it is folded from, which
// has no node for the root at all (F7). Both halves are asserted over the *same*
// fixture, which is what catches Task 3's coder-flagged gap: a rebuild guarded by a
// `NoteTree` folder walk would deselect the root board on every rescan. A coverage
// pin, not expected to go red: the two trees already disagree on `""` by construction.
@Test func workspaceTreeFoldersContainsTheRootWhereTheNoteTreeItIsFoldedFromHasNoNodeAtAll() {
    let boards = ["Labs.canvas", "01 Progetti/01 Progetti.canvas"]
    let noteTree = NoteTree.build(fromPaths: boards)
    let workspaceTree = WorkspaceTree.build(boards: boards, boardPath: testBoardPath(forFolder:))

    #expect(WorkspaceTree.folders(in: workspaceTree).contains(""))
    #expect(!noteTree.contains { $0.kind == .folder && $0.id == "" })
}

// MARK: - Task 6: WorkspaceNameField.state(name:parent:available:) (R-02, R-03, R-04)

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

// MARK: - Task 6: WorkspaceFolderSheets.parentOptions(from:) (ADR-0022 §D11)

@Test func parentOptionsMapsBoardsToRootFirstDeduplicatedAncestorsIncluded() {
    let boards = ["Labs.canvas", "01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas"]

    let options = WorkspaceFolderSheets.parentOptions(from: boards)

    #expect(options == ["", "01 Progetti", "01 Progetti/a", "01 Progetti/b"])
}
