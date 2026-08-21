import Foundation

/// `perg search <query>` - the same query language the app's global search speaks.
///
/// `tag:`, `path:`, `task:open`, `"frase esatta"` and bare words, all ANDed
/// (SPEC §12). Parsed by `SearchQuery`, which is the app's own parser: a second
/// grammar here would be a second thing to keep in step.
enum SearchCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let hits = try VaultAPI.search(
            session, arguments.rest(from: 1), limit: arguments["limit"].flatMap(Int.init)
        )

        if arguments.has("json") {
            Output.json(hits)
        } else {
            for hit in hits {
                Output.line(hit.path)
                if !hit.excerpt.isEmpty { Output.line("    \(hit.excerpt)") }
            }
        }
        // Nothing found is not a failure - it is an answer, and a script testing the
        // exit code should not have to special-case an empty vault.
        return .success
    }
}
