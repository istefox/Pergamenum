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
