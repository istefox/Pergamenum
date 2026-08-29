import Foundation
import Testing
@testable import Pergamenum

// ADR-0028 §D6, plan `2026-08-29-wysiwyg-markdown-in-workspace`, Task 2 (R-07, R-08).
//
// `ListContinuation` is the pure Enter-continuation and ordered-run-renumbering arithmetic that
// sits beside `LineFormat` in `Sources/Core/Editor/` but answers a different question: both of
// `newline` and `renumbered` are questions about the *run* a line belongs to - where it starts,
// where it ends, what its own first ordinal was - which `LineFormat` has no notion of (ADR-0028
// §A9). These tests are RED against the stub bodies in
// `Sources/Core/Editor/ListContinuation.swift`, which return `nil` unconditionally so the target
// (and both connectors, `perg`/`pergamenum-mcp`, via the `sharedSources` glob) keep building.
// `try #require(...)` is used to unwrap the stub's `nil` cleanly instead of letting a force-unwrap
// crash the process, matching this repo's own RED convention
// (`Tests/CalendarDayMenuTests.swift`'s header note). The coder fills in the real arithmetic in a
// later task.

// MARK: - Helpers

private func caretAtEnd(_ text: String) -> NSRange {
    NSRange(location: (text as NSString).length, length: 0)
}

/// A caret positioned right after the first occurrence of `substring` in `text`.
private func caretAfter(_ substring: String, in text: String) -> NSRange {
    let haystack = text as NSString
    let found = haystack.range(of: substring)
    return NSRange(location: found.location + found.length, length: 0)
}

/// A caret positioned right before the first occurrence of `substring` in `text`.
private func caretBefore(_ substring: String, in text: String) -> NSRange {
    let haystack = text as NSString
    let found = haystack.range(of: substring)
    return NSRange(location: found.location, length: 0)
}

private func fullRange(_ text: String) -> NSRange {
    NSRange(location: 0, length: (text as NSString).length)
}

/// Asserts that pressing Return at `selection` in `text` produces `expectedText`, with the caret
/// landing right before `selectionBefore` in the result - or, when `selectionBefore` is nil, at
/// the very end of the result (the shape every continuation case in this file but one takes).
private func expectContinuation(
    in text: String, at selection: NSRange, resultsIn expectedText: String,
    selectionBefore: String? = nil
) throws {
    let result = try #require(ListContinuation.newline(in: text, at: selection))
    #expect(result.text == expectedText)
    let expectedSelection = selectionBefore.map { caretBefore($0, in: expectedText) } ?? caretAtEnd(expectedText)
    #expect(result.selection == expectedSelection)
}

// MARK: - newline (R-07)

@Test func caretAtEndOfBulletItemContinuesWithTheSameMarker() throws {
    let text = "- primo\n- secondo"
    try expectContinuation(
        in: text, at: caretAtEnd(text), resultsIn: "- primo\n- secondo\n- "
    )
}

@Test func caretAtEndOfStarBulletItemPreservesTheStarMarker() throws {
    // The marker's own character is preserved, not normalised to "-".
    let text = "* primo\n* secondo"
    try expectContinuation(
        in: text, at: caretAtEnd(text), resultsIn: "* primo\n* secondo\n* "
    )
}

@Test func caretAtEndOfPlusBulletItemPreservesThePlusMarker() throws {
    let text = "+ primo\n+ secondo"
    try expectContinuation(
        in: text, at: caretAtEnd(text), resultsIn: "+ primo\n+ secondo\n+ "
    )
}

@Test func caretAtEndOfOrderedItemContinuesAndRenumbersTheRestOfTheRunInOneEdit() throws {
    // "5. due" is not contiguous with "1. uno" - the returned text is already renumbered
    // (1./2./3.) so the continuation and the renumbering land in one string replacement, one
    // undo step (R-12's precondition).
    let text = "1. uno\n5. due"
    try expectContinuation(
        in: text, at: caretAtEnd(text), resultsIn: "1. uno\n2. due\n3. "
    )
}

@Test func caretAtEndOfCheckboxItemContinuesWithAnEmptyCheckboxNeverDone() throws {
    let text = "- [ ] fai"
    try expectContinuation(
        in: text, at: caretAtEnd(text), resultsIn: "- [ ] fai\n- [ ] "
    )
}

@Test func caretOnAnEmptyBulletItemRemovesThePrefixInsteadOfInsertingANewLine() throws {
    let text = "- "
    try expectContinuation(in: text, at: caretAtEnd(text), resultsIn: "")
}

@Test func caretOnAnEmptyOrderedItemRemovesThePrefixInsteadOfInsertingANewLine() throws {
    let text = "1. "
    try expectContinuation(in: text, at: caretAtEnd(text), resultsIn: "")
}

@Test func caretOnAnEmptyCheckboxItemRemovesThePrefixInsteadOfInsertingANewLine() throws {
    let text = "- [ ] "
    try expectContinuation(in: text, at: caretAtEnd(text), resultsIn: "")
}

@Test func indentationIsCarriedOverToTheContinuedNestedBulletLine() throws {
    let text = "  - annidato"
    try expectContinuation(
        in: text, at: caretAtEnd(text), resultsIn: "  - annidato\n  - "
    )
}

@Test func caretInTheMiddleOfAnItemSplitsItAndTheSecondHalfKeepsTheMarker() throws {
    let text = "- primo secondo"
    try expectContinuation(
        in: text, at: caretBefore("secondo", in: text),
        resultsIn: "- primo \n- secondo", selectionBefore: "secondo"
    )
}

@Test func aNonListLineReturnsNil() {
    let text = "just prose, no marker at all"
    #expect(ListContinuation.newline(in: text, at: caretAtEnd(text)) == nil)
}

@Test func anEmptyDocumentReturnsNil() {
    let text = ""
    #expect(ListContinuation.newline(in: text, at: caretAtEnd(text)) == nil)
}

@Test func aCaretInsideAFencedCodeBlockReturnsNilEvenOnAListLookingLine() {
    let text = "```\n- item\n```"
    #expect(ListContinuation.newline(in: text, at: caretAfter("- item", in: text)) == nil)
}

@Test func aNonEmptySelectionReturnsNil() {
    // Return over a selection is a replace, not a continuation.
    let text = "- primo"
    #expect(ListContinuation.newline(in: text, at: fullRange(text)) == nil)
}

// MARK: - renumbered (R-08)

@Test func aRunWithGapsRenumbersContiguouslyFromItsFirstOrdinal() {
    let text = "1. a\n3. b\n7. c"
    #expect(ListContinuation.renumbered(text) == "1. a\n2. b\n3. c")
}

@Test func aRunRenumbersFromItsOwnFirstOrdinalNeverFromOne() {
    // The pinning test (ADR-0028 §A6): a run deliberately started at 3 stays at 3.
    let text = "3. a\n9. b"
    #expect(ListContinuation.renumbered(text) == "3. a\n4. b")
}

@Test func anAlreadyContiguousRunReturnsNil() {
    // No edit, no undo step, no fight with the typist.
    let text = "1. a\n2. b\n3. c"
    #expect(ListContinuation.renumbered(text) == nil)
}

@Test func anOrderedItemFollowedByABulletItemIsTwoRunsAndBothStayUntouched() {
    let text = "1. uno\n- due"
    #expect(ListContinuation.renumbered(text) == nil)
}

@Test func aBlankLineSeparatesTwoOrderedRunsEachRestartingFromItsOwnFirstOrdinal() {
    let text = "1. a\n5. b\n\n1. x\n9. y"
    #expect(ListContinuation.renumbered(text) == "1. a\n2. b\n\n1. x\n2. y")
}

@Test func nestedItemsRenumberWithinTheirOwnLevelIndependentlyOfTheOuterRun() {
    let text = "1. a\n  1. x\n  5. y\n2. b"
    #expect(ListContinuation.renumbered(text) == "1. a\n  1. x\n  2. y\n2. b")
}

@Test func aParenDelimitedRunKeepsTheParenDelimiterItWasWrittenWith() {
    let text = "1) a\n5) b"
    #expect(ListContinuation.renumbered(text) == "1) a\n2) b")
}

@Test func aCheckboxLineEndsAnOrderedRunAndIsNeverRenumbered() {
    // If the checkbox line were (wrongly) treated as part of the run above it, "5. c" would be
    // read as the run's third item and rewritten to "3. c". It is not part of that run - "- [ ]"
    // is not an ordered item - so "5. c" is its own one-item run and nothing changes at all.
    let text = "1. a\n- [ ] b\n5. c"
    #expect(ListContinuation.renumbered(text) == nil)
}

@Test func textWithNoOrderedListAtAllReturnsNil() {
    let text = "no ordered list here\njust prose"
    #expect(ListContinuation.renumbered(text) == nil)
}
