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

        // One matcher for the whole loop: it compiles the query's `regex:` patterns, and
        // compiling them once per note is the difference between a search and a pause.
        let matcher = SearchQuery.Matcher(query)
        var results: [SearchResult] = []
        for record in candidates(for: query) {
            guard let (_, text) = try? read(record.relativePath) else { continue }
            guard matcher.matches(record: record, text: text) else { continue }

            results.append(SearchResult(
                path: record.relativePath,
                title: record.title,
                excerpt: matcher.excerpt(in: text)
            ))
            if results.count >= limit { break }
        }
        return results
    }

    /// The notes worth reading for a query.
    ///
    /// `is:starred`, `linked:` and `orphan:` are the three operators no note can answer
    /// about itself (ADR-0012 D8): the star lives in the store beside the vault and the
    /// other two in the link graph. Narrowing here rather than inside the loop means the
    /// files those operators exclude are never opened at all.
    private func candidates(for query: SearchQuery) -> [NoteRecord] {
        guard query.needsVaultContext else { return index.allNotes }

        var allowed: Set<String>?
        func narrow(to paths: Set<String>) {
            allowed = allowed.map { $0.intersection(paths) } ?? paths
        }

        if query.starredOnly { narrow(to: starred) }
        if query.orphansOnly { narrow(to: index.orphans) }
        for title in query.linkedTo { narrow(to: index.neighbourhood(ofTitle: title)) }

        guard let allowed else { return index.allNotes }
        return index.allNotes.filter { allowed.contains($0.relativePath) }
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
