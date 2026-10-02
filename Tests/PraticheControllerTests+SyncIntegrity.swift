import Foundation
import Testing
@testable import Pergamenum

// Split out of `PraticheControllerTests.swift` under PG-293 (#638) to clear its SwiftLint
// `file_length` warning: a pure move, no test changed.

// MARK: - ADR-0068 Task 3 (R-14, R-15, R-19, R-20, R-21)

/// A tiny reference box so `performSync` can reach back into the `PraticheController`
/// that owns it - the closure is captured before the controller it belongs to exists.
@MainActor
private final class ControllerBox {
    var controller: PraticheController?
}

@MainActor
@Suite(.serialized) struct PraticaSyncAllMidPassTests {
    /// R-14/§D13 item 8: `syncAll`'s own `for pratica in pratiche` snapshots the array
    /// once, before its first `await` - a pratica archived by the FIRST call's own
    /// `performSync` (simulating «Chiudi» reached from a command run mid-sync) must
    /// not be synced by this SAME pass with its now-stale eligibility. Red until Task
    /// 6 re-reads `pratiche.first(where:)` before each trigger, `fireDueFSEventsPulses`'
    /// own shape (`PraticheController+Triggers.swift:110`).
    @Test func aPraticaArchivedDuringThePassIsNotSyncedAndItsWatcherRecordsNoSyncMark() async throws {
        let box = ControllerBox()
        var calls: [String] = []
        let controller = PraticheController(
            probe: { .granted },
            performSync: { path, _ in
                calls.append(path)
                if path == "P1", let idx = box.controller?.pratiche.firstIndex(where: { $0.id == "P2" }) {
                    box.controller?.pratiche[idx].status = "archived"
                }
            }
        )
        box.controller = controller
        let now = Date()
        controller.pratiche = [
            PraticaListItem(id: "P1", title: "P1", client: "Rossi", status: "active", lastActivity: now, messagesSinceLastOpen: 0, hasNonEmptyTray: false),
            PraticaListItem(id: "P2", title: "P2", client: "Rossi", status: "active", lastActivity: now, messagesSinceLastOpen: 0, hasNonEmptyTray: false),
        ]
        let vault = VaultController()

        await controller.syncAll(in: vault, kind: .windowKey)

        #expect(!calls.contains("P2"), "a pratica archived mid-pass must not be synced by the same pass")
        #expect(
            controller.watchersByPraticaPath["P2"]?.lastWindowKeySyncAt == nil,
            "an unsynced pratica's watcher must record no sync mark"
        )
    }
}

@MainActor
@Suite(.serialized) struct PraticaLiveSyncCancelDuringPreparationTests {
    private static let praticaPath = "01 Progetti/Rossi/Offerta 2026"

    /// R-15/§D14: «Annulla» reaching the preparation phase (before any engine exists)
    /// must stop the run before it ever writes anything. Red until Task 6 adds the
    /// run-level `stopRequested` flag: today `cancel()`'s `guard let running else {
    /// return }` is a no-op with nothing running yet, so the run proceeds to
    /// completion regardless of the `cancel()` call landing during preparation.
    @Test func cancelDuringPreparationStopsTheRunBeforeTheEngineEverStarts() async throws {
        let vault = try TemporaryVault()
        try vault.write(
            "---\ndate: 2026-09-01\ntags:\n  - type-note\npergamenum-dossier: 1\n---\n\nAppunti.",
            to: "\(Self.praticaPath)/pratica.md"
        )
        let fixture = try MailStoreFixture.build(
            mailboxes: [.init(rowID: 1, url: "ews://acct1/INBOX")],
            messages: [.init(
                rowID: 1, subject: "Richiesta offerta", senderAddress: "m.rossi@rossi-spa.it",
                mailboxRowID: 1, conversationID: 112_409,
                dateSent: Date(timeIntervalSince1970: 1_749_557_170),
                dateReceived: Date(timeIntervalSince1970: 1_749_557_170),
                emlxBody: EmailFixtureCorpus.completeMessageRFC822
            )]
        )
        await MailStoreOverride.acquire(settingRootTo: fixture.root)
        defer { MailStoreOverride.release() }

        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let sync = PraticaLiveSync(vault: vaultController)
        sync.controller = pratiche

        let gate = Gate()
        sync.preparationStep = { mailRoot, stateDirectory, dossier, ledgerEntries, proposalWindow in
            await gate.wait()
            return MailStorePreparation.prepare(
                mailRoot: mailRoot, stateDirectory: stateDirectory, dossier: dossier,
                ledgerEntries: ledgerEntries, proposalWindow: proposalWindow
            )
        }

        let runTask = Task { await sync.run(praticaPath: Self.praticaPath, kind: .manualRefresh) }
        sync.cancel()
        gate.open()
        await runTask.value

        let emailDir = vault.root.appending(path: "\(Self.praticaPath)/email", directoryHint: .isDirectory)
        let writtenFiles = (try? FileManager.default.contentsOfDirectory(atPath: emailDir.path(percentEncoded: false))) ?? []
        #expect(writtenFiles.isEmpty, "a cancel reaching the preparation phase must stop the run before it ever writes")
    }
}

@MainActor
@Suite(.serialized) struct PraticaExcludeOrderingTests {
    /// R-19/§D12 controller half: «Escludi» must write the exclusion FIRST and trash
    /// the files only once that landed - an unparseable dossier must trash nothing.
    /// Red until Task 4 reorders `exclude(_:detail:)`: today it trashes first
    /// (`PraticaCommandActions.swift`'s `exclude`, `:181`) and only then calls
    /// `updateDossier`, so an unparseable dossier still loses its files even though
    /// the exclusion itself could never be recorded.
    @Test func excludeOnAnUnparseableDossierTrashesNothing() async throws {
        let vault = try TemporaryVault()
        try vault.write("---\ndate: 2026-09-01\n---\n\nNessun dossier qui.\n", to: "Rossi/pratica.md")
        try vault.write("---\ndate: 2026-09-01\ntags:\n  - type-note\n---\n\nCorpo.", to: "Rossi/email/msg.md")
        try vault.write("da: a@b.it", to: "Rossi/email/msg.eml")

        let controller = VaultController(recents: .volatile(), openTabs: .volatile())
        await controller.open(vault.root)
        let pratiche = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let actions = PraticaCommandActions(pratiche: pratiche, vault: controller, navigation: Navigation())
        let detail = PraticaRowDetail(
            notePath: "Rossi/email/msg.md", body: "", quotedHistory: nil, signature: nil, attachments: [],
            storeReferences: [], isPending: false, senderAddress: nil, linkedNote: nil
        )
        let entry = PraticaTimelineEntry(
            id: "Rossi/email/msg.md", kind: .message, date: Date(), direction: .received,
            senderDisplayName: "Rossi", subject: "Richiesta", bodyPreview: "", hasAttachments: false,
            messageID: "<abc@rossi-spa.it>", isInMail: true
        )

        await actions.exclude(entry, detail: detail)

        #expect(
            FileManager.default.fileExists(atPath: vault.root.appending(path: "Rossi/email/msg.md").path(percentEncoded: false)),
            "an unparseable dossier must trash nothing - the exclusion write must be attempted, and refused, first"
        )
    }
}

@MainActor
@Suite(.serialized) struct PraticheControllerVaultScopedTeardownTests {
    /// R-20/§D15: a vault switch must clear the activation observer along with the
    /// rest of the vault-scoped state, amending ADR-0052 §D5's "deliberately NOT
    /// cleared" bullet for this one property. Red until Task 6:
    /// `resetVaultScopedState()` today leaves `windowKeyObserver` untouched.
    @Test func aVaultChangeClearsTheActivationObserver() async throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let vault = VaultController(recents: .volatile(), openTabs: .volatile())
        controller.startWatching(vault)
        try #require(controller.windowKeyObserver != nil, "setup: startWatching must have armed the observer")

        controller.reloadLedger(for: nil)

        #expect(controller.windowKeyObserver == nil, "a vault change must clear the observer, not merely stop syncing")
    }

    /// R-20/§D15: `startWatching`'s closures must capture the vault weakly, or a
    /// switched-away vault stays retained by the controller's own observer for as
    /// long as the pane never reopens. Red until Task 6 adds `[weak vault]`: today's
    /// closures capture `vault` by strong reference (`PraticheController+Triggers
    /// .swift`'s `startWatching`).
    @Test func startWatchingDoesNotRetainTheVaultStrongly() async throws {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        var vault: VaultController? = VaultController(recents: .volatile(), openTabs: .volatile())
        weak var weakVault = vault
        controller.startWatching(vault!)

        vault = nil

        #expect(weakVault == nil, "the controller's own watchers must not be the last strong reference to a switched-away vault")
    }
}

@MainActor
@Suite(.serialized) struct PraticheControllerInspectorKeyTests {
    /// R-21/§D16: a «Nota» write to the selected pratica's own `pratica.md` must
    /// advance `inspectorKey(for:)`, or the inspector never reloads after an
    /// in-app write to the note it is showing. Red: today's stub hardcodes
    /// `generation: 0` and never reads `session.landedGeneration(at:)` at all.
    @Test func aWriteToTheSelectedPraticasNoteAdvancesTheInspectorKey() async throws {
        let vault = try TemporaryVault()
        try vault.write("---\ndate: 2026-09-01\ntags:\n  - type-note\npergamenum-dossier: 1\n---\n\nAppunti.", to: "Rossi/pratica.md")
        let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
        await session.rescan()
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.selection = "Rossi"

        let before = controller.inspectorKey(for: session)
        _ = try await session.write(
            "---\ndate: 2026-09-01\ntags:\n  - type-note\npergamenum-dossier: 1\n---\n\nAppunti modificati.",
            to: "Rossi/pratica.md"
        )
        let after = controller.inspectorKey(for: session)

        #expect(before != after, "a landed write to the selected pratica's own note must advance the inspector key")
    }
}
