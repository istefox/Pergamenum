import AppKit
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

/// G2 H15 (ADR-0074): the geometry the arithmetic above feeds. The observer is installed by
/// `observeWidthChanges(of:)` on the clip view's frame notification with `queue: .main`, so the
/// block runs one main-queue hop after the resize; the test awaits exactly that hop. Nothing
/// is shown: the scroll view is never in a window, and its frame is resized directly, which is
/// what a pane resize does to it.
@MainActor
@Test func resizingTheScrollViewRecentresTheColumnThroughTheFrameObserver() async {
    var view = NoteTextView(
        text: .constant("nota\n"), theme: .emergency, noteTitles: [], tagSuggestions: [],
        onFollowLink: { _ in }
    )
    view.readableWidth = true
    let coordinator = view.makeCoordinator()
    let textView = CompletingTextView(usingTextLayoutManager: true)
    let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
    scrollView.documentView = textView
    coordinator.textView = textView
    let cap = view.theme.spacing(.readable)
    coordinator.observeWidthChanges(of: scrollView)
    coordinator.applyReadableWidth(to: textView)
    let before = textView.textContainerInset.width
    #expect(before == (scrollView.contentView.bounds.width - cap) / 2)
    #expect(before > NoteTextView.Coordinator.minimumHorizontalInset)

    scrollView.setFrameSize(NSSize(width: 1000, height: 800))
    await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }

    let after = textView.textContainerInset.width
    #expect(after == (scrollView.contentView.bounds.width - cap) / 2)
    #expect(after < before)
    #expect(textView.textContainerInset.height == NoteTextView.Coordinator.verticalInset)
}
