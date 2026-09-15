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
}
