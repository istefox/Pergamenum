import Foundation
import SQLite3
import Testing
@testable import Pergamenum

// ADR-0072 §D8, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 5 - R-11, R-12.
//
// Reading a counterpart used to cost one statement for the ids plus two per conversation (its
// rows, then its recipients). Batched, it costs one plus two per batch, whatever the number of
// conversations inside a batch: counted at the connection, with `SQLITE_TRACE_STMT` (the fixture
// has no triggers, so one event is one statement). The order stays Task 1's pinned order across
// a batch boundary, and a deleted message stays out. A mailbox's store directory is listed once
// per reader once found (R-12), and a mailbox where none was found is listed again (plan G2).

private final class StatementCounter {
    var count = 0
}

/// Runs `body` with a statement trace on the connection, and answers how many statements ran.
private func countingStatements<Result>(
    on connection: MailStoreConnection, _ body: () -> Result
) -> (result: Result, statements: Int) {
    let counter = StatementCounter()
    let context = Unmanaged.passUnretained(counter).toOpaque()
    sqlite3_trace_v2(connection.handle, UInt32(SQLITE_TRACE_STMT), { _, context, _, _ in
        guard let context else { return 0 }
        Unmanaged<StatementCounter>.fromOpaque(context).takeUnretainedValue().count += 1
        return 0
    }, context)
    let result = withExtendedLifetime(counter) { body() }
    sqlite3_trace_v2(connection.handle, 0, nil, nil)
    return (result, counter.count)
}

/// `n` conversations with the counterpart, one message each carrying two recipients, and one
/// conversation without it.
private func counterpartStore(conversations n: Int) throws -> MailStoreFixture.Built {
    var messages = (0..<n).map { index in
        MailOrderFixture.message(
            100 + index, conversation: 1000 + index, at: TimeInterval(10 * index),
            from: MailOrderFixture.counterpart, to: ["uno@x.it", "due@x.it"]
        )
    }
    messages.append(MailOrderFixture.message(900, conversation: 9000, at: 5, from: "altro@x.it", to: ["terzo@x.it"]))
    return try MailStoreFixture.build(mailboxes: [MailOrderFixture.inbox], messages: messages)
}

@Suite struct MailStoreReaderBatchTests {
    @Test(arguments: [(0, 1), (1, 3), (3, 5), (4, 5), (5, 7)])
    func aCounterpartCostsOneStatementPlusTwoPerBatch(_ conversations: Int, _ expected: Int) throws {
        let fixture = try counterpartStore(conversations: conversations)
        let connection = try MailStoreConnection.open(at: fixture.indexURL, readOnly: true)
        let reader = MailStoreReader(connection: connection, batchSize: 2)

        let counted = countingStatements(on: connection) {
            reader.conversations(counterpart: MailOrderFixture.counterpart, within: MailOrderFixture.window)
        }

        #expect(counted.result.count == conversations)
        #expect(counted.result.allSatisfy { $0.messages.map(\.recipients) == [["uno@x.it", "due@x.it"]] })
        #expect(counted.statements == expected)
    }

    @Test(arguments: [1, 2, 3])
    func theOrderSurvivesABatchBoundary(_ batchSize: Int) throws {
        let fixture = try MailOrderFixture.build()
        let batched = try MailStoreReader(storeURL: fixture.indexURL, batchSize: batchSize)
        let reference = try MailStoreReader(storeURL: fixture.indexURL)
        let window = MailOrderFixture.window

        let conversations = batched.conversations(counterpart: MailOrderFixture.counterpart, within: window)

        #expect(conversations == reference.conversations(counterpart: MailOrderFixture.counterpart, within: window))
        #expect(conversations.map(\.conversationID) == MailOrderFixture.expectedConversations)
        #expect(conversations.map { $0.messages.map(\.rowID) } == MailOrderFixture.expectedRowIDs)
        #expect(conversations.map { $0.messages.map(\.recipients) } == MailOrderFixture.expectedRecipients)
    }

    @Test func fiveConversationsReadTheSameInBatchesOfTwo() throws {
        let fixture = try counterpartStore(conversations: 5)
        let batched = try MailStoreReader(storeURL: fixture.indexURL, batchSize: 2)
        let reference = try MailStoreReader(storeURL: fixture.indexURL)
        let window = MailOrderFixture.window

        let conversations = batched.conversations(counterpart: MailOrderFixture.counterpart, within: window)

        #expect(conversations.map(\.conversationID) == [1004, 1003, 1002, 1001, 1000])
        #expect(conversations == reference.conversations(counterpart: MailOrderFixture.counterpart, within: window))
    }

    @Test func aDeletedMessageStaysOutOfABatch() throws {
        let fixture = try MailOrderFixture.build()
        let reader = try MailStoreReader(storeURL: fixture.indexURL, batchSize: 2)

        let conversation = reader
            .conversations(counterpart: MailOrderFixture.counterpart, within: MailOrderFixture.window)
            .first { $0.conversationID == 200 }

        #expect(conversation?.messages.map(\.rowID) == [21])
        #expect(reader.messages(inConversation: 200).map(\.rowID) == [21])
    }
}

// MARK: - R-12

private let inbox = MailOrderFixture.inbox
private let sent = MailStoreFixture.Mailbox(rowID: 2, url: "ews://account/Sent")

private func mailboxDirectory(_ root: URL, _ name: String) -> URL {
    root.appending(path: "account", directoryHint: .isDirectory)
        .appending(path: "\(name).mbox", directoryHint: .isDirectory)
}

private func makeStore(_ name: String, in mailbox: URL) throws -> URL {
    let store = mailbox.appending(path: name, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    return store
}

@Suite struct MailStoreReaderStoreDirectoryTests {
    private static let storeA = "11111111-1111-1111-1111-111111111111"
    private static let storeB = "22222222-2222-2222-2222-222222222222"
    private static let storeC = "33333333-3333-3333-3333-333333333333"

    private func build() throws -> MailStoreFixture.Built {
        try MailStoreFixture.build(mailboxes: [inbox, sent], messages: [
            MailOrderFixture.message(1, conversation: 10, at: 0, from: MailOrderFixture.counterpart),
            MailOrderFixture.message(2, conversation: 10, at: 10, from: MailOrderFixture.counterpart),
            MailStoreFixture.Message(
                rowID: 3, subject: "Inviato", senderAddress: "stefano@stefer.it", mailboxRowID: sent.rowID,
                conversationID: 11, dateSent: MailOrderFixture.start, dateReceived: MailOrderFixture.start,
                deleted: false, recipients: [MailOrderFixture.counterpart]
            ),
        ])
    }

    @Test func aFoundStoreDirectoryIsListedOncePerReader() throws {
        let fixture = try build()
        let mailbox = mailboxDirectory(fixture.root, "INBOX")
        let storeA = try makeStore(Self.storeA, in: mailbox)
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let first = try #require(reader.row(rowID: 1))
        let second = try #require(reader.row(rowID: 2))

        let firstPath = try #require(reader.emlxPath(forRow: first)).path(percentEncoded: false)
        let secondPath = try #require(reader.emlxPath(forRow: second)).path(percentEncoded: false)
        #expect(firstPath.hasPrefix(storeA.path(percentEncoded: false)))
        #expect(secondPath.hasPrefix(storeA.path(percentEncoded: false)))

        // A replaced by B on disk: the same reader still answers A, so it did not list again.
        let storeB = mailbox.appending(path: Self.storeB, directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: storeA, to: storeB)
        let again = try #require(reader.emlxPath(forRow: first)).path(percentEncoded: false)
        #expect(again.contains(Self.storeA))
        let fresh = try MailStoreReader(storeURL: fixture.indexURL)
        let freshPath = try #require(fresh.emlxPath(forRow: first)).path(percentEncoded: false)
        #expect(freshPath.contains(Self.storeB))
    }

    @Test func aMailboxWithNoStoreDirectoryIsListedAgain() throws {
        let fixture = try build()
        let mailbox = mailboxDirectory(fixture.root, "Sent")
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let row = try #require(reader.row(rowID: 3))

        let before = try #require(reader.emlxPath(forRow: row)).path(percentEncoded: false)
        let data = mailbox.appending(path: "Data", directoryHint: .isDirectory)
        #expect(before.hasPrefix(data.path(percentEncoded: false)))

        let storeC = try makeStore(Self.storeC, in: mailbox)
        let after = try #require(reader.emlxPath(forRow: row)).path(percentEncoded: false)
        #expect(after.hasPrefix(storeC.path(percentEncoded: false)))
    }
}
