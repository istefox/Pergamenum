import Foundation
import Testing
@testable import Pergamenum

// PG-192, ADR-0052 §D8: a writer that touches sibling state beside the ledger calls the door
// FIRST, because on a change of vault the door resets that state, and the reverse order lets the
// reset land on top of what the writer has just set. `select` has its own test of this rule
// (PG-191, `PraticheLedgerDoorTests.selectSurvivesAVaultSwitchInsteadOfBeingSilentlyDropped`);
// `updateTray` is pinned here.
//
// `moveLedgerState` and `forgetLedgerState` follow the same rule but have no test of it here, and
// cannot have one from outside: measured on 2026-10-01 by reversing each and running a vault-switch
// test against it, which stayed green. On a vault switch every sibling they touch (`trayProposals`,
// `trayCounts`, `watchersByPraticaPath`, `selection`) is one the door's reset clears, so both orders
// end empty; and what they write outside the reset (`praticaPathRedirects`, `forgottenPraticaPaths`)
// is written only for a path in flight, which their own `syncingPraticaPath`/`regeneratingPraticaPaths`
// branches record identically in either order. The rule there guards a future sibling the reset
// would not clear, which is why it stays written down in both functions. Their ordering is
// therefore consciously not pinned: a test would need a production hook that observes the sibling
// state at the moment before the door's reset runs, and none is added for a test alone.
//
// New file rather than more tests in `PraticheLedgerDoorTests.swift`, which sits a few lines short
// of SwiftLint's `file_length` error (ADR-0045's precedent).

private let pathX = "01 Progetti/Tifone/X"

@MainActor
private func opened(_ vault: borrowing TemporaryVault) async throws -> (VaultController, VaultSession) {
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    return (vaultController, try #require(vaultController.session))
}

private func proposal() -> PraticaTrayModel.PraticaTrayProposal {
    let day = Date(timeIntervalSince1970: 1_749_557_170)
    return PraticaTrayModel.PraticaTrayProposal(
        conversationID: 42, subject: "Re: Preventivo", counterpart: "m.rossi@rossi-spa.it",
        dateRange: day...day, messageCount: 2
    )
}

@MainActor
@Suite(.serialized) struct PraticheLedgerOrderingTests {
    /// The case §D8 names: a sync for vault B finishes on a controller whose memory still came
    /// from vault A's ledger. The door resets the tray, and only the door-first order leaves the
    /// proposals the sync has just computed in place - the reverse order sets them and then watches
    /// the reset drop them (measured: red with `persistTrayCount` moved after the assignments).
    @Test func updateTrayOnAVaultSwitchKeepsTheProposalsItJustComputed() async throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let (controllerA, sessionA) = try await opened(vaultA)
        let (controllerB, sessionB) = try await opened(vaultB)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        pratiche.load(from: controllerA)
        #expect(pratiche.ledgerOrigin == .loaded(PraticheController.ledgerURL(for: sessionA)), "precondition")

        pratiche.updateTray([proposal()], for: pathX, in: controllerB)

        #expect(pratiche.trayProposals == [pathX: [proposal()]], "the proposals the sync computed survive the reset")
        #expect(pratiche.trayCounts == [pathX: 1], "and so does their count")
        #expect(pratiche.ledgerOrigin == .loaded(PraticheController.ledgerURL(for: sessionB)))
        let onDiskB = PraticaLedger.load(from: PraticheController.ledgerURL(for: sessionB))
        #expect(onDiskB.byPraticaPath[pathX]?.trayCount == 1, "the count reached B's own file")
        controllerA.close()
        controllerB.close()
    }
}
