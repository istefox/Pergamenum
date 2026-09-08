import Testing
@testable import Pergamenum

private func parsed(_ source: String) throws -> ViewFilter {
    try ViewFilter.parse(source, line: 1)
}

// MARK: - R-06: every leaf remains available to the query builder

@Test func allProducesNoTerms() throws {
    let filter = try ViewBlock.parse("render: list").filter

    #expect(ViewQueryFlattening.terms(of: filter) == [])
}

@Test func pathLeafProducesItself() throws {
    let filter = try parsed("path(\"Clienti\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func tagLeafProducesItself() throws {
    let filter = try parsed("tag(\"x\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func linksToLeafProducesItself() throws {
    let filter = try parsed("linksTo(\"Nota\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func linkedFromLeafProducesItself() throws {
    let filter = try parsed("linkedFrom(\"Nota\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func openTaskLeafProducesItself() throws {
    let filter = try parsed("task(open)")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func hasOpenTasksLeafProducesItself() throws {
    let filter = try parsed("has(tasks.open)")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func textLeafProducesItself() throws {
    let filter = try parsed("text(\"frequenza propria\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func dateComparisonLeafProducesItself() throws {
    let filter = try parsed("date >= 2026-08-01")

    #expect(ViewQueryFlattening.terms(of: filter) == [filter])
}

@Test func leftAssociatedAndPreservesSourceOrder() throws {
    let first = try parsed("path(\"Clienti\")")
    let second = try parsed("tag(\"x\")")
    let third = try parsed("text(\"needle\")")
    let filter = try parsed("path(\"Clienti\") and tag(\"x\") and text(\"needle\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [first, second, third])
}

@Test func parenthesizedAndPreservesSourceOrder() throws {
    let first = try parsed("path(\"Clienti\")")
    let second = try parsed("tag(\"x\")")
    let third = try parsed("text(\"needle\")")
    let filter = try parsed("(path(\"Clienti\") and tag(\"x\")) and text(\"needle\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [first, second, third])
}

@Test func comparisonAndCallRemainFlatTerms() throws {
    let first = try parsed("date >= today")
    let second = try parsed("tag(\"x\")")
    let filter = try parsed("date >= today and tag(\"x\")")

    #expect(ViewQueryFlattening.terms(of: filter) == [first, second])
}

// MARK: - R-07: non-flat Boolean shapes require the raw-text fallback

@Test func orIsNotFlat() throws {
    let filter = try parsed("path(\"Clienti\") or tag(\"x\")")

    #expect(ViewQueryFlattening.terms(of: filter) == nil)
}

@Test func notIsNotFlat() throws {
    let filter = try parsed("not path(\"Clienti\")")

    #expect(ViewQueryFlattening.terms(of: filter) == nil)
}

@Test func andContainingNotIsNotFlat() throws {
    let filter = try parsed("path(\"Clienti\") and not tag(\"x\")")

    #expect(ViewQueryFlattening.terms(of: filter) == nil)
}

@Test func andContainingOrIsNotFlat() throws {
    let filter = try parsed("path(\"Clienti\") and (tag(\"x\") or text(\"needle\"))")

    #expect(ViewQueryFlattening.terms(of: filter) == nil)
}
