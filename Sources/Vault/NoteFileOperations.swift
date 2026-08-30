import Foundation

/// Renaming, moving and deleting notes on disk, with the link rewriting W-08 requires.
///
/// Separate from `VaultController` because these are the three operations that change
/// the vault's shape rather than a note's text, and because each of them has to be
/// checked directly: a rename that half-rewrites the vault is not something to
/// discover by using the app.
struct NoteFileOperations {
    let store: NoteStore
    /// Boards are rewritten too: a `.canvas` node points at a file by path, so a
    /// rename or a move that ignored them would leave a card pointing at nothing
    /// while the note itself was fine - a break the user only finds later, on the
    /// board, with no clue what caused it. Observed on a real vault: renaming a note
    /// left its card on the root board pointing at a file that no longer existed.
    ///
    /// Found by walking the vault rather than taken from the index, which holds notes
    /// and not boards. A rename is rare enough to afford one directory walk, and a
    /// board this missed would be a board silently left broken.
    private func boardPaths() -> [String] {
        let rootPath = store.root.path(percentEncoded: false)
        guard let enumerator = FileManager.default.enumerator(
            at: store.root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var paths: [String] = []
        for case let url as URL in enumerator
        where url.pathExtension.lowercased() == CanvasStore.fileExtension {
            let path = url.standardizedFileURL.path(percentEncoded: false)
            guard path.hasPrefix(rootPath) else { continue }
            paths.append(String(path.dropFirst(rootPath.count)).trimmingCharacters(
                in: CharacterSet(charactersIn: "/")
            ))
        }
        return paths
    }

    /// What a rename or a move actually did, so the caller can update its index and
    /// tell the user what happened.
    struct Outcome: Equatable, Sendable {
        var newPath: String
        /// Notes whose links were rewritten, by path.
        var rewrittenPaths: [String] = []
        /// Notes that point at this one but could not be rewritten, with the reason.
        /// Reported rather than swallowed: a link left behind is a broken link.
        var failures: [String] = []
    }

    // MARK: - Computing what would change (ADR-0016 §D6)
    //
    // `rename`, `move` and `trash` above write directly and stay exactly as they were, for the
    // callers - this file's own tests included - that have no journal to go through. What
    // follows computes the same arithmetic without touching disk, the split
    // `VaultSession+TagRename` already makes between `tagRenamePreview` and `renameTag`: one
    // function decides what would change, a second one - on `VaultSession+Files` - performs
    // exactly that inside a transaction. A dry run is then honest by construction, not by a flag
    // every method has to remember to check.

    /// One file's text before and after a rename or a move that has not happened, so the plan and
    /// the performance read the same triple.
    struct FileChange: Equatable, Sendable {
        let path: String
        let before: String
        let after: String
    }

    /// What a rename would change: its destination, the notes that would be rewritten, the
    /// boards that would be repointed, and anything unreadable along the way.
    struct RenamePlan: Equatable, Sendable {
        var newPath: String
        var noteChanges: [FileChange] = []
        var boardChanges: [FileChange] = []
        var failures: [String] = []
    }

    /// What a move would change: its destination and the boards that would be repointed. No
    /// note text: a wikilink names a note by title, not by path (wikilink.md W-01).
    struct MovePlan: Equatable, Sendable {
        var newPath: String
        var boardChanges: [FileChange] = []
        var failures: [String] = []
    }

    /// What a rename would do, read from where the note still is - not from where `rename`
    /// would leave it, since nothing has moved yet when this runs.
    func renamePlan(
        _ relativePath: String,
        to newTitle: String,
        knownPaths: [String]
    ) throws -> RenamePlan {
        let violations = NoteName.validate(newTitle)
        guard violations.isEmpty else { throw FileOperationError.invalidTitle(violations) }

        let oldTitle = NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent)
        let folder = (relativePath as NSString).deletingLastPathComponent
        let fileName = NoteName.fileName(for: newTitle)
        let newPath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"

        guard exists(relativePath) else { throw FileOperationError.missing(relativePath) }
        guard newPath == relativePath || !exists(newPath) else {
            throw FileOperationError.alreadyExists(newPath)
        }

        var plan = RenamePlan(newPath: newPath)
        for path in knownPaths {
            // The note itself is still at `relativePath`: only the performer, moving it first,
            // earns the right to read it back from `newPath`.
            let readPath = path == relativePath ? relativePath : path
            let writePath = path == relativePath ? newPath : path
            guard let (_, text) = try? store.read(readPath) else {
                plan.failures.append("\(path): non leggibile")
                continue
            }
            guard let updated = NoteRename.rewritingLinks(in: text, from: oldTitle, to: newTitle)
            else { continue }
            plan.noteChanges.append(FileChange(path: writePath, before: text, after: updated))
        }

        let boards = repointBoardsPlan(from: relativePath, to: newPath)
        plan.boardChanges = boards.changes
        plan.failures.append(contentsOf: boards.failures)
        return plan
    }

    /// What a move would do. Mirrors `move`'s own no-op and validation order, since a caller
    /// asking to move a note into the folder it is already in gets back its own path rather
    /// than a plan nobody needs to perform.
    func movePlan(_ relativePath: String, toFolder folder: String) throws -> MovePlan {
        let fileName = (relativePath as NSString).lastPathComponent
        let newPath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        guard newPath != relativePath else { return MovePlan(newPath: relativePath) }
        guard exists(relativePath) else { throw FileOperationError.missing(relativePath) }
        guard !exists(newPath) else { throw FileOperationError.alreadyExists(newPath) }

        var plan = MovePlan(newPath: newPath)
        let boards = repointBoardsPlan(from: relativePath, to: newPath)
        plan.boardChanges = boards.changes
        plan.failures = boards.failures
        return plan
    }

    /// Notes that would be left pointing at nothing if `relativePath` went to the trash. Read
    /// rather than written: `trash`'s own version computes the same thing after moving the file,
    /// which changes nothing here since neither reads `relativePath` itself.
    func danglingLinks(for relativePath: String, knownPaths: [String]) -> [String] {
        let title = NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent)
        let needle = title.lowercased()
        return knownPaths.filter { path in
            guard path != relativePath, let (_, text) = try? store.read(path) else { return false }
            return WikilinkParser.links(in: text).contains { $0.target.lowercased() == needle }
        }
    }

    /// What repointing every board's cards would change, read rather than written - `repointBoards`
    /// performs exactly this once a caller has decided to.
    private func repointBoardsPlan(
        from oldPath: String, to newPath: String
    ) -> (changes: [FileChange], failures: [String]) {
        guard oldPath != newPath else { return ([], []) }
        var changes: [FileChange] = []
        var failures: [String] = []
        for boardPath in boardPaths() {
            let url = store.url(for: boardPath)
            guard let data = try? Data(contentsOf: url),
                  var document = try? CanvasDocument(data: data)
            else { continue }

            var changed = false
            for index in document.nodes.indices {
                guard case .file(let path, let subpath) = document.nodes[index].kind, path == oldPath
                else { continue }
                document.nodes[index].kind = .file(path: newPath, subpath: subpath)
                changed = true
            }
            guard changed else { continue }

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
                changes.append(FileChange(path: boardPath, before: before, after: after))
            } catch {
                failures.append("\(boardPath): \(error)")
            }
        }
        return (changes, failures)
    }

    /// Renames a note and rewrites every link that pointed at its old title.
    ///
    /// The file is moved first and the links after: the move is one operation that
    /// either happens or does not, while the rewrite touches many files and can fail
    /// on any of them. Doing it the other way round would leave the vault pointing at
    /// a note that does not exist yet if the move then failed.
    func rename(
        _ relativePath: String,
        to newTitle: String,
        knownPaths: [String]
    ) throws -> Outcome {
        let violations = NoteName.validate(newTitle)
        guard violations.isEmpty else { throw FileOperationError.invalidTitle(violations) }

        let oldTitle = NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent)
        let folder = (relativePath as NSString).deletingLastPathComponent
        let fileName = NoteName.fileName(for: newTitle)
        let newPath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"

        guard exists(relativePath) else { throw FileOperationError.missing(relativePath) }
        guard newPath == relativePath || !exists(newPath) else {
            throw FileOperationError.alreadyExists(newPath)
        }

        if newPath != relativePath {
            do {
                try FileManager.default.moveItem(at: store.url(for: relativePath), to: store.url(for: newPath))
            } catch {
                throw FileOperationError.failed("rinomina: \(error.localizedDescription)")
            }
        }

        var outcome = Outcome(newPath: newPath)
        for path in knownPaths {
            // The note itself is included: a note may link to its own title from its
            // `## Note correlate` section only by mistake, but its frontmatter or body
            // can still mention it, and leaving that one stale would be arbitrary.
            let readPath = path == relativePath ? newPath : path
            guard let (_, text) = try? store.read(readPath) else {
                outcome.failures.append("\(path): non leggibile")
                continue
            }
            guard let updated = NoteRename.rewritingLinks(in: text, from: oldTitle, to: newTitle)
            else { continue }

            do {
                _ = try store.write(updated, to: readPath)
                outcome.rewrittenPaths.append(readPath)
            } catch {
                outcome.failures.append("\(readPath): \(error)")
            }
        }

        repointBoards(from: relativePath, to: newPath, into: &outcome)
        return outcome
    }

    /// Moves a note to another folder.
    ///
    /// No link rewriting: a wikilink names a note by title, not by path, so moving a
    /// note between folders breaks nothing (wikilink.md W-01).
    func move(_ relativePath: String, toFolder folder: String) throws -> Outcome {
        let fileName = (relativePath as NSString).lastPathComponent
        let newPath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
        guard newPath != relativePath else { return Outcome(newPath: relativePath) }
        guard exists(relativePath) else { throw FileOperationError.missing(relativePath) }
        guard !exists(newPath) else { throw FileOperationError.alreadyExists(newPath) }

        do {
            let destination = store.url(for: newPath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: store.url(for: relativePath), to: destination)
        } catch {
            throw FileOperationError.failed("spostamento: \(error.localizedDescription)")
        }

        var outcome = Outcome(newPath: newPath)
        repointBoards(from: relativePath, to: newPath, into: &outcome)
        return outcome
    }

    /// Points every board card that referenced `oldPath` at `newPath`.
    ///
    /// The document is decoded and re-encoded rather than patched as text, so a board
    /// written by Obsidian keeps the keys this app does not know about.
    private func repointBoards(from oldPath: String, to newPath: String, into outcome: inout Outcome) {
        guard oldPath != newPath else { return }
        for boardPath in boardPaths() {
            let url = store.url(for: boardPath)
            guard let data = try? Data(contentsOf: url),
                  var document = try? CanvasDocument(data: data)
            else { continue }

            var changed = false
            for index in document.nodes.indices {
                guard case .file(let path, let subpath) = document.nodes[index].kind, path == oldPath
                else { continue }
                document.nodes[index].kind = .file(path: newPath, subpath: subpath)
                changed = true
            }
            guard changed else { continue }

            do {
                try document.encoded().write(to: url, options: .atomic)
                outcome.rewrittenPaths.append(boardPath)
            } catch {
                outcome.failures.append("\(boardPath): \(error)")
            }
        }
    }

    /// Moves a note to the Finder's trash, and reports which notes now link to
    /// nothing.
    ///
    /// The trash rather than an unlink: a note deleted by a misclick is recoverable
    /// there, and nothing this app does is worth making that unrecoverable.
    func trash(_ relativePath: String, knownPaths: [String]) throws -> [String] {
        guard exists(relativePath) else { throw FileOperationError.missing(relativePath) }
        let title = NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent)

        do {
            try FileManager.default.trashItem(at: store.url(for: relativePath), resultingItemURL: nil)
        } catch {
            throw FileOperationError.failed("eliminazione: \(error.localizedDescription)")
        }

        let needle = title.lowercased()
        return knownPaths.filter { path in
            guard path != relativePath, let (_, text) = try? store.read(path) else { return false }
            return WikilinkParser.links(in: text).contains { $0.target.lowercased() == needle }
        }
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: store.url(for: relativePath).path(percentEncoded: false))
    }
}
