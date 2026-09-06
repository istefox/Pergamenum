import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 9 -
// R-05; ADR §D6.
//
// `FrontmatterRules.validate`'s exact matching rule for the allowance
// (`^pergamenum-[a-z0-9]+(-[a-z0-9]+)*$`), pinned key by key rather than folded into
// `ConventionsTests.swift`'s single foreign-key test, so a future change to the pattern shows
// exactly which shape broke rather than one test failing for an unstated reason.
//
// Every assertion that depends on the new allowance is red until Task 9's coder writes the
// four-line change at `Frontmatter.swift:335` (doc comment `:5-9` updated in the same task).
// The round-trip test at the bottom is not: the parser and the serializer are untouched by
// this task (ADR §D6), so it is a regression guard confirming that fact, not a red assertion
// - the same "passes trivially and that is expected" shape this chain's other stub-backed
// suites already document (e.g. `Tests/PlaudQuoteTests.swift`).

private func document(withForeignKey line: String) -> NoteDocument {
    NoteDocument.parse("""
    ---
    date: 2026-08-11
    tags:
      - type-note
      - topic-trascrizione
    \(line)
    ---
    corpo
    """)
}

@Test func aLowercasePrefixedKeyIsAllowed() {
    let doc = document(withForeignKey: #"pergamenum-plaud-id: "abc""#)
    #expect(!FrontmatterRules.validate(doc).contains(.foreignKey("pergamenum-plaud-id")))
}

@Test func anyOtherLowercasePrefixedKeyIsAlsoAllowed() {
    // The allowance is the whole namespace, not the three named keys by name (ADR §D6: "a
    // future feature wanting a fourth prefixed key gets it for free from the linter rule").
    let doc = document(withForeignKey: "pergamenum-anything-else: 1")
    #expect(!FrontmatterRules.validate(doc).contains(.foreignKey("pergamenum-anything-else")))
}

@Test func aWrongCasePrefixIsStillAForeignKey() {
    let doc = document(withForeignKey: #"Pergamenum-Plaud-Id: "abc""#)
    #expect(FrontmatterRules.validate(doc).contains(.foreignKey("Pergamenum-Plaud-Id")))
}

@Test func thePrefixAloneWithNoHyphenIsStillAForeignKey() {
    let doc = document(withForeignKey: "pergamenum: true")
    #expect(FrontmatterRules.validate(doc).contains(.foreignKey("pergamenum")))
}

@Test func anUnrelatedForeignKeyIsUnaffectedByTheAllowance() {
    let doc = document(withForeignKey: "obsidian-foo: bar")
    #expect(FrontmatterRules.validate(doc).contains(.foreignKey("obsidian-foo")))
}

@Test func aPrefixedKeyRoundTripsByteForByteThroughParseAndSerialize() {
    // Not red: the parser (`Frontmatter.swift:206-208`) and the serializer (`:299-301`)
    // already preserve and rewrite any foreign key verbatim, prefixed or not - this task
    // changes only the linter's verdict at `:335`.
    let original = """
    ---
    date: 2026-08-11
    tags:
      - type-note
      - topic-trascrizione
    pergamenum-plaud-id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
    pergamenum-plaud-recorded-at: "2026-09-04T11:48:07"
    pergamenum-plaud-duration-ms: 1236000
    ---
    corpo
    """
    let doc = NoteDocument.parse(original)
    #expect(doc.serialized() == original)
}
