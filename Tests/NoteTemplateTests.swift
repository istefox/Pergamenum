import Foundation
import Testing
@testable import Pergamenum

// The templates half of M9 (ADR-0011 D5-D7): what a template contributes to a new note,
// and what `createNote` writes with and without one.

// MARK: - Che cosa un template porta con sé

private let templateWithFrontmatter = """
---
date: 2026-01-01
tags:
  - type-note
---

# {{title}}

Data: {{date}}

## Presenti
"""

@Test func theTemplatesOwnFrontmatterIsDroppedAndTheRestKeptVerbatim() {
    let body = NoteTemplate.body(of: templateWithFrontmatter)

    #expect(body == "# {{title}}\n\nData: {{date}}\n\n## Presenti")
    // The date and the tag belong to the template, not to what is being written. The new
    // note gets its own block from `createNote`, so neither may survive this call.
    #expect(!body.contains("2026-01-01"))
    #expect(!body.contains("type-note"))
}

@Test func aTemplateWithNoFrontmatterBlockContributesItsWholeText() {
    #expect(NoteTemplate.body(of: "# Solo testo\n\nNiente blocco.")
        == "# Solo testo\n\nNiente blocco.")
}

@Test func leadingBlankLinesAreTrimmedSoTheNoteDoesNotOpenWithTwo() {
    // `createNote` supplies the single separating newline itself; without this trim a
    // template whose body began after a blank line would produce two.
    #expect(NoteTemplate.body(of: "---\ndate: 2026-01-01\n---\n\n\n\n# Titolo")
        == "# Titolo")
}

@Test func isTemplateRecognisesTheFolderAndNothingThatMerelyStartsLikeIt() {
    #expect(NoteTemplate.isTemplate("Templates/Riunione.md"))
    #expect(NoteTemplate.isTemplate("Templates/Sotto/Riunione.md"))
    #expect(!NoteTemplate.isTemplate("Riunione.md"))
    #expect(!NoteTemplate.isTemplate("01 Progetti/Riunione.md"))
    // The negative control that matters: a sibling folder whose name merely begins with
    // the reserved one is not reserved.
    #expect(!NoteTemplate.isTemplate("TemplatesVecchi/Riunione.md"))
}

// MARK: - I due segnaposto

// Force-unwrapped at file scope, the same way `CalendarTests` and `DateEntryTests`
// already do it: a literal that will not parse is a broken test file, not a runtime case.
private let sampleDate = CalendarDate(iso: "2026-08-18")!

@Test func bothPlaceholdersAreSubstituted() {
    let result = NoteTemplate.substituting(
        title: "Riunione con Rossi", date: sampleDate, in: "# {{title}}\n\nData: {{date}}"
    )

    #expect(result == "# Riunione con Rossi\n\nData: 2026-08-18")
}

@Test func eachPlaceholderSubstitutesOnItsOwn() {
    #expect(NoteTemplate.substituting(title: "T", date: sampleDate, in: "{{title}}") == "T")
    #expect(NoteTemplate.substituting(title: "T", date: sampleDate, in: "{{date}}") == "2026-08-18")
}

@Test func anUnknownPlaceholderIsLeftExactlyAsWritten() {
    // v1 knows two (D7). Emptying a third would destroy text somebody typed on the
    // strength of a guess about what they meant; left visible it is a question they can
    // answer themselves.
    let result = NoteTemplate.substituting(
        title: "T", date: sampleDate, in: "{{title}} {{autore}} {{date}}"
    )

    #expect(result == "T {{autore}} 2026-08-18")
}

@Test func aBodyWithNoPlaceholdersComesBackUnchanged() {
    let body = "# Titolo fisso\n\nNessun segnaposto qui."

    #expect(NoteTemplate.substituting(title: "T", date: sampleDate, in: body) == body)
}

// MARK: - Che cosa createNote scrive

@MainActor
@Test func creatingWithoutABodyWritesExactlyWhatItWroteBeforeTemplatesExisted() async throws {
    // The regression guard for the new `body:` argument. It defaults to empty for every
    // caller that does not pass a template, and that path must be byte-identical - this
    // change could otherwise alter every note the app has ever created rather than only
    // the templated ones.
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let result = try session.createNote(title: "Semplice", date: sampleDate)

    #expect(result.text == "---\ndate: 2026-08-18\ntags:\n  - type-note\n---\n\n")
}

@MainActor
@Test func creatingFromATemplateKeepsItsBodyAndNotItsFrontmatter() async throws {
    let vault = try TemporaryVault()
    try vault.write(templateWithFrontmatter, to: "Templates/Riunione.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    let body = NoteTemplate.substituting(
        title: "Riunione con Rossi",
        date: sampleDate,
        in: NoteTemplate.body(of: templateWithFrontmatter)
    )
    let result = try session.createNote(title: "Riunione con Rossi", date: sampleDate, body: body)

    #expect(result.text == """
    ---
    date: 2026-08-18
    tags:
      - type-note
    ---

    # Riunione con Rossi

    Data: 2026-08-18

    ## Presenti
    """)
    // The template's own date must not have travelled: the note is dated today, not
    // whenever the template was written.
    #expect(!result.text.contains("2026-01-01"))
}

@MainActor
@Test func theTemplatesFolderIsListedAsTemplatesAndOtherNotesAreNot() async throws {
    let vault = try TemporaryVault()
    try vault.write(templateWithFrontmatter, to: "Templates/Riunione.md")
    try vault.write(templateWithFrontmatter, to: "Templates/Verbale.md")
    try vault.write(templateWithFrontmatter, to: "01 Progetti/Ordinaria.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    // Title-sorted, and the ordinary note is absent - the negative control, since the
    // filter matching everything would still pass an "are the two templates there" check.
    #expect(session.templates.map(\.title) == ["Riunione", "Verbale"])
}
