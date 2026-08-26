import Foundation

/// Reads and writes the `.canvas` files that back the Workspace boards.
///
/// SPEC §6.1 makes a board a spatial view of a real folder: the board for
/// `01 Progetti/vibrofer-emea` is `01 Progetti/vibrofer-emea/vibrofer-emea.canvas`,
/// created on first entry. That mapping is what keeps "file over app" true for the
/// Workspace - the folder is the truth, the canvas only says where things sit.
struct CanvasStore: Sendable {
    /// Resolved at construction for the same reason as `NoteStore.root`.
    let root: URL

    init(root: URL) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
    }

    static let fileExtension = "canvas"

    /// Vault-relative path of the board file for a folder. The root folder's board is
    /// named after the vault so it does not collide with a note called "canvas".
    func boardPath(forFolder folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty {
            return "\(root.lastPathComponent).\(Self.fileExtension)"
        }
        let name = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        return "\(trimmed)/\(name).\(Self.fileExtension)"
    }

    func url(forFolder folder: String) -> URL {
        root.appending(path: boardPath(forFolder: folder), directoryHint: .notDirectory)
    }

    /// Loads a folder's board, returning an empty canvas when the file does not exist
    /// yet. Not created on read: a board file appears when something is placed on it,
    /// so merely looking into a folder does not litter the vault.
    func load(folder: String) throws -> CanvasDocument {
        let fileURL = url(forFolder: folder)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return .empty
        }
        return try CanvasDocument(data: try Data(contentsOf: fileURL))
    }

    @discardableResult
    func save(_ document: CanvasDocument, folder: String) throws -> String {
        let fileURL = url(forFolder: folder)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try document.encoded()
        try data.write(to: fileURL, options: .atomic)
        return NoteStore.hash(data)
    }

    /// The folder's real contents, split into what the board already shows and what it
    /// does not.
    ///
    /// SPEC §6.1: files dropped into the folder from Finder appear in a "Nuovi
    /// elementi" tray to be placed by hand. Nothing is positioned automatically,
    /// because a position the user did not choose is noise on a spatial canvas.
    func contents(ofFolder folder: String, board: CanvasDocument) -> FolderContents {
        let directory = folder.isEmpty
            ? root
            : root.appending(path: folder, directoryHint: .isDirectory)

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []

        let placed = Set(board.nodes.compactMap { node -> String? in
            if case .file(let path, _) = node.kind { return path }
            return nil
        })

        var subfolders: [String] = []
        var unplaced: [String] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            guard !VaultLayout.isExcludedDirectory(name) else { continue }
            let relativePath = folder.isEmpty ? name : "\(folder)/\(name)"

            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                subfolders.append(relativePath)
                if !placed.contains(relativePath) { unplaced.append(relativePath) }
                continue
            }
            // The board's own file is not an item on the board.
            guard relativePath != boardPath(forFolder: folder) else { continue }
            if !placed.contains(relativePath) { unplaced.append(relativePath) }
        }
        return FolderContents(subfolders: subfolders, unplaced: unplaced)
    }

    struct FolderContents: Equatable, Sendable {
        var subfolders: [String]
        /// Real entries the board has no node for yet.
        var unplaced: [String]
    }

    /// Every `.canvas` file in the vault, as vault-relative paths, sorted.
    ///
    /// ADR-0021 D10: boards are enumerated on demand rather than carried in
    /// `IndexSnapshot`, which stays a note index. Called when the Workspace browser
    /// appears and on `scanGeneration`, the same trigger the note tree rebuilds on.
    ///
    /// The walk mirrors `VaultScanner.scan()`: an enumerator that skips the descendants
    /// of an excluded directory outright rather than filtering its files one at a time,
    /// so `.obsidian`, `.git`, `.trash` and our own `.pergamenum` are never entered.
    func allBoards() -> [String] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }

        var paths: [String] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.name ?? url.lastPathComponent

            if values?.isDirectory == true {
                if VaultLayout.isExcludedDirectory(name) { enumerator.skipDescendants() }
                continue
            }
            guard url.pathExtension.lowercased() == Self.fileExtension else { continue }
            paths.append(VaultScanner.relativePath(of: url, under: root))
        }
        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Path-addressing API (ADR-0025 §D1)
    //
    // A board is told its own path instead of deriving it from a folder - the decision
    // ADR-0025 exists to make. Plan
    // `docs/superpowers/plans/2026-08-27-workspace-folder-board-separation.md`, Task 1.
    //
    // This sits alongside the folder-derived API above rather than replacing it, and
    // only for this task's RED step: `boardPath(forFolder:)`/`url(forFolder:)`/
    // `load(folder:)`/`save(_:folder:)`/`contents(ofFolder:board:)` are deleted or
    // re-signed in place by the coder's GREEN-phase work, which also migrates every
    // caller of the old shape - `BoardTray`, `BoardCardMenu`, `WorkspaceBrowser` and
    // `FolderFileOperations` - in the same batch ("a removal has no placeholder").
    // Those four files sit outside this task's write scope, so the old members stay so
    // the whole target keeps building.
    //
    // Every body below is a placeholder, never real logic: `load(board:)` always
    // throws `.missing`, the rest return the emptiest value that still type-checks.
    // `url(forBoard:)` is the one exception - a plain path join with no judgment call,
    // exactly like `url(forFolder:)` above.

    func url(forBoard board: String) -> URL {
        root.appending(path: board, directoryHint: .notDirectory)
    }

    /// Placeholder: always throws `.missing`. The real body loads the file at
    /// `url(forBoard:)` when it exists and throws only when it does not (ADR-0025
    /// §D1, F2) - the coder's GREEN-phase work.
    func load(board: String) throws -> CanvasDocument {
        throw StoreError.missing(board)
    }

    /// Placeholder: writes nothing, returns an empty hash.
    @discardableResult
    func save(_ document: CanvasDocument, board: String) throws -> String {
        ""
    }

    /// Placeholder: reports no entries at all.
    func contents(ofBoard board: String, document: CanvasDocument) -> FolderContents {
        FolderContents(subfolders: [], unplaced: [])
    }

    /// Placeholder: creates nothing, returns an empty path.
    func createBoard(named name: String, in parent: String) throws -> String {
        ""
    }

    /// Placeholder: always reports the name as taken.
    func boardNameIsAvailable(_ name: String, in parent: String) -> Bool {
        false
    }

    /// Placeholder: reports no folders.
    func allFolders() -> [String] {
        []
    }

    /// Creates a real directory for a folder card (SPEC §6.4, tool 4).
    func createFolder(named name: String, in parent: String) throws -> String {
        let relativePath = parent.isEmpty ? name : "\(parent)/\(name)"
        let directory = root.appending(path: relativePath, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            throw StoreError.alreadyExists(relativePath)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return relativePath
    }

    enum StoreError: Error, CustomStringConvertible {
        case alreadyExists(String)
        /// ADR-0025 §D1: a `load(board:)` whose file is not there fails loudly instead
        /// of silently returning `.empty` (F2 - "the single most damaging failure
        /// mode of the feature").
        case missing(String)

        var description: String {
            switch self {
            case .alreadyExists(let path): "\(path) esiste già"
            case .missing(let path): "\(path) non esiste"
            }
        }
    }
}

/// Identifiers for new nodes.
///
/// JSON Canvas only requires uniqueness within the file. A 16-hex-character value is
/// the shape Obsidian writes, which keeps a Pergamenum canvas visually
/// indistinguishable from one Obsidian produced.
enum CanvasID {
    static func generate() -> String {
        let digits = "0123456789abcdef"
        return String((0..<16).map { _ in digits.randomElement()! })
    }

    /// Duplica's own generator (ADR-0023 §D11): retries `make()` against every id already
    /// in the document - nodes and edges both, since a strict JSON Canvas reader is
    /// entitled to treat them as one namespace - with a bounded random retry and then a
    /// deterministic suffix walk that cannot fail to terminate or return a taken id.
    ///
    /// Plan `docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md`, Task 2
    /// (R-10, R-11). `generate()` above is untouched: `Tests/CanvasTests.swift` pins its
    /// 16-hex shape and Obsidian parity depends on it.
    static func generate(avoiding taken: Set<String>, using make: () -> String = { generate() }) -> String {
        // A collision between two 16-hex values is already improbable; sixteen of them in
        // a row means the generator is not producing free values at all, so stop asking.
        for _ in 0..<16 {
            let candidate = make()
            if !taken.contains(candidate) { return candidate }
        }

        // Deterministic escape, so a generator that can never produce a free value still
        // terminates with an id `taken` does not hold. The walk visits distinct
        // candidates 0, 1, 2, … - the same twelve-character stem with a different four-hex
        // counter - and `taken` holds exactly `taken.count` values, so at most that many
        // of them can collide: candidate number `taken.count` is free at the latest.
        // More candidates than `taken` can hold is the whole argument; the loop cannot run
        // away and cannot return a taken id.
        let stem = String(make().prefix(12))
        var counter = 0
        var candidate = stem + String(format: "%04x", counter)
        while taken.contains(candidate) {
            counter += 1
            candidate = stem + String(format: "%04x", counter)
        }
        return candidate
    }
}
