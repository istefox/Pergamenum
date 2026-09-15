import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.
//
// Split out of `PraticaSyncRetryTests.swift` (PG-159/PG-160, ADR-0045 §D1/§D8): the
// Regression MARK block below, unedited.

@Suite struct PraticaSyncRegressionRetryTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: Regression - `regeneratePending` must run on the request shape production
    // actually sends it, not the shape a hand-built test can get away with.
    //
    // `PraticheController.runExclusive` builds `candidates` from
    // `MembershipRule.candidates(dossier:store:onDisk:)`, which subtracts `onDisk` from
    // its result by design (rule 5, "minus what is already on disk"). So the SECOND
    // sync below never repeats the message in `candidates` - exactly what production
    // sends, and exactly the shape the bug above made `regeneratePending` silently do
    // nothing with.
    //
    // Each second sync below opens a FRESH engine on the rebuilt index, never the
    // first sync's own `engine` - `regeneratePending` now calls `reader.row(forMessageID:)`,
    // and `PraticaSyncEngine.openedReader()` caches its `MailStoreReader` for the
    // actor's whole lifetime, so a rebuild "in place" at the same path is invisible to
    // an already-open engine (the same reason `aMessageWhoseRowDisappearsKeepsItsFilesLosesItsLinkAndIsNeverDeleted`
    // above opens a second engine). Production never hits this: `MailStoreCopy.publish`
    // gives every sync its own fresh generation directory, never an in-place rewrite.

    /// A three-attachment message, for the "one of two pending resolves, a third
    /// already-linked attachment is untouched" case (R-06's second sentence) - no
    /// existing `EmailFixtureCorpus` builder carries three parts, and this batch's
    /// tester scope is `Tests/PraticaSyncTests.swift` only.
    private static func threeAttachmentMessageRFC822(
        messageID: String,
        firstBytes: Data,
        secondBytes: Data,
        thirdBytes: Data,
        boundary: String = "----=_Pergamenum_ThreeAttachments_Boundary"
    ) -> String {
        """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta con tre allegati\r
        Message-Id: <\(messageID)>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato tre file.\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="a-subito.pdf"\r
        \r
        \(firstBytes.base64EncodedString())\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="b-risolve.pdf"\r
        \r
        \(secondBytes.base64EncodedString())\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="c-mai.pdf"\r
        \r
        \(thirdBytes.base64EncodedString())\r
        --\(boundary)--\r
        """
    }

    @Test func aResolvedAttachmentResolvesOnAnOrdinarySyncOnceTheMessageIsOnDisk() async throws {
        let firstMessage = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "resolve2@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato troncato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let firstRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<resolve2@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        let firstOutcome = try await engine.sync(firstRequest)
        #expect(firstOutcome.importedMessageIDs == ["<resolve2@rossi-spa.it>"])

        let secondMessage = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "resolve2@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: EmailFixtureCorpus.pdfBytes()
        )
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Con allegato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )],
            in: fixture.root
        )

        // The production shape: the message is no longer in `candidates` (it is
        // already on disk), but it is in `onDisk` - the same pair
        // `MembershipRule.candidates` and `PraticheController.runExclusive` actually
        // hand the engine on every sync after the first.
        let secondEngine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [], onDisk: ["<resolve2@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "the pending entry must be gone once bytes resolve")
        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"])
        #expect(secondOutcome.resolvedAttachmentFiles.count == 1, "one note amended in one line")
    }

    @Test func aPendingBodyRegeneratesOnAnOrdinarySyncOnceTheMessageIsOnDisk() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta (corpo in arrivo)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.headersOnlyMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let firstRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<pendingbody2@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        let firstOutcome = try await engine.sync(firstRequest)
        #expect(firstOutcome.writtenFiles.count == 1, "the pending message is still written once, as a placeholder")

        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: "pendingbody2@rossi-spa.it")
            )],
            in: fixture.root
        )

        let secondEngine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [], onDisk: ["<pendingbody2@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)
        #expect(secondOutcome.regeneratedPendingFiles.count == 1, "the pending file is rewritten unasked")

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.body == .complete, "the body arrived; the file is no longer pending")
    }

    @Test func aNotResolvableRowIDFallsBackToTheLedgerEntry() async throws {
        let firstMessage = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "ledgerfallback@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato troncato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let firstRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<ledgerfallback@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(firstRequest)

        // Mail renumbers the ROWID on reindex - the index can no longer resolve this
        // Message-ID to the row it actually needs, so `regeneratePending` must fall
        // back to the ledger's own bridge triple, exactly as `regenerationPreview`
        // already does for the manual «Rigenera» path.
        let secondMessage = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "ledgerfallback@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: EmailFixtureCorpus.pdfBytes()
        )
        let secondFixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 99, subject: "Con allegato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )]
        )
        // Forces `reader.row(forMessageID:)` to answer `.notResolvableFromIndex`, so
        // this test actually exercises the ledger `rowID` fallback rather than the
        // index's own header lookup (which would otherwise just resolve rowID 99
        // directly, the same as every other resolution test above).
        try MailStoreFixture.dropMessageGlobalDataTable(indexURL: secondFixture.indexURL)
        let secondEngine = Fixtures.makeEngine(mailStoreURL: secondFixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [], onDisk: ["<ledgerfallback@rossi-spa.it>"], settings: .default,
            ledgerEntries: [
                PraticaLedger.Entry(messageID: "<ledgerfallback@rossi-spa.it>", rowID: 99, conversationID: 112_409),
            ]
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_offerta.pdf"])
        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"])
        #expect(secondOutcome.resolvedAttachmentFiles.count == 1)
    }

    @Test func onlyTheResolvingAttachmentMovesWhileASecondStaysPendingAndAThirdLinkedOneIsUntouched() async throws {
        let firstMessage = Self.threeAttachmentMessageRFC822(
            messageID: "partial@rossi-spa.it",
            firstBytes: EmailFixtureCorpus.pdfBytes(pages: 1),
            secondBytes: EmailFixtureCorpus.truncatedPDFBytes(),
            thirdBytes: EmailFixtureCorpus.truncatedPDFBytes()
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta con tre allegati", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<partial@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc1 = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc1.frontmatter.linkedAttachmentNames == ["20260610_a-subito.pdf"])
        #expect(
            Set(doc1.frontmatter.pendingAttachmentNames)
                == Set(["20260610_b-risolve.pdf", "20260610_c-mai.pdf"])
        )

        // Only the second attachment's bytes resolve; the third stays truncated.
        let secondMessage = Self.threeAttachmentMessageRFC822(
            messageID: "partial@rossi-spa.it",
            firstBytes: EmailFixtureCorpus.pdfBytes(pages: 1),
            secondBytes: EmailFixtureCorpus.pdfBytes(pages: 2),
            thirdBytes: EmailFixtureCorpus.truncatedPDFBytes()
        )
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta con tre allegati", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )],
            in: fixture.root
        )

        let secondOutcome = try await engine.sync(request)

        let doc2 = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(
            Set(doc2.frontmatter.linkedAttachmentNames)
                == Set(["20260610_a-subito.pdf", "20260610_b-risolve.pdf"]),
            "the already-linked first attachment is untouched, the resolving second joins it"
        )
        #expect(
            doc2.frontmatter.pendingAttachmentNames == ["20260610_c-mai.pdf"],
            "the never-resolving third stays pending"
        )
        #expect(
            Set(Fixtures.allegatiFiles(under: vaultRoot))
                == Set(["20260610_a-subito.pdf", "20260610_b-risolve.pdf"])
        )
        #expect(secondOutcome.resolvedAttachmentFiles.count == 1, "one note amended, even though two names changed in it")
    }

    @Test func tenConsecutiveSyncsOverANeverResolvingFixtureWriteOnlyOnceAndNeverGrowAnyOutcomeArray() async throws {
        let message = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "nogrow@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato troncato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<nogrow@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1, "the first sync writes the pending placeholder once")
        let (noteURL, _) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Fixtures.modificationDate(of: noteURL)

        for run in 2...10 {
            let outcome = try await engine.sync(request)
            #expect(outcome.writtenFiles.isEmpty, "run \(run) must write nothing - the attachment never resolves")
            #expect(outcome.resolvedAttachmentFiles.isEmpty, "run \(run) must resolve nothing")
            #expect(outcome.regeneratedPendingFiles.isEmpty, "run \(run) must regenerate nothing")
        }

        #expect(
            try Fixtures.modificationDate(of: noteURL) == firstModified,
            "ten unresolved retries must leave the file exactly as the first sync wrote it - no leak (R-05)"
        )
    }
}
