import Foundation
import Testing
@testable import Pergamenum

// ADR-0072, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-08.
//
// A literal table of what `Glob` answers today, so folding a pattern once (Task 3) cannot change
// a single match: no wildcard, `*`, `?`, `*` alone, the empty pattern, the backtracking case, and
// accents and capitals on both sides. The same table pins search's `tag:`/`-tag:` rule and a
// view's `text()` needle, the two other places the same folding runs per record.

struct GlobRow: Sendable, CustomStringConvertible {
    let pattern: String
    let candidate: String
    let expected: Bool
    var description: String { "\(pattern.debugDescription) ~ \(candidate.prefix(40).debugDescription)" }

    init(_ pattern: String, _ candidate: String, _ expected: Bool) {
        self.pattern = pattern
        self.candidate = candidate
        self.expected = expected
    }
}

private let longRun = String(repeating: "a", count: 200)

enum GlobTable {
    /// `Glob.matchesTag`: exact (folded) without a wildcard, a whole-string glob with one.
    static let tag: [GlobRow] = [
        GlobRow("client-acme", "client-acme", true),
        GlobRow("client-acme", "client-acme-industriale", false),
        GlobRow("CLIENT-ACME", "client-acme", true),
        GlobRow("client-acme", "Client-Acme", true),
        GlobRow("client-*", "client-acme", true),
        GlobRow("client-*", "project-client", false),
        GlobRow("*-acme", "client-acme", true),
        GlobRow("client-acm?", "client-acme", true),
        GlobRow("client-acm?", "client-acm", false),
        GlobRow("*", "topic-gomma", true),
        GlobRow("*", "", true),
        GlobRow("", "", true),
        GlobRow("", "client-acme", false),
        GlobRow("équipe-*", "Equipe-nord", true),
        GlobRow("topic-caffè", "topic-caffe", true),
        GlobRow("TOPIC-CAFFÈ", "topic-caffe", true),
        GlobRow("topic-caffe", "topic-caff", false),
    ]

    /// `Glob.matchesPath`: a folded prefix without a wildcard, a whole-path glob with one.
    static let path: [GlobRow] = [
        GlobRow("Clienti", "Clienti/Rossi.md", true),
        GlobRow("clienti", "Clienti/Rossi.md", true),
        GlobRow("Clienti", "Clienti2/Rossi.md", true),
        GlobRow("Clienti/", "Clienti2/Rossi.md", false),
        GlobRow("Progetti", "Clienti/Progetti.md", false),
        GlobRow("", "Clienti/Rossi.md", true),
        GlobRow("*", "Clienti/Rossi.md", true),
        GlobRow("Clienti/*", "Clienti/Rossi.md", true),
        GlobRow("Clienti/*", "Fornitori/Rossi.md", false),
        GlobRow("Clienti/*.md", "Clienti/Sub/Rossi.md", true),
        GlobRow("*.md", "Nota.MD", true),
        GlobRow("*.md", "Nota.canvas", false),
        GlobRow("?lienti/*", "Clienti/a", true),
        GlobRow("?lienti/*", "lienti/a", false),
        GlobRow("équipe/*", "Equipe/x", true),
        GlobRow("Équipe", "equipe/nota.md", true),
        GlobRow("Equipe", "Équipe/nota.md", true),
        GlobRow("a*a*a*", longRun + "/b.md", true),
        GlobRow("a*a*a*b", longRun, false),
        GlobRow("a*a*a*b.md", longRun + "/b.md", true),
    ]

    /// `Glob.matches`: always the whole candidate, wildcard or not.
    static let whole: [GlobRow] = [
        GlobRow("abc", "abc", true),
        GlobRow("abc", "abcd", false),
        GlobRow("abc", "ABC", true),
        GlobRow("", "", true),
        GlobRow("", "a", false),
        GlobRow("a?c", "abc", true),
        GlobRow("a?c", "ac", false),
        GlobRow("*c", "abc", true),
        GlobRow("a*", "", false),
        GlobRow("*", "", true),
        GlobRow("**", "x", true),
        GlobRow("A*", "abc", true),
        GlobRow("è?", "ex", true),
        GlobRow("a*a*a*b", longRun, false),
    ]
}

@Test(arguments: GlobTable.tag)
func globMatchesTagAnswersTheRecordedTable(_ row: GlobRow) {
    #expect(Glob.matchesTag(row.pattern, row.candidate) == row.expected)
}

@Test(arguments: GlobTable.path)
func globMatchesPathAnswersTheRecordedTable(_ row: GlobRow) {
    #expect(Glob.matchesPath(row.pattern, row.candidate) == row.expected)
}

@Test(arguments: GlobTable.whole)
func globMatchesAnswersTheRecordedTable(_ row: GlobRow) {
    #expect(Glob.matches(row.pattern, row.candidate) == row.expected)
}

// Task 3: the same tables through a pattern prepared once, which is what a view and a search
// now hold for the whole evaluation.

@Test(arguments: GlobTable.tag)
func aPreparedPatternMatchesTagAsTheRecordedTable(_ row: GlobRow) {
    #expect(Glob.Pattern(row.pattern).matchesTag(row.candidate) == row.expected)
}

@Test(arguments: GlobTable.path)
func aPreparedPatternMatchesPathAsTheRecordedTable(_ row: GlobRow) {
    #expect(Glob.Pattern(row.pattern).matchesPath(row.candidate) == row.expected)
}

@Test(arguments: GlobTable.whole)
func aPreparedPatternMatchesAsTheRecordedTable(_ row: GlobRow) {
    #expect(Glob.Pattern(row.pattern).matches(row.candidate) == row.expected)
}

@Test func onePreparedPatternAnswersManyCandidatesAsIfPreparedForEach() {
    let pattern = Glob.Pattern("Clienti/*/Offerta?")
    let candidates = ["Clienti/Rossi/Offerta1", "clienti/città/offertaX", "Clienti/Offerta1", "Clienti/a/b/OffertaZ"]
    let reused = candidates.map(pattern.matchesPath)
    #expect(reused == candidates.map { Glob.matchesPath("Clienti/*/Offerta?", $0) })
    #expect(reused == [true, true, false, true])
}

// MARK: - Search's `tag:` and `-tag:`, over frontmatter and task tags

private func searchRecord(tags: [String], taskLine: String? = nil) -> NoteRecord {
    var frontmatter = Frontmatter.empty
    frontmatter.date = CalendarDate(iso: "2026-08-11")
    frontmatter.tags = tags.compactMap(Tag.init)
    let path = "01 Progetti/Nota.md"
    return NoteRecord(
        relativePath: path, title: "Nota", frontmatter: frontmatter, linkTargets: [],
        tasks: taskLine.map { TaskParser.tasks(in: $0, sourcePath: path) } ?? [],
        modifiedAt: .distantPast, byteSize: 0, contentHash: "-"
    )
}

struct SearchTagRow: Sendable, CustomStringConvertible {
    let query: String
    let frontmatterTags: [String]
    let taskLine: String?
    let expected: Bool
    var description: String { "\(query) over \(frontmatterTags) \(taskLine ?? "")" }
}

enum SearchTagTable {
    static let rows: [SearchTagRow] = [
        SearchTagRow(query: "tag:client-acme", frontmatterTags: ["client-acme"], taskLine: nil, expected: true),
        SearchTagRow(
            query: "tag:client-acme", frontmatterTags: ["client-acme-industriale"], taskLine: nil, expected: false
        ),
        SearchTagRow(
            query: "tag:client-acme", frontmatterTags: [], taskLine: "- [ ] Chiamare #client-acme", expected: true
        ),
        SearchTagRow(
            query: "tag:client-*", frontmatterTags: [], taskLine: "- [ ] Chiamare #client-acme", expected: true
        ),
        SearchTagRow(query: "tag:client-*", frontmatterTags: ["project-client"], taskLine: nil, expected: false),
        SearchTagRow(query: "tag:CLIENT-ACME", frontmatterTags: ["client-acme"], taskLine: nil, expected: true),
        SearchTagRow(query: "tag:#client-acme", frontmatterTags: ["client-acme"], taskLine: nil, expected: true),
        SearchTagRow(query: "tag:client-acm?", frontmatterTags: ["client-acme"], taskLine: nil, expected: true),
        SearchTagRow(
            query: "-tag:client-acme", frontmatterTags: [], taskLine: "- [ ] Chiamare #client-acme", expected: false
        ),
        SearchTagRow(query: "-tag:client-*", frontmatterTags: ["project-presse"], taskLine: nil, expected: true),
        SearchTagRow(query: "-tag:status-a", frontmatterTags: ["status-attivo"], taskLine: nil, expected: true),
        SearchTagRow(query: "tag:status-a", frontmatterTags: ["status-attivo"], taskLine: nil, expected: false),
        SearchTagRow(
            query: "tag:type-* -tag:status-*", frontmatterTags: ["type-note"],
            taskLine: "- [ ] Fare #status-aperto", expected: false
        ),
    ]
}

@Test(arguments: SearchTagTable.rows)
func searchTagRuleAnswersTheRecordedTable(_ row: SearchTagRow) {
    let record = searchRecord(tags: row.frontmatterTags, taskLine: row.taskLine)
    #expect(SearchQuery(row.query).matches(record: record, text: "Corpo della nota.") == row.expected)
}

// MARK: - A view's `text()` needle, accents and case

private struct OneNoteCorpus: ViewCorpus {
    var records: [NoteRecord]
    func paths(forTitle title: String) -> [String] { [] }
}

struct TextNeedleRow: Sendable, CustomStringConvertible {
    let needle: String
    let body: String
    let expectedTotal: Int
    var description: String { "\(needle) in \(body)" }
}

enum TextNeedleTable {
    static let rows: [TextNeedleRow] = [
        TextNeedleRow(needle: "TRASMISSIBILITA", body: "Trasmissibilità sotto radice", expectedTotal: 1),
        TextNeedleRow(needle: "città", body: "UNA CITTA DI PROVINCIA", expectedTotal: 1),
        TextNeedleRow(needle: "Équipe", body: "l'equipe del reparto", expectedTotal: 1),
        TextNeedleRow(needle: "frequenza", body: "La Frequenza propria", expectedTotal: 1),
        TextNeedleRow(needle: "gomma-metallo", body: "articoli tecnici in gomma e metallo", expectedTotal: 0),
    ]
}

@Test(arguments: TextNeedleTable.rows)
func viewTextNeedleAnswersTheRecordedTable(_ row: TextNeedleRow) throws {
    let block = try ViewBlock.parse("render: list\nwhere: text(\"\(row.needle)\")")
    let corpus = OneNoteCorpus(records: [searchRecord(tags: ["type-note"])])
    let result = ViewEvaluator.evaluate(block, over: corpus) { _ in row.body }
    #expect(result.total == row.expectedTotal)
}
