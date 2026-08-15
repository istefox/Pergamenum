import Foundation

/// `perg search <query>` - the same query language the app's global search speaks.
///
/// `tag:`, `path:`, `task:open`, `"frase esatta"` and bare words, all ANDed
/// (SPEC §12). Parsed by `SearchQuery`, which is the app's own parser: a second
/// grammar here would be a second thing to keep in step.
enum SearchCommands {
    struct Hit: Encodable {
        let path: String
        let title: String
        let excerpt: String
    }

    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        let raw = arguments.rest(from: 1)
        guard !raw.isEmpty else {
            throw CommandError(#"uso: perg search <query>   es. perg search 'tag:type-note curva'"#, code: .usage)
        }

        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))
        let limit = arguments["limit"].flatMap(Int.init) ?? 200
        let results = session.search(SearchQuery(raw), limit: limit)

        if arguments.has("json") {
            Output.json(results.map { Hit(path: $0.path, title: $0.title, excerpt: $0.excerpt) })
        } else {
            for result in results {
                Output.line(result.path)
                if !result.excerpt.isEmpty { Output.line("    \(result.excerpt)") }
            }
        }
        // Nothing found is not a failure - it is an answer, and a script testing the
        // exit code should not have to special-case an empty vault.
        return .success
    }
}
