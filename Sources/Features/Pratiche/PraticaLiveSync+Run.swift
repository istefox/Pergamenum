import Foundation

// ADR-0045 §D2/PG-160: `PraticaLiveSync`'s `runExclusive` pipeline, split out verbatim
// once the class body crossed `type_body_length`'s own warning line. Pure move, no
// behaviour change.

extension PraticaLiveSync {
    /// The values one `runExclusive` run threads through its five extracted steps.
    /// Bundled rather than passed loose: `session`, `root` and `controller` are the
    /// exact instances captured by `runExclusive`'s own top-of-function `guard let`,
    /// not re-read from `self.vault`/`self.controller`, because the live vault can
    /// change under a `Task.detached` suspension mid-run and every step must keep
    /// acting on the vault THIS run started against (this file's own established
    /// `vault.session === session` guard shape).
    @MainActor
    private struct RunContext {
        /// Renamed from `praticaPath` (round-4 review, §1) and made `private`: after
        /// this rename there is no way to spell a pratica path inside this pipeline
        /// other than through `livePraticaPath(in:)` below - the guards this whole
        /// chain needs then land at every point of use automatically, rather than
        /// being hand-placed and therefore forgettable at a future sixth `await`.
        private var capturedPraticaPath: String
        var session: VaultSession
        var root: URL
        var settings: PraticheSettings
        var controller: PraticheController

        init(
            praticaPath: String, session: VaultSession, root: URL,
            settings: PraticheSettings, controller: PraticheController
        ) {
            self.capturedPraticaPath = praticaPath
            self.session = session
            self.root = root
            self.settings = settings
            self.controller = controller
        }

        /// The ONLY way a step in this pipeline obtains the pratica folder it may
        /// touch (round-4 review, §1): both facts a step needs, behind one call.
        /// Session identity is checked FIRST, because `praticaPathRedirects`
        /// describes the LIVE vault only - `load(from:)` never clears it on a vault
        /// switch (§6), so consulting it against a captured path from a vault that is
        /// no longer live could resolve through some OTHER vault's own relocations by
        /// pure coincidence. When the vault has changed, this returns the path exactly
        /// as captured instead of throwing: a vault switch is this pipeline's own
        /// separate, long-standing concern, already handled by the
        /// `vault.session === session` checks each step carries where it actually
        /// matters (`runEngine`'s own doc comment - "a vault switch mid-sync can never
        /// leave a completed import unrecorded"). A relocation is a fact about THIS
        /// vault alone, and is the only thing this door ever refuses.
        func livePraticaPath(in vault: VaultController) throws -> String {
            guard vault.session === session else { return capturedPraticaPath }
            return try controller.praticaPath(continuing: capturedPraticaPath)
        }
    }

    /// Not `private`: `PraticaLiveSync.swift`'s `run(praticaPath:kind:)` is in a
    /// separate file, and is this member's only caller.
    func runExclusive(praticaPath: String) async -> RunOutcome {
        guard let controller, let session = vault.session, let root = vault.root else { return .finished }
        guard let dossier = PraticheController.dossier(at: praticaPath, vaultRoot: root) else {
            controller.report("«\(praticaPath)» non ha un dossier leggibile in pratica.md.")
            return .finished
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

        // Round-4 review, §1 (prerequisite): moved up from right before the detached
        // `prepare` call below, so the claim brackets the WHOLE of this function.
        // `praticaPath(continuing:)` is only meaningful while a claim is held -
        // `moveLedgerState` records a redirect only for a key `isInFlight` finds
        // actually claimed, and `pruneRedirectsIfIdle` wipes the whole map the moment
        // nothing anywhere is still claimed. Behaviour change on the happy path: nil.
        controller.beginSync(praticaPath)
        defer { controller.endSync() }

        do {
            let outcome = await Task.detached(priority: .utility) {
                MailStorePreparation.prepare(
                    mailRoot: mailRoot, stateDirectory: stateDirectory,
                    dossier: dossier, ledgerEntries: state.entries, proposalWindow: window
                )
            }.value

            // The one hand-placed guard (round-4 review, §2): right after the detached
            // preparation above returns and before `switch outcome` even runs, so
            // nothing below is derived from a copy built for a pratica that has since
            // moved. Every other guard in this pipeline lands automatically, inside
            // the steps themselves, through `livePraticaPath(in:)`.
            _ = try context.livePraticaPath(in: vault)

            let prepared: MailStorePreparation.Prepared
            switch outcome {
            case .ready(let value): prepared = value
            case .failed(let message):
                controller.report(message)
                return .finished
            }

            var effectiveDossier = try await applyConversationRemap(prepared, dossier: dossier, context: context)
            reportPreparationProblems(prepared, controller: controller)

            let evaluated = try await evaluateCandidates(
                dossier: effectiveDossier, prepared: prepared, onDisk: onDisk, context: context
            )
            effectiveDossier = evaluated.dossier

            guard try await runEngine(
                dossier: effectiveDossier, candidates: evaluated.candidates.messages, onDisk: onDisk,
                ledgerEntries: state.entries, indexURL: prepared.indexURL, context: context
            ) else { return .finished }

            try refreshTray(effectiveDossier: effectiveDossier, prepared: prepared, window: window, claimed: claimed, context: context)
            return .finished
        } catch let stop as PraticaRunStop {
            // PG-168: raised here and nowhere earlier because here the writer is provably
            // finished - `engine.sync` has returned - so a directory still standing at the
            // vacated path is a fact, not a race. Reported, never touched.
            if let leftover = PraticaRunStop.leftoverNotice(after: stop),
               FileManager.default.fileExists(
                   atPath: root.appending(path: leftover.path, directoryHint: .isDirectory).path(percentEncoded: false)
               ) {
                controller.report(leftover.sentence)
            }
            switch stop {
            case .vaultChanged:
                return .finished
            case .praticaRelocated(_, let to):
                return .relocated(to: to)
            case .praticaTrashed:
                // PG-169: `.finished`, never `.relocated(to:)` - that drives `Self.requeue`,
                // and a re-enqueued run for a trashed pratica would only dequeue into the
                // «non ha un dossier leggibile in pratica.md» report above.
                return .finished
            }
        } catch {
            // Every step below only ever throws `PraticaRunStop` - its own errors
            // (a write refusal, a decode failure) are already caught and reported
            // where they happen. Kept for exhaustiveness, not because this is expected
            // to run.
            return .finished
        }
    }

    /// §D23.4: repoint the ledger and the dossier together, before candidates are
    /// evaluated, so this run already imports through the renumbered id rather than
    /// waiting for a later sync to notice.
    private func applyConversationRemap(
        _ prepared: MailStorePreparation.Prepared, dossier: Dossier, context: RunContext
    ) async throws -> Dossier {
        var effectiveDossier = dossier
        guard !prepared.conversationRemap.isEmpty else { return effectiveDossier }
        // Resolved OUTSIDE the `do` below (round-4 review, §2): a `PraticaRunStop` must
        // propagate to `runExclusive`'s own catch, not be swallowed by the catch-all
        // just below, which exists for `session.read`/`session.write`'s own errors.
        // PG-168's third case: no re-check after the `session.write` below, and none is
        // needed. It passes `expecting: record.contentHash`, `VaultDisk.write` compares that
        // against the bytes it reads itself inside the actor, and a note that moved with its
        // folder reads back as nothing - so a relocation landing during the write is refused
        // with `movedOn`, never landed at the vacated path.
        let praticaPath = try context.livePraticaPath(in: vault)
        let notePath = PraticaNaming.praticaNotePath(of: praticaPath)
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
                // Round-4 review, §6: the ledger is repointed only once the note write
                // above has actually succeeded, never before it and never on a catch
                // path. Doing it first (as this used to) left the ledger holding the
                // new id and the dossier the old one whenever the write was refused or
                // threw - `MailStorePreparation.resolveFollowedConversations` recovers
                // a renumbering by filtering `ledgerEntries` for the OLD id, which is
                // then empty and never retried, a permanent silent loss unrelated to
                // relocation. All-or-nothing keeps the failure retriable instead.
                // The run's own session, and whether it is still the live one, read HERE after the
                // `await` above and not before it (ADR-0052 §D7, ADR-0043 §D7): a vault switch in
                // that window sends the repointing to this session's own file.
                context.controller.remapLedgerConversations(
                    prepared.conversationRemap, of: praticaPath,
                    session: context.session, isCurrentVault: vault.session === context.session
                )
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
    ) async throws -> (dossier: Dossier, candidates: MembershipRule.Candidates) {
        var effectiveDossier = dossier
        var candidates = MembershipRule.candidates(
            dossier: effectiveDossier, store: prepared.snapshot, onDisk: onDisk
        )
        if !candidates.autoFollowedConversations.isEmpty {
            for conversation in candidates.autoFollowedConversations {
                effectiveDossier = PraticaTrayModel.following(conversationID: conversation, in: effectiveDossier)
            }
            // Round-4 review, §2: resolved immediately before the write it guards.
            // PG-168's third case: no re-check after the await, and none is needed - the
            // write goes through `DossierWriter.update`'s `expecting:`, refused after a move
            // exactly as `applyConversationRemap`'s is above.
            let praticaPath = try context.livePraticaPath(in: vault)
            await DossierWriter.update(at: praticaPath, session: context.session) { $0 = effectiveDossier }
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
        dossier: Dossier, candidates: [MailMessageRow], onDisk: Set<String>,
        ledgerEntries: [PraticaLedger.Entry], indexURL: URL, context: RunContext
    ) async throws -> Bool {
        let session = context.session
        // Round-4 review, §2: resolved before building `SyncRequest` below - the
        // largest of the six damaged consumers (context, §D6 of the plan): this folder
        // is what the engine writes every message `.md` and attachment into for the
        // whole of `engine.sync` below, and `SyncRequest.praticaFolder` is frozen for
        // that entire call.
        let praticaPath = try context.livePraticaPath(in: vault)
        let engine = PraticaSyncEngine(mailStoreURL: indexURL, vaultRoot: context.root) { text, path, expecting in
            // PG-168: never recreate the folder a relocation or a trash has just vacated -
        // the engine's only door onto a note, so this holds for every write it will ever make.
        _ = try await session.write(text, to: path, expecting: expecting, requiringExistingFolder: true)
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
                praticaFolder: praticaPath,
                dossier: dossier,
                candidates: candidates,
                onDisk: onDisk,
                settings: context.settings,
                ledgerEntries: ledgerEntries
            ))
            // Round-4 review, §5 (the one contested decision): resolved again here,
            // AFTER `engine.sync` returns - a relocation landing mid-sync leaves some
            // messages written before the move (they travelled with the folder) and at
            // most one after it (stranded under the vacated path), so this partial
            // `SyncOutcome` mixes two truths. Recording it would put the stranded
            // message into `importedMessageIDs` under the NEW key and make it silently
            // missing forever - the next sync's `onDisk` would then exclude it from
            // `MembershipRule.candidates`, and it is never re-imported. Discarding
            // costs only re-derivable work: everything already on disk is decoded and
            // skipped by the next sync, and this run's own bridge/`notInStore`
            // findings are recomputed by it. Never a missing message - do not "fix"
            // this back to recording a partial outcome.
            //
            // A `PraticaRunStop` here is rethrown, not folded into the two catch arms
            // below: their `vault.session === session` guards stay exactly as they
            // are, because their consequence differs from this one - a vault switch
            // still records (this call's own `isCurrentVault` flag is what already
            // keeps THAT safe), a relocation never does.
            let currentPraticaPath = try context.livePraticaPath(in: vault)
            // The vault open when this run started may no longer be the one open now
            // (a person can switch vaults mid-sync): the files above were written
            // through the SESSION captured at the top of this function, which is
            // correct, and so is this ledger write - `recordSyncOutcome` takes the
            // captured `session` explicitly and persists into ITS OWN ledger file
            // regardless of what is live, so a vault switch mid-sync can never leave a
            // completed import unrecorded OR bleed into whatever vault is live now.
            context.controller.recordSyncOutcome(
                result, for: currentPraticaPath, session: session, isCurrentVault: vault.session === session
            )
        } catch let stop as PraticaRunStop {
            throw stop
        } catch let refusal as VaultSession.WriteRefusal {
            // PG-168: a write refused because the folder it was about to land in is gone is
            // usually the relocation or the trash this run is being stopped for, not a failure
            // - and reporting «Sincronizzazione non riuscita» over a run that is about to
            // requeue itself would announce one that did not happen. Asking the live path
            // first throws the `PraticaRunStop` that `runExclusive`'s ladder turns into a
            // requeue or a quiet finish, and the partial outcome is never recorded. Only when
            // nothing relocated it (the folder was deleted from outside the app) does this fall
            // through to the report.
            if case .folderVanished = refusal { _ = try context.livePraticaPath(in: vault) }
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
    ) throws {
        // Round-4 review, §2: resolved before `dossier(at:)` - this is the guard that
        // closes `persistTrayCount`'s re-insertion at the vacated path, the worst of
        // the six damaged consumers (it recreates the very defect this whole chain
        // exists to fix).
        let praticaPath = try context.livePraticaPath(in: vault)
        let followed = PraticheController.dossier(at: praticaPath, vaultRoot: context.root) ?? effectiveDossier
        let tray = MembershipRule.trayCandidates(
            dossier: followed,
            store: prepared.snapshot,
            window: window,
            claimedByOtherPratiche: claimed
        )
        context.controller.updateTray(
            PraticaTrayModel.proposals(from: tray, ownAddresses: Set(context.settings.ownAddresses)),
            for: praticaPath, in: vault
        )
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
