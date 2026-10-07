import AppKit
import Testing
@testable import Pergamenum

/// (coverage) `CardTextView.Coordinator.matchFocus(_:editable:)`, moved unchanged into
/// `CardTextView+Focus.swift` by PG-395 and read by no test. The behaviour asserted is the one its
/// doc comment states: the card takes the keyboard when editing starts, gives it back when editing
/// ends, and, with no window yet, asks again once the view is in one.
///
/// The window is a plain `NSWindow` that is never ordered in, never made key and never sent an
/// event (R-15 of the hosted-view harness): a first responder can be set on a window nobody sees.
@MainActor
@Suite struct CardTextViewFocusTests {
    private struct Fixture {
        let coordinator: CardTextView.Coordinator
        let scrollView: NSScrollView
        let textView: FormattingTextView
    }

    private func makeFixture(editable: Bool) throws -> Fixture {
        let view = CardTextView(
            text: .constant("testo"),
            theme: .emergency,
            style: CardTextStyle(color: nil, alignment: nil),
            isEditable: editable,
            hidesMarkup: false
        )
        let scrollView = FormattingTextView.scrollableTextView()
        scrollView.frame = CGRect(x: 0, y: 0, width: 200, height: 100)
        let textView = try #require(scrollView.documentView as? FormattingTextView)
        textView.isEditable = editable
        return Fixture(coordinator: view.makeCoordinator(), scrollView: scrollView, textView: textView)
    }

    private func makeWindow(holding scrollView: NSScrollView) -> NSWindow {
        let window = NSWindow(
            contentRect: scrollView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        return window
    }

    @Test func editingTakesTheKeyboard() throws {
        let fixture = try makeFixture(editable: true)
        let window = makeWindow(holding: fixture.scrollView)
        defer { window.contentView = nil }
        #expect(window.firstResponder !== fixture.textView)

        fixture.coordinator.matchFocus(fixture.textView, editable: true)

        #expect(window.firstResponder === fixture.textView)
    }

    @Test func endingEditingGivesTheKeyboardBack() throws {
        let fixture = try makeFixture(editable: true)
        let window = makeWindow(holding: fixture.scrollView)
        defer { window.contentView = nil }
        fixture.coordinator.matchFocus(fixture.textView, editable: true)
        try #require(window.firstResponder === fixture.textView)

        fixture.textView.isEditable = false
        fixture.coordinator.matchFocus(fixture.textView, editable: false)

        #expect(window.firstResponder !== fixture.textView)
    }

    @Test func aCardNotEditingLeavesAnotherViewsKeyboardAlone() throws {
        let fixture = try makeFixture(editable: false)
        let window = makeWindow(holding: fixture.scrollView)
        defer { window.contentView = nil }
        let before = window.firstResponder

        fixture.coordinator.matchFocus(fixture.textView, editable: false)

        #expect(window.firstResponder === before)
        #expect(window.firstResponder !== fixture.textView)
    }

    @Test func aCardAlreadyHoldingTheKeyboardKeepsItWhileEditing() throws {
        let fixture = try makeFixture(editable: true)
        let window = makeWindow(holding: fixture.scrollView)
        defer { window.contentView = nil }
        fixture.coordinator.matchFocus(fixture.textView, editable: true)

        fixture.coordinator.matchFocus(fixture.textView, editable: true)

        #expect(window.firstResponder === fixture.textView)
    }

    /// The very first update after a card is created has no window: the request is repeated once
    /// the view is in one.
    @Test func editingWithoutAWindowAsksAgainOnceTheViewIsInOne() async throws {
        let fixture = try makeFixture(editable: true)
        #expect(fixture.textView.window == nil)

        fixture.coordinator.matchFocus(fixture.textView, editable: true)
        let window = makeWindow(holding: fixture.scrollView)
        defer { window.contentView = nil }

        for _ in 0..<100 where window.firstResponder !== fixture.textView {
            await Task.yield()
        }
        #expect(window.firstResponder === fixture.textView)
    }

    @Test func notEditingWithoutAWindowAsksForNothing() async throws {
        let fixture = try makeFixture(editable: false)

        fixture.coordinator.matchFocus(fixture.textView, editable: false)
        let window = makeWindow(holding: fixture.scrollView)
        defer { window.contentView = nil }
        for _ in 0..<20 { await Task.yield() }

        #expect(window.firstResponder !== fixture.textView)
    }
}
