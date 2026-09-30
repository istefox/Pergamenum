import Foundation
import Testing
@testable import Pergamenum

// ADR-0072, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 3 - R-07.
//
// One view evaluation reads the corpus's records once and resolves each distinct title once.
// Counted at the corpus, the natural boundary the evaluator reads through: no production counter.
// Before Task 3 the records were read three times (`evaluate`, then twice in `Context.init`) and a
// title was resolved once per record per link, so a hub every note links to was resolved as many
// times as it was linked, and again for every row a `linksTo`/`linkedFrom` term tested.

/// What a `CountingCorpus` was asked, behind a lock: the evaluator may be handed a corpus from
/// any isolation, and the protocol is `Sendable`.
private final class WorkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var recordReads = 0
    private var titleCalls: [String: Int] = [:]

    func readRecords() { lock.withLock { recordReads += 1 } }
    func resolved(_ title: String) { lock.withLock { titleCalls[title, default: 0] += 1 } }

    var reads: Int { lock.withLock { recordReads } }
    var calls: [String: Int] { lock.withLock { titleCalls } }
}

private struct CountingCorpus: ViewCorpus {
    let stored: [NoteRecord]
    let counter: WorkCounter

    var records: [NoteRecord] {
        counter.readRecords()
        return stored
    }

    func paths(forTitle title: String) -> [String] {
        counter.resolved(title)
        let key = title.lowercased()
        return stored.filter { $0.title.lowercased() == key }.map(\.relativePath)
    }
}

private func countedRecord(_ title: String, links: [String]) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    return NoteRecord(
        relativePath: "N/\(title).md", title: title, frontmatter: frontmatter, linkTargets: links,
        tasks: [], modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

/// Twenty notes that each link the hub and one neighbour, the hub linking back to three of them,
/// and one unresolved target shared by every note.
private func hubCorpus() -> CountingCorpus {
    var records = (1...20).map { countedRecord("Nota \($0)", links: ["Hub", "Nota \($0 % 20 + 1)", "Assente"]) }
    records.append(countedRecord("Hub", links: ["Nota 1", "Nota 2", "Nota 3"]))
    return CountingCorpus(stored: records, counter: WorkCounter())
}

@Test(arguments: [
    #"linksTo("Hub") and linkedFrom("Hub")"#,
    #"linksTo("Hub") or linkedFrom("Hub")"#,
    #"not linksTo("Hub")"#,
])
func oneEvaluationReadsTheRecordsOnceAndResolvesEachTitleOnce(_ filter: String) throws {
    let corpus = hubCorpus()
    let block = try ViewBlock.parse("render: list\nwhere: \(filter)\ncolumns: [title, linkedFrom, unresolved]")

    let result = ViewEvaluator.evaluate(block, over: corpus)

    #expect(result.total > 0)
    #expect(corpus.counter.reads == 1)
    let repeated = corpus.counter.calls.filter { $0.value > 1 }
    #expect(repeated.isEmpty, "resolved more than once: \(repeated)")
}
