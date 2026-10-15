import Foundation
import Testing
@testable import Pergamenum

// ADR-0087 §D2 and §D3, plan docs/plans/note-workflow-n5.md, Task 1 (R-38).
//
// The shared callout grammar: the kind a keyword names, the title line `Callout.header(inLine:)`
// recognises, and the block the parser folds a quote run into.

private func quote(_ level: Int, _ text: String) -> MarkdownBlock.QuoteLine {
    MarkdownBlock.QuoteLine(level: level, text: text)
}

// MARK: - Kinds

@Suite struct CalloutKinds {
    private static let readings: [(String, CalloutKind)] = [
        ("note", .note), ("tip", .tip), ("important", .important), ("warning", .warning), ("caution", .caution),
        ("nota", .note), ("suggerimento", .tip), ("importante", .important), ("avviso", .warning),
        ("attenzione", .caution),
        ("WARNING", .warning), ("Avviso", .warning), ("NOTE", .note), ("Suggerimento", .tip),
    ]

    @Test func theFiveEnglishKeywordsAndTheFiveItalianAliasesReadAsTheirCase() { // R-38
        for (keyword, kind) in Self.readings {
            #expect(CalloutKind(keyword: keyword) == kind, "[!\(keyword)]")
        }
    }

    @Test func anyOtherTypeReadsAsOtherAsWritten() { // R-38
        #expect(CalloutKind(keyword: "faq") == .other("faq"))
        #expect(CalloutKind(keyword: "FAQ") == .other("FAQ"))
        #expect(CalloutKind(keyword: "Domande-Frequenti") == .other("Domande-Frequenti"))
    }

    @Test func theKeywordIsAlwaysTheEnglishOneForTheFive() { // R-38
        #expect(CalloutKind.note.keyword == "note")
        #expect(CalloutKind.tip.keyword == "tip")
        #expect(CalloutKind.important.keyword == "important")
        #expect(CalloutKind.warning.keyword == "warning")
        #expect(CalloutKind.caution.keyword == "caution")
        // An Italian alias is read as the case, so what the app would write for it is English.
        #expect(CalloutKind(keyword: "avviso").keyword == "warning")
    }

    @Test func theLabelIsItalianForTheFiveAndTheCapitalisedTypeForOther() { // R-38
        #expect(CalloutKind.note.label == "Nota")
        #expect(CalloutKind.tip.label == "Suggerimento")
        #expect(CalloutKind.important.label == "Importante")
        #expect(CalloutKind.warning.label == "Avviso")
        #expect(CalloutKind.caution.label == "Attenzione")
        #expect(CalloutKind.other("faq").label == "Faq")
        #expect(CalloutKind.other("domande").label == "Domande")
    }

    @Test func theExportClassIsOneOfSixFixedValues() { // R-43
        #expect(CalloutKind.note.exportClass == "callout-note")
        #expect(CalloutKind.tip.exportClass == "callout-tip")
        #expect(CalloutKind.important.exportClass == "callout-important")
        #expect(CalloutKind.warning.exportClass == "callout-warning")
        #expect(CalloutKind.caution.exportClass == "callout-caution")
        #expect(CalloutKind.other("faq").exportClass == "callout-other")
        // Never text from the note, however hostile (ADR-0087 §D12).
        #expect(CalloutKind.other("x\" onload=\"y").exportClass == "callout-other")
    }
}

// MARK: - The title line

@Suite struct CalloutHeaders {
    @Test func aBareHeaderIsAFixedCalloutWithNoTitle() { // R-38
        #expect(Callout.header(inLine: "> [!note]") == Callout.Header(
            kind: .note, fold: .fixed, title: nil, markerLength: 9
        ))
    }

    @Test func aTitleIsWhatFollowsTheKeywordAndNeverPartOfTheMarker() { // R-38
        #expect(Callout.header(inLine: "> [!note] Titolo") == Callout.Header(
            kind: .note, fold: .fixed, title: "Titolo", markerLength: 10
        ))
    }

    @Test func aMinusFoldsAndTheCaretNeedsNoSpace() { // R-38
        #expect(Callout.header(inLine: ">[!tip]- Titolo") == Callout.Header(
            kind: .tip, fold: .folded, title: "Titolo", markerLength: 9
        ))
    }

    @Test func aPlusStartsOpenAndAnItalianAliasReadsAsItsCase() { // R-38
        #expect(Callout.header(inLine: "> [!avviso]+") == Callout.Header(
            kind: .warning, fold: .open, title: nil, markerLength: 12
        ))
    }

    @Test(arguments: ["> [!]", "> [note]", "> > [!note]", "[!note] senza caret", "> testo"])
    func aLineThatIsNotAHeaderIsNil(_ line: String) { // R-38
        #expect(Callout.header(inLine: line) == nil, "\(line.debugDescription)")
    }
}

// MARK: - The block

@Suite struct CalloutBlocks {
    @Test func theBodyLinesCarryTheirLevelMinusOne() { // R-38
        #expect(MarkdownBlockParser.blocks(in: "> [!note] Titolo\n> a\n>> b") == [
            .callout(Callout(kind: .note, title: "Titolo", fold: .fixed, body: [quote(0, "a"), quote(1, "b")])),
        ])
    }

    @Test func theRunEndsAtTheFirstNonQuoteLine() { // R-38
        #expect(MarkdownBlockParser.blocks(in: "> [!tip] T\n> a\ntesto") == [
            .callout(Callout(kind: .tip, title: "T", fold: .fixed, body: [quote(0, "a")])),
            .paragraph("testo"),
        ])
    }

    @Test func aHeaderWithNothingAfterItIsACalloutWithAnEmptyBody() { // R-38
        #expect(MarkdownBlockParser.blocks(in: "> [!note]") == [
            .callout(Callout(kind: .note, title: nil, fold: .fixed, body: [])),
        ])
    }

    @Test func aFoldSignIsCarriedIntoTheBlock() { // R-38
        #expect(MarkdownBlockParser.blocks(in: "> [!avviso]- Forno\n> Corpo") == [
            .callout(Callout(kind: .warning, title: "Forno", fold: .folded, body: [quote(0, "Corpo")])),
        ])
    }

    @Test func aTypeAtLevelTwoStaysQuoteText() { // R-38
        #expect(MarkdownBlockParser.blocks(in: ">> [!note] x") == [.quote([quote(2, "[!note] x")])])
    }

    /// The header opens a callout only as the first line of its quote run (ADR-0087 §D2).
    @Test func aTypeOnALaterLineOfAPlainQuoteStaysQuoteText() { // R-38
        #expect(MarkdownBlockParser.blocks(in: "> a\n> [!note] b") == [
            .quote([quote(1, "a"), quote(1, "[!note] b")]),
        ])
    }
}
