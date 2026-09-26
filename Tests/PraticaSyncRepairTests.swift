import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

@Suite struct PraticaSyncRepairTests {
    private typealias Fixtures = PraticaSyncFixtures

    private static let secondPraticaFolder = "01 Progetti/Bianchi/Preventivo 2026"

    private static func seedExistingMessage(
        under vaultRoot: URL,
        folder: String = Fixtures.praticaFolder,
        messageID: String,
        date: Date = Date(timeIntervalSince1970: 1_781_093_170),
        linkedAttachmentNames: [String],
        fileName: String? = nil
    ) throws -> URL {
        let document = MessageDocument(
            frontmatter: .init(
                schemaVersion: 1,
                messageID: "<\(messageID)>",
                conversationID: 112_409,
                direction: .received,
                date: date,
                received: date,
                from: "Mario Rossi <m.rossi@rossi-spa.it>",
                to: ["Stefano Ferri <stefano@stefer.it>"],
                cc: [],
                subject: "Offerta",
                attachments: linkedAttachmentNames.map { MessageDocument.attachmentEntry(linking: $0) },
                body: .complete,
                original: nil
            ),
            newText: "Buongiorno, in allegato.",
            quotedHistory: nil,
            signature: nil
        )
        let text = MessageDocument.render(document, tags: [])
        let emailDir = vaultRoot.appending(path: "\(folder)/email", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: emailDir, withIntermediateDirectories: true)
        let sanitizedID = messageID.replacingOccurrences(of: "@", with: "-").replacingOccurrences(of: ".", with: "-")
        let name = fileName ?? "20260610_1406_seed_\(sanitizedID).md"
        let url = emailDir.appending(path: name, directoryHint: .notDirectory)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }

    private static func seedAllegatiFile(
        under vaultRoot: URL, folder: String = Fixtures.praticaFolder, name: String, bytes: Data
    ) throws {
        let dir = vaultRoot.appending(path: "\(folder)/allegati", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appending(path: name, directoryHint: .notDirectory), options: .atomic)
    }

    @Test func aCompleteMessageWithNoPendingAttachmentsIsNeverRePreparedOrRewritten() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000), emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, _) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Fixtures.modificationDate(of: noteURL)

        let secondOutcome = try await engine.sync(request)

        #expect(secondOutcome.writtenFiles.isEmpty, "a .complete message with no pending attachment is never revisited")
        #expect(secondOutcome.resolvedAttachmentFiles.isEmpty)
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty)
        #expect(
            try Fixtures.modificationDate(of: noteURL) == firstModified,
            "ADR-0036 §D6's rule, unchanged for a message that never had a pending attachment"
        )
    }

    @Test func rigeneraOnAMessageWithAPendingAttachmentStillProducesAFullRenderNotAPatch() async throws {
        let message = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "rigenera@rossi-spa.it", filename: "offerta.pdf"
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
                Fixtures.row(rowID: 1, messageID: "<rigenera@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
        let handEditedText = originalText + "\n\nAggiunto a mano, e che «Rigenera» deve scartare.\n"
        try Data(handEditedText.utf8).write(to: noteURL, options: .atomic)

        let plan = try await engine.regenerationPreview(request, messageID: "<rigenera@rossi-spa.it>", rowID: nil)

        #expect(plan.currentText == handEditedText)
        #expect(
            !plan.replacementText.contains("Aggiunto a mano"),
            "«Rigenera» is a full render (ADR §D21, unchanged) - it must not preserve a hand edit the way §D4's patch does"
        )
        #expect(
            plan.replacementText == originalText,
            "the replacement is a whole note reproducing what a fresh import would write, not a one-line patch"
        )
        #expect(plan.diff != nil, "the hand-edited file on disk differs from the full-render replacement")
    }

    // MARK: Task 7 (ADR-0040 §D7) - a corrupt file already in the vault is trashed and
    // its message re-enters the cycle (R-10, R-11, R-12)
    //
    // Every scenario seeds its "already in the vault" state directly through
    // `seedExistingMessage`/`seedAllegatiFile`, never through a first `engine.sync(_:)`
    // call - the corrupt file's presence must not depend on what Mail currently holds
    // for that `Message-ID` (ADR-0040 §D7's premise: legacy damage, or disk-level
    // corruption unrelated to Mail's own state). `folderContext(of:)` scans `email/`
    // and `allegati/` directly off disk regardless of `request.candidates`, so an
    // empty candidate list is enough to exercise the repair pass alone, with no risk
    // of `regeneratePending`/the main loop resolving the same message in the same run.

    @Test func aZeroByteFileAlreadyInAllegatiIsRepairedWhileAValidFileStaysUntouched() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let noteURL = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "repair1@rossi-spa.it",
            linkedAttachmentNames: ["20260610_buono.pdf", "20260610_cattivo.pdf"]
        )
        let validBytes = EmailFixtureCorpus.pdfBytes(pages: 1)
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_buono.pdf", bytes: validBytes)
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_cattivo.pdf", bytes: Data())

        // Mail's own index carries nothing for this Message-ID - the seeded state
        // stands for legacy damage the retry pass cannot resolve on its own, and an
        // empty candidate list keeps this a pure repair-pass test (§D7).
        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        let outcome = try await engine.sync(request)

        #expect(
            Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_buono.pdf"],
            "the zero-byte file is gone from allegati/, the valid one stays (R-10, R-11)"
        )
        let bytesAfter = try Data(contentsOf:
            vaultRoot.appending(path: "\(Fixtures.praticaFolder)/allegati/20260610_buono.pdf", directoryHint: .notDirectory))
        #expect(bytesAfter == validBytes, "the valid file's own bytes must be byte-identical after the repair pass")

        let doc = try #require(MessageDocument.parse(String(contentsOf: noteURL, encoding: .utf8)))
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_buono.pdf"])
        #expect(
            doc.frontmatter.pendingAttachmentNames == ["20260610_cattivo.pdf"],
            "the corrupt file's link becomes pending (R-10), never silently dropped"
        )
        #expect(outcome.resolvedAttachmentFiles.count == 1, "the repair patches exactly the one note that linked the corrupt file")
    }

    @Test func aCorruptFileInOneFoldersAllegatiDoesNotAffectAnIdenticallyNamedValidFileInAnother() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let noteA = try Self.seedExistingMessage(
            under: vaultRoot, folder: Fixtures.praticaFolder, messageID: "isoA@rossi-spa.it",
            linkedAttachmentNames: ["20260610_comune.pdf"], fileName: "20260610_1406_seed_a.md"
        )
        try Self.seedAllegatiFile(under: vaultRoot, folder: Fixtures.praticaFolder, name: "20260610_comune.pdf", bytes: Data())

        let noteB = try Self.seedExistingMessage(
            under: vaultRoot, folder: Self.secondPraticaFolder, messageID: "isoB@bianchi-srl.it",
            linkedAttachmentNames: ["20260610_comune.pdf"], fileName: "20260610_1406_seed_b.md"
        )
        let validBytesB = EmailFixtureCorpus.pdfBytes(pages: 2)
        try Self.seedAllegatiFile(
            under: vaultRoot, folder: Self.secondPraticaFolder, name: "20260610_comune.pdf", bytes: validBytesB
        )

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        // Scoped to folder A only - `request.praticaFolder` is what `folderContext(of:)`
        // resolves `email/`/`allegati/` under; folder B is never scanned by this sync.
        let requestA = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        _ = try await engine.sync(requestA)

        #expect(
            Fixtures.allegatiFiles(under: vaultRoot, folder: Fixtures.praticaFolder).isEmpty,
            "folder A's corrupt file is trashed; nothing else was ever there"
        )
        let docA = try #require(MessageDocument.parse(String(contentsOf: noteA, encoding: .utf8)))
        #expect(docA.frontmatter.pendingAttachmentNames == ["20260610_comune.pdf"])

        let bytesB = try Data(contentsOf:
            vaultRoot.appending(path: "\(Self.secondPraticaFolder)/allegati/20260610_comune.pdf", directoryHint: .notDirectory))
        #expect(bytesB == validBytesB, "folder B's identically-named, unrelated, valid file must be untouched by A's repair (R-11)")
        let docB = try #require(MessageDocument.parse(String(contentsOf: noteB, encoding: .utf8)))
        #expect(docB.frontmatter.linkedAttachmentNames == ["20260610_comune.pdf"], "folder B's link is unaffected - it was never scanned")
    }

    @Test func theTrashedFilesDigestIsExcludedFromDedupSoANewEmptyAttachmentIsNeverLinkedToTheTrashedName() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let noteA = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "dedupA@rossi-spa.it",
            linkedAttachmentNames: ["20260610_offerta.pdf"]
        )
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_offerta.pdf", bytes: Data())

        // A second, unrelated message whose own attachment also decodes to zero bytes -
        // the same SHA-256 (of empty `Data`) the now-trashed file had. If that digest
        // were still in the dedup map after the repair, this attachment could be
        // mistaken for "already present" and linked to the trashed (now-gone) name
        // instead of getting its own pending entry (R-12).
        let secondMessage = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "dedupB@rossi-spa.it", filename: "nuovo.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato vuoto", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )]
        )
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<dedupB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let docA = try #require(MessageDocument.parse(String(contentsOf: noteA, encoding: .utf8)))
        #expect(docA.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"], "A's link is downgraded by the same run's repair pass")

        let documents = try Fixtures.messageDocuments(under: vaultRoot)
        let docB = try #require(documents.first { $0.frontmatter.messageID == "<dedupB@rossi-spa.it>" })
        #expect(docB.frontmatter.linkedAttachmentNames.isEmpty, "an empty attachment must never be linked")
        #expect(
            !docB.frontmatter.pendingAttachmentNames.contains("20260610_offerta.pdf"),
            "the new empty attachment must not be mistaken for the trashed file by digest (R-12)"
        )
        #expect(
            docB.frontmatter.pendingAttachmentNames == ["20260610_nuovo.pdf"],
            "it gets its own pending entry, named after itself, not the trashed one"
        )
    }

    @Test func aCorruptFileIsRepairedAndResolvedInOneSyncWhenMailAlreadyHasTheRealBytes() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let noteURL = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "resolveinone@rossi-spa.it",
            linkedAttachmentNames: ["20260610_offerta.pdf"]
        )
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_offerta.pdf", bytes: Data())

        let realBytes = EmailFixtureCorpus.pdfBytes(pages: 1)
        let realMessage = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "resolveinone@rossi-spa.it", attachmentFilename: "offerta.pdf", attachmentBytes: realBytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Con allegato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: realMessage
            )]
        )
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<resolveinone@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(
            Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"],
            "the good bytes now sit at the same generated name"
        )
        let bytesAfter = try Data(contentsOf:
            vaultRoot.appending(path: "\(Fixtures.praticaFolder)/allegati/20260610_offerta.pdf", directoryHint: .notDirectory))
        #expect(bytesAfter == realBytes, "the file on disk is the real one, not the trashed placeholder")
        let doc = try #require(MessageDocument.parse(String(contentsOf: noteURL, encoding: .utf8)))
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_offerta.pdf"])
        #expect(
            doc.frontmatter.pendingAttachmentNames.isEmpty,
            "a single sync both repairs the corrupt file and re-imports it, since Mail already has the bytes (§D7)"
        )
    }

    @Test func aSecondSyncAfterACompletedRepairFindsNothingLeftToRepair() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let noteURL = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "noop@rossi-spa.it",
            linkedAttachmentNames: ["20260610_buono.pdf", "20260610_cattivo.pdf"]
        )
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_buono.pdf", bytes: EmailFixtureCorpus.pdfBytes(pages: 1))
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_cattivo.pdf", bytes: Data())

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.resolvedAttachmentFiles.count == 1, "the first sync does the one repair there is to do")

        let textAfterFirstRepair = try String(contentsOf: noteURL, encoding: .utf8)
        let modifiedAfterFirstRepair = try Fixtures.modificationDate(of: noteURL)

        let secondOutcome = try await engine.sync(request)

        #expect(secondOutcome.resolvedAttachmentFiles.isEmpty, "nothing left to repair - §D7.2's no-flag-needed claim, asserted not argued")
        #expect(secondOutcome.attachmentProblems.isEmpty)
        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_buono.pdf"], "no further change to allegati/")
        #expect(
            try String(contentsOf: noteURL, encoding: .utf8) == textAfterFirstRepair,
            "the note must not be rewritten a second time"
        )
        #expect(
            try Fixtures.modificationDate(of: noteURL) == modifiedAfterFirstRepair,
            "not even touched, not just written identically (§D6's no-op rule reused for the repair patch)"
        )
    }

    // §D7.3: `FileManager.trashItem` fails when it cannot remove the item from its
    // containing directory - a real POSIX seam on this test volume (verified by hand:
    // `chmod 555` on a directory blocks `rm` of a file inside it with "Permission
    // denied", the same unlink-requires-write-on-the-parent rule trashing ultimately
    // relies on), no coder-added seam needed.
    @Test func aTrashFailureLeavesTheFileAloneAndReportsTheProblemWithoutDowngradingTheLink() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let noteURL = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "trashfail@rossi-spa.it",
            linkedAttachmentNames: ["20260610_cattivo.pdf"]
        )
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_cattivo.pdf", bytes: Data())

        let allegatiDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/allegati", directoryHint: .isDirectory)
        let corruptPath = allegatiDir.appending(path: "20260610_cattivo.pdf", directoryHint: .notDirectory)
            .path(percentEncoded: false)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: allegatiDir.path(percentEncoded: false)
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: allegatiDir.path(percentEncoded: false)
            )
        }

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        let outcome = try await engine.sync(request)

        #expect(
            FileManager.default.fileExists(atPath: corruptPath),
            "a file that could not be trashed is left alone, not silently unlinked another way (§D7.3)"
        )
        let doc = try #require(MessageDocument.parse(String(contentsOf: noteURL, encoding: .utf8)))
        #expect(
            doc.frontmatter.linkedAttachmentNames == ["20260610_cattivo.pdf"],
            "the link is not downgraded when the trash itself failed - an orphan nobody could find otherwise"
        )
        #expect(!outcome.attachmentProblems.isEmpty, "the failure is reported through the sync outcome (§D7.3)")
        #expect(outcome.resolvedAttachmentFiles.isEmpty, "nothing was actually resolved")
    }
}
