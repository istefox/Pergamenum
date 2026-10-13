import Foundation

/// The window-shaped half of a batch move (ADR-0026 §D8, §D10): `canOperate`/
/// `canOperateOnFolder` before anything touches disk, `flushBoard()` first so the
/// autosave cannot recreate what just moved (ADR-0022 §F10), every moved note followed
/// into tabs and RECENTI, a rescan afterwards, and **one** block registered on `undo`
/// for the whole batch - a six-row move is one undo step (R-12), and the block
/// re-registers itself with the arguments swapped, which is how `UndoManager` produces
/// redo with no custom redo code.
///
/// `Tests/VaultMoveTests.swift` (ADR-0026, this plan's Task 3) owns this signature.
extension VaultController {
    /// Moves `items` into `destination` and registers the whole batch as one undo step
    /// (R-01 … R-05, R-12).
    ///
    /// Returns the full outcome rather than a `Bool` (PG-083): a caller needs every
    /// refusal and every failure, not only whether `didMove` is true, and it needs the
    /// `moves` that actually landed on disk to know where the open board went - a plan
    /// re-computed independently can name an item that never made it. Every one of those
    /// is also on `problems` regardless, because a drop that does nothing and says
    /// nothing is the failure mode this repository keeps writing ADR sections about.
    ///
    /// An item that failed *after* the batch started writing is reported the same way and
    /// does not cancel the rest: whatever landed on disk is followed and registered on
    /// `undo`, because files that moved with nothing on the undo stack to bring them back
    /// is the worse of the two outcomes (`VaultSession.moveItems` makes the same argument
    /// from the other side).
    @discardableResult
    func moveItems(
        _ items: [VaultItemRef], into destination: String, undo: UndoManager?
    ) async -> VaultSession.MoveBatchOutcome {
        guard let session else {
            var outcome = VaultSession.MoveBatchOutcome()
            outcome.refusals = ["nessun vault aperto"]
            return outcome
        }
        if let reason = refusal(forAll: items) {
            var outcome = VaultSession.MoveBatchOutcome()
            outcome.refusals = [reason]
            return outcome
        }

        let outcome = await session.moveItems(items, into: destination)

        for refusal in outcome.refusals {
            recordProblem("spostamento rifiutato - \(refusal)")
        }
        for failure in outcome.failures {
            recordProblem("spostamento non riuscito - \(failure)")
        }
        guard outcome.didMove else { return outcome }

        follow(outcome)

        guard let undo else {
            // Degrading silently is what §D8 refuses: the move happened and it cannot be
            // taken back, and only the person who made it can decide what to do about it.
            recordProblem("spostamento non annullabile: nessun gestore di undo disponibile")
            return outcome
        }
        registerInverse(VaultMoveBatch.inverse(of: outcome.moves), undo: undo)
        return outcome
    }

    /// Registers `moves` as the batch's next undo/redo step: `NSUndoManager` calls the
    /// handler below synchronously for the matching `undo()`/`redo()`, and everything
    /// that handler needs to decide *whether* to register the swap - the missing-item and
    /// refusal checks - is itself synchronous, so it runs before anything is registered or
    /// touches disk (ADR-0043 follow-up, preserving ADR-0026 §D8: a redo of an undo that
    /// never happened must never be offered).
    private func registerInverse(_ moves: [VaultMove], undo: UndoManager) {
        undo.setActionName("Sposta")
        undo.registerUndo(withTarget: self) { controller in
            controller.attemptInverse(moves, undo: undo)
        }
    }

    /// The handler `registerInverse` installs, run synchronously by `NSUndoManager` for
    /// the `undo()`/`redo()` that consumes this step.
    ///
    /// Resolves where each item sits now and refuses the whole batch, recording why,
    /// before registering anything - the race §D8 names, "a later rename moved it", asked
    /// for the whole batch before one item is dispatched: a partial inverse is an undo
    /// step that puts back some of what the user sees and not the rest (§D6). Only once
    /// every item in the batch is confirmed still where the previous step left it does
    /// this register the *next* swap - synchronously, inside the same `undo()`/`redo()`
    /// extent that invoked this handler, which is what lands it on the correct stack
    /// (ADR-0043 follow-up: registering it any later, once `performInverse`'s `await`
    /// has returned, always landed back on the undo stack instead of flipping to redo) -
    /// and hands the actual moves to `performInverse`.
    private func attemptInverse(_ moves: [VaultMove], undo: UndoManager) {
        guard let session, !moves.isEmpty else { return }

        // Where each item sits *now*: inside `from`, under its own name, because a move
        // never renames (§D5). `VaultMove.item.path` names the row as it was before the
        // forward move, so it cannot be used as-is - `VaultMoveBatch.inverse`'s own note
        // says the caller re-derives this.
        let current = moves.map {
            (destination: $0.to, ref: VaultItemRef(path: Self.path(of: $0.item.path, in: $0.from), kind: $0.item.kind))
        }

        let missing = current.filter { !session.exists($0.ref.path) }
        guard missing.isEmpty else {
            recordProblem(
                "annulla spostamento: \(missing.map(\.ref.path).joined(separator: ", ")) non è più dove si trovava"
            )
            return
        }
        // These refs were built by this undo, not by a Workspace browser row, so no
        // `settleForVerb()` ran upstream, and the step can run from any pane while the board is
        // kept (ADR-0091 §D3). The forward door's settle, before anything moves, asked only when
        // the step carries the open board itself or a folder that holds it: a pending edit is
        // flushed into the file before it leaves, a conflicted board refuses the step, and an
        // unrelated open board is never asked, so it cannot consume this step.
        let carriesBoard = current.contains { carriesOpenBoard($0.ref) }
        if carriesBoard, !openBoard.settleForVerb() { return }
        guard refusal(forAll: current.map(\.ref)) == nil else { return }
        // `settleForVerb()` refuses only a conflict: a flush whose write failed leaves the board
        // pending. A folder holding it was refused just above by `folderRefusal`; a `.board` ref
        // is refused here, with the same sentence, so the file does not move away from the
        // unsaved edits that point at it.
        if carriesBoard, openBoard.hasUnsavedChanges, let board = openBoardPath {
            let name = ((board as NSString).lastPathComponent as NSString).deletingPathExtension
            recordProblem(Self.unsavedBoardInFolderRefusal(named: name))
            return
        }

        registerInverse(VaultMoveBatch.inverse(of: moves), undo: undo)
        Task { @MainActor in
            await performInverse(current)
        }
    }

    /// The actual disk work: `session.moveItems` per landing folder, following moved
    /// notes into tabs and RECENTI and the open board to where it landed, and reporting any
    /// failure. `attemptInverse` has already resolved and cleared every item and already
    /// registered this step's redo/undo swap by the time this runs.
    private func performInverse(_ current: [(destination: String, ref: VaultItemRef)]) async {
        guard let session else { return }
        // Read before the first suspension, as the forward door reads it (ADR-0043 §D7): the
        // board the moves below may carry, followed to where it lands once they have run.
        let openBefore = openBoard.board
        var landed: [VaultMove] = []

        // One call per landing folder, because an inverse is the only batch whose items
        // can be going to different places: they return to wherever each came from.
        // First-appearance order rather than `Dictionary(grouping:)`'s, which has none.
        var destinations: [String] = []
        for entry in current where !destinations.contains(entry.destination) {
            destinations.append(entry.destination)
        }

        var failures: [String] = []
        for destination in destinations {
            let group = current.filter { $0.destination == destination }.map(\.ref)
            let outcome = await session.moveItems(group, into: destination)
            failures.append(contentsOf: outcome.refusals)
            failures.append(contentsOf: outcome.failures)
            if outcome.moves.count != group.count && outcome.refusals.isEmpty && outcome.failures.isEmpty {
                failures.append("«\(destination)»: \(group.count - outcome.moves.count) elementi non spostati")
            }
            // Outside the `failures.isEmpty` guard below on purpose: a group that came back
            // half-moved still moved half, and those notes are in tabs and in an index that
            // both now name a path nothing is at. The redo/undo swap for this step was
            // already registered by `attemptInverse` before this ran, so a failure here
            // cannot cost it - only the failure report is at stake.
            follow(outcome)
            landed.append(contentsOf: outcome.moves)
        }
        // The forward door's landing rule (`WorkspaceView+FolderVerbs`): the open board, when a
        // move carried it and it is still the one open, is reopened where it returned, so its
        // next save is not aimed at a path that has gone. Whatever landed, failures or not.
        openBoard.followMove(from: openBefore, moves: landed)

        guard failures.isEmpty else {
            for failure in failures {
                recordProblem("annulla spostamento: \(failure)")
            }
            return
        }
    }

    /// Whether moving `ref` carries the open board: the board itself, or a folder that holds
    /// it, by `folderRefusal`'s prefix rule. False when no board is open.
    private func carriesOpenBoard(_ ref: VaultItemRef) -> Bool {
        guard let board = openBoardPath else { return false }
        let path = ref.path.trimmingCharacters(in: .pathSlashes)
        return board == path || board.hasPrefix("\(path)/")
    }

    // MARK: - The window's half

    /// Refuses the whole batch while any note it would carry has unsaved edits, before
    /// anything touches disk (ADR-0026 §D10). Answers the reason rather than a `Bool`
    /// (PG-083) so the caller can put it in `MoveBatchOutcome.refusals` instead of
    /// re-reading `problems.last`.
    ///
    /// The two guards that already exist, each asked of the kind it was written for: a
    /// note by its own path, a folder by the subtree it holds. A board is neither, and it is
    /// not asked: a forward `.board` ref is built only by the Workspace browser's rows
    /// (`WorkspaceBrowser+Tree.swift`, `WorkspaceRow+Move.swift`), whose move has already
    /// passed `settleForVerb()` (`WorkspaceView+FolderVerbs.swift`) before it gets here, and
    /// the undo/redo that builds one again runs that same settle first, and refuses a board its
    /// flush left pending (`attemptInverse`). The first refusal ends the walk.
    ///
    /// A folder can be refused for a dirty note under it or, since ADR-0091 §D8, for the
    /// Workspace board kept with unsaved edits under it: `folderRefusal(_:)` answers which
    /// sentence, and that sentence is recorded and returned, never `problems.last` (PG-083).
    private func refusal(forAll items: [VaultItemRef]) -> String? {
        for item in items {
            switch item.kind {
            case .note where !canOperate(on: item.path): return Self.unsavedNoteRefusal
            case .folder:
                guard let refusal = folderRefusal(item.path) else { continue }
                recordProblem(refusal)
                return refusal
            default: continue
            }
        }
        return nil
    }

    /// Relocates what follows a moved folder, then rebuilds the index - `renameFolder`'s
    /// follow-ups, for a batch. The tabs and RECENTI already followed every carried note:
    /// the session announced each move as it landed (ADR-0067 §D1), forward and on
    /// `performInverse`'s undo/redo alike.
    private func follow(_ outcome: VaultSession.MoveBatchOutcome) {
        // The single choke point for both directions (§D8's own claim): this runs for
        // a forward move and, unchanged, for `performInverse`'s undo/redo - so a moved
        // pratica's ledger follows the same way back as it followed forward.
        if !outcome.movedFolders.isEmpty {
            didRelocateFolders?(outcome.movedFolders)
        }
        Task { await rescan() }
    }

    /// `path`'s own last component inside `folder`, the vault root spelled `""` - the
    /// landing rule `VaultMoveBatch` applies when it plans a move, applied here to read
    /// back where a completed one put things.
    private static func path(of path: String, in folder: String) -> String {
        let name = (path as NSString).lastPathComponent
        return folder.isEmpty ? name : "\(folder)/\(name)"
    }
}
