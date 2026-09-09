import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02,
// R-03.
//
// The read side: queries the *published copy* (`MailStoreCopy`) through a
// `MailStoreConnection`, never Mail's live database. The five queries R-03 names.
struct MailStoreReader {
    /// `row(forMessageID:)`'s answer (ADR §D3): the index's own `message_id` column
    /// is probed as an opaque `INTEGER` hash (PROBE 1, C9), not a queryable RFC
    /// `Message-ID` string, so a lookup by that string can only ever be answered
    /// `.notResolvableFromIndex` here - resolving it for real is the ledger's job
    /// (`PraticaLedger`, Task 3), not this reader's.
    enum RowLookup: Equatable, Sendable {
        case found(MailMessageRow)
        case notResolvableFromIndex
    }

    private let connection: MailStoreConnection

    init(connection: MailStoreConnection) {
        self.connection = connection
    }

    /// Opens `storeURL` (a published generation's `Envelope Index`,
    /// `MailStoreCopy.PublishResult`'s payload) read-only and wraps it.
    init(storeURL: URL) throws {
        self.init(connection: try MailStoreConnection.open(at: storeURL, readOnly: true))
    }

    /// Every non-deleted message whose `conversation_id` matches (R-03) - Mail's own
    /// threading (SPEC "Verified facts"), which membership evaluation follows
    /// (`MembershipRule`, Task 3) rather than reinventing.
    ///
    /// Stub: tester-declared boundary (ADR-0155). Unreachable today - `init(storeURL:)`
    /// always throws until the coder implements `MailStoreConnection.open`.
    func messages(inConversation conversationID: Int) -> [MailMessageRow] {
        fatalError("MailStoreReader.messages(inConversation:) is unreachable until MailStoreConnection.open works")
    }

    /// Conversations with at least one message from/to `address`, dated within
    /// `window` (R-03) - the tray's own candidate query (ADR §D2 / SPEC "Membership
    /// rule").
    ///
    /// Stub: tester-declared boundary (ADR-0155). Unreachable today, see above.
    func conversations(counterpart address: String, within window: ClosedRange<Date>) -> [MailConversation] {
        fatalError("MailStoreReader.conversations(counterpart:within:) unreachable until MailStoreConnection.open works")
    }

    /// A row by RFC `Message-ID` (R-03). See `RowLookup`'s own doc comment: given
    /// PROBE 1's answer, the honest result is always `.notResolvableFromIndex` -
    /// still routed through the connection for interface consistency with the other
    /// four queries, and still a coder-owned body under ADR-0155.
    ///
    /// Stub: tester-declared boundary (ADR-0155). Unreachable today, see above.
    func row(forMessageID messageID: String) -> RowLookup {
        fatalError("MailStoreReader.row(forMessageID:) is unreachable until MailStoreConnection.open works")
    }

    /// Attachment names recorded for one message (R-03).
    ///
    /// Stub: tester-declared boundary (ADR-0155). Unreachable today, see above.
    func attachments(forMessage rowID: Int) -> [MailAttachmentRef] {
        fatalError("MailStoreReader.attachments(forMessage:) is unreachable until MailStoreConnection.open works")
    }

    /// The `.emlx` path predicted for a row from its mailbox url + ROWID (R-03,
    /// PROBE 2 / ADR §D4). The digit-fan rule PROBE 2 measures and the
    /// `.found`/`.notInStore`/`.ruleFailed` distinction both live in Task 2's
    /// `EMLXLocator`; this is the thin, store-aware entry point R-03 names directly
    /// on `MailStoreReader`.
    ///
    /// Stub: tester-declared boundary (ADR-0155). Unreachable today, see above.
    func emlxPath(forRow row: MailMessageRow) -> URL? {
        fatalError("MailStoreReader.emlxPath(forRow:) is unreachable until MailStoreConnection.open works")
    }
}
