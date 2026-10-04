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
    /// `BoardContentLayer` placed the way `WorkspaceView+Board.swift`'s `board` places it: zoom and pan
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
            .environment(Navigation())
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
        #expect(host.refusals.isEmpty)
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
        #expect(host.refusals.isEmpty)
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
        #expect(host.refusals.isEmpty)
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
        // PG-201: pins the refusal count from inside this test's own task, independent of
        // whether `withKnownIssue`/`Issue.record` end up attributed to it by `xcodebuild`.
        #expect(host.refusals == [
            "orderFront", "orderFrontRegardless", "makeKeyAndOrderFront", "order(_:relativeTo:)",
            "sendEvent",
        ])
    }

    /// PG-331: what lets `neverShown` tell another app's foreground change from its own. This
    /// app's own activation is never counted, so a test that activates the app still fails the
    /// app-level half; another app's launch, activation or termination is. Driven on a private
    /// notification center, so nothing on the machine is activated to prove it.
    ///
    /// Each assertion waits until the log has seen every notification posted so far, so "not
    /// counted" is read after delivery, never before it. Measured on 2026-10-03, a post to an
    /// observer on `OperationQueue.main` runs the block before `post` returns, from the main
    /// thread and from a background one alike, so the wait ends on its first check; it is
    /// bounded and kept so the test stays correct if that ever changes.
    @Test func theForegroundLogCountsOtherApplicationsAndNeverThisOne() async throws {
        let center = NotificationCenter()
        // A still foreground, so nothing in this test reads the machine's own applications:
        // only the notifications posted below reach the log.
        let still = ForegroundLog.Snapshot(frontmostPID: nil, runningPIDs: [])
        let log = ForegroundLog(source: ForegroundLog.Source { still })
        log.startListening(to: center)
        defer { log.stopListening() }
        let current = NSRunningApplication.current
        let other = try #require(NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier != current.processIdentifier
        })

        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            center.post(name: name, object: nil, userInfo: [NSWorkspace.applicationUserInfoKey: current])
        }
        let selfEventsSeen = await Self.waitUntil { log.delivered == 2 }
        try #require(selfEventsSeen)
        #expect(!log.otherApplicationMoved)

        center.post(
            name: NSWorkspace.didTerminateApplicationNotification, object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: other]
        )
        let otherEventSeen = await Self.waitUntil { log.delivered == 3 }
        try #require(otherEventSeen)
        #expect(log.otherApplicationMoved)
    }

    /// A `ForegroundLog.Source` a test moves by hand.
    @MainActor
    private final class ForegroundScript {
        var snapshot: ForegroundLog.Snapshot
        init(_ snapshot: ForegroundLog.Snapshot) { self.snapshot = snapshot }
        var source: ForegroundLog.Source { ForegroundLog.Source { self.snapshot } }
    }

    /// One poll case: the snapshot at `startListening`, the one at the diagnosis, and what the
    /// report's poll must answer. This process is pid 100 throughout.
    struct PollCase: Sendable, CustomTestStringConvertible {
        let name: String
        let start: ForegroundLog.Snapshot
        let now: ForegroundLog.Snapshot
        let moved: Bool
        var testDescription: String { name }
    }

    nonisolated static let pollCases: [PollCase] = [
        PollCase(
            name: "frontmost changes to another pid",
            start: .init(frontmostPID: 200, runningPIDs: [100, 200, 300]),
            now: .init(frontmostPID: 300, runningPIDs: [100, 200, 300]), moved: true
        ),
        PollCase(
            name: "a foreign pid joins the running set",
            start: .init(frontmostPID: 200, runningPIDs: [100, 200]),
            now: .init(frontmostPID: 200, runningPIDs: [100, 200, 400]), moved: true
        ),
        PollCase(
            name: "a foreign pid leaves the running set",
            start: .init(frontmostPID: 200, runningPIDs: [100, 200, 400]),
            now: .init(frontmostPID: 200, runningPIDs: [100, 200]), moved: true
        ),
        PollCase(
            name: "frontmost changes to this process",
            start: .init(frontmostPID: 200, runningPIDs: [100, 200]),
            now: .init(frontmostPID: 100, runningPIDs: [100, 200]), moved: false
        ),
        PollCase(
            name: "nothing changes",
            start: .init(frontmostPID: 200, runningPIDs: [100, 200]),
            now: .init(frontmostPID: 200, runningPIDs: [100, 200]), moved: false
        ),
        PollCase(
            name: "this process joins the running set",
            start: .init(frontmostPID: 200, runningPIDs: [200]),
            now: .init(frontmostPID: 200, runningPIDs: [100, 200]), moved: false
        ),
        PollCase(
            name: "this process leaves the running set",
            start: .init(frontmostPID: 200, runningPIDs: [100, 200]),
            now: .init(frontmostPID: 200, runningPIDs: [200]), moved: false
        ),
    ]

    /// PG-331: the report's poll. Another application becoming frontmost, or a foreign pid
    /// joining or leaving the running set, reads as a move; this process becoming frontmost, or
    /// its own pid coming and going, does not.
    @Test(arguments: pollCases)
    func theReportPollTellsAnotherApplicationFromThisOne(_ poll: PollCase) {
        #expect(ForegroundLog.wouldMove(from: poll.start, to: poll.now, currentPID: 100) == poll.moved)
    }

    /// PG-331: the poll is the report's, never the decision's. With the foreground moved and no
    /// notification delivered, `otherApplicationMoved` stays false and the diagnosis shows both.
    @Test func theReportPollNeverSkipsTheAppLevelHalf() {
        let start = ForegroundLog.Snapshot(frontmostPID: 200, runningPIDs: [100, 200])
        let script = ForegroundScript(start)
        let log = ForegroundLog(source: script.source, currentPID: 100)
        log.startListening(to: NotificationCenter())
        defer { log.stopListening() }

        script.snapshot = .init(frontmostPID: 500, runningPIDs: [100, 200, 500])
        let diagnosis = log.diagnose()
        #expect(diagnosis.pollWouldMove)
        #expect(!diagnosis.moved)
        #expect(diagnosis.start == start && diagnosis.now == script.snapshot)
        #expect(!log.otherApplicationMoved)
        #expect(log.delivered == 0)
    }

    /// PG-331: the issue `neverShown` records when it answers false names every input: both
    /// halves at the start and now, the notification-driven decision, what the report's poll
    /// would have said, the foreground's start and now, and the notifications delivered.
    @Test func theNeverShownReportNamesEveryInput() {
        let start = ForegroundLog.Snapshot(
            frontmostPID: 200, runningPIDs: [100, 200, 300], names: [100: "Me", 200: "Xcode", 300: "Old"]
        )
        let now = ForegroundLog.Snapshot(
            frontmostPID: 400, runningPIDs: [100, 200, 400], names: [100: "Me", 200: "Xcode", 400: "Host"]
        )
        let state = NeverShown.State(
            windowVisible: false, windowKey: false, activeAtStart: true, activeNow: false,
            keyWindowAtStart: "NSWindow #7 \"Pergamenum\"", keyWindowNow: "none", keyWindowUnchanged: false,
            foreground: ForegroundLog.Diagnosis(
                moved: false, pollWouldMove: true, start: start, now: now,
                notifications: ["launch 400 Host +0.120s"]
            )
        )
        #expect(NeverShown.report(state) == """
            neverShown is false (PG-331 diagnosis)
            window: visible=false key=false
            app: isActive start=true now=false; keyWindow start=NSWindow #7 "Pergamenum" now=none changed=true
            foreground: moved=false (from notifications); foreground poll would say moved=true (report only, not counted)
            frontmost: start=200 Xcode now=400 Host
            running: appeared [400 Host] vanished [300 Old]
            notifications: [launch 400 Host +0.120s]
            """)
    }

    /// PG-331: `neverShown`'s whole truth table. A shown or key window always fails; with no
    /// other app moving the foreground the app-level half is the original assertion, unrelaxed;
    /// only another app's move lets an app-level change through.
    @Test func neverShownDecisionTable() {
        // (windowHidden, otherApplicationMoved, activeUnchanged, keyWindowUnchanged)
        let holding: Set<[Bool]> = [
            [true, false, true, true],
            [true, true, true, true],
            [true, true, true, false],
            [true, true, false, true],
            [true, true, false, false],
        ]
        for row in 0 ..< 16 {
            let bits = (0 ..< 4).map { row & (8 >> $0) != 0 }
            let result = NeverShown.holds(
                windowHidden: bits[0], otherApplicationMoved: bits[1],
                activeUnchanged: bits[2], keyWindowUnchanged: bits[3]
            )
            #expect(result == holding.contains(bits), "row \(bits)")
        }
    }

    /// Polls `condition` on the main actor, yielding a millisecond between reads, for at most
    /// two seconds; true as soon as it holds.
    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while !condition() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}
