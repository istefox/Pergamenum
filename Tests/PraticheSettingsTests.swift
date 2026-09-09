import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 9 - R-35,
// R-36.
//
// `PraticheSettings` round-trip and clamping (Task 3) are already real - kept here as
// a completeness check, not a red test, so a future regression in Task 9's own
// Settings tab is caught by the same file that owns the tab's coverage. The genuinely
// red half of this file is `MailStoreReader.sentSenderAddresses()`
// (`Sources/Core/Email/MailStoreReader.swift`), a tester-declared boundary (ADR-0155
// §D1): the coder fills the body - always `[]` today, which is wrong-but-compiling,
// never a `fatalError`, so these tests are genuinely red on the query result itself
// (`MailStoreReader.init(storeURL:)` and the rest of the R-03 queries are real as of
// this batch - only the R-35 addition is new and stubbed).

@MainActor
@Suite(.serialized) struct PraticheSettingsRoundTripTests {
    // MARK: - R-35: the eight rows persist, six of them through `VaultSettings.pratiche`

    @Test func praticheSettingsRoundTripThroughSettingsJSON() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)

        session.updateSettings { settings in
            settings.pratiche.rootFolder = "02 Clienti"
            settings.pratiche.ownAddresses = ["stefano@stefer.it", "s.ferri@vibrofer.it"]
            settings.pratiche.keepOriginalEML = false
            settings.pratiche.attachmentThresholdMB = 250
            settings.pratiche.proposalWindowDays = 30
            settings.pratiche.mirrorsToDailyNote = false
        }

        let reread = VaultSession.readSettings(in: vault.root).settings
        #expect(reread.pratiche.rootFolder == "02 Clienti")
        #expect(reread.pratiche.ownAddresses == ["stefano@stefer.it", "s.ferri@vibrofer.it"])
        #expect(reread.pratiche.keepOriginalEML == false)
        #expect(reread.pratiche.attachmentThresholdMB == 250)
        #expect(reread.pratiche.proposalWindowDays == 30)
        #expect(reread.pratiche.mirrorsToDailyNote == false)
    }

    @Test func handEditedZeroNeverMeansNoThresholdOrNoWindow() throws {
        // ADR §D10: a hand-edited `0` must clamp, not silently mean "propose
        // nothing"/"never threshold" - already real (Task 3), asserted here since it
        // is exactly the boundary R-35's Settings row exposes through a `Stepper`.
        let vault = try TemporaryVault()
        try vault.write("""
        {
          "pratiche": {
            "attachmentThresholdMB": 0,
            "proposalWindowDays": 0
          }
        }
        """, to: ".pergamenum/settings.json")

        let settings = VaultSession.readSettings(in: vault.root).settings
        #expect(settings.pratiche.attachmentThresholdMB == PraticheSettings.attachmentThresholdRange.lowerBound)
        #expect(settings.pratiche.proposalWindowDays == PraticheSettings.proposalWindowRange.lowerBound)
    }
}

// MARK: - R-35: own-address pre-fill from Mail's "Sent" mailboxes

@Suite(.serialized) struct MailStoreReaderSentSenderAddressesTests {
    @Test func sentSenderAddressesReturnsOnlyAddressesFromSentMailboxesDeduplicated() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.sentMailbox, Self.inboxMailbox],
            messages: [Self.firstSentMessage, Self.secondSentMessageSameAddress, Self.receivedMessage]
        )

        // Red at construction (`MailStoreConnection.open` always throws, batch 1) and
        // red again on the query even once construction is fixed, since
        // `sentSenderAddresses()` is a tester-declared stub returning `[]`.
        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let addresses = reader.sentSenderAddresses()
        #expect(Set(addresses) == ["stefano@stefer.it"])
    }

    @Test func sentSenderAddressesRecognisesTheItalianPostaInviataSpelling() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.postaInviataMailbox],
            messages: [Self.firstSentMessage]
        )

        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let addresses = reader.sentSenderAddresses()
        #expect(addresses == ["stefano@stefer.it"])
    }

    @Test func sentSenderAddressesIgnoresANonSentMailboxEntirely() throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.inboxMailbox],
            messages: [Self.receivedMessage]
        )

        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        #expect(reader.sentSenderAddresses().isEmpty)
    }

    // MARK: - Fixtures

    private static let sentMailbox = MailStoreFixture.Mailbox(rowID: 1, url: "ews://account/Sent")
    private static let inboxMailbox = MailStoreFixture.Mailbox(rowID: 2, url: "ews://account/INBOX")
    private static let postaInviataMailbox = MailStoreFixture.Mailbox(rowID: 3, url: "ews://account/Posta Inviata")

    private static let firstSentMessage = MailStoreFixture.Message(
        rowID: 1,
        subject: "Offerta OF-2026-118",
        senderAddress: "stefano@stefer.it",
        mailboxRowID: 1,
        conversationID: 1,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_000_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_000_030)
    )

    private static let secondSentMessageSameAddress = MailStoreFixture.Message(
        rowID: 2,
        subject: "Re: Offerta OF-2026-118",
        senderAddress: "stefano@stefer.it",
        mailboxRowID: 1,
        conversationID: 1,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_010_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_010_030)
    )

    private static let receivedMessage = MailStoreFixture.Message(
        rowID: 3,
        subject: "Richiesta offerta",
        senderAddress: "m.rossi@rossi-spa.it",
        mailboxRowID: 2,
        conversationID: 2,
        dateSent: Date(timeIntervalSinceReferenceDate: 700_020_000),
        dateReceived: Date(timeIntervalSinceReferenceDate: 700_020_030)
    )
}
