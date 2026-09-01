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
struct BoardFileOperations {
    let store: NoteStore

    /// Built here rather than injected, the same reasoning `FolderFileOperations`
    /// gives: `CanvasStore` is a value over the same root, and what this file needs
    /// from it - `allBoards()`, "every board in the vault" - is a walk with exclusion
    /// rules that would be a second spelling of an enumeration that already has one.
    private var canvas: CanvasStore { CanvasStore(root: store.root) }

    /// Built here for the same reason `canvas` above is, and reached for exactly one
    /// thing: `repointBoardsPlan(from:to:)`, the vault-wide `.canvas` node pass. It reads
    /// two paths and repoints every node naming the first, which is the same question
    /// whether the thing that moved was a directory or a file - so a board rename runs
    /// that loop rather than keeping a third copy of it (ADR-0025 §D6).
    private var folderOperations: FolderFileOperations { FolderFileOperations(store: store) }

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
    ///
    /// Two reference classes change and no third one does. The board's file name is
    /// rewritten in every note that named it - the `^[[old.canvas]]` marker and the plain
    /// `[[old.canvas]]` link are the same rewrite (ADR-0021 §D3, ADR-0022 §D3) - unless
    /// the name is ambiguous, and `.canvas` node paths pointing at this exact file are
    /// repointed vault-wide. **No ordinary `[[Nota]]` wikilink is touched**: a wikilink
    /// names a note by title and a board rename changes no title.
    func renamePlan(
        _ relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> BoardRenamePlan {
        // `NoteName.validate` rather than a rule of this file's own: it is what
        // `FolderFileOperations.validate` delegates to and therefore what the sheet
        // renders through `ConformanceText.lines`, so a board name that is refused here
        // is refused with wording the user has already seen (ADR-0022 §D11).
        let violations = NoteName.validate(newName)
        guard violations.isEmpty else { throw FileOperationError.invalidTitle(violations) }

        let oldPath = Self.normalized(relativePath)
        let oldName = (oldPath as NSString).lastPathComponent
        let folder = (oldPath as NSString).deletingLastPathComponent
        let newFileName = "\(newName).\(CanvasStore.fileExtension)"
        let newPath = folder.isEmpty ? newFileName : "\(folder)/\(newFileName)"

        guard isFile(oldPath) else { throw FileOperationError.missing(relativePath) }
        guard newPath == oldPath || !exists(newPath) else {
            throw FileOperationError.alreadyExists(newPath)
        }

        var plan = BoardRenamePlan(newPath: newPath)
        guard newPath != oldPath else { return plan }

        // The relocated ADR-0022 §D4 guard (ADR-0025 §D6). `WorkspaceBoardResolver` and
        // `IndexSnapshot.tasks(assignedToWorkspace:)` match a board by file name alone,
        // so two boards sharing one - which this chain makes legal, not impossible - make
        // every marker for either of them ambiguous. Rewriting them would repoint
        // references this rename never touched, so the name-level pass is dropped whole
        // and reported.
        let sharing = canvas.allBoards().filter {
            WorkspaceBoardResolver.matches($0, workspacePath: oldName)
        }
        if sharing.count > 1 {
            plan.failures.append(
                "«\(oldName)» nomina \(sharing.count) board: marker e link lasciati invariati"
            )
        } else {
            for path in knownPaths {
                let text: String
                do {
                    (_, text) = try store.read(path)
                } catch {
                    plan.failures.append("\(path): \(error)")
                    continue
                }
                guard let updated = NoteRename.rewritingLinks(
                    in: text, from: oldName, to: newFileName
                ) else { continue }
                // No path substitution: renaming a board moves one file and no note
                // with it, so every note is still where it was read from.
                plan.noteChanges.append(NoteFileOperations.FileChange(
                    path: path, before: text, after: updated
                ))
            }
        }

        // The one vault-wide node repoint, run rather than copied (ADR-0025 §D6): a card
        // pointing at this board names its full path, which is unambiguous however many
        // files share the last component - so it is repointed even when the guard above
        // fired.
        let boards = folderOperations.repointBoardsPlan(from: oldPath, to: newPath)
        plan.boardChanges = boards.changes
        plan.failures.append(contentsOf: boards.failures)
        return plan
    }

    /// What a board rename actually did: its destination and anything that failed
    /// along the way.
    struct RenameOutcome: Equatable, Sendable {
        var newPath: String
        var failures: [String] = []
    }

    /// Renames `<folder>/<old>.canvas` to `<folder>/<new>.canvas` - same folder, never
    /// a move - refusing a name collision before writing anything, then rewriting the
    /// marker and repointing board nodes (ADR-0025 §D6).
    ///
    /// The plan is computed first and the file moved second, and both happen before a
    /// single rewrite: the move is one operation that either happens or does not, while
    /// the rewrites are many and each can fail on its own. A collision or a missing file
    /// throws out of `renamePlan` with nothing written at all, which is what makes
    /// "refuses before writing" a property of the code rather than of the order somebody
    /// happened to call things in (`FolderFileOperations.renameFolder`'s own argument).
    func renameBoard(
        at relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> RenameOutcome {
        let plan = try renamePlan(relativePath, to: newName, knownPaths: knownPaths)
        let oldPath = Self.normalized(relativePath)

        if plan.newPath != oldPath {
            do {
                try FileManager.default.moveItem(
                    at: store.url(for: oldPath), to: store.url(for: plan.newPath)
                )
            } catch {
                throw FileOperationError.failed("rinomina board: \(error)")
            }
        }

        var outcome = RenameOutcome(newPath: plan.newPath, failures: plan.failures)
        for change in plan.noteChanges {
            do {
                try store.write(change.after, to: change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        // Written as bytes rather than through `NoteStore.write`: a `.canvas` is not a
        // note and the planned text is already the encoded document
        // (`FolderFileOperations.renameFolder` writes its own the same way).
        for change in plan.boardChanges {
            do {
                try Data(change.after.utf8).write(to: store.url(for: change.path), options: .atomic)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        return outcome
    }

    /// Moves the `.canvas` at `relativePath` to the Finder's Trash and returns the
    /// resulting URL - `trashItem`, never `removeItem` (ADR-0022 §D7), which is what
    /// proves the file was trashed rather than unlinked. No marker rewrite: an
    /// orphaned `^[[x.canvas]]` is already a first-class outcome
    /// (`WorkspaceBoardResolution.notFound`, ADR-0025 F9), the same story a note
    /// delete already tells for a dangling wikilink.
    func trashBoard(at relativePath: String) throws -> URL? {
        let board = Self.normalized(relativePath)
        guard isFile(board) else { throw FileOperationError.missing(relativePath) }

        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(
                at: store.url(for: board), resultingItemURL: &resulting
            )
        } catch {
            throw FileOperationError.failed("eliminazione board: \(error)")
        }
        return resulting as URL?
    }

    // MARK: - ADR-0026: Move (§D1, §D7)

    /// What a board *move* would change: the file name is kept, only the folder it
    /// sits in changes - the mirror of `renamePlan`, which keeps the folder and changes
    /// the name (ADR-0026 §D1).
    struct MovePlan: Equatable, Sendable {
        var newPath: String
        var boardChanges: [NoteFileOperations.FileChange] = []
        var failures: [String] = []
    }

    /// What `moveBoard` would do, read from where the board still is - nothing has moved
    /// yet when this runs (ADR-0026 §D1).
    ///
    /// **One** reference class changes: `.canvas` node paths naming this exact file,
    /// repointed vault-wide through the same `repointBoardsPlan` a rename runs. Nothing
    /// else. No `^[[x.canvas]]` marker and no `[[x.canvas]]` link is rewritten, because
    /// both name a bare **file name** and a move changes no file name (ADR-0026 §D7) -
    /// which is also why ADR-0022 §D4's relocated ambiguity guard is not consulted here:
    /// a move cannot make an already-ambiguous name resolve any differently.
    ///
    /// No name validation either: the only name involved is the one the board already
    /// carries, and refusing it now would refuse a file the vault already holds.
    func movePlan(_ relativePath: String, toFolder folder: String) throws -> MovePlan {
        let oldPath = Self.normalized(relativePath)
        let fileName = (oldPath as NSString).lastPathComponent
        let destination = Self.normalized(folder)
        let newPath = destination.isEmpty ? fileName : "\(destination)/\(fileName)"

        guard isFile(oldPath) else { throw FileOperationError.missing(relativePath) }
        guard newPath == oldPath || !exists(newPath) else {
            throw FileOperationError.alreadyExists(newPath)
        }

        var plan = MovePlan(newPath: newPath)
        guard newPath != oldPath else { return plan }

        let boards = folderOperations.repointBoardsPlan(from: oldPath, to: newPath)
        plan.boardChanges = boards.changes
        plan.failures.append(contentsOf: boards.failures)
        return plan
    }

    /// What a board move actually did (ADR-0026 §D1).
    struct MoveOutcome: Equatable, Sendable {
        var newPath: String
        var failures: [String] = []
    }

    /// Moves `<old folder>/<name>.canvas` to `<new folder>/<name>.canvas` - same file
    /// name, never a rename - refusing a collision before writing anything, then
    /// repointing every card that named the old path (ADR-0026 §D1, §D7).
    ///
    /// `renameBoard`'s order, and for `renameBoard`'s reason: the plan is computed and
    /// the file moved before a single rewrite, because the move is one operation that
    /// either happens or does not while the rewrites are many and each can fail on its
    /// own. A collision or a missing file throws out of `movePlan` with nothing written
    /// at all.
    ///
    /// The destination folder is created if it is not there yet - the same
    /// `createDirectory(withIntermediateDirectories:)` `renameFolder` and
    /// `NoteFileOperations.move` both make before their own `moveItem`.
    func moveBoard(at relativePath: String, toFolder folder: String) throws -> MoveOutcome {
        let plan = try movePlan(relativePath, toFolder: folder)
        let oldPath = Self.normalized(relativePath)

        if plan.newPath != oldPath {
            do {
                let destination = store.url(for: plan.newPath)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(at: store.url(for: oldPath), to: destination)
            } catch {
                throw FileOperationError.failed("spostamento board: \(error)")
            }
        }

        var outcome = MoveOutcome(newPath: plan.newPath, failures: plan.failures)
        // Written as bytes rather than through `NoteStore.write`, for `renameBoard`'s
        // reason: a `.canvas` is not a note and the planned text is already the encoded
        // document. The board that moved is written at its **new** path, which is what
        // `repointBoardsPlan`'s `writePath` substitution already computed.
        for change in plan.boardChanges {
            do {
                try Data(change.after.utf8).write(to: store.url(for: change.path), options: .atomic)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        return outcome
    }

    // MARK: - Paths

    /// A vault-relative path with the leading and trailing slashes a caller may have
    /// carried in, removed - `FolderFileOperations.normalized`'s trim, applied to a file
    /// path so `/A/x.canvas` and `A/x.canvas` name the same board here too.
    private static func normalized(_ relativePath: String) -> String {
        relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false))
    }

    /// There, and not a directory: a folder may share a name with a `.canvas` beside it
    /// (`CanvasStore.createBoard`), so "the file exists" is not the same question as
    /// "something with this path exists".
    private func isFile(_ relativePath: String) -> Bool {
        var flag: ObjCBool = false
        let found = FileManager.default.fileExists(
            atPath: store.url(for: relativePath).path(percentEncoded: false), isDirectory: &flag
        )
        return found && !flag.boolValue
    }
}
