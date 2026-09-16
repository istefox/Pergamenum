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

    // MARK: Unlinked mentions

    /// The notes that name this one without linking to it (ADR-0012 D9).
    ///
    /// **Computed when asked and never cached.** This is a full-vault text scan - the same
    /// read loop `search` runs - so putting it on every note opening would charge that cost to
    /// the gesture people make most. The result is not written to `IndexCache` either: its
    /// schema version is spent by M11 (ADR-0009 §D2) and this milestone must not touch it.
    ///
    /// Aliases count as names, and a note that reaches this one *through* an alias is still an
    /// unlinked mention: an alias serves search and never the link target (F-07), so no
    /// backlink exists to remove it from the list.
    func unlinkedMentions(for relativePath: String, limit: Int = 50) -> [SearchResult] {
        guard let subject = index.note(at: relativePath) else { return [] }
        let names = [subject.title] + subject.frontmatter.aliases
        let alreadyLinking = Set(index.backlinks(toTitle: subject.title).map(\.relativePath))

        var results: [SearchResult] = []
        for record in index.allNotes {
            guard record.relativePath != relativePath,
                  !alreadyLinking.contains(record.relativePath),
                  let (_, text) = try? read(record.relativePath),
                  let line = UnlinkedMentions.firstMentionLine(of: names, in: text)
            else { continue }

            results.append(SearchResult(path: record.relativePath, title: record.title, excerpt: line))
            if results.count >= limit { break }
        }
        return results
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
            relatedMissingInFrontmatter: discrepancies.missingInFrontmatter,
            taskMarkers: taskMarkerViolations(path: path, text: text),
            categories: categoryViolations(path: path, document: document)
        )
    }

    /// The two advisory `pergamenum-category` rules of ADR-0047 §D10 (R-10).
    ///
    /// Unlike `taskMarkerViolations`, this reads `self.categories` (the registry) and
    /// `self.index` (every other note's own linked slug) - the one place in the lint
    /// path that can see both, since `violations(path:title:text:)` is a method on
    /// `VaultSession` rather than a pure function of the three arguments it takes. The
    /// note under test is included among the claimants by its own `path` even when the
    /// index does not know it yet (a brand new, unsaved note): otherwise the very first
    /// note to claim a slug would report itself as its own duplicate.
    private func categoryViolations(path: String, document: NoteDocument) -> [CategoryViolation] {
        guard let slug = CategoryFrontmatter.slug(in: document.frontmatter.foreignKeys) else { return [] }

        var findings: [CategoryViolation] = []
        if !categories.entries.contains(where: { $0.slug == slug }) {
            findings.append(.unknownSlug(slug))
        }

        var claimants = Set(index.allNotes.filter { $0.categorySlug == slug }.map(\.relativePath))
        claimants.insert(path)
        if let home = claimants.sorted().first, home != path {
            findings.append(.duplicateHome(slug, home: home))
        }
        return findings
    }

    /// The two advisory task-marker rules of ADR-0021 §D11 (R-11, R-12).
    ///
    /// A pure function of the note's own text: `TaskParser.tasks(in:sourcePath:)` reads
    /// the string and nothing else, so no index and no vault are consulted and the rule
    /// is testable without either. That is also what makes R-12 note-local by
    /// construction (§D2) - a matching `^id` in a different note is not visible from
    /// here, so it cannot clear the finding.
    private func taskMarkerViolations(path: String, text: String) -> [TaskMarkerViolation] {
        let tasks = TaskParser.tasks(in: text, sourcePath: path)
        let localIDs = Set(tasks.compactMap(\.localID))
        var findings: [TaskMarkerViolation] = []

        for task in tasks {
            let targets = TaskParser.workspaceTargets(inLine: task.rawLine)
            if targets.count > 1 {
                findings.append(
                    .duplicateWorkspace(line: task.lineIndex, kept: targets[0], ignored: targets[1])
                )
            }
            if let parent = task.parentLocalID, !localIDs.contains(parent) {
                findings.append(.orphanedParent(line: task.lineIndex, parent: parent))
            }
        }
        return findings
    }
}
