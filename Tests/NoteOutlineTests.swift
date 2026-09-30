import AppKit
import Foundation
import Testing
@testable import Pergamenum

/// The note's index (M8).
///
/// Two things here are load-bearing. What counts as a heading has to be the same rule the
/// rest of the app uses, or the index lists sections the note does not have. And the index
/// has to agree with the reading view about the *order* of those sections, because that
/// ordinal is the only thing connecting a click in the sidebar to a block on screen.

private func titles(_ text: String) -> [String] {
    NoteOutline.entries(in: text).map(\.title)
}

// MARK: - What is a heading

@Test func listsHeadingsInOrderWithTheirLevels() {
    let note = """
    # Curva di trasmissibilità
    testo
    ## Prove in laboratorio
    ### Campione A
    """
    let entries = NoteOutline.entries(in: note)
    #expect(entries.map(\.title) == ["Curva di trasmissibilità", "Prove in laboratorio", "Campione A"])
    #expect(entries.map(\.kind) == [.heading(level: 1), .heading(level: 2), .heading(level: 3)])
}

@Test func aTagAtTheStartOfALineIsNotAHeading() {
    // `#` with no space is a tag, which is the rule `MarkdownStyler` already applies. An
    // index that listed every tag as a section would be useless in this vault.
    #expect(titles("#project-forno\n# Vero titolo") == ["Vero titolo"])
    #expect(titles("####### troppi cancelletti").isEmpty)
}

@Test func aHashInsideACodeFenceIsNotAHeading() {
    // The defect closed earlier today, asserted from the other side: this would have been
    // the second place in the project to read a shell comment as markdown.
    let note = """
    # Vero titolo

    ```sh
    # rigenera l'indice
    perg index --rebuild
    ```

    ## Dopo il blocco
    """
    #expect(titles(note) == ["Vero titolo", "Dopo il blocco"])
}

@Test func theFrontmatterIsNotPartOfTheIndex() {
    // `---` is not a heading, but the keys inside a frontmatter block are not either, and
    // a note whose body starts with a heading must still show it.
    let note = "---\ndate: 2026-08-17\ntags:\n  - topic-editor\n---\n\n# Primo titolo\n"
    #expect(titles(note) == ["Primo titolo"])
}

// MARK: - What a row says

@Test func aHeadingShowsItsTextAndNotItsMarkdown() {
    // An index full of brackets is harder to scan than the note it indexes.
    #expect(titles("## Vedi [[Altra nota]] qui") == ["Vedi Altra nota qui"])
    #expect(titles("## Prove **decisive**") == ["Prove decisive"])
    #expect(titles("## `perg index`") == ["perg index"])
}

@Test func anEmbedOnItsOwnLineIsAnEntryAndOneInsideASentenceIsNot() {
    // A picture in the middle of a sentence is an illustration, not a section.
    let note = """
    # Titolo
    ![[Mescole per il forno]]
    Testo con ![[foto.png]] dentro la frase.
    """
    let entries = NoteOutline.entries(in: note)
    #expect(entries.map(\.title) == ["Titolo", "Mescole per il forno"])
    #expect(entries.last?.kind == .embed)
}

@Test func anEmbedIsIndentedInsideTheSectionItSitsUnder() {
    // Markdown gives an embed no level of its own; the document does.
    let note = "# Uno\n## Due\n![[Mescole per il forno]]\n"
    #expect(NoteOutline.entries(in: note).map(\.level) == [1, 2, 3])
}

@Test func aNoteWithNoHeadingsGivesAnEmptyIndexAndNotAnError() {
    #expect(NoteOutline.entries(in: "").isEmpty)
    #expect(NoteOutline.entries(in: "solo prosa, nessun titolo").isEmpty)
    #expect(NoteOutline.entries(in: "---\ndate: 2026-08-17\n---\n").isEmpty)
}

@Test func theRangeIsTheWholeLineSoTheEditorCanScrollToIt() {
    let note = "prima\n## Il titolo\ndopo"
    let entry = NoteOutline.entries(in: note).first
    #expect(entry.map { String(note[$0.range]) } == "## Il titolo")
}

// MARK: - The bridge between the two surfaces

@Test func theNthEntryIsTheNthBlockTheReadingViewDraws() {
    // The only place the sidebar and the reading view can disagree. A click scrolls by
    // ordinal - the nth entry is the nth heading-or-embed block - so if one of the two
    // ever changes its mind about what a heading is, this goes red instead of a click
    // quietly landing on the wrong section.
    let note = """
    ---
    date: 2026-08-17
    ---

    # Curva di trasmissibilità

    Testo con #topic-editor dentro.

    ```python
    # non è un titolo
    def f(): pass
    ```

    ## Prove in laboratorio

    ![[Mescole per il forno]]

    ### Campione A, 60 shore

    Testo con ![[foto.png]] dentro la frase.

    ####### non è un titolo
    """
    let entries = NoteOutline.entries(in: note)
    let blocks = MarkdownBlockParser.blocks(in: NoteDocument.parse(note).body)

    let indexed = blocks.compactMap { block -> (title: String, level: Int?)? in
        switch block {
        case .heading(let level, let text): (text, level)
        case .embed(let target, let alt): (alt ?? target, nil)
        // A note embed became its own block with ADR-0010, and the index still lists it as
        // one entry. Both have to be counted here or the two go out of step by one for the
        // rest of the note, which is a click landing on the wrong section.
        case .transclusion(let reference, let section): (section.map { "\(reference)#\($0)" } ?? reference, nil)
        default: nil
        }
    }
    #expect(entries.count == indexed.count)
    for (entry, block) in zip(entries, indexed) {
        // The titles are compared after the same stripping the index does, because the
        // block parser keeps the raw text and the index does not.
        let blockTitle = MarkdownInlineParser.spans(in: block.title).map(\.text).joined()
        #expect(entry.title == blockTitle)
        if case .heading(let level) = entry.kind {
            #expect(level == block.level)
        } else {
            #expect(block.level == nil)
        }
    }
}

// MARK: - CRLF notes (PG-274)

@Test func aCRLFNoteListsEveryHeadingWithNoCarriageReturn() {
    // "\r\n" is one Character, so a walk for "\n" read the whole note as one line.
    let lf = "# Uno\ntesto\n## Due\n### Tre\n"
    let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(titles(crlf) == ["Uno", "Due", "Tre"])
    #expect(titles(crlf) == titles(lf))
    #expect(NoteOutline.entries(in: crlf).map(\.kind) == NoteOutline.entries(in: lf).map(\.kind))
}

@Test func aCRLFNoteOutlineRangesExcludeTheLineBreak() {
    let crlf = "# Uno\r\ntesto\r\n## Due\r\n"
    let entries = NoteOutline.entries(in: crlf)
    #expect(entries.map { String(crlf[$0.range]) } == ["# Uno", "## Due"])
}

@Test func aCRLFNoteWithFrontmatterAndAFenceKeepsTheOutlineRight() {
    let crlf = "---\r\ndate: 2026-08-11\r\n---\r\n# Vero\r\n```sh\r\n# commento\r\n```\r\n## Dopo\r\n"
    #expect(titles(crlf) == ["Vero", "Dopo"])
}

// MARK: - The pane's move reaches the note (ADR-0074 G2 H11)

/// G2 H11, second half: `OutlinePane`'s drop hands its replacements to
/// `Navigation.moveOutlineSection`, `EditorColumnView` forwards `navigation.outlineMove` as the
/// column's pending replacements and the coordinator's `apply(_:to:)` writes them. The
/// SwiftUI `.onChange` hop between the last two cannot run in-process; everything either side
/// of it can, and `OutlineMoveTests` only applies the replacements to an `NSMutableString`
/// rather than to a real text view. The first half of H11 (the selection reporting a new
/// entry) is already pinned by `OutlineEntryCallbackFiresOnChangeOnly` in
/// `EditorControllerReadTimingRemainingTests`. The undo half catches a missing undo registration,
/// not a split within one event (event grouping merges those in production too).
@MainActor
@Test func anOutlineDropRewritesTheNoteInTheEditorAndOneUndoRestoresIt() throws {
    let note = "# A\ntesto di A\n# B\ntesto di B"
    let fixture = EmbedEditorFixtures.editor(text: note, hidesMarkup: false, root: nil, thumbnails: nil)
    defer { fixture.window.orderOut(nil) }
    let undo = try #require(fixture.textView.undoManager)
    let navigation = Navigation()
    let dropped = try #require(OutlineMove.replacements(in: note, moving: 0, toPrecede: nil))

    navigation.moveOutlineSection(dropped)
    let request = try #require(navigation.outlineMove)
    fixture.coordinator.apply(request.replacements.map { ($0.range, $0.text) }, to: fixture.textView)

    #expect(navigation.pane == .notes)
    #expect(fixture.textView.string == "# B\ntesto di B\n# A\ntesto di A")

    undo.undo()

    #expect(fixture.textView.string == note)
    #expect(!undo.canUndo, "one undo must have consumed the whole section move")
}
