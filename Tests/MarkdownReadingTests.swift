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

// MARK: - Tables

/// SPEC §5 puts GFM tables in the required dialect, and the Inserisci menu already
/// writes one. Until now the reading view had no table block at all, so every row of
/// every table in the vault came out as a paragraph full of pipes - the separator row
/// included.

@Test func aTableNeedsItsDelimiterRowToBeATable() {
    let table = MarkdownBlockParser.blocks(in: "| a | b |\n|---|---|\n| 1 | 2 |")
    #expect(table == [.table(MarkdownBlock.Table(
        header: ["a", "b"],
        alignments: [.leading, .leading],
        rows: [["1", "2"]]
    ))])

    // The same first line without one is prose that happens to contain a pipe, and
    // reading it as a table would eat the paragraph under it.
    #expect(MarkdownBlockParser.blocks(in: "| a | b |\ntesto") == [.paragraph("| a | b |\ntesto")])
}

@Test func aDelimiterRowOfTheWrongWidthIsNotATable() {
    // GFM requires the delimiter to have exactly as many cells as the header.
    let blocks = MarkdownBlockParser.blocks(in: "| a | b |\n|---|")
    #expect(blocks == [.paragraph("| a | b |\n|---|")])
}

@Test func colonsInTheDelimiterSetTheColumnAlignment() {
    let blocks = MarkdownBlockParser.blocks(in: "| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 | 3 |")
    guard case .table(let table) = blocks.first else {
        Issue.record("atteso un blocco tabella, trovato \(blocks)")
        return
    }
    #expect(table.alignments == [.leading, .center, .trailing])
}

@Test func rowsArePaddedAndTruncatedToTheHeaderWidth() {
    let blocks = MarkdownBlockParser.blocks(in: "| a | b |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |")
    guard case .table(let table) = blocks.first else {
        Issue.record("atteso un blocco tabella, trovato \(blocks)")
        return
    }
    // A view indexes a row by column, so a short row would crash it and a long one
    // would draw a cell the table has no column for.
    #expect(table.rows == [["1", ""], ["1", "2"]])
}

@Test func anEscapedPipeStaysInsideItsCell() {
    let blocks = MarkdownBlockParser.blocks(in: "| comando | esito |\n|---|---|\n| a \\| b | ok |")
    guard case .table(let table) = blocks.first else {
        Issue.record("atteso un blocco tabella, trovato \(blocks)")
        return
    }
    #expect(table.rows == [["a | b", "ok"]])
}

@Test func aBackslashThatEscapesNothingKeepsItself() {
    let blocks = MarkdownBlockParser.blocks(in: "| percorso |\n|---|\n| C:\\dati |")
    guard case .table(let table) = blocks.first else {
        Issue.record("atteso un blocco tabella, trovato \(blocks)")
        return
    }
    #expect(table.rows == [["C:\\dati"]])
}

@Test func aBlankLineEndsTheTable() {
    let blocks = MarkdownBlockParser.blocks(in: "| a |\n|---|\n| 1 |\n\ntesto dopo")
    #expect(blocks.count == 2)
    #expect(blocks.last == .paragraph("testo dopo"))
}

@Test func aTableInsideAFenceIsCode() {
    // The fence is checked first, so a table in a code sample stays a code sample.
    let blocks = MarkdownBlockParser.blocks(in: "```markdown\n| a |\n|---|\n```")
    #expect(blocks == [.code(language: "markdown", lines: ["| a |", "|---|"])])
}

@Test func aRuleAfterAParagraphIsStillARule() {
    // `---` reaches the table check before the rule check, and a paragraph above it
    // may well contain a pipe: the widths disagree, so it stays a rule.
    let blocks = MarkdownBlockParser.blocks(in: "testo con | pipe\n---\naltro")
    #expect(blocks == [.paragraph("testo con | pipe"), .rule, .paragraph("altro")])
}

@Test func aTableEndsTheParagraphAboveIt() {
    let blocks = MarkdownBlockParser.blocks(in: "introduzione\n| a |\n|---|\n| 1 |")
    #expect(blocks.count == 2)
    #expect(blocks.first == .paragraph("introduzione"))
}
