import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-03.

/// One row of the index's `mailboxes` table (probed schema, Task 1 PROBE 1: `ROWID`,
/// `url TEXT NOT NULL`, plus counters this feature never reads).
///
/// `url` is Mail's own identifier for the account/folder (`ews://…` for every account
/// on this Mac, per the SPEC's verified facts) - it is what the `.emlx` fan-out rule
/// resolves into a directory (ADR §D4, probed and implemented in Task 2's
/// `EMLXLocator`).
struct MailboxRef: Equatable, Hashable, Sendable {
    var rowID: Int
    var url: String
}
