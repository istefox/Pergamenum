import Foundation
import Testing
@testable import Pergamenum

// ADR-0022: Creating, renaming and deleting a workspace is a folder operation,
// performed outside the journal.
// Plan: docs/superpowers/plans/2026-08-25-workspace-ui-creazione-board-toolbar-e-r.md,
// Tasks 5-6.
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
