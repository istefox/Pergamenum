import Foundation

/// Capture: one door, four destinations (ADR-0008 §D6).
///
/// The panel, the `pergamenum://capture` route, `perg capture` and the MCP tool all
/// come through here. That is §D4 of the same ADR, and it is not a preference: a
/// capture implemented in the panel is a capture the CLI does not have, and the two
/// would grow different ideas of which folder an inbox note lives in.
///
/// Nothing here is new behaviour. Each destination is composed from a write that
/// already exists and is already tested - `createNote`, `captureTask`, `dailyNote`,
/// `append` - so what this file adds is the choice between them and the sentences said
/// when the choice does not make sense.
extension VaultAPI {
    /// Where a captured line goes.
    enum CaptureDestination: Equatable, Sendable {
        /// A new note, titled by the first line. `nil` folder means the inbox folder.
        case newNote(folder: String?)
        /// A task line in the inbox note.
        case task
        /// The end of today's daily note, created if today has none yet.
        case today
        /// The end of a note that already exists.
        case note(String)

        /// The folder a captured note lands in when the caller names none.
        ///
        /// The same folder the inbox note lives in (`TaskDestination.inboxPath`), so a
        /// vault does not grow a second idea of where unsorted things go.
        static let defaultFolder = "00 Inbox"

        /// Reads what a caller wrote, in either language: a shell and a model both type
        /// the word they saw somewhere else.
        ///
        /// No default here, deliberately. Each caller states its own and they differ:
        /// `pergamenum://capture?text=…` has meant "append to today" since SPEC §9
        /// published it, while `perg capture` with no `--dest` means a new note. A
        /// default hidden in this function would have quietly changed the route.
        static func named(_ raw: String, folder: String?) throws -> CaptureDestination {
            switch raw {
            case "note", "nota": return .newNote(folder: folder)
            case "task", "attività", "attivita": return .task
            case "today", "oggi": return .today
            case let other where other.hasPrefix("note:"):
                let path = String(other.dropFirst("note:".count))
                guard !path.isEmpty else {
                    throw ConnectorError("«note:» vuole il percorso di una nota dopo i due punti", usage: true)
                }
                return .note(path)
            case let other:
                throw ConnectorError(
                    "«\(other)» non è una destinazione; ci sono note, task, today, note:PERCORSO",
                    usage: true
                )
            }
        }
    }

    /// Writes a captured line where the destination says.
    ///
    /// `scheduled` and `due` belong to a task and to nothing else. On the other three
    /// destinations they are refused rather than dropped: a caller who asked for a
    /// deadline and got a note without one has been told nothing, and will believe the
    /// deadline is there.
    @MainActor
    static func capture(
        _ session: VaultSession,
        to destination: CaptureDestination,
        text: String,
        scheduled: String? = nil,
        due: String? = nil
    ) throws -> WriteSummary {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw ConnectorError("serve il testo da catturare", usage: true)
        }
        if destination != .task, scheduled != nil || due != nil {
            throw ConnectorError(
                "le date valgono solo per un task: usa --dest task, oppure toglile",
                usage: true
            )
        }

        switch destination {
        case .task:
            return try addTask(session, text: body, scheduled: scheduled, due: due, note: nil)
        case .today:
            return try captureIntoDay(session, text: body)
        case .note(let path):
            return try appendToNote(session, at: path, text: body)
        case .newNote(let folder):
            return try captureAsNote(session, text: body, folder: folder)
        }
    }

    // MARK: Today

    /// Today's daily note, created from the template when the day has none, then the
    /// text on the end of it.
    ///
    /// Two writes for one capture, and the summary describes the second: the first is
    /// the note coming into existence, which `dailyNote(for:)` has always done on
    /// demand and which nobody thinks of as part of what they captured.
    @MainActor
    private static func captureIntoDay(
        _ session: VaultSession, text: String
    ) throws -> WriteSummary {
        let path: String
        do {
            path = try session.dailyNote(for: .today)
        } catch let refusal as VaultSession.CreationError {
            throw ConnectorError("\(refusal)")
        }
        // A rehearsal creates nothing, so on a day with no note yet there is nothing to
        // append to and the second write would refuse a file that does not exist. Found
        // by running it: the unit suite exercises a day that already has a note, which
        // is the one case where this does not happen.
        guard session.exists(path) else {
            return WriteSummary(
                path: path,
                applied: false,
                diff: UnifiedDiff.between("", text + "\n", path: path, isNew: true),
                note: "la nota del giorno verrebbe creata prima"
            )
        }
        return try appendToNote(session, at: path, text: text)
    }

    // MARK: A new note

    /// The first line titles the note, the rest becomes its body.
    ///
    /// One field captures both because the panel has one field. The title still goes
    /// through `NoteName` like any other: capture is a faster way to write a note, not
    /// a way around the conventions, and a refused title comes back with its reason
    /// rather than being quietly corrected (SPEC §4.2).
    @MainActor
    private static func captureAsNote(
        _ session: VaultSession, text: String, folder: String?
    ) throws -> WriteSummary {
        var lines = text.components(separatedBy: "\n")
        let title = lines.removeFirst().trimmingCharacters(in: .whitespaces)
        let rest = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let created = try createNote(
            session,
            title: title,
            folder: folder ?? CaptureDestination.defaultFolder,
            topic: nil,
            date: nil
        )
        guard !rest.isEmpty else { return created }

        // A dry run has not created anything, so there is nothing to append to and the
        // second write would fail on a note that does not exist. The diff of the note
        // being created is the honest answer to "what would this do".
        guard !session.isDryRun else {
            return WriteSummary(
                path: created.path,
                applied: false,
                diff: created.diff,
                note: "il corpo verrebbe aggiunto dopo la creazione"
            )
        }
        return try appendToNote(session, at: created.path, text: rest)
    }
}
