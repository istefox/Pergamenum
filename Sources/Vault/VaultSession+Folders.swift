import Foundation

/// Renaming and trashing a folder - the session half (ADR-0022 §D1).
///
/// No `transaction`: a directory has no journal representation (ADR-0022 §D6, F7), so
/// unlike `VaultSession+Files` this file writes directly, through
/// `FolderFileOperations`, and carries the stars along by hand (`moveStar`,
/// `forgetStar`, ADR-0012 §D6).
///
/// Not reachable from `VaultAPI`, and therefore not from `perg` or the MCP server:
/// a write that `--dry-run` cannot rehearse and `undo` cannot reverse would break the
/// guarantee ADR-0007 §D6 makes to every connector caller. The exclusion is mechanical
/// rather than a promise - `sharedSources` in `Project.swift` names each `Sources/Vault`
/// file one at a time, and it does not name this one.
extension VaultSession {
    private var folderOperations: FolderFileOperations { FolderFileOperations(store: store) }

    /// Renames a folder, carries the star of every moved note to its new path, and
    /// returns what the facade needs to follow tabs and RECENTI.
    func renameFolder(at relativePath: String, to newName: String) throws -> FolderFileOperations.RenameOutcome {
        let outcome = try folderOperations.renameFolder(
            at: relativePath, to: newName, knownPaths: index.allNotes.map(\.relativePath)
        )
        // A star is a path, so it moves with the file or it points at nothing
        // (ADR-0012 §D6) - the same follow-up a note rename performs, once per note
        // the folder took with it.
        for moved in outcome.movedNotes {
            moveStar(from: moved.old, to: moved.new)
        }
        return outcome
    }

    /// Trashes a folder and forgets the star of every note it removed.
    ///
    /// The caller confirms first: this does the deleting, it does not ask.
    func trashFolder(at relativePath: String) throws -> (url: URL?, trashedNotePaths: [String]) {
        let result = try folderOperations.trashFolder(at: relativePath)
        for path in result.trashedNotePaths {
            forgetStar(path)
        }
        return result
    }
}
