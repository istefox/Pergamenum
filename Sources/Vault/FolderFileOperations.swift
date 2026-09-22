import Foundation

/// Folder-shaped rules and writes: validation, collision, content counts, and the
/// rename/delete verbs a Workspace folder needs (ADR-0022 §D1).
///
/// Modelled on `NoteFileOperations`'s direct-write half (`rename`/`move`/`trash`,
/// ADR-0016 §D6 F8): a plan is computed without touching disk, then performed in one
/// pass. Unlike the note verbs, a folder verb is not journalled (ADR-0022 §D6) - there
/// is no `VaultSession+Journal` counterpart to call through, because the journal's
/// vocabulary is one file's text and a directory has none.
struct FolderFileOperations {
    let store: NoteStore

    /// Test-only observability: called once per pass this type makes over
    /// `canvas.allBoards()` while computing a repoint - never once per node, never once per
    /// file it decides to rewrite. A no-op default costs one branch and changes no
    /// production behaviour; nothing outside a test ever sets it, and each test constructs
    /// its own `FolderFileOperations` value, so there is no shared state for two tests to
    /// race on. Exists so `Tests/VaultBatchMoveTests.swift` can assert R-05's "one walk for
    /// the whole batch" claim exactly, rather than inferring it from output shape alone
    /// (ADR-0041 §D8, Task 7).
    var onBoardsWalk: () -> Void = {}

    /// Built here rather than injected: `CanvasStore` is a value over the same root, and
    /// what this file needs from it - `allBoards()`, "every board in the vault" (F4) -
    /// is a walk with exclusion rules that would be a second spelling of an enumeration
    /// that already has one. It is asked for the node repoint and for nothing else: a
    /// folder rename renames no `.canvas` and rewrites no marker any more (ADR-0025 §D6),
    /// so nothing here derives a board from the name of the folder holding it.
    private var canvas: CanvasStore { CanvasStore(root: store.root) }

    // MARK: - Task 1: validation, collision, content counts (R-03, R-04, R-10)

    /// Delegates to `NoteName.validate`: a folder name follows the same rules a note
    /// title does (`/` is already in `NoteName.forbiddenCharacters`).
    ///
    /// A delegation rather than a second rule set, deliberately: the sheets render the
    /// violations through `ConformanceText.lines`, so a folder that answered to
    /// different rules would produce violation text describing a rule the user has
    /// never seen anywhere else in the app. `.`/`..` are the one exception: reused as
    /// `.containsForbiddenCharacter` rather than a new `NoteName.Violation` case (PG-045).
    static func validate(_ name: String) -> [NoteName.Violation] {
        var violations = NoteName.validate(name)
        if name == "." || name == ".." { violations.append(.containsForbiddenCharacter(".")) }
        return violations
    }

    /// Whether `name` is free inside `parent` - false for a directory *or* a file
    /// already there.
    ///
    /// The comparison is the file system's own: `fileExists` is asked about the
    /// candidate path and answers the way the volume behaves, which on this machine's
    /// case-insensitive APFS means `nuova` is unavailable once `Nuova` exists. Folding
    /// the case ourselves would be a guess that is wrong on a case-sensitive volume in
    /// exactly the direction that loses a folder.
    func nameIsAvailable(_ name: String, in parent: String) -> Bool {
        let relativePath = parent.isEmpty ? name : "\(parent)/\(name)"
        return !exists(relativePath)
    }

    /// Creates a real directory for a folder card, validated the same way rename and
    /// delete already are (PG-047). `CanvasStore.createFolder` on its own only checks
    /// `fileExists` - this is the one folder write that used to bypass this file's own
    /// rules, relying on a UI guard that not every creation surface has.
    func createFolder(named name: String, in parent: String) throws -> String {
        let violations = Self.validate(name)
        guard violations.isEmpty else { throw FileOperationError.invalidTitle(violations) }
        return try canvas.createFolder(named: name, in: parent)
    }

    /// Every `.md` note and every subdirectory under `folder`, counted recursively and
    /// skipping the descendants of any `VaultLayout.isExcludedDirectory` directory,
    /// exactly as `CanvasStore.allBoards()` does. The board file itself is not a note.
    ///
    /// `nil` when `folder` could not be read (PG-048) - a genuinely empty folder and a
    /// stale selection pointing at one that is gone are not the same answer, and a
    /// destructive-delete dialog reading this must not claim to know a count it never
    /// took.
    func contentCounts(at folder: String) -> (notes: Int, subfolders: Int)? {
        guard let walked = walk(folder) else { return nil }
        return (notes: walked.notePaths.count, subfolders: walked.subfolders)
    }

    /// One pass over a folder's subtree, answering the two questions anything here asks
    /// of it: which notes are inside (so their tabs and their stars can follow) and how
    /// many subfolders there are (so the delete confirmation can say).
    ///
    /// The walk no longer *mirrors* `CanvasStore.allBoards()`, it is the same one:
    /// `VaultWalk` (ADR-0041 §D3) skips the descendants of an excluded directory outright
    /// rather than filtering its files one at a time, so `.obsidian`, `.git`, `.trash` and
    /// our own `.pergamenum` are never entered - and, more to the point here, never
    /// counted. Two doc comments claiming to mirror each other is how the three copies
    /// drifted in the first place.
    ///
    /// `nil` when `folder` does not exist or its enumerator could not be built (PG-048) -
    /// never silently folded into "nothing here", which is the answer for a folder that
    /// exists and is empty.
    ///
    /// Not `private`: `moveFolder` reads it from `FolderFileOperations+Move.swift`, and
    /// `private` in Swift is file-scoped, so an extension in a sibling file cannot see it.
    /// Same reason as `repointBoardsPlan` above, which `BoardFileOperations` already
    /// reaches from outside this file.
    func walk(_ folder: String) -> (notePaths: [String], subfolders: Int)? {
        let boundary = VaultBoundary(root: store.root)
        let directory: URL
        if folder.isEmpty {
            directory = boundary.root
        } else {
            // A folder path that leaves the vault is not a folder this can count, and the
            // `nil` this signature already returns says so (ADR-0041 §D1/§D3).
            guard let resolved = try? boundary.url(for: folder) else { return nil }
            directory = resolved
        }

        // The existence check stays here rather than moving into the walk: an enumerator
        // over a directory that is not there is not `nil`, it is empty - measured - so
        // this is the only thing that still tells "gone" from "empty" (PG-048).
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        // Same two keys as before the unification, for `CanvasStore.walk()`'s reason: a
        // symlink to a directory is one to `.isDirectoryKey` and not to the URL's own
        // trailing separator, and what a delete dialog counts should not change here.
        guard let walk = try? VaultWalk(
            boundary: boundary, subfolder: folder, keys: [.isDirectoryKey, .nameKey]
        ) else {
            return nil
        }

        var notePaths: [String] = []
        var subfolders = 0
        walk.forEach { file in
            if file.isDirectory {
                subfolders += 1
                return
            }
            guard file.url.pathExtension.lowercased() == "md" else { return }
            notePaths.append(file.relativePath)
        }
        return (notePaths, subfolders)
    }

    // MARK: - Task 2: the rename plan, computed off disk (R-06, R-07)

    /// What a folder rename would change: its destination and the boards vault-wide
    /// whose cards would be repointed (ADR-0022 §D2.1).
    ///
    /// `noteChanges` stays and is always empty. It is the field the tests read to state
    /// what this operation does *not* do: a folder rename rewrites no note text at all
    /// since ADR-0025 §D6, and a guarantee spelled as an empty list the performer still
    /// writes through is one a future planner can break loudly rather than silently.
    struct FolderRenamePlan: Equatable, Sendable {
        var newPath: String
        var noteChanges: [VaultFileChange] = []
        var boardChanges: [VaultFileChange] = []
        var failures: [String] = []
    }

    /// What `renameFolder` would do, read from where the folder still is - nothing has
    /// moved yet when this runs (ADR-0022 §D2.1, ADR-0025 §D6).
    ///
    /// **One** reference class changes: `.canvas` node paths, repointed by prefix,
    /// vault-wide. Nothing else. No `.canvas` file is renamed, because no board is named
    /// after its folder any more (ADR-0025 §D1), so no note holds a stale board file name
    /// for this operation to rewrite and ADR-0022 §D4's ambiguity guard has nothing to
    /// guard - it belongs to `BoardFileOperations.renamePlan` now (R-09). **No ordinary
    /// `[[Nota]]` wikilink is touched** either: a wikilink names a note by title and a
    /// folder rename changes no title (ADR-0022 §F3).
    func renamePlan(
        _ relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> FolderRenamePlan {
        let violations = Self.validate(newName)
        guard violations.isEmpty else { throw FileOperationError.invalidTitle(violations) }

        let oldFolder = Self.normalized(relativePath)
        guard !oldFolder.isEmpty else {
            throw FileOperationError.failed("la radice del vault non si rinomina")
        }

        let parent = (oldFolder as NSString).deletingLastPathComponent
        let newFolder = parent.isEmpty ? newName : "\(parent)/\(newName)"

        guard isDirectory(oldFolder) else { throw FileOperationError.missing(relativePath) }
        guard newFolder == oldFolder || !exists(newFolder) else {
            throw FileOperationError.alreadyExists(newFolder)
        }

        var plan = FolderRenamePlan(newPath: newFolder)

        let boards = repointBoardsPlan(from: oldFolder, to: newFolder)
        plan.boardChanges = boards.changes
        plan.failures.append(contentsOf: boards.failures)
        return plan
    }

    /// What repointing every board's cards would change, read rather than written.
    ///
    /// The prefix is `<old>/` and never `<old>`: a sibling folder called
    /// `vecchio-altro` starts with the same characters and has nothing to do with this
    /// rename. Each document is decoded and re-encoded through `CanvasDocument` rather
    /// than patched as text, so a board written by Obsidian keeps the keys this app
    /// does not know about (`NoteFileOperations.repointBoards` makes the same choice).
    ///
    /// Not private, and `oldPath`/`newPath` rather than `oldFolder`/`newFolder`, because
    /// `BoardFileOperations.renamePlan` runs this same pass for a **file** path
    /// (ADR-0025 §D6): a node's `file` matches on the exact-path arm and no node can
    /// carry the `<old>/` prefix of a `.canvas`, so the rule is one rule and there is no
    /// third copy of this loop in the repository.
    func repointBoardsPlan(
        from oldPath: String,
        to newPath: String
    ) -> (changes: [VaultFileChange], failures: [String]) {
        guard oldPath != newPath else { return ([], []) }
        onBoardsWalk()
        var changes: [VaultFileChange] = []
        var failures: [String] = []

        for boardPath in canvas.allBoards() {
            guard let url = try? store.url(for: boardPath),
                  let data = try? Data(contentsOf: url),
                  var document = try? CanvasDocument(data: data)
            else { continue }

            var changed = false
            for index in document.nodes.indices {
                guard case .file(let path, let subpath) = document.nodes[index].kind,
                      path == oldPath || path.hasPrefix("\(oldPath)/")
                else { continue }
                document.nodes[index].kind = .file(
                    path: Self.repointing(path, from: oldPath, to: newPath), subpath: subpath
                )
                changed = true
            }
            guard changed else { continue }

            // Where the performer will find this board once what moved has moved: the
            // renamed directory carried it along, or - for a board rename - it *is* the
            // file that moved, which the same substitution answers for.
            let writePath = Self.repointing(boardPath, from: oldPath, to: newPath)

            guard let before = String(bytes: data, encoding: .utf8) else {
                failures.append("\(boardPath): non leggibile come testo")
                continue
            }
            do {
                let encoded = try document.encoded()
                guard let after = String(bytes: encoded, encoding: .utf8) else {
                    failures.append("\(boardPath): non codificabile come testo")
                    continue
                }
                changes.append(VaultFileChange(
                    path: writePath, before: before, after: after
                ))
            } catch {
                failures.append("\(boardPath): \(error)")
            }
        }
        return (changes, failures)
    }

    /// Real batched form of `repointBoardsPlan(from:to:)` above (ADR-0041 §D8, Task 7):
    /// every path a batch moved, repointed together in **one** pass over
    /// `canvas.allBoards()` rather than one pass per move.
    ///
    /// Two moves that touch the same board merge into **one** `VaultFileChange` for that
    /// board, every node it repoints carried in the same re-encoded document - not one
    /// change per move, which would each read the board's original, still-unwritten bytes
    /// and have the later one silently discard the earlier one's repoint once a caller fed
    /// both into `VaultPlanApplication.apply` in order (the exact drift ADR-0041 names).
    /// `onBoardsWalk()` fires exactly once for the whole call; an empty batch (after
    /// dropping any no-op `from == to` pair) returns without walking at all, matching the
    /// single-pair form's own early-out.
    ///
    /// `failures` here still names a board, same as the single-pair form, but a caller
    /// should read an entry as the **batch's** failure rather than any one move's: several
    /// of the batch's moves can all repoint a node on the same board, so there is no single
    /// move it would be correct to blame that board's encode failure on.
    func repointBoardsPlan(
        moves: [(from: String, to: String)]
    ) -> (changes: [VaultFileChange], failures: [String]) {
        let moves = moves.filter { $0.from != $0.to }
        guard !moves.isEmpty else { return ([], []) }
        onBoardsWalk()
        var changes: [VaultFileChange] = []
        var failures: [String] = []

        for boardPath in canvas.allBoards() {
            guard let url = try? store.url(for: boardPath),
                  let data = try? Data(contentsOf: url),
                  var document = try? CanvasDocument(data: data)
            else { continue }

            var changed = false
            for index in document.nodes.indices {
                guard case .file(let path, let subpath) = document.nodes[index].kind,
                      let move = moves.first(where: { path == $0.from || path.hasPrefix("\($0.from)/") })
                else { continue }
                document.nodes[index].kind = .file(
                    path: Self.repointing(path, from: move.from, to: move.to), subpath: subpath
                )
                changed = true
            }
            guard changed else { continue }

            // Where this board itself lands, the same substitution a node's does: a board
            // that is itself one of the batch's moved paths (a board move riding along in
            // the same batch) writes to its own new location; every other board stays
            // exactly where it is.
            let writePath = moves.reduce(boardPath) { path, move in
                Self.repointing(path, from: move.from, to: move.to)
            }

            guard let before = String(bytes: data, encoding: .utf8) else {
                failures.append("\(boardPath): non leggibile come testo")
                continue
            }
            do {
                let encoded = try document.encoded()
                guard let after = String(bytes: encoded, encoding: .utf8) else {
                    failures.append("\(boardPath): non codificabile come testo")
                    continue
                }
                changes.append(VaultFileChange(path: writePath, before: before, after: after))
            } catch {
                failures.append("\(boardPath): \(error)")
            }
        }
        return (changes, failures)
    }

    // MARK: - Task 3: performing it (R-05, R-06, R-07, R-11)

    /// What a folder rename actually did: its destination, the notes it moved (old
    /// path, new path), every path it rewrote, and anything that failed along the way.
    struct RenameOutcome: Equatable, Sendable {
        var newPath: String
        var movedNotes: [MovedNote] = []
        var rewrittenPaths: [String] = []
        var failures: [String] = []
        /// Board paths whose bytes moved on between the plan and the write, refused
        /// rather than clobbered (ADR-0054 §D6). Declared after `failures` so every
        /// existing memberwise call stays valid (ADR-0046 §D4's compatibility rule).
        var refusals: [String] = []
    }

    /// Moves the directory and writes every planned change - in that order, and the
    /// order is the point.
    ///
    /// The move is one operation that either happens or does not; the repoints are many,
    /// each of which can fail on its own. Doing them the other way round would leave the
    /// vault pointing at a folder that does not exist yet if the move then failed - the
    /// argument `NoteFileOperations.rename` already makes for a note.
    ///
    /// No `.canvas` inside the folder is renamed: a board carries its own name and moves
    /// with the directory under it (ADR-0025 §D6, R-09). Renaming one here is what
    /// ADR-0022 §D5 did while a board was named after its folder, and the derivation that
    /// made it necessary is gone.
    func renameFolder(
        at relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> RenameOutcome {
        let plan = try renamePlan(relativePath, to: newName, knownPaths: knownPaths)
        let oldFolder = Self.normalized(relativePath)

        // Read before anything moves: afterwards there is nothing at the old path to
        // enumerate, and the caller needs both halves of each pair to follow its tabs.
        // `renamePlan` above has already thrown if `oldFolder` is missing, so `walk`
        // returning nil here is unreachable in practice (PG-048).
        let movedNotes = (walk(oldFolder)?.notePaths ?? []).map {
            MovedNote(old: $0, new: Self.repointing($0, from: oldFolder, to: plan.newPath))
        }

        // A same-name rename is admitted by the guard above (`newFolder == oldFolder`)
        // but has nothing to move - unguarded, `moveItem` throws "file already exists"
        // moving a directory onto itself (PG-049). `NoteFileOperations.rename` skips its
        // own move the same way on a no-op.
        if plan.newPath != oldFolder {
            do {
                let destination = store.root.appending(path: plan.newPath, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try FileManager.default.moveItem(
                    at: store.root.appending(path: oldFolder, directoryHint: .isDirectory),
                    to: destination
                )
            } catch {
                throw FileOperationError.failed("rinomina cartella: \(error.localizedDescription)")
            }
        }

        var outcome = RenameOutcome(
            newPath: plan.newPath, movedNotes: movedNotes, failures: plan.failures
        )

        let notes = VaultPlanApplication.apply(plan.noteChanges) {
            try store.write($0.after, to: $0.path)
        }
        // Guarded through the one repoint door (ADR-0054 §D6) rather than an unconditional
        // byte write - which is why `apply` takes the writer rather than assuming one
        // (ADR-0041 §D4).
        let boards = VaultPlanApplication.apply(plan.boardChanges, writing: canvas.writeRepoint)
        outcome.rewrittenPaths = notes.rewrittenPaths + boards.rewrittenPaths
        outcome.failures.append(contentsOf: notes.failures + boards.failures)
        outcome.refusals.append(contentsOf: boards.refusals)
        return outcome
    }

    /// Moves the whole folder to the Finder's Trash and reports every `.md` path that
    /// went with it, so the caller can close their tabs.
    ///
    /// `trashItem` and never `removeItem` (ADR-0022 §D7): a folder deleted by a
    /// misclick is recoverable there, this operation is not journalled, and the Trash
    /// is the only recovery story it has. The `resultingItemURL` is returned rather
    /// than discarded because it is what proves the folder was trashed rather than
    /// unlinked - `removeItem` could not produce one.
    func trashFolder(at relativePath: String) throws -> (url: URL?, trashedNotePaths: [String]) {
        let folder = Self.normalized(relativePath)
        guard !folder.isEmpty else {
            throw FileOperationError.failed("la radice del vault non si elimina")
        }
        guard isDirectory(folder) else { throw FileOperationError.missing(relativePath) }

        // The guard above has already confirmed `folder` exists, so `walk` returning
        // nil here is unreachable in practice (PG-048).
        let trashedNotePaths = walk(folder)?.notePaths ?? []
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(
                at: store.root.appending(path: folder, directoryHint: .isDirectory),
                resultingItemURL: &resulting
            )
        } catch {
            throw FileOperationError.failed("eliminazione: \(error.localizedDescription)")
        }
        return (resulting as URL?, trashedNotePaths)
    }

    // MARK: - ADR-0026: Move (§D1, §D7)
    //
    // In `FolderFileOperations+Move.swift`, which is also why the four helpers below carry
    // no `private`. See that file's header.

    // MARK: - Paths
    //
    // None of the four carries `private`: `FolderFileOperations+Move.swift` reads all of
    // them, and `private` in Swift is file-scoped, so an extension in a sibling file cannot
    // see it. Same reason as `repointBoardsPlan` above. They stay implementation detail by
    // convention rather than by keyword - nothing outside this type's own two files calls
    // any of them.

    /// A vault-relative path with the leading and trailing slashes a caller may have
    /// carried in, removed, so `01 Progetti/vecchio/` and `01 Progetti/vecchio` name the
    /// same folder here - the trim `BoardFileOperations` makes for a board path too.
    static func normalized(_ relativePath: String) -> String {
        relativePath.trimmingCharacters(in: .pathSlashes)
    }

    /// `path` as it will read once `oldFolder` has become `newFolder`. Unchanged for
    /// anything outside the renamed folder, which is what makes the prefix test `<old>/`
    /// rather than `<old>`.
    static func repointing(_ path: String, from oldFolder: String, to newFolder: String) -> String {
        if path == oldFolder { return newFolder }
        guard path.hasPrefix("\(oldFolder)/") else { return path }
        return newFolder + String(path.dropFirst(oldFolder.count))
    }

    /// A boundary violation answers `false` (ADR-0041 §D2, Task 2's decision for the
    /// `Bool`-returning sites), matching `VaultSession.exists`.
    func exists(_ relativePath: String) -> Bool {
        guard let url = try? store.url(for: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func isDirectory(_ relativePath: String) -> Bool {
        guard let url = try? store.url(for: relativePath) else { return false }
        var flag: ObjCBool = false
        let found = FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false), isDirectory: &flag
        )
        return found && flag.boolValue
    }
}
