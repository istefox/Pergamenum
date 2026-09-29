import Foundation

// ADR-0071 (Contenitore, a managed document archive fed from a drop folder) §D4 steps 1 and 2,
// plan docs/plans/contenitore.md, Task 4 - R-03, R-08.
//
// App-only (§D14): the drop folder is the app's business, never a connector's.

/// What one observation of the drop folder saw, and which entries are ready to import.
///
/// Pure apart from `read(_:)`, which lists the folder: `classify(_:)` takes plain values, so
/// every rule below runs in a test without a file system. It keeps the size and modification
/// date of every file it saw, which is what "stable" means (R-03): a file is ready when both
/// equal what the previous observation recorded, and the first sighting only records them.
struct DropFolderListing {
    /// One entry of the drop folder, as listed.
    struct Entry: Equatable, Sendable {
        var name: String
        var isDirectory: Bool = false
        var size: Int64 = 0
        var modified: Date = .distantPast
        /// A dataless iCloud file whose download status is not `.current`: present by name,
        /// absent by content.
        var isDataless: Bool = false
    }

    /// Where one entry stands after an observation.
    enum Classification: Equatable, Sendable {
        /// Stable across two observations: import it now.
        case ready
        /// First sighting, or still changing: look again later.
        case waiting
        /// A dot-file other than an iCloud stub: ignored without a word.
        case hidden
        /// A folder: never descended into, reported by the engine once per name.
        case subfolder
        /// An iCloud placeholder, reported under the name of the file it stands in for.
        case placeholder(name: String)
        /// A dropped `.md` or `.canvas`, never imported (gate G3, `refusedExtensions`).
        case refused
    }

    private struct Signature: Equatable {
        let size: Int64
        let modified: Date
    }

    /// Extensions refused at ingest, lowercased (gate G3). A `.md` would share its scheda's name;
    /// a `.canvas` would be listed as a board and renamed, moved or trashed alone by the board
    /// verbs, splitting the pair.
    private static let refusedExtensions: Set<String> = ["md", "canvas"]

    /// Size and date per file name, from the previous observation.
    private var memory: [String: Signature] = [:]

    /// Classifies one observation's entries, in the order given, and remembers each file's size
    /// and date for the next. A name absent from this observation is forgotten, so a file taken
    /// away and dropped again starts over.
    ///
    /// The iCloud stub is recognised before the hidden-file rule: the stub is itself a dot-file,
    /// and a placeholder silently ignored as hidden is a document the person believes they
    /// dropped (§D4 step 1).
    mutating func classify(_ entries: [Entry]) -> [(entry: Entry, classification: Classification)] {
        var next: [String: Signature] = [:]
        var result: [(entry: Entry, classification: Classification)] = []

        for entry in entries {
            let classification: Classification
            if let stood = Self.placeholderTarget(of: entry.name) {
                classification = .placeholder(name: stood)
            } else if entry.name.hasPrefix(".") {
                classification = .hidden
            } else if entry.isDirectory {
                classification = .subfolder
            } else if entry.isDataless {
                classification = .placeholder(name: entry.name)
            } else if Self.refusedExtensions.contains((entry.name as NSString).pathExtension.lowercased()) {
                classification = .refused
            } else {
                let signature = Signature(size: entry.size, modified: entry.modified)
                classification = memory[entry.name] == signature ? .ready : .waiting
                next[entry.name] = signature
            }
            result.append((entry, classification))
        }
        memory = next
        return result
    }

    /// The name of the file an iCloud stub stands in for, `VaultScanner`'s `.name.icloud` rule
    /// widened to any extension, or nil when `name` is not a stub.
    static func placeholderTarget(of name: String) -> String? {
        let suffix = ".icloud"
        guard name.hasPrefix("."), name.hasSuffix(suffix), name.count > suffix.count + 1 else { return nil }
        return String(name.dropFirst().dropLast(suffix.count))
    }

    /// The drop folder's entries, hidden ones included (the stub is one), sorted by name so an
    /// observation is deterministic.
    static func read(_ folder: URL) throws -> [Entry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: []
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isUbiquitous = values?.isUbiquitousItem ?? false
            let status = values?.ubiquitousItemDownloadingStatus
            return Entry(
                name: url.lastPathComponent,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast,
                isDataless: isUbiquitous && status != nil && status != .current
            )
        }
        .sorted { $0.name < $1.name }
    }
}
