import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D4, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 2 - R-05.
//
// The inspector shows the first ten unresolved links. `unresolvedLinks(limit:)` builds source
// lists only for the entries it keeps, and must equal the prefix of the full sort for every
// limit: targets and source paths alike, with numeric, accented and case-variant targets.

private func linkingRecord(_ path: String, _ targets: [String]) -> NoteRecord {
    NoteRecord(
        relativePath: path, title: String(path.dropLast(3)), frontmatter: .empty, linkTargets: targets,
        tasks: [], modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

private let limitRecords = [
    linkingRecord("Uno.md", ["Nota 2", "Nota 10", "Nota 1", "Città", "citta", "Due"]),
    linkingRecord("Due.md", ["nota 10", "Éclair", "eclair", "Zeta", "alfa", "Alfa 3"]),
    linkingRecord("Tre.md", ["Beta", "Nota 2", "Ómicron", "omicron", "Gamma", "Delta", "Uno"]),
    linkingRecord("Quattro.md", ["Epsilon", "Nota 20", "zeta"]),
]

private func limitSnapshot() -> IndexSnapshot {
    var index = IndexSnapshot()
    index.replaceAll(with: .init(records: limitRecords, failures: [], boardTaskRecords: []), duration: .zero)
    return index
}

private func shape(_ entries: [(target: String, sources: [NoteRecord])]) -> [String] {
    entries.map { "\($0.target) <- \($0.sources.map(\.relativePath).joined(separator: ","))" }
}

@Test func theSnapshotHoldsMoreThanTenUnresolvedTargets() {
    let all = limitSnapshot().unresolvedLinks()
    #expect(all.count > 10)
    #expect(!all.contains { ["Uno", "Due"].contains($0.target) }, "a target a note answers to is resolved")
}

@Test(arguments: [0, 1, 10, -1, -2])
func aLimitEqualsThePrefixOfTheFullSort(_ requested: Int) {
    let index = limitSnapshot()
    let all = index.unresolvedLinks()
    // -1 stands for the whole count, -2 for five past it.
    let limit = requested == -1 ? all.count : requested == -2 ? all.count + 5 : requested

    let limited = index.unresolvedLinks(limit: limit)

    #expect(shape(limited) == shape(Array(all.prefix(limit))))
}
