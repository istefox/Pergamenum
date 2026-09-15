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
// Two things are true of every method here and stated once rather than repeated: none of
// them makes a request while `isIsolated`, and none of them lets a thrown error reach a
// person as `"\(error)"` (R-13) - the failure lands on `bannerMessage` when it is about the
// service and on `rowErrors`/`confirmationFailures` when it is about one recording.
// `Tests/RecordingsControllerTests.swift` drives all of it through `FakePlaudService`.
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

    /// ADR-0045 §D3 (PG-143 structure refactor): `recordings`, `entries`, `health`,
    /// `confirmationFailures`, `pollExpired`, `bannerMessage` and `rowErrors` below drop
    /// `private(set)` for a plain `var` - `RecordingsController+Ledger.swift`'s
    /// `reloadLedger`/`record`/`isolate` write every one of them from a separate file,
    /// `RecordingsController+Interface.swift` adds a second writer for `bannerMessage`
    /// (`updateDays`) and `rowErrors` (`loadProposal`, `saveDraft`), and
    /// `RecordingsController+Import.swift` adds a third for `rowErrors` (`importAccepted`)
    /// and `confirmationFailures` (`confirm`). `pollingRecordingIDs` and `pollSteps` keep
    /// `private(set)`: every write to either stays in this file.
    ///
    /// The current vault's recordings, wire state as last fetched by `refresh()`.
    var recordings: [PlaudRecording] = []
    /// The local ledger (`plaud.json`, ADR §D12), keyed by recording id - reloaded whenever
    /// `vault.session` changes identity (R-12), never merged across vaults.
    var entries: [String: PlaudVaultStore.Entry] = [:]
    var health: HealthStatus = .unknown
    /// Recording ids whose two-phase import (ADR §D13) wrote the note but whose
    /// `confirmImported` call has not yet succeeded, with the readable message from the
    /// failed attempt (R-13). Cleared on a successful `retryConfirmation`.
    var confirmationFailures: [String: String] = [:]
    /// Recording ids a poll `Task` is currently sleeping/asking `job(id:)` for (ADR §D4).
    private(set) var pollingRecordingIDs: Set<String> = []
    /// Recording ids whose poll hit the 30-minute bound and stopped itself (ADR §D4); the
    /// row is expected to say so and offer «Aggiorna» instead of resuming automatically.
    var pollExpired: Set<String> = []
    /// The step the last polled job reported (`transcript`/`extract`/`cleanup`), by
    /// recording id - what a `processing` row shows beside its progress indicator. The
    /// service's own word, never a translation: it is a stage name, not a sentence, and a
    /// paraphrase here would be one this app invented.
    private(set) var pollSteps: [String: String] = [:]
    /// The last error surfaced at pane scope (health checks, list refresh) rather than on
    /// one row - never a raw `Error` interpolation (R-13).
    var bannerMessage: String?
    /// A per-recording readable error (R-13, R-07's general case): a failed `process()`
    /// call, or a job that ended with `error` non-nil, mapped through
    /// `PlaudError.readableLastError`/`.message` - never a raw `Error` interpolation.
    /// Distinct from `confirmationFailures`, which is specifically the two-phase import's
    /// own owed-confirmation state.
    var rowErrors: [String: String] = [:]

    /// Not private, following `DayController.vault`'s own reasoning: Impostazioni' Giorni
    /// field (Task 8) writes through this controller, not through `vault.updateSettings`
    /// (ADR §D12), and needs to reach it from outside this file.
    let vault: VaultController

    /// Not `private`: `RecordingsController+Interface.swift`'s `loadProposal` and
    /// `RecordingsController+Import.swift`'s `confirm` are this controller's extensions in
    /// separate files, and both call it directly (ADR-0045 §D3).
    let service: any PlaudService
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

    /// ADR-0045 §D3 (PG-143 structure refactor): `store` and `ledger` below widen from
    /// `private` to a plain `var` - `RecordingsController+Ledger.swift` (`reloadLedger`,
    /// `record`, `notePath`), `RecordingsController+Interface.swift` (`draft`, `saveDraft`,
    /// `clearDraft`, `updateDays`, `ensureStore`) and `RecordingsController+Import.swift`
    /// (`importAccepted`, `confirm`) all read and write them from their own file.
    /// `storeIdentity` widens the same way, for `RecordingsController+Ledger.swift`'s
    /// `reloadLedger` alone. `pollTasks`, right after, keeps its `private`: nothing outside
    /// this file ever touches it.
    ///
    /// The local files this vault's ledger and drafts live in (ADR §D12), `nil` until a
    /// vault is open. Rebuilt, never merged, when `vault.session` changes identity (R-12).
    var store: PlaudVaultStore?
    /// Which session `store` was built for, as its own state directory - the identity
    /// ADR-0017 gives a vault, rather than the root path a rename would change.
    var storeIdentity: String?
    var ledger: PlaudVaultStore.Ledger = .empty
    private var pollTasks: [String: Task<Void, Never>] = [:]

    /// Shown verbatim by the pane's banner while `-disablePlaud YES` (or a test host) is in
    /// force: the person is told the app is not asking, not that the service is down.
    static let isolatedMessage = "Importazione Plaud disattivata per questa sessione: nessuna richiesta al servizio."

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
        if self.isIsolated { health = .unavailable(message: Self.isolatedMessage) }
    }

    // MARK: - Loading

    /// The one sequence «Aggiorna registrazioni» ever means, whether it comes from the
    /// toolbar button or the Cmd+R shortcut: `checkHealth()` first, so a service that has come
    /// back since a previous failure clears the health banner, then `refresh()`. Two separate
    /// call sites each doing only `refresh()` is exactly how the banner used to stay up after
    /// a successful refresh proved the service reachable (RTF review finding, 2026-09-06).
    func refreshAndCheckHealth() async {
        await checkHealth()
        await refresh()
    }

    /// Reloads the local ledger when `vault.session` has changed identity (R-12) and fetches
    /// `GET /recordings?days=N` for the days window the ledger holds (ADR §D12).
    ///
    /// A no-op under `isIsolated`, per this file's header - a test asserts the fake receives
    /// zero calls.
    func refresh() async {
        guard !isIsolated else { return isolate() }
        reloadLedger()
        guard store != nil else {
            bannerMessage = Self.noVaultMessage
            return
        }
        do {
            recordings = try await service.recordings(days: ledger.days)
            bannerMessage = nil
        } catch {
            bannerMessage = readableMessage(error)
        }
    }

    /// `GET /health` (R-02). Never called by anything else in this file automatically - no
    /// timer, no launch check (ADR §D4/§D14).
    func checkHealth() async {
        guard !isIsolated else { return isolate() }
        do {
            let reported = try await service.health()
            health = .available
            // Reachable but with no recorder attached is a different sentence from
            // unreachable, and it belongs on the banner rather than on the health state:
            // the list still loads, it is simply empty of anything new.
            bannerMessage = reported.plaud == "connected" ? nil : PlaudError.serviceDisconnected.message
        } catch {
            let message = readableMessage(error)
            health = .unavailable(message: message)
            bannerMessage = message
        }
    }

    // MARK: - Processing / polling

    /// `POST /recordings/{id}/process`, then polls `GET /jobs/{id}` on one stored `Task`
    /// every `pollInterval`, until the job carries a `proposalId` or an `error` (ADR §D4) -
    /// cancelled on that job end, when `vault.session` changes identity, and by `stop()`.
    /// Bounded at `pollTimeout`; past it, the poll cancels itself and the recording's id
    /// joins `pollExpired`. A thrown `PlaudError` from either the initial `process` call or
    /// a polled job's `error` string is mapped to `rowErrors[recordingID]` (R-07, R-13) -
    /// never a crash, never a raw `Error` interpolation.
    func process(_ recordingID: String, force: Bool = false) async {
        guard !isIsolated else { return isolate() }
        rowErrors[recordingID] = nil
        pollExpired.remove(recordingID)
        do {
            let handle = try await service.process(id: recordingID, force: force)
            startPolling(recordingID: recordingID, jobID: handle.jobId)
        } catch {
            // The request itself failed: there is no job to watch, so no poll starts.
            rowErrors[recordingID] = readableMessage(error)
        }
    }

    /// Cancels every in-flight poll. Called by the scene when the pane's owner goes away
    /// (ADR §D4) - never by anything inside this file automatically.
    func stop() {
        for task in pollTasks.values { task.cancel() }
        pollTasks.removeAll()
        pollingRecordingIDs.removeAll()
        pollSteps.removeAll()
    }

    /// One structured `Task` per recording, sleeping rather than firing a `Timer` (ADR §D4):
    /// a cancelled sleep ends the poll immediately, which a repeating timer cannot do.
    private func startPolling(recordingID: String, jobID: String) {
        pollTasks[recordingID]?.cancel()
        pollingRecordingIDs.insert(recordingID)

        let interval = pollInterval
        // Computed once, here: a deadline recomputed inside the loop would move with every
        // iteration and the 30-minute bound would never arrive.
        let deadline = ContinuousClock.now.advanced(by: pollTimeout)
        pollTasks[recordingID] = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return // cancelled while sleeping: `stop()` has already cleared the state
                }
                guard let self, !Task.isCancelled else { return }
                guard ContinuousClock.now < deadline else {
                    // Past the bound a silent repeating request stops being something the
                    // person asked for: the row says so and offers «Aggiorna» instead.
                    await finishPolling(recordingID, expired: true)
                    return
                }
                guard await askJob(id: jobID, for: recordingID) else { return }
            }
        }
    }

    /// One `GET /jobs/{id}`. `true` while the job is still running, `false` once it has
    /// ended - with a proposal, with an error, or with a state that says it failed.
    private func askJob(id jobID: String, for recordingID: String) async -> Bool {
        do {
            let job = try await service.job(id: jobID)
            if let step = job.step, !step.isEmpty { pollSteps[recordingID] = step }
            if let failure = job.error, !failure.isEmpty {
                rowErrors[recordingID] = PlaudError.readableLastError(failure)
                await finishPolling(recordingID, expired: false)
                return false
            }
            if job.proposalId != nil {
                await finishPolling(recordingID, expired: false)
                return false
            }
            if job.state == "failed" {
                // A failed job that carried no `error` at all would otherwise be polled
                // until the 30-minute bound for a result that is never coming.
                rowErrors[recordingID] = PlaudError.readableLastError(
                    job.error ?? "il servizio non ha indicato un motivo"
                )
                await finishPolling(recordingID, expired: false)
                return false
            }
            return true
        } catch {
            rowErrors[recordingID] = readableMessage(error)
            await finishPolling(recordingID, expired: false)
            return false
        }
    }

    /// Ends one recording's poll and re-reads `GET /recordings`, so the row lands on the state
    /// the service now reports without anyone pressing «Aggiorna» (Task 10's live walkthrough:
    /// nothing here re-fetched, so even the *final* state of a job appeared only after a manual
    /// refresh - the whole processing run was invisible).
    ///
    /// `async`, awaited at every call site, rather than an unstructured `Task { await refresh() }`:
    /// every call site is already inside the poll's own `Task`, so the re-fetch stays part of
    /// the poll's lifetime and `stop()` ends it with everything else - a detached task would
    /// outlive the poll that owns it and could repopulate `recordings` for a vault that has
    /// changed underneath it (R-12).
    ///
    /// Order matters twice over, which is why the poll's own state is dropped *after* the
    /// await rather than before it. `refresh()` reloads the ledger, and `reloadLedger()` clears
    /// `pollExpired` whenever it builds the store - including the very first build, when no
    /// vault has been switched at all - so a marker written before the await would be wiped by
    /// the refresh that follows it. And while the re-fetch is in flight the row is better left
    /// saying «in corso» (`RecordingsPane.effectiveState`) than flashing the stale wire state
    /// it is about to replace.
    private func finishPolling(_ recordingID: String, expired: Bool) async {
        // Cleared first, and only this: `refresh()` may reach `stop()`, which cancels every
        // task still in this dictionary - including, otherwise, the one running this line.
        pollTasks[recordingID] = nil
        await refresh()
        pollingRecordingIDs.remove(recordingID)
        pollSteps[recordingID] = nil
        if expired { pollExpired.insert(recordingID) }
    }

    // MARK: - Delete (R-09)

    /// Confirmation is the caller's job. Calls `vault.trashNote(at:)`
    /// (`VaultController+Files.swift:70`) and marks the ledger entry deleted - no service
    /// method is called at all, per the contract having no delete endpoint (ADR §D9's
    /// "asking the service" rejection).
    func delete(recordingID: String) async {
        guard !isIsolated else { return isolate() }
        guard var entry = ledger.recordings[recordingID] else { return }

        if let path = entry.notePath {
            guard await vault.trashNote(at: path) else {
                // `trashNote` already recorded why (an unsaved note, a failed move): the
                // ledger must not say deleted while the note is still there.
                rowErrors[recordingID] = "Nota non eliminata: \(path)"
                return
            }
        }
        entry.status = "deleted"
        // The note is gone, so the path is no longer an anchor for anything: a later import
        // of the same recording writes a new note rather than resurrecting this one.
        entry.notePath = nil
        // `quoteFingerprints` survives on purpose - a deletion is a decision, and the
        // suppression set is what keeps it (ADR §D9).
        entry.pendingConfirmation = []
        record(entry, for: recordingID)
    }
}
