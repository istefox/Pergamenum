import Foundation
import MCP

/// The vault, for as long as the server runs.
///
/// One session, kept open. `VaultSession` is `@MainActor` because the app's views read
/// it synchronously, and this class inherits that isolation rather than fighting it: the
/// server's handlers are async, so awaiting the main actor from them costs nothing and
/// buys the same code path the app uses.
///
/// The vault is rescanned before every call. The person whose vault this is has the app
/// open on it and is editing while the model reads, so an index built at launch would be
/// answering about a vault that no longer exists. `IndexCache` compares hashes and reuses
/// what has not changed, which is what makes that affordable.
@MainActor
final class VaultHost {
    private let session: VaultSession
    let allowsWriting: Bool

    private init(session: VaultSession, allowsWriting: Bool) {
        self.session = session
        self.allowsWriting = allowsWriting
    }

    static func open(at root: URL, allowsWriting: Bool) async -> VaultHost {
        VaultHost(
            session: await VaultResolution.session(at: root), allowsWriting: allowsWriting
        )
    }

    var root: URL { session.root }

    var tools: [Tool] {
        ToolCatalogue.reading + (allowsWriting ? ToolCatalogue.writing : [])
    }

    // MARK: Calling

    /// Answers a tool call, turning a refusal into a result rather than a protocol error.
    ///
    /// `isError` on the result is the difference between "the server broke" and "the
    /// vault said no": the second is something the model can read and act on, and a
    /// JSON-RPC error would only tell it that something went wrong somewhere.
    func call(_ parameters: CallTool.Parameters) async -> CallTool.Result {
        await session.rescan()
        do {
            return try perform(parameters.name, ToolArguments(parameters.arguments))
        } catch let refusal as ConnectorError {
            return CallTool.Result(content: [.text(refusal.description)], isError: true)
        } catch {
            return CallTool.Result(content: [.text("\(error)")], isError: true)
        }
    }

    /// Four dispatch tables rather than two, split the way the CLI's groups are: a single
    /// switch over twenty names is past what SwiftLint allows and, more to the point,
    /// past what anyone scans without losing their place.
    private func perform(_ name: String, _ arguments: ToolArguments) throws -> CallTool.Result {
        if let result = try readNotes(name, arguments) { return result }
        if let result = try readWork(name, arguments) { return result }
        if let result = try write(name, arguments) { return result }
        throw ConnectorError("«\(name)» non è uno strumento di questo server", usage: true)
    }

    // MARK: Reading

    /// The notes and the links between them.
    private func readNotes(_ name: String, _ arguments: ToolArguments) throws -> CallTool.Result? {
        switch name {
        case "search_vault":
            return reply(try VaultAPI.search(
                session, try arguments.required("query"), limit: arguments.int("limit")
            ))
        case "read_note":
            return reply(try VaultAPI.note(session, at: try arguments.required("path")))
        case "list_notes":
            return reply(VaultAPI.notes(session, inFolder: arguments.string("folder")))
        case "note_links":
            return reply(try VaultAPI.links(session, at: try arguments.required("path")))
        case "note_backlinks":
            return reply(try VaultAPI.backlinks(session, toTitle: try arguments.required("title")))
        case "unresolved_links":
            return reply(VaultAPI.unresolvedLinks(session))
        default:
            return nil
        }
    }

    /// The work: tasks, days, conformance, and what the vault knows about itself.
    private func readWork(_ name: String, _ arguments: ToolArguments) throws -> CallTool.Result? {
        switch name {
        case "list_tasks":
            return reply(try VaultAPI.tasks(
                session,
                view: arguments.string("view"),
                on: arguments.string("day"),
                includingCompleted: arguments.bool("includeCompleted", default: false)
            ))
        case "day_agenda":
            return reply(try VaultAPI.day(session, on: arguments.string("day")))
        case "lint_note":
            return reply(try VaultAPI.lint(session, at: try arguments.required("path")))
        case "lint_vault":
            return reply(try VaultAPI.lint(session, at: nil))
        case "vault_stats":
            return reply(VaultAPI.stats(session))
        case "journal_log":
            return reply(VaultAPI.journalLog(at: session.root, limit: arguments.int("limit")))
        default:
            return nil
        }
    }

    // MARK: Writing

    /// Every write goes through here, and every one of them is armed first.
    ///
    /// The `allowsWriting` check is a second lock on a door that was never shown: the
    /// writing tools are absent from `tools/list` without `--allow-write`, and a client
    /// that calls one anyway is told no rather than obeyed.
    private func write(_ name: String, _ arguments: ToolArguments) throws -> CallTool.Result? {
        guard ToolCatalogue.writing.contains(where: { $0.name == name }) else { return nil }
        guard allowsWriting else {
            throw ConnectorError(
                """
                questo server è stato avviato in sola lettura: «\(name)» scriverebbe nel \
                vault. Riavvialo con --allow-write se è quello che vuoi.
                """
            )
        }
        VaultAPI.arm(session, command: name, dryRun: arguments.bool("dryRun", default: true))

        switch name {
        case "create_note":
            return reply(try VaultAPI.createNote(
                session,
                title: try arguments.required("title"),
                folder: arguments.string("folder"),
                topic: arguments.string("topic"),
                date: arguments.string("date")
            ))
        case "append_to_note":
            return reply(try VaultAPI.appendToNote(
                session, at: try arguments.required("path"), text: try arguments.required("text")
            ))
        case "capture":
            // "note" when the model says nothing, the same default `perg capture` uses.
            // The URL route's default is "today" and lives at its own call site, so the
            // two cannot drift into each other (ADR-0008 §D5).
            return reply(try VaultAPI.capture(
                session,
                to: try VaultAPI.CaptureDestination.named(
                    arguments.string("destination") ?? "note",
                    folder: arguments.string("folder")
                ),
                text: try arguments.required("text"),
                scheduled: arguments.string("scheduled"),
                due: arguments.string("due")
            ))
        default:
            return try writeWork(name, arguments)
        }
    }

    /// The writes that act on a task or on a day, plus the one that puts a file back.
    private func writeWork(_ name: String, _ arguments: ToolArguments) throws -> CallTool.Result? {
        switch name {
        case "add_task":
            return reply(try VaultAPI.addTask(
                session,
                text: try arguments.required("text"),
                scheduled: arguments.string("scheduled"),
                due: arguments.string("due"),
                note: arguments.string("note")
            ))
        case "complete_task":
            return reply(try VaultAPI.changeTask(
                session, matching: try arguments.required("task"), .done
            ))
        case "reopen_task":
            return reply(try VaultAPI.changeTask(
                session, matching: try arguments.required("task"), .reopen
            ))
        case "reschedule_task":
            return reply(try VaultAPI.changeTask(
                session,
                matching: try arguments.required("task"),
                .reschedule(to: try arguments.required("to"))
            ))
        case "add_time_block":
            return reply(try VaultAPI.addTimeBlock(
                session,
                title: try arguments.required("title"),
                at: try arguments.required("at"),
                minutes: arguments.int("minutes"),
                on: arguments.string("day")
            ))
        case "undo_write":
            return reply(try VaultAPI.undo(session, id: try arguments.required("id")))
        default:
            return nil
        }
    }

    // MARK: Notes as resources

    /// The vault's notes as MCP resources, so a client can attach one without spending a
    /// tool call on it.
    ///
    /// The URI is the app's own `pergamenum://note?file=…` - the very link "Copia link
    /// Pergamenum" puts on the clipboard. One builder, one parser, and a URI that also
    /// happens to open the note in the app if anyone clicks it.
    func resources(after cursor: String?) -> ListResources.Result {
        let notes = session.index.allNotes
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + Self.pageSize, notes.count)
        guard start < end else { return ListResources.Result(resources: []) }

        let page = notes[start..<end].compactMap { record -> Resource? in
            guard let uri = PergamenumLink.note(path: record.relativePath) else { return nil }
            return Resource(
                name: record.title,
                uri: uri.absoluteString,
                description: record.relativePath,
                mimeType: "text/markdown"
            )
        }
        return ListResources.Result(
            resources: page, nextCursor: end < notes.count ? String(end) : nil
        )
    }

    func resource(at uri: String) throws -> ReadResource.Result {
        guard let url = URL(string: uri), case .note(let path)? = PergamenumRoute(url) else {
            throw ConnectorError("«\(uri)» non è una nota di questo vault", usage: true)
        }
        let note = try VaultAPI.note(session, at: path)
        return ReadResource.Result(contents: [
            .text(note.text, uri: uri, mimeType: "text/markdown"),
        ])
    }

    /// Enough notes to be useful in one round trip, few enough that a vault of a few
    /// thousand does not arrive as a single frame.
    private static let pageSize = 200

    // MARK: Shared

    private func reply(_ payload: some Encodable) -> CallTool.Result {
        do {
            return CallTool.Result(content: [.text(try ConnectorJSON.encode(payload))])
        } catch {
            // Reported rather than swallowed: a caller waiting on JSON that never
            // arrives has nothing to go on.
            return CallTool.Result(
                content: [.text("la risposta non è stata serializzata: \(error)")], isError: true
            )
        }
    }
}
