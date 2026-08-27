import Foundation
import Testing
@testable import Pergamenum

// ADR-0025: A folder is a container, a board is a file, and neither is named after the
// other.
// Plan: docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 2.
//
// This file REPLACES ADR-0024 §D2/§D3's fold tests (the ones that asserted a folder and
// the `.canvas` named after it collapse into one row, and that a `.canvas` not named
// after its folder is drawn inert as `.foreignBoard`). Under ADR-0025 a folder and a
// board are always two rows - the fold is gone, and so is the whole notion of a
// "foreign" board: every `.canvas` is an ordinary, openable row wherever it lives
// (R-01, R-03, R-04, R-10, R-11).
//
// RED: `WorkspaceTree.build(folders:boards:)` is a placeholder returning `[]`
// unconditionally, so every assertion built on top of it is red on its
// `#expect`/`#require`, never on a build error - the same discipline the ADR-0024
// predecessor of this file used for its own placeholders. `WorkspaceTree.Node.Kind`'s
// two new cases (`.folder`, `.board(path:)`) exist **alongside** ADR-0024's
// `.workspace`/`.foreignBoard`, which is why `WorkspaceBrowser.swift`'s five exhaustive
// switches over `Kind` needed a placeholder arm each to keep compiling - they are not
// this task's rewrite (`identifier(for:)`/`selection(for:)` are Task 2's GREEN; the
// other three are Task 5's), so those arms return a value that is deliberately wrong
// rather than the coder's answer. `WorkspaceSelection.board(path:)` is a placeholder
// **constructor**, not a real third enum case: Swift resolves `Type.board(label:)` calls
// by argument label like an overloaded function, but a `case .board` *pattern match*
// becomes ambiguous the instant two cases share the base name "board" with different
// labels (confirmed with `swiftc -typecheck` before writing this) - and
// `WorkspaceController.swift` plus `Tests/WorkspaceOpenStateTests.swift`/
// `Tests/WorkspaceBrowserToolbarTests.swift` still construct and pattern-match the
// ADR-0024 `.board(folder:)` case today, unmodified, because they belong to Tasks 3 and
// 5. `WorkspaceSelection.swift`'s doc comment carries the full explanation.

// MARK: - Fixture shared by every WorkspaceTree.build(folders:boards:) test below
//
// Deliberately the shapes R-01, R-03, R-04, R-10 and R-11 name: a root-level board with
// no folder above it (R-11), a folder that owns a board named after itself - now a row
// beside its sibling folders rather than folded into them (R-01) - a folder holding two
// boards, neither special (R-03), an empty folder nested two deep (R-10), and a folder
// whose single board shares no name with it at all (R-04).

private let fixtureFolders = [
    "01 Progetti", "01 Progetti/a", "01 Progetti/b", "Vuota", "Vuota/dentro", "prova",
]

private let fixtureBoards = [
    "Pergamena.canvas",
    "01 Progetti/01 Progetti.canvas",
    "01 Progetti/a/a.canvas",
    "01 Progetti/b/b.canvas", "01 Progetti/b/altro.canvas",
    "prova/prova.canvas",
]

// MARK: - WorkspaceTree.build(folders:boards:) (R-01, R-03, R-04, R-10, R-11)

@Test func buildHasNoRootRowAndOrdersFoldersBeforeLeavesAtTheTopLevel() {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    // No synthesized root: the top level is the vault root's own contents, folders
    // first then leaves - `NoteTree`'s own order (R-11).
    #expect(tree.map(\.id) == ["01 Progetti", "prova", "Vuota", "Pergamena.canvas"])

    // No node with id == "" anywhere in the tree - not only at the top level.
    func walk(_ nodes: [WorkspaceTree.Node]) -> Bool {
        nodes.contains { $0.id.isEmpty || walk($0.children) }
    }
    #expect(!walk(tree))
}

@Test func aRootLevelBoardIsAnOrdinaryTopLevelBoardRowWithNoSynthesis() throws {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let pergamena = try #require(tree.first { $0.id == "Pergamena.canvas" })

    #expect(pergamena.kind == .board(path: "Pergamena.canvas"))
    #expect(pergamena.name == "Pergamena")
    #expect(pergamena.children.isEmpty)
}

@Test func aFolderAndTheBoardNamedAfterItAreTwoSiblingRowsNotOneFoldedRow() throws {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let progetti = try #require(tree.first { $0.id == "01 Progetti" })

    #expect(progetti.kind == .folder)
    // The board this folder owns is a row of its own, beside its sibling folders - the
    // reversal of ADR-0024 §D2, not a child dropped from the list.
    #expect(progetti.children.map(\.id) == [
        "01 Progetti/a", "01 Progetti/b", "01 Progetti/01 Progetti.canvas",
    ])
}

@Test func aFolderWithTwoBoardsHasTwoIndistinguishableBoardChildren() throws {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let progetti = try #require(tree.first { $0.id == "01 Progetti" })
    let b = try #require(progetti.children.first { $0.id == "01 Progetti/b" })

    #expect(b.kind == .folder)
    // Both are `.board`, in the same way - "altro.canvas" is no longer special in any
    // way, which is ADR-0024 §D3's supersession stated as a test.
    #expect(Set(b.children.map(\.id)) == ["01 Progetti/b/b.canvas", "01 Progetti/b/altro.canvas"])
    #expect(b.children.allSatisfy {
        if case .board = $0.kind { true } else { false }
    })
}

@Test func anEmptyNestedFolderExistsAsAFolderNodeWithNoChildren() throws {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let vuota = try #require(tree.first { $0.id == "Vuota" })
    let dentro = try #require(vuota.children.first { $0.id == "Vuota/dentro" })

    // The assertion that proves the tree is not built from `allBoards()` alone - a
    // folder with no `.canvas` anywhere under it still gets a row (R-10).
    #expect(dentro.kind == .folder)
    #expect(dentro.children.isEmpty)
}

@Test func aFolderAndItsUnrelatedlyNamedBoardCarryDifferentIdsAndBothResolve() throws {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let prova = try #require(tree.first { $0.id == "prova" })
    let board = try #require(prova.children.first { $0.id == "prova/prova.canvas" })

    #expect(prova.kind == .folder)
    #expect(board.kind == .board(path: "prova/prova.canvas"))
    #expect(prova.id != board.id)
}

@Test func boardCountCountsEveryBoardAtOrBelowAFolderAndIsZeroForAnEmptyOne() throws {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let progetti = try #require(tree.first { $0.id == "01 Progetti" })
    let vuota = try #require(tree.first { $0.id == "Vuota" })

    // "01 Progetti": its own board (1) + "a"'s board (1) + "b"'s two boards (2) = 4.
    #expect(progetti.boardCount == 4)
    #expect(vuota.boardCount == 0)
}

@Test func numericOrderingPlacesNineBeforeTenAndFoldersBeforeLeavesAtTheSameLevel() {
    // `localizedStandardCompare` (`NoteTree.swift:123, 129`), replicated by
    // `WorkspaceTree.build` rather than restated: "9 Note" sorts before "10 Note", and
    // both folders sort ahead of the leaf at the same level - given deliberately out of
    // order to prove the builder sorts rather than merely preserving input order.
    let tree = WorkspaceTree.build(
        folders: ["10 Note", "9 Note"],
        boards: ["1 Leaf.canvas"]
    )

    #expect(tree.map(\.id) == ["9 Note", "10 Note", "1 Leaf.canvas"])
}

// MARK: - WorkspaceTree.folders(in:) (R-01)

@Test func foldersInReturnsFolderIdsOnlyAndNoBoardPath() {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let folders = WorkspaceTree.folders(in: tree)

    #expect(Set(folders) == Set([
        "01 Progetti", "01 Progetti/a", "01 Progetti/b", "Vuota", "Vuota/dentro", "prova",
    ]))
    #expect(!folders.contains { $0.hasSuffix(".canvas") })
}

// MARK: - WorkspaceTree.node(withID:in:) (R-01, R-03, R-04)

@Test func nodeWithIDFindsAFolderAndABoardAndReturnsNilForAnUnknownID() {
    let tree = WorkspaceTree.build(folders: fixtureFolders, boards: fixtureBoards)

    let folder = WorkspaceTree.node(withID: "01 Progetti/b", in: tree)
    let board = WorkspaceTree.node(withID: "01 Progetti/b/altro.canvas", in: tree)
    let missing = WorkspaceTree.node(withID: "nope", in: tree)

    #expect(folder?.kind == .folder)
    #expect(board?.kind == .board(path: "01 Progetti/b/altro.canvas"))
    #expect(missing == nil)
}

// MARK: - WorkspaceSelection (ADR-0025 §D3)

@Test func boardSelectionsPathIsTheBoardsOwnFileAndFolderIsItsContainingFolder() {
    #expect(WorkspaceSelection.board(path: "A/x.canvas").path == "A/x.canvas")
    #expect(WorkspaceSelection.board(path: "A/x.canvas").folder == "A")
}

@Test func aRootLevelBoardSelectionsFolderIsEmpty() {
    #expect(WorkspaceSelection.board(path: "x.canvas").folder == "")
}

@Test func folderSelectionsPathAndFolderAreBothTheFolderItself() {
    #expect(WorkspaceSelection.folder("A/b").path == "A/b")
    #expect(WorkspaceSelection.folder("A/b").folder == "A/b")
}

@Test func hasBoardIsTrueOnlyForTheBoardCase() {
    #expect(WorkspaceSelection.board(path: "A/x.canvas").hasBoard)
    #expect(!WorkspaceSelection.folder("A").hasBoard)
}

// MARK: - WorkspaceBrowser.identifier(for:) (ADR-0025, no "workspace-foreign-board-" left)
//
// Built directly rather than through `WorkspaceTree.build(folders:boards:)`, which is a
// placeholder that never produces a `.folder`/`.board` node in RED - `identifier(for:)`
// is asked in isolation, the way ADR-0024's predecessor test asked it before any fold
// existed to build the node for it either.

@Test func identifierForABoardIsTheWorkspaceBoardSpellingOverItsOwnPath() {
    let node = WorkspaceTree.Node(
        id: "A/x.canvas", name: "x", kind: .board(path: "A/x.canvas"), children: [], boardCount: 0
    )

    #expect(WorkspaceBrowser.identifier(for: node) == "workspace-board-A/x.canvas")
}

@Test func identifierForAFolderIsTheWorkspaceFolderSpellingOverItsOwnPath() {
    let node = WorkspaceTree.Node(
        id: "Vuota", name: "Vuota", kind: .folder, children: [], boardCount: 0
    )

    #expect(WorkspaceBrowser.identifier(for: node) == "workspace-folder-Vuota")
}

// ADR-0024 §D3's `.foreignBoard` and its `workspace-…-board-` third identifier form are
// gone, not merely untested: the two assertions above are this file's only calls to
// `identifier(for:)`, and neither node is that kind - there is no third spelling because
// nothing here constructs the case that used to produce one (its own assertion at the
// predecessor file's line 185 is deleted, not inverted, since the concept itself is gone).
