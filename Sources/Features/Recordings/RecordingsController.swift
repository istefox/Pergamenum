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
    /// The step the last polled job reported (`transcript`/`extract`/`cleanup`), by
    /// recording id - what a `processing` row shows beside its progress indicator. The
    /// service's own word, never a translation: it is a stage name, not a sentence, and a
    /// paraphrase here would be one this app invented.
    private(set) var pollSteps: [String: String] = [:]
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

    /// The local files this vault's ledger and drafts live in (ADR §D12), `nil` until a
    /// vault is open. Rebuilt, never merged, when `vault.session` changes identity (R-12).
    private var store: PlaudVaultStore?
    /// Which session `store` was built for, as its own state directory - the identity
    /// ADR-0017 gives a vault, rather than the root path a rename would change.
    private var storeIdentity: String?
    private var ledger: PlaudVaultStore.Ledger = .empty
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
    ) async {
        guard !isIsolated else { return isolate() }
        reloadLedger()
        guard let session = vault.session, store != nil else {
            rowErrors[recordingID] = Self.noVaultMessage
            return
        }
        // An unparseable `recorded_at` used to fall through silently to today's date, both
        // in the note's frontmatter and in its file name (`notePath`/`TranscriptNote.render`
        // each default to "now" when parsing fails) - filing a malformed recording under the
        // wrong date instead of surfacing it (RTF review finding, 2026-09-06). Rejected here,
        // before either fallback is ever reached.
        guard PlaudTimestamp.parse(proposal.recording.recordedAt) != nil else {
            rowErrors[recordingID] = "Data di registrazione non valida: \"\(proposal.recording.recordedAt)\""
            return
        }

        var entry = ledger.recordings[recordingID] ?? PlaudVaultStore.Entry(status: "new")
        // The note is the source of truth (principle 1): what it already holds suppresses a
        // task just as the ledger does, and it is read here rather than remembered.
        let existingText = entry.notePath.flatMap { try? session.read($0).text }
        let text = TranscriptNote.render(
            proposal: proposal,
            acceptedTaskIDs: acceptedTaskIDs,
            speakerRenames: speakerRenames,
            ledgerFingerprints: entry.quoteFingerprints,
            existingNoteText: existingText
        )
        let path = entry.notePath ?? notePath(for: proposal, in: session)

        // Phase 1: the file first. A failure here means nothing was imported at all, so
        // nothing is recorded and no confirmation is owed.
        do {
            try session.write(text, to: path)
        } catch {
            rowErrors[recordingID] = "Scrittura della nota non riuscita: \(path)"
            return
        }

        entry.status = "imported"
        entry.notePath = path
        entry.quoteFingerprints = fingerprints(
            ofAccepted: acceptedTaskIDs, in: proposal, added: entry.quoteFingerprints
        )
        entry.pendingConfirmation = acceptedTaskIDs.sorted()
        entry.lastImportedAt = Date.now.ISO8601Format()
        guard record(entry, for: recordingID) else {
            // The ledger write failed: the pending-confirmation debt never reached disk, so
            // telling the service "imported" now would leave nothing to retry it from
            // (ADR §D13). `rowErrors[recordingID]` is already set by `record`.
            return
        }

        // Phase 2, and only now: a confirmation the vault cannot honour would mark the
        // recording imported service-side with nothing to show for it (ADR §D13).
        await confirm(recordingID: recordingID, taskIDs: entry.pendingConfirmation)
    }

    /// Re-issues only phase 2 of `importAccepted` for the ids already recorded as
    /// `pendingConfirmation` - no note write, no proposal re-fetch, one `confirmImported`
    /// call.
    func retryConfirmation(recordingID: String) async {
        guard !isIsolated else { return isolate() }
        guard let entry = entries[recordingID], !entry.pendingConfirmation.isEmpty else { return }
        await confirm(recordingID: recordingID, taskIDs: entry.pendingConfirmation)
    }

    /// `POST /proposals/{id}/imported` with exactly the accepted ids and nothing else
    /// (R-06). On success the debt is cleared; on failure the note stays written and the
    /// debt stays owed, which is the whole point of recording it before asking (ADR §D13).
    private func confirm(recordingID: String, taskIDs: [String]) async {
        do {
            try await service.confirmImported(recordingID: recordingID, taskIDs: taskIDs)
            confirmationFailures[recordingID] = nil
            guard var entry = ledger.recordings[recordingID] else { return }
            entry.pendingConfirmation = []
            record(entry, for: recordingID)
        } catch {
            confirmationFailures[recordingID] = readableMessage(error)
        }
    }

    /// Every accepted task's quote fingerprint, added to the ones already recorded. The
    /// ledger only ever grows (ADR §D9): that is what makes a task the person deleted from
    /// the note stay deleted instead of returning on the next forced re-run.
    private func fingerprints(
        ofAccepted acceptedTaskIDs: Set<String>, in proposal: PlaudProposal, added existing: [String]
    ) -> [String] {
        var known = existing
        for theme in proposal.themes {
            for task in theme.tasks where acceptedTaskIDs.contains(task.id) {
                let fingerprint = PlaudQuote.fingerprint(task.quote)
                guard !known.contains(fingerprint) else { continue }
                known.append(fingerprint)
            }
        }
        return known
    }

    // MARK: - Delete (R-09)

    /// Confirmation is the caller's job. Calls `vault.trashNote(at:)`
    /// (`VaultController+Files.swift:70`) and marks the ledger entry deleted - no service
    /// method is called at all, per the contract having no delete endpoint (ADR §D9's
    /// "asking the service" rejection).
    func delete(recordingID: String) {
        guard !isIsolated else { return isolate() }
        guard var entry = ledger.recordings[recordingID] else { return }

        if let path = entry.notePath {
            guard vault.trashNote(at: path) else {
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

// MARK: - Ledger, vault scoping (R-12) and readable failure (R-13)

// In an extension purely for length: the class body above is already at SwiftLint's
// `type_body_length` limit, and nothing here is part of what the pane calls.
extension RecordingsController {
    static let noVaultMessage = "Nessun vault aperto: apri un vault prima di importare una registrazione."

    /// Rebuilds the store when `vault.session` has changed identity and rereads the ledger
    /// from disk, which is where every other writer of these files leaves its state.
    private func reloadLedger() {
        guard let session = vault.session else {
            store = nil
            storeIdentity = nil
            ledger = .empty
            entries = [:]
            recordings = []
            stop()
            return
        }

        let identity = session.state.directory.path(percentEncoded: false)
        if identity != storeIdentity {
            // A poll belongs to the vault that started it, and so does everything a row
            // was saying about it (R-12).
            stop()
            storeIdentity = identity
            store = PlaudVaultStore(directory: session.state.directory)
            recordings = []
            rowErrors = [:]
            confirmationFailures = [:]
            pollExpired = []
        }
        ledger = store?.loadLedger() ?? .empty
        entries = ledger.recordings
    }

    /// Writes one entry through, disk first: `pendingConfirmation` that never reached the
    /// file is a debt nothing would retry after a relaunch (ADR §D13). Returns whether the
    /// write actually reached disk, so a caller about to tell the service "imported" can
    /// refuse to when it did not (`importAccepted`).
    @discardableResult
    private func record(_ entry: PlaudVaultStore.Entry, for recordingID: String) -> Bool {
        ledger.recordings[recordingID] = entry
        entries = ledger.recordings
        do {
            try store?.saveLedger(ledger)
            return true
        } catch {
            rowErrors[recordingID] = "Stato locale non salvato: la conferma non verrà ritentata dopo la chiusura."
            return false
        }
    }

    /// Where a recording's note goes the first time it is imported: `<notes folder>/` at the
    /// vault root, named by `ImportNaming.recordingNoteTitle` (ADR §D5) and made unique the
    /// way every other import already is.
    private func notePath(for proposal: PlaudProposal, in session: VaultSession) -> String {
        let recordedAt = PlaudTimestamp.parse(proposal.recording.recordedAt) ?? Date.now
        let title = ImportNaming.recordingNoteTitle(recordedAt: recordedAt, name: proposal.recording.name)
        let folder = ledger.notesFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let directory = folder.isEmpty
            ? session.root
            : session.root.appending(path: folder, directoryHint: .isDirectory)
        let fileName = ImportNaming.uniqueFileName(NoteName.fileName(for: title), in: directory)
        return folder.isEmpty ? fileName : "\(folder)/\(fileName)"
    }

    /// The one state an isolated launch ever reports, set on every entry point rather than
    /// once: a method that returned silently would leave a banner from before the flag.
    private func isolate() {
        health = .unavailable(message: Self.isolatedMessage)
        bannerMessage = Self.isolatedMessage
    }

    /// R-13: a readable sentence for anything thrown, never `"\(error)"`. `PlaudError` owns
    /// its own wording; anything else is reported through the transport case, which is what
    /// a failure that never reached the mapping table actually was.
    private func readableMessage(_ error: any Error) -> String {
        if let plaud = error as? PlaudError { return plaud.message }
        return PlaudError.transportFailure(error.localizedDescription).message
    }
}

// MARK: - What the interface asks for (Task 7's sheet, Task 8's Impostazioni field)

// ADR-0032 (Plaud recording import into Pergamenum), plan
// docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Tasks 7-8 -
// R-04, R-10, R-11; ADR §D9, §D12.
//
// Four reads and two writes the pane cannot perform for itself, because they need the
// service, the session or the store - all three private to this file. Kept here rather than
// spread into the views for the reason the whole controller exists: a view that fetched its
// own proposal, or resolved its own state directory, would be a second place the isolation
// flag (`isIsolated`) and the vault scoping (R-12) have to be remembered.
extension RecordingsController {
    /// `GET /proposals/{id}` for the review sheet (R-04). `nil` on any failure, with the
    /// readable reason left on the row (R-13) rather than thrown at a view that has no way
    /// to say it.
    func loadProposal(recordingID: String) async -> PlaudProposal? {
        guard !isIsolated else {
            isolate()
            return nil
        }
        do {
            let proposal = try await service.proposal(recordingID: recordingID)
            rowErrors[recordingID] = nil
            return proposal
        } catch {
            rowErrors[recordingID] = readableMessage(error)
            return nil
        }
    }

    /// ADR §D9's suppression set for one recording: the union of the ledger's fingerprints
    /// and the ones the note itself already carries. Read from the file every time rather
    /// than cached - the note is the source of truth and the person may have edited it since.
    func suppressedFingerprints(recordingID: String) -> Set<String> {
        ensureStore()
        guard let entry = ledger.recordings[recordingID] else { return [] }
        var existingText: String?
        if let path = entry.notePath, let session = vault.session {
            existingText = try? session.read(path).text
        }
        return TranscriptNote.suppressionSet(
            existingNoteText: existingText, ledgerFingerprints: entry.quoteFingerprints
        )
    }

    /// The pending review for a recording, or `nil` when there is none or when the one on
    /// disk was taken against a different `generated_at` (R-10's boundary, ADR §D12).
    func draft(recordingID: String, generatedAt: String) -> PlaudVaultStore.Draft? {
        ensureStore()
        return store?.draft(for: recordingID, currentGeneratedAt: generatedAt)
    }

    /// R-10: called on every checkbox and every rename field as it changes, so a sheet
    /// dismissed by accident - or an app quit mid-review - comes back to the same decisions.
    func saveDraft(_ draft: PlaudVaultStore.Draft, for recordingID: String) {
        ensureStore()
        guard let store else { return }
        var drafts = store.loadDrafts()
        drafts[recordingID] = draft
        do {
            try store.saveDrafts(drafts)
        } catch {
            rowErrors[recordingID] = "Bozza di revisione non salvata: le scelte non verranno "
                + "ripristinate dopo la chiusura."
        }
    }

    /// Dropped once its decisions have been acted on: keeping it would restore them over a
    /// later, different proposal for the same recording.
    func clearDraft(for recordingID: String) {
        ensureStore()
        guard let store else { return }
        var drafts = store.loadDrafts()
        guard drafts.removeValue(forKey: recordingID) != nil else { return }
        try? store.saveDrafts(drafts)
    }

    /// R-11's «Giorni registrazioni Plaud», read straight off the ledger.
    ///
    /// A vault-scoped operational setting living in `plaud.json` and **not** in
    /// `VaultSettings` (ADR §D12): Impostazioni writes it through `updateDays(_:)` below, so
    /// looking for a `VaultSettings` key for it is looking for something that does not exist.
    var days: Int { ledger.days }

    /// Clamped to what the service accepts, on the way in: outside 1…3650 it answers 400
    /// `invalid_days`, and a setting that can only fail is not a setting.
    func updateDays(_ requested: Int) {
        ensureStore()
        guard store != nil else { return }
        ledger.days = min(max(requested, PlaudVaultStore.minimumDays), PlaudVaultStore.maximumDays)
        do {
            try store?.saveLedger(ledger)
        } catch {
            bannerMessage = "Intervallo di giorni non salvato: la cartella di stato del vault non è scrivibile."
        }
    }

    /// Reads the ledger once for a caller that arrives before the pane has (Impostazioni is
    /// its own scene and may be opened first). Not on every call: `saveDraft` runs on every
    /// keystroke of a rename field, and a disk read per keystroke is a cost with no answer.
    private func ensureStore() {
        guard store == nil else { return }
        reloadLedger()
    }
}
