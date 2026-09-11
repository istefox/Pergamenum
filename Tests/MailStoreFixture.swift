import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02,
// R-03, R-19.
//
// Builds a small, synthetic Envelope Index and matching `.emlx` files for the Mail
// tests (ADR §D7): nothing here is copied out of `~/Library/Mail` - every byte is
// authored in this file, the same rule `-disableCalendar`'s UI-test fixtures follow.
// The `CREATE TABLE` statements below reproduce, column-for-column, the schema read
// once by hand from a throwaway copy of this Mac's own `Envelope Index`
// (`PRAGMA table_info`, never a `SELECT` of a row) on 2026-09-09 and deleted
// immediately after - see this dispatch's own report for the exact output (PROBE 1
// SCHEMA).
//
// Populated through the `sqlite3` command-line tool via `Process`, never through
// `sqlite3_` calls - that stays inside `Sources/Core/Email/MailStoreConnection.swift`
// alone (ADR §D1), which is exactly what
// `Tests/MailStoreReaderTests.swift.onlyMailStoreConnectionMentionsSQLite3Symbols`
// checks.
enum MailStoreFixture {
    struct Mailbox: Sendable {
        var rowID: Int
        var url: String
    }

    struct Attachment: Sendable {
        var attachmentID: String
        var name: String
    }

    struct Message: Sendable {
        var rowID: Int
        var subject: String
        var senderAddress: String
        var mailboxRowID: Int
        var conversationID: Int
        var dateSent: Date
        var dateReceived: Date
        var deleted: Bool = false
        var attachments: [Attachment] = []
        var emlxBody: String = "Subject: test\n\ncorpo del messaggio di prova.\n"
        /// Recipient addresses joined into `recipients` through `addresses`, exactly
        /// the shape Task 2's live probe confirmed (ADR §D24.5's "Follow-up - Task 2
        /// probe results, PG-119": column names, no schema correction needed). Empty
        /// by default - most fixture messages in the existing suites carry none.
        var recipients: [String] = []
    }

    struct Built {
        /// Shaped like `~/Library/Mail/V10` - what `MailStoreLocation.resolve()` is
        /// meant to return under `-mailStoreRoot`.
        var root: URL
        /// `<root>/MailData/Envelope Index`.
        var indexURL: URL
        var mailboxes: [Mailbox]
        var messages: [Message]
    }

    enum FixtureError: Error, CustomStringConvertible, Equatable {
        case sqlite3NotFound(path: String)
        case scriptFailed(exitCode: Int32, stderr: String)

        var description: String {
            switch self {
            case let .sqlite3NotFound(path):
                "il tool sqlite3 non è stato trovato in \(path)"
            case let .scriptFailed(exitCode, stderr):
                "sqlite3 è uscito con codice \(exitCode): \(stderr)"
            }
        }
    }

    /// Creates a fresh temporary directory holding a real, schema-accurate
    /// `Envelope Index` plus one `.emlx` file per message. `directory` lets a test
    /// reuse the same root across two `build` calls (to simulate an unchanged vs.
    /// changed source mtime); when `nil`, a fresh one-per-call directory is used.
    static func build(
        mailboxes: [Mailbox],
        messages: [Message],
        in directory: URL? = nil
    ) throws -> Built {
        let root = try directory ?? freshRoot()
        let mailDataDirectory = root.appending(path: "MailData", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mailDataDirectory, withIntermediateDirectories: true)
        let indexURL = mailDataDirectory.appending(path: "Envelope Index", directoryHint: .notDirectory)

        // A rebuild in place (same `directory`) starts from a clean database, or the
        // second `CREATE TABLE` in the same file would fail.
        try? FileManager.default.removeItem(at: indexURL)

        try runSQLite3(script: sqlScript(mailboxes: mailboxes, messages: messages), databasePath: indexURL)

        for message in messages {
            try writeEMLX(message, mailboxes: mailboxes, root: root)
        }

        return Built(root: root, indexURL: indexURL, mailboxes: mailboxes, messages: messages)
    }

    /// Removes `recipients` from an already-built fixture's index, in place - the
    /// "older Mail / mis-named table" shape `supportsRecipients()` and the recipients
    /// join must both fail closed against, never throw (ADR §D24.4).
    static func dropRecipientsTable(indexURL: URL) throws {
        let statement = ["DROP", "TABLE recipients;"].joined(separator: " ")
        try runSQLite3(script: statement, databasePath: indexURL)
    }

    // MARK: - Directory scaffolding

    private static func freshRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mailstore-fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// PROBE 2's measured rule (ADR §D4,
    /// `MailStoreReader.emlxPath(forRow:)`'s own doc comment): the account directory
    /// is the mailbox url's host, each path component becomes a nested `.mbox`
    /// directory, then `Data/<fan>/Messages/<ROWID>.emlx` - `<fan>` is `ROWID / 1000`
    /// written one digit per directory in reverse, empty below 1000. Deliberately
    /// writes **no** store-uuid level: `MailStoreReader.storeDirectory(in:)` falls
    /// back to the `.mbox` itself when it finds none, and that fallback is the layout
    /// this fixture exercises.
    private static func writeEMLX(_ message: Message, mailboxes: [Mailbox], root: URL) throws {
        guard let mailbox = mailboxes.first(where: { $0.rowID == message.mailboxRowID }) else { return }
        guard let parsedURL = URL(string: mailbox.url),
              let account = parsedURL.host(percentEncoded: false)
        else { return }

        var directory = root.appending(path: account, directoryHint: .isDirectory)
        for component in parsedURL.pathComponents where component != "/" {
            directory = directory.appending(path: "\(component).mbox", directoryHint: .isDirectory)
        }
        directory = directory.appending(path: "Data", directoryHint: .isDirectory)
        for digit in fanOut(forRowID: message.rowID) {
            directory = directory.appending(path: digit, directoryHint: .isDirectory)
        }
        let messagesDirectory = directory.appending(path: "Messages", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messagesDirectory, withIntermediateDirectories: true)
        let emlxURL = messagesDirectory.appending(path: "\(message.rowID).emlx", directoryHint: .notDirectory)

        let bodyData = Data(message.emlxBody.utf8)
        var fileData = Data("\(bodyData.count)\n".utf8)
        fileData.append(bodyData)
        try fileData.write(to: emlxURL)
    }

    /// `146053` → `["6", "4", "1"]`; `8900` → `["8"]`; `169` → `[]` - the same rule
    /// `MailStoreReader.fanOut(forRowID:)` implements, kept here so the fixture never
    /// depends on production code for its own layout.
    private static func fanOut(forRowID rowID: Int) -> [String] {
        let quotient = rowID / 1000
        guard quotient > 0 else { return [] }
        return String(quotient).reversed().map(String.init)
    }

    // MARK: - The SQL script

    private static func sqlScript(mailboxes: [Mailbox], messages: [Message]) -> String {
        var statements: [String] = [schemaSQL]

        for mailbox in mailboxes {
            statements.append(
                "INSERT INTO mailboxes (ROWID, url) VALUES (\(mailbox.rowID), '\(escaped(mailbox.url))');"
            )
        }

        var addressRowIDByAddress: [String: Int] = [:]
        var subjectRowIDBySubject: [String: Int] = [:]

        for message in messages {
            let senderRowID = rowID(for: message.senderAddress, in: &addressRowIDByAddress) { nextRowID in
                let address = escaped(message.senderAddress)
                statements.append(
                    "INSERT INTO addresses (ROWID, address, comment) VALUES (\(nextRowID), '\(address)', '');"
                )
            }
            let subjectRowID = rowID(for: message.subject, in: &subjectRowIDBySubject) { nextRowID in
                statements.append(
                    "INSERT INTO subjects (ROWID, subject) VALUES (\(nextRowID), '\(escaped(message.subject))');"
                )
            }

            // `date_sent`/`date_received` are whole seconds of Unix epoch time in the
            // real Envelope Index (PROBE 1, measured range 2007-11-21 … 2026-09-09 on
            // the published copy), never Mac absolute time - see
            // `MailStoreReader.date(_:)`'s own doc comment for the same measurement.
            statements.append("""
            INSERT INTO messages (
                ROWID, message_id, global_message_id, sender, subject,
                date_sent, date_received, mailbox, deleted, conversation_id
            ) VALUES (
                \(message.rowID), \(indexMessageIDHash(for: message.rowID)), \(message.rowID),
                \(senderRowID), \(subjectRowID),
                \(Int(message.dateSent.timeIntervalSince1970)),
                \(Int(message.dateReceived.timeIntervalSince1970)),
                \(message.mailboxRowID), \(message.deleted ? 1 : 0), \(message.conversationID)
            );
            """)

            for attachment in message.attachments {
                statements.append("""
                INSERT INTO attachments (message, attachment_id, name)
                VALUES (\(message.rowID), '\(escaped(attachment.attachmentID))', '\(escaped(attachment.name))');
                """)
            }

            // §D24.1's join target: `recipients.message`/`.address` → `addresses.ROWID`,
            // column-for-column what Task 2's live probe measured (ADR §D24.5's own
            // follow-up note). Reuses `addressRowIDByAddress` so a recipient sharing an
            // address with a sender (or another recipient) is not inserted twice.
            for (position, recipientAddress) in message.recipients.enumerated() {
                let recipientRowID = rowID(for: recipientAddress, in: &addressRowIDByAddress) { nextRowID in
                    let address = escaped(recipientAddress)
                    statements.append(
                        "INSERT INTO addresses (ROWID, address, comment) VALUES (\(nextRowID), '\(address)', '');"
                    )
                }
                statements.append("""
                INSERT INTO recipients (message, address, position)
                VALUES (\(message.rowID), \(recipientRowID), \(position));
                """)
            }

            // 96.9% of a real store's rows carry this (PROBE 1, `MailStoreReader.row(forMessageID:)`'s
            // own doc comment) - the fixture reproduces it whenever the authored `emlxBody` actually
            // carries a `Message-ID` header, so `row(forMessageID:)` is exercised the same way a real
            // store answers it, not always `.notResolvableFromIndex`.
            if let header = messageIDHeader(in: message.emlxBody) {
                statements.append("""
                INSERT INTO message_global_data (ROWID, message_id, message_id_header)
                VALUES (\(message.rowID), \(indexMessageIDHash(for: message.rowID)), '\(escaped(header))');
                """)
            }
        }

        return statements.joined(separator: "\n")
    }

    /// Extracts the `Message-ID:` header's value from a raw RFC 822 body, the same
    /// text `writeEMLX` writes to disk - never a separate authored field, or the two
    /// could silently disagree.
    private static func messageIDHeader(in emlxBody: String) -> String? {
        // `.split(separator: "\n")` (a Character) never matches here: Swift composes a
        // literal `\r\n` into one extended grapheme cluster, so a Character equal to a
        // bare `"\n"` does not occur in this text at all, and the "split" is the whole
        // body as a single element. `components(separatedBy:)` searches for the
        // substring `"\n"` instead, which does find it inside the cluster.
        for line in emlxBody.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { break }
            guard let colon = trimmedLine.firstIndex(of: ":") else { continue }
            let name = trimmedLine[trimmedLine.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            guard name.caseInsensitiveCompare("Message-ID") == .orderedSame else { continue }
            return trimmedLine[trimmedLine.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// A stand-in for Mail's own opaque `messages.message_id` hash (PROBE 1, C9:
    /// probed as `INTEGER` on this Mac, 2026-09-09) - never a real value, just
    /// something stable and distinguishable per fixture row.
    private static func indexMessageIDHash(for rowID: Int) -> Int {
        rowID * 104_729
    }

    private static func rowID(
        for key: String, in table: inout [String: Int], insert: (Int) -> Void
    ) -> Int {
        if let existing = table[key] { return existing }
        let nextRowID = table.count + 1
        table[key] = nextRowID
        insert(nextRowID)
        return nextRowID
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "'", with: "''")
    }

    /// Column-for-column with PROBE 1's `PRAGMA table_info` output (this dispatch's
    /// report). Columns this feature never reads keep their real `NOT NULL DEFAULT`
    /// shape only where SQLite would otherwise reject the `INSERT` above.
    private static let schemaSQL = """
    CREATE TABLE messages (
        ROWID INTEGER PRIMARY KEY,
        message_id INTEGER NOT NULL,
        global_message_id INTEGER NOT NULL,
        remote_id INTEGER,
        document_id TEXT,
        sender INTEGER,
        subject_prefix TEXT,
        subject INTEGER NOT NULL,
        summary INTEGER,
        date_sent INTEGER,
        date_received INTEGER,
        mailbox INTEGER NOT NULL,
        remote_mailbox INTEGER,
        flags INTEGER NOT NULL DEFAULT 0,
        read INTEGER NOT NULL DEFAULT 0,
        flagged INTEGER NOT NULL DEFAULT 0,
        deleted INTEGER NOT NULL DEFAULT 0,
        size INTEGER NOT NULL DEFAULT 0,
        conversation_id INTEGER NOT NULL DEFAULT 0,
        is_urgent INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE addresses (
        ROWID INTEGER PRIMARY KEY,
        address TEXT NOT NULL,
        comment TEXT NOT NULL
    );
    CREATE TABLE subjects (
        ROWID INTEGER PRIMARY KEY,
        subject TEXT NOT NULL
    );
    CREATE TABLE recipients (
        ROWID INTEGER PRIMARY KEY,
        message INTEGER NOT NULL,
        address INTEGER NOT NULL,
        type INTEGER,
        position INTEGER
    );
    CREATE TABLE attachments (
        ROWID INTEGER PRIMARY KEY,
        message INTEGER NOT NULL,
        attachment_id TEXT,
        name TEXT
    );
    CREATE TABLE mailboxes (
        ROWID INTEGER PRIMARY KEY,
        url TEXT NOT NULL,
        total_count INTEGER NOT NULL DEFAULT 0,
        unread_count INTEGER NOT NULL DEFAULT 0,
        deleted_count INTEGER NOT NULL DEFAULT 0,
        unseen_count INTEGER NOT NULL DEFAULT 0,
        unread_count_adjusted_for_duplicates INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE message_global_data (
        ROWID INTEGER PRIMARY KEY,
        message_id INTEGER NOT NULL,
        message_id_header TEXT
    );
    """

    // MARK: - Running sqlite3

    private static func runSQLite3(script: String, databasePath: URL) throws {
        let sqlite3Path = "/usr/bin/sqlite3"
        guard FileManager.default.fileExists(atPath: sqlite3Path) else {
            throw FixtureError.sqlite3NotFound(path: sqlite3Path)
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mailstore-fixture-\(UUID().uuidString).sql", directoryHint: .notDirectory)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlite3Path)
        process.arguments = [databasePath.path(percentEncoded: false), ".read \(scriptURL.path(percentEncoded: false))"]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            throw FixtureError.scriptFailed(
                exitCode: process.terminationStatus,
                stderr: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}
