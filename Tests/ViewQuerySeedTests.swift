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

// Task 5 contract comes from the batch brief. Production declarations belong to
// the coder; tests call the real validation entry point without a test-side stub.
@MainActor
@Suite("ViewQueryValidation: R-02, R-07 and R-12")
struct ViewQueryValidation {
    @Test("R-02: a complete draft validates to the writer's round-tripped block")
    func completeDraftRoundTrips() throws {
        let body = """
        from: path("Clienti") or path("Archivio")
        where: tag("client-*") and text("needle")
        sort: modified desc, title
        group: tag("status-*")
        render: board
        columns: [modified, title, tags]
        limit: 20
        """
        let draft = ViewQueryDraft.seed(from: body)
        let written = try ViewBlock.parse(ViewQueryText.body(of: draft))
        let result = ViewQueryBuilderSheet.validation(of: draft)

        #expect(try result.get() == written)
        #expect(try result.get() == ViewBlock.parse(body))
    }

    @Test("R-12: a board without a group preserves assemble's own error")
    func boardWithoutGroup() throws {
        var draft = ViewQueryDraft.seed(from: "render: table")
        draft.render = .board
        let expected = try #require(#expect(throws: ViewBlockError.self) {
            try ViewBlock.parse(ViewQueryText.body(of: draft))
        })
        let actual = try failure(of: draft)

        #expect(actual.reason.contains("aggiungi «group»"))
        #expect(actual.line == expected.line)
        #expect(actual.reason == expected.reason)
        #expect(actual.description == expected.description)
    }

    @Test("R-07, R-12: invalid raw where preserves the filter parser's line and reason",
          arguments: ["(tag(\"client-*\")", "tag(\"client-*\") or", "task(cancelled)"])
    func invalidRawWhere(raw: String) throws {
        var draft = ViewQueryDraft.seed(from: "render: table")
        draft.scope = ["Clienti"]
        draft.rawWhere = raw
        let bodyLines = ViewQueryText.body(of: draft).split(separator: "\n", omittingEmptySubsequences: false)
        let whereIndex = try #require(bodyLines.firstIndex { $0.hasPrefix("where:") })
        // A preceding from line catches validators that always pass line 1.
        #expect(whereIndex > 0)
        let expected = try #require(#expect(throws: ViewBlockError.self) {
            try ViewFilter.parse(raw, line: whereIndex + 1)
        })
        let actual = try failure(of: draft)

        #expect(actual.line == expected.line)
        #expect(actual.reason == expected.reason)
        #expect(actual.description == expected.description)
    }

    @Test("R-12, ADR D7: an incomplete row fails with a reason even beside complete rows",
          arguments: [false, true])
    func incompleteTerm(hasCompleteRow: Bool) throws {
        var draft = ViewQueryDraft.seed(from: "render: table")
        draft.terms = hasCompleteRow ? [.text("needle"), .tag("")] : [.tag("")]
        // D7's explicit exception: the writer omits unfinished rows, so the body
        // parses, but validation must prevent silently committing their omission.
        _ = try ViewBlock.parse(ViewQueryText.body(of: draft))
        let actual = try failure(of: draft)

        #expect(actual.reason.contains { !$0.isWhitespace })
        #expect(actual.description.contains(actual.reason))
    }

    @Test("R-12: validation and ViewBlock.parse agree for complete rows across a draft table")
    func parserEquivalence() throws {
        var drafts: [ViewQueryDraft] = []
        for renderer in ViewBlock.Renderer.allCases {
            var draft = ViewQueryDraft.seed(from: "render: table")
            draft.render = renderer
            drafts.append(draft)
            draft.group = .tag("status-*")
            draft.scope = ["Clienti", "Archivio"]
            draft.terms = [.tag("client-*"), .text("needle")]
            drafts.append(draft)
        }
        // Empty/whitespace, the positive boundary, invalid numbers and overflow:
        // the parser supplies the expected outcome, never a second numeric checker.
        for limit in ["", "   ", "-1", "0", "1", "20", String(Int.max), String(Int.max) + "0", "1.5", "no"] {
            var draft = ViewQueryDraft.seed(from: "render: table")
            draft.limit = limit
            drafts.append(draft)
        }
        for raw in ["tag(\"client-*\") or text(\"needle\")", "(tag(\"a\") or tag(\"b\")) and text(\"x\")",
                    "tag(\"a\") or", "(tag(\"a\")"] {
            var draft = ViewQueryDraft.seed(from: "render: table")
            draft.rawWhere = raw
            drafts.append(draft)
        }

        for draft in drafts {
            let body = ViewQueryText.body(of: draft)
            let parsed = Result { try ViewBlock.parse(body) }
            switch (parsed, ViewQueryBuilderSheet.validation(of: draft)) {
            case let (.success(expected), .success(actual)):
                #expect(actual == expected, "Body: \(body)")
            case let (.failure(error), .failure(actual)):
                let expected = try #require(error as? ViewBlockError)
                #expect(actual.line == expected.line, "Body: \(body)")
                #expect(actual.reason == expected.reason, "Body: \(body)")
            case (.success, .failure):
                Issue.record("Validation rejected a parser-accepted body: \(body)")
            case (.failure, .success):
                Issue.record("Validation accepted a parser-rejected body: \(body)")
            }
        }
    }

    private func failure(of draft: ViewQueryDraft) throws -> ViewBlockError {
        try #require(#expect(throws: ViewBlockError.self) {
            try ViewQueryBuilderSheet.validation(of: draft).get()
        })
    }
}
