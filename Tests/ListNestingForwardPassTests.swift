import Foundation
import Testing
@testable import Pergamenum

// PG-139 (issue #239), Task 1: `ListNesting.levels(in:)` folds the same stack
// `level(in:lineStart:indent:)` rebuilds per line, in one forward pass over the whole note.
// This is a differential test, not a new spec: it is what keeps the two implementations
// from silently drifting apart as either one is touched later, by asserting they agree on
// the same line of the same text, at the same `indent` the production call site
// (`MarkdownStyler`'s `listMarkerSpan`) already computes for it.

/// The true start of the line containing the first occurrence of `marker` - indentation
/// included, walked back to the preceding `"\n"` (or `text.startIndex`) rather than to
/// `marker`'s own position. `ListNestingTests.swift`'s own helper returns `range.lowerBound`
/// directly, which is safe there only because `level(in:lineStart:indent:)`'s backward walk
/// tolerates a `lineStart` that skips a purely-whitespace prefix (the skipped indentation
/// reconstructs as a harmless "indented non-list line"); `levels(in:)`'s dictionary is keyed
/// by the *real* line start, so a lookup needs the exact same index this returns.
private func lineStart(of marker: String, in text: String) -> String.Index {
    guard let range = text.range(of: marker) else {
        fatalError("marker not found: \(marker)")
    }
    let beforeMarker = text[text.startIndex..<range.lowerBound]
    return beforeMarker.lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
}

/// Asserts `levels(in:)[lineStart] == level(in:lineStart:indent:)` at `lineStart`, naming
/// `label` on failure. `forward` being `nil` while `backward` is a real level (or the
/// reverse) fails this exactly as a mismatched value would - a dictionary miss here is
/// exactly what `listMarkerSpan`'s own coalesced fallback exists to guard against.
private func expectAgreement(
    _ text: String,
    at target: String.Index,
    indent: Int,
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let forward = ListNesting.levels(in: text)[target]
    let backward = ListNesting.level(in: text, lineStart: target, indent: indent)
    #expect(
        forward == backward,
        "\(label): forward=\(String(describing: forward)) backward=\(backward)",
        sourceLocation: sourceLocation
    )
}

@Test func tabsMixedWithSpacesAgree() {
    // A tab (4 columns) then two literal spaces (2 columns) = indent 6, nesting under a
    // parent whose own content column is 2 ("- ").
    let text = "- padre\n\t  - figlio"
    let target = lineStart(of: "- figlio", in: text)
    expectAgreement(text, at: target, indent: 6, "tab mixed with spaces")
}

@Test func aCheckboxLineIsCountedAsAnAncestorInBothImplementations() {
    // The shared `markerWidth` grammar does not special-case a checkbox - only
    // `MarkdownStyler`'s own `listMarkerSpan`/`taskMarker` refuse it a *styled* marker span
    // (ADR-0028 §D2). A line nested under one must still see it as an open ancestor, in
    // both the forward fold and the backward walk.
    let text = "- [ ] fai\n  - sotto"
    let target = lineStart(of: "- sotto", in: text)
    expectAgreement(text, at: target, indent: 2, "checkbox line as ancestor")
}

@Test func aBlankLineInsideAListChangesNothingInEitherImplementation() {
    let text = "- a\n\n  - b"
    let target = lineStart(of: "- b", in: text)
    expectAgreement(text, at: target, indent: 2, "blank line inside a list")
}

@Test func aColumnZeroProseLineClosesEveryOpenListInBothImplementations() {
    let text = "- a\n\nparagrafo\n\n- b"
    let target = lineStart(of: "- b", in: text)
    expectAgreement(text, at: target, indent: 0, "column-0 prose splitting two runs")
}

@Test func aYAMLListInsideFrontmatterIsSeenByBothBecauseNeitherFiltersIt() {
    // `levels(in:)` scans from `text.startIndex`, frontmatter included and no fence filter
    // - exactly what `level(in:lineStart:indent:)`'s own backward walk already sees from any
    // `lineStart` below it. Whatever the two agree the level *is* here is beside the point;
    // that they agree at all is what this pins.
    let text = "---\ntags:\n  - a\n  - b\n---\n\n- corpo"
    expectAgreement(text, at: lineStart(of: "- a", in: text), indent: 2, "frontmatter YAML list, first item")
    expectAgreement(text, at: lineStart(of: "- b", in: text), indent: 2, "frontmatter YAML list, second item")
    expectAgreement(text, at: lineStart(of: "- corpo", in: text), indent: 0, "body list after frontmatter")
}

@Test func aListLookingLineInsideAFenceIsCountedNotFilteredByEitherImplementation() {
    // `ListNesting` has no notion of a fence at all - that filtering happens one layer up,
    // in `MarkdownStyler.spans(in:)`'s own per-line loop (`aListMarkerInsideAFenceHasNoListMarkerSpan`,
    // `MarkdownStylerTests.swift`). Both implementations here still walk straight through it.
    let text = "```\n- inside fence\n```\n\n- outside"
    expectAgreement(text, at: lineStart(of: "- inside fence", in: text), indent: 0, "list-looking line inside a fence")
    expectAgreement(text, at: lineStart(of: "- outside", in: text), indent: 0, "list line after the fence")
}

@Test func mixedOrderedAndBulletSiblingsAgree() {
    let text = "- a\n1. b\n* c"
    let target = lineStart(of: "* c", in: text)
    expectAgreement(text, at: target, indent: 0, "mixed ordered/bullet siblings")
}

@Test func multiDigitOrdinalContentColumnAgrees() {
    // "100. " is a 5-column marker (3 digits, then ". ") - a child indented exactly 5
    // reaches that content column and nests, the same tie-break
    // `spansTieBreakAttachesToTheDeepestListThatStillFits` pins in `MarkdownStylerTests`.
    let text = "100. padre\n     - figlio"
    let target = lineStart(of: "- figlio", in: text)
    expectAgreement(text, at: target, indent: 5, "multi-digit ordinal content column")
}

@Test func eightLevelsDeepBothCapAtSix() {
    let eightDeep = (1...8)
        .map { String(repeating: "  ", count: $0 - 1) + "- n\($0)" }
        .joined(separator: "\n")
    let target = lineStart(of: "- n8", in: eightDeep)
    expectAgreement(eightDeep, at: target, indent: 14, "eight levels deep, capped at six")
}

@Test func crlfLineEndingsAgree() {
    // Swift's `Character` treats "\r\n" as one grapheme cluster, so `firstIndex(of: "\n")`
    // - what both implementations split lines on - finds nothing inside it: a CRLF note
    // reads as a single "line" to both, and that degenerate agreement is exactly what this
    // pins, not CRLF support (neither implementation has any of its own).
    let text = "- a\r\n- b"
    expectAgreement(text, at: text.startIndex, indent: 0, "CRLF-joined text reads as one line")
}

@Test func aListLineWithNoTrailingNewlineIsStillSeenByBoth() {
    let text = "- a\n  - b"
    let target = lineStart(of: "- b", in: text)
    #expect(text.hasSuffix("- b"), "fixture sanity: the corpus must not end in a newline")
    expectAgreement(text, at: target, indent: 2, "no trailing newline")
}

@Test func emptyStringHasNoListLinesInTheForwardPass() {
    #expect(ListNesting.levels(in: "").isEmpty)
}

@Test func lineStartEqualToTheDocumentsOwnStartIndexAgrees() {
    let text = "- primo\n  - secondo"
    #expect(lineStart(of: "- primo", in: text) == text.startIndex)
    expectAgreement(text, at: text.startIndex, indent: 0, "lineStart == startIndex")
}
