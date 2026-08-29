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

// MARK: - Return inside a card's list, its renumbering, and one undo step per press
//
// ADR-0028, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 6 (R-07, R-08, R-12).
//
// The card's half of what `Tests/NoteListEditingTests.swift` asserts for the note editor, and
// deliberately the same shape: the arithmetic is `ListContinuation`'s and is already covered by
// `Tests/ListContinuationTests.swift` (Task 2), so what is under test here is only the *wiring* -
// that a Return reaching a real `FormattingTextView` turns into that function's answer, as one
// edit on the storage and therefore one undo step on the card's own stack (ADR-0027 §D2).
//
// Two fixtures, on purpose. The caret assertions use the bare `makeView` above, with no
// coordinator: `applyStyling` on a windowless text view leaves the selection at the end of the
// text (the harness artifact `Tests/CardConcealmentTests.swift:76-80` records), so a wired card
// cannot answer "where did the caret land". The undo assertions need the opposite - the
// coordinator, because the manager Cmd+Z reaches is the one it hands out from
// `undoManager(for:)`, and because the renumber pass they exercise lives in its `textDidChange`.
//
// RED, expected, until Task 6's coder overrides `FormattingTextView.insertNewline(_:)` and adds
// the renumber pass to `CardTextView.Coordinator.textDidChange`:
// `returnAtTheEndOfACardsBulletItemContinuesTheList`,
// `returnOnACardsEmptyItemLeavesTheList`,
// `returnInsideACardsOrderedRunRenumbersTheRestOfItInTheSameEdit`,
// `returnAtTheEndOfACardsCheckboxItemContinuesWithAnEmptyBox`,
// `oneUndoOnTheCardsOwnStackTakesBackTheWholeContinuation`,
// `oneUndoOnTheCardsOwnStackTakesBackTheContinuationAndItsRenumberingTogether` and
// `deletingAMiddleItemOfACardsOrderedRunRenumbersTheRestAndOneUndoTakesBothBack` all fail on
// today's build, where Return falls through to AppKit and inserts a bare newline and nothing
// renumbers anything. `returnOnACardsPlainLineInsertsAPlainNewlineAndNothingElse` is green on
// arrival - it is the fall-through case, and it is here to pin that the claim stays narrow once
// the rest goes green.

/// Return as it reaches the card's text view: the responder method the plan names as the
/// implementation site, never a synthesised `NSEvent` - routing one needs a window and a first
/// responder, neither of which this file has ever built.
@MainActor
private func pressReturn(_ view: FormattingTextView) {
    view.insertNewline(nil)
}

/// The offset just past `line`'s last character - where a caret sits when Return is pressed at
/// the end of that line.
private func endOf(_ line: String, in text: String) -> Int {
    NSMaxRange((text as NSString).range(of: line))
}

/// The leading ordinal of every line that carries one, in document order. Reads a run's
/// contiguity off the text itself rather than off a hard-coded expected string.
private func ordinals(in text: String) -> [Int] {
    text.split(separator: "\n", omittingEmptySubsequences: false).compactMap {
        Int($0.prefix { $0.isNumber })
    }
}

@MainActor
private struct WiredCard {
    let scrollView: NSScrollView
    let textView: FormattingTextView
    let coordinator: CardTextView.Coordinator
}

/// A card wired the way `CardTextView.makeNSView` wires it - the coordinator as the text view's
/// delegate (which is what makes `undoManager(for:)` answer), `allowsUndo`, and the two
/// decoration-delegate assignments - holding `text` with a caret at `caret`.
///
/// The same compromise `Tests/CardConcealmentTests.swift:35` makes: `makeNSView` needs an
/// `NSViewRepresentable.Context` no test can build, so the harness repeats its assignments but
/// calls the real coordinator for everything it is actually asserting.
@MainActor
private func wiredCard(_ text: String, caret: Int) throws -> WiredCard {
    let view = CardTextView(
        text: .constant(text),
        theme: .emergency,
        style: CardTextStyle(color: nil, alignment: nil),
        isEditable: true,
        hidesMarkup: true
    )
    let coordinator = view.makeCoordinator()
    let scrollView = FormattingTextView.scrollableTextView()
    let textView = try #require(
        scrollView.documentView as? FormattingTextView,
        "scrollableTextView() must hand back an instance of the receiving class"
    )
    textView.delegate = coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.textContentStorage?.delegate = coordinator.decorations
    textView.textLayoutManager?.delegate = coordinator.decorations
    // Assigning `.string` posts no `textDidChange` and registers no undo action, so "one undo
    // returns to this" stays an assertion about the edit alone.
    textView.string = text
    coordinator.configure(textView, editable: true)
    coordinator.applyStyling(to: textView)
    textView.setSelectedRange(NSRange(location: caret, length: 0))
    return WiredCard(scrollView: scrollView, textView: textView, coordinator: coordinator)
}

// MARK: R-07: continuing and leaving a list on a card

@MainActor
@Test func returnAtTheEndOfACardsBulletItemContinuesTheList() {
    let view = makeView("- primo", selecting: NSRange(location: 7, length: 0))

    pressReturn(view)

    #expect(view.string == "- primo\n- ")
    // Past the marker it just wrote, not before it: the next character typed is the item's text.
    #expect(view.selectedRange() == NSRange(location: 10, length: 0))
}

@MainActor
@Test func returnOnACardsEmptyItemLeavesTheList() {
    // The state the test above ends in, set up directly rather than by pressing Return twice:
    // this is R-07's *exit* rule and it has to be able to fail on its own.
    let view = makeView("- primo\n- ", selecting: NSRange(location: 10, length: 0))

    pressReturn(view)

    // The empty item's prefix goes and no line is inserted - one blank paragraph after
    // "- primo", not two.
    #expect(view.string == "- primo\n")
    #expect(view.selectedRange() == NSRange(location: 8, length: 0))
}

@MainActor
@Test func returnAtTheEndOfACardsCheckboxItemContinuesWithAnEmptyBox() {
    let text = "- [ ] fai"
    let view = makeView(text, selecting: NSRange(location: (text as NSString).length, length: 0))

    pressReturn(view)

    // Always an empty box, whatever this item's state - a To Do card that continued "- [x]"
    // would tick something nobody did.
    #expect(view.string == "- [ ] fai\n- [ ] ")
    #expect(view.selectedRange() == NSRange(location: 16, length: 0))
}

@MainActor
@Test func returnOnACardsPlainLineInsertsAPlainNewlineAndNothingElse() {
    let text = "prosa normale"
    let view = makeView(text, selecting: NSRange(location: (text as NSString).length, length: 0))

    pressReturn(view)

    // The claim has to stay narrow: everywhere that is not a list item, Return is AppKit's own
    // Return and writes exactly one newline.
    #expect(view.string == "prosa normale\n")
    #expect(view.selectedRange() == NSRange(location: 14, length: 0))
}

// MARK: R-08: an ordered run on a card stays contiguous

@MainActor
@Test func returnInsideACardsOrderedRunRenumbersTheRestOfItInTheSameEdit() throws {
    let text = "1. uno\n2. due\n3. tre"
    let caret = endOf("2. due", in: text)
    // Derived from the pure function Task 2 already tested, not hand-written: what is asserted
    // here is that the card ends up holding that exact answer, and a hand-copied string would
    // only be asserting this test's own arithmetic.
    let expected = try #require(
        ListContinuation.newline(in: text, at: NSRange(location: caret, length: 0))
    )
    let view = makeView(text, selecting: NSRange(location: caret, length: 0))

    pressReturn(view)

    #expect(view.string == expected.text)
    #expect(view.selectedRange() == expected.selection)
    // R-08 spelled out: four items, numbered 1 to 4, no gap left where the new one went in.
    #expect(ordinals(in: view.string) == [1, 2, 3, 4])
}

// MARK: R-12: one press, one undo, on the card's own stack

@MainActor
@Test func oneUndoOnTheCardsOwnStackTakesBackTheWholeContinuation() throws {
    let card = try wiredCard("- primo", caret: 7)
    let undo = card.coordinator.undoManager
    // Load-bearing premise, not decoration: the edit registers on whatever `textView.undoManager`
    // resolves to, and this view has no window behind it - so if the delegate's manager is not
    // the one, `undo()` below would be undoing an empty stack and the assertion would pass for
    // the wrong reason.
    #expect(card.textView.undoManager === undo, "la carta deve annullare sulla propria pila")

    pressReturn(card.textView)
    #expect(card.textView.string == "- primo\n- ")

    undo.undo()

    #expect(card.textView.string == "- primo")
}

@MainActor
@Test func oneUndoOnTheCardsOwnStackTakesBackTheContinuationAndItsRenumberingTogether() throws {
    let text = "1. uno\n2. due\n3. tre"
    let caret = endOf("2. due", in: text)
    let expected = try #require(
        ListContinuation.newline(in: text, at: NSRange(location: caret, length: 0))
    )
    let card = try wiredCard(text, caret: caret)
    let undo = card.coordinator.undoManager
    #expect(card.textView.undoManager === undo, "la carta deve annullare sulla propria pila")

    pressReturn(card.textView)
    // Asserted before the undo on purpose: without it this test would pass on a build where
    // Return only inserts a bare newline, since one undo takes *that* back too. What has to be
    // undone in one step is the renumbering as well.
    #expect(card.textView.string == expected.text)

    undo.undo()

    #expect(card.textView.string == text)
}

/// The assertion that turns ADR-0027 §D2's «AppKit groups them» into a fact.
///
/// A deletion is not a Return, so the insertion-time renumbering `ListContinuation.newline`
/// performs inside its own returned string cannot answer for it: the run is made contiguous
/// again by the coordinator's `textDidChange` pass, a *second* write, and whether one Cmd+Z
/// takes both back is a claim about `groupsByEvent` rather than about either write. If it fails,
/// the fix is the coder's - group the pair explicitly with
/// `beginUndoGrouping`/`endUndoGrouping` - never a weaker assertion here: a person who deletes
/// an item and presses Cmd+Z once must get their item back, not a list still renumbered around
/// the hole it left.
@MainActor
@Test func deletingAMiddleItemOfACardsOrderedRunRenumbersTheRestAndOneUndoTakesBothBack() throws {
    let text = "1. uno\n2. due\n3. tre"
    let card = try wiredCard(text, caret: 0)
    let undo = card.coordinator.undoManager
    #expect(card.textView.undoManager === undo, "la carta deve annullare sulla propria pila")

    // The app's own atomic idiom, which is what a Backspace over a selected line reaches too:
    // `shouldChangeText` is the call that registers the undo action, so a raw
    // `textStorage.replaceCharacters` without it would leave nothing to undo.
    let victim = (card.textView.string as NSString).range(of: "2. due\n")
    #expect(victim.location != NSNotFound, "premessa: la riga da cancellare deve esistere")
    #expect(
        card.textView.shouldChangeText(in: victim, replacementString: ""),
        "premessa: la vista deve accettare la modifica"
    )
    card.textView.textStorage?.replaceCharacters(in: victim, with: "")
    card.textView.didChangeText()

    #expect(card.textView.string == "1. uno\n2. tre")
    #expect(ordinals(in: card.textView.string) == [1, 2])

    // One call, not two.
    undo.undo()

    #expect(card.textView.string == text)
}
