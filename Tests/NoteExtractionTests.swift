import Foundation
import Testing
@testable import Pergamenum

// PG-387 (N4), ADR-0085 §D8, plan docs/plans/pg-387-n4-birth-of-note.md, Task 2 - R-13, R-15:
// `NoteExtraction`, the pure planning of «Estrai in una nota».

private let frontmatter = "---\ndate: 2026-10-01\ntags:\n  - type-note\n  - topic-a\n---\n"

/// Line 1 is the opening delimiter. Lines 2 to 5 are the keys, line 6 the closing delimiter,
/// line 7 the blank one, lines 8 to 10 the body.
private let source = frontmatter + "\nUno\nDue\nTre\n"

private func substring(_ text: String, _ range: NSRange) -> String {
    (text as NSString).substring(with: range)
}

private func withoutLineBreaks(_ text: String) -> String {
    text.trimmingCharacters(in: .newlines)
}

// MARK: - range(ofLines:)

@Test func aLineRangeIsOneBasedAndInclusiveOverTheWholeFile() throws {
    let text = "a\nb\nc\nd\n"

    let first = try NoteExtraction.range(ofLines: 1...1, in: text).get()
    #expect(first.location == 0)
    #expect(withoutLineBreaks(substring(text, first)) == "a")

    let middle = try NoteExtraction.range(ofLines: 2...3, in: text).get()
    #expect(middle.location == 2)
    #expect(withoutLineBreaks(substring(text, middle)) == "b\nc")
}

@Test func frontmatterLinesCountTowardTheLineNumbers() throws {
    let range = try NoteExtraction.range(ofLines: 9...9, in: source).get()

    #expect(withoutLineBreaks(substring(source, range)) == "Due")
}

@Test func aLineRangePastTheEndOrBelowOneIsOutOfBounds() {
    let text = "a\nb\nc\n"

    #expect(NoteExtraction.range(ofLines: 5...6, in: text) == .failure(.outOfBounds))
    #expect(NoteExtraction.range(ofLines: 2...9, in: text) == .failure(.outOfBounds))
    #expect(NoteExtraction.range(ofLines: 0...1, in: text) == .failure(.outOfBounds))
}

@Test func aCRLFFileCountsLinesAndOffsetsInUTF16Units() throws {
    let text = "a\r\nb\r\nc\r\n"

    let range = try NoteExtraction.range(ofLines: 2...2, in: text).get()

    // "a\r\n" is three UTF-16 units, so the second line starts at 3 whatever Character says.
    #expect(range.location == 3)
    #expect(withoutLineBreaks(substring(text, range)) == "b")
}

@Test func theLastLineWithNoTerminatorIsTheWholeTail() throws {
    let text = "a\nb"

    let range = try NoteExtraction.range(ofLines: 2...2, in: text).get()

    #expect(range == NSRange(location: 2, length: 1))
}

// MARK: - plan

@Test func aRangeInTheBodyGivesTheExtractedTextAndTheSourceWithTheLinkInItsPlace() throws {
    let range = try NoteExtraction.range(ofLines: 9...10, in: source).get()

    let plan = try NoteExtraction.plan(source: source, range: range, expectedText: nil, title: "Titolo").get()

    // The final line break of a line range stays in the source; the extracted text drops it.
    #expect(plan.extracted == "Due\nTre")
    #expect(plan.link == "[[Titolo]]")
    #expect(plan.replacedSource == frontmatter + "\nUno\n[[Titolo]]\n")
}

@Test func theLinkTakesExactlyThePlaceOfAnArbitraryRange() throws {
    let range = (source as NSString).range(of: "Due")

    let plan = try NoteExtraction.plan(source: source, range: range, expectedText: "Due", title: "Titolo").get()

    #expect(plan.extracted == "Due")
    #expect(plan.replacedSource == frontmatter + "\nUno\n[[Titolo]]\nTre\n")
}

@Test func theSourceFrontmatterIsByteIdentical() throws {
    let range = (source as NSString).range(of: "Tre")

    let plan = try NoteExtraction.plan(source: source, range: range, expectedText: nil, title: "T").get()

    #expect(plan.replacedSource.hasPrefix(frontmatter))
}

@Test func aNoteWithNoFrontmatterCanBeExtractedFromItsFirstLine() throws {
    let text = "Uno\nDue\n"
    let range = (text as NSString).range(of: "Uno")

    let plan = try NoteExtraction.plan(source: text, range: range, expectedText: nil, title: "T").get()

    #expect(plan.replacedSource == "[[T]]\nDue\n")
}

@Test func aRangeInsideTheFrontmatterIsRefused() throws {
    let range = (source as NSString).range(of: "topic-a")

    #expect(NoteExtraction.plan(source: source, range: range, expectedText: nil, title: "T")
        == .failure(.touchesFrontmatter))
}

@Test func aRangeThatStartsInTheFrontmatterAndEndsInTheBodyIsRefused() {
    let start = (source as NSString).range(of: "tags:").location
    let end = (source as NSString).range(of: "Due").upperBound
    let range = NSRange(location: start, length: end - start)

    #expect(NoteExtraction.plan(source: source, range: range, expectedText: nil, title: "T")
        == .failure(.touchesFrontmatter))
}

@Test func theDelimiterLinesAreFrontmatterToo() throws {
    // Lines 1 to 3: the opening delimiter, `date:` and `tags:`.
    let range = try NoteExtraction.range(ofLines: 1...3, in: source).get()

    #expect(NoteExtraction.plan(source: source, range: range, expectedText: nil, title: "T")
        == .failure(.touchesFrontmatter))
}

@Test func aTextThatIsNotWhatWasSelectedIsRefused() {
    let range = (source as NSString).range(of: "Due")

    #expect(NoteExtraction.plan(source: source, range: range, expectedText: "Altro", title: "T")
        == .failure(.textChanged))
}

@Test func anEmptyRangeIsRefused() {
    let location = (source as NSString).range(of: "Due").location

    #expect(NoteExtraction.plan(source: source, range: NSRange(location: location, length: 0), expectedText: nil, title: "T")
        == .failure(.empty))
}

@Test func aRangePastTheEndOfTheSourceIsOutOfBounds() {
    let range = NSRange(location: source.utf16.count - 2, length: 10)

    #expect(NoteExtraction.plan(source: source, range: range, expectedText: nil, title: "T")
        == .failure(.outOfBounds))
}

@Test func everyExtractionRefusalHasADistinctNonEmptySentence() {
    let refusals: [NoteExtraction.Refusal] = [.empty, .outOfBounds, .textChanged, .touchesFrontmatter]
    let sentences = refusals.map(\.sentence)

    #expect(sentences.allSatisfy { !$0.isEmpty })
    #expect(Set(sentences).count == sentences.count)
}
