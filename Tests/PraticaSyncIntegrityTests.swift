import Foundation
import Testing
@testable import Pergamenum

// ADR-0068 (Pratiche sync integrity), plan
// docs/plans/pg-257-pratiche-sync-integrity-and-post-write-door.md, Task 3 -
// R-10, R-12, R-16, R-17 (engine half).
//
// Tester-declared red suite: every test below documents, in its own comment, the
// exact production line that is still missing the Task 5 fix it exercises.

@Suite struct PraticaSyncIntegrityTests {
    private typealias Fixtures = PraticaSyncFixtures

    // MARK: - R-10, item 4/§D6: the ledger's own ROWID resolves what the index cannot

    /// A message this pratica already imported, whose literal `Message-ID` no longer
    /// matches any row (Mail rewrote the header, keeping the same ROWID - the
    /// "ROWID reused" shape ADR-0068 §D6 names), must not be marked «Non più in
    /// Mail» when the ledger's own recorded ROWID still resolves. Red until Task 5:
    /// `noLongerInMail(request:reader:)` (`PraticaSyncEngine.swift:206`) checks only
    /// `reader.row(forMessageID:)` today, with no ledger fallback.
    @Test func aMessageTheIndexCannotResolveByLiteralIDButTheLedgersRowIDCanIsNotMarkedGone() async throws {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let firstRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<abc123@rossi-spa.it>")],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(firstRequest)

        // Mail rewrites the header at the same ROWID (an index rebuild's own
        // pathology, ADR-0068 §D6's "known limit"): the literal string
        // `<abc123@rossi-spa.it>` is no longer stored anywhere in the index.
        try await Task.sleep(for: .milliseconds(50))
        _ = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: "renumbered999@rossi-spa.it")
            )],
            in: fixture.root
        )
        let secondEngine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let secondRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<renumbered999@rossi-spa.it>")],
            onDisk: ["<abc123@rossi-spa.it>"], settings: .default,
            ledgerEntries: [PraticaLedger.Entry(messageID: "<abc123@rossi-spa.it>", rowID: 1, conversationID: 112_409)]
        )
        let secondOutcome = try await secondEngine.sync(secondRequest)

        #expect(
            !secondOutcome.noLongerInMail.contains("<abc123@rossi-spa.it>"),
            "the ledger's own ROWID still resolves at Mail - this must not read as gone"
        )
    }

    /// The other half of §D6: `recordSyncOutcome` must clear «Non più in Mail» for a
    /// message the ledger's fallback (or the index) found again, not only for one
    /// re-imported this run. Red until Task 5: `recordSyncOutcome`
    /// (`PraticheController+Ledger.swift:321`) subtracts `importedMessageIDs` alone.
    @MainActor
    @Test func recordSyncOutcomeClearsTheMarkerForAMessageMerelySeenAgain() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let praticaPath = "01 Progetti/Rossi/Offerta 2026"
        controller.updateLedger(.live(session)) {
            var state = PraticaLedger.PraticaState.empty
            state.importedMessageIDs = ["<abc123@rossi-spa.it>"]
            state.notInStore = ["<abc123@rossi-spa.it>"]
            $0.byPraticaPath[praticaPath] = state
        }

        let outcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: [], noLongerInMail: [], regeneratedPendingFiles: [],
            cancelled: false, bridge: [], seenInMail: ["<abc123@rossi-spa.it>"]
        )
        controller.recordSyncOutcome(outcome, for: praticaPath, session: session, isCurrentVault: true)

        #expect(
            controller.ledger.byPraticaPath[praticaPath]?.notInStore.isEmpty == true,
            "a message merely seen again (not re-imported) must lose the marker too"
        )
    }

    // MARK: - R-12, item 6/§D8: an unreadable message note still reserves its name

    /// `folderContext(of:)` must append an unreadable `.md`'s file name to
    /// `takenNoteNames` before its `continue` - today it skips straight past
    /// (`PraticaSyncEngine+Folder.swift:61`), so the unreadable file's name is free
    /// for a fresh import to reuse, which would collide on disk. This test drives
    /// `folderContext(of:)` directly (it is `not private`), rather than through a
    /// full `sync()`, since forcing the exact colliding basename through the naming
    /// algorithm end-to-end is Task 5's own integration concern.
    @Test func folderContextReservesAnUnreadableNotesNameAndLeavesItsBytesAlone() async throws {
        let vaultRoot = try Fixtures.makeVaultRoot()
        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: emailDir, withIntermediateDirectories: true)
        let unreadable = emailDir.appending(path: "2026-01-01_msg.md", directoryHint: .notDirectory)
        let originalBytes = Data("---\npergamenum-mail-message-id: \"<x@y>\"\n---\n".utf8)
        try originalBytes.write(to: unreadable)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path(percentEncoded: false))
        // Restored before the bytes-unchanged read below, not merely at teardown - a chmod-000
        // file cannot be read back at all while the bit is still off, so a `defer` alone made
        // the read itself throw. The `defer` stays as a safety net for an early throw/return,
        // and is a no-op once the explicit restore below has already run.
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path(percentEncoded: false))
        }

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [], onDisk: [], settings: .default
        )

        let context = try await engine.folderContext(of: request)

        #expect(
            context.takenNoteNames.contains { $0.fileName == "2026-01-01_msg.md" },
            "an unreadable note's name must still be reserved, or a fresh import can collide with it"
        )

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path(percentEncoded: false))
        let bytesAfter = try Data(contentsOf: unreadable, options: [.uncached])
        #expect(bytesAfter == originalBytes, "the unreadable note's bytes must be left alone by folderContext")
    }

    // MARK: - R-17, item 11 engine half/§D10: a quarantine failure is a problem, not an abort

    /// An injected `quarantine` that throws must not abort the run: every message
    /// decoded before the failure keeps its place in `importedMessageIDs`, and the
    /// failure becomes one sentence in `outcome.attachmentProblems`. Red until Task
    /// 5 wires the two call sites (`commit`'s attachment loop and its `.eml` write)
    /// through `self.quarantine` instead of calling `AttachmentQuarantine.apply`
    /// directly - today's injected closure is stored but never invoked, so no
    /// failure is ever seen and `attachmentProblems` stays empty.
    @Test func aThrowingQuarantineIsRecordedAsAProblemNotAnAbort() async throws {
        let bytes = EmailFixtureCorpus.pdfBytes(pages: 1)
        let message = EmailFixtureCorpus.singleAttachmentMessageRFC822(
            messageID: "quarantine1@rossi-spa.it", attachmentFilename: "offerta.pdf", attachmentBytes: bytes
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Con allegato", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1_781_093_170),
                dateReceived: Date(timeIntervalSince1970: 1_781_093_170), emlxBody: message
            )]
        )
        let vaultRoot = try Fixtures.makeVaultRoot()
        struct QuarantineFailure: Error {}
        let engine = PraticaSyncEngine(
            mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot,
            write: { text, relativePath in
                let url = vaultRoot.appending(path: relativePath, directoryHint: .notDirectory)
                try Data(text.utf8).write(to: url, options: .atomic)
            },
            quarantine: { _ in throw QuarantineFailure() }
        )
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: "<quarantine1@rossi-spa.it>", date: Date(timeIntervalSince1970: 1_781_093_170))],
            onDisk: [], settings: .default
        )

        let outcome = try await engine.sync(request)

        #expect(
            outcome.importedMessageIDs.contains("<quarantine1@rossi-spa.it>"),
            "the message must still import even though quarantining its attachment failed"
        )
        #expect(
            outcome.attachmentProblems.count == 1,
            "a quarantine failure must be recorded as one problem sentence - red until Task 5 wires the injected closure in"
        )
    }
}
