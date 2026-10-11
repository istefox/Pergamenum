import Foundation
import Testing
@testable import Pergamenum

/// R-20 (ADR-0083 §D7): when the Cmd+hover preview shows and when it goes, as a pure state machine
/// with time passed in. Every close rule of the SPEC is a line here, so the controller that wires
/// them to AppKit has nothing left to decide.
///
/// Times are binary-exact (multiples of 0.125) so the 250 ms dwell compares without rounding.
@Suite struct LinkPreviewTriggerTests {
    private static let dwell = LinkPreviewTrigger.dwell
    private static let runA = NSRange(location: 5, length: 4)
    private static let runB = NSRange(location: 20, length: 6)

    /// A trigger already showing `runA`, with Command held since time 0.
    private static func shown() -> LinkPreviewTrigger {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: runA, commandDown: true, at: 0))
        _ = trigger.handle(.tick(dwell))
        return trigger
    }

    @Test func theDwellIsTwoHundredAndFiftyMilliseconds() {
        #expect(LinkPreviewTrigger.dwell == 0.25)
    }

    // MARK: The dwell

    @Test func aPointerOnARunWithCommandDownSchedulesTheDwellAndShowsNothingYet() {
        var trigger = LinkPreviewTrigger()
        let effect = trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 0))
        #expect(effect == .schedule(after: Self.dwell))
        #expect(trigger.shownRun == nil)
        #expect(trigger.handle(.tick(0.125)) == .none)
        #expect(trigger.shownRun == nil)
    }

    @Test func theTickAtTwoHundredAndFiftyMillisecondsShows() {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 0))
        #expect(trigger.handle(.tick(Self.dwell)) == .show(run: Self.runA))
        #expect(trigger.shownRun == Self.runA)
    }

    @Test func aPointerOnARunWithoutCommandNeverSchedulesOrShows() {
        var trigger = LinkPreviewTrigger()
        #expect(trigger.handle(.pointer(run: Self.runA, commandDown: false, at: 0)) == .none)
        #expect(trigger.handle(.tick(Self.dwell)) == .none)
        #expect(trigger.shownRun == nil)
    }

    @Test func aPointerOnNoRunNeverSchedulesOrShows() {
        var trigger = LinkPreviewTrigger()
        #expect(trigger.handle(.pointer(run: nil, commandDown: true, at: 0)) == .none)
        #expect(trigger.handle(.tick(Self.dwell)) == .none)
        #expect(trigger.shownRun == nil)
    }

    @Test func commandPressedWhileThePointerRestsOnARunStartsTheDwell() {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: Self.runA, commandDown: false, at: 0))
        #expect(trigger.handle(.command(isDown: true, at: 1)) == .schedule(after: Self.dwell))
        #expect(trigger.handle(.tick(1 + Self.dwell)) == .show(run: Self.runA))
    }

    @Test func movingToAnotherRunRestartsTheDwell() {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 0))
        let restart = trigger.handle(.pointer(run: Self.runB, commandDown: true, at: 0.125))
        #expect(restart == .schedule(after: Self.dwell))
        // The first dwell would have ended here; the second has not.
        #expect(trigger.handle(.tick(Self.dwell)) == .none)
        #expect(trigger.handle(.tick(0.125 + Self.dwell)) == .show(run: Self.runB))
    }

    @Test func aKeyDuringTheDwellCancelsIt() {
        // Cmd+S or Cmd+F typed with the pointer over a link must not flash a popover.
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 0))
        _ = trigger.handle(.keyDown)
        #expect(trigger.handle(.tick(Self.dwell)) == .none)
        #expect(trigger.shownRun == nil)
    }

    // MARK: What closes it

    @Test func commandReleasedHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.command(isDown: false, at: 1)) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func thePointerLeavingTheRunHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.pointer(run: nil, commandDown: true, at: 1)) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func thePointerLeavingTheTextViewHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.pointerExited) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func aScrollHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.scroll) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func aKeyHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.keyDown) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func theWindowResigningKeyHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.resignKey) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func theTextChangingHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.textChanged) == .hide)
        #expect(trigger.shownRun == nil)
    }

    @Test func theNoteChangingHides() {
        var trigger = Self.shown()
        #expect(trigger.handle(.noteChanged) == .hide)
        #expect(trigger.shownRun == nil)
    }

    // MARK: Escape

    @Test func escapeWhileShownHidesAndIsConsumed() {
        var trigger = Self.shown()
        #expect(trigger.handle(.escape) == .hideConsumingEscape)
        #expect(trigger.shownRun == nil)
    }

    @Test func escapeWhileHiddenIsLeftToTheEditor() {
        var trigger = LinkPreviewTrigger()
        #expect(trigger.handle(.escape) == .none)
        #expect(trigger.shownRun == nil)
    }

    // MARK: A show that did not take

    @Test func aFailedShowReturnsToHiddenAndNeedsAFreshDwell() {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 0))
        #expect(trigger.handle(.tick(Self.dwell)) == .show(run: Self.runA))

        _ = trigger.handle(.showFailed)
        #expect(trigger.shownRun == nil)
        // Nothing shows by itself afterwards.
        #expect(trigger.handle(.tick(1)) == .none)
        #expect(trigger.shownRun == nil)

        // A fresh dwell does.
        _ = trigger.handle(.pointerExited)
        #expect(trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 2)) == .schedule(after: Self.dwell))
        #expect(trigger.handle(.tick(2 + Self.dwell)) == .show(run: Self.runA))
    }

    // MARK: A key typed before Command is not a chord

    @Test func typingThenPressingCommandThenHoveringStillShows() {
        // A key typed with Command up latched `keyPressed` until Command was released and pressed
        // again, so type, hold Command, move onto a link showed nothing (ADR-0083 §D7).
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.pointer(run: Self.runA, commandDown: false, at: 0))
        _ = trigger.handle(.keyDown)
        #expect(trigger.handle(.command(isDown: true, at: 1)) == .schedule(after: Self.dwell))
        #expect(trigger.handle(.tick(1 + Self.dwell)) == .show(run: Self.runA))
    }

    @Test func typingThenCommandThenMovingOntoALinkShows() {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.keyDown)
        _ = trigger.handle(.command(isDown: true, at: 1))
        #expect(trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 2)) == .schedule(after: Self.dwell))
        #expect(trigger.handle(.tick(2 + Self.dwell)) == .show(run: Self.runA))
    }

    @Test func aPointerEventCarryingCommandClearsAKeyTypedBeforeIt() {
        // No `flagsChanged` reached the trigger (the monitor was not up yet): the pointer event
        // is the first to say Command is down.
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.keyDown)
        #expect(trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 1)) == .schedule(after: Self.dwell))
        #expect(trigger.handle(.tick(1 + Self.dwell)) == .show(run: Self.runA))
    }

    @Test func aKeyPressedWhileCommandIsHeldStillLatchesThroughMovesAndModifiers() {
        var trigger = LinkPreviewTrigger()
        _ = trigger.handle(.command(isDown: true, at: 0))
        _ = trigger.handle(.keyDown)
        // Command already down: a Shift `flagsChanged` and a move with Command are not a new press.
        #expect(trigger.handle(.command(isDown: true, at: 1)) == .none)
        #expect(trigger.handle(.pointer(run: Self.runA, commandDown: true, at: 2)) == .none)
        #expect(trigger.handle(.tick(2 + Self.dwell)) == .none)
        #expect(trigger.shownRun == nil)
        // Released and pressed again, it is a fresh press.
        _ = trigger.handle(.command(isDown: false, at: 3))
        #expect(trigger.handle(.command(isDown: true, at: 4)) == .schedule(after: Self.dwell))
        #expect(trigger.handle(.tick(4 + Self.dwell)) == .show(run: Self.runA))
    }
}
