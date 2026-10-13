import Foundation
import Testing
@testable import Pergamenum

// (coverage) ADR-0091 §D3 and ADR-0045, plan docs/plans/per-paragraph-restyle.md.
//
// `WikilinkParser.codeRanges(in:)` was split into the fenced half (`fencedCodeRanges(in:)`), the
// per-line inline half (`inlineCodeRanges(inLine:)`) and the fence predicate (`marksCodeFence`), so
// `StructureMap` and `MarkdownLineSignature` read the same rule instead of writing their own. The
// whole function keeps its tests elsewhere; these pin the three pieces the diff exposed, and only what
// their doc comments and the old function's documented contract already say: three backticks or three
// tildes mark a fence, only the opening fence carries an info string, an unterminated fence runs to the
// end, an inline span pairs backticks within one line.

private func substrings(_ ranges: [Range<String.Index>], in text: String) -> [String] {
    ranges.map { String(text[$0]) }
}

@Suite struct WikilinkCodeRangesSplit {
    // MARK: marksCodeFence

    @Test(arguments: ["```", "```swift", "~~~", "~~~~", "````"])
    func threeBackticksOrThreeTildesMarkAFence(_ line: String) {
        #expect(WikilinkParser.marksCodeFence(line))
    }

    @Test(arguments: ["", "``", "~~", "text ```", "`~~", "- ```", "> ```"])
    func anythingElseIsNotAFenceMark(_ line: String) {
        #expect(!WikilinkParser.marksCodeFence(line))
    }

    // MARK: fencedCodeRanges

    @Test func aFenceRunsFromItsOpeningLineToTheEndOfItsClosingLine() {
        let text = "prima\n```swift\nlet a = 1\n```\ndopo\n"
        #expect(substrings(WikilinkParser.fencedCodeRanges(in: text[...]), in: text) == ["```swift\nlet a = 1\n```"])
    }

    @Test func aTildeFenceIsAFenceToo() {
        let text = "~~~\ncodice\n~~~\n"
        #expect(substrings(WikilinkParser.fencedCodeRanges(in: text[...]), in: text) == ["~~~\ncodice\n~~~"])
    }

    @Test func onlyTheOpeningFenceMayCarryAnInfoString() {
        // "``` e poi altro" does not close the block: a closing fence is the delimiter alone.
        let text = "```\nuno\n``` e poi altro\ndue\n```\nfuori\n"
        #expect(substrings(WikilinkParser.fencedCodeRanges(in: text[...]), in: text)
            == ["```\nuno\n``` e poi altro\ndue\n```"])
    }

    @Test func anUnterminatedFenceRunsToTheEndOfTheText() {
        let text = "prima\n```\ncodice senza fine\nancora"
        #expect(substrings(WikilinkParser.fencedCodeRanges(in: text[...]), in: text) == ["```\ncodice senza fine\nancora"])
    }

    @Test func aTextWithoutAFenceHasNoFencedRange() {
        let text = "solo prosa con `codice` in linea\n"
        #expect(WikilinkParser.fencedCodeRanges(in: text[...]).isEmpty)
        #expect(WikilinkParser.fencedCodeRanges(in: ""[...]).isEmpty)
    }

    @Test func aCRLFNoteIsWalkedLineByLine() {
        let text = "a\r\n```\r\ncodice\r\n```\r\nb\r\n"
        #expect(substrings(WikilinkParser.fencedCodeRanges(in: text[...]), in: text) == ["```\r\ncodice\r\n```"])
    }

    // MARK: inlineCodeRanges

    @Test func backticksPairWithinTheLineInOrder() {
        let line = "uno `a` due `b` tre"
        #expect(substrings(WikilinkParser.inlineCodeRanges(inLine: line[...]), in: line) == ["`a`", "`b`"])
    }

    @Test func anOddBacktickPairsWithNothing() {
        let line = "uno `a` due ` tre"
        #expect(substrings(WikilinkParser.inlineCodeRanges(inLine: line[...]), in: line) == ["`a`"])
        #expect(WikilinkParser.inlineCodeRanges(inLine: "solo ` uno"[...]).isEmpty)
    }

    @Test func aLineWithoutBackticksHasNoInlineRange() {
        #expect(WikilinkParser.inlineCodeRanges(inLine: "nessun codice qui"[...]).isEmpty)
        #expect(WikilinkParser.inlineCodeRanges(inLine: ""[...]).isEmpty)
    }

    @Test func theRangesIndexTheBaseStringWhenTheLineIsASlice() {
        let text = "prima riga\nuna `slice` di seconda riga\nterza"
        let start = text.index(text.startIndex, offsetBy: 11)
        let end = text[start...].firstIndex(of: "\n") ?? text.endIndex
        let ranges = WikilinkParser.inlineCodeRanges(inLine: text[start..<end])
        #expect(substrings(ranges, in: text) == ["`slice`"])
        #expect(ranges.first?.lowerBound == text.range(of: "`slice`")?.lowerBound)
    }

    // MARK: codeRanges is the two halves

    @Test func codeRangesIsTheFencedRangesAndTheInlineSpansOutsideThem() {
        let text = "a `x` b\n```\n`y` dentro\n```\nc `z` d\n"
        let found = Set(substrings(WikilinkParser.codeRanges(in: text), in: text))
        // The backticks inside the fence are the fence's own, not a span of theirs.
        #expect(found == ["`x`", "```\n`y` dentro\n```", "`z`"])
    }
}
