import Foundation

/// Round-4 review (follow-up to `ba09c06`, `docs/plans/pg-pratica-relocation-mid-sync-
/// stop.md`): why a run must STOP rather than adapt once its own pratica folder has
/// moved out from under it - `PraticaLiveSync+Run.swift`'s `RunContext.livePraticaPath(
/// in:)` is the door every step goes through, and this is what it throws.
enum PraticaRunStop: Error, Equatable, Sendable {
    /// The vault open when a run started is no longer the one live now - a genuinely
    /// different concern from a relocation (this pipeline tolerates a vault switch:
    /// see `PraticaLiveSync+Run.swift`'s `runEngine`), thrown only where continuing to
    /// derive state from a preparation built for a vault nobody is looking at any more
    /// would be pure waste.
    case vaultChanged
    /// The pratica folder a run captured has moved WITHIN the same vault: `from` is
    /// what the run captured, `to` is where `praticaPathRedirects` says it lives now -
    /// carried because the caller that must stop is the caller that must ask for a
    /// fresh run at `to` (§3 of the plan above).
    case praticaRelocated(from: String, to: String)
    /// The pratica folder a run captured, or an ancestor of it, went to the Trash while the
    /// run was still in flight (PG-169, ADR-0026 §D7's 2026-09-19 amendment) - the deletion
    /// twin of `.praticaRelocated`. `path` is what the run captured. It carries no
    /// destination because there is none, and `runExclusive` maps it to `.finished`, never
    /// to `.relocated(to:)`: a re-enqueued run for a trashed pratica would only dequeue into
    /// the «non ha un dossier leggibile» report.
    case praticaTrashed(path: String)
}

/// What `PraticaLiveSync.commitRegeneration` tells `PraticaCommandActions.confirmRegeneration`
/// to do about the files it has already trashed. Not a `Bool`: a `Bool` cannot say "already
/// reported, and what is on screen is better than anything you could add" - and
/// `PraticheController.report` is last-writer-wins on a single line, so a second sentence does
/// not add to the first, it replaces it.
enum PraticaRegenerationCommit: Equatable, Sendable {
    /// Written. Nothing to put back.
    case committed
    /// Refused before writing - the pratica folder was relocated or trashed - and the sentence
    /// saying so, and that the files are in the Trash, is already on the banner. Put the files
    /// back if the destination allows, and say nothing.
    case refused
    /// The write itself failed. Put the files back, and own the sentence about any that could
    /// not be: the failure report says why, not where they are.
    case failed
}

extension PraticaRunStop {
    /// The Italian sentence «Rigenera…» reports when the guard on its own pratica folder
    /// refuses it - `PraticaLiveSync.prepareRegeneration` before showing a preview,
    /// `commitRegeneration` before writing. Chosen here, not at either call site, so the two
    /// cannot drift and neither grows a branch: a folder that moved sends the person to «la
    /// nuova posizione», and a folder that went to the Trash (PG-169) has none to send them to.
    static func regenerationRefusal(after error: Error, of folder: String) -> String {
        if case .praticaTrashed? = error as? PraticaRunStop {
            return "«\(folder)» è stata eliminata: la rigenerazione non è stata eseguita."
        }
        return "«\(folder)» è stata spostata: riapri «Rigenera…» dalla nuova posizione."
    }

    /// PG-168: the path a stopped run leaves behind and the Italian sentence that names it, for
    /// the caller to report **only if something is still standing there**. `nil` for
    /// `.vaultChanged`, which vacated nothing.
    ///
    /// Reported and never touched: a directory named `email/` with no `pratica.md` beside it is
    /// indistinguishable from one a person made by hand, and deleting files on a heuristic is
    /// what "File over app" forbids. The write guard (`requiringExistingFolder:`,
    /// `PraticaSyncEngine.makeDirectory`) stops a run bringing the vacated folder back; this is
    /// for what it cannot reason about - a folder an older build orphaned, or bytes whose atomic
    /// rename landed just before a `mv` enumerated the directory and so did not travel with it.
    static func leftoverNotice(after stop: PraticaRunStop) -> (path: String, sentence: String)? {
        switch stop {
        case .vaultChanged:
            nil
        case .praticaRelocated(let from, _):
            (from, "Dopo lo spostamento è rimasta una cartella in «\(from)»: controllala, non la tocco.")
        case .praticaTrashed(let path):
            (path, "Dopo l'eliminazione è rimasta una cartella in «\(path)»: controllala, non la tocco.")
        }
    }
}

/// Where a pratica path some in-flight caller captured stands by the time that caller looks
/// again (ADR-0026 §D7, PG-169). One value rather than a redirect map read beside a tombstone
/// set: a second collection read separately is the `assertInsideVault(url)` shape CLAUDE.md's
/// working agreement forbids, and the fourth caller would read one and forget the other.
/// Private to this file, since `praticaPath(continuing:)`, `recordSyncOutcome` and
/// `endRegeneration` - the only three askers - all live here.
private enum PraticaPathDestination: Equatable {
    /// Nothing relocated it and nothing trashed it.
    case same
    /// Relocated, once or more, and lives at this path now.
    case moved(String)
    /// Its folder went to the Trash - or, after a relocation, the folder it was last relocated
    /// to did. The payload is the end of the redirect chain (the captured path itself when
    /// nothing moved), because that is the key `regeneratingPraticaPaths` still holds and
    /// `endRegeneration` has to release.
    case forgotten(String)
}

extension PraticheController {
    /// What a finished sync found waiting for this pratica (R-30). Also refreshes the
    /// list, since the dot on a row is one of these counts.
    func updateTray(
        _ proposals: [PraticaTrayModel.PraticaTrayProposal],
        for praticaPath: String,
        in vault: VaultController
    ) {
        // The door first, the two assignments after it (ADR-0052 §D8): the door can reset both
        // dictionaries on a change of vault, and the reverse order would drop the proposals a sync
        // has just computed the first time the marker mismatches. `persistTrayCount` reads only
        // `count`, so nothing is lost by the move.
        persistTrayCount(proposals.count, for: praticaPath, in: vault)
        trayProposals[praticaPath] = proposals
        trayCounts[praticaPath] = proposals.count
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
        updateLedger(.live(vault.session)) { ledger in
            var state = ledger.byPraticaPath[praticaPath] ?? .empty
            // Returning without a mutation is what keeps the file from being rewritten: the door
            // saves only a ledger that differs from the one it started with.
            guard state.trayCount != count else { return }
            state.trayCount = count
            ledger.byPraticaPath[praticaPath] = state
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
    ///
    /// The ledger goes through `reloadLedger(for:)` (ADR-0052 §D1/§D5), which records which file
    /// the memory came from and resets the tray, the watchers, the selection and everything read
    /// for it when that file belongs to a different vault - or to none, the vault having closed.
    /// A re-read of the same vault resets nothing: this runs after every pratica command.
    func load(from vault: VaultController) {
        guard let session = vault.session else {
            reloadLedger(for: nil)
            // Round-4 review, §6: a redirect entry describes THIS vault's own
            // relocations alone (`livePraticaPath`'s own "session identity checked
            // first" reason, `PraticaLiveSync+Run.swift`) - once the vault is gone,
            // nothing it described still applies. No live bug either way (pruning,
            // plus that session-identity-first ordering, already make a stale entry
            // harmless), but dropping it here makes the invariant local rather than
            // inferred. Deliberately NOT unconditional at the top of this function:
            // `load(from:)` also runs on the SAME vault right after an ordinary
            // rename/status-change/delete (`PraticaCommandActions`), and clearing the
            // map there could erase an entry `moveLedgerState` just left, moments
            // earlier in the same call stack, for a sync still in flight. The same holds
            // for a tombstone `forgetLedgerState` just left (PG-169) - `confirmDeletion`
            // calls `load(from:)` straight after its trash.
            praticaPathRedirects.removeAll()
            forgottenPraticaPaths.removeAll()
            return
        }
        reloadLedger(for: session)
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
            links = .empty
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
        // ADR-0049 Task 5 (R-04): the same beat as `timeline`/`details` above, and
        // the one `PraticaCommandActions.reload()` calls after every link write.
        links = PraticaLinks.parse(
            praticaFileAt: root.appending(
                path: PraticaNaming.praticaNotePath(of: selection), directoryHint: .notDirectory
            )
        )
    }

    private func markOpened(_ praticaPath: String, in vault: VaultController) {
        // A ledger that will not save costs one badge, not a pratica: the door reports it and
        // never throws it at the person reading their mail.
        updateLedger(.live(vault.session)) { ledger in
            var state = ledger.byPraticaPath[praticaPath] ?? .empty
            state.lastOpenedAt = Date()
            ledger.byPraticaPath[praticaPath] = state
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
        let released = syncingPraticaPath
        syncingPraticaPath = nil
        syncProgress = nil
        if let released { dropTombstoneIfUnclaimed(released) }
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
    /// corruption, not a UI-only glitch. Both halves go through `updateLedger(_:_:)`
    /// (ADR-0052 §D2), which is also what makes a live write on a controller that never
    /// loaded read the file first instead of saving an empty ledger over it.
    func recordSyncOutcome(
        _ outcome: PraticaSyncEngine.SyncOutcome, for praticaPath: String, session: VaultSession,
        isCurrentVault: Bool
    ) {
        // A relocation that ran on the main actor while this outcome's own sync was
        // still in flight has already moved the ledger key out from under
        // `praticaPath` (`moveLedgerState`, below) - only meaningful against `self`
        // when this outcome belongs to the vault that redirect map describes. The
        // tombstones (`forgottenPraticaPaths`) describe the live vault alone for the same
        // reason.
        let currentPath: String
        if isCurrentVault {
            switch destination(of: praticaPath) {
            case .same: currentPath = praticaPath
            case .moved(let moved): currentPath = moved
            // A trash (PG-169) that ran while this outcome's own run was in flight has
            // already removed the ledger key. Writing anything now - a key, a `problem`
            // sentence, the `ledger` assignment - would put back what it removed. This is
            // the one guard that closes the regeneration half of that race, since
            // `commitRegeneration` deliberately has no post-`await` re-check: the engine's
            // patch writes carry `expecting:` and its full render cannot recreate a vacated
            // folder (PG-168), so a relocation landing mid-write costs the ledger nothing.
            case .forgotten: return
            }
        } else {
            currentPath = praticaPath
        }
        // The observable property is this controller's view of the LIVE vault - never
        // updated on behalf of a vault that is no longer the one open, which is `.stale`'s
        // whole meaning: its own file, read fresh, and neither `ledger` nor its marker touched.
        updateLedger(isCurrentVault ? .live(session) : .stale(session)) { ledger in
            var state = ledger.byPraticaPath[currentPath] ?? .empty
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
            ledger.byPraticaPath[currentPath] = state
        }
        if isCurrentVault {
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
    /// `destination(of:)` (below) no longer removes what it reads, so two
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
        // The door first, its siblings after (ADR-0052 §D8): on a change of vault it resets
        // `trayProposals`, `trayCounts`, `watchersByPraticaPath` and `selection`, and what follows
        // must remap what is there afterwards, not what a vault that has just been left held.
        // The remap itself saves through the door only if a key really moved.
        updateLedger(.live(vault.session)) { ledger in
            Self.remapKeys(
                &ledger.byPraticaPath, from: oldPath, to: newPath,
                redirects: &praticaPathRedirects, isInFlight: isInFlight
            )
        }
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
            // Round-4 review, §4: the redirect above is what stops the ledger/UI
            // consumers from writing under the vacated path once they NEXT reach one
            // of `livePraticaPath`'s guards - the ENGINE itself, mid-message, is not
            // one of those consumers and keeps writing into the old folder until then
            // (which used to recreate it). Asking it to stop here, at the exact moment
            // its own claimed path is found relocated, bounds that window to "the message
            // being written right now" - `PraticaSyncEngine.cancel()` is cooperative,
            // checked once per message, so that message can still reach its write. It can
            // no longer bring the vacated folder back (PG-168): `PraticaSyncEngine.
            // makeDirectory` and the `requiringExistingFolder:` write refuse instead.
            requestSyncStopForVanishedPath?()
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

    /// The deletion twin of `moveLedgerState(from:to:in:)` (ADR-0026 §D7, amended
    /// 2026-09-19, PG-169): a pratica folder sent to the Trash - or an ancestor of one, which
    /// takes every descendant pratica with it - leaves every piece of path-keyed Pratiche state
    /// describing a folder that is gone. The ledger is the one that does harm: a pratica
    /// recreated under the same name would inherit the old one's history - its
    /// `importedMessageIDs`, its «non più in Mail» list, its bridge `entries`, `lastOpenedAt`
    /// and tray count. Measured, not assumed: `MailStoreReader.rows` builds every row with
    /// `messageID: nil`, so stale ids do not by themselves stop `workItems` from queuing a
    /// message (the engine's own on-disk `Message-ID` scan decides); the harm is history
    /// leaking into a folder that never earned it, not a silent skip.
    ///
    /// Subtree-aware for the same reason the move twin is, through the same `isInSubtree`
    /// predicate, so `01 Progetti-altro` is never taken for a descendant of `01 Progetti`. The
    /// ledger key, the tray proposals and counts and the per-pratica watcher are removed; a
    /// selection inside the subtree goes through `select(nil, in:)`, so `expansion`, the
    /// timeline, the details and the links follow it as they do when a person deselects,
    /// rather than keep describing a folder in the Trash.
    ///
    /// A run still in flight for the folder is stopped and its outcome discarded.
    /// `syncingPraticaPath` and `regeneratingPraticaPaths` are deliberately NOT cleared, unlike
    /// a relocation, which remaps them: the claim stays where the run itself releases it
    /// (`endSync`/`endRegeneration`), because clearing it here would let `pruneRedirectsIfIdle`
    /// wipe the tombstone while the run it protects is still going. The tombstone is recorded
    /// independently of the dictionaries: a pratica's very first sync has no ledger entry yet
    /// (`?? .empty` never inserts one), so `removeKeys` alone would not have seen it.
    ///
    /// Nothing here prunes a key merely because its folder is missing from the disk, and
    /// nothing at load does either. A Finder move, an unmounted volume and a not-yet-scanned
    /// index all look exactly like a deleted pratica, and pruning on that evidence would turn
    /// the relocation bug into unrecoverable history loss. Only a trash this app performed
    /// itself is proof.
    func forgetLedgerState(under path: String, in vault: VaultController) {
        // Snapshotted before anything below touches the claims - `moveLedgerState`'s own
        // first line, and for the same reason.
        let isInFlight: (String) -> Bool = { [syncingPraticaPath, regeneratingPraticaPaths] key in
            key == syncingPraticaPath || regeneratingPraticaPaths.contains(key)
        }
        // This hook fires for ANY folder trashed through the note list or the Workspace browser,
        // including before the Pratiche pane has ever loaded the ledger. That case used to be
        // patched here (PG-169: «if the in-memory ledger is `.empty`, read the file first»), a
        // heuristic that took a genuinely empty ledger for an unloaded one. The marker replaces
        // it (ADR-0052 §D4): the door reads the file when memory did not come from it, and saves
        // only when a key really left, so an unrelated trash leaves the file byte-identical.
        // The door first, its siblings after (§D8).
        updateLedger(.live(vault.session)) { ledger in
            Self.removeKeys(
                &ledger.byPraticaPath, under: path, forgotten: &forgottenPraticaPaths, isInFlight: isInFlight
            )
        }
        Self.removeKeys(
            &trayProposals, under: path, forgotten: &forgottenPraticaPaths, isInFlight: isInFlight
        )
        Self.removeKeys(
            &trayCounts, under: path, forgotten: &forgottenPraticaPaths, isInFlight: isInFlight
        )
        Self.removeKeys(
            &watchersByPraticaPath, under: path, forgotten: &forgottenPraticaPaths, isInFlight: isInFlight
        )
        if let syncingPraticaPath, Self.isInSubtree(syncingPraticaPath, of: path) {
            forgottenPraticaPaths.insert(syncingPraticaPath)
            // The engine, mid-message, is not one of the consumers the tombstone stops: it
            // keeps writing into the trashed folder until it is asked to stop
            // (`PraticaSyncEngine.cancel()` is cooperative, checked once per message, so the
            // message being written right now can still reach its write - and is refused,
            // not landed: it may not recreate the trashed folder, PG-168).
            requestSyncStopForVanishedPath?()
        }
        for claimed in regeneratingPraticaPaths where Self.isInSubtree(claimed, of: path) {
            forgottenPraticaPaths.insert(claimed)
        }
        if let selection, Self.isInSubtree(selection, of: path) {
            select(nil, in: vault)
        }
    }

    /// The one place `VaultController.didTrashFolder` calls into (ADR-0026 §D7, wired by
    /// `PergamenumApp.init`): the deletion twin of `followFolderRelocations(_:in:)`, called
    /// once for the folder the trash door sent to the Trash - a pratica itself or any ancestor
    /// of one, since `forgetLedgerState` is subtree-aware.
    func followFolderTrashing(_ path: String, in vault: VaultController) {
        forgetLedgerState(under: path, in: vault)
    }

    /// Whether `path` is `root` itself or nested inside it. The prefix is `"\(root)/"` and
    /// never the bare path, `VaultMoveBatch.plan`'s own convention (`VaultMoveBatch.swift:
    /// 63-70`) to avoid mistaking `a-altro` for a descendant of `a`. The one predicate both
    /// `remappedPath` (the move twin) and `removeKeys` (the delete twin) ask, so the
    /// sibling-prefix rule cannot drift between the two.
    private static func isInSubtree(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix("\(root)/")
    }

    /// `path` itself, or `path` remapped to sit under `newPath` when it was nested
    /// inside `oldPath` - `nil` when `path` is neither, meaning it is untouched by this
    /// relocation (`isInSubtree`'s own rule).
    private static func remappedPath(_ path: String, from oldPath: String, to newPath: String) -> String? {
        guard isInSubtree(path, of: oldPath) else { return nil }
        return path == oldPath ? newPath : newPath + path.dropFirst(oldPath.count)
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

    /// The deletion twin of `remapKeys`: every key equal to or nested inside `path` is
    /// removed, everything else untouched. A removed key joins `forgotten` only when
    /// `isInFlight(key)` says a sync or regeneration still holds it as its own captured path
    /// (review round 2's MINOR 1 rule, kept) - a deletion with nothing running for `key`
    /// records no tombstone, since nothing will ever read one.
    private static func removeKeys<Value>(
        _ dict: inout [String: Value], under path: String,
        forgotten: inout Set<String>, isInFlight: (String) -> Bool
    ) {
        for key in Array(dict.keys) where isInSubtree(key, of: path) {
            dict.removeValue(forKey: key)
            if isInFlight(key) { forgotten.insert(key) }
        }
    }

    /// `praticaPath` as some in-flight caller captured it, resolved to wherever a
    /// relocation moved its ledger key by the time the caller's own outcome arrives -
    /// itself when no relocation ever touched it - and to `.forgotten` when the folder it
    /// ended up at was trashed in the meantime (PG-169). Walks more than one hop only when
    /// the same pratica was relocated twice before that outcome landed.
    ///
    /// Never mutates `praticaPathRedirects` or `forgottenPraticaPaths` (review round 2,
    /// MINOR 2): the old `removeValue` read let the FIRST of two concurrent in-flight
    /// callers sharing the same pre-move path (an ordinary sync and a "Rigenera…" commit
    /// can race each other for the same pratica - `PraticaLiveSync`'s `SyncRunQueue` only
    /// serializes ordinary syncs against each other) consume the entry, leaving the second
    /// to fall through to the stale key and resurrect it. `endSync`/`endRegeneration` are
    /// what eventually drop an entry, once nothing anywhere is still in flight to need it
    /// (`pruneRedirectsIfIdle`, below) - never a single read.
    private func destination(of captured: String) -> PraticaPathDestination {
        var current = captured
        var visited: Set<String> = [captured]
        while let next = praticaPathRedirects[current], visited.insert(next).inserted {
            current = next
        }
        if forgottenPraticaPaths.contains(current) { return .forgotten(current) }
        return current == captured ? .same : .moved(current)
    }

    /// The pratica folder an in-flight run captured, returned only while it is still
    /// where that run left it (round-4 review, §1). Throws `.praticaRelocated`
    /// when it moved: a run must not keep writing - files or ledger keys - under a path a
    /// relocation has vacated. Carries the new path because the caller that must stop
    /// is the caller that must ask for a fresh run there. Throws `.praticaTrashed` when
    /// the folder went to the Trash (PG-169), which carries no destination: there is
    /// nowhere to ask for a fresh run. A resolver, not a bare
    /// `hasRelocated(_:) -> Bool` predicate: the `assertInsideVault(url)` shape
    /// CLAUDE.md's working agreement forbids, containment per ADR-0041's
    /// `VaultBoundary.url(for:)` precedent.
    func praticaPath(continuing captured: String) throws -> String {
        switch destination(of: captured) {
        case .same:
            return captured
        case .moved(let current):
            throw PraticaRunStop.praticaRelocated(from: captured, to: current)
        case .forgotten:
            throw PraticaRunStop.praticaTrashed(path: captured)
        }
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
    /// (`moveLedgerState`, above), not the value this call was made with. A trash
    /// (PG-169) leaves the claim exactly where it was - `forgetLedgerState` never clears it,
    /// so that this is the one place it is released - and `.forgotten` names the end of the
    /// chain for the case a relocation came first.
    ///
    /// The tombstone of the path released goes with the claim, unless something else still
    /// claims THAT path (ADR-0052 §D6): an open «Rigenera…» on another pratica is not a reason
    /// to keep refusing this one once it has been recreated.
    func endRegeneration(_ praticaPath: String) {
        let released: String
        switch destination(of: praticaPath) {
        case .same: released = praticaPath
        case .moved(let current), .forgotten(let current): released = current
        }
        regeneratingPraticaPaths.remove(released)
        dropTombstoneIfUnclaimed(released)
        if released != praticaPath { dropTombstoneIfUnclaimed(praticaPath) }
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

    /// Review round 2, MINOR 2's other half: since `destination(of:)` never removes what
    /// it reads, nothing prunes `praticaPathRedirects` on a per-entry basis. The whole map
    /// is safe to drop in one go the moment NOTHING is in flight anywhere -
    /// `syncingPraticaPath == nil && regeneratingPraticaPaths.isEmpty` - since every entry
    /// in it exists only because `moveLedgerState` found something in flight for that key
    /// at the time (MINOR 1), and nothing left running means every caller that could have
    /// needed one has already resolved through it. `forgottenPraticaPaths` goes with it, for
    /// the same reason: `forgetLedgerState` tombstones only a key something claims. Called
    /// from `endSync` and `endRegeneration`, the two places that can make this true.
    private func pruneRedirectsIfIdle() {
        guard syncingPraticaPath == nil, regeneratingPraticaPaths.isEmpty else { return }
        praticaPathRedirects.removeAll()
        forgottenPraticaPaths.removeAll()
    }

    /// A tombstone outlives its own run only while something still claims THAT path; a claim on
    /// another path is not its business (ADR-0052 §D6, PG-173's second half). Where
    /// `pruneRedirectsIfIdle` above answers for the whole controller at once, this answers for one
    /// path, so a healthy pratica recreated under a trashed one's name is not refused because an
    /// unrelated «Rigenera…» sheet happens to be open. A claim still open on the path keeps its
    /// tombstone, and that claim's outcome is still discarded (PG-169's behaviour, unchanged).
    private func dropTombstoneIfUnclaimed(_ path: String) {
        guard path != syncingPraticaPath, !regeneratingPraticaPaths.contains(path) else { return }
        forgottenPraticaPaths.remove(path)
    }

    /// §D23.4: Mail renumbered a followed conversation Mail's own way (a new
    /// `conversation_id` recovered from a member `Message-ID`'s still-known row) - the
    /// ledger's own triples have to be repointed too, or the next sync's
    /// `memberMessageIDs(forConversation:)` answers nothing for the new id and the
    /// pratica silently loses its recovery data one renumbering later.
    ///
    /// Declared here (ADR-0155 §D1); the coder wires the body (§D23.4's repointing,
    /// called from `PraticaLiveSync.runExclusive` before candidates are evaluated).
    ///
    /// Takes the run's own `session` and an `isCurrentVault` flag, like `recordSyncOutcome`
    /// (ADR-0052 §D7), and not the `VaultController` it used to: it runs after an `await
    /// session.write`, and a vault switch landing inside that window must write the repointing
    /// into the run's OWN ledger file rather than into whatever vault is live now - or drop it.
    /// Dropping it is not free, since the note has already been rewritten with the new id.
    /// The `guard var state` moved inside the closure: read outside the door it looked at an
    /// unloaded ledger, found nothing and returned.
    func remapLedgerConversations(
        _ remap: [Int: Int], of praticaPath: String, session: VaultSession, isCurrentVault: Bool
    ) {
        guard !remap.isEmpty else { return }
        updateLedger(isCurrentVault ? .live(session) : .stale(session)) { ledger in
            guard var state = ledger.byPraticaPath[praticaPath] else { return }
            state.entries = state.entries.map { entry in
                guard let newID = remap[entry.conversationID] else { return entry }
                return PraticaLedger.Entry(
                    messageID: entry.messageID, rowID: entry.rowID, conversationID: newID
                )
            }
            ledger.byPraticaPath[praticaPath] = state
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
