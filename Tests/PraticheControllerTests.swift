import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-17, R-18.
//
// No test here touches `~/Library/Mail`; `stateReadsEPERMAsNotGranted` and the
// `PraticheController` tests build their own throwaway, unreadable file instead.
//
// The other suites that used to share this file live in `PraticheControllerTests+*.swift`,
// split out under PG-293 (#638) to clear its SwiftLint `file_length` warning.

@Suite(.serialized) struct PraticaWatcherTests {
    // MARK: - R-17: automatic triggers, throttle, debounce, closed-pratica escape hatch

    @Test func windowKeyTriggerIsThrottledToOncePerSixtySeconds() {
        var watcher = PraticaWatcher()
        let t0 = Date()

        #expect(watcher.decideWindowKeyTrigger(eligibility: .automatic, now: t0) == true)
        #expect(
            watcher.decideWindowKeyTrigger(eligibility: .automatic, now: t0.addingTimeInterval(30)) == false,
            "a second window-key sync inside the 60s throttle must not run"
        )
        #expect(
            watcher.decideWindowKeyTrigger(eligibility: .automatic, now: t0.addingTimeInterval(61)) == true,
            "past the 60s window, the next window-key sync runs again"
        )
    }

    @Test func fsEventsPulseFiresTenSecondsAfterTheLastPulseNotTheFirst() {
        var watcher = PraticaWatcher()
        let t0 = Date()

        watcher.registerFSEventsPulse(now: t0)
        #expect(watcher.isFSEventsFireDue(now: t0.addingTimeInterval(5)) == false)

        // A second pulse before the first one's debounce elapsed resets the window -
        // this is a debounce, not a throttle: a burst of writes collapses into one
        // sync 10s after the *last* pulse, not 10s after the first.
        watcher.registerFSEventsPulse(now: t0.addingTimeInterval(5))
        #expect(
            watcher.isFSEventsFireDue(now: t0.addingTimeInterval(12)) == false,
            "the second pulse should have pushed the debounce window out to t+15"
        )
        #expect(
            watcher.isFSEventsFireDue(now: t0.addingTimeInterval(16)) == true,
            "10s after the last pulse, the fire is due"
        )
    }

    @Test func closedPraticaSyncsOnlyThroughManualRefresh() {
        var watcher = PraticaWatcher()
        let now = Date()

        #expect(
            watcher.decideImmediateTrigger(.vaultOpen, eligibility: .manualOnly, now: now) == false,
            "status-archived/status-final must not sync on vault open"
        )
        #expect(
            watcher.decideWindowKeyTrigger(eligibility: .manualOnly, now: now) == false,
            "status-archived/status-final must not sync on window-key"
        )
        watcher.registerFSEventsPulse(now: now)
        #expect(
            watcher.isFSEventsFireDue(now: now.addingTimeInterval(11)) == false,
            "status-archived/status-final must not sync automatically, however long the debounce waits"
        )
        #expect(
            watcher.decideImmediateTrigger(.manualRefresh, eligibility: .manualOnly, now: now) == true,
            "«Aggiorna ora» always works, regardless of eligibility"
        )
    }

    @Test func activeOrWaitingPraticaSyncsOnVaultOpen() {
        let watcher = PraticaWatcher()
        #expect(watcher.decideImmediateTrigger(.vaultOpen, eligibility: .automatic, now: Date()) == true)
    }
}

// MARK: - R-18: Full Disk Access probe and banner

@Suite(.serialized) struct FullDiskAccessProbeTests {
    @Test func stateReadsEPERMAsNotGranted() throws {
        let unreadable = try Self.makeUnreadableFile()
        defer { Self.restoreAndRemove(unreadable) }

        #expect(FullDiskAccessProbe.state(probing: unreadable) == .notGranted)
    }

    @Test func stateReadsAnOrdinaryReadableFileAsGranted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-fda-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let readable = directory.appending(path: "Envelope Index", directoryHint: .notDirectory)
        try Data("fixture".utf8).write(to: readable)

        #expect(FullDiskAccessProbe.state(probing: readable) == .granted)
    }

    /// R-18/`FullDiskAccessProbe.swift`'s own doc comment: "Every other failure, ENOENT
    /// first among them, answers `.granted`" - a missing store is «Nessun archivio di
    /// Mail trovato», never the Full Disk Access banner. Converts
    /// `UITests/PraticheUITests.swift:192`
    /// (`testTheFullDiskAccessBannerIsAbsentWithAReadableMailStoreFixture`)'s own
    /// setup: a readable, empty temporary directory whose `Envelope Index` file was
    /// never written, exactly what that UI test's `mailStoreRoot` fixture is.
    @Test func stateReadsENOENTAsGranted() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-fda-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appending(path: "Envelope Index", directoryHint: .notDirectory)

        #expect(FullDiskAccessProbe.state(probing: missing) == .granted)
    }

    static func makeUnreadableFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-fda-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "Envelope Index", directoryHint: .notDirectory)
        try Data("fixture".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    /// Permissions restored before removal - a 000 file refuses its own deletion the
    /// same way `VaultStateTests`' 555 directories do.
    static func restoreAndRemove(_ file: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path(percentEncoded: false))
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}

@MainActor
@Suite(.serialized) struct PraticheControllerTests {
    @Test func fullDiskAccessBannerClearsOnTheNextTriggerWithNoRestart() async throws {
        let unreadable = try FullDiskAccessProbeTests.makeUnreadableFile()
        defer { FullDiskAccessProbeTests.restoreAndRemove(unreadable) }

        var syncCallCount = 0
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state(probing: unreadable) },
            performSync: { _, _ in syncCallCount += 1 }
        )

        // Real behaviour (R-18): the probe runs once at `init`, so an unreadable
        // store is reflected before any trigger fires at all.
        #expect(controller.fullDiskAccessState == .notGranted)

        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .vaultOpen, eligibility: .automatic)
        #expect(syncCallCount == 0, "a sync must not run while the store is unreadable")

        // Grant access without restarting the app - the *next* trigger alone must
        // notice (R-18: "the probe is repeated per trigger").
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: unreadable.path(percentEncoded: false)
        )
        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .vaultOpen, eligibility: .automatic)
        #expect(controller.fullDiskAccessState == .granted)
        #expect(syncCallCount == 1)
    }

    @Test func noSyncEverRunsWhileTheStoreStaysUnreadable() async throws {
        let unreadable = try FullDiskAccessProbeTests.makeUnreadableFile()
        defer { FullDiskAccessProbeTests.restoreAndRemove(unreadable) }

        var syncCallCount = 0
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state(probing: unreadable) },
            performSync: { _, _ in syncCallCount += 1 }
        )

        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .vaultOpen, eligibility: .automatic)
        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .windowKey, eligibility: .automatic)
        await controller.trigger("01 Progetti/Rossi/Offerta", kind: .manualRefresh, eligibility: .manualOnly)

        #expect(syncCallCount == 0)
        #expect(controller.fullDiskAccessState == .notGranted)
    }
}

// MARK: - R-30: `selectedTray`, the chosen pratica's own proposals

// plan `docs/plans/ui-suite-replacement.md` Task 5, PR 3: converts
// `UITests/PraticheUITests.swift:211` (`testTheTrayIsAbsentWithNoProposals`)'s own
// claim - a pratica with no tray proposals reads back an empty `selectedTray`, which
// is what makes `PraticaTrayStrip` (`PraticaTrayModel.isHidden(_:)`) absent - plus the
// two neighbouring shapes `selectedTray`'s own guard covers: no selection at all, and
// a selection that is not the only key `trayProposals` holds.
@MainActor
@Suite(.serialized) struct PraticheControllerSelectedTrayTests {
    private static func proposal(conversationID: Int = 1) -> PraticaTrayModel.PraticaTrayProposal {
        PraticaTrayModel.PraticaTrayProposal(
            conversationID: conversationID, subject: "Richiesta offerta", counterpart: "m.rossi@rossi-spa.it",
            dateRange: Date()...Date(), messageCount: 2
        )
    }

    @Test func selectedTrayIsEmptyWithNoSelectionEvenWhenSomeOtherPraticaHasProposals() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.trayProposals["01 Progetti/Rossi/Offerta"] = [Self.proposal()]

        #expect(controller.selection == nil)
        #expect(controller.selectedTray.isEmpty, "no pratica is selected, so nothing is that pratica's own tray")
    }

    @Test func selectedTrayIsEmptyWhenTheSelectedPraticaHasNoProposals() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        controller.selection = "01 Progetti/Rossi/Offerta"

        #expect(controller.selectedTray.isEmpty)
    }

    @Test func selectedTrayReadsBackExactlyTheSelectedPraticasOwnProposalsNeverASiblings() {
        let controller = PraticheController(probe: { .granted }, performSync: { _, _ in })
        let mine = Self.proposal()
        controller.trayProposals["01 Progetti/Rossi/Offerta"] = [mine]
        controller.trayProposals["01 Progetti/Acme/Altra"] = [Self.proposal(conversationID: 2)]
        controller.selection = "01 Progetti/Rossi/Offerta"

        #expect(controller.selectedTray == [mine])
    }
}
