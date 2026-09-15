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
    private let vault: VaultController
    /// The engine of the sync currently running, or `nil` between syncs.
    private var running: PraticaSyncEngine?
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

    /// The values one `runExclusive` run threads through its five extracted steps.
    /// Bundled rather than passed loose: `session`, `root` and `controller` are the
    /// exact instances captured by `runExclusive`'s own top-of-function `guard let`,
    /// not re-read from `self.vault`/`self.controller`, because the live vault can
    /// change under a `Task.detached` suspension mid-run and every step must keep
    /// acting on the vault THIS run started against (this file's own established
    /// `vault.session === session` guard shape).
    private struct RunContext {
        var praticaPath: String
        var session: VaultSession
        var root: URL
        var settings: PraticheSettings
        var controller: PraticheController
    }

    private func runExclusive(praticaPath: String) async {
        guard let controller, let session = vault.session, let root = vault.root else { return }
        guard let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root) else {
            controller.report("«\(praticaPath)» non ha un dossier leggibile in pratica.md.")
            return
        }

        let settings = vault.settings.pratiche
        let context = RunContext(
            praticaPath: praticaPath, session: session, root: root, settings: settings, controller: controller
        )
        let stateDirectory = PraticheController.stateDirectory(for: session)
        let state = controller.ledger.byPraticaPath[praticaPath] ?? .empty
        let onDisk = Set(state.importedMessageIDs)
        let mailRoot = MailStoreLocation.resolve()
        // R-30/SPEC "Membership rule": the window the tray proposes inside, and the
        // conversations somebody else's pratica already follows - read here, on the
        // main actor, because both come from state this object is not allowed to touch
        // from the detached task below.
        let now = Date()
        let window = now.addingTimeInterval(-Double(settings.proposalWindowDays) * 86_400)...now
        let claimed = Self.conversationsClaimedByOtherPratiche(
            than: praticaPath, among: controller.pratiche, vaultRoot: root
        )

        controller.beginSync(praticaPath)
        defer { controller.endSync() }

        let outcome = await Task.detached(priority: .utility) {
            MailStorePreparation.prepare(
                mailRoot: mailRoot, stateDirectory: stateDirectory,
                dossier: dossier, ledgerEntries: state.entries, proposalWindow: window
            )
        }.value

        let prepared: MailStorePreparation.Prepared
        switch outcome {
        case .ready(let value): prepared = value
        case .failed(let message):
            controller.report(message)
            return
        }

        var effectiveDossier = await applyConversationRemap(prepared, dossier: dossier, context: context)
        reportPreparationProblems(prepared, controller: controller)

        let evaluated = await evaluateCandidates(
            dossier: effectiveDossier, prepared: prepared, onDisk: onDisk, context: context
        )
        effectiveDossier = evaluated.dossier

        guard await runEngine(
            dossier: effectiveDossier, candidates: evaluated.candidates.messages, onDisk: onDisk,
            indexURL: prepared.indexURL, context: context
        ) else { return }

        refreshTray(effectiveDossier: effectiveDossier, prepared: prepared, window: window, claimed: claimed, context: context)
    }

    /// §D23.4: repoint the ledger and the dossier together, before candidates are
    /// evaluated, so this run already imports through the renumbered id rather than
    /// waiting for a later sync to notice.
    private func applyConversationRemap(
        _ prepared: MailStorePreparation.Prepared, dossier: Dossier, context: RunContext
    ) async -> Dossier {
        var effectiveDossier = dossier
        guard !prepared.conversationRemap.isEmpty else { return effectiveDossier }
        context.controller.remapLedgerConversations(prepared.conversationRemap, of: context.praticaPath, in: vault)
        let notePath = PraticaNaming.praticaNotePath(of: context.praticaPath)
        do {
            let (record, text) = try context.session.read(notePath)
            var document = NoteDocument.parse(text)
            let before = document
            if var updated = Dossier.parse(document.frontmatter.foreignKeys) {
                for index in updated.conversations.indices {
                    if let newID = prepared.conversationRemap[updated.conversations[index]] {
                        updated.conversations[index] = newID
                    }
                }
                // Collapse a duplicate a remap can create (two old ids folding into
                // one new one) while preserving first-seen position - the order a
                // person followed things in (`PraticaTrayModel.following`'s own reason).
                var seen: Set<Int> = []
                updated.conversations = updated.conversations.filter { seen.insert($0).inserted }
                document.frontmatter.foreignKeys = Dossier.merging(updated, into: document.frontmatter.foreignKeys)
                if document != before {
                    // ADR-0043 §D8, Task 9: `expecting:` closes the window between the
                    // read above and this write - a remap landing over a concurrent
                    // dossier edit would otherwise silently discard it.
                    try await context.session.write(document.serialized(), to: notePath, expecting: record.contentHash)
                }
                effectiveDossier = updated
            }
        } catch let refusal as VaultSession.WriteRefusal {
            context.controller.report("«\(notePath)» non è stato aggiornato: \(refusal.description)")
        } catch {
            context.controller.report("«\(notePath)» non è stato aggiornato: \(error.localizedDescription)")
        }
        return effectiveDossier
    }

    /// §D23.5/§D24.4: the two reports a preparation can carry, each shown once per sync.
    private func reportPreparationProblems(_ prepared: MailStorePreparation.Prepared, controller: PraticheController) {
        if !prepared.unrecoverableConversations.isEmpty {
            controller.report(
                "Una conversazione seguita non è più ricostruibile in Mail: \(prepared.unrecoverableConversations.count)."
            )
        }
        if prepared.recipientsUnsupported {
            controller.report(
                "L'indice di Mail non espone i destinatari: la vaschetta vede solo i messaggi ricevuti."
            )
        }
    }

    /// §D22.3: two evaluations, and the second is proved to be the last - rule 3
    /// skips an id already in `dossier.conversations`, so once every auto-followed
    /// id from the first pass is written into `effectiveDossier`, a second pass
    /// auto-follows nothing new. This lets a keyword match import the whole thread
    /// in the run that found it, not just the one matching message.
    private func evaluateCandidates(
        dossier: Dossier, prepared: MailStorePreparation.Prepared, onDisk: Set<String>, context: RunContext
    ) async -> (dossier: Dossier, candidates: MembershipRule.Candidates) {
        var effectiveDossier = dossier
        var candidates = MembershipRule.candidates(
            dossier: effectiveDossier, store: prepared.snapshot, onDisk: onDisk
        )
        if !candidates.autoFollowedConversations.isEmpty {
            for conversation in candidates.autoFollowedConversations {
                effectiveDossier = PraticaTrayModel.following(conversationID: conversation, in: effectiveDossier)
            }
            await DossierWriter.update(at: context.praticaPath, session: context.session) { $0 = effectiveDossier }
            candidates = MembershipRule.candidates(
                dossier: effectiveDossier, store: prepared.snapshot, onDisk: onDisk
            )
        }
        return (effectiveDossier, candidates)
    }

    /// Engine construction, the progress task, `sync`, `recordSyncOutcome` and the two
    /// catch arms. Returns `false` when the vault open at the start of this run is no
    /// longer the one live now, which means every step after this one must stop - the
    /// same check `runExclusive` used to make right after this block, inline.
    private func runEngine(
        dossier: Dossier, candidates: [MailMessageRow], onDisk: Set<String>, indexURL: URL, context: RunContext
    ) async -> Bool {
        let session = context.session
        let engine = PraticaSyncEngine(mailStoreURL: indexURL, vaultRoot: context.root) { text, path, expecting in
            _ = try await session.write(text, to: path, expecting: expecting)
        }
        // Kept for the duration of this one sync and cleared after it: «Annulla» has
        // an engine to reach only while there is a sync to stop.
        running = engine
        defer { running = nil }
        let controller = context.controller
        let progress = Task { @MainActor [weak controller] in
            for await step in await engine.progressStream() { controller?.updateProgress(step) }
        }
        defer { progress.cancel() }

        do {
            let result = try await engine.sync(PraticaSyncEngine.SyncRequest(
                praticaFolder: context.praticaPath,
                dossier: dossier,
                candidates: candidates,
                onDisk: onDisk,
                settings: context.settings
            ))
            // The vault open when this run started may no longer be the one open now
            // (a person can switch vaults mid-sync): the files above were written
            // through the SESSION captured at the top of this function, which is
            // correct, and so is this ledger write - `recordSyncOutcome` takes the
            // captured `session` explicitly and persists into ITS OWN ledger file
            // regardless of what is live, so a vault switch mid-sync can never leave a
            // completed import unrecorded OR bleed into whatever vault is live now.
            context.controller.recordSyncOutcome(
                result, for: context.praticaPath, session: session, isCurrentVault: vault.session === session
            )
        } catch let refusal as VaultSession.WriteRefusal {
            guard vault.session === session else { return false }
            context.controller.report("Sincronizzazione non riuscita: \(refusal.description)")
        } catch {
            guard vault.session === session else { return false }
            context.controller.report("Sincronizzazione non riuscita: \(error.localizedDescription)")
        }

        return vault.session === session
    }

    /// After the import and not before it: a conversation this run has just started
    /// following is no longer a proposal, and the tray would otherwise offer back
    /// what the person just accepted.
    private func refreshTray(
        effectiveDossier: Dossier, prepared: MailStorePreparation.Prepared,
        window: ClosedRange<Date>, claimed: Set<Int>, context: RunContext
    ) {
        let followed = PraticheController.dossier(at: context.praticaPath, vaultRoot: context.root) ?? effectiveDossier
        let tray = MembershipRule.trayCandidates(
            dossier: followed,
            store: prepared.snapshot,
            window: window,
            claimedByOtherPratiche: claimed
        )
        context.controller.updateTray(
            PraticaTrayModel.proposals(from: tray, ownAddresses: Set(context.settings.ownAddresses)),
            for: context.praticaPath, in: vault
        )
    }

    // MARK: - «Rigenera» (ADR §D21)

    /// §D21.1: publishes a fresh store copy, then asks the engine to acquire the
    /// replacement text and diff it - nothing is trashed or written yet. The engine is
    /// kept in `regenerationEngine` for `commitRegeneration` below, since it is the
    /// one thing that must not be re-derived between preview and commit.
    func prepareRegeneration(praticaPath: String, messageID: String) async {
        guard let controller, let session = vault.session, let root = vault.root else { return }
        let settings = vault.settings.pratiche
        guard let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root) else {
            controller.report("«\(praticaPath)» non ha un dossier leggibile in pratica.md.")
            controller.regeneration = nil
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
            guard vault.session === session else { return }
            controller.regeneration = .ready(plan)
        } catch {
            guard vault.session === session else { return }
            controller.regeneration = nil
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
            return false
        }
        do {
            let outcome = try await engine.commitRegeneration(plan)
            controller.recordSyncOutcome(
                outcome, for: plan.praticaFolder, session: session, isCurrentVault: vault.session === session
            )
            return true
        } catch {
            guard vault.session === session else { return false }
            controller.report(Self.regenerationFailureMessage(error))
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

    /// R-13's `claimedByOtherPratiche`: every conversation any *other* pratica already
    /// follows, read from the files rather than from the index, for the same reason
    /// `PraticheController.dossier(at:vaultRoot:)` does - a sync acts on the dossier as
    /// it is now, not as the last scan saw it.
    private static func conversationsClaimedByOtherPratiche(
        than praticaPath: String, among pratiche: [PraticaListItem], vaultRoot: URL
    ) -> Set<Int> {
        var claimed: Set<Int> = []
        for pratica in pratiche where pratica.id != praticaPath {
            guard let dossier = PraticheController.dossier(at: pratica.id, vaultRoot: vaultRoot)
            else { continue }
            claimed.formUnion(dossier.conversations)
        }
        return claimed
    }
}
