import Foundation
import Testing
@testable import Pergamenum

// PG-260 (Audit Fable chain 7), R-01…R-05: search `tag:` and `-tag:` use the views' rule,
// `Glob.matchesTag` - exact without a wildcard, glob with one - where they used a prefix.

private func record(tags: [String], tasks: [TaskItem] = []) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = tags.compactMap(Tag.init)
    return NoteRecord(
        relativePath: "01 Progetti/Nota.md", title: "Nota", frontmatter: frontmatter,
        linkTargets: [], tasks: tasks, modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

private func search(_ raw: String, _ record: NoteRecord) -> Bool {
    SearchQuery(raw).matches(record: record, text: "Corpo della nota.")
}

private struct OneRecordCorpus: ViewCorpus {
    var records: [NoteRecord]
    func paths(forTitle title: String) -> [String] { [] }
}

/// How many notes a view with `where: <filter>` finds over a corpus of exactly one.
private func viewTotal(_ filter: String, over record: NoteRecord) throws -> Int {
    let block = try ViewBlock.parse("render: list\nwhere: \(filter)")
    return ViewEvaluator.evaluate(block, over: OneRecordCorpus(records: [record])).total
}

// MARK: - The rule, one case at a time

@Test func anExactTagDoesNotTakeALongerOne() {
    #expect(search("tag:client-acme", record(tags: ["client-acme"])))
    #expect(!search("tag:client-acme", record(tags: ["client-acme-industriale"])))
}

@Test func aNegatedTagExcludesOnlyThatTag() {
    #expect(!search("-tag:status-a", record(tags: ["status-a"])))
    #expect(search("-tag:status-a", record(tags: ["status-attivo"])))
    #expect(search("-tag:status-a", record(tags: ["status-archiviato"])))
}

@Test func aStarMatchesAFamily() {
    #expect(search("tag:client-*", record(tags: ["client-acme"])))
    #expect(search("tag:client-*", record(tags: ["client-acme-industriale"])))
    #expect(!search("tag:client-*", record(tags: ["project-client"])))
}

@Test func aQuestionMarkMatchesOneCharacter() {
    #expect(search("tag:client-acm?", record(tags: ["client-acme"])))
    #expect(!search("tag:client-acm?", record(tags: ["client-acme-industriale"])))
    #expect(!search("tag:client-acm?", record(tags: ["client-acm"])))
}

// MARK: - Search and views cannot drift (R-04)

/// One table fed to both matchers: exact, prefix only, suffix only, `*` leading, trailing
/// and inner, `?`, an uppercase pattern, and the `status-a`/`status-attivo` pair.
private let tagPairs: [(String, String)] = [
    ("client-acme", "client-acme"),
    ("client-acme", "client-acme-industriale"),
    ("acme-industriale", "client-acme-industriale"),
    ("*-acme", "client-acme"),
    ("*-acme", "client-acme-industriale"),
    ("client-*", "client-acme-industriale"),
    ("client-*-industriale", "client-acme-industriale"),
    ("client-*-industriale", "client-acme"),
    ("client-acm?", "client-acme"),
    ("client-acm?", "client-acme-industriale"),
    ("CLIENT-ACME", "client-acme"),
    ("Client-*", "client-acme"),
    ("status-a", "status-attivo"),
    ("status-a", "status-a"),
]

@Test(arguments: tagPairs)
func searchAndViewsAgreeOnEveryTagPair(pattern: String, tag: String) throws {
    let note = record(tags: [tag])
    #expect(note.frontmatter.tags.map(\.description) == [tag])

    let rule = Glob.matchesTag(pattern, tag)
    #expect(search("tag:\(pattern)", note) == rule)
    #expect(try viewTotal("tag(\"\(pattern)\")", over: note) == (rule ? 1 : 0))

    #expect(search("-tag:\(pattern)", note) == !rule)
    #expect(try viewTotal("not tag(\"\(pattern)\")", over: note) == (rule ? 0 : 1))
}

// MARK: - Task tags are still searched (R-05)

@Test func aTaskTagIsStillSearched() throws {
    let task = try #require(
        TaskParser.parse(line: "- [ ] Chiamare #client-acme-industriale", sourcePath: "x.md", lineIndex: 0)
    )
    let note = record(tags: ["type-note"], tasks: [task])

    #expect(search("tag:client-acme-industriale", note))
    #expect(!search("tag:client-acme", note))
    #expect(search("tag:client-*", note))
}
