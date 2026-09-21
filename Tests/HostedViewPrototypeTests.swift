import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// SPEC R-08's prototype: one SwiftUI view and one Workspace view, each built for real in a
/// window that is never shown, with events handed to them directly (`HostedViewSupport.swift`).
///
/// These pin what holds. What was tried and does not - a mouse event reaching a SwiftUI
/// gesture, and a board with text cards, which needs `CommandActions` and through it
/// `EventKitStore` (R-15 keeps EventKit out) - is recorded in `docs/adr/0053-...` and in
/// `docs/plans/ui-suite-replacement.md` §8, and in the doc comment of `HostedView`, not here:
/// a test asserting that something does not work would go red on the day it starts to.
///
/// `.serialized`: each test builds its own window and reads `NSApp` state around it, and two
/// running side by side would each see the other's window come and go.
@MainActor
@Suite(.serialized)
struct HostedViewPrototypeTests {
    /// `BoardContentLayer` placed the way `WorkspaceView.swift:357-366` places it: zoom and pan
    /// applied around it, the theme and the vault controller in the environment. Both are read
    /// through `@Environment` and are fatal when missing, which is why the layer cannot be
    /// hosted bare.
    ///
    /// **A replica, not the production wrapper.** The two modifiers are copied here by hand and
    /// `WorkspaceView` itself is not hosted. The test that uses this pins that the layer redraws
    /// when the controller's zoom and pan change, not that `WorkspaceView` applies them the same
    /// way; if that placement changes, this copy does not follow.
    private struct HostedBoard: View {
        let workspace: WorkspaceController
        let vault: VaultController
        let viewport: CGSize

        var body: some View {
            ZStack(alignment: .topLeading) {
                BoardContentLayer(workspace: workspace, modifiers: [], viewportSize: viewport)
                    .scaleEffect(workspace.zoom, anchor: .topLeading)
                    .offset(workspace.pan)
            }
            .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
            .clipped()
            .environment(vault)
            .environment(\.theme, .emergency)
        }
    }

    private static let note = NoteRecord(
        relativePath: "Nota.md", title: "Nota", frontmatter: .empty, linkTargets: [], tasks: [],
        modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )

    // MARK: SwiftUI view

    @Test func aSwiftUISheetDrawsAndAnswersItsKeyEquivalents() async throws {
        var cancelled = 0
        var confirmed: [String] = []
        let host = HostedView(
            RenameNoteSheet(
                note: Self.note, onConfirm: { confirmed.append($0) }, onCancel: { cancelled += 1 }
            )
            .environment(\.theme, .emergency),
            size: CGSize(width: 460, height: 260)
        )
        defer { host.tearDown() }
        await host.settle()

        let drawn = try #require(host.snapshot())
        #expect(drawn.distinctColors > 1)

        // The default action is disabled while the title is unchanged, so Return confirms nothing.
        // That is weak evidence about delivery: `RenameNoteSheet` keeps the title in `@State`, so
        // the two expectations below would hold just the same if Return never reached the view.
        // Only Esc, which does fire something, proves that a key arrived.
        try await host.key("\r", keyCode: 36)
        #expect(confirmed.isEmpty)
        #expect(cancelled == 0)

        let handled = try await host.key("\u{1b}", keyCode: 53)
        #expect(handled)
        #expect(cancelled == 1)
        #expect(confirmed.isEmpty)
        #expect(host.neverShown)
    }

    // MARK: Workspace views

    @Test func aWorkspaceToolColumnAnswersABareKeyAndMovesTheLiveController() async throws {
        let root = try CanvasTemporaryRoot()
        let workspace = try openedWorkspaceController(rootURL: root.url)
        let host = HostedView(
            BoardToolbar(workspace: workspace).environment(\.theme, .emergency),
            size: CGSize(width: 44, height: 500)
        )
        defer { host.tearDown() }
        await host.settle()
        #expect(workspace.tool == .select)

        let link = try await host.key("l", keyCode: 37)
        #expect(link)
        #expect(workspace.tool == .link)

        let text = try await host.key("t", keyCode: 17)
        #expect(text)
        #expect(workspace.tool == .text)

        // A letter no tool answers to is not taken, and leaves the tool as it was.
        let unbound = try await host.key("z", keyCode: 6)
        #expect(!unbound)
        #expect(workspace.tool == .text)
        #expect(host.neverShown)
    }

    @Test func aWorkspaceBoardDrawsAndRedrawsWithTheControllersZoomAndPan() async throws {
        let root = try CanvasTemporaryRoot()
        let workspace = try openedWorkspaceController(rootURL: root.url)
        _ = workspace.addLink("https://example.invalid/a", at: CGPoint(x: 0, y: 0))
        _ = workspace.addLink("https://example.invalid/b", at: CGPoint(x: 400, y: 0))
        #expect(workspace.document.nodes.count == 2)

        let vault = VaultController(
            recents: .volatile(), openTabs: .volatile(), pinnedTags: .volatile()
        )
        let viewport = CGSize(width: 900, height: 600)
        let host = HostedView(
            HostedBoard(workspace: workspace, vault: vault, viewport: viewport), size: viewport
        )
        defer { host.tearDown() }
        await host.settle()

        let whole = try #require(host.snapshot())
        #expect(whole.distinctColors > 1)

        // The control: with nothing changed a second read is the same picture, so the difference
        // asserted below is the zoom and pan and not the snapshot's own noise.
        await host.settle()
        let unchanged = try #require(host.snapshot())
        #expect(unchanged == whole)

        workspace.setZoom(0.5)
        workspace.pan = CGSize(width: 100, height: 50)
        await host.settle()

        let zoomed = try #require(host.snapshot())
        #expect(zoomed.png != whole.png)
        #expect(workspace.zoom == 0.5)
        #expect(host.neverShown)
    }

    // MARK: The harness itself (R-15)

    /// What this pins is the window's refusals, which nothing else here exercises: the other tests
    /// already assert `neverShown` after real hosting and real key equivalents, so a bare
    /// "hosted, therefore hidden" check would add nothing to them.
    ///
    /// If a refusal were ever removed, this is the test that would put the window on screen for a
    /// moment, and it fails on the missing issue.
    @Test func theHarnessWindowRefusesFocusAndEveryCallThatWouldShowIt() async throws {
        let host = HostedView(
            Text("R-15").environment(\.theme, .emergency), size: CGSize(width: 120, height: 40)
        )
        defer { host.tearDown() }
        await host.settle()

        #expect(!host.window.canBecomeKey)
        #expect(!host.window.canBecomeMain)

        // Each call below would show the window or hand it an event. The window records an issue
        // and does nothing; `withKnownIssue` turns that issue into a pass, and fails the test if
        // a call goes through without one.
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: host.window.windowNumber,
            context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
            keyCode: 0
        ))
        withKnownIssue { host.window.orderFront(nil) }
        withKnownIssue { host.window.orderFrontRegardless() }
        withKnownIssue { host.window.makeKeyAndOrderFront(nil) }
        withKnownIssue { host.window.order(.above, relativeTo: 0) }
        withKnownIssue { host.window.sendEvent(event) }
        #expect(host.neverShown)
    }
}
