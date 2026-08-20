import Foundation

/// Deciding whether one note answers a query, and which of its lines to show for it.
///
/// Apart from the parsing for one reason: `regex:` has to be compiled, and compiling it once
/// per note in a vault-wide loop is the difference between a search and a pause. `Matcher`
/// holds the compiled patterns for the length of a search; `SearchQuery` stays a value that
/// can be compared, stored and tested without one.
extension SearchQuery {
    struct Matcher {
        let query: SearchQuery
        private let required: [NSRegularExpression]
        private let forbidden: [NSRegularExpression]
        /// True when the query cannot be satisfied by anything, because a pattern in it does
        /// not compile.
        private let refusesEverything: Bool

        init(_ query: SearchQuery) {
            self.query = query
            required = query.patterns.compactMap(Self.compile)
            forbidden = query.negatedPatterns.compactMap(Self.compile)
            refusesEverything = !query.invalidPatterns.isEmpty
                || required.count != query.patterns.count
                || forbidden.count != query.negatedPatterns.count
        }

        /// `anchorsMatchLines` so `^## ` means the start of a heading rather than the start
        /// of the note, which is the only reading that is useful in a markdown file.
        private static func compile(_ pattern: String) -> NSRegularExpression? {
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines])
        }

        /// Whether a note satisfies every part of the query.
        ///
        /// `is:starred`, `linked:` and `orphan:` are not decided here: a note cannot answer
        /// them about itself. `VaultSession.search` applies those before it reads anything.
        func matches(record: NoteRecord, text: String) -> Bool {
            guard !query.isEmpty else { return true }
            guard !refusesEverything else { return false }
            return matchesText(text, title: record.title) && matchesMetadata(record)
        }

        /// The words, the phrases and the patterns, against the note as written.
        private func matchesText(_ text: String, title: String) -> Bool {
            let haystack = SearchQuery.fold(text + " " + title)

            for needle in query.words + query.phrases
            where !haystack.contains(SearchQuery.fold(needle)) { return false }
            for needle in query.negatedWords + query.negatedPhrases
            where haystack.contains(SearchQuery.fold(needle)) { return false }

            for expression in required where !expression.hasMatch(in: text) { return false }
            for expression in forbidden where expression.hasMatch(in: text) { return false }
            return true
        }

        /// The path, the tags, the modification day and the tasks: what the index knows
        /// about a note without opening it.
        private func matchesMetadata(_ record: NoteRecord) -> Bool {
            let pathHaystack = record.relativePath.lowercased()
            for path in query.paths where !pathHaystack.contains(path) { return false }
            for path in query.negatedPaths where pathHaystack.contains(path) { return false }

            let noteTags = Set(record.frontmatter.tags.map { $0.description.lowercased() })
                .union(record.tasks.flatMap { $0.tags.map { $0.description.lowercased() } })
            for tag in query.tags where !noteTags.contains(where: { $0.hasPrefix(tag) }) { return false }
            for tag in query.negatedTags where noteTags.contains(where: { $0.hasPrefix(tag) }) { return false }

            if let modified = query.modified, !modified.admits(CalendarDate(record.modifiedAt)) {
                return false
            }
            if let taskState = query.taskState {
                let wanted = record.tasks.contains { task in
                    taskState == .open ? task.state.isOpen : task.state == taskState
                }
                guard wanted else { return false }
            }
            return true
        }

        /// The first line the query hits, for context in the result list.
        ///
        /// A query made only of `is:starred`, `modified:` or `orphan:` has nothing to point
        /// at inside the note and returns an empty string rather than an arbitrary line.
        func excerpt(in text: String) -> String {
            let needles = query.phrases + query.words
            guard !needles.isEmpty || !required.isEmpty else { return "" }

            for line in text.components(separatedBy: "\n") {
                let folded = SearchQuery.fold(line)
                let hit = needles.contains { folded.contains(SearchQuery.fold($0)) }
                    || required.contains { $0.hasMatch(in: line) }
                if hit { return line.trimmingCharacters(in: .whitespaces) }
            }
            return ""
        }
    }

    /// Whether a note satisfies the query, for a caller judging a single note.
    ///
    /// A loop over the vault should build one `Matcher` instead: this compiles the query's
    /// patterns again on every call.
    func matches(record: NoteRecord, text: String) -> Bool {
        Matcher(self).matches(record: record, text: text)
    }
}

private extension NSRegularExpression {
    func hasMatch(in text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
