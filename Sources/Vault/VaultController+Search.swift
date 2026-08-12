import Foundation

/// Full-text search over the vault (SPEC §12).
///
/// An extension in its own file, reading through its own `NoteStore` rather than the
/// controller's: the store is a value type whose safety check is its own, so building
/// one here costs nothing and keeps the controller's private state private.
extension VaultController {
    struct SearchResult: Identifiable, Sendable {
        var id: String { path }
        var path: String
        var title: String
        /// The first matching line, for context in the result list.
        var excerpt: String
    }

    /// Full-text search across the vault (SPEC §12).
    ///
    /// Reads each note from disk rather than searching a cached copy of its text: the
    /// index holds structure, not content, and returning a hit for text that is no
    /// longer there is worse than taking a moment longer.
    func search(_ query: SearchQuery, limit: Int = 200) -> [SearchResult] {
        guard let root, !query.isEmpty else { return [] }
        let store = NoteStore(root: root)

        var results: [SearchResult] = []
        for record in index.allNotes {
            guard let (_, text) = try? store.read(record.relativePath) else { continue }
            guard query.matches(record: record, text: text) else { continue }

            results.append(SearchResult(
                path: record.relativePath,
                title: record.title,
                excerpt: Self.excerpt(for: query, in: text)
            ))
            if results.count >= limit { break }
        }
        return results
    }

    /// The first line containing a searched word or phrase.
    static func excerpt(for query: SearchQuery, in text: String) -> String {
        let needles = query.phrases + query.words
        guard !needles.isEmpty else { return "" }

        for line in text.components(separatedBy: "\n") {
            let folded = SearchQuery.fold(line)
            if needles.contains(where: { folded.contains(SearchQuery.fold($0)) }) {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
