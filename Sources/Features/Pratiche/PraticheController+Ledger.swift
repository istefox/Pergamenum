import Foundation

extension PraticheController {
    /// What a finished sync found waiting for this pratica (R-30). Also refreshes the
    /// list, since the dot on a row is one of these counts.
    func updateTray(
        _ proposals: [PraticaTrayModel.PraticaTrayProposal],
        for praticaPath: String,
        in vault: VaultController
    ) {
        trayProposals[praticaPath] = proposals
        trayCounts[praticaPath] = proposals.count
        persistTrayCount(proposals.count, for: praticaPath, in: vault)
        pratiche = Self.listItems(
            in: vault, ledger: ledger, trayCounts: trayCounts,
            rootFolder: vault.settings.pratiche.rootFolder
        )
    }

    /// Writes the tray's own count into the ledger (`PraticaLedger.PraticaState.
    /// trayCount`, Task 9's widening).
    ///
    /// `trayCounts` alone lives for as long as this window does, and R-36 forbids
    /// `VaultAPI.pratiche(_:)` from opening the Mail store to recount: without this
    /// line a re-launched `perg`/`pergamenum-mcp` could only ever answer `0`, which
    /// reads as «niente da smistare» rather than as «nessuno ha ancora guardato».
    ///
    /// Skipped when nothing changed, so a sync that finds the same proposals again
    /// does not rewrite the file - and, for a pratica with no tray and no ledger entry
    /// yet, does not create one to say zero.
    private func persistTrayCount(_ count: Int, for praticaPath: String, in vault: VaultController) {
        guard let session = vault.session else { return }
        var state = ledger.byPraticaPath[praticaPath] ?? .empty
        guard state.trayCount != count else { return }
        state.trayCount = count
        ledger.byPraticaPath[praticaPath] = state
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    /// «Aggiungi» and «Ignora» both take the row off the strip at once: the write that
    /// makes it stay away has already happened, and a row that lingers until the next
    /// sync reads as a button that did nothing.
    func dismissTrayProposal(_ conversationID: Int, for praticaPath: String, in vault: VaultController) {
        let remaining = (trayProposals[praticaPath] ?? []).filter { $0.conversationID != conversationID }
        updateTray(remaining, for: praticaPath, in: vault)
    }

    // MARK: - Reading the vault

    /// Rebuilds the list from the index and re-reads the ledger. Cheap enough to call
    /// from the pane's `.task` and after every sync: it walks the index this app
    /// already keeps, and reads exactly one JSON file.
    func load(from vault: VaultController) {
        guard let session = vault.session else {
            pratiche = []
            timeline = []
            details = [:]
            ledger = .empty
            return
        }
        ledger = PraticaLedger.load(from: Self.ledgerURL(for: session))
        pratiche = Self.listItems(
            in: vault, ledger: ledger, trayCounts: trayCounts,
            rootFolder: vault.settings.pratiche.rootFolder
        )
        if let selection, !pratiche.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
        reloadTimeline(from: vault)
    }

    /// Choosing a row: reads its timeline and marks it opened, which is what makes the
    /// badge go out (R-33 - the count is "since `lastOpenedAt`").
    func select(_ praticaPath: String?, in vault: VaultController) {
        selection = praticaPath
        expansion = PraticaTimelineModel.ExpansionState()
        if let praticaPath { markOpened(praticaPath, in: vault) }
        reloadTimeline(from: vault)
        pratiche = Self.listItems(
            in: vault, ledger: ledger, trayCounts: trayCounts,
            rootFolder: vault.settings.pratiche.rootFolder
        )
    }

    func reloadTimeline(from vault: VaultController) {
        guard let selection, let root = vault.root else {
            timeline = []
            details = [:]
            return
        }
        let read = Self.readTimeline(
            praticaPath: selection,
            vaultRoot: root,
            // R-26: which messages have left Mail is ledger state, not something the
            // folder on disk can say - a message deleted from Mail keeps its file.
            notInStore: Set(ledger.byPraticaPath[selection]?.notInStore ?? [])
        )
        timeline = PraticaTimelineModel.ordered(read.entries)
        details = read.details
    }

    private func markOpened(_ praticaPath: String, in vault: VaultController) {
        guard let session = vault.session else { return }
        var state = ledger.byPraticaPath[praticaPath] ?? .empty
        state.lastOpenedAt = Date()
        ledger.byPraticaPath[praticaPath] = state
        // A ledger that will not save costs one badge, not a pratica: reported, never
        // thrown at the person reading their mail.
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    // MARK: - What a running sync reports back

    func beginSync(_ praticaPath: String) {
        syncingPraticaPath = praticaPath
        syncProgress = nil
        problem = nil
    }

    func updateProgress(_ progress: PraticaSyncEngine.Progress) {
        syncProgress = progress
    }

    func endSync() {
        syncingPraticaPath = nil
        syncProgress = nil
    }

    func report(_ message: String) {
        problem = message
    }

    /// Records what a finished sync imported, so the next one resumes instead of
    /// starting over (R-11).
    ///
    /// `isCurrentVault` (`vault.session === session`, decided by the caller - this type
    /// holds no `VaultController` to check it itself) says whether `session` is still
    /// the live vault. When it is not, this reads and rewrites `session`'s OWN ledger
    /// file fresh from disk instead of `self.ledger`: that property tracks whichever
    /// vault is live right now, and merging a stale sync's outcome into a DIFFERENT
    /// vault's in-memory ledger before saving it back under `session`'s own path would
    /// write that other vault's entries into this one's file - a real cross-vault
    /// corruption, not a UI-only glitch.
    func recordSyncOutcome(
        _ outcome: PraticaSyncEngine.SyncOutcome, for praticaPath: String, session: VaultSession,
        isCurrentVault: Bool
    ) {
        let url = Self.ledgerURL(for: session)
        var sessionLedger = isCurrentVault ? ledger : PraticaLedger.load(from: url)
        var state = sessionLedger.byPraticaPath[praticaPath] ?? .empty
        state.lastSyncAt = Date()
        var imported = Set(state.importedMessageIDs)
        imported.formUnion(outcome.importedMessageIDs)
        state.importedMessageIDs = imported.sorted()
        // R-16: what this run found gone from Mail joins what earlier runs found, and
        // what it imported again leaves the list - a message that came back (a mailbox
        // put back, an archive re-indexed) gets its link back with it.
        var gone = Set(state.notInStore)
        gone.formUnion(outcome.noLongerInMail)
        gone.subtract(outcome.importedMessageIDs)
        state.notInStore = gone.sorted()
        // §D23.2: the §D3 bridge, keyed by Message-ID so a regeneration's fresh triple
        // replaces the stale one rather than appending a second - newest wins because
        // Mail renumbers ROWIDs on an index rebuild, and a stale ROWID is worse than
        // none (`forgetImportedMessage`'s own reason). Sorted because `PraticaLedger.save`
        // pretty-prints with `.sortedKeys`, so the file stays diffable by hand.
        var entriesByID = Dictionary(
            state.entries.map { ($0.messageID, $0) }, uniquingKeysWith: { _, new in new }
        )
        for entry in outcome.bridge { entriesByID[entry.messageID] = entry }
        state.entries = entriesByID.values.sorted { $0.messageID < $1.messageID }
        sessionLedger.byPraticaPath[praticaPath] = state
        do {
            try sessionLedger.save(to: url)
        } catch {
            if isCurrentVault {
                problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
            }
        }
        // The observable property is this controller's view of the LIVE vault - never
        // updated on behalf of a vault that is no longer the one open.
        if isCurrentVault {
            ledger = sessionLedger
            // ADR-0040 §D10/§D7.3: what this run's attachment repair pass could not
            // fix - a file it could not trash, a downgrade it could not write. Empty
            // on every healthy run.
            if !outcome.attachmentProblems.isEmpty {
                problem = [problem, outcome.attachmentProblems.joined(separator: "\n")]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            }
        }
    }

    /// «Rinomina» (R-34) moves the folder, and the ledger is keyed by the folder's
    /// path: without this the renamed pratica reads as one nobody has ever synced,
    /// and the next sync re-imports every message it already has on disk.
    ///
    /// The tray counts travel too, or the dot on the row goes out for no reason a
    /// person could name (R-33).
    func moveLedgerState(from oldPath: String, to newPath: String, in vault: VaultController) {
        guard oldPath != newPath else { return }
        if let state = ledger.byPraticaPath.removeValue(forKey: oldPath) {
            ledger.byPraticaPath[newPath] = state
        }
        if let proposals = trayProposals.removeValue(forKey: oldPath) {
            trayProposals[newPath] = proposals
        }
        if let count = trayCounts.removeValue(forKey: oldPath) {
            trayCounts[newPath] = count
        }
        if selection == oldPath { selection = newPath }
        guard let session = vault.session else { return }
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    /// §D23.4: Mail renumbered a followed conversation Mail's own way (a new
    /// `conversation_id` recovered from a member `Message-ID`'s still-known row) - the
    /// ledger's own triples have to be repointed too, or the next sync's
    /// `memberMessageIDs(forConversation:)` answers nothing for the new id and the
    /// pratica silently loses its recovery data one renumbering later.
    ///
    /// Declared here (ADR-0155 §D1); the coder wires the body (§D23.4's repointing,
    /// called from `PraticaLiveSync.runExclusive` before candidates are evaluated).
    func remapLedgerConversations(_ remap: [Int: Int], of praticaPath: String, in vault: VaultController) {
        guard !remap.isEmpty, var state = ledger.byPraticaPath[praticaPath] else { return }
        state.entries = state.entries.map { entry in
            guard let newID = remap[entry.conversationID] else { return entry }
            return PraticaLedger.Entry(
                messageID: entry.messageID, rowID: entry.rowID, conversationID: newID
            )
        }
        ledger.byPraticaPath[praticaPath] = state
        guard let session = vault.session else { return }
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    // MARK: - Paths

    static func ledgerURL(for session: VaultSession) -> URL {
        stateDirectory(for: session).appending(path: ledgerFileName, directoryHint: .notDirectory)
    }

    /// `…/vaults/<id>/pratiche/` - the copy of the Envelope Index and the ledger both
    /// live here (SPEC "Per-vault state"), never inside the vault.
    static func stateDirectory(for session: VaultSession) -> URL {
        session.state.directory.appending(path: stateDirectoryName, directoryHint: .isDirectory)
    }
}
