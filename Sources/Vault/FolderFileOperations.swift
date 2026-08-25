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

    /// Built here rather than injected: `CanvasStore` is a value over the same root,
    /// and the two things this file needs from it - `boardPath(forFolder:)` and
    /// `allBoards()` - are the definition of "which file backs this folder" (F1) and
    /// "every board in the vault" (F4). Deriving either by hand would be a second
    /// spelling of a mapping that already has one.
    private var canvas: CanvasStore { CanvasStore(root: store.root) }

    enum OperationError: Error, CustomStringConvertible {
        case invalidTitle([NoteName.Violation])
        case alreadyExists(String)
        case missing(String)
        case failed(String)

        var description: String {
            switch self {
            case .invalidTitle(let violations): "titolo non conforme: \(violations)"
            case .alreadyExists(let path): "esiste già: \(path)"
            case .missing(let path): "non esiste: \(path)"
            case .failed(let reason): reason
            }
        }
    }

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

    /// Every `.md` note and every subdirectory under `folder`, counted recursively and
    /// skipping the descendants of any `VaultLayout.isExcludedDirectory` directory,
    /// exactly as `CanvasStore.allBoards()` does. The board file itself is not a note.
    func contentCounts(at folder: String) -> (notes: Int, subfolders: Int) {
        let walked = walk(folder)
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
    private func walk(_ folder: String) -> (notePaths: [String], subfolders: Int) {
        let directory = folder.isEmpty
            ? store.root
            : store.root.appending(path: folder, directoryHint: .isDirectory)

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else {
            return ([], 0)
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
    ///
    /// Two reference classes change and no third one does. `.canvas` node paths are
    /// repointed by prefix, vault-wide, always. The folder's own board file name is
    /// rewritten in every note that named it - the `^[[old.canvas]]` marker and the
    /// plain `[[old.canvas]]` link are the same rewrite (ADR-0022 §D3) - unless the
    /// name is ambiguous (§D4). **No ordinary `[[Nota]]` wikilink is touched**: a
    /// wikilink names a note by title and a folder rename changes no title (§F3), so
    /// there is nothing there to rewrite.
    func renamePlan(
        _ relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> FolderRenamePlan {
        let violations = Self.validate(newName)
        guard violations.isEmpty else { throw OperationError.invalidTitle(violations) }

        let oldFolder = Self.normalized(relativePath)
        guard !oldFolder.isEmpty else {
            throw OperationError.failed("la radice del vault non si rinomina")
        }

        let parent = (oldFolder as NSString).deletingLastPathComponent
        let newFolder = parent.isEmpty ? newName : "\(parent)/\(newName)"

        guard isDirectory(oldFolder) else { throw OperationError.missing(relativePath) }
        guard newFolder == oldFolder || !exists(newFolder) else {
            throw OperationError.alreadyExists(newFolder)
        }

        var plan = FolderRenamePlan(newPath: newFolder)

        // The board file: named after its folder (F1), so exactly one of them changes
        // name, and only if it is there at all. A folder with no board has no marker
        // pointing at it either - `WorkspacePicker` lists real files (§D5).
        let oldBoardPath = canvas.boardPath(forFolder: oldFolder)
        let oldBoardName = (oldBoardPath as NSString).lastPathComponent
        let newBoardName = (canvas.boardPath(forFolder: newFolder) as NSString).lastPathComponent
        let hasBoard = exists(oldBoardPath)
        if hasBoard {
            plan.boardRename = (from: "\(newFolder)/\(oldBoardName)", to: "\(newFolder)/\(newBoardName)")
        }

        if hasBoard, oldBoardName != newBoardName {
            // `tasks(assignedToWorkspace:)` matches a board by file name alone (F5), so
            // two folders sharing a name make every marker for either of them
            // ambiguous. Rewriting them would break references this rename never
            // touched, so the name-level pass is dropped whole and reported (§D4).
            let sharing = canvas.allBoards().filter {
                ($0 as NSString).lastPathComponent.lowercased() == oldBoardName.lowercased()
            }
            if sharing.count > 1 {
                plan.failures.append(
                    "«\(oldBoardName)» nomina \(sharing.count) board: marker e link lasciati invariati"
                )
            } else {
                for path in knownPaths {
                    guard let (_, text) = try? store.read(path) else {
                        plan.failures.append("\(path): non leggibile")
                        continue
                    }
                    guard let updated = NoteRename.rewritingLinks(
                        in: text, from: oldBoardName, to: newBoardName
                    ) else { continue }
                    // The performer moves the directory before it writes anything, so a
                    // note inside the renamed folder is already at its new path by then.
                    plan.noteChanges.append(NoteFileOperations.FileChange(
                        path: Self.repointing(path, from: oldFolder, to: newFolder),
                        before: text,
                        after: updated
                    ))
                }
            }
        }

        let boards = repointBoardsPlan(from: oldFolder, to: newFolder, boardRename: plan.boardRename)
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
    private func repointBoardsPlan(
        from oldFolder: String,
        to newFolder: String,
        boardRename: (from: String, to: String)?
    ) -> (changes: [NoteFileOperations.FileChange], failures: [String]) {
        guard oldFolder != newFolder else { return ([], []) }
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
                      path.hasPrefix("\(oldFolder)/")
                else { continue }
                document.nodes[index].kind = .file(
                    path: Self.repointing(path, from: oldFolder, to: newFolder), subpath: subpath
                )
                changed = true
            }
            guard changed else { continue }

            // Where the performer will find this board once the directory has moved and
            // the folder's own board has been renamed inside it.
            var writePath = Self.repointing(boardPath, from: oldFolder, to: newFolder)
            if let boardRename, writePath == boardRename.from { writePath = boardRename.to }

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
    struct RenameOutcome {
        var newPath: String
        var movedNotes: [(old: String, new: String)] = []
        var rewrittenPaths: [String] = []
        var failures: [String] = []
    }

    /// Moves the directory, renames its board file if it has one, and writes every
    /// planned change - in that order, and the order is the point.
    ///
    /// The move is one operation that either happens or does not; the board rename and
    /// the text rewrites are many, each of which can fail on its own. Doing them the
    /// other way round would leave the vault pointing at a folder that does not exist
    /// yet if the move then failed - the argument `NoteFileOperations.rename` already
    /// makes for a note.
    ///
    /// The board file is renamed *with* the folder rather than after it: without that,
    /// `CanvasStore.boardPath(forFolder:)` names a file that is no longer there and
    /// `load(folder:)` returns `.empty` **without failing**, so the board reads blank
    /// while its content sits on disk under the old name (ADR-0022 §F1, §D5).
    func renameFolder(
        at relativePath: String,
        to newName: String,
        knownPaths: [String]
    ) throws -> RenameOutcome {
        let plan = try renamePlan(relativePath, to: newName, knownPaths: knownPaths)
        let oldFolder = Self.normalized(relativePath)

        // Read before anything moves: afterwards there is nothing at the old path to
        // enumerate, and the caller needs both halves of each pair to follow its tabs.
        let movedNotes = walk(oldFolder).notePaths.map {
            (old: $0, new: Self.repointing($0, from: oldFolder, to: plan.newPath))
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
            throw OperationError.failed("rinomina cartella: \(error.localizedDescription)")
        }

        var outcome = RenameOutcome(
            newPath: plan.newPath, movedNotes: movedNotes, failures: plan.failures
        )

        if let rename = plan.boardRename, rename.from != rename.to {
            do {
                try FileManager.default.moveItem(
                    at: store.url(for: rename.from), to: store.url(for: rename.to)
                )
                outcome.rewrittenPaths.append(rename.to)
            } catch {
                outcome.failures.append("\(rename.to): \(error.localizedDescription)")
            }
        }

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
            throw OperationError.failed("la radice del vault non si elimina")
        }
        guard isDirectory(folder) else { throw OperationError.missing(relativePath) }

        let trashedNotePaths = walk(folder).notePaths
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(
                at: store.root.appending(path: folder, directoryHint: .isDirectory),
                resultingItemURL: &resulting
            )
        } catch {
            throw OperationError.failed("eliminazione: \(error.localizedDescription)")
        }
        return (resulting as URL?, trashedNotePaths)
    }

    // MARK: - Paths

    /// A vault-relative path with the leading and trailing slashes a caller may have
    /// carried in, removed - the same trim `CanvasStore.boardPath(forFolder:)` makes,
    /// so `01 Progetti/vecchio/` and `01 Progetti/vecchio` name the same folder here
    /// too.
    private static func normalized(_ relativePath: String) -> String {
        relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// `path` as it will read once `oldFolder` has become `newFolder`. Unchanged for
    /// anything outside the renamed folder, which is what makes the prefix test `<old>/`
    /// rather than `<old>`.
    private static func repointing(_ path: String, from oldFolder: String, to newFolder: String) -> String {
        if path == oldFolder { return newFolder }
        guard path.hasPrefix("\(oldFolder)/") else { return path }
        return newFolder + String(path.dropFirst(oldFolder.count))
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false))
    }

    private func isDirectory(_ relativePath: String) -> Bool {
        var flag: ObjCBool = false
        let found = FileManager.default.fileExists(
            atPath: store.url(for: relativePath).path(percentEncoded: false), isDirectory: &flag
        )
        return found && flag.boolValue
    }
}
