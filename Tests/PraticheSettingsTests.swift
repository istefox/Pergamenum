import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 9 - R-35,
// R-36.
//
// `PraticheSettings` round-trip and clamping are kept here as a completeness check, so a
// regression in the Settings tab is caught by the file that owns its coverage.

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

        let reader = try MailStoreReader(storeURL: fixture.indexURL)
        let addresses = reader.sentSenderAddresses()
        #expect(Set(addresses) == ["stefano@stefer.it"])
    }

    @Test func sentSenderAddressesRecognisesTheItalianPostaInviataSpelling() throws {
        // The message must live in the «Posta Inviata» mailbox (ROWID 3) for the
        // messages → mailboxes join to find it; the shared `firstSentMessage` fixture
        // files itself under ROWID 1, which this store does not contain.
        var message = Self.firstSentMessage
        message.mailboxRowID = Self.postaInviataMailbox.rowID
        let fixture = try MailStoreFixture.build(
            mailboxes: [Self.postaInviataMailbox],
            messages: [message]
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
