import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

@Suite struct PraticaSyncThresholdTests {
    private typealias Fixtures = PraticaSyncFixtures

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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<bigvalid@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<bigwrong@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.isEmpty, "a reference is a promise the file is there - R-07")
        #expect(doc.frontmatter.pendingAttachmentNames == ["20260610_offerta-falsa.pdf"])
    }

    // R-07's third case, from the plan verbatim: "reached through Task 6's retry, so
    // this assertion may have to land in Task 6's batch if Task 5 ships first. Say so
    // in the commit message rather than weakening it." Written here per that
    // instruction - NOT weakened, NOT omitted. It needs more than Task 5 alone
    // provides: `prepare`'s existing-file guard (`:356-364`) only lets a file be
    // rewritten when it is `.pending` (or an explicit «Rigenera») - a `.complete`
    // message with only a pending *attachment* (this case, per R-04's own rule) is
    // revisited through Task 6's clause (ADR-0040 §D5).
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        // Reused unchanged for both syncs, the same idiom
        // `aHeadersOnlyMessageIsWrittenPendingAndRegeneratedOnceTheBodyArrives` uses
        // above: `onDisk` stays empty both times, so the second sync reaches this
        // message through `PraticaSyncPlan.workItems` exactly as the first one did,
        // and whether it is actually rewritten is entirely `prepare`'s guard's call.
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<bigretry@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
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

        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        #expect(doc.frontmatter.storeReferences.map(\.name) == ["offerta-grande.pdf"], "R-07's retry, via Task 6")
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty, "the pending entry must go once bytes resolve")
        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty, "still over threshold - never copied")
    }

    // MARK: ADR-0048 - `storePath`'s own pre-existing over-threshold branch (real,
    // non-empty inline bytes, never `resolveExternalized`) also switched from
    // `ordinal + 1` to `part.partNumber`. The two tests above never actually exercise
    // that switch, because their fixture is a flat `multipart/mixed` where the
    // attachment is the array's second element either way - `ordinal + 1` and
    // `partNumber` agree by coincidence. This one nests a `multipart/alternative`
    // ahead of the attachment so the two schemes disagree ("3" vs the real "2"), and
    // seeds a sibling file at the real number, so a wrong guess would silently
    // fall back to the `.emlx` path (`storePath`'s own not-found fallback,
    // `PraticaSyncEngine+Attachments.swift:39`) instead of failing loudly.

    @Test func anOverThresholdInlineAttachmentBehindANestedAlternativeUsesItsRealPartNumber() async throws {
        var bytes = Data("%PDF-1.7\n".utf8)
        bytes.append(Data(repeating: 0x41, count: 2 * 1024 * 1024))
        bytes.append(Data("\n%%EOF\n".utf8))
        let boundary = "----=_Pergamenum_ThresholdNested_Mixed"
        let altBoundary = "----=_Pergamenum_ThresholdNested_Alt"
        let message = """
        From: Mario Rossi <m.rossi@rossi-spa.it>\r
        To: Stefano Ferri <stefano@stefer.it>\r
        Subject: Offerta grande con alternativa\r
        Message-Id: <bignestedalt@rossi-spa.it>\r
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
        Content-Type: application/pdf\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="offerta-grande.pdf"\r
        \r
        \(bytes.base64EncodedString())\r
        --\(boundary)--\r
        """
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Offerta grande con alternativa", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        // Seeded at the alternative-aware "2" - the old `ordinal + 1` scheme would
        // have looked for this attachment at "3" (plain, html, attachment counted
        // flat) and, finding nothing there, silently fallen back to the `.emlx` path.
        try PraticaSyncFixtures.writeExternalizedAttachment(
            bytes, named: "offerta-grande.pdf", rowID: 1, part: "2", into: fixture
        )

        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        var settings = PraticheSettings.default
        settings.attachmentThresholdMB = 1
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<bignestedalt@rossi-spa.it>")],
            onDisk: [], settings: settings
        )
        _ = try await engine.sync(request)

        #expect(Fixtures.allegatiFiles(under: vaultRoot).isEmpty)
        let doc = try Fixtures.onlyMessageDocument(under: vaultRoot)
        let reference = try #require(doc.frontmatter.storeReferences.first)
        #expect(reference.name == "offerta-grande.pdf")
        #expect(
            reference.storePath.contains("/2/"),
            "storePath's own over-threshold branch must resolve the real nested part number, not fall back to the .emlx path because ordinal + 1 guessed \"3\""
        )
        #expect(doc.frontmatter.pendingAttachmentNames.isEmpty)
    }
}
