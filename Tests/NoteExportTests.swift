import Foundation
import Testing
@testable import Pergamenum

private let note = """
---
date: 2026-08-12
tags:
  - type-note
related:
  - "[[Altra nota]]"
---

# Curva di trasmissibilità

Il supporto **AV-45** ha una frequenza propria di *4,2 Hz*.

## Note correlate

- [[Altra nota]] — sorgente dei dati di carico

## Metodo

Misura con `accelerometro` triassiale.
"""

@Test func exportingMarkdownRemovesTheFrontmatter() {
    let exported = NoteExport.markdown(from: note)
    // The frontmatter is this system's bookkeeping and means nothing to the reader
    // (frontmatter.md 6.3).
    #expect(!exported.contains("type-note"))
    #expect(!exported.contains("date:"))
    #expect(exported.hasPrefix("# Curva di trasmissibilità"))
}

@Test func exportingMarkdownRemovesTheRelatedSectionButKeepsWhatFollows() {
    let exported = NoteExport.markdown(from: note)
    // The section points at notes the reader does not have (wikilink.md 6.3).
    #expect(!exported.contains("Note correlate"))
    #expect(!exported.contains("sorgente dei dati di carico"))
    #expect(exported.contains("## Metodo"))
    #expect(exported.contains("accelerometro"))
}

@Test func aNoteWithoutARelatedSectionExportsWhole() {
    let plain = """
    ---
    date: 2026-08-12
    tags:
      - type-note
    ---

    Solo corpo.
    """
    #expect(NoteExport.markdown(from: plain) == "Solo corpo.\n")
}

// MARK: - HTML

@Test func headingsAndEmphasisBecomeMarkup() {
    let html = MarkdownHTML.render("# Titolo\n\nTesto **forte** e *lieve*.")
    #expect(html.contains("<h1>Titolo</h1>"))
    #expect(html.contains("<strong>forte</strong>"))
    #expect(html.contains("<em>lieve</em>"))
}

@Test func aWikilinkBecomesItsDisplayText() {
    // The reader has no vault to resolve it in.
    #expect(MarkdownHTML.inline("Vedi [[Curva di trasmissibilità]].")
        == "Vedi Curva di trasmissibilità.")
    #expect(MarkdownHTML.inline("[[Nota#Sezione|come qui]]") == "come qui")
    #expect(MarkdownHTML.inline("[[Nota#Sezione]]") == "Nota")
}

@Test func aMarkdownLinkBecomesAnAnchor() {
    #expect(MarkdownHTML.inline("[Vibrofer](https://vibrofer.it)")
        == "<a href=\"https://vibrofer.it\">Vibrofer</a>")
}

@Test func aBulletListBecomesAList() {
    let html = MarkdownHTML.render("- uno\n- due")
    #expect(html == "<ul>\n<li>uno</li>\n<li>due</li>\n</ul>")
}

@Test func aNumberedListIsOrdered() {
    let html = MarkdownHTML.render("1. primo\n2. secondo")
    #expect(html.contains("<ol>"))
    #expect(html.contains("<li>primo</li>"))
}

@Test func aTaskListKeepsItsBoxes() {
    let html = MarkdownHTML.render("- [ ] da fare\n- [x] fatto")
    // An exported checklist that lost its state would be a different document.
    #expect(html.contains("☐ da fare"))
    #expect(html.contains("☑ fatto"))
}

@Test func aFencedBlockIsCodeAndItsContentIsNotInterpreted() {
    let html = MarkdownHTML.render("```swift\nlet x = a < b && *p\n```")
    #expect(html.contains("<pre><code>"))
    #expect(html.contains("a &lt; b"))
    #expect(!html.contains("<em>"))
}

@Test func aTableBecomesATable() {
    let html = MarkdownHTML.render("""
    | Grandezza | Valore |
    |---|---|
    | Carico | 450 daN |
    """)
    #expect(html.contains("<th>Grandezza</th>"))
    #expect(html.contains("<td>450 daN</td>"))
    // The alignment row is a separator, not a row of data.
    #expect(!html.contains("<td>---</td>"))
}

@Test func aQuoteBecomesABlockquote() {
    #expect(MarkdownHTML.render("> citato").contains("<blockquote><p>citato</p></blockquote>"))
}

@Test func angleBracketsInProseAreEscapedNotSwallowed() {
    let html = MarkdownHTML.render("Frequenza < 5 Hz & carico > 400 daN")
    #expect(html.contains("&lt; 5 Hz &amp; carico &gt;"))
}

@Test func anUnmatchedAsteriskStaysAsText() {
    // Dropping it silently would change what the note says.
    #expect(MarkdownHTML.inline("2 * 3 daN") == "2 * 3 daN")
}

@Test func theExportedPageCarriesTheTitleAndTheBody() {
    let html = NoteExport.html(from: note, title: "Curva di trasmissibilità")
    #expect(html.contains("<title>Curva di trasmissibilità</title>"))
    #expect(html.contains("<h1>Curva di trasmissibilità</h1>"))
    #expect(!html.contains("Note correlate"))
    #expect(html.hasPrefix("<!DOCTYPE html>"))
}

// MARK: - The PDF actually written

@MainActor
@Test func exportingAPDFWritesARealPDFFile() throws {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-export-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }

    // Long enough to paginate: a PDF whose second page is missing is the failure an
    // export must not have.
    let body = (1...80).map { "Riga \($0) del corpo della nota esportata." }.joined(separator: "\n\n")
    try NoteExporter.writePDF(html: NoteExport.html(from: body, title: "Prova"), to: url)

    let data = try Data(contentsOf: url)
    #expect(data.count > 1000)
    #expect(data.prefix(5) == Data("%PDF-".utf8))
}
