import Foundation

// Plan docs/plans/pg-138-pg-141-pg-142-performance-debt.md, Task 7 - R-19.
//
// The source guards (`SharedSourcesPurityTests`, `PlaudIsolationTests`, `PraticheIsolationTests`)
// each walked and read their own directories of `Sources/`, so one test run read most of the tree
// several times over. This walks it once per test process and every guard selects its directories
// from the result by path prefix. What each guard decides stays in the guard.

/// Every `.swift` file under `Sources/`, read once per test process.
enum SourceTreeSnapshot {
    struct File: Sendable {
        /// From the repository root, `/`-separated: `Sources/Core/Email/MailStoreReader.swift`.
        let relativePath: String
        /// Absolute, as the guards report an offending file.
        let path: String
        /// `nil` when the file could not be read as UTF-8, which every guard skips.
        let contents: String?
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private enum Loaded: Sendable {
        case files([File])
        case failed(String)
    }

    /// Initialised once, on first use, by whichever guard runs first.
    private static let loaded: Loaded = {
        let sourcesRoot: URL
        do {
            sourcesRoot = try resolvedRepoRoot().appendingPathComponent("Sources")
        } catch {
            return .failed("\(error)")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesRoot, includingPropertiesForKeys: nil
        ) else {
            return .failed("Could not enumerate \(sourcesRoot.path)")
        }

        let rootPrefix = sourcesRoot.path + "/"
        var files: [File] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let path = fileURL.path
            // Never skipped silently: a path outside the root would mean the prefix selection
            // below cannot be trusted.
            guard path.hasPrefix(rootPrefix) else {
                return .failed("\(path) is not under \(rootPrefix)")
            }
            files.append(File(
                relativePath: "Sources/" + path.dropFirst(rootPrefix.count),
                path: path,
                contents: try? String(contentsOf: fileURL, encoding: .utf8)
            ))
        }
        return .files(files)
    }()

    /// Every `.swift` file under `Sources/`. Throws when the tree could not be walked, never
    /// answers an empty list in its place.
    static func files() throws -> [File] {
        switch loaded {
        case let .files(files): return files
        case let .failed(reason): throw Failure(description: reason)
        }
    }

    /// The `.swift` files under `directory`, a path from the repository root such as
    /// `"Sources/Core"`.
    static func files(under directory: String) throws -> [File] {
        let prefix = directory.hasSuffix("/") ? directory : directory + "/"
        return try files().filter { $0.relativePath.hasPrefix(prefix) }
    }
}
