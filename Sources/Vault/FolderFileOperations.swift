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
    /// never seen anywhere else in the app.
    static func validate(_ name: String) -> [NoteName.Violation] {
        NoteName.validate(name)
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
    /// The walk mirrors `CanvasStore.allBoards()`: an enumerator that skips the
    /// descendants of an excluded directory outright rather than filtering its files
    /// one at a time, so `.obsidian`, `.git`, `.trash` and our own `.pergamenum` are
    /// never entered - and, more to the point here, never counted.
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
        let directory = folder.isEmpty
            ? store.root
            : store.root.appending(path: folder, directoryHint: .isDirectory)

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else {
            return nil
        }

        var notePaths: [String] = []
        var subfolders = 0
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.name ?? url.lastPathComponent

            if values?.isDirectory == true {
                if VaultLayout.isExcludedDirectory(name) {
                    enumerator.skipDescendants()
                    continue
                }
                subfolders += 1
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            notePaths.append(VaultScanner.relativePath(of: url, under: store.root))
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
        var noteChanges: [NoteFileOperations.FileChange] = []
        var boardChanges: [NoteFileOperations.FileChange] = []
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
    ) -> (changes: [NoteFileOperations.FileChange], failures: [String]) {
        guard oldPath != newPath else { return ([], []) }
        var changes: [NoteFileOperations.FileChange] = []
        var failures: [String] = []

        for boardPath in canvas.allBoards() {
            let url = store.url(for: boardPath)
            guard let data = try? Data(contentsOf: url),
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
                changes.append(NoteFileOperations.FileChange(
                    path: writePath, before: before, after: after
                ))
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

        var outcome = RenameOutcome(
            newPath: plan.newPath, movedNotes: movedNotes, failures: plan.failures
        )

        for change in plan.noteChanges {
            do {
                try store.write(change.after, to: change.path)
                outcome.rewrittenPaths.append(change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
        for change in plan.boardChanges {
            do {
                try Data(change.after.utf8).write(to: store.url(for: change.path), options: .atomic)
                outcome.rewrittenPaths.append(change.path)
            } catch {
                outcome.failures.append("\(change.path): \(error)")
            }
        }
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
        relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// `path` as it will read once `oldFolder` has become `newFolder`. Unchanged for
    /// anything outside the renamed folder, which is what makes the prefix test `<old>/`
    /// rather than `<old>`.
    static func repointing(_ path: String, from oldFolder: String, to newFolder: String) -> String {
        if path == oldFolder { return newFolder }
        guard path.hasPrefix("\(oldFolder)/") else { return path }
        return newFolder + String(path.dropFirst(oldFolder.count))
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false))
    }

    func isDirectory(_ relativePath: String) -> Bool {
        var flag: ObjCBool = false
        let found = FileManager.default.fileExists(
            atPath: store.url(for: relativePath).path(percentEncoded: false), isDirectory: &flag
        )
        return found && flag.boolValue
    }
}
