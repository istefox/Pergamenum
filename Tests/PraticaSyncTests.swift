import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.
//
// `PraticaSyncPlan.workItems` and every `PraticaSyncEngine` method are declared-but-
// stubbed by this batch's tester (ADR-0155 §D1) - every test below is red because the
// stub does nothing, not because a symbol is missing. The coder fills in the bodies;
// these tests, unedited, are what proves the fill-in is correct.

// MARK: - Shared fixtures

private func sampleDossier(
    counterparts: [String] = ["m.rossi@rossi-spa.it"],
    conversations: [Int] = [112_409]
) -> Dossier {
    Dossier(
        schemaVersion: 1, counterparts: counterparts, conversations: conversations,
        keywords: [], included: [], excluded: [], ignored: []
    )
}

private func occurrenceCount(of substring: String, in text: String) -> Int {
    guard !substring.isEmpty else { return 0 }
    var count = 0
    var searchStart = text.startIndex
    while let range = text.range(of: substring, range: searchStart..<text.endIndex) {
        count += 1
        searchStart = range.upperBound
    }
    return count
}

private func row(
    rowID: Int,
    messageID: String,
    mailboxURL: String = "ews://acct1/INBOX",
    date: Date = Date(timeIntervalSince1970: 1_749_557_170),
    deleted: Bool = false
) -> MailMessageRow {
    MailMessageRow(
        rowID: rowID, indexMessageIDHash: nil, globalMessageID: nil,
        subject: "Richiesta offerta", sender: "m.rossi@rossi-spa.it",
        dateSent: date, dateReceived: date,
        mailbox: MailboxRef(rowID: 1, url: mailboxURL),
        conversationID: 112_409, deleted: deleted, messageID: messageID
    )
}

// MARK: - `PraticaSyncPlan.workItems` (pure - no fixture needed)

@Suite struct PraticaSyncPlanTests {
    @Test func ordersCandidatesNewestFirst() {
        let older = row(rowID: 1, messageID: "<older@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000))
        let newer = row(rowID: 2, messageID: "<newer@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000))
        let items = PraticaSyncPlan.workItems(
            dossier: sampleDossier(), candidates: [older, newer], onDisk: [], settings: .default
        )
        #expect(items.map(\.row.rowID) == [2, 1], "newest (rowID 2) must lead")
    }

    @Test func skipsMessageIDsAlreadyOnDisk() {
        let imported = row(rowID: 1, messageID: "<already@rossi-spa.it>")
        let items = PraticaSyncPlan.workItems(
            dossier: sampleDossier(), candidates: [imported],
            onDisk: ["<already@rossi-spa.it>"], settings: .default
        )
        #expect(items.isEmpty, "an already-imported Message-ID must not be queued again")
    }

    // ADR §D15
    @Test func resolvesTheSameMessageIdSeenInTwoMailboxesToExactlyOneItem() {
        let inTrash = row(rowID: 9, messageID: "<dup@rossi-spa.it>", mailboxURL: "ews://acct1/Trash")
        let inInbox = row(rowID: 3, messageID: "<dup@rossi-spa.it>", mailboxURL: "ews://acct1/INBOX")
        let items = PraticaSyncPlan.workItems(
            dossier: sampleDossier(), candidates: [inTrash, inInbox], onDisk: [], settings: .default
        )
        #expect(items.count == 1, "one Message-ID in two mailboxes must produce exactly one work item")
        #expect(items.first?.row.mailbox.url == "ews://acct1/INBOX", "the non-Trash/Junk copy survives")
    }
}

// MARK: - `PraticaSyncEngine` (fixture store + temporary vault)

@Suite struct PraticaSyncEngineTests {
    /// A throwaway vault-shaped directory (no `VaultSession`, no note index - the
    /// engine's own attachment/`.eml` writes are plain files, and the one `.md` hop
    /// this closure stands in for is `VaultSession.write`'s job in production).
    private static func makeVaultRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-pratica-sync-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeEngine(mailStoreURL: URL, vaultRoot: URL) -> PraticaSyncEngine {
        PraticaSyncEngine(mailStoreURL: mailStoreURL, vaultRoot: vaultRoot) { text, relativePath in
            let url = vaultRoot.appending(path: relativePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    private static let praticaFolder = "01 Progetti/Rossi/Offerta 2026"
    /// A second, unrelated pratica folder - Task 7's isolation test needs two
    /// `allegati/` directories the engine must never confuse (R-11).
    private static let secondPraticaFolder = "01 Progetti/Bianchi/Preventivo 2026"

    private static func mdFiles(under vaultRoot: URL, folder: String = praticaFolder) -> [String] {
        let emailDir = vaultRoot.appending(path: "\(folder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
    }

    private static func allegatiFiles(under vaultRoot: URL, folder: String = praticaFolder) -> [String] {
        let dir = vaultRoot.appending(path: "\(folder)/allegati", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []).sorted()
    }

    /// Every message note currently on disk, parsed, in file-name order - Tasks 4/5's
    /// tests read the attachment lists back through `MessageDocument`, never by
    /// grepping the rendered text.
    private static func messageDocuments(under vaultRoot: URL, folder: String = praticaFolder) throws -> [MessageDocument] {
        let emailDir = vaultRoot.appending(path: "\(folder)/email", directoryHint: .isDirectory)
        return try Self.mdFiles(under: vaultRoot, folder: folder).map { name in
            let text = try String(contentsOf: emailDir.appending(path: name), encoding: .utf8)
            return try #require(MessageDocument.parse(text), "\(name) must parse back as a message note")
        }
    }

    /// The single message note this test's sync produced - fails loudly (`#require`)
    /// rather than silently reading `nil` when a test's own setup wrote zero or more
    /// than one, which would otherwise misreport as "no attachments" everywhere below.
    private static func onlyMessageDocument(under vaultRoot: URL, folder: String = praticaFolder) throws -> MessageDocument {
        let documents = try Self.messageDocuments(under: vaultRoot, folder: folder)
        return try #require(documents.first, "expected exactly one message note, found \(documents.count)")
    }

    /// Writes a message note directly to `email/`, bypassing both the engine and Mail
    /// entirely - Task 7's own premise is a file already sitting in the vault before
    /// this fix shipped (or corrupted by something other than Mail), and that state
    /// must be constructible without depending on whatever the Mail fixture currently
    /// holds for this `Message-ID` (ADR-0040 §D7). Returns the note's file URL.
    private static func seedExistingMessage(
        under vaultRoot: URL,
        folder: String = praticaFolder,
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

    /// Writes a file directly into `allegati/`, bypassing the engine - the other half
    /// of `seedExistingMessage`'s "legacy state already in the vault" premise.
    private static func seedAllegatiFile(
        under vaultRoot: URL, folder: String = praticaFolder, name: String, bytes: Data
    ) throws {
        let dir = vaultRoot.appending(path: "\(folder)/allegati", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try bytes.write(to: dir.appending(path: name, directoryHint: .notDirectory), options: .atomic)
    }

    // MARK: R-11 - atomic writes, cancel between two messages, resumable from the ledger

    @Test func cancellingBetweenTwoMessagesLeavesOnlyCompleteFilesResumableFromTheLedger() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Prima", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                    dateReceived: Date(timeIntervalSince1970: 1000),
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                ),
                .init(
                    rowID: 2, subject: "Seconda", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 2000),
                    dateReceived: Date(timeIntervalSince1970: 2000),
                    emlxBody: EmailFixtureCorpus.completeMessageRFC822
                        .replacingOccurrences(of: "abc123@rossi-spa.it", with: "def456@rossi-spa.it")
                ),
            ]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 2, messageID: "<def456@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000)),
                row(rowID: 1, messageID: "<abc123@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000)),
            ],
            onDisk: [], settings: .default
        )

        let syncTask = Task { try await engine.sync(request) }
        for await progress in await engine.progressStream() where progress.completed == 1 {
            await engine.cancel()
            break
        }
        let outcome = try await syncTask.value

        #expect(outcome.cancelled, "cancel() was called after the first message finished")
        #expect(outcome.writtenFiles.count == 1, "only the message before the cancellation boundary is written")
        #expect(Self.mdFiles(under: vaultRoot).count == 1, "exactly one complete .md file, nothing partial")

        // No temp artefact from an interrupted atomic write is left anywhere in the vault.
        let everyFile = (FileManager.default.enumerator(at: vaultRoot, includingPropertiesForKeys: nil)?
            .allObjects as? [URL]) ?? []
        #expect(!everyFile.contains { $0.lastPathComponent.contains(".tmp") })
    }

    // MARK: R-09 - `.eml` retention, and never for a pending message (ADR §D18)

    @Test func writesEmlBesideTheNoteAndReferencesItWhenRetentionIsOn() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.keepOriginalEML = true
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        let emailDir = vaultRoot.appending(path: "\(Self.praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let mdName = names.first { $0.hasSuffix(".md") }
        let baseName = mdName.map { ($0 as NSString).deletingPathExtension }

        #expect(names.contains { $0.hasSuffix(".eml") }, "no .eml was written")
        if let mdName, let baseName {
            let text = try? String(contentsOf: emailDir.appending(path: mdName), encoding: .utf8)
            #expect(text?.contains("pergamenum-mail-original: \"\(baseName).eml\"") == true)
        } else {
            Issue.record("no .md file was written at all")
        }
    }

    @Test func writesNoEmlWhenRetentionIsOff() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.keepOriginalEML = false
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        let emailDir = vaultRoot.appending(path: "\(Self.praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        #expect(!names.contains { $0.hasSuffix(".eml") }, "retention is off; no .eml must exist")
    }

    @Test func neverWritesAnEmlForAPendingMessageEvenWithRetentionOn() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta (corpo in arrivo)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.headersOnlyMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.keepOriginalEML = true
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<pending123@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        let outcome = try await engine.sync(request)

        #expect(outcome.writtenFiles.contains { $0.hasSuffix(".md") }, "the pending .md itself must still be written")
        #expect(!outcome.writtenFiles.contains { $0.hasSuffix(".eml") }, "§D18: no complete RFC 822 bytes exist yet")
    }

    // MARK: R-10 - attachment naming, SHA-256 linking, collision, threshold, inline images

    @Test func attachmentIsCopiedAsDateUnderscoreNameAndAnIdenticalSha256IsLinkedNotCopied() async throws {
        // PDF-shaped bytes (Tests/EmailFixtureCorpus.swift, Task 2, ADR-0040 §D2): plain
        // prose named `.pdf` would fail `AttachmentIntegrity`'s check once Task 4 wires it
        // in, turning this SHA-256-linking test red for a reason unrelated to its point.
        let bytes = EmailFixtureCorpus.pdfBytes(pages: 1)
        let messageA = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "msgA@rossi-spa.it", attachmentFilename: "offerta.pdf", attachmentBytes: bytes
        )
        let messageB = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "msgB@rossi-spa.it", attachmentFilename: "offerta.pdf", attachmentBytes: bytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Con allegato A", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                    dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: messageA
                ),
                .init(
                    rowID: 2, subject: "Con allegato B", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_171),
                    dateReceived: Date(timeIntervalSince1970: 1_781_093_171), emlxBody: messageB
                ),
            ]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<msgA@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
                row(rowID: 2, messageID: "<msgB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_171)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Self.allegatiFiles(under: vaultRoot)
        #expect(files == ["20260610_offerta.pdf"], "identical content must produce exactly one copy, linked twice")
        // PG-123: the copy is a download as far as Gatekeeper is concerned.
        let copy = vaultRoot.appending(path: "\(Self.praticaFolder)/allegati/20260610_offerta.pdf", directoryHint: .notDirectory)
        #expect(AttachmentQuarantine.isApplied(to: copy), "every attachment placed in allegati/ carries com.apple.quarantine")
    }

    @Test func aDifferentContentAttachmentWithTheSameNameCollidesToDash2() async throws {
        // PDF-shaped bytes, one page count each so the two attachments are genuinely
        // different content (Tests/EmailFixtureCorpus.swift, Task 2, ADR-0040 §D2).
        let messageA = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "msgA@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: EmailFixtureCorpus.pdfBytes(pages: 1)
        )
        let messageB = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "msgB@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: EmailFixtureCorpus.pdfBytes(pages: 2)
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Con allegato A", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                    dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: messageA
                ),
                .init(
                    rowID: 2, subject: "Con allegato B", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_171),
                    dateReceived: Date(timeIntervalSince1970: 1_781_093_171), emlxBody: messageB
                ),
            ]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<msgA@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
                row(rowID: 2, messageID: "<msgB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_171)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Self.allegatiFiles(under: vaultRoot)
        #expect(files == ["20260610_offerta-2.pdf", "20260610_offerta.pdf"])
    }

    @Test func anAttachmentOverTheThresholdIsRecordedWithoutBeingCopied() async throws {
        let bigBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024) // 2 MB
        let message = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "big@rossi-spa.it", attachmentFilename: "disegno-staffa.dwg", attachmentBytes: bigBytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Disegno grande", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1 // the 2 MB attachment is over this
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<big@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty, "an over-threshold attachment must never be copied")

        // Coordinator follow-up (closes the gap the original Task 4 report flagged
        // instead of guessing at): the over-threshold attachment still needs a home in
        // the message file's frontmatter (SPEC "Edge cases": `{ name, size, storePath }`,
        // declared as `MessageDocument.StoreReference`). The stub records nothing, so
        // this half stays red until the coder wires `PraticaSyncEngine` to append one
        // `StoreReference` per over-threshold attachment.
        let emailDir = vaultRoot.appending(path: "\(Self.praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let doc = names.first { $0.hasSuffix(".md") }
            .flatMap { try? String(contentsOf: emailDir.appending(path: $0), encoding: .utf8) }
            .flatMap(MessageDocument.parse)
        let reference = doc?.frontmatter.storeReferences.first
        #expect(reference?.name == "disegno-staffa.dwg")
        #expect((reference?.size ?? 0) > 1024 * 1024, "the recorded size must be the real over-threshold size")
    }

    @Test func anInlineImageIsDroppedOnlyWhenBothLightAndSmallElseSavedAndEmbedded() async throws {
        // Small-in-both: a genuine tiny logo - dropped, matching the pre-amendment case.
        let logoImage = EmailFixtureCorpus.solidColorPNG(width: 32, height: 32)
        // Light-in-bytes-but-real-dimensions: a solid-fill PNG compresses tiny regardless of
        // pixel size - this is the actual regression fixture, a stand-in for a real screenshot
        // or photo that happens to compress well under 50 KB.
        let screenshotImage = EmailFixtureCorpus.solidColorPNG(width: 800, height: 600)
        // Heavy regardless of dimensions: the pre-amendment "kept" case, unchanged. Must be a
        // real, ImageIO-decodable PNG (`AttachmentIntegrity` now gates the write on signature +
        // `IEND` before size is ever considered) that still lands over the weight threshold -
        // `solidColorPNG` compresses too well at any dimension to reach that, so this uses noisy,
        // low-correlation pixel data deflate cannot shrink.
        let heavyImage = EmailFixtureCorpus.noisyPNG(width: 200, height: 200)
        // Undecodable and light: the safe-fallback path - never dropped on a guess. A real PNG
        // signature and a literal `IEND` inside the tail window make `AttachmentIntegrity` call
        // this `.usable`, but the bytes between them are not a valid IHDR/IDAT chunk stream, so
        // `CGImageSourceCopyPropertiesAtIndex` cannot read pixel dimensions from it and
        // `InlineImageClassifier.isDecorative` falls through to its safe "keep it" default.
        let undecodableImage: Data = {
            var bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            bytes.append(Data("not a real IHDR chunk, garbage ImageIO cannot parse as PNG structure".utf8))
            bytes.append(Data("IEND".utf8))
            return bytes
        }()

        let messages: [(id: String, contentID: String, filename: String, bytes: Data)] = [
            ("logo@rossi-spa.it", "logo", "logo.png", logoImage),
            ("screenshot@rossi-spa.it", "screenshot", "screenshot.png", screenshotImage),
            ("heavy@rossi-spa.it", "heavy", "heavy.png", heavyImage),
            ("undecodable@rossi-spa.it", "undecodable", "undecodable.png", undecodableImage),
        ]
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: messages.enumerated().map { index, message in
                .init(
                    rowID: index + 1, subject: "Immagine \(message.contentID)",
                    senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: Double(1000 * (index + 1))),
                    dateReceived: Date(timeIntervalSince1970: Double(1000 * (index + 1))),
                    emlxBody: EmailFixtureCorpus.singleInlineImageMessageRFC822(
                        messageID: message.id, contentID: message.contentID,
                        imageBytes: message.bytes, filename: message.filename
                    )
                )
            }
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: messages.enumerated().map { index, message in
                row(
                    rowID: index + 1, messageID: "<\(message.id)>",
                    date: Date(timeIntervalSince1970: Double(1000 * (index + 1)))
                )
            },
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Self.allegatiFiles(under: vaultRoot)
        #expect(!files.contains { $0.contains("logo") }, "an image small in both bytes and pixels is dropped")
        #expect(
            files.contains { $0.contains("screenshot") },
            "a light-but-real-dimensions image must be kept, not mistaken for a logo"
        )
        #expect(files.contains { $0.contains("heavy") }, "an over-50-KB inline image must still be kept")
        #expect(
            files.contains { $0.contains("undecodable") },
            "unreadable dimensions must never be treated as decorative"
        )
    }

    // MARK: Task 4 (R-01, R-02, R-04, R-12) - the write path refuses bytes that are
    // not the file, and a partly-ready message is still `.complete`
    //
    // `AttachmentIntegrity.verdict` (Task 1) and the pending-attachment codec
    // (`MessageDocument.attachmentEntry(pending:)` / `.isPendingAttachmentEntry` /
    // `.linkedAttachmentNames` / `.pendingAttachmentNames`, Task 3) already exist;
    // `PraticaSyncEngine.prepare`'s part loop does not consult either one yet (ADR-0040
    // §D2, §D3) - every test below is red today for that behavioural reason, not for a
    // missing symbol, and stays red until Task 4's engine change lands.

    @Test func aZeroByteAttachmentIsNeverPlacedAndBecomesAPendingEntry() async throws {
        let message = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "zerobyte@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato vuoto", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<zerobyte@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty, "a zero-byte attachment must never be copied (R-01)")
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.body == .complete, "a partly-ready message is still .complete (R-04)")
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
    }

    @Test func aTruncatedPDFAttachmentIsNeverPlacedAndBecomesAPendingEntry() async throws {
        let message = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "truncated@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato troncato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<truncated@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty, "a truncated PDF must never be copied (R-02)")
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.body == .complete)
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
    }

    @Test func anUnknownFormatAttachmentIsPlacedNormallyRegardlessOfItsBytes() async throws {
        // R-03's consequence at the engine level: `.dwg` has no signature entry, so an
        // attachment this app cannot describe is never rejected for want of one - it is
        // judged on emptiness alone, and 100 bytes of 0x41 is not empty.
        let message = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "unknownformat@rossi-spa.it", attachmentFilename: "disegno.dwg",
            attachmentBytes: Data(repeating: 0x41, count: 100)
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Disegno", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<unknownformat@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot) == ["20260610_disegno.dwg"])
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_disegno.dwg"])
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
    }

    @Test func aMixedMessageWithOneValidAndOneTruncatedAttachmentIsStillComplete() async throws {
        let message = EmailFixtureCorpus.mixedValidAndTruncatedAttachmentsRFC822(messageID: "mixed@rossi-spa.it")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta con due allegati", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<mixed@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot) == ["20260610_valido.pdf"], "R-04: the good half is still placed")
        #expect(Self.mdFiles(under: vaultRoot).count == 1)
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.body == .complete)
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_valido.pdf"])
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_troncato.pdf"])
    }

    // ADR-0040 R-12's regression: before this fix, two zero-byte attachments hashed
    // alike (both empty `Data`), so the second was silently deduplicated onto the
    // first one's placed name - two different missing files were reported as one.
    @Test func twoDifferentMessagesWithADifferentZeroByteAttachmentEachGetTwoDistinctPendingEntriesAndNoFile() async throws {
        let messageA = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "zeroA@rossi-spa.it", filename: "a.pdf"
        )
        let messageB = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "zeroB@rossi-spa.it", filename: "b.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Allegato vuoto A", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                    dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: messageA
                ),
                .init(
                    rowID: 2, subject: "Allegato vuoto B", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_171),
                    dateReceived: Date(timeIntervalSince1970: 1_781_093_171), emlxBody: messageB
                ),
            ]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<zeroA@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
                row(rowID: 2, messageID: "<zeroB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_171)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty, "R-12: no shared file must ever be produced")
        let docs = try Self.messageDocuments(under: vaultRoot)
        #expect(docs.count == 2)
        let pendingNames = Set(docs.flatMap(\.frontmatter.pendingAttachmentNames))
        #expect(
            pendingNames == ["20260610_a.pdf", "20260610_b.pdf"],
            "each message must name its own pending attachment, never share one"
        )
    }

    @Test func aZeroByteInlineImageIsNeverPlacedAndLeavesNoDanglingCidOrEmbedReference() async throws {
        let message = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "zeroinline@rossi-spa.it", contentID: "zeroinline", imageBytes: Data(), filename: "logo.png"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine vuota", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<zeroinline@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty, "a zero-byte inline image must never be copied")
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(!doc.newText.contains("cid:"), "a bare cid: reference must never survive into the body")
        #expect(!doc.newText.contains("![["), "no embed can point at a file that was never placed")
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
        // ADR-0042 §D1: an inline image never becomes a pending *attachment* - the
        // body still mentions it (`vedi immagine cid:zeroinline`), so it gets a
        // placeholder and a `pergamenum-mail-inline-pending` entry instead (R-01, R-02).
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingInlineImages == ["zeroinline"])
        #expect(doc.newText.contains(MessageInlineImage.placeholder))
    }

    // MARK: - ADR-0042 (Pratiche inline image placeholders) - Task 4, R-01, R-02, R-03, R-08

    @Test func anHTMLMessageWithOneMissingInlineImageGetsExactlyOnePlaceholderAndOnePlacedFile() async throws {
        let placedBytes = EmailFixtureCorpus.solidColorPNG(width: 800, height: 600)
        let message = EmailFixtureCorpus.htmlInlineImagesMessageRFC822(
            messageID: "htmltwo@rossi-spa.it",
            images: [
                EmailFixtureCorpus.InlineImageSpec(contentID: "missing", filename: "missing.png", bytes: Data()),
                EmailFixtureCorpus.InlineImageSpec(contentID: "placed", filename: "placed.png", bytes: placedBytes),
            ]
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Newsletter", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<htmltwo@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "an inline image is never a pending attachment")
        #expect(doc.frontmatter.pendingInlineImages == ["missing"])
        #expect(
            occurrenceCount(of: MessageInlineImage.placeholder, in: doc.newText) == 1,
            "exactly one placeholder, for the image with no bytes"
        )
        #expect(doc.newText.contains("![["), "the image with bytes is embedded, not left pending")
        #expect(Self.allegatiFiles(under: vaultRoot).count == 1, "only the placed image reaches allegati/")
    }

    @Test func anHTMLMessageWhoseChosenPlainTextAlternativeNeverMentionsTheImagesGetsNoPlaceholderAtAll() async throws {
        // The reported defect: `bodyText` prefers a non-empty `text/plain` part, and a
        // real newsletter's plain-text alternative frequently never mentions the ids
        // the HTML alternative's `cid:` images carry - R-03 says that must produce no
        // placeholder and no pending state at all, not a phantom "In attesa" pill.
        let placedBytes = EmailFixtureCorpus.solidColorPNG(width: 800, height: 600)
        let message = EmailFixtureCorpus.htmlInlineImagesWithPlainAlternativeRFC822(
            messageID: "htmlplain@rossi-spa.it",
            images: [
                EmailFixtureCorpus.InlineImageSpec(contentID: "missing", filename: "missing.png", bytes: Data()),
                EmailFixtureCorpus.InlineImageSpec(contentID: "placed", filename: "placed.png", bytes: placedBytes),
            ]
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Newsletter", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<htmlplain@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingInlineImages.isEmpty, "R-03: no id the body never mentions gets pending state")
        #expect(!doc.newText.contains(MessageInlineImage.placeholder))
        #expect(Self.allegatiFiles(under: vaultRoot).count == 1, "the image with bytes is still placed regardless")
    }

    @Test func aDecorativeInlineImageWithBytesLeavesNoPlaceholderNoEntryAndNoMarkdownRemnant() async throws {
        // The pre-existing bug this amendment also fixes (§D8/R-08): the old code
        // stripped only the bare `cid:` reference, leaving `![Logo]()` behind.
        let logoImage = EmailFixtureCorpus.solidColorPNG(width: 32, height: 32)
        let message = EmailFixtureCorpus.htmlInlineImagesMessageRFC822(
            messageID: "decorative@rossi-spa.it",
            images: [EmailFixtureCorpus.InlineImageSpec(contentID: "logo", filename: "logo.png", bytes: logoImage)]
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Firma", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<decorative@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingInlineImages.isEmpty)
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
        #expect(!doc.newText.contains(MessageInlineImage.placeholder))
        #expect(!doc.newText.contains("!["), "no `![Logo]()` remnant, not even an empty embed construct")
        #expect(!doc.newText.contains("cid:"))
        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty)
    }

    @Test func aReplyWithThreeInlineImagesRecordsPendingInlineImagesInFileOrderNotMIMEOrder() async throws {
        // ADR-0042 §D6: the fixture's MIME order is deliberately reversed against
        // reading order (signature part first, new-text part last) - this fails if
        // the code ever resolves deferral tokens before `QuoteSplitter.split`, using
        // decode ordinal order instead of the note's own render order.
        let message = EmailFixtureCorpus.signatureInlineImagesReplyRFC822(
            messageID: "reply@rossi-spa.it",
            newTextImage: EmailFixtureCorpus.InlineImageSpec(contentID: "newtext", bytes: Data()),
            quotedImage: EmailFixtureCorpus.InlineImageSpec(contentID: "quoted", bytes: Data()),
            signatureImage: EmailFixtureCorpus.InlineImageSpec(contentID: "signature", bytes: Data())
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Re: Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<reply@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingInlineImages == ["newtext", "quoted", "signature"])
        #expect(occurrenceCount(of: MessageInlineImage.placeholder, in: doc.newText) == 1)
        #expect(occurrenceCount(of: MessageInlineImage.placeholder, in: doc.quotedHistory ?? "") == 1)
        #expect(occurrenceCount(of: MessageInlineImage.placeholder, in: doc.signature ?? "") == 1)
    }

    @Test func aRealAttachmentPendingAndAnInlineImagePendingCoexistInDistinctLists() async throws {
        // One message, both kinds of "Mail hasn't downloaded this yet" at once - a
        // zero-byte ordinary attachment and a zero-byte inline image the plain-text
        // body mentions - to prove the two pending lists never merge (R-01, R-12).
        let boundary = "----=_Pergamenum_MixedPending_Boundary"
        let message = """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta con allegato e immagine in attesa\r
        Message-Id: <mixedpending@rossi-spa.it>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato il file e vedi immagine cid:innerimg\r
        --\(boundary)\r
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="offerta.pdf"\r
        \r
        \r
        --\(boundary)\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <innerimg>\r
        Content-Disposition: inline; filename="inner.png"\r
        \r
        \r
        --\(boundary)--\r
        """
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine in attesa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<mixedpending@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.pendingInlineImages == ["innerimg"])
        #expect(doc.newText.contains(MessageInlineImage.placeholder))
    }

    // MARK: Task 5 (R-07) - the over-threshold path is checked too, before the
    // reference is recorded
    //
    // ADR-0040 finding 3: the store-reference branch is chosen by `bytes.count >
    // thresholdBytes(...)`, so a zero-byte part can never reach it - these tests need
    // genuinely large, and for the second one genuinely wrong, bytes.

    @Test func anOverThresholdValidPDFStillGetsAStoreReferenceAndNoFile() async throws {
        // Guards the case Task 5 must NOT break:
        // `anAttachmentOverTheThresholdIsRecordedWithoutBeingCopied` above already
        // proves this for a `.dwg` fixture, which has no entry in
        // `AttachmentIntegrity`'s table and would pass even with the check wired in
        // wrong. This repeats the guarantee with a `.pdf` name specifically so the
        // signature check is actually exercised by a format it knows.
        var bytes = Data("%PDF-1.7\n".utf8)
        bytes.append(Data(repeating: 0x41, count: 2 * 1024 * 1024))
        bytes.append(Data("\n%%EOF\n".utf8))
        let message = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "bigvalid@rossi-spa.it", attachmentFilename: "offerta-grande.pdf", attachmentBytes: bytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta grande", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<bigvalid@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.map(\.name) == ["offerta-grande.pdf"])
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
    }

    @Test func anOverThresholdAttachmentWithWrongBytesGetsNoStoreReferenceButAPendingEntry() async throws {
        // R-07: large, present, and wrong - exactly the case a guard on the copy
        // branch alone (ADR-0040 finding 3) would let straight through unchanged.
        let badBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        let message = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "bigwrong@rossi-spa.it", attachmentFilename: "offerta-falsa.pdf", attachmentBytes: badBytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta falsa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<bigwrong@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.isEmpty, "a reference is a promise the file is there - R-07")
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta-falsa.pdf"])
    }

    // R-07's third case, from the plan verbatim: "reached through Task 6's retry, so
    // this assertion may have to land in Task 6's batch if Task 5 ships first. Say so
    // in the commit message rather than weakening it." Written here per that
    // instruction - NOT weakened, NOT omitted. It needs more than Task 5 alone
    // provides: `prepare`'s existing-file guard (`:356-364`) only lets a file be
    // rewritten when it is `.pending` (or an explicit «Rigenera») - a `.complete`
    // message with only a pending *attachment* (this case, per R-04's own rule) is not
    // revisited by that guard until Task 6 adds its clause (ADR-0040 §D5). Expect this
    // test to stay red after Task 5 alone and to go green only once Task 6 lands - if
    // it is still red after Task 6 too, that is a real defect, not this test being
    // wrong.
    @Test func anOverThresholdAttachmentThatLaterBecomesValidGetsAStoreReferenceAndLosesItsPendingEntry() async throws {
        let badBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024)
        let firstMessage = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "bigretry@rossi-spa.it", attachmentFilename: "offerta-grande.pdf", attachmentBytes: badBytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta grande", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        // Reused unchanged for both syncs, the same idiom
        // `aHeadersOnlyMessageIsWrittenPendingAndRegeneratedOnceTheBodyArrives` uses
        // above: `onDisk` stays empty both times, so the second sync reaches this
        // message through `PraticaSyncPlan.workItems` exactly as the first one did,
        // and whether it is actually rewritten is entirely `prepare`'s guard's call.
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<bigretry@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        var goodBytes = Data("%PDF-1.7\n".utf8)
        goodBytes.append(Data(repeating: 0x41, count: 2 * 1024 * 1024))
        goodBytes.append(Data("\n%%EOF\n".utf8))
        let secondMessage = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "bigretry@rossi-spa.it", attachmentFilename: "offerta-grande.pdf", attachmentBytes: goodBytes
        )
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta grande", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )],
            in: fixture.root
        )

        _ = try await engine.sync(request)

        let doc = try Self.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.map(\.name) == ["offerta-grande.pdf"], "R-07's retry, via Task 6")
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "the pending entry must go once bytes resolve")
        #expect(Self.allegatiFiles(under: vaultRoot).isEmpty, "still over threshold - never copied")
    }

    // MARK: R-15 - pending body, and the one file a later sync rewrites unasked

    @Test func aHeadersOnlyMessageIsWrittenPendingAndRegeneratedOnceTheBodyArrives() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta (corpo in arrivo)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.headersOnlyMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<pending123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1, "the pending message is still written once, as a placeholder")

        let emailDir = vaultRoot.appending(path: "\(Self.praticaFolder)/email", directoryHint: .isDirectory)
        let firstNames = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let firstDoc = firstNames.first { $0.hasSuffix(".md") }
            .flatMap { try? String(contentsOf: emailDir.appending(path: $0), encoding: .utf8) }
            .flatMap(MessageDocument.parse)
        #expect(firstDoc?.frontmatter.body == .pending)
        #expect(firstDoc?.newText.isEmpty == false, "a placeholder body, never an empty one")

        // The body has since arrived: the same ROWID's `.emlx` is rewritten in place.
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: "pending123@rossi-spa.it")
            )],
            in: fixture.root
        )

        let secondOutcome = try await engine.sync(request)
        #expect(secondOutcome.regeneratedPendingFiles.count == 1, "the pending file is rewritten unasked")

        let secondNames = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let secondDoc = secondNames.first { $0.hasSuffix(".md") }
            .flatMap { try? String(contentsOf: emailDir.appending(path: $0), encoding: .utf8) }
            .flatMap(MessageDocument.parse)
        #expect(secondDoc?.frontmatter.body == .complete, "the body arrived; the file is no longer pending")
    }

    // MARK: R-16 - a vanished row keeps its file, loses its link, is never deleted

    @Test func aMessageWhoseRowDisappearsKeepsItsFilesLosesItsLinkAndIsNeverDeleted() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        let firstRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(firstRequest)

        let emailDir = vaultRoot.appending(path: "\(Self.praticaFolder)/email", directoryHint: .isDirectory)
        let firstNames = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let mdName = try #require(firstNames.first { $0.hasSuffix(".md") })
        let mdURL = emailDir.appending(path: mdName)

        // Second sync: the message no longer surfaces among this run's candidates -
        // its row is gone from Mail - but the ledger still remembers importing it. A
        // fresh, separate fixture with no rows at all (rather than rebuilding the same
        // one) is what actually makes `reader.row(forMessageID:)` answer
        // `.notResolvableFromIndex` here: `PraticaSyncEngine.openedReader()` caches its
        // `MailStoreReader` for the actor's lifetime, so a rebuild "in place" at the
        // first fixture's own path would be invisible to this already-open engine.
        let goneFixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let secondEngine = Self.makeEngine(mailStoreURL: goneFixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [], onDisk: ["<abc123@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)

        #expect(secondOutcome.noLongerInMail == ["<abc123@rossi-spa.it>"])
        #expect(FileManager.default.fileExists(atPath: mdURL.path(percentEncoded: false)), "the file is kept, never deleted")
    }

    // MARK: §D23.1 - the bridge triple is recorded at the write boundary

    // ADR §D23, plan docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 1
    // - `SyncOutcome.bridge` is declared by this batch's tester (ADR-0155 §D1);
    // `commit` does not append to it yet, so `outcome.bridge` stays empty regardless
    // of what was imported. Both tests below are red until the coder wires the
    // `PreparedMessage.rowID`/`.conversationID` fields and the `commit`-time append
    // (§D23.1's own two numbered steps).
    @Test func recordsOneBridgeEntryPerImportedMessageAndNoneForAMessageWithNoConversationID() async throws {
        let messageWithConversation = EmailFixtureCorpus.completeMessageRFC822
        let messageWithoutConversation = EmailFixtureCorpus.completeMessageRFC822
            .replacingOccurrences(of: "abc123@rossi-spa.it", with: "noconv@rossi-spa.it")
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Con conversazione", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                    dateReceived: Date(timeIntervalSince1970: 1000), emlxBody: messageWithConversation
                ),
                .init(
                    rowID: 2, subject: "Senza conversazione", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 2000),
                    dateReceived: Date(timeIntervalSince1970: 2000), emlxBody: messageWithoutConversation
                ),
            ]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var withConversation = row(rowID: 1, messageID: "<abc123@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000))
        withConversation.conversationID = 112_409
        var withoutConversation = row(rowID: 2, messageID: "<noconv@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000))
        withoutConversation.conversationID = nil

        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [withoutConversation, withConversation],
            onDisk: [], settings: .default
        )
        let outcome = try await engine.sync(request)

        #expect(outcome.writtenFiles.count == 2, "both messages are imported regardless of the bridge")
        #expect(outcome.bridge.count == 1, "only the message with a conversation_id gets a bridge entry")
        let entry = try #require(outcome.bridge.first)
        #expect(entry.messageID == "<abc123@rossi-spa.it>")
        #expect(entry.rowID == 1)
        #expect(entry.conversationID == 112_409)
    }

    @Test func aRegenerationOfAPendingMessageRecordsItsBridgeTripleToo() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta (corpo in arrivo)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.headersOnlyMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<pending123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.bridge.count == 1, "the pending placeholder still gets a bridge triple - §D23.1 is 'outside the isRegeneration branch'")

        // The body has since arrived under a NEW ROWID (Mail's own reindex): the
        // regeneration must replace the triple, not merely add to it.
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 99, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1000), dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: "pending123@rossi-spa.it")
            )],
            in: fixture.root
        )
        var regenerated = row(rowID: 99, messageID: "<pending123@rossi-spa.it>")
        regenerated.conversationID = 112_409
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [regenerated], onDisk: ["<pending123@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await engine.sync(secondRequest)

        #expect(secondOutcome.regeneratedPendingFiles.count == 1)
        #expect(secondOutcome.bridge.count == 1, "the regeneration's own run records exactly its own triple")
        #expect(secondOutcome.bridge.first?.rowID == 99, "the stale ROWID 1 is what this regeneration corrects")
    }

    // MARK: Task 6 (ADR-0040 §D4, §D5, §D6) - every sync revisits a message that is
    // still waiting, and amends one line when it resolves (R-05, R-06)
    //
    // `PraticaSyncEngine.FolderContext.ExistingMessage.text` (§D6 - needed to compare a
    // patch against the file already read) does not exist yet, and neither does
    // `SyncOutcome.resolvedAttachmentFiles`/`.attachmentProblems` (§D10). Most tests
    // below are red because they fail to COMPILE against the current
    // `PraticaSyncEngine.swift`, not merely because the logic is wrong - this batch's
    // tester does not touch `Sources/` at all (per this dispatch's explicit scope); the
    // coder both declares those symbols and fills in Task 6's guard clause, selection
    // clause and write-mode fork.

    private static func modificationDate(of url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return try #require(attributes[.modificationDate] as? Date)
    }

    /// The single note this suite's fixtures produce, and its raw file URL - unlike
    /// `onlyMessageDocument`, this keeps the text as written so a test can compare
    /// byte-for-byte rather than through `MessageDocument.parse`'s round trip.
    private static func onlyNoteURLAndText(under vaultRoot: URL) throws -> (url: URL, text: String) {
        let emailDir = vaultRoot.appending(path: "\(praticaFolder)/email", directoryHint: .isDirectory)
        let name = try #require(Self.mdFiles(under: vaultRoot).first, "expected exactly one message note")
        let url = emailDir.appending(path: name, directoryHint: .notDirectory)
        return (url, try String(contentsOf: url, encoding: .utf8))
    }

    /// `text` with its `pergamenum-mail-attachments:` line removed - the one line §D4's
    /// patch mode may ever touch. Two texts equal after this strip differ, if at all,
    /// only on that one line.
    private static func removingAttachmentsLine(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("\(MessageDocument.attachmentsKey):") }
            .joined(separator: "\n")
    }

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

    @Test func aTruncatedAttachmentIsRetriedAtNoCostWhenNothingHasChanged() async throws {
        let message = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "nocost@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato troncato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<nocost@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, firstText) = try Self.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Self.modificationDate(of: noteURL)

        let secondOutcome = try await engine.sync(request)

        let secondText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(secondText == firstText, "an unresolved retry must not touch a single byte of the note (§D6)")
        #expect(
            try Self.modificationDate(of: noteURL) == firstModified,
            "an unresolved retry must not rewrite the file at all, not even to the same bytes"
        )
        #expect(secondOutcome.resolvedAttachmentFiles.isEmpty, "nothing resolved - no-op per §D6")
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty, "a patch is never counted as a full regeneration")
    }

    @Test func aResolvedAttachmentPatchesTheAttachmentsLineAndPreservesAHandEditedBody() async throws {
        let firstMessage = EmailFixtureCorpus.truncatedAttachmentMessageRFC822(
            messageID: "resolve@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato troncato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<resolve@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Self.onlyNoteURLAndText(under: vaultRoot)
        // §D4's whole reason to exist: a person annotates the note between two syncs.
        let handEditedText = originalText + "\n\nAggiunto a mano dopo la prima sincronizzazione.\n"
        try Data(handEditedText.utf8).write(to: noteURL, options: .atomic)

        let secondMessage = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "resolve@rossi-spa.it", attachmentFilename: "offerta.pdf",
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

        let secondOutcome = try await engine.sync(request)

        let secondText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(
            Self.removingAttachmentsLine(secondText) == Self.removingAttachmentsLine(handEditedText),
            "every byte but the attachments line must survive, including the hand-edited prose (R-06)"
        )
        #expect(
            secondText.contains("Aggiunto a mano dopo la prima sincronizzazione."),
            "the hand edit itself must survive the patch"
        )

        let doc = try #require(MessageDocument.parse(secondText))
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "the pending entry must be gone once bytes resolve")
        #expect(Self.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"])
        #expect(secondOutcome.resolvedAttachmentFiles.count == 1, "one note amended in one line")
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty, "a patch is never a full regeneration")
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
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<partial@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc1 = try Self.onlyMessageDocument(under: vaultRoot)
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

        let doc2 = try Self.onlyMessageDocument(under: vaultRoot)
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
            Set(Self.allegatiFiles(under: vaultRoot))
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
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<nogrow@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1, "the first sync writes the pending placeholder once")
        let (noteURL, _) = try Self.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Self.modificationDate(of: noteURL)

        for run in 2...10 {
            let outcome = try await engine.sync(request)
            #expect(outcome.writtenFiles.isEmpty, "run \(run) must write nothing - the attachment never resolves")
            #expect(outcome.resolvedAttachmentFiles.isEmpty, "run \(run) must resolve nothing")
            #expect(outcome.regeneratedPendingFiles.isEmpty, "run \(run) must regenerate nothing")
        }

        #expect(
            try Self.modificationDate(of: noteURL) == firstModified,
            "ten unresolved retries must leave the file exactly as the first sync wrote it - no leak (R-05)"
        )
    }

    // MARK: - ADR-0042 (Pratiche inline image placeholders) - Task 5, R-04, R-06, R-07

    @Test func aResolvedInlineImagePatchesItsPlaceholderAndPreservesAHandEditedBody() async throws {
        let firstMessage = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "inlineresolve@rossi-spa.it", contentID: "inlineresolve",
            imageBytes: Data(), filename: "logo.png"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine in attesa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<inlineresolve@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Self.onlyNoteURLAndText(under: vaultRoot)
        #expect(originalText.contains(MessageInlineImage.placeholder))
        // §D8's whole reason to exist: a person annotates the note between two syncs.
        let handEditedText = originalText + "\n\nAggiunto a mano dopo la prima sincronizzazione.\n"
        try Data(handEditedText.utf8).write(to: noteURL, options: .atomic)

        let realBytes = EmailFixtureCorpus.solidColorPNG(width: 800, height: 600)
        let secondMessage = EmailFixtureCorpus.fillingInlineImageBytes(
            in: firstMessage, contentID: "inlineresolve", with: realBytes
        )
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine in attesa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )],
            in: fixture.root
        )

        let secondOutcome = try await engine.sync(request)

        let secondText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(!secondText.contains(MessageInlineImage.placeholder), "the placeholder becomes the real embed")
        #expect(secondText.contains("![["), "the resolved image is embedded, not merely linked")
        #expect(
            secondText.contains("Aggiunto a mano dopo la prima sincronizzazione."),
            "the hand edit must survive the patch"
        )

        let doc = try #require(MessageDocument.parse(secondText))
        #expect(doc.frontmatter.pendingInlineImages.isEmpty)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(Self.allegatiFiles(under: vaultRoot).count == 1)
        #expect(secondOutcome.resolvedAttachmentFiles.count == 1, "one note amended, in place")
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty, "a patch is never a full regeneration")
    }

    @Test func aCountMismatchLinksTheResolvedImageAsAnAttachmentInsteadOfTouchingAnyPlaceholder() async throws {
        let firstMessage = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "mismatch@rossi-spa.it", contentID: "mismatch",
            imageBytes: Data(), filename: "logo.png"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine in attesa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: firstMessage
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<mismatch@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Self.onlyNoteURLAndText(under: vaultRoot)
        #expect(originalText.contains(MessageInlineImage.placeholder))
        // A person deletes the placeholder by hand - the file's placeholder count (0)
        // no longer matches the recorded pending count (1), so ADR-0042 §D8 forbids
        // touching any placeholder: the resolved image must not land in the wrong
        // paragraph on a guess.
        let editedText = originalText.replacingOccurrences(of: MessageInlineImage.placeholder, with: "")
        try Data(editedText.utf8).write(to: noteURL, options: .atomic)

        let realBytes = EmailFixtureCorpus.solidColorPNG(width: 800, height: 600)
        let secondMessage = EmailFixtureCorpus.fillingInlineImageBytes(
            in: firstMessage, contentID: "mismatch", with: realBytes
        )
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine in attesa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: secondMessage
            )],
            in: fixture.root
        )

        _ = try await engine.sync(request)

        let secondText = try String(contentsOf: noteURL, encoding: .utf8)
        let doc = try #require(MessageDocument.parse(secondText))
        #expect(doc.frontmatter.pendingInlineImages.isEmpty, "resolved, even though it could not be placed")
        #expect(
            doc.frontmatter.linkedAttachmentNames.count == 1,
            "a count mismatch links the resolved image as an ordinary attachment instead of losing it"
        )
        #expect(Self.allegatiFiles(under: vaultRoot).count == 1)
    }

    @Test func tenConsecutiveSyncsOverANeverResolvingInlineImageWriteOnlyOnceAndNeverGrowAnyOutcomeArray() async throws {
        let message = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "inlinenogrow@rossi-spa.it", contentID: "inlinenogrow",
            imageBytes: Data(), filename: "logo.png"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine in attesa", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<inlinenogrow@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1)
        let (noteURL, _) = try Self.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Self.modificationDate(of: noteURL)

        for run in 2...10 {
            let outcome = try await engine.sync(request)
            #expect(outcome.writtenFiles.isEmpty, "run \(run) must write nothing - the image never resolves")
            #expect(outcome.resolvedAttachmentFiles.isEmpty, "run \(run) must resolve nothing")
        }

        #expect(
            try Self.modificationDate(of: noteURL) == firstModified,
            "ten unresolved retries must leave the file exactly as the first sync wrote it - the no-op rule (§D6)"
        )
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
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, _) = try Self.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Self.modificationDate(of: noteURL)

        let secondOutcome = try await engine.sync(request)

        #expect(secondOutcome.writtenFiles.isEmpty, "a .complete message with no pending attachment is never revisited")
        #expect(secondOutcome.resolvedAttachmentFiles.isEmpty)
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty)
        #expect(
            try Self.modificationDate(of: noteURL) == firstModified,
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
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<rigenera@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Self.onlyNoteURLAndText(under: vaultRoot)
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
    // `PraticaSyncEngine.FolderContext.corruptAttachmentNames` does not exist yet
    // (tester scope for this dispatch is `Tests/PraticaSyncTests.swift` only - no
    // stub is declared in `Sources/`, unlike this batch's usual ADR-0155 §D1
    // convention). Every test below is expected to fail to COMPILE against the
    // current `PraticaSyncEngine.swift`, not merely to assert something false; the
    // coder both declares the field and fills in the repair-and-resolve step.
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
        let vaultRoot = try Self.makeVaultRoot()
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
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        let outcome = try await engine.sync(request)

        #expect(
            Self.allegatiFiles(under: vaultRoot) == ["20260610_buono.pdf"],
            "the zero-byte file is gone from allegati/, the valid one stays (R-10, R-11)"
        )
        let bytesAfter = try Data(contentsOf:
            vaultRoot.appending(path: "\(Self.praticaFolder)/allegati/20260610_buono.pdf", directoryHint: .notDirectory))
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
        let vaultRoot = try Self.makeVaultRoot()
        let noteA = try Self.seedExistingMessage(
            under: vaultRoot, folder: Self.praticaFolder, messageID: "isoA@rossi-spa.it",
            linkedAttachmentNames: ["20260610_comune.pdf"], fileName: "20260610_1406_seed_a.md"
        )
        try Self.seedAllegatiFile(under: vaultRoot, folder: Self.praticaFolder, name: "20260610_comune.pdf", bytes: Data())

        let noteB = try Self.seedExistingMessage(
            under: vaultRoot, folder: Self.secondPraticaFolder, messageID: "isoB@bianchi-srl.it",
            linkedAttachmentNames: ["20260610_comune.pdf"], fileName: "20260610_1406_seed_b.md"
        )
        let validBytesB = EmailFixtureCorpus.pdfBytes(pages: 2)
        try Self.seedAllegatiFile(
            under: vaultRoot, folder: Self.secondPraticaFolder, name: "20260610_comune.pdf", bytes: validBytesB
        )

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        // Scoped to folder A only - `request.praticaFolder` is what `folderContext(of:)`
        // resolves `email/`/`allegati/` under; folder B is never scanned by this sync.
        let requestA = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        _ = try await engine.sync(requestA)

        #expect(
            Self.allegatiFiles(under: vaultRoot, folder: Self.praticaFolder).isEmpty,
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
        let vaultRoot = try Self.makeVaultRoot()
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
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<dedupB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let docA = try #require(MessageDocument.parse(String(contentsOf: noteA, encoding: .utf8)))
        #expect(docA.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"], "A's link is downgraded by the same run's repair pass")

        let documents = try Self.messageDocuments(under: vaultRoot)
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
        let vaultRoot = try Self.makeVaultRoot()
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
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<resolveinone@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(
            Self.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"],
            "the good bytes now sit at the same generated name"
        )
        let bytesAfter = try Data(contentsOf:
            vaultRoot.appending(path: "\(Self.praticaFolder)/allegati/20260610_offerta.pdf", directoryHint: .notDirectory))
        #expect(bytesAfter == realBytes, "the file on disk is the real one, not the trashed placeholder")
        let doc = try #require(MessageDocument.parse(String(contentsOf: noteURL, encoding: .utf8)))
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_offerta.pdf"])
        #expect(
            doc.frontmatter.pendingAttachmentNames.isEmpty,
            "a single sync both repairs the corrupt file and re-imports it, since Mail already has the bytes (§D7)"
        )
    }

    @Test func aSecondSyncAfterACompletedRepairFindsNothingLeftToRepair() async throws {
        let vaultRoot = try Self.makeVaultRoot()
        let noteURL = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "noop@rossi-spa.it",
            linkedAttachmentNames: ["20260610_buono.pdf", "20260610_cattivo.pdf"]
        )
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_buono.pdf", bytes: EmailFixtureCorpus.pdfBytes(pages: 1))
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_cattivo.pdf", bytes: Data())

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(), candidates: [], onDisk: [], settings: .default
        )
        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.resolvedAttachmentFiles.count == 1, "the first sync does the one repair there is to do")

        let textAfterFirstRepair = try String(contentsOf: noteURL, encoding: .utf8)
        let modifiedAfterFirstRepair = try Self.modificationDate(of: noteURL)

        let secondOutcome = try await engine.sync(request)

        #expect(secondOutcome.resolvedAttachmentFiles.isEmpty, "nothing left to repair - §D7.2's no-flag-needed claim, asserted not argued")
        #expect(secondOutcome.attachmentProblems.isEmpty)
        #expect(Self.allegatiFiles(under: vaultRoot) == ["20260610_buono.pdf"], "no further change to allegati/")
        #expect(
            try String(contentsOf: noteURL, encoding: .utf8) == textAfterFirstRepair,
            "the note must not be rewritten a second time"
        )
        #expect(
            try Self.modificationDate(of: noteURL) == modifiedAfterFirstRepair,
            "not even touched, not just written identically (§D6's no-op rule reused for the repair patch)"
        )
    }

    // §D7.3: `FileManager.trashItem` fails when it cannot remove the item from its
    // containing directory - a real POSIX seam on this test volume (verified by hand:
    // `chmod 555` on a directory blocks `rm` of a file inside it with "Permission
    // denied", the same unlink-requires-write-on-the-parent rule trashing ultimately
    // relies on), no coder-added seam needed.
    @Test func aTrashFailureLeavesTheFileAloneAndReportsTheProblemWithoutDowngradingTheLink() async throws {
        let vaultRoot = try Self.makeVaultRoot()
        let noteURL = try Self.seedExistingMessage(
            under: vaultRoot, messageID: "trashfail@rossi-spa.it",
            linkedAttachmentNames: ["20260610_cattivo.pdf"]
        )
        try Self.seedAllegatiFile(under: vaultRoot, name: "20260610_cattivo.pdf", bytes: Data())

        let allegatiDir = vaultRoot.appending(path: "\(Self.praticaFolder)/allegati", directoryHint: .isDirectory)
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
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(), candidates: [], onDisk: [], settings: .default
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

// MARK: - §D21 - «Rigenera» acquires the replacement before it destroys anything

// ADR §D21, plan docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 5 -
// `regenerationPreview`/`commitRegeneration` are declared-but-stubbed by this batch's
// tester (ADR-0155 §D1): both always throw `RegenerationFailure.rowNotFound`
// unconditionally, so every test below is red because the stub never resolves a row or
// writes anything, not because a symbol is missing.
@Suite struct PraticaRegenerationTests {
    private static func makeVaultRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-pratica-regen-vault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeEngine(mailStoreURL: URL, vaultRoot: URL) -> PraticaSyncEngine {
        PraticaSyncEngine(mailStoreURL: mailStoreURL, vaultRoot: vaultRoot) { text, relativePath in
            let url = vaultRoot.appending(path: relativePath, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    private static let praticaFolder = "01 Progetti/Rossi/Offerta 2026"
    private static let messageID = "<abc123@rossi-spa.it>"

    /// Builds a fixture with the one standard message this whole suite regenerates,
    /// and a fresh vault it has already been synced into once.
    private static func syncedFixtureAndVault() async throws -> (fixture: MailStoreFixture.Built, vaultRoot: URL, engine: PraticaSyncEngine, request: PraticaSyncEngine.SyncRequest) {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [row(rowID: 1, messageID: Self.messageID)],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)
        return (fixture, vaultRoot, engine, request)
    }

    /// The one `.md` note the fixture above writes, and its vault-relative path.
    private static func writtenNote(under vaultRoot: URL) throws -> (path: String, text: String) {
        let emailDir = vaultRoot.appending(path: "\(praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let name = try #require(names.first { $0.hasSuffix(".md") }, "the first sync must have written a note")
        let url = emailDir.appending(path: name, directoryHint: .notDirectory)
        let text = try String(contentsOf: url, encoding: .utf8)
        return ("\(praticaFolder)/email/\(name)", text)
    }

    @Test func regenerationPreviewReplacementTextMatchesTheOriginalImportAndDiffIsNilUntilEdited() async throws {
        let (_, vaultRoot, engine, request) = try await Self.syncedFixtureAndVault()
        let (notePath, originalText) = try Self.writtenNote(under: vaultRoot)

        // Unmodified: the file on disk already matches what a fresh import would
        // write, so there is nothing to show a diff of.
        let unchangedPlan = try await engine.regenerationPreview(request, messageID: Self.messageID, rowID: nil)
        #expect(unchangedPlan.notePath == notePath)
        #expect(unchangedPlan.currentText == originalText)
        #expect(
            unchangedPlan.replacementText == originalText,
            "re-decoding the same .emlx must reproduce the same note text"
        )
        #expect(unchangedPlan.diff == nil, "current and replacement are identical; there is nothing to diff")

        // Hand-edited: the replacement is still what a fresh import would write, but
        // now it differs from what is on disk, so a diff must be shown.
        let handEditedText = originalText + "\n\nAggiunto a mano.\n"
        try Data(handEditedText.utf8).write(
            to: vaultRoot.appending(path: notePath, directoryHint: .notDirectory), options: .atomic
        )
        let editedPlan = try await engine.regenerationPreview(request, messageID: Self.messageID, rowID: nil)
        #expect(editedPlan.currentText == handEditedText)
        #expect(editedPlan.replacementText == originalText, "the replacement is unaffected by the hand edit")
        #expect(editedPlan.diff != nil, "a hand-edited file must produce a non-nil diff against the replacement")
    }

    @Test func commitRegenerationWritesExactlyThePlansReplacementTextToItsNotePath() async throws {
        let (_, vaultRoot, engine, request) = try await Self.syncedFixtureAndVault()
        let (notePath, originalText) = try Self.writtenNote(under: vaultRoot)
        let noteURL = vaultRoot.appending(path: notePath, directoryHint: .notDirectory)
        try Data((originalText + "\n\nAggiunto a mano.\n").utf8).write(to: noteURL, options: .atomic)

        let plan = try await engine.regenerationPreview(request, messageID: Self.messageID, rowID: nil)
        _ = try await engine.commitRegeneration(plan)

        let writtenText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(
            writtenText == plan.replacementText,
            "commitRegeneration must write exactly the previewed replacement text, not re-acquire it"
        )
    }

    // ADR §D4/§D21: the `.emlx` is genuinely gone - the acquisition must fail with
    // `.notInStore` specifically (never a bug, R-16's own case), and touch no file. A
    // test that only asserted "throws" would already pass against the stub for the
    // wrong reason, since the stub always throws unconditionally
    // (`RegenerationFailure.rowNotFound`); asserting the exact case is what keeps this
    // one red until the coder distinguishes "no row" from "row found, no .emlx".
    @Test func regenerationPreviewFailsWithNotInStoreWhenTheEmlxIsGoneAndTheFileOnDiskIsUntouched() async throws {
        let (fixture, vaultRoot, engine, request) = try await Self.syncedFixtureAndVault()
        let (notePath, originalText) = try Self.writtenNote(under: vaultRoot)

        // The row still resolves from the index; only the underlying `.emlx` file is
        // gone.
        let everyFile = (FileManager.default.enumerator(at: fixture.root, includingPropertiesForKeys: nil)?
            .allObjects as? [URL]) ?? []
        for url in everyFile where url.pathExtension == "emlx" {
            try FileManager.default.removeItem(at: url)
        }

        do {
            _ = try await engine.regenerationPreview(request, messageID: Self.messageID, rowID: nil)
            Issue.record("expected regenerationPreview to throw RegenerationFailure.notInStore")
        } catch let failure as PraticaSyncEngine.RegenerationFailure {
            #expect(failure == .notInStore, "the row resolves; only the .emlx is missing - this is R-16's case, not rowNotFound")
        } catch {
            Issue.record("expected RegenerationFailure.notInStore, got \(error)")
        }

        let bytesAfter = try Data(contentsOf: vaultRoot.appending(path: notePath, directoryHint: .notDirectory))
        #expect(bytesAfter == Data(originalText.utf8), "a failed acquisition must never touch the file on disk")
    }
}
