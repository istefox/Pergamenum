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

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 9 -
// R-05; ADR §D6. Added beside `preservesForeignKeysInsteadOfDroppingThem` rather than
// replacing it, per the plan's own instruction: an ordinary foreign key must still be
// reported, only a `pergamenum-`-prefixed one stops being one.
//
// `FrontmatterRules.validate` (`Frontmatter.swift:335`) does not yet special-case the
// prefix, so this is red until Task 9's coder adds the four-line allowance. The Task 4
// linter assertion (`Tests/TranscriptNoteTests.swift`, "The linter (D6/D7, Task 9)") turns
// green at the same time - confirm it there, it is not duplicated here.
@Test func aPergamenumPrefixedForeignKeyProducesNoFinding() {
    let note = """
    ---
    date: 2026-08-11
    tags:
      - type-note
      - topic-trascrizione
    pergamenum-plaud-id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
    ---
    corpo
    """
    let document = NoteDocument.parse(note)
    #expect(document.frontmatter.foreignKeys.map(\.name) == ["pergamenum-plaud-id"])
    #expect(!FrontmatterRules.validate(document).contains(.foreignKey("pergamenum-plaud-id")))
    // Still preserved verbatim - the parser and the serializer are not touched, only the
    // linter's opinion of the key (ADR §D6: "the change is four lines in one function").
    #expect(document.serialized().contains(#"pergamenum-plaud-id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6""#))
}

// ADR-0065 §D1.6 (gate G2): this used to be `reordersTagsOnSave`, which pinned a re-sort of
// an untouched tags key on every save - exactly the unasked diff R-01 forbids. The canonical
// order still applies whenever the app writes the tags key; its counterpart,
// `anUnchangedTagsKeyKeepsItsSourceOrder`, lives in `FrontmatterRoundTripTests`.
@Test func reordersTagsWhenTheTagsKeyIsWritten() throws {
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
    var document = NoteDocument.parse(note)
    document.frontmatter.tags.append(try #require(Tag("topic-alfa")))
    let saved = document.serialized()
    let tagBlock = saved.components(separatedBy: "\n").filter { $0.hasPrefix("  - ") }
    #expect(tagBlock == ["  - client-alfa", "  - type-note", "  - topic-alfa", "  - topic-zeta"])
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
