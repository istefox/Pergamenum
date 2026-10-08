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
    /// - Parameter today: the day a relative bound resolves against (ADR-0014 §D3). Handed in
    ///   rather than read from the clock down in the filter, so a test can fix it: a test that
    ///   cannot is a test that fails one day a year. The default keeps every existing caller
    ///   unchanged, and every existing caller wants the machine's today.
    static func evaluate(
        _ block: ViewBlock,
        over corpus: some ViewCorpus,
        today: CalendarDate = .today,
        body: (NoteRecord) -> String? = { _ in nil }
    ) -> ViewResult {
        // Read once: a corpus computes its records on each read (ADR-0072).
        let records = corpus.records
        let context = Context(records: records, corpus: corpus, block: block, today: today)
        var rows: [ViewResult.Row] = []

        for record in records where context.isInScope(record) {
            var loaded: String??
            let read = { () -> String? in
                if let loaded { return loaded }
                let text = body(record)
                loaded = .some(text)
                return text
            }
            guard context.matches(record, read) else { continue }
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

    /// Each row's key values are read once, before the sort, and carried beside it: asked
    /// from inside the comparator they are recomputed for both operands of every
    /// comparison, and a field's value can be a walk of the graph.
    private static func sorted(
        _ rows: [ViewResult.Row], by keys: [ViewBlock.SortKey], in graph: ViewGraph
    ) -> [ViewResult.Row] {
        rows
            .map { row in
                (values: keys.map { $0.field.value(of: row.record, in: graph) }, row: row)
            }
            .sorted { lhs, rhs in
                for (position, key) in keys.enumerated() {
                    let left = lhs.values[position]
                    let right = rhs.values[position]
                    guard left != right else { continue }
                    return key.descending ? right < left : left < right
                }
                // Always a last resort, so two notes that tie on every key still come back
                // in the same order twice running.
                return lhs.row.title.localizedStandardCompare(rhs.row.title) == .orderedAscending
            }
            .map(\.row)
    }

    // MARK: Grouping

    private static func grouped(
        _ rows: [ViewResult.Row], by grouping: ViewBlock.Grouping?, in graph: ViewGraph
    ) -> [ViewResult.Group] {
        guard let grouping else { return [ViewResult.Group(label: nil, rows: rows)] }
        // A `.tag` grouping's pattern, folded once for every row rather than once per tag.
        let tagPattern: Glob.Pattern? = if case .tag(let glob) = grouping { Glob.Pattern(glob) } else { nil }

        var named: [String: [ViewResult.Row]] = [:]
        var unnamed: [ViewResult.Row] = []
        for row in rows {
            let labels = self.labels(for: row, by: grouping, tagPattern: tagPattern, in: graph)
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
        for row: ViewResult.Row, by grouping: ViewBlock.Grouping, tagPattern: Glob.Pattern?, in graph: ViewGraph
    ) -> [String] {
        switch grouping {
        case .tag(let glob):
            row.record.frontmatter.tags.map(\.description)
                .filter { (tagPattern ?? Glob.Pattern(glob)).matchesTag($0) }.sorted()
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

    /// A `ViewFilter` with its per-evaluation work done: titles resolved, patterns and
    /// needles folded, a relative bound read against the day (ADR-0072). Built once per
    /// evaluation, so the row loop only compares.
    private indirect enum PreparedFilter {
        case all
        case and(PreparedFilter, PreparedFilter)
        case or(PreparedFilter, PreparedFilter)
        case not(PreparedFilter)
        case path(Glob.Pattern)
        case tag(Glob.Pattern)
        /// The paths the title resolves to.
        case linksTo(Set<String>)
        /// The paths the title resolves to that are notes of the corpus.
        case linkedFrom([String])
        case task(TaskItem.State)
        case has(ViewField)
        /// The folded needle.
        case text(String)
        case comparison(ViewField, ViewFilter.Comparison, CalendarDate)
    }

    /// The graph facts, the lookups, and the one decision per term.
    ///
    /// A value built once per evaluation: `linkedFrom` and `unresolved` are each a pass
    /// over every record, and asking them inside the row loop is the quadratic version of
    /// the same answer. Every title is resolved once here and never again (ADR-0072).
    private struct Context {
        let graph: ViewGraph
        /// The day a relative bound means. Carried here rather than reached for, which is the
        /// whole of ADR-0014 §D3.
        let today: CalendarDate
        /// Per note path, every path its link targets resolve to, self-links included -
        /// unlike `graph.incoming`, which leaves them out.
        private let reaches: [String: Set<String>]
        private let scope: [Glob.Pattern]
        private let filter: PreparedFilter

        init(records: [NoteRecord], corpus: some ViewCorpus, block: ViewBlock, today: CalendarDate) {
            self.today = today
            var resolved: [String: [String]] = [:]
            func resolve(_ title: String) -> [String] {
                if let paths = resolved[title] { return paths }
                let paths = corpus.paths(forTitle: title)
                resolved[title] = paths
                return paths
            }

            var graph = ViewGraph()
            var byPath: [String: NoteRecord] = [:]
            var reaches: [String: Set<String>] = [:]
            for record in records {
                byPath[record.relativePath] = record
                var reached: Set<String> = []
                // ADR-0084 §D2: the one derivation, through the memo, so the corpus is still
                // asked once per title.
                let unresolved = UnresolvedTargets.of(record.linkTargets, resolving: resolve)
                if !unresolved.isEmpty {
                    graph.unresolved[record.relativePath, default: []].append(contentsOf: unresolved)
                }
                for target in record.linkTargets {
                    let paths = resolve(target)
                    reached.formUnion(paths)
                    for path in paths where path != record.relativePath {
                        graph.incoming[path, default: []].append(record.title)
                    }
                }
                // The last record for a path wins, as it does in `byPath`.
                reaches[record.relativePath] = reached
            }
            for key in graph.incoming.keys { graph.incoming[key] = Array(Set(graph.incoming[key] ?? [])).sorted() }

            self.graph = graph
            self.reaches = reaches
            scope = block.scope.map(Glob.Pattern.init)
            filter = Self.prepare(block.filter, today: today, resolve: resolve, byPath: byPath)
        }

        /// `from`: a scope, so an empty one is the whole vault rather than nothing.
        func isInScope(_ record: NoteRecord) -> Bool {
            scope.isEmpty || scope.contains { $0.matchesPath(record.relativePath) }
        }

        func matches(_ record: NoteRecord, _ body: () -> String?) -> Bool {
            matches(filter, record, body)
        }

        // MARK: Preparing

        /// The connectives here, the terms next door, for the same complexity reason as
        /// `matches` below.
        private static func prepare(
            _ filter: ViewFilter, today: CalendarDate,
            resolve: (String) -> [String], byPath: [String: NoteRecord]
        ) -> PreparedFilter {
            func recurse(_ inner: ViewFilter) -> PreparedFilter {
                prepare(inner, today: today, resolve: resolve, byPath: byPath)
            }
            return switch filter {
            case .all: .all
            case .and(let lhs, let rhs): .and(recurse(lhs), recurse(rhs))
            case .or(let lhs, let rhs): .or(recurse(lhs), recurse(rhs))
            case .not(let inner): .not(recurse(inner))
            default: prepareTerm(filter, today: today, resolve: resolve, byPath: byPath)
            }
        }

        private static func prepareTerm(
            _ filter: ViewFilter, today: CalendarDate,
            resolve: (String) -> [String], byPath: [String: NoteRecord]
        ) -> PreparedFilter {
            switch filter {
            case .path(let glob): .path(Glob.Pattern(glob))
            case .tag(let glob): .tag(Glob.Pattern(glob))
            // Resolved rather than spelled: `linksTo("Nota")` is about the note that link
            // reaches, so an alias or a different capitalisation is the same edge.
            case .linksTo(let title): .linksTo(Set(resolve(title)))
            case .linkedFrom(let title): .linkedFrom(resolve(title).filter { byPath[$0] != nil })
            case .task(let state): .task(state)
            case .has(let field): .has(field)
            case .text(let needle): .text(SearchQuery.fold(needle))
            case .comparison(let field, let comparison, let bound):
                .comparison(field, comparison, bound.resolved(on: today))
            // Listed rather than defaulted, so a term added to the grammar is a compile
            // error here and not a filter that silently lets every note through.
            case .all, .and, .or, .not: .all
            }
        }

        // MARK: Matching

        /// The connectives here, the terms next door: one function over twelve cases
        /// scores 13 on SwiftLint's complexity rule, and `CommandActions.run` records why
        /// this codebase splits rather than disables.
        private func matches(_ filter: PreparedFilter, _ record: NoteRecord, _ body: () -> String?) -> Bool {
            switch filter {
            case .all: true
            case .and(let lhs, let rhs): matches(lhs, record, body) && matches(rhs, record, body)
            case .or(let lhs, let rhs): matches(lhs, record, body) || matches(rhs, record, body)
            case .not(let inner): !matches(inner, record, body)
            default: matchesTerm(filter, record, body)
            }
        }

        private func matchesTerm(_ filter: PreparedFilter, _ record: NoteRecord, _ body: () -> String?) -> Bool {
            switch filter {
            case .path(let pattern): pattern.matchesPath(record.relativePath)
            case .tag(let pattern): record.frontmatter.tags.contains { pattern.matchesTag($0.description) }
            case .linksTo(let targets): !targets.isDisjoint(with: reaches[record.relativePath] ?? [])
            case .linkedFrom(let sources): sources.contains { reaches[$0]?.contains(record.relativePath) ?? false }
            case .task(let state): record.tasks.contains { state == .open ? $0.state.isOpen : $0.state == state }
            case .has(let field): !field.value(of: record, in: graph).isEmpty
            case .text(let needle): body().map { SearchQuery.fold($0).contains(needle) } ?? false
            case .comparison(let field, let comparison, let bound):
                if case .day(let day) = field.value(of: record, in: graph) {
                    comparison.admits(day, against: bound)
                } else {
                    false
                }
            case .all, .and, .or, .not:
                true
            }
        }
    }
}
