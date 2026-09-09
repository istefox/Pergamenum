import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02,
// R-03, R-19.
//
// Every declaration under test here (`MailStoreLocation`, `MailStoreCopy`,
// `MailStoreConnection`, `MailStoreReader`, the value types) is a tester-declared
// boundary (ADR-0155): the coder fills the bodies. `MailStoreConnection.open` always
// throws today, which is what keeps every `MailStoreReader` query red rather than
// crashing the process on a `fatalError` - construction fails before any query body
// ever runs. `MailStoreFixture` (`Tests/MailStoreFixture.swift`) builds every fixture;
// no test here touches `~/Library/Mail`.

@Suite(.serialized) struct MailStoreReaderTests {
    // MARK: - R-19: MailStoreLocation

    @Test func resolveNeverPointsAtTheRealMailLibraryUnderTest() {
        // Real behaviour (ADR §D7): under xctest, with no override, `resolve()`
        // returns a per-process temporary fixture root - never
        // `~/Library/Mail/V10`. The stub returns a fixed placeholder outside the
        // temporary directory, so this fails until the coder implements §D7.
        let resolved = MailStoreLocation.resolve()
        let temporaryDirectory = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        #expect(resolved.path(percentEncoded: false).hasPrefix(temporaryDirectory))
    }

    @Test func resolveIsStablePerProcessNotPerCall() {
        // Real behaviour (ADR §D7, mirroring `VaultState.testProcessBase`): the same
        // per-process fixture root is returned on every call within one process, or
        // a session that calls `resolve()` twice loses state written by the first
        // call. This is expected to already hold for the current constant stub -
        // kept as a guard against a future implementation that resolves a *new*
        // temporary directory per call.
        #expect(MailStoreLocation.resolve() == MailStoreLocation.resolve())
    }

    @Test func resolveHonoursTheMailStoreRootOverride() {
        // R-19: `-mailStoreRoot <path>` must redirect the reader to a fixture store.
        // `MailStoreLocation.resolve()` reads `UserDefaults.standard` directly
        // (mirroring `VaultState.processDefaultBase()`'s own `-stateBase` read), and
        // a custom `UserDefaults(suiteName:)` is not in `.standard`'s search list -
        // `resolve()` would never see a key set anywhere else. Writing to `.standard`
        // is therefore required, not a shortcut; the suite is `.serialized` (Swift
        // Testing runs tests in parallel by default) so this write cannot race the
        // two sibling `resolve()` tests above, and the key is removed in `defer` so
        // it cannot leak into either of them on a later run.
        let overridePath = "/tmp/pergamenum-mailstore-reader-tests-override"
        UserDefaults.standard.set(overridePath, forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        // `resolve()` builds its result as `URL(filePath:directoryHint: .isDirectory)`
        // (see its own implementation), which appends a trailing slash to the path -
        // comparing the raw string against `overridePath` would fail on that slash
        // alone, so the expectation is built the identical way rather than loosened
        // to a prefix check.
        let resolved = MailStoreLocation.resolve()
        let expected = URL(filePath: overridePath, directoryHint: .isDirectory)
        #expect(resolved == expected)
    }

    // MARK: - R-02: MailStoreCopy

    @Test func publishCopiesOnTheFirstCallAndProducesAReadableIndex() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.firstMessage]
        )
        let stateDirectory = try Self.freshStateDirectory()

        let result = MailStoreCopy.publish(from: fixture.root, into: stateDirectory)

        guard case let .published(publishedURL) = result else {
            Issue.record("expected .published, got \(result)")
            return
        }
        // Real behaviour (ADR §D2): the published generation actually holds a copy
        // of `Envelope Index`. The stub answers `.published` at a placeholder URL
        // with no file ever written, so this fails until the coder implements the
        // staging/copy/rename sequence.
        let copiedIndex = publishedURL.appending(path: "Envelope Index", directoryHint: .notDirectory)
        #expect(FileManager.default.fileExists(atPath: copiedIndex.path(percentEncoded: false)))
    }

    @Test func publishSkipsWhenSourceModificationDateIsUnchanged() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.firstMessage]
        )
        let stateDirectory = try Self.freshStateDirectory()

        let first = MailStoreCopy.publish(from: fixture.root, into: stateDirectory)
        guard case let .published(firstURL) = first else {
            Issue.record("expected the first call to publish, got \(first)")
            return
        }

        // R-02: "skipping the copy when the source mtime is unchanged". The stub
        // always answers `.published`, never `.unchanged`, so this fails until the
        // coder compares the source's modification date against the published
        // generation's own stamp (ADR §D2).
        let second = MailStoreCopy.publish(from: fixture.root, into: stateDirectory)
        #expect(second == .unchanged(firstURL))
    }

    @Test func publishRepublishesWhenSourceChanges() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.firstMessage]
        )
        let stateDirectory = try Self.freshStateDirectory()

        let first = MailStoreCopy.publish(from: fixture.root, into: stateDirectory)
        guard case let .published(firstURL) = first else {
            Issue.record("expected the first call to publish, got \(first)")
            return
        }

        // Touch the source to move its modification date forward, then add a
        // message - simulating Mail having written to its own index since the last
        // publish.
        try Self.touchAndAppendMessage(fixture: fixture)

        let second = MailStoreCopy.publish(from: fixture.root, into: stateDirectory)
        // Real behaviour: a changed source republishes into a *new* generation,
        // distinct from the first (ADR §D2: one directory per generation, oldest
        // ones deleted afterwards). The stub answers the exact same fixed
        // placeholder every time for the same `stateDirectory`, so this fails until
        // the coder compares modification dates and mints a fresh generation.
        guard case let .published(secondURL) = second else {
            Issue.record("expected .published again after the source changed, got \(second)")
            return
        }
        #expect(secondURL != firstURL)
    }

    @Test func publishReportsMailIsWritingOnATornCopyAfterOneRetry() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.firstMessage]
        )
        // Simulate "Mail wrote mid-copy" (ADR §D2 step 3) by truncating the source
        // index to a size no valid SQLite file can have.
        let truncated = Data([0x53, 0x51, 0x4C]) // "SQL", short of the real header
        try truncated.write(to: fixture.indexURL)
        let stateDirectory = try Self.freshStateDirectory()

        // R-02 / ADR §D2 step 3: a torn copy is retried once, then reported as
        // `.mailIsWriting`, never surfaced as a half-populated reader. The stub
        // always answers `.published`, so this fails until the coder implements
        // `PRAGMA quick_check` + the one retry.
        let result = MailStoreCopy.publish(from: fixture.root, into: stateDirectory)
        #expect(result == .mailIsWriting)
    }

    @Test func publishReportsStoreMissingRatherThanAnEmptyDatabase() throws {
        let emptySource = try Self.freshStateDirectory()
        let stateDirectory = try Self.freshStateDirectory()

        // R-02 / ADR §D1: `SQLITE_OPEN_CREATE` is never passed, so a source with no
        // `Envelope Index` must answer `.storeMissing`, never mint an empty,
        // permanently-"nessun messaggio" database. The stub always answers
        // `.published`, so this fails until the coder checks for the source file
        // before ever opening anything.
        let result = MailStoreCopy.publish(from: emptySource, into: stateDirectory)
        #expect(result == .storeMissing)
    }

    // MARK: - R-03: the five MailStoreReader queries

    @Test func messagesInConversationReturnsTheFixturesKnownRows() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.firstMessage, Self.secondMessageSameConversation, Self.thirdMessageOtherConversation]
        )

        // R-03: "messages by conversation id". `init(storeURL:)` throws until the
        // coder implements `MailStoreConnection.open`, so this is red at
        // construction - the query body itself is dead code until then.
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let messages = reader.messages(inConversation: Self.sharedConversationID)
        #expect(Set(messages.map(\.rowID)) == [Self.firstMessage.rowID, Self.secondMessageSameConversation.rowID])
    }

    @Test func conversationsByCounterpartWithinWindowReturnsTheFixturesKnownRows() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.firstMessage, Self.secondMessageSameConversation, Self.thirdMessageOtherConversation]
        )
        let window = Self.firstMessage.dateSent.addingTimeInterval(-86_400)
            ... Self.secondMessageSameConversation.dateSent.addingTimeInterval(86_400)

        // R-03: "conversations by counterpart address within a date window".
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let conversations = reader.conversations(counterpart: Self.firstMessage.senderAddress, within: window)
        #expect(conversations.map(\.conversationID) == [Self.sharedConversationID])
    }

    @Test func rowByMessageIDRoutesThroughTheReaderNotTheIndex() throws {
        let fixture = try MailStoreFixture.build(mailboxes: [Self.inboxMailbox], messages: [Self.firstMessage])

        // R-03 / ADR §D3: given PROBE 1's answer (C9: `message_id` is an opaque
        // `INTEGER` hash), the honest result is always `.notResolvableFromIndex` -
        // the real `Message-ID` lookup is the ledger's job (Task 3). This is still
        // red today because construction itself throws.
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let lookup = reader.row(forMessageID: "<abc@rossi-spa.it>")
        #expect(lookup == .notResolvableFromIndex)
    }

    @Test func attachmentsForMessageReturnsTheFixturesKnownNames() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.messageWithAttachments]
        )

        // R-03: "attachment names per message".
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let attachments = reader.attachments(forMessage: Self.messageWithAttachments.rowID)
        #expect(Set(attachments.compactMap(\.name)) == ["offerta.pdf", "disegno.dwg"])
    }

    @Test func emlxPathForRowMatchesWhatPROBE2WillMeasure() throws {
        let fixture = try MailStoreFixture.build(mailboxes: [Self.inboxMailbox], messages: [Self.firstMessage])

        // R-03: "the .emlx path for a row (mailbox url + ROWID)". PROBE 2's measured
        // rule (`MailStoreReader.emlxPath(forRow:)`'s own doc comment):
        // `<root>/<account = url host>/<url path component>.mbox/Data/<fan>/Messages/<ROWID>.emlx`,
        // with no store-uuid level when the fixture writes none - the reader's own
        // fallback for that case. `Self.inboxMailbox.url` is `ews://account/INBOX`
        // and ROWID 1's fan-out is empty (below 1000), so the fixture's mailbox
        // directory is `account/INBOX.mbox`, not the old percent-underscore guess.
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let mailboxRow = MailboxRef(rowID: Self.inboxMailbox.rowID, url: Self.inboxMailbox.url)
        let row = MailMessageRow(
            rowID: Self.firstMessage.rowID,
            indexMessageIDHash: nil,
            globalMessageID: nil,
            subject: Self.firstMessage.subject,
            sender: Self.firstMessage.senderAddress,
            dateSent: Self.firstMessage.dateSent,
            dateReceived: Self.firstMessage.dateReceived,
            mailbox: mailboxRow,
            conversationID: Self.firstMessage.conversationID,
            deleted: false,
            messageID: nil
        )
        let expectedURL = fixture.root
            .appending(path: "account", directoryHint: .isDirectory)
            .appending(path: "INBOX.mbox", directoryHint: .isDirectory)
            .appending(path: "Data/Messages", directoryHint: .isDirectory)
            .appending(path: "\(Self.firstMessage.rowID).emlx", directoryHint: .notDirectory)

        let emlxURL = reader.emlxPath(forRow: row)
        #expect(emlxURL == expectedURL)
    }

    // MARK: - The one-file rule (ADR §D1)

    @Test func onlyMailStoreConnectionMentionsSQLite3Symbols() throws {
        let emailDirectory = try Self.repoRoot().appending(path: "Sources/Core/Email", directoryHint: .isDirectory)
        var offending: [String] = []

        let contents = try FileManager.default.contentsOfDirectory(
            at: emailDirectory, includingPropertiesForKeys: nil
        )
        let connectionFileName = "MailStoreConnection.swift"
        for fileURL in contents where fileURL.pathExtension == "swift" && fileURL.lastPathComponent != connectionFileName {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            if text.contains("sqlite3_") {
                offending.append(fileURL.lastPathComponent)
            }
        }

        #expect(offending.isEmpty, "sqlite3_ found outside MailStoreConnection.swift: \(offending)")
    }

    // MARK: - Fixtures shared across tests

    private static let inboxMailbox = MailStoreFixture.Mailbox(rowID: 1, url: "ews://account/INBOX")

    private static let sharedConversationID = 112_409

    private static let firstMessage = MailStoreFixture.Message(
        rowID: 1,
        subject: "Richiesta offerta staffe antivibranti",
        senderAddress: "m.rossi@rossi-spa.it",
        mailboxRowID: 1,
        conversationID: sharedConversationID,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_000_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_000_030)
    )

    private static let secondMessageSameConversation = MailStoreFixture.Message(
        rowID: 2,
        subject: "Re: Richiesta offerta staffe antivibranti",
        senderAddress: "stefano@stefer.it",
        mailboxRowID: 1,
        conversationID: sharedConversationID,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_010_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_010_030)
    )

    private static let thirdMessageOtherConversation = MailStoreFixture.Message(
        rowID: 3,
        subject: "Altra pratica",
        senderAddress: "altro@esempio.it",
        mailboxRowID: 1,
        conversationID: 999_999,
        dateSent: Date(timeIntervalSinceReferenceDate: 800_000_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 800_000_030)
    )

    private static let messageWithAttachments = MailStoreFixture.Message(
        rowID: 4,
        subject: "Disegni allegati",
        senderAddress: "m.rossi@rossi-spa.it",
        mailboxRowID: 1,
        conversationID: 555_555,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_020_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_020_030),
        attachments: [
            MailStoreFixture.Attachment(attachmentID: "att-1", name: "offerta.pdf"),
            MailStoreFixture.Attachment(attachmentID: "att-2", name: "disegno.dwg"),
        ]
    )

    private static func freshStateDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mailstore-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Moves the fixture's `Envelope Index` modification date forward and appends a
    /// second message to the same database - a stand-in for "Mail wrote since the
    /// last publish".
    private static func touchAndAppendMessage(fixture: MailStoreFixture.Built) throws {
        _ = try MailStoreFixture.build(
            mailboxes: fixture.mailboxes,
            messages: [Self.firstMessage, Self.secondMessageSameConversation],
            in: fixture.root
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: fixture.indexURL.path(percentEncoded: false)
        )
    }

    /// Same resolution `Tests/SharedSourcesPurityTests.swift` uses.
    private static func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MailStoreReaderTests.swift -> Tests/
            .deletingLastPathComponent() // Tests/ -> repository root
    }
}
