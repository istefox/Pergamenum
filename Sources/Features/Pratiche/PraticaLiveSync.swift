import Foundation

// MARK: - The live wiring (`PergamenumApp`'s one `@State`)

extension PraticheController {
    /// The controller the running app holds: the real probe, the real sync engine, and
    /// the two automatic triggers armed by `startWatching(_:)`.
    ///
    /// A coordinator object rather than a closure capturing the controller: the two
    /// dependencies are `let`s handed to `init` (the signature the tests were written against), so
    /// the sync closure cannot capture a controller that does not exist yet.
    static func live(vault: VaultController) -> PraticheController {
        let coordinator = PraticaLiveSync(vault: vault)
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state() },
            performSync: { [coordinator] path, kind in await coordinator.run(praticaPath: path, kind: kind) }
        )
        coordinator.controller = controller
        controller.requestSyncCancellation = { [coordinator] in coordinator.cancel() }
        controller.requestSyncStopForVanishedPath = { [coordinator] in coordinator.stopForVanishedPath() }
        controller.prepareRegeneration = { [coordinator] praticaPath, messageID in
            await coordinator.prepareRegeneration(praticaPath: praticaPath, messageID: messageID)
        }
        controller.commitRegeneration = { [coordinator] plan in
            await coordinator.commitRegeneration(plan)
        }
        return controller
    }
}

/// What one `runExclusive` run ends with (round-4 review, §3) - the "echo the value
/// back, not a bare bit" idiom `SyncRunQueue.request`/`finished` below already use:
/// `.relocated(to:)` names the exact path this pipeline must ask to run again, rather
/// than a caller having to re-derive it from `praticaPathRedirects` itself.
enum RunOutcome: Equatable, Sendable {
    case finished
    case relocated(to: String)
}

/// The pure serialization rule behind `PraticaLiveSync.run(praticaPath:)` - the same
/// `PraticaWatcher` precedent (this file, R-17): extracted so a scheduling rule is
/// testable without the real async work (Mail store copy, SQLite read, file writes)
/// behind it.
///
/// `PraticaLiveSync` runs one sync at a time system-wide (`running`, and the
/// controller's own single `syncingPraticaPath`, both track exactly one). Before this
/// existed, two `run(praticaPath:)` calls overlapping across an `await` suspension
/// each assigned `running` and each `defer`-cleared it, so the earlier sync became
/// uncancellable and its own cleanup could fire after a *later* sync had already
/// taken over the shared reference.
struct SyncRunQueue: Equatable {
    private(set) var isRunning = false
    private(set) var pending: [String] = []

    /// A path asks to run. `nil` means it was queued, not started - the caller must
    /// not begin work. A non-`nil` result is always `path` itself, echoed back so the
    /// call site reads as "the path to actually run", not as a bare permission bit.
    mutating func request(_ path: String) -> String? {
        guard !isRunning else {
            if !pending.contains(path) { pending.append(path) }
            return nil
        }
        isRunning = true
        return path
    }

    /// The active run just finished. `nil` means the queue is empty - the caller
    /// stops and the whole coordinator goes idle. A non-`nil` result is the next path
    /// to run immediately, with `isRunning` still `true`.
    mutating func finished() -> String? {
        guard !pending.isEmpty else {
            isRunning = false
            return nil
        }
        return pending.removeFirst()
    }

    /// «Annulla» (R-11): drops every request left waiting behind the one actually
    /// cancelled, so an interrupted sync is not silently followed by a queued one.
    /// Never touches `isRunning` - the active run's own `finished()` call is still
    /// what ends it, once its (cancelled) `runExclusive` returns.
    mutating func cancelPending() {
        pending.removeAll()
    }
}

/// Runs one pratica's real sync: publishes a copy of the Envelope Index, evaluates the
/// membership rule against it, and hands the candidates to `PraticaSyncEngine`.
///
/// Everything that touches Mail's own files happens inside one detached task
/// (`prepare(...)` below) and returns `Sendable` values: the SQLite connection never
/// leaves it, and the copy - 355 MB on this Mac - is never made on the main actor
/// (`MailStoreCopy.publish`'s own instruction).
@MainActor
final class PraticaLiveSync {
    weak var controller: PraticheController?
    /// Not `private`: `PraticaLiveSync+Run.swift`'s `runExclusive(praticaPath:)` and its
    /// extracted steps are in a separate file, and read this throughout.
    let vault: VaultController
    /// The engine of the sync currently running, or `nil` between syncs.
    ///
    /// Not `private`: `PraticaLiveSync+Run.swift`'s `runEngine(...)` is in a separate
    /// file, and is this member's only writer.
    var running: PraticaSyncEngine?
    /// The pure serialization rule behind `run(praticaPath:)` - see `SyncRunQueue`'s
    /// own doc for why concurrent triggers must not run `runExclusive` concurrently.
    private var queue = SyncRunQueue()
    /// What a queued request needs once it is finally dequeued: which vault it
    /// belongs to, and which trigger asked for it (:976's fix - a queued
    /// `.automatic` request must recheck the pratica's CURRENT eligibility at
    /// dequeue time, since "closed while another sync ran" is exactly the window
    /// where that eligibility can change under it; `.manualRefresh` never rechecks,
    /// per R-17's "closed pratiche sync only through «Aggiorna ora»").
    private struct QueuedRequest {
        var session: VaultSession
        var kind: PraticaWatcher.Trigger
    }

    /// Which vault (and trigger) a QUEUED path belongs to, recorded at the moment it
    /// was asked for. `praticaPath` is vault-relative: a request queued while vault A
    /// is open and only dequeued after a switch to vault B would otherwise resolve
    /// A's path against B's folder tree. `run(praticaPath:kind:)` drops a dequeued
    /// request whose recorded session no longer matches the live one instead of
    /// running it.
    private var queuedRequests: [String: QueuedRequest] = [:]

    /// Held between `prepareRegeneration` and `commitRegeneration` (ADR §D21.2):
    /// `PraticaSyncEngine.commitRegeneration(_:)` only writes, it never re-opens the
    /// reader, so the same actor instance that produced the plan is what commits it.
    ///
    /// Review round 3: also this attempt's own identity token. `prepareRegeneration`
    /// creates a fresh instance and assigns it here before its only `await` - so once
    /// that `await` returns, comparing the local `engine` against this property answers
    /// "is my attempt still the current one, or has a newer `prepareRegeneration` call
    /// already overwritten it". `dismissRegeneration` ("Annulla") releases a claim
    /// without cancelling the in-flight `Task` behind it (cooperative cancellation, the
    /// same shape as `cancel()` above, has nothing to cancel here - `regenerationPreview`
    /// has no internal cancellation checkpoint); an abandoned attempt's own completion
    /// finds this property already pointing at the newer attempt's engine and drops its
    /// result instead of clobbering `controller.regeneration` or double-releasing a claim
    /// `dismissRegeneration` already ended.
    private var regenerationEngine: PraticaSyncEngine?

    /// «Annulla» (R-11). Cooperative and asynchronous by nature: the engine observes
    /// it at its next message boundary, so everything already written stays complete.
    /// Also drops every queued request: an interrupted sync should not be silently
    /// followed by the ones a burst of triggers left waiting behind it.
    func cancel() {
        queue.cancelPending()
        queuedRequests.removeAll()
        guard let running else { return }
        Task { await running.cancel() }
    }

    /// Round-4 review, §4: asks the running engine to stop because ITS OWN pratica
    /// folder just relocated - or, since PG-169, went to the Trash: the path the run
    /// captured is gone either way, and which of the two it was does not change what the
    /// engine has to do. Deliberately not `cancel()` above, which also drops
    /// `queue.pending`/`queuedRequests` wholesale and would discard other pratiche's
    /// own queued syncs that have nothing to do with this one. Cooperative, same
    /// as `cancel()`: the engine observes it at its next message boundary, so the
    /// message being written at the instant of the move or trash still reaches its write - which
    /// is refused rather than landed, since it may not recreate the vacated folder (`PG-168`).
    func stopForVanishedPath() {
        guard let running else { return }
        Task { await running.cancel() }
    }

    init(vault: VaultController) {
        self.vault = vault
    }

    /// Every trigger funnels through here (SPEC "Full Disk Access" / R-17/R-18).
    /// Concurrent triggers - a window activation and an FSEvents pulse landing while
    /// this actor is suspended inside a previous sync's `await` - are serialized
    /// through `queue` instead of running `runExclusive` concurrently, since
    /// `running` and the controller's `syncingPraticaPath` each track exactly one
    /// sync at a time.
    func run(praticaPath: String, kind: PraticaWatcher.Trigger) async {
        guard let session = vault.session else { return }
        guard let toRun = queue.request(praticaPath) else {
            queuedRequests[praticaPath] = Self.coalesce(
                queuedRequests[praticaPath], with: QueuedRequest(session: session, kind: kind)
            )
            return
        }
        var current = toRun
        var currentSession = session
        var currentKind = kind
        while true {
            if vault.session === currentSession, isStillEligible(current, kind: currentKind) {
                let outcome = await runExclusive(praticaPath: current)
                // Round-4 review, §3: a relocation mid-run left `current`'s pratica
                // sitting at a path this run never got to sync - ask for it again
                // BEFORE `queue.finished()` dequeues whatever else is waiting, so the
                // request lands in `pending` (`SyncRunQueue.request` returns `nil`
                // while `isRunning` is still `true` here, never dropped) rather than
                // being lost. Livelock would need a SECOND relocation to land inside
                // this very requeue's own run, which needs a person to move the same
                // pratica again before the retry even starts - bounded in practice, no
                // counter added.
                if let requeued = Self.requeue(after: outcome, kind: currentKind) {
                    _ = queue.request(requeued.path)
                    queuedRequests[requeued.path] = Self.coalesce(
                        queuedRequests[requeued.path], with: QueuedRequest(session: currentSession, kind: requeued.kind)
                    )
                }
            }
            guard let next = queue.finished() else { break }
            current = next
            let queued = queuedRequests.removeValue(forKey: next)
            currentSession = queued?.session ?? currentSession
            currentKind = queued?.kind ?? currentKind
        }
    }

    /// The pure decision behind the re-enqueue above, extracted the same way
    /// `SyncRunQueue` was (this file's own established idiom, `shouldRunQueuedRequest`/
    /// `coalescedKind`'s own precedent). `nil` means the run finished on its own and
    /// nothing needs to run again. The trigger kind is always the SAME `kind` the
    /// relocated run was itself running under, never a hard-coded `.manualRefresh`:
    /// that is what lets `shouldRunQueuedRequest` still revoke an `.automatic` requeue
    /// if the pratica closed meanwhile (R-17), and what keeps a `.manualRefresh`
    /// sticky through `coalesce`.
    nonisolated static func requeue(
        after outcome: RunOutcome, kind: PraticaWatcher.Trigger
    ) -> (path: String, kind: PraticaWatcher.Trigger)? {
        guard case .relocated(let newPath) = outcome else { return nil }
        return (newPath, kind)
    }

    /// :976's recheck. `.manualRefresh` ignores `Eligibility` entirely, same as
    /// `PraticheController.trigger(_:kind:eligibility:)` does for the immediate path -
    /// a queued «Aggiorna ora» must still run even if the pratica closed while it
    /// waited. Every other trigger kind is only queued because it was `.automatic`
    /// when first asked for (`PraticheController.trigger` never queues a request that
    /// didn't already pass that check), so what changed is whether it STILL is -
    /// re-read the live `pratiche` list rather than trusting the stale decision.
    /// A pratica no longer found (deleted, or the vault moved on) runs rather than
    /// silently drops: closing the request instead of running it once more is a much
    /// smaller cost than a dropped result nobody asked for a second time.
    private func isStillEligible(_ praticaPath: String, kind: PraticaWatcher.Trigger) -> Bool {
        Self.shouldRunQueuedRequest(
            kind: kind,
            currentEligibility: controller?.pratiche.first { $0.id == praticaPath }.map(PraticheController.eligibility(of:))
        )
    }

    /// The pure decision behind `isStillEligible`, extracted the same way `SyncRunQueue`
    /// was extracted from this same function's earlier body (this file's own header
    /// comment) - so the rule is testable without the async work, the real `pratiche`
    /// list, or a live `PraticheController` at all. `currentEligibility == nil` means
    /// the pratica could not be found in the live list; treated the same as "run it",
    /// per `isStillEligible`'s own doc.
    nonisolated static func shouldRunQueuedRequest(
        kind: PraticaWatcher.Trigger, currentEligibility: PraticaWatcher.Eligibility?
    ) -> Bool {
        guard kind != .manualRefresh else { return true }
        guard let currentEligibility else { return true }
        return currentEligibility == .automatic
    }

    /// :1001's fix. The same path can already sit in `queuedRequests` when a second
    /// trigger asks for it (`SyncRunQueue.request` only dedupes `queue.pending` by
    /// path, never by trigger kind) - an unconditional overwrite let a later automatic
    /// trigger silently downgrade an earlier `.manualRefresh`'s stored kind, so
    /// `shouldRunQueuedRequest` would then treat an explicit «Aggiorna ora» as
    /// revocable if the pratica closed before it dequeued. `.manualRefresh`, once
    /// recorded, is sticky: nothing coalesced afterwards can un-record it - UNLESS the
    /// incoming request belongs to a DIFFERENT session (:1059's fix on top of :1001's
    /// own): sticking with the old session's `QueuedRequest` wholesale would keep
    /// `run(praticaPath:kind:)`'s later `vault.session === currentSession` check
    /// comparing against a vault nobody has open any more, silently dropping a genuine
    /// refresh queued for the SAME path in the vault that is open now. A session
    /// change always wins outright, same as an empty queue slot.
    private nonisolated static func coalesce(_ existing: QueuedRequest?, with incoming: QueuedRequest) -> QueuedRequest {
        guard let existing, existing.session === incoming.session,
            Self.coalescedKind(existing: existing.kind, incoming: incoming.kind) == existing.kind
        else { return incoming }
        return existing
    }

    /// The pure decision behind `coalesce`, extracted the same way `shouldRunQueuedRequest`
    /// was - testable with no `QueuedRequest`, no session, no controller. `existing == nil`
    /// means nothing was queued yet, so the incoming kind always wins.
    nonisolated static func coalescedKind(
        existing: PraticaWatcher.Trigger?, incoming: PraticaWatcher.Trigger
    ) -> PraticaWatcher.Trigger {
        guard let existing, existing == .manualRefresh else { return incoming }
        return existing
    }

    // MARK: - «Rigenera» (ADR §D21)

    /// §D21.1: publishes a fresh store copy, then asks the engine to acquire the
    /// replacement text and diff it - nothing is trashed or written yet. The engine is
    /// kept in `regenerationEngine` for `commitRegeneration` below, since it is the
    /// one thing that must not be re-derived between preview and commit.
    func prepareRegeneration(praticaPath: String, messageID: String) async {
        guard let controller, let session = vault.session, let root = vault.root else { return }
        // Review round 2, MINOR 1: claimed from here, before the first `await` below,
        // so a relocation racing this attempt still leaves `moveLedgerState` a
        // `praticaPathRedirects` entry to redirect `plan.praticaFolder` through later.
        controller.beginRegeneration(praticaPath)
        let settings = vault.settings.pratiche
        guard let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root) else {
            controller.report("«\(praticaPath)» non ha un dossier leggibile in pratica.md.")
            controller.regeneration = nil
            controller.endRegeneration(praticaPath)
            return
        }
        let state = controller.ledgerState(of: praticaPath, in: session)
        let onDisk = Set(state.importedMessageIDs)
        // §D3: the ledger's own bridge, for a message the fresh index copy cannot
        // resolve by `Message-ID` on its own.
        let rowID = state.entries.first { $0.messageID == messageID }?.rowID
        let mailRoot = MailStoreLocation.resolve()
        let stateDirectory = PraticheController.stateDirectory(for: session)

        let indexURL: URL
        switch MailStorePreparation.reader(mailRoot: mailRoot, stateDirectory: stateDirectory) {
        case .ready(_, let openedIndexURL):
            indexURL = openedIndexURL
        case .failed(let message):
            controller.report(message)
            controller.regeneration = nil
            controller.endRegeneration(praticaPath)
            return
        }

        let engine = PraticaSyncEngine(mailStoreURL: indexURL, vaultRoot: root) { text, path, expecting in
            // PG-168: never recreate the folder a relocation or a trash has just vacated -
        // the engine's only door onto a note, so this holds for every write it will ever make.
        _ = try await session.write(text, to: path, expecting: expecting, requiringExistingFolder: true)
        }
        regenerationEngine = engine

        let request = PraticaSyncEngine.SyncRequest(
            praticaFolder: praticaPath, dossier: dossier, candidates: [], onDisk: onDisk, settings: settings
        )
        do {
            let plan = try await engine.regenerationPreview(request, messageID: messageID, rowID: rowID)
            guard regenerationEngine === engine else {
                // Review round 3: superseded. «Annulla» already released this attempt's
                // claim (`dismissRegeneration`), and a later `prepareRegeneration` call
                // has since overwritten `regenerationEngine` with its own - dropping
                // silently must not touch `controller.regeneration` (it now belongs to
                // that later attempt) nor call `endRegeneration` again (nothing left to
                // release; the claim this attempt held is either already gone or, if the
                // pratica path is the same, now the later attempt's own).
                return
            }
            guard vault.session === session else {
                controller.endRegeneration(praticaPath)
                return
            }
            // Round-4 review, §2: a third guard in this ladder, ordered after both
            // above (a superseded attempt stays silent, a vault switch already ended
            // the claim) - the folder relocated while `regenerationPreview`'s own
            // `await` was in flight. `plan.praticaFolder` still names the vacated
            // path, and `commitRegeneration`'s own guard below would refuse it
            // anyway, so there is nothing useful left to show. No auto-retry: unlike
            // an ordinary sync (§3), regenerating one specific message is a
            // per-message user action, not something this pipeline re-enqueues on
            // its own.
            do {
                _ = try controller.praticaPath(continuing: praticaPath)
            } catch {
                controller.regeneration = nil
                controller.endRegeneration(praticaPath)
                controller.report(PraticaRunStop.regenerationRefusal(after: error, of: praticaPath))
                return
            }
            controller.regeneration = .ready(plan)
            // Stays claimed: `.ready` still needs the claim through however long the
            // sheet sits on screen, and through the commit that follows it.
        } catch {
            guard regenerationEngine === engine else {
                return
            }
            guard vault.session === session else {
                controller.endRegeneration(praticaPath)
                return
            }
            controller.regeneration = nil
            controller.endRegeneration(praticaPath)
            controller.report(Self.regenerationFailureMessage(error))
        }
    }

    /// §D21.2: commits an already-previewed plan through the same engine instance that
    /// produced it, then records the outcome in the ledger exactly as an ordinary sync
    /// would (`isRegeneration` routes it into `regeneratedPendingFiles`, never
    /// `importedMessageIDs` - `PraticaSyncEngine.commit`'s own rule). Anything but
    /// `.committed` tells the caller to put the trashed files back; `.refused` also says the
    /// sentence explaining why is already on the banner.
    func commitRegeneration(_ plan: PraticaSyncEngine.RegenerationPlan) async -> PraticaRegenerationCommit {
        guard let controller, let session = vault.session, let engine = regenerationEngine else {
            controller?.report("Rigenerazione non riuscita: il motore di sincronizzazione non è più disponibile.")
            controller?.endRegeneration(plan.praticaFolder)
            return .failed
        }
        // Round-4 review, §2: refused BEFORE anything is written - `plan.praticaFolder`
        // was captured when the preview ran, and the diff may have sat on screen long
        // enough for the folder to relocate before the person agreed to it.
        // `PraticaCommandActions.confirmRegeneration` has already trashed the current
        // files by the time this runs, so anything but `.committed` is what tells it to put
        // them back (`PraticaFileOperations.restore`) rather than leaving the message
        // missing - though `restore` uses `moveItem`, which does not create intermediate
        // directories (and must not: that would resurrect the vacated folder, PG-168), so a
        // relocated folder leaves the trashed files exactly where they are. The sentence below
        // says so, and `.refused` is what stops `confirmRegeneration` overwriting it.
        do {
            _ = try controller.praticaPath(continuing: plan.praticaFolder)
        } catch {
            controller.report(
                PraticaRunStop.regenerationRefusal(after: error, of: plan.praticaFolder)
                    + " I file del messaggio restano nel Cestino, recuperabili da lì."
            )
            controller.endRegeneration(plan.praticaFolder)
            return .refused
        }
        // No re-check after this await, unlike `runEngine`'s post-`engine.sync` guard, and
        // none is needed (PG-168's third case): a relocation landing during this write cannot
        // resurrect the folder. The engine's `commit` verifies the pratica up front
        // (`makeDirectory`), and this engine's closure passes `requiringExistingFolder:`, so
        // the write is refused rather than landed. `recordSyncOutcome` below still resolves
        // `plan.praticaFolder` through the redirect, so the ledger stays correct either way.
        do {
            let outcome = try await engine.commitRegeneration(plan)
            controller.recordSyncOutcome(
                outcome, for: plan.praticaFolder, session: session, isCurrentVault: vault.session === session
            )
            controller.endRegeneration(plan.praticaFolder)
            return .committed
        } catch {
            guard vault.session === session else {
                controller.endRegeneration(plan.praticaFolder)
                return .failed
            }
            controller.report(Self.regenerationFailureMessage(error))
            controller.endRegeneration(plan.praticaFolder)
            return .failed
        }
    }

    private static func regenerationFailureMessage(_ error: Error) -> String {
        guard let failure = error as? PraticaSyncEngine.RegenerationFailure else {
            return "Rigenerazione non riuscita: \(error.localizedDescription)"
        }
        switch failure {
        case .rowNotFound:
            return "Il messaggio non è stato trovato nell'indice di Mail."
        case .notInStore:
            return "Il messaggio non è più in Mail: non c'è nulla da cui rigenerarlo."
        case .notDecodable:
            return "Il messaggio non è stato letto correttamente da Mail."
        case .fileMissing:
            return "Il file della nota non è stato trovato nel vault."
        }
    }
}
