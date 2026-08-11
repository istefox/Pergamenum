import Foundation
import Testing
@testable import Pergamenum

// MARK: - Tags

@Test(arguments: [
    "type-note",
    "topic-vibration-isolation",
    "client-acmespa",
    "project-pergamenum",
    "status-inbox",
    "source-web",
    "area-quality",
    "competitor-someone",
    "topic-en1090",
])
func acceptsWellFormedTags(_ raw: String) {
    #expect(Tag(raw)?.description == raw)
}

@Test(arguments: [
    "note",                      // no namespace
    "type/note",                 // nested form, removed by SPEC §4.4
    "Type-note",                 // uppercase namespace
    "type-Note",                 // uppercase value
    "type-",                     // empty value
    "type--note",                // doubled hyphen
    "type-note-",                // trailing hyphen
    "unknown-value",             // namespace not in T-01
    "type-note con spazio",
])
func rejectsMalformedTags(_ raw: String) {
    #expect(Tag(raw) == nil)
}

@Test func acceptsInlineHashForm() {
    // tag.md 5.3 allows `#client-acmespa` in the body, same tag as in frontmatter.
    #expect(Tag("#client-acmespa") == Tag("client-acmespa"))
}

@Test func ordersTagsByNamespaceThenAlphabetically() {
    let tags = ["topic-zeta", "type-note", "client-beta", "topic-alfa", "client-alfa"]
        .compactMap(Tag.init)
    #expect(TagRules.ordered(tags).map(\.description) == [
        "client-alfa", "client-beta", "type-note", "topic-alfa", "topic-zeta",
    ])
}

@Test func reportsMoreThanSevenTags() {
    let tags = (1...8).compactMap { Tag("topic-t\($0)") } + [Tag("type-note")!]
    let violations = TagRules.validate(tags, category: .note, vocabulary: .empty)
    #expect(violations.contains { if case .tooMany = $0 { true } else { false } })
}

@Test func reportsMoreThanOneStatus() {
    let tags = [Tag("type-note")!, Tag("topic-x")!, Tag("status-inbox")!, Tag("status-done")!]
    let violations = TagRules.validate(tags, category: .capture, vocabulary: .empty)
    #expect(violations.contains { if case .multipleStatus = $0 { true } else { false } })
}

@Test(arguments: ["topic-2026", "topic-2026-08", "topic-2026-08-11", "topic-20260811"])
func reportsDateTags(_ raw: String) {
    let tag = Tag(raw)!
    let violations = TagRules.validate([tag], category: .daily, vocabulary: .empty)
    #expect(violations.contains(.dateTag(tag)))
}

@Test func doesNotMistakeAnOrdinaryNumberForADate() {
    // A material grade, not a year: the heuristic must not fire on it.
    let tag = Tag("topic-4140")!
    let violations = TagRules.validate([tag], category: .daily, vocabulary: .empty)
    #expect(!violations.contains(.dateTag(tag)))
}

@Test func ordinaryNoteNeedsTypeNoteAndATopic() {
    let violations = TagRules.validate([Tag("client-acme")!], category: .note, vocabulary: .empty)
    #expect(violations.contains(.missingRequiredTag("type-note")))
    #expect(violations.contains(.missingRequiredTag("topic-*")))
}

@Test func dailyNoteNeedsOnlyTypeNote() {
    // A real vocabulary, because with an empty one `type-note` is correctly reported
    // as unverifiable and the absence of *other* violations would be untestable.
    let vocabulary = Vocabulary(type: ["note"], status: [], area: [], source: [], deliverableKind: [])
    let violations = TagRules.validate([Tag("type-note")!], category: .daily, vocabulary: vocabulary)
    #expect(violations.isEmpty)
}

@Test func reportsClosedFamilyValueOutsideTheVocabulary() {
    let vocabulary = Vocabulary(
        type: ["note"], status: ["inbox"], area: [], source: [], deliverableKind: []
    )
    let stray = Tag("type-inventato")!
    let violations = TagRules.validate(
        [Tag("type-note")!, Tag("topic-x")!, stray], category: .note, vocabulary: vocabulary
    )
    #expect(violations.contains(.notInVocabulary(stray)))
}

@Test func reportsRatherThanPassesWhenTheVocabularyIsEmpty() {
    // An unrun check is not a clean result: with no table imported, a closed-family
    // value must be flagged as unverifiable rather than silently accepted.
    let violations = TagRules.validate(
        [Tag("type-note")!, Tag("topic-x")!], category: .note, vocabulary: .empty
    )
    #expect(violations.contains(.vocabularyUnavailable(.type)))
}

// MARK: - Calendar dates

@Test func parsesAndRendersIsoDates() {
    let date = CalendarDate(iso: "2026-08-11")
    #expect(date?.description == "2026-08-11")
    #expect(date?.compactForm == "20260811")
}

@Test(arguments: ["2026-8-11", "2026/08/11", "26-08-11", "2026-13-01", "2026-02-30", "2026-08-11T10:00"])
func rejectsNonIsoDates(_ raw: String) {
    #expect(CalendarDate(iso: raw) == nil)
}

@Test func acceptsLeapDayOnlyInLeapYears() {
    #expect(CalendarDate(iso: "2024-02-29") != nil)
    #expect(CalendarDate(iso: "2026-02-29") == nil)
    #expect(CalendarDate(iso: "2100-02-29") == nil)
    #expect(CalendarDate(iso: "2000-02-29") != nil)
}

// MARK: - Frontmatter

private let conformantNote = """
---
date: 2026-08-11
tags:
  - type-note
  - topic-vibration-isolation
related:
  - "[[Curva di trasmissibilità]]"
aliases:
  - Trasmissibilita
---

Il corpo della nota.

## Note correlate

- [[Curva di trasmissibilità]] — fornisce i dati sperimentali
"""

@Test func parsesAConformantNote() {
    let document = NoteDocument.parse(conformantNote)
    #expect(document.hasFrontmatterBlock)
    #expect(document.frontmatter.date == CalendarDate(iso: "2026-08-11"))
    #expect(document.frontmatter.tags.map(\.description) == ["type-note", "topic-vibration-isolation"])
    #expect(document.frontmatter.related == ["[[Curva di trasmissibilità]]"])
    #expect(document.frontmatter.aliases == ["Trasmissibilita"])
    #expect(document.frontmatter.foreignKeys.isEmpty)
    #expect(document.body.contains("Il corpo della nota."))
    #expect(FrontmatterRules.validate(document).isEmpty)
}

@Test func roundTripsWithoutChangingTheFile() {
    // The load-bearing property of the whole vault layer: opening a conformant note
    // and writing it back must produce the same bytes, or every note the user merely
    // looks at drifts.
    let document = NoteDocument.parse(conformantNote)
    #expect(document.serialized() == conformantNote)
}

@Test func preservesForeignKeysInsteadOfDroppingThem() {
    let note = """
    ---
    date: 2026-08-11
    tags:
      - type-note
      - topic-x
    cssclass: wide
    ---
    corpo
    """
    let document = NoteDocument.parse(note)
    #expect(document.frontmatter.foreignKeys.map(\.name) == ["cssclass"])
    #expect(FrontmatterRules.validate(document).contains(.foreignKey("cssclass")))
    // Reported, and still present after a save: F-02 makes it a non-conformity, not
    // a licence to delete something the user wrote.
    #expect(document.serialized().contains("cssclass: wide"))
}

@Test func reordersTagsOnSave() {
    let note = """
    ---
    date: 2026-08-11
    tags:
      - topic-zeta
      - type-note
      - client-alfa
    ---
    corpo
    """
    let saved = NoteDocument.parse(note).serialized()
    let tagBlock = saved.components(separatedBy: "\n").filter { $0.hasPrefix("  - ") }
    #expect(tagBlock == ["  - client-alfa", "  - type-note", "  - topic-zeta"])
}

@Test func reportsTheInlineTagListForm() {
    let note = """
    ---
    date: 2026-08-11
    tags: [type-note, topic-x]
    ---
    corpo
    """
    let document = NoteDocument.parse(note)
    #expect(document.frontmatter.tags.count == 2)
    #expect(FrontmatterRules.validate(document).contains(.inlineTagList))
}

@Test func omitsEmptyOptionalKeys() {
    // F-08: an optional key with no value is omitted, never written as `[]`.
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = [Tag("type-note")!]
    let rendered = FrontmatterSerializer.render(frontmatter)
    #expect(!rendered.contains("related"))
    #expect(!rendered.contains("aliases"))
    #expect(!rendered.contains("[]"))
}

@Test func treatsAFileWithoutFrontmatterAsAllBody() {
    let document = NoteDocument.parse("# Titolo\n\ntesto")
    #expect(!document.hasFrontmatterBlock)
    #expect(document.body == "# Titolo\n\ntesto")
    #expect(FrontmatterRules.validate(document) == [.missingBlock])
}

@Test func doesNotSwallowTheFileWhenTheBlockIsUnterminated() {
    // An opening delimiter with no closing one must not eat the note.
    let document = NoteDocument.parse("---\ndate: 2026-08-11\ntesto che continua")
    #expect(!document.hasFrontmatterBlock)
    #expect(document.body.contains("testo che continua"))
}

// MARK: - Wikilinks

@Test func parsesEveryWikilinkForm() {
    let body = "Vedi [[Nota semplice]], [[Nota#Sezione]], [[Nota|testo]] e ![[schema.pdf]]."
    let links = WikilinkParser.links(in: body)

    #expect(links.map(\.target) == ["Nota semplice", "Nota", "Nota", "schema.pdf"])
    #expect(links[1].section == "Sezione")
    #expect(links[2].displayText == "testo")
    #expect(links[3].isEmbed)
    #expect(!links[0].isEmbed)
}

@Test func splitsSectionAndDisplayTextTogether() {
    let links = WikilinkParser.links(in: "[[Nota#Sezione|testo]]")
    #expect(links.count == 1)
    #expect(links[0].target == "Nota")
    #expect(links[0].section == "Sezione")
    #expect(links[0].displayText == "testo")
}

@Test func ignoresEmptyAndUnbalancedLinks() {
    #expect(WikilinkParser.links(in: "[[]] e [[   ]]").isEmpty)
    #expect(WikilinkParser.links(in: "[[non chiuso").isEmpty)
}

@Test func findsTheInnerLinkWhenBracketsNest() {
    let links = WikilinkParser.links(in: "testo [[a [[b]] coda")
    #expect(links.map(\.target) == ["b"])
}

@Test func rendersBackToSource() {
    for source in ["[[Nota]]", "[[Nota#Sezione]]", "[[Nota|testo]]", "![[file.pdf]]"] {
        #expect(WikilinkParser.links(in: source).first?.rendered == source)
    }
}

// MARK: - Related section

@Test func readsStructuralLinksWithTheirReasons() {
    let links = RelatedSection.parse(from: """
    ## Note correlate

    - [[Curva di trasmissibilità]] — fornisce i dati sperimentali
    - [[Scelta del supporto]] - applica il criterio

    ## Altra sezione

    - [[Non conta]] — fuori sezione
    """)
    #expect(links.count == 2)
    #expect(links[0] == StructuralLink(target: "Curva di trasmissibilità", reason: "fornisce i dati sperimentali"))
    // A plain hyphen is accepted as the separator too: a note typed by hand will have
    // whichever dash the keyboard produced.
    #expect(links[1].reason == "applica il criterio")
}

@Test func detectsRelatedAndSectionDisagreeing() {
    let result = RelatedSection.discrepancies(
        frontmatterRelated: ["\"[[A]]\"", "\"[[B]]\""],
        sectionLinks: [StructuralLink(target: "B", reason: "motivo"), StructuralLink(target: "C", reason: "motivo")]
    )
    #expect(result.missingInSection == ["A"])
    #expect(result.missingInFrontmatter == ["C"])
}

@Test func acceptsRelatedAndSectionInAgreement() {
    let document = NoteDocument.parse(conformantNote)
    let result = RelatedSection.discrepancies(
        frontmatterRelated: document.frontmatter.related,
        sectionLinks: RelatedSection.parse(from: document.body)
    )
    #expect(result.missingInSection.isEmpty)
    #expect(result.missingInFrontmatter.isEmpty)
}

// MARK: - Note names

@Test(arguments: ["Nota/sbagliata", "Nota:sbagliata", "Nota#sbagliata", "Nota[1]", "Nota|alt"])
func rejectsForbiddenCharactersInTitles(_ title: String) {
    #expect(NoteName.validate(title).contains { if case .containsForbiddenCharacter = $0 { true } else { false } })
}

@Test func rejectsOverlongTitles() {
    let title = String(repeating: "a", count: 61)
    #expect(NoteName.validate(title).contains(.tooLong(count: 61)))
    #expect(NoteName.validate(String(repeating: "a", count: 60)).isEmpty)
}

@Test(arguments: ["Relazione di calcolo v2", "Relazione_v10", "Relazione-V3"])
func rejectsVersionSuffixes(_ title: String) {
    #expect(NoteName.validate(title).contains { if case .hasVersionSuffix = $0 { true } else { false } })
}

@Test func acceptsTitlesWithAccentsAndSpaces() {
    #expect(NoteName.validate("Trasmissibilità e rapporto di frequenza").isEmpty)
}

@Test func acceptsAWordThatMerelyStartsWithV() {
    // "v" followed by digits is a version; "vibrazioni" is not.
    #expect(NoteName.validate("Analisi delle vibrazioni").isEmpty)
}

@Test func requiresTheCompactFormForDailyNotes() {
    #expect(NoteName.validateDaily("20260811").isEmpty)
    #expect(!NoteName.validateDaily("2026-08-11").isEmpty)
}

@Test func sanitizesArbitraryTextIntoAUsableTitle() {
    let sanitized = NoteName.sanitized("  Offerta: supporti [rev 2] / EMEA  ")
    #expect(!sanitized.contains(where: NoteName.forbiddenCharacters.contains))
    #expect(sanitized == sanitized.trimmingCharacters(in: .whitespaces))
}

@Test func classifiesDailyNotesByFolder() {
    #expect(NoteName.category(forFileName: "20260811.md", dailyFolder: "Calendar", path: "Calendar/20260811.md") == .daily)
    // Same name outside the daily folder is an event note, not a daily note.
    #expect(NoteName.category(forFileName: "20260811.md", dailyFolder: "Calendar", path: "01 Progetti/20260811.md") == .note)
    #expect(NoteName.category(forFileName: "Titolo.md", dailyFolder: "Calendar", path: "Titolo.md") == .note)
}

// MARK: - Harness convention import

/// Mirrors the real document shape: numbered heading, prose, then a markdown table
/// whose first column carries the full tag.
private let tagDocumentFixture = """
### 4.3 Formazione dei tag project (famiglia aperta)

Testo che non contiene tabelle.

### 4.4 Vocabolario chiuso: type

La colonna "Tipo nel nome file" e la mappa vincolante verso naming.md.

| Tag | Contenuto | Tipo nel nome file |
|---|---|---|
| type-offer | offerta tecnico-commerciale | Offerta |
| type-report | relazione tecnica | Relazione, Scheda |
| type-note | nota di conoscenza | (naming.md 4.6) |

### 4.5 Formazione dei tag topic (famiglia aperta)

Seed list: `topic-acoustics`.

### 4.6 Vocabolario chiuso: status

| Tag | Significato | Transizioni ammesse |
|---|---|---|
| status-inbox | acquisito | verso active o archived |
| status-active | in lavorazione | verso waiting |

### 4.7 Vocabolario chiuso: area

| Tag | Copre |
|---|---|
| area-engineering | calcoli |

### 4.8 Vocabolario chiuso: source

| Tag | Copre |
|---|---|
| source-email | arrivato via email |
"""

private let namingDocumentFixture = """
### 6.1 Tipo deliverable (categoria 4.1)

| Tipo | Uso |
|---|---|
| Offerta | offerta tecnico-commerciale |
| Relazione | relazione tecnica finale |

### 6.2 Tipo documento tecnico di terzi
"""

@Test func importsTheClosedVocabulariesFromTheConventionDocuments() {
    let result = HarnessImporter.parse(
        tagDocument: tagDocumentFixture, namingDocument: namingDocumentFixture
    )
    #expect(result.problems.isEmpty, "\(result.problems)")
    #expect(result.vocabulary.type == ["offer", "report", "note"])
    #expect(result.vocabulary.status == ["inbox", "active"])
    #expect(result.vocabulary.area == ["engineering"])
    #expect(result.vocabulary.source == ["email"])
    #expect(result.vocabulary.deliverableKind == ["Offerta", "Relazione"])
}

@Test func doesNotBorrowTheNextSectionsTableWhenOneIsMissing() {
    // A section whose table was deleted must fail loudly. Silently taking the next
    // table would populate `status` with type values and then reject valid tags.
    let truncated = """
    ### 4.6 Vocabolario chiuso: status

    Tabella temporaneamente rimossa.

    ### 4.7 Vocabolario chiuso: area

    | Tag | Copre |
    |---|---|
    | area-engineering | calcoli |
    """
    let result = HarnessImporter.parse(tagDocument: truncated, namingDocument: "")
    #expect(result.vocabulary.status.isEmpty)
    #expect(result.problems.contains { $0.contains("4.6") })
    #expect(result.vocabulary.area == ["engineering"])
}

@Test func reportsEverySectionItCouldNotFind() {
    let result = HarnessImporter.parse(tagDocument: "", namingDocument: "")
    #expect(result.problems.count == 5)
    #expect(result.vocabulary.isEmpty)
}

@Test func ignoresRowsThatDoNotCarryTheExpectedNamespace() {
    let mixed = """
    ### 4.7 Vocabolario chiuso: area

    | Tag | Copre |
    |---|---|
    | area-engineering | calcoli |
    | note-a-margine | riga che non e un tag area |
    """
    let result = HarnessImporter.parse(tagDocument: mixed, namingDocument: "")
    #expect(result.vocabulary.area == ["engineering"])
}

@Test func bundledVocabularyMatchesTheReplicatedTables() throws {
    let url = try #require(
        Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
            ?? Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json", subdirectory: "Resources"),
        "vocabolari.json is not in the bundle"
    )
    let vocabulary = try JSONDecoder().decode(Vocabulary.self, from: try Data(contentsOf: url))

    #expect(vocabulary.type.contains("note"))
    #expect(vocabulary.type.count == 20)
    #expect(vocabulary.status == ["inbox", "active", "waiting", "final", "archived"])
    #expect(vocabulary.area.count == 7)
    #expect(vocabulary.source.count == 5)
    #expect(vocabulary.deliverableKind.contains("Offerta"))
}

// MARK: - Code is not a wikilink

@Test func ignoresBashTestSyntaxInAFencedBlock() {
    // Observed on the real Labs vault: `[[ ... ]]` is bash's test syntax, and every
    // shell snippet was filling the unresolved-links panel.
    let note = """
    Prima del blocco.

    ```bash
    if [[ "${esiti[*]}" == "0 0 0" ]]; then
      echo ok
    fi
    ```

    Dopo il blocco, un vero [[Collegamento]].
    """
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Collegamento"])
}

@Test func ignoresTomlArrayOfTablesInAFencedBlock() {
    let note = """
    ```toml
    [[tool.mypy.overrides]]
    module = "x"
    ```
    """
    #expect(WikilinkParser.links(in: note).isEmpty)
}

@Test func ignoresInlineCodeSpans() {
    #expect(WikilinkParser.links(in: "usa `[[ -f file ]]` nel test").isEmpty)
    #expect(WikilinkParser.links(in: "`codice` e poi [[Vero link]]").map(\.target) == ["Vero link"])
}

@Test func treatsAnUnterminatedFenceAsRunningToTheEnd() {
    // The reader sees everything after the fence as code, so the parser must agree.
    let note = "testo\n\n```\n[[non un link]]\n"
    #expect(WikilinkParser.links(in: note).isEmpty)
}

@Test func stillFindsLinksAroundCode() {
    let note = """
    [[Uno]] prima.

    ```
    [[dentro]]
    ```

    [[Due]] dopo.
    """
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Uno", "Due"])
}

@Test func doesNotCloseAFenceOnALineCarryingAnInfoString() {
    // Only the opening fence may carry text after the backticks; treating a
    // "``` qualcosa" line as a close would end the block early and expose its tail.
    let note = "```\n[[dentro]]\n``` non chiude\n[[ancora dentro]]\n```\n[[fuori]]"
    #expect(WikilinkParser.links(in: note).map(\.target) == ["fuori"])
}

@Test func inlineSpanMaskingSurvivesAFenceEarlierInTheNote() {
    // Regression from the real Labs vault: pairing backticks across the whole text
    // desynchronised on the three of each fence, so an inline span further down was
    // no longer recognised and `[[tool.mypy.overrides]]` was indexed as a link.
    let note = """
    ```python
    print("x")
    ```

    Attivalo per modulo con `[[tool.mypy.overrides]]` ed elenca i moduli.

    Un vero [[Collegamento]] resta tale.
    """
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Collegamento"])
}

@Test func doesNotPairBackticksAcrossLines() {
    // An unclosed span must not swallow the next line's real link.
    let note = "riga con ` aperto\n[[Vero]]"
    #expect(WikilinkParser.links(in: note).map(\.target) == ["Vero"])
}
