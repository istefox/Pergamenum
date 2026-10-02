import Foundation
import Testing
@testable import Pergamenum

// Split out of `PraticheControllerTests.swift` under PG-293 (#638) to clear its SwiftLint
// `file_length` warning: a pure move, no test changed. The suite's review-round tests sit in
// `PraticheControllerTests+FolderRelocationRedirects.swift`.

// MARK: - PG "allegati non si scaricano": a folder relocation must not orphan the ledger
//
// `PraticheController.moveLedgerState(from:to:in:)` (`PraticheController+Ledger.swift`)
// used to be an exact-key swap, reachable only from the pratica's own «Rinomina…». It is
// now subtree-aware and reachable from the generic ADR-0026 batch move/rename path too,
// via `VaultController.didRelocateFolders` → `followFolderRelocations(_:in:)`. The bug
// this fixes: a pratica that is a *descendant* of a moved or renamed ancestor folder
// never had its ledger key move, so `PraticaSyncEngine.regeneratePending`'s ledger
// fallback silently found nothing there forever.

@MainActor
@Suite(.serialized) struct PraticaLedgerFolderRelocationTests {
    @Test func moveLedgerStateRemapsExactKey() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        // No session in these tests, so the ledger is seeded through the door: marker `.none`,
        // target `nil`, memory only (ADR-0052 §D9).
        controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti/Tifone/X"] = .empty }
        let vault = VaultController()

        controller.moveLedgerState(from: "01 Progetti/Tifone/X", to: "Calendar/01 Progetti/Tifone/X", in: vault)

        #expect(controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] == nil)
        #expect(controller.ledger.byPraticaPath["Calendar/01 Progetti/Tifone/X"] != nil)
    }

    @Test func moveLedgerStateRemapsDescendantPraticheUnderMovedAncestor() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        var state = PraticaLedger.PraticaState.empty
        state.importedMessageIDs = ["<a@rossi-spa.it>"]
        controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti/Tifone/X"] = state }
        let vault = VaultController()

        // The actual bug shape: the pratica itself is not the moved item, an ANCESTOR of
        // it is.
        controller.moveLedgerState(from: "01 Progetti", to: "Calendar/01 Progetti", in: vault)

        #expect(
            controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] == nil,
            "the orphaned old key must not linger once the remap has run"
        )
        let moved = controller.ledger.byPraticaPath["Calendar/01 Progetti/Tifone/X"]
        #expect(
            moved?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "the pratica's own state - not just an empty key - must travel with the remap"
        )
    }

    @Test func moveLedgerStateLeavesSiblingPrefixAlone() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.updateLedger(.live(nil)) { $0.byPraticaPath["01 Progetti-altro"] = .empty }
        let vault = VaultController()

        controller.moveLedgerState(from: "01 Progetti", to: "Calendar/01 Progetti", in: vault)

        #expect(
            controller.ledger.byPraticaPath["01 Progetti-altro"] != nil,
            "a sibling whose name merely starts with the same characters is not a descendant"
        )
        #expect(controller.ledger.byPraticaPath["Calendar/01 Progetti-altro"] == nil)
    }

    @Test func moveLedgerStateCarriesTrayCountsSelectionWatchersAndSyncingPath() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        controller.trayCounts[oldPath] = 3
        controller.trayProposals[oldPath] = []
        controller.watchersByPraticaPath[oldPath] = PraticaWatcher()
        controller.selection = oldPath
        controller.syncingPraticaPath = oldPath
        let vault = VaultController()

        controller.moveLedgerState(from: oldPath, to: newPath, in: vault)

        #expect(controller.trayCounts[newPath] == 3)
        #expect(controller.trayCounts[oldPath] == nil, "the old key must not linger once its count travelled")
        #expect(controller.trayProposals[newPath] != nil)
        #expect(controller.watchersByPraticaPath[newPath] != nil, "a stale watcher never fires for the new path")
        #expect(controller.watchersByPraticaPath[oldPath] == nil)
        #expect(controller.selection == newPath, "the open pratica must stay selected across its own relocation")
        #expect(
            controller.syncingPraticaPath == newPath,
            "an in-flight sync's completion must land on the new path, not resurrect the orphaned key"
        )
    }

    @Test func moveLedgerStatePersistsToDisk() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)

        let pratiche = PraticheController.live(vault: vaultController)
        // On disk and not in memory (ADR-0052 §D9): a session exists, so the door reads the file.
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["01 Progetti/Tifone/X"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))

        pratiche.moveLedgerState(
            from: "01 Progetti/Tifone/X", to: "Calendar/01 Progetti/Tifone/X", in: vaultController
        )

        let onDisk = PraticaLedger.load(from: PraticheController.ledgerURL(for: session))
        #expect(onDisk.byPraticaPath["01 Progetti/Tifone/X"] == nil)
        #expect(
            onDisk.byPraticaPath["Calendar/01 Progetti/Tifone/X"] != nil,
            "the remap must be saved, not only held in memory"
        )

        vaultController.close()
    }

    @Test func undoOfFolderMoveRestoresLedgerKey() async throws {
        let vault = try TemporaryVault()
        let root = vault.root
        try vault.write(
            "---\ndate: 2026-09-17\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "F/pratica.md"
        )
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(root)
        // `PergamenumApp.init`'s own wiring (this plan's own note): not going through
        // `PergamenumApp` in a test, so the hook is set by hand.
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didRelocateFolders = { [weak pratiche] moved in
            pratiche?.followFolderRelocations(moved, in: vaultController)
        }
        let session = try #require(vaultController.session)
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["F"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))
        let manager = UndoManager()

        let outcome = await vaultController.moveItems(
            [VaultItemRef(path: "F", kind: .folder)], into: "Dest", undo: manager
        )

        #expect(outcome.didMove)
        #expect(pratiche.ledger.byPraticaPath["F"] == nil, "the forward move must not leave the old key behind")
        #expect(
            pratiche.ledger.byPraticaPath["Dest/F"] != nil,
            "the forward move must carry the ledger key to the new path"
        )

        manager.undo()
        try await waitUntil { pratiche.ledger.byPraticaPath["F"] != nil }

        #expect(pratiche.ledger.byPraticaPath["F"] != nil, "the undo must carry the ledger key back")
        #expect(pratiche.ledger.byPraticaPath["Dest/F"] == nil)

        vaultController.close()
    }

    @Test func renameOfAncestorFolderRemapsLedgerKey() async throws {
        let vault = try TemporaryVault()
        let root = vault.root
        try vault.write(
            "---\ndate: 2026-09-17\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "01 Progetti/Tifone/pratica.md"
        )
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(root)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didRelocateFolders = { [weak pratiche] moved in
            pratiche?.followFolderRelocations(moved, in: vaultController)
        }
        let session = try #require(vaultController.session)
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath["01 Progetti/Tifone"] = .empty
        try seeded.save(to: PraticheController.ledgerURL(for: session))

        let newPath = vaultController.renameFolder(at: "01 Progetti", to: "Calendar")

        #expect(newPath == "Calendar")
        #expect(
            pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] == nil,
            "renaming the ancestor must not leave the descendant pratica's key behind"
        )
        #expect(
            pratiche.ledger.byPraticaPath["Calendar/Tifone"] != nil,
            "renaming an ancestor folder orphans a descendant pratica the same way a move does"
        )

        vaultController.close()
    }

    /// The actual race, not just the redirect map's own bookkeeping (that is what
    /// `moveLedgerStateCarriesTrayCountsSelectionWatchersAndSyncingPath` above already
    /// covers): a sync captures `praticaPath` before its own `await`s
    /// (`PraticaLiveSync+Run.swift`'s `runExclusive`), a relocation runs on the main
    /// actor while that sync is still in flight, and only THEN does the sync's outcome
    /// arrive, still carrying the pre-move path. `recordSyncOutcome` must fold it into
    /// wherever the ledger key now actually lives, never resurrect the orphaned one.
    @Test func recordSyncOutcomeFoldsIntoRelocatedPathAndNeverResurrectsTheOldKey() throws {
        let vault = try TemporaryVault()
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let oldPath = "01 Progetti/Tifone/X"
        let newPath = "Calendar/01 Progetti/Tifone/X"
        controller.updateLedger(.live(nil)) { $0.byPraticaPath[oldPath] = .empty }
        // Mirrors `beginSync(praticaPath)`, called before `runExclusive`'s own `await`s.
        controller.beginSync(oldPath)
        let vaultController = VaultController()

        // The relocation - drag-and-drop, or a rename of an ancestor - runs on the main
        // actor while the sync above is still in flight (ADR-0043 §D7's window).
        controller.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vaultController)
        #expect(controller.ledger.byPraticaPath[oldPath] == nil, "the relocation itself must not leave the old key behind")

        // The in-flight sync's own outcome lands afterwards, still keyed by the path it
        // captured before the relocation ran.
        let outcome = PraticaSyncEngine.SyncOutcome(
            writtenFiles: [], importedMessageIDs: ["<a@rossi-spa.it>"],
            noLongerInMail: [], regeneratedPendingFiles: [], cancelled: false, bridge: []
        )
        controller.recordSyncOutcome(outcome, for: oldPath, session: session, isCurrentVault: true)

        #expect(
            controller.ledger.byPraticaPath[oldPath] == nil,
            "a sync outcome arriving after the relocation must not resurrect the orphaned key"
        )
        #expect(
            controller.ledger.byPraticaPath[newPath]?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "the outcome must fold into wherever the pratica's ledger now actually lives"
        )
    }
}
