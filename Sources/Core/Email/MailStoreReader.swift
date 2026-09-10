import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02,
// R-03.
//
// The read side: queries the *published copy* (`MailStoreCopy`) through a
// `MailStoreConnection`, never Mail's live database. The five queries R-03 names.
//
// None of the five throws. The copy they read was `PRAGMA quick_check`ed and counted
// before it was published (ADR §D2 step 3), so a failure here is a schema the store
// does not have rather than a torn file: the honest answer is "this index cannot
// answer that", which is an empty result or `.notResolvableFromIndex`.
struct MailStoreReader {
    /// `row(forMessageID:)`'s answer (ADR §D3).
    ///
    /// PROBE 1 (C9, measured on a published copy of this Mac's own store on
    /// 2026-09-09) confirmed `messages.message_id` is an opaque `INTEGER` hash in all
    /// 127,677 rows - no RFC `Message-ID` string can ever match it. It also found what
    /// the SPEC and the ADR did not know about: `message_global_data.message_id_header`
    /// is `TEXT` and holds the RFC id, for 123,693 of those rows (96.9%). §D3's own
    /// condition - "implemented only if Task 1's probe proves the index stores the RFC
    /// id in a queryable form" - is therefore met, through that table rather than
    /// through `messages.message_id`.
    ///
    /// `.notResolvableFromIndex` stays the answer for the remaining 3.1%, for a store
    /// whose schema predates that table, and for any id never seen - the ledger
    /// (`PraticaLedger`, Task 3) is still what makes those resolvable, exactly as §D3
    /// designed.
    enum RowLookup: Equatable, Sendable {
        case found(MailMessageRow)
        case notResolvableFromIndex
    }

    private let connection: MailStoreConnection

    /// The `~/Library/Mail/V10`-shaped directory the `.emlx` fan-out is resolved
    /// against. Never the published copy: the copy holds one file, `Envelope Index`,
    /// while every `.emlx` stays in Mail's own tree, read-only, where Mail put it.
    private let mailRoot: URL

    init(connection: MailStoreConnection) {
        self.connection = connection
        mailRoot = MailStoreLocation.resolve()
    }

    /// Opens `storeURL` (a published generation's `Envelope Index`,
    /// `MailStoreCopy.PublishResult`'s payload) read-only and wraps it.
    init(storeURL: URL) throws {
        connection = try MailStoreConnection.open(at: storeURL, readOnly: true)
        mailRoot = Self.mailRoot(forStoreAt: storeURL)
    }

    // MARK: - R-35: own-address pre-fill (Task 9)

    /// Distinct sender addresses of every message sent from a "Sent"/"Posta inviata"
    /// mailbox (SPEC "Sent detection and counterpart": Settings › Pratiche › «I miei
    /// indirizzi» "is a list, pre-filled from the index (`addresses` rows that appear
    /// as `sender` in Sent/Posta inviata mailboxes, deduplicated)"). This is the one
    /// read in this feature that genuinely needs the Mail store - it powers the
    /// Settings tab's pre-fill, never `VaultAPI` (R-36 forbids a connector from
    /// opening the store at all).
    ///
    /// Lower-cased and sorted: `MessageDocument.direction`'s own address comparison
    /// is already case-insensitive (`isOwn(_:_:)`), so a pre-filled list that still
    /// disagreed on case with a hand-typed address would be a second, silent notion
    /// of "the same address".
    ///
    /// `%Posta%Inviata%` rather than the `%Posta Inviata%` this function was declared
    /// with: a mailbox url is a URL, so the Italian name reaches the index either as
    /// `Posta Inviata` or percent-encoded as `Posta%20Inviata`, and one `LIKE`
    /// wildcard between the two words covers both without a second clause. `LIKE` is
    /// case-insensitive for ASCII in SQLite, so `Posta inviata` matches too.
    ///
    /// Deleted messages are not excluded, unlike every other query here: an address a
    /// message was sent *from* is still mine after that message goes to the trash, and
    /// a person who empties their Sent mailbox would otherwise pre-fill nothing.
    func sentSenderAddresses() -> [String] {
        let sql = """
        SELECT DISTINCT a.address
        FROM messages AS m
        JOIN addresses AS a ON a.ROWID = m.sender
        JOIN mailboxes AS mb ON mb.ROWID = m.mailbox
        WHERE mb.url LIKE '%Sent%' OR mb.url LIKE '%Posta%Inviata%'
        """
        let addresses = (try? collect(sql) { _ in } read: { statement in
            connection.columnText(statement, 0)?
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
        }) ?? []
        return Set(addresses.filter { !$0.isEmpty }).sorted()
    }

    // MARK: - R-03, the five queries

    /// Every non-deleted message whose `conversation_id` matches (R-03) - Mail's own
    /// threading (SPEC "Verified facts"), which membership evaluation follows
    /// (`MembershipRule`, Task 3) rather than reinventing.
    func messages(inConversation conversationID: Int) -> [MailMessageRow] {
        let sql = """
        \(Self.rowSelect)
        WHERE m.conversation_id = ?1 AND m.deleted = 0
        ORDER BY m.date_sent
        """
        var messages = (try? rows(sql) { connection.bindInt($0, 1, conversationID) }) ?? []
        let recipientsByMessage = recipients(forConversation: conversationID)
        for index in messages.indices {
            messages[index].recipients = recipientsByMessage[messages[index].rowID] ?? []
        }
        return messages
    }

    /// Conversations with at least one message from/to `address`, dated within
    /// `window` (R-03) - the tray's own candidate query (ADR §D2 / SPEC "Membership
    /// rule").
    ///
    /// Two statements, never one: the candidate ids are collected and the statement
    /// finalized before each conversation is read, rather than nesting a second query
    /// inside a stepping loop that is still open.
    func conversations(counterpart address: String, within window: ClosedRange<Date>) -> [MailConversation] {
        let sql = """
        SELECT m.conversation_id, MAX(m.date_sent) AS last_sent
        FROM messages AS m
        LEFT JOIN addresses AS a ON a.ROWID = m.sender
        WHERE m.deleted = 0
          AND m.date_sent BETWEEN ?1 AND ?2
          AND (a.address = ?3 COLLATE NOCASE
               OR EXISTS (
                   SELECT 1 FROM recipients AS r
                   JOIN addresses AS ra ON ra.ROWID = r.address
                   WHERE r.message = m.ROWID AND ra.address = ?3 COLLATE NOCASE
               ))
        GROUP BY m.conversation_id
        ORDER BY last_sent DESC
        """

        let identifiers: [Int]
        do {
            identifiers = try collect(sql) { statement in
                connection.bindInt(statement, 1, Self.storedDate(window.lowerBound))
                connection.bindInt(statement, 2, Self.storedDate(window.upperBound))
                connection.bindText(statement, 3, address)
            } read: { statement in
                connection.columnInt(statement, 0)
            }
        } catch {
            return []
        }

        return identifiers.map { MailConversation(conversationID: $0, messages: messages(inConversation: $0)) }
    }

    /// A row by RFC `Message-ID` (R-03), through `message_global_data.message_id_header`
    /// - see `RowLookup`. A store without that table (an older Mail, or the unit
    /// suite's fixture) fails to prepare the statement, which is the same answer said
    /// differently: this index cannot resolve that id.
    func row(forMessageID messageID: String) -> RowLookup {
        let sql = """
        \(Self.rowSelect)
        JOIN message_global_data AS g ON g.message_id = m.message_id
        WHERE g.message_id_header = ?1
        LIMIT 1
        """
        guard var found = try? rows(sql, bind: { connection.bindText($0, 1, messageID) }).first else {
            return .notResolvableFromIndex
        }
        found.recipients = recipients(forMessage: found.rowID)
        return .found(found)
    }

    /// Whether this store exposes a queryable `recipients` table (ADR §D24.4).
    /// Asked once per sync, because a store without one silently reduces the tray
    /// and the keyword arm to sender-only matching - the exact defect §D24 fixes,
    /// reintroduced by a schema rather than by code.
    ///
    func supportsRecipients() -> Bool {
        guard let statement = try? connection.prepare("SELECT 1 FROM recipients LIMIT 1") else {
            return false
        }
        defer { connection.finalize(statement) }
        return (try? connection.step(statement)) != nil
    }

    /// A row by index ROWID (ADR §D24, the sixth query) - needed by Task 5's
    /// regeneration flow, not by this task's tests.
    func row(rowID: Int) -> MailMessageRow? {
        let sql = """
        \(Self.rowSelect)
        WHERE m.ROWID = ?1
        LIMIT 1
        """
        guard var found = try? rows(sql, bind: { connection.bindInt($0, 1, rowID) }).first else {
            return nil
        }
        found.recipients = recipients(forMessage: found.rowID)
        return found
    }

    /// §D24.2: the recipients join for a whole conversation, one extra statement
    /// per conversation (never per message) - folded onto `messages(inConversation:)`'s
    /// already-built rows by the caller. Fails closed (an unpreparable statement, e.g.
    /// no `recipients` table, answers "no recipients" for everyone) rather than
    /// throwing (§D24.4).
    private func recipients(forConversation conversationID: Int) -> [Int: [String]] {
        let sql = """
        SELECT r.message, a.address
        FROM recipients AS r
        JOIN addresses AS a ON a.ROWID = r.address
        JOIN messages AS m ON m.ROWID = r.message
        WHERE m.conversation_id = ?1
        """
        let rows = (try? collect(sql) { statement in
            connection.bindInt(statement, 1, conversationID)
        } read: { statement -> (Int, String)? in
            guard let message = connection.columnInt(statement, 0),
                  let address = connection.columnText(statement, 1)
            else { return nil }
            return (message, address.lowercased())
        }) ?? []

        var byMessage: [Int: [String]] = [:]
        for (message, address) in rows {
            byMessage[message, default: []].append(address)
        }
        return byMessage
    }

    /// §D24.2's other `WHERE` variant, for a single message (`row(forMessageID:)`,
    /// `row(rowID:)`) - same fail-closed behavior as the conversation form above.
    private func recipients(forMessage rowID: Int) -> [String] {
        let sql = """
        SELECT r.message, a.address
        FROM recipients AS r
        JOIN addresses AS a ON a.ROWID = r.address
        WHERE r.message = ?1
        """
        return (try? collect(sql) { statement in
            connection.bindInt(statement, 1, rowID)
        } read: { statement in
            connection.columnText(statement, 1)?.lowercased()
        }) ?? []
    }

    /// Attachment names recorded for one message (R-03).
    func attachments(forMessage rowID: Int) -> [MailAttachmentRef] {
        let sql = "SELECT message, attachment_id, name FROM attachments WHERE message = ?1"
        let refs = try? collect(sql) { statement in
            connection.bindInt(statement, 1, rowID)
        } read: { statement in
            MailAttachmentRef(
                messageRowID: connection.columnInt(statement, 0) ?? rowID,
                attachmentID: connection.columnText(statement, 1),
                name: connection.columnText(statement, 2)
            )
        }
        return refs ?? []
    }

    /// The `.emlx` path predicted for a row from its mailbox url + ROWID (R-03,
    /// PROBE 2 / ADR §D4), measured on three real rows in three mailboxes of two
    /// accounts on 2026-09-09:
    ///
    ///     <root>/<account>/<Folder>.mbox[/<Sub>.mbox…]/<store-uuid>/Data/<fan>/Messages/<ROWID>.emlx
    ///
    /// - the account is the mailbox url's host, the folders are its path components
    ///   percent-decoded, one `.mbox` directory each, nested;
    /// - `<store-uuid>` is one UUID directory inside the `.mbox`, identical for every
    ///   mailbox of every account in this store - it is *not* in the index, so it is
    ///   read from the directory rather than derived;
    /// - `<fan>` is `ROWID / 1000` written one digit per directory **in reverse**, and
    ///   is empty for a ROWID below 1000 (measured: `146053` → `6/4/1`, `83970` →
    ///   `3/8`, `8900` → `8`, `169` → none).
    ///
    /// Predicted, never verified: whether that file exists, whether Mail parked a
    /// headers-only `<ROWID>.partial.emlx` there instead (PROBE 2 found 723 of them in
    /// one mailbox - R-15's «corpo non ancora scaricato», never R-16's «non più in
    /// Mail»), and the bounded enumeration that repairs a drifted rule are ADR §D4's
    /// `EMLXLocator`, Task 2.
    func emlxPath(forRow row: MailMessageRow) -> URL? {
        guard let mailbox = Self.mailboxDirectory(for: row.mailbox.url, under: mailRoot) else { return nil }
        var directory = Self.storeDirectory(in: mailbox).appending(path: "Data", directoryHint: .isDirectory)
        for digit in Self.fanOut(forRowID: row.rowID) {
            directory = directory.appending(path: digit, directoryHint: .isDirectory)
        }
        return directory
            .appending(path: "Messages", directoryHint: .isDirectory)
            .appending(path: "\(row.rowID).emlx", directoryHint: .notDirectory)
    }

    // MARK: - The shared row shape

    private static let rowSelect = """
    SELECT m.ROWID, m.message_id, m.global_message_id, s.subject, a.address,
           m.date_sent, m.date_received, m.mailbox, mb.url, m.conversation_id, m.deleted
    FROM messages AS m
    LEFT JOIN subjects AS s ON s.ROWID = m.subject
    LEFT JOIN addresses AS a ON a.ROWID = m.sender
    LEFT JOIN mailboxes AS mb ON mb.ROWID = m.mailbox
    """

    private func rows(_ sql: String, bind: (OpaquePointer) -> Void) throws -> [MailMessageRow] {
        try collect(sql, bind: bind) { statement in
            MailMessageRow(
                rowID: connection.columnInt(statement, 0) ?? 0,
                indexMessageIDHash: connection.columnInt(statement, 1),
                globalMessageID: connection.columnInt(statement, 2),
                subject: connection.columnText(statement, 3),
                sender: connection.columnText(statement, 4),
                dateSent: Self.date(connection.columnInt(statement, 5)),
                dateReceived: Self.date(connection.columnInt(statement, 6)),
                mailbox: MailboxRef(
                    rowID: connection.columnInt(statement, 7) ?? 0,
                    url: connection.columnText(statement, 8) ?? ""
                ),
                conversationID: connection.columnInt(statement, 9),
                deleted: (connection.columnInt(statement, 10) ?? 0) != 0,
                // The RFC id belongs to the ledger, not to this row (ADR §D3): a row
                // read straight out of the index carries none.
                messageID: nil
            )
        }
    }

    /// Prepare, bind, step to `SQLITE_DONE`, finalize - the one place a statement's
    /// lifetime is managed, so no caller can leak one.
    private func collect<Element>(
        _ sql: String,
        bind: (OpaquePointer) -> Void,
        read: (OpaquePointer) -> Element?
    ) throws -> [Element] {
        let statement = try connection.prepare(sql)
        defer { connection.finalize(statement) }
        bind(statement)

        var elements: [Element] = []
        while try connection.step(statement) {
            if let element = read(statement) {
                elements.append(element)
            }
        }
        return elements
    }

    // MARK: - Dates

    /// Mail stores both dates as whole seconds of **Unix** epoch, not the Mac absolute
    /// time the rest of this app's Foundation code defaults to. Measured on the
    /// published copy on 2026-09-09: `date_sent` runs `1195669666 … 1788976510`, which
    /// reads as `2007-11-21 … 2026-09-09 17:55` on the Unix epoch and as
    /// `2038 … 2057` on the Mac one - the upper bound is the hour the probe ran, so
    /// there is nothing to weigh. Read through `timeIntervalSinceReferenceDate` every
    /// message in a pratica would be dated thirty-one years into the future, silently,
    /// and the timeline would still look plausible one row at a time.
    private static func date(_ stored: Int?) -> Date? {
        guard let stored else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(stored))
    }

    private static func storedDate(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    // MARK: - Paths

    /// The fixture store and the published copy are told apart by the one directory
    /// name Mail's own layout guarantees: `<root>/MailData/Envelope Index`. A store
    /// opened anywhere else is a published generation (`<state>/gen-…/Envelope Index`),
    /// whose `.emlx` files live in the *live* tree, not beside the copy.
    private static func mailRoot(forStoreAt storeURL: URL) -> URL {
        let container = storeURL.deletingLastPathComponent()
        if container.lastPathComponent == "MailData" {
            return container.deletingLastPathComponent()
        }
        return MailStoreLocation.resolve()
    }

    private static func mailboxDirectory(for mailboxURL: String, under root: URL) -> URL? {
        // Decoded on both halves: `pathComponents` already decodes, and `host()`
        // defaults to the *encoded* form, which would spell a directory name Mail
        // never wrote if an account identifier ever stopped being a bare UUID.
        guard let parsed = URL(string: mailboxURL),
              let account = parsed.host(percentEncoded: false)
        else { return nil }
        var directory = root.appending(path: account, directoryHint: .isDirectory)
        for component in parsed.pathComponents where component != "/" {
            directory = directory.appending(path: "\(component).mbox", directoryHint: .isDirectory)
        }
        return directory
    }

    /// The UUID directory inside a `.mbox`, when there is one. Read rather than
    /// derived: PROBE 2 measured it identical across both accounts and all three
    /// mailboxes, but nothing in the index carries it, so guessing it would be
    /// guessing.
    private static func storeDirectory(in mailbox: URL) -> URL {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: mailbox, includingPropertiesForKeys: nil
        ) else { return mailbox }

        guard let store = entries.first(where: { UUID(uuidString: $0.lastPathComponent) != nil }) else {
            return mailbox
        }
        return mailbox.appending(path: store.lastPathComponent, directoryHint: .isDirectory)
    }

    /// `146053` → `["6", "4", "1"]`; `8900` → `["8"]`; `169` → `[]` (PROBE 2).
    private static func fanOut(forRowID rowID: Int) -> [String] {
        let quotient = rowID / 1000
        guard quotient > 0 else { return [] }
        return String(quotient).reversed().map(String.init)
    }
}
