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
    var neverShown: Bool {
        !window.isVisible && !window.isKeyWindow
            && NSApp.isActive == wasActive && NSApp.keyWindow === keyWindowAtStart
    }

    /// Lets the view graph and the main run loop catch up with whatever was just sent.
    ///
    /// A suspension rather than a nested run loop: the main run loop turns while the test is
    /// suspended, and no other test's job can start inside this one's stack.
    func settle() async {
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(20))
            hosting.layoutSubtreeIfNeeded()
        }
    }

    /// The end of the test: the window taken down the way `EditorHeightTests` takes its own
    /// down, and the hosting view let go so a representable inside it is dismantled.
    func tearDown() {
        window.orderOut(nil)
        window.contentView = nil
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
