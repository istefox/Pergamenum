import Foundation
import Testing
@testable import Pergamenum

// ADR-0072 §D8, plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 1 - R-11.
// This is plan gate G3.
//
// The order `MailStoreReader` returns today, pinned before Task 5 batches its reads and writes the
// order out (`ORDER BY m.date_sent, m.ROWID`, recipients `ORDER BY r.ROWID`): two messages with an
// equal `date_sent` whose ROWIDs are inserted out of array order come back in ROWID order, and a
// message's recipients come back in the order their rows were inserted. If this is red on the
// baseline, the explicit order would change behaviour and Task 5 stops.

/// Four conversations with one counterpart, one conversation without it, a tie on `date_sent`,
/// a deleted message, and messages carrying two or three recipients. Internal so the batch tests
/// of Task 5 read the same store.
enum MailOrderFixture {
    static let counterpart = "cliente@rossi-spa.it"
    static let inbox = MailStoreFixture.Mailbox(rowID: 1, url: "ews://account/INBOX")
    static let start = Date(timeIntervalSince1970: 1_780_000_000)
    static let window = start...start.addingTimeInterval(10_000)

    static func message(
        _ rowID: Int, conversation: Int, at seconds: TimeInterval, from sender: String,
        to recipients: [String] = [], deleted: Bool = false
    ) -> MailStoreFixture.Message {
        MailStoreFixture.Message(
            rowID: rowID, subject: "Conversazione \(conversation)", senderAddress: sender,
            mailboxRowID: inbox.rowID, conversationID: conversation,
            dateSent: start.addingTimeInterval(seconds), dateReceived: start.addingTimeInterval(seconds + 30),
            deleted: deleted, recipients: recipients
        )
    }

    /// Array order is insertion order: 12 is inserted before 11, with the same `date_sent`.
    static let messages: [MailStoreFixture.Message] = [
        message(12, conversation: 100, at: 100, from: counterpart, to: ["B@x.it", "a@x.it", "c@x.it"]),
        message(11, conversation: 100, at: 100, from: "stefano@stefer.it", to: [counterpart, "z@x.it"]),
        message(13, conversation: 100, at: 300, from: counterpart),
        message(21, conversation: 200, at: 200, from: "altro@x.it", to: ["y@x.it", counterpart]),
        message(22, conversation: 200, at: 500, from: counterpart, deleted: true),
        message(31, conversation: 300, at: 400, from: counterpart),
        message(32, conversation: 300, at: 50, from: "e@x.it", to: ["g@x.it", "f@x.it"]),
        message(41, conversation: 400, at: 600, from: counterpart),
        message(51, conversation: 500, at: 700, from: "nessuno@x.it", to: ["altro@x.it"]),
    ]

    /// Conversation ids, newest first, then each conversation's ROWIDs and each message's
    /// recipients, exactly as the baseline reader answered.
    static let expectedConversations = [400, 300, 100, 200]
    static let expectedRowIDs: [[Int]] = [[41], [32, 31], [11, 12, 13], [21]]
    static let expectedRecipients: [[[String]]] = [
        [[]],
        [["g@x.it", "f@x.it"], []],
        [[counterpart, "z@x.it"], ["b@x.it", "a@x.it", "c@x.it"], []],
        [["y@x.it", counterpart]],
    ]

    static func build() throws -> MailStoreFixture.Built {
        try MailStoreFixture.build(mailboxes: [inbox], messages: messages)
    }
}

@Suite struct MailStoreReaderOrderPinTests {
    @Test func aCounterpartReadComesBackInTheBaselineOrder() throws {
        let fixture = try MailOrderFixture.build()
        let reader = try MailStoreReader(storeURL: fixture.indexURL)

        let conversations = reader.conversations(
            counterpart: MailOrderFixture.counterpart, within: MailOrderFixture.window
        )

        #expect(conversations.map(\.conversationID) == MailOrderFixture.expectedConversations)
        #expect(conversations.map { $0.messages.map(\.rowID) } == MailOrderFixture.expectedRowIDs)
        #expect(conversations.map { $0.messages.map(\.recipients) } == MailOrderFixture.expectedRecipients)
        #expect(conversations.allSatisfy { $0.messages.allSatisfy { !$0.deleted } })
    }

    @Test func aConversationReadComesBackInTheBaselineOrder() throws {
        let fixture = try MailOrderFixture.build()
        let reader = try MailStoreReader(storeURL: fixture.indexURL)

        for (index, conversation) in MailOrderFixture.expectedConversations.enumerated() {
            let messages = reader.messages(inConversation: conversation)
            #expect(messages.map(\.rowID) == MailOrderFixture.expectedRowIDs[index])
            #expect(messages.map(\.recipients) == MailOrderFixture.expectedRecipients[index])
        }
        #expect(reader.messages(inConversation: 500).map(\.rowID) == [51])
        #expect(reader.messages(inConversation: 123).isEmpty)
    }

    @Test func aSingleRowCarriesItsRecipientsInRowOrder() throws {
        let fixture = try MailOrderFixture.build()
        let reader = try MailStoreReader(storeURL: fixture.indexURL)

        #expect(reader.row(rowID: 12)?.recipients == ["b@x.it", "a@x.it", "c@x.it"])
        #expect(reader.row(rowID: 11)?.recipients == [MailOrderFixture.counterpart, "z@x.it"])
        #expect(reader.row(rowID: 13)?.recipients == [])
        // `row(rowID:)` does not filter deleted rows, today or after.
        #expect(reader.row(rowID: 22)?.deleted == true)
        #expect(reader.row(rowID: 999) == nil)
    }
}
