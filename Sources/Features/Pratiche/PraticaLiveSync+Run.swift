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
    private struct RunContext {
        var praticaPath: String
        var session: VaultSession
        var root: URL
        var settings: PraticheSettings
        var controller: PraticheController
    }

    /// Not `private`: `PraticaLiveSync.swift`'s `run(praticaPath:kind:)` is in a
    /// separate file, and is this member's only caller.
    func runExclusive(praticaPath: String) async {
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
            ledgerEntries: state.entries, indexURL: prepared.indexURL, context: context
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
        dossier: Dossier, candidates: [MailMessageRow], onDisk: Set<String>,
        ledgerEntries: [PraticaLedger.Entry], indexURL: URL, context: RunContext
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
                settings: context.settings,
                ledgerEntries: ledgerEntries
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
