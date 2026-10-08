import Foundation
import Testing
@testable import Pergamenum

// ADR-0084 §D1 (a backlink row says why: the line, a count, a badge), SPEC R-24, plan
// docs/plans/note-workflow-n3.md Task 1.
//
// `BacklinkContext.lines` and `BacklinkRow.make` are pure, so no vault stands behind them. The
// last test is the one that matters most: "a link the index counts" and "a link a row counts"
// are one predicate, `Wikilink.isNoteLink`, and a drift between them would show a backlink row
// whose line the index never believed in.

// MARK: - lines(linking:in:)

@Test func eachLinkToTheTitleGivesOneEntryInSourceOrder() {
    let text = """
    Prima riga con [[Curva]] dentro.
    Una riga senza nulla.
      Terza riga: ancora [[Curva]], indentata.
    """

    #expect(BacklinkContext.lines(linking: "Curva", in: text) == [
        "Prima riga con [[Curva]] dentro.",
        "Terza riga: ancora [[Curva]], indentata.",
    ])
}

@Test func twoLinksOnOneLineGiveTwoEntries() {
    // "One entry per link": the count of a row is the number of links, not of lines.
    let text = "Vedi [[Curva]] e poi di nuovo [[Curva]]."

    #expect(BacklinkContext.lines(linking: "Curva", in: text).count == 2)
}

@Test func anAliasASectionAndANoteEmbedAreLinks() {
    let text = """
    Con alias: [[Curva|la curva]].
    Con sezione: [[Curva#Taratura]].
    Trasclusione: ![[Curva]]
    """

    #expect(BacklinkContext.lines(linking: "Curva", in: text) == [
        "Con alias: [[Curva|la curva]].",
        "Con sezione: [[Curva#Taratura]].",
        "Trasclusione: ![[Curva]]",
    ])
}

@Test func aCanvasLinkAndAFileEmbedAreNotLinksToANote() {
    let text = """
    La board [[Curva.canvas]] non è una nota.
    Il file ![[Curva.png]] nemmeno.
    """

    #expect(BacklinkContext.lines(linking: "Curva", in: text).isEmpty)
    #expect(BacklinkContext.lines(linking: "Curva.canvas", in: text).isEmpty)
}

@Test func aLinkInsideACodeFenceOrAnInlineSpanIsNotALink() {
    let text = """
    ```
    [[Curva]] dentro un blocco di codice
    ```
    E `[[Curva]]` dentro un codice inline.
    Fuori dal codice [[Curva]].
    """

    #expect(BacklinkContext.lines(linking: "Curva", in: text) == ["Fuori dal codice [[Curva]]."])
}

@Test func theTitleIsMatchedWithoutRegardToCase() {
    let text = "Vedi [[curva]] e [[CURVA]]."

    #expect(BacklinkContext.lines(linking: "Curva", in: text).count == 2)
}

@Test func aLinkToAnotherTitleIsNotAnEntry() {
    #expect(BacklinkContext.lines(linking: "Curva", in: "Vedi [[Curvatura]] e [[Altra]].").isEmpty)
}

@Test func theFrontmatterIsNotBodyAndGivesNoEntry() {
    // `related` names the target in the frontmatter, but a *line* is a body line: the badge says
    // «strutturale», the line says what the body says.
    let text = """
    ---
    date: 2026-10-07
    tags:
      - type-note
    related:
      - "[[Curva]]"
    ---

    Corpo senza collegamenti.
    """

    #expect(BacklinkContext.lines(linking: "Curva", in: text).isEmpty)
}

@Test func aNoteThatLinksOnlyThroughRelatedYieldsItsNoteCorrelateBulletLine() {
    let text = """
    ---
    date: 2026-10-07
    tags:
      - type-note
    related:
      - "[[Curva]]"
    ---

    Corpo senza collegamenti.

    ## Note correlate

    - [[Curva]] — fornisce i dati di taratura
    """

    #expect(BacklinkContext.lines(linking: "Curva", in: text) == ["- [[Curva]] — fornisce i dati di taratura"])
}

// MARK: - BacklinkRow.make

@Test func aRowCarriesTheCountTheFirstLineAndThePathOfTheSource() {
    let text = """
    Intro.
    Prima menzione: [[Curva]].
    Seconda menzione: [[Curva|di nuovo]].
    """

    let row = BacklinkRow.make(
        path: "Tecnica/Taratura.md", title: "Taratura", text: text, linking: "Curva", related: []
    )

    #expect(row.path == "Tecnica/Taratura.md")
    #expect(row.id == "Tecnica/Taratura.md")
    #expect(row.title == "Taratura")
    #expect(row.count == 2)
    #expect(row.firstLine == "Prima menzione: [[Curva]].")
    #expect(!row.isStructural)
}

@Test func aRowIsStructuralWhenTheSourcesRelatedNamesTheTarget() {
    let text = "Corpo.\n\n## Note correlate\n\n- [[Curva]] — motivo\n"

    let structural = BacklinkRow.make(
        path: "A.md", title: "A", text: text, linking: "Curva", related: ["\"[[Curva]]\""]
    )
    let other = BacklinkRow.make(
        path: "A.md", title: "A", text: text, linking: "Curva", related: ["\"[[Altra]]\""]
    )

    #expect(structural.isStructural)
    #expect(!other.isStructural, "related che nomina un'altra nota non rende strutturale questo legame")
}

@Test func aRowWithNoLineHasNoFirstLineAndACountOfZero() {
    let row = BacklinkRow.make(
        path: "A.md", title: "A", text: "Corpo senza link.", linking: "Curva", related: []
    )

    #expect(row.count == 0)
    #expect(row.firstLine == nil)
}

@Test func aRelatedOnlyRowCountsItsBulletAsItsContext() {
    let text = "Corpo.\n\n## Note correlate\n\n- [[Curva]] — fornisce i dati\n"

    let row = BacklinkRow.make(
        path: "A.md", title: "A", text: text, linking: "Curva", related: ["\"[[Curva]]\""]
    )

    #expect(row.isStructural)
    #expect(row.count == 1)
    #expect(row.firstLine == "- [[Curva]] — fornisce i dati")
}

// MARK: - One predicate for the index and for a row (ADR-0084 §D1)

/// Every shape the index's old `where` clause told apart: plain, aliased, sectioned, a note
/// embed, a file embed, a `.canvas` link and embed, a remote embed, a note named as a path, and
/// the same in code.
private let agreementCorpus: [String] = [
    "Un [[Nota]], un [[Nota|alias]], un [[Altra#Sezione]] e ![[Trasclusa]].",
    "File: ![[foto.png]], ![[Scheda.pdf]] e ![[audio.m4a]].",
    "Board: [[Q4.canvas]] e ![[Q4.canvas]] non sono note.",
    "Un percorso: ![[Cartella/Percorso.md]] e [[Cartella/Altro.md]].",
    "Remoto: ![[https://esempio.it/immagine.png]].",
    "```\n[[NelCodice]] e ![[NelCodice.png]]\n```\nFuori: [[FuoriDalCodice]].",
    "Inline `[[Inline]]` e [[Esterno]].",
    "Doppio [[Ripetuto]] e ancora [[Ripetuto]] con [[ripetuto]].",
    "Niente link qui.",
]

@Test func theIndexAndARowCountTheSameLinks() {
    for text in agreementCorpus {
        let document = NoteDocument.parse(text)
        let indexed = Set(NoteStore.linkTargets(in: document))
        let counted = Set(WikilinkParser.links(in: document.body).filter(\.isNoteLink).map(\.target))

        #expect(indexed == counted, "l'indice e la riga contano link diversi in: \(text)")
    }

    // Not vacuous: the corpus does hold links the index keeps.
    let all = agreementCorpus.flatMap { NoteStore.linkTargets(in: NoteDocument.parse($0)) }
    #expect(all.contains("Nota"))
    #expect(all.contains("FuoriDalCodice"))
    #expect(!all.contains("Q4.canvas"))
    #expect(!all.contains("foto.png"))
}

/// The index keys a link by `target` (`NoteStore.linkTargets`, `IndexSnapshot.backlinkIndex`), so a
/// bold-wrapped `[[**Curva**]]` is a backlink of `**Curva**` and not of `Curva`: a row counts what
/// the index counts, with no `resolvedTitle` in between.
@Test func aRowComparesTheLinkTargetAsTheIndexKeysItNotTheResolvedTitle() {
    let text = "Con enfasi [[**Curva**]] e senza [[Curva]]."
    let document = NoteDocument.parse(text)

    #expect(NoteStore.linkTargets(in: document) == ["**Curva**", "Curva"])
    #expect(BacklinkContext.lines(linking: "Curva", in: text) == [text], "una sola voce: il link senza enfasi")
    #expect(BacklinkContext.lines(linking: "**Curva**", in: text) == [text])

    let onlyEmphasised = "Solo [[**Curva**]] qui."
    #expect(BacklinkContext.lines(linking: "Curva", in: onlyEmphasised).isEmpty)
    let row = BacklinkRow.make(
        path: "A.md", title: "A", text: onlyEmphasised, linking: "Curva", related: ["[[**Curva**]]"]
    )
    #expect(row.count == 0)
    #expect(!row.isStructural, "anche related si legge per target, come fa IndexSnapshot")
}
