import Foundation

/// Full-text search over the vault (SPEC §12), as the app asks for it.
///
/// The work is on `VaultSession` (ADR-0007 §D3); this names the result type where the
/// views already expect it. The app searches through the cooperative door only (PG-260):
/// the synchronous one is the connectors' and the tests'.
extension VaultController {
    typealias SearchResult = VaultSession.SearchResult

    /// The cooperative door (PG-260): chunked, pausing between chunks, stopping on
    /// cancellation. With no vault open it answers nothing.
    func searchCooperatively(_ query: SearchQuery, limit: Int = 200) async throws -> [SearchResult] {
        guard let session else { return [] }
        return try await session.searchCooperatively(query, limit: limit)
    }

    /// The notes that name one without linking to it (ADR-0012 D9), on request only.
    func unlinkedMentions(for relativePath: String) -> [SearchResult] {
        session?.unlinkedMentions(for: relativePath) ?? []
    }
}
