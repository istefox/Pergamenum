import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md - regression
// coverage for the stale-session guard added to `PraticaLiveSync.runExclusive`
// (`Sources/Features/Pratiche/PraticheController.swift`).
//
// Investigation note (read before extending this file): `runExclusive` captures
// `let session = vault.session` before its two `await` suspension points (the
// detached Mail-store `prepare(...)` and `engine.sync(...)`), then guards
// `vault.session === session` before calling `recordSyncOutcome`/`updateTray` - if
// the person switched vaults mid-sync, the stale completion is dropped instead of
// writing into the wrong vault's ledger or refreshing the UI from the wrong vault.
//
// Reproducing that race end-to-end would need `vault.open(otherRoot)` to land
// deterministically between the capture and the guard. Nothing in `PraticaLiveSync`/
// `PraticaSyncEngine` exposes a hook to pause there (checked: no delay-injection
// point, no completion handshake for "prepare finished" a test could await before
// triggering the switch - see `PraticaSyncEngine.swift`'s only two `Task.yield()`
// call sites, neither reachable from outside). A `Task { await sync.run(...) }`
// racing a concurrent `await vault.open(...)` on the same `@MainActor` would depend
// on the relative timing of two independent real-I/O paths (`MailStoreCopy.publish`
// + `MailStoreReader` vs. a full vault rescan + thumbnail store creation), which is
// exactly the nondeterministic trigger this dispatch was told not to force. Neither
// existing pratiche fixture pattern drives `PraticaLiveSync` itself for the same
// reason: `PraticaSyncFixtures.makeEngine(mailStoreURL:vaultRoot:)` drives
// `PraticaSyncEngine` one layer below it, and `PraticheConnectorTests`'s
// `VaultSession(root:stateBase:)` never touches `PraticaLiveSync` at all.
//
// Fallback, per the dispatch brief: lock in the contract the guard depends on.
// `recordSyncOutcome(_:for:session:)` takes an explicit `VaultSession` and writes
// only into that session's own ledger file - never into "whatever `vault.session`
// happens to be right now". That is the property that makes
// `guard vault.session === session else { return }` meaningful in the first place;
// if a future edit made `recordSyncOutcome` read `vault.session` internally instead
// of the session it was handed, this test would catch it.
//
// Correction (RTF cycle 3, finding :1075): the "not a reachable production bug"
// claim this comment used to make here was wrong the moment `runExclusive` stopped
// guarding the call itself (the ledger write must survive a switch, only the
// UI-visible steps stay guarded - see that function's own comment). Calling
// `recordSyncOutcome` for a session that is NO LONGER live is now the normal path
// for a sync that finishes after the person has moved on, not an edge case to rule
// out. `isCurrentVault` (computed by the caller, since this type holds no
// `VaultController` to check it itself) is what keeps that safe: `false` reads and
// rewrites `session`'s own file fresh from disk instead of the shared, already-moved
// -on `self.ledger`, and never mutates `self.ledger` at all.
//
// Round-4 review (`docs/plans/pg-pratica-relocation-mid-sync-stop.md`), consumer-side
// conclusion, recorded so a future round does not re-litigate it: the same
// unreproducible-end-to-end finding above is why `PraticaRunStop`/`livePraticaPath(in:)`
// is tested by INSTALLING a `praticaPathRedirects` entry at a synchronous seam
// (`beginSync`/`beginRegeneration`, then `followFolderRelocations`) and driving
// production code with the resulting stale path, never by racing a real relocation
// against a real sync's timing - `Tests/PraticheControllerTests.swift`'s
// `PraticaLedgerFolderRelocationTests` and `PraticaLiveSyncRelocatedMidRunTests.swift`'s
// own suite both follow this without exception, and its regeneration-drop test needed
// two redesigns to get there. First, the plan's own suggestion - reusing
// `PraticaRegenerationSupersededPreviewTests`'s `waitUntil`-on-`regeneratingPratica
// Paths` pin plus a concurrent `Task`, on the theory that `prepareRegeneration`'s one
// `await` stays suspended long enough to interleave. Verified against this fixture and
// found not just unreliable but structurally impossible: that `await` never actually
// yields the MainActor back to the poller before running to full completion. Second, a
// seam-based fallback that called the real `prepareRegeneration` once, in full, after
// pre-installing its claim by hand - broken for a different reason, found only once
// written: `beginRegeneration` is not idempotent to repeat once a relocation has
// already reassigned `regeneratingPraticaPaths` wholesale, and `prepareRegeneration`
// begins its own claim unconditionally on its first line, so calling it as both "the
// stand-in for an already-open claim" and "the call under test" claims twice and
// leaks. The test that survived tests the same primitives `praticaPath(continuing:)`,
// `beginRegeneration` and `endRegeneration` directly, never the function that cannot be
// driven twice.
@MainActor
@Suite(.serialized) struct PraticaLiveSyncRecordOutcomeTests {
    @Test func recordSyncOutcomeWritesOnlyIntoTheExplicitSessionNeverAnotherOpenVault() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = VaultSession(root: vaultA.root, stateBase: vaultA.stateBase)
        let sessionB = VaultSession(root: vaultB.root, stateBase: vaultB.stateBase)

        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let praticaPath = "01 Progetti/Rossi/Offerta"
        let outcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: ["\(praticaPath)/email/20260610_richiesta-offerta.md"],
            importedMessageIDs: ["<abc@rossi-spa.it>"],
            noLongerInMail: [],
            regeneratedPendingFiles: [],
            cancelled: false,
            bridge: []
        )

        controller.recordSyncOutcome(outcome, for: praticaPath, session: sessionA, isCurrentVault: true)

        let ledgerA = PraticaLedger.load(from: PraticheController.ledgerURL(for: sessionA))
        #expect(ledgerA.byPraticaPath[praticaPath]?.importedMessageIDs == ["<abc@rossi-spa.it>"])

        let ledgerBURL = PraticheController.ledgerURL(for: sessionB)
        let ledgerB = PraticaLedger.load(from: ledgerBURL)
        #expect(
            ledgerB.byPraticaPath[praticaPath] == nil,
            "a sync outcome recorded against session A must never appear in session B's ledger"
        )
        #expect(
            !FileManager.default.fileExists(atPath: ledgerBURL.path(percentEncoded: false)),
            "recording against session A must not create session B's ledger file at all"
        )
    }

    /// The scenario the file header above used to dismiss as unreachable, now the
    /// normal shape of a sync that outlives the vault it started in: `runExclusive`
    /// calls this with `isCurrentVault: false` for exactly this case.
    @Test func recordSyncOutcomeForAStaleSessionWritesToItsOwnFileAndLeavesTheLiveLedgerAlone() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = VaultSession(root: vaultA.root, stateBase: vaultA.stateBase)
        let sessionB = VaultSession(root: vaultB.root, stateBase: vaultB.stateBase)

        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let praticaPathA = "01 Progetti/Rossi/Offerta"
        let praticaPathB = "01 Progetti/Verdi/Contratto"

        // Vault A is "live": its outcome is recorded as current, landing in the
        // controller's shared, observable `ledger`.
        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>"],
                noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
            ),
            for: praticaPathA, session: sessionA, isCurrentVault: true
        )
        let ledgerBeforeStaleWrite = controller.ledger

        // A sync against vault B finishes only NOW, after the person already switched
        // away from it (`isCurrentVault: false`, as `runExclusive` computes when
        // `vault.session` no longer equals the session it captured).
        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<b@verdi-srl.it>"],
                noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
            ),
            for: praticaPathB, session: sessionB, isCurrentVault: false
        )

        let ledgerB = PraticaLedger.load(from: PraticheController.ledgerURL(for: sessionB))
        #expect(
            ledgerB.byPraticaPath[praticaPathB]?.importedMessageIDs == ["<b@verdi-srl.it>"],
            "a stale sync's outcome must still reach its OWN session's ledger file on disk"
        )
        #expect(
            controller.ledger == ledgerBeforeStaleWrite,
            "the controller's shared, observable ledger tracks the LIVE vault only - a stale session's write must never appear in it"
        )
    }

    /// PG-169's regression guard (`docs/plans/pg-169-pratica-ledger-forgotten-on-folder-
    /// trash.md`, Task 4): `recordSyncOutcome` now resolves through a resolver that can also
    /// answer "forgotten", so an ordinary record for a pratica nobody trashed must be exactly
    /// what it was - including while a tombstone exists for a DIFFERENT pratica. The trashed
    /// side of the same call is `Tests/PraticaLiveSyncTrashedMidRunTests.swift`'s.
    @Test func recordSyncOutcomeStillWritesWhenSomeOtherPraticaWasTrashedMidRun() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let praticaPath = "01 Progetti/Rossi/Offerta"
        let trashedPath = "01 Progetti/Verdi/Contratto"
        controller.beginSync(praticaPath)
        controller.beginRegeneration(trashedPath)
        controller.followFolderTrashing(trashedPath, in: VaultController())
        #expect(controller.forgottenPraticaPaths == [trashedPath], "precondition: a tombstone exists for the other one")

        controller.recordSyncOutcome(
            PraticaSyncEngine.SyncOutcome(
                writtenFiles: [], importedMessageIDs: ["<abc@rossi-spa.it>"],
                noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
            ),
            for: praticaPath, session: session, isCurrentVault: true
        )

        #expect(
            controller.ledger.byPraticaPath[praticaPath]?.importedMessageIDs == ["<abc@rossi-spa.it>"],
            "a tombstone for another pratica must not swallow this one's outcome"
        )
        let onDisk = PraticaLedger.load(from: PraticheController.ledgerURL(for: session))
        #expect(onDisk.byPraticaPath[praticaPath]?.importedMessageIDs == ["<abc@rossi-spa.it>"])
        #expect(controller.ledger.byPraticaPath[trashedPath] == nil, "and the trashed one stays gone")
    }
}
