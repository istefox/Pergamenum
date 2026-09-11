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
    /// Every recipient address of this message - To, Cc and Bcc alike, lower-cased,
    /// joined from `recipients` through `addresses` (ADR §D24.1). Empty for a store
    /// whose schema has no `recipients` table and for a message that has none.
    ///
    /// Flat, with no To/Cc/Bcc distinction: every consumer asks "does this message
    /// touch this address", and nothing in this feature renders or filters by
    /// recipient kind.
    ///
    /// Declared **last** and defaulted so the memberwise initialiser stays
    /// source-compatible with every existing construction site (`Tests/PraticaSyncTests.swift`,
    /// `Tests/MembershipRuleTests.swift`, `Tests/MailStoreReaderTests.swift`,
    /// `Tests/PraticaTrayTests.swift`).
    var recipients: [String] = []
}
