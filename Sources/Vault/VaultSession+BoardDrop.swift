import Foundation

/// The one write a view makes (ADR-0009 §D5): a card dragged between two columns of a board.
///
/// **It narrows §D5 rather than contradicting it, and the reason is worth the paragraph.** The
/// ADR says the drop goes through "the vocabulary check of §4.4 like any other tag write", on
/// the stated premise that nothing in §4.4 says a note carries one status. It does: SPEC §4.4
/// lists *massimo un `status-*` (T-05)*, and tag.md 5.1 forbids `status-final` on a note
/// outright (reserved for a Deliverable, naming.md 6.1 - an export, never a note) - `perg lint`
/// reports both on a note the ADR's own example would produce. The vocabulary check alone would
/// therefore let a gesture write a tag the app's own linter refuses, in a note nobody is
/// looking at.
///
/// So the guard here is the whole of the tag linter rather than the vocabulary table, and it is
/// **differential**: the violations the note already has are compared with the ones it would
/// have, and the drop is refused only when it *introduces* one. A note that was already
/// non-conformant stays draggable, because the drag did not put it in that state and refusing
/// would leave the person no way out of it from the board that showed the problem - which is
/// the same argument §D5 makes for not refusing a multi-status card.
///
/// Not in `sharedSources`, so neither connector compiles it: a drop is a gesture, and the tag
/// write a command-line tool would want is a different command with its own arguments.
extension VaultSession {
    /// What a drop did, or why it did nothing.
    struct BoardDropOutcome: Sendable, Equatable {
        var path: String
        /// The journal id, when something was written. `undoJournalledWrites` takes it back.
        var journalID: String?
        /// The tag violations the drop would have introduced. Empty when it went through.
        var introduced: [TagViolation] = []
        /// Set when the refusal is not about conformance: an unreadable frontmatter, a file
        /// that would not write.
        var problem: String?

        var didWrite: Bool { journalID != nil }
    }

    /// Moves a note between two columns of a board: one tag out, one tag in.
    ///
    /// `from` nil is a drag out of *Senza stato*, `to` nil a drag into it (§D5). The journal is
    /// armed for exactly this write and disarmed after, the narrowing of ADR-0007 §D6 that
    /// ADR-0012 D7 already took for the tag rename: a person editing the note in front of them
    /// needs no undo log, and a note rewritten by a gesture on a card is not that.
    func moveOnBoard(_ path: String, from old: Tag?, to new: Tag?) async -> BoardDropOutcome {
        var outcome = BoardDropOutcome(path: path)
        guard old != new else { return outcome }

        guard let existing = try? read(path) else {
            outcome.problem = "non riesco a leggere \(path)"
            return outcome
        }
        guard let rewritten = TagRename.move(from: old, to: new, in: existing.text) else {
            outcome.problem = "non riesco a modificare i tag di questa nota senza riscriverle il frontmatter"
            return outcome
        }
        guard rewritten != existing.text else { return outcome }

        let before = violations(path: path, title: existing.record.title, text: existing.text).tags
        let after = violations(path: path, title: existing.record.title, text: rewritten).tags
        let introduced = after.filter { !before.contains($0) }
        guard introduced.isEmpty else {
            outcome.introduced = introduced
            return outcome
        }

        let journal = journalOnDisk
        let entriesBefore = Set(journal.entries().map(\.id))
        let previousJournal = self.journal
        let previousCommand = journalCommand
        self.journal = journal
        journalCommand = "board \(old?.description ?? "—") → \(new?.description ?? "—")"
        defer {
            self.journal = previousJournal
            journalCommand = previousCommand
        }

        // `expecting:` the hash `existing` was read with (ADR-0057 §D8, #496): a writer
        // landing between the read and this write is refused, never overwritten.
        do {
            try await write(rewritten, to: path, expecting: existing.record.contentHash)
        } catch let refusal as VaultSession.WriteRefusal {
            // Its own sentence: `localizedDescription` on this type is Foundation's generic one.
            outcome.problem = refusal.description
            return outcome
        } catch {
            outcome.problem = error.localizedDescription
            return outcome
        }
        outcome.journalID = journal.entries().first { !entriesBefore.contains($0.id) }?.id
        return outcome
    }
}
