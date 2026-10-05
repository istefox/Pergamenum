import AppKit
import Observation
import SwiftUI
import Testing
@testable import Pergamenum

/// PG-336, ADR-0089 G1 and §D7, plan Task 5: the premise pin. The quit can name a conflicted
/// board only while a `WorkspaceController` exists, and `VaultController.openBoard` is a weak
/// reference to the one `WorkspaceView` keeps as `@State`. The plan's claim is that the
/// controller is gone once the pane is not on screen, so a board in conflict on a pane the
/// person has left has already lost its edits before Cmd+Q (G2).
///
/// If this test goes red because `openBoard` survives the branch's removal, the premise is
/// void: G1's reason and §D7's residual no longer hold, and the ADR needs another look, not
/// this test an edit.
@MainActor
@Suite(.serialized)
struct QuitBoardLifetimeHostedTests {
    @Observable
    @MainActor
    final class PaneFlag {
        var shown = true
    }

    private struct Root: View {
        let flag: PaneFlag

        var body: some View {
            if flag.shown {
                WorkspaceView()
            } else {
                Color.clear
            }
        }
    }

    @Test func theBoardControllerIsGoneOnceTheWorkspacePaneLeavesTheScreen() async throws {
        let vault = try TemporaryVault()
        let controller = VaultController(
            recents: .volatile(), openTabs: .volatile(), pinnedTags: .volatile()
        )
        await controller.open(vault.root)
        defer { controller.close() }

        let flag = PaneFlag()
        let host = HostedView(
            Root(flag: flag)
                .environment(controller)
                .environment(Navigation())
                .environment(ThemeEngine())
                .environment(\.theme, .emergency),
            size: CGSize(width: 1200, height: 800)
        )
        defer { host.tearDown() }
        await host.settle()
        try await waitUntil { controller.openBoard != nil }

        flag.shown = false
        await host.settle()
        try await waitUntil(timeout: .seconds(5)) { controller.openBoard == nil }

        #expect(controller.openBoard == nil)
        #expect(host.neverShown)
        #expect(host.refusals.isEmpty)
    }
}
