import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 2 - R-06.
//
// SPEC §14 amendment (ADR §D16): HTML rendering stays excluded; extracting the body's
// text into light markdown is included from this chain on. Every fixture is synthetic
// (`Tests/EmailFixtureCorpus.swift`).

@Suite struct HTMLTextReducerTests {
    @Test func preservesParagraphsAndLineBreaks() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlParagraphsAndBreak)
        #expect(reduced.contains("Prima riga.\nSeconda riga."))
        #expect(reduced.contains("Secondo paragrafo."))
        #expect(!reduced.contains("<p>"))
        #expect(!reduced.contains("<br>"))
    }

    @Test func rendersAnUnorderedList() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlUnorderedList)
        #expect(reduced.contains("- Uno"))
        #expect(reduced.contains("- Due"))
    }

    @Test func rendersAnOrderedList() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlOrderedList)
        #expect(reduced.contains("1. Uno"))
        #expect(reduced.contains("2. Due"))
    }

    @Test func rendersALinkAsMarkdown() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlLink)
        #expect(reduced.contains("[il sito](https://vibrofer.it)"))
    }

    @Test func keepsAnOpenableLinkUnchanged() {
        let reduced = HTMLTextReducer.reduce("<p><a href=\"https://example.com\">testo</a></p>")
        #expect(reduced.contains("[testo](https://example.com)"))
    }

    @Test func reducesALinkWithARefusedSchemeToItsText() {
        // PG-124: the href never reaches the note, so no surface downstream can open it.
        let reduced = HTMLTextReducer.reduce("<p><a href=\"javascript:alert(1)\">testo</a></p>")
        #expect(reduced.contains("testo"))
        #expect(!reduced.contains("]("))
        #expect(!reduced.contains("javascript"))
    }

    @Test func rendersBoldAsDoubleAsterisks() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlBold)
        #expect(reduced.contains("**importante**"))
        #expect(reduced.contains("**anche questo**"))
    }

    @Test func rendersARegularTableAsAGFMTable() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlTable)
        #expect(reduced.contains("| Nome | Prezzo |"))
        #expect(reduced.contains("| --- | --- |"))
        #expect(reduced.contains("| Staffa | 12 |"))
    }

    @Test func dropsStylesAndScripts() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlWithStyleAndScript)
        #expect(reduced.contains("testo vero"))
        #expect(!reduced.contains("color: red"))
        #expect(!reduced.contains("alert"))
    }

    @Test func dropsARemoteImage() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlRemoteImage)
        #expect(!reduced.contains("tracker.example.test"))
    }

    @Test func dropsA1x1TrackingPixel() {
        let reduced = HTMLTextReducer.reduce(EmailFixtureCorpus.htmlTrackingPixel)
        #expect(!reduced.contains("tracker.example.test"))
        #expect(reduced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: Entities

    @Test(arguments: [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&apos;", "'"), ("&#39;", "'"),
        ("&nbsp;", " "), ("&euro;", "€"), ("&hellip;", "…"),
        ("&rsquo;", "\u{2019}"), ("&#8217;", "\u{2019}"), ("&lsquo;", "\u{2018}"),
        ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ("&ndash;", "\u{2013}"), ("&mdash;", "\u{2014}"),
        // The lookup is case-insensitive.
        ("&AMP;", "&"), ("&Euro;", "€"),
        // Numeric references outside the table go through the parse.
        ("&#65;", "A"), ("&#x41;", "A"), ("&#X41;", "A"),
    ])
    func decodesEntity(entity: String, expected: String) {
        #expect(HTMLTextReducer.reduce("<p>a\(entity)b</p>").contains("a\(expected)b"))
    }

    @Test(arguments: ["&unknown;", "&#xZZ;", "&#1114112;", "&toolongentityname;"])
    func leavesAnUnmappableEntityAsWritten(entity: String) {
        #expect(HTMLTextReducer.reduce("<p>a\(entity)b</p>").contains("a\(entity)b"))
    }
}
