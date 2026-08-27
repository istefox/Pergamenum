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
/// `Tests/VaultMoveTests.swift` (ADR-0026, this plan's Task 3) owns this signature; the
/// body here is a placeholder so the target builds - the real dispatch is the code
/// step's, not the test step's.
extension VaultSession {
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
    func moveItems(_ items: [VaultItemRef], into destination: String) throws -> MoveBatchOutcome {
        MoveBatchOutcome()
    }
}
