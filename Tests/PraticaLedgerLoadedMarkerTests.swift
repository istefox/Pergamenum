import Foundation
import Testing
@testable import Pergamenum

// PG-172, #312: a ledger writer must not save `PraticheController.ledger` before that
// property mirrors the vault's own `ledger.json`. `ledger` starts `.empty` and only
// `load(from:)` fills it, so before the door (`ensureLedgerLoaded(for:)`) `moveLedgerState`,
// `recordSyncOutcome`, `updateTray` and the rest saved an empty or another vault's ledger
// straight over the real file. Every test here starts from a controller nothing has
// `load(from:)`ed, with real history on disk.

private let praticaNote = """
---
pergamenum-dossier: 1
pergamenum-dossier-counterparts:
  - m.rossi@rossi-spa.it
---

Appunti pratica.
"""

private func historyState(importing ids: String...) -> PraticaLedger.PraticaState {
    var state = PraticaLedger.PraticaState.empty
    state.importedMessageIDs = ids
    return state
}

private func outcome(importing ids: [String]) -> PraticaSyncEngine.SyncOutcome {
    PraticaSyncEngine.SyncOutcome(
        writtenFiles: [], importedMessageIDs: ids, noLongerInMail: [], regeneratedPendingFiles: [],
        cancelled: false, bridge: []
    )
}

@MainActor
@Suite(.serialized) struct PraticaLedgerLoadedMarkerTests {
    private static let folder = "01 Progetti/Tifone"
    private static let neighbour = "01 Progetti/Verdi"

    /// A vault with two pratiche whose history is already on disk, opened, and a controller
    /// that has never loaded.
    private struct Fixture {
        let controller: VaultController
        let session: VaultSession
        let url: URL
        let pratiche: PraticheController
    }

    private func fixture(in vault: borrowing TemporaryVault) async throws -> Fixture {
        try vault.write(praticaNote, to: "\(Self.folder)/pratica.md")
        try vault.write(praticaNote, to: "\(Self.neighbour)/pratica.md")
        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let session = try #require(controller.session)
        let url = PraticheController.ledgerURL(for: session)
        var onDisk = PraticaLedger.empty
        onDisk.byPraticaPath[Self.folder] = historyState(importing: "<a@rossi-spa.it>")
        onDisk.byPraticaPath[Self.neighbour] = historyState(importing: "<b@rossi-spa.it>")
        try onDisk.save(to: url)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        #expect(pratiche.ledger == .empty, "precondition: nothing has called `load(from:)`")
        return Fixture(controller: controller, session: session, url: url, pratiche: pratiche)
    }

    @Test func recordSyncOutcomeBeforeAnyLoadKeepsTheHistoryOnDisk() async throws {
        let vault = try TemporaryVault()
        let f = try await fixture(in: vault)

        f.pratiche.recordSyncOutcome(
            outcome(importing: ["<new@rossi-spa.it>"]), for: Self.folder, session: f.session, isCurrentVault: true
        )

        let saved = PraticaLedger.load(from: f.url)
        #expect(
            saved.byPraticaPath[Self.folder]?.importedMessageIDs == ["<a@rossi-spa.it>", "<new@rossi-spa.it>"],
            "the outcome merges into the history on disk instead of replacing it"
        )
        #expect(
            saved.byPraticaPath[Self.neighbour]?.importedMessageIDs == ["<b@rossi-spa.it>"],
            "and a neighbour's history is not wiped"
        )
        f.controller.close()
    }

    @Test func updateTrayBeforeAnyLoadKeepsTheHistoryOnDisk() async throws {
        let vault = try TemporaryVault()
        let f = try await fixture(in: vault)

        let proposal = PraticaTrayModel.PraticaTrayProposal(
            conversationID: 7, subject: "Preventivo", counterpart: "m.rossi@rossi-spa.it",
            dateRange: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 60), messageCount: 2
        )
        f.pratiche.updateTray([proposal], for: Self.folder, in: f.controller)

        let saved = PraticaLedger.load(from: f.url)
        #expect(saved.byPraticaPath[Self.folder]?.trayCount == 1)
        #expect(saved.byPraticaPath[Self.folder]?.importedMessageIDs == ["<a@rossi-spa.it>"])
        #expect(saved.byPraticaPath[Self.neighbour]?.importedMessageIDs == ["<b@rossi-spa.it>"])
        f.controller.close()
    }

    @Test func moveLedgerStateBeforeAnyLoadCarriesTheKeyAndKeepsTheRest() async throws {
        let vault = try TemporaryVault()
        let f = try await fixture(in: vault)

        f.pratiche.moveLedgerState(from: Self.folder, to: "02 Archivio/Tifone", in: f.controller)

        let saved = PraticaLedger.load(from: f.url)
        #expect(saved.byPraticaPath[Self.folder] == nil)
        #expect(
            saved.byPraticaPath["02 Archivio/Tifone"]?.importedMessageIDs == ["<a@rossi-spa.it>"],
            "the history followed the folder, from the file rather than from an empty memory copy"
        )
        #expect(saved.byPraticaPath[Self.neighbour]?.importedMessageIDs == ["<b@rossi-spa.it>"])
        f.controller.close()
    }

    @Test func markingAPraticaOpenedBeforeAnyLoadKeepsTheHistoryOnDisk() async throws {
        let vault = try TemporaryVault()
        let f = try await fixture(in: vault)

        f.pratiche.select(Self.folder, in: f.controller)

        let saved = PraticaLedger.load(from: f.url)
        #expect(saved.byPraticaPath[Self.folder]?.lastOpenedAt != nil)
        #expect(saved.byPraticaPath[Self.folder]?.importedMessageIDs == ["<a@rossi-spa.it>"])
        #expect(saved.byPraticaPath[Self.neighbour]?.importedMessageIDs == ["<b@rossi-spa.it>"])
        f.controller.close()
    }

    @Test func aLedgerLoadedForAnotherVaultIsNeverWrittenIntoThisOne() async throws {
        let vaultA = try TemporaryVault()
        let a = try await fixture(in: vaultA)
        a.pratiche.load(from: a.controller)
        #expect(a.pratiche.ledger.byPraticaPath[Self.folder] != nil, "precondition: loaded for vault A")
        a.controller.close()

        // Vault B holds a pratica of its own; the controller is still the one that loaded A.
        let other = try TemporaryVault()
        try other.write(praticaNote, to: "\(Self.neighbour)/pratica.md")
        let controllerB = VaultController(recents: .volatile(), openTabs: .volatile())
        await controllerB.open(other.root)
        let sessionB = try #require(controllerB.session)
        let urlB = PraticheController.ledgerURL(for: sessionB)
        var onDiskB = PraticaLedger.empty
        onDiskB.byPraticaPath[Self.neighbour] = historyState(importing: "<b@rossi-spa.it>")
        try onDiskB.save(to: urlB)

        a.pratiche.moveLedgerState(from: Self.neighbour, to: "02 Archivio/Verdi", in: controllerB)

        let saved = PraticaLedger.load(from: urlB)
        #expect(saved.byPraticaPath[Self.folder] == nil, "vault A's pratica must not leak into B's file")
        #expect(saved.byPraticaPath["02 Archivio/Verdi"]?.importedMessageIDs == ["<b@rossi-spa.it>"])
        #expect(a.pratiche.ledger == saved, "and memory now mirrors B")
        controllerB.close()
    }

    @Test func aLoadedLedgerIsNotReReadOverAnUnsavedInMemoryChange() async throws {
        let vault = try TemporaryVault()
        let f = try await fixture(in: vault)
        f.pratiche.load(from: f.controller)
        f.pratiche.ledger.byPraticaPath[Self.folder]?.importedMessageIDs.append("<unsaved@rossi-spa.it>")

        f.pratiche.ensureLedgerLoaded(for: f.session)

        #expect(
            f.pratiche.ledger.byPraticaPath[Self.folder]?.importedMessageIDs.contains("<unsaved@rossi-spa.it>") == true,
            "the door trusts a memory copy that already mirrors this vault's file"
        )
        f.controller.close()
    }
}

extension PraticheController {
    /// Declares the in-memory `ledger` to be the one loaded for `vault`, without touching the
    /// disk (PG-172, #312). For a test that seeds `ledger` by hand and then drives a writer:
    /// `ensureLedgerLoaded(for:)` would otherwise, correctly, re-read the file and drop the
    /// seed, since nothing says the memory copy mirrors it. Not for a test whose point is the
    /// unloaded state.
    func markLedgerLoaded(in vault: VaultController) {
        ledgerLoadedURL = vault.session.map(Self.ledgerURL(for:))
    }
}
