import Foundation

/// Everything a connector can ask the vault without changing it.
///
/// Thin by design: `VaultSession` and `IndexSnapshot` already know how to answer, and
/// what is added here is the shape of the answer plus the sentence said when a path is
/// not there. Both connectors call these, so neither can quietly answer differently.
extension VaultAPI {
    @MainActor
    static func notes(_ session: VaultSession, inFolder folder: String?) -> [NoteSummary] {
        // A path prefix, which is how a person thinks about a vault whose folders are
        // its only structure.
        session.index.allNotes
            .filter { folder.map($0.relativePath.hasPrefix) ?? true }
            .map(NoteSummary.init)
    }

    @MainActor
    static func note(_ session: VaultSession, at path: String) throws -> NoteText {
        guard let (record, text) = try? session.read(path) else {
            throw ConnectorError("non riesco a leggere «\(path)»")
        }
        return NoteText(note: NoteSummary(record), text: text)
    }

    @MainActor
    static func links(_ session: VaultSession, at path: String) throws -> LinkSummary {
        guard let record = session.index.note(at: path) else {
            throw ConnectorError("«\(path)» non è nell'indice")
        }
        return LinkSummary(
            resolved: record.linkTargets.filter { !session.index.resolve(title: $0).isEmpty },
            unresolved: record.linkTargets.filter { session.index.resolve(title: $0).isEmpty }
        )
    }

    /// By title, not by path: a backlink is a wikilink, and a wikilink names a title.
    @MainActor
    static func backlinks(_ session: VaultSession, toTitle title: String) throws -> [NoteReference] {
        guard !title.isEmpty else {
            throw ConnectorError("serve un titolo a cui cercare i backlink", usage: true)
        }
        return session.index.backlinks(toTitle: title).map(NoteReference.init)
    }

    @MainActor
    static func unresolvedLinks(_ session: VaultSession) -> [UnresolvedLink] {
        session.index.unresolvedLinks().map {
            UnresolvedLink(target: $0.target, sources: $0.sources.map(\.relativePath))
        }
    }

    /// A `limit` a read can use (ADR-0063 §D1.1): absent stays absent, `0` is legal and
    /// answers empty, and a negative number is the caller's bug, refused rather than
    /// clamped so it is seen.
    static func checkedLimit(_ limit: Int?, named name: String = "limit") throws -> Int? {
        if let limit, limit < 0 { throw limitRefusal(named: name, raw: String(limit)) }
        return limit
    }

    /// An argument's text read into a number (ADR-0063 §D1.2), for the front ends that
    /// receive a `limit` as text. `nil` means the argument was not given; text `Int.init`
    /// cannot read, `""` included, is refused with the same sentence as a negative number,
    /// never mistaken for «no limit». `"-1"` reads as `-1` and is refused by
    /// `checkedLimit`, not here.
    static func limit(parsing text: String?, named name: String = "limit") throws -> Int? {
        guard let text else { return nil }
        guard let number = Int(text) else { throw limitRefusal(named: name, raw: text) }
        return number
    }

    /// The one sentence both refusals say, so a script or a model sees the same words
    /// whichever way the number arrived wrong.
    private static func limitRefusal(named name: String, raw: String) -> ConnectorError {
        ConnectorError("«\(name)» vuole un numero intero da 0 in su: «\(raw)» non lo è", usage: true)
    }

    @MainActor
    static func search(_ session: VaultSession, _ raw: String, limit: Int?) throws -> [SearchHit] {
        let limit = try checkedLimit(limit)
        guard !raw.isEmpty else {
            throw ConnectorError(
                #"serve una query: tag:, path:, task:open, "frase esatta" e parole, in AND"#,
                usage: true
            )
        }
        return session.search(SearchQuery(raw), limit: limit ?? 200).map(SearchHit.init)
    }

    @MainActor
    static func tasks(
        _ session: VaultSession, view: String?, on rawDay: String?, includingCompleted: Bool
    ) throws -> [TaskSummary] {
        session.index.tasks(
            for: try taskView(view), on: try day(rawDay), includingCompleted: includingCompleted
        ).map(TaskSummary.init)
    }

    @MainActor
    static func day(_ session: VaultSession, on rawDay: String?) throws -> DaySummary {
        let date = try day(rawDay)
        let path = session.dailyNotePath(for: date)
        return DaySummary(
            date: date.description,
            notePath: path,
            noteExists: session.exists(path),
            blocks: session.timeBlocks(on: date).map(BlockSummary.init),
            scheduled: session.index.allTasks.filter { $0.isScheduled(on: date) }.map(TaskSummary.init),
            due: session.index.allTasks.filter(\.state.isOpen).filter { $0.due == date }.map(TaskSummary.init)
        )
    }

    /// The conformance check of SPEC §4.7, over one note or over the whole vault.
    ///
    /// The tag tables live in `.pergamenum/vocabolari.json`, a replica of harness-system
    /// (SPEC §4.6). A vault the app has never opened has no replica, and neither
    /// connector has a resource bundle to seed one from - so the vocabulary is empty and
    /// the tag rules have nothing to judge against. `warning` says so rather than
    /// letting a clean report be trusted for more than it is.
    @MainActor
    static func lint(_ session: VaultSession, at path: String?) throws -> LintReport {
        let paths: [String]
        if let path {
            guard session.exists(path) else { throw ConnectorError("«\(path)» non è nel vault") }
            paths = [path]
        } else {
            paths = session.index.allNotes.map(\.relativePath)
        }

        let findings = paths.compactMap { path -> LintFinding? in
            guard let violations = session.violations(forRecordAt: path), !violations.isEmpty else {
                return nil
            }
            return LintFinding(path: path, violations)
        }

        return LintReport(
            checked: paths.count,
            conformant: paths.count - findings.count,
            findings: findings,
            warning: session.vocabulary.isEmpty
                ? """
                  nessun vocabolario in .pergamenum/vocabolari.json: le regole sui tag non \
                  sono state applicate. Apri il vault in Pergamenum una volta, o copiaci il file.
                  """
                : nil
        )
    }

    @MainActor
    static func stats(_ session: VaultSession) -> VaultStats {
        let index = session.index
        let duration = index.lastScanDuration.components
        return VaultStats(
            vault: session.root.path(percentEncoded: false),
            notes: index.count,
            tasks: index.allTasks.count,
            openTasks: index.allTasks.filter(\.state.isOpen).count,
            unresolvedLinks: index.unresolvedLinks().count,
            reusedFromCache: index.reusedFromCache,
            failures: index.failures,
            scanMilliseconds: Int(duration.seconds * 1000)
                + Int(duration.attoseconds / 1_000_000_000_000_000)
        )
    }
}
