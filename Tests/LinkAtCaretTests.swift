import Foundation
import Testing
@testable import Pergamenum

/// R-21 (ADR-0083 §D3): which followable link the caret is on, as one pure rule over the
/// `.editorLink` runs of the caret's paragraph and the wikilinks' source ranges.
///
/// The ranges in each test are read off a literal string, written beside the test, so a reader can
/// count the offsets the way the editor does (UTF-16).
@Suite struct LinkAtCaretTests {
    private static func url(_ title: String) -> URL { MarkdownAttributedText.noteURL(for: title) }

    private static func run(_ location: Int, _ length: Int, _ title: String) -> LinkAtCaret.Run {
        LinkAtCaret.Run(range: NSRange(location: location, length: length), url: url(title))
    }

    // MARK: A run under the caret

    /// `Vedi Dest qui`: the run is "Dest", 5..<9.
    @Test func aCaretInsideARunPicksItsURL() {
        let runs = [Self.run(5, 4, "Dest")]
        #expect(LinkAtCaret.pick(caret: 7, runs: runs, wikilinks: []) == Self.url("Dest"))
    }

    @Test func aCaretAtTheStartOfARunPicksItsURL() {
        let runs = [Self.run(5, 4, "Dest")]
        #expect(LinkAtCaret.pick(caret: 5, runs: runs, wikilinks: []) == Self.url("Dest"))
    }

    @Test func aCaretAtTheEndOfARunPicksItsURL() {
        // Touching the run at either edge counts: the caret that has just typed or arrowed past
        // the last letter of a link is still on it.
        let runs = [Self.run(5, 4, "Dest")]
        #expect(LinkAtCaret.pick(caret: 9, runs: runs, wikilinks: []) == Self.url("Dest"))
    }

    @Test func aCaretAwayFromEveryRunPicksNothing() {
        let runs = [Self.run(5, 4, "Dest")]
        #expect(LinkAtCaret.pick(caret: 2, runs: runs, wikilinks: []) == nil)
        #expect(LinkAtCaret.pick(caret: 12, runs: runs, wikilinks: []) == nil)
    }

    // MARK: Inside the wikilink's own syntax

    /// `[[Nota]]`: the run is "Nota", 2..<6; the wikilink is 0..<8.
    @Test func aCaretInsideTheOpeningBracketsPicksTheRunInsideThatWikilink() {
        let runs = [Self.run(2, 4, "Nota")]
        let wikilinks = [NSRange(location: 0, length: 8)]
        #expect(LinkAtCaret.pick(caret: 1, runs: runs, wikilinks: wikilinks) == Self.url("Nota"))
    }

    @Test func aCaretBetweenTheClosingBracketsPicksTheRunInsideThatWikilink() {
        let runs = [Self.run(2, 4, "Nota")]
        let wikilinks = [NSRange(location: 0, length: 8)]
        #expect(LinkAtCaret.pick(caret: 7, runs: runs, wikilinks: wikilinks) == Self.url("Nota"))
    }

    /// `[[Nota|alias]]`: the run is "Nota", 2..<6; the wikilink is 0..<14; the alias is 7..<12.
    @Test func aCaretInTheAliasPicksTheRunOfTheTitleBeforeIt() {
        let runs = [Self.run(2, 4, "Nota")]
        let wikilinks = [NSRange(location: 0, length: 14)]
        #expect(LinkAtCaret.pick(caret: 9, runs: runs, wikilinks: wikilinks) == Self.url("Nota"))
    }

    @Test func aWikilinkWithNoRunInsideItPicksNothing() {
        // `![[foto.png]]` styled as an embed carries no note run to hand over.
        let wikilinks = [NSRange(location: 0, length: 13)]
        #expect(LinkAtCaret.pick(caret: 5, runs: [], wikilinks: wikilinks) == nil)
    }

    // MARK: Several candidates

    /// `[testo [[Nota]] fine](https://x.com)`: the CommonMark label is 1..<20, the wikilink inside
    /// it 7..<15, and its run "Nota" 9..<13.
    @Test func aMarkdownLinkWhoseLabelHoldsAWikilinkPicksTheWikilinksURL() {
        let outer = LinkAtCaret.Run(
            range: NSRange(location: 1, length: 19), url: URL(string: "https://x.com")!
        )
        let inner = Self.run(9, 4, "Nota")
        let wikilinks = [NSRange(location: 7, length: 8)]
        #expect(LinkAtCaret.pick(caret: 10, runs: [outer, inner], wikilinks: wikilinks) == Self.url("Nota"))
        // Order of the arguments must not decide it.
        #expect(LinkAtCaret.pick(caret: 10, runs: [inner, outer], wikilinks: wikilinks) == Self.url("Nota"))
    }

    @Test func inThatLabelAwayFromTheWikilinkTheOuterLinkWins() {
        let outer = LinkAtCaret.Run(
            range: NSRange(location: 1, length: 19), url: URL(string: "https://x.com")!
        )
        let inner = Self.run(9, 4, "Nota")
        let wikilinks = [NSRange(location: 7, length: 8)]
        #expect(
            LinkAtCaret.pick(caret: 3, runs: [outer, inner], wikilinks: wikilinks)
                == URL(string: "https://x.com")
        )
    }

    /// `[[Uno]] e [[Due]]`: "Uno" is 2..<5, "Due" is 12..<15.
    @Test func twoRunsOnALinePickTheOneAtTheCaret() {
        let runs = [Self.run(2, 3, "Uno"), Self.run(12, 3, "Due")]
        let wikilinks = [NSRange(location: 0, length: 7), NSRange(location: 10, length: 7)]
        #expect(LinkAtCaret.pick(caret: 3, runs: runs, wikilinks: wikilinks) == Self.url("Uno"))
        #expect(LinkAtCaret.pick(caret: 13, runs: runs, wikilinks: wikilinks) == Self.url("Due"))
        #expect(LinkAtCaret.pick(caret: 8, runs: runs, wikilinks: wikilinks) == nil)
    }

    @Test func noRunsAndNoWikilinksPickNothing() {
        #expect(LinkAtCaret.pick(caret: 0, runs: [], wikilinks: []) == nil)
    }
}
