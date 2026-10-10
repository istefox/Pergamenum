import Foundation

// ADR-0083 §D7 (PG-386, N3 session B).

/// When the Cmd+hover preview shows and when it goes (ADR-0083 §D7): a pure state machine, time
/// passed in, so the dwell and every close rule are asserted without a clock or a window.
///
/// It shows when Command is held, no non-modifier key has been pressed since, the pointer rests
/// on one run, and `dwell` has passed since the last of those became true. Shift and Option do not
/// matter, so the preview stays while the person reaches for a click variant.
struct LinkPreviewTrigger: Equatable, Sendable {
    /// How long Command, the pointer on one run and no other key must hold before it shows.
    static let dwell: TimeInterval = 0.25

    /// The run the preview is showing for, nil while hidden.
    private(set) var shownRun: NSRange?
    /// The run under the pointer, nil when it is on none or outside the text view.
    private var pointerRun: NSRange?
    private var commandDown = false
    /// A key was pressed while Command was held: nothing shows again until Command is released,
    /// so a Cmd+S or Cmd+F typed with the pointer over a link never flashes a preview. A key typed
    /// with Command up is forgotten when Command goes down.
    private var keyPressed = false
    /// When the running dwell started, nil when none is running.
    private var dwellStart: TimeInterval?

    enum Event: Equatable, Sendable {
        case pointer(run: NSRange?, commandDown: Bool, at: TimeInterval)
        case command(isDown: Bool, at: TimeInterval)
        case tick(TimeInterval)
        case keyDown
        case escape
        case scroll
        case pointerExited
        case resignKey
        case textChanged
        case noteChanged
        case showFailed
    }

    enum Effect: Equatable, Sendable {
        case none
        case schedule(after: TimeInterval)
        case show(run: NSRange)
        case hide
        case hideConsumingEscape
    }

    mutating func handle(_ event: Event) -> Effect {
        switch event {
        case let .pointer(run, isDown, time):
            return pointer(run, commandDown: isDown, at: time)
        case let .command(isDown, time):
            return command(isDown: isDown, at: time)
        case .tick(let time):
            guard shownRun == nil, let start = dwellStart, let run = pointerRun,
                  commandDown, !keyPressed, time - start >= Self.dwell
            else { return .none }
            dwellStart = nil
            shownRun = run
            return .show(run: run)
        case .keyDown:
            keyPressed = true
            return close()
        case .escape:
            keyPressed = true
            return close() == .hide ? .hideConsumingEscape : .none
        case .pointerExited:
            pointerRun = nil
            return close()
        case .scroll, .resignKey, .textChanged, .noteChanged:
            return close()
        case .showFailed:
            // Back to hidden with no dwell running: only a fresh pointer event starts one.
            shownRun = nil
            dwellStart = nil
            return .none
        }
    }

    private mutating func pointer(_ run: NSRange?, commandDown isDown: Bool, at time: TimeInterval) -> Effect {
        let runChanged = run != pointerRun
        pointerRun = run
        // A key typed with Command up does not count against a Command held from here on: only a
        // key pressed while Command is held does, so Command going down clears it (ADR-0083 §D7).
        if !isDown || !commandDown { keyPressed = false }
        commandDown = isDown
        if let shown = shownRun {
            if run == shown && isDown { return .none }
            return close()
        }
        guard isDown, run != nil, !keyPressed else {
            dwellStart = nil
            return .none
        }
        if !runChanged, dwellStart != nil { return .none }
        dwellStart = time
        return .schedule(after: Self.dwell)
    }

    private mutating func command(isDown: Bool, at time: TimeInterval) -> Effect {
        // A `flagsChanged` for Shift or Option while Command stays held is not a new press.
        guard isDown != commandDown else { return .none }
        commandDown = isDown
        // Command going down or up ends whatever key came before it: the latch is for a key pressed
        // while Command is held, so type-then-Command-then-hover still previews.
        keyPressed = false
        guard isDown else { return close() }
        guard pointerRun != nil else { return .none }
        dwellStart = time
        return .schedule(after: Self.dwell)
    }

    /// Cancels the dwell and hides what is shown.
    private mutating func close() -> Effect {
        dwellStart = nil
        guard shownRun != nil else { return .none }
        shownRun = nil
        return .hide
    }
}
