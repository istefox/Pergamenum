import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

@Suite struct PraticaSyncAttachmentTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: R-10 - attachment naming, SHA-256 linking, collision, threshold, inline images

    /// `anInlineImageIsDroppedOnlyWhenBothLightAndSmallElseSavedAndEmbedded`'s own fixture
    /// table, named rather than a bare tuple - consumed only by that one function.
    private struct InlineImageCase {
        let id: String
        let contentID: String
        let filename: String
        let bytes: Data
    }

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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<msgA@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
                Fixtures.row(rowID: 2, messageID: "<msgB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_171)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Fixtures.allegatiFiles(under: vaultRoot)
        #expect(files == ["20260610_offerta.pdf"], "identical content must produce exactly one copy, linked twice")
        // PG-123: the copy is a download as far as Gatekeeper is concerned.
        let copy = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/allegati/20260610_offerta.pdf", directoryHint: .notDirectory)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<msgA@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
                Fixtures.row(rowID: 2, messageID: "<msgB@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_171)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Fixtures.allegatiFiles(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1 // the 2 MB attachment is over this
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<big@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "an over-threshold attachment must never be copied")

        // Coordinator follow-up (closes the gap the original Task 4 report flagged
        // instead of guessing at): the over-threshold attachment still needs a home in
        // the message file's frontmatter (SPEC "Edge cases": `{ name, size, storePath }`,
        // declared as `MessageDocument.StoreReference`): one `StoreReference` per
        // over-threshold attachment.
        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
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

        let messages: [InlineImageCase] = [
            InlineImageCase(id: "logo@rossi-spa.it", contentID: "logo", filename: "logo.png", bytes: logoImage),
            InlineImageCase(
                id: "screenshot@rossi-spa.it", contentID: "screenshot", filename: "screenshot.png",
                bytes: screenshotImage
            ),
            InlineImageCase(id: "heavy@rossi-spa.it", contentID: "heavy", filename: "heavy.png", bytes: heavyImage),
            InlineImageCase(
                id: "undecodable@rossi-spa.it", contentID: "undecodable", filename: "undecodable.png",
                bytes: undecodableImage
            ),
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: messages.enumerated().map { index, message in
                Fixtures.row(
                    rowID: index + 1, messageID: "<\(message.id)>",
                    date: Date(timeIntervalSince1970: Double(1000 * (index + 1)))
                )
            },
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Fixtures.allegatiFiles(under: vaultRoot)
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
}
