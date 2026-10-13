import Foundation

// ADR-0085 §D10 and ADR-0086 §D6, plan docs/plans/pg-387-n4-birth-of-note.md - R-05, R-10, R-15.
// The payloads live here, never in `VaultPayloads.swift`, whose `LintFinding` and
// `PraticaSummary` are protected.

extension VaultAPI {
    /// `classify_note` / `perg note classify`.
    struct ClassifySummary: Encodable {
        let path: String
        let applied: Bool
        let diff: String?
        let movedTo: String?
        let note: String?
    }

    /// `extract_to_note` / `perg note extract`.
    struct ExtractSummary: Encodable {
        let created: String
        let applied: Bool
        let createdDiff: String?
        let sourceDiff: String?
        let sourceRefused: String?
        let note: String?
    }

    /// «Classifica» for a connector: `topics` is one comma-separated string, read through
    /// `TagEntry` like the app's field; `folder` optionally moves the note after the write.
    ///
    /// The diff is against the bytes read before the call, so a real run reports what it changed
    /// rather than an empty comparison with the file it just wrote.
    @MainActor
    static func classifyNote(
        _ session: VaultSession, at path: String, topics: String, folder: String?
    ) async throws -> ClassifySummary {
        guard !path.isEmpty else { throw ConnectorError("serve il percorso della nota", usage: true) }
        guard let before = try? session.read(path).text else { throw ConnectorError("«\(path)» non esiste") }
        let chosen = try parsedTopics(topics, session: session)
        do {
            let outcome = try await session.classifyNote(
                at: path, topics: chosen, toFolder: folder.flatMap { $0.isEmpty ? nil : $0 }
            )
            return ClassifySummary(
                path: path,
                applied: !session.isDryRun,
                diff: UnifiedDiff.between(before, outcome.written.text, path: path),
                movedTo: outcome.movedTo,
                note: outcome.moveProblem
            )
        } catch let refusal as ClassificationRefusal {
            throw ConnectorError(refusal.sentence, usage: true)
        } catch let refusal as VaultSession.NoteClassifyRefusal {
            throw ConnectorError(refusal.description, usage: true)
        } catch let refusal as VaultWriteRefusal {
            throw ConnectorError("non scritto: \(refusal.description)")
        }
    }

    /// «Estrai in una nota» for a connector: lines `fromLine`...`toLine` (1-based, inclusive,
    /// counted over the whole file) become a note in `folder` (the source's own when nil), and
    /// the source holds `[[title]]` in their place.
    @MainActor
    static func extractToNote(
        _ session: VaultSession, at path: String, fromLine: Int, toLine: Int,
        title: String, folder: String?, topics: String?
    ) async throws -> ExtractSummary {
        guard !path.isEmpty else { throw ConnectorError("serve il percorso della nota", usage: true) }
        guard !title.isEmpty else { throw ConnectorError("serve un titolo per la nota nuova", usage: true) }
        guard fromLine <= toLine else {
            throw ConnectorError("righe \(fromLine)-\(toLine): la prima viene dopo l'ultima", usage: true)
        }
        guard let text = try? session.read(path).text else { throw ConnectorError("«\(path)» non esiste") }
        let range: NSRange
        switch NoteExtraction.range(ofLines: fromLine...toLine, in: text) {
        case .success(let found): range = found
        case .failure(let refusal): throw ConnectorError(refusal.sentence, usage: true)
        }
        let chosen = try topics.map { try parsedTopics($0, session: session) } ?? []
        let destination = folder ?? (path as NSString).deletingLastPathComponent

        let outcome: VaultSession.ExtractOutcome
        do {
            outcome = try await session.extractToNote(
                from: path, range: range, expectedText: (text as NSString).substring(with: range),
                title: title, in: destination, topics: chosen, date: .today
            )
        } catch let refusal as NoteExtraction.Refusal {
            throw ConnectorError(refusal.sentence, usage: true)
        } catch let refusal as VaultSession.CreationError {
            throw ConnectorError("\(refusal)")
        }

        let created = outcome.created
        switch outcome.source {
        case .replaced(let replaced):
            return ExtractSummary(
                created: created.path, applied: !session.isDryRun,
                createdDiff: UnifiedDiff.between("", created.text, path: created.path, isNew: true),
                sourceDiff: UnifiedDiff.between(text, replaced.text, path: path),
                sourceRefused: nil, note: nil
            )
        case .refused(let sentence):
            return ExtractSummary(
                created: created.path, applied: !session.isDryRun,
                createdDiff: UnifiedDiff.between("", created.text, path: created.path, isNew: true),
                sourceDiff: nil, sourceRefused: sentence,
                note: "la nota «\(created.path)» è stata creata, ma «\(path)» non contiene il link"
            )
        }
    }

    // MARK: Templates (ADR-0086 §D6)

    /// The template `reference` names, resolved for `title` and `date` with `{{cursor}}` removed,
    /// or a usage error listing the templates when it names none or several.
    @MainActor
    static func resolvedTemplate(
        _ session: VaultSession, reference: String, title: String, date: CalendarDate
    ) throws -> NoteTemplate.Resolved {
        let path: String
        switch NoteTemplate.reference(reference, among: session.templates.map(\.relativePath)) {
        case .success(let found): path = found
        case .failure(let refusal): throw ConnectorError(refusal.sentence, usage: true)
        }
        guard let text = try? session.read(path).text else {
            throw ConnectorError("il modello «\(path)» non si legge")
        }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return NoteTemplate.resolve(
            NoteTemplate.body(of: text), title: title, date: date,
            time: TaskTime(hour: clock.hour ?? 0, minute: clock.minute ?? 0)
        )
    }

    /// `VaultSession.createNote` with a body, its refusal said as a connector error.
    @MainActor
    static func createNoteWritten(
        _ session: VaultSession, title: String, folder: String, topics: [Tag], date: CalendarDate, body: String
    ) async throws -> WriteSummary {
        do {
            let result = try await session.createNote(title: title, in: folder, date: date, topics: topics, body: body)
            return summarise(result, session: session)
        } catch let refusal as VaultSession.CreationError {
            throw ConnectorError("\(refusal)")
        }
    }

    /// A connector's comma-separated topic string as tags, a refused item as a usage error.
    @MainActor
    private static func parsedTopics(_ list: String, session: VaultSession) throws -> [Tag] {
        switch TagEntry.topics(fromList: list, vocabulary: session.vocabulary) {
        case .success(let topics): return topics
        case .failure(let refusal): throw ConnectorError(refusal.sentence, usage: true)
        }
    }
}
