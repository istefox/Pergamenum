import Foundation
import Testing
@testable import Pergamenum

// ADR-0048 (externalized attachments resolved from the sibling `Attachments/`
// directory), amending ADR-0040 §D2 - Exchange sometimes writes a part's bytes only to
// Mail's own sibling `Attachments/<rowID>/<part>/` directory, leaving the inline MIME
// payload permanently empty (`AttachmentIntegrity.verdict` answers `.empty`, not merely
// "not yet"). These tests exercise `PraticaSyncEngine`'s new sibling-directory
// resolution, kept in their own file per the plan's own instruction, so
// `PraticaSyncAttachmentTests`/`PraticaSyncRetryTests` do not grow further.

@Suite struct PraticaSyncExternalizedAttachmentTests {
    private typealias Fixtures = PraticaSyncFixtures

    @Test func anAttachmentWithEmptyInlineBytesResolvesFromTheSiblingDirectory() async throws {
        let message = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "externalized@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Allegato esternalizzato", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        // `singleAttachmentMessageRFC822` (which `zeroByteAttachmentMessageRFC822` calls
        // into) is a flat `multipart/mixed`: text/plain at "1", the attachment at "2".
        try Fixtures.writeExternalizedAttachment(
            EmailFixtureCorpus.pdfBytes(), named: "offerta.pdf", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<externalized@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Fixtures.allegatiFiles(under: vaultRoot)
        #expect(files == ["20260610_offerta.pdf"], "the sibling file's bytes must be placed on the very first sync")

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.linkedAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "resolved, not pending")

        let copy = vaultRoot.appending(
            path: "\(Fixtures.praticaFolder)/allegati/20260610_offerta.pdf", directoryHint: .notDirectory
        )
        #expect(AttachmentQuarantine.isApplied(to: copy), "an externalized attachment is a download too")
    }

    @Test func anAttachmentStaysPendingWhenNoSiblingFileExists() async throws {
        // Today's behavior, explicit regression: no sibling file is ever written for
        // this rowID, so the empty inline payload has nothing to resolve from.
        let message = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "nosibling@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Nessun file esternalizzato", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<nosibling@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "nothing to place without a sibling file")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
    }

    @Test func anAttachmentStaysPendingWhenTheSiblingFileIsItselfCorrupt() async throws {
        let message = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "corruptsibling@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "File esternalizzato corrotto", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        // The wrong magic number for the declared `.pdf` extension - `AttachmentIntegrity`
        // must reject it exactly as it would an inline part with the same bytes.
        try Fixtures.writeExternalizedAttachment(
            Data("this is not a pdf".utf8), named: "offerta.pdf", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<corruptsibling@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "a corrupt sibling file must never be placed")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
    }

    @Test func anOverThresholdExternalizedAttachmentBecomesAStoreReferenceWithoutBeingCopied() async throws {
        // `.dwg` has no signature entry in `AttachmentIntegrity` (ADR-0040 finding 2's
        // own precedent), so this exercises the size/threshold logic without also
        // needing a real, over-threshold-sized file of a recognised format.
        let message = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "overthreshold@rossi-spa.it", filename: "disegno-staffa.dwg"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Disegno esternalizzato grande", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let bigBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024) // 2 MB
        try Fixtures.writeExternalizedAttachment(
            bigBytes, named: "disegno-staffa.dwg", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1 // the 2 MB sibling file is over this
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<overthreshold@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(
            Fixtures.allegatiFiles(under: vaultRoot).isEmpty,
            "an over-threshold externalized attachment must never be copied into allegati/"
        )
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        let reference = try #require(doc.frontmatter.storeReferences.first)
        #expect(reference.name == "disegno-staffa.dwg")
        #expect(reference.size == bigBytes.count)
        #expect(reference.storePath.contains("Attachments"), "recorded where it really lives in Mail's own store")
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "an over-threshold reference is resolved, not pending")
    }

    @Test func anExternalizedAttachmentBehindANestedAlternativeResolvesAtItsCorrectPartNumber() async throws {
        // The regression the numbering fix exists for: the old `ordinal + 1` scheme
        // would have looked for this attachment at flat index "3" (text, html, then the
        // attachment); RFC 3501 numbering puts it at "2", because the alternative
        // container consumes slot "1" for both of its own children.
        let boundary = "----=_Pergamenum_Externalized_Mixed"
        let altBoundary = "----=_Pergamenum_Externalized_Alt"
        let message = """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta con alternativa e allegato esternalizzato\r
        Message-Id: <nestedexternalized@rossi-spa.it>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: multipart/alternative; boundary="\(altBoundary)"\r
        \r
        --\(altBoundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato la nostra offerta.\r
        --\(altBoundary)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        <p>Buongiorno, in allegato la nostra offerta.</p>\r
        --\(altBoundary)--\r
        --\(boundary)\r
        Content-Type: application/octet-stream\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="offerta.pdf"\r
        \r
        \r
        --\(boundary)--\r
        """
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta con alternativa", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        // Seeded at "2" - the alternative consumes "1" for its own plain/html children,
        // never "3", which is what the old flat-index bug would have looked for.
        try Fixtures.writeExternalizedAttachment(
            EmailFixtureCorpus.pdfBytes(), named: "offerta.pdf", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<nestedexternalized@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Fixtures.allegatiFiles(under: vaultRoot)
        #expect(files == ["20260610_offerta.pdf"], "must resolve at the real RFC 3501 number, not a flat decode index")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
    }

    @Test func anAttachmentStaysPendingWhenTheSiblingFileExistsButIsItselfEmpty() async throws {
        // Distinct from `anAttachmentStaysPendingWhenNoSiblingFileExists`: there the
        // path itself doesn't exist, so `resourceValues` throws and `try?` folds it to
        // `.unavailable`. Here the file exists - the directory walk and the stat both
        // succeed - but is itself zero bytes, so it must be caught by the `size > 0`
        // guard rather than going on to a `Data(contentsOf:)` read of nothing, or a
        // crash on an empty file `AttachmentIntegrity` never gets the chance to see.
        let message = EmailFixtureCorpus.zeroByteAttachmentMessageRFC822(
            messageID: "emptysibling@rossi-spa.it", filename: "offerta.pdf"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "File esternalizzato vuoto", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        try Fixtures.writeExternalizedAttachment(
            Data(), named: "offerta.pdf", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<emptysibling@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "an empty sibling file is still nothing to place")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta.pdf"])
        #expect(doc.frontmatter.linkedAttachmentNames.isEmpty)
    }

    @Test func aThreeLevelNestedOverThresholdExternalizedAttachmentResolvesAtItsCorrectPartNumber() async throws {
        // Combines the two dimensions no single existing test does together: the
        // sibling file is both nested three levels deep (`mixed` › `related` ›
        // `alternative`, the attachment itself a fourth `mixed` child) AND over the
        // configured threshold, so it must land in `resolveExternalized`'s
        // `.overThreshold` branch - never the whole-file `Data(contentsOf:)` read -
        // while still being found at the correct RFC 3501 number rather than a flat
        // decode-order guess.
        let mixedBoundary = "----=_Pergamenum_Externalized3_Mixed"
        let relatedBoundary = "----=_Pergamenum_Externalized3_Related"
        let altBoundary = "----=_Pergamenum_Externalized3_Alt"
        let message = """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Disegno con struttura a tre livelli\r
        Message-Id: <nestedexternalizedbig@rossi-spa.it>\r
        Date: Wed, 10 Jun 2026 14:06:10 +0200\r
        Content-Type: multipart/mixed; boundary="\(mixedBoundary)"\r
        \r
        --\(mixedBoundary)\r
        Content-Type: multipart/related; boundary="\(relatedBoundary)"\r
        \r
        --\(relatedBoundary)\r
        Content-Type: multipart/alternative; boundary="\(altBoundary)"\r
        \r
        --\(altBoundary)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Buongiorno, in allegato il disegno.\r
        --\(altBoundary)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        <p>Buongiorno, in allegato il disegno.</p>\r
        --\(altBoundary)--\r
        --\(relatedBoundary)\r
        Content-Type: image/png\r
        Content-Transfer-Encoding: base64\r
        Content-ID: <img1>\r
        Content-Disposition: inline; filename="img1.png"\r
        \r
        aW1nLWJ5dGVz\r
        --\(relatedBoundary)--\r
        --\(mixedBoundary)\r
        Content-Type: application/octet-stream\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="disegno-staffa.dwg"\r
        \r
        \r
        --\(mixedBoundary)--\r
        """
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Disegno a tre livelli", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        // `mixed` › `related` (slot "1") › `alternative` (slot "1.1", consuming no
        // `MIMEPart`): the plain/html pair sits at "1.1.1"/"1.1.2", the inline image at
        // "1.2", and the attachment - `mixed`'s own second child - at "2", exactly the
        // three-level `MIMEDecoderTests` shape, seeded with an over-threshold file.
        let bigBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024) // 2 MB
        try Fixtures.writeExternalizedAttachment(
            bigBytes, named: "disegno-staffa.dwg", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1 // the 2 MB sibling file is over this
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<nestedexternalizedbig@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(
            Fixtures.allegatiFiles(under: vaultRoot).isEmpty,
            "a three-level-deep over-threshold externalized attachment must never be copied"
        )
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        let reference = try #require(doc.frontmatter.storeReferences.first)
        #expect(reference.name == "disegno-staffa.dwg")
        #expect(reference.size == bigBytes.count)
        #expect(
            reference.storePath.contains("/2/"),
            "must resolve at the real nested RFC 3501 number \"2\", not a flat decode-order guess"
        )
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
    }

    @Test func anOverThresholdInlineImageWithASiblingFileStaysUnresolvedNotAStoreReference() async throws {
        // §5's explicit scope note: an inline image never gets an over-threshold
        // `StoreReference` path, even when a sibling file genuinely exists and is
        // genuinely over threshold - `resolveInlineImage` only matches
        // `resolveExternalized`'s `.bytes` case, so `.overThreshold` here must fall
        // through exactly like `.unavailable` does: deferred (the body does reference
        // the id), never embedded, never a reference.
        let message = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "inlinebig@rossi-spa.it", contentID: "img1",
            imageBytes: Data(), filename: "img1.png"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine inline grande", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let bigBytes = Data(repeating: 0x41, count: 2 * 1024 * 1024) // 2 MB, well over threshold
        try Fixtures.writeExternalizedAttachment(
            bigBytes, named: "img1.png", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<inlinebig@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "no over-threshold path exists for inline images")
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.isEmpty, "an inline image never becomes a StoreReference")
        #expect(
            doc.frontmatter.pendingInlineImages == ["img1"],
            "falls through to the deferred/pending path exactly like an unavailable sibling would"
        )
    }

    // MARK: §5 - inline images, same mechanism, smaller scope

    @Test func anInlineImageWithEmptyInlineBytesResolvesFromTheSiblingDirectory() async throws {
        let message = EmailFixtureCorpus.singleInlineImageMessageRFC822(
            messageID: "inlineexternalized@rossi-spa.it", contentID: "img1",
            imageBytes: Data(), filename: "img1.png"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Immagine inline esternalizzata", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        // `singleInlineImageMessageRFC822` is one `multipart/related` with two direct
        // children: text/plain at "1", the inline image at "2".
        //
        // A large, non-decorative PNG (never dropped as a small logo, unlike
        // `solidColorPNG` at logo dimensions - `PraticaSyncAttachmentTests`' own
        // "heavy" case) so this test exercises resolution, not `InlineImageClassifier`.
        try Fixtures.writeExternalizedAttachment(
            EmailFixtureCorpus.noisyPNG(width: 200, height: 200), named: "img1.png", rowID: 1, part: "2",
            into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<inlineexternalized@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let files = Fixtures.allegatiFiles(under: vaultRoot)
        #expect(files == ["20260610_img1.png"], "the sibling image must be placed on the very first sync")

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.newText.contains("![[20260610_img1.png]]"), "embedded where the sender put it, not listed")
        #expect(doc.frontmatter.pendingInlineImages.isEmpty)
    }
}
