import AppKit
import Testing
@testable import Pergamenum

// ADR-0027 §D1, plan `2026-08-28-unificare-nota-e-testo-in-un-solo-strume`, Task 5
// (R-03, R-04, R-05).
//
// Scope of this file: `FormattingTextView.toggleInlineFormat(_:)`, `.toggleLineFormat(_:)` and
// `.inlineFormat(forKeyEquivalent:modifierFlags:)` - the wiring that turns `InlineFormat` (M8)
// and `LineFormat` (Task 2), both pure and already tested on their own, into edits on a real
// `NSTextView`. No window is created: `NSTextView` instantiates and answers `.string` /
// `.selectedRange()` fine off-screen, the same way `Tests/InlineFormatTests.swift` drives a bare
// `CompletingTextView` for its own non-layout-dependent assertions.
//
// RED: `toggleInlineFormat(_:)`, `.toggleLineFormat(_:)` and
// `.inlineFormat(forKeyEquivalent:modifierFlags:)` are all `fatalError` stubs in
// `FormattingTextView.swift` until Task 5's coder fills them in - every `@Test` below is
// expected to crash the run it belongs to, not merely fail an assertion, the same TDD shape
// `Tests/CardTextViewTests.swift` and `Tests/LineFormatTests.swift` document for Tasks 3 and 2.
// `performKeyEquivalent(with:)` itself is stubbed to return `false` unconditionally rather than
// `fatalError` (it sits in the live key-event path of a hand-run Debug build), so it is not
// asserted directly here - the pure mapping function it will call is what is red instead, per
// the plan's own instruction to "assert against the key-event → action mapping, not against a
// real keystroke".

@MainActor
private func makeView(_ text: String, selecting range: NSRange) -> FormattingTextView {
    let view = FormattingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    view.string = text
    view.setSelectedRange(range)
    return view
}

private func range(of word: String, in text: String) -> NSRange {
    (text as NSString).range(of: word)
}

private func fullRange(_ text: String) -> NSRange {
    NSRange(location: 0, length: (text as NSString).length)
}

// MARK: - R-03: bold/italic/strikethrough over a selection

@MainActor
@Test func boldOverASelectionWrapsExactlyItAndLeavesTheRestByteIdentical() {
    let text = "prima parola dopo"
    let view = makeView(text, selecting: range(of: "parola", in: text))

    view.toggleInlineFormat(.bold)

    #expect(view.string == "prima **parola** dopo")
    // What came before and after the selected word is untouched, character for character.
    #expect(view.string.hasPrefix("prima "))
    #expect(view.string.hasSuffix(" dopo"))
}

@MainActor
@Test func boldOverAnAlreadyBoldSelectionUnwrapsItMarkersOutsideTheSelection() {
    // Double-click shape: the word alone is selected, the markers sit outside it.
    let text = "prima **parola** dopo"
    let view = makeView(text, selecting: range(of: "parola", in: text))

    view.toggleInlineFormat(.bold)

    #expect(view.string == "prima parola dopo")
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "parola")
}

@MainActor
@Test func boldOverAnAlreadyBoldSelectionUnwrapsItMarkersInsideTheSelection() {
    // Drag-select shape: the whole `**parola**`, markers included, is what is selected.
    let text = "prima **parola** dopo"
    let view = makeView(text, selecting: range(of: "**parola**", in: text))

    view.toggleInlineFormat(.bold)

    #expect(view.string == "prima parola dopo")
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "parola")
}

@MainActor
@Test func italicOverAWordWhoseNeighbourIsAlreadyBoldDoesNotProduceFourAsterisks() {
    // The SPEC edge case, re-asserted through this wiring rather than only against
    // `InlineFormat` directly (`InlineFormatTests.boldTextDoesNotReportItselfItalic`):
    // `**parola**` has a lone `*` on each side of `*parola*`, which a naive check would call
    // an italic wrap. `isLongerMarker` says otherwise, so toggling italic here *wraps* instead
    // of (mis-)unwrapping - and the result must be the correct triple-star combination, never
    // a corrupted run of four asterisks.
    let text = "prima **parola** dopo"
    let view = makeView(text, selecting: range(of: "parola", in: text))

    view.toggleInlineFormat(.italic)

    #expect(view.string == "prima ***parola*** dopo")
    #expect(!view.string.contains("****"), "must never produce a run of four asterisks")
}

@MainActor
@Test func strikethroughOverASelectionWrapsWithTildes() {
    let text = "prima parola dopo"
    let view = makeView(text, selecting: range(of: "parola", in: text))

    view.toggleInlineFormat(.strikethrough)

    #expect(view.string == "prima ~~parola~~ dopo")
}

// MARK: - R-04: Cmd+B / Cmd+I resolve to the bold/italic actions

@MainActor
@Test func cmdBResolvesToBold() {
    let format = FormattingTextView.inlineFormat(forKeyEquivalent: "b", modifierFlags: .command)
    #expect(format == .bold)
}

@MainActor
@Test func cmdIResolvesToItalic() {
    let format = FormattingTextView.inlineFormat(forKeyEquivalent: "i", modifierFlags: .command)
    #expect(format == .italic)
}

@MainActor
@Test func cmdShiftBDoesNotResolveToBold() {
    // `ShortcutCommand.newBoard` is Cmd+Shift+B (`ShortcutCommand.swift:215`). R-04 requires no
    // collision, which means exactly `.command` and no more - a Shift held down alongside must
    // resolve to nothing here, leaving the event free to reach `newBoard` instead.
    let format = FormattingTextView.inlineFormat(
        forKeyEquivalent: "b", modifierFlags: [.command, .shift]
    )
    #expect(format == nil)
}

@MainActor
@Test func cmdOptionIDoesNotResolveToItalic() {
    // `ShortcutCommand.toggleInspector` is Cmd+Opt+I (`ShortcutCommand.swift:276`), the mirror
    // case of the one above.
    let format = FormattingTextView.inlineFormat(
        forKeyEquivalent: "i", modifierFlags: [.command, .option]
    )
    #expect(format == nil)
}

@MainActor
@Test func commandWithAnUnrelatedKeyResolvesToNothing() {
    let format = FormattingTextView.inlineFormat(forKeyEquivalent: "x", modifierFlags: .command)
    #expect(format == nil)
}

@MainActor
@Test func bWithNoModifierAtAllResolvesToNothing() {
    // The bare-key tool shortcuts (`t` for Testo, and the freed `n`) are a different path
    // entirely (`BoardChrome.swift:118-128`); this mapping must not also answer for them.
    let format = FormattingTextView.inlineFormat(forKeyEquivalent: "b", modifierFlags: [])
    #expect(format == nil)
}

// MARK: - R-05: bullet/numbered/heading over a multi-line selection

@MainActor
@Test func aBulletAppliedToAMultiLineSelectionPrefixesEveryTouchedLine() {
    let text = "primo\nsecondo\nterzo"
    let view = makeView(text, selecting: fullRange(text))

    view.toggleLineFormat(.bullet)

    #expect(view.string == "- primo\n- secondo\n- terzo")
}

@MainActor
@Test func aNumberedListAppliedToAMultiLineSelectionWritesSequentialMarkers() {
    let text = "primo\nsecondo\nterzo"
    let view = makeView(text, selecting: fullRange(text))

    view.toggleLineFormat(.numbered)

    #expect(view.string == "1. primo\n2. secondo\n3. terzo")
}

@MainActor
@Test func aHeadingAppliedToAMultiLineSelectionPrefixesEveryTouchedLineAtThatLevel() {
    let text = "uno\ndue"
    let view = makeView(text, selecting: fullRange(text))

    view.toggleLineFormat(.heading(level: 2))

    #expect(view.string == "## uno\n## due")
}

// MARK: - After a format action, the selection still covers the same words (toggle round-trips)

@MainActor
@Test func toggleInlineFormatTwiceRoundTripsTextAndSelection() {
    let text = "prima parola dopo"
    let view = makeView(text, selecting: range(of: "parola", in: text))

    view.toggleInlineFormat(.bold)
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "parola")

    view.toggleInlineFormat(.bold)
    #expect(view.string == text)
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "parola")
}

@MainActor
@Test func toggleLineFormatTwiceRoundTripsTextAndKeepsSelectionOnTheWords() {
    let text = "primo secondo"
    let view = makeView(text, selecting: range(of: "secondo", in: text))

    view.toggleLineFormat(.bullet)
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "secondo")

    view.toggleLineFormat(.bullet)
    #expect(view.string == text)
    #expect((view.string as NSString).substring(with: view.selectedRange()) == "secondo")
}
