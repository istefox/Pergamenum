import Foundation
import Testing
@testable import Pergamenum

/// `WorkspaceController.hasOpenBoard`: whether a board has been chosen, as opposed to
/// merely loaded and ready. `attach` prepares the root board so it is ready the instant
/// it is picked, but that preparation must not itself read as a choice - see the
/// Workspace pane's empty state, which is driven by this flag rather than by `folder`.

private func makeTempRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-workspace-open-state-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor
@Test func attachingDoesNotOpenABoard() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))
    #expect(controller.hasOpenBoard == false)
}

@MainActor
@Test func openingAFolderMarksTheBoardOpen() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))
    controller.open(folder: "")
    #expect(controller.hasOpenBoard == true)
}

@MainActor
@Test func detachingClosesTheBoardAgain() throws {
    let root = try makeTempRoot()
    let controller = WorkspaceController()
    controller.attach(to: CanvasStore(root: root))
    controller.open(folder: "")
    controller.detach()
    #expect(controller.hasOpenBoard == false)
}
