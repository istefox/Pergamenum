import Foundation
import Testing
@testable import Pergamenum

// ADR-0087 §D2, plan docs/plans/note-workflow-n5.md, Task 1 (R-36, R-37, R-39, R-40).
//
// The shared grammar of N5's constructs, asserted on the value forms every reading surface reads:
// the `==` highlight, the nesting level of a quote line, a closed fence's chrome, and the caption a
// transclusion's source line becomes.

private func quote(_ level: Int, _ text: String) -> MarkdownBlock.QuoteLine {
    MarkdownBlock.QuoteLine(level: level, text: text)
}

// MARK: - Highlights (R-36)

@Suite struct HighlightParsing {
    @Test func doubleEqualsHighlightsTheRunBetweenThem() { // R-36
        let spans = MarkdownInlineParser.spans(in: "a ==b== c")
        #expect(spans == [
            MarkdownSpan(text: "a "),
            MarkdownSpan(text: "b", styles: [.highlight]),
            MarkdownSpan(text: " c"),
        ])
    }

    /// The SPEC's edge case: code spans are matched first, so `==` inside one is code.
    @Test func doubleEqualsInsideACodeSpanIsNotAHighlight() { // R-36
        #expect(MarkdownInlineParser.spans(in: "`a==b==`") == [MarkdownSpan(text: "a==b==", styles: [.code])])
    }

    @Test(arguments: ["a == b == c", "==a", "== a==", "====", "=====", "======"])
    func aMarkerThatCannotOpenOrCloseOpensNothing(_ text: String) { // R-36
        #expect(MarkdownInlineParser.spans(in: text) == [MarkdownSpan(text: text)], "\(text.debugDescription)")
    }

    /// A line of `=` is a setext underline, never a highlight: `====` was an empty one and `======` a pill
    /// of `==` with four characters concealed.
    @Test func aRunOfEqualsAfterTheOpeningPairIsNoHighlight() { // R-36
        for line in ["====", "=====", "======"] {
            #expect(MarkdownInlineParser.tokens(in: Substring(line)).isEmpty, "\(line)")
        }
    }

    @Test func strongNestsInsideAHighlight() { // R-36
        #expect(MarkdownInlineParser.spans(in: "==**x**==") == [
            MarkdownSpan(text: "x", styles: [.highlight, .strong]),
        ])
    }
}

// MARK: - Quote levels (R-39)

@Suite struct QuoteLevels {
    /// `>> b` is level 2 whichever way the spaces fall (ADR-0087 §D2).
    @Test func aDoubledCaretIsLevelTwo() { // R-39
        #expect(MarkdownBlockParser.blocks(in: "> a\n>> b") == [.quote([quote(1, "a"), quote(2, "b")])])
    }

    /// ADR-0087 §D2 spells the rule as CommonMark's: each `>` optionally followed by spaces, so
    /// `> > c` is level 2 as well. Note for Task 2: the line-token layer reads `> > c` as a level-1
    /// quote whose text is `> c` (`MarkdownLineTokenTests`, styler corpus S13), so this level cannot
    /// simply be the token's. Plan Task 1 pins `1, 2, 2` for this exact input.
    @Test func aSpacedNestedCaretIsLevelTwoToo() { // R-39
        #expect(MarkdownBlockParser.blocks(in: "> a\n>> b\n> > c") == [
            .quote([quote(1, "a"), quote(2, "b"), quote(2, "c")]),
        ])
    }

    /// A level-1 quote's texts equal today's, so the export of a single-level quote keeps its bytes
    /// (E06's input).
    @Test func aLevelOneQuoteKeepsTodaysTexts() { // R-39
        #expect(MarkdownBlockParser.blocks(in: ">citato\n> ancora") == [
            .quote([quote(1, "citato"), quote(1, "ancora")]),
        ])
    }
}

// MARK: - Fence chrome (R-37)

@Suite struct FenceChromeParsing {
    private static let note = "intro\n```swift\nlet a = 1\nlet b = 2\n```\nfine"

    /// UTF-16 offsets into `note`: the opening line is 6..<14, the body 15..<35, the closing line
    /// 35..<38 and "fine" starts at 39.
    private static func slice(_ range: Range<String.Index>, of text: String) -> String {
        String(text[range])
    }

    @Test func aClosedFenceYieldsOneBlockWithItsLinesBodyAndLanguage() throws { // R-37
        let blocks = FenceChrome.blocks(in: Self.note)
        let chrome = try #require(blocks.first, "no chrome for a closed fence")
        #expect(blocks.count == 1)
        #expect(Self.slice(chrome.opening, of: Self.note) == "```swift")
        #expect(Self.slice(chrome.closing, of: Self.note) == "```")
        // The body is the code. Whether it carries the line break before the closing fence is not
        // stated by the SPEC, so the assertion ignores it (reported as a gap).
        #expect(Self.slice(chrome.body, of: Self.note).trimmingCharacters(in: .newlines) == "let a = 1\nlet b = 2")
        #expect(chrome.language == "swift")
        #expect(chrome.lineCount == 2)
    }

    @Test func anEmptyFenceCountsZeroLines() throws { // R-37
        let text = "```\n```"
        let chrome = try #require(FenceChrome.blocks(in: text).first, "no chrome for an empty closed fence")
        #expect(chrome.lineCount == 0)
        #expect(chrome.language == nil)
        #expect(Self.slice(chrome.body, of: text).isEmpty)
    }

    @Test func anUnclosedFenceYieldsNone() { // R-37
        #expect(FenceChrome.blocks(in: "```swift\nlet a = 1").isEmpty)
    }

    @Test func aViewFenceYieldsNone() { // R-37
        #expect(FenceChrome.blocks(in: "```pergamenum-view\nrender: list\n```").isEmpty)
    }

    @Test(arguments: [6, 10, 13, 15, 20, 34, 35, 36, 37])
    func blockContainingFindsTheBlockFromAnyOffsetInItsThreeParts(_ offset: Int) throws { // R-37
        let found = FenceChrome.block(containing: offset, in: Self.note)
        #expect(found != nil, "offset \(offset) is inside the fence")
        #expect(found == FenceChrome.blocks(in: Self.note).first)
    }

    @Test(arguments: [0, 3, 40, 42])
    func blockContainingFindsNothingOutsideTheFence(_ offset: Int) { // R-37
        #expect(FenceChrome.block(containing: offset, in: Self.note) == nil, "offset \(offset) is outside")
    }

    @Test(arguments: [(1, "1 riga"), (2, "2 righe"), (12, "12 righe"), (0, "0 righe")])
    func theLineCountLabelIsSingularOnlyForOne(_ count: Int, _ label: String) { // R-37
        let empty = "".startIndex..<"".startIndex
        let chrome = FenceChrome(opening: empty, closing: empty, body: empty, language: nil, lineCount: count)
        #expect(chrome.lineCountLabel == label)
    }
}

// MARK: - The transclusion caption (R-40, R-43)

@Suite struct TransclusionCaptionText {
    @Test func aCaptionNamesTheNoteAndTheSection() { // R-40
        #expect(TransclusionCaption.text(note: "Nota", section: "Sezione") == "da «Nota» › Sezione")
    }

    @Test func aCaptionWithNoSectionNamesTheNoteOnly() { // R-40
        #expect(TransclusionCaption.text(note: "Nota", section: nil) == "da «Nota»")
    }

    // The editor names the note by its resolved title; the export reads the name off the reference (R-43).
    @Test(arguments: [
        ("Altra nota", "Altra nota"), ("Cartella/Altra nota", "Altra nota"), ("A/B/Altra nota", "Altra nota"),
        ("Cartella/Altra nota.md", "Altra nota"), ("Altra nota.MD", "Altra nota"), (".md", ".md"),
    ])
    func aReferenceIsNamedByItsLastPathComponent(reference: String, name: String) { // R-43
        #expect(TransclusionCaption.name(ofReference: reference) == name)
    }
}
