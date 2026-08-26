import Foundation
import Testing
@testable import Pergamenum

// ADR-0024: One selection, one row, one meaning.
// Plan: docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md, Task 1.
//
// The two pure types this feature is built from, neither importing SwiftUI so a test can
// ask them directly: the single selection value (ADR-0024 §D4, R-04/R-05) and the fold
// that turns `NoteTree.build(fromPaths:)`'s output into one row per folder, the board it
// owns drawn on that row rather than beside it (ADR-0024 §D2/§D3, R-01/R-03/R-05).
//
// RED: `WorkspaceSelection.folder`/`.hasBoard` are trivial and already correct (given
// verbatim by the plan, so those two assertions are not expected to fail). Everything
// against `WorkspaceTree.build`/`.folders(in:)`/`.flattened(_:)`/`.node(withID:in:)` is
// red on its assertions: the four functions are placeholders returning `[]`/`nil`, never
// a `fatalError()` or a force-unwrap, so the target still builds.
//
// Extended for Task 3 (the two pure functions its view-level rewrite reads, R-09 and
// ADR-0024 §D10): `WorkspaceBrowser.rows(matching:in:)` and `WorkspaceBrowser
// .identifier(for:)` are likewise placeholders (`[]` and `""`), red on their
// assertions rather than on a build error.

// MARK: - WorkspaceSelection (R-01, R-03, R-05)

@Test func workspaceSelectionFolderReturnsTheAssociatedPathForBothCases() {
    #expect(WorkspaceSelection.board(folder: "01 Progetti").folder == "01 Progetti")
    #expect(WorkspaceSelection.folder("01 Progetti").folder == "01 Progetti")
}

@Test func workspaceSelectionHasBoardIsTrueOnlyForTheBoardCase() {
    #expect(WorkspaceSelection.board(folder: "01 Progetti").hasBoard)
    #expect(!WorkspaceSelection.folder("01 Progetti").hasBoard)
}

// MARK: - Fixture shared by every WorkspaceTree test below

// ADR-0024 §D2/§D3's four cases in one vault: a root board, a folder whose own board is
// named after it (with two sub-folders under it), a folder that only groups (no board of
// its own) and a folder holding a `.canvas` that is *not* named after it - the "foreign
// board" case §D3 exists for.
private let fixtureBoards = [
    "Labs.canvas",
    "01 Progetti/01 Progetti.canvas",
    "01 Progetti/a/a.canvas",
    "01 Progetti/b/b.canvas",
    "01 Progetti/b/altro.canvas",
    "Vuota/dentro/dentro.canvas",
]

// The real rule (`CanvasStore.boardPath(forFolder:)`), stubbed rather than reached
// through a `CanvasStore`/vault on disk - `boardPath` is a closure asked, never restated
// (ADR-0024 §D2), so the transform under test never restates it either.
private func fixtureBoardPath(_ folder: String) -> String {
    folder.isEmpty
        ? "Labs.canvas"
        : "\(folder)/\((folder as NSString).lastPathComponent).canvas"
}

// MARK: - WorkspaceTree.build(boards:boardPath:) (R-01, R-03, R-05)

@Test func buildFoldsAFolderAndItsOwnBoardIntoOneNodeOverTheADR0024Fixture() throws {
    let tree = WorkspaceTree.build(boards: fixtureBoards, boardPath: fixtureBoardPath)

    // Top level: folders first, then leaves - NoteTree's own order - and the root board
    // is the row for folder "" (F7: NoteTree emits no root node, so this synthesizes it).
    #expect(tree.map(\.id) == ["01 Progetti", "Vuota", ""])
    let root = try #require(tree.first { $0.id == "" })
    #expect(root.name == "Labs")

    // "01 Progetti" carries its own board, and the board's leaf is not a separate child
    // row among its children.
    let progetti = try #require(tree.first { $0.id == "01 Progetti" })
    #expect(progetti.kind == .workspace(board: "01 Progetti/01 Progetti.canvas"))
    #expect(progetti.children.map(\.id) == ["01 Progetti/a", "01 Progetti/b"])

    // "Vuota" owns no board of its own - a board-less folder is a node, not an omission
    // (R-05, Decision 3).
    let vuota = try #require(tree.first { $0.id == "Vuota" })
    #expect(vuota.kind == .workspace(board: nil))
    #expect(vuota.children.map(\.id) == ["Vuota/dentro"])

    // "01 Progetti/b/altro.canvas" is not named after the folder holding it - it survives
    // as a `.foreignBoard` node of its own, the only child "01 Progetti/b" has.
    let b = try #require(progetti.children.first { $0.id == "01 Progetti/b" })
    #expect(b.children.map(\.kind) == [.foreignBoard(path: "01 Progetti/b/altro.canvas")])

    // boardCount is NoteTree.Node.noteCount carried through unchanged: a (1) + b (b.canvas
    // + altro.canvas = 2) + "01 Progetti"'s own board leaf (1) = 4.
    #expect(progetti.boardCount == 4)
}

// MARK: - WorkspaceTree.folders(in:) (R-01, R-03, R-05)

@Test func foldersInIncludesTheRootAndExcludesEveryForeignBoardPath() {
    let tree = WorkspaceTree.build(boards: fixtureBoards, boardPath: fixtureBoardPath)

    let folders = WorkspaceTree.folders(in: tree)

    #expect(Set(folders) == Set([
        "", "01 Progetti", "01 Progetti/a", "01 Progetti/b", "Vuota", "Vuota/dentro",
    ]))
    #expect(!folders.contains("01 Progetti/b/altro.canvas"))
}

// MARK: - WorkspaceTree.flattened(_:) (R-01, R-03, R-05)

@Test func flattenedWalksDepthFirstWithDepthAndIncludesTheRootRow() {
    let tree = WorkspaceTree.build(boards: fixtureBoards, boardPath: fixtureBoardPath)

    let flat = WorkspaceTree.flattened(tree)

    #expect(flat.map(\.node.id) == [
        "01 Progetti", "01 Progetti/a", "01 Progetti/b", "01 Progetti/b/altro.canvas",
        "Vuota", "Vuota/dentro",
        "",
    ])
    #expect(flat.map(\.depth) == [0, 1, 1, 2, 0, 1, 0])
}

// MARK: - WorkspaceTree.node(withID:in:) (R-01, R-03, R-05)

@Test func nodeWithIDFindsTheRootAndANestedFolderAndReturnsNilForAForeignBoardPath() throws {
    let tree = WorkspaceTree.build(boards: fixtureBoards, boardPath: fixtureBoardPath)

    let root = try #require(WorkspaceTree.node(withID: "", in: tree))
    #expect(root.name == "Labs")

    let nested = try #require(WorkspaceTree.node(withID: "01 Progetti/b", in: tree))
    #expect(nested.kind == .workspace(board: "01 Progetti/b/b.canvas"))

    #expect(WorkspaceTree.node(withID: "01 Progetti/b/altro.canvas", in: tree) == nil)
}

// MARK: - WorkspaceBrowser.rows(matching:in:) (R-09)
//
// ADR-0024 Task 3: the filtered list's input. `WorkspaceBrowser.rows(matching:in:)` is
// a placeholder returning `[]`, so both assertions below are red on their expectations,
// never on a build error.

@Test func rowsMatchingReturnsWorkspaceRowsByIdOrNameCaseInsensitivelyAndFindsTheRootByName() throws {
    let tree = WorkspaceTree.build(boards: fixtureBoards, boardPath: fixtureBoardPath)

    // "a" over the ADR-0024 fixture: "01 Progetti/a" (id ends in "a"), "Vuota" and
    // "Vuota/dentro" (both paths carry "Vuota", which contains "a") and the root, whose
    // id is "" - never a match on its own - reachable only because its name "Labs" is.
    // "01 Progetti" and "01 Progetti/b" contain no "a" in either id or name and are
    // excluded, and the `.foreignBoard` "01 Progetti/b/altro.canvas" is excluded even
    // though its path contains "a", because only `.workspace` rows are ever selectable
    // (ADR-0024 §D3) and a search result a click cannot act on is not a result.
    let matches = WorkspaceBrowser.rows(matching: "a", in: tree)

    #expect(Set(matches.map(\.id)) == Set(["01 Progetti/a", "Vuota", "Vuota/dentro", ""]))
    #expect(!matches.contains { if case .foreignBoard = $0.kind { true } else { false } })

    let root = try #require(matches.first { $0.id == "" })
    #expect(root.name == "Labs")
}

// MARK: - WorkspaceBrowser.identifier(for:) (ADR-0024 §D10)
//
// `WorkspaceBrowser.identifier(for:)` is a placeholder returning `""`, so every
// assertion below is red on its expectation, never on a build error.

@Test func identifierForSpellsTheThreeADR0024IdentifierFormsAndTheRootIsWorkspaceBoardLabs() throws {
    let tree = WorkspaceTree.build(boards: fixtureBoards, boardPath: fixtureBoardPath)

    // The root row owns the vault's board, so it gets the board form - and it is the
    // exact string `UITests/WorkspaceOpenStateUITests.swift:39` already builds today
    // (ADR-0024 §D10 preserves it byte-identical).
    let root = try #require(WorkspaceTree.node(withID: "", in: tree))
    #expect(WorkspaceBrowser.identifier(for: root) == "workspace-board-Labs.canvas")

    // "Vuota" owns no board of its own - the folder form.
    let vuota = try #require(WorkspaceTree.node(withID: "Vuota", in: tree))
    #expect(WorkspaceBrowser.identifier(for: vuota) == "workspace-folder-Vuota")

    // "01 Progetti/b/altro.canvas" is a `.foreignBoard` - the third form, distinct from
    // both, so a test can tell "unopenable by design" from "missing" (ADR-0024 §D10).
    let progetti = try #require(WorkspaceTree.node(withID: "01 Progetti", in: tree))
    let b = try #require(progetti.children.first { $0.id == "01 Progetti/b" })
    let foreign = try #require(
        b.children.first { if case .foreignBoard = $0.kind { true } else { false } }
    )
    #expect(WorkspaceBrowser.identifier(for: foreign) == "workspace-foreign-board-01 Progetti/b/altro.canvas")
}
