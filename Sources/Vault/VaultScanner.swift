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

        var isEmpty: Bool { records.isEmpty && failures.isEmpty }
    }

    func scan() -> Outcome {
        let store = NoteStore(root: root)
        var records: [NoteRecord] = []
        var failures: [(String, String)] = []

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return Outcome(records: [], failures: [(root.lastPathComponent, "the vault could not be opened")])
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
            do {
                records.append(try store.read(relativePath).record)
            } catch {
                failures.append((relativePath, "\(error)"))
            }
        }
        return Outcome(records: records, failures: failures)
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
