import Foundation
import Testing
@testable import Pergamenum

// PG-172 / #312 follow-up, READ side: ADR-0052's door covers every ledger WRITER, but
// `PraticaLiveSync.runExclusive` and `prepareRegeneration` read `controller.ledger` for
// `state.entries` (the §D3 bridge that lets `MailStorePreparation.prepare` recover a
// conversation Mail renumbered) and `importedMessageIDs` without going through it. A live sync
// fires from a window-key or FSEvents trigger without the Pratiche pane having called
// `load(from:)`, so on a never-loaded controller those reads see `.empty`.

private func dossierNoteText(conversations: [Int]) -> String {
    let conversationsList = conversations.map(String.init).joined(separator: ", ")
    return """
    ---
    date: 2026-09-01
    tags:
      - type-note
      - topic-pratica
      - client-rossi
      - status-active
      - source-email
    pergamenum-dossier: 1
    pergamenum-dossier-counterparts:
      - m.rossi@rossi-spa.it
    pergamenum-dossier-conversations: [\(conversationsList)]
    ---

    Appunti pratica.
    """
}

@MainActor
@Suite(.serialized) struct PraticaLiveSyncUnloadedLedgerReadTests {
    private static let folder = PraticaSyncFixtures.praticaFolder

    /// Mail renumbered the conversation (112_409 to 550_001). Only the ledger's bridge entry
    /// can tell the sync that the old id and the new one are the same conversation, so a
    /// controller that has not read the ledger cannot follow the renumbering.
    @Test func aSyncOnANeverLoadedControllerStillFollowsAConversationMailRenumbered() async throws {
        try await followsRenumbering(loadingFirst: false)
    }

    /// Control: the same scenario once the pane has loaded the ledger, so the test above fails
    /// for the read gap and not for its own setup.
    @Test func aSyncOnALoadedControllerFollowsAConversationMailRenumbered() async throws {
        try await followsRenumbering(loadingFirst: true)
    }

    private func followsRenumbering(loadingFirst: Bool) async throws {
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.folder)/pratica.md")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 550_001, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        var seeded = PraticaLedger.PraticaState.empty
        seeded.entries = [PraticaLedger.Entry(messageID: "<abc123@rossi-spa.it>", rowID: 1, conversationID: 112_409)]
        var onDisk = PraticaLedger.empty
        onDisk.byPraticaPath[Self.folder] = seeded
        try onDisk.save(to: PraticheController.ledgerURL(for: session))

        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        if loadingFirst {
            pratiche.load(from: vaultController)
        } else {
            // Nothing calls `load(from:)`: the pane was never opened.
            #expect(pratiche.ledger == .empty, "precondition: the controller has not read the ledger")
        }
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        _ = await sync.runExclusive(praticaPath: Self.folder)

        let root = try #require(vaultController.root)
        let dossier = try #require(PraticheController.dossier(at: Self.folder, vaultRoot: root))
        #expect(
            dossier.conversations == [550_001],
            "the sync must read the ledger's bridge from disk and follow Mail's renumbering"
        )

        vaultController.close()
    }
}
