import Foundation
import Testing
@testable import Pergamenum

// Split out of `PraticheControllerTests.swift` under PG-293 (#638) to clear its SwiftLint
// `file_length` warning: a pure move, no test changed.

// MARK: - Review round 3: a stale «Rigenera…» preview must never clobber a superseding one

@MainActor
@Suite(.serialized) struct PraticaRegenerationSupersededPreviewTests {
    private typealias Fixtures = PraticaSyncFixtures

    /// A second, distinct message for the same pratica - `EmailFixtureCorpus` has no
    /// builder taking an arbitrary `Message-Id`, and this suite needs one message the
    /// index resolves as something other than the one `completeMessageRFC822` already
    /// is (`PraticaSyncRegressionRetryTests.threeAttachmentMessageRFC822`'s own reason
    /// for authoring its own body inline rather than reusing a fixed one).
    private static func secondMessageRFC822(messageID: String) -> String {
        """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Conferma ordine\r
        Message-Id: \(messageID)\r
        Date: Thu, 11 Jun 2026 15:30:00 +0200\r
        \r
        Confermiamo la ricezione del suo ordine.\r
        """
    }

    /// Review round 3's MAJOR, introduced by round 2's own fix: `prepareRegeneration`
    /// captured `praticaPath` before its only `await` (`engine.regenerationPreview`), but
    /// nothing stopped an attempt abandoned by «Annulla» from resuming later and writing
    /// `.ready` over a DIFFERENT, still-current attempt's own state once dismissing the
    /// first no longer canceled anything in flight.
    ///
    /// End-to-end through `PraticheController.live(vault:)` + `PraticaLiveSync`, the
    /// same production wiring `PergamenumApp` uses - unlike the analogous `runExclusive`
    /// race `Tests/PraticaLiveSyncRecordOutcomeTests.swift` found unreproducible
    /// end-to-end (no controllable suspension point reachable from outside),
    /// `prepareRegeneration` has exactly one: the single `await
    /// engine.regenerationPreview(...)` call, with nothing before it in the function
    /// ever suspending. `waitUntil` on `regeneratingPraticaPaths` - set by the very first
    /// line of that unbroken synchronous prefix - therefore pins task A at that exact
    /// boundary deterministically, no sleep-against-the-actor guess needed.
    @Test func anAbandonedRegenerationPreviewNeverClobbersASupersedingOne() async throws {
        let praticaPath = Fixtures.praticaFolder
        let messageIDA = "<abc123@rossi-spa.it>"
        let messageIDB = "<def456@rossi-spa.it>"
        let dateA = Date(timeIntervalSince1970: 1_749_557_170)
        let dateB = Date(timeIntervalSince1970: 1_749_643_570)

        let vault = try TemporaryVault()
        try vault.write(dossierNote(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: dateA, dateReceived: dateA,
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                ),
                .init(
                    rowID: 2, subject: "Conferma ordine", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: dateB, dateReceived: dateB,
                    emlxBody: Self.secondMessageRFC822(messageID: messageIDB)
                ),
            ]
        )
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        // Both notes seeded directly (`PraticaRegenerationTests`'s own pattern) - a real
        // membership-rule sync is not what this race is about.
        let seedEngine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vault.root)
        let seedRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: praticaPath, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: messageIDA, date: dateA),
                Fixtures.row(rowID: 2, messageID: messageIDB, date: dateB),
            ],
            onDisk: [], settings: .default
        )
        _ = try await seedEngine.sync(seedRequest)

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController.live(vault: vaultController)

        // «Rigenera…» on A - `PraticaCommandActions.requestRegeneration`'s own shape:
        // the sheet opens to `.preparing` before the async preview is even started.
        pratiche.regeneration = .preparing(notePath: "A", subject: "A", praticaPath: praticaPath)
        let taskA = Task { @MainActor in
            await pratiche.prepareRegeneration?(praticaPath, messageIDA)
        }
        try await waitUntil { pratiche.regeneratingPraticaPaths.contains(praticaPath) }

        // «Annulla», before A's own preview has resolved.
        pratiche.dismissRegeneration()
        #expect(pratiche.regeneration == nil)
        #expect(!pratiche.regeneratingPraticaPaths.contains(praticaPath), "dismissing A must release its claim")

        // «Rigenera…» on B, a different message in the same pratica - runs to completion
        // before A's abandoned preview ever resolves.
        pratiche.regeneration = .preparing(notePath: "B", subject: "B", praticaPath: praticaPath)
        await pratiche.prepareRegeneration?(praticaPath, messageIDB)

        guard case .ready(let planB) = pratiche.regeneration else {
            Issue.record("expected B's own preview to resolve to .ready, got \(String(describing: pratiche.regeneration))")
            // taskA still needs the override held by `defer { MailStoreOverride.release() }`
            // above - await it before returning, or this early exit releases the gate while
            // taskA is still resolving against it.
            _ = await taskA.value
            vaultController.close()
            return
        }
        #expect(planB.messageID == messageIDB)

        // A's stale, abandoned preview actually resolves only now.
        _ = await taskA.value

        guard case .ready(let planAfter) = pratiche.regeneration else {
            Issue.record(
                "A's resurfaced, superseded preview must never clobber B's - got \(String(describing: pratiche.regeneration))"
            )
            vaultController.close()
            return
        }
        #expect(planAfter.messageID == messageIDB, "A's stale preview must never resurface once B has superseded it")
        #expect(
            pratiche.regeneratingPraticaPaths.contains(praticaPath),
            "B's own claim must still be held - A's stale completion must not double-release it"
        )

        vaultController.close()
    }
}

// ADR-0040 §D8 (R-08): a pending attachment entry (the bare name, no `[[…]]`) must not
// silently become an ordinary chip pointing at a file `allegati/` does not have.

@Suite struct PraticaReadTimelinePendingAttachmentsTests {
    @Test func readTimelineSplitsOneLinkedAndOnePendingAttachmentIntoTheirOwnLists() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pratica-pending-attachments-\(UUID().uuidString)", directoryHint: .isDirectory)
        let praticaPath = "Rossi/Offerta"
        let messagesFolder = root.appending(path: "\(praticaPath)/email", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: messagesFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let document = MessageDocument(
            frontmatter: MessageDocument.MailFrontmatter(
                schemaVersion: 1, messageID: "<offerta@rossi-spa.it>", conversationID: 1, direction: .received,
                date: Date(timeIntervalSince1970: 1_749_557_170), received: nil,
                from: "m.rossi@rossi-spa.it", to: [], cc: [], subject: "Offerta",
                attachments: ["[[offerta.pdf]]", "bozza.docx"], body: .complete, original: nil
            ),
            newText: "Testo del messaggio.", quotedHistory: nil, signature: nil
        )
        let text = MessageDocument.render(document, tags: [Tag(namespace: .type, value: "email")])
        try text.write(
            to: messagesFolder.appending(path: "20260610_1406_Rossi_offerta.md", directoryHint: .notDirectory),
            atomically: true, encoding: .utf8
        )

        let read = PraticheController.readTimeline(praticaPath: praticaPath, vaultRoot: root)

        #expect(read.entries.count == 1)
        let detail = try #require(read.details[read.entries[0].id])
        #expect(
            detail.attachments.map(\.name) == ["offerta.pdf"],
            "only the linked `[[…]]` entry becomes a PraticaAttachmentRef"
        )
        #expect(
            detail.pendingAttachments == ["bozza.docx"],
            "the bare, still-pending entry must land in pendingAttachments, not attachments"
        )
    }
}
