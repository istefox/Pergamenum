import Foundation
import Testing
@testable import Pergamenum

// ADR-0037 (word-grained markdown reveal-on-caret in the editor), plan
// `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 1 (R-01, R-02, R-04, R-05, R-10).
//
// Scope of this file: `InlineSpanReveal.constructs(inParagraph:)` and
// `.revealed(inParagraph:touchedBy:)` - pure offset arithmetic over a single paragraph's
// `String`, no delegate, no `NSTextView`, no layout pass. `constructs` decides what a
// bold/italic/strikethrough/wikilink/CommonMark-link construct's whole extent is (ADR §D4);
// `revealed` decides which of those extents a caret or a selection touches (ADR §D5).
//
// RED: both functions are stub bodies in `InlineSpanReveal.swift` returning `[]`
// unconditionally until Task 1's coder fills them in. Every `@Test` below that asserts a
// non-empty result is expected to fail red, not to crash the run - this is TDD, the
// "no construct"/"out of bounds" edge cases are legitimately green against the stub too, and
// that is not a bug in the test.

private func range(of word: String, in text: String) -> NSRange {
    (text as NSString).range(of: word)
}

private func fullRange(_ text: String) -> NSRange {
    NSRange(location: 0, length: (text as NSString).length)
}

// MARK: - Single constructs, whole run including delimiters (ADR §D4)

@Test func boldAloneIsTheWholeRunDelimitersIncluded() {
    let text = "**grassetto**"
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [fullRange(text)])
}

@Test func strikethroughAloneIsTheWholeRunDelimitersIncluded() {
    let text = "~~barrato~~"
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [fullRange(text)])
}

@Test func aBareWikilinkIsItsWholeBracketedRun() {
    let text = "[[Nota]]"
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [fullRange(text)])
}

@Test func aWikilinkWithAnAliasIsStillOneWholeRun() {
    let text = "[[Nota reale|testo mostrato]]"
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [fullRange(text)])
}

@Test func aCommonMarkLinkIsReconstructedAsOneWholeRunFromTheTwoLinkSyntaxHalves() {
    // `MarkdownStyler` never emits this as a single span (F2 in the plan): it emits `[`
    // as one `.linkSyntax` span and `](https://x.y)` as another. `constructs` joins them.
    let text = "[testo](https://x.y)"
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [fullRange(text)])
}

// MARK: - R-01: several constructs on one line, only the caret's own reveals

@Test func twoBoldRunsOnOneLineOnlyTheCaretsOwnRunReveals() {
    let text = "**uno** e **due**"
    let first = range(of: "**uno**", in: text)
    let second = range(of: "**due**", in: text)
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [first, second])

    let caretInFirst = NSRange(location: first.location + 3, length: 0) // inside "uno"
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: caretInFirst) == [first])
}

@Test func twoCommonMarkLinksOnOneLineRevealOnlyTheOneTouched() {
    // The pairing's real test: two `[` .. `](url)` reconstructions on the same line must not
    // cross-pollinate.
    let text = "[uno](https://a.b) e [due](https://c.d)"
    let first = range(of: "[uno](https://a.b)", in: text)
    let second = range(of: "[due](https://c.d)", in: text)
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [first, second])

    let caretInSecond = NSRange(location: second.location + 2, length: 0) // inside "due"
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: caretInSecond) == [second])
}

// MARK: - R-05: nesting, innermost wins for a caret

@Test func nestedEmphasisACaretInTheInnerRunRevealsTheInnerRunOnly() {
    let text = "**bold con *italic* dentro**"
    let outer = fullRange(text)
    let inner = range(of: "*italic*", in: text)
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [outer, inner])

    let caretInInner = NSRange(location: inner.location + 4, length: 0) // inside "italic"
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: caretInInner) == [inner])
}

@Test func nestedEmphasisACaretInTheOuterPrefixRevealsTheOuterRunOnly() {
    let text = "**bold con *italic* dentro**"
    let outer = fullRange(text)

    let prefix = range(of: "bold con ", in: text)
    let caretInOuterPrefix = NSRange(location: prefix.location + 2, length: 0)
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: caretInOuterPrefix) == [outer])
}

// MARK: - Adjacency: a caret exactly at either delimiter boundary still reveals (closed interval)

@Test func aCaretExactlyAtEitherDelimiterBoundaryStillReveals() {
    let text = "**grassetto**"
    let span = fullRange(text)

    let atFirstStar = NSRange(location: span.location, length: 0)
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: atFirstStar) == [span])

    let afterLastStar = NSRange(location: NSMaxRange(span), length: 0)
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: afterLastStar) == [span])
}

// MARK: - R-04: a non-empty selection reveals every span it touches, no innermost filtering

@Test func aSelectionSpanningTwoRunsRevealsBothWithNoInnermostFiltering() {
    let text = "**uno** e **due**"
    let first = range(of: "**uno**", in: text)
    let second = range(of: "**due**", in: text)

    let from = first.location + 2 // inside "uno"
    let to = second.location + 2 // inside "due"
    let selection = NSRange(location: from, length: to - from)

    let revealed = InlineSpanReveal.revealed(inParagraph: text, touchedBy: selection)
    #expect(revealed.count == 2)
    #expect(revealed.contains(first))
    #expect(revealed.contains(second))
}

// MARK: - Edge cases

@Test func aLineWithNoConstructReturnsNoConstructsAndRevealsNothing() {
    let text = "solo testo semplice, niente da rivelare"
    #expect(InlineSpanReveal.constructs(inParagraph: text) == [])

    let caret = NSRange(location: 5, length: 0)
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: caret) == [])
}

@Test func anOutOfBoundsRangeReturnsEmptyWithoutCrashing() {
    let text = "**grassetto**"
    let outOfBounds = NSRange(location: 999, length: 3)
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: outOfBounds) == [])
}

@Test func anNSNotFoundRangeReturnsEmptyWithoutCrashing() {
    // What a text view with no selection/composition reports; it must be read as "nothing
    // here", not as a location to look up (the same rule `MarkupRevealTests` pins for
    // `MarkupReveal.paragraphs`'s `markedRange`/`currentMatch` inputs).
    let text = "**grassetto**"
    let notFound = NSRange(location: NSNotFound, length: 0)
    #expect(InlineSpanReveal.revealed(inParagraph: text, touchedBy: notFound) == [])
}
