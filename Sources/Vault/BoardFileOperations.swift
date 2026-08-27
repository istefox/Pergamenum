import Foundation

/// Board-shaped rules and writes: a rename plan computed off disk - including the
/// relocated ADR-0022 §D4 ambiguity guard - and performing it, rename on disk or
/// delete to the Trash (ADR-0025 §D6).
///
/// `FolderFileOperations`'s shape, re-aimed at a `.canvas` file instead of a directory:
/// a plan is computed without touching disk, then performed in one pass, writing
/// directly through `FileManager` and `NoteStore` (ADR-0022 §F8). Like the folder
/// verbs, a board verb is not journalled (§D6, ADR-0022 §D6): `WriteJournal`'s three
/// entry kinds cannot express "rename, then rewrite N notes and repoint M boards" as
/// one reversible unit (ADR-0016 §D1), and this file is deliberately absent from
/// `sharedSources` in `Project.swift` so no connector can reach a write that neither
/// `--dry-run` nor `undo` can answer for (ADR-0025 §D6/A10, ADR-0022 §D6).
///
/// TODO(ADR-0025 Task 7, RED phase): every body below is a placeholder that throws
/// `.notImplementedYet`. `Tests/BoardFileOperationsTests.swift` is red on its
/// assertions rather than on a missing symbol - the coder's GREEN pass fills these in,
/// reusing the vault-wide repoint loop `FolderFileOperations.swift` already runs
/// rather than writing a third one.
struct BoardFileOperations {
    let store: NoteStore

    /// Built here rather than injected, the same reasoning `FolderFileOperations`
    /// gives: `CanvasStore` is a value over the same root, and what this file needs
    /// from it - `allBoards()`, "every board in the vault" - is a walk with exclusion
    /// rules that would be a second spelling of an enumeration that already has one.
    private var canvas: CanvasStore { CanvasStore(root: store.root) }

    enum OperationError: Error, CustomStringConvertible {
        case invalidTitle([NoteName.Violation])
        case alreadyExists(String)
        case missing(String)
        case failed(String)
        /// Removed once every body below has a real implementation (ADR-0025 Task 7).
        case notImplementedYet

        var description: String {
            switch self {
            case .invalidTitle(let violations): "titolo non conforme: \(violations)"
            case .alreadyExists(let path): "esiste già: \(path)"
            case .missing(let path): "non esiste: \(path)"
            case .failed(let reason): reason
            case .notImplementedYet: "BoardFileOperations: non ancora implementato (ADR-0025 Task 7)"
            }
        }
    }

    /// What a board rename would change: its destination, the notes whose task marker
    /// or plain link would be rewritten, the boards vault-wide whose cards would be
    /// repointed, and anything that failed - including the relocated ADR-0022 §D4
    /// guard, which skips the note-rewrite pass whole and reports it when the old
    /// board's file name is ambiguous (ADR-0025 §D6).
    struct BoardRenamePlan {
        var newPath: String
        var noteChanges: [NoteFileOperations.FileChange] = []
        var boardChanges: [NoteFileOperations.FileChange] = []
        var failures: [String] = []
    }

    /// What `renameBoard` would do, read from where the board still is - nothing has
    /// moved yet when this runs (ADR-0025 §D6).
    ///
    /// A rename is always a new file name under the *same* folder, never a move: the
    /// destination is `<folder>/<newName>.canvas`.
    func renamePlan(
        _ relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> BoardRenamePlan {
        throw OperationError.notImplementedYet
    }

    /// What a board rename actually did: its destination, every path it rewrote, and
    /// anything that failed along the way.
    struct RenameOutcome {
        var newPath: String
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }

    /// Renames `<folder>/<old>.canvas` to `<folder>/<new>.canvas` - same folder, never
    /// a move - refusing a name collision before writing anything, then rewriting the
    /// marker and repointing board nodes (ADR-0025 §D6).
    func renameBoard(
        at relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> RenameOutcome {
        throw OperationError.notImplementedYet
    }

    /// Moves the `.canvas` at `relativePath` to the Finder's Trash and returns the
    /// resulting URL - `trashItem`, never `removeItem` (ADR-0022 §D7), which is what
    /// proves the file was trashed rather than unlinked. No marker rewrite: an
    /// orphaned `^[[x.canvas]]` is already a first-class outcome
    /// (`WorkspaceBoardResolution.notFound`, ADR-0025 F9), the same story a note
    /// delete already tells for a dangling wikilink.
    func trashBoard(at relativePath: String) throws -> URL? {
        throw OperationError.notImplementedYet
    }
}
