import Foundation
@testable import Pergamenum

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 2.
//
// A `PlaudService` whose every response is set per test, including thrown errors - the
// `StubCalendarStore` shape (`Tests/DayTestSupport.swift`) for a network dependency instead
// of EventKit: a socket cannot run in a test process either, for a different reason (there
// may be no service loaded, or a real one that would be told to do real work).
//
// An `actor`, not a `@MainActor` class: `PlaudService: Sendable` (ADR §D2), and this repo's
// only other actor, `ThumbnailStore` (`Sources/Vault/ThumbnailStore.swift`), is the
// precedent for a `Sendable`-conforming type carrying mutable state safely across `async`
// calls, rather than reaching for `@unchecked Sendable` on a plain class.
//
// Every stored result is `Result<Value, PlaudError>`, never `Result<Value, Error>`: an
// actor's stored properties must themselves be `Sendable`, and the bare `Error` existential
// is not - only `PlaudError` (declared `Sendable`, Task 1) is ever actually thrown by this
// app's own mapping, so this loses no real test case.
actor FakePlaudService: PlaudService {
    var healthResult: Result<PlaudHealth, PlaudError> = .success(
        PlaudHealth(status: "ok", plaud: "connected", version: "0.2.0")
    )
    var recordingsResult: Result<[PlaudRecording], PlaudError> = .success([])
    var processResult: Result<PlaudJobHandle, PlaudError> = .success(
        PlaudJobHandle(jobId: "job-1", state: "queued")
    )
    var jobResult: Result<PlaudJob, PlaudError> = .success(
        PlaudJob(state: "queued", step: nil, error: nil, proposalId: nil)
    )
    /// `nil` throws `.proposalNotFound` - a test that never calls `setProposalResult` gets
    /// the same 404 shape the real service gives for a recording with no proposal yet.
    var proposalResult: Result<PlaudProposal, PlaudError>?
    var confirmImportedResult: Result<Void, PlaudError> = .success(())

    private(set) var healthCallCount = 0
    private(set) var recordingsCallCount = 0
    private(set) var processCalls: [(id: String, force: Bool)] = []
    private(set) var jobCalls: [String] = []
    private(set) var proposalCalls: [String] = []
    private(set) var confirmImportedCalls: [(recordingID: String, taskIDs: [String])] = []

    /// The total number of requests this fake has answered, of any kind - what an
    /// `isIsolated` test (Task 6, `RecordingsController`) asserts is zero.
    var totalCallCount: Int {
        healthCallCount + recordingsCallCount + processCalls.count + jobCalls.count
            + proposalCalls.count + confirmImportedCalls.count
    }

    func setHealthResult(_ result: Result<PlaudHealth, PlaudError>) {
        healthResult = result
    }

    func setRecordingsResult(_ result: Result<[PlaudRecording], PlaudError>) {
        recordingsResult = result
    }

    func setProcessResult(_ result: Result<PlaudJobHandle, PlaudError>) {
        processResult = result
    }

    func setJobResult(_ result: Result<PlaudJob, PlaudError>) {
        jobResult = result
    }

    func setProposalResult(_ result: Result<PlaudProposal, PlaudError>?) {
        proposalResult = result
    }

    func setConfirmImportedResult(_ result: Result<Void, PlaudError>) {
        confirmImportedResult = result
    }

    func health() async throws -> PlaudHealth {
        healthCallCount += 1
        return try healthResult.get()
    }

    func recordings(days: Int) async throws -> [PlaudRecording] {
        recordingsCallCount += 1
        return try recordingsResult.get()
    }

    func process(id: String, force: Bool) async throws -> PlaudJobHandle {
        processCalls.append((id, force))
        return try processResult.get()
    }

    func job(id: String) async throws -> PlaudJob {
        jobCalls.append(id)
        return try jobResult.get()
    }

    func proposal(recordingID: String) async throws -> PlaudProposal {
        proposalCalls.append(recordingID)
        guard let proposalResult else {
            throw PlaudError.proposalNotFound
        }
        return try proposalResult.get()
    }

    func confirmImported(recordingID: String, taskIDs: [String]) async throws {
        confirmImportedCalls.append((recordingID, taskIDs))
        try confirmImportedResult.get()
    }
}
