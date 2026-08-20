import Foundation
import Testing
@testable import Pergamenum

private func record(
    path: String = "01 Progetti/Nota.md",
    title: String = "Nota",
    tags: [String] = ["type-note", "topic-vibration-isolation"],
    tasks: [TaskItem] = [],
    modifiedOn iso: String = "2026-08-11"
) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = tags.compactMap(Tag.init)
    var components = DateComponents()
    components.year = Int(iso.prefix(4))
    components.month = Int(iso.dropFirst(5).prefix(2))
    components.day = Int(iso.suffix(2))
    components.hour = 12
    return NoteRecord(
        relativePath: path, title: title, frontmatter: frontmatter, linkTargets: [],
        tasks: tasks, modifiedAt: Calendar.current.date(from: components) ?? .distantPast,
        byteSize: 0, contentHash: "-"
    )
}

private let body = """
Il rapporto fra frequenza di eccitazione e frequenza propria decide se un
isolatore attenua o amplifica. Trasmissibilità sotto radice di due.
"""

// MARK: - Parsing

@Test func parsesBareWords() {
    let query = SearchQuery("curva trasmissibilità")
    #expect(query.words == ["curva", "trasmissibilità"])
    #expect(query.phrases.isEmpty)
}

@Test func parsesQuotedPhrases() {
    let query = SearchQuery("\"frequenza propria\" curva")
    #expect(query.phrases == ["frequenza propria"])
    #expect(query.words == ["curva"])
}

@Test func parsesTheOperatorsOfTheSpec() {
    let query = SearchQuery("tag:type-note path:01 task:open")
    #expect(query.tags == ["type-note"])
    #expect(query.paths == ["01"])
    #expect(query.taskState == .open)
}

@Test func acceptsATagWrittenWithItsHash() {
    // `#type-note` is how a tag appears in the body; typing it must not make the
    // filter miss.
    #expect(SearchQuery("tag:#type-note").tags == ["type-note"])
}

@Test func treatsAnUnclosedQuoteAsPlainText() {
    // Dropping it would silently search for nothing.
    let query = SearchQuery("\"frequenza propria")
    #expect(query.phrases == ["frequenza propria"])
    #expect(query.words.isEmpty)
}

@Test func anEmptyQueryMatchesEverything() {
    let query = SearchQuery("   ")
    #expect(query.isEmpty)
    #expect(query.matches(record: record(), text: body))
}

@Test func ignoresAnUnknownTaskState() {
    #expect(SearchQuery("task:forse").taskState == nil)
}

// MARK: - Matching

@Test func matchesWordsAnywhereInTheNote() {
    #expect(SearchQuery("isolatore").matches(record: record(), text: body))
    #expect(!SearchQuery("pompa").matches(record: record(), text: body))
}

@Test func matchesTheTitleAsWellAsTheBody() {
    #expect(SearchQuery("nota").matches(record: record(), text: body))
}

@Test func foldsAccentsAndCase() {
    // "trasmissibilita" must find "Trasmissibilità": nobody types the accent in a
    // search field.
    #expect(SearchQuery("TRASMISSIBILITA").matches(record: record(), text: body))
    #expect(SearchQuery("trasmissibilità").matches(record: record(), text: body))
}

@Test func requiresEveryTermToMatch() {
    // Terms narrow. A search that widened as you added words would be useless.
    #expect(SearchQuery("isolatore frequenza").matches(record: record(), text: body))
    #expect(!SearchQuery("isolatore pompa").matches(record: record(), text: body))
}

@Test func matchesAPhraseOnlyWhenContiguous() {
    #expect(SearchQuery("\"frequenza propria\"").matches(record: record(), text: body))
    #expect(!SearchQuery("\"propria frequenza\"").matches(record: record(), text: body))
}

@Test func filtersByTag() {
    #expect(SearchQuery("tag:topic-vibration-isolation").matches(record: record(), text: body))
    #expect(!SearchQuery("tag:topic-acoustics").matches(record: record(), text: body))
    // A prefix matches, so `tag:topic-` finds every topic.
    #expect(SearchQuery("tag:topic-").matches(record: record(), text: body))
}

@Test func findsATagThatOnlyAppearsOnATask() {
    let task = TaskParser.parse(line: "- [ ] Fare #project-emea", sourcePath: "x.md", lineIndex: 0)!
    #expect(SearchQuery("tag:project-emea").matches(record: record(tasks: [task]), text: body))
}

@Test func filtersByPath() {
    #expect(SearchQuery("path:01").matches(record: record(), text: body))
    #expect(!SearchQuery("path:03").matches(record: record(), text: body))
}

@Test func acceptsAQuotedPathWithSpaces() {
    // The folders in this vault are called "01 Progetti"; without quoting, the
    // operator would split on the space and the rest would become a search word.
    let query = SearchQuery("path:\"01 Progetti\"")
    #expect(query.paths == ["01 progetti"])
    #expect(query.words.isEmpty)
    #expect(query.matches(record: record(), text: body))
    #expect(!SearchQuery("path:\"03 Risorse\"").matches(record: record(), text: body))
}

@Test func filtersByTaskState() {
    let open = TaskParser.parse(line: "- [ ] Aperto", sourcePath: "x.md", lineIndex: 0)!
    let done = TaskParser.parse(line: "- [x] Fatto", sourcePath: "x.md", lineIndex: 1)!

    #expect(SearchQuery("task:open").matches(record: record(tasks: [open]), text: body))
    #expect(!SearchQuery("task:open").matches(record: record(tasks: [done]), text: body))
    #expect(SearchQuery("task:done").matches(record: record(tasks: [done]), text: body))
    #expect(!SearchQuery("task:open").matches(record: record(tasks: []), text: body))
}

@Test func countsARescheduledTaskAsOpen() {
    let moved = TaskParser.parse(line: "- [>] Rimandato", sourcePath: "x.md", lineIndex: 0)!
    #expect(SearchQuery("task:open").matches(record: record(tasks: [moved]), text: body))
}

@Test func combinesOperatorsAndWords() {
    let task = TaskParser.parse(line: "- [ ] Rivedere", sourcePath: "x.md", lineIndex: 0)!
    let subject = record(tasks: [task])

    #expect(SearchQuery("tag:type-note path:01 task:open isolatore")
        .matches(record: subject, text: body))
    // One failing term is enough to exclude the note.
    #expect(!SearchQuery("tag:type-note path:99 isolatore")
        .matches(record: subject, text: body))
}

// MARK: - Negation (ADR-0012 D8)

@Test func parsesANegatedWord() {
    let query = SearchQuery("isolatore -pompa")
    #expect(query.words == ["isolatore"])
    #expect(query.negatedWords == ["pompa"])
}

@Test func parsesANegatedPhrase() {
    // The `-` sits before the opening quote, so the tokeniser has to carry it across.
    let query = SearchQuery("-\"frequenza propria\"")
    #expect(query.negatedPhrases == ["frequenza propria"])
    #expect(query.phrases.isEmpty)
    #expect(query.words.isEmpty)
}

@Test func parsesNegatedOperators() {
    let query = SearchQuery("-tag:type-note -path:\"03 Risorse\"")
    #expect(query.negatedTags == ["type-note"])
    #expect(query.negatedPaths == ["03 risorse"])
    #expect(query.tags.isEmpty)
    #expect(query.paths.isEmpty)
}

@Test func excludesANoteCarryingANegatedTerm() {
    #expect(SearchQuery("isolatore -pompa").matches(record: record(), text: body))
    #expect(!SearchQuery("isolatore -amplifica").matches(record: record(), text: body))
    #expect(!SearchQuery("-tag:type-note").matches(record: record(), text: body))
    #expect(!SearchQuery("-path:01").matches(record: record(), text: body))
    #expect(SearchQuery("-path:99").matches(record: record(), text: body))
}

@Test func readsAMinusOnAnOperatorWithoutANegatedFormAsText() {
    // `-orphan:` and `-modified:` have no obvious meaning, and guessing one would be a
    // decision taken silently. They become the literal text they look like, which is
    // what an unknown `foo:bar` already does.
    let query = SearchQuery("-orphan:")
    #expect(!query.orphansOnly)
    #expect(query.negatedWords == ["orphan:"])
}

// MARK: - regex:

@Test func parsesARegexKeepingItsCase() {
    // Lowercasing the pattern would rewrite it: `\S` and `\s` are opposites.
    #expect(SearchQuery("regex:\\S+").patterns == ["\\S+"])
}

@Test func matchesARegexPerLine() {
    let text = "# Titolo\n## Sezione\nCorpo"
    #expect(SearchQuery("regex:^##\\s").matches(record: record(), text: text))
    #expect(!SearchQuery("regex:^###\\s").matches(record: record(), text: text))
}

@Test func matchesARegexIgnoringCase() {
    #expect(SearchQuery("regex:TRASMISSIBILIT").matches(record: record(), text: body))
}

@Test func excludesOnANegatedRegex() {
    #expect(!SearchQuery("-regex:isolatore").matches(record: record(), text: body))
    #expect(SearchQuery("-regex:pompa").matches(record: record(), text: body))
}

@Test func aQueryWithABrokenPatternMatchesNothing() {
    // Matching everything would look like an answer, which is the worse failure.
    let query = SearchQuery("regex:[unclosed")
    #expect(query.invalidPatterns == ["[unclosed"])
    #expect(query.patterns.isEmpty)
    #expect(!query.isEmpty)
    #expect(!query.matches(record: record(), text: body))
}

// MARK: - modified:

@Test func parsesTheDateForms() {
    let day = CalendarDate(iso: "2026-08-11")
    #expect(SearchQuery("modified:2026-08-11").modified == SearchQuery.DateFilter("2026-08-11"))
    #expect(SearchQuery("modified:>2026-08-11").modified?.from == day)
    #expect(SearchQuery("modified:>=2026-08-11").modified?.from == day)
    #expect(SearchQuery("modified:<2026-08-11").modified?.to == day)
    let range = SearchQuery("modified:2026-08-01..2026-08-19").modified
    #expect(range?.from == CalendarDate(iso: "2026-08-01"))
    #expect(range?.to == CalendarDate(iso: "2026-08-19"))
}

@Test func ignoresAModifiedFilterThatIsNotADate() {
    #expect(SearchQuery("modified:ieri").modified == nil)
    #expect(SearchQuery("modified:11/08/2026").modified == nil)
}

@Test func filtersByModificationDay() {
    let note = record(modifiedOn: "2026-08-11")
    #expect(SearchQuery("modified:2026-08-11").matches(record: note, text: body))
    #expect(!SearchQuery("modified:2026-08-12").matches(record: note, text: body))
    #expect(SearchQuery("modified:>2026-08-01").matches(record: note, text: body))
    #expect(!SearchQuery("modified:>2026-08-12").matches(record: note, text: body))
    #expect(SearchQuery("modified:<2026-08-11").matches(record: note, text: body))
    #expect(SearchQuery("modified:2026-08-01..2026-08-19").matches(record: note, text: body))
    #expect(!SearchQuery("modified:2026-08-01..2026-08-10").matches(record: note, text: body))
}

@Test func intersectsTwoModifiedFilters() {
    // Everything else in a query ANDs; two bounds have to tighten, not replace.
    let query = SearchQuery("modified:>2026-08-05 modified:<2026-08-15")
    #expect(query.modified?.from == CalendarDate(iso: "2026-08-05"))
    #expect(query.modified?.to == CalendarDate(iso: "2026-08-15"))
}

// MARK: - The operators the vault answers

@Test func parsesTheVaultOperators() {
    let query = SearchQuery("is:starred orphan: linked:\"Curva di trasmissibilità\"")
    #expect(query.starredOnly)
    #expect(query.orphansOnly)
    #expect(query.linkedTo == ["curva di trasmissibilità"])
    #expect(query.needsVaultContext)
}

@Test func doesNotDecideTheVaultOperatorsFromTheNoteAlone() {
    // `is:starred` and the graph operators are applied by `VaultSession.search`, which
    // has the store and the index; a note cannot answer them about itself, and
    // answering "no" here would drop every result.
    #expect(SearchQuery("is:starred").matches(record: record(), text: body))
    #expect(SearchQuery("orphan:").matches(record: record(), text: body))
    #expect(!SearchQuery("isolatore").needsVaultContext)
}

@Test func aQueryOfOperatorsAloneIsNotEmpty() {
    #expect(!SearchQuery("is:starred").isEmpty)
    #expect(!SearchQuery("modified:>2026-08-01").isEmpty)
    #expect(!SearchQuery("-pompa").isEmpty)
}

// MARK: - Unlinked mentions (ADR-0012 D9)

private let mentioning = """
---
date: 2026-08-11
tags:
  - type-note
aliases:
  - Curva di trasmissibilità
---

Rifare il calcolo con la curva di trasmissibilità reale.
"""

@Test func findsTheLineThatNamesANote() {
    let line = UnlinkedMentions.firstMentionLine(of: ["Curva di trasmissibilità"], in: mentioning)
    #expect(line == "Rifare il calcolo con la curva di trasmissibilità reale.")
}

@Test func ignoresTheFrontmatter() {
    // The alias block names the note too, and reporting it would mean listing a note's own
    // bookkeeping as prose about it.
    let text = "---\ndate: 2026-08-11\ntags:\n  - type-note\naliases:\n  - Curva\n---\n\nAltro.\n"
    #expect(UnlinkedMentions.firstMentionLine(of: ["Curva"], in: text) == nil)
}

@Test func doesNotCountAnOccurrenceInsideAWikilink() {
    // That is the opposite of an unlinked mention, and the note is already a backlink.
    let text = "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\nVedi [[Curva di trasmissibilità]].\n"
    #expect(UnlinkedMentions.firstMentionLine(of: ["Curva di trasmissibilità"], in: text) == nil)
}

@Test func requiresAWholeWord() {
    #expect(!UnlinkedMentions.mentions(["Curva"], in: "La curvatura del profilo."))
    #expect(UnlinkedMentions.mentions(["Curva"], in: "La curva, misurata."))
    #expect(UnlinkedMentions.mentions(["Curva"], in: "Curva."))
}

@Test func foldsAccentsAndCaseLikeTheSearchDoes() {
    #expect(UnlinkedMentions.mentions(["Trasmissibilità"], in: "La trasmissibilita misurata."))
    #expect(UnlinkedMentions.mentions(["trasmissibilita"], in: "TRASMISSIBILITÀ sotto radice."))
}

@Test func findsAMentionOverlappingAFailedOne() {
    // The scan steps one character on after a match that lost on its boundaries, not one
    // match on: skipping the whole occurrence would step over the good one inside it.
    #expect(UnlinkedMentions.mentions(["ala"], in: "balala ala."))
}

@Test func aNameThatIsOnlyWhitespaceMatchesNothing() {
    #expect(!UnlinkedMentions.mentions(["   "], in: "Qualsiasi riga."))
    #expect(!UnlinkedMentions.mentions([""], in: "Qualsiasi riga."))
}
