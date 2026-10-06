import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D1/§D4, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-18).
//
// The value forms `MarkdownBlockParser.blocks(in:)` and `MarkdownInlineParser.spans(in:)` keep
// their signatures and become projections of the token layer. Three guards that are green on
// today's code and must stay byte for byte green after it (the values below were captured from
// the parsers as they stand on `3e5df0a6`, not written from belief), and the one red case: the
// `>date` rule of §D4.

@Suite struct MarkdownProjections {
    // MARK: Green guards, now and after

    // (n2-page R-18) The block projection is given a body, never a note: a body that opens with
    // `---\nx\n---` has a rule, a paragraph and a rule, not frontmatter.
    @Test func aBodyOpeningWithThreeDashesStaysRuleParagraphRule() {
        #expect(
            MarkdownBlockParser.blocks(in: "---\nx\n---\n\ntesto")
                == [.rule, .paragraph("x"), .rule, .paragraph("testo")]
        )
    }

    // (n2-page R-18) The inline projection emits `#tag`, `>date`, `!date` and `@annotation` as
    // plain text merged with their neighbours, exactly as the exporter shows them today.
    @Test func theInlineProjectionKeepsTheAppConventionsAsPlainText() {
        let text = "ciao #project-av45 e >2026-10-04 e !2026-10-09 e @done(2026-10-01) fine"
        #expect(MarkdownInlineParser.spans(in: text) == [MarkdownSpan(text: text)])

        #expect(
            MarkdownInlineParser.spans(in: "**a** #tag e >2026-10-04")
                == [
                    MarkdownSpan(text: "a", styles: [.strong]),
                    MarkdownSpan(text: " #tag e >2026-10-04"),
                ]
        )
    }

    // (n2-page R-18) A quote with a space after its marker stays a quote, date or not.
    @Test func aDateAfterAQuoteMarkerAndASpaceStaysAQuote() {
        #expect(MarkdownBlockParser.blocks(in: "> 2026-10-04 riunione") == [.quote(["2026-10-04 riunione"])])
        #expect(MarkdownBlockParser.blocks(in: ">citato") == [.quote(["citato"])])
    }

    // (n2-page R-18) An invalid date right after the caret is no scheduling token: still a quote.
    @Test func anInvalidDateRightAfterTheCaretStaysAQuote() {
        #expect(MarkdownBlockParser.blocks(in: ">2026-02-31") == [.quote(["2026-02-31"])])
    }

    // (n2-page R-18) ADR-0082 §D4's second export change: a single `*` steps over the `**` pair
    // nested in it, so the strong run nests in the italic and no star is left as text. On
    // `3e5df0a6` the italic closed at the first star of `**` (NoteExportGoldenCorpus E48, class A).
    @Test func aStrongRunNestedInAnItalicOneNests() {
        #expect(
            MarkdownInlineParser.spans(in: "*corsivo con **forte** dentro*")
                == [
                    MarkdownSpan(text: "corsivo con ", styles: [.emphasis]),
                    MarkdownSpan(text: "forte", styles: [.emphasis, .strong]),
                    MarkdownSpan(text: " dentro", styles: [.emphasis]),
                ]
        )
        // The outer italic keeps its own last star: `*a **b***` is an italic holding a bold.
        #expect(
            MarkdownInlineParser.spans(in: "*a **b***")
                == [
                    MarkdownSpan(text: "a ", styles: [.emphasis]),
                    MarkdownSpan(text: "b", styles: [.emphasis, .strong]),
                ]
        )
    }

    // MARK: Red: ADR-0082 §D4

    // (n2-page R-18) `>YYYY-MM-DD` at the start of a line is a scheduling token in the shared
    // block grammar, as it has always been in the editor: a paragraph, not a quote. The exporter's
    // output changes for this one input (NoteExportGoldenCorpus E46, class A).
    @Test func aScheduledDateAtTheStartOfALineIsAParagraphNotAQuote() {
        #expect(MarkdownBlockParser.blocks(in: ">2026-10-04 riunione") == [.paragraph(">2026-10-04 riunione")])
    }
}
