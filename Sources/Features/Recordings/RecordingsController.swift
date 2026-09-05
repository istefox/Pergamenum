import Foundation
import Observation

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 6 -
// R-01, R-02, R-03, R-06, R-07, R-09, R-12, R-13; ADR §D4, §D9, §D12, §D13.
//
// The logic of the Registrazioni pane: list, health, process/poll, two-phase import,
// delete. `DayController(store:vault:)` (`Sources/Features/Today/DayController.swift`) is
// the shape this follows - separated from the view so a suite with no window can drive it
// against `FakePlaudService` (`Tests/FakePlaudService.swift`), never a real socket.
//
// Tester-declared signature only (this dispatch's brief, task 6: "Tester first... Red
// first."). Every method body below is an intentional no-op placeholder; the coder
// implements the real behaviour each doc comment names. `Tests/RecordingsControllerTests.swift`
// is written against the behaviour these comments describe and is red until it exists.
@MainActor
@Observable
final class RecordingsController {
    /// Whether the service is reachable, per the last `checkHealth()` (R-02). `.unknown`
    /// before the first check; `.unavailable` carries the readable message a banner shows
    /// verbatim, including while `isIsolated`.
    enum HealthStatus: Equatable, Sendable {
        case unknown
        case available
        case unavailable(message: String)
    }

    /// The current vault's recordings, wire state as last fetched by `refresh()`.
    private(set) var recordings: [PlaudRecording] = []
    /// The local ledger (`plaud.json`, ADR §D12), keyed by recording id - reloaded whenever
    /// `vault.session` changes identity (R-12), never merged across vaults.
    private(set) var entries: [String: PlaudVaultStore.Entry] = [:]
    private(set) var health: HealthStatus = .unknown
    /// Recording ids whose two-phase import (ADR §D13) wrote the note but whose
    /// `confirmImported` call has not yet succeeded, with the readable message from the
    /// failed attempt (R-13). Cleared on a successful `retryConfirmation`.
    private(set) var confirmationFailures: [String: String] = [:]
    /// Recording ids a poll `Task` is currently sleeping/asking `job(id:)` for (ADR §D4).
    private(set) var pollingRecordingIDs: Set<String> = []
    /// Recording ids whose poll hit the 30-minute bound and stopped itself (ADR §D4); the
    /// row is expected to say so and offer «Aggiorna» instead of resuming automatically.
    private(set) var pollExpired: Set<String> = []
    /// The last error surfaced at pane scope (health checks, list refresh) rather than on
    /// one row - never a raw `Error` interpolation (R-13).
    private(set) var bannerMessage: String?
    /// A per-recording readable error (R-13, R-07's general case): a failed `process()`
    /// call, or a job that ended with `error` non-nil, mapped through
    /// `PlaudError.readableLastError`/`.message` - never a raw `Error` interpolation.
    /// Distinct from `confirmationFailures`, which is specifically the two-phase import's
    /// own owed-confirmation state.
    private(set) var rowErrors: [String: String] = [:]

    /// Not private, following `DayController.vault`'s own reasoning: Impostazioni' Giorni
    /// field (Task 8) writes through this controller, not through `vault.updateSettings`
    /// (ADR §D12), and needs to reach it from outside this file.
    let vault: VaultController

    private let service: any PlaudService
    /// Injected so a test can shorten both without a real 3-second/30-minute wait (ADR §D4
    /// names the production values; the brief asks tests not to sleep for real).
    private let pollInterval: Duration
    private let pollTimeout: Duration

    /// `defaults.bool(forKey: "disablePlaud")` **or** `isTestHost` - the exact shape
    /// `SparkleUpdateController.isIsolated` settled on (`Sources/App/SparkleUpdateController.swift`,
    /// its own header explains why): `-disablePlaud YES` (ADR §D3) is one input,
    /// `.claude/test-cmd` hosting the unit suite inside the real app with no launch
    /// arguments at all is the other, and either alone is enough. When true, every method
    /// below returns without making a request of any kind, and `health` reports
    /// unavailable.
    ///
    /// No access modifier (not `private`), for the same reason as the precedent above: a
    /// `private` member is invisible to `Tests/RecordingsControllerTests.swift` even
    /// through `@testable import`, since `private` is file-scoped in Swift.
    let isIsolated: Bool

    init(
        service: any PlaudService,
        vault: VaultController,
        defaults: UserDefaults = .standard,
        isTestHost: Bool = VaultState.isRunningUnderTest,
        pollInterval: Duration = .seconds(3),
        pollTimeout: Duration = .seconds(60 * 30)
    ) {
        self.service = service
        self.vault = vault
        self.isIsolated = defaults.bool(forKey: "disablePlaud") || isTestHost
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    // MARK: - Loading

    /// Reloads the local ledger when `vault.session` has changed identity (R-12) and fetches
    /// `GET /recordings?days=N` for the days window the ledger holds (ADR §D12).
    ///
    /// A no-op under `isIsolated`, per this file's header - a test asserts the fake receives
    /// zero calls.
    func refresh() async {}

    /// `GET /health` (R-02). Never called by anything else in this file automatically - no
    /// timer, no launch check (ADR §D4/§D14).
    func checkHealth() async {}

    // MARK: - Processing / polling

    /// `POST /recordings/{id}/process`, then polls `GET /jobs/{id}` on one stored `Task`
    /// every `pollInterval`, until the job carries a `proposalId` or an `error` (ADR §D4) -
    /// cancelled on that job end, when `vault.session` changes identity, and by `stop()`.
    /// Bounded at `pollTimeout`; past it, the poll cancels itself and the recording's id
    /// joins `pollExpired`. A thrown `PlaudError` from either the initial `process` call or
    /// a polled job's `error` string is mapped to `rowErrors[recordingID]` (R-07, R-13) -
    /// never a crash, never a raw `Error` interpolation.
    func process(_ recordingID: String, force: Bool = false) async {}

    /// Cancels every in-flight poll. Called by the scene when the pane's owner goes away
    /// (ADR §D4) - never by anything inside this file automatically.
    func stop() {}

    // MARK: - Two-phase import (ADR §D13)

    /// Phase 1: renders the note through `TranscriptNote.render` and writes it via
    /// `vault.session?.write(_:to:)`, recording the new fingerprints and
    /// `pendingConfirmation` in the ledger. Phase 2: `POST /proposals/{id}/imported` with
    /// exactly `acceptedTaskIDs` (R-06 - the rejected ids are never sent). If phase 2
    /// throws, the note stays written, `confirmationFailures[recordingID]` is set to the
    /// readable message (R-13), and `pendingConfirmation` stays owed for `retryConfirmation`
    /// to retry - the note is never re-written and no fingerprint is ever added twice.
    func importAccepted(
        recordingID: String,
        proposal: PlaudProposal,
        acceptedTaskIDs: Set<String>,
        speakerRenames: [String: String]
    ) async {}

    /// Re-issues only phase 2 of `importAccepted` for the ids already recorded as
    /// `pendingConfirmation` - no note write, no proposal re-fetch, one `confirmImported`
    /// call.
    func retryConfirmation(recordingID: String) async {}

    // MARK: - Delete (R-09)

    /// Confirmation is the caller's job. Calls `vault.trashNote(at:)`
    /// (`VaultController+Files.swift:70`) and marks the ledger entry deleted - no service
    /// method is called at all, per the contract having no delete endpoint (ADR §D9's
    /// "asking the service" rejection).
    func delete(recordingID: String) {}
}
