import AppKit
import Testing
@testable import Pergamenum

/// R-20 (ADR-0083 §D7): the preview controller's lifecycle against a real styled text view, a spy
/// presenter, and an injected clock and scheduler. No popover appears, no window is ordered front
/// and no event is sent: the controller's methods are called the way its tracker and its monitor
/// would call them.
@MainActor
@Suite struct LinkPreviewControllerLifecycle {
    private static let text = "Vedi [[Destinazione]] e [sito](https://example.com) e ![[immagine.png]] qui."
    private static let link = NSRange(location: 5, length: 16)

    struct Rig {
        let fixture: EmbedEditorFixtures.Fixture
        let controller: LinkPreviewController
        let presenter: LinkPreviewPresenterSpy
        let clock: LinkPreviewClock
        let requested: Requested
    }

    @MainActor
    final class Requested {
        var targets: [String] = []
        var sections: [String?] = []
    }

    private static func rig(text: String = text, preview: Bool = true) throws -> Rig {
        let fixture = EmbedEditorFixtures.editor(text: text, hidesMarkup: false, root: nil, thumbnails: nil)
        fixture.textView.delegate = fixture.coordinator
        fixture.coordinator.applyStyling(to: fixture.textView, theme: .emergency)
        let requested = Requested()
        if preview {
            fixture.coordinator.parent.links.preview = { target, section in
                requested.targets.append(target)
                requested.sections.append(section)
                return LinkPreviewContent(kind: .note(title: target, lines: ["riga"], missingSection: nil))
            }
        }
        let presenter = LinkPreviewPresenterSpy()
        let clock = LinkPreviewClock()
        let coordinator = fixture.coordinator
        let controller = LinkPreviewController(
            parent: { coordinator.parent }, presenter: presenter, now: clock.now, schedule: clock.schedule
        )
        controller.attach(to: fixture.textView)
        return Rig(fixture: fixture, controller: controller, presenter: presenter, clock: clock, requested: requested)
    }

    /// Pointer over `range` with Command held, then the dwell.
    private static func hover(_ rig: Rig, over range: NSRange = link, dwell: TimeInterval = 0.26) throws {
        let point = rig.fixture.textView.pointOver(range)
        try #require(point != .zero, "layout did not reach the run")
        rig.controller.pointerEntered()
        rig.controller.pointerMoved(to: point, commandDown: true)
        rig.clock.advance(by: dwell)
    }

    // MARK: Tracking area and monitor

    @Test func attachInstallsOneTrackingAreaOwnedByTheTrackerAndASecondAddsNone() throws {
        let fixture = EmbedEditorFixtures.editor(text: Self.text, hidesMarkup: false, root: nil, thumbnails: nil)
        let controller = LinkPreviewController(
            parent: { fixture.coordinator.parent }, presenter: LinkPreviewPresenterSpy(),
            now: { 0 }, schedule: { _, _ in }
        )
        let before = fixture.textView.trackingAreas.count

        controller.attach(to: fixture.textView)

        let added = Array(fixture.textView.trackingAreas.dropFirst(before))
        #expect(controller.hasTrackingArea)
        #expect(added.count == 1)
        let area = try #require(added.first)
        #expect(area.options.isSuperset(of: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]))
        #expect((area.owner as AnyObject?) !== fixture.textView)

        controller.attach(to: fixture.textView)
        #expect(fixture.textView.trackingAreas.count == before + 1)
    }

    @Test func theEventMonitorExistsOnlyWhileThePointerIsInside() throws {
        let rig = try Self.rig()
        #expect(!rig.controller.hasEventMonitor)

        rig.controller.pointerEntered()
        rig.controller.pointerEntered()
        #expect(rig.controller.hasEventMonitor)

        rig.controller.pointerExited()
        #expect(!rig.controller.hasEventMonitor)
        rig.controller.tearDown()
    }

    // MARK: Showing

    @Test func aNoteLinkShowsTheHostsContentAfterTheDwellAnchoredToTheRun() throws {
        let rig = try Self.rig()
        let point = rig.fixture.textView.pointOver(Self.link)
        try #require(point != .zero)
        rig.controller.pointerEntered()
        rig.controller.pointerMoved(to: point, commandDown: true)

        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.clock.scheduledDelays.contains(0.25))

        rig.clock.advance(by: 0.26)

        #expect(rig.requested.targets == ["Destinazione"])
        #expect(rig.requested.sections == [nil])
        let shown = try #require(rig.presenter.shown.first)
        #expect(rig.presenter.shown.count == 1)
        #expect(shown.view === rig.fixture.textView)
        #expect(shown.content == LinkPreviewContent(kind: .note(title: "Destinazione", lines: ["riga"], missingSection: nil)))
        #expect(!shown.rect.isEmpty)
        #expect(shown.rect.insetBy(dx: -4, dy: -4).contains(point))
        rig.controller.tearDown()
    }

    @Test func aLinkThatNamesASectionAsksForThatSection() throws {
        let rig = try Self.rig(text: "Vedi [[Nota#Sezione]] qui.")

        // Over the title, "Nota" {7,4}: the only clickable run of the link, so the one a click
        // would follow (`linkCharacterIndex(at:)`, PG-220). The section is read off the whole
        // `[[Nota#Sezione]]` the parser finds around that character.
        try Self.hover(rig, over: NSRange(location: 7, length: 4))

        #expect(rig.requested.targets == ["Nota"])
        #expect(rig.requested.sections == ["Sezione"])
        rig.controller.tearDown()
    }

    @Test func noPopoverBeforeTheDwellHasPassed() throws {
        let rig = try Self.rig()

        try Self.hover(rig, dwell: 0.1)

        #expect(rig.presenter.shown.isEmpty)
        rig.controller.tearDown()
    }

    @Test func withoutCommandNothingIsScheduledOrShown() throws {
        let rig = try Self.rig()
        let point = rig.fixture.textView.pointOver(Self.link)
        try #require(point != .zero)

        rig.controller.pointerEntered()
        rig.controller.pointerMoved(to: point, commandDown: false)
        rig.clock.advance(by: 1)

        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.requested.targets.isEmpty)
        rig.controller.tearDown()
    }

    @Test func anExternalLinkNeverAsksForContentOrShows() throws {
        let rig = try Self.rig()
        let site = (Self.text as NSString).range(of: "sito")

        try Self.hover(rig, over: site)

        #expect(rig.requested.targets.isEmpty)
        #expect(rig.presenter.shown.isEmpty)
        rig.controller.tearDown()
    }

    @Test func aFileEmbedNeverAsksForContentOrShows() throws {
        let rig = try Self.rig()
        let embed = (Self.text as NSString).range(of: "![[immagine.png]]")

        try Self.hover(rig, over: embed)

        #expect(rig.requested.targets.isEmpty)
        #expect(rig.presenter.shown.isEmpty)
        rig.controller.tearDown()
    }

    @Test func withNoPreviewInputThePresenterIsNeverCalled() throws {
        let rig = try Self.rig(preview: false)

        try Self.hover(rig)

        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.presenter.hideCount == 0)
        rig.controller.tearDown()
    }

    @Test func aKeyDuringTheDwellCancelsIt() throws {
        let rig = try Self.rig()
        let point = rig.fixture.textView.pointOver(Self.link)
        try #require(point != .zero)
        rig.controller.pointerEntered()
        rig.controller.pointerMoved(to: point, commandDown: true)

        _ = rig.controller.keyPressed(isEscape: false)
        rig.clock.advance(by: 0.5)

        #expect(rig.presenter.shown.isEmpty)
        rig.controller.tearDown()
    }

    // MARK: Hiding

    private static func shownRig() throws -> Rig {
        let rig = try Self.rig()
        try Self.hover(rig)
        try #require(rig.presenter.shown.count == 1, "the preview did not show")
        return rig
    }

    @Test(arguments: [
        "commandUp", "pointerExited", "key", "scroll", "resignKey", "textChanged", "noteChanged", "escape",
    ])
    func eachClosingEventHidesTheShownPreview(event: String) throws {
        let rig = try Self.shownRig()
        let hidesBefore = rig.presenter.hideCount

        switch event {
        case "commandUp": rig.controller.commandChanged(isDown: false)
        case "pointerExited": rig.controller.pointerExited()
        case "key": _ = rig.controller.keyPressed(isEscape: false)
        case "scroll": rig.controller.scrolled()
        case "resignKey": rig.controller.windowResignedKey()
        case "textChanged": rig.controller.textChanged()
        case "noteChanged": rig.controller.noteChanged()
        default: _ = rig.controller.keyPressed(isEscape: true)
        }

        #expect(rig.presenter.hideCount == hidesBefore + 1)
        #expect(!rig.presenter.isShowing)
        rig.controller.tearDown()
    }

    @Test func escapeIsConsumedOnlyWhileTheCardIsUp() throws {
        let hidden = try Self.rig()
        #expect(!hidden.controller.keyPressed(isEscape: true))

        // Any key closes the card (ADR-0083 §D7), so a plain key and Escape each get a card of
        // their own: the plain key is never consumed, Escape is consumed once and only then.
        let plainKey = try Self.shownRig()
        #expect(!plainKey.controller.keyPressed(isEscape: false))
        #expect(!plainKey.presenter.isShowing)
        plainKey.controller.tearDown()

        let shown = try Self.shownRig()
        #expect(shown.controller.keyPressed(isEscape: true))
        #expect(!shown.presenter.isShowing)
        #expect(!shown.controller.keyPressed(isEscape: true), "the card is down: Escape is not ours")
        shown.controller.tearDown()
    }

    @Test func theWindowKeyObservationExistsOnlyWhileShown() throws {
        let rig = try Self.rig()
        #expect(!rig.controller.isObservingWindowKey)

        try Self.hover(rig)
        #expect(rig.controller.isObservingWindowKey)

        rig.controller.commandChanged(isDown: false)
        #expect(!rig.controller.isObservingWindowKey)
        rig.controller.tearDown()
    }
}

/// The suite's second half, an extension only to keep each body under `type_body_length`.
@MainActor
extension LinkPreviewControllerLifecycle {
    // MARK: A presenter that cannot show

    @Test func aRefusedShowLeavesTheControllerHiddenUntilAFreshDwell() throws {
        let rig = try Self.rig()
        rig.presenter.canShow = false
        try Self.hover(rig)
        #expect(rig.presenter.shown.count == 1)
        #expect(!rig.controller.isObservingWindowKey)

        // Time passing over the same run asks again for nothing.
        rig.clock.advance(by: 1)
        #expect(rig.presenter.shown.count == 1)

        // A fresh move over the run is a fresh dwell.
        rig.presenter.canShow = true
        let point = rig.fixture.textView.pointOver(Self.link)
        rig.controller.pointerMoved(to: point, commandDown: true)
        rig.clock.advance(by: 0.26)
        #expect(rig.presenter.shown.count == 2)
        #expect(rig.presenter.isShowing)
        rig.controller.tearDown()
    }

    // MARK: Teardown

    @Test func tearDownHidesAndLeavesEveryFlagFalse() throws {
        let rig = try Self.shownRig()
        #expect(rig.controller.hasEventMonitor)

        rig.controller.tearDown()

        #expect(!rig.presenter.isShowing)
        #expect(rig.presenter.hideCount >= 1)
        #expect(!rig.controller.hasEventMonitor)
        #expect(!rig.controller.isObservingWindowKey)
        #expect(!rig.controller.hasTrackingArea)
    }

    @Test func tearDownIsSafeWhenTheTextViewHasNoWindow() {
        let textView = CompletingTextView(usingTextLayoutManager: true)
        let view = NoteTextView(
            text: .constant("Vedi [[A]]"), theme: .emergency, noteTitles: [], tagSuggestions: [],
            hidesMarkup: false, onFollowLink: { _ in }, vault: .init(vaultRoot: nil, notePath: "Nota.md", thumbnails: nil)
        )
        let presenter = LinkPreviewPresenterSpy()
        let controller = LinkPreviewController(
            parent: { view }, presenter: presenter, now: { 0 }, schedule: { _, _ in }
        )
        controller.attach(to: textView)
        controller.pointerEntered()
        #expect(controller.hasEventMonitor)
        #expect(textView.window == nil)

        controller.tearDown()

        #expect(!controller.hasEventMonitor)
        #expect(!controller.isObservingWindowKey)
        #expect(!controller.hasTrackingArea)
    }

    // MARK: The keyboard stays with the editor

    @Test func theTextViewIsFirstResponderBeforeDuringAndAfterTheShow() throws {
        let rig = try Self.rig()
        let window = rig.fixture.window
        #expect(window.makeFirstResponder(rig.fixture.textView))
        var during: NSResponder?
        rig.presenter.duringShow = { during = window.firstResponder }
        #expect(window.firstResponder === rig.fixture.textView)

        try Self.hover(rig)

        #expect(rig.presenter.shown.count == 1)
        #expect(during === rig.fixture.textView)
        #expect(window.firstResponder === rig.fixture.textView)
        rig.controller.tearDown()
    }

    // MARK: A pointer already inside when the area was added

    @Test func theTrackingAreaAssumesThePointerInsideSoMouseExitedStillArrives() throws {
        let fixture = EmbedEditorFixtures.editor(text: Self.text, hidesMarkup: false, root: nil, thumbnails: nil)
        let controller = LinkPreviewController(
            parent: { fixture.coordinator.parent }, presenter: LinkPreviewPresenterSpy(),
            now: { 0 }, schedule: { _, _ in }
        )
        let before = fixture.textView.trackingAreas.count

        controller.attach(to: fixture.textView)

        let area = try #require(fixture.textView.trackingAreas.dropFirst(before).first)
        #expect(area.options.contains(.assumeInside))
        controller.tearDown()
    }

    @Test func aMoveWithoutAMouseEnteredStillInstallsTheMonitorOnce() throws {
        // AppKit sends no `mouseEntered` for an area added with the pointer already inside, so
        // Command release, Escape, a key and a scroll would never close the popover.
        let rig = try Self.rig()
        let point = rig.fixture.textView.pointOver(Self.link)
        try #require(point != .zero)
        #expect(!rig.controller.hasEventMonitor)

        rig.controller.pointerMoved(to: point, commandDown: false)
        rig.controller.pointerMoved(to: point, commandDown: false)
        #expect(rig.controller.hasEventMonitor)

        rig.controller.pointerExited()
        #expect(!rig.controller.hasEventMonitor)
        rig.controller.tearDown()
    }

    // MARK: Only a link the styler made

    @Test func aWikilinkInsideAFencedCodeBlockNeverPreviews() throws {
        let fenced = "Vedi:\n\n```\n[[Destinazione]]\n```\n\nfine."
        let rig = try Self.rig(text: fenced)
        let code = (fenced as NSString).range(of: "[[Destinazione]]")

        try Self.hover(rig, over: code)

        #expect(rig.requested.targets.isEmpty)
        #expect(rig.presenter.shown.isEmpty)
        rig.controller.tearDown()
    }
}

/// A window that is visible and not key, never ordered anywhere: what the popover's guard reads.
private final class VisibleNonKeyWindow: NSWindow {
    override var isVisible: Bool { true }
    override var isKeyWindow: Bool { false }
}

/// The window losing key before any card is up (a dwell scheduled before an app switch).
@MainActor
extension LinkPreviewControllerLifecycle {
    @Test func aWindowResignBeforeTheDwellFiresShowsNothingAndRemovesTheMonitor() throws {
        let rig = try Self.rig()
        let point = rig.fixture.textView.pointOver(Self.link)
        try #require(point != .zero)
        rig.controller.pointerEntered()
        rig.controller.pointerMoved(to: point, commandDown: true)
        #expect(rig.controller.hasEventMonitor)
        #expect(rig.clock.scheduledDelays.contains(0.25))

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: rig.fixture.window)
        rig.clock.advance(by: 0.26)

        #expect(rig.presenter.shown.isEmpty)
        #expect(rig.requested.targets.isEmpty)
        #expect(!rig.controller.hasEventMonitor)
        rig.controller.tearDown()
    }

    @Test func aMoveInTheKeyWindowAfterTheResignInstallsTheMonitorAgain() throws {
        let rig = try Self.rig()
        let point = rig.fixture.textView.pointOver(Self.link)
        try #require(point != .zero)
        rig.controller.pointerEntered()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: rig.fixture.window)
        #expect(!rig.controller.hasEventMonitor)

        rig.controller.pointerMoved(to: point, commandDown: true)
        rig.clock.advance(by: 0.26)

        #expect(rig.controller.hasEventMonitor)
        #expect(rig.presenter.shown.count == 1)
        rig.controller.tearDown()
    }
}

/// The production presenter against a window that is visible but not key. The hosted harness's own
/// window is never visible either, so this stand-in is the only way to reach the key guard.
@MainActor
@Suite struct LinkPreviewPopoverKeyGuard {
    @Test func aVisibleWindowThatIsNotKeyIsRefusedWithoutShowing() throws {
        let window = VisibleNonKeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless],
            backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false
        let textView = CompletingTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        window.contentView?.addSubview(textView)
        try #require(textView.window === window)
        try #require(window.isVisible && !window.isKeyWindow, "the stand-in must pass every guard but the key one")
        let presenter = LinkPreviewPopover()

        let shown = presenter.show(
            LinkPreviewContent(kind: .board(name: "Piano")),
            anchoredTo: NSRect(x: 0, y: 0, width: 40, height: 14), in: textView
        )

        #expect(!shown)
        #expect(!presenter.popover.isShown)
    }
}
