import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 3 - R-08,
// R-12.

/// One imported message's `.md` file: the closed four-key frontmatter plus the
/// `pergamenum-mail-*` keys (SPEC "Message file frontmatter"), the new text as body,
/// and the quoted history (plus a signature) in a `<details>` block.
struct MessageDocument: Equatable, Sendable {
    enum Direction: String, Equatable, Sendable {
        case received
        case sent
    }

    enum BodyState: String, Equatable, Sendable {
        case complete
        case pending
    }

    struct MailFrontmatter: Equatable, Sendable {
        /// `pergamenum-mail` - the schema version of the keys below.
        var schemaVersion: Int
        /// `pergamenum-mail-message-id`, with the angle brackets (SPEC's own example
        /// keeps them, unlike `EmailHeaders.messageID`).
        var messageID: String
        var conversationID: Int?
        var direction: Direction
        /// `pergamenum-mail-date` - the header `Date`, governs ordering.
        var date: Date
        var received: Date?
        var from: String
        var to: [String]
        var cc: [String]
        /// Wikilinks, e.g. `"[[20260610_offerta-2024-118.pdf]]"`.
        var attachments: [String]
        var body: BodyState
        /// `pergamenum-mail-original` - absent when retention is off (R-09).
        var original: String?
    }

    var frontmatter: MailFrontmatter
    var newText: String
    var quotedHistory: String?
    var signature: String?

    /// Renders the full `.md` file text (R-08): closed frontmatter (`date`, `tags`,
    /// `related`, `aliases`) plus the `pergamenum-mail-*` keys, then `newText`, then a
    /// `<details>` block holding `quotedHistory` and, under its own `Firma` summary,
    /// `signature`.
    static func render(_ document: MessageDocument, tags: [Tag]) -> String {
        // Coder-owned.
        ""
    }

    /// Parses a message `.md` file back into structured form - used by R-08's
    /// collision rule (does an existing file carry this `Message-ID`?) and by the
    /// sync's "already on disk" dedup (SPEC "Membership rule", item 5) when the
    /// ledger does not have the answer.
    static func parse(_ text: String) -> MessageDocument? {
        // Coder-owned.
        nil
    }

    /// R-12: `sent` iff `from` is one of `ownAddresses` (case-insensitive) - **never**
    /// derived from the mailbox, so an archived sent message still counts as sent.
    static func direction(from: EmailAddress?, ownAddresses: Set<String>) -> Direction {
        // Coder-owned.
        .received
    }

    /// R-12: the sender of a received message; for a sent one, the first `to`
    /// recipient not in `ownAddresses`, else the first `cc`.
    static func counterpart(
        direction: Direction,
        from: EmailAddress?,
        to: [EmailAddress],
        cc: [EmailAddress],
        ownAddresses: Set<String>
    ) -> EmailAddress? {
        // Coder-owned.
        nil
    }
}
