import Foundation
import Testing
@testable import Pergamenum

// The capture exemption (#30) and the harness convention import.
// Split out of ConventionsTests.swift (PG-148, ADR-0051): the file had passed 800 lines across
// eleven MARK sections and no @Suite, so each section moved whole and none was edited.

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
