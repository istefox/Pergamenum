import Foundation
import Testing
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 6 -
// R-01, R-02, R-03, R-06, R-07, R-09, R-12, R-13; ADR §D4, §D9, §D12, §D13.
//
// `RecordingsController`'s production body is a tester-declared stub (every method is an
// intentional no-op, see `Sources/Features/Recordings/RecordingsController.swift`), so most
// assertions below are red until the coder implements the real behaviour each doc comment
// there names. Every test drives `FakePlaudService` (`Tests/FakePlaudService.swift`) - no
// test touches the network.
//
// `isTestHost: false` is passed explicitly everywhere a test wants the fake to actually
// receive calls, following `Sources/App/SparkleUpdateController.swift`'s own precedent
// (`Tests/SparkleUpdateControllerTests.swift`): `.claude/test-cmd` hosts this very suite
// inside the real app with no `-disablePlaud` argument to pass, so the default
// `isTestHost: VaultState.isRunningUnderTest` reads `true` here and would isolate every
// test that omitted the override.

@MainActor
private func openVaultController(_ root: URL) async -> VaultController {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(root)
    return controller
}

/// A throwaway `UserDefaults` suite per test, never `.standard` - a shared domain would
/// make one test's `disablePlaud` value leak into another's, and `.claude/test-cmd` gives
/// no guarantee about test ordering.
private func isolatedDefaults(disablePlaud: Bool = false) -> UserDefaults {
    let suiteName = "RecordingsControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.set(disablePlaud, forKey: "disablePlaud")
    return defaults
}

private func sampleRecording(
    id: String, name: String = "Registrazione", state: PlaudRecordingState = .new
) -> PlaudRecording {
    PlaudRecording(
        id: id, name: name, recordedAt: "2026-09-04T11:00:00", durationMs: 60_000,
        deviceSerial: "device-1", state: state, lastError: nil
    )
}

private func sampleProposal(recordingID: String, themes: [PlaudTheme]) -> PlaudProposal {
    PlaudProposal(
        recording: PlaudProposalRecording(
            id: recordingID, name: "Riunione", recordedAt: "2026-09-04T11:48:07", durationMs: 60_000
        ),
        recordingKind: .meeting,
        themes: themes,
        transcript: PlaudTranscript(language: "it", text: "Speaker 1: prova.", speakers: ["Speaker 1"]),
        warnings: [],
        generatedAt: "2026-09-05T07:55:24.906Z"
    )
}

// MARK: - Isolation

@MainActor
@Test func everyMethodIsANoOpWhenIsolatedAndMakesNoRequest() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(disablePlaud: true), isTestHost: false
    )
    #expect(sut.isIsolated == true)

    let proposal = sampleProposal(recordingID: "rec-1", themes: [])
    await sut.refresh()
    await sut.checkHealth()
    await sut.process("rec-1")
    await sut.importAccepted(recordingID: "rec-1", proposal: proposal, acceptedTaskIDs: [], speakerRenames: [:])
    await sut.retryConfirmation(recordingID: "rec-1")
    await sut.delete(recordingID: "rec-1")

    #expect(await fake.totalCallCount == 0)
    if case .unavailable = sut.health {
        // acceptable: isolated reports unavailable without ever asking the fake
    } else {
        Issue.record("expected .unavailable while isolated, got \(sut.health)")
    }

    controllerVault.close()
}

// MARK: - Vault scoping (R-12)

@MainActor
@Test func switchingVaultsShowsOnlyTheSecondVaultsOwnEntries() async throws {
    let controllerVault = VaultController(recents: .volatile(), openTabs: .volatile())
    let fake = FakePlaudService()
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    let vaultA = try TemporaryVault()
    await controllerVault.open(vaultA.root)
    await fake.setRecordingsResult(.success([sampleRecording(id: "rec-a")]))
    await sut.refresh()
    #expect(sut.recordings.map(\.id) == ["rec-a"])

    let vaultB = try TemporaryVault()
    await controllerVault.open(vaultB.root)
    await fake.setRecordingsResult(.success([sampleRecording(id: "rec-b")]))
    await sut.refresh()

    #expect(sut.recordings.map(\.id) == ["rec-b"])
    #expect(sut.entries["rec-a"] == nil)

    controllerVault.close()
}

// MARK: - Two-phase import (ADR §D13)

/// An unparseable `recorded_at` used to fall through silently to today's date in both the
/// note's file name and its frontmatter (RTF review finding, 2026-09-06) - filing a
/// malformed recording under the wrong date instead of surfacing it. The import must be
/// rejected before either fallback is reached: no note write, no confirmation.
@MainActor
@Test func rejectsTheImportWhenRecordedAtCannotBeParsed() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    let proposal = PlaudProposal(
        recording: PlaudProposalRecording(
            id: "rec-1", name: "Riunione", recordedAt: "not-a-timestamp", durationMs: 60_000
        ),
        recordingKind: .meeting,
        themes: [],
        transcript: PlaudTranscript(language: "it", text: "Speaker 1: prova.", speakers: ["Speaker 1"]),
        warnings: [],
        generatedAt: "2026-09-05T07:55:24.906Z"
    )

    await sut.importAccepted(recordingID: "rec-1", proposal: proposal, acceptedTaskIDs: [], speakerRenames: [:])

    #expect(sut.rowErrors["rec-1"] != nil)
    #expect(sut.entries["rec-1"]?.notePath == nil)
    #expect(await fake.confirmImportedCalls.isEmpty)

    controllerVault.close()
}

@MainActor
@Test func aFailedConfirmationLeavesTheNoteWrittenAndRetryReissuesOnlyThePost() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setConfirmImportedResult(.failure(.serviceDisconnected))
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    let proposal = sampleProposal(recordingID: "rec-1", themes: [
        PlaudTheme(name: "Azioni", tasks: [
            PlaudTask(id: "t1", title: "Fare qualcosa", quote: "una prova", urgency: 3, importance: 3, dueHint: nil),
        ]),
    ])

    await sut.importAccepted(recordingID: "rec-1", proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:])

    #expect(await fake.confirmImportedCalls.count == 1)
    #expect(sut.confirmationFailures["rec-1"] != nil)

    let notePath = try #require(sut.entries["rec-1"]?.notePath)
    let noteURL = vault.root.appending(path: notePath, directoryHint: .notDirectory)
    let firstBytes = try String(contentsOf: noteURL, encoding: .utf8)
    #expect(!firstBytes.isEmpty)

    await sut.retryConfirmation(recordingID: "rec-1")

    #expect(await fake.confirmImportedCalls.count == 2)
    // Only the POST was reissued: no second note write, no proposal re-fetch, no
    // second process/job call.
    #expect(await fake.proposalCalls.isEmpty)
    #expect(await fake.processCalls.isEmpty)
    #expect(await fake.jobCalls.isEmpty)

    let secondBytes = try String(contentsOf: noteURL, encoding: .utf8)
    #expect(secondBytes == firstBytes)

    controllerVault.close()
}

/// ADR §D13's two-phase import rests on the ledger write reaching disk before the
/// confirmation is sent - a directory that refuses the write (`0o555`, no execute-only
/// trick needed: the parent already exists, so only the write bit inside it matters)
/// reproduces that failure without touching `PlaudVaultStore` from the test.
@MainActor
@Test func aFailedLedgerWriteNeverSendsTheConfirmation() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    let stateDirectory = try #require(controllerVault.session?.state.directory)
    try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o555], ofItemAtPath: stateDirectory.path(percentEncoded: false)
    )
    defer {
        // Restored before `TemporaryVault.deinit` tries to remove the tree.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stateDirectory.path(percentEncoded: false)
        )
    }

    let proposal = sampleProposal(recordingID: "rec-1", themes: [
        PlaudTheme(name: "Azioni", tasks: [
            PlaudTask(id: "t1", title: "Fare qualcosa", quote: "una prova", urgency: 3, importance: 3, dueHint: nil),
        ]),
    ])

    await sut.importAccepted(recordingID: "rec-1", proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:])

    #expect(await fake.confirmImportedCalls.isEmpty)
    #expect(sut.rowErrors["rec-1"] != nil)

    controllerVault.close()
}

@MainActor
@Test func confirmsExactlyTheAcceptedTaskIdsAndNoOthers() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    let proposal = sampleProposal(recordingID: "rec-1", themes: [
        PlaudTheme(name: "Azioni", tasks: [
            PlaudTask(id: "t1", title: "Accettato", quote: "quote 1", urgency: 3, importance: 3, dueHint: nil),
            PlaudTask(id: "t2", title: "Rifiutato", quote: "quote 2", urgency: 3, importance: 3, dueHint: nil),
        ]),
    ])

    await sut.importAccepted(recordingID: "rec-1", proposal: proposal, acceptedTaskIDs: ["t1"], speakerRenames: [:])

    let calls = await fake.confirmImportedCalls
    let call = try #require(calls.first)
    #expect(call.taskIDs.contains("t1"))
    #expect(!call.taskIDs.contains("t2"))

    controllerVault.close()
}

// MARK: - Delete (R-09)

@MainActor
@Test func deletingARecordingTrashesTheNoteMarksTheLedgerAndCallsNoServiceMethod() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    guard let session = controllerVault.session else {
        Issue.record("expected a session after open(_:)")
        return
    }
    let fake = FakePlaudService()
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    let notePath = "Registrazioni/Nota importata.md"
    try vault.write(
        "---\ndate: 2026-09-04\ntags:\n  - type-note\n  - topic-trascrizione\n---\n\ncorpo\n",
        to: notePath
    )
    await session.rescan()

    // Seeds the same ledger `refresh()` is documented to load (ADR §D12), directly
    // through `PlaudVaultStore` rather than a network round-trip - `delete(recordingID:)`
    // has to know which note a recording id maps to from *somewhere*, and the ledger,
    // keyed under the session's own state directory, is that somewhere.
    let store = PlaudVaultStore(directory: session.state.directory)
    var ledger = store.loadLedger()
    ledger.recordings["rec-1"] = PlaudVaultStore.Entry(status: "imported", notePath: notePath)
    try store.saveLedger(ledger)
    await sut.refresh()
    // Captured after `refresh()`, not asserted as zero outright: `refresh()` itself
    // legitimately calls `GET /recordings` (ADR §D12) - what R-09/ADR §D9 promise is
    // that `delete` on its own adds no call on top of that.
    let callCountBeforeDelete = await fake.totalCallCount

    await sut.delete(recordingID: "rec-1")

    let stillExists = FileManager.default.fileExists(
        atPath: vault.root.appending(path: notePath, directoryHint: .notDirectory).path(percentEncoded: false)
    )
    #expect(!stillExists, "delete(recordingID:) must call vault.trashNote(at:) for the ledger's own notePath")
    #expect(sut.entries["rec-1"]?.status == "deleted")
    #expect(
        await fake.totalCallCount == callCountBeforeDelete,
        "the contract has no delete endpoint (ADR §D9) - delete itself must call no service method"
    )

    controllerVault.close()
}

// MARK: - Polling (ADR §D4)

@MainActor
@Test func pollingStopsAsSoonAsTheJobProducesAProposal() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setProcessResult(.success(PlaudJobHandle(jobId: "job-1", state: "queued")))
    await fake.setJobResult(.success(PlaudJob(state: "processing", step: nil, error: nil, proposalId: nil)))

    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false,
        pollInterval: .milliseconds(5), pollTimeout: .seconds(30)
    )

    await sut.process("rec-1")
    try await Task.sleep(for: .milliseconds(30))
    #expect(sut.pollingRecordingIDs.contains("rec-1"))

    await fake.setJobResult(.success(PlaudJob(state: "ready", step: nil, error: nil, proposalId: "prop-1")))
    try await Task.sleep(for: .milliseconds(60))

    #expect(!sut.pollingRecordingIDs.contains("rec-1"))
    #expect(!sut.pollExpired.contains("rec-1"))

    controllerVault.close()
}

@MainActor
@Test func pollingStopsAndMarksExpiredAfterTheInjectedTimeout() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setProcessResult(.success(PlaudJobHandle(jobId: "job-1", state: "queued")))
    await fake.setJobResult(.success(PlaudJob(state: "processing", step: "trascrizione", error: nil, proposalId: nil)))

    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false,
        pollInterval: .milliseconds(5), pollTimeout: .milliseconds(25)
    )

    await sut.process("rec-1")
    try await Task.sleep(for: .milliseconds(150))

    #expect(sut.pollExpired.contains("rec-1"))
    #expect(!sut.pollingRecordingIDs.contains("rec-1"))
    #expect(await fake.jobCalls.count > 1)

    controllerVault.close()
}

@MainActor
@Test func stopCancelsEveryInFlightPoll() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setProcessResult(.success(PlaudJobHandle(jobId: "job-1", state: "queued")))
    await fake.setJobResult(.success(PlaudJob(state: "processing", step: nil, error: nil, proposalId: nil)))

    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false,
        pollInterval: .milliseconds(5), pollTimeout: .seconds(30)
    )

    await sut.process("rec-1")
    try await Task.sleep(for: .milliseconds(30))
    #expect(sut.pollingRecordingIDs.contains("rec-1"))

    sut.stop()
    try await Task.sleep(for: .milliseconds(30))
    #expect(sut.pollingRecordingIDs.isEmpty)

    controllerVault.close()
}

@MainActor
@Test func finishingAPollRefreshesTheRecordingsListAutomatically() async throws {
    // Task 10's live HITL walkthrough of ADR-0032 (bug-fix follow-up to Tasks 7/8, not a new
    // task number): `finishPolling(_:expired:)` never triggers a re-fetch of `/recordings`
    // when a poll ends, so even the final state does not appear on its own - only a manual
    // refresh (Cmd+R / reopening the pane) shows it. This asserts `sut.recordings` reflects
    // the fake's *current* answer once the poll ends, with no explicit `sut.refresh()` call
    // from the test after `process()` starts it.
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setRecordingsResult(.success([sampleRecording(id: "rec-1", state: .new)]))
    await fake.setProcessResult(.success(PlaudJobHandle(jobId: "job-1", state: "queued")))
    await fake.setJobResult(.success(PlaudJob(state: "processing", step: nil, error: nil, proposalId: nil)))

    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false,
        pollInterval: .milliseconds(5), pollTimeout: .seconds(30)
    )

    await sut.refresh()
    #expect(sut.recordings.map(\.state) == [.new])

    await sut.process("rec-1")
    try await Task.sleep(for: .milliseconds(20))
    #expect(sut.pollingRecordingIDs.contains("rec-1"))

    // What a real re-fetch of `/recordings` would report once the job has produced a
    // proposal - set on the fake before the poll's next tick sees `proposalId` non-nil and
    // ends it, never through a `sut.refresh()` call from this test.
    await fake.setRecordingsResult(.success([sampleRecording(id: "rec-1", state: .imported)]))
    await fake.setJobResult(.success(PlaudJob(state: "ready", step: nil, error: nil, proposalId: "prop-1")))
    try await Task.sleep(for: .milliseconds(60))

    #expect(!sut.pollingRecordingIDs.contains("rec-1"))
    #expect(
        sut.recordings.map(\.state) == [.imported],
        "finishPolling(_:expired:) must re-fetch the recordings list automatically when a poll ends"
    )

    controllerVault.close()
}

// MARK: - Readable errors (R-07, R-13)

@MainActor
@Test func aFailedHealthCheckSurfacesAReadableBannerMessageNeverARawError() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setHealthResult(.failure(.serviceDisconnected))
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    await sut.checkHealth()

    guard case let .unavailable(message) = sut.health else {
        Issue.record("expected .unavailable, got \(sut.health)")
        return
    }
    #expect(message == PlaudError.serviceDisconnected.message)
    #expect(!message.contains("PlaudError"))
    #expect(!message.contains("serviceDisconnected"))

    controllerVault.close()
}

/// Cmd+R and the toolbar button must mean the same thing (RTF review finding, 2026-09-06):
/// before this, Cmd+R called only `refresh()`, so a service that had recovered since a prior
/// failed health check still showed the health banner in place of the freshly-fetched rows.
@MainActor
@Test func refreshAndCheckHealthClearsAStaleUnavailableBannerOnceTheServiceAnswersAgain() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setHealthResult(.failure(.serviceDisconnected))
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    await sut.checkHealth()
    guard case .unavailable = sut.health else {
        Issue.record("expected .unavailable after the failed health check, got \(sut.health)")
        return
    }

    await fake.setHealthResult(.success(PlaudHealth(status: "ok", plaud: "connected", version: "0.2.0")))
    await fake.setRecordingsResult(.success([sampleRecording(id: "rec-1")]))
    await sut.refreshAndCheckHealth()

    #expect(sut.health == .available)
    #expect(sut.recordings.map(\.id) == ["rec-1"])

    controllerVault.close()
}

@MainActor
@Test func aFailedProcessCallSurfacesOnTheRowRatherThanCrashing() async throws {
    let vault = try TemporaryVault()
    let controllerVault = await openVaultController(vault.root)
    let fake = FakePlaudService()
    await fake.setProcessResult(.failure(.unknownRecording))
    let sut = RecordingsController(
        service: fake, vault: controllerVault, defaults: isolatedDefaults(), isTestHost: false
    )

    // No crash: reaching the assertions below already proves it.
    await sut.process("rec-1")

    #expect(sut.rowErrors["rec-1"] == PlaudError.unknownRecording.message)
    #expect(sut.pollingRecordingIDs.isEmpty, "a process call that itself failed must not start a poll")

    controllerVault.close()
}
