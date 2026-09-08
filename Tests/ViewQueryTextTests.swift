import Foundation
import Testing
@testable import Pergamenum

private func draft(
    scope: [String] = [],
    terms: [ViewFilter] = [],
    sort: [ViewBlock.SortKey] = [],
    group: ViewBlock.Grouping? = nil,
    render: ViewBlock.Renderer = .table,
    columns: [ViewField] = [],
    limit: String = ""
) -> ViewQueryDraft {
    ViewQueryDraft(
        scope: scope,
        terms: terms,
        sort: sort,
        group: group,
        render: render,
        columns: columns,
        limit: limit
    )
}

private func lines(in body: String, beginningWith key: String) -> [Substring] {
    body.split(separator: "\n").filter { $0.hasPrefix("\(key):") }
}

private func fenceBody(in text: String, openingOffset: Int) -> String? {
    let opening = text.index(text.startIndex, offsetBy: openingOffset)
    let fenceLines = text[opening...].split(separator: "\n", omittingEmptySubsequences: false)
    guard fenceLines.first == "```pergamenum-view",
          let closing = fenceLines.dropFirst().firstIndex(of: "```")
    else { return nil }
    return fenceLines[fenceLines.index(after: fenceLines.startIndex)..<closing].joined(separator: "\n")
}

// MARK: - Complete blocks and declaration order

@Test func allSevenKeysRoundTripInViewBlockDeclarationOrder() throws {
    let terms: [ViewFilter] = [
        .tag("client-*"),
        .not(.tag("status-chiuso")),
    ]
    let intended = ViewBlock(
        scope: ["Clienti"],
        filter: .and(terms[0], terms[1]),
        sort: [.init(field: .modified, descending: true)],
        group: .tag("status-*"),
        render: .board,
        columns: [.title, .tags, .modified, .tasksOpen, .deadlineNext],
        limit: 20
    )

    let body = ViewQueryText.body(of: draft(
        scope: intended.scope,
        terms: terms,
        sort: intended.sort,
        group: intended.group,
        render: intended.render,
        columns: intended.columns,
        limit: "20"
    ))

    #expect(try ViewBlock.parse(body) == intended)
    #expect(body.split(separator: "\n").map { $0.split(separator: ":", maxSplits: 1)[0] }
        == ["from", "where", "sort", "group", "render", "columns", "limit"])
}

// MARK: - Optional sections

@Test func fromWritesOnlyPathTermsJoinedByOr() throws {
    let body = ViewQueryText.body(of: draft(scope: ["a", "b"]))

    #expect(lines(in: body, beginningWith: "from") == ["from: path(\"a\") or path(\"b\")"])
    #expect(try ViewBlock.parse(body).scope == ["a", "b"])
}

@Test func zeroFromRowsOmitTheKey() throws {
    let body = ViewQueryText.body(of: draft(scope: []))

    #expect(lines(in: body, beginningWith: "from").isEmpty)
    #expect(try ViewBlock.parse(body).scope.isEmpty)
}

@Test func emptySectionsAreOmittedRatherThanWrittenBare() throws {
    let body = ViewQueryText.body(of: draft(
        sort: [],
        group: .tag("status-*"),
        render: .table,
        limit: "   "
    ))

    #expect(lines(in: body, beginningWith: "sort").isEmpty)
    #expect(lines(in: body, beginningWith: "group").isEmpty)
    #expect(lines(in: body, beginningWith: "limit").isEmpty)
    #expect(try ViewBlock.parse(body).render == .table)
}

@Test func anIncompleteTermContributesNoWhereClause() throws {
    let body = ViewQueryText.body(of: draft(terms: [.tag("")]))

    #expect(!body.contains("tag(\"\")"))
    #expect(lines(in: body, beginningWith: "where").isEmpty)
    #expect(try ViewBlock.parse(body).filter == .all)
}

// MARK: - Renderer column defaults

@Test func everyRenderersEffectiveColumnsAreOmitted() throws {
    for renderer in ViewBlock.Renderer.allCases {
        let group: ViewBlock.Grouping? = renderer == .board ? .tag("status-*") : nil
        let block = ViewBlock(group: group, render: renderer)

        #expect(ViewQueryText.columnsToWrite(block.effectiveColumns, render: renderer) == nil)

        let body = ViewQueryText.body(of: draft(
            group: group,
            render: renderer,
            columns: block.effectiveColumns
        ))
        #expect(lines(in: body, beginningWith: "columns").isEmpty)
        #expect(try ViewBlock.parse(body).effectiveColumns == block.effectiveColumns)
    }
}

@Test func columnsDifferingByOneElementArePreserved() throws {
    let selection: [ViewField] = [.title]

    #expect(ViewQueryText.columnsToWrite(selection, render: .board) == selection)

    let body = ViewQueryText.body(of: draft(
        group: .tag("status-*"),
        render: .board,
        columns: selection
    ))
    #expect(lines(in: body, beginningWith: "columns") == ["columns: [title]"])
    #expect(try ViewBlock.parse(body).columns == selection)
}

@Test func reorderedDefaultColumnsArePreserved() throws {
    let selection: [ViewField] = [.tags, .title]

    #expect(ViewQueryText.columnsToWrite(selection, render: .board) == selection)

    let body = ViewQueryText.body(of: draft(
        group: .tag("status-*"),
        render: .board,
        columns: selection
    ))
    #expect(lines(in: body, beginningWith: "columns") == ["columns: [tags, title]"])
    #expect(try ViewBlock.parse(body).columns == selection)
}

// MARK: - Filter terms and date bounds

@Test func everyFilterTermKindRoundTripsThroughTheParser() throws {
    let terms: [ViewFilter] = [
        .path("01 Progetti"),
        .tag("status-*"),
        .linksTo("Nota"),
        .linkedFrom("Nota"),
        .task(.open),
        .task(.done),
        .has(.tasksOpen),
        .text("frequenza propria"),
    ]

    for term in terms {
        let text = ViewQueryText.text(of: term)
        #expect(try ViewFilter.parse(text, line: 1) == term)
    }
}

@Test func dateBoundsUseOnlyTheParsersSpellings() throws {
    let day = try #require(CalendarDate(iso: "2026-08-01"))
    let bounds: [(ViewDateBound, String)] = [
        (.day(day), "2026-08-01"),
        (.today, "today"),
        (.daysBeforeToday(7), "today-7"),
        (.weekStart, "week-start"),
    ]

    for (bound, expectedSpelling) in bounds {
        let text = ViewQueryText.text(of: .comparison(.date, .atLeast, bound))
        let spelling = try #require(text.split(separator: " ").last.map(String.init))

        #expect(spelling == expectedSpelling)
        #expect(ViewDateBound.parse(spelling) == bound)
        #expect(try ViewFilter.parse(text, line: 1) == .comparison(.date, .atLeast, bound))
        #expect(!text.contains("oggi"))
        #expect(!text.contains("inizio-settimana"))
    }
}

// MARK: - Editor insertion stubs

@Test(arguments: [true, false])
func stubsAreClosedParseableViewFences(atLineStart: Bool) throws {
    let stub = ViewQueryText.stub(atLineStart: atLineStart)

    if atLineStart {
        #expect(stub.text.hasPrefix("```pergamenum-view\n"))
        #expect(stub.openingOffset == 0)
    } else {
        #expect(stub.text.hasPrefix("\n```pergamenum-view\n"))
        #expect(stub.openingOffset == 1)
    }

    let body = try #require(fenceBody(in: stub.text, openingOffset: stub.openingOffset))
    #expect(try ViewBlock.parse(body).render == .table)
    #expect(stub.text[stub.text.index(stub.text.startIndex, offsetBy: stub.openingOffset)...]
        .contains("\n```"))

    let run = EditorDecorationDelegate.viewBlockRun(
        in: stub.text as NSString,
        atParagraphStart: stub.openingOffset
    )
    #expect(run != nil)
    #expect(run?.block?.render == .table)
}

// MARK: - Task 6: R-05 / R-06 row-to-term contract

// Proposed production API for the coder, since Task 6's row model is not declared yet:
// ViewQueryTermRow.Value(kind:argument:field:comparison:) exposes a pure optional term.
// Kind is CaseIterable; comparisonFields and hasFields are the actual picker choices.
// No test-local row implementation: these assertions must exercise production conversion.

@Test("R-06: the row offers exactly the eight term kinds")
func termRowOffersExactlyEightKinds() {
    let expected: [ViewQueryTermRow.Kind] = [
        .path, .tag, .linksTo, .linkedFrom, .task, .has, .text, .comparison,
    ]
    #expect(ViewQueryTermRow.Kind.allCases.count == 8)
    #expect(expected.allSatisfy { ViewQueryTermRow.Kind.allCases.contains($0) })
}

@Test("R-06: each row kind converts its own argument")
func eachTermRowKindConvertsItsArgument() {
    #expect(ViewQueryTermRow.Value(kind: .path, argument: "01 */Clienti").term
        == .path("01 */Clienti"))
    #expect(ViewQueryTermRow.Value(kind: .tag, argument: "status-*").term
        == .tag("status-*"))
    #expect(ViewQueryTermRow.Value(kind: .linksTo, argument: "Nota destinazione").term
        == .linksTo("Nota destinazione"))
    #expect(ViewQueryTermRow.Value(kind: .linkedFrom, argument: "Nota origine").term
        == .linkedFrom("Nota origine"))
    #expect(ViewQueryTermRow.Value(kind: .task, argument: "open").term == .task(.open))
    #expect(ViewQueryTermRow.Value(kind: .has, argument: "tasks.open").term == .has(.tasksOpen))
    #expect(ViewQueryTermRow.Value(kind: .text, argument: "frequenza propria").term
        == .text("frequenza propria"))
    #expect(ViewQueryTermRow.Value(
        kind: .comparison, argument: "today-7", field: .modified, comparison: .atLeast
    ).term == .comparison(.modified, .atLeast, .daysBeforeToday(7)))
}

@Test("R-06: task rows preserve the done choice")
func doneTaskRowConvertsToDone() {
    #expect(ViewQueryTermRow.Value(kind: .task, argument: "done").term == .task(.done))
}

@Test("R-06 / C7: comparison choices are only date and modified")
func comparisonRowOffersOnlyDateFields() {
    let fields = ViewQueryTermRow.comparisonFields
    #expect(fields.count == 2)
    #expect(fields.contains(.date))
    #expect(fields.contains(.modified))
}

@Test("R-06 / C7: conversion refuses every non-date field", arguments: ViewField.allCases)
func comparisonRowRefusesNonDateFields(field: ViewField) {
    let row = ViewQueryTermRow.Value(
        kind: .comparison, argument: "today", field: field, comparison: .atLeast
    )
    if field == .date || field == .modified {
        #expect(row.term == .comparison(field, .atLeast, .today))
    } else {
        #expect(row.term == nil)
    }
}

@Test("R-06: has choices contain all 18 fields and nothing else")
func hasRowOffersEveryFieldExactlyOnce() {
    let fields = ViewQueryTermRow.hasFields
    #expect(fields.count == 18)
    #expect(ViewField.allCases.count == 18)
    for field in ViewField.allCases {
        #expect(fields.filter { $0 == field }.count == 1)
    }
}

@Test("R-06: has converts every field", arguments: ViewField.allCases)
func hasRowConvertsEveryField(field: ViewField) {
    #expect(ViewQueryTermRow.Value(kind: .has, argument: field.rawValue).term == .has(field))
}

@Test("R-06 / D7: every kind omits an empty argument", arguments: ViewQueryTermRow.Kind.allCases)
func emptyTermRowConvertsToNothing(kind: ViewQueryTermRow.Kind) throws {
    let row = ViewQueryTermRow.Value(
        kind: kind, argument: "", field: .modified, comparison: .atLeast
    )
    #expect(row.term == nil)
    let body = ViewQueryText.body(of: draft(terms: [row.term].compactMap { $0 }))
    #expect(lines(in: body, beginningWith: "where").isEmpty)
    #expect(try ViewBlock.parse(body).filter == .all)
}

@Test("R-06 / C1: date rows preserve symbolic bounds including zero days")
func comparisonRowsPreserveDateBounds() {
    let bounds: [(String, ViewDateBound)] = [
        ("today", .today),
        ("today-0", .daysBeforeToday(0)),
        ("today-7", .daysBeforeToday(7)),
        ("week-start", .weekStart),
    ]
    for field in [ViewField.date, .modified] {
        for (argument, bound) in bounds {
            #expect(ViewQueryTermRow.Value(
                kind: .comparison, argument: argument, field: field, comparison: .atLeast
            ).term == .comparison(field, .atLeast, bound))
        }
    }
}

@Test("R-05: Ambito path row values reach the from section joined with or")
func scopeRowGlobsAreJoinedWithOr() throws {
    let globs = ["01 */Clienti", "Archivio/2026?", "équipe/*"]
    let rows = globs.map { ViewQueryTermRow.Value(kind: .path, argument: $0) }
    let scope = try rows.map { row -> String in
        let term = try #require(row.term)
        guard case let .path(glob) = term else {
            Issue.record("An Ambito row must produce a path term")
            return ""
        }
        return glob
    }
    #expect(scope == globs)
    let body = ViewQueryText.body(of: draft(scope: scope))
    #expect(lines(in: body, beginningWith: "from") == [
        "from: path(\"01 */Clienti\") or path(\"Archivio/2026?\") or path(\"équipe/*\")",
    ])
    #expect(try ViewBlock.parse(body).scope == globs)
}

// MARK: - Task 7: R-11 live match count

private struct MatchCountCorpus: ViewCorpus {
    var records: [NoteRecord]

    func paths(forTitle title: String) -> [String] {
        records.filter { $0.title.lowercased() == title.lowercased() }.map(\.relativePath)
    }
}

private func matchCountCorpus() -> MatchCountCorpus {
    MatchCountCorpus(records: (0..<10).map { index in
        var frontmatter = Frontmatter.empty
        frontmatter.tags = ["note-\(index)", index < 4 ? "status-open" : "status-closed"]
            .compactMap(Tag.init)
        return NoteRecord(
            relativePath: "Clienti/Note \(index).md",
            title: "Note \(index)",
            frontmatter: frontmatter,
            linkTargets: [],
            embedTargets: [],
            tasks: [],
            modifiedAt: Date(timeIntervalSince1970: 0),
            byteSize: 100,
            contentHash: "fixture-\(index)"
        )
    })
}

@Test("R-11: re-picking the selected folder preserves the assembled debounce key")
func repickingFolderPreservesMatchCountKey() {
    let original = draft(scope: ["Clienti"], terms: [.tag("status-open")])
    let repicked = draft(scope: ["Clienti"], terms: [.tag("status-open")])
    repicked.scope[0] = "Clienti"

    #expect(ViewQueryText.body(of: repicked) == ViewQueryText.body(of: original))
}

@Test("R-11: toggling a column off and back on restores the assembled debounce key")
func restoringColumnRestoresMatchCountKey() {
    let original = draft(columns: [.title, .tags])
    let toggled = draft(columns: [.title, .tags])
    let initialKey = ViewQueryText.body(of: original)

    toggled.columns.removeLast()
    #expect(ViewQueryText.body(of: toggled) != initialKey)
    toggled.columns.append(.tags)
    #expect(ViewQueryText.body(of: toggled) == initialKey)
}

@Test("R-11: a recorded draft change changes the assembled debounce key")
func changedFilterChangesMatchCountKey() throws {
    let original = draft(terms: [.tag("status-open")])
    let changed = draft(terms: [.tag("status-closed")])
    let originalBody = ViewQueryText.body(of: original)
    let changedBody = ViewQueryText.body(of: changed)

    #expect(originalBody != changedBody)
    #expect(try ViewBlock.parse(originalBody).filter == .tag("status-open"))
    #expect(try ViewBlock.parse(changedBody).filter == .tag("status-closed"))
}

// Proposed production seam for the coder; the sheet's debounced task must use it:
// @MainActor static func matchCount(for block: ViewBlock, queries: ViewQuerySource?) -> Int?
// It returns queries.evaluate(block).total when a vault exists, otherwise nil.
// These tests deliberately do not supply a test-local implementation of that behavior.

@Test("R-11: the count is the evaluator total, including zero matches",
      arguments: [("note-*", 10), ("status-open", 4), ("note-0", 1), ("missing-*", 0)])
@MainActor
func matchCountUsesEvaluatorTotal(tag: String, expected: Int) throws {
    let corpus = matchCountCorpus()
    #expect(corpus.records.count == 10)
    let body = ViewQueryText.body(of: draft(scope: ["Clienti"], terms: [.tag(tag)]))
    let block = try ViewBlock.parse(body)
    let today = try #require(CalendarDate(iso: "2026-09-08"))
    let result = ViewEvaluator.evaluate(block, over: corpus, today: today)
    #expect(result.total == expected)

    var evaluatedBlocks: [ViewBlock] = []
    let queries = ViewQuerySource(evaluate: { received in
        evaluatedBlocks.append(received)
        return ViewEvaluator.evaluate(received, over: corpus, today: today)
    })
    let count = ViewQueryBuilderSheet.matchCount(for: block, queries: queries)

    #expect(count == Optional(expected))
    #expect(evaluatedBlocks == [block])
}

@Test("R-11: the count includes matches beyond the displayed row limit",
      arguments: [1, 4, 10, 11])
@MainActor
func matchCountIsNotLimitedRowCount(limit: Int) throws {
    let corpus = matchCountCorpus()
    let block = try ViewBlock.parse(ViewQueryText.body(of: draft(limit: String(limit))))
    let today = try #require(CalendarDate(iso: "2026-09-08"))
    let result = ViewEvaluator.evaluate(block, over: corpus, today: today)
    #expect(result.rows.count == min(limit, 10))
    #expect(result.total == 10)

    let queries = ViewQuerySource(evaluate: { received in
        ViewEvaluator.evaluate(received, over: corpus, today: today)
    })
    #expect(ViewQueryBuilderSheet.matchCount(for: block, queries: queries) == 10)
}

@Test("R-11: no vault means absent count even for a filter that would match nothing",
      arguments: ["note-*", "missing-*"])
@MainActor
func noVaultHasNoMatchCount(tag: String) throws {
    let block = try ViewBlock.parse(ViewQueryText.body(of: draft(terms: [.tag(tag)])))

    #expect(ViewQueryBuilderSheet.matchCount(for: block, queries: nil) == nil)
}
