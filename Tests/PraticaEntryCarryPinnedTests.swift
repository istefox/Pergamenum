import Foundation
import Testing
@testable import Pergamenum

// ADR-0076 §D6 (PG-338), plan docs/plans/pratiche-message-anchored-entries.md, Task 5 -
// R-13, R-16, R-17: Escludi, «Aggiungi anche a…» and «Rigenera» gain no code and write no
// `pratica.md` body; these pin that. Also here, the other file being at its length limit:
// the carry's start condition when only the sidecar moved. Beside `PraticaEntryCarryTests.swift`, on its harness,
// in a file of its own to keep both under SwiftLint's file_length warning.

@MainActor
@Suite(.serialized) struct PraticaEntryCarryPinnedTests {
    private typealias Rig = CarryHarness

    // MARK: - R-13

    @Test func excludeLeavesTheEntriesByteIdenticalAndOrphanedAndUndoAnchorsThemAgain() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let bodyBefore = Rig.body(try harness.text(Rig.sourceNote))
        let (entry, detail) = try harness.row(Rig.messageID)

        await harness.actions.exclude(entry, detail: detail)

        #expect(!harness.exists("\(Rig.source)/\(Rig.messageFile)"))
        #expect(try harness.text(Rig.sourceNote).contains("pergamenum-dossier-excluded"))
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == bodyBefore)
        let excluded = harness.entryPlacements(in: Rig.source)
        #expect(excluded.filter { $0 == .orphaned(messageID: Rig.messageID) }.count == 2)
        #expect(!excluded.contains(.anchored(messageID: Rig.messageID)))

        harness.manager.undo()
        try await waitUntil {
            harness.exists("\(Rig.source)/\(Rig.messageFile)")
                && (try? harness.text(Rig.sourceNote))?.contains("pergamenum-dossier-excluded") == false
        }

        #expect(Rig.body(try harness.text(Rig.sourceNote)) == bodyBefore)
        #expect(harness.entryPlacements(in: Rig.source).filter { $0 == .anchored(messageID: Rig.messageID) }.count == 2)
        harness.controller.close()
    }

    // MARK: - R-16

    @Test func alsoAddLeavesBothBodiesAndShowsTheCopyWithNoEntryUnderIt() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let (entry, detail) = try harness.row(Rig.messageID)

        await harness.actions.alsoAdd(entry, detail: detail, to: harness.destinationItem)

        #expect(harness.exists("\(Rig.source)/\(Rig.messageFile)"))
        #expect(harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == Rig.sourceBody)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.destinationBody)
        #expect(harness.entryPlacements(in: Rig.destination).isEmpty)
        #expect(harness.pratiche.timeline.map(\.messageID) == [Rig.messageID])
        harness.controller.close()
    }

    // MARK: - R-17 (the `PraticaRegenerationTests` harness)

    @Test func regenerationLeavesPraticaUnwrittenAndTheEntriesAnchored() async throws {
        typealias Fixtures = PraticaSyncFixtures
        let messageID = "<abc123@rossi-spa.it>"
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
        defer { try? FileManager.default.removeItem(at: vaultRoot) }
        let engine = Fixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vaultRoot)
        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: Fixtures.praticaFolder, dossier: Fixtures.sampleDossier(),
            candidates: [Fixtures.row(rowID: 1, messageID: messageID)],
            onDisk: [], settings: .default
        )
        _ = try await engine.sync(request)

        let imported = PraticheController.readTimeline(praticaPath: Fixtures.praticaFolder, vaultRoot: vaultRoot)
        let anchor = try #require(imported.entries.first { $0.kind == .message }?.messageID)
        let line = try #require(PraticaEntryAnchor.line(for: anchor))
        let praticaURL = vaultRoot.appending(
            path: PraticaNaming.praticaNotePath(of: Fixtures.praticaFolder), directoryHint: .notDirectory
        )
        let pratica = "---\npergamenum-dossier: 1\n---\n\n"
            + "## 2026-06-10 10:00 Nota · Mario Rossi\n\(line)\nPrima voce.\n\n"
            + "## 2026-06-10 12:00 Telefonata · Mario Rossi\n\(line)\nSeconda voce.\n"
        try Data(pratica.utf8).write(to: praticaURL)

        let plan = try await engine.regenerationPreview(request, messageID: messageID, rowID: nil)
        _ = try await engine.commitRegeneration(plan)

        #expect(try Data(contentsOf: praticaURL) == Data(pratica.utf8))
        let after = PraticheController.readTimeline(praticaPath: Fixtures.praticaFolder, vaultRoot: vaultRoot)
        let placements = PraticaTimelineModel.ordered(after.entries).filter { $0.kind != .message }.map(\.placement)
        #expect(placements == [.anchored(messageID: anchor), .anchored(messageID: anchor)])
    }

    // MARK: - R-14, the start condition

    /// `moveFiles` moves the `.md` and the `.eml` independently. An immutable `.md` makes its
    /// own move fail while the sidecar moves: the message is still in the source, so its entries
    /// must stay there, anchored to it, and nothing is appended to the destination.
    @Test func aMessageNoteThatDidNotMoveKeepsItsEntriesInTheSourceWhileItsSidecarMoved() async throws {
        let vault = try TemporaryVault()
        let harness = try await Rig.open(vault.root)
        let sidecar = "\(Rig.messageFile.dropLast(2))eml"
        try Rig.write("sidecar", to: "\(Rig.source)/\(sidecar)", under: vault.root)
        let note = vault.root.appending(path: "\(Rig.source)/\(Rig.messageFile)", directoryHint: .notDirectory)
        var immutable = URLResourceValues()
        immutable.isUserImmutable = true
        var noteURL = note
        try noteURL.setResourceValues(immutable)
        defer {
            var mutable = URLResourceValues()
            mutable.isUserImmutable = false
            try? noteURL.setResourceValues(mutable)
        }
        let sourceBefore = try harness.text(Rig.sourceNote)
        let destinationBefore = try harness.text(Rig.destinationNote)

        try await harness.move()

        try #require(harness.exists("\(Rig.destination)/\(sidecar)"), "the sidecar moved")
        #expect(harness.exists("\(Rig.source)/\(Rig.messageFile)"), "the message note did not")
        #expect(!harness.exists("\(Rig.destination)/\(Rig.messageFile)"))
        #expect(Rig.body(try harness.text(Rig.sourceNote)) == Rig.body(sourceBefore))
        #expect(PraticaEntryEdit.blocks(anchoredTo: Rig.messageID, in: try harness.text(Rig.sourceNote)).count == 2)
        #expect(try harness.text(Rig.destinationNote).contains("pergamenum-message") == false)
        #expect(Rig.body(try harness.text(Rig.destinationNote)) == Rig.body(destinationBefore))
        let problem = try #require(harness.pratiche.problem)
        #expect(!problem.contains("voci collegate"), "\(problem)")
        harness.controller.close()
    }
}
