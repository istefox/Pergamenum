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

    let result = try await session.createNote(title: "Semplice", date: sampleDate)

    // REWRITTEN (PG-384, ADR-0080 §D1): this pinned `type-note` alone. A note born with no
    // `topic-*` is now a capture on every path, so `status-inbox` follows `type-note`. The
    // regression it guards is unchanged: nothing else about the bytes moved.
    // (n1-seams R-01)
    #expect(result.text == "---\ndate: 2026-08-18\ntags:\n  - type-note\n  - status-inbox\n---\n\n")
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
    let result = try await session.createNote(title: "Riunione con Rossi", date: sampleDate, body: body)

    // REWRITTEN (PG-384, ADR-0080 §D1): the same one-line change as the pin above, the
    // template's body is untouched. (n1-seams R-01)
    #expect(result.text == """
    ---
    date: 2026-08-18
    tags:
      - type-note
      - status-inbox
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

// MARK: - PG-387 (ADR-0086 §D1): `resolve`, `{{time}}` and `{{cursor}}` (R-07, R-08)

private let nineOhFive = TaskTime(hour: 9, minute: 5)

@Test func theTimePlaceholderResolvesToHoursAndMinutesWithTwoDigits() {
    let resolved = NoteTemplate.resolve("Ora {{time}}", title: "T", date: sampleDate, time: nineOhFive)

    #expect(resolved.body == "Ora 09:05")
    #expect(resolved.caretOffset == nil)
}

@Test func resolveStillSubstitutesTitleAndDateAndLeavesAnUnknownPlaceholderAlone() {
    let resolved = NoteTemplate.resolve(
        "{{title}} {{autore}} {{date}}", title: "Ciao", date: sampleDate, time: nineOhFive
    )

    #expect(resolved.body == "Ciao {{autore}} 2026-08-18")
}

@Test func theCursorMarkerIsNeverWrittenAndGivesTheOffsetWhereItStood() {
    let resolved = NoteTemplate.resolve(
        "# {{title}}\n\n{{cursor}}", title: "Ciao", date: sampleDate, time: nineOhFive
    )

    #expect(resolved.body == "# Ciao\n\n")
    #expect(resolved.caretOffset == 8)
}

@Test func withTwoMarkersTheFirstWinsAndBothAreGone() {
    let resolved = NoteTemplate.resolve(
        "A{{cursor}}B{{cursor}}C", title: "T", date: sampleDate, time: nineOhFive
    )

    #expect(resolved.body == "ABC")
    #expect(resolved.caretOffset == 1)
}

@Test func aTitleThatContainsTheMarkerIsWrittenAsTypedAndTheRealMarkerStillWins() {
    // The marker is located in the template before any other substitution, so the title's
    // copy of it is typed text and the caret goes where the template put its own.
    let resolved = NoteTemplate.resolve(
        "# {{title}}\n{{cursor}}", title: "Ciao {{cursor}}", date: sampleDate, time: nineOhFive
    )

    #expect(resolved.body == "# Ciao {{cursor}}\n")
    #expect(resolved.caretOffset == "# Ciao {{cursor}}\n".utf16.count)
}

@Test func aTemplateWithoutAMarkerHasNoOffset() {
    let resolved = NoteTemplate.resolve("# {{title}}", title: "T", date: sampleDate, time: nineOhFive)

    #expect(resolved.body == "# T")
    #expect(resolved.caretOffset == nil)
}

@Test func theOffsetCountsUTF16UnitsNotCharacters() {
    // The emoji is one Character and two UTF-16 units; an NSTextView counts the second.
    let resolved = NoteTemplate.resolve("😀{{cursor}}", title: "T", date: sampleDate, time: nineOhFive)

    #expect(resolved.body == "😀")
    #expect(resolved.caretOffset == 2)
}

@Test func theCaretInTheWrittenTextIsTheAbsoluteOffsetAfterTheFrontmatter() throws {
    let resolved = NoteTemplate.resolve(
        "# {{title}}\n\n{{cursor}}Fine", title: "Ciao", date: sampleDate, time: nineOhFive
    )
    let frontmatter = "---\ndate: 2026-08-18\ntags:\n  - type-note\n---\n"
    // What `createNote` writes: the block, one separating line break, then the body.
    let written = frontmatter + "\n" + resolved.body

    let offset = try #require(resolved.caret(inWritten: written))
    #expect(offset == frontmatter.utf16.count + 1 + 8)
    // And the offset really is where "Fine" starts.
    #expect((written as NSString).substring(from: offset) == "Fine")
    #expect(NoteTemplate.resolve("senza", title: "T", date: sampleDate, time: nineOhFive)
        .caret(inWritten: "---\n---\n\nsenza") == nil)
}

@Test func cursorBackIsTheUnitsBetweenTheCaretAndTheEndOfTheBody() throws {
    let resolved = NoteTemplate.resolve(
        "# {{title}}\n\n{{cursor}}\n\nFine", title: "Ciao", date: sampleDate, time: nineOhFive
    )
    let offset = try #require(resolved.caretOffset)

    #expect(resolved.cursorBack == resolved.body.utf16.count - offset)
    #expect(resolved.cursorBack == 6)
    #expect(NoteTemplate.resolve("senza", title: "T", date: sampleDate, time: nineOhFive).cursorBack == nil)
}

// MARK: - PG-387 (ADR-0086 §D5): `composing` (R-09)

@Test func aCapturedTextGoesAtTheMarker() {
    let resolved = NoteTemplate.Resolved(body: "# Ciao\n\n", caretOffset: 8)

    #expect(NoteTemplate.composing(captured: "Testo", into: resolved) == "# Ciao\n\nTesto")
}

@Test func aCapturedTextIsInsertedAtTheMarkerEvenWithBodyAfterIt() {
    let resolved = NoteTemplate.Resolved(body: "A\nB", caretOffset: 2)

    #expect(NoteTemplate.composing(captured: "Testo", into: resolved) == "A\nTestoB")
}

@Test func withoutAMarkerTheBodyThenOneBlankLineThenTheText() {
    let resolved = NoteTemplate.Resolved(body: "# Ciao", caretOffset: nil)

    #expect(NoteTemplate.composing(captured: "Testo", into: resolved) == "# Ciao\n\nTesto")
}

// MARK: - PG-387 (ADR-0086 §D6): `reference` (R-10)

private let twoTemplates = ["Templates/Riunione.md", "Templates/Verbale.md"]

@Test func aReferenceByExactPathByTitleAndByFileNameAllResolveToThePath() {
    #expect(NoteTemplate.reference("Templates/Riunione.md", among: twoTemplates) == .success("Templates/Riunione.md"))
    #expect(NoteTemplate.reference("Riunione", among: twoTemplates) == .success("Templates/Riunione.md"))
    #expect(NoteTemplate.reference("Riunione.md", among: twoTemplates) == .success("Templates/Riunione.md"))
    #expect(NoteTemplate.reference("Verbale", among: twoTemplates) == .success("Templates/Verbale.md"))
}

@Test func anUnknownReferenceListsTheTemplatesThatExist() throws {
    let result = NoteTemplate.reference("Assente", among: twoTemplates)

    guard case .failure(.unknown(let name, let available)) = result else {
        Issue.record("expected .unknown, got \(result)")
        return
    }
    #expect(name == "Assente")
    #expect(available.count == 2)
    #expect(available.allSatisfy { $0.contains("Riunione") || $0.contains("Verbale") })
    // The sentence is what both connectors show: it names the template the person can pick.
    let sentence = try #require(result.failureValue).sentence
    #expect(sentence.contains("Assente"))
    #expect(sentence.contains("Riunione"))
    #expect(sentence.contains("Verbale"))
}

@Test func twoTemplatesWithTheSameTitleAreAmbiguousAndNamed() throws {
    let paths = ["Templates/A/Riunione.md", "Templates/B/Riunione.md", "Templates/Verbale.md"]

    for reference in ["Riunione", "Riunione.md"] {
        let result = NoteTemplate.reference(reference, among: paths)
        guard case .failure(.ambiguous(_, let candidates)) = result else {
            Issue.record("expected .ambiguous for «\(reference)», got \(result)")
            continue
        }
        #expect(Set(candidates) == ["Templates/A/Riunione.md", "Templates/B/Riunione.md"])
        let sentence = try #require(result.failureValue).sentence
        #expect(sentence.contains("Templates/A/Riunione.md"))
        #expect(sentence.contains("Templates/B/Riunione.md"))
    }
    // The exact path settles it.
    #expect(NoteTemplate.reference("Templates/A/Riunione.md", among: paths) == .success("Templates/A/Riunione.md"))
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}
