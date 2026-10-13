import AppKit
import Observation
import SwiftUI
import Testing
@testable import Pergamenum

/// PG-392, ADR-0091, plan Task 2 (R-01, R-02, R-03, R-08): the premise pin, inverted.
///
/// PG-336 (ADR-0089 G1, §D7) pinned here that a `WorkspaceController` existed only while
/// `WorkspaceView` was on screen: `VaultController.openBoard` was a weak reference to the
/// view's `@State`, so a board in conflict on a pane the person had left was already gone
/// before Cmd+Q. That file's header said that if the premise went red, the ADR needed another
/// look, not the test an edit. ADR-0091 is that look (G4, 2026-10-08): the controller is
/// created with the `VaultController` and owned by it, so the premise is inverted and this file
/// is rewritten in place to pin the inverse. None of the old assertions is disabled; the one
/// that asserted the controller's disappearance now asserts its survival.
///
/// The hosted harness allows file cards only, using `placeFile` as `WorkspaceFitOnOpenHostedTests`
/// does: a text card needs `CommandActions` and through it `EventKitStore`, which the harness
/// keeps out (R-15). Every test keeps `neverShown` and `refusals`.
@MainActor
@Suite(.serialized)
struct QuitBoardLifetimeHostedTests {
    @Observable
    @MainActor
    final class PaneFlag {
        var shown = true
    }

    private static let size = CGSize(width: 1200, height: 800)

    private struct Root: View {
        let flag: PaneFlag
        let controller: VaultController
        // Held, not built in `body`: a flag change re-runs `body`, and a fresh `Navigation` or
        // `ThemeEngine` on each run would be a different environment on every remount.
        private let navigation = Navigation()
        private let themeEngine = ThemeEngine()

        var body: some View {
            Group {
                if flag.shown {
                    WorkspaceView()
                } else {
                    Color.clear
                }
            }
            .environment(controller)
            .environment(navigation)
            .environment(themeEngine)
            .environment(\.theme, .emergency)
        }
    }

    /// Counts what SwiftUI delivers to a plain view, with no Workspace in the way.
    @MainActor
    final class Counts {
        var appeared = 0
        var disappeared = 0
    }

    private struct Probe: View {
        let flag: PaneFlag
        let counts: Counts

        var body: some View {
            if flag.shown {
                Color.red
                    .onAppear { counts.appeared += 1 }
                    .onDisappear { counts.disappeared += 1 }
            } else {
                Color.clear
            }
        }
    }

    /// Writes a board at the vault root with one file card at `point`, through the store, and
    /// returns its path. A file card, not a text one: see the header.
    private static func board(
        _ name: String, cardAt point: CGPoint = CGPoint(x: 6000, y: 4000), in store: CanvasStore
    ) throws -> String {
        let path = try store.createBoard(named: name, in: "")
        let writer = WorkspaceController()
        writer.attach(to: store)
        writer.open(board: path)
        _ = writer.placeFile("\(name).png", at: point)
        writer.detach()
        return path
    }

    private static func openedVault(_ vault: borrowing TemporaryVault) async -> VaultController {
        let controller = VaultController(
            recents: .volatile(), openTabs: .volatile(), pinnedTags: .volatile()
        )
        await controller.open(vault.root)
        return controller
    }

    // MARK: Step 0: does the harness deliver onDisappear?

    @Test func theHarnessDeliversOnDisappearWhenAViewLeavesTheTree() async throws {
        // Plan Task 2 step 0. No test in the repository depended on `onDisappear` before this
        // rewrite, and every release assertion below rides on it, so it is measured on a plain
        // view first: if this goes red, (c) and (d) cannot be read as the pane leave's.
        let flag = PaneFlag()
        let counts = Counts()
        let host = HostedView(Probe(flag: flag, counts: counts), size: Self.size)
        defer { host.tearDown() }
        await host.settle()
        #expect(counts.appeared == 1)
        #expect(counts.disappeared == 0)

        flag.shown = false
        await host.settle()

        #expect(counts.disappeared == 1)
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
    }

    // MARK: R-01

    @Test func theBoardControllerIsTheSameObjectAcrossALeaveAndAReentry() async throws {
        let vault = try TemporaryVault()
        let path = try Self.board("Uno", in: CanvasStore(root: vault.root))
        let controller = await Self.openedVault(vault)
        defer { controller.close() }
        let owned = controller.openBoard

        let flag = PaneFlag()
        let host = HostedView(Root(flag: flag, controller: controller), size: Self.size)
        defer { host.tearDown() }
        await host.settle()

        flag.shown = false
        await host.settle()
        flag.shown = true
        await host.settle()
        #expect(controller.openBoard === owned)

        // The view draws from that object: the fit-on-open the view owns lands on the board
        // opened through the vault's controller, a card thousands of points from the origin.
        owned.open(board: path)
        await host.settle()
        #expect(owned.board == path)
        #expect(owned.zoom != 1 || owned.pan != .zero)

        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
    }

    // MARK: R-02

    @Test func aConflictedBoardSurvivesALeaveAndComesBackConflicted() async throws {
        let vault = try TemporaryVault()
        let root = vault.root
        let path = try Self.board("Uno", in: CanvasStore(root: root))
        let controller = await Self.openedVault(vault)
        defer { controller.close() }
        let board = controller.openBoard

        let flag = PaneFlag()
        let host = HostedView(Root(flag: flag, controller: controller), size: Self.size)
        defer { host.tearDown() }
        await host.settle()

        board.open(board: path)
        _ = board.placeFile("Due.png", at: CGPoint(x: 100, y: 100))
        let externalStore = CanvasStore(root: root)
        var diverged = try externalStore.load(board: path)
        diverged.nodes.append(CanvasNode(
            id: "external", kind: .text("altro"), x: 400, y: 400, width: 100, height: 60
        ))
        try externalStore.save(diverged, board: path)
        board.flushPendingSave()
        guard case .conflicted = board.saveState else {
            Issue.record("setup expected .conflicted, got \(board.saveState)")
            return
        }
        let document = board.document
        let origin = board.origin
        let state = board.saveState

        flag.shown = false
        await host.settle()
        flag.shown = true
        await host.settle()

        // The banner is `BoardTopBar` reading `saveState`, which this pins; no accessibility
        // lookup, which the harness cannot do.
        #expect(board.saveState == state)
        #expect(board.board == path)
        #expect(board.document == document)
        #expect(board.origin == origin)
        #expect(controller.openBoard === board)

        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
        board.detach()
    }

    // MARK: R-03

    @Test func aCleanBoardIsReleasedToTheEmptyStateOnLeave() async throws {
        let vault = try TemporaryVault()
        let path = try Self.board("Uno", in: CanvasStore(root: vault.root))
        let controller = await Self.openedVault(vault)
        defer { controller.close() }
        let board = controller.openBoard

        let flag = PaneFlag()
        let host = HostedView(Root(flag: flag, controller: controller), size: Self.size)
        defer { host.tearDown() }
        await host.settle()

        board.open(board: path)
        await host.settle()
        #expect(board.isShowingBoard)

        flag.shown = false
        await host.settle()
        #expect(board.board == "")

        flag.shown = true
        await host.settle()
        #expect(!board.isShowingBoard)

        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
    }

    // MARK: R-08

    @Test func aCanvasRouteParkedOnAColdPaneOpensWhenThePaneMounts() async throws {
        let vault = try TemporaryVault()
        let path = try Self.board("Uno", in: CanvasStore(root: vault.root))
        let controller = await Self.openedVault(vault)
        defer { controller.close() }

        let flag = PaneFlag()
        flag.shown = false
        let host = HostedView(Root(flag: flag, controller: controller), size: Self.size)
        defer { host.tearDown() }
        await host.settle()
        #expect(controller.openBoardPath == nil)

        // As `pergamenum://canvas?file=…` parks it (and as `WindowPlace.apply` does).
        controller.routeState.pendingCanvas = (path, nil)
        flag.shown = true
        await host.settle()
        try await waitUntil(timeout: .seconds(5)) { controller.openBoardPath == path }

        #expect(controller.openBoardPath == path)
        #expect(controller.routeState.pendingCanvas == nil)

        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
    }
}
