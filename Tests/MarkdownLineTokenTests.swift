import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D1, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-18).
//
// `MarkdownBlockParser.lineTokens(in:readsFrontmatter:)`: one classification per line with the
// ranges of its markers. Red until Task 3 declares the real token layer (the stub answers `[]`).
//
// Ranges are compared as the text they cover, never as raw indices, so an assertion reads as the
// markdown it is about. Only behaviour the SPEC, ADR-0082 §D1/§D4 or the plan's own list states
// is pinned, plus two readings the grammar settled on where none of them spoke, each kept as the
// old styler had it so the styler corpus shows them unchanged (S13, S15): a quote written `> >`
// is level 1 with the two-character marker `> ` (CommonMark would say 2), and a bare `#` or
// `######` with no space after it is a paragraph, not a heading token (the block parser agreed;
// the plan's G0 item 10, for the gutter, speaks of a heading with no title).

private func tokens(_ text: String, frontmatter: Bool = false) -> [MarkdownLineToken] {
    MarkdownBlockParser.lineTokens(in: text, readsFrontmatter: frontmatter)
}

private func slice(_ text: String, _ range: Range<String.Index>) -> String {
    String(text[range])
}

private func offsets(_ text: String, _ range: Range<String.Index>) -> Range<Int> {
    text.distance(from: text.startIndex, to: range.lowerBound)..<text.distance(from: text.startIndex, to: range.upperBound)
}

@Suite struct MarkdownLineTokens {
    // MARK: Headings

    // (n2-page R-18)
    @Test(arguments: 1...6)
    func aHeadingCarriesItsLevelAndItsMarkerRun(_ level: Int) throws {
        let text = String(repeating: "#", count: level) + " Titolo"
        let result = tokens(text)

        let token = try #require(result.first)
        #expect(result.count == 1)
        #expect(slice(text, token.range) == text)
        guard case .heading(let found, let marker) = token.kind else {
            Issue.record("not a heading: \(token.kind)")
            return
        }
        #expect(found == level)
        #expect(slice(text, marker) == String(repeating: "#", count: level) + " ", "the hashes and the space after them")
    }

    // (n2-page R-18) An H6 reveals `###### `, the widest run the gutter must hold.
    @Test func anH6MarkerIsSixHashesAndASpace() throws {
        let text = "###### Sesto"
        let token = try #require(tokens(text).first)
        guard case .heading(6, let marker) = token.kind else {
            Issue.record("not an H6: \(token.kind)")
            return
        }
        #expect(slice(text, marker) == "###### ")
        #expect(offsets(text, marker) == 0..<7)
    }

    // (n2-page R-18) A heading with no title yet: the hashes and a space, nothing after.
    @Test func aHeadingWithNoTitleIsStillAHeadingToken() throws {
        let text = "## "
        let token = try #require(tokens(text).first)
        guard case .heading(2, let marker) = token.kind else {
            Issue.record("not a heading: \(token.kind)")
            return
        }
        #expect(slice(text, marker) == "## ")
    }

    // (n2-page R-18) `#tag` and seven hashes are not headings.
    @Test func aHashWithNoSpaceAfterItAndSevenHashesAreNotHeadings() {
        for text in ["#tag", "#Titolo", "####### troppo"] {
            for token in tokens(text) {
                if case .heading = token.kind { Issue.record("\(text) read as a heading") }
            }
            #expect(tokens(text).count == 1, "\(text)")
            #expect(tokens(text).first?.kind == .paragraph, "\(text)")
        }
    }

    // (n2-page R-18) Bare hashes with no space after them are a paragraph, as the old styler and
    // the block parser read them (styler corpus S15, unchanged).
    @Test(arguments: ["#", "######"])
    func bareHashesAreAParagraph(_ text: String) {
        #expect(tokens(text).map(\.kind) == [.paragraph])
    }

    // MARK: Lists

    // (n2-page R-18)
    @Test(arguments: ["- ", "* ", "+ "])
    func aBulletItemCarriesItsMarkerRunAndLevel(_ bullet: String) throws {
        let text = bullet + "uno"
        let token = try #require(tokens(text).first)
        guard case .listItem(let ordered, let indentation, let marker, let level) = token.kind else {
            Issue.record("not a list item: \(token.kind)")
            return
        }
        #expect(!ordered)
        #expect(slice(text, indentation).isEmpty)
        #expect(slice(text, marker) == bullet, "the marker and its trailing space")
        #expect(level == 1)
    }

    // (n2-page R-18)
    @Test(arguments: ["1. ", "10. ", "12) "])
    func anOrderedItemCarriesItsMarkerRun(_ marker: String) throws {
        let text = marker + "voce"
        let token = try #require(tokens(text).first)
        guard case .listItem(let ordered, _, let found, let level) = token.kind else {
            Issue.record("not a list item: \(token.kind)")
            return
        }
        #expect(ordered)
        #expect(slice(text, found) == marker)
        #expect(level == 1)
    }

    // (n2-page R-18) The indentation run (spaces and tabs) and the `ListNesting` level.
    @Test func nestedItemsCarryTheirIndentationRunAndNestingLevel() throws {
        let text = "- uno\n  - due\n    - tre"
        let result = tokens(text)
        #expect(result.count == 3)
        let expected: [(indent: String, level: Int)] = [("", 1), ("  ", 2), ("    ", 3)]
        for (token, want) in zip(result, expected) {
            guard case .listItem(_, let indentation, let marker, let level) = token.kind else {
                Issue.record("not a list item: \(token.kind)")
                continue
            }
            #expect(slice(text, indentation) == want.indent)
            #expect(slice(text, marker) == "- ")
            #expect(level == want.level)
            // The marker starts right after the indentation.
            #expect(indentation.upperBound == marker.lowerBound)
        }
    }

    // (n2-page R-18) A tab is indentation too.
    @Test func aTabIndentedItemHangsUnderItsParent() throws {
        let text = "- uno\n\t- due"
        let second = try #require(tokens(text).last)
        guard case .listItem(_, let indentation, let marker, let level) = second.kind else {
            Issue.record("not a list item: \(second.kind)")
            return
        }
        #expect(slice(text, indentation) == "\t")
        #expect(slice(text, marker) == "- ")
        #expect(level == 2)
    }

    // MARK: Tasks

    // (n2-page R-18) Every `TaskItem.State`, and a task is not a list item.
    @Test(arguments: [
        (" ", TaskItem.State.open), ("x", .done), ("-", .cancelled), (">", .rescheduled),
    ])
    func aTaskCarriesItsStateAndItsWholeMarker(_ box: String, _ state: TaskItem.State) throws {
        let text = "- [\(box)] da fare"
        let result = tokens(text)
        let token = try #require(result.first)
        #expect(result.count == 1)
        guard case .task(let found, let marker, _) = token.kind else {
            Issue.record("not a task: \(token.kind)")
            return
        }
        #expect(found == state)
        #expect(slice(text, marker) == "- [\(box)]", "the whole bracket, as the checkbox glyph replaces it")
    }

    // (n2-page R-18) The token layer is the reading view's grammar, which has always drawn a box for
    // a `+` bullet and for a blank run before `[`; the editor's styler keeps only the exact
    // `-`/`*` + one space form (`MarkdownStyler`'s mapping, S48/S49). A tab after the bullet is no
    // bullet in either reading, so `-\t[ ] x` is prose.
    @Test(arguments: [("+ [ ] x", "+ [ ]"), ("-  [ ] x", "-  [ ]")])
    func aWiderBoxIsATaskTokenForTheReadingView(_ text: String, _ marker: String) throws {
        let token = try #require(tokens(text).first)
        guard case .task(.open, let found, _) = token.kind else {
            Issue.record("not an open task: \(token.kind)")
            return
        }
        #expect(slice(text, found) == marker)
    }

    // (n2-page R-18) A task line carries its list depth from the one forward pass (PG-139), so the
    // editor's demoted bullet (S48) never walks the note backward per line.
    @Test func aTaskCarriesItsListLevel() throws {
        let result = tokens("- uno\n  + [ ] due\n    - [x] tre")
        let levels = result.compactMap { token -> Int? in
            if case .task(_, _, let level) = token.kind { return level }
            return nil
        }
        #expect(levels == [2, 3])
    }

    @Test func aTabAfterTheBulletIsNoTaskAndNoListItem() throws {
        let token = try #require(tokens("-\t[ ] x").first)
        #expect(token.kind == .paragraph)
    }

    // MARK: Quotes

    // (n2-page R-18)
    @Test func aQuoteCarriesItsLevelAndMarkerRun() throws {
        let text = "> citazione"
        let token = try #require(tokens(text).first)
        guard case .quote(let level, let marker) = token.kind else {
            Issue.record("not a quote: \(token.kind)")
            return
        }
        #expect(level == 1)
        #expect(slice(text, marker) == "> ")
    }

    // (n2-page R-18) `>` with no space after it is still a quote (GFM); two carets are level 2.
    @Test func aQuoteNeedsNoSpaceAndCountsItsCarets() throws {
        let one = try #require(tokens(">senza spazio").first)
        guard case .quote(1, let marker) = one.kind else {
            Issue.record("not a level-1 quote: \(one.kind)")
            return
        }
        #expect(slice(">senza spazio", marker) == ">")

        let two = try #require(tokens(">>annidata").first)
        guard case .quote(2, let nested) = two.kind else {
            Issue.record("not a level-2 quote: \(two.kind)")
            return
        }
        #expect(slice(">>annidata", nested) == ">>")
    }

    // (n2-page R-18) `> >` is a level-1 quote whose marker is the first `> `, as the old styler
    // read it (styler corpus S13, unchanged).
    @Test func aSpacedNestedQuoteIsALevelOneQuoteLine() throws {
        let text = "> > annidata"
        let token = try #require(tokens(text).first)
        guard case .quote(let level, let marker) = token.kind else {
            Issue.record("not a quote: \(token.kind)")
            return
        }
        #expect(level == 1)
        #expect(slice(text, marker) == "> ")
    }

    // MARK: The `>date` rule (ADR-0082 §D4)

    // (n2-page R-18) `>YYYY-MM-DD` at the start of a line is a scheduling token, not a quote.
    @Test func aDateRightAfterTheCaretIsAParagraphNotAQuote() {
        #expect(tokens(">2026-10-04 x").map(\.kind) == [.paragraph])
    }

    // (n2-page R-18) With a space it stays a quote.
    @Test func aDateAfterASpaceStaysAQuote() throws {
        let token = try #require(tokens("> 2026-10-04").first)
        guard case .quote = token.kind else {
            Issue.record("not a quote: \(token.kind)")
            return
        }
    }

    // (n2-page R-18) An invalid date at line start is not a scheduling token: it stays a quote,
    // which keeps the `CalendarDate(iso:)` test of the styler's date rule.
    @Test func anInvalidDateRightAfterTheCaretStaysAQuote() throws {
        let token = try #require(tokens(">2026-02-31").first)
        guard case .quote = token.kind else {
            Issue.record("not a quote: \(token.kind)")
            return
        }
    }

    // MARK: Rules, fences, tables, anchors, blank lines

    // (n2-page R-18)
    @Test(arguments: ["---", "***", "___", "- - -", "* * *"])
    func aThematicBreakIsARule(_ line: String) {
        #expect(tokens(line).map(\.kind) == [.rule], "\(line)")
    }

    // (n2-page R-18) A fence's open (with its language), body and close.
    @Test func aFenceHasAnOpenABodyAndAClose() {
        let text = "```swift\nlet x = 1\n# non un titolo\n```"
        #expect(tokens(text).map(\.kind) == [.fenceOpen(language: "swift"), .fenceBody, .fenceBody, .fenceClose])
        #expect(tokens("```\nx\n```").map(\.kind) == [.fenceOpen(language: nil), .fenceBody, .fenceClose])
    }

    // (n2-page R-18) A `pergamenum-view` fence is a fence like any other, with its own language.
    @Test func aViewBlockFenceOpensWithItsLanguage() {
        let text = "```pergamenum-view\nrender: table\n```"
        #expect(tokens(text).map(\.kind) == [.fenceOpen(language: ViewBlock.language), .fenceBody, .fenceClose])
    }

    // (n2-page R-18) A table is its header, its delimiter row and its body rows.
    @Test func everyLineOfATableIsATableRow() {
        let text = "| a | b |\n|:--|--:|\n| 1 | 2 |\n\ndopo"
        #expect(tokens(text).map(\.kind) == [.tableRow, .tableRow, .tableRow, .blank, .paragraph])
        // A pipe line with no delimiter row after it is prose.
        #expect(tokens("| solo | riga |").map(\.kind) == [.paragraph])
    }

    // (n2-page R-18)
    @Test func aMessageAnchorLineIsAMessageAnchor() {
        #expect(tokens("<!-- pergamenum-message: <abc@example.com> -->").map(\.kind) == [.messageAnchor])
    }

    // (n2-page R-18)
    @Test func blankAndProseLinesAreClassified() {
        #expect(tokens("uno\n\ndue").map(\.kind) == [.paragraph, .blank, .paragraph])
    }

    // MARK: Frontmatter

    // (n2-page R-18) Read only when asked: the block projection is given a body.
    @Test func frontmatterIsReadOnlyWhenAsked() {
        let text = "---\ndate: 2026-10-04\n---\n\n# Titolo"
        let asked = tokens(text, frontmatter: true).map(\.kind)
        #expect(asked.count == 5)
        #expect(Array(asked.prefix(3)) == [.frontmatter, .frontmatter, .frontmatter])
        #expect(asked.dropFirst(3).first == .blank)

        let notAsked = tokens(text).map(\.kind)
        #expect(!notAsked.contains(.frontmatter))
        #expect(notAsked.first == .rule, "a leading `---` of a body is a rule")
    }

    // MARK: Line terminators

    // (n2-page R-18) A CRLF line ends before its `\r\n`: the range never carries the terminator.
    @Test func crlfLineRangesExcludeTheTerminator() {
        let text = "# Titolo\r\n\r\n- uno\r\nfine"
        let result = tokens(text)
        #expect(result.map { slice(text, $0.range) } == ["# Titolo", "", "- uno", "fine"])
        #expect(result.map(\.kind).count == 4)
        #expect(result.dropFirst().first?.kind == .blank)
    }

    // (n2-page R-18) Every token's range is the line it classifies, in order.
    @Test func eachTokenCoversOneLineInOrder() {
        let text = "uno\ndue\ntre"
        #expect(tokens(text).map { slice(text, $0.range) } == ["uno", "due", "tre"])
    }
}
