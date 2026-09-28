import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// ADR-0066 §D6 point 6 (PG-287): the fit-on-open in `WorkspaceView` keys on `workspace.board`,
/// not `workspace.folder`. Two boards in one folder each open framed on their own content.
///
/// The real `WorkspaceView` is hosted here, not a replica: the modifier under test lives in its
/// `body`, so only the production view can pin it. Its `WorkspaceController` is `@State` inside
/// the view and reached through `VaultController.openBoard`, the weak reference `attach` sets
/// (ADR-0066 §D5). The boards hold file cards only: a text card needs `CommandActions` and
/// through it `EventKitStore`, which the hosted-view harness keeps out (R-15).
///
/// Red against the pre-fix `.onChange(of: workspace.folder)`: both boards share folder `F`, so
/// opening the second changed nothing the modifier watched, and its card, thousands of points
/// away from the first board's, stayed off screen.
@MainActor
@Suite(.serialized)
struct WorkspaceFitOnOpenHostedTests {
    private static let size = CGSize(width: 1200, height: 800)

    /// Writes a board in `F` with one file card at `point`, through the store, and returns its path.
    private static func board(
        _ name: String, cardAt point: CGPoint, in store: CanvasStore
    ) throws -> (path: String, card: CGRect) {
        let path = try store.createBoard(named: name, in: "F")
        let writer = WorkspaceController()
        writer.attach(to: store)
        writer.open(board: path)
        let id = writer.placeFile("F/\(name).png", at: point)
        let frame = try #require(writer.document.node(id: id)).frame
        writer.detach()
        return (path, frame)
    }

    /// Where `frame` lands in the view after zoom and pan, the placement `WorkspaceView`
    /// applies to its content layer (`scaleEffect` from the top leading corner, then `offset`).
    private static func onScreen(_ frame: CGRect, _ workspace: WorkspaceController) -> CGRect {
        CGRect(
            x: frame.minX * workspace.zoom + workspace.pan.width,
            y: frame.minY * workspace.zoom + workspace.pan.height,
            width: frame.width * workspace.zoom,
            height: frame.height * workspace.zoom
        )
    }

    @Test func aSecondBoardInTheSameFolderOpensFramedOnItsOwnContent() async throws {
        let vault = try TemporaryVault()
        try FileManager.default.createDirectory(
            at: vault.root.appending(path: "F", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        let store = CanvasStore(root: vault.root)
        let first = try Self.board("Uno", cardAt: CGPoint(x: 6000, y: 4000), in: store)
        let second = try Self.board("Due", cardAt: CGPoint(x: -9000, y: -7000), in: store)

        let controller = VaultController(
            recents: .volatile(), openTabs: .volatile(), pinnedTags: .volatile()
        )
        await controller.open(vault.root)
        defer { controller.close() }

        let host = HostedView(
            WorkspaceView()
                .environment(controller)
                .environment(Navigation())
                .environment(ThemeEngine())
                .environment(\.theme, .emergency),
            size: Self.size
        )
        defer { host.tearDown() }
        await host.settle()

        let workspace = try #require(controller.openBoard)
        let viewport = CGRect(origin: .zero, size: Self.size)

        workspace.open(board: first.path)
        await host.settle()
        #expect(workspace.board == first.path)
        let firstOnScreen = Self.onScreen(first.card, workspace)
        #expect(viewport.contains(CGPoint(x: firstOnScreen.midX, y: firstOnScreen.midY)))

        workspace.open(board: second.path)
        await host.settle()
        #expect(workspace.board == second.path)
        #expect(workspace.folder == "F")
        let secondOnScreen = Self.onScreen(second.card, workspace)
        #expect(viewport.contains(CGPoint(x: secondOnScreen.midX, y: secondOnScreen.midY)))

        #expect(host.neverShown)
    }
}
