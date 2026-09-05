import Testing
@testable import Pergamenum

/// The editor's readable-width inset (ADR-0030 §D6): the text column is capped to `cap`
/// points and centred by widening the horizontal `textContainerInset`, rather than by ever
/// setting a frame - `growToFitTheText`'s own header documents why a frame set from here
/// would re-enter SwiftUI's update pass and cost typed text, the same trap this pure
/// arithmetic is designed to stay clear of.
///
/// `Coordinator.horizontalInset(viewWidth:cap:minimum:isOn:)` is pure and static exactly so
/// it can be asserted on without a window - the geometry that actually assigns the result
/// still needs one, and is the coder's job, not this file's.
@Test func readableWidthCentersTheColumnWhenWiderThanTheCap() {
    let inset = NoteTextView.Coordinator.horizontalInset(
        viewWidth: 1200, cap: 720, minimum: 24, isOn: true
    )
    #expect(inset == 240)
}

@Test func readableWidthFallsBackToTheFixedInsetWhenNarrowerThanTheCap() {
    let inset = NoteTextView.Coordinator.horizontalInset(
        viewWidth: 700, cap: 720, minimum: 24, isOn: true
    )
    #expect(inset == 24)
}

/// The exact boundary where `(viewWidth - cap) / 2 == minimum` - asserted explicitly
/// because an off-by-one here is a column that jumps as the window crosses it.
@Test func readableWidthAtTheExactBoundaryStaysAtTheMinimum() {
    let inset = NoteTextView.Coordinator.horizontalInset(
        viewWidth: 768, cap: 720, minimum: 24, isOn: true
    )
    #expect(inset == 24)
}

@Test func readableWidthOffAlwaysReturnsTheMinimumRegardlessOfWidth() {
    let inset = NoteTextView.Coordinator.horizontalInset(
        viewWidth: 2000, cap: 720, minimum: 24, isOn: false
    )
    #expect(inset == 24)
}

@Test func readableWidthNeverGoesNegativeAtAZeroViewWidth() {
    let inset = NoteTextView.Coordinator.horizontalInset(
        viewWidth: 0, cap: 720, minimum: 24, isOn: true
    )
    #expect(inset == 24)
}

@Test func readableWidthNeverGoesNegativeAtANegativeViewWidth() {
    let inset = NoteTextView.Coordinator.horizontalInset(
        viewWidth: -100, cap: 720, minimum: 24, isOn: true
    )
    #expect(inset == 24)
}
