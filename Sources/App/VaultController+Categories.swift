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
}
