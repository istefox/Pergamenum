import Foundation
import Testing
@testable import Pergamenum

// Split out of `PraticheControllerTests.swift` under PG-293 (#638) to clear its SwiftLint
// `file_length` warning: a pure move, no test changed.

// MARK: - §D23.2 - the bridge merges into the ledger, newest triple wins

// ADR §D23, plan docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 1.
// `recordSyncOutcome`'s merge of `outcome.bridge` into `state.entries` (§D23.2).
@MainActor
@Suite(.serialized) struct PraticaLedgerBridgeMergeTests {
    @Test func recordSyncOutcomeMergesBridgeEntriesNewestTripleWinsPerMessageID() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"

        let firstOutcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>", "<b@rossi-spa.it>"],
            noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false,
            bridge: [
                PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 1, conversationID: 112_409),
                PraticaLedger.Entry(messageID: "<b@rossi-spa.it>", rowID: 2, conversationID: 112_409),
            ]
        )
        controller.recordSyncOutcome(firstOutcome, for: praticaPath, session: session, isCurrentVault: true)

        let entriesAfterFirstSync = (controller.ledger.byPraticaPath[praticaPath]?.entries ?? [])
            .sorted { $0.messageID < $1.messageID }
        #expect(
            entriesAfterFirstSync == [
                PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 1, conversationID: 112_409),
                PraticaLedger.Entry(messageID: "<b@rossi-spa.it>", rowID: 2, conversationID: 112_409),
            ],
            "the very first sync's own triples must already be recorded"
        )

        // A second sync that re-imports nothing new: what is already recorded must
        // stay exactly as it is.
        let secondOutcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: [],
            noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
        )
        controller.recordSyncOutcome(secondOutcome, for: praticaPath, session: session, isCurrentVault: true)

        let entriesAfterSecondSync = (controller.ledger.byPraticaPath[praticaPath]?.entries ?? [])
            .sorted { $0.messageID < $1.messageID }
        #expect(
            entriesAfterSecondSync == [
                PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 1, conversationID: 112_409),
                PraticaLedger.Entry(messageID: "<b@rossi-spa.it>", rowID: 2, conversationID: 112_409),
            ],
            "a sync that imports nothing new must leave `entries` unchanged"
        )

        // A regeneration of `<a@…>` under a new ROWID replaces THAT message's triple
        // alone (§D23.2's own "newest triple wins"), leaving `<b@…>` untouched.
        let regenerationOutcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: [],
            noLongerInMail: [], regeneratedPendingFiles: ["\(praticaPath)/email/richiesta.md"], cancelled: false,
            bridge: [PraticaLedger.Entry(messageID: "<a@rossi-spa.it>", rowID: 99, conversationID: 112_409)]
        )
        controller.recordSyncOutcome(regenerationOutcome, for: praticaPath, session: session, isCurrentVault: true)

        let entries = controller.ledger.byPraticaPath[praticaPath]?.entries ?? []
        #expect(entries.first { $0.messageID == "<a@rossi-spa.it>" }?.rowID == 99, "the regenerated message's triple is replaced")
        #expect(entries.first { $0.messageID == "<b@rossi-spa.it>" }?.rowID == 2, "an untouched message's triple is left alone")
        #expect(entries.count == 2, "a regeneration replaces a triple, it never adds a second one for the same Message-ID")
    }
}

// MARK: - §D23.3/§D23.4/§D23.6 - recovery, repointing and the renumbering round-trip

// Full end-to-end coverage through `PraticheController.live(vault:)` +
// `PraticaLiveSync`, the same production wiring `PergamenumApp` uses - `prepare`'s
// conversation loop (§D23.3), `remapLedgerConversations` (§D23.4) and the
// `controller.report(_:)` banner (§D23.5); `MailStoreLocation`'s `-mailStoreRoot`
// override (already implemented, `Tests/MailStoreReaderTests.swift`'s own pattern)
// points the real sync at a `MailStoreFixture`-built store, never at
// `~/Library/Mail`.
// Internal rather than private: `PraticheControllerTests+Regeneration.swift` reads it too.
func dossierNote(conversations: [Int], counterparts: [String] = ["m.rossi@rossi-spa.it"]) -> String {
    let counterpartLines = counterparts.map { "  - \($0)" }.joined(separator: "\n")
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
    \(counterpartLines)
    pergamenum-dossier-conversations: [\(conversationsList)]
    ---

    Appunti pratica.
    """
}

@MainActor
@Suite(.serialized) struct PraticaConversationRenumberingTests {
    @Test func syncRenumbersAFollowedConversationWhoseIdMailHasChanged() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)

        let pratiche = PraticheController.live(vault: vaultController)
        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        let ledgerAfterFirstSync = pratiche.ledger.byPraticaPath[praticaPath]
        #expect(
            ledgerAfterFirstSync?.entries.first?.conversationID == 112_409,
            "the first sync's own bridge triple must name the conversation as it is now"
        )
        // Round-4 review, test 11: the cheapest regression check that
        // `RunContext.livePraticaPath(in:)`'s new resolver calls, threaded through all
        // six of `runExclusive`'s steps, did not break the ordinary no-relocation path -
        // an import must still land and still be recorded when nothing ever moves.
        #expect(
            ledgerAfterFirstSync?.importedMessageIDs == ["<abc123@rossi-spa.it>"],
            "an ordinary sync must still import and still record, with every new `livePraticaPath` guard resolving to a no-op"
        )

        // Mail renumbers the conversation on a reindex: same ROWID, same Message-ID,
        // a brand new `conversation_id`. A short pause guarantees the source's own
        // modification date actually moves (`MailStoreCopy.publish`'s own millisecond
        // generation key), matching how the real Mail store never rewrites its index
        // twice inside the same millisecond either.
        try await Task.sleep(for: .milliseconds(50))
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 550_001, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )],
            in: fixture.root
        )

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations == [550_001], "§D23.4: the renumbered id replaces the old one, in the same position")

        let ledgerAfterSecondSync = pratiche.ledger.byPraticaPath[praticaPath]
        #expect(
            ledgerAfterSecondSync?.entries.first?.conversationID == 550_001,
            "§D23.4: the ledger's own triple is repointed too, or the next renumbering has nothing to recover from"
        )
    }
}

@MainActor
@Suite(.serialized) struct PraticaConversationRecoveryReportingTests {
    @Test func aConversationWithNoRowsAndNoLedgerEntriesIsLeftAloneNoRecoveryNoBanner() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        // The store has no message at all - nothing was ever imported for 112409, so
        // an empty result is not evidence of renumbering (§D23.3's own comment).
        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)

        let pratiche = PraticheController.live(vault: vaultController)
        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(pratiche.problem == nil, "no ledger entries for 112409 means nothing to recover and nothing to report")
        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations == [112_409], "an empty, never-imported conversation is never touched")
    }

    @Test func aFollowedConversationWhoseEveryKnownMemberIsGoneReportsOnceAndStaysInTheDossier() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        // The store holds no message at all any more - the ledger's one known member
        // of 112409 has vanished from Mail entirely.
        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)

        // §D3's bridge, seeded directly into the ledger file rather than through a
        // real sync (`Tests/PraticheConnectorTests.swift`'s own seeding pattern) -
        // this pratica already imported `<vanished@rossi-spa.it>` under 112409 at
        // some point before this test begins.
        var ledger = PraticaLedger.empty
        ledger.byPraticaPath[praticaPath] = .empty
        ledger.byPraticaPath[praticaPath]?.entries = [
            PraticaLedger.Entry(messageID: "<vanished@rossi-spa.it>", rowID: 1, conversationID: 112_409),
        ]
        try ledger.save(to: PraticheController.ledgerURL(for: session))

        let pratiche = PraticheController.live(vault: vaultController)
        pratiche.load(from: vaultController)

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(
            pratiche.problem == "Una conversazione seguita non è più ricostruibile in Mail: 1.",
            "§D23.5: reported once, in the exact sentence the ADR spells out"
        )
        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations == [112_409], "R-14: an unrecoverable conversation is never dropped from the dossier")
    }

    /// PG-109/§D23.5: the ledger persistence and tray row the banner-only fix left
    /// out. Same fixture shape as the test above - a followed conversation whose one
    /// known member has vanished - but this one checks what survives past the run
    /// that found it, and what happens once the conversation is no longer empty.
    @Test func unrecoverableConversationsPersistToTheLedgerAndClearOnceRecovered() async throws {
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)

        var ledger = PraticaLedger.empty
        ledger.byPraticaPath[praticaPath] = .empty
        ledger.byPraticaPath[praticaPath]?.entries = [
            PraticaLedger.Entry(messageID: "<vanished@rossi-spa.it>", rowID: 1, conversationID: 112_409),
        ]
        try ledger.save(to: PraticheController.ledgerURL(for: session))

        let pratiche = PraticheController.live(vault: vaultController)
        pratiche.load(from: vaultController)

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(
            pratiche.ledger.byPraticaPath[praticaPath]?.unrecoverableConversations == [112_409],
            "the run that found it unrecoverable must persist it, not just report it once"
        )

        // The member is back (Mail's index rebuilt, or the message simply reappeared):
        // rebuilt in the SAME directory, exactly as `MailStoreFixture.build`'s own doc
        // comment describes for simulating a store change across two syncs.
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Re: Preventivo", senderAddress: "mario@rossi-spa.it",
                    mailboxRowID: 1, conversationID: 112_409, dateSent: Date(), dateReceived: Date()
                ),
            ],
            in: fixture.root
        )

        await pratiche.trigger(praticaPath, kind: .manualRefresh, eligibility: .automatic)

        #expect(
            pratiche.ledger.byPraticaPath[praticaPath]?.unrecoverableConversations == [],
            "recovered on its own the next sync - no dismiss action, no separate invalidation rule needed"
        )
    }
}
