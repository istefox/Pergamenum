import AppKit
import SwiftUI
import Testing
@testable import Pergamenum

/// A window AppKit can never hand focus to and that refuses to be shown (R-15). It cannot become
/// key or main, and each call that would put it on screen (`orderFront`, `orderFrontRegardless`,
/// `makeKeyAndOrderFront`, `order(_:relativeTo:)` to anywhere but out) or hand it an event
/// (`sendEvent`, other than AppKit's own bookkeeping) records an issue naming the call and does
/// nothing, so a test that reaches for one fails loudly and takes nothing from the person at the
/// keyboard.
private final class NeverKeyWindow: NSWindow {
    /// Every refused call, by name. `Issue.record` below is called from AppKit's own run-loop
    /// callbacks, outside the test's task context (PG-201): Swift Testing attributes that issue
    /// to `Test «unknown»`, and one observed `xcodebuild` run printed "failed with 11 issues" and
    /// still exited `** TEST SUCCEEDED **`. This array is read back inside the test's own task
    /// through `HostedView.neverShown`, so a refusal fails the test through an ordinary `#expect`
    /// instead of depending on `Issue.record`'s attribution.
    private(set) var refusals: [String] = []

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderFront(_ sender: Any?) { refuse("orderFront") }
    override func orderFrontRegardless() { refuse("orderFrontRegardless") }
    override func makeKeyAndOrderFront(_ sender: Any?) { refuse("makeKeyAndOrderFront") }

    /// AppKit hands every window its own bookkeeping events: a window-moved `.appKitDefined`
    /// arrives on the run loop, outside any test, while a hosted view settles (measured on macOS
    /// 27, twice per window). Those go through. Anything else is an event a test sent.
    override func sendEvent(_ event: NSEvent) {
        guard event.type != .appKitDefined else { return super.sendEvent(event) }
        refuse("sendEvent")
    }

    /// Taking the window out is the one placement that goes through: `HostedView.tearDown`
    /// does it, the way `EditorHeightTests` takes its own window down.
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place != .out else { return super.order(place, relativeTo: otherWin) }
        refuse("order(_:relativeTo:)")
    }

    private func refuse(_ call: String) {
        let why = "was called on a hosted-view window, which is never shown or sent events"
        refusals.append(call)
        Issue.record("R-15: `NSWindow.\(call)` \(why). Nothing was done.")
    }
}

/// A SwiftUI view built for real, in a window that is never shown, with events handed to it
/// directly - the harness SPEC R-08 asks for and R-15 constrains.
///
/// **R-15 is held here rather than re-derived by each test, as far as a type can hold it.**
/// Nothing in this file calls `makeKeyAndOrderFront`, `orderFront` or `NSApp.activate`, and no
/// event goes through `NSWindow.sendEvent` or `NSApp.sendEvent`: those are the calls that turn a
/// window into a visible, key one on the person's own screen, which is what the `Stop` hook
/// running this target at the end of every turn must never do (CLAUDE.md, working agreements).
/// The window is a `NeverKeyWindow`: it refuses key and main, and a test that reaches through
/// `window` for `orderFront`, `orderFrontRegardless`, `makeKeyAndOrderFront`, `order(_:relativeTo:)`
/// or `sendEvent` (bar AppKit's own bookkeeping events) gets a recorded issue naming the call and
/// no effect. `window` is still an `NSWindow` a test can hold, `NSApp.activate` is not
/// intercepted, and `NSApp.sendEvent` is refused only for an event it routes to this window, so
/// keeping those out stays a matter of review. `neverShown` is the check afterwards, of the
/// effects rather than of the calls.
///
/// The three subsystems the UI suite's launch flags exist to keep out (`-disableCalendar`,
/// `-disableUpdater`, `-mailStoreRoot`) have no in-process equivalent to pass, so the harness
/// keeps out of them by construction: a test hands it a view already built with injected
/// state, never the app, `EventKitStore`, `SparkleUpdateController` or a Mail store.
///
/// **What reaches a hosted view, measured on macOS 27 / Xcode 27 (2026-09-21).**
/// - A key equivalent handed to `performKeyEquivalent(with:)` reaches a SwiftUI
///   `.keyboardShortcut` button, bare letters and Esc included (`key(_:keyCode:)`).
/// - What SwiftUI drew can be read back offscreen through `cacheDisplay` (`snapshot()`).
/// - A mouse event does **not** reach a SwiftUI tap, double tap, drag or `Button`: the hosting
///   view holds no gesture recognizer and no tracking area, and a board's hosting view has no
///   subviews, so `hitTest` can only answer with the hosting view itself. There is deliberately
///   no `click` or `drag` here, and no way to add one without `sendEvent`, which R-15 forbids.
///   A test whose subject is a SwiftUI pointer gesture stays a GUI test.
/// - SwiftUI's accessibility tree is a single childless group in-process, so a label "as read
///   from the tree" cannot be checked here either; the label's own text can, through a pure
///   function.
///
/// Each test builds its own; nothing is shared between two of them (SPEC, "Edge cases").
@MainActor
final class HostedView<Content: View> {
    let window: NSWindow
    let hosting: NSHostingView<Content>

    private let wasActive: Bool
    private let keyWindowAtStart: NSWindow?
    private let foreground = ForegroundLog()

    enum HostError: Error {
        case eventNotBuilt
    }

    /// What the hosting view drew, read back offscreen.
    struct Snapshot: Equatable {
        /// How many distinct colours a fixed scatter of points lands on: one means a flat
        /// fill, so nothing was drawn.
        let distinctColors: Int
        /// The whole picture, PNG encoded, so two equal pictures compare equal.
        let png: Data
    }

    /// `size` is the content size in points. The window is titled, like the one
    /// `EditorHeightTests` builds, and gets the hosting view as its content view; it is laid
    /// out once and never ordered in.
    init(_ content: Content, size: CGSize) {
        wasActive = NSApp.isActive
        keyWindowAtStart = NSApp.keyWindow
        foreground.startListening()
        hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NeverKeyWindow(
            contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
    }

    /// True while this harness has left the machine as it found it: the window not on screen,
    /// not key, and the app's own active state and key window unchanged (R-15). It says whether,
    /// not which call: a refused `orderFront` or `sendEvent` names itself as a recorded issue.
    ///
    /// **The app-level half is asked only when no other app moved the foreground meanwhile**
    /// (PG-331). Whether this app is active, and so which window is its key window, is
    /// machine-wide state: another session's `xcodebuild` launching or quitting its own test
    /// host activates one app and deactivates another, and every hosted test then in flight -
    /// several at once, since they interleave on the main actor at each `settle()` - read that
    /// as its own doing and failed, a different set each run and only while such a run was live.
    /// A test that activates this app itself posts no other app's launch, activation or
    /// termination, so on a quiet machine the check is exactly what it was; when another app
    /// did move the foreground, the change is not this harness's to answer for, and the
    /// window-level half - which no other process can touch - still holds the test to R-15.
    /// Once skipped, the app-level half stays skipped for the rest of this harness's life, and
    /// `appLevelCheckSkipped` says so. The decision itself is `NeverShown.holds`, pinned by
    /// `HostedViewPrototypeTests.neverShownDecisionTable`.
    ///
    /// **A residual race, named rather than closed:** nothing orders another app's workspace
    /// notification before this app's own activation change. `NSApp.isActive` can flip as soon
    /// as the window server says so, while the workspace notification reaches this process only
    /// when the main run loop next drains it; a read landing between the two still fails as
    /// before. The foreground log narrows the flake, it does not remove it.
    ///
    /// **When it answers false it records an issue naming every input it read**
    /// (`NeverShown.report`): which half failed, each window and app-level value at the start
    /// and now, whether a notification came, the frontmost application and the running set at
    /// the start and at this read, and every workspace notification delivered meanwhile. The
    /// cause of this flake has not been measured: on 2026-10-04, 27 runs of the five hosted
    /// suites beside 336 launches and quits of a second `xcodebuild` test host never changed
    /// this app's active state or key window at all, so the scenario named above did not
    /// reproduce. A synchronous poll of the frontmost application, counted as "another app
    /// moved", was tried and dropped for want of evidence: it would skip the app-level half on
    /// any process coming or going. The report says what that poll would have answered
    /// (`foreground poll`), so the next red shows whether it would have saved the test.
    var neverShown: Bool {
        let windowVisible = window.isVisible
        let windowKey = window.isKeyWindow
        let activeNow = NSApp.isActive
        let keyWindowNow = NSApp.keyWindow
        let otherApplicationMoved = foreground.otherApplicationMoved
        let holds = NeverShown.holds(
            windowHidden: !windowVisible && !windowKey,
            otherApplicationMoved: otherApplicationMoved,
            activeUnchanged: activeNow == wasActive,
            keyWindowUnchanged: keyWindowNow === keyWindowAtStart
        )
        guard !holds else { return true }
        // Read after the app's own state, so the foreground the report shows is at least as
        // recent as the change it is meant to explain.
        let state = NeverShown.State(
            windowVisible: windowVisible, windowKey: windowKey,
            activeAtStart: wasActive, activeNow: activeNow,
            keyWindowAtStart: NeverShown.describe(keyWindowAtStart),
            keyWindowNow: NeverShown.describe(keyWindowNow),
            keyWindowUnchanged: keyWindowNow === keyWindowAtStart,
            foreground: foreground.diagnose()
        )
        Issue.record(Comment(rawValue: NeverShown.report(state)))
        return false
    }

    /// True when `neverShown` has stopped asking the app-level half, because another app
    /// launched, activated or quit since this harness was built (PG-331).
    var appLevelCheckSkipped: Bool { foreground.otherApplicationMoved }

    /// Every `NeverKeyWindow` call refused so far, by name (empty on a test that never provokes
    /// one). `Issue.record` inside `refuse(_:)` runs from an AppKit run-loop callback, outside the
    /// test's task context, and is not reliably attributed to the running test - one `xcodebuild`
    /// run printed "failed with 11 issues" and still exited `** TEST SUCCEEDED **` (PG-201). A
    /// test that does not deliberately provoke a refusal should `#expect(host.refusals.isEmpty)`
    /// as well as `neverShown`, so the check runs inside its own task and fails the run for real.
    var refusals: [String] {
        (window as? NeverKeyWindow)?.refusals ?? []
    }

    /// Lets the view graph and the main run loop catch up with whatever was just sent.
    ///
    /// A suspension rather than a nested run loop: the main run loop turns while the test is
    /// suspended, and no other test's job can start inside this one's stack.
    ///
    /// The budget is 10 iterations, not the original 3 (PG-214/#424): a concurrent `xcodebuild`
    /// process from another worktree, sharing this machine's CPU with the Stop hook's own run,
    /// can starve the layout/draw pass past a 60ms budget without any source change, reading back
    /// a stale `tool` or `snapshot()`. Each extra iteration is a yielding sleep, not spinning, so
    /// an unloaded machine pays only the wall time of the sleeps already needed to settle.
    func settle() async {
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(20))
            hosting.layoutSubtreeIfNeeded()
        }
    }

    /// The end of the test: the window taken down the way `EditorHeightTests` takes its own
    /// down, and the hosting view let go so a representable inside it is dismantled.
    func tearDown() {
        window.orderOut(nil)
        window.contentView = nil
        foreground.stopListening()
    }

    /// A key equivalent (Return, Esc, a bare letter, Cmd+key) offered to the hosting view, the
    /// way the window offers one to its content before anything else looks at it. Answers
    /// whether the view took it.
    @discardableResult
    func key(
        _ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []
    ) async throws -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ) else { throw HostError.eventNotBuilt }
        let handled = hosting.performKeyEquivalent(with: event)
        await settle()
        return handled
    }

    /// What the view draws now, without showing the window.
    func snapshot() -> Snapshot? {
        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds),
              rep.pixelsWide > 0, rep.pixelsHigh > 0
        else { return nil }
        hosting.cacheDisplay(in: bounds, to: rep)
        var colors = Set<String>()
        for step in 0..<600 {
            let x = (step * 37) % rep.pixelsWide
            let y = (step * 53) % rep.pixelsHigh
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            colors.insert(String(
                format: "%.2f-%.2f-%.2f-%.2f", color.redComponent, color.greenComponent,
                color.blueComponent, color.alphaComponent
            ))
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return Snapshot(distinctColors: colors.count, png: png)
    }
}

// MARK: - Who moved the foreground

/// `HostedView.neverShown`'s decision, apart from the state it reads so its truth table can be
/// pinned. The window half always counts; the app-level half counts unless another app moved
/// the foreground. With `otherApplicationMoved` false it is the original assertion, unrelaxed.
enum NeverShown {
    static func holds(
        windowHidden: Bool, otherApplicationMoved: Bool, activeUnchanged: Bool, keyWindowUnchanged: Bool
    ) -> Bool {
        guard windowHidden else { return false }
        return otherApplicationMoved || (activeUnchanged && keyWindowUnchanged)
    }

    /// Every input `HostedView.neverShown` read, as it read them.
    struct State {
        var windowVisible: Bool
        var windowKey: Bool
        var activeAtStart: Bool
        var activeNow: Bool
        var keyWindowAtStart: String
        var keyWindowNow: String
        var keyWindowUnchanged: Bool
        var foreground: ForegroundLog.Diagnosis
    }

    /// A window as the report names it: its class, number and title, or `none`.
    @MainActor
    static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "none" }
        return "\(type(of: window)) #\(window.windowNumber) \"\(window.title)\""
    }

    /// The text recorded when `neverShown` answers false: one line per half, then what the
    /// foreground log knew - whether a notification counted, what the report-only poll would
    /// have answered, the frontmost application and the running set at the start and at this
    /// read, and every workspace notification delivered since the start.
    static func report(_ state: State) -> String {
        let foreground = state.foreground
        func name(_ pid: pid_t?, in snapshot: ForegroundLog.Snapshot?) -> String {
            guard let pid else { return "none" }
            return snapshot?.names[pid].map { "\(pid) \($0)" } ?? "\(pid)"
        }
        func list(_ pids: Set<pid_t>, in snapshot: ForegroundLog.Snapshot?) -> String {
            "[" + pids.sorted().map { name($0, in: snapshot) }.joined(separator: ", ") + "]"
        }
        var lines = [
            "neverShown is false (PG-331 diagnosis)",
            "window: visible=\(state.windowVisible) key=\(state.windowKey)",
            "app: isActive start=\(state.activeAtStart) now=\(state.activeNow); "
                + "keyWindow start=\(state.keyWindowAtStart) now=\(state.keyWindowNow) "
                + "changed=\(!state.keyWindowUnchanged)",
            "foreground: moved=\(foreground.moved) (from notifications); "
                + "foreground poll would say moved=\(foreground.pollWouldMove) (report only, not counted)",
        ]
        if let start = foreground.start, let now = foreground.now {
            lines.append(
                "frontmost: start=\(name(start.frontmostPID, in: start)) now=\(name(now.frontmostPID, in: now))"
            )
            lines.append(
                "running: appeared \(list(now.runningPIDs.subtracting(start.runningPIDs), in: now)) "
                    + "vanished \(list(start.runningPIDs.subtracting(now.runningPIDs), in: start))"
            )
        } else {
            lines.append("frontmost: not listening")
        }
        lines.append("notifications: [" + foreground.notifications.joined(separator: ", ") + "]")
        return lines.joined(separator: "\n")
    }
}

/// Records whether an application other than this one launched, became active or quit, through
/// the workspace's own notifications: the three ways another process changes this app's
/// activation without anything in this process asking (PG-331, `HostedView.neverShown`).
///
/// For the report alone (`diagnose()`, `NeverShown.report`) it also keeps a snapshot of the
/// frontmost application and the running set taken in `startListening`, compares it with one
/// read at diagnosis time, and lists every notification it received. None of that changes
/// `otherApplicationMoved`: only a notification from another process does.
///
/// A class rather than state on `HostedView` because the observer blocks outlive no test: they
/// are removed in `stopListening()` (called by `tearDown()`). A harness a test never tears down
/// leaves three inert observer blocks in the notification center, nothing more: each captures
/// this log weakly, so neither the log nor the view is kept alive by them.
@MainActor
final class ForegroundLog {
    /// The frontmost application and every running one, by pid, with their names.
    struct Snapshot: Equatable {
        let frontmostPID: pid_t?
        let runningPIDs: Set<pid_t>
        var names: [pid_t: String] = [:]
    }

    /// Where a `Snapshot` is read from: the live workspace by default, a closure a test drives
    /// otherwise.
    struct Source {
        let read: @MainActor () -> Snapshot

        static var workspace: Source {
            Source {
                let workspace = NSWorkspace.shared
                let running = workspace.runningApplications
                var names: [pid_t: String] = [:]
                for app in running {
                    names[app.processIdentifier] = app.localizedName ?? app.bundleIdentifier ?? "?"
                }
                return Snapshot(
                    frontmostPID: workspace.frontmostApplication?.processIdentifier,
                    runningPIDs: Set(running.map(\.processIdentifier)),
                    names: names
                )
            }
        }
    }

    /// What one diagnosis saw (`NeverShown.report`).
    struct Diagnosis {
        /// `otherApplicationMoved` at this read: a notification from another process came.
        var moved: Bool
        /// What `ForegroundLog.wouldMove` answers for `start` and `now`. Not counted.
        var pollWouldMove: Bool
        var start: Snapshot?
        var now: Snapshot?
        /// Every notification delivered since the start, this process's own included:
        /// "<event> <pid> <name> +<seconds since the start>".
        var notifications: [String] = []
    }

    private(set) var otherApplicationMoved = false
    /// Every notification this log's observers received, counted before the PID filter, so a
    /// test can tell "filtered out" from "never delivered".
    private(set) var delivered = 0
    private var notifications: [String] = []
    private var start: Snapshot?
    private var startUptime: TimeInterval = 0
    private let source: Source
    private let currentPID: pid_t
    private var observers: [any NSObjectProtocol] = []
    private var center: NotificationCenter?

    private static let events: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
    ]

    init(source: Source = .workspace, currentPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.source = source
        self.currentPID = currentPID
    }

    /// The report's poll: a pid other than `currentPID` appeared in or vanished from the
    /// running set, or the frontmost application changed to one that is not `currentPID`.
    /// It says whether a poll would have explained a red; it decides nothing.
    static func wouldMove(from start: Snapshot, to now: Snapshot, currentPID: pid_t) -> Bool {
        var changed = start.runningPIDs.symmetricDifference(now.runningPIDs)
        changed.remove(currentPID)
        if !changed.isEmpty { return true }
        return now.frontmostPID != start.frontmostPID && now.frontmostPID != currentPID
    }

    /// Reads the foreground once more and answers what the log knows now. Changes nothing.
    func diagnose() -> Diagnosis {
        let now = start.map { _ in source.read() }
        var pollWouldMove = false
        if let start, let now { pollWouldMove = Self.wouldMove(from: start, to: now, currentPID: currentPID) }
        return Diagnosis(
            moved: otherApplicationMoved, pollWouldMove: pollWouldMove,
            start: start, now: now, notifications: notifications
        )
    }

    func startListening(to center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        let currentPID = currentPID
        start = source.read()
        startUptime = ProcessInfo.processInfo.systemUptime
        observers = Self.events.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let movedPID = app?.processIdentifier
                let entry = Self.entry(name: notification.name, app: app)
                let uptime = ProcessInfo.processInfo.systemUptime
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.delivered += 1
                    self.notifications.append(entry + String(format: " +%.3fs", uptime - self.startUptime))
                    if let movedPID, movedPID != currentPID { self.otherApplicationMoved = true }
                }
            }
        }
        self.center = center
    }

    private nonisolated static func entry(name: Notification.Name, app: NSRunningApplication?) -> String {
        let event = switch name {
        case NSWorkspace.didLaunchApplicationNotification: "launch"
        case NSWorkspace.didActivateApplicationNotification: "activate"
        case NSWorkspace.didTerminateApplicationNotification: "terminate"
        default: name.rawValue
        }
        guard let app else { return "\(event) ?" }
        return "\(event) \(app.processIdentifier) \(app.localizedName ?? app.bundleIdentifier ?? "?")"
    }

    func stopListening() {
        for observer in observers { center?.removeObserver(observer) }
        observers = []
        center = nil
    }
}

// MARK: - Frames by name

/// Frames reported by `onGeometryChange`, by name, in the window's coordinates - what a hosted
/// layout test reads back once the view has settled (`PraticaTimelineLaneHostedTests`,
/// `PraticaTimelineEntryGapHostedTests`).
final class FrameBox: @unchecked Sendable {
    var frames: [String: CGRect] = [:]
}

extension View {
    /// Records this view's global frame in `box` under `name`, on every geometry change.
    func report(_ name: String, into box: FrameBox) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { box.frames[name] = $0 }
    }
}
