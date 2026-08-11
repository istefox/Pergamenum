import Foundation
import Testing
@testable import Pergamenum

private func record(
    path: String = "01 Progetti/Nota.md",
    title: String = "Nota",
    tags: [String] = ["type-note", "topic-vibration-isolation"],
    tasks: [TaskItem] = []
) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = tags.compactMap(Tag.init)
    return NoteRecord(
        relativePath: path, title: title, frontmatter: frontmatter, linkTargets: [],
        tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
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
