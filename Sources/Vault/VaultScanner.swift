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

        var isEmpty: Bool { records.isEmpty && failures.isEmpty }
    }

    /// Records already known, keyed by path, from `.pergamenum/cache.db`.
    ///
    /// A cached record is reused only when the file's size and modification date both
    /// still match. That is a cheap check against a stale cache; the expensive and
    /// exact one - the content hash - would mean reading the file, which is the work
    /// being avoided.
    var cached: [String: IndexCache.Entry] = [:]

    /// How many notes the last scan took from the cache, for the index panel.
    final class Statistics: @unchecked Sendable {
        var reused = 0
    }

    func scan() -> Outcome {
        let store = NoteStore(root: root)
        var records: [NoteRecord] = []
        var failures: [(String, String)] = []
        var reused = 0

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .nameKey, .fileSizeKey, .contentModificationDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return Outcome(
                records: [],
                failures: [(root.lastPathComponent, "the vault could not be opened")]
            )
        }

        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.name ?? url.lastPathComponent

            if values?.isDirectory == true {
                // Skipping descendants here is what keeps `.obsidian`, `.git` and our
                // own `.pergamenum` out of the walk entirely rather than filtering
                // their contents one file at a time.
                if VaultLayout.isExcludedDirectory(name) { enumerator.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == "md" else { continue }

            let relativePath = Self.relativePath(of: url, under: root)
            if let entry = cached[relativePath], isUnchanged(entry, at: url) {
                records.append(entry.record.record)
                reused += 1
                continue
            }
            do {
                records.append(try store.read(relativePath).record)
            } catch {
                failures.append((relativePath, "\(error)"))
            }
        }
        return Outcome(records: records, failures: failures, reusedFromCache: reused)
    }

    /// Percent-decoded, separator-normalised path of `url` relative to `root`.
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

    private func isUnchanged(_ entry: IndexCache.Entry, at url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return Self.isUnchanged(
            entry,
            size: values?.fileSize ?? -1,
            modifiedAt: values?.contentModificationDate
        )
    }
}
