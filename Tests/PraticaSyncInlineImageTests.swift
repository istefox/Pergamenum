import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

// MARK: - Shared fixtures

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

@Suite struct PraticaSyncInlineImageTests {
    private typealias Fixtures = PraticaSyncFixtures

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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<htmltwo@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "an inline image is never a pending attachment")
        #expect(doc.frontmatter.pendingInlineImages == ["missing"])
        #expect(
            occurrenceCount(of: MessageInlineImage.placeholder, in: doc.newText) == 1,
            "exactly one placeholder, for the image with no bytes"
        )
        #expect(doc.newText.contains("![["), "the image with bytes is embedded, not left pending")
        #expect(Fixtures.allegatiFiles(under: vaultRoot).count == 1, "only the placed image reaches allegati/")
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<htmlplain@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingInlineImages.isEmpty, "R-03: no id the body never mentions gets pending state")
        #expect(!doc.newText.contains(MessageInlineImage.placeholder))
        #expect(Fixtures.allegatiFiles(under: vaultRoot).count == 1, "the image with bytes is still placed regardless")
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<decorative@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
        #expect(doc.frontmatter.pendingInlineImages.isEmpty)
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
        #expect(!doc.newText.contains(MessageInlineImage.placeholder))
        #expect(!doc.newText.contains("!["), "no `![Logo]()` remnant, not even an empty embed construct")
        #expect(!doc.newText.contains("cid:"))
        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<reply@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<mixedpending@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.pendingInlineImages == ["innerimg"])
        #expect(doc.newText.contains(MessageInlineImage.placeholder))
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<inlineresolve@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
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
        #expect(Fixtures.allegatiFiles(under: vaultRoot).count == 1)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<mismatch@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
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
        #expect(Fixtures.allegatiFiles(under: vaultRoot).count == 1)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<inlinenogrow@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )

        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1)
        let (noteURL, _) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Fixtures.modificationDate(of: noteURL)

        for run in 2...10 {
            let outcome = try await engine.sync(request)
            #expect(outcome.writtenFiles.isEmpty, "run \(run) must write nothing - the image never resolves")
            #expect(outcome.resolvedAttachmentFiles.isEmpty, "run \(run) must resolve nothing")
        }

        #expect(
            try Fixtures.modificationDate(of: noteURL) == firstModified,
            "ten unresolved retries must leave the file exactly as the first sync wrote it - the no-op rule (§D6)"
        )
    }
}
