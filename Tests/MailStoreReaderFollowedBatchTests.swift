import Foundation
import SQLite3
import Testing
@testable import Pergamenum

// ADR-0072 §D8, plan gate G4 (2026-09-29) - R-11, the "followed conversations" half.
//
// `MailStorePreparation.resolveFollowedConversations` reads every conversation a pratica follows
// through `MailStoreReader.messages(inConversations:)`. The statement count must not depend on
// how many conversations are followed (one pair per batch), and each conversation's messages and
// recipients must equal what `messages(inConversation:)` answers for it alone.

private final class FollowedStatementCounter {
    var count = 0
}

private func countingFollowedStatements<Result>(
    on connection: MailStoreConnection, _ body: () -> Result
) -> (result: Result, statements: Int) {
    let counter = FollowedStatementCounter()
    let context = Unmanaged.passUnretained(counter).toOpaque()
    sqlite3_trace_v2(connection.handle, UInt32(SQLITE_TRACE_STMT), { _, context, _, _ in
        guard let context else { return 0 }
        Unmanaged<FollowedStatementCounter>.fromOpaque(context).takeUnretainedValue().count += 1
        return 0
    }, context)
    let result = withExtendedLifetime(counter) { body() }
    sqlite3_trace_v2(connection.handle, 0, nil, nil)
    return (result, counter.count)
}

/// `n` conversations of one message each, two recipients apiece.
private func followedStore(conversations n: Int) throws -> MailStoreFixture.Built {
    let messages = (0..<n).map { index in
        MailOrderFixture.message(
            100 + index, conversation: 1000 + index, at: TimeInterval(10 * index),
            from: MailOrderFixture.counterpart, to: ["uno@x.it", "due@x.it"]
        )
    }
    return try MailStoreFixture.build(mailboxes: [MailOrderFixture.inbox], messages: messages)
}

@Suite struct MailStoreReaderFollowedBatchTests {
    @Test(arguments: [(0, 0), (1, 2), (2, 2), (3, 4), (5, 6), (6, 6)])
    func followedConversationsCostTwoStatementsPerBatch(_ followed: Int, _ expected: Int) throws {
        let fixture = try followedStore(conversations: 6)
        let connection = try MailStoreConnection.open(at: fixture.indexURL, readOnly: true)
        let reader = MailStoreReader(connection: connection, batchSize: 2)
        let ids = (0..<followed).map { 1000 + $0 }

        let counted = countingFollowedStatements(on: connection) { reader.messages(inConversations: ids) }

        #expect(counted.result.count == followed)
        #expect(counted.statements == expected)
    }

    @Test(arguments: [1, 2, 4, 100])
    func eachConversationEqualsItsOwnRead(_ batchSize: Int) throws {
        let fixture = try MailOrderFixture.build()
        let batched = try MailStoreReader(storeURL: fixture.indexURL, batchSize: batchSize)
        let single = try MailStoreReader(storeURL: fixture.indexURL)
        // 999 has no message at all; 100 is asked twice.
        let ids = [400, 100, 999, 300, 200, 100]

        let byConversation = batched.messages(inConversations: ids)

        #expect(Set(byConversation.keys) == [100, 200, 300, 400])
        for id in [100, 200, 300, 400] {
            #expect(byConversation[id] == single.messages(inConversation: id), "conversation \(id)")
        }
        #expect(byConversation[999] == nil, "a conversation with no message has no key")
        // The tied `date_sent` in 100 comes back in ROWID order, recipients in row order.
        #expect(byConversation[100]?.map(\.rowID) == [11, 12, 13])
        // The deleted message of 200 stays out.
        #expect(byConversation[200]?.map(\.rowID) == [21])
    }

    @Test func noConversationsRunNoStatement() throws {
        let fixture = try MailOrderFixture.build()
        let connection = try MailStoreConnection.open(at: fixture.indexURL, readOnly: true)
        let reader = MailStoreReader(connection: connection, batchSize: 2)

        let counted = countingFollowedStatements(on: connection) { reader.messages(inConversations: []) }

        #expect(counted.result.isEmpty)
        #expect(counted.statements == 0)
    }
}
