import Foundation

// ADR-0085 §D4/§D8 and ADR-0086 §D3, plan docs/plans/pg-387-n4-birth-of-note.md - R-03, R-06,
// R-13, R-14. Shared with `perg` and `pergamenum-mcp` (named in `Project.swift`'s
// `sharedSources`): nothing here may reach for an app type.

extension VaultSession {
    /// Why «Classifica» refused a request before reading the rule (gate G-S).
    enum NoteClassifyRefusal: Error, Equatable, CustomStringConvertible {
        /// A folder was asked for on a Contenitore scheda, whose place is the Contenitore's
        /// (ADR-0071 §D7, ADR-0085 §D5).
        case schedaHasNoFolder

        var description: String {
            switch self {
            case .schedaHasNoFolder:
                "Un documento del Contenitore resta nel Contenitore: classificalo senza cartella."
            }
        }
    }

    // MARK: «Classifica»

    /// What «Classifica» did: the frontmatter write, and the optional move that followed it.
    struct NoteClassifyOutcome: Equatable, Sendable {
        let written: WriteResult
        /// The path the note moved to, nil when no move was asked for or the move failed.
        let movedTo: String?
        /// Why the move failed after the write landed; never thrown (the `addStructuralLink` rule).
        let moveProblem: String?
    }

    /// Classifies a note: one guarded write, then an optional move (ADR-0085 §D4).
    ///
    /// Write first, move second: a refused write moves nothing, and a failed move leaves a
    /// classified note where it was, reported in `moveProblem` rather than thrown. The move runs
    /// outside the write's gesture because `moveNote` opens its own, and a nested transaction
    /// asserts (ADR-0050). The rule's refusal (`ClassificationRefusal`) is thrown before any write.
    func classifyNote(at path: String, topics: [Tag], toFolder folder: String?) async throws -> NoteClassifyOutcome {
        let (record, text) = try read(path)
        if folder != nil, record.contenitore != nil { throw NoteClassifyRefusal.schedaHasNoFolder }

        var document = NoteDocument.parse(text)
        document.frontmatter.tags = try NoteClassification.classify(
            tags: document.frontmatter.tags, topics: topics, vocabulary: vocabulary
        ).get()
        let updated = document.serialized()
        let written = try await transaction("note classify") {
            try await write(updated, to: path, expecting: record.contentHash)
        }

        guard let folder, folder != (path as NSString).deletingLastPathComponent else {
            return NoteClassifyOutcome(written: written, movedTo: nil, moveProblem: nil)
        }
        do {
            let moved = try await moveNote(at: path, toFolder: folder)
            let left = VaultFileProblems.sentences(failures: moved.failures, refusals: moved.refusals)
            return NoteClassifyOutcome(written: written, movedTo: moved.newPath, moveProblem: left)
        } catch {
            return NoteClassifyOutcome(
                written: written, movedTo: nil,
                moveProblem: "classificata, ma non spostata in «\(folder)»: \(error)"
            )
        }
    }

    // MARK: «Estrai in una nota»

    /// What «Estrai» did: the new note, and whether the source took the `[[Titolo]]` link.
    struct ExtractOutcome: Equatable, Sendable {
        let created: WriteResult
        let source: SourceWrite

        enum SourceWrite: Equatable, Sendable {
            case replaced(WriteResult)
            case refused(String)
        }
    }

    /// Creates a note from `range` of `sourcePath`, then replaces the range with `[[Titolo]]`
    /// (ADR-0085 §D8): two writes in one gesture, the first `expectingAbsent:`, the second
    /// `expecting:` the hash the plan was computed from.
    ///
    /// A refused plan or a refused creation throws with nothing written. A refusal or failure of
    /// the second write keeps the new note and is returned as `.refused`, never thrown, so the
    /// caller can name both results (the `addStructuralLink` rule).
    func extractToNote(
        from sourcePath: String,
        range: NSRange,
        expectedText: String,
        title: String,
        in folder: String,
        topics: [Tag],
        date: CalendarDate
    ) async throws -> ExtractOutcome {
        try await transaction("note extract") {
            let (record, text) = try read(sourcePath)
            let plan = try NoteExtraction.plan(
                source: text, range: range, expectedText: expectedText, title: title
            ).get()
            let created = try await createNote(
                title: title, in: folder, date: date, topics: topics, body: plan.extracted + "\n"
            )
            do {
                let replaced = try await write(plan.replacedSource, to: sourcePath, expecting: record.contentHash)
                return ExtractOutcome(created: created, source: .replaced(replaced))
            } catch let refusal as WriteRefusal {
                return ExtractOutcome(created: created, source: .refused(refusal.description))
            } catch {
                return ExtractOutcome(
                    created: created, source: .refused("«\(sourcePath)» non aggiornata: \(error.localizedDescription)")
                )
            }
        }
    }

    // MARK: The day's note

    /// A day's note: where it is, whether the call created it, and where the template's
    /// `{{cursor}}` put the caret (an absolute UTF-16 offset in the written text).
    struct DailyNoteBirth: Equatable, Sendable {
        let path: String
        let created: Bool
        let caret: Int?
    }

    /// The one door every day's note is born through; `dailyNote(for:)` forwards here
    /// (ADR-0086 §D3).
    ///
    /// An existing day is returned untouched. A new one is created from the daily template when
    /// the setting names one, resolved for the day and for the time of `now`; a setting that is
    /// missing, unreadable or outside `Templates/` records a problem and the day is created bare,
    /// because a template never blocks the day.
    func dailyNoteBirth(for date: CalendarDate, at now: Date) async throws -> DailyNoteBirth {
        let path = dailyNotePath(for: date)
        if exists(path) { return DailyNoteBirth(path: path, created: false, caret: nil) }
        let title = date.compactForm
        let resolved = dailyTemplate(title: title, date: date, at: now)
        let result = try await createNote(
            title: title, in: settings.dailyFolder, date: date, category: .daily, body: resolved?.body ?? ""
        )
        return DailyNoteBirth(path: result.path, created: true, caret: resolved?.caret(inWritten: result.text))
    }

    /// The daily template resolved for `date` at `now`, or nil when the setting names none or
    /// names one that cannot be used (a problem is recorded for the latter).
    private func dailyTemplate(title: String, date: CalendarDate, at now: Date) -> NoteTemplate.Resolved? {
        guard let setting = settings.dailyTemplate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !setting.isEmpty
        else { return nil }
        let components = setting.split(separator: "/", omittingEmptySubsequences: false)
        guard NoteTemplate.isTemplate(setting), setting.hasSuffix(".md"), !components.contains("..") else {
            recordProblem("modello della nota del giorno ignorato: «\(setting)» non è una nota di \(NoteTemplate.folder)/")
            return nil
        }
        guard let text = try? read(setting).text else {
            recordProblem("modello della nota del giorno «\(setting)» non leggibile: giorno creato vuoto")
            return nil
        }
        let clock = Calendar.current.dateComponents([.hour, .minute], from: now)
        return NoteTemplate.resolve(
            NoteTemplate.body(of: text), title: title, date: date,
            time: TaskTime(hour: clock.hour ?? 0, minute: clock.minute ?? 0)
        )
    }
}

/// What a move left behind on the boards, as one sentence or nil.
private enum VaultFileProblems {
    static func sentences(failures: [String], refusals: [String]) -> String? {
        let all = failures + refusals.map { VaultWriteRefusal.movedOn($0).description }
        return all.isEmpty ? nil : all.joined(separator: "; ")
    }
}
