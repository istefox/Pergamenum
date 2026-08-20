import Foundation
import Testing
@testable import Pergamenum

// What `![[…]]` points at, and what a transclusion shows (ADR-0010).
//
// The half worth reading is the classification: the same syntax means a picture or a
// note, and the app got it wrong in one direction for months - every note embed drew
// "file non trovato nel vault", which is PG-020.

// MARK: - Note or file (§D2)

@Test func aTargetWithNoExtensionIsANote() {
    #expect(Transclusion.target(ofLine: "![[Curva di trasmissibilità]]")
        == .note(reference: "Curva di trasmissibilità", section: nil))
}

@Test func aTargetWithAFileExtensionIsAFile() {
    #expect(Transclusion.target(ofLine: "![[foto.png]]") == .file(target: "foto.png", alt: nil))
    #expect(Transclusion.target(ofLine: "![didascalia](schema.pdf)")
        == .file(target: "schema.pdf", alt: "didascalia"))
}

@Test func markdownIsTheOneExtensionThatStillMeansANote() {
    // How a note is named on disk, so this is a note written as a path.
    #expect(Transclusion.target(ofLine: "![[Progetti/Forno.md]]")
        == .note(reference: "Progetti/Forno.md", section: nil))
}

@Test func aDotInATitleDoesNotMakeItAFile() {
    // The rule that a looser "contains a dot" test would get wrong, and it would get it
    // wrong on ordinary Italian titles rather than on something contrived.
    #expect(Transclusion.isNoteReference("Analisi 3.5 mm"))
    #expect(Transclusion.isNoteReference("Riunione del 12.03"))
    #expect(!Transclusion.isNoteReference("misure.csv"))
}

@Test func aSectionIsSplitOffTheReference() {
    #expect(Transclusion.target(ofLine: "![[Prove#Campioni]]")
        == .note(reference: "Prove", section: "Campioni"))
    // The size suffix Obsidian uses is not ours to interpret and is dropped by
    // `Attachment.embed`; what is left still has to classify as a file.
    #expect(Transclusion.target(ofLine: "![[foto.png|300]]") == .file(target: "foto.png", alt: nil))
}

@Test func aRemoteTargetIsNeitherOfTheTwo() {
    // Principle 2: nothing is fetched, so this stays a link for the inline path to draw.
    #expect(Transclusion.target(ofLine: "![[https://example.com/foto.png]]") == nil)
    #expect(Transclusion.target(ofLine: "![x](https://example.com/foto.png)") == nil)
}

@Test func aLineThatIsNotOnlyAnEmbedIsNotATransclusion() {
    // An embed inside a sentence is an illustration in that sentence, and a note unfolded
    // in the middle of one would cut it in two.
    #expect(Transclusion.target(ofLine: "vedi ![[Curva]] per il dettaglio") == nil)
}

// MARK: - What is shown (§D5)

private let note = """
---
date: 2026-08-17
---
# Prove in laboratorio
corpo iniziale

## Campioni
tre campioni

### Durezza
60, 70 e 80 shore

## Strumenti
un fonometro
"""

@Test func aTransclusionWithoutASectionShowsTheBodyWithoutTheFrontmatter() {
    let excerpt = Transclusion.excerpt(of: note, section: nil)
    #expect(excerpt?.hasPrefix("# Prove in laboratorio") == true)
    #expect(excerpt?.contains("date: 2026-08-17") == false)
}

@Test func aSectionCarriesItsSubsectionsAndStopsAtTheNextOfTheSameLevel() {
    // The rule is `NoteFolding`'s, reused rather than re-derived, and this is the case
    // that tells the two apart: `## Campioni` has to take `### Durezza` with it.
    let excerpt = try? #require(Transclusion.excerpt(of: note, section: "Campioni"))
    #expect(excerpt?.hasPrefix("## Campioni") == true)
    #expect(excerpt?.contains("### Durezza") == true)
    #expect(excerpt?.contains("60, 70 e 80 shore") == true)
    #expect(excerpt?.contains("## Strumenti") == false)
    #expect(excerpt?.contains("corpo iniziale") == false)
}

@Test func theLastTranscludedSectionRunsToTheEndOfTheNote() {
    let excerpt = Transclusion.excerpt(of: note, section: "Strumenti")
    #expect(excerpt == "## Strumenti\nun fonometro")
}

@Test func aSectionIsMatchedWithoutCaseAndWithoutSurroundingSpace() {
    #expect(Transclusion.excerpt(of: note, section: "  campioni ")?.hasPrefix("## Campioni") == true)
}

@Test func aSectionThatNoHeadingAnswersToIsNilRatherThanTheWholeNote() {
    // Showing the whole note instead would look exactly like the section having been
    // deleted, which is the worse of the two lies.
    #expect(Transclusion.excerpt(of: note, section: "Conclusioni") == nil)
}

@Test func aHeadingInsideAFenceIsNotASectionToTransclude() {
    // Inherited from `NoteOutline` through `NoteFolding`; asserted here because this is
    // the third feature that would get it wrong on its own.
    let text = """
    # Vero

    ```sh
    # non è un titolo
    perg index
    ```
    """
    #expect(Transclusion.excerpt(of: text, section: "non è un titolo") == nil)
    #expect(Transclusion.excerpt(of: text, section: "Vero")?.contains("perg index") == true)
}

// MARK: - The blocks a note is drawn from

@Test func theParserTellsATranscludedNoteFromAnEmbeddedFile() {
    let blocks = MarkdownBlockParser.blocks(in: "![[Curva]]\n\n![[foto.png]]\n\n![[Prove#Campioni]]")
    #expect(blocks.contains(.transclusion(reference: "Curva", section: nil)))
    #expect(blocks.contains(.embed(target: "foto.png", alt: nil)))
    #expect(blocks.contains(.transclusion(reference: "Prove", section: "Campioni")))
}

// MARK: - The lines the editor decorates

@Test func occurrencesCarryTheReferenceTheSectionAndTheLineOffset() {
    let text = "# Titolo\n\n![[Prove]]\n\n![[Prove#Campioni]]\n"
    let found = Transclusion.occurrences(in: text)
    #expect(found.count == 2)
    #expect(found.first == Transclusion.Occurrence(lineOffset: 10, reference: "Prove", section: nil))
    #expect(found.last?.section == "Campioni")
    // The offset is UTF-16 and has to land on the line's first character, or the editor
    // decorates a line nobody named.
    let ns = text as NSString
    #expect(found.allSatisfy { ns.substring(from: $0.lineOffset).hasPrefix("![[") })
}

@Test func occurrencesCountInUTF16SoAnAccentAboveThemDoesNotShiftThem() {
    // The editor counts in UTF-16 and this vault is written in Italian. Counted in
    // characters, every accented letter above the line would move it one place early.
    let text = "# Perché\ncorpo à è ì\n![[Prove]]\n"
    let found = Transclusion.occurrences(in: text)
    let ns = text as NSString
    #expect(found.count == 1)
    #expect(found.first.map { ns.substring(from: $0.lineOffset).hasPrefix("![[Prove]]") } == true)
}

@Test func aFileEmbedAndAnInlineEmbedAreNotOccurrences() {
    #expect(Transclusion.occurrences(in: "![[foto.png]]\n").isEmpty)
    #expect(Transclusion.occurrences(in: "vedi ![[Prove]] qui\n").isEmpty)
}

@Test func occurrencesSkipFencesAndFrontmatter() {
    let text = """
    ---
    date: 2026-08-17
    related: ["![[Prove]]"]
    ---
    ```md
    ![[Nel fence]]
    ```

    ![[Vera]]
    """
    let found = Transclusion.occurrences(in: text)
    #expect(found.map(\.reference) == ["Vera"])
}

// MARK: - The index (§D7)

@Test func aTranscludedNoteIsALinkAndAnEmbeddedFileIsNot() {
    let text = "vedi [[Altra]]\n\n![[Curva di trasmissibilità]]\n\n![[foto.png]]\n"
    let targets = NoteStore.linkTargets(in: text)
    #expect(targets.contains("Altra"))
    #expect(targets.contains("Curva di trasmissibilità"))
    #expect(!targets.contains("foto.png"))
}

/// The complement of the test above, and the field M11 spent its schema bump on
/// (ADR-0009 §D2): what `linkTargets` leaves out is exactly what `embeddedFiles` takes.
@Test func embeddedFilesTakesTheHalfLinkTargetsLeaves() {
    let text = """
    ---
    date: 2026-08-20
    ---

    ![[Curva di trasmissibilità]]

    ![[foto.png]]

    ![didascalia](allegati/scheda.pdf)

    ![[foto.png]]

    Una riga con ![[inline.png]] dentro una frase.

    ![](https://example.com/remota.png)

    ```
    ![[dentro-il-codice.png]]
    ```
    """
    // In order, once each. The transcluded note is a link and stays out; the inline one
    // is an illustration in a sentence; the remote one is not a file in the vault; the
    // fenced one is code.
    #expect(Transclusion.embeddedFiles(in: text) == ["foto.png", "allegati/scheda.pdf"])
}

@Test func aTranscludedSectionCountsAsALinkToItsNoteOnce() {
    // Two references to the same note, one of them to a section: one link, and the
    // backlink panel says the note is named once rather than twice.
    let targets = NoteStore.linkTargets(in: "![[Prove#Campioni]]\n\n[[Prove]]\n")
    #expect(targets == ["Prove"])
}
