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
        guard violations.isEmpty else { throw OperationError.invalidTitle(violations) }

        let oldTitle = NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent)
        let folder = (relativePath as NSString).deletingLastPathComponent
        let fileName = NoteName.fileName(for: newTitle)
        let newPath = folder.isEmpty ? fileName : "\(folder)/\(fileName)"

        guard exists(relativePath) else { throw OperationError.missing(relativePath) }
        guard newPath == relativePath || !exists(newPath) else {
            throw OperationError.alreadyExists(newPath)
        }

        if newPath != relativePath {
            do {
                try FileManager.default.moveItem(at: store.url(for: relativePath), to: store.url(for: newPath))
            } catch {
                throw OperationError.failed("rinomina: \(error.localizedDescription)")
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
        guard exists(relativePath) else { throw OperationError.missing(relativePath) }
        guard !exists(newPath) else { throw OperationError.alreadyExists(newPath) }

        do {
            let destination = store.url(for: newPath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: store.url(for: relativePath), to: destination)
        } catch {
            throw OperationError.failed("spostamento: \(error.localizedDescription)")
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
        guard exists(relativePath) else { throw OperationError.missing(relativePath) }
        let title = NoteName.title(fromFileName: (relativePath as NSString).lastPathComponent)

        do {
            try FileManager.default.trashItem(at: store.url(for: relativePath), resultingItemURL: nil)
        } catch {
            throw OperationError.failed("eliminazione: \(error.localizedDescription)")
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
