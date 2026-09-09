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

    private static func mdFiles(under vaultRoot: URL) -> [String] {
        let emailDir = vaultRoot.appending(path: "\(praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
    }

    private static func allegatiFiles(under vaultRoot: URL) -> [String] {
        let dir = vaultRoot.appending(path: "\(praticaFolder)/allegati", directoryHint: .isDirectory)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))) ?? []).sorted()
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
        let bytes = Data("contenuto-identico".utf8)
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
    }

    @Test func aDifferentContentAttachmentWithTheSameNameCollidesToDash2() async throws {
        let messageA = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "msgA@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: Data("versione 1".utf8)
        )
        let messageB = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "msgB@rossi-spa.it", attachmentFilename: "offerta.pdf",
            attachmentBytes: Data("versione 2, diversa".utf8)
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

    @Test func anInlineImageUnder50KBIsDroppedAndALargerOneIsSavedAndEmbedded() async throws {
        let smallImage = Data("hello".utf8) // ≪ 50 KB
        let largeImage = Data(repeating: 0x42, count: 60_000) // > 50 KB
        let smallMessage = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "smallimg@rossi-spa.it", contentID: "logo-small", imageBytes: smallImage
        )
        let largeMessage = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "largeimg@rossi-spa.it", contentID: "logo-large", imageBytes: largeImage
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [
                .init(
                    rowID: 1, subject: "Immagine piccola", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                    dateReceived: Date(timeIntervalSince1970: 1000), emlxBody: smallMessage
                ),
                .init(
                    rowID: 2, subject: "Immagine grande", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                    conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 2000),
                    dateReceived: Date(timeIntervalSince1970: 2000), emlxBody: largeMessage
                ),
            ]
        )
        let vaultRoot = try Self.makeVaultRoot()
        let engine = Self.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [
                row(rowID: 1, messageID: "<smallimg@rossi-spa.it>", date: Date(timeIntervalSince1970: 1000)),
                row(rowID: 2, messageID: "<largeimg@rossi-spa.it>", date: Date(timeIntervalSince1970: 2000)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Self.allegatiFiles(under: vaultRoot)
        #expect(!files.contains { $0.contains("logo-small") }, "an inline image under 50 KB is dropped")
        #expect(files.contains { $0.hasSuffix(".png") }, "the larger inline image must be saved")
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
        // its row is gone from Mail - but the ledger still remembers importing it.
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.praticaFolder, dossier: sampleDossier(),
            candidates: [], onDisk: ["<abc123@rossi-spa.it>"], settings: .default
        )
        let secondOutcome = try await engine.sync(secondRequest)

        #expect(secondOutcome.noLongerInMail == ["<abc123@rossi-spa.it>"])
        #expect(FileManager.default.fileExists(atPath: mdURL.path(percentEncoded: false)), "the file is kept, never deleted")
    }
}
