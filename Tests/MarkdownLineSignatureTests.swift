import Foundation
import Testing
@testable import Pergamenum

// ADR-0091 §D1 and §D3, plan docs/plans/per-paragraph-restyle.md, Task 1 (R-03, R-04).
//
// The grammar facts the widening rests on, asked of the shared sources: a line's structural signature
// against each recogniser it restates, `lineTokens` with a list seed against today's tokens, and a
// fragment's transclusions against the slice of the whole note's. Red until Task 2 gives the
// placeholders their bodies.

private func signature(_ line: String) -> MarkdownLineSignature {
    MarkdownLineSignature.of(Substring(line))
}

// MARK: - fenceMark: CodeFence.marks plus the `~~~` of WikilinkParser.codeRanges

// (R-04) The fence mark is read on the trimmed line, with backticks or tildes.
@Test(arguments: ["```", "```swift", "   ```", "\t```pergamenum-view", "~~~", "  ~~~ bash", "``` trailing text"])
func aFenceLineCarriesTheFenceMark(_ line: String) {
    #expect(signature(line).fenceMark, "\(line.debugDescription)")
}

// (R-04) Two backticks, a mark that is not first and prose are no fence line.
@Test(arguments: ["``", "~~", "text ```", "a ~~~", "", "- item", "| a | b |"])
func aNonFenceLineCarriesNoFenceMark(_ line: String) {
    #expect(!signature(line).fenceMark, "\(line.debugDescription)")
}

// MARK: - tableCapable: a `|`, or GFMTable.alignments reading a delimiter row

// (R-04) A pipe makes a line able to be part of a table, whatever else it holds.
@Test(arguments: ["| a | b |", "a | b", "|", "x | y | z", "  | indented | row |", "| - | - |", "| :-: | --: |"])
func aLineWithAPipeIsTableCapable(_ line: String) {
    #expect(signature(line).tableCapable, "\(line.debugDescription)")
}

// (R-04) A pipe-less delimiter row is a one-column delimiter (`GFMTable.alignments`), so it can
// follow a `| a |` header.
@Test(arguments: ["---", "--", ":-:", ":--", "--:"])
func aPipelessDelimiterRowIsTableCapable(_ line: String) {
    #expect(signature(line).tableCapable, "\(line.debugDescription)")
}

// (R-04) Prose, a list line and a blank line cannot be part of a table.
@Test(arguments: ["plain text", "- item", "1. item", "> quote", "# Heading", "", "   "])
func proseIsNotTableCapable(_ line: String) {
    #expect(!signature(line).tableCapable, "\(line.debugDescription)")
}

// MARK: - listRole: ListNesting.role, the forward walk's own column arithmetic

// (R-04) A list line's role carries its indentation and its content column, a tab counting as 4.
@Test func aListLineIsAnItemWithItsColumns() {
    #expect(signature("- a").listRole == .item(indent: 0, contentColumn: 2))
    #expect(signature("* a").listRole == .item(indent: 0, contentColumn: 2))
    #expect(signature("+ a").listRole == .item(indent: 0, contentColumn: 2))
    #expect(signature("  - b").listRole == .item(indent: 2, contentColumn: 4))
    #expect(signature("\t- c").listRole == .item(indent: 4, contentColumn: 6))
    #expect(signature("\t  - d").listRole == .item(indent: 6, contentColumn: 8))
    #expect(signature("12. x").listRole == .item(indent: 0, contentColumn: 4))
    #expect(signature("1) x").listRole == .item(indent: 0, contentColumn: 3))
    // A checkbox line is counted as an ancestor, exactly as the forward walk counts it today.
    #expect(signature("- [ ] fai").listRole == .item(indent: 0, contentColumn: 2))
}

// (R-04) An empty line is blank; an indented line that is no list line continues the open item; a
// non-blank line at column 0 that is no list line resets the stack.
@Test func theThreeOtherRolesOfAListWalk() {
    #expect(signature("").listRole == .blank)
    #expect(signature("    text").listRole == .continuation)
    #expect(signature("  more").listRole == .continuation)
    #expect(signature("text").listRole == .reset)
    #expect(signature("-x").listRole == .reset)
    #expect(signature("1.x").listRole == .reset)
    #expect(signature("# Heading").listRole == .reset)
}

// MARK: - brackets: the tokens of WikilinkParser.links, in order

// (R-04) A link is an opener then a closer.
@Test func aWikilinkIsOneOpenerAndOneCloser() {
    #expect(signature("a [[b]] c").brackets == [.open(embed: false, inCode: false), .close])
}

// (R-04) `![[` is an embed opener.
@Test func anEmbedOpenerIsMarkedAsAnEmbed() {
    #expect(signature("![[img.png]]").brackets == [.open(embed: true, inCode: false), .close])
}

// (R-04) The tokens come in source order, whatever they are.
@Test func bracketsKeepSourceOrder() {
    #expect(signature("]] then [[").brackets == [.close, .open(embed: false, inCode: false)])
    #expect(signature("[[a [[b]]").brackets == [
        .open(embed: false, inCode: false), .open(embed: false, inCode: false), .close,
    ])
    #expect(signature("[[a]] and ![[b]]").brackets == [
        .open(embed: false, inCode: false), .close, .open(embed: true, inCode: false), .close,
    ])
}

// (R-04) An opener an inline backtick span on the same line covers is marked as in code, which the
// pending-opener rule ignores, as `WikilinkParser.codeRanges` does.
@Test func anOpenerInsideAnInlineCodeSpanIsInCode() {
    #expect(signature("`[[x]]` y").brackets == [.open(embed: false, inCode: true), .close])
    #expect(signature("[[x]] and `[[y]]`").brackets == [
        .open(embed: false, inCode: false), .close, .open(embed: false, inCode: true), .close,
    ])
}

// (R-04) A single bracket is no token, and a line with none has none.
@Test func singleBracketsAreNoTokens() {
    #expect(signature("a [ b ] c").brackets.isEmpty)
    #expect(signature("[x](url)").brackets.isEmpty)
    #expect(signature("plain").brackets.isEmpty)
}

// MARK: - isQuote: the token layer's quote predicate (ADR-0087's amendment of ADR-0091 §D3)

// (R-38, R-39) A line whose first non-blank character opens a quote marker is a quote line, at any
// level, with or without the space, and indented by spaces or a tab. A callout header is one too.
@Test(arguments: ["> a", ">a", ">", "> ", ">> b", "> > c", "  > indented", "\t> tab", "> [!note] Titolo", "> [!avviso]- T"])
func aQuoteLineCarriesIsQuote(_ line: String) {
    #expect(signature(line).isQuote, "\(line.debugDescription)")
}

// (R-38, R-39) Prose, a list line, a heading, a blank line, a `>` that is not first and a `>date`
// scheduling token (the token layer's own exclusion) are no quote line.
@Test(arguments: ["plain", "- item", "1. item", "# Heading", "", "   ", "a > b", "- > not first", ">2026-10-14", ">2026-10-14 10:30"])
func aNonQuoteLineCarriesNoIsQuote(_ line: String) {
    #expect(!signature(line).isQuote, "\(line.debugDescription)")
}

// MARK: - lineTokens(listSeed:)

private let listAndTaskTexts: [String] = [
    "",
    "plain\n\nprose",
    "- a\n  - b\n    - c\n  - d\ntext\n- e",
    "1. one\n2. two\n   - nested\n3. three",
    "---\ntitle: x\n---\n- a\n  - [ ] t",
    "```\n- not a list\n```\n- real",
    "| a | b |\n| - | - |\n| 1 | 2 |\n- after",
    "- a\r\n  - b\r\n  - c",
]

private func listLevels(_ tokens: [MarkdownLineToken]) -> [Int] {
    tokens.compactMap { token in
        switch token.kind {
        case .listItem(_, _, _, let level): level
        case .task(_, _, let level): level
        default: nil
        }
    }
}

// (R-03) An empty seed is today's call: every existing caller passes nothing and gets today's tokens.
@Test(arguments: listAndTaskTexts)
func aListSeedOfNothingChangesNothing(_ text: String) {
    let today = MarkdownBlockParser.lineTokens(in: text, readsFrontmatter: true, endsLine: LineBreak.isTerminator)
    let seeded = MarkdownBlockParser.lineTokens(
        in: text, readsFrontmatter: true, endsLine: LineBreak.isTerminator, listSeed: []
    )
    #expect(seeded == today)
    #expect(MarkdownBlockParser.lineTokens(in: text, listSeed: []) == MarkdownBlockParser.lineTokens(in: text))
}

// (R-03) A seed is the stack in force at the first line: the same two lines nest one level deeper
// under an open item of content column 2 than they do alone.
@Test func aListSeedDeepensTheLevelsOfTheFragment() {
    let fragment = "  - child\n  - sibling"
    let alone = MarkdownBlockParser.lineTokens(in: fragment, endsLine: LineBreak.isTerminator)
    let seeded = MarkdownBlockParser.lineTokens(in: fragment, endsLine: LineBreak.isTerminator, listSeed: [2])
    #expect(listLevels(alone) == [1, 1])
    #expect(listLevels(seeded) == [2, 2])
}

// (R-03) A task line takes the seed the same way a list line does.
@Test func aListSeedReachesATaskLine() {
    let fragment = "  - [ ] task"
    let alone = MarkdownBlockParser.lineTokens(in: fragment, endsLine: LineBreak.isTerminator)
    let seeded = MarkdownBlockParser.lineTokens(in: fragment, endsLine: LineBreak.isTerminator, listSeed: [2])
    #expect(listLevels(alone) == [1])
    #expect(listLevels(seeded) == [2])
}

// MARK: - Transclusion.occurrences(inFragment:offset:)

private let transcludingNote = """
intro
![[Nota A]]
mid
```
![[In codice]]
```
![[Nota B#sez]]
fine
"""

private func utf16Range(of line: String, in text: String) -> NSRange {
    let nsText = text as NSString
    let found = nsText.range(of: line)
    guard found.location != NSNotFound else {
        Issue.record("\(line) is not in the text")
        return NSRange(location: 0, length: 0)
    }
    return found
}

private func slice(of text: String, _ range: NSRange) -> String {
    (text as NSString).substring(with: range)
}

// (R-03) The note's own scan, to compare a fragment's with. Non-vacuity: it finds the two notes.
@Test func theWholeNoteHoldsTwoTranscludedNotes() {
    let all = Transclusion.occurrences(in: transcludingNote)
    #expect(all.map(\.reference) == ["Nota A", "Nota B"])
}

// (R-03) A fragment of plain lines answers the slice of the whole note's occurrences, offsets in the
// note's coordinates.
@Test func aFragmentsOccurrencesAreTheSliceOfTheWholeNotesOccurrences() {
    let whole = Transclusion.occurrences(in: transcludingNote)
    let start = utf16Range(of: "![[Nota A]]", in: transcludingNote).location
    let end = utf16Range(of: "mid", in: transcludingNote)
    let fragmentRange = NSRange(location: start, length: NSMaxRange(end) - start)
    let fragment = slice(of: transcludingNote, fragmentRange)

    let found = Transclusion.occurrences(inFragment: fragment, offset: fragmentRange.location)
    let expected = whole.filter { NSLocationInRange($0.lineOffset, fragmentRange) }
    #expect(!expected.isEmpty)
    #expect(found == expected)
}

// (R-03) The last lines of the note.
@Test func aFragmentAtTheEndOfTheNoteFindsItsTranscludedNote() {
    let whole = Transclusion.occurrences(in: transcludingNote)
    let start = utf16Range(of: "![[Nota B#sez]]", in: transcludingNote).location
    let length = (transcludingNote as NSString).length - start
    let fragmentRange = NSRange(location: start, length: length)

    let found = Transclusion.occurrences(inFragment: slice(of: transcludingNote, fragmentRange), offset: start)
    #expect(found == whole.filter { NSLocationInRange($0.lineOffset, fragmentRange) })
    #expect(found.map(\.reference) == ["Nota B"])
    #expect(found.first?.section == "sez")
}

// (R-03) A whole fence is a fragment the widening can hand over: the line inside it is code, never a
// transclusion.
@Test func aTranscludingLineInsideAWholeFenceIsNotAnOccurrence() {
    let start = utf16Range(of: "```\n![[In codice]]\n```", in: transcludingNote)
    let fragment = slice(of: transcludingNote, start)
    #expect(Transclusion.occurrences(inFragment: fragment, offset: start.location).isEmpty)
}

// (R-03) A fragment that starts the note carries offset 0, and is the whole scan when it is the note.
@Test func aFragmentThatIsTheWholeNoteAtOffsetZeroEqualsTheWholeScan() {
    let note = "![[Uno]]\ntesto\n![[Due#a]]\n"
    let whole = Transclusion.occurrences(in: note)
    #expect(whole.count == 2)
    #expect(Transclusion.occurrences(inFragment: note, offset: 0) == whole)
}

// (R-03) CRLF lines: a styler line ends at "\r\n", and the offsets count the "\r" of every line before.
@Test func aCRLFFragmentKeepsTheNotesOffsets() {
    let note = "uno\r\n![[Nota A]]\r\ndue\r\n![[Nota B]]\r\ntre"
    let whole = Transclusion.occurrences(in: note)
    #expect(whole.count == 2)
    let start = utf16Range(of: "![[Nota B]]", in: note).location
    let length = (note as NSString).length - start
    let found = Transclusion.occurrences(inFragment: slice(of: note, NSRange(location: start, length: length)), offset: start)
    #expect(found == whole.filter { $0.lineOffset >= start })
    #expect(found.count == 1)
}
