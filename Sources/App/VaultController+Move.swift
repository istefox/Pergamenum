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
        undo.setActionName("Sposta")
        // `registerUndo`'s handler is synchronous and `moveInverse` is not any more
        // (ADR-0043 §D2): the hop is the only way in, and nothing here depends on the
        // inverse having finished by the time the handler returns.
        undo.registerUndo(withTarget: self) { controller in
            Task { @MainActor in
                await controller.moveInverse(VaultMoveBatch.inverse(of: outcome.moves), undo: undo)
            }
        }
        return outcome
    }

    /// Performs `moves` and, only if all of them landed, re-registers their own inverse -
    /// which is the redo, and the whole of it (ADR-0026 §D8: "the handler performs the
    /// inverse batch and re-registers itself with the arguments swapped, which is how
    /// `NSUndoManager` produces redo - there is no custom redo code").
    ///
    /// Called from inside an `UndoManager` handler, so the registration it makes lands on
    /// the redo stack; called again from that redo's handler, so the recursion alternates
    /// for as long as Cmd+Z and Cmd+Shift+Z do.
    func moveInverse(_ moves: [VaultMove], undo: UndoManager?) async {
        guard let session, !moves.isEmpty else { return }

        // Where each item sits *now*: inside `from`, under its own name, because a move
        // never renames (§D5). `VaultMove.item.path` names the row as it was before the
        // forward move, so it cannot be used as-is - `VaultMoveBatch.inverse`'s own note
        // says the caller re-derives this.
        let current = moves.map {
            (destination: $0.to, ref: VaultItemRef(path: Self.path(of: $0.item.path, in: $0.from), kind: $0.item.kind))
        }

        // The race §D8 names, "a later rename moved it", asked for the whole batch before
        // one item is dispatched: a partial inverse is an undo step that puts back some of
        // what the user sees and not the rest (§D6). Nothing is written and nothing is
        // re-registered - a redo of an undo that did not happen is worse than no redo.
        let missing = current.filter { !session.exists($0.ref.path) }
        guard missing.isEmpty else {
            recordProblem(
                "annulla spostamento: \(missing.map(\.ref.path).joined(separator: ", ")) non è più dove si trovava"
            )
            return
        }
        guard refusal(forAll: current.map(\.ref)) == nil else { return }

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
            // both now name a path nothing is at. What the failure costs is the redo
            // registration, not the follow-up.
            follow(outcome)
        }

        guard failures.isEmpty else {
            for failure in failures {
                recordProblem("annulla spostamento: \(failure)")
            }
            return
        }

        undo?.setActionName("Sposta")
        undo?.registerUndo(withTarget: self) { controller in
            Task { @MainActor in
                await controller.moveInverse(VaultMoveBatch.inverse(of: moves), undo: undo)
            }
        }
    }

    // MARK: - The window's half

    /// Refuses the whole batch while any note it would carry has unsaved edits, before
    /// anything touches disk (ADR-0026 §D10). Answers the reason rather than a `Bool`
    /// (PG-083) so the caller can put it in `MoveBatchOutcome.refusals` instead of
    /// re-reading `problems.last`.
    ///
    /// The two guards that already exist, each asked of the kind it was written for: a
    /// note by its own path, a folder by the subtree it holds. A board is neither - the
    /// editor cannot have a `.canvas` open with unsaved edits - so it is not asked. Both
    /// guards test against the single `openNote`, so at most one reason can ever fire;
    /// `allSatisfy`'s short-circuit was never hiding a second one.
    private func refusal(forAll items: [VaultItemRef]) -> String? {
        for item in items {
            switch item.kind {
            case .note where !canOperate(on: item.path): return Self.unsavedNoteRefusal
            case .folder where !canOperateOnFolder(item.path): return Self.unsavedNoteInFolderRefusal
            default: continue
            }
        }
        return nil
    }

    /// Follows every note the batch carried into the tabs and RECENTI that were showing
    /// it, then rebuilds the index - `renameFolder`'s two follow-ups, for a batch.
    private func follow(_ outcome: VaultSession.MoveBatchOutcome) {
        for moved in outcome.movedNotes {
            movedNote(from: moved.old, to: moved.new)
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
