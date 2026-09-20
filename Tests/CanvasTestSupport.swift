import Foundation
@testable import Pergamenum

/// A throwaway directory a canvas or workspace test builds boards in, with the two helpers
/// those tests reach for. It is the second shared throwaway fixture beside `TemporaryVault`
/// (ADR-0051 §D2, PG-176), and the only other one a suite should adopt: it is a plain
/// directory, not a vault, so it makes no `stateBase` that nothing here would read.
///
/// Its root is `url`, not `root`. The four private copies this replaced each named it `url`
/// and each was a strict subset of this one, so adopting it changes a type name and nothing else.
struct CanvasTemporaryRoot: ~Copyable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-canvas-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func makeDirectory(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: url.appending(path: relativePath, directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    func makeFile(_ relativePath: String, _ contents: String = "x") throws {
        let fileURL = url.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: fileURL)
    }
}

/// A `WorkspaceController` attached to a fresh store with one board already created and
/// open at the vault root - the fixture every controller test that mutates a document
/// needs, since `attach` alone opens nothing (ADR-0025 §D4) and `mutate` now refuses to
/// write without an open board (PG-062).
@MainActor
func openedWorkspaceController(rootURL: URL) throws -> WorkspaceController {
    let store = CanvasStore(root: rootURL)
    let controller = WorkspaceController()
    controller.attach(to: store)
    let board = try store.createBoard(named: rootURL.lastPathComponent, in: "")
    controller.open(board: board)
    return controller
}
