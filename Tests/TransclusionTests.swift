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

// MARK: - The index (§D7)

@Test func aTranscludedNoteIsALinkAndAnEmbeddedFileIsNot() {
    let text = "vedi [[Altra]]\n\n![[Curva di trasmissibilità]]\n\n![[foto.png]]\n"
    let targets = NoteStore.linkTargets(in: text)
    #expect(targets.contains("Altra"))
    #expect(targets.contains("Curva di trasmissibilità"))
    #expect(!targets.contains("foto.png"))
}

@Test func aTranscludedSectionCountsAsALinkToItsNoteOnce() {
    // Two references to the same note, one of them to a section: one link, and the
    // backlink panel says the note is named once rather than twice.
    let targets = NoteStore.linkTargets(in: "![[Prove#Campioni]]\n\n[[Prove]]\n")
    #expect(targets == ["Prove"])
}
