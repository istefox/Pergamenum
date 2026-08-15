import Foundation

/// `perg note …` - reading the vault's notes and the links between them.
enum NoteCommands {
    struct NoteSummary: Encodable {
        let path: String
        let title: String
        let tags: [String]
        let date: String?
        let tasks: Int
        let links: [String]
    }

    struct Backlink: Encodable {
        let path: String
        let title: String
    }

    struct Unresolved: Encodable {
        let target: String
        let sources: [String]
    }

    @MainActor
    static func run(_ arguments: Arguments) async throws -> ExitCode {
        let session = await VaultResolution.session(at: try VaultResolution.root(from: arguments))

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

    // MARK: list

    @MainActor
    private static func list(_ session: VaultSession, _ arguments: Arguments) -> ExitCode {
        // `--folder` filters by path prefix, which is how a person thinks about a vault
        // whose folders are its only structure.
        let folder = arguments["folder"]
        let records = session.index.allNotes.filter { record in
            guard let folder else { return true }
            return record.relativePath.hasPrefix(folder)
        }

        if arguments.has("json") {
            Output.json(records.map(summary))
        } else {
            for record in records {
                Output.line(record.relativePath)
            }
        }
        return .success
    }

    private static func summary(_ record: NoteRecord) -> NoteSummary {
        NoteSummary(
            path: record.relativePath,
            title: record.title,
            tags: record.frontmatter.tags.map(\.description),
            date: record.frontmatter.date?.description,
            tasks: record.tasks.count,
            links: record.linkTargets
        )
    }

    // MARK: read

    @MainActor
    private static func read(_ session: VaultSession, _ arguments: Arguments) throws -> ExitCode {
        let path = try requirePath(arguments, "note read <percorso>")
        guard let (record, text) = try? session.read(path) else {
            throw CommandError("non riesco a leggere «\(path)»")
        }

        if arguments.has("json") {
            struct Payload: Encodable {
                let note: NoteSummary
                let text: String
            }
            Output.json(Payload(note: summary(record), text: text))
        } else {
            // The file verbatim, so `perg note read x.md > y.md` is a copy and the
            // frontmatter a model reads is the frontmatter on disk.
            Output.line(text)
        }
        return .success
    }

    // MARK: links

    @MainActor
    private static func links(_ session: VaultSession, _ arguments: Arguments) throws -> ExitCode {
        let path = try requirePath(arguments, "note links <percorso>")
        guard let record = session.index.note(at: path) else {
            throw CommandError("«\(path)» non è nell'indice")
        }

        // Resolved and unresolved reported apart: a link that answers to nothing is
        // the interesting half, and a flat list hides it.
        let resolved = record.linkTargets.filter { !session.index.resolve(title: $0).isEmpty }
        let dangling = record.linkTargets.filter { session.index.resolve(title: $0).isEmpty }

        if arguments.has("json") {
            struct Payload: Encodable {
                let resolved: [String]
                let unresolved: [String]
            }
            Output.json(Payload(resolved: resolved, unresolved: dangling))
        } else {
            for target in resolved { Output.line(target) }
            for target in dangling { Output.line("\(target)  (non risolto)") }
        }
        return .success
    }

    @MainActor
    private static func backlinks(_ session: VaultSession, _ arguments: Arguments) throws -> ExitCode {
        // By title, not by path: a backlink is a wikilink, and a wikilink names a title.
        // Joined from every remaining word, so a title with spaces works unquoted.
        let title = arguments.rest(from: 2)
        guard !title.isEmpty else {
            throw CommandError("uso: perg note backlinks <titolo>", code: .usage)
        }
        let records = session.index.backlinks(toTitle: title)

        if arguments.has("json") {
            Output.json(records.map { Backlink(path: $0.relativePath, title: $0.title) })
        } else {
            for record in records { Output.line(record.relativePath) }
        }
        return .success
    }

    @MainActor
    private static func unresolved(_ session: VaultSession, _ arguments: Arguments) -> ExitCode {
        let links = session.index.unresolvedLinks()

        if arguments.has("json") {
            Output.json(links.map { Unresolved(target: $0.target, sources: $0.sources.map(\.relativePath)) })
        } else {
            for link in links {
                Output.line("\(link.target)  <- \(link.sources.map(\.relativePath).joined(separator: ", "))")
            }
        }
        return .success
    }

    // MARK: Shared

    static func requirePath(_ arguments: Arguments, _ usage: String) throws -> String {
        guard let path = arguments.word(2), !path.isEmpty else {
            throw CommandError("uso: perg \(usage)", code: .usage)
        }
        return path
    }
}
