import Foundation
import Testing
@testable import Pergamenum

// ADR-0072, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-07.
//
// What `linksTo` and `linkedFrom` answer today, asserted literally, before Task 3 resolves each
// title once per evaluation instead of once per record: an alias, a different capitalisation, an
// ambiguous title (two paths), a self-link, an unresolved title and a title nobody links to.

/// Resolves a title the way `IndexSnapshot` plus aliases would: case-insensitive, over the title
/// and every alias.
private struct GraphCorpus: ViewCorpus {
    var records: [NoteRecord]

    func paths(forTitle title: String) -> [String] {
        let key = title.lowercased()
        return records
            .filter { $0.title.lowercased() == key || $0.frontmatter.aliases.contains { $0.lowercased() == key } }
            .map(\.relativePath)
    }
}

private func graphRecord(_ title: String, _ path: String, aliases: [String] = [], links: [String] = []) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.aliases = aliases
    return NoteRecord(
        relativePath: path, title: title, frontmatter: frontmatter, linkTargets: links,
        tasks: [], modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

/// `Alfa` links itself (lowercase) and `Beta`; `Beta` links `Alfa` through its alias; two notes
/// share the title `Gemello`; `Delta` links the ambiguous title in capitals and an unresolved one;
/// nobody links `Epsilon`.
private let graph = GraphCorpus(records: [
    graphRecord("Alfa", "A/Alfa.md", aliases: ["Primo"], links: ["Beta", "alfa"]),
    graphRecord("Beta", "B/Beta.md", links: ["Primo"]),
    graphRecord("Gemello", "X/Gemello.md"),
    graphRecord("Gemello", "Y/Gemello.md", links: ["Beta"]),
    graphRecord("Delta", "D/Delta.md", links: ["GEMELLO", "Nessuno"]),
    graphRecord("Epsilon", "E/Epsilon.md"),
])

struct GraphPinRow: Sendable, CustomStringConvertible {
    let filter: String
    let paths: [String]
    var description: String { filter }
}

enum GraphPinTable {
    static let rows: [GraphPinRow] = [
        GraphPinRow(filter: #"linksTo("Alfa")"#, paths: ["A/Alfa.md", "B/Beta.md"]),
        GraphPinRow(filter: #"linksTo("primo")"#, paths: ["A/Alfa.md", "B/Beta.md"]),
        GraphPinRow(filter: #"linksTo("ALFA")"#, paths: ["A/Alfa.md", "B/Beta.md"]),
        GraphPinRow(filter: #"linksTo("Beta")"#, paths: ["A/Alfa.md", "Y/Gemello.md"]),
        GraphPinRow(filter: #"linksTo("Gemello")"#, paths: ["D/Delta.md"]),
        GraphPinRow(filter: #"linksTo("Nessuno")"#, paths: []),
        GraphPinRow(filter: #"linksTo("Epsilon")"#, paths: []),
        GraphPinRow(filter: #"linkedFrom("Alfa")"#, paths: ["A/Alfa.md", "B/Beta.md"]),
        GraphPinRow(filter: #"linkedFrom("primo")"#, paths: ["A/Alfa.md", "B/Beta.md"]),
        GraphPinRow(filter: #"linkedFrom("ALFA")"#, paths: ["A/Alfa.md", "B/Beta.md"]),
        GraphPinRow(filter: #"linkedFrom("Beta")"#, paths: ["A/Alfa.md"]),
        GraphPinRow(filter: #"linkedFrom("Gemello")"#, paths: ["B/Beta.md"]),
        GraphPinRow(filter: #"linkedFrom("Delta")"#, paths: ["X/Gemello.md", "Y/Gemello.md"]),
        GraphPinRow(filter: #"linkedFrom("Nessuno")"#, paths: []),
        GraphPinRow(filter: #"linkedFrom("Epsilon")"#, paths: []),
        GraphPinRow(filter: #"linksTo("Beta") and linkedFrom("Alfa")"#, paths: ["A/Alfa.md"]),
        GraphPinRow(
            filter: #"not linksTo("Alfa")"#,
            paths: ["D/Delta.md", "E/Epsilon.md", "X/Gemello.md", "Y/Gemello.md"]
        ),
    ]
}

@Test(arguments: GraphPinTable.rows)
func linkTermsAnswerTheRecordedGraph(_ row: GraphPinRow) throws {
    let block = try ViewBlock.parse("render: list\nwhere: \(row.filter)")
    let result = ViewEvaluator.evaluate(block, over: graph)
    // Two notes share a title, and the evaluator's last-resort sort key is the title, so
    // their relative order is not part of what this pins: the set of paths and the total are.
    #expect(result.rows.map(\.path).sorted() == row.paths)
    #expect(result.total == row.paths.count)
}
