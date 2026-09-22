import Foundation
import Testing
@testable import Pergamenum

// PG-169, ADR-0026 §D7's 2026-09-19 amendment (`docs/plans/pg-169-pratica-ledger-forgotten-
// on-folder-trash.md`, Task 4) - R-06: a pratica folder sent to the Trash WHILE its own sync
// or regeneration is still in flight must stop the run and discard its outcome, rather than
// let `recordSyncOutcome` put back the ledger key the trash just removed.
//
// The deletion twin of `Tests/PraticaLiveSyncRelocatedMidRunTests.swift`, and built the same
// way for the same reason (`Tests/PraticaLiveSyncRecordOutcomeTests.swift`'s own header,
// ADR-0046 §D2/§D11): no test here races a trash against a real sync by timing. "A trash has
// happened" is an entry in `forgottenPraticaPaths`, so every test installs it at the seam
// production code itself uses - `beginSync`/`beginRegeneration`, then the real
// `followFolderTrashing(_:in:)` - and drives `PraticaLiveSync`/`PraticheController` with the
// path the run captured. Fully deterministic. The folder itself stays on disk in the tests
// that run the real pipeline: what is under test is the controller's own state, and
// `runExclusive` needs a readable `pratica.md` to get past its first guard.
//
// The residual this cannot and does not claim to close is `PG-168`'s first case: the message
// being written at the instant of the trash can still land in the trashed folder and recreate
// it, since `PraticaSyncEngine.cancel()` is cooperative. What is asserted is the stop request
// and the discarded outcome, never that zero bytes land.

private let dossierNote = """
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
pergamenum-dossier-conversations: [112409]
---

Appunti pratica.
"""

private func syncOutcome(importing ids: [String], regenerated: [String] = []) -> PraticaSyncEngine.SyncOutcome {
    PraticaSyncEngine.SyncOutcome(
        writtenFiles: [], importedMessageIDs: ids, noLongerInMail: [], regeneratedPendingFiles: regenerated,
        cancelled: false, bridge: []
    )
}

/// What `praticaPath(continuing:)` throws for `path`, or `nil` when it lets the run continue.
@MainActor
private func stop(continuing path: String, on controller: PraticheController) -> PraticaRunStop? {
    do {
        _ = try controller.praticaPath(continuing: path)
        return nil
    } catch {
        return error as? PraticaRunStop
    }
}

/// A spy for `requestSyncStopForVanishedPath`, which is `@MainActor` and so cannot be counted
/// through a captured `var`.
@MainActor
private final class StopSpy {
    var requests = 0
}

@MainActor
@Suite(.serialized) struct PraticaLiveSyncTrashedMidRunTests {
    private static let folder = PraticaSyncFixtures.praticaFolder
    private static let moved = "Calendar/\(PraticaSyncFixtures.praticaFolder)"

    // MARK: - The one door, `praticaPath(continuing:)`

    @Test func praticaPathContinuingRefusesAPraticaThatWasTrashed() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing(Self.folder, in: VaultController())

        #expect(
            stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder),
            "a run whose folder went to the Trash must be told to stop, and told it was the Trash"
        )
    }

    /// A trash of an ANCESTOR reaches a run the same way: the claim is a descendant of what
    /// was trashed, which is the shape the whole subtree rule exists for.
    @Test func praticaPathContinuingRefusesAPraticaWhoseAncestorWasTrashed() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing("01 Progetti", in: VaultController())

        #expect(stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder))
    }

    /// The relocation chain and the tombstone meet: a run captured `folder`, the folder moved
    /// to `moved`, and it is `moved` that went to the Trash. The chain must resolve to
    /// `.forgotten`, never to `.moved` - a run told "it lives at `moved` now" would go and
    /// ask for a fresh run there.
    @Test func aTrashedPraticaIsRefusedEvenAfterARelocationHop() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let vault = VaultController()
        pratiche.beginSync(Self.folder)
        pratiche.followFolderRelocations([MovedNote(old: Self.folder, new: Self.moved)], in: vault)
        #expect(
            stop(continuing: Self.folder, on: pratiche) == .praticaRelocated(from: Self.folder, to: Self.moved),
            "precondition: before the trash, the same call answers the relocation"
        )

        pratiche.followFolderTrashing(Self.moved, in: vault)

        #expect(
            stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder),
            "the destination was trashed, so what the run captured is gone, not moved"
        )
    }

    @Test func praticaPathContinuingStillLetsAnUntouchedPraticaContinue() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing("01 Progetti-altro/Y", in: VaultController())

        #expect(stop(continuing: Self.folder, on: pratiche) == nil, "another folder's trash is not this run's")
    }

    // MARK: - What a finishing run writes back

    /// The headline for the regeneration half: `commitRegeneration` has no post-`await`
    /// re-check on purpose (`PG-168`'s third case), so `recordSyncOutcome` is the only guard
    /// standing between a finishing regeneration and the ledger key the trash just removed.
    @Test func recordSyncOutcomeWritesNothingForATrashedPratica() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        var seeded = PraticaLedger.PraticaState.empty
        seeded.importedMessageIDs = ["<preesistente@rossi-spa.it>"]
        // On disk and not in memory (ADR-0052 §D9): the trash below reads the file through the door.
        var seededLedger = PraticaLedger.empty
        seededLedger.byPraticaPath[Self.folder] = seeded
        try seededLedger.save(to: url)
        // Mirrors `beginRegeneration(plan.praticaFolder)`, claimed before `commitRegeneration`'s await.
        pratiche.beginRegeneration(Self.folder)

        pratiche.followFolderTrashing(Self.folder, in: vaultController)
        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "precondition: the trash itself removed the key")

        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<a@rossi-spa.it>"], regenerated: ["<a@rossi-spa.it>"]),
            for: Self.folder, session: session, isCurrentVault: true
        )

        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "the outcome must not resurrect the trashed key")
        #expect(
            PraticaLedger.load(from: url).byPraticaPath[Self.folder] == nil,
            "nor in the saved file - it must write nothing at all"
        )
        #expect(pratiche.problem == nil, "a discarded outcome is not a failure, so it reports nothing")
    }

    @Test func recordSyncOutcomeWritesNothingForAPraticaTrashedMidSync() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        // No ledger entry seeded: a pratica's first sync has none yet.
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing(Self.folder, in: vaultController)
        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<a@rossi-spa.it>"]),
            for: Self.folder, session: session, isCurrentVault: true
        )

        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil)
        #expect(PraticaLedger.load(from: PraticheController.ledgerURL(for: session)).byPraticaPath[Self.folder] == nil)
    }

    /// The tombstone describes the LIVE vault alone, exactly as the redirect map does: an
    /// outcome for a vault that is no longer live is recorded into its own file as always,
    /// whatever path this controller's live state has forgotten.
    @Test func recordSyncOutcomeForAStaleSessionIgnoresTheLiveVaultsTombstones() throws {
        let vaultA = try TemporaryVault()
        let staleSession = VaultSession(root: vaultA.root, stateBase: vaultA.stateBase)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())

        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<a@rossi-spa.it>"]),
            for: Self.folder, session: staleSession, isCurrentVault: false
        )

        let onDisk = PraticaLedger.load(from: PraticheController.ledgerURL(for: staleSession))
        #expect(
            onDisk.byPraticaPath[Self.folder]?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "the tombstone belongs to the live vault; a stale session's own ledger is not its business"
        )
    }

    // MARK: - The pipeline

    /// The trashed run ends `.finished`, never `.relocated(to:)`: `.relocated` drives
    /// `PraticaLiveSync.requeue`, and a re-enqueued run for a trashed pratica would only
    /// dequeue into `runExclusive`'s «non ha un dossier leggibile» report.
    @Test func runExclusiveReturnsFinishedForATrashedPraticaSoNothingIsRequeued() async throws {
        let vault = try TemporaryVault()
        try vault.write(dossierNote, to: "\(Self.folder)/pratica.md")
        let fixture = try MailStoreFixture.build(mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")], messages: [])
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath[Self.folder] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))

        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: vaultController)

        let outcome = await sync.runExclusive(praticaPath: Self.folder)

        #expect(outcome == .finished, "the caller must not be told a path to ask for: there is none")
        #expect(PraticaLiveSync.requeue(after: outcome, kind: .fsEvents) == nil, "so nothing is re-enqueued")
        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "the stopped run must not resurrect the trashed key")
        #expect(PraticaSyncFixtures.mdFiles(under: vault.root).isEmpty, "the stopped run wrote nothing")
        // The fixture flags the trash in the ledger but leaves `pratica.md` on disk (the run
        // has to read the dossier before it can be stopped), so a directory really does stand
        // at the vacated path: PG-168's leftover notice, and only it, is the right report. A
        // stop is never «Sincronizzazione non riuscita».
        #expect(
            pratiche.problem == PraticaRunStop.leftoverNotice(after: .praticaTrashed(path: Self.folder))?.sentence,
            "a run stopped by a deletion reports at most the leftover it can see, never a failure"
        )
        #expect(pratiche.syncingPraticaPath == nil, "the claim is released by the run's own defer")
        #expect(pratiche.forgottenPraticaPaths.isEmpty, "and with nothing in flight the tombstone goes with it")

        vaultController.close()
    }

    @Test func commitRegenerationRefusesAfterTheTrashAndWritesNothing() async throws {
        let messageID = "<abc123@rossi-spa.it>"
        let date = Date(timeIntervalSince1970: 1_749_557_170)
        let vault = try TemporaryVault()
        try vault.write(dossierNote, to: "\(Self.folder)/pratica.md")

        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it", mailboxRowID: 1,
                conversationID: 112_409, dateSent: date, dateReceived: date,
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        // Seeded directly, `PraticaLiveSyncRelocatedMidRunTests`' own pattern: a real
        // membership-rule sync is not what this test is about.
        let seedEngine = PraticaSyncFixtures.makeEngine(mailStoreURL: fixture.indexURL, vaultRoot: vault.root)
        let seedRequest = PraticaSyncEngine.SyncRequest(
            praticaFolder: Self.folder, dossier: PraticaSyncFixtures.sampleDossier(),
            candidates: [PraticaSyncFixtures.row(rowID: 1, messageID: messageID, date: date)],
            onDisk: [], settings: .default
        )
        _ = try await seedEngine.sync(seedRequest)

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController.live(vault: vaultController)

        await pratiche.prepareRegeneration?(Self.folder, messageID)
        guard case .ready(let plan) = pratiche.regeneration else {
            Issue.record("expected the preview to resolve to .ready before this test's own trash")
            vaultController.close()
            return
        }

        // The trash lands while this exact plan sits on the sheet.
        pratiche.followFolderTrashing(Self.folder, in: vaultController)

        guard let commit = pratiche.commitRegeneration else {
            Issue.record("expected PraticheController.live(vault:) to wire commitRegeneration")
            vaultController.close()
            return
        }
        let outcome = await commit(plan)

        #expect(outcome == .refused, "a trashed folder must refuse the commit rather than write into it")
        #expect(
            PraticaSyncFixtures.mdFiles(under: vault.root).count == 1,
            "nothing new may be written - only the one message the seed sync already wrote"
        )
        #expect(pratiche.regeneratingPraticaPaths.isEmpty, "the claim must be released exactly once, not leaked")
        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "and the refused commit records nothing")
        #expect(
            pratiche.problem?.contains("eliminata") == true,
            "the refusal must say the folder was deleted, not that it moved to a position that does not exist"
        )
        #expect(pratiche.problem?.contains("spostata") == false)

        vaultController.close()
    }

    // MARK: - Asking the engine to stop, and what a trash records

    @Test func liveWiringGivesTheControllerAWayToStopTheEngine() {
        let pratiche = PraticheController.live(vault: VaultController())

        #expect(
            pratiche.requestSyncStopForVanishedPath != nil,
            "the closure `forgetLedgerState` calls must be wired by `live(vault:)`, or a trash stops nothing"
        )
    }

    @Test func trashingAPraticaWithASyncInFlightAsksTheEngineToStop() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let spy = StopSpy()
        pratiche.requestSyncStopForVanishedPath = { spy.requests += 1 }
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing(Self.folder, in: VaultController())

        #expect(spy.requests == 1, "the engine keeps writing into the trashed folder until it is asked to stop")
    }

    @Test func trashingAnAncestorWithASyncInFlightAsksTheEngineToStop() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let spy = StopSpy()
        pratiche.requestSyncStopForVanishedPath = { spy.requests += 1 }
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing("01 Progetti", in: VaultController())

        #expect(spy.requests == 1)
    }

    @Test func trashingSomethingElseNeverAsksTheEngineToStop() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let spy = StopSpy()
        pratiche.requestSyncStopForVanishedPath = { spy.requests += 1 }
        let vault = VaultController()

        pratiche.followFolderTrashing(Self.folder, in: vault)
        #expect(spy.requests == 0, "nothing was running, so there is nothing to stop")

        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing("01 Progetti-altro/Y", in: vault)
        #expect(spy.requests == 0, "another folder's trash is not this run's, and would discard its work for nothing")
    }

    /// Review round 2's MINOR 1 rule, kept: a deletion with nothing running records no
    /// tombstone, since nothing will ever read one - the set would otherwise grow by one
    /// entry per deleted pratica for the life of the session.
    @Test func trashingAPraticaWithNoRunInFlightRecordsNoTombstone() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.updateLedger(.live(nil)) { $0.byPraticaPath[Self.folder] = .empty }
        pratiche.trayCounts[Self.folder] = 2

        pratiche.followFolderTrashing(Self.folder, in: VaultController())

        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "the state itself is still forgotten")
        #expect(pratiche.forgottenPraticaPaths.isEmpty, "but nothing was in flight to read a tombstone")
    }

    /// Design step 3, R-08's race: a pratica's very FIRST sync has no ledger entry yet
    /// (`state ... ?? .empty` never inserts one), so a tombstone driven by the dictionaries
    /// alone would never see it.
    @Test func aFirstSyncWithNoLedgerEntryYetIsStillTombstoned() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "precondition: no entry for this pratica")
        pratiche.beginSync(Self.folder)

        pratiche.followFolderTrashing(Self.folder, in: VaultController())

        #expect(pratiche.forgottenPraticaPaths == [Self.folder])
        #expect(stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder))
    }

    @Test func aRegenerationWithNoLedgerEntryYetIsStillTombstoned() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginRegeneration(Self.folder)

        pratiche.followFolderTrashing("01 Progetti", in: VaultController())

        #expect(pratiche.forgottenPraticaPaths == [Self.folder], "an ancestor's trash tombstones the claim it covers")
        #expect(
            pratiche.regeneratingPraticaPaths == [Self.folder],
            "and leaves the claim itself where the run will release it"
        )
    }

    // MARK: - The claim and the tombstone's lifetime

    @Test func endRegenerationReleasesAClaimATrashLeftInPlace() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginRegeneration(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())
        #expect(stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder))

        pratiche.endRegeneration(Self.folder)

        #expect(pratiche.regeneratingPraticaPaths.isEmpty, "the claim must be released, not leaked")
        #expect(pratiche.forgottenPraticaPaths.isEmpty, "and with nothing left in flight the tombstone is dropped")
    }

    /// The edge the resolver's `.forgotten` payload exists for: a relocation remapped the
    /// claim to `moved`, then `moved` was trashed. The claim `regeneratingPraticaPaths` holds
    /// is `moved`, not the path the caller captured, so releasing "the path as given" would
    /// leak it and `pruneRedirectsIfIdle` would never run again.
    @Test func endRegenerationReleasesTheClaimOfAPraticaRelocatedAndThenTrashed() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let vault = VaultController()
        pratiche.beginRegeneration(Self.folder)
        pratiche.followFolderRelocations([MovedNote(old: Self.folder, new: Self.moved)], in: vault)
        pratiche.followFolderTrashing(Self.moved, in: vault)
        #expect(pratiche.regeneratingPraticaPaths == [Self.moved], "precondition: the claim sits at the destination")

        pratiche.endRegeneration(Self.folder)

        #expect(pratiche.regeneratingPraticaPaths.isEmpty, "the caller's own captured path resolves to the claim held")
        #expect(pratiche.praticaPathRedirects.isEmpty)
        #expect(pratiche.forgottenPraticaPaths.isEmpty)
    }

    /// The tombstone is only meaningful while a run holds its claim: once the run ends, a
    /// pratica recreated under the same name is an ordinary pratica, not a refused one.
    @Test func theTombstoneIsDroppedWhenTheRunEndsSoARecreatedPraticaIsNotRefused() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())
        #expect(stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder))

        pratiche.endSync()

        #expect(pratiche.forgottenPraticaPaths.isEmpty)
        #expect(stop(continuing: Self.folder, on: pratiche) == nil, "the name is free to be a live pratica again")
    }

    // MARK: - A tombstone falls per path (PG-172 / PG-173's second half, ADR-0052 §D6)

    /// R-07. The refusal of a healthy sync by an UNRELATED open claim was the reported symptom:
    /// X's run ends while a «Rigenera…» on Y is still open, so nothing is idle and the old
    /// all-or-nothing prune kept X's tombstone, refusing a pratica recreated under X's name.
    @Test func endingXsSyncDropsXsTombstoneWhileAnotherPraticasClaimIsStillOpen() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let other = "01 Progetti/Altra"
        pratiche.beginSync(Self.folder)
        pratiche.beginRegeneration(other)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())
        pratiche.followFolderTrashing(other, in: VaultController())
        #expect(pratiche.forgottenPraticaPaths == [Self.folder, other], "precondition: both claims were tombstoned")

        pratiche.endSync()

        #expect(!pratiche.forgottenPraticaPaths.contains(Self.folder), "X's claim ended, so X's tombstone falls")
        #expect(pratiche.regeneratingPraticaPaths == [other], "Y's claim is still open")
        #expect(pratiche.forgottenPraticaPaths == [other], "and Y's own tombstone stays with it")
        #expect(stop(continuing: Self.folder, on: pratiche) == nil, "a recreated X is not refused")
        #expect(stop(continuing: other, on: pratiche) == .praticaTrashed(path: other), "while Y's stale claim still is")
    }

    /// R-08, PG-169's behaviour unchanged: a claim still open on X keeps X's tombstone, and that
    /// claim's outcome is still discarded.
    @Test func aClaimStillOpenOnXKeepsXsTombstone() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)
        pratiche.beginRegeneration(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())

        pratiche.endSync()

        #expect(pratiche.forgottenPraticaPaths == [Self.folder], "the regeneration claim on X is still open")
        #expect(stop(continuing: Self.folder, on: pratiche) == .praticaTrashed(path: Self.folder))
        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<a@rossi-spa.it>"]), for: Self.folder, session: session, isCurrentVault: true
        )
        #expect(pratiche.ledger.byPraticaPath[Self.folder] == nil, "the stale claim's outcome is discarded")
        let ledgerFile = PraticheController.ledgerURL(for: session).path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: ledgerFile), "and writes nothing at all")

        pratiche.endRegeneration(Self.folder)

        #expect(pratiche.forgottenPraticaPaths.isEmpty, "the last claim on X ending is what lets its tombstone go")
    }

    /// The regeneration twin of the first test.
    @Test func endingARegenerationDropsOnlyItsOwnTombstone() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let other = "01 Progetti/Altra"
        pratiche.beginRegeneration(Self.folder)
        pratiche.beginRegeneration(other)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())
        pratiche.followFolderTrashing(other, in: VaultController())
        #expect(pratiche.forgottenPraticaPaths == [Self.folder, other], "precondition")

        pratiche.endRegeneration(Self.folder)

        #expect(pratiche.forgottenPraticaPaths == [other], "only the ended regeneration's own tombstone fell")
        #expect(pratiche.regeneratingPraticaPaths == [other])
        #expect(stop(continuing: Self.folder, on: pratiche) == nil)
        #expect(stop(continuing: other, on: pratiche) == .praticaTrashed(path: other))
    }

    /// `destination(of:)` resolving to `.forgotten(current)`: the caller captured `folder`, a
    /// relocation moved the claim to `moved`, `moved` was trashed. The tombstone that must fall is
    /// `moved`'s, and a claim on another path must not be what keeps it.
    @Test func endingARelocatedThenTrashedRegenerationDropsTheTombstoneOfWhereItEndedUp() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let vault = VaultController()
        let other = "01 Progetti/Altra"
        pratiche.beginRegeneration(Self.folder)
        pratiche.beginRegeneration(other)
        pratiche.followFolderRelocations([MovedNote(old: Self.folder, new: Self.moved)], in: vault)
        pratiche.followFolderTrashing(Self.moved, in: vault)
        pratiche.followFolderTrashing(other, in: vault)
        #expect(pratiche.forgottenPraticaPaths == [Self.moved, other], "precondition")

        pratiche.endRegeneration(Self.folder)

        #expect(pratiche.regeneratingPraticaPaths == [other], "the claim held at the destination was released")
        #expect(pratiche.forgottenPraticaPaths == [other], "the destination's tombstone fell, the open claim's did not")
    }

    /// `confirmDeletion` calls `load(from:)` straight after its trash, still inside the same
    /// call stack as a run that may be in flight - clearing the tombstone there would erase it
    /// before the run it protects has looked (`moveLedgerState`'s own reason for the same rule
    /// on the redirect map).
    @Test func loadingTheSameVaultKeepsATombstoneAnInFlightRunStillNeeds() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: vaultController)

        pratiche.load(from: vaultController)

        #expect(pratiche.forgottenPraticaPaths == [Self.folder])
        vaultController.close()
    }

    @Test func loadingWithNoVaultDropsEveryTombstone() {
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.beginSync(Self.folder)
        pratiche.followFolderTrashing(Self.folder, in: VaultController())
        #expect(pratiche.forgottenPraticaPaths == [Self.folder], "precondition")

        pratiche.load(from: VaultController())

        #expect(pratiche.forgottenPraticaPaths.isEmpty, "a tombstone belongs to the vault that was live then")
    }
}
