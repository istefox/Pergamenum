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
                in: .pathSlashes
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

    /// What a rename would change: its destination, the notes that would be rewritten, the
    /// boards that would be repointed, and anything unreadable along the way.
    struct RenamePlan: Equatable, Sendable {
        var newPath: String
        var noteChanges: [VaultFileChange] = []
        var boardChanges: [VaultFileChange] = []
        var failures: [String] = []
    }

    /// What a move would change: its destination and the boards that would be repointed. No
    /// note text: a wikilink names a note by title, not by path (wikilink.md W-01).
    struct MovePlan: Equatable, Sendable {
        var newPath: String
        var boardChanges: [VaultFileChange] = []
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
            // The note itself is included: a note may link to its own title from its
            // `## Note correlate` section only by mistake, but its frontmatter or body can
            // still mention it, and leaving that one stale would be arbitrary. It is still at
            // `relativePath` while this runs - nothing has moved yet - so it is read from
            // there and written at `newPath`, which is where the performer moves it first.
            let readPath = path == relativePath ? relativePath : path
            let writePath = path == relativePath ? newPath : path
            guard let text = try? store.text(readPath) else {
                plan.failures.append("\(path): non leggibile")
                continue
            }
            guard let updated = NoteRename.rewritingLinks(in: text, from: oldTitle, to: newTitle)
            else { continue }
            plan.noteChanges.append(VaultFileChange(path: writePath, before: text, after: updated))
        }

        let boards = repointBoardsPlan(
            from: relativePath, to: newPath, titleChange: (old: oldTitle, new: newTitle)
        )
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
            guard path != relativePath, let text = try? store.text(path) else { return false }
            return WikilinkParser.links(in: text).contains { $0.target.lowercased() == needle }
        }
    }

    /// What repointing every board's cards would change, read rather than written - `repointBoards`
    /// performs exactly this once a caller has decided to.
    ///
    /// `titleChange` is `nil` for a move (a wikilink names a note by title, not by path -
    /// wikilink.md W-01 - so a move touches no card text) and `(oldTitle, newTitle)` for a
    /// rename, so a board's own `.text`-kind card body is rewritten the same way `.md` file text
    /// already is (`NoteRename.rewritingLinks`), not only its `.file`-kind embeds.
    private func repointBoardsPlan(
        from oldPath: String, to newPath: String, titleChange: (old: String, new: String)? = nil
    ) -> (changes: [VaultFileChange], failures: [String]) {
        guard oldPath != newPath else { return ([], []) }
        var changes: [VaultFileChange] = []
        var failures: [String] = []
        for boardPath in boardPaths() {
            guard let url = try? store.url(for: boardPath),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? CanvasDocument(data: data),
                  let document = repointedDocument(
                      decoded, from: oldPath, to: newPath, titleChange: titleChange
                  )
            else { continue }

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
                changes.append(VaultFileChange(path: boardPath, before: before, after: after))
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
    ///
    /// What to change is `renamePlan`'s answer and nothing else (ADR-0041 §D5). The loop this
    /// method used to keep read each note back from its new path *after* the move; the plan
    /// performs the same substitution as `writePath` *before* it, over the same text, so the
    /// bytes are the ones `NoteRenameCharacterizationTests` pinned down against the old loop.
    /// The validation - invalid title, missing note, colliding destination - is the plan's own
    /// too, and it still throws before anything has moved or been written.
    func rename(
        _ relativePath: String,
        to newTitle: String,
        knownPaths: [String]
    ) throws -> Outcome {
        let plan = try renamePlan(relativePath, to: newTitle, knownPaths: knownPaths)

        if plan.newPath != relativePath {
            do {
                try FileManager.default.moveItem(
                    at: try store.url(for: relativePath), to: try store.url(for: plan.newPath)
                )
            } catch {
                throw FileOperationError.failed("rinomina: \(error.localizedDescription)")
            }
        }

        var outcome = Outcome(newPath: plan.newPath, failures: plan.failures)
        let notes = VaultPlanApplication.apply(plan.noteChanges) {
            try store.write($0.after, to: $0.path)
        }
        // Written as bytes rather than through `NoteStore.write`: a `.canvas` is not a note and
        // the planned text is already the encoded document - the same split `FolderFileOperations`
        // and `BoardFileOperations` make, which is why the writer is injected (ADR-0041 §D4).
        let boards = VaultPlanApplication.apply(plan.boardChanges) {
            try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic)
        }
        outcome.rewrittenPaths = notes.rewrittenPaths + boards.rewrittenPaths
        outcome.failures.append(contentsOf: notes.failures + boards.failures)
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
            let destination = try store.url(for: newPath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: try store.url(for: relativePath), to: destination)
        } catch {
            throw FileOperationError.failed("spostamento: \(error.localizedDescription)")
        }

        var outcome = Outcome(newPath: newPath)
        repointBoards(from: relativePath, to: newPath, into: &outcome)
        return outcome
    }

    /// Points every board card that referenced `oldPath` at `newPath`, and rewrites `oldTitle`
    /// wikilinks inside `.text`-kind card bodies when `titleChange` is given (see
    /// `repointBoardsPlan`'s doc comment - the same `nil`-for-move/`(old,new)`-for-rename split).
    ///
    /// The document is decoded and re-encoded rather than patched as text, so a board
    /// written by Obsidian keeps the keys this app does not know about.
    private func repointBoards(
        from oldPath: String, to newPath: String,
        titleChange: (old: String, new: String)? = nil,
        into outcome: inout Outcome
    ) {
        guard oldPath != newPath else { return }
        for boardPath in boardPaths() {
            guard let url = try? store.url(for: boardPath),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? CanvasDocument(data: data),
                  let document = repointedDocument(
                      decoded, from: oldPath, to: newPath, titleChange: titleChange
                  )
            else { continue }

            do {
                try document.encoded().write(to: url, options: .atomic)
                outcome.rewrittenPaths.append(boardPath)
            } catch {
                outcome.failures.append("\(boardPath): \(error)")
            }
        }
    }

    /// The node-rewrite rule itself, in one place: `repointBoardsPlan` reads its result and
    /// `repointBoards` writes it, and neither owns a second copy of what a repoint means.
    ///
    /// Returns `nil` when the board mentions neither `oldPath` nor - for a rename -
    /// `titleChange.old`, which is the "nothing to write here" case both callers skip.
    private func repointedDocument(
        _ document: CanvasDocument,
        from oldPath: String, to newPath: String,
        titleChange: (old: String, new: String)?
    ) -> CanvasDocument? {
        var document = document
        var changed = false
        for index in document.nodes.indices {
            switch document.nodes[index].kind {
            case .file(let path, let subpath) where path == oldPath:
                document.nodes[index].kind = .file(path: newPath, subpath: subpath)
                changed = true
            case .text(let body):
                // A card has no `related:` frontmatter to preserve, so this must not run
                // NoteRename's quoted-related fallback (`includeQuotedRelated: false`) -
                // otherwise an unrelated quoted bullet line that happens to fold-match the
                // old title would be silently rewritten too.
                guard let titleChange,
                      let updated = NoteRename.rewritingLinks(
                          in: body, from: titleChange.old, to: titleChange.new,
                          includeQuotedRelated: false
                      )
                else { continue }
                document.nodes[index].kind = .text(updated)
                changed = true
            default:
                continue
            }
        }
        return changed ? document : nil
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
            try FileManager.default.trashItem(at: try store.url(for: relativePath), resultingItemURL: nil)
        } catch {
            throw FileOperationError.failed("eliminazione: \(error.localizedDescription)")
        }

        let needle = title.lowercased()
        return knownPaths.filter { path in
            guard path != relativePath, let text = try? store.text(path) else { return false }
            return WikilinkParser.links(in: text).contains { $0.target.lowercased() == needle }
        }
    }

    /// A boundary violation answers `false` (ADR-0041 §D2, Task 2's decision for the
    /// `Bool`-returning sites).
    private func exists(_ relativePath: String) -> Bool {
        guard let url = try? store.url(for: relativePath) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

extension CharacterSet {
    /// The set every vault-relative path is trimmed with, so a leading or trailing
    /// slash never makes two spellings of one path. Held once rather than built at each
    /// call site: `boardPaths()` trims inside a walk of the whole vault. Declared in
    /// this file because it is one of the few under `Sources/Vault` that `perg` and
    /// `pergamenum-mcp` compile too (`sharedSources`), so the app-only callers -
    /// `FolderFileOperations`, `BoardFileOperations`, `VaultController` - can reach it
    /// while the connector builds still see the declaration they need.
    static let pathSlashes = CharacterSet(charactersIn: "/")
}
