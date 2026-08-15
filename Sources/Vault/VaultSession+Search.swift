import Foundation

/// Full-text search over the vault (SPEC §12), and the conformance linter of §4.7.
///
/// Both read the files rather than the index: the index holds structure, not content,
/// and the linter's whole job is to report what is on disk. A stale row would return a
/// hit for text that is no longer there, or call a note clean after someone edited it
/// in Obsidian.
extension VaultSession {
    struct SearchResult: Identifiable, Sendable {
        var id: String { path }
        var path: String
        var title: String
        /// The first matching line, for context in the result list.
        var excerpt: String
    }

    /// Full-text search across the vault (SPEC §12).
    func search(_ query: SearchQuery, limit: Int = 200) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        var results: [SearchResult] = []
        for record in index.allNotes {
            guard let (_, text) = try? read(record.relativePath) else { continue }
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

    // MARK: Conformance

    /// Validates any note in the vault by path, for the vault-wide conformance view.
    func violations(forRecordAt relativePath: String) -> NoteViolations? {
        guard let (_, text) = try? read(relativePath) else { return nil }
        return violations(
            path: relativePath,
            title: NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent),
            text: text
        )
    }

    /// Validates a note's text against every convention rule.
    func violations(path: String, title: String, text: String) -> NoteViolations {
        let document = NoteDocument.parse(text)
        let category = NoteName.category(
            forFileName: (path as NSString).lastPathComponent,
            dailyFolder: settings.dailyFolder,
            path: path
        )
        let discrepancies = RelatedSection.discrepancies(
            frontmatterRelated: document.frontmatter.related,
            sectionLinks: RelatedSection.parse(from: document.body)
        )
        // A daily note is judged by its own naming rule: `20260811` would fail the
        // ordinary title check for looking like a version-less date, and passing it
        // through `validate` would report every daily note as non-conformant.
        let nameViolations = category == .daily
            ? NoteName.validateDaily(title)
            : NoteName.validate(title)

        return NoteViolations(
            name: nameViolations,
            frontmatter: FrontmatterRules.validate(document),
            tags: TagRules.validate(document.frontmatter.tags, category: category, vocabulary: vocabulary),
            relatedMissingInSection: discrepancies.missingInSection,
            relatedMissingInFrontmatter: discrepancies.missingInFrontmatter
        )
    }
}
