import Foundation

/// The category registry's lifecycle (ADR-0047 §D2/§D3): create, edit, reorder,
/// reparent, archive, unarchive, delete, promote-implicit. Every mutation validates
/// through `CategoryRegistry.validating(_:version:)` and saves once - no batching, no
/// journal, the same call ADR-0022 made for folder rename/delete (SPEC "Risks").
extension VaultSession {
    @discardableResult
    func createCategory(_ category: Category) -> CategoryRegistry.RefusalReason? {
        mutateCategories { $0 + [category] }
    }

    @discardableResult
    func updateCategory(_ category: Category) -> CategoryRegistry.RefusalReason? {
        mutateCategories { entries in entries.map { $0.slug == category.slug ? category : $0 } }
    }

    /// Reassigns `order` to every sibling of `parent` (nil for top-level), in the
    /// sequence given - a drag among sibling rows (SPEC "UI flows: Reorder/reparent").
    @discardableResult
    func reorderCategories(_ slugs: [String], parent: String?) -> CategoryRegistry.RefusalReason? {
        mutateCategories { entries in
            var order: [String: Int] = [:]
            for (index, slug) in slugs.enumerated() { order[slug] = index }
            return entries.map { entry in
                guard entry.parent == parent, let newOrder = order[entry.slug] else { return entry }
                var updated = entry
                updated.order = newOrder
                return updated
            }
        }
    }

    /// Drag onto a top-level row (SPEC "UI flows"): reparents one category, registry
    /// only, no task line touched (ADR-0047 §D13).
    @discardableResult
    func reparentCategory(_ slug: String, to parentSlug: String?) -> CategoryRegistry.RefusalReason? {
        mutateCategories { entries in
            entries.map { entry in
                guard entry.slug == slug else { return entry }
                var updated = entry
                updated.parent = parentSlug
                return updated
            }
        }
    }

    /// Archives `slug` and cascades over its subtree (SPEC edge case: "archiving a
    /// parent archives the subtree").
    @discardableResult
    func archiveCategory(_ slug: String) -> CategoryRegistry.RefusalReason? {
        setCategoryArchived(slug, archived: true)
    }

    /// Unarchives `slug`, cascading over its subtree the same way `archiveCategory`
    /// does, and additionally unarchiving its parent when that parent is archived
    /// (SPEC edge case: "unarchiving a child whose parent is archived unarchives the
    /// parent too").
    @discardableResult
    func unarchiveCategory(_ slug: String) -> CategoryRegistry.RefusalReason? {
        setCategoryArchived(slug, archived: false)
    }

    /// Delete touches the registry only (SPEC "Decisions"): the tasks keep their tag
    /// and reappear as an implicit category on the next scan. A deleted parent's
    /// children keep pointing at a slug that no longer exists in the registry, which
    /// the sidebar already shows at top level with a warning badge (SPEC edge case).
    func deleteCategory(_ slug: String) {
        mutateCategories { $0.filter { $0.slug != slug } }
    }

    /// "Registra" (SPEC "Decisions"): turns an implicit category into a registered one
    /// with no other change - the tasks that already carry the tag are untouched.
    @discardableResult
    func promoteImplicitCategory(
        _ slug: String, name: String? = nil, color: String
    ) -> CategoryRegistry.RefusalReason? {
        let nextOrder = (categories.entries.filter { $0.parent == nil }.map(\.order).max() ?? -1) + 1
        return createCategory(Category(slug: slug, name: name ?? slug, color: color, order: nextOrder))
    }

    /// Writes `pergamenum-category: <slug>` into a note's frontmatter (SPEC "Note ↔
    /// category", ADR-0047 §D10) - the linked-note half of a category's "home". A note
    /// carries at most one such key (SPEC "Note ↔ category": "one slug per note"), so
    /// linking replaces whichever key was already there rather than adding a second
    /// line, and nothing else in the note is touched.
    @discardableResult
    func linkCategory(_ slug: String, toNoteAt relativePath: String) async -> WriteOutcome {
        await rewriteCategoryKey(at: relativePath) { keys in
            var updated = keys.filter { $0.name != CategoryFrontmatter.key }
            updated.append(.init(name: CategoryFrontmatter.key, lines: ["\(CategoryFrontmatter.key): \(slug)"]))
            return updated
        }
    }

    /// Removes the `pergamenum-category` key (the note inspector's unlink affordance,
    /// SPEC "UI flows: Linked note"). The note's own `#project-*` task tags, if any,
    /// are untouched and keep counting as usual (SPEC "Task ↔ category").
    @discardableResult
    func unlinkCategory(fromNoteAt relativePath: String) async -> WriteOutcome {
        await rewriteCategoryKey(at: relativePath) { keys in
            keys.filter { $0.name != CategoryFrontmatter.key }
        }
    }

    /// The one write `linkCategory`/`unlinkCategory` funnel through: rewrite the
    /// frontmatter's foreign keys, re-serialize, and write through the door with
    /// `expecting:` (ADR-0043 §D8) - the same shape `apply(_:to:)` uses for a task line
    /// (`VaultSession+Tasks.swift`).
    private func rewriteCategoryKey(
        at relativePath: String,
        _ transform: ([Frontmatter.ForeignKey]) -> [Frontmatter.ForeignKey]
    ) async -> WriteOutcome {
        do {
            let (_, text) = try read(relativePath)
            var document = NoteDocument.parse(text)
            document.frontmatter.foreignKeys = transform(document.frontmatter.foreignKeys)
            let updated = document.serialized()
            guard updated != text else { return .unchanged }
            return .written(try await write(updated, to: relativePath, expecting: NoteStore.hash(Data(text.utf8))))
        } catch is VaultSession.WriteRefusal {
            recordProblem("la nota è cambiata nel frattempo: \(relativePath)")
            return .stale
        } catch {
            recordProblem("\(relativePath): \(error)")
            return .failed
        }
    }

    /// Applies `archived` to `slug` and its children, then handles the child-unarchives-
    /// parent edge case (SPEC edge cases). Shared by `archiveCategory`/`unarchiveCategory`
    /// so the cascade cannot drift between the two directions.
    private func setCategoryArchived(_ slug: String, archived: Bool) -> CategoryRegistry.RefusalReason? {
        mutateCategories { entries in
            var updated = entries
            let bySlug = Dictionary(uniqueKeysWithValues: entries.map { ($0.slug, $0) })
            let cascade = CategoryRegistry(version: categories.version, entries: entries).subtreeSlugs(of: slug)
            for index in updated.indices where cascade.contains(updated[index].slug) {
                updated[index].archived = archived
            }
            if !archived, let parentSlug = bySlug[slug]?.parent,
               let parentIndex = updated.firstIndex(where: { $0.slug == parentSlug }) {
                updated[parentIndex].archived = false
            }
            return updated
        }
    }

    /// The one place every mutation above funnels through: refuses while the on-disk
    /// registry could not be read (§D2), otherwise validates the candidate entries and
    /// saves once.
    private func mutateCategories(
        _ transform: ([Category]) -> [Category]
    ) -> CategoryRegistry.RefusalReason? {
        guard !categoryRegistryMalformed else {
            recordProblem("\(VaultLayout.categoriesFile) è malformato: nessuna modifica viene salvata")
            return .registryUnreadable
        }
        switch CategoryRegistry.validating(transform(categories.entries), version: categories.version) {
        case .failure(let reason):
            return reason
        case .success(let updated):
            categories = updated
            if let problem = categoryStore.save(updated) { recordProblem(problem) }
            return nil
        }
    }
}
