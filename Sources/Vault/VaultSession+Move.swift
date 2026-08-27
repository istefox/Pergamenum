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
    struct MoveBatchOutcome {
        /// The moves the batch actually performed, in the order `VaultMoveBatch.plan`
        /// returned them - what `VaultController` hands to `boardAfterMove` and to
        /// `UndoManager.registerUndo`'s inverse.
        var moves: [VaultMove] = []
        /// Every note the batch carried, old path then new - what the facade needs to
        /// follow tabs and RECENTI, `renameFolder`'s own `movedNotes` shape.
        var movedNotes: [(old: String, new: String)] = []
        /// `VaultMoveBatch.Result.refused`'s reasons, verbatim, when the batch could not
        /// commit at all (ADR-0026 §D6, all-or-nothing) - empty on a successful batch.
        var refusals: [String] = []
    }

    /// Moves `items` into `destination` as one batch, all-or-nothing (ADR-0026 §D6).
    /// `destination` is a vault-relative folder path, the vault root spelled `""`
    /// (R-05).
    ///
    /// A refusal is a returned `MoveBatchOutcome` with `refusals` filled and `moves`
    /// empty, never a `throw`: the five rules of `VaultMoveBatch.plan` are the batch
    /// answering a question, and the caller has a dialog to name them in (R-07). What
    /// does throw is an operation that got past the plan and then failed on disk.
    func moveItems(_ items: [VaultItemRef], into destination: String) throws -> MoveBatchOutcome {
        var outcome = MoveBatchOutcome()

        switch VaultMoveBatch.plan(items, into: destination, exists: { exists($0) }) {
        case .refused(let reasons):
            outcome.refusals = reasons
            return outcome

        case .moves(let moves):
            for move in moves {
                switch move.item.kind {
                case .note:
                    // The existing journalled path (ADR-0026 §D2): `moveNote` writes
                    // through `transaction("note move")`, carries the star and repoints
                    // the cards. A second spelling of that verb here would be exactly the
                    // drift `CLAUDE.md`'s connector section is about.
                    let note = try moveNote(at: move.item.path, toFolder: move.to)
                    outcome.movedNotes.append((old: move.item.path, new: note.newPath))
                    report(note.failures)

                case .board:
                    // No star and no moved note: a `.canvas` is neither (the reason
                    // `renameBoard` is not `renameFolder` with a different path).
                    let board = try boardOperations.moveBoard(at: move.item.path, toFolder: move.to)
                    report(board.failures)

                case .folder:
                    let folder = try folderOperations.moveFolder(at: move.item.path, toParent: move.to)
                    // A star is a path, so it moves with the file or it points at nothing
                    // (ADR-0012 §D6) - `renameFolder`'s own follow-up, once per note the
                    // directory took with it.
                    for moved in folder.movedNotes {
                        moveStar(from: moved.old, to: moved.new)
                    }
                    outcome.movedNotes.append(contentsOf: folder.movedNotes)
                    report(folder.failures)
                }
                outcome.moves.append(move)
            }
            return outcome
        }
    }

    /// Says what a repoint could not rewrite, rather than dropping it.
    ///
    /// `MoveBatchOutcome` has no `failures` field - the batch either committed or
    /// refused, and a card left pointing at the old path is neither - so the visible
    /// channel is the session's own problem list, which `VaultController.problems`
    /// already surfaces. `renameFolder` reports the same class of failure from the facade
    /// side; the difference is only which of the two holds the list.
    private func report(_ failures: [String]) {
        for failure in failures {
            recordProblem("riferimento non aggiornato: \(failure)")
        }
    }
}
