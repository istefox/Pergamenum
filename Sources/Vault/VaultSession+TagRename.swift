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
    /// and the notes that refused to be written.
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

        let journal = WriteJournal(root: root)
        let entriesBefore = Set(journal.entries().map(\.id))
        let previousJournal = self.journal
        let previousCommand = journalCommand
        self.journal = journal
        journalCommand = "tag rename \(old) → \(new)"
        defer {
            self.journal = previousJournal
            journalCommand = previousCommand
        }

        var outcome = TagRenameOutcome()
        for change in changes {
            do {
                try write(change.after, to: change.path)
                outcome.changed.append(change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error.localizedDescription)")
            }
        }
        // Read back rather than remembered as they were written: `write` records through the
        // journal itself, and asking the journal what it now holds is the only account of the
        // group that cannot disagree with the file.
        outcome.journalIDs = journal.entries()
            .filter { !entriesBefore.contains($0.id) }
            .map(\.id)
        return outcome
    }

    /// Puts a whole group back, refusing any note that has moved on since.
    ///
    /// The guarantee `WriteJournal` gives per file, applied to a group: a note edited after the
    /// rename keeps its edit and is named in the refusals, rather than being quietly overwritten
    /// with a version that predates work the journal knows nothing about. Newest first, so a
    /// note written twice in the group ends on its oldest text.
    @discardableResult
    func undoTagRename(_ ids: [String]) -> TagRenameOutcome {
        let journal = WriteJournal(root: root)
        var outcome = TagRenameOutcome()
        for id in ids.reversed() {
            guard let entry = journal.entry(id: id) else {
                outcome.failures.append("\(id): non è nel journal")
                continue
            }
            guard let current = try? read(entry.path) else {
                outcome.failures.append("\(entry.path): non c'è più")
                continue
            }
            guard current.record.contentHash == entry.hashAfter else {
                outcome.failures.append("\(entry.path): è cambiato dopo la rinomina, non lo tocco")
                continue
            }
            guard let textBefore = entry.textBefore else {
                outcome.failures.append("\(entry.path): quella scrittura ha creato il file")
                continue
            }
            do {
                try write(textBefore, to: entry.path)
                outcome.changed.append(entry.path)
            } catch {
                outcome.failures.append("\(entry.path): \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
