import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 4 -
// R-09, R-10, R-11, R-15, R-16, §D15.

@Suite struct PraticaSyncRetryTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: Task 6 (ADR-0040 §D4, §D5, §D6) - every sync revisits a message that is
    // still waiting, and amends one line when it resolves (R-05, R-06)
    //
    // The tests below read `PraticaSyncEngine.FolderContext.ExistingMessage.text` (§D6 -
    // needed to compare a patch against the file already read) and
    // `SyncOutcome.resolvedAttachmentFiles`/`.attachmentProblems` (§D10).

    /// `text` with its `pergamenum-mail-attachments:` line removed - the one line §D4's
    /// patch mode may ever touch. Two texts equal after this strip differ, if at all,
    /// only on that one line.
    private static func removingAttachmentsLine(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("\(MessageDocument.attachmentsKey):") }
            .joined(separator: "\n")
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<nocost@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, firstText) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
        let firstModified = try Fixtures.modificationDate(of: noteURL)

        let secondOutcome = try await engine.sync(request)

        let secondText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(secondText == firstText, "an unresolved retry must not touch a single byte of the note (§D6)")
        #expect(
            try Fixtures.modificationDate(of: noteURL) == firstModified,
            "an unresolved retry must not rewrite the file at all, not even to the same bytes"
        )
        #expect(secondOutcome.resolvedAttachmentFiles.isEmpty, "nothing resolved - no-op per §D6")
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty, "a patch is never counted as a full regeneration")
    }

    /// This test's second `sync(request)` reuses the *first* request unchanged -
    /// `onDisk: []` on both calls - so the message never leaves `candidates` and the
    /// resolution below comes from the MAIN LOOP's `prepare()` re-processing it, not
    /// from `regeneratePending`. `aResolvedAttachmentResolvesOnAnOrdinarySyncOnceTheMessageIsOnDisk`
    /// below is what exercises `regeneratePending` with the shape `MembershipRule`
    /// actually produces in production (`candidates: []`, `onDisk: [messageID]`).
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
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [
                Fixtures.row(rowID: 1, messageID: "<resolve@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170)),
            ],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let (noteURL, originalText) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
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
        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"])
        #expect(secondOutcome.resolvedAttachmentFiles.count == 1, "one note amended in one line")
        #expect(secondOutcome.regeneratedPendingFiles.isEmpty, "a patch is never a full regeneration")
    }

    // MARK: PG-169 (R-07) - a folder restored from the Trash comes back with no ledger entry

    /// SPEC PG-169's one claim that rests on reading code rather than running it: no journal
    /// and no undo for the ledger removal, because a pratica folder restored from the Trash
    /// with an empty ledger re-reconciles against the message files already in it instead of
    /// duplicating or overwriting them. The shape is the restored folder's: the files are on
    /// disk, the ledger says nothing (`onDisk: []` both times, since `onDisk` is exactly
    /// `state.importedMessageIDs`, which the trash emptied).
    ///
    /// What this deliberately does NOT assert is that the restore is free. The second run
    /// writes nothing, so nothing re-enters `importedMessageIDs`: the restored pratica's ledger
    /// stays empty for those messages, and every later sync re-walks and re-decodes them. That
    /// is the accepted cost of "recovery is the Trash" (plan PG-169, §R-07), not a defect this
    /// test hides.
    @Test func aResyncWithAnEmptyLedgerLeavesTheMessageFilesExactlyAsTheyAre() async throws {
        let date = Date(timeIntervalSince1970: 1_781_093_170)
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: date, dateReceived: date,
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>", date: date)],
            onDisk: [], settings: .default
        )
        let firstOutcome = try await engine.sync(request)
        #expect(firstOutcome.writtenFiles.count == 1, "precondition: the first sync wrote the message")
        #expect(firstOutcome.importedMessageIDs == ["<abc123@rossi-spa.it>"])

        let namesBefore = Fixtures.mdFiles(under: vaultRoot)
        let (noteURL, textBefore) = try Fixtures.onlyNoteURLAndText(under: vaultRoot)
        let modifiedBefore = try Fixtures.modificationDate(of: noteURL)

        // The restored-folder shape: the file is there, the ledger has forgotten it.
        let secondOutcome = try await engine.sync(request)

        #expect(Fixtures.mdFiles(under: vaultRoot) == namesBefore, "no message file may be added or renamed")
        #expect(
            try String(contentsOf: noteURL, encoding: .utf8) == textBefore,
            "the note that was already there must be byte-identical afterwards"
        )
        #expect(
            try Fixtures.modificationDate(of: noteURL) == modifiedBefore,
            "and not rewritten at all, not even to the same bytes"
        )
        #expect(secondOutcome.writtenFiles.isEmpty, "the message is already on disk, so nothing is written")
        #expect(
            secondOutcome.importedMessageIDs.isEmpty,
            "a skipped message never re-enters the ledger, which is what the accepted cost in this test's header is"
        )
    }
}
