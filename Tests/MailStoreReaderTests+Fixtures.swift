import Foundation
import Testing
@testable import Pergamenum

// Fixtures and helpers for `MailStoreReaderTests.swift`, split out under PG-174 (#321) to
// clear its file_length and type_body_length warnings. Members are `internal` rather than
// `private` because the tests that read them stay in the main file; this file holds no
// tests of its own.

extension MailStoreReaderTests {
    // MARK: - Fixtures shared across tests

    static let inboxMailbox = MailStoreFixture.Mailbox(rowID: 1, url: "ews://account/INBOX")

    static let sharedConversationID = 112_409

    static let firstMessage = MailStoreFixture.Message(
        rowID: 1,
        subject: "Richiesta offerta staffe antivibranti",
        senderAddress: "m.rossi@rossi-spa.it",
        mailboxRowID: 1,
        conversationID: sharedConversationID,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_000_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_000_030)
    )

    static let secondMessageSameConversation = MailStoreFixture.Message(
        rowID: 2,
        subject: "Re: Richiesta offerta staffe antivibranti",
        senderAddress: "stefano@stefer.it",
        mailboxRowID: 1,
        conversationID: sharedConversationID,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_010_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_010_030)
    )

    static let thirdMessageOtherConversation = MailStoreFixture.Message(
        rowID: 3,
        subject: "Altra pratica",
        senderAddress: "altro@esempio.it",
        mailboxRowID: 1,
        conversationID: 999_999,
        dateSent: Date(timeIntervalSinceReferenceDate: 800_000_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 800_000_030)
    )

    static let messageWithAttachments = MailStoreFixture.Message(
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

    static let recipientsConversationID = 424_242

    static let messageWithRecipients = MailStoreFixture.Message(
        rowID: 5,
        subject: "Preventivo con destinatari",
        senderAddress: "m.rossi@rossi-spa.it",
        mailboxRowID: 1,
        conversationID: recipientsConversationID,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_030_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_030_030),
        recipients: ["A.Bianchi@ROSSI-SPA.IT", "carla@rossi-spa.it"]
    )

    static let messageWithNoRecipients = MailStoreFixture.Message(
        rowID: 6,
        subject: "Senza destinatari",
        senderAddress: "m.rossi@rossi-spa.it",
        mailboxRowID: 1,
        conversationID: recipientsConversationID,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_030_100),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_030_130)
    )

    static func freshStateDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mailstore-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Moves the fixture's `Envelope Index` modification date forward and appends a
    /// second message to the same database - a stand-in for "Mail wrote since the
    /// last publish".
    static func touchAndAppendMessage(fixture: MailStoreFixture.Built) throws {
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
}
