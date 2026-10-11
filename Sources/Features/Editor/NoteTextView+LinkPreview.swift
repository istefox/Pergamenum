import AppKit

// ADR-0083 §D7 (PG-386, N3 session B).

/// Owns the Cmd+hover preview's whole lifecycle for one text view (ADR-0074 §D2/§D3): the tracker
/// and its tracking area, the one local event monitor, the window-key observation, the trigger and
/// the presenter. Nothing else shows or closes the popover.
///
/// When it shows and when it goes is `LinkPreviewTrigger`'s, a pure state machine; this class only
/// feeds it events and carries out what it answers. The monitor exists only while the pointer is
/// inside the text view (and goes when the window loses key) and the window observation only while
/// the card is up, so an editor the pointer never visits pays for neither.
@MainActor
final class LinkPreviewController {
    /// The link under the pointer: the run the trigger keys on (and the popover anchors to), and
    /// what the host is asked to preview.
    struct HoveredLink: Equatable {
        let run: NSRange
        let target: String
        let section: String?
    }

    private let parent: () -> NoteTextView?
    private let presenter: LinkPreviewPresenting
    private let now: () -> TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void

    private var trigger = LinkPreviewTrigger()
    private weak var textView: CompletingTextView?
    /// The tracking area's owner. Not the text view: `NSTextView` sets its own pointer from
    /// `mouseMoved(with:)` (ADR-0090), and an area it owned would call that override, not ours.
    private var tracker: LinkPreviewTracker?
    private var trackingArea: NSTrackingArea?
    private var monitor: Any?
    private var windowObserver: NSObjectProtocol?
    /// Alive with `monitor`: the window losing key before any card is up.
    private var keyLossObserver: NSObjectProtocol?
    private var hovered: HoveredLink?
    /// The last pointer position, so the anchor is the line of a wrapped run the pointer is on.
    private var lastPoint: NSPoint?

    init(
        parent: @escaping () -> NoteTextView?,
        presenter: LinkPreviewPresenting,
        now: @escaping () -> TimeInterval,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void
    ) {
        self.parent = parent
        self.presenter = presenter
        self.now = now
        self.schedule = schedule
    }

    /// The production wiring, out of the Coordinator's body for its length: the real popover in the
    /// editor's theme, the process clock, the main queue.
    static func live(for coordinator: NoteTextView.Coordinator) -> LinkPreviewController {
        LinkPreviewController(
            parent: { [weak coordinator] in coordinator?.parent },
            presenter: LinkPreviewPopover(theme: { [weak coordinator] in coordinator?.parent.theme ?? .emergency }),
            now: { ProcessInfo.processInfo.systemUptime },
            schedule: { delay, fire in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { fire() } }
            }
        )
    }

    var hasEventMonitor: Bool { monitor != nil }
    var hasTrackingArea: Bool { trackingArea != nil }
    var isObservingWindowKey: Bool { windowObserver != nil }

    /// Installs the tracking area once. `pushInputs` calls this on every update, so a second call
    /// over the same text view adds nothing.
    func attach(to textView: CompletingTextView) {
        if self.textView === textView, trackingArea != nil { return }
        removeTrackingArea()
        self.textView = textView
        let tracker = self.tracker ?? LinkPreviewTracker(controller: self)
        tracker.view = textView
        self.tracker = tracker
        let area = NSTrackingArea(
            rect: .zero,
            // `.assumeInside`: an area added with the pointer already inside gets no `mouseEntered`,
            // and with it `mouseExited` would not arrive for that first visit either.
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .assumeInside],
            owner: tracker,
            userInfo: nil
        )
        textView.addTrackingArea(area)
        trackingArea = area
    }

    // MARK: Events

    /// The pointer came into the text view: the one local monitor for Command, keys and scrolling.
    /// Idempotent, and also called from `pointerMoved`: AppKit does not deliver `mouseEntered` for
    /// a tracking area added with the pointer already inside.
    func pointerEntered() {
        guard monitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .scrollWheel]
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            let commandDown = event.modifierFlags.contains(.command)
            let isEscape = event.keyCode == 53
            // Local monitors are delivered on the main thread; only the signature does not say so.
            let consumed = MainActor.assumeIsolated {
                self?.monitored(type, commandDown: commandDown, isEscape: isEscape) ?? false
            }
            return consumed ? nil : event
        }
        observeKeyLoss()
    }

    func pointerMoved(to point: NSPoint, commandDown: Bool) {
        lastPoint = point
        pointerEntered()
        // No preview input, no run: the trigger then never schedules and the presenter is never
        // asked, whatever the pointer is over.
        hovered = parent()?.links.preview == nil ? nil : textView.flatMap { Self.link(at: point, in: $0) }
        apply(trigger.handle(.pointer(run: hovered?.run, commandDown: commandDown, at: now())))
    }

    func pointerExited() {
        hovered = nil
        lastPoint = nil
        apply(trigger.handle(.pointerExited))
        removeMonitor()
    }

    func commandChanged(isDown: Bool) {
        apply(trigger.handle(.command(isDown: isDown, at: now())))
    }

    /// True when the key was Escape and the preview was up, so the editor must not also act on it.
    func keyPressed(isEscape: Bool) -> Bool {
        let effect = trigger.handle(isEscape ? .escape : .keyDown)
        apply(effect)
        return effect == .hideConsumingEscape
    }

    func scrolled() { apply(trigger.handle(.scroll)) }
    func windowResignedKey() { apply(trigger.handle(.resignKey)) }
    func textChanged() { apply(trigger.handle(.textChanged)) }
    func noteChanged() { apply(trigger.handle(.noteChanged)) }

    /// Hides what is up and takes down the monitor, the observation and the tracking area. Safe on
    /// a text view that never had a window.
    func tearDown() {
        if presenter.isShowing { presenter.hide() }
        trigger = LinkPreviewTrigger()
        hovered = nil
        lastPoint = nil
        removeMonitor()
        stopObservingWindowKey()
        removeTrackingArea()
        tracker = nil
        textView = nil
    }

    // MARK: Effects

    private func monitored(_ type: NSEvent.EventType, commandDown: Bool, isEscape: Bool) -> Bool {
        switch type {
        case .flagsChanged: commandChanged(isDown: commandDown)
        case .keyDown: return keyPressed(isEscape: isEscape)
        case .scrollWheel: scrolled()
        default: break
        }
        return false
    }

    private func apply(_ effect: LinkPreviewTrigger.Effect) {
        switch effect {
        case .none:
            break
        case .schedule(let delay):
            schedule(delay) { [weak self] in
                guard let self else { return }
                apply(trigger.handle(.tick(now())))
            }
        case .show(let run):
            show(run)
        case .hide, .hideConsumingEscape:
            presenter.hide()
            stopObservingWindowKey()
        case .hideAndSchedule(let delay):
            presenter.hide()
            stopObservingWindowKey()
            apply(.schedule(after: delay))
        }
    }

    /// Asks the host for the content and the presenter for the card. Any refusal - no content, no
    /// laid-out rect, a presenter that could not show - leaves the trigger hidden until a fresh dwell.
    private func show(_ run: NSRange) {
        guard let textView, let hovered, hovered.run == run,
              let content = parent()?.links.preview?(hovered.target, hovered.section),
              let rect = anchorRect(for: run, in: textView),
              presenter.show(content, anchoredTo: rect, in: textView)
        else {
            _ = trigger.handle(.showFailed)
            return
        }
        observeWindowKey(of: textView)
    }

    /// The run's rect in the text view's coordinates: the line segment the pointer is on when the
    /// run wraps, otherwise its first. Nil until layout has reached the run, never a zero rect a
    /// popover would clamp to a screen corner.
    private func anchorRect(for run: NSRange, in textView: NSTextView) -> NSRect? {
        guard let layout = textView.textLayoutManager,
              let content = layout.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: run.location),
              let end = content.location(start, offsetBy: run.length),
              let range = NSTextRange(location: start, end: end)
        else { return nil }
        layout.ensureLayout(for: range)
        var rects: [NSRect] = []
        let origin = textView.textContainerOrigin
        layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, frame, _, _ in
            if !frame.isEmpty { rects.append(frame.offsetBy(dx: origin.x, dy: origin.y)) }
            return true
        }
        return rects.first { rect in lastPoint.map(rect.contains) ?? false } ?? rects.first
    }

    // MARK: Plumbing

    private func observeWindowKey(of textView: NSTextView) {
        guard windowObserver == nil, let window = textView.window else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowResignedKey() }
        }
    }

    private func stopObservingWindowKey() {
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }

    /// Watches for the window losing key for as long as the monitor lives, not only while the card
    /// is up: a dwell scheduled before an app switch (Command still held through Cmd+Tab) has no
    /// card yet for `observeWindowKey` to be watching. Losing key cancels that dwell and takes the
    /// monitor down; the next pointer move in the key window installs it again.
    private func observeKeyLoss() {
        guard keyLossObserver == nil, let window = textView?.window else { return }
        keyLossObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windowResignedKey()
                self?.removeMonitor()
            }
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let keyLossObserver { NotificationCenter.default.removeObserver(keyLossObserver) }
        keyLossObserver = nil
    }

    private func removeTrackingArea() {
        if let trackingArea { textView?.removeTrackingArea(trackingArea) }
        trackingArea = nil
    }

    /// The previewable link under `point`: the character there comes from the text view's own
    /// `linkCharacterIndex(at:)`, the one point-to-link resolution clicks use (PG-220), so the
    /// preview answers exactly where a click would follow. That character is then widened to the
    /// wikilink (not an embed) whose source contains it, whole brackets and section included, or
    /// else to the `.editorLink` run a click follows to a note. An external link, a tag, a date and
    /// a file embed have no preview.
    ///
    /// The wikilink widening comes first because the section is not in the link's URL: the run the
    /// trigger keys on is the whole `[[Nota#Sezione]]`, and the section is the parser's to say.
    ///
    /// A text view that was never drawn has an empty TextKit 2 viewport, and the first
    /// `characterIndexForInsertion(at:)` through it answers the end of the text (measured on the
    /// hosted editor fixture: 76 of 76, then 13 once laid out). Laying the viewport out first when
    /// it is empty makes the one resolution answer from the first move; a drawn editor never has
    /// an empty viewport, so this costs it nothing.
    static func link(at point: NSPoint, in textView: CompletingTextView) -> HoveredLink? {
        if let viewport = textView.textLayoutManager?.textViewportLayoutController,
           viewport.viewportBounds.isEmpty {
            viewport.layoutViewport()
        }
        guard let storage = textView.textStorage, let index = textView.linkCharacterIndex(at: point)
        else { return nil }
        let text = storage.string as NSString
        let paragraph = text.paragraphRange(for: NSRange(location: index, length: 0))
        let source = text.substring(with: paragraph)
        for link in WikilinkParser.links(in: source) where !link.isEmbed {
            let local = NSRange(link.range, in: source)
            let run = NSRange(location: paragraph.location + local.location, length: local.length)
            if NSLocationInRange(index, run) {
                return HoveredLink(run: run, target: link.resolvedTitle, section: link.section)
            }
        }
        var effective = NSRange()
        let value = storage.attribute(.editorLink, at: index, longestEffectiveRange: &effective, in: paragraph)
        guard let url = value as? URL,
              case .note(let title) = MarkdownAttributedText.clickTarget(for: url)
        else { return nil }
        return HoveredLink(run: effective, target: title, section: nil)
    }
}

/// The tracking area's owner: forwards the three pointer events to the controller, with the point
/// in the text view's coordinates and Command read off the event.
@MainActor
private final class LinkPreviewTracker: NSResponder {
    private weak var controller: LinkPreviewController?

    init(controller: LinkPreviewController) {
        self.controller = controller
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseEntered(with event: NSEvent) {
        controller?.pointerEntered()
        moved(event)
    }

    override func mouseMoved(with event: NSEvent) { moved(event) }

    override func mouseExited(with event: NSEvent) { controller?.pointerExited() }

    private func moved(_ event: NSEvent) {
        guard let view else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        controller?.pointerMoved(to: point, commandDown: event.modifierFlags.contains(.command))
    }

    /// The text view the controller is attached to, the only view this tracker's area lives on.
    weak var view: NSView?
}
