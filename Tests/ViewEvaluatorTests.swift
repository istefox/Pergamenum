import Foundation
import Testing
@testable import Pergamenum

// MARK: - A vault of ten notes, held in memory

private struct Corpus: ViewCorpus {
    var records: [NoteRecord]

    func paths(forTitle title: String) -> [String] {
        records.filter { $0.title.lowercased() == title.lowercased() }.map(\.relativePath)
    }
}

private func record(
    _ title: String,
    path: String? = nil,
    tags: [String] = [],
    date: String? = nil,
    aliases: [String] = [],
    related: [String] = [],
    links: [String] = [],
    tasks: String = "",
    size: Int = 100,
    modified: String = "2026-08-11"
) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = date.flatMap { CalendarDate(iso: $0) }
    frontmatter.tags = tags.compactMap(Tag.init)
    frontmatter.aliases = aliases
    frontmatter.related = related
    let relativePath = path ?? "Clienti/\(title).md"
    var components = DateComponents()
    components.year = Int(modified.prefix(4))
    components.month = Int(modified.dropFirst(5).prefix(2))
    components.day = Int(modified.suffix(2))
    components.hour = 12
    return NoteRecord(
        relativePath: relativePath,
        title: title,
        frontmatter: frontmatter,
        linkTargets: links,
        tasks: TaskParser.tasks(in: tasks, sourcePath: relativePath),
        modifiedAt: Calendar.current.date(from: components) ?? .distantPast,
        byteSize: size,
        contentHash: "-"
    )
}

private let vault = Corpus(records: [
    record(
        "Vibrofer", tags: ["client-vibrofer", "status-aperto"], date: "2026-08-01",
        aliases: ["Vibrofer Srl"], links: ["Presse"],
        tasks: "- [ ] Sopralluogo !2026-09-10\n- [x] Preventivo",
        size: 400, modified: "2026-08-18"
    ),
    record(
        "Ceramiche", tags: ["client-ceramiche", "status-chiuso"], date: "2026-07-01",
        tasks: "- [x] Consegna", modified: "2026-08-02"
    ),
    record(
        "Presse", path: "Progetti/Presse.md", tags: ["project-presse", "status-aperto"],
        related: ["[[Vibrofer]]"], links: ["Vibrofer", "Nota che non esiste"],
        tasks: "- [ ] Disegno >2026-08-25 !2026-08-30", modified: "2026-08-19"
    ),
    record("Letture", path: "Letture/Letture.md", tags: ["type-note"], size: 20),
])

private func evaluate(_ source: String, over corpus: Corpus = vault, body: String? = nil) throws -> ViewResult {
    let block = try ViewBlock.parse(source)
    guard let body else { return ViewEvaluator.evaluate(block, over: corpus) }
    return ViewEvaluator.evaluate(block, over: corpus) { _ in body }
}

// MARK: - Scope and filter

@Test func anEmptyFromIsTheWholeVault() throws {
    #expect(try evaluate("render: list").total == 4)
}

@Test func fromNarrowsByPathPrefix() throws {
    let result = try evaluate("render: list\nfrom: path(\"Clienti\")")
    #expect(result.rows.map(\.title) == ["Ceramiche", "Vibrofer"])
}

@Test func tagTermMatchesTheGlob() throws {
    let result = try evaluate("render: list\nwhere: tag(\"client-*\")")
    #expect(Set(result.rows.map(\.title)) == ["Vibrofer", "Ceramiche"])
}

@Test func andOrNotCombineTheWayTheyParse() throws {
    let result = try evaluate("render: list\nwhere: tag(\"client-*\") and not tag(\"status-chiuso\")")
    #expect(result.rows.map(\.title) == ["Vibrofer"])
}

@Test func linksToFollowsTheResolvedEdge() throws {
    #expect(try evaluate("render: list\nwhere: linksTo(\"Presse\")").rows.map(\.title) == ["Vibrofer"])
    #expect(try evaluate("render: list\nwhere: linkedFrom(\"Presse\")").rows.map(\.title) == ["Vibrofer"])
}

@Test func aLinkNoNoteAnswersToIsNotAnEdge() throws {
    #expect(try evaluate("render: list\nwhere: linksTo(\"Nota che non esiste\")").total == 0)
}

@Test func taskTermReadsTheStateOfTheLines() throws {
    #expect(Set(try evaluate("render: list\nwhere: task(open)").rows.map(\.title)) == ["Vibrofer", "Presse"])
    #expect(Set(try evaluate("render: list\nwhere: task(done)").rows.map(\.title)) == ["Vibrofer", "Ceramiche"])
}

@Test func datesCompareOnBothFields() throws {
    #expect(try evaluate("render: list\nwhere: date >= 2026-08-01").rows.map(\.title) == ["Vibrofer"])
    #expect(Set(try evaluate("render: list\nwhere: modified > 2026-08-15").rows.map(\.title))
        == ["Vibrofer", "Presse"])
}

/// §D3: `has()` is true when the field exists and is not empty. An absent key, an empty
/// list and a note with no open task all read as false.
@Test func hasReadsEmptinessRatherThanPresence() throws {
    #expect(Set(try evaluate("render: list\nwhere: has(date)").rows.map(\.title)) == ["Vibrofer", "Ceramiche"])
    #expect(try evaluate("render: list\nwhere: has(aliases)").rows.map(\.title) == ["Vibrofer"])
    #expect(try evaluate("render: list\nwhere: has(related)").rows.map(\.title) == ["Presse"])
    #expect(Set(try evaluate("render: list\nwhere: has(tasks.open)").rows.map(\.title)) == ["Vibrofer", "Presse"])
    #expect(try evaluate("render: list\nwhere: has(unresolved)").rows.map(\.title) == ["Presse"])
    #expect(try evaluate("render: list\nwhere: has(folder) and not has(links)").rows.map(\.title)
        == ["Ceramiche", "Letture"])
}

// MARK: - text() and its reader

@Test func textMatchesWhatTheReaderReturns() throws {
    let result = try evaluate("render: list\nwhere: text(\"frequenza\")", body: "La frequenza propria decide.")
    #expect(result.total == 4)
}

@Test func textIsFoldedLikeTheGlobalSearch() throws {
    let result = try evaluate("render: list\nwhere: text(\"TRASMISSIBILITA\")", body: "Trasmissibilità sotto radice")
    #expect(result.total == 4)
}

/// With no reader a `text()` view matches **nothing**. Matching everything would make an
/// empty answer look like a full one.
@Test func textWithNoReaderMatchesNothing() throws {
    #expect(try evaluate("render: list\nwhere: text(\"frequenza\")").total == 0)
}

// MARK: - Fields

@Test func everyFieldDerivesFromTheRecordOrTheGraph() throws {
    let columns = ViewField.names.joined(separator: ", ")
    let result = try evaluate("render: table\nwhere: tag(\"project-presse\")\ncolumns: [\(columns)]")
    let row = try #require(result.rows.first)

    #expect(row.values[.title] == .text("Presse"))
    #expect(row.values[.path] == .text("Progetti/Presse.md"))
    #expect(row.values[.folder] == .text("Progetti"))
    #expect(row.values[.tags] == .list(["project-presse", "status-aperto"]))
    #expect(row.values[.date] == .absent)
    #expect(row.values[.aliases] == .list([]))
    #expect(row.values[.related] == .list(["[[Vibrofer]]"]))
    #expect(row.values[.modified] == .day(CalendarDate(iso: "2026-08-19")!))
    #expect(row.values[.size] == .number(100))
    #expect(row.values[.links] == .list(["Vibrofer", "Nota che non esiste"]))
    #expect(row.values[.linkedFrom] == .list(["Vibrofer"]))
    #expect(row.values[.tasksOpen] == .number(1))
    #expect(row.values[.tasksDone] == .number(0))
    #expect(row.values[.tasksTotal] == .number(1))
    #expect(row.values[.deadlineNext] == .day(CalendarDate(iso: "2026-08-30")!))
    #expect(row.values[.scheduledNext] == .day(CalendarDate(iso: "2026-08-25")!))
    #expect(row.values[.unresolved] == .list(["Nota che non esiste"]))
}

/// What the derivation table costs in compile-time exhaustiveness, bought back here: a
/// field added without one trips its own `assertionFailure` on this line.
@Test func everyFieldHasADerivation() {
    let note = record("X")
    for field in ViewField.allCases { _ = field.value(of: note) }
    #expect(ViewField.allCases.count == ViewField.names.count)
}

@Test func onlyTheColumnsAskedForAreResolved() throws {
    let result = try evaluate("render: table\ncolumns: [title]\nlimit: 1")
    #expect(result.rows.first?.values.keys.map(\.self) == [.title])
}

/// A deadline is the earliest open one, with no clock involved: a view that read today
/// would answer the same question differently tomorrow.
@Test func theNextDeadlineIsTheEarliestOpenOneAndIgnoresDoneTasks() {
    let note = record("X", tasks: "- [x] Vecchio !2026-01-01\n- [ ] Nuovo !2026-12-01\n- [ ] Prima !2026-09-01")
    #expect(ViewField.deadlineNext.value(of: note) == .day(CalendarDate(iso: "2026-09-01")!))
}

// MARK: - Sorting, limiting, grouping

@Test func sortsDescendingAndFallsBackToTheTitle() throws {
    let result = try evaluate("render: table\nsort: modified desc")
    #expect(result.rows.map(\.title) == ["Presse", "Vibrofer", "Letture", "Ceramiche"])
}

@Test func aNoteWithNoValueSortsLastRatherThanFirst() throws {
    let result = try evaluate("render: table\nsort: deadline.next")
    #expect(result.rows.map(\.title) == ["Presse", "Vibrofer", "Ceramiche", "Letture"])
}

@Test func limitCutsTheRowsAndTotalStillCounts() throws {
    let result = try evaluate("render: table\nsort: title\nlimit: 2")
    #expect(result.rows.count == 2)
    #expect(result.total == 4)
}

@Test func aLimitPastTheEndChangesNothing() throws {
    #expect(try evaluate("render: table\nlimit: 900").rows.count == 4)
}

@Test func groupingSplitsByTheTagAndPutsTheUnnamedGroupFirst() throws {
    let result = try evaluate("render: board\ngroup: tag(\"status-*\")")
    #expect(result.groups.map(\.label) == [nil, "status-aperto", "status-chiuso"])
    #expect(result.groups[0].rows.map(\.title) == ["Letture"])
    #expect(Set(result.groups[1].rows.map(\.title)) == ["Vibrofer", "Presse"])
}

/// §D5: a note carrying two `status-*` tags appears in both columns. The file really does
/// say both.
@Test func aNoteWithTwoStatusesAppearsInBothColumns() throws {
    let corpus = Corpus(records: [record("Doppia", tags: ["status-aperto", "status-chiuso"])])
    let result = try evaluate("render: board\ngroup: tag(\"status-*\")", over: corpus)
    #expect(result.groups.count == 2)
    #expect(result.groups.allSatisfy { $0.rows.map(\.title) == ["Doppia"] })
    #expect(result.total == 1)
}

@Test func groupingByAFieldUsesItsValue() throws {
    let result = try evaluate("render: table\ngroup: folder")
    #expect(result.groups.map(\.label) == ["Clienti", "Letture", "Progetti"])
}

@Test func withoutGroupThereIsOneUnnamedGroup() throws {
    let result = try evaluate("render: table")
    #expect(result.groups.count == 1)
    #expect(result.groups[0].label == nil)
    #expect(result.groups[0].rows.count == 4)
}
