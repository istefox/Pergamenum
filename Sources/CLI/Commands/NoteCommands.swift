import Foundation

/// `perg note …` - reading the vault's notes and the links between them.
enum NoteCommands {
    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        let session = try await VaultResolution.session(at: try VaultResolution.root(from: arguments))

        switch arguments.word(1) {
        case "list": return list(session, arguments)
        case "read": return try read(session, arguments)
        case "links": return try links(session, arguments)
        case "backlinks": return try backlinks(session, arguments)
        case "unresolved": return unresolved(session, arguments)
        case let other:
            throw CommandError(
                "«note \(other ?? "")» non esiste; ci sono list, read, links, backlinks, unresolved",
                code: .usage
            )
        }
    }

    @MainActor
    private static func list(_ session: VaultSession, _ arguments: Arguments) -> ExitCode {
        let notes = VaultAPI.notes(session, inFolder: arguments["folder"])
        if arguments.has("json") {
            Output.json(notes)
        } else {
            for note in notes { Output.line(note.path) }
        }
        return .success
    }

    @MainActor
    private static func read(_ session: VaultSession, _ arguments: Arguments) throws -> ExitCode {
        let note = try VaultAPI.note(session, at: try requirePath(arguments, "note read <percorso>"))
        if arguments.has("json") {
            Output.json(note)
        } else {
            // The file verbatim, so `perg note read x.md > y.md` is a copy and the
            // frontmatter a model reads is the frontmatter on disk.
            Output.line(note.text)
        }
        return .success
    }

    @MainActor
    private static func links(_ session: VaultSession, _ arguments: Arguments) throws -> ExitCode {
        let links = try VaultAPI.links(session, at: try requirePath(arguments, "note links <percorso>"))
        if arguments.has("json") {
            Output.json(links)
        } else {
            for target in links.resolved { Output.line(target) }
            for target in links.unresolved { Output.line("\(target)  (non risolto)") }
        }
        return .success
    }

    @MainActor
    private static func backlinks(_ session: VaultSession, _ arguments: Arguments) throws -> ExitCode {
        // Joined from every remaining word, so a title with spaces works unquoted.
        let notes = try VaultAPI.backlinks(session, toTitle: arguments.rest(from: 2))
        if arguments.has("json") {
            Output.json(notes)
        } else {
            for note in notes { Output.line(note.path) }
        }
        return .success
    }

    @MainActor
    private static func unresolved(_ session: VaultSession, _ arguments: Arguments) -> ExitCode {
        let links = VaultAPI.unresolvedLinks(session)
        if arguments.has("json") {
            Output.json(links)
        } else {
            for link in links {
                Output.line("\(link.target)  <- \(link.sources.joined(separator: ", "))")
            }
        }
        return .success
    }

    static func requirePath(_ arguments: Arguments, _ usage: String) throws -> String {
        guard let path = arguments.word(2), !path.isEmpty else {
            throw CommandError("uso: perg \(usage)", code: .usage)
        }
        return path
    }
}
