import CoreGraphics
import Foundation
import Testing
@testable import Pergamenum

// ADR-0024: One selection, one row, one meaning.
// Plan: docs/superpowers/plans/2026-08-25-workspace-board-tree-single-selection.md, Task 2.
//
// This file REPLACES the `hasOpenBoard`-flag-era tests written for `5041d5c`: the
// controller no longer holds a stored boolean and a separate `closeBoard()`, it holds
// one optional `WorkspaceSelection?` (`current`) that is both "which row is lit" and
// "is a board drawn" (ADR-0024 §D4). Every assertion below reads `current` and the
// derived `isShowingBoard`, never a boolean of its own.
//
// RED: `WorkspaceController.select(_:)`, the `open(folder:)`/`load(folder:)` split,
// `attach`'s and `detach`'s handling of `current`, and `breadcrumb`'s walk are all
// placeholder bodies at this point in the task (no-ops / early returns) - only the
// stored `current` property and the trivial computed `isShowingBoard` are implemented
// in full, since the plan states neither is a judgment call. Every test below is
// therefore expected to fail on its `#expect`, not on a build error; filling in the
// placeholder bodies is the coder's GREEN-section work.

private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-workspace-open-state-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

// MARK: - attach (R-10, first half)

@MainActor
@Test func attachLoadsTheRootBoardWithoutSelectingIt() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    // "Loaded, not chosen" is a two-sided claim: nothing is selected, AND the root
    // board's document is ready the instant the vault attaches.
    #expect(controller.current == nil)
    #expect(controller.isShowingBoard == false)
    #expect(controller.folder == "")
}

// MARK: - open(folder:) (R-04)

@MainActor
@Test func openingAFolderSelectsItsBoard() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    controller.open(folder: "")

    #expect(controller.current == .board(folder: ""))
    #expect(controller.isShowingBoard == true)
}

// MARK: - select(_:) (R-04)

@MainActor
@Test func selectingABoardlessFolderClosesTheOpenBoard() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))
    controller.open(folder: "")
    controller.selection = ["some-card-id"]

    controller.select(.folder("Progetti"))

    #expect(controller.current == .folder("Progetti"))
    #expect(controller.isShowingBoard == false)
    #expect(controller.selection.isEmpty)
}

// MARK: - select(nil) (R-11 - this is what `closeBoard()` was)

@MainActor
@Test func selectingNilClosesTheBoard() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))
    controller.open(folder: "")

    controller.select(nil)

    #expect(controller.current == nil)
    #expect(controller.isShowingBoard == false)
}

// MARK: - select(_:) no-op guard (ADR-0024 §D4)

@MainActor
@Test func selectingTheSameBoardTwiceLeavesZoomAndPanUntouched() throws {
    // This is the whole reason `select(_:)` guards `new != current`: without it,
    // ADR-0023 §D4's context menu (which sets the selection before raising a sheet)
    // would re-open the board already on screen and reset the zoom and pan of
    // whatever the user was looking at.
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    controller.select(.board(folder: "A"))
    controller.zoom = 2.5
    controller.pan = CGSize(width: 40, height: -12)

    controller.select(.board(folder: "A"))

    #expect(controller.zoom == 2.5)
    #expect(controller.pan == CGSize(width: 40, height: -12))
}

// MARK: - detach

@MainActor
@Test func detachClearsTheSelection() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))
    controller.open(folder: "")

    controller.detach()

    #expect(controller.current == nil)
}

// MARK: - breadcrumb (ADR-0024 §D8.1)

@MainActor
@Test func breadcrumbFollowsTheSelectionNotTheLoadedDocument() throws {
    // A `.folder(F)` selection loads nothing (§D4), so the breadcrumb has to walk
    // `current`, not the last-loaded `folder` - otherwise it would keep showing the
    // previous board's trail while the tree showed a board-less folder as selected.
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))

    controller.select(.folder("01 Progetti/a"))

    #expect(controller.breadcrumb.map(\.title) == ["Workspace", "01 Progetti", "a"])
}
