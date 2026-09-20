import Foundation

/// The category registry's lifecycle, reachable from the window (ADR-0047 §D2/§D3, R-01).
///
/// The mutations themselves are on `VaultSession` (`VaultSession+Categories.swift`) - the
/// same split `VaultController+Folders.swift` makes for a folder rename. What is added
/// here is only "there is no vault open", which every other facade method already
/// answers the same way (PG-051): no `canOperate` guard and no rescan, unlike a folder
/// operation, because a category mutation touches the registry file alone (SPEC "Risks":
/// "no batching, no journal") and `categories` already reads through to the session live,
/// the same way `index` does - a view sees the new registry the moment `mutateCategories`
/// returns, with nothing to rescan.
extension VaultController {
    @discardableResult
    func createCategory(_ category: Category) -> CategoryRegistry.RefusalReason? {
        session?.createCategory(category)
    }

    @discardableResult
    func updateCategory(_ category: Category) -> CategoryRegistry.RefusalReason? {
        session?.updateCategory(category)
    }

    /// A drag among sibling category rows (R-01, `CategoryDropResolver`).
    @discardableResult
    func reorderCategories(_ slugs: [String], parent: String?) -> CategoryRegistry.RefusalReason? {
        session?.reorderCategories(slugs, parent: parent)
    }

    /// A category row dragged onto another top-level one (R-01, `CategoryDropResolver`).
    @discardableResult
    func reparentCategory(_ slug: String, to parentSlug: String?) -> CategoryRegistry.RefusalReason? {
        session?.reparentCategory(slug, to: parentSlug)
    }

    @discardableResult
    func archiveCategory(_ slug: String) -> CategoryRegistry.RefusalReason? {
        session?.archiveCategory(slug)
    }

    @discardableResult
    func unarchiveCategory(_ slug: String) -> CategoryRegistry.RefusalReason? {
        session?.unarchiveCategory(slug)
    }

    func deleteCategory(_ slug: String) {
        session?.deleteCategory(slug)
    }

    @discardableResult
    func promoteImplicitCategory(_ slug: String, color: String) -> CategoryRegistry.RefusalReason? {
        session?.promoteImplicitCategory(slug, color: color)
    }

    /// Links a note to a category by writing its `pergamenum-category` key (SPEC "UI
    /// flows: Linked note", ADR-0047 §D10). Follows `apply(_:to:)`'s own shape
    /// (`VaultController+Tasks.swift`): a write puts an open editor back in step, a
    /// stale hash asks for a rescan rather than guessing, and the caller only needs a
    /// `Bool`.
    @discardableResult
    func linkCategory(_ slug: String, toNoteAt relativePath: String) async -> Bool {
        guard let session else { return false }
        return handle(await session.linkCategory(slug, toNoteAt: relativePath))
    }

    /// Makes a note the category's one home, displacing any previous one (PG-166): the
    /// entry point every «Collega una nota…» / «Assegna una categoria…» affordance calls,
    /// where `linkCategory` alone would leave two notes claiming the slug.
    @discardableResult
    func setCategoryHome(_ slug: String, toNoteAt relativePath: String) async -> Bool {
        guard let session else { return false }
        return handle(await session.setCategoryHome(slug, toNoteAt: relativePath))
    }

    /// The note inspector's unlink affordance (SPEC "UI flows: Linked note").
    @discardableResult
    func unlinkCategory(fromNoteAt relativePath: String) async -> Bool {
        guard let session else { return false }
        return handle(await session.unlinkCategory(fromNoteAt: relativePath))
    }

    /// `linkCategory`/`unlinkCategory`'s shared outcome handling.
    private func handle(_ outcome: VaultSession.WriteOutcome) -> Bool {
        switch outcome {
        case .written(let result):
            syncOpenNote(with: result)
            return true
        case .unchanged:
            return true
        case .stale:
            Task { await rescan() }
            return false
        case .failed:
            return false
        }
    }
}
