import Foundation
import Testing
@testable import Pergamenum

// PG-168 / #313: a sync must never bring a pratica folder into existence. The message in
// flight when a folder is relocated or trashed is past `PraticaSyncEngine.cancel()`'s
// cooperative boundary, and every write on its path used to create its own parent chain -
// leaving a stray `<vacated>/email/` holding a valid message and no `pratica.md` beside it.
//
// Nothing here races a relocation against a sync by timing
// (`Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s header): "the folder has gone" is the
// state on disk a relocation leaves, installed before the sync (or, for the mid-run case,
// from inside the engine's own write closure, which is called exactly once per note and is
// therefore a deterministic seam). Fully deterministic.

@MainActor @Suite(.serialized) struct PraticaSyncVacatedFolderTests {
    private typealias Fixtures = PraticaSyncFixtures

    private static let dateA = Date(timeIntervalSince1970: 1_781_093_170)
    private static let dateB = Date(timeIntervalSince1970: 1_781_093_171)

    /// One or two messages of the same conversation, `withAttachment` giving the first one a
    /// PDF-shaped attachment (`AttachmentIntegrity` would reject prose named `.pdf`).
    private static func fixture(messages: Int = 1, withAttachment: Bool = false) throws -> MailStoreFixture.Built {
        var built: [MailStoreFixture.Message] = []
        for index in 1...messages {
            let id = "msg\(index)@rossi-spa.it"
            let body = withAttachment && index == 1
                ? EmailFixtureCorpus.singleAttachmentMessageRFC822(
                    messageID: id, attachmentFilename: "offerta.pdf",
                    attachmentBytes: EmailFixtureCorpus.pdfBytes(pages: 1)
                )
                : EmailFixtureCorpus.completeMessageRFC822
                    .replacingOccurrences(of: "abc123@rossi-spa.it", with: id)
            let date = index == 1 ? dateA : dateB
            built.append(.init(
                rowID: index, subject: "Messaggio \(index)", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409, dateSent: date, dateReceived: date, emlxBody: body
            ))
        }
        return try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: built)
    }

    private static func request(messages: Int = 1) -> PraticaSyncEngine.SyncRequest {
        var candidates = [Fixtures.row(rowID: 1, messageID: "<msg1@rossi-spa.it>", date: dateA)]
        if messages > 1 { candidates.append(Fixtures.row(rowID: 2, messageID: "<msg2@rossi-spa.it>", date: dateB)) }
        return PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: candidates, onDisk: [], settings: .default
        )
    }

    private static func exists(_ relativePath: String, under root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: relativePath).path(percentEncoded: false))
    }

    // MARK: - A vacated folder is refused, and nothing is recreated

    /// The headline: the folder a relocation has vacated stays vacated.
    @Test func aSyncIntoAVacatedFolderIsRefusedAndRecreatesNothing() async throws {
        let fixture = try Self.fixture()
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        try FileManager.default.removeItem(at: vaultRoot.appending(path: Fixtures.praticaFolder))

        await #expect(throws: VaultWriteRefusal.folderVanished(Fixtures.praticaFolder)) {
            _ = try await engine.sync(Self.request())
        }
        #expect(
            !Self.exists(Fixtures.praticaFolder, under: vaultRoot),
            "a refused sync must not bring the vacated pratica folder back, not even as an empty directory"
        )
    }

    /// The case a bare "parent exists" check would miss, and what justifies asking for
    /// `pratica.md` rather than the directory: the folder survived, its dossier did not.
    @Test func aFolderThatSurvivedWithoutItsDossierIsRefused() async throws {
        let fixture = try Self.fixture()
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        try FileManager.default.removeItem(at: vaultRoot.appending(path: "\(Fixtures.praticaFolder)/pratica.md"))

        await #expect(throws: VaultWriteRefusal.folderVanished(Fixtures.praticaFolder)) {
            _ = try await engine.sync(Self.request())
        }
        #expect(
            Fixtures.mdFiles(under: vaultRoot).isEmpty,
            "no message may be written beside a pratica with no dossier"
        )
    }

    /// Covers `writeAtomically`: attachment bytes never pass through `VaultSession`, so
    /// `expecting:` never protected them and the vault-level flag cannot reach them.
    @Test func anAttachmentIsNeverWrittenUnderAVacatedFolder() async throws {
        let fixture = try Self.fixture(withAttachment: true)
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        try FileManager.default.removeItem(at: vaultRoot.appending(path: Fixtures.praticaFolder))

        await #expect(throws: VaultWriteRefusal.folderVanished(Fixtures.praticaFolder)) {
            _ = try await engine.sync(Self.request())
        }
        #expect(
            !Self.exists("\(Fixtures.praticaFolder)/allegati", under: vaultRoot),
            "attachment bytes must not recreate the vacated folder's allegati/"
        )
        #expect(!Self.exists(Fixtures.praticaFolder, under: vaultRoot))
    }

    // MARK: - The guard does not break creation

    /// The test most likely to catch an over-strict `makeDirectory`: a pratica's first sync
    /// has neither `email/` nor `allegati/` yet, and both must still come into being.
    @Test func aFirstSyncStillCreatesEmailAndAllegati() async throws {
        let fixture = try Self.fixture(withAttachment: true)
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        #expect(!Self.exists("\(Fixtures.praticaFolder)/email", under: vaultRoot), "fixture precondition")

        _ = try await engine.sync(Self.request())

        #expect(Fixtures.mdFiles(under: vaultRoot).count == 1, "the message must still land")
        #expect(Fixtures.allegatiFiles(under: vaultRoot) == ["20260610_offerta.pdf"], "and so must its attachment")
    }

    /// Today a message with nothing to attach creates no `allegati/`; the guard must not
    /// turn every pratica into one with an empty folder.
    @Test func aMessageWithNoAttachmentsCreatesNoAllegatiDirectory() async throws {
        let fixture = try Self.fixture()
        let vaultRoot = try Fixtures.makeVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)

        _ = try await engine.sync(Self.request())

        #expect(Fixtures.mdFiles(under: vaultRoot).count == 1)
        #expect(!Self.exists("\(Fixtures.praticaFolder)/allegati", under: vaultRoot))
    }

    // MARK: - The regression itself

    /// Counts how many notes the engine's write closure has been asked for. A reference
    /// type on the main actor, since the closure is `@MainActor` and cannot mutate a
    /// captured `var`.
    @MainActor private final class WriteCounter {
        var calls = 0
    }

    /// The scenario PG-168 describes, reproduced with no timing: the pratica folder
    /// is moved from inside the write closure, right after the first note lands, so the second
    /// message is the one "in flight when the folder moved". It must be refused - not written
    /// under the vacated path, which used to recreate it.
    @Test func aRelocationBetweenTwoMessagesStopsTheRunInsteadOfWritingUnderTheVacatedPath() async throws {
        let fixture = try Self.fixture(messages: 2)
        let vaultRoot = try Fixtures.makeVaultRoot()
        let moved = "Calendar/\(Fixtures.praticaFolder)"
        let counter = WriteCounter()
        let engine = PraticaSyncEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot) { text, relativePath in
            let url = vaultRoot.appending(path: relativePath, directoryHint: .notDirectory)
            try Data(text.utf8).write(to: url, options: .atomic)
            counter.calls += 1
            guard counter.calls == 1 else { return }
            let destination = vaultRoot.appending(path: moved, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(
                at: vaultRoot.appending(path: Fixtures.praticaFolder, directoryHint: .isDirectory), to: destination
            )
        }

        await #expect(throws: VaultWriteRefusal.folderVanished(Fixtures.praticaFolder)) {
            _ = try await engine.sync(Self.request(messages: 2))
        }

        #expect(
            Fixtures.mdFiles(under: vaultRoot, folder: moved).count == 1,
            "the first message travelled with the folder"
        )
        #expect(
            !Self.exists(Fixtures.praticaFolder, under: vaultRoot),
            "the second message must not have recreated the vacated folder"
        )
    }

    // MARK: - The leftover notice

    @Test func aRelocationOrTrashNamesTheVacatedPathAndAVaultChangeSaysNothing() {
        let moved = PraticaRunStop.leftoverNotice(after: .praticaRelocated(from: "A", to: "B"))
        let trashed = PraticaRunStop.leftoverNotice(after: .praticaTrashed(path: "A"))

        #expect(moved?.path == "A")
        #expect(moved?.sentence.contains("«A»") == true)
        #expect(trashed?.path == "A")
        #expect(trashed?.sentence.contains("«A»") == true)
        #expect(PraticaRunStop.leftoverNotice(after: .vaultChanged) == nil)
    }
}
