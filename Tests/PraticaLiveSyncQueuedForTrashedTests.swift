import Foundation
import Testing
@testable import Pergamenum

// PG-173, first half (a residual of PG-169): a sync queued behind another one for a pratica
// that gets trashed before it dequeues holds no claim, so the trash records no tombstone for
// it and `shouldRunQueuedRequest` still runs it. It reaches `runExclusive` with no folder on
// disk at all, and used to report «"…" non ha un dossier leggibile in pratica.md» in the pane
// for a pratica the person had just thrown away.
//
// Driven through `runExclusive` directly, the seam every dequeued request goes through
// (`PraticaLiveSync.run(praticaPath:kind:)`), rather than by racing a real queue: the state
// a dequeued run meets - no folder, no claim, no tombstone - is installed as it is, and the
// result is deterministic. The first half is silent only because nobody asked: an explicit
// «Aggiorna ora» on the same missing folder must answer. Neither test reaches the mail store: both runs end at the dossier
// guard, before `MailStoreLocation.resolve()`.
@MainActor
@Suite(.serialized) struct PraticaLiveSyncQueuedForTrashedTests {
    private static let folder = PraticaSyncFixtures.praticaFolder

    @Test func aRunForAPraticaWhoseFolderIsGoneEndsWithoutReportingAnything() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        let outcome = await sync.runExclusive(praticaPath: Self.folder, kind: .fsEvents)

        #expect(outcome == .finished)
        #expect(pratiche.problem == nil, "a trashed pratica has no dossier to call unreadable")
        #expect(pratiche.syncingPraticaPath == nil, "and the run never claimed it")
        vaultController.close()
    }

    @Test func aRunForAPraticaWhoseFolderIsThereWithoutADossierStillReportsIt() async throws {
        let vault = try TemporaryVault()
        try vault.write("Appunti.", to: "\(Self.folder)/appunti.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        let outcome = await sync.runExclusive(praticaPath: Self.folder, kind: .fsEvents)

        #expect(outcome == .finished)
        #expect(
            pratiche.problem == "«\(Self.folder)» non ha un dossier leggibile in pratica.md.",
            "a folder that is still there with no readable pratica.md is a real problem to show"
        )
        vaultController.close()
    }

    @Test func aManualRefreshOfAPraticaWhoseFolderIsGoneSaysSo() async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        let outcome = await sync.runExclusive(praticaPath: Self.folder, kind: .manualRefresh)

        #expect(outcome == .finished)
        #expect(
            pratiche.problem == "La cartella «\(Self.folder)» non c'è più.",
            "somebody clicked «Aggiorna ora»: a pratica moved in Finder or on an unmounted volume must not answer with silence"
        )
        #expect(pratiche.syncingPraticaPath == nil)
        vaultController.close()
    }

    @Test(arguments: [PraticaWatcher.Trigger.vaultOpen, .windowKey, .fsEvents])
    func anAutomaticRunForAPraticaWhoseFolderIsGoneStaysSilent(kind: PraticaWatcher.Trigger) async throws {
        let vault = try TemporaryVault()
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        let outcome = await sync.runExclusive(praticaPath: Self.folder, kind: kind)

        #expect(outcome == .finished)
        #expect(pratiche.problem == nil, "nobody asked for \(kind): nothing to say about a folder that is gone")
        vaultController.close()
    }
}
