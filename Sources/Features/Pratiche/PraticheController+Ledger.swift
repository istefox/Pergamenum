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
        pruneRedirectsIfIdle()
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
        // A relocation that ran on the main actor while this outcome's own sync was
        // still in flight has already moved the ledger key out from under
        // `praticaPath` (`moveLedgerState`, below) - only meaningful against `self`
        // when this outcome belongs to the vault that redirect map describes.
        let currentPath = isCurrentVault ? resolvePraticaPathRedirect(praticaPath) : praticaPath
        var sessionLedger = isCurrentVault ? ledger : PraticaLedger.load(from: url)
        var state = sessionLedger.byPraticaPath[currentPath] ?? .empty
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
        sessionLedger.byPraticaPath[currentPath] = state
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

    /// A folder move or rename (R-34's «Rinomina», or the generic ADR-0026 batch move/
    /// rename path) orphans every path-keyed piece of Pratiche state unless it follows:
    /// the ledger is keyed by the pratica folder's own path, and a pratica does not
    /// have to be the moved item itself to be carried along - it can be a descendant of
    /// a moved or renamed *ancestor* folder (the actual bug this fixes, PG "allegati non
    /// si scaricano"). Subtree-aware for exactly that reason: every key equal to
    /// `oldPath` OR nested inside it moves to the same relative position under
    /// `newPath`, one call covering both the pratica-itself and the
    /// pratica-is-a-descendant shapes.
    ///
    /// The tray counts, the selection, the per-pratica watcher and an in-flight sync's
    /// or regeneration's own path all travel too, or each detaches from the moved
    /// pratica on its own: a stale watcher never fires for the new path. Remapping
    /// `syncingPraticaPath`/`regeneratingPraticaPaths` only keeps what the UI shows in
    /// step with reality, though - it is `praticaPathRedirects` that actually stops an
    /// in-flight sync's or regeneration's completion from resurrecting the orphaned key:
    /// `recordSyncOutcome` was found (by review) to write unconditionally under the path
    /// it was called with, captured before its own `await`s and never re-read from
    /// `syncingPraticaPath` (ADR-0026 §D7, ADR-0043 §D7's shape again).
    ///
    /// Review round 2 found two MINORs in that redirect map and both are fixed here:
    /// a redirect entry is now recorded only for a key `isInFlight` finds actually
    /// claimed by `syncingPraticaPath` or `regeneratingPraticaPaths` at this exact
    /// moment (MINOR 1 - most relocations run with nothing syncing or regenerating and
    /// now add zero entries, closing the unconditional per-relocation growth); and
    /// `resolvePraticaPathRedirect` (below) no longer removes what it reads, so two
    /// concurrent in-flight callers sharing the same pre-move path both resolve
    /// correctly instead of the first consuming the entry out from under the second
    /// (MINOR 2). Nothing here needs a `selection` redirect: `recordSyncOutcome` only
    /// ever resolves a path a sync or regeneration itself captured, never the UI's own
    /// selection.
    func moveLedgerState(from oldPath: String, to newPath: String, in vault: VaultController) {
        guard oldPath != newPath else { return }
        // Snapshotted before any of the remaps below touch `syncingPraticaPath`/
        // `regeneratingPraticaPaths` themselves, so this still reads their PRE-move
        // values while every one of the following calls is still relocating `oldPath`.
        let isInFlight: (String) -> Bool = { [syncingPraticaPath, regeneratingPraticaPaths] path in
            path == syncingPraticaPath || regeneratingPraticaPaths.contains(path)
        }
        Self.remapKeys(&ledger.byPraticaPath, from: oldPath, to: newPath, redirects: &praticaPathRedirects, isInFlight: isInFlight)
        Self.remapKeys(&trayProposals, from: oldPath, to: newPath, redirects: &praticaPathRedirects, isInFlight: isInFlight)
        Self.remapKeys(&trayCounts, from: oldPath, to: newPath, redirects: &praticaPathRedirects, isInFlight: isInFlight)
        Self.remapKeys(&watchersByPraticaPath, from: oldPath, to: newPath, redirects: &praticaPathRedirects, isInFlight: isInFlight)
        if let selection, let remapped = Self.remappedPath(selection, from: oldPath, to: newPath) {
            self.selection = remapped
        }
        if let syncingPraticaPath, let remapped = Self.remappedPath(syncingPraticaPath, from: oldPath, to: newPath) {
            self.syncingPraticaPath = remapped
            // Independent of the `ledger.byPraticaPath` remap above: a pratica's very
            // first sync has no ledger entry yet (`state ... ?? .empty` never inserts
            // one), so that remap alone would not have seen this key.
            praticaPathRedirects[syncingPraticaPath] = remapped
        }
        if !regeneratingPraticaPaths.isEmpty {
            var remappedRegenerations: Set<String> = []
            for path in regeneratingPraticaPaths {
                if let remapped = Self.remappedPath(path, from: oldPath, to: newPath) {
                    praticaPathRedirects[path] = remapped
                    remappedRegenerations.insert(remapped)
                } else {
                    remappedRegenerations.insert(path)
                }
            }
            regeneratingPraticaPaths = remappedRegenerations
        }
        guard let session = vault.session else { return }
        do { try ledger.save(to: Self.ledgerURL(for: session)) } catch {
            problem = "Non è stato possibile aggiornare il registro delle pratiche: \(error.localizedDescription)"
        }
    }

    /// The one place `VaultController.didRelocateFolders` calls into (ADR-0026 §D7,
    /// wired by `PergamenumApp.init`): one call per folder the batch moved or renamed,
    /// covering forward moves, renames of an ancestor folder, and undo/redo alike,
    /// since all three fold into the same `MovedNote` shape upstream.
    func followFolderRelocations(_ moved: [MovedNote], in vault: VaultController) {
        for relocation in moved {
            moveLedgerState(from: relocation.old, to: relocation.new, in: vault)
        }
    }

    /// `path` itself, or `path` remapped to sit under `newPath` when it was nested
    /// inside `oldPath` - `nil` when `path` is neither, meaning it is untouched by this
    /// relocation. The prefix is `"\(oldPath)/"` and never the bare path,
    /// `VaultMoveBatch.plan`'s own convention (`VaultMoveBatch.swift:63-70`) to avoid
    /// mistaking `a-altro` for a descendant of `a`.
    private static func remappedPath(_ path: String, from oldPath: String, to newPath: String) -> String? {
        if path == oldPath { return newPath }
        if path.hasPrefix("\(oldPath)/") { return newPath + path.dropFirst(oldPath.count) }
        return nil
    }

    /// The dictionary-keyed twin of `remappedPath`: every key equal to or nested inside
    /// `oldPath` moves to its equivalent key under `newPath`, same value, everything
    /// else untouched. Records the move into `redirects[key] = remapped` only when
    /// `isInFlight(key)` says something could still present `key` as its own captured
    /// pre-move path (review round 2, MINOR 1) - a relocation with nothing syncing or
    /// regenerating for `key` leaves no redirect at all, since nothing will ever read it.
    ///
    /// The `dict[remapped] = value` assignment overwrites rather than merges whatever
    /// already sat at `remapped` (MINOR flagged by review) - left as-is on purpose: a
    /// real relocation lands `remapped` on a path the move just vacated, so a
    /// collision here would mean two distinct folders resolved to the same key, a
    /// state this generic helper has no `Value`-specific way to merge or even detect.
    private static func remapKeys<Value>(
        _ dict: inout [String: Value], from oldPath: String, to newPath: String,
        redirects: inout [String: String], isInFlight: (String) -> Bool
    ) {
        for key in Array(dict.keys) {
            guard let remapped = remappedPath(key, from: oldPath, to: newPath) else { continue }
            guard let value = dict.removeValue(forKey: key) else { continue }
            dict[remapped] = value
            if isInFlight(key) { redirects[key] = remapped }
        }
    }

    /// `praticaPath` as some in-flight caller captured it, resolved to wherever a
    /// relocation moved its ledger key by the time the caller's own outcome arrives -
    /// itself when no relocation ever touched it. Walks more than one hop only when the
    /// same pratica was relocated twice before that outcome landed.
    ///
    /// Never mutates `praticaPathRedirects` (review round 2, MINOR 2): the old
    /// `removeValue` read let the FIRST of two concurrent in-flight callers sharing the
    /// same pre-move path (an ordinary sync and a "Rigenera…" commit can race each
    /// other for the same pratica - `PraticaLiveSync`'s `SyncRunQueue` only serializes
    /// ordinary syncs against each other) consume the entry, leaving the second to fall
    /// through to the stale key and resurrect it. `endSync`/`endRegeneration` are what
    /// eventually drop an entry, once nothing anywhere is still in flight to need it
    /// (`pruneRedirectsIfIdle`, below) - never a single read.
    private func resolvePraticaPathRedirect(_ praticaPath: String) -> String {
        var current = praticaPath
        var visited: Set<String> = [praticaPath]
        while let next = praticaPathRedirects[current], visited.insert(next).inserted {
            current = next
        }
        return current
    }

    // MARK: - «Rigenera…»'s own in-flight marker (review round 2)

    /// Claims `praticaPath` for a «Rigenera…» attempt (ADR §D21) - called once, from
    /// `PraticaLiveSync.prepareRegeneration`, before its first `await`. Matched by
    /// exactly one `endRegeneration` call on every exit that will not itself call
    /// `recordSyncOutcome`, or the claim never releases.
    ///
    /// Review round 3's one exception: an attempt `prepareRegeneration` finds superseded
    /// on resuming from its `await` (`regenerationEngine` now points at a *later*
    /// attempt's engine) drops its result WITHOUT calling `endRegeneration` - not a
    /// leaked claim, since a supersession only happens after «Annulla» already released
    /// this attempt's own claim through `dismissRegeneration` below, and the shared
    /// `praticaPath` key it briefly held may by then belong to that later attempt.
    func beginRegeneration(_ praticaPath: String) {
        regeneratingPraticaPaths.insert(praticaPath)
    }

    /// Releases a claim `beginRegeneration` made. Resolves `praticaPath` (the caller's
    /// own, possibly stale, captured value) through the same redirect chain
    /// `recordSyncOutcome` reads, since a relocation mid-regeneration keeps
    /// `regeneratingPraticaPaths` itself live-updated to the CURRENT path
    /// (`moveLedgerState`, above), not the value this call was made with.
    func endRegeneration(_ praticaPath: String) {
        regeneratingPraticaPaths.remove(resolvePraticaPathRedirect(praticaPath))
        pruneRedirectsIfIdle()
    }

    /// «Annulla»/«Chiudi» on the «Rigenera…» sheet (`PratichePane+Sheets.swift`),
    /// before any commit runs: releases whichever pratica this attempt claimed, then
    /// dismisses the sheet - the one UI-facing caller of `endRegeneration`, since every
    /// other exit already has its own praticaPath in scope directly.
    func dismissRegeneration() {
        switch regeneration {
        case .preparing(_, _, let praticaPath): endRegeneration(praticaPath)
        case .ready(let plan): endRegeneration(plan.praticaFolder)
        case nil: break
        }
        regeneration = nil
    }

    /// Review round 2, MINOR 2's other half: since `resolvePraticaPathRedirect` never
    /// removes what it reads, nothing prunes `praticaPathRedirects` on a per-entry
    /// basis. The whole map is safe to drop in one go the moment NOTHING is in flight
    /// anywhere - `syncingPraticaPath == nil && regeneratingPraticaPaths.isEmpty` -
    /// since every entry in it exists only because `moveLedgerState` found something in
    /// flight for that key at the time (MINOR 1), and nothing left running means every
    /// caller that could have needed one has already resolved through it. Called from
    /// `endSync` and `endRegeneration`, the two places that can make this true.
    private func pruneRedirectsIfIdle() {
        guard syncingPraticaPath == nil, regeneratingPraticaPaths.isEmpty else { return }
        praticaPathRedirects.removeAll()
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
