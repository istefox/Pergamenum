import Foundation

/// The vault as a view needs to see it.
///
/// Two members, because two is all the grammar of §D3 can ask for: the notes, and what a
/// wikilink target resolves to. `IndexSnapshot` conforms in two lines; a test conforms in
/// ten, which is why the evaluator takes this rather than the snapshot itself.
protocol ViewCorpus: Sendable {
    var records: [NoteRecord] { get }
    /// The note paths a wikilink target resolves to. None means unresolved, more than one
    /// means ambiguous (W-07).
    func paths(forTitle title: String) -> [String]
}

/// The rows a view draws.
struct ViewResult: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        var record: NoteRecord
        /// The block's `columns`, already resolved. A renderer that wants a field the
        /// block did not ask for still has the record.
        var values: [ViewField: ViewValue]

        var path: String { record.relativePath }
        var title: String { record.title }
    }

    struct Group: Equatable, Sendable {
        /// `nil` is the group for the notes the grouping does not name - the board's
        /// *Senza stato* column (§D5), which is the only way to take a status off a note
        /// with a gesture. The word itself belongs to the renderer, not here.
        var label: String?
        var rows: [Row]
    }

    /// One group with a `nil` label when the block has no `group`.
    var groups: [Group]
    /// How many notes matched, before `limit`.
    var total: Int

    var rows: [Row] { groups.flatMap(\.rows) }
}

/// Running a view against the index (ADR-0009 §D4, §D6).
///
/// Nothing is memoised: no materialised result, no cached row set, no "last known" list.
/// The index is rebuilt from the vault and a view is evaluated from the index, which is
/// principle 3 still holding after this feature exists.
enum ViewEvaluator {
    /// `body` is how `text()` reads a note. It is a parameter because `Core` does not
    /// touch the filesystem - `VaultSession` has the reader, and `VaultSession+Search` is
    /// the precedent for who opens files. The default reads nothing, so a `text()` term
    /// with no reader matches **nothing**: quietly matching everything is the failure
    /// that makes a result look like an answer.
    static func evaluate(
        _ block: ViewBlock,
        over corpus: some ViewCorpus,
        body: (NoteRecord) -> String? = { _ in nil }
    ) -> ViewResult {
        let context = Context(corpus: corpus)
        var rows: [ViewResult.Row] = []

        for record in corpus.records where context.isInScope(record, of: block) {
            var loaded: String??
            let read = { () -> String? in
                if let loaded { return loaded }
                let text = body(record)
                loaded = .some(text)
                return text
            }
            guard context.matches(block.filter, record, read) else { continue }
            var values: [ViewField: ViewValue] = [:]
            for field in block.columns { values[field] = field.value(of: record, in: context.graph) }
            rows.append(ViewResult.Row(record: record, values: values))
        }

        let total = rows.count
        rows = sorted(rows, by: block.sort, in: context.graph)
        if let limit = block.limit { rows = Array(rows.prefix(limit)) }
        return ViewResult(groups: grouped(rows, by: block.group, in: context.graph), total: total)
    }

    // MARK: Sorting

    private static func sorted(
        _ rows: [ViewResult.Row], by keys: [ViewBlock.SortKey], in graph: ViewGraph
    ) -> [ViewResult.Row] {
        rows.sorted { lhs, rhs in
            for key in keys {
                let left = key.field.value(of: lhs.record, in: graph)
                let right = key.field.value(of: rhs.record, in: graph)
                guard left != right else { continue }
                return key.descending ? right < left : left < right
            }
            // Always a last resort, so two notes that tie on every key still come back in
            // the same order twice running.
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    // MARK: Grouping

    private static func grouped(
        _ rows: [ViewResult.Row], by grouping: ViewBlock.Grouping?, in graph: ViewGraph
    ) -> [ViewResult.Group] {
        guard let grouping else { return [ViewResult.Group(label: nil, rows: rows)] }

        var named: [String: [ViewResult.Row]] = [:]
        var unnamed: [ViewResult.Row] = []
        for row in rows {
            let labels = self.labels(for: row, by: grouping, in: graph)
            // §D5: a note carrying two `status-*` tags appears in **both** columns. The
            // file really does say both, and a board that showed it once would be a board
            // that lies about the file to keep itself tidy.
            if labels.isEmpty { unnamed.append(row) } else {
                for label in labels { named[label, default: []].append(row) }
            }
        }

        // The unnamed group first: on a board it is *Senza stato*, and a column that
        // appeared halfway down the row of columns would read as one status among others.
        var groups = unnamed.isEmpty ? [] : [ViewResult.Group(label: nil, rows: unnamed)]
        groups += named.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ViewResult.Group(label: $0, rows: named[$0] ?? []) }
        return groups
    }

    private static func labels(
        for row: ViewResult.Row, by grouping: ViewBlock.Grouping, in graph: ViewGraph
    ) -> [String] {
        switch grouping {
        case .tag(let glob):
            row.record.frontmatter.tags.map(\.description).filter { Glob.matchesTag(glob, $0) }.sorted()
        case .field(let field):
            switch field.value(of: row.record, in: graph) {
            case .absent: []
            case .list(let items): items
            case .text(let text): text.isEmpty ? [] : [text]
            case .number(let value): [String(value)]
            case .day(let day): [day.description]
            }
        }
    }

    // MARK: Matching

    /// The graph facts, the lookups, and the one decision per term.
    ///
    /// A value built once per evaluation: `linkedFrom` and `unresolved` are each a pass
    /// over every record, and asking them inside the row loop is the quadratic version of
    /// the same answer.
    private struct Context {
        let graph: ViewGraph
        private let byPath: [String: NoteRecord]
        private let resolve: @Sendable (String) -> [String]

        init(corpus: some ViewCorpus) {
            var graph = ViewGraph()
            var byPath: [String: NoteRecord] = [:]
            for record in corpus.records { byPath[record.relativePath] = record }

            for record in corpus.records {
                for target in record.linkTargets {
                    let paths = corpus.paths(forTitle: target)
                    if paths.isEmpty {
                        graph.unresolved[record.relativePath, default: []].append(target)
                        continue
                    }
                    for path in paths where path != record.relativePath {
                        graph.incoming[path, default: []].append(record.title)
                    }
                }
            }
            for key in graph.incoming.keys { graph.incoming[key] = Array(Set(graph.incoming[key] ?? [])).sorted() }

            self.graph = graph
            self.byPath = byPath
            resolve = { corpus.paths(forTitle: $0) }
        }

        /// `from`: a scope, so an empty one is the whole vault rather than nothing.
        func isInScope(_ record: NoteRecord, of block: ViewBlock) -> Bool {
            block.scope.isEmpty || block.scope.contains { Glob.matchesPath($0, record.relativePath) }
        }

        /// The connectives here, the terms next door: one function over twelve cases
        /// scores 13 on SwiftLint's complexity rule, and `CommandActions.run` records why
        /// this codebase splits rather than disables.
        func matches(_ filter: ViewFilter, _ record: NoteRecord, _ body: () -> String?) -> Bool {
            switch filter {
            case .all: true
            case .and(let lhs, let rhs): matches(lhs, record, body) && matches(rhs, record, body)
            case .or(let lhs, let rhs): matches(lhs, record, body) || matches(rhs, record, body)
            case .not(let inner): !matches(inner, record, body)
            default: matchesTerm(filter, record, body)
            }
        }

        private func matchesTerm(_ filter: ViewFilter, _ record: NoteRecord, _ body: () -> String?) -> Bool {
            switch filter {
            case .path(let glob): Glob.matchesPath(glob, record.relativePath)
            case .tag(let glob): record.frontmatter.tags.contains { Glob.matchesTag(glob, $0.description) }
            case .linksTo(let title): linksTo(title, from: record)
            case .linkedFrom(let title): linkedFrom(title, to: record)
            case .task(let state): record.tasks.contains { state == .open ? $0.state.isOpen : $0.state == state }
            case .has(let field): !field.value(of: record, in: graph).isEmpty
            case .text(let needle): body().map { SearchQuery.fold($0).contains(SearchQuery.fold(needle)) } ?? false
            case .comparison(let field, let comparison, let bound):
                if case .day(let day) = field.value(of: record, in: graph) {
                    comparison.admits(day, against: bound)
                } else {
                    false
                }
            // Listed rather than defaulted, so a term added to the grammar is a compile
            // error here and not a filter that silently lets every note through.
            case .all, .and, .or, .not:
                true
            }
        }

        /// Resolved rather than spelled: `linksTo("Nota")` is about the note that link
        /// reaches, so an alias or a different capitalisation is the same edge.
        private func linksTo(_ title: String, from record: NoteRecord) -> Bool {
            let targets = Set(resolve(title))
            guard !targets.isEmpty else { return false }
            return record.linkTargets.contains { !targets.isDisjoint(with: resolve($0)) }
        }

        private func linkedFrom(_ title: String, to record: NoteRecord) -> Bool {
            resolve(title)
                .compactMap { byPath[$0] }
                .contains { source in
                    source.linkTargets.contains { resolve($0).contains(record.relativePath) }
                }
        }
    }
}
