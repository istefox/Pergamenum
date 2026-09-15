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

// MARK: - §D21 - «Rigenera» acquires the replacement before it destroys anything

// ADR §D21, plan docs/superpowers/plans/2026-09-10-pratiche-pg105-pg108.md, Task 5 -
// `regenerationPreview`/`commitRegeneration` are declared-but-stubbed by this batch's
// tester (ADR-0155 §D1): both always throw `RegenerationFailure.rowNotFound`
// unconditionally, so every test below is red because the stub never resolves a row or
// writes anything, not because a symbol is missing.
@Suite struct PraticaRegenerationTests {
    private typealias Fixtures = PraticaSyncFixtures

    private static let messageID = "<abc123@rossi-spa.it>"

    /// `syncedFixtureAndVault()`'s four parts, named rather than a bare tuple.
    private struct SyncedVault {
        var fixture: MailStoreFixture.Built
        var vaultRoot: URL
        var engine: PraticaSyncEngine
        var request: PraticaSyncEngine.SyncRequest
    }

    /// Builds a fixture with the one standard message this whole suite regenerates,
    /// and a fresh vault it has already been synced into once.
    private static func syncedFixtureAndVault() async throws -> SyncedVault {
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let vaultRoot = try Fixtures.makeRegenerationVaultRoot()
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: Self.messageID)],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)
        return SyncedVault(fixture: fixture, vaultRoot: vaultRoot, engine: engine, request: request)
    }

    /// The one `.md` note the fixture above writes, and its vault-relative path.
    private static func writtenNote(under vaultRoot: URL) throws -> (path: String, text: String) {
        let emailDir = vaultRoot.appending(path: "\(Fixtures.praticaFolder)/email", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        let name = try #require(names.first { $0.hasSuffix(".md") }, "the first sync must have written a note")
        let url = emailDir.appending(path: name, directoryHint: .notDirectory)
        let text = try String(contentsOf: url, encoding: .utf8)
        return ("\(Fixtures.praticaFolder)/email/\(name)", text)
    }

    @Test func regenerationPreviewReplacementTextMatchesTheOriginalImportAndDiffIsNilUntilEdited() async throws {
        let synced = try await Self.syncedFixtureAndVault()
        let (notePath, originalText) = try Self.writtenNote(under: synced.vaultRoot)

        // Unmodified: the file on disk already matches what a fresh import would
        // write, so there is nothing to show a diff of.
        let unchangedPlan = try await synced.engine.regenerationPreview(synced.request, messageID: Self.messageID, rowID: nil)
        #expect(unchangedPlan.notePath == notePath)
        #expect(unchangedPlan.currentText == originalText)
        #expect(
            unchangedPlan.replacementText == originalText,
            "re-decoding the same .emlx must reproduce the same note text"
        )
        #expect(unchangedPlan.diff == nil, "current and replacement are identical; there is nothing to diff")

        // Hand-edited: the replacement is still what a fresh import would write, but
        // now it differs from what is on disk, so a diff must be shown.
        let handEditedText = originalText + "\n\nAggiunto a mano.\n"
        try Data(handEditedText.utf8).write(
            to: synced.vaultRoot.appending(path: notePath, directoryHint: .notDirectory), options: .atomic
        )
        let editedPlan = try await synced.engine.regenerationPreview(synced.request, messageID: Self.messageID, rowID: nil)
        #expect(editedPlan.currentText == handEditedText)
        #expect(editedPlan.replacementText == originalText, "the replacement is unaffected by the hand edit")
        #expect(editedPlan.diff != nil, "a hand-edited file must produce a non-nil diff against the replacement")
    }

    @Test func commitRegenerationWritesExactlyThePlansReplacementTextToItsNotePath() async throws {
        let synced = try await Self.syncedFixtureAndVault()
        let (notePath, originalText) = try Self.writtenNote(under: synced.vaultRoot)
        let noteURL = synced.vaultRoot.appending(path: notePath, directoryHint: .notDirectory)
        try Data((originalText + "\n\nAggiunto a mano.\n").utf8).write(to: noteURL, options: .atomic)

        let plan = try await synced.engine.regenerationPreview(synced.request, messageID: Self.messageID, rowID: nil)
        _ = try await synced.engine.commitRegeneration(plan)

        let writtenText = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(
            writtenText == plan.replacementText,
            "commitRegeneration must write exactly the previewed replacement text, not re-acquire it"
        )
    }

    // ADR §D4/§D21: the `.emlx` is genuinely gone - the acquisition must fail with
    // `.notInStore` specifically (never a bug, R-16's own case), and touch no file. A
    // test that only asserted "throws" would already pass against the stub for the
    // wrong reason, since the stub always throws unconditionally
    // (`RegenerationFailure.rowNotFound`); asserting the exact case is what keeps this
    // one red until the coder distinguishes "no row" from "row found, no .emlx".
    @Test func regenerationPreviewFailsWithNotInStoreWhenTheEmlxIsGoneAndTheFileOnDiskIsUntouched() async throws {
        let synced = try await Self.syncedFixtureAndVault()
        let (notePath, originalText) = try Self.writtenNote(under: synced.vaultRoot)

        // The row still resolves from the index; only the underlying `.emlx` file is
        // gone.
        let everyFile = (FileManager.default.enumerator(at: synced.fixture.root, includingPropertiesForKeys: nil)?
            .allObjects as? [URL]) ?? []
        for url in everyFile where url.pathExtension == "emlx" {
            try FileManager.default.removeItem(at: url)
        }

        do {
            _ = try await synced.engine.regenerationPreview(synced.request, messageID: Self.messageID, rowID: nil)
            Issue.record("expected regenerationPreview to throw RegenerationFailure.notInStore")
        } catch let failure as PraticaSyncEngine.RegenerationFailure {
            #expect(failure == .notInStore, "the row resolves; only the .emlx is missing - this is R-16's case, not rowNotFound")
        } catch {
            Issue.record("expected RegenerationFailure.notInStore, got \(error)")
        }

        let bytesAfter = try Data(contentsOf: synced.vaultRoot.appending(path: notePath, directoryHint: .notDirectory))
        #expect(bytesAfter == Data(originalText.utf8), "a failed acquisition must never touch the file on disk")
    }
}
