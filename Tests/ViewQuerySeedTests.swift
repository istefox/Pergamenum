import Testing
@testable import Pergamenum

// Task 3 contract: ViewQueryDraft.seed(from:) is nonthrowing. rawWhere is the
// optional verbatim fallback; nil means the draft uses terms instead.
@Suite("View query seed: R-02 and R-03")
struct ViewQuerySeedTests {
    private static let completeBody = """
    from: path("Clienti") or path("Archivio")
    where: tag("client-*") and text("needle")
    sort: modified desc, title
    group: tag("status-*")
    render: board
    columns: [modified, title, tags]
    limit: 20
    """

    private static let keys = ["from", "where", "sort", "group", "render", "columns", "limit"]

    private func replacing(_ key: String, with value: String) -> String {
        Self.completeBody.split(separator: "\n").map { line in
            line.hasPrefix("\(key):") ? "\(key): \(value)" : String(line)
        }.joined(separator: "\n")
    }

    private func expectDefaults(_ draft: ViewQueryDraft) {
        #expect(draft.scope.isEmpty)
        #expect(draft.terms.isEmpty)
        #expect(draft.rawWhere == nil)
        #expect(draft.sort.isEmpty)
        #expect(draft.group == nil)
        #expect(draft.render == .table)
        #expect(draft.columns.isEmpty)
        #expect(draft.limit.isEmpty)
    }

    // Compare every unaffected section directly: the writer can intentionally omit
    // sections, so a serialized comparison alone could hide lost draft state.
    private func expectRecovery(_ body: String, brokenKey: String) throws {
        let original = try ViewBlock.parse(Self.completeBody)
        let draft = ViewQueryDraft.seed(from: body)

        #expect(draft.scope == (brokenKey == "from" ? [] : original.scope))
        let expectedTerms: [ViewFilter] = brokenKey == "where" ? [] : [.tag("client-*"), .text("needle")]
        #expect(draft.terms == expectedTerms)
        #expect(draft.rawWhere == nil)
        #expect(draft.sort == (brokenKey == "sort" ? [] : original.sort))
        #expect(draft.group == (brokenKey == "group" ? nil : original.group))
        #expect(draft.render == (brokenKey == "render" ? .table : original.render))
        #expect(draft.columns == (brokenKey == "columns" ? [] : original.columns))
        #expect(draft.limit == (brokenKey == "limit" ? "" : "20"))
    }

    @Test("R-02: all seven keys survive seed and writer round trip")
    func allSevenKeysRoundTrip() throws {
        let original = try ViewBlock.parse(Self.completeBody)
        let draft = ViewQueryDraft.seed(from: Self.completeBody)
        let written = ViewQueryText.body(of: draft)

        #expect(try ViewBlock.parse(written) == original)
        #expect(written == Self.completeBody)
    }

    @Test("R-02: a flat where seeds ordered filter rows")
    func flatWhereUsesRows() {
        let draft = ViewQueryDraft.seed(from: Self.completeBody)

        #expect(draft.terms == [.tag("client-*"), .text("needle")])
        #expect(draft.rawWhere == nil)
    }

    @Test("R-02, R-07 data: or stays verbatim while the other six keys seed")
    func disjunctionUsesRawText() throws {
        let raw = "tag(\"client-*\")  or   text(\"needle: exact\")"
        let body = replacing("where", with: raw)
        let original = try ViewBlock.parse(body)
        let draft = ViewQueryDraft.seed(from: body)

        #expect(draft.rawWhere == raw)
        #expect(draft.terms.isEmpty)
        #expect(draft.scope == original.scope)
        #expect(draft.sort == original.sort)
        #expect(draft.group == original.group)
        #expect(draft.render == original.render)
        #expect(draft.columns == original.columns)
        #expect(draft.limit == "20")
        let written = ViewQueryText.body(of: draft)
        #expect(written.split(separator: "\n").contains(Substring("where: \(raw)")))
        #expect(try ViewBlock.parse(written) == original)
    }

    @Test("R-03: invalid render defaults only render")
    func brokenRender() throws {
        try expectRecovery(replacing("render", with: "tabella"), brokenKey: "render")
    }

    @Test("R-03: absent sort field defaults only sort")
    func brokenSort() throws {
        try expectRecovery(replacing("sort", with: "creato desc"), brokenKey: "sort")
    }

    @Test("R-03: nonnumeric limit defaults only limit")
    func brokenLimit() throws {
        try expectRecovery(replacing("limit", with: "zero"), brokenKey: "limit")
    }

    @Test("R-03: non-path scope defaults only from")
    func brokenFrom() throws {
        try expectRecovery(replacing("from", with: "type-note"), brokenKey: "from")
    }

    @Test("R-03: bareword filter defaults only where, without raw fallback")
    func brokenWhere() throws {
        try expectRecovery(replacing("where", with: "type-note"), brokenKey: "where")
    }

    @Test("R-03: compound group defaults only group")
    func brokenGroup() throws {
        try expectRecovery(replacing("group", with: "tag(\"a\") and tag(\"b\")"), brokenKey: "group")
    }

    @Test("R-03: absent column defaults only columns")
    func brokenColumns() throws {
        try expectRecovery(replacing("columns", with: "[titolo]"), brokenKey: "columns")
    }

    @Test("R-03: prose and empty bodies seed defaults", arguments: ["", "\n  \n\t\n", "Ordinary prose\nNo query here"])
    func nonQueryBodies(body: String) {
        expectDefaults(ViewQueryDraft.seed(from: body))
    }

    @Test("R-02: board and group seed together in either line order", arguments: [true, false])
    func boardAndGroup(boardFirst: Bool) throws {
        let lines = ["render: board", "group: tag(\"status-*\")"]
        let body = (boardFirst ? lines : Array(lines.reversed())).joined(separator: "\n")
        let draft = ViewQueryDraft.seed(from: body)

        #expect(draft.render == .board)
        #expect(draft.group == .tag("status-*"))
        #expect(try ViewBlock.parse(ViewQueryText.body(of: draft)) == ViewBlock.parse(body))
    }

    @Test("R-02, R-03: duplicate keys keep the first occurrence", arguments: keys)
    func duplicateKeyKeepsFirst(key: String) throws {
        let alternatives = [
            "from": "path(\"Other\")",
            "where": "tag(\"other\")",
            "sort": "title desc",
            "group": "tag(\"other-*\")",
            "render": "list",
            "columns": "[title]",
            "limit": "1",
        ]
        let alternative = try #require(alternatives[key])
        let draft = ViewQueryDraft.seed(from: Self.completeBody + "\n\(key): \(alternative)")

        #expect(ViewQueryText.body(of: draft) == Self.completeBody)
        #expect(draft.rawWhere == nil)
    }

    @Test("R-03: an invalid first occurrence cannot be replaced by a valid duplicate", arguments: keys)
    func invalidFirstDuplicateKeepsDefault(key: String) throws {
        try expectRecovery("\(key): invalid\n" + Self.completeBody, brokenKey: key)
    }

    @Test("R-02: splitting on the first colon preserves colons inside values")
    func colonInsideValue() throws {
        let body = replacing("where", with: "text(\"status: open\")")
        let draft = ViewQueryDraft.seed(from: body)

        #expect(draft.terms == [.text("status: open")])
        #expect(draft.rawWhere == nil)
        #expect(try ViewBlock.parse(ViewQueryText.body(of: draft)) == ViewBlock.parse(body))
    }
}
