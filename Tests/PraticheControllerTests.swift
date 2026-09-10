import Foundation
import Testing
@testable import Pergamenum

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 5 -
// R-17, R-18.
//
// Every declaration under test here (`PraticaWatcher`, `FullDiskAccessProbe`,
// `PraticheController`) is a tester-declared boundary (ADR-0155): the coder fills the
// bodies. `PraticaWatcher`'s decision methods are stubbed to wrong-but-safe constants
// (`true`/`false`/no-op) and `FullDiskAccessProbe.state(probing:)` is stubbed to
// always report `.granted` - both keep every test below red without ever crashing
// the process the way a `fatalError` stub would. No test here touches
// `~/Library/Mail`; `stateReadsEPERMAsNotGranted` and the `PraticheController` tests
// build their own throwaway, unreadable file instead.

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
