import Foundation
import Observation

/// What the global search sheet shows, ordered by generation (PG-260, R-08, R-09).
///
/// Taken out of `GlobalSearchView` so the ordering is a fact a test can drive: the sleep and
/// the search are handed in, and a test parks each of them on a gate.
///
/// Two rules. The invalid `regex:` patterns and the spinner belong to the query being
/// searched, so both are set after the debounce and not while the pattern is still being
/// typed. And every search that begins takes a new generation: only the current one may
/// publish results or clear the spinner, so a superseded search - cancelled by the view's
/// `.task(id:)` when the text changed - can neither stop the spinner of the search that
/// replaced it nor overwrite that search's results.
@MainActor
@Observable
final class GlobalSearchState {
    typealias Sleep = @MainActor (Duration) async -> Void
    typealias Search = @MainActor (SearchQuery) async throws -> [VaultSession.SearchResult]

    /// A short pause so a search does not run on every keystroke of a long query.
    static let debounce: Duration = .milliseconds(180)

    private(set) var results: [VaultSession.SearchResult] = []
    private(set) var isSearching = false
    /// The `regex:` patterns of the searched query that do not compile. Shown rather than
    /// swallowed: an empty result list reads as "nothing found", and the difference
    /// between that and "your pattern is broken" is the whole value of the message.
    private(set) var invalidPatterns: [String] = []
    /// The raw text whose answer `results` is. Nil until one has been published.
    private(set) var answeredRaw: String?

    /// Bumped by every search that begins and by every clear. A run publishes only while
    /// the generation it took is still the current one.
    private var generation = 0

    /// One query, from keystroke to published answer.
    func run(_ raw: String, sleep: Sleep, search: Search) async {
        let query = SearchQuery(raw)
        guard !query.isEmpty else {
            generation += 1
            results = []
            isSearching = false
            invalidPatterns = []
            answeredRaw = nil
            return
        }

        await sleep(Self.debounce)
        guard !Task.isCancelled else { return }

        generation += 1
        let mine = generation
        invalidPatterns = query.invalidPatterns
        isSearching = true

        do {
            let answer = try await search(query)
            guard mine == generation else { return }
            isSearching = false
            // A search that finished its last chunk as it was cancelled answers a query
            // nobody is looking at any more.
            guard !Task.isCancelled else { return }
            results = answer
            answeredRaw = raw
        } catch {
            guard mine == generation else { return }
            isSearching = false
        }
    }
}
