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
        /// A new note, titled by the first line. `nil` folder means the vault's inbox
        /// folder (`VaultSession.inboxFolder`), the same folder the inbox note lives in, so
        /// a vault does not grow a second idea of where unsorted things go.
        case newNote(folder: String?)
        /// A task line. `nil` note means the vault's inbox note (`VaultSession.inboxNotePath`,
        /// `TaskDestination.inboxPath` when nothing is set); an existing note's path means the
        /// task is written there instead.
        case task(note: String?)
        /// The end of today's daily note, created if today has none yet.
        case today
        /// The end of a note that already exists.
        case note(String)

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
            case "task", "attività", "attivita": return .task(note: nil)
            case "today", "oggi": return .today
            case let other where other.hasPrefix("note:"):
                let path = String(other.dropFirst("note:".count))
                guard !path.isEmpty else {
                    throw ConnectorError("«note:» vuole il percorso di una nota dopo i due punti", usage: true)
                }
                return .note(path)
            case let other where other.hasPrefix("task:"):
                let path = String(other.dropFirst("task:".count))
                guard !path.isEmpty else {
                    throw ConnectorError("«task:» vuole il percorso di una nota dopo i due punti", usage: true)
                }
                return .task(note: path)
            case let other:
                throw ConnectorError(
                    "«\(other)» non è una destinazione; ci sono note, task, today, note:PERCORSO, task:PERCORSO",
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
    ) async throws -> WriteSummary {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            throw ConnectorError("serve il testo da catturare", usage: true)
        }
        if case .task = destination {} else if scheduled != nil || due != nil {
            throw ConnectorError(
                "le date valgono solo per un task: usa --dest task, oppure toglile",
                usage: true
            )
        }

        switch destination {
        case .task(let note):
            return try await addTask(session, text: body, scheduled: scheduled, due: due, note: note)
        case .today:
            return try await captureIntoDay(session, text: body)
        case .note(let path):
            return try await appendToNote(session, at: path, text: body)
        case .newNote(let folder):
            return try await captureAsNote(session, text: body, folder: folder)
        }
    }

    // MARK: Today

    /// Today's daily note, created when the day has none (the daily frontmatter,
    /// `type-note` alone, and an empty body: there is no daily template), then the text on
    /// the end of it.
    ///
    /// Two writes for one capture, and the summary describes the second: the first is
    /// the note coming into existence, which `dailyNote(for:)` has always done on
    /// demand and which nobody thinks of as part of what they captured.
    @MainActor
    private static func captureIntoDay(
        _ session: VaultSession, text: String
    ) async throws -> WriteSummary {
        let path: String
        do {
            path = try await session.dailyNote(for: .today)
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
        return try await appendToNote(session, at: path, text: text)
    }

    // MARK: A new note

    /// The first line titles the note, the rest becomes its body.
    ///
    /// One field captures both because the panel has one field. A first line
    /// `NoteName` refuses is not refused here: `CaptureTitle.derive` makes a legal title
    /// from it, and the whole text, first line included, becomes the body, so nothing
    /// typed is lost (ADR-0080 §D3). `createNote` still refuses an invalid title; it is
    /// never handed one. A derived title already taken is refused like a typed one.
    @MainActor
    private static func captureAsNote(
        _ session: VaultSession, text: String, folder: String?
    ) async throws -> WriteSummary {
        // Split at the first line break as the typed line reads one (`CaptureTitle.endsTypedLine`):
        // `"\r\n"` is one `Character`, so a split on `"\n"` left its `"\r"` on the title and in
        // the file name (PG-327). The body is the bytes after that break, as given: `append`
        // decides its breaks from the note's own (PG-322).
        let firstBreak = text.firstIndex(where: CaptureTitle.endsTypedLine)
        let derived = CaptureTitle.derive(
            fromTypedLine: CaptureTitle.typedLine(of: text), now: Date(), calendar: .current
        )
        let rest = derived.differsFromTyped
            ? text.trimmingCharacters(in: .whitespacesAndNewlines)
            : firstBreak
                .map { String(text[text.index(after: $0)...]) }?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let created = try await createNote(
            session,
            title: derived.title,
            folder: folder ?? session.inboxFolder,
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
        return try await appendToNote(session, at: created.path, text: rest)
    }
}
