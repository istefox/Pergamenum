import Foundation

/// Renaming and trashing a folder - the session half (ADR-0022 §D1).
///
/// No `transaction`: a directory has no journal representation (ADR-0022 §D6, F7), so
/// unlike `VaultSession+Files` this file writes directly, through
/// `FolderFileOperations`, and carries the stars along by hand (`moveStar`,
/// `forgetStar`, ADR-0012 §D6).
///
/// **RED boundary** (plan `2026-08-25-workspace-ui-creazione-board-toolbar-e-r`, Task
/// 4): the two bodies below are signatures only, both throwing
/// `FolderFileOperations.OperationError.notImplementedYet`; the coder fills them in
/// next. See `Tests/VaultSessionFolderOperationsTests.swift`.
extension VaultSession {
    private var folderOperations: FolderFileOperations { FolderFileOperations(store: store) }

    /// Renames a folder, carries the star of every moved note to its new path, and
    /// returns what the facade needs to follow tabs and RECENTI.
    func renameFolder(at relativePath: String, to newName: String) throws -> FolderFileOperations.RenameOutcome {
        throw FolderFileOperations.OperationError.notImplementedYet
    }

    /// Trashes a folder and forgets the star of every note it removed.
    func trashFolder(at relativePath: String) throws -> (url: URL?, trashedNotePaths: [String]) {
        throw FolderFileOperations.OperationError.notImplementedYet
    }
}
