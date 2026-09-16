import Foundation

/// One move verb for three kinds of thing - a note, a board or a folder - dispatched
/// through the operations that already exist for each rather than reimplemented
/// (ADR-0026 §D2, §D6): a note goes through the existing journalled `moveNote`, a board
/// through `BoardFileOperations.moveBoard`, a folder through
/// `FolderFileOperations.moveFolder`. `VaultMoveBatch.plan` decides the batch first, and
/// nothing is dispatched at all unless every item passed.
///
/// Not in `sharedSources` (`Project.swift`), unlike `VaultSession+Files.swift`: a write
/// `--dry-run` cannot rehearse and the connector `undo` cannot reverse must stay
/// unreachable from `perg` and `pergamenum-mcp` (ADR-0022 §D6, ADR-0025 §D6, ADR-0026
/// §D1).
///
/// `Tests/VaultMoveTests.swift` (ADR-0026, this plan's Task 3) owns this signature.
extension VaultSession {
    // Rebuilt per call, `VaultSession+Folders`' own spelling - both are `private` to
    // their own file, which is why this file declares its own rather than reaching for
    // that one.
    private var boardOperations: BoardFileOperations { BoardFileOperations(store: store) }
    private var folderOperations: FolderFileOperations { FolderFileOperations(store: store) }

    /// What a completed batch move did, across every kind of item it touched.
    struct MoveBatchOutcome: Equatable, Sendable {
        /// The moves the batch actually performed, in the order `VaultMoveBatch.plan`
        /// returned them - what `VaultController` hands to `boardAfterMove` and to
        /// `UndoManager.registerUndo`'s inverse.
        var moves: [VaultMove] = []
        /// Every note the batch carried, old path then new - what the facade needs to
        /// follow tabs and RECENTI, `renameFolder`'s own `movedNotes` shape.
        var movedNotes: [MovedNote] = []
        /// `VaultMoveBatch.Result.refused`'s reasons, verbatim, when the batch could not
        /// commit at all (ADR-0026 §D6, all-or-nothing) - empty on a successful batch.
        var refusals: [String] = []
        /// What failed *after* the batch had started writing: one line per item whose
        /// operation threw on disk, naming the item and the error.
        ///
        /// A different thing from `refusals`, and the distinction is the whole point.
        /// `VaultMoveBatch.plan`'s all-or-nothing holds for the decision, not for the
        /// execution: an item can pass every pre-write rule and still fail on disk -
        /// permissions, a full volume, or the plain TOCTOU of something that moved between
        /// the plan and the loop. When that happens the items already written stay written,
        /// so they are in `moves` and the caller can follow and undo them; the ones that
        /// did not are named here.
        var failures: [String] = []

        /// Whether anything actually landed on disk - the condition every caller of
        /// `VaultController.moveItems` needs to decide success, named once so it is
        /// asked the same way everywhere instead of each site re-deriving `!moves.isEmpty`.
        var didMove: Bool { !moves.isEmpty }
    }

    /// Moves `items` into `destination` as one batch, all-or-nothing (ADR-0026 §D6).
    /// `destination` is a vault-relative folder path, the vault root spelled `""`
    /// (R-05).
    ///
    /// A refusal is a returned `MoveBatchOutcome` with `refusals` filled and `moves`
    /// empty, never a `throw`: the five rules of `VaultMoveBatch.plan` are the batch
    /// answering a question, and the caller has a dialog to name them in (R-07).
    ///
    /// **This never throws either.** An operation that got past the plan and then failed
    /// on disk is caught per item and named in `failures`, and the loop carries on with
    /// the rest. Letting one item's error unwind the whole call would discard the outcome
    /// built for the items *before* it - which are already written - so the caller could
    /// neither follow their notes into the open tabs nor register an undo for them: the
    /// files would have moved with nothing on the undo stack able to bring them back. The
    /// all-or-nothing of §D6 is a property of the decision (`VaultMoveBatch.plan` refuses
    /// before a byte is written), not a promise the file system can be held to once the
    /// writing has started.
    ///
    /// **The starred-note write is batched (ADR-0041 §D8, Task 7).** Every item in the loop
    /// below still goes through its own existing operation - `moveNote`, `moveBoard`,
    /// `moveFolder` - unchanged, so a `.canvas` repoint for a moved note or board is still
    /// one pass per item, not one for the batch: `moveNote`'s repoint is
    /// `NoteFileOperations`'s own private copy and is out of this task's scope
    /// (`Tests/VaultBatchMoveTests.swift`'s header explains why). What changed is only the
    /// starred-note write: `starred.json` is now saved **once** for the whole batch, through
    /// `extractStarForBatchedMove`/`commitBatchedStarMoves` below, instead of once per
    /// starred note the way `moveNote`'s own internal `moveStar` call used to trigger on
    /// its own.
    func moveItems(_ items: [VaultItemRef], into destination: String) async -> MoveBatchOutcome {
        var outcome = MoveBatchOutcome()

        switch VaultMoveBatch.plan(items, into: destination, exists: { exists($0) }) {
        case .refused(let reasons):
            outcome.refusals = reasons
            return outcome

        case .moves(let moves):
            // Collected across every item in the batch and committed **once**, after the
            // loop, through `commitBatchedStarMoves` (ADR-0041 §D8, Task 7) - not once per
            // starred note the way `moveNote`'s own internal `moveStar` call would do on
            // its own. See `extractStarForBatchedMove`'s doc comment
            // (`VaultSession+Starred.swift`) for how its call below neutralizes that.
            var pendingNewStarredPaths: [String] = []

            for move in moves {
                // Set only for a `.note` item whose star was taken out ahead of the move
                // below - the one case that can still throw *after* the extraction, and so
                // the one case that needs putting back if it does.
                var extractedStarPath: String?
                do {
                    switch move.item.kind {
                    case .note:
                        // The existing journalled path (ADR-0026 §D2): `moveNote` writes
                        // through `transaction("note move")`, carries the star and repoints
                        // the cards. A second spelling of that verb here would be exactly
                        // the drift `CLAUDE.md`'s connector section is about.
                        if extractStarForBatchedMove(move.item.path) {
                            extractedStarPath = move.item.path
                        }
                        let note = try await moveNote(at: move.item.path, toFolder: move.to)
                        outcome.movedNotes.append(MovedNote(old: move.item.path, new: note.newPath))
                        if extractedStarPath != nil {
                            pendingNewStarredPaths.append(note.newPath)
                        }
                        report(note.failures)
                        // A refusal (ADR-0046 §D1) here is a note whose bytes moved on since
                        // `VaultMoveBatch.plan` was computed - a different thing from this
                        // outcome's own `refusals` above (§D7), which is about the batch not
                        // committing at all. Its own sentence (§D4: "different causes,
                        // different Italian sentences"), the same one
                        // `VaultController+Files.swift`'s `renameNote`/`moveNote` already use,
                        // not `report`'s failure wording.
                        reportRefusals(note.refusals)

                    case .board:
                        // No star and no moved note: a `.canvas` is neither (the reason
                        // `renameBoard` is not `renameFolder` with a different path).
                        let board = try boardOperations.moveBoard(at: move.item.path, toFolder: move.to)
                        report(board.failures)

                    case .folder:
                        let folder = try folderOperations.moveFolder(at: move.item.path, toParent: move.to)
                        // A star is a path, so it moves with the file or it points at
                        // nothing (ADR-0012 §D6) - `renameFolder`'s own follow-up, once per
                        // note the directory took with it, folded into the same
                        // once-per-batch commit as the `.note` case above rather than
                        // saved per note here.
                        for moved in folder.movedNotes where extractStarForBatchedMove(moved.old) {
                            pendingNewStarredPaths.append(moved.new)
                        }
                        outcome.movedNotes.append(contentsOf: folder.movedNotes)
                        report(folder.failures)
                    }
                } catch {
                    // The file never moved, so a star taken from it above belongs back
                    // where it was - in memory only, since the batch has not saved yet and
                    // `starred.json` on disk was never touched for it.
                    if let oldPath = extractedStarPath {
                        restoreExtractedStar(oldPath)
                    }
                    // Named, not swallowed, and `move` is deliberately not appended to
                    // `moves`: the inverse the caller registers must describe what is
                    // actually on disk, so an item that did not move must not be in the
                    // batch that undo will try to move back.
                    outcome.failures.append("«\(move.item.path)»: \(error)")
                    continue
                }
                outcome.moves.append(move)
            }
            commitBatchedStarMoves(pendingNewStarredPaths)
            return outcome
        }
    }

    /// Says what a repoint could not rewrite, rather than dropping it.
    ///
    /// Not `MoveBatchOutcome.failures`, which is about an item that did **not** move: the
    /// item this is called for moved, and only a reference to it was left pointing at the
    /// old path. So the visible channel is the session's own problem list, which
    /// `VaultController.problems` already surfaces. `renameFolder` reports the same class
    /// of failure from the facade side; the difference is only which of the two holds the
    /// list.
    private func report(_ failures: [String]) {
        for failure in failures {
            recordProblem("riferimento non aggiornato: \(failure)")
        }
    }

    /// Says a stale-write refusal in its own sentence, not `report`'s failure wording
    /// (ADR-0046 §D4): "this note could not be written" and "this note changed under me,
    /// so I did not write it" have different causes and different severities, and
    /// `VaultWriteRefusal.movedOn(_).description` is the one Italian sentence for the
    /// second - the same one `VaultController+Files.swift`'s `renameNote`/`moveNote`
    /// already reuse rather than writing a second wording of it here.
    ///
    /// Internal, not `private`: `Tests/VaultMoveTests.swift` drives it directly, the same
    /// `writeGuarded`/`writeFileGuarded` reason (`VaultSession.swift`) - a genuine stale
    /// write cannot be forced deterministically through the full `moveItems` batch (the
    /// plan-then-write window has no controllable suspension point), so the wording is
    /// exercised this way rather than raced.
    func reportRefusals(_ refusals: [String]) {
        for refusal in refusals {
            recordProblem(VaultWriteRefusal.movedOn(refusal).description)
        }
    }
}
