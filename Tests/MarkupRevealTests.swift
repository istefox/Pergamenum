import Foundation
import Testing
@testable import Pergamenum

// `MarkupReveal.paragraphs` (ADR-0018 §D2), pure offset arithmetic against a plain
// `String` - no `NSTextView`, no delegate, no layout pass. The four triggers, one test
// each, plus the edge cases a stale or out-of-bounds range must not crash on.

/// Three headings, each on its own line, so every offset used below can be read off the
/// text itself:
///
/// ```
/// 0  "# Uno\n"       (6)
/// 6  "corpo uno\n"   (10)
/// 16 "# Due\n"       (6)
/// 22 "corpo due\n"   (10)
/// 32 "# Tre\n"       (6)
/// 38 "corpo tre\n"   (10)
/// ```
private let note = "# Uno\ncorpo uno\n# Due\ncorpo due\n# Tre\ncorpo tre\n"
private let headingUno = 0
private let corpoUno = 6
private let headingDue = 16
private let corpoDue = 22
private let headingTre = 32

private let noComposition = NSRange(location: NSNotFound, length: 0)

@Test func theCaretsParagraphIsRevealed() {
    // Anywhere inside the paragraph, not only at its very start.
    let caret = NSRange(location: 3, length: 0)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: caret, markedRange: noComposition, currentMatch: nil)
            == [headingUno]
    )
}

@Test func aCaretExactlyAtAParagraphsStartBelongsToThatParagraph() {
    // The boundary case: offset 16 is both the end of "corpo uno\n" and the start of
    // "# Due\n". A caret there is about to type into the heading, not the line above.
    let caret = NSRange(location: headingDue, length: 0)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: caret, markedRange: noComposition, currentMatch: nil)
            == [headingDue]
    )
}

@Test func aSelectionSpanningSeveralParagraphsRevealsAllOfThem() {
    // From inside "corpo uno" to inside "corpo due": three paragraphs touched, not just
    // the two the selection's endpoints happen to sit in.
    let selection = NSRange(location: 8, length: 17)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: selection, markedRange: noComposition, currentMatch: nil)
            == [corpoUno, headingDue, corpoDue]
    )
}

@Test func anActiveIMECompositionRevealsItsOwnParagraphTooAndNotOnlyTheSelections() {
    let caret = NSRange(location: 0, length: 0)
    let marked = NSRange(location: 34, length: 2)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: caret, markedRange: marked, currentMatch: nil)
            == [headingUno, headingTre]
    )
}

@Test func theFindBarsCurrentMatchRevealsItsParagraphTooAndNotOnlyTheSelections() {
    let caret = NSRange(location: 0, length: 0)
    let match = NSRange(location: 24, length: 3)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: caret, markedRange: noComposition, currentMatch: match)
            == [headingUno, corpoDue]
    )
}

@Test func noActiveCompositionDoesNotRevealAnythingOnItsOwn() {
    // `NSNotFound` is what a text view with no composition reports; it must be read as
    // "nothing here", not as a location to look up.
    let caret = NSRange(location: 0, length: 0)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: caret, markedRange: noComposition, currentMatch: nil)
            == [headingUno]
    )
}

// MARK: Edge cases

@Test func anOutOfBoundsSelectionIsSkippedRatherThanTrusted() {
    // The find bar's last match, say, after an edit shortened the note out from under it.
    let stale = NSRange(location: 100, length: 5)
    #expect(
        MarkupReveal.paragraphs(in: "corpo\n", selection: stale, markedRange: noComposition, currentMatch: nil)
            .isEmpty
    )
}

@Test func anOutOfBoundsCurrentMatchIsSkippedWhileTheSelectionStillReveals() {
    let caret = NSRange(location: 0, length: 0)
    let staleMatch = NSRange(location: 999, length: 3)
    #expect(
        MarkupReveal.paragraphs(in: note, selection: caret, markedRange: noComposition, currentMatch: staleMatch)
            == [headingUno]
    )
}

@Test func anEmptyDocumentDoesNotCrashAndRevealsNothingBeyondItself() {
    let caret = NSRange(location: 0, length: 0)
    let result = MarkupReveal.paragraphs(in: "", selection: caret, markedRange: noComposition, currentMatch: nil)
    #expect(result.allSatisfy { $0 == 0 })
}

// MARK: Lists (ADR-0028, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 4, R-03)

/// Three list items, each its own paragraph:
///
/// ```
/// 0  "- primo\n"    (8)
/// 8  "- secondo\n"  (10)
/// 18 "- terzo\n"    (8)
/// ```
private let list = "- primo\n- secondo\n- terzo\n"
private let primo = 0
private let secondo = 8
private let terzo = 18

@Test func onlyTheCaretsOwnItemIsRevealedInAList() {
    // A list is three paragraphs like any other three, and `paragraphs` is offset
    // arithmetic that knows nothing about markdown - so the item being edited comes back
    // and its neighbours do not. Green on arrival is the expected result: a red here would
    // mean the reveal rule needs a list arm, which is a finding, not something to patch
    // quietly.
    let caret = NSRange(location: secondo + 4, length: 0)
    let revealed = MarkupReveal.paragraphs(
        in: list, selection: caret, markedRange: noComposition, currentMatch: nil
    )
    #expect(revealed == [secondo])
    #expect(!revealed.contains(primo))
    #expect(!revealed.contains(terzo))
}

@Test func aCaretAtTheVeryEndOfTheDocumentStillBelongsToTheLastParagraph() {
    // No trailing newline: the whole string is one paragraph, and a caret at `length`
    // still lands inside it rather than in a paragraph past the end of the text.
    let text = "corpo"
    let caret = NSRange(location: (text as NSString).length, length: 0)
    #expect(
        MarkupReveal.paragraphs(in: text, selection: caret, markedRange: noComposition, currentMatch: nil) == [0]
    )
}

// MARK: - `MarkupReveal.inlineSpans` (ADR-0037 §D6)
//
// Plan `2026-09-08-word-grained-markdown-reveal-on-caret-in`, Task 2. Same four inputs and
// the same three triggers as `MarkupReveal.paragraphs` above, but the note-wide table is
// keyed by paragraph-start offset with **paragraph-relative** `NSRange` values - the same
// key space `hiddenMarkers` already uses (ADR-0037 §D1). The production body in
// `NoteTextView+Reveal.swift` is a `[:]` stub (tester owns the interface, coder the body,
// per this chain's plan conventions): every test below that expects a non-empty table is
// RED until Task 2's coder fills it in.

@Suite("MarkupReveal.inlineSpans")
struct MarkupRevealInlineSpansTests {
    private let noComposition = NSRange(location: NSNotFound, length: 0)

    /// Three paragraphs, offsets and constructs readable off the text itself:
    ///
    /// ```
    /// 0  "riga uno\n"           (9)   plain, no inline construct
    /// 9  "testo *enfasi* qui\n" (19)  "*enfasi*" at local (6, 8) -> absolute (15, 8)
    /// 28 "altro *segno* qui\n"  (18)  "*segno*" at local (6, 7) -> absolute (34, 7)
    /// ```
    private let inlineNote = "riga uno\ntesto *enfasi* qui\naltro *segno* qui\n"
    private let paragraphA = 0
    private let paragraphB = 9
    private let paragraphC = 28

    @Test func aCaretInTheSecondParagraphKeysOnlyThatParagraph() {
        let caret = NSRange(location: 19, length: 0) // inside "*enfasi*"
        #expect(
            MarkupReveal.inlineSpans(
                in: inlineNote, selection: caret, markedRange: noComposition, currentMatch: nil
            ) == [paragraphB: [NSRange(location: 6, length: 8)]]
        )
    }

    @Test func aSelectionSpanningTwoParagraphsKeysBoth() {
        // From inside "*enfasi*" (paragraph B) to inside "*segno*" (paragraph C), covering
        // neither paragraph's boundary in full - the ordinary partial-overlap case, not the
        // full-coverage rule the next test covers.
        let selection = NSRange(location: 20, length: 16)
        #expect(
            MarkupReveal.inlineSpans(
                in: inlineNote, selection: selection, markedRange: noComposition, currentMatch: nil
            ) == [
                paragraphB: [NSRange(location: 6, length: 8)],
                paragraphC: [NSRange(location: 6, length: 7)],
            ]
        )
    }

    @Test func aFullyCoveredParagraphYieldsOneWholeSpanRatherThanItsParsedConstruct() {
        // The trigger's bounds exactly match paragraph B's own bounds - ADR-0037 §D5's "do
        // not parse" rule: the answer is the whole paragraph (0, 19), never the inner
        // "*enfasi*" construct at (6, 8) that a parse would have found instead.
        let selection = NSRange(location: paragraphB, length: 19)
        #expect(
            MarkupReveal.inlineSpans(
                in: inlineNote, selection: selection, markedRange: noComposition, currentMatch: nil
            ) == [paragraphB: [NSRange(location: 0, length: 19)]]
        )
    }

    @Test func theFindBarsCurrentMatchIsATriggerTooAndNotOnlyTheSelection() {
        let caret = NSRange(location: 19, length: 0) // paragraph B's construct
        let match = NSRange(location: 36, length: 2) // inside paragraph C's "*segno*"
        #expect(
            MarkupReveal.inlineSpans(
                in: inlineNote, selection: caret, markedRange: noComposition, currentMatch: match
            ) == [
                paragraphB: [NSRange(location: 6, length: 8)],
                paragraphC: [NSRange(location: 6, length: 7)],
            ]
        )
    }

    @Test func anActiveIMECompositionIsATriggerTooAndNotOnlyTheSelection() {
        let caret = NSRange(location: 19, length: 0) // paragraph B's construct
        let marked = NSRange(location: 36, length: 2) // inside paragraph C's "*segno*"
        #expect(
            MarkupReveal.inlineSpans(
                in: inlineNote, selection: caret, markedRange: marked, currentMatch: nil
            ) == [
                paragraphB: [NSRange(location: 6, length: 8)],
                paragraphC: [NSRange(location: 6, length: 7)],
            ]
        )
    }

    // MARK: Edge cases

    @Test func aParagraphWithNoConstructContributesNoKey() {
        let caret = NSRange(location: paragraphA, length: 0) // inside "riga uno", no markup at all
        #expect(
            MarkupReveal.inlineSpans(
                in: inlineNote, selection: caret, markedRange: noComposition, currentMatch: nil
            ).isEmpty
        )
    }

    @Test func anOutOfBoundsSelectionIsSkippedRatherThanTrusted() {
        // The find bar's last match, say, after an edit shortened the note out from under it.
        let stale = NSRange(location: 100, length: 5)
        #expect(
            MarkupReveal.inlineSpans(
                in: "corpo\n", selection: stale, markedRange: noComposition, currentMatch: nil
            ).isEmpty
        )
    }

    @Test func anOutOfBoundsCurrentMatchIsSkippedWithoutCrashing() {
        let caret = NSRange(location: 0, length: 0)
        let staleMatch = NSRange(location: 999, length: 3)
        #expect(
            MarkupReveal.inlineSpans(
                in: "corpo\n", selection: caret, markedRange: noComposition, currentMatch: staleMatch
            ).isEmpty
        )
    }

    @Test func aNotFoundSelectionIsSkippedWithoutCrashing() {
        // A real `NSTextView` never reports `NSNotFound` from `selectedRange()`, but
        // `inlineSpans` shares its out-of-bounds tolerance with `MarkupReveal`'s private
        // `add(_:of:to:)`, which applies the same `NSNotFound` guard to every trigger it is
        // handed - this exercises that guard on the selection input itself.
        let notFound = NSRange(location: NSNotFound, length: 0)
        #expect(
            MarkupReveal.inlineSpans(
                in: "corpo\n", selection: notFound, markedRange: noComposition, currentMatch: nil
            ).isEmpty
        )
    }

    // MARK: Cross-invariant with `MarkupReveal.paragraphs` (ADR-0037 §D6)

    @Test func everyInlineSpansKeyIsAlsoAParagraphsKey() {
        // "Every paragraph key in `inlineSpans`' answer is also in `paragraphs`' answer for
        // the same inputs" (ADR-0037 §D6) - checked over a handful of the triggers exercised
        // above, including ones with no revealed span at all.
        let cases: [(selection: NSRange, markedRange: NSRange, currentMatch: NSRange?)] = [
            (NSRange(location: 19, length: 0), noComposition, nil),
            (NSRange(location: 20, length: 16), noComposition, nil),
            (NSRange(location: paragraphB, length: 19), noComposition, nil),
            (NSRange(location: 19, length: 0), noComposition, NSRange(location: 36, length: 2)),
            (NSRange(location: 19, length: 0), NSRange(location: 36, length: 2), nil),
            (NSRange(location: 0, length: 0), noComposition, nil),
        ]
        for testCase in cases {
            let keys = Set(
                MarkupReveal.inlineSpans(
                    in: inlineNote,
                    selection: testCase.selection,
                    markedRange: testCase.markedRange,
                    currentMatch: testCase.currentMatch
                ).keys
            )
            let paragraphs = MarkupReveal.paragraphs(
                in: inlineNote,
                selection: testCase.selection,
                markedRange: testCase.markedRange,
                currentMatch: testCase.currentMatch
            )
            #expect(keys.isSubset(of: paragraphs))
        }
    }
}
