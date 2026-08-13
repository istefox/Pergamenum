import Foundation
import Testing
@testable import Pergamenum

// MARK: - Blocks

@Test func headingsNeedASpaceSoATagStaysATag() {
    #expect(MarkdownBlockParser.blocks(in: "# Titolo") == [.heading(level: 1, text: "Titolo")])
    #expect(MarkdownBlockParser.blocks(in: "### Sotto") == [.heading(level: 3, text: "Sotto")])
    // `#project-vibrofer` is a tag of SPEC §4.4, not a heading.
    #expect(MarkdownBlockParser.blocks(in: "#project-vibrofer") == [.paragraph("#project-vibrofer")])
}

@Test func consecutiveBulletsBecomeOneList() {
    let blocks = MarkdownBlockParser.blocks(in: "- uno\n- due\n- tre")
    #expect(blocks == [.bulletList(["uno", "due", "tre"])])
}

@Test func aBlankLineEndsTheList() {
    let blocks = MarkdownBlockParser.blocks(in: "- uno\n\ntesto")
    #expect(blocks == [.bulletList(["uno"]), .paragraph("testo")])
}

@Test func numberedItemsKeepTheirOwnList() {
    #expect(MarkdownBlockParser.blocks(in: "1. uno\n2. due") == [.numberedList(["uno", "due"])])
    // A year at the start of a line is not a list: the marker needs its dot and space.
    #expect(MarkdownBlockParser.blocks(in: "2026 è passato") == [.paragraph("2026 è passato")])
}

@Test func checklistLinesKeepTheirMarker() {
    let blocks = MarkdownBlockParser.blocks(in: "- [ ] aperto\n- [x] fatto\n- [-] annullato\n- [>] rinviato")
    #expect(blocks == [.tasks([
        MarkdownBlock.TaskLine(isDone: false, marker: " ", text: "aperto"),
        MarkdownBlock.TaskLine(isDone: true, marker: "x", text: "fatto"),
        MarkdownBlock.TaskLine(isDone: false, marker: "-", text: "annullato"),
        MarkdownBlock.TaskLine(isDone: false, marker: ">", text: "rinviato"),
    ])])
}

@Test func aFencedBlockIsTakenVerbatim() {
    let text = """
    ```swift
    # non è un titolo
    - non è una lista
    ```
    """
    #expect(MarkdownBlockParser.blocks(in: text) == [
        .code(language: "swift", lines: ["# non è un titolo", "- non è una lista"]),
    ])
}

@Test func anUnclosedFenceStillEndsAtTheEndOfTheNote() {
    // Otherwise the parser would run off the end and the note would render empty,
    // which loses the text rather than showing it oddly.
    #expect(MarkdownBlockParser.blocks(in: "```\nresto") == [.code(language: nil, lines: ["resto"])])
}

@Test func quotesAndRulesAreTheirOwnBlocks() {
    #expect(MarkdownBlockParser.blocks(in: "> citata\n> ancora") == [.quote(["citata", "ancora"])])
    #expect(MarkdownBlockParser.blocks(in: "---") == [.rule])
}

@Test func frontmatterIsNotPartOfTheBody() {
    let note = """
    ---
    date: 2026-08-12
    tags:
      - project-vibrofer
    ---

    # Titolo
    """
    let body = NoteDocument.parse(note).body
    #expect(MarkdownBlockParser.blocks(in: body) == [.heading(level: 1, text: "Titolo")])
}

// MARK: - Inline

@Test func boldItalicAndCodeBecomeSpans() {
    let spans = MarkdownInlineParser.spans(in: "testo **grassetto** e *corsivo* e `codice`")
    #expect(spans.contains { $0.text == "grassetto" && $0.styles == [.strong] })
    #expect(spans.contains { $0.text == "corsivo" && $0.styles == [.emphasis] })
    #expect(spans.contains { $0.text == "codice" && $0.styles == [.code] })
}

@Test func markupInsideCodeIsNotMarkup() {
    let spans = MarkdownInlineParser.spans(in: "`**non grassetto**`")
    #expect(spans == [MarkdownSpan(text: "**non grassetto**", styles: [.code])])
}

@Test func aWikilinkCarriesTheTitleAndShowsItsLabel() {
    #expect(MarkdownInlineParser.spans(in: "[[Nota]]") == [
        MarkdownSpan(text: "Nota", link: .note(title: "Nota")),
    ])
    #expect(MarkdownInlineParser.spans(in: "[[Nota|altro testo]]") == [
        MarkdownSpan(text: "altro testo", link: .note(title: "Nota")),
    ])
}

@Test func aMarkdownLinkKeepsItsTarget() {
    #expect(MarkdownInlineParser.spans(in: "[sito](https://esempio.it)") == [
        MarkdownSpan(text: "sito", link: .url("https://esempio.it")),
    ])
}

@Test func unmatchedSyntaxStaysVisibleInsteadOfDisappearing() {
    // The failure that matters in a reading view is losing the user's text.
    #expect(MarkdownInlineParser.spans(in: "2 * 3 * 4").map(\.text).joined() == "2 * 3 * 4")
    #expect(MarkdownInlineParser.spans(in: "[[non chiuso").map(\.text).joined() == "[[non chiuso")
    #expect(MarkdownInlineParser.spans(in: "**aperto").map(\.text).joined() == "**aperto")
}

@Test func nestedEmphasisKeepsBothStyles() {
    let spans = MarkdownInlineParser.spans(in: "**forte con *corsivo***")
    #expect(spans.contains { $0.text == "corsivo" && $0.styles == [.strong, .emphasis] })
}
