import Foundation

// The folder *move* verb, in a file of its own (ADR-0026 §D1, §D7).
//
// Split out for the reason `VaultController+Move.swift` and `VaultSession+Move.swift` are
// their own files at the two layers above this one, and at the same seam: ADR-0026 added a
// whole second verb - plan, outcome, performer - beside a rename verb that was already the
// bulk of `FolderFileOperations.swift`, which took that file past the 400 lines SwiftLint
// warns at and its struct body past 250. A move is `renamePlan`'s mirror (it keeps the name
// and changes the parent, where a rename keeps the parent and changes the name), which is
// exactly the kind of self-contained half that moves cleanly. Nothing about the verb changed
// in the move.
extension FolderFileOperations {
    // MARK: - ADR-0026: Move (§D1, §D7)

    /// What a folder *move* would change: the folder's own name is kept, only its
    /// parent changes - the mirror of `renamePlan`, which keeps the parent and changes
    /// the name (ADR-0026 §D1).
    struct MovePlan: Equatable, Sendable {
        var newPath: String
        var boardChanges: [VaultFileChange] = []
        var failures: [String] = []
    }

    /// What `moveFolder` would do, read from where the folder still is - nothing has
    /// moved yet when this runs (ADR-0026 §D1).
    ///
    /// `renamePlan`'s reference classes, unchanged: **one** changes, `.canvas` node paths
    /// repointed by prefix vault-wide, and nothing else - no wikilink (it names a note by
    /// title) and no `^[[board.canvas]]` marker (it names a bare file name, and a move
    /// changes neither a title nor a file name, ADR-0026 §D7). No name validation either:
    /// the only name involved is the one the folder already carries.
    ///
    /// Two refusals, in this order. `wouldNest` first, because a folder dropped onto
    /// itself or into one of its own descendants is not a collision and must not be
    /// reported as one (§D5, R-06); the prefix is `"\(oldFolder)/"` and never `oldFolder`,
    /// so a sibling called `a-altro` is not a descendant of `a` - `repointing`'s own rule.
    /// `alreadyExists` second, for a name already taken at the destination (R-07).
    func movePlan(_ relativePath: String, toParent parent: String) throws -> MovePlan {
        let oldFolder = Self.normalized(relativePath)
        guard !oldFolder.isEmpty else {
            throw FileOperationError.failed("la radice del vault non si sposta")
        }

        let destination = Self.normalized(parent)
        let name = (oldFolder as NSString).lastPathComponent
        let newFolder = destination.isEmpty ? name : "\(destination)/\(name)"

        guard isDirectory(oldFolder) else { throw FileOperationError.missing(relativePath) }
        guard destination != oldFolder, !destination.hasPrefix("\(oldFolder)/") else {
            throw FileOperationError.wouldNest(oldFolder)
        }
        guard newFolder == oldFolder || !exists(newFolder) else {
            throw FileOperationError.alreadyExists(newFolder)
        }

        var plan = MovePlan(newPath: newFolder)
        guard newFolder != oldFolder else { return plan }

        let boards = repointBoardsPlan(from: oldFolder, to: newFolder)
        plan.boardChanges = boards.changes
        plan.failures.append(contentsOf: boards.failures)
        return plan
    }

    /// What a folder move actually did (ADR-0026 §D1).
    struct MoveOutcome: Equatable, Sendable {
        var newPath: String
        var movedNotes: [MovedNote] = []
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }

    /// Moves the directory under a different parent - same folder name, never a rename -
    /// carrying everything inside it, then writing every planned repoint (ADR-0026 §D1,
    /// §D7).
    ///
    /// `renameFolder`'s order and `renameFolder`'s reasons. The move is one operation
    /// that either happens or does not; the repoints are many, each of which can fail on
    /// its own, so doing them the other way round would leave the vault pointing at a
    /// folder that does not exist yet if the move then failed. And the walk runs *before*
    /// anything moves: afterwards there is nothing at the old path to enumerate, and the
    /// caller needs both halves of each pair to follow its tabs and carry its stars.
    ///
    /// A board *inside* the moved folder that a plan rewrote is written at its new path:
    /// the directory carried it there, and `repointBoardsPlan`'s `writePath` substitution
    /// already computed where that is.
    func moveFolder(at relativePath: String, toParent parent: String) throws -> MoveOutcome {
        let plan = try movePlan(relativePath, toParent: parent)
        let oldFolder = Self.normalized(relativePath)

        // `movePlan` above has already thrown if `oldFolder` does not exist, so `walk`
        // returning nil here is unreachable in practice - the fallback exists only to
        // satisfy the optional PG-048 introduced, not because a real folder is missing.
        let movedNotes = (walk(oldFolder)?.notePaths ?? []).map {
            MovedNote(old: $0, new: Self.repointing($0, from: oldFolder, to: plan.newPath))
        }

        if plan.newPath != oldFolder {
            do {
                let destination = store.root.appending(
                    path: plan.newPath, directoryHint: .isDirectory
                )
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(
                    at: store.root.appending(path: oldFolder, directoryHint: .isDirectory),
                    to: destination
                )
            } catch {
                throw FileOperationError.failed("spostamento cartella: \(error.localizedDescription)")
            }
        }

        var outcome = MoveOutcome(
            newPath: plan.newPath, movedNotes: movedNotes, failures: plan.failures
        )
        let boards = VaultPlanApplication.apply(plan.boardChanges) {
            try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic)
        }
        outcome.rewrittenPaths.append(contentsOf: boards.rewrittenPaths)
        outcome.failures.append(contentsOf: boards.failures)
        return outcome
    }
}
