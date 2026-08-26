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
// `WorkspaceBrowser.allFolders(in:)` is pre-existing, already-correct logic behind
// "Espandi tutto" - widened from `private` to internal so this file can reach it -
// and its test is a coverage pin, not expected to fail.
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
// coder flag `rebuild()`'s stale-selection check (the naive `NoteTree`-based
// `allFolders(in:)` has no node for the root).

// MARK: - Task 5: WorkspaceBrowserToolbar.canMutate(folder:) (R-09)

@Test func canMutateIsFalseForTheVaultRootAndTrueForAnOrdinaryFolder() {
    #expect(!WorkspaceBrowserToolbar.canMutate(folder: ""))
    #expect(WorkspaceBrowserToolbar.canMutate(folder: "01 Progetti"))
}

// MARK: - Task 5: WorkspaceBrowser.allFolders(in:) (R-01)

// The toolbar's "Espandi tutto" button drives the same `expanded` binding the tree's
// context menu already does (ADR-0022 §D8) - this pins the fixture shape the button
// will read, not new behaviour.
// MARK: - ADR-0023 Task 4: WorkspaceBrowser.allFolders(in:) fed by NoteTree.build(fromPaths:) (R-01, R-02)
//
// ADR-0023: A command is named once and rendered twice.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 4.
//
// R-02 as a property of the tree, not of a guard: `NoteTree.build(fromPaths:)` never
// produces a folder node for the vault root - no path component names it, so there is no
// root row for a context menu to hide Rinomina/Elimina from in the first place. Both
// `WorkspaceBrowser.allFolders(in:)` and `WorkspaceBrowserToolbar.canMutate(folder:)`
// already exist and are already correct (ADR-0022); these two tests are coverage pins
// over the real board-path builder rather than new logic, so they are not expected to go
// red on their assertions - the SPEC correction they back (SPEC "Three things ... false"
// table) is what makes them worth pinning down here, ahead of Task 4's context-menu GREEN.

@Test func allFoldersOfATreeBuiltFromRealBoardPathsExcludesTheRootAndEveryMemberIsMutable() {
    let tree = NoteTree.build(fromPaths: [
        "Labs.canvas", "01 Progetti/a/a.canvas", "01 Progetti/b/b.canvas",
    ])

    let folders = WorkspaceBrowser.allFolders(in: tree)

    #expect(folders == ["01 Progetti", "01 Progetti/a", "01 Progetti/b"])
    #expect(!folders.contains(""))
    for folder in folders {
        #expect(WorkspaceBrowserToolbar.canMutate(folder: folder), "«\(folder)» dovrebbe essere mutabile")
    }
}

@Test func canMutateStaysFalseForTheRootSpelledAsASlash() {
    #expect(!WorkspaceBrowserToolbar.canMutate(folder: "/"))
}

@Test func allFoldersReturnsEveryFolderIdOfAFixtureTree() {
    let tree: [NoteTree.Node] = [
        NoteTree.Node(
            id: "01 Progetti",
            name: "01 Progetti",
            kind: .folder,
            children: [
                NoteTree.Node(
                    id: "01 Progetti/vibrofer",
                    name: "vibrofer",
                    kind: .folder,
                    children: [
                        NoteTree.Node(
                            id: "01 Progetti/vibrofer/vibrofer.canvas",
                            name: "vibrofer",
                            kind: .note,
                            children: nil,
                            noteCount: 1
                        ),
                    ],
                    noteCount: 1
                ),
            ],
            noteCount: 1
        ),
        NoteTree.Node(id: "Labs.canvas", name: "Labs", kind: .note, children: nil, noteCount: 1),
    ]

    let folders = WorkspaceBrowser.allFolders(in: tree)

    #expect(folders == ["01 Progetti", "01 Progetti/vibrofer"])
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
// .folders(in:)` - not the `NoteTree`-based `WorkspaceBrowser.allFolders(in:)`, which
// has no node for the root at all (F7). Built over the *same* fixture, this is what
// catches Task 3's coder-flagged gap: a rebuild still guarded by `allFolders(in:)`
// would deselect the root board on every rescan. A coverage pin, not expected to go
// red: both functions already exist and already disagree on `""`.
@Test func workspaceTreeFoldersContainsTheRootWhereTheNaiveAllFoldersDoesNot() {
    let boards = ["Labs.canvas", "01 Progetti/01 Progetti.canvas"]
    let noteTree = NoteTree.build(fromPaths: boards)
    let workspaceTree = WorkspaceTree.build(boards: boards) { folder in
        folder.isEmpty ? "Labs.canvas" : "\(folder)/\((folder as NSString).lastPathComponent).canvas"
    }

    #expect(WorkspaceTree.folders(in: workspaceTree).contains(""))
    #expect(!WorkspaceBrowser.allFolders(in: noteTree).contains(""))
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
