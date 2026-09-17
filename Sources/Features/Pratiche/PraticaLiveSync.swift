import Foundation

// MARK: - The live wiring (`PergamenumApp`'s one `@State`)

extension PraticheController {
    /// The controller the running app holds: the real probe, the real sync engine, and
    /// the two automatic triggers armed by `startWatching(_:)`.
    ///
    /// A coordinator object rather than a closure capturing the controller: the two
    /// dependencies are `let`s handed to `init` (the tester's signature, ADR-0155), so
    /// the sync closure cannot capture a controller that does not exist yet.
    static func live(vault: VaultController) -> PraticheController {
        let coordinator = PraticaLiveSync(vault: vault)
        let controller = PraticheController(
            probe: { FullDiskAccessProbe.state() },
            performSync: { [coordinator] path, kind in await coordinator.run(praticaPath: path, kind: kind) }
        )
        coordinator.controller = controller
        controller.requestSyncCancellation = { [coordinator] in coordinator.cancel() }
        controller.prepareRegeneration = { [coordinator] praticaPath, messageID in
            await coordinator.prepareRegeneration(praticaPath: praticaPath, messageID: messageID)
        }
        controller.commitRegeneration = { [coordinator] plan in
            await coordinator.commitRegeneration(plan)
        }
        return controller
    }
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
                await runExclusive(praticaPath: current)
            }
            guard let next = queue.finished() else { break }
            current = next
            let queued = queuedRequests.removeValue(forKey: next)
            currentSession = queued?.session ?? currentSession
            currentKind = queued?.kind ?? currentKind
        }
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
        let state = controller.ledger.byPraticaPath[praticaPath] ?? .empty
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
            _ = try await session.write(text, to: path, expecting: expecting)
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
    /// `importedMessageIDs` - `PraticaSyncEngine.commit`'s own rule). `false` on
    /// failure, so the caller can put the trashed files back.
    func commitRegeneration(_ plan: PraticaSyncEngine.RegenerationPlan) async -> Bool {
        guard let controller, let session = vault.session, let engine = regenerationEngine else {
            controller?.report("Rigenerazione non riuscita: il motore di sincronizzazione non è più disponibile.")
            controller?.endRegeneration(plan.praticaFolder)
            return false
        }
        do {
            let outcome = try await engine.commitRegeneration(plan)
            controller.recordSyncOutcome(
                outcome, for: plan.praticaFolder, session: session, isCurrentVault: vault.session === session
            )
            controller.endRegeneration(plan.praticaFolder)
            return true
        } catch {
            guard vault.session === session else {
                controller.endRegeneration(plan.praticaFolder)
                return false
            }
            controller.report(Self.regenerationFailureMessage(error))
            controller.endRegeneration(plan.praticaFolder)
            return false
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
