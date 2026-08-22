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

@Test func aCaretAtTheVeryEndOfTheDocumentStillBelongsToTheLastParagraph() {
    // No trailing newline: the whole string is one paragraph, and a caret at `length`
    // still lands inside it rather than in a paragraph past the end of the text.
    let text = "corpo"
    let caret = NSRange(location: (text as NSString).length, length: 0)
    #expect(
        MarkupReveal.paragraphs(in: text, selection: caret, markedRange: noComposition, currentMatch: nil) == [0]
    )
}
