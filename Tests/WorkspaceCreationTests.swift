import Foundation
import Testing
@testable import Pergamenum

// ADR-0025: A folder is a container, a board is a file, and neither is named after the
// other.
// Plan: docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 6.
//
// R-01, R-02. `WorkspaceView+FolderVerbs.createWorkspace(named:in:)` is `@MainActor` view
// code and is not instantiated here; what is asserted instead is the pure boundary the
// dispatch brief names - `CanvasStore` and `WorkspaceTree` directly, the split
// ADR-0022 §D11 already established for the sheet's own predicate.
//
// No placeholder signature is declared in this file: every member the four assertions
// below need - `CanvasStore.createFolder(named:in:)`, `createBoard(named:in:)`,
// `allFolders()`, `allBoards()`, `WorkspaceTree.build(folders:boards:)`,
// `WorkspaceTree.node(withID:in:)` and `WorkspaceFolderSheets.parentOptions(from:)` -
// already exists with a real body, from Tasks 1, 2 and 5 of this same chain. Three of the
// four assertions below therefore already pass: `CanvasStore.createFolder(named:in:)`
// never wrote a board even before this chain (the false-claims table's second row), and
// `WorkspaceTree.build` has represented an empty folder correctly since Task 2. They stay
// in this file rather than being dropped, because they are the closest a unit test can
// get to pinning R-01/R-02 without instantiating `WorkspaceView` - the actual RED subject,
// `WorkspaceView+FolderVerbs.swift:32`'s `try store.save(.empty, folder: created)`, is
// `@MainActor` view code this file cannot reach, and stays the coder's GREEN-phase
// deletion. The fourth assertion, on `WorkspaceFolderSheets.parentOptions(from:)`, is
// genuinely RED under the current implementation: fed a plain folder list the way
// `allFolders()` produces it (ancestors and leaves alike, not derived from board paths),
// today's `parentOptions` only recovers the *ancestors* of what it is handed and drops a
// leaf folder that holds no further subfolder of its own - see the test below for the
// worked trace.

// MARK: - Fixture

private struct TemporaryRoot: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-workspace-creation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: relativePath, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }
}

// MARK: - Creating a folder creates no board (R-01)

@Test func createFolderShowsNoNewCanvasThroughAllBoards() throws {
    let root = try TemporaryRoot()
    let store = CanvasStore(root: root.url)
    let boardsBefore = Set(store.allBoards())

    let created = try store.createFolder(named: "Nuova", in: "")

    let boardsAfter = Set(store.allBoards())
    #expect(boardsAfter == boardsBefore)
    #expect(!boardsAfter.contains("\(created)/\(created).canvas"))
    #expect(!boardsAfter.contains("\(created).canvas"))
}

@Test func createFolderAppearsInTheTreeAsAnExpandableFolderWithNoChildren() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("01 Progetti")
    let store = CanvasStore(root: root.url)

    let created = try store.createFolder(named: "Nuova", in: "01 Progetti")
    #expect(created == "01 Progetti/Nuova")

    let tree = WorkspaceTree.build(folders: store.allFolders(), boards: store.allBoards())
    let node = try #require(WorkspaceTree.node(withID: created, in: tree))
    #expect(node.kind == .folder)
    #expect(node.children.isEmpty)
}

// MARK: - Creating a board creates no folder (R-02)

@Test func createBoardAppearsInTheTreeAsABoardRowWithNoNewFolder() throws {
    let root = try TemporaryRoot()
    try root.makeDirectory("A")
    let store = CanvasStore(root: root.url)
    let foldersBefore = Set(store.allFolders())

    let created = try store.createBoard(named: "qualsiasi-nome", in: "A")
    #expect(created == "A/qualsiasi-nome.canvas")

    // No new folder appeared beyond what already existed - a board is a file, not a
    // directory named after it (R-02).
    let foldersAfter = Set(store.allFolders())
    #expect(foldersAfter == foldersBefore)

    let tree = WorkspaceTree.build(folders: store.allFolders(), boards: store.allBoards())
    let node = try #require(WorkspaceTree.node(withID: created, in: tree))
    #expect(node.kind == .board(path: created))

    // The board sits inside the folder it was created in, as that folder's own child
    // row, never as a detached top-level one.
    let folderNode = try #require(WorkspaceTree.node(withID: "A", in: tree))
    #expect(folderNode.children.contains { $0.id == created })
}

// MARK: - The parent picker is fed from `allFolders()`, not from board-path ancestors
// (ADR-0022 §D11's objection to `vault.folders`, finally answerable)

@Test func parentOptionsOffersAFolderThatHoldsOnlySubfoldersAndOneThatHoldsOnlyBoards() {
    // Shaped exactly as `CanvasStore.allFolders()` returns it: every real directory,
    // "A" (holds only the subfolder "A/B", no board of its own) and "A/B" (holds only a
    // board, no subfolder of its own) both included as plain entries - never derived
    // from a list of board paths.
    //
    // Traced against today's implementation: `parentOptions(from:)` walks each element
    // it is handed as if it were a *board* path and inserts only its ancestors via
    // `deletingLastPathComponent`. Fed "A", the ancestor is "" (nothing inserted). Fed
    // "A/B", the ancestor is "A" (inserted) and then "" (loop stops). "A/B" itself is
    // never inserted - only ever an ancestor's ancestor is, never the leaf handed in -
    // so the folder that holds only a board is silently missing from the picker.
    let folders: [FolderPath] = ["A", "A/B"]

    let options = WorkspaceFolderSheets.parentOptions(from: folders)

    #expect(options.contains("A"))
    #expect(options.contains("A/B"))
}
