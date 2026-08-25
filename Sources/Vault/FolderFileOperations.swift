import Foundation

/// Folder-shaped rules and writes: validation, collision, content counts, and the
/// rename/delete verbs a Workspace folder needs (ADR-0022 §D1).
///
/// Modelled on `NoteFileOperations`'s direct-write half (`rename`/`move`/`trash`,
/// ADR-0016 §D6 F8): a plan is computed without touching disk, then performed in one
/// pass. Unlike the note verbs, a folder verb is not journalled (ADR-0022 §D6) - there
/// is no `VaultSession+Journal` counterpart to call through.
///
/// **RED boundary** (plan `2026-08-25-workspace-ui-creazione-board-toolbar-e-r`, Tasks
/// 1-4): every method below is a signature the coder fills in next. Every body here
/// throws `.notImplementedYet` or returns an intentionally-wrong placeholder value -
/// never `fatalError()`, never a force-unwrap (`~/.claude/rules/swift.md`) - so the
/// target builds and the tests in `Tests/FolderFileOperationTests.swift` fail on their
/// assertions rather than on a compile error.
struct FolderFileOperations {
    let store: NoteStore

    enum OperationError: Error, CustomStringConvertible {
        case invalidTitle([NoteName.Violation])
        case alreadyExists(String)
        case missing(String)
        case failed(String)
        /// Marks a body not implemented yet. See the RED-boundary note above.
        case notImplementedYet

        var description: String {
            switch self {
            case .invalidTitle(let violations): "titolo non conforme: \(violations)"
            case .alreadyExists(let path): "esiste già: \(path)"
            case .missing(let path): "non esiste: \(path)"
            case .failed(let reason): reason
            case .notImplementedYet: "non ancora implementato"
            }
        }
    }

    // MARK: - Task 1: validation, collision, content counts (R-03, R-04, R-10)

    /// Delegates to `NoteName.validate`: a folder name follows the same rules a note
    /// title does (`/` is already in `NoteName.forbiddenCharacters`).
    static func validate(_ name: String) -> [NoteName.Violation] {
        []
    }

    /// Whether `name` is free inside `parent` - false for a directory *or* a file
    /// already there, compared the way the filesystem does (case-insensitive on this
    /// machine's volume), never by lowercasing the strings ourselves.
    func nameIsAvailable(_ name: String, in parent: String) -> Bool {
        true
    }

    /// Every `.md` note and every subdirectory under `folder`, counted recursively and
    /// skipping the descendants of any `VaultLayout.isExcludedDirectory` directory,
    /// exactly as `CanvasStore.allBoards()` does. The board file itself is not a note.
    func contentCounts(at folder: String) -> (notes: Int, subfolders: Int) {
        (0, 0)
    }

    // MARK: - Task 2: the rename plan, computed off disk (R-06, R-07)

    /// What a folder rename would change: its destination, its own board's rename (at
    /// the *post-move* paths the performer will use, ADR-0022 §D5), the notes whose
    /// task marker or board-filename link would be rewritten, and the boards
    /// vault-wide whose cards would be repointed.
    struct FolderRenamePlan {
        var newPath: String
        var boardRename: (from: String, to: String)?
        var noteChanges: [NoteFileOperations.FileChange] = []
        var boardChanges: [NoteFileOperations.FileChange] = []
        var failures: [String] = []
    }

    /// What `renameFolder` would do, read from where the folder still is - nothing has
    /// moved yet when this runs (ADR-0022 §D2-§D5).
    func renamePlan(
        _ relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> FolderRenamePlan {
        throw OperationError.notImplementedYet
    }

    // MARK: - Task 3: performing it (R-05, R-06, R-07, R-11)

    /// What a folder rename actually did: its destination, the notes it moved (old
    /// path, new path), every path it rewrote, and anything that failed along the way.
    struct RenameOutcome {
        var newPath: String
        var movedNotes: [(old: String, new: String)] = []
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }

    /// Moves the directory, renames its board file if it has one, and writes every
    /// planned change - in that order (ADR-0022 §D5, mirroring the argument
    /// `NoteFileOperations.rename` already makes for moving before rewriting).
    func renameFolder(
        at relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> RenameOutcome {
        throw OperationError.notImplementedYet
    }

    /// Moves the whole folder to the Finder's Trash (`FileManager.trashItem`, never
    /// `removeItem` - ADR-0022 §D7) and reports every `.md` path that went with it, so
    /// the caller can close their tabs.
    func trashFolder(at relativePath: String) throws -> (url: URL?, trashedNotePaths: [String]) {
        throw OperationError.notImplementedYet
    }
}
