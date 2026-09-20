import Foundation
import Testing
@testable import Pergamenum

// Round-4 review, follow-up to `ba09c06` (`docs/plans/pg-pratica-relocation-mid-sync-
// stop.md`): a pratica folder relocated WHILE its own sync is still in flight must stop
// the run rather than keep writing under the vacated path. Kept out of
// `Tests/PraticheControllerTests.swift` on purpose (that file's own `file_length`
// budget, PG-160's shape applied here too) - only the three narrow `praticaPath(
// continuing:)` tests stay in `PraticaLedgerFolderRelocationTests` there, beside the
// redirect-map tests they extend.
//
// No test here races a relocation against a real sync by timing
// (`Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s own header, extended by this same
// plan): "a relocation has happened" is just an entry in `praticaPathRedirects`, so
// every test below installs it at the seam production code itself uses -
// `beginSync`/`beginRegeneration`, then the real `followFolderRelocations(_:in:)` - and
// drives `PraticaLiveSync`/`PraticheController` with the resulting stale path. Fully
// deterministic.
//
// `PraticaLiveSync` is constructed directly (`sync.controller = pratiche`, the same
// "not going through `PergamenumApp` in a test, so the hook is set by hand" shape
// `Tests/PraticheControllerTests.swift`'s `undoOfFolderMoveRestoresLedgerKey` already
// uses for `didRelocateFolders`) rather than through `PraticheController.live(vault:)`,
// which builds its own internal coordinator and hands back no reference to it - this
// suite needs to call `runExclusive(praticaPath:)` directly, bypassing `SyncRunQueue`.

private func dossierNoteText(conversations: [Int]) -> String {
    let conversationsList = conversations.map(String.init).joined(separator: ", ")
    return """
    ---
    date: 2026-09-01
    tags:
      - type-note
      - topic-pratica
      - client-rossi
      - status-active
      - source-email
    pergamenum-dossier: 1
    pergamenum-dossier-counterparts:
      - m.rossi@rossi-spa.it
    pergamenum-dossier-conversations: [\(conversationsList)]
    ---

    Appunti pratica.
    """
}

@MainActor
@Suite(.serialized) struct PraticaLiveSyncRelocatedMidRunTests {
    private static let old = PraticaSyncFixtures.praticaFolder
    private static let new = "Calendar/\(PraticaSyncFixtures.praticaFolder)"

    /// The headline (test 4): the run stops entirely once its own claimed path is found
    /// relocated, rather than writing - files or ledger keys - under the folder the
    /// relocation just vacated.
    @Test func aRelocationMidSyncStopsTheRunInsteadOfWritingUnderTheVacatedPath() async throws {
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.old)/pratica.md")
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.new)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        // Seeded BEFORE the relocation, so `followFolderRelocations` itself carries this
        // state to `new` (production's own remap) - proving the stopped run neither
        // resurrects `old` nor rewrites what the relocation already left at `new`.
        var seeded = PraticaLedger.PraticaState.empty
        seeded.importedMessageIDs = ["<preesistente@rossi-spa.it>"]
        // On disk and not in memory (ADR-0052 §D9): `followFolderRelocations` reads the file through
        // the door, so a value assigned to a controller that never loaded would be discarded.
        let session = try #require(vaultController.session)
        var seededLedger = PraticaLedger.empty
        seededLedger.byPraticaPath[Self.old] = seeded
        try seededLedger.save(to: PraticheController.ledgerURL(for: session))
        pratiche.trayCounts[Self.old] = 2
        pratiche.trayProposals[Self.old] = []

        // The seam every test in this file uses (this file's own header): `beginSync`
        // first, matching `runExclusive`'s own claim, then the real relocation.
        pratiche.beginSync(Self.old)
        pratiche.followFolderRelocations([MovedNote(old: Self.old, new: Self.new)], in: vaultController)
        let ledgerAtNewBeforeRun = pratiche.ledger.byPraticaPath[Self.new]

        let outcome = await sync.runExclusive(praticaPath: Self.old)

        #expect(outcome == .relocated(to: Self.new))
        #expect(
            PraticaSyncFixtures.mdFiles(under: vault.root, folder: Self.old).isEmpty,
            "nothing may be written under the vacated folder"
        )
        #expect(pratiche.ledger.byPraticaPath[Self.old] == nil, "the stopped run must not resurrect the orphaned key")
        #expect(
            pratiche.ledger.byPraticaPath[Self.new] == ledgerAtNewBeforeRun,
            "the relocated entry must be left exactly as the relocation itself left it"
        )
        #expect(pratiche.trayCounts[Self.old] == nil, "persistTrayCount must not re-insert a count at the vacated path")
        #expect(pratiche.trayProposals[Self.old] == nil, "updateTray must not re-insert proposals at the vacated path")

        vaultController.close()
    }

    /// Test 5, the narrower claim inside test 4's stop: even when Mail's own
    /// `conversation_id` for this pratica HAS changed (§D23.4's renumbering, the same
    /// shape `PraticaConversationRenumberingTests` exercises), a relocation caught at
    /// the very first guard - before `applyConversationRemap` ever runs - means
    /// `remapLedgerConversations` is never reached with the stale captured path at all,
    /// so the ledger's own conversation id is left exactly where the relocation itself
    /// left it, never repointed under either key by this run.
    @Test func aRelocationMidSyncLeavesTheRelocatedLedgerEntryUntouched() async throws {
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.old)/pratica.md")
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.new)/pratica.md")

        // Mail has already renumbered the conversation - `prepared.conversationRemap`
        // would be non-empty, exactly the condition `applyConversationRemap` exists for.
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 550_001, dateSent: Date(timeIntervalSince1970: 1000),
                dateReceived: Date(timeIntervalSince1970: 1000),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        var seeded = PraticaLedger.PraticaState.empty
        seeded.entries = [PraticaLedger.Entry(messageID: "<abc123@rossi-spa.it>", rowID: 1, conversationID: 112_409)]
        let session = try #require(vaultController.session)
        var seededLedger = PraticaLedger.empty
        seededLedger.byPraticaPath[Self.old] = seeded
        try seededLedger.save(to: PraticheController.ledgerURL(for: session))

        pratiche.beginSync(Self.old)
        pratiche.followFolderRelocations([MovedNote(old: Self.old, new: Self.new)], in: vaultController)

        _ = await sync.runExclusive(praticaPath: Self.old)

        #expect(pratiche.ledger.byPraticaPath[Self.old] == nil)
        #expect(
            pratiche.ledger.byPraticaPath[Self.new]?.entries.first?.conversationID == 112_409,
            "remapLedgerConversations must never be reached once the run has already stopped for relocation"
        )

        vaultController.close()
    }

    /// Test 6: the caller must learn not just THAT the run stopped, but WHERE the
    /// pratica lives now - `.finished` alone would leave `new` never synced again
    /// (this file's own header's "counterweight, verified": nothing re-triggers a sync
    /// on its own).
    @Test func runExclusiveReportsTheRelocationSoTheNewPathIsSyncedAgain() async throws {
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.old)/pratica.md")

        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        pratiche.beginSync(Self.old)
        pratiche.followFolderRelocations([MovedNote(old: Self.old, new: Self.new)], in: vaultController)

        let outcome = await sync.runExclusive(praticaPath: Self.old)

        #expect(
            outcome == .relocated(to: Self.new),
            "the caller must be told the new path, not just that the run stopped, or nothing ever syncs the relocated pratica again"
        )

        vaultController.close()
    }

    /// Test 9: «Rigenera…»'s own commit, refused the same way once its captured folder
    /// has relocated - `plan.praticaFolder` was fixed when the preview ran, and the diff
    /// may have sat on screen long enough for the folder to move before the person
    /// agreed to it.
    @Test func commitRegenerationRefusesAfterTheRelocationInsteadOfWritingUnderTheVacatedPath() async throws {
        let messageID = "<abc123@rossi-spa.it>"
        let date = Date(timeIntervalSince1970: 1_749_557_170)
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(Self.old)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: date, dateReceived: date,
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        UserDefaults.standard.set(fixture.root.path(percentEncoded: false), forKey: MailStoreLocation.overrideKey)
        defer { UserDefaults.standard.removeObject(forKey: MailStoreLocation.overrideKey) }

        // Seeded directly (`PraticaRegenerationSupersededPreviewTests`'s own pattern): a
        // real membership-rule sync is not what this test is about.
        let seedEngine = PraticaSyncFixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vault.root)
        let seedRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.old, dossier: PraticaSyncFixtures.sampleDossier(),
            candidates: [PraticaSyncFixtures.row(rowID: 1, messageID: messageID, date: date)],
            onDisk: [], settings: .default
        )
        _ = try await seedEngine.sync(seedRequest)

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController.live(vault: vaultController)

        await pratiche.prepareRegeneration?(Self.old, messageID)
        guard case .ready(let plan) = pratiche.regeneration else {
            Issue.record("expected the preview to resolve to .ready before this test's own relocation")
            vaultController.close()
            return
        }

        // The relocation lands while this exact plan sits on the sheet - the seam this
        // suite always uses instead of a real timing race.
        pratiche.followFolderRelocations([MovedNote(old: Self.old, new: Self.new)], in: vaultController)

        guard let commit = pratiche.commitRegeneration else {
            Issue.record("expected PraticheController.live(vault:) to wire commitRegeneration")
            vaultController.close()
            return
        }
        let outcome = await commit(plan)

        #expect(outcome == .refused, "a relocated folder must refuse the commit rather than write under the vacated path")
        #expect(
            PraticaSyncFixtures.mdFiles(under: vault.root, folder: Self.old).count == 1,
            "nothing new may be written under the vacated folder - only the one message the seed sync already wrote"
        )
        #expect(pratiche.regeneratingPraticaPaths.isEmpty, "the claim must be released exactly once, not leaked")
        #expect(pratiche.problem != nil, "the refusal must be reported so the person knows where the files went")
        #expect(
            pratiche.problem?.hasSuffix("recuperabili da lì.") == true,
            "the refusal's own sentence must survive the restore that follows it (PG-168)"
        )

        vaultController.close()
    }

    /// Test 10, twice redesigned - both deviations recorded here since a third round
    /// should not have to re-derive either.
    ///
    /// First attempt matched the plan's own suggestion: pin `prepareRegeneration`'s one
    /// `await` with the round-3 `waitUntil` tool (`PraticaRegenerationSupersededPreview
    /// Tests`'s pattern - claim, poll `regeneratingPraticaPaths`, then act). Verified
    /// against this fixture and found not just unreliable but structurally impossible:
    /// `engine.regenerationPreview`'s one `await` never actually yields the MainActor
    /// back to the poller before running to full completion, so the relocation always
    /// lands too late - the same class of race `Tests/PraticaLiveSyncRecordOutcomeTests
    /// .swift`'s header already found unreproducible for `runExclusive`, for the same
    /// reason (no controllable suspension point reachable from outside).
    ///
    /// Second attempt tried this file's own fallback seam instead - `beginRegeneration`
    /// before the relocation, then one complete, un-raced `prepareRegeneration` call -
    /// on the wrong assumption that `beginRegeneration` is idempotent to repeat. It is
    /// not, once a relocation has already run: `moveLedgerState` reassigns
    /// `regeneratingPraticaPaths` wholesale (old entries out, remapped entries in), so a
    /// SECOND `beginRegeneration(old)` call afterwards - which is exactly what calling
    /// the real `prepareRegeneration` a second time does, on its own very first line -
    /// re-inserts the raw, un-remapped `old` value alongside the already-remapped `new`
    /// one. `endRegeneration` only ever resolves and removes the CURRENT value, so the
    /// stale `old` entry it did not insert is never the one it looks for, and leaks.
    /// `commitRegeneration` (test 9 above) has no such problem because it never calls
    /// `beginRegeneration` at all - it only ever resolves and ends a claim someone else
    /// already made, so composing it with a manual prior `beginRegeneration` is safe.
    /// `prepareRegeneration` IS the one call that begins, so it cannot be both "the
    /// stand-in for an already-open claim" and "the call under test" without claiming
    /// twice.
    ///
    /// Resolution: test the contract `prepareRegeneration`'s guard 3 and its catch
    /// block depend on directly, at the same primitives tests 1-3 exercise
    /// (`praticaPath(continuing:)`) plus the two this plan adds for regeneration
    /// (`beginRegeneration`/`endRegeneration`), without going through the function that
    /// cannot be driven twice. `PraticaLiveSync.swift:361-368`'s three statements
    /// (`regeneration = nil`, `endRegeneration(praticaPath)`, `report(...)`) are the
    /// only thing this leaves unverified by a test, past reading the diff - the same
    /// residual this codebase already accepted for `runExclusive`'s stale-session guard.
    @Test func endRegenerationReleasesAClaimARelocationRemappedWhileItWasStillHeld() throws {
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })

        // `prepareRegeneration`'s own first line, before its one `await`.
        pratiche.beginRegeneration(Self.old)

        // The relocation lands while that claim is still open - this suite's own seam.
        pratiche.followFolderRelocations([MovedNote(old: Self.old, new: Self.new)], in: vaultController)
        #expect(
            pratiche.regeneratingPraticaPaths == [Self.new],
            "moveLedgerState keeps regeneratingPraticaPaths itself live-updated to the current path"
        )

        // `prepareRegeneration`'s guard 3, resuming from its `await`: the original
        // captured value resolves through the redirect and is refused.
        do {
            _ = try pratiche.praticaPath(continuing: Self.old)
            Issue.record("expected praticaPath(continuing:) to throw for a relocated pratica")
        } catch PraticaRunStop.praticaRelocated(let from, let to) {
            #expect(from == Self.old)
            #expect(to == Self.new)
        }

        // ...and releases with the SAME original value the guard was given - resolving
        // it is `endRegeneration`'s own job, not the caller's.
        pratiche.endRegeneration(Self.old)

        #expect(
            pratiche.regeneratingPraticaPaths.isEmpty,
            "the claim, resolved through the redirect to the new path, must be released, not leaked"
        )
    }
}

// MARK: - Tests 7-8: the pure re-enqueue decision, no async work behind it

@Suite struct PraticaLiveSyncRequeueTests {
    @Test func requeueAfterRelocationAsksForTheNewPathWithTheSameTriggerKind() {
        let requeued = PraticaLiveSync.requeue(after: .relocated(to: "Calendar/X"), kind: .fsEvents)
        #expect(requeued?.path == "Calendar/X")
        #expect(
            requeued?.kind == .fsEvents,
            "the SAME trigger kind the relocated run was itself running under, never a hard-coded .manualRefresh"
        )
    }

    @Test func requeueAfterAnOrdinaryFinishAsksForNothing() {
        #expect(PraticaLiveSync.requeue(after: .finished, kind: .manualRefresh) == nil)
    }

    /// Test 8: the requeued request must land BEHIND the aborting run, in `pending`,
    /// never dropped - `SyncRunQueue.request` returns `nil` while `isRunning` is still
    /// `true`, exactly the state `run(praticaPath:kind:)`'s loop is in at the moment it
    /// re-requests the relocated path.
    @Test func aRequeuedRelocationRequestQueuesBehindTheAbortingRunInsteadOfBeingDropped() {
        var queue = SyncRunQueue()
        let started = queue.request(Self.oldPath)
        #expect(started == Self.oldPath)

        let queuedWhileStillRunning = queue.request(Self.newPath)
        #expect(queuedWhileStillRunning == nil, "must queue, not start, while the aborting run still holds the slot")

        let next = queue.finished()
        #expect(next == Self.newPath, "the requeued relocation must be dequeued next, never dropped")
    }

    private static let oldPath = "01 Progetti/Tifone/X"
    private static let newPath = "Calendar/01 Progetti/Tifone/X"
}

// MARK: - §6: the write-ordering fix behind `applyConversationRemap`

@Suite struct MailStorePreparationWriteOrderingTests {
    /// Pins the exact shape the plan's §6 describes: with the ledger ALREADY repointed
    /// to a renumbered conversation id but the note's own frontmatter still listing the
    /// old one (the state the old, unordered write left behind whenever it was refused
    /// or threw), `resolveFollowedConversations`' ledger-based recovery filters by the
    /// OLD id and finds nothing, so no remap is ever recomputed - this is what makes
    /// "write the note first, repoint the ledger only on success" non-negotiable rather
    /// than a matter of taste.
    @Test func prepareRecomputesNoRemapOnceTheLedgerIsRepointedButTheDossierIsNot() throws {
        let oldConversationID = 112_409
        let newConversationID = 550_001
        let messageID = "<abc123@rossi-spa.it>"
        let date = Date(timeIntervalSince1970: 1000)

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: newConversationID, dateSent: date, dateReceived: date,
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        let stateDirectory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-mailstore-state-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let dossier = PraticaSyncFixtures.sampleDossier(conversations: [oldConversationID])
        let ledgerEntries = [
            PraticaLedger.Entry(messageID: messageID, rowID: 1, conversationID: newConversationID),
        ]
        let window = date.addingTimeInterval(-86_400)...date.addingTimeInterval(86_400)

        let result = MailStorePreparation.prepare(
            mailRoot: fixture.root, stateDirectory: stateDirectory, dossier: dossier,
            ledgerEntries: ledgerEntries, proposalWindow: window
        )

        guard case .ready(let prepared) = result else {
            Issue.record("expected .ready, got \(result)")
            return
        }
        #expect(
            prepared.conversationRemap.isEmpty,
            "with the ledger already pointing at the new id, filtering by the OLD id finds no known member left to recover from"
        )
    }
}

// MARK: - §6: `follow`/`ignore` re-read `pratiche.selection` AFTER their own `await`

@MainActor
@Suite struct PraticaCommandActionsFollowIgnoreReReadTests {
    /// A genuine interleaving test would need a synchronous claim analogous to
    /// `beginSync`/`regeneratingPraticaPaths` - the seam every other test in this file
    /// installs state at - and neither `follow` nor `ignore` has one:
    /// `pratiche.selection` is an ordinary property, not a per-pratica in-flight set.
    /// `Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s own header already rules out
    /// forcing a race by timing instead. What this proves is narrower but still real:
    /// the second guard this fix added does not silently break the ordinary, no-race
    /// path - the proposal is still dismissed at the pratica actually selected once the
    /// write returns.
    @Test func followDismissesTheProposalAtTheSelectionCurrentWhenTheWriteReturns() async throws {
        let praticaPath = PraticaSyncFixtures.praticaFolder
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.select(praticaPath, in: vaultController)
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        let proposal = try #require(Self.proposal(conversationID: 550_001))
        pratiche.trayProposals[praticaPath] = [proposal]

        await actions.follow(proposal)

        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.conversations.contains(550_001), "follow must still write the conversation it was asked to follow")
        #expect(
            pratiche.trayProposals[praticaPath]?.contains { $0.conversationID == 550_001 } == false,
            "the proposal must be dismissed at the pratica actually selected once the write returns"
        )

        vaultController.close()
    }

    @Test func ignoreDismissesTheProposalAtTheSelectionCurrentWhenTheWriteReturns() async throws {
        let praticaPath = PraticaSyncFixtures.praticaFolder
        let vault = try TemporaryVault()
        try vault.write(dossierNoteText(conversations: [112_409]), to: "\(praticaPath)/pratica.md")

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.select(praticaPath, in: vaultController)
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        let proposal = try #require(Self.proposal(conversationID: 550_001))
        pratiche.trayProposals[praticaPath] = [proposal]

        await actions.ignore(proposal)

        let dossier = try #require(PraticheController.dossier(at: praticaPath, vaultRoot: vault.root))
        #expect(dossier.ignored.contains(550_001), "ignore must still write the conversation into pergamenum-dossier-ignored")
        #expect(
            pratiche.trayProposals[praticaPath]?.contains { $0.conversationID == 550_001 } == false,
            "the proposal must be dismissed at the pratica actually selected once the write returns"
        )

        vaultController.close()
    }

    private static func proposal(conversationID: Int) -> PraticaTrayModel.PraticaTrayProposal? {
        let row = MailMessageRow(
            rowID: 1, indexMessageIDHash: 1, globalMessageID: 1, subject: "Richiesta offerta",
            sender: "m.rossi@rossi-spa.it", dateSent: Date(timeIntervalSince1970: 1000), dateReceived: nil,
            mailbox: MailboxRef(rowID: 1, url: "ews://acct1/INBOX"), conversationID: conversationID,
            deleted: false, messageID: "<abc@rossi-spa.it>"
        )
        return PraticaTrayModel.proposals(from: [MembershipRule.TrayEntry(conversationID: conversationID, messages: [row])]).first
    }
}
