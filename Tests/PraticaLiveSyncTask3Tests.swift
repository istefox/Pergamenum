import Foundation
import Testing
@testable import Pergamenum

// ADR-0067 (Task 3): declarations for items 12 ("Engine release", R-18), 18 ("Live
// target", R-24) and 19 ("Preparation sentence", R-25). `PraticaLiveSync` built
// directly rather than through `.live(vault:)`, per the plan's own instruction, so
// `regenerationEngine`'s own private state is reachable through the two Task 3
// declarations (`holdsRegenerationEngine`, `releaseRegenerationEngine()`) without a
// third accessor.

private func minimalDossierNote() -> String {
    """
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
    pergamenum-dossier-conversations: [112409]
    ---

    Appunti pratica.
    """
}

@MainActor
@Suite(.serialized) struct PraticaLiveSyncEngineReleaseTests {
    private static let praticaPath = "01 Progetti/Rossi/Offerta 2026"
    private static let messageID = "<abc123@rossi-spa.it>"

    private func makeFixture() throws -> MailStoreFixture.Built {
        try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                    mailboxRowID: 1, conversationID: 112_409,
                    dateSent: Date(timeIntervalSince1970: 1_749_557_170),
                    dateReceived: Date(timeIntervalSince1970: 1_749_557_170),
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                ),
            ]
        )
    }

    /// R-18's release half: «Annulla»/«Chiudi» (`dismissRegeneration`) does not yet
    /// release the held engine - `PraticheController+Ledger.swift:674` calls nothing
    /// on `PraticaLiveSync`. Red until Task 6 wires `controller.releaseRegeneration`.
    @Test func dismissingAPreviewedRegenerationReleasesTheEngine() async throws {
        let vault = try TemporaryVault()
        try vault.write(minimalDossierNote(), to: "\(Self.praticaPath)/pratica.md")
        let fixture = try makeFixture()
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche
        pratiche.releaseRegeneration = { [sync] in sync.releaseRegenerationEngine() }

        pratiche.regeneration = .preparing(notePath: "email/msg.md", subject: "x", praticaPath: Self.praticaPath)
        await sync.prepareRegeneration(praticaPath: Self.praticaPath, messageID: Self.messageID)
        #expect(sync.holdsRegenerationEngine, "prepareRegeneration must hold an engine once it resolves")

        pratiche.dismissRegeneration()

        #expect(!sync.holdsRegenerationEngine, "dismissRegeneration must release the held engine")
    }

    /// R-18's release half, the other exit: a commit that runs to completion must
    /// also release the claim - `commitRegeneration` never calls
    /// `releaseRegenerationEngine` today.
    @Test func committingAPreviewedRegenerationReleasesTheEngine() async throws {
        let vault = try TemporaryVault()
        try vault.write(minimalDossierNote(), to: "\(Self.praticaPath)/pratica.md")
        let fixture = try makeFixture()
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche
        pratiche.releaseRegeneration = { [sync] in sync.releaseRegenerationEngine() }

        // A regeneration replaces an already-imported message's own note - `run` with
        // `.manualRefresh` (ignores eligibility entirely, no `pratiche.load` needed)
        // performs that first import for real, so the message is on disk before this
        // test asks to regenerate it.
        await sync.run(praticaPath: Self.praticaPath, kind: .manualRefresh)

        pratiche.regeneration = .preparing(notePath: "email/msg.md", subject: "x", praticaPath: Self.praticaPath)
        await sync.prepareRegeneration(praticaPath: Self.praticaPath, messageID: Self.messageID)
        guard case .ready(let plan) = pratiche.regeneration else {
            Issue.record("expected the preview to resolve to .ready")
            return
        }

        _ = await sync.commitRegeneration(plan)

        #expect(!sync.holdsRegenerationEngine, "commitRegeneration must release the held engine on completion")
    }
}

// MARK: - R-24: `PraticaCommandActions.liveTarget(of:)`

@MainActor
@Suite struct PraticaLiveTargetTests {
    @Test func liveTargetIsNilOnceTheFolderHasMovedAwayByHand() async throws {
        let vault = try TemporaryVault()
        try vault.write(minimalDossierNote(), to: "Rossi/pratica.md")
        try vault.write(minimalDossierNote(), to: "Bianchi/pratica.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.load(from: controller)
        let actions = PraticaCommandActions(pratiche: pratiche, vault: controller, navigation: Navigation())

        let target = await actions.addToPratica(messageID: "<abc@rossi-spa.it>", praticaPath: "Rossi")
        #expect(target == "Rossi", "the happy path returns the path")

        try FileManager.default.moveItem(
            at: vault.root.appending(path: "Rossi", directoryHint: .isDirectory),
            to: vault.root.appending(path: "Rossi-spostata", directoryHint: .isDirectory)
        )

        #expect(actions.liveTarget(of: "Rossi") == nil, "a folder moved by hand must no longer be a live target")
    }
}

// MARK: - R-25: `PraticaLiveSync.preparationProblemSentence`

@Suite struct PreparationProblemSentenceTests {
    @Test func joinsBothSentencesWhenBothProblemsAreTrue() throws {
        let sentence = try #require(
            PraticaLiveSync.preparationProblemSentence(unrecoverableConversations: 2, recipientsUnsupported: true)
        )
        #expect(sentence.contains("2"))
        #expect(sentence.contains("non espone i destinatari"))
    }

    @Test func nilWhenNeitherProblemHappened() {
        #expect(PraticaLiveSync.preparationProblemSentence(unrecoverableConversations: 0, recipientsUnsupported: false) == nil)
    }
}
