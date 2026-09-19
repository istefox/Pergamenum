import Foundation
import Testing
@testable import Pergamenum

// PG-169, ADR-0026 §D7's 2026-09-19 amendment (`docs/plans/pg-169-pratica-ledger-forgotten-
// on-folder-trash.md`, Tasks 2 and 3) - R-01, R-02, R-03, R-04, R-08.
//
// The deletion twin of `PraticaLedgerFolderRelocationTests` (`Tests/PraticheControllerTests
// .swift`), test for test: `PraticheController.forgetLedgerState(under:in:)` is to a folder
// sent to the Trash what `moveLedgerState(from:to:in:)` is to a folder that moved. A new
// file rather than an addition there, because that file is at 968 lines against SwiftLint's
// `file_length` error at 1000 (ADR-0045's own precedent for where a new battery goes).
//
// What is NOT here, on purpose: the in-flight halves (R-06), which `Tests/PraticaLiveSync
// TrashedMidRunTests.swift` owns, and the hook's own fired-once/refused/failed contract
// (R-04/R-05 at the door), which `Tests/VaultSessionFolderOperationsTests.swift` owns beside
// the facade's other folder tests.

private let praticaNote = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
---

Appunti pratica.
"""

private func ledgerState(importing ids: String...) -> PraticaLedger.PraticaState {
    var state = PraticaLedger.PraticaState.empty
    state.importedMessageIDs = ids
    return state
}

@MainActor
@Suite(.serialized) struct PraticaLedgerFolderTrashTests {
    // MARK: - The routine itself (R-01, R-02, R-03)

    @Test func forgetLedgerStateRemovesTheExactKey() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] = ledgerState(importing: "<a@rossi-spa.it>")
        controller.ledger.byPraticaPath["01 Progetti/Tifone/Y"] = .empty
        let vault = VaultController()

        controller.forgetLedgerState(under: "01 Progetti/Tifone/X", in: vault)

        #expect(controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] == nil)
        #expect(
            controller.ledger.byPraticaPath["01 Progetti/Tifone/Y"] != nil,
            "trashing one pratica must leave its neighbour's ledger alone"
        )
    }

    @Test func forgetLedgerStateRemovesEveryDescendantUnderATrashedAncestor() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] = ledgerState(importing: "<a@rossi-spa.it>")
        controller.ledger.byPraticaPath["01 Progetti/Rossi/Y"] = ledgerState(importing: "<b@rossi-spa.it>")
        controller.ledger.byPraticaPath["02 Archivio/Z"] = ledgerState(importing: "<c@rossi-spa.it>")
        let vault = VaultController()

        // The bug shape the relocation twin already had: the pratica is not the trashed
        // item, an ANCESTOR of it is.
        controller.forgetLedgerState(under: "01 Progetti", in: vault)

        #expect(
            controller.ledger.byPraticaPath["01 Progetti/Tifone/X"] == nil,
            "a pratica nested inside the trashed folder goes with it"
        )
        #expect(controller.ledger.byPraticaPath["01 Progetti/Rossi/Y"] == nil, "and so does every other one under it")
        #expect(
            controller.ledger.byPraticaPath["02 Archivio/Z"]?.importedMessageIDs == ["<c@rossi-spa.it>"],
            "a pratica in an unrelated folder keeps its whole state, not just its key"
        )
    }

    @Test func forgetLedgerStateLeavesASiblingPrefixAlone() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.ledger.byPraticaPath["01 Progetti/Tifone"] = .empty
        controller.ledger.byPraticaPath["01 Progetti-altro"] = .empty
        controller.ledger.byPraticaPath["01 Progetti-altro/Y"] = .empty
        let vault = VaultController()

        controller.forgetLedgerState(under: "01 Progetti", in: vault)

        #expect(controller.ledger.byPraticaPath["01 Progetti/Tifone"] == nil)
        #expect(
            controller.ledger.byPraticaPath["01 Progetti-altro"] != nil,
            "a sibling whose name merely starts with the same characters is not a descendant"
        )
        #expect(controller.ledger.byPraticaPath["01 Progetti-altro/Y"] != nil)
    }

    @Test func forgetLedgerStateRemovesTrayProposalsCountsAndTheWatcher() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let trashed = "01 Progetti/Tifone/X"
        let sibling = "01 Progetti-altro/Y"
        for path in [trashed, sibling] {
            controller.trayCounts[path] = 3
            controller.trayProposals[path] = []
            controller.watchersByPraticaPath[path] = PraticaWatcher()
        }
        let vault = VaultController()

        controller.forgetLedgerState(under: "01 Progetti", in: vault)

        #expect(controller.trayCounts[trashed] == nil, "the dot on a row that no longer exists must go")
        #expect(controller.trayProposals[trashed] == nil)
        #expect(controller.watchersByPraticaPath[trashed] == nil, "a watcher on a trashed folder must not survive")
        #expect(controller.trayCounts[sibling] == 3, "the sibling's count is not the trashed subtree's")
        #expect(controller.trayProposals[sibling] != nil)
        #expect(controller.watchersByPraticaPath[sibling] != nil)
    }

    @Test func forgetLedgerStateClearsASelectionInsideTheTrashedSubtreeAndLeavesOneOutsideIt() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let vault = VaultController()
        // What `reloadTimeline` reads back to empty once the selection is gone - seeded so
        // the test can tell "cleared through `select(nil, in:)`" from a bare `selection = nil`.
        controller.selection = "01 Progetti/Tifone/X"
        controller.expansion = PraticaTimelineModel.ExpansionState(expandedIDs: ["row-1"])
        controller.links = PraticaLinks(notes: ["Nota collegata"])

        controller.forgetLedgerState(under: "01 Progetti", in: vault)

        #expect(controller.selection == nil, "the open pratica was inside the trashed subtree")
        #expect(controller.expansion == PraticaTimelineModel.ExpansionState(), "expansion follows the deselect")
        #expect(controller.links == .empty, "the inspector's links follow it too, not just the list")
        #expect(controller.timeline.isEmpty)
        #expect(controller.details.isEmpty)

        controller.selection = "01 Progetti-altro/Y"
        controller.links = PraticaLinks(notes: ["Altra nota"])
        controller.forgetLedgerState(under: "01 Progetti", in: vault)

        #expect(controller.selection == "01 Progetti-altro/Y", "a selection outside the subtree is not this deletion's")
        #expect(controller.links == PraticaLinks(notes: ["Altra nota"]))
    }

    @Test func forgetLedgerStatePersistsTheRemovalToDisk() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)

        let pratiche = PraticheController.live(vault: vaultController)
        pratiche.ledger.byPraticaPath["01 Progetti/Tifone/X"] = ledgerState(importing: "<a@rossi-spa.it>")
        pratiche.ledger.byPraticaPath["01 Progetti-altro/Y"] = .empty
        // The key is on disk BEFORE the removal, or the assertion below proves nothing:
        // an empty file would satisfy it just as well.
        try pratiche.ledger.save(to: url)
        #expect(PraticaLedger.load(from: url).byPraticaPath["01 Progetti/Tifone/X"] != nil)

        pratiche.forgetLedgerState(under: "01 Progetti", in: vaultController)

        let onDisk = PraticaLedger.load(from: url)
        #expect(
            onDisk.byPraticaPath["01 Progetti/Tifone/X"] == nil,
            "the removal must be saved, not only held in memory"
        )
        #expect(onDisk.byPraticaPath["01 Progetti-altro/Y"] != nil, "and the save must not take a sibling with it")

        vaultController.close()
    }

    // MARK: - Through the door and the command (R-04, R-08)

    /// R-04 at the seam an app-level test can reach: the real `VaultController.trashFolder`,
    /// the hook wired by hand exactly as `PergamenumApp.init` wires it (the way
    /// `undoOfFolderMoveRestoresLedgerKey` wires `didRelocateFolders`).
    @Test func trashingAFolderThroughTheDoorForgetsTheLedgerKey() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNote, to: "01 Progetti/Tifone/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didTrashFolder = { [weak pratiche] path in
            pratiche?.followFolderTrashing(path, in: vaultController)
        }
        pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] = ledgerState(importing: "<a@rossi-spa.it>")
        try pratiche.ledger.save(to: url)

        let trashed = vaultController.trashFolder(at: "01 Progetti/Tifone")

        #expect(trashed)
        #expect(pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] == nil, "the door must forget what it trashed")
        #expect(PraticaLedger.load(from: url).byPraticaPath["01 Progetti/Tifone"] == nil, "in the file too")

        vaultController.close()
    }

    @Test func trashingAnAncestorFolderThroughTheDoorForgetsEveryDescendantPraticaKey() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNote, to: "01 Progetti/Tifone/pratica.md")
        try vault.write(praticaNote, to: "01 Progetti-altro/Y/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didTrashFolder = { [weak pratiche] path in
            pratiche?.followFolderTrashing(path, in: vaultController)
        }
        pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] = ledgerState(importing: "<a@rossi-spa.it>")
        pratiche.ledger.byPraticaPath["01 Progetti-altro/Y"] = ledgerState(importing: "<b@rossi-spa.it>")

        let trashed = vaultController.trashFolder(at: "01 Progetti")

        #expect(trashed)
        #expect(pratiche.ledger.byPraticaPath["01 Progetti/Tifone"] == nil)
        #expect(
            pratiche.ledger.byPraticaPath["01 Progetti-altro/Y"]?.importedMessageIDs == ["<b@rossi-spa.it>"],
            "the sibling folder is on disk and untouched, so its history must be too"
        )

        vaultController.close()
    }

    /// The one caller-level proof a unit test can reach (plan Task 3): «Elimina pratica»
    /// through `PraticaCommandActions.confirmDeletion(of:)`. Selecting the pratica first is
    /// what puts its key in the ledger the way the app does (`select` marks it opened), and
    /// what makes the final `selection == nil` mean something - `confirmDeletion` no longer
    /// clears it itself, the hook does.
    @Test func deletingAPraticaThroughItsOwnCommandForgetsTheLedgerKey() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNote, to: "01 Progetti/Tifone/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didTrashFolder = { [weak pratiche] path in
            pratiche?.followFolderTrashing(path, in: vaultController)
        }
        let item = PraticaListItem(
            id: "01 Progetti/Tifone", title: "Tifone", client: "rossi", status: "active",
            lastActivity: Date(), messagesSinceLastOpen: 0, hasNonEmptyTray: false
        )
        pratiche.select(item.id, in: vaultController)
        #expect(pratiche.ledger.byPraticaPath[item.id] != nil, "precondition: opening the pratica put it in the ledger")
        let actions = PraticaCommandActions(pratiche: pratiche, vault: vaultController, navigation: Navigation())

        actions.confirmDeletion(of: item)

        // `confirmDeletion` re-reads the ledger from disk right after the trash
        // (`pratiche.load(from:)`), so a key that had only been removed in memory would be
        // back by here - this is what makes the file assertion below the real one.
        #expect(pratiche.ledger.byPraticaPath[item.id] == nil, "deleting a pratica must forget its ledger key")
        #expect(PraticaLedger.load(from: PraticheController.ledgerURL(for: session)).byPraticaPath[item.id] == nil)
        #expect(pratiche.selection == nil, "the deleted pratica must not stay selected")

        vaultController.close()
    }

    /// The ticket's acceptance case (R-08): the old pratica's imported ids must not filter
    /// the new pratica's first sync. `runExclusive` reads exactly `state.importedMessageIDs`
    /// as its `onDisk` set, so an empty one here is an unfiltered first sync there.
    @Test func aPraticaRecreatedUnderTheSameNameStartsFromAnEmptyLedger() async throws {
        let vault = try TemporaryVault()
        let path = "01 Progetti/Tifone"
        try vault.write(praticaNote, to: "\(path)/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let pratiche = PraticheController.live(vault: vaultController)
        vaultController.didTrashFolder = { [weak pratiche] trashed in
            pratiche?.followFolderTrashing(trashed, in: vaultController)
        }
        pratiche.ledger.byPraticaPath[path] = ledgerState(importing: "<a@rossi-spa.it>", "<b@rossi-spa.it>")
        try pratiche.ledger.save(to: PraticheController.ledgerURL(for: session))

        #expect(vaultController.trashFolder(at: path))
        try vault.write(praticaNote, to: "\(path)/pratica.md")
        pratiche.load(from: vaultController)

        #expect(pratiche.ledger.byPraticaPath[path] == nil, "the recreated pratica must not inherit the old one's key")
        #expect(
            (pratiche.ledger.byPraticaPath[path]?.importedMessageIDs ?? []).isEmpty,
            "so its first sync is not filtered by messages that were never imported into the new folder"
        )

        vaultController.close()
    }

    // MARK: - A controller that never loaded its ledger

    /// The hook is wired app-wide, so it fires for ANY folder trashed through the note list or
    /// the Workspace browser, including before the Pratiche pane has ever been shown in the
    /// session - when `ledger` is still the `.empty` it starts as and `load(from:)` has not yet
    /// read the file. Saving that empty value overwrote every pratica's history on disk. The
    /// file must come through such a trash byte for byte.
    @Test func trashingAnUnrelatedFolderBeforeTheLedgerIsLoadedLeavesTheFileUntouched() async throws {
        let vault = try TemporaryVault()
        let pratica = "01 Progetti/Tifone"
        try vault.write(praticaNote, to: "\(pratica)/pratica.md")
        try vault.write("Una nota.", to: "Altro/nota.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        var onDisk = PraticaLedger.empty
        var state = ledgerState(importing: "<a@rossi-spa.it>", "<b@rossi-spa.it>")
        state.lastOpenedAt = Date(timeIntervalSince1970: 1_749_557_170)
        state.trayCount = 3
        onDisk.byPraticaPath[pratica] = state
        try onDisk.save(to: url)
        let before = try Data(contentsOf: url)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        vaultController.didTrashFolder = { [weak pratiche] trashed in
            pratiche?.followFolderTrashing(trashed, in: vaultController)
        }
        #expect(pratiche.ledger == .empty, "precondition: nothing has called `load(from:)`")

        #expect(vaultController.trashFolder(at: "Altro"))

        #expect(try Data(contentsOf: url) == before, "an unrelated trash must not rewrite the ledger file")
        #expect(PraticaLedger.load(from: url) == onDisk)
        #expect(pratiche.problem == nil)

        vaultController.close()
    }

    /// The other half: not loading must not make the trash of a real pratica a no-op either.
    /// The ledger is read from disk before anything is removed, so the pratica's key leaves
    /// the file and a neighbour's history stays.
    @Test func trashingAPraticaBeforeTheLedgerIsLoadedStillRemovesItsKeyFromDisk() async throws {
        let vault = try TemporaryVault()
        let pratica = "01 Progetti/Tifone"
        let neighbour = "01 Progetti/Verdi"
        try vault.write(praticaNote, to: "\(pratica)/pratica.md")
        try vault.write(praticaNote, to: "\(neighbour)/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let session = try #require(vaultController.session)
        let url = PraticheController.ledgerURL(for: session)
        var onDisk = PraticaLedger.empty
        onDisk.byPraticaPath[pratica] = ledgerState(importing: "<a@rossi-spa.it>")
        onDisk.byPraticaPath[neighbour] = ledgerState(importing: "<b@rossi-spa.it>")
        try onDisk.save(to: url)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        vaultController.didTrashFolder = { [weak pratiche] trashed in
            pratiche?.followFolderTrashing(trashed, in: vaultController)
        }
        #expect(pratiche.ledger == .empty, "precondition: nothing has called `load(from:)`")

        #expect(vaultController.trashFolder(at: pratica))

        let saved = PraticaLedger.load(from: url)
        #expect(saved.byPraticaPath[pratica] == nil, "the trashed pratica's key is gone from the file")
        #expect(saved.byPraticaPath[neighbour]?.importedMessageIDs == ["<b@rossi-spa.it>"])
        #expect(pratiche.ledger == saved, "and the controller now holds what the file holds")

        vaultController.close()
    }
}
