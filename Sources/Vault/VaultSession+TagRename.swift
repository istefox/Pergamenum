import Foundation

/// Renaming a tag across the whole vault (ADR-0012 D7).
///
/// **N single-note writes through `write`, journalled, presented as one operation.** The
/// expensive answer, chosen on purpose: it is the first multi-note write in this app that does
/// *not* go around the journal, and it is the shape `note rename|move|trash` will need in M13.
/// `NoteFileOperations` rewrites links outside `VaultSession.write` today, which is why neither
/// connector can offer those commands - doing this the same way would double that debt.
///
/// **It narrows ADR-0007 §D6 rather than contradicting it.** The app arms no journal, because
/// a person editing the note in front of them does not need an undo log beside the file. That
/// reasoning is about one note being looked at. It does not reach forty notes rewritten at
/// once, thirty-nine of which are off screen and none of which will be proof-read - so the
/// journal is armed for the duration of this one operation and disarmed after.
extension VaultSession {
    /// One note the rename would touch, and the text it would get.
    struct TagRenameChange: Sendable, Equatable, Identifiable {
        var id: String { path }
        let path: String
        let title: String
        let before: String
        let after: String
    }

    /// What a performed rename left behind: what changed, the journal ids that can put it back,
    /// and the notes that refused to be written. Named for its first caller; `undoJournalledWrites`
    /// hands the same shape back to a board's drop.
    struct TagRenameOutcome: Sendable, Equatable {
        var changed: [String] = []
        var journalIDs: [String] = []
        var failures: [String] = []
    }

    /// The notes carrying the tag, with the text each would get. Reads files; writes nothing.
    ///
    /// This is what the sheet shows before anything happens, and it is computed by the same
    /// function that performs the change - not by a second one that would drift from it.
    func tagRenamePreview(_ old: Tag, to new: Tag) -> [TagRenameChange] {
        index.allNotes
            .filter { $0.frontmatter.tags.contains(old) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .compactMap { record in
                guard let existing = try? read(record.relativePath),
                      let rewritten = TagRename.apply(old, to: new, in: existing.text)
                else { return nil }
                return TagRenameChange(
                    path: record.relativePath,
                    title: record.title,
                    before: existing.text,
                    after: rewritten
                )
            }
    }

    /// Performs the rename, one note at a time, with the journal armed for exactly as long as
    /// it takes and disarmed again afterwards.
    ///
    /// A note that fails is reported and the rest go on: stopping half way through would leave
    /// the vault split between two spellings of the same tag with no record of where the line
    /// fell.
    @discardableResult
    func renameTag(_ old: Tag, to new: Tag) -> TagRenameOutcome {
        let changes = tagRenamePreview(old, to: new)
        guard !changes.isEmpty else { return TagRenameOutcome() }

        let journal = journalOnDisk
        let entriesBefore = Set(journal.entries().map(\.id))
        let previousJournal = self.journal
        let previousCommand = journalCommand
        self.journal = journal
        journalCommand = "tag rename \(old) → \(new)"
        defer {
            self.journal = previousJournal
            journalCommand = previousCommand
        }

        let fileChanges = changes.map {
            VaultFileChange(path: $0.path, before: $0.before, after: $0.after)
        }
        let result = VaultPlanApplication.apply(fileChanges) {
            try write($0.after, to: $0.path)
        }
        var outcome = TagRenameOutcome(changed: result.rewrittenPaths, failures: result.failures)
        // Read back rather than remembered as they were written: `write` records through the
        // journal itself, and asking the journal what it now holds is the only account of the
        // group that cannot disagree with the file.
        outcome.journalIDs = journal.entries()
            .filter { !entriesBefore.contains($0.id) }
            .map(\.id)
        return outcome
    }

    /// Puts a whole group of journalled writes back, all of it or none of it (ADR-0016 §D5).
    ///
    /// Named for what it does rather than for the rename, because it is not only the rename's
    /// any more: a board's drop (ADR-0009 §D5) is one journalled write and comes back through
    /// this same function with a single id.
    ///
    /// **Refuses the whole group rather than the notes that moved on**, since this plan's second
    /// decision: two undo semantics in one app is the drift this codebase keeps refusing, so a
    /// note edited after the rename now keeps the rest of the group from coming back too, named
    /// among the refusals rather than left as the one exception the rest silently succeeded
    /// around. `preflightUndo`/`performUndo` on `VaultSession+Journal` are the shared guard and
    /// the shared reversal, so this and `undo(operation:)` cannot drift onto two different rules
    /// for the same three kinds.
    @discardableResult
    func undoJournalledWrites(_ ids: [String]) -> TagRenameOutcome {
        let journal = journalOnDisk
        // `entry(id:)` re-reads and re-decodes the whole file per id. One read, keyed by
        // id, answers the same thing: `uniquingKeysWith: { _, last in last }` keeps the
        // last line carrying an id, which is exactly `entries().last { $0.id == id }`.
        let byID = Dictionary(
            journal.entries().map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }
        )
        var entries: [WriteJournal.Entry] = []
        var missing: [String] = []
        for id in ids {
            if let entry = byID[id] {
                entries.append(entry)
            } else {
                missing.append("\(id): non è nel journal")
            }
        }

        let failures = missing + preflightUndo(entries)
        guard failures.isEmpty else { return TagRenameOutcome(failures: failures) }

        let (changed, runtimeFailures) = performUndo(entries)
        return TagRenameOutcome(changed: changed, failures: runtimeFailures)
    }
}
