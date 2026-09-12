import Foundation

/// The one vault walk, replacing the three drifted copies in `VaultScanner.scan()`,
/// `CanvasStore.walk()` and `FolderFileOperations.walk(_:)` (ADR-0041 §D3, Task 4).
///
/// Three properties, one per finding §D3 names:
///
/// 1. It is built from a `VaultBoundary`, never from a bare `URL`, so the walk cannot be
///    the way back into the vault layer around the guard of §D1.
/// 2. `VaultLayout.isExcludedDirectory` is consulted here and `skipDescendants()` called
///    here, so `.git`, `.obsidian`, `.trash` and our own `.pergamenum` are never entered -
///    three callers stop remembering to do it, and none of them can forget.
/// 3. The root is turned into a path prefix **once, in `init`**; every entry's
///    `relativePath` is that prefix dropped. `VaultScanner.relativePath(of:under:)` paid a
///    `standardizedFileURL` per file of every scan, which is `PG-140`'s
///    `perf-VaultScanner.swift-a0b`.
struct VaultWalk: Sendable {
    struct Entry: Sendable {
        let url: URL
        /// Path relative to the **vault root**, never to `subfolder` - a walk scoped to
        /// `01 Progetti` still yields `01 Progetti/Nota.md`.
        ///
        /// A directory keeps the trailing separator the enumerator's own URL carries
        /// (`01 Progetti/`), because that is what the three walks being replaced saw and
        /// `CanvasStore` already strips it where it matters.
        let relativePath: String
        let name: String
        let isDirectory: Bool
        /// `nil` unless `keys` asked for `.fileSizeKey`.
        let byteSize: Int?
        /// `nil` unless `keys` asked for `.contentModificationDateKey`.
        let modifiedAt: Date?
    }

    /// Where enumeration starts: the vault root, or the subfolder resolved through the
    /// boundary. Not the same thing as the prefix relative paths are measured from.
    private let start: URL

    /// The vault root as the file system spells it, with a trailing separator.
    ///
    /// Computed from `.canonicalPathKey` rather than from `root.path`, because the two
    /// disagree and the enumerator sides with the file system: measured on macOS 26, a
    /// walk started at `/var/folders/…/T/vault/` hands back `/private/var/folders/…`
    /// URLs, while `URL.standardizedFileURL`/`resolvingSymlinksInPath` both *strip* the
    /// `/private` prefix. Dropping `root.path` off those entries would match nothing and
    /// fall back to bare file names. `canonicalPath` is the spelling the enumerator uses,
    /// so the prefix drop below is exact - and it is read once here, not per file.
    private let rootPrefix: String

    /// What the caller asked to know about each entry. Empty means "nothing extra", and
    /// then no `resourceValues` call is paid per file at all: `isDirectory` and `name`
    /// come off the URL, which is measurably the same answer for an enumerated file.
    private let keys: Set<URLResourceKey>

    /// `subfolder.isEmpty` deliberately skips `boundary.url(for:)`: that resolver refuses
    /// `""` (SPEC/`VaultBoundary` doc: "the vault directory is not one"), but an empty
    /// subfolder here means "walk the whole vault", not "resolve a file named nothing".
    /// A non-empty subfolder still goes through the boundary, which is what makes
    /// `subfolder: "../escape"` throw.
    init(boundary: VaultBoundary, subfolder: String = "", keys: Set<URLResourceKey> = []) throws {
        if subfolder.isEmpty {
            start = boundary.root
        } else {
            start = try boundary.url(for: subfolder)
        }
        self.keys = keys

        let rootPath = (try? boundary.root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath)
            ?? boundary.root.path(percentEncoded: false)
        rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    }

    /// Every file and directory under the walk's subtree, the excluded directories and
    /// everything below them left out.
    ///
    /// The enumerator is built here rather than held as a property for two reasons: it is
    /// a reference type, which a `Sendable` value type may not carry, and it is consumed
    /// by a single pass - a walk that silently yields nothing the second time a caller
    /// iterated it would be exactly the kind of trap this type exists to remove.
    func forEach(_ body: (Entry) -> Void) {
        guard let enumerator = FileManager.default.enumerator(
            at: start,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            // Deliberate fallbacks (PG-039): `resourceValues` can fail on a transient race
            // with the file system, and for an enumerated URL the volume reports the same
            // name its last path component already carries.
            let values = keys.isEmpty ? nil : try? url.resourceValues(forKeys: keys)
            let isDirectory = values?.isDirectory ?? url.hasDirectoryPath
            let name = values?.name ?? url.lastPathComponent

            if isDirectory, VaultLayout.isExcludedDirectory(name) {
                // Skipping the descendants, rather than filtering them one file at a time,
                // is the whole difference: nothing inside an excluded directory is ever
                // read, let alone yielded.
                enumerator.skipDescendants()
                continue
            }

            body(Entry(
                url: url,
                relativePath: relativePath(of: url),
                name: name,
                isDirectory: isDirectory,
                byteSize: values?.fileSize,
                modifiedAt: values?.contentModificationDate
            ))
        }
    }

    /// The prefix drop, with `VaultScanner.relativePath(of:under:)`'s own fallback for a
    /// URL that somehow is not under the root: its last component, never a path that
    /// would read as vault-relative and not be.
    private func relativePath(of url: URL) -> String {
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix(rootPrefix) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPrefix.count))
    }
}
