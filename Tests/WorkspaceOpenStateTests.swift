import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0025: a board is addressed by its own file path, never derived from the folder
// holding it - a folder may hold any number of boards under any name, and `attach`
// loads nothing at all (§D1, §D4).
// Plan: docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md, Task 3.
//
// Lineage (ADR-0024): this file keeps that chain's own note true - the controller holds
// one optional `WorkspaceSelection?` (`current`) that is both "which row is lit" and "is
// a board drawn" (ADR-0024 §D4). Every assertion below reads `current` and the derived
// `isShowingBoard`, never a boolean of its own. What changes in this pass is the
// payload: `.board` now carries the board's own file path rather than a folder name
// (ADR-0025 §D3), so every test that opens a board opens it **by path**, and - because
// `load(board:)` throws on a miss (§D1) rather than returning `.empty` - creates the
// file first with `CanvasStore.createBoard(named:in:)` wherever GREEN needs it to
// actually exist.
//
// RED: `WorkspaceController.open(board:)` is a placeholder (empty body) at this point in
// the task - see the doc comment beside it in `WorkspaceController.swift`. `attach`,
// `select(_:)` and `breadcrumb` are still their ADR-0024 bodies, unmodified. Every test
// below is expected to fail on its `#expect`, not on a build error; filling in the
// placeholder and rewiring `attach`/`select`/`breadcrumb` is the coder's GREEN-section
// work.

private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-workspace-open-state-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeDirectory(_ relativePath: String, in root: URL) throws {
    try FileManager.default.createDirectory(
        at: root.appending(path: relativePath, directoryHint: .isDirectory),
        withIntermediateDirectories: true
    )
}

// MARK: - attach (F7, R-10 first half)

@MainActor
@Test func attachLoadsNothingAndSelectsNothing() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    // "Loaded, not chosen" (ADR-0024) becomes "not loaded at all" (ADR-0025 §D4): there
    // is no root board to load any more, so `attach` leaves the board slot as empty as
    // the selection.
    #expect(controller.current == nil)
    #expect(controller.isShowingBoard == false)
    #expect(controller.board == "")
    #expect(controller.folder == "")
    #expect(controller.document == .empty)
}

// MARK: - open(board:) (R-06)

@MainActor
@Test func openingAnExistingBoardSelectsItByItsOwnPath() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    try makeDirectory("A", in: root)
    let path = try store.createBoard(named: "x", in: "A")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.open(board: path)

    #expect(controller.current == .board(path: path))
    #expect(controller.board == path)
    #expect(controller.folder == "A")
    #expect(controller.isShowingBoard == true)
}

@MainActor
@Test func openingTwoBoardsInTheSameFolderEachLoadsItsOwnDocument() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    try makeDirectory("A", in: root)
    let uno = try store.createBoard(named: "uno", in: "A")
    try store.save(
        CanvasDocument(nodes: [CanvasNode(id: CanvasID.generate(), kind: .text("uno"), x: 0, y: 0, width: 100, height: 100)]),
        board: uno
    )
    let due = try store.createBoard(named: "due", in: "A")
    try store.save(
        CanvasDocument(nodes: [
            CanvasNode(id: CanvasID.generate(), kind: .text("a"), x: 0, y: 0, width: 100, height: 100),
            CanvasNode(id: CanvasID.generate(), kind: .text("b"), x: 200, y: 0, width: 100, height: 100)
        ]),
        board: due
    )
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.open(board: uno)
    #expect(controller.folder == "A")
    #expect(controller.document.nodes.count == 1)

    controller.open(board: due)
    // Board identity is the path, not the folder (R-06, R-03's controller half): two
    // boards sharing a folder must each load its own document, not silently keep
    // serving whichever one the folder used to imply (ADR-0025 F1).
    #expect(controller.folder == "A")
    #expect(controller.document.nodes.count == 2)
    #expect(controller.current == .board(path: due))
}

@MainActor
@Test func openingAMissingBoardPathSelectsNothingAndRecordsAProblem() async throws {
    let vault = try TemporaryVault()
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)

    let workspace = WorkspaceController()
    workspace.attach(to: CanvasStore(root: vault.root), vault: vaultController)
    let currentBefore = workspace.current
    let showingBefore = workspace.isShowingBoard

    workspace.open(board: "A/non-esiste.canvas")

    // The successor to `load(folder:)`'s silent `.empty` (ADR-0025 §D1/§D4): a board
    // that is not there is reported, not rendered blank, and nothing is selected.
    #expect(workspace.current == currentBefore)
    #expect(workspace.isShowingBoard == showingBefore)
    #expect(!vaultController.problems.isEmpty)
    vaultController.close()
}

@MainActor
@Test func openingABoardAtTheVaultRootGivesAnEmptyFolder() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    let path = try store.createBoard(named: "Pergamena", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.open(board: path)

    #expect(controller.folder == "")
    #expect(controller.current == .board(path: path))
}

// MARK: - select(_:) (ADR-0024 §D4, re-asserted against the path-addressed `.board` case)

@MainActor
@Test func selectingABoardlessFolderClosesTheOpenBoard() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    let path = try store.createBoard(named: "Root", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: path)
    controller.selection = ["some-card-id"]

    controller.select(.folder("Progetti"))

    #expect(controller.current == .folder("Progetti"))
    #expect(controller.isShowingBoard == false)
    #expect(controller.selection.isEmpty)
}

@MainActor
@Test func selectingNilClosesTheBoard() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    let path = try store.createBoard(named: "Root", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: path)

    controller.select(nil)

    #expect(controller.current == nil)
    #expect(controller.isShowingBoard == false)
}

@MainActor
@Test func selectingTheSameBoardTwiceLeavesZoomAndPanUntouched() throws {
    // The whole reason `select(_:)` guards `new != current`: without it, ADR-0023 §D4's
    // context menu (which sets the selection before raising a sheet) would re-open the
    // board already on screen and reset the zoom and pan of whatever the user was
    // looking at.
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    try makeDirectory("A", in: root)
    let path = try store.createBoard(named: "x", in: "A")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.select(.board(path: path))
    controller.zoom = 2.5
    controller.pan = CGSize(width: 40, height: -12)

    controller.select(.board(path: path))

    #expect(controller.zoom == 2.5)
    #expect(controller.pan == CGSize(width: 40, height: -12))
}

// MARK: - detach

@MainActor
@Test func detachClearsTheSelection() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    let path = try store.createBoard(named: "Root", in: "")
    let controller = WorkspaceController()
    controller.attach(to: store)
    controller.open(board: path)

    controller.detach()

    #expect(controller.current == nil)
}

// MARK: - breadcrumb (ADR-0024 §D8.1, extended by R-12)

@MainActor
@Test func breadcrumbWithNothingSelectedIsExactlyTheRootAndNothingMore() throws {
    // `navigatesTheBoardHierarchyWithABreadcrumb` (Tests/CanvasTests.swift) already pins
    // the *title* half of this ("Workspace" alone after `attach`) and passes unchanged
    // by this task. This pins the whole tuple - title AND folder - and the count.
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    #expect(controller.current == nil)
    let trail = controller.breadcrumb
    #expect(trail.count == 1)
    #expect(trail.map(\.title) == ["Workspace"])
    #expect(trail.map(\.folder) == [""])
}

@MainActor
@Test func breadcrumbMovesForABoardlessFolderSelectionWithNoBoardOnScreen() throws {
    // Selecting a board-less folder opens nothing (`isShowingBoard` stays false, §D5),
    // yet the breadcrumb still moves to name it, because it walks `current` rather than
    // the last-loaded document (ADR-0024 §D8.1).
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    controller.select(.folder("Vuota"))

    #expect(controller.isShowingBoard == false)
    #expect(controller.breadcrumb.map(\.title) == ["Workspace", "Vuota"])
}

@MainActor
@Test func breadcrumbNamesTheBoardsOwnFileAsItsLastSegmentNotTheFolder() throws {
    // R-12's chrome half: the last segment names the `.canvas` file, not the folder
    // holding it - the two can differ now that a board is addressed by its own path
    // (ADR-0025 §D3), so the breadcrumb has one more segment than the folder has
    // components whenever the board's name does not match its folder's.
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    try makeDirectory("01 Progetti/vibrofer-emea", in: root)
    let path = try store.createBoard(named: "board", in: "01 Progetti/vibrofer-emea")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.select(.board(path: path))

    #expect(controller.breadcrumb.map(\.title) == ["Workspace", "01 Progetti", "vibrofer-emea", "board"])
}

// MARK: - openRoute (F6, R-12)

@MainActor
@Test func openRouteOpensTheExactPathTheRouteCarriesNotTheFoldersDerivedBoard() throws {
    let root = try makeTempRoot()
    let store = CanvasStore(root: root)
    try makeDirectory("A", in: root)
    let altroPath = try store.createBoard(named: "altro", in: "A")
    let controller = WorkspaceController()
    controller.attach(to: store)

    controller.openRoute((path: altroPath, nodeID: nil), viewport: .zero)

    // F6 of ADR-0025: a `pergamenum://canvas?file=A/altro.canvas` link must open exactly
    // that file, not the folder-derived `A/A.canvas` the old `open(folder:)` path opened
    // instead - the defect this task closes.
    #expect(controller.current == .board(path: altroPath))
}
