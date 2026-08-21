import Foundation
import Testing
@testable import Pergamenum

// MARK: - The seven keys

@Test func parsesTheBlockTheAdrPrints() throws {
    let block = try ViewBlock.parse("""
    from: path("Clienti")
    where: tag("client-*") and not tag("status-chiuso")
    sort: modified desc
    group: tag("status-*")
    render: board
    columns: [title, tags, modified, tasks.open, deadline.next]
    """)

    #expect(block.scope == ["Clienti"])
    #expect(block.filter == .and(.tag("client-*"), .not(.tag("status-chiuso"))))
    #expect(block.sort == [ViewBlock.SortKey(field: .modified, descending: true)])
    #expect(block.group == .tag("status-*"))
    #expect(block.render == .board)
    #expect(block.columns == [.title, .tags, .modified, .tasksOpen, .deadlineNext])
    #expect(block.limit == nil)
}

@Test func rendersIsTheOnlyRequiredKey() throws {
    let block = try ViewBlock.parse("render: list")
    #expect(block.render == .list)
    #expect(block.scope.isEmpty)
    #expect(block.filter == .all)
    #expect(block.sort.isEmpty)
    #expect(block.group == nil)
    #expect(block.columns.isEmpty)
}

@Test func aBlockWithoutRenderDoesNotParse() {
    #expect(throws: ViewBlockError.self) { try ViewBlock.parse("where: tag(\"type-note\")") }
}

@Test func parsesLimitAndRefusesANonPositiveOne() throws {
    #expect(try ViewBlock.parse("render: table\nlimit: 20").limit == 20)
    let error = #expect(throws: ViewBlockError.self) { try ViewBlock.parse("render: table\nlimit: 0") }
    #expect(error?.line == 2)
}

@Test func parsesSortWithSeveralKeysAndDirections() throws {
    let block = try ViewBlock.parse("render: table\nsort: deadline.next asc, title, modified desc")
    #expect(block.sort == [
        ViewBlock.SortKey(field: .deadlineNext),
        ViewBlock.SortKey(field: .title),
        ViewBlock.SortKey(field: .modified, descending: true),
    ])
}

@Test func columnsParseWithOrWithoutBrackets() throws {
    #expect(try ViewBlock.parse("render: table\ncolumns: [title, size]").columns == [.title, .size])
    #expect(try ViewBlock.parse("render: table\ncolumns: title, size").columns == [.title, .size])
}

@Test func groupTakesATagGlobOrAField() throws {
    #expect(try ViewBlock.parse("render: table\ngroup: tag(\"status-*\")").group == .tag("status-*"))
    #expect(try ViewBlock.parse("render: table\ngroup: folder").group == .field(.folder))
}

/// §D5: only a tag namespace can be dragged. Grouping by anything else is a report.
@Test func onlyATagGroupingIsWritable() throws {
    #expect(ViewBlock.Grouping.tag("status-*").isWritable)
    #expect(!ViewBlock.Grouping.field(.folder).isWritable)
}

// MARK: - Errors name the line

@Test func anUnknownKeyNamesItsLineAndTheSeven() {
    let error = #expect(throws: ViewBlockError.self) {
        try ViewBlock.parse("render: table\nfilter: tag(\"x\")")
    }
    #expect(error?.line == 2)
    #expect(error?.reason.contains("chiave sconosciuta") == true)
    #expect(error?.description.hasPrefix("riga 2:") == true)
}

@Test func aRepeatedKeyIsRefusedRatherThanQuietlyOverwritten() {
    let error = #expect(throws: ViewBlockError.self) {
        try ViewBlock.parse("render: table\nwhere: tag(\"a-b\")\nwhere: tag(\"c-d\")")
    }
    #expect(error?.line == 3)
    #expect(error?.reason.contains("riga 2") == true)
}

@Test func aLineWithoutAColonNamesItself() {
    let error = #expect(throws: ViewBlockError.self) { try ViewBlock.parse("render: table\nsoltanto parole") }
    #expect(error?.line == 2)
}

@Test func blankLinesAreSkippedSoTheNumbersStillMatchWhatIsWritten() {
    let error = #expect(throws: ViewBlockError.self) {
        try ViewBlock.parse("render: table\n\n\nlimit: no")
    }
    #expect(error?.line == 4)
}

/// §D1: a board without `group` is a parse error. A silent single column looks like a
/// filter that matched nothing.
@Test func aBoardWithoutGroupIsAParseError() {
    let error = #expect(throws: ViewBlockError.self) { try ViewBlock.parse("render: board") }
    #expect(error?.reason.contains("group") == true)
}

@Test func fromTakesOnlyPaths() throws {
    #expect(try ViewBlock.parse("render: list\nfrom: path(\"A\") or path(\"B\")").scope == ["A", "B"])
    let error = #expect(throws: ViewBlockError.self) {
        try ViewBlock.parse("render: list\nfrom: tag(\"type-note\")")
    }
    #expect(error?.reason.contains("«where»") == true)
}

// MARK: - The field that does not exist, and the one that just started to

@Test func createdIsRefusedWithTheReasonRatherThanAsUnknown() {
    let error = #expect(throws: ViewBlockError.self) { try ViewBlock.parse("render: table\nsort: created desc") }
    #expect(error?.reason.contains("data di modifica") == true)
}

/// The one schema change M11 was allowed, and it has been spent: the gallery's field
/// parses like any other.
@Test func embedTargetsIsAFieldNow() throws {
    #expect(try ViewBlock.parse("render: gallery\ncolumns: [embedTargets]").columns == [.embedTargets])
}

@Test func hasNamesOnlyTheClosedList() {
    let error = #expect(throws: ViewBlockError.self) {
        try ViewBlock.parse("render: table\nwhere: has(cliente)")
    }
    #expect(error?.reason.contains("campo sconosciuto") == true)
    #expect(error?.reason.contains("tasks.open") == true)
}

// MARK: - The where grammar

@Test func parsesEveryTerm() throws {
    #expect(try ViewFilter.parse("path(\"01 Progetti\")", line: 1) == .path("01 Progetti"))
    #expect(try ViewFilter.parse("tag(client-vibrofer)", line: 1) == .tag("client-vibrofer"))
    #expect(try ViewFilter.parse("linksTo(\"Nota\")", line: 1) == .linksTo("Nota"))
    #expect(try ViewFilter.parse("linkedFrom(\"Nota\")", line: 1) == .linkedFrom("Nota"))
    #expect(try ViewFilter.parse("task(open)", line: 1) == .task(.open))
    #expect(try ViewFilter.parse("task(done)", line: 1) == .task(.done))
    #expect(try ViewFilter.parse("has(deadline.next)", line: 1) == .has(.deadlineNext))
    #expect(try ViewFilter.parse("text(\"frequenza propria\")", line: 1) == .text("frequenza propria"))
}

@Test func parsesDateComparisons() throws {
    let day = CalendarDate(iso: "2026-08-01")!
    #expect(try ViewFilter.parse("date >= 2026-08-01", line: 1) == .comparison(.date, .atLeast, day))
    #expect(try ViewFilter.parse("modified<2026-08-01", line: 1) == .comparison(.modified, .lessThan, day))
    #expect(try ViewFilter.parse("date == 2026-08-01", line: 1) == .comparison(.date, .equalTo, day))
}

@Test func onlyTheTwoDatesCompare() {
    #expect(throws: ViewBlockError.self) { try ViewFilter.parse("size > 2026-08-01", line: 1) }
    #expect(throws: ViewBlockError.self) { try ViewFilter.parse("date > ieri", line: 1) }
}

@Test func notBindsTighterThanAndAndAndTighterThanOr() throws {
    let filter = try ViewFilter.parse("not tag(\"a-a\") and tag(\"b-b\") or tag(\"c-c\")", line: 1)
    #expect(filter == .or(.and(.not(.tag("a-a")), .tag("b-b")), .tag("c-c")))
}

@Test func parenthesesOverrideThePrecedence() throws {
    let filter = try ViewFilter.parse("tag(\"a-a\") and (tag(\"b-b\") or tag(\"c-c\"))", line: 1)
    #expect(filter == .and(.tag("a-a"), .or(.tag("b-b"), .tag("c-c"))))
}

@Test func keywordsAreCaseInsensitive() throws {
    #expect(try ViewFilter.parse("tag(\"a-a\") AND NOT tag(\"b-b\")", line: 1) == .and(.tag("a-a"), .not(.tag("b-b"))))
}

@Test func anUnclosedParenthesisIsNamedOnItsLine() {
    let error = #expect(throws: ViewBlockError.self) { try ViewFilter.parse("(tag(\"a-a\")", line: 7) }
    #expect(error?.line == 7)
    #expect(error?.reason.contains("parentesi") == true)
}

@Test func anUnknownTermListsTheOnesThereAre() {
    let error = #expect(throws: ViewBlockError.self) { try ViewFilter.parse("cliente(\"Vibrofer\")", line: 1) }
    #expect(error?.reason.contains("termine sconosciuto") == true)
}

@Test func aRegexIsNotATerm() {
    #expect(throws: ViewBlockError.self) { try ViewFilter.parse("regex(\"^## \")", line: 1) }
}

@Test func taskTakesOnlyOpenOrDone() {
    let error = #expect(throws: ViewBlockError.self) { try ViewFilter.parse("task(cancelled)", line: 1) }
    #expect(error?.reason.contains("open o done") == true)
}

@Test func onlyTextReadsTheFiles() throws {
    #expect(try ViewFilter.parse("tag(\"a-a\") and text(\"x\")", line: 1).readsText)
    #expect(!(try ViewFilter.parse("tag(\"a-a\") and has(date)", line: 1).readsText))
}

// MARK: - Globs

@Test func globsMatchTheWayTheTwoTermsNeed() {
    #expect(Glob.matches("client-*", "client-vibrofer"))
    #expect(Glob.matches("*-vibrofer", "client-vibrofer"))
    #expect(Glob.matches("a*a*a", "abacada"))
    #expect(!Glob.matches("client-*", "competitor-x"))
    #expect(Glob.matches("nota?", "notaX"))
    #expect(!Glob.matches("nota?", "nota"))
}

/// A tag without a wildcard is exact; a path without one is a prefix. `tag("status-a")`
/// quietly taking `status-aperto` is the failure this asymmetry exists to prevent.
@Test func tagsAreExactWithoutAWildcardAndPathsArePrefixes() {
    #expect(Glob.matchesTag("status-aperto", "status-aperto"))
    #expect(!Glob.matchesTag("status-a", "status-aperto"))
    #expect(Glob.matchesTag("status-*", "status-aperto"))
    #expect(Glob.matchesPath("Clienti", "Clienti/Vibrofer.md"))
    #expect(!Glob.matchesPath("Clienti", "Archivio/Clienti/Vibrofer.md"))
    #expect(Glob.matchesPath("*/Clienti/*", "Archivio/Clienti/Vibrofer.md"))
}

// MARK: - Finding the blocks in a note

@Test func readsTheFencesOfANoteAndLeavesTheRestAlone() {
    let note = """
    # Clienti

    ```pergamenum-view
    render: table
    ```

    ```swift
    let x = 1
    ```

    ```pergamenum-view
    render: board
    ```
    """
    let blocks = ViewBlock.blocks(in: note)
    #expect(blocks.count == 2)
    #expect((try? blocks[0].get())?.render == .table)
    // The second one is a board with no group: an error in the note, not an empty result.
    #expect(throws: ViewBlockError.self) { try blocks[1].get() }
}
