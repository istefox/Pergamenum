import Foundation
import Testing
@testable import Pergamenum

// `EmbedNavigation` (ADR-0018 slice 3, Step 4): pure range arithmetic for D5's caret
// and delete rules over a drawn embed's run - no `NSTextView`, no delegate, matching
// `MarkupRevealTests`'s own split.
//
// One fixture throughout: "prima\n![[foto.png]]\ndopo\n". "prima\n" is six characters, so
// the run - "![[foto.png]]", thirteen characters, never the trailing newline - starts at
// offset 6 and its far edge is offset 19. The whole text is twenty-five characters.

private let run = NSRange(location: 6, length: 13)
private let textLength = 25

// MARK: - Moving

@Test func aCaretAtTheRunsLeftEdgeSkipsItInOneStepMovingRight() {
    let selection = NSRange(location: run.location, length: 0)
    #expect(
        EmbedNavigation.moved(selection: selection, direction: .right, extending: false, drawnRuns: [run])
            == NSRange(location: NSMaxRange(run), length: 0)
    )
}

@Test func aCaretAtTheRunsRightEdgeSkipsItInOneStepMovingLeft() {
    let selection = NSRange(location: NSMaxRange(run), length: 0)
    #expect(
        EmbedNavigation.moved(selection: selection, direction: .left, extending: false, drawnRuns: [run])
            == NSRange(location: run.location, length: 0)
    )
}

@Test func extendingRightFromABareCaretSelectsTheWholeRun() {
    let selection = NSRange(location: run.location, length: 0)
    #expect(
        EmbedNavigation.moved(selection: selection, direction: .right, extending: true, drawnRuns: [run]) == run
    )
}

@Test func extendingLeftFromABareCaretSelectsTheWholeRun() {
    let selection = NSRange(location: NSMaxRange(run), length: 0)
    #expect(
        EmbedNavigation.moved(selection: selection, direction: .left, extending: true, drawnRuns: [run]) == run
    )
}

@Test func extendingRightPastTheRunKeepsTheAnchorAndGrowsToTheFarEdge() {
    // A selection that already starts two characters before the run, extended further
    // right: the anchor (`selection.location`) stays, the end jumps past the whole run.
    let selection = NSRange(location: run.location - 2, length: 2)
    #expect(
        EmbedNavigation.moved(selection: selection, direction: .right, extending: true, drawnRuns: [run])
            == NSRange(location: selection.location, length: NSMaxRange(run) - selection.location)
    )
}

@Test func extendingLeftPastTheRunKeepsTheAnchorAndGrowsToTheFarEdge() {
    let selection = NSRange(location: NSMaxRange(run), length: 2)
    #expect(
        EmbedNavigation.moved(selection: selection, direction: .left, extending: true, drawnRuns: [run])
            == NSRange(location: run.location, length: NSMaxRange(selection) - run.location)
    )
}

@Test func aRunNotInTheDrawnSetIsNeverCrossed() {
    // `hidesMarkup` off, or a rendition not yet ready: the caller hands over an empty
    // set, and movement must fall back to the ordinary, character-by-character answer
    // `super` gives.
    let selection = NSRange(location: run.location, length: 0)
    #expect(EmbedNavigation.moved(selection: selection, direction: .right, extending: false, drawnRuns: []) == nil)
}

@Test func aCaretNotAtEitherEdgeIsOrdinary() {
    let selection = NSRange(location: run.location + 3, length: 0)
    #expect(EmbedNavigation.moved(selection: selection, direction: .right, extending: false, drawnRuns: [run]) == nil)
    #expect(EmbedNavigation.moved(selection: selection, direction: .left, extending: false, drawnRuns: [run]) == nil)
}

@Test func aPlainMoveOverAnExistingSelectionIsNeverIntercepted() {
    // AppKit's own rule is to collapse to an edge, not to step past it - not this
    // function's concern, so it defers unconditionally.
    let selection = NSRange(location: run.location, length: 4)
    #expect(EmbedNavigation.moved(selection: selection, direction: .right, extending: false, drawnRuns: [run]) == nil)
}

// MARK: - Deleting

@Test func backspaceAtTheRunsRightEdgeRemovesTheWholeRunAndItsNewline() {
    let selection = NSRange(location: NSMaxRange(run), length: 0)
    #expect(
        EmbedNavigation.deletionRange(
            selection: selection, direction: .backward, drawnRuns: [run], textLength: textLength
        ) == NSRange(location: run.location, length: run.length + 1)
    )
}

@Test func deleteAtTheRunsLeftEdgeRemovesTheWholeRunAndItsNewline() {
    let selection = NSRange(location: run.location, length: 0)
    #expect(
        EmbedNavigation.deletionRange(
            selection: selection, direction: .forward, drawnRuns: [run], textLength: textLength
        ) == NSRange(location: run.location, length: run.length + 1)
    )
}

@Test func backspaceAnywhereElseIsOrdinary() {
    let selection = NSRange(location: run.location + 3, length: 0)
    #expect(
        EmbedNavigation.deletionRange(
            selection: selection, direction: .backward, drawnRuns: [run], textLength: textLength
        ) == nil
    )
}

@Test func deleteAtTheLeftEdgeIsOrdinaryWhenTheRunIsNotInTheDrawnSet() {
    #expect(
        EmbedNavigation.deletionRange(
            selection: NSRange(location: run.location, length: 0),
            direction: .forward, drawnRuns: [], textLength: textLength
        ) == nil
    )
}

@Test func deletingAnExistingSelectionIsNeverIntercepted() {
    let selection = NSRange(location: NSMaxRange(run), length: 3)
    #expect(
        EmbedNavigation.deletionRange(
            selection: selection, direction: .backward, drawnRuns: [run], textLength: textLength
        ) == nil
    )
}

@Test func aRunAtTheVeryEndOfTheDocumentWithNoTrailingNewlineIsClampedRatherThanCrashing() {
    // The one embed that could be the note's very last line, with nothing after it to
    // eat: `textLength` is the run's own far edge, so the "+1" for the newline must be
    // clamped rather than reach past the end of the string.
    let lastRun = NSRange(location: 6, length: 13)
    let selection = NSRange(location: NSMaxRange(lastRun), length: 0)
    #expect(
        EmbedNavigation.deletionRange(
            selection: selection, direction: .backward, drawnRuns: [lastRun], textLength: NSMaxRange(lastRun)
        ) == NSRange(location: lastRun.location, length: lastRun.length)
    )
}
