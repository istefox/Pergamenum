import Foundation

/// Full-text search over the vault (SPEC §12), as the app asks for it.
///
/// The work is on `VaultSession` (ADR-0007 §D3); this names the result type where the
/// views already expect it.
extension VaultController {
    typealias SearchResult = VaultSession.SearchResult

    func search(_ query: SearchQuery, limit: Int = 200) -> [SearchResult] {
        session?.search(query, limit: limit) ?? []
    }

    /// The notes that name one without linking to it (ADR-0012 D9), on request only.
    func unlinkedMentions(for relativePath: String) -> [SearchResult] {
        session?.unlinkedMentions(for: relativePath) ?? []
    }
}
