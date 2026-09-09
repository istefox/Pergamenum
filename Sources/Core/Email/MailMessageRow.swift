import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-03.

/// One row of the index's `messages` table (probed schema, Task 1 PROBE 1), joined
/// against `addresses`/`subjects`/`mailboxes` at read time so a caller never sees the
/// index's own integer foreign keys.
struct MailMessageRow: Equatable, Sendable {
    var rowID: Int
    /// The index's own `messages.message_id` column - probed as `INTEGER` (PROBE 1,
    /// C9), i.e. an opaque hash, **not** the RFC 5322 `Message-ID` string. Kept only
    /// for diagnostics; no code resolves a row by this value (ADR §D3).
    var indexMessageIDHash: Int?
    var globalMessageID: Int?
    var subject: String?
    /// The sender's address, joined from `addresses.address` through
    /// `messages.sender`.
    var sender: String?
    var dateSent: Date?
    var dateReceived: Date?
    var mailbox: MailboxRef
    var conversationID: Int?
    var deleted: Bool
    /// The RFC `Message-ID`, when it is known - resolved through the ledger (ADR
    /// §D3, Task 3), never through the index. `nil` for a row the ledger has never
    /// seen.
    var messageID: String?
}
