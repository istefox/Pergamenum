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

// MARK: - The capture exemption (#30)

/// The category is what a file name and a path can say; `status-inbox` is what the note
/// itself says. The topic exemption of SPEC §4.7 hangs on the second, because the linter
/// only ever has the first and it never spells `.capture`.
private let inboxVocabulary = Vocabulary(
    type: ["note"], status: ["inbox"], area: [], source: [], deliverableKind: []
)

@Test func aNoteMarkedInboxDoesNotNeedATopicYet() {
    let tags = [Tag("type-note")!, Tag("status-inbox")!]
    // Judged as `.note`, which is the only thing `NoteName.category` can return for
    // `00 Inbox/Capture.md` - and still conformant.
    let violations = TagRules.validate(tags, category: .note, vocabulary: inboxVocabulary)
    #expect(violations.isEmpty, "\(violations)")
}

@Test func aNoteMarkedInboxStillNeedsTypeNote() {
    // The exemption is about the subject, not about the kind: a capture is still a note.
    let violations = TagRules.validate(
        [Tag("status-inbox")!], category: .note, vocabulary: inboxVocabulary
    )
    #expect(violations.contains(.missingRequiredTag("type-note")))
    #expect(!violations.contains(.missingRequiredTag("topic-*")))
}

@Test func anOrdinaryNoteWithoutTheInboxTagStillNeedsATopic() {
    // The negative control: without `status-inbox` nothing changed.
    let violations = TagRules.validate(
        [Tag("type-note")!], category: .note, vocabulary: inboxVocabulary
    )
    #expect(violations.contains(.missingRequiredTag("topic-*")))
}

@Test func filingACaptureUnderATopicKeepsItConformant() {
    let tags = [Tag("type-note")!, Tag("topic-acustica")!, Tag("status-inbox")!]
    let violations = TagRules.validate(tags, category: .note, vocabulary: inboxVocabulary)
    #expect(violations.isEmpty, "\(violations)")
}

@Test func aCategoryKnowsWhichTagsItsNotesAreBornWith() {
    // One rule, read by `createNote` and by the inbox template both. They used to write
    // the same set out separately, which is how the app came to generate a file its own
    // linter flagged.
    #expect(TagRules.initialTags(for: .capture).map(\.description) == ["type-note", "status-inbox"])
    #expect(TagRules.initialTags(for: .daily).map(\.description) == ["type-note"])
    #expect(TagRules.initialTags(for: .note, topics: [Tag("topic-acustica")!]).map(\.description)
        == ["type-note", "topic-acustica"])
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

// MARK: - Recording note titles (ADR-0032 §D5, plan Task 4, R-05)
//
// `ImportNaming.recordingNoteTitle(recordedAt:name:)` is additive (this file compiles
// into `perg` and `pergamenum-mcp` too, Foundation-only). Its production body is a
// tester-declared stub (see `ImportNaming.swift`) - every test below is red until the
// coder implements the four rules the ADR names.

@Test func derivesATitleFromAColonBearingHumanNameWithNoForbiddenCharacters() throws {
    // Measured live on 2026-09-05 (ADR-0032 M1): a recording's `name` can be a long
    // human title with a colon in it, neither of which `NoteName` accepts as-is.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let name = "09-04 Riunione: Preparazione revisione trimestrale con cliente - Diagramma di Flusso Componenti"

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: name)

    #expect(title.hasPrefix("20260904_Registrazione_"))
    #expect(NoteName.validate(title).isEmpty, "\(NoteName.validate(title))")
}

@Test func derivesATitleFromTheOldTimestampFormName() throws {
    // Measured live (ADR-0032 M1): one recording still carries `name` as the raw
    // timestamp the SPEC originally documented for all of them.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:44:51"))
    let name = "2026-09-04 13:44:51"

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: name)

    #expect(title.hasPrefix("20260904_Registrazione_"))
    #expect(NoteName.validate(title).isEmpty, "\(NoteName.validate(title))")
}

@Test func dropsALeadingDateLikeTokenBeforeSlugging() throws {
    // ADR §D5 rule 1: six of eight measured names begin `09-04 ` or `2026-09-04 `, and
    // leaving it in would slug the date twice. Stripping it means the title is the same
    // whether or not the recording's own name repeats the day it was recorded on.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let bare = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: "Sopralluogo linea 4")
    let withShortToken = ImportNaming.recordingNoteTitle(
        recordedAt: recordedAt, name: "09-04 Sopralluogo linea 4"
    )
    let withLongToken = ImportNaming.recordingNoteTitle(
        recordedAt: recordedAt, name: "2026-09-04 Sopralluogo linea 4"
    )

    #expect(bare == withShortToken)
    #expect(bare == withLongToken)
    #expect(!bare.contains("09-04"))
}

@Test func truncatesTheSlugAtAWordBoundaryWithNoTrailingHyphen() throws {
    // ADR §D5 rule 2: `NoteName.maximumLength` is 60 and a measured name reaches 79 (in
    // fact the file this was measured against is a good deal longer once slugged), so the
    // slug must be cut at a whole word, never mid-word, and never leave a trailing `-`.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-09-04T11:48:07"))
    let name = "Argomento molto lungo che supera abbondantemente il limite di sessanta caratteri per il titolo della nota di registrazione di oggi"

    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: name)

    #expect(title.count <= NoteName.maximumLength)
    #expect(!title.hasSuffix("-"))

    let prefix = "20260904_Registrazione_"
    guard title.hasPrefix(prefix) else {
        Issue.record("title \(title) does not start with the derived date prefix")
        return
    }
    let slug = title.dropFirst(prefix.count)
    let sourceWords = Set(ImportNaming.kebabCase(name, maximumWords: 999).split(separator: "-"))
    for word in slug.split(separator: "-") {
        #expect(sourceWords.contains(word), "\"\(word)\" is not a whole word from the source name")
    }
}

@Test func usesTheRecordingsOwnLocalDateNotTodays() throws {
    // ADR §D5 rule 4: a recording imported a week later is filed under the day it
    // happened, not the day somebody pressed "Elabora". The expected prefix is computed
    // from the same `CalendarDate(_:in:)` the production code has to use, rather than a
    // hardcoded literal, so this test is not itself timezone-dependent.
    let recordedAt = try #require(PlaudTimestamp.parse("2026-08-11T09:00:00"))
    let localDate = CalendarDate(recordedAt, in: .current)
    let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: "Nota di prova")
    #expect(title.hasPrefix("\(localDate.compactForm)_Registrazione_"))
    // And distinct from "today" (this suite is not run on 2026-08-11 itself).
    #expect(localDate != .today)
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

// MARK: - Editor edits

@Test func wrapsASelectionInAMarkdownLinkWhenAURLIsPasted() {
    #expect(EditorEdits.markdownLink(pasting: "https://vibrofer.it", over: "il sito")
        == "[il sito](https://vibrofer.it)")
    // Other schemes count too: the vault links out to Obsidian, DEVONthink and Mail.
    #expect(EditorEdits.markdownLink(pasting: "message://%3Cabc%3E", over: "la mail")
        == "[la mail](message://%3Cabc%3E)")
}

@Test func leavesAnOrdinaryPasteAlone() {
    // Nothing selected, or the pasted text is not a URL: a normal paste.
    #expect(EditorEdits.markdownLink(pasting: "https://vibrofer.it", over: "") == nil)
    #expect(EditorEdits.markdownLink(pasting: "testo normale", over: "selezione") == nil)
    // A bare host is more likely text than a link, and guessing rewrites what was typed.
    #expect(EditorEdits.markdownLink(pasting: "vibrofer.it", over: "selezione") == nil)
}

@Test func buildsAnEmbedFromAFileName() {
    // The name, not the path: a wikilink resolves by name, and a path breaks as soon
    // as the file is moved inside the app.
    #expect(EditorEdits.embed(forFileNamed: "schema.pdf") == "![[schema.pdf]]")
}

@Test(arguments: ["https://x.test", "obsidian://open?vault=Labs", "message://%3Ca%3E", "pergamenum://today"])
func recognisesURLs(_ text: String) {
    #expect(EditorEdits.isURL(text))
}

@Test(arguments: ["", "testo", "vibrofer.it", "https://"])
func rejectsWhatIsNotAURL(_ text: String) {
    #expect(!EditorEdits.isURL(text))
}

@Test func theVocabularyFileKeepsItsCommentThroughARoundTrip() throws {
    // The shipped file carries a `_comment` saying harness-system owns these tables.
    // The importer wrote only the five tables, so the first real import deleted the one
    // sentence telling the reader not to hand-edit the file they were looking at.
    var vocabulary = Vocabulary(
        type: ["note"], status: ["draft"], area: ["training"],
        source: ["web"], deliverableKind: ["report"]
    )
    vocabulary.note = "Replica: re-import rather than editing."

    let data = try JSONEncoder().encode(vocabulary)
    let asText = try #require(String(data: data, encoding: .utf8))
    // Written under the key the file has always used, not under "note".
    #expect(asText.contains("\"_comment\""))
    #expect(try JSONDecoder().decode(Vocabulary.self, from: data) == vocabulary)
}

@Test func aVocabularyFileWithNoCommentStillReads() throws {
    // Every vault written before the comment existed.
    let json = Data("""
    {"type":["note"],"status":[],"area":[],"source":[],"deliverableKind":[]}
    """.utf8)
    let decoded = try JSONDecoder().decode(Vocabulary.self, from: json)
    #expect(decoded.note == nil)
    #expect(decoded.type == ["note"])
}
