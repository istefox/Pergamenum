import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

@Suite struct PraticaSyncIntegrityTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: Task 4 (R-01, R-02, R-04, R-12) - the write path refuses bytes that are
    // not the file, and a partly-ready message is still `.complete`
    //
    // `AttachmentIntegrity.verdict` (Task 1) and the pending-attachment codec
    // (`MessageDocument.attachmentEntry(pending:)` / `.isPendingAttachmentEntry` /
    // `.linkedAttachmentNames` / `.pendingAttachmentNames`, Task 3) are what
    // `PraticaSyncEngine.prepare`'s part loop consults (ADR-0040 §D2, §D3).

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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<zerobyte@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "a zero-byte attachment must never be copied (R-01)")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<truncated@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "a truncated PDF must never be copied (R-02)")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<unknownformat@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_disegno.dwg"])
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<mixed@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_valido.pdf"], "R-04: the good half is still placed")
        #expect(Fixtures.mdFiles(under: vaultRoot).count == 1)
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<zeroA@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
                Fixtures.row(rowID: 2, messageID: "<zeroB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_171)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "R-12: no shared file must ever be produced")
        let docs = try Fixtures.messageDocuments(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<zeroinline@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "a zero-byte inline image must never be copied")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
}
