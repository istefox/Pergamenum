import Foundation

/// Walks a vault and yields every markdown note in it.
///
/// A cold scan is what rebuilds the index from nothing (ADR-0001 §D2), so it must
/// stay cheap enough to run on demand rather than being something the app avoids.
struct VaultScanner: Sendable {
    let root: URL

    struct Outcome: Sendable {
        var records: [NoteRecord]
        /// Files that exist but could not be read, with the reason. Reported instead
        /// of skipped: a note missing from the index is invisible in search and in
        /// backlinks, and the user has no way to notice on their own.
        var failures: [(path: String, reason: String)]
        /// How many of the records came from the cache rather than from disk.
        var reusedFromCache = 0
        /// The tasks every scanned `.canvas` board's own To Do card(s) carry (PG-074,
        /// plan Section 4). A board with no task-bearing `.text` node contributes nothing
        /// here, never an empty record - the same "absent, not empty" rule
        /// `WorkspaceController.toggleFold` follows for `foldedHeadings`.
        var boardTaskRecords: [BoardTaskRecord] = []

        var isEmpty: Bool { records.isEmpty && failures.isEmpty && boardTaskRecords.isEmpty }
    }

    /// Records already known, keyed by path, from `.pergamenum/cache.db`.
    ///
    /// A cached record is reused only when the file's size and modification date both
    /// still match. That is a cheap check against a stale cache; the expensive and
    /// exact one - the content hash - would mean reading the file, which is the work
    /// being avoided.
    var cached: [String: IndexCache.Entry] = [:]

    /// Cached board task records, keyed by the board's relative path - `cached`'s sibling for
    /// the second table `IndexCache` now carries.
    var cachedBoardTasks: [String: IndexCache.BoardEntry] = [:]

    func scan() -> Outcome {
        let store = NoteStore(root: root)
        var records: [NoteRecord] = []
        var failures: [(String, String)] = []
        var reused = 0
        var boardTaskRecords: [BoardTaskRecord] = []

        // The exclusion rule, the `skipDescendants()` call and the root standardisation
        // all live in `VaultWalk` now (ADR-0041 §D3). What stays here is the part that was
        // never a walk concern: which files this scan cares about and when a cached row
        // may stand in for reading one.
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .nameKey, .fileSizeKey, .contentModificationDateKey,
        ]
        guard let walk = try? VaultWalk(boundary: VaultBoundary(root: root), keys: keys) else {
            return Outcome(
                records: [],
                failures: [(root.lastPathComponent, "the vault could not be opened")]
            )
        }

        walk.forEach { file in
            let url = file.url
            let name = file.name
            guard !file.isDirectory else { return }

            guard url.pathExtension.lowercased() == "md" else {
                if url.pathExtension.lowercased() == CanvasStore.fileExtension {
                    let boardPath = file.relativePath
                    // The walk already asked for the size and the modification date of this
                    // very file; asking the file system again per entry is the one thing the
                    // cheap check was meant to avoid. Nil handling is unchanged: a missing
                    // size reads as -1 and a missing date answers false.
                    if let entry = cachedBoardTasks[boardPath],
                       Self.isUnchanged(
                           entry,
                           size: file.byteSize ?? -1,
                           modifiedAt: file.modifiedAt
                       ) {
                        boardTaskRecords.append(entry.record.record)
                    } else if let record = Self.boardTaskRecord(
                        at: url, relativePath: boardPath
                    ) {
                        boardTaskRecords.append(record)
                    }
                }
                if let note = Self.evictedNoteName(from: name) {
                    let placeholder = file.relativePath
                    failures.append((
                        String(placeholder.dropLast(name.count)) + note,
                        "non è scaricata da iCloud: apri il vault in Finder e scegli «Conserva scaricato»"
                    ))
                }
                return
            }

            let relativePath = file.relativePath
            if let entry = cached[relativePath],
               Self.isUnchanged(
                   entry,
                   size: file.byteSize ?? -1,
                   modifiedAt: file.modifiedAt
               ) {
                records.append(entry.record.record)
                reused += 1
                return
            }
            do {
                records.append(try store.read(relativePath).record)
            } catch {
                failures.append((relativePath, "\(error)"))
            }
        }
        return Outcome(
            records: records, failures: failures, reusedFromCache: reused,
            boardTaskRecords: boardTaskRecords
        )
    }

    /// The tasks one board contributes to the index, or nil when it holds none.
    ///
    /// The entry criterion is deliberately content-based, per the SPEC (plan Section 4): no
    /// marker on `CanvasNode` distinguishes a purpose-made To Do card from a freehand Testo
    /// card that starts the same way, so a `.text` node is scanned exactly when its own first
    /// line already parses as a task line. A board unreadable or with no such node contributes
    /// nothing, silently - a `.canvas` a freehand card lives on is not a scanner failure.
    private static func boardTaskRecord(
        at url: URL, relativePath: String
    ) -> BoardTaskRecord? {
        // `CanvasStore.load(board:)` is an exists-check, a read and `CanvasDocument(data:)`;
        // the read already happened on the line above, and the file existing is implied by
        // it having been read. Decoding those same bytes keeps the error → nil behaviour.
        guard let data = try? Data(contentsOf: url),
              let document = try? CanvasDocument(data: data)
        else { return nil }

        var tasks: [TaskItem] = []
        for node in document.nodes {
            guard case .text(let text) = node.kind else { continue }
            let firstLine = text.prefix { $0 != "\n" }
            guard TaskParser.parse(line: String(firstLine), sourcePath: relativePath, lineIndex: 0) != nil
            else { continue }

            tasks += TaskParser.tasks(in: text, sourcePath: relativePath).map { task in
                var task = task
                task.nodeID = node.id
                return task
            }
        }
        guard !tasks.isEmpty else { return nil }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return BoardTaskRecord(
            relativePath: relativePath,
            tasks: tasks,
            modifiedAt: values?.contentModificationDate ?? Date(timeIntervalSince1970: 0),
            byteSize: values?.fileSize ?? data.count,
            contentHash: NoteStore.hash(data)
        )
    }

    /// Percent-decoded, separator-normalised path of `url` relative to `root`.
    /// The note an iCloud placeholder stands in for, or nil when the file is something
    /// else entirely.
    ///
    /// With "Optimize Mac Storage" on, iCloud Drive evicts a file it thinks is cold and
    /// leaves a hidden `.Nota.md.icloud` stub where `Nota.md` was. The stub's extension
    /// is no longer `md`, so the walk drops it without a word and the note is simply
    /// gone: absent from search, absent from the linter, and absent from the index that
    /// resolves wikilinks. What the user sees is a link that stopped resolving, which
    /// reads exactly like a link they typed wrong - a vault lying in the one way its
    /// owner cannot tell apart from their own mistake.
    ///
    /// Principle 6 puts the vault in iCloud Drive on purpose, so this is a normal state
    /// of a supported setup rather than an exotic failure, and it is reported.
    static func evictedNoteName(from fileName: String) -> String? {
        let suffix = ".icloud"
        guard fileName.hasPrefix("."), fileName.hasSuffix(suffix) else { return nil }
        let note = String(fileName.dropFirst().dropLast(suffix.count))
        guard (note as NSString).pathExtension.lowercased() == "md" else { return nil }
        return note
    }

    /// The iCloud placeholder's file name for a note file name - the inverse of
    /// `evictedNoteName(from:)`, so the naming rule lives in one file, both directions
    /// (ADR-0064 §D2). `VaultDisk.reconcile` asks for it to tell an evicted note from a
    /// deleted one.
    static func evictedPlaceholderName(for noteFileName: String) -> String {
        "." + noteFileName + ".icloud"
    }

    /// Percent-decoded, separator-normalised path of `url` relative to `root`.
    ///
    /// No walk calls this any more - `VaultWalk` drops a prefix it computed once, which is
    /// what `PG-140`'s `perf-VaultScanner.swift-a0b` asked for. It stays because
    /// `VaultWatcher` still needs it (`VaultWatcher.Sink.handle`), and for a path that arrived
    /// from FSEvents rather than from an enumerator the per-URL `standardizedFileURL` is
    /// the work, not the waste: nothing has canonicalised that spelling yet.
    static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let filePath = url.standardizedFileURL.path(percentEncoded: false)
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        let trimmed = filePath.dropFirst(rootPath.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }
}

extension VaultScanner {
    /// Whether a cached row still describes the file on disk.
    static func isUnchanged(_ entry: IndexCache.Entry, size: Int, modifiedAt: Date?) -> Bool {
        guard let modifiedAt else { return false }
        // Sub-second precision differs between file systems and between the value
        // Foundation reports on read and on write, so the comparison is to the second.
        return entry.byteSize == size
            && abs(entry.modifiedAt.timeIntervalSince(modifiedAt)) < 1
    }

    /// Whether a cached board-task row still describes the file on disk -
    /// `isUnchanged(_:size:modifiedAt:)`'s sibling for the second table.
    static func isUnchanged(_ entry: IndexCache.BoardEntry, size: Int, modifiedAt: Date?) -> Bool {
        guard let modifiedAt else { return false }
        return entry.byteSize == size
            && abs(entry.modifiedAt.timeIntervalSince(modifiedAt)) < 1
    }
}
