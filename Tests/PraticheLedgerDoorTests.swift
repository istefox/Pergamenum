import Foundation
import Testing
@testable import Pergamenum

// PG-172, ADR-0052 (`docs/plans/pg-172-pratiche-ledger-marker.md`, Tasks 2-4) - R-01 to R-06.
//
// The ledger is saved back over a file nothing else can rebuild, so what is pinned here is the
// direction of each mistake: a writer that saves a ledger which never came from the file it
// saves into (R-01, R-02), one that refuses a file that is merely absent (R-03), and one that
// saves over a file it could not read (R-04). Every test drives `PraticheController` directly
// and reads `ledger.json` back off a temporary state base, as the folder-trash batteries do.
//
// Seeding follows ADR-0052 §D9: a test that drives a writer against a real session seeds on DISK,
// because the door reads the file and would discard anything assigned to memory. `ledger` has no
// setter outside the controller's own file (R-10), so there is no test of that: the compiler
// enforces it and this suite could not even spell the assignment.
//
// New file rather than more tests in `PraticheControllerTests.swift`, which sits a few lines short
// of SwiftLint's `file_length` error (ADR-0045's precedent).

// MARK: - Fixtures

private let pathX = "01 Progetti/Tifone/X"
private let pathY = "01 Progetti/Rossi/Y"
private let pathZ = "01 Progetti/Verdi/Z"

/// Whole seconds: the ledger file stores ISO 8601 and drops any fraction, so a date with one would
/// never compare equal after a round trip.
private let seedDate = Date(timeIntervalSince1970: 1_749_557_170)

/// Two pratiche that differ in every field a writer could lose, so a partial or empty ledger
/// written over this one is visible in whichever field it drops.
private func twoPratiche() -> PraticaLedger {
    var x = PraticaLedger.PraticaState.empty
    x.importedMessageIDs = ["<x1@rossi-spa.it>"]
    x.entries = [PraticaLedger.Entry(messageID: "<x1@rossi-spa.it>", rowID: 11, conversationID: 1)]
    x.notInStore = ["<gone@rossi-spa.it>"]
    x.pending = ["<pending@rossi-spa.it>"]
    x.lastOpenedAt = seedDate
    x.trayCount = 7
    var y = PraticaLedger.PraticaState.empty
    y.importedMessageIDs = ["<y1@bianchi.it>", "<y2@bianchi.it>"]
    y.entries = [PraticaLedger.Entry(messageID: "<y1@bianchi.it>", rowID: 21, conversationID: 5)]
    y.lastSyncAt = seedDate
    y.trayCount = 2
    var ledger = PraticaLedger.empty
    ledger.byPraticaPath[pathX] = x
    ledger.byPraticaPath[pathY] = y
    return ledger
}

/// The other vault's own ledger: one pratica the first vault has never heard of.
private func otherVaultPratiche() -> PraticaLedger {
    var z = PraticaLedger.PraticaState.empty
    z.importedMessageIDs = ["<z1@verdi.it>"]
    z.trayCount = 4
    var ledger = PraticaLedger.empty
    ledger.byPraticaPath[pathZ] = z
    return ledger
}

private func stateImporting(_ ids: String...) -> PraticaLedger.PraticaState {
    var state = PraticaLedger.PraticaState.empty
    state.importedMessageIDs = ids
    return state
}

private func syncOutcome(importing ids: [String]) -> PraticaSyncEngine.SyncOutcome {
    PraticaSyncEngine.SyncOutcome(
        writtenFiles: [], importedMessageIDs: ids, noLongerInMail: [], regeneratedPendingFiles: [],
        cancelled: false, bridge: []
    )
}

@MainActor
private func session(of vault: borrowing TemporaryVault) -> VaultSession {
    VaultSession(root: vault.root, stateBase: vault.stateBase)
}

@MainActor
private func url(of session: VaultSession) -> URL {
    PraticheController.ledgerURL(for: session)
}

@MainActor
private func write(_ ledger: PraticaLedger, for session: VaultSession) throws {
    try ledger.save(to: url(of: session))
}

@MainActor
private func bytes(of session: VaultSession) throws -> Data {
    try Data(contentsOf: url(of: session))
}

@MainActor
private func onDisk(_ session: VaultSession) -> PraticaLedger {
    PraticaLedger.load(from: url(of: session))
}

private let corruptBytes = Data("{ not json".utf8)

/// Corrupt JSON at the ledger's own path: there, and unreadable.
@MainActor
private func plantCorruptLedger(for session: VaultSession) throws {
    let target = url(of: session)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try corruptBytes.write(to: target)
}

@MainActor
private func newController() -> PraticheController {
    PraticheController(probe: { .granted }, performSync: { _, _ in })
}

@MainActor
private func openedController(on vault: borrowing TemporaryVault) async throws -> (VaultController, VaultSession) {
    let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
    await vaultController.open(vault.root)
    return (vaultController, try #require(vaultController.session))
}

private func listItem(_ path: String) -> PraticaListItem {
    PraticaListItem(
        id: path, title: "Tifone", client: "rossi", status: "active",
        lastActivity: Date(), messagesSinceLastOpen: 0, hasNonEmptyTray: false
    )
}

/// Everything R-06 names, plus the three properties the reset also clears, filled with vault A's
/// state under `path`.
@MainActor
private func seedVaultScopedState(on controller: PraticheController, at path: String) {
    controller.pratiche = [listItem(path)]
    controller.trayProposals = [path: []]
    controller.trayCounts = [path: 3]
    controller.watchersByPraticaPath = [path: PraticaWatcher()]
    controller.selection = path
    controller.selectedEntryID = "entry-1"
    controller.expansion = PraticaTimelineModel.ExpansionState(expandedIDs: ["entry-1"])
    controller.timeline = [
        PraticaTimelineEntry(
            id: "entry-1", kind: .note, date: seedDate, direction: nil, senderDisplayName: "",
            subject: "Nota", bodyPreview: "", hasAttachments: false, messageID: nil, isInMail: true
        ),
    ]
    controller.details = [
        "entry-1": PraticaRowDetail(
            notePath: "\(path)/pratica.md", body: "", quotedHistory: nil, signature: nil, attachments: [],
            storeReferences: [], isPending: false, senderAddress: nil
        ),
    ]
    controller.links = PraticaLinks(notes: ["Offerta 2026"])
}

@MainActor
private func expectVaultScopedStateCleared(_ controller: PraticheController, _ context: String) {
    #expect(controller.pratiche.isEmpty, "pratiche: \(context)")
    #expect(controller.trayProposals.isEmpty, "trayProposals: \(context)")
    #expect(controller.trayCounts.isEmpty, "trayCounts: \(context)")
    #expect(controller.watchersByPraticaPath.isEmpty, "watchersByPraticaPath: \(context)")
    #expect(controller.selection == nil, "selection: \(context)")
    #expect(controller.selectedEntryID == nil, "selectedEntryID: \(context)")
    #expect(controller.expansion == PraticaTimelineModel.ExpansionState(), "expansion: \(context)")
    #expect(controller.timeline.isEmpty, "timeline: \(context)")
    #expect(controller.details.isEmpty, "details: \(context)")
    #expect(controller.links == .empty, "links: \(context)")
}

private func praticaNote(client: String) -> String {
    """
    ---
    date: 2026-09-01
    tags:
      - type-note
      - topic-pratica
      - client-\(client)
      - status-active
      - source-email
    pergamenum-dossier: 1
    pergamenum-dossier-counterparts:
      - m.rossi@rossi-spa.it
    ---

    Appunti pratica.
    """
}

/// The six save sites of `PraticheController+Ledger.swift`: the four SPEC.md names, the trash path
/// and the conversation remap the plan found beside them.
private enum LedgerWriter: String, CaseIterable, Sendable {
    case trayCount, openedStamp, folderMove, syncOutcome, trash, conversationRemap
}

@MainActor
private func run(
    _ writer: LedgerWriter, on pratiche: PraticheController, in vault: VaultController, session: VaultSession
) {
    switch writer {
    case .trayCount:
        pratiche.updateTray([], for: pathX, in: vault)
    case .openedStamp:
        pratiche.select(pathX, in: vault)
    case .folderMove:
        pratiche.moveLedgerState(from: pathX, to: "Calendario/\(pathX)", in: vault)
    case .syncOutcome:
        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<nuovo@rossi-spa.it>"]), for: pathX, session: session, isCurrentVault: true
        )
    case .trash:
        pratiche.followFolderTrashing(pathX, in: vault)
    case .conversationRemap:
        pratiche.remapLedgerConversations([1: 2], of: pathX, session: session, isCurrentVault: true)
    }
}

// MARK: - The door itself (Task 2)

@MainActor
@Suite(.serialized) struct PraticheLedgerDoorTests {
    // MARK: R-01: a controller that never loaded

    @Test func aWriterOnANeverLoadedControllerReadsTheFileFirstAndKeepsEveryOtherPratica() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let controller = newController()
        #expect(controller.ledger == .empty, "precondition: nothing was ever loaded")
        #expect(controller.ledgerOrigin == .none)

        let result = controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX]?.trayCount = 0 }

        var expected = seeded
        expected.byPraticaPath[pathX]?.trayCount = 0
        #expect(result == .saved)
        #expect(onDisk(session) == expected, "every pratica's prior state survives; only the intended field differs")
        #expect(controller.ledger == expected)
        #expect(controller.ledgerOrigin == .loaded(url(of: session)))
    }

    /// `.none` to a file is a first load and not a change of vault: what the controller holds for
    /// the pratica it already shows is not the previous vault's, and must not be wiped by the first
    /// write reaching the door.
    @Test func theFirstLoadFromNothingResetsNothing() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try write(twoPratiche(), for: session)
        let controller = newController()
        seedVaultScopedState(on: controller, at: pathX)

        controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX]?.trayCount = 0 }

        #expect(controller.trayCounts == [pathX: 3])
        #expect(controller.watchersByPraticaPath.keys.contains(pathX))
        #expect(controller.selection == pathX)
        #expect(controller.pratiche.map(\.id) == [pathX])
    }

    // MARK: R-02: a writer for another vault

    @Test func aWriterForAnotherVaultLeavesTheFirstVaultsFileByteIdentical() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        try write(otherVaultPratiche(), for: sessionB)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 9 }
        let bytesOfA = try bytes(of: sessionA)

        let result = controller.updateLedger(.live(sessionB)) { $0.byPraticaPath[pathZ]?.trayCount = 6 }

        #expect(result == .saved)
        #expect(try bytes(of: sessionA) == bytesOfA, "A's file is not touched by a write that belongs to B")
        var expectedB = otherVaultPratiche()
        expectedB.byPraticaPath[pathZ]?.trayCount = 6
        #expect(onDisk(sessionB) == expectedB, "B's file holds B's prior state plus the change")
        #expect(onDisk(sessionB).byPraticaPath[pathX] == nil, "and nothing from A")
        #expect(onDisk(sessionB).byPraticaPath[pathY] == nil)
        #expect(controller.ledgerOrigin == .loaded(url(of: sessionB)))
    }

    /// R-02 and R-03 together: B has no ledger yet, so the write is a creation, and it must not be
    /// a creation of A's ledger under B's name.
    @Test func aWriterForAnotherVaultWithNoLedgerYetStartsFromEmptyAndNothingOfTheFirstLeaksIn() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 9 }
        #expect(!FileManager.default.fileExists(atPath: url(of: sessionB).path(percentEncoded: false)), "precondition")

        let fresh = stateImporting("<z@verdi.it>")
        let result = controller.updateLedger(.live(sessionB)) { $0.byPraticaPath[pathZ] = fresh }

        #expect(result == .saved)
        var expectedB = PraticaLedger.empty
        expectedB.byPraticaPath[pathZ] = stateImporting("<z@verdi.it>")
        #expect(onDisk(sessionB) == expectedB)
    }

    @Test func aStaleSessionWriteNeverTouchesTheLiveLedgerOrItsMarker() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        try write(otherVaultPratiche(), for: sessionB)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 9 }
        let liveLedger = controller.ledger
        let liveOrigin = controller.ledgerOrigin
        let bytesOfA = try bytes(of: sessionA)

        let result = controller.updateLedger(.stale(sessionB)) { $0.byPraticaPath[pathZ]?.trayCount = 6 }

        #expect(result == .saved)
        #expect(controller.ledger == liveLedger, "the live ledger describes the live vault alone")
        #expect(controller.ledgerOrigin == liveOrigin, "and so does its marker")
        #expect(try bytes(of: sessionA) == bytesOfA)
        var expectedB = otherVaultPratiche()
        expectedB.byPraticaPath[pathZ]?.trayCount = 6
        #expect(onDisk(sessionB) == expectedB, "B's own file was read fresh, changed and written back")
    }

    /// PG-191: a vault closed and reopened on the SAME root mid-run gets a brand-new
    /// `VaultSession` identity for the file `ledgerOrigin` already names. `.stale` must reroute
    /// to `.live` for that session, or the write lands on disk without updating `ledger`, and the
    /// next `.live` writer overwrites it with older in-memory state (one re-sync lost, PG-172's
    /// loss again). Contrast with `aStaleSessionWriteNeverTouchesTheLiveLedgerOrItsMarker` above,
    /// where the session names a genuinely different vault and must NOT reroute.
    @Test func aStaleSessionForTheSameFileAsTheLiveMarkerReroutesToLive() throws {
        let vault = try TemporaryVault()
        let sessionA = session(of: vault)
        let sessionAReopened = session(of: vault)
        try write(twoPratiche(), for: sessionA)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 9 }
        let liveOrigin = controller.ledgerOrigin

        let result = controller.updateLedger(.stale(sessionAReopened)) { $0.byPraticaPath[pathX]?.trayCount = 6 }

        #expect(result == .saved)
        #expect(controller.ledgerOrigin == liveOrigin, "still the same file, so the marker does not move")
        #expect(controller.ledger.byPraticaPath[pathX]?.trayCount == 6, "the write must land in memory, not only on disk")
        #expect(onDisk(sessionA).byPraticaPath[pathX]?.trayCount == 6)
    }

    @Test func aStaleSessionWriteOnANeverLoadedControllerStillLeavesTheMarkerAlone() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try write(twoPratiche(), for: session)
        let controller = newController()

        controller.updateLedger(.stale(session)) { $0.byPraticaPath[pathX]?.trayCount = 0 }

        #expect(controller.ledger == .empty)
        #expect(controller.ledgerOrigin == .none)
        var expected = twoPratiche()
        expected.byPraticaPath[pathX]?.trayCount = 0
        #expect(onDisk(session) == expected)
    }

    // MARK: R-06: the vault-scoped state follows the marker

    @Test func aWriterForAnotherVaultResetsTheVaultScopedState() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 8 }
        seedVaultScopedState(on: controller, at: pathX)
        #expect(controller.trayCounts == [pathX: 3], "precondition: A's state is really there")

        controller.updateLedger(.live(sessionB)) { $0.byPraticaPath[pathZ] = stateImporting("<z@verdi.it>") }

        expectVaultScopedStateCleared(controller, "vault A's state must not survive into vault B")
    }

    /// What the reset deliberately leaves alone (ADR-0052 §D5): a writer reaches the reset in the
    /// middle of a run, and clearing a tombstone or a claim there would put back the ledger key a
    /// trash had just removed.
    @Test func aWriterForAnotherVaultLeavesAnInFlightRunsClaimAndTombstoneAlone() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 8 }
        controller.beginSync(pathX)
        controller.beginRegeneration(pathY)
        controller.forgottenPraticaPaths = [pathX]
        controller.praticaPathRedirects = [pathY: "Calendario/\(pathY)"]

        controller.updateLedger(.live(sessionB)) { $0.byPraticaPath[pathZ] = stateImporting("<z@verdi.it>") }

        #expect(controller.syncingPraticaPath == pathX)
        #expect(controller.regeneratingPraticaPaths == [pathY])
        #expect(controller.forgottenPraticaPaths == [pathX])
        #expect(controller.praticaPathRedirects == [pathY: "Calendario/\(pathY)"])
    }

    @Test func aClosedVaultClearsTheSameSet() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try write(twoPratiche(), for: session)
        let controller = newController()
        controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX]?.trayCount = 8 }
        seedVaultScopedState(on: controller, at: pathX)
        let bytesBefore = try bytes(of: session)

        let result = controller.updateLedger(.live(nil)) { _ in }

        #expect(result == .unchanged)
        expectVaultScopedStateCleared(controller, "closing the vault clears what belonged to it")
        #expect(controller.ledger == .empty)
        #expect(controller.ledgerOrigin == .none)
        #expect(try bytes(of: session) == bytesBefore, "and the vault's own file is not the closed vault's to rewrite")
    }

    // MARK: PG-191: select must not let the door's own reset erase the click

    /// The click that started this bug report: a row tap delivered after the environment's
    /// `vault` has already switched, but before this controller has loaded THAT vault's own
    /// ledger. `select` used to set `selection` and only then call `markOpened`, whose door can
    /// reset `selection` to `nil` on exactly this marker mismatch - dropping the click right
    /// after it landed. Two vaults share the same pratica path on purpose (the ADR-0052 §D5
    /// comment's own example - "01 Progetti/Tifone is not an unusual name") so a passing
    /// `selection` is unambiguous proof it names the row this call was actually given.
    @Test func selectSurvivesAVaultSwitchInsteadOfBeingSilentlyDropped() async throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        try vaultA.write(praticaNote(client: "rossi"), to: "\(pathX)/pratica.md")
        try vaultB.write(praticaNote(client: "bianchi"), to: "\(pathX)/pratica.md")
        let (vaultControllerA, sessionA) = try await openedController(on: vaultA)
        let (vaultControllerB, sessionB) = try await openedController(on: vaultB)
        let pratiche = newController()
        pratiche.load(from: vaultControllerA)
        #expect(pratiche.ledgerOrigin == .loaded(url(of: sessionA)), "precondition: memory came from A's file")

        pratiche.select(pathX, in: vaultControllerB)

        #expect(pratiche.selection == pathX, "the click must not be dropped by the door's own reset")
        #expect(pratiche.ledgerOrigin == .loaded(url(of: sessionB)), "the door has adopted B's file by the time select returns")

        vaultControllerA.close()
        vaultControllerB.close()
    }

    // MARK: R-03: no file at all is not a refusal

    @Test func aFirstWriteWithNoLedgerFileSavesRatherThanRefusing() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        let target = url(of: session)
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)), "precondition")
        let controller = newController()

        let created = stateImporting("<x@rossi-spa.it>")
        let result = controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX] = created }

        #expect(result == .saved)
        #expect(onDisk(session).byPraticaPath[pathX] == created)
        #expect(controller.ledgerOrigin == .loaded(target))
        #expect(controller.problem == nil, "a first-ever write is a creation, not a problem")
    }

    @Test func aFirstWriteForAStaleSessionWithNoLedgerFileSavesToo() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        let controller = newController()

        let created = stateImporting("<x@rossi-spa.it>")
        let result = controller.updateLedger(.stale(session)) { $0.byPraticaPath[pathX] = created }

        #expect(result == .saved)
        #expect(onDisk(session).byPraticaPath[pathX] == created)
        #expect(controller.problem == nil)
    }

}

// MARK: - An unreadable ledger is never written, and a repaired one is (R-04, R-05)

@MainActor
@Suite(.serialized) struct PraticheLedgerUnreadableTests {

    @Test func anUnreadableLedgerIsNeverWrittenAndIsReportedOnce() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try plantCorruptLedger(for: session)
        let target = url(of: session)
        let controller = newController()

        var results: [PraticheController.LedgerWrite] = []
        results.append(controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX] = stateImporting("<1@a.it>") })

        let sentence = try #require(controller.problem, "the first refusal is reported")
        #expect(sentence.contains("registro delle pratiche"))
        #expect(sentence.contains(target.path(percentEncoded: false)), "and names the file")

        // The other calls must stay silent: cleared by hand, so any repeat would show.
        controller.problem = nil
        results.append(controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX] = stateImporting("<2@a.it>") })
        results.append(controller.updateLedger(.live(session)) { $0.byPraticaPath[pathY] = stateImporting("<3@a.it>") })
        results.append(controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX] = stateImporting("<4@a.it>") })

        #expect(results == Array(repeating: .refused, count: 4))
        #expect(controller.problem == nil, "one message per file per session, however many writers run")
        #expect(try bytes(of: session) == corruptBytes, "the file is byte-identical after four refused writes")
        #expect(controller.ledgerOrigin == .unreadable(target))
        #expect(
            controller.ledger.byPraticaPath[pathX] == stateImporting("<4@a.it>"),
            "applied in memory so the session stays coherent (ADR-0052 §D3), and saved nowhere"
        )
    }

    /// Each of the six save sites, alone, against a file it cannot read. The four SPEC.md names,
    /// the trash path, and the conversation remap.
    @Test(arguments: LedgerWriter.allCases)
    private func anUnreadableLedgerIsLeftByteIdenticalByEveryWriter(_ writer: LedgerWriter) async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        try plantCorruptLedger(for: session)
        let pratiche = newController()

        run(writer, on: pratiche, in: vaultController, session: session)

        #expect(try bytes(of: session) == corruptBytes, "\(writer): the unreadable file must not be altered")
        #expect(pratiche.problem?.contains("registro delle pratiche") == true, "\(writer): reported")
        let named = pratiche.problem?.contains(url(of: session).path(percentEncoded: false)) == true
        #expect(named, "\(writer): names the file")
        vaultController.close()
    }

    @Test func allSixWritersInTurnReportAnUnreadableLedgerExactlyOnce() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        try plantCorruptLedger(for: session)
        let pratiche = newController()

        var reports = 0
        for writer in LedgerWriter.allCases {
            pratiche.problem = nil
            run(writer, on: pratiche, in: vaultController, session: session)
            if pratiche.problem?.contains("registro delle pratiche") == true { reports += 1 }
        }

        #expect(reports == 1, "one sentence for the file for the whole session, not one per writer")
        #expect(try bytes(of: session) == corruptBytes)
        vaultController.close()
    }

    @Test func aStaleSessionWriteToAnUnreadableLedgerIsRefusedAndReportedOnce() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        try plantCorruptLedger(for: sessionB)
        let controller = newController()
        controller.updateLedger(.live(sessionA)) { $0.byPraticaPath[pathX]?.trayCount = 9 }
        let bytesOfA = try bytes(of: sessionA)

        let firstTry = stateImporting("<z@verdi.it>")
        let first = controller.updateLedger(.stale(sessionB)) { $0.byPraticaPath[pathZ] = firstTry }

        #expect(first == .refused)
        #expect(controller.problem?.contains(url(of: sessionB).path(percentEncoded: false)) == true)
        controller.problem = nil
        let secondTry = stateImporting("<z2@verdi.it>")
        let second = controller.updateLedger(.stale(sessionB)) { $0.byPraticaPath[pathZ] = secondTry }
        #expect(second == .refused)
        #expect(controller.problem == nil, "reported once per file")
        #expect(try bytes(of: sessionB) == corruptBytes)
        #expect(try bytes(of: sessionA) == bytesOfA, "and the live vault's file is not involved")
        #expect(controller.ledgerOrigin == .loaded(url(of: sessionA)), "the marker still describes the live vault")
    }

    // MARK: R-05: repaired, loaded again, saving again

    @Test func aRepairedLedgerSavesAgainAfterTheNextLoad() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try plantCorruptLedger(for: session)
        let target = url(of: session)
        let controller = newController()
        let refused = controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX] = stateImporting("<1@a.it>") }
        #expect(refused == .refused, "precondition")
        let repaired = twoPratiche()
        try write(repaired, for: session)

        let beforeLoad = controller.updateLedger(.live(session)) { $0.byPraticaPath[pathY]?.trayCount = 0 }
        #expect(beforeLoad == .refused, "an unreadable marker keeps refusing until a load finds the file readable")
        #expect(onDisk(session) == repaired, "and the repaired file is untouched until then")

        controller.reloadLedger(for: session)
        #expect(controller.ledgerOrigin == .loaded(target))
        #expect(controller.ledger == repaired)

        let saved = controller.updateLedger(.live(session)) { $0.byPraticaPath[pathY]?.trayCount = 0 }

        #expect(saved == .saved)
        var expected = repaired
        expected.byPraticaPath[pathY]?.trayCount = 0
        #expect(onDisk(session) == expected)
    }

    /// The same, through `load(from:)`, the call the pane, the settings tab and both sheets make.
    @Test func aRepairedLedgerSavesAgainAfterLoadFromTheController() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        try plantCorruptLedger(for: session)
        let pratiche = newController()
        pratiche.updateTray([], for: pathX, in: vaultController)
        #expect(pratiche.ledgerOrigin == .unreadable(url(of: session)), "precondition")
        let repaired = twoPratiche()
        try write(repaired, for: session)

        pratiche.load(from: vaultController)
        pratiche.updateTray([], for: pathX, in: vaultController)

        var expected = repaired
        expected.byPraticaPath[pathX]?.trayCount = 0
        #expect(onDisk(session) == expected, "a load returns the controller to normal saving")
        vaultController.close()
    }

    /// «cleared per file when a later read of it succeeds» (ADR-0052 §D3): a file that is repaired
    /// and breaks again is a new problem for the person, not one already reported.
    @Test func aFileRepairedAndBrokenAgainIsReportedAgain() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try plantCorruptLedger(for: session)
        let controller = newController()
        controller.updateLedger(.live(session)) { $0.byPraticaPath[pathX] = stateImporting("<1@a.it>") }
        #expect(controller.problem != nil, "precondition")
        try write(twoPratiche(), for: session)
        controller.reloadLedger(for: session)
        controller.problem = nil

        try corruptBytes.write(to: url(of: session))
        controller.reloadLedger(for: session)

        #expect(controller.problem?.contains("registro delle pratiche") == true)
    }
}

// MARK: - The six writers on a controller that never loaded (Task 3)

@MainActor
@Suite(.serialized) struct PraticheLedgerFreshWriterTests {
    @Test func trayCountOnANeverLoadedControllerKeepsEveryOtherPratica() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let pratiche = newController()

        pratiche.updateTray([], for: pathX, in: vaultController)

        var expected = seeded
        expected.byPraticaPath[pathX]?.trayCount = 0
        #expect(onDisk(session) == expected)
        vaultController.close()
    }

    @Test func openedStampOnANeverLoadedControllerKeepsEveryOtherPratica() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let pratiche = newController()

        pratiche.select(pathX, in: vaultController)

        let stamped = try #require(onDisk(session).byPraticaPath[pathX]?.lastOpenedAt)
        #expect(stamped > seedDate, "the opened stamp moved forward")
        var expected = seeded
        expected.byPraticaPath[pathX]?.lastOpenedAt = stamped
        #expect(onDisk(session) == expected, "and nothing else about either pratica changed")
        vaultController.close()
    }

    @Test func folderMoveOnANeverLoadedControllerKeepsEveryOtherPratica() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let pratiche = newController()
        let moved = "Calendario/\(pathX)"

        pratiche.moveLedgerState(from: pathX, to: moved, in: vaultController)

        var expected = seeded
        expected.byPraticaPath[moved] = expected.byPraticaPath.removeValue(forKey: pathX)
        #expect(onDisk(session) == expected, "the key followed the folder and the other pratica was not lost")
        vaultController.close()
    }

    @Test func syncOutcomeOnANeverLoadedControllerKeepsEveryOtherPratica() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let pratiche = newController()

        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<nuovo@rossi-spa.it>"]), for: pathX, session: session, isCurrentVault: true
        )

        let result = onDisk(session)
        #expect(result.byPraticaPath[pathY] == seeded.byPraticaPath[pathY], "the other pratica is untouched")
        let x = try #require(result.byPraticaPath[pathX])
        let priorX = try #require(seeded.byPraticaPath[pathX])
        #expect(
            x.importedMessageIDs == ["<nuovo@rossi-spa.it>", "<x1@rossi-spa.it>"],
            "what it imported joins what was there"
        )
        #expect(x.entries == priorX.entries)
        #expect(x.notInStore == priorX.notInStore)
        #expect(x.pending == priorX.pending)
        #expect(x.trayCount == priorX.trayCount)
        #expect(x.lastOpenedAt == priorX.lastOpenedAt)
        #expect(x.lastSyncAt != nil, "and the outcome itself was recorded")
        vaultController.close()
    }

    @Test func trashOnANeverLoadedControllerKeepsEveryOtherPratica() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let pratiche = newController()

        pratiche.followFolderTrashing(pathX, in: vaultController)

        var expected = seeded
        expected.byPraticaPath[pathX] = nil
        #expect(onDisk(session) == expected, "the trashed pratica's key went and every other one stayed")
        vaultController.close()
    }

    @Test func conversationRemapOnANeverLoadedControllerKeepsEveryOtherPratica() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let seeded = twoPratiche()
        try write(seeded, for: session)
        let pratiche = newController()

        pratiche.remapLedgerConversations([1: 2], of: pathX, session: session, isCurrentVault: true)

        var expected = seeded
        expected.byPraticaPath[pathX]?.entries = [
            PraticaLedger.Entry(messageID: "<x1@rossi-spa.it>", rowID: 11, conversationID: 2),
        ]
        #expect(onDisk(session) == expected, "the entry was repointed and nothing else in the ledger moved")
        vaultController.close()
    }

    /// The same remap for a session that is no longer the live one: its own file, and neither the
    /// live vault's memory nor its file (`runExclusive`'s window between the note rewrite and the
    /// ledger repointing).
    @Test func conversationRemapForAStaleSessionWritesItsOwnFile() throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        let sessionA = session(of: vaultA)
        let sessionB = session(of: vaultB)
        try write(twoPratiche(), for: sessionA)
        var ledgerB = twoPratiche()
        ledgerB.byPraticaPath[pathX]?.trayCount = 1
        try write(ledgerB, for: sessionB)
        let pratiche = newController()
        pratiche.updateLedger(.live(sessionA)) { _ in }
        let liveLedger = pratiche.ledger
        let bytesOfA = try bytes(of: sessionA)

        pratiche.remapLedgerConversations([1: 2], of: pathX, session: sessionB, isCurrentVault: false)

        var expectedB = ledgerB
        expectedB.byPraticaPath[pathX]?.entries = [
            PraticaLedger.Entry(messageID: "<x1@rossi-spa.it>", rowID: 11, conversationID: 2),
        ]
        #expect(onDisk(sessionB) == expectedB, "B's own file was repointed")
        #expect(try bytes(of: sessionA) == bytesOfA, "the live vault's file was not")
        #expect(pratiche.ledger == liveLedger, "nor was the live ledger in memory")
        #expect(pratiche.ledgerOrigin == .loaded(url(of: sessionA)))
    }

    // MARK: Relocation with a real session (the two in-memory seeds that no longer reach the outcome)

    /// `PraticaLedgerFolderRelocationTests.recordSyncOutcomeFoldsIntoRelocatedPathAndNeverResurrectsTheOldKey`
    /// seeds `.live(nil)` on a controller whose `recordSyncOutcome` then reads a real session's
    /// file: the door discards that memory seed, so the test still proves the path resolution but
    /// no longer proves the outcome folds into the pratica's PRIOR state. This one seeds on disk.
    @Test func aSyncOutcomeAfterARelocationFoldsIntoTheMovedKeyAndKeepsItsHistory() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let oldPath = pathX
        let newPath = "Calendario/\(pathX)"
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath[oldPath] = stateImporting("<preesistente@rossi-spa.it>")
        try write(seeded, for: session)
        let pratiche = newController()
        pratiche.load(from: vaultController)
        pratiche.beginSync(oldPath)

        pratiche.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vaultController)
        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<a@rossi-spa.it>"]), for: oldPath, session: session, isCurrentVault: true
        )

        for ledger in [pratiche.ledger, onDisk(session)] {
            #expect(ledger.byPraticaPath[oldPath] == nil, "the orphaned key is not resurrected")
            #expect(
                ledger.byPraticaPath[newPath]?.importedMessageIDs
                    == ["<a@rossi-spa.it>", "<preesistente@rossi-spa.it>"],
                "the outcome folds into the moved key AND keeps what the pratica had imported before"
            )
        }
        vaultController.close()
    }

    /// The two-concurrent-callers shape (a sync and a «Rigenera…» both captured the pre-move
    /// path), with the prior state on disk so the second outcome's merge is visible too.
    @Test func twoOutcomesAfterARelocationBothFoldIntoTheMovedKeyAndKeepItsHistory() async throws {
        let vault = try TemporaryVault()
        let (vaultController, session) = try await openedController(on: vault)
        let oldPath = pathX
        let newPath = "Calendario/\(pathX)"
        var seeded = PraticaLedger.empty
        seeded.byPraticaPath[oldPath] = stateImporting("<preesistente@rossi-spa.it>")
        try write(seeded, for: session)
        let pratiche = newController()
        pratiche.load(from: vaultController)
        pratiche.beginSync(oldPath)
        pratiche.beginRegeneration(oldPath)

        pratiche.followFolderRelocations([MovedNote(old: oldPath, new: newPath)], in: vaultController)
        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<a@rossi-spa.it>"]), for: oldPath, session: session, isCurrentVault: true
        )
        pratiche.recordSyncOutcome(
            syncOutcome(importing: ["<b@rossi-spa.it>"]), for: oldPath, session: session, isCurrentVault: true
        )

        for ledger in [pratiche.ledger, onDisk(session)] {
            #expect(ledger.byPraticaPath[oldPath] == nil, "neither caller resurrects the old key")
            #expect(
                ledger.byPraticaPath[newPath]?.importedMessageIDs
                    == ["<a@rossi-spa.it>", "<b@rossi-spa.it>", "<preesistente@rossi-spa.it>"],
                "both outcomes land on the moved key, on top of what it already held"
            )
        }
        vaultController.close()
    }
}

// MARK: - `load(from:)` goes through the same loader (Task 4)

@MainActor
@Suite(.serialized) struct PraticheLedgerLoadTests {
    private static let pathA = "01 Progetti/Tifone"
    private static let pathB = "01 Progetti/Altro"

    @Test func loadingVaultBAfterVaultAClearsTrayWatchersSelectionTimelineAndDetails() async throws {
        let vaultA = try TemporaryVault()
        let vaultB = try TemporaryVault()
        try vaultA.write(praticaNote(client: "rossi"), to: "\(Self.pathA)/pratica.md")
        try vaultB.write(praticaNote(client: "verdi"), to: "\(Self.pathB)/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vaultA.root)
        let pratiche = newController()
        pratiche.load(from: vaultController)
        #expect(pratiche.pratiche.map(\.id) == [Self.pathA], "precondition: A's pratica is listed")
        seedVaultScopedState(on: pratiche, at: Self.pathA)

        await vaultController.open(vaultB.root)
        pratiche.load(from: vaultController)

        #expect(pratiche.trayProposals.isEmpty, "trayProposals")
        #expect(pratiche.trayCounts.isEmpty, "trayCounts")
        #expect(pratiche.watchersByPraticaPath.isEmpty, "watchersByPraticaPath")
        #expect(pratiche.selection == nil, "selection")
        #expect(pratiche.timeline.isEmpty, "timeline")
        #expect(pratiche.details.isEmpty, "details")
        #expect(pratiche.pratiche.map(\.id) == [Self.pathB], "the list holds no entry of vault A")
        vaultController.close()
    }

    /// The trap the ordering exists to avoid: `load(from:)` runs after EVERY pratica command
    /// (`PraticaCommandActions.swift:98,111,128`), so a reset there would wipe the tray on every
    /// rename of the pratica being looked at.
    @Test func loadingTheSameVaultAgainKeepsTheTrayStateAndTheWatchers() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNote(client: "rossi"), to: "\(Self.pathA)/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = newController()
        pratiche.load(from: vaultController)
        pratiche.trayProposals = [Self.pathA: []]
        pratiche.trayCounts = [Self.pathA: 3]
        pratiche.watchersByPraticaPath = [Self.pathA: PraticaWatcher()]
        pratiche.selection = Self.pathA

        pratiche.load(from: vaultController)

        #expect(pratiche.trayProposals == [Self.pathA: []])
        #expect(pratiche.trayCounts == [Self.pathA: 3])
        #expect(pratiche.watchersByPraticaPath.keys.contains(Self.pathA))
        #expect(pratiche.selection == Self.pathA)
        vaultController.close()
    }

    @Test func closingTheVaultClearsTheSameSet() async throws {
        let vault = try TemporaryVault()
        try vault.write(praticaNote(client: "rossi"), to: "\(Self.pathA)/pratica.md")
        let vaultController = VaultController(recents: .volatile(), openTabs: .volatile())
        await vaultController.open(vault.root)
        let pratiche = newController()
        pratiche.load(from: vaultController)
        seedVaultScopedState(on: pratiche, at: Self.pathA)

        vaultController.close()
        pratiche.load(from: vaultController)

        expectVaultScopedStateCleared(pratiche, "closing the vault clears what belonged to it")
        #expect(pratiche.ledger == .empty)
        #expect(pratiche.ledgerOrigin == .none)
    }

    /// `load(from:)` reads again even when the marker already names the file: a ledger changed on
    /// disk (by `perg`, or by hand) is what the next load must show.
    @Test func reloadingTheSameLedgerReadsTheFileAgain() throws {
        let vault = try TemporaryVault()
        let session = session(of: vault)
        try write(twoPratiche(), for: session)
        let controller = newController()
        controller.updateLedger(.live(session)) { _ in }
        #expect(controller.ledger == twoPratiche(), "precondition")
        try otherVaultPratiche().save(to: url(of: session))

        controller.reloadLedger(for: session)

        #expect(controller.ledger == otherVaultPratiche())
    }
}
