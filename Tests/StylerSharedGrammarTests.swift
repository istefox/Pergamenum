import Foundation
import Testing
@testable import Pergamenum

// ADR-0082 §D2, plan docs/plans/pg-385-n2-page.md, Task 2 (PG-385, R-18; closes PG-347, #762).
//
// The styler classifies through the same parsers the reading surfaces and the HTML export use,
// so `file_name_here` is plain in the editor as it already is in the export. Red until Task 3
// maps the token layer onto `Span`. `_` emphasis stays unconcealed (G0): the styler styles a `_`
// run the parser accepts and keeps its delimiters visible.

private func isEmphasisSpan(_ span: MarkdownStyler.Span) -> Bool {
    span == .italic || span == .emphasisMarker || span == .bold
}

@MainActor
@Suite struct StylerSharedGrammar {
    // (n2-page R-18) PG-347: an intraword underscore pair is not emphasis.
    @Test(arguments: ["file_name_here", "nome_file_lungo", "nome_file_lungo e nome_file_lungo_due"])
    func intrawordUnderscoresCarryNoEmphasisSpan(_ text: String) {
        let spans = MarkdownStyler.spans(in: text).map(\.span)
        #expect(!spans.contains(where: isEmphasisSpan), "\(text): \(spans)")
    }

    // (n2-page R-18) A spaced `*` is a multiplication sign, not emphasis.
    @Test func spacedStarsCarryNoEmphasisSpan() {
        let spans = MarkdownStyler.spans(in: "2 * 3 * 4").map(\.span)
        #expect(!spans.contains(where: isEmphasisSpan), "\(spans)")
    }

    // (n2-page R-18) The export already agrees: no `<em>` for either.
    @Test(arguments: ["file_name_here", "2 * 3 * 4", "nome_file_lungo"])
    func theExportHoldsNoEmphasisEither(_ text: String) {
        #expect(!MarkdownHTML.render(text).contains("<em>"), "\(text)")
    }

    // (n2-page R-18) `_a_` at word boundaries is italic, and its underscores are no marker the
    // editor would conceal: `_` emphasis stays unconcealed.
    @Test func anUnderscorePairIsItalicAndItsDelimitersStayVisible() throws {
        let text = "_a_"
        let styled = MarkdownStyler.spans(in: text)
        let italic = try #require(styled.first { $0.span == .italic })
        #expect(String(text[italic.range]) == "_a_")
        #expect(!styled.contains { $0.span == .emphasisMarker }, "no `.emphasisMarker` over a `_`")
        for item in styled {
            #expect(
                NoteTextView.Coordinator.hiddenKind(for: item.span) == nil,
                "\(item.span) would be concealed"
            )
        }
    }

    // (n2-page R-18) The star form still conceals its delimiters, as before (ADR-0018 slice 2).
    @Test func aStarPairKeepsItsConcealableMarkers() {
        let styled = MarkdownStyler.spans(in: "*a* e **b**")
        #expect(styled.filter { $0.span == .emphasisMarker }.count == 4)
        #expect(styled.contains { $0.span == .italic })
        #expect(styled.contains { $0.span == .bold })
    }
}
