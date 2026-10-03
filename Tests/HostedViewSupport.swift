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
    var neverShown: Bool {
        NeverShown.holds(
            windowHidden: !window.isVisible && !window.isKeyWindow,
            otherApplicationMoved: foreground.otherApplicationMoved,
            activeUnchanged: NSApp.isActive == wasActive,
            keyWindowUnchanged: NSApp.keyWindow === keyWindowAtStart
        )
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
}

/// Records whether an application other than this one launched, became active or quit, through
/// the workspace's own notifications: the three ways another process changes this app's
/// activation without anything in this process asking (PG-331, `HostedView.neverShown`).
///
/// A class rather than state on `HostedView` because the observer blocks outlive no test: they
/// are removed in `stopListening()` (called by `tearDown()`). A harness a test never tears down
/// leaves three inert observer blocks in the notification center, nothing more: each captures
/// this log weakly, so neither the log nor the view is kept alive by them.
@MainActor
final class ForegroundLog {
    private(set) var otherApplicationMoved = false
    /// Every notification this log's observers received, counted before the PID filter, so a
    /// test can tell "filtered out" from "never delivered".
    private(set) var delivered = 0
    private var observers: [any NSObjectProtocol] = []
    private var center: NotificationCenter?

    private static let events: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
    ]

    func startListening(to center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        observers = Self.events.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let movedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.delivered += 1
                    if let movedPID, movedPID != currentPID { self.otherApplicationMoved = true }
                }
            }
        }
        self.center = center
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
