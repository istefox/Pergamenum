import Foundation

/// Reads and writes the `.canvas` files that back the Workspace boards.
///
/// ADR-0025 §D1: a board is addressed by its own vault-relative path and is never
/// derived from the folder holding it. A folder is a container and a board is a file,
/// so a folder may hold no board, one, or several, under any name - and the store is
/// told which one it is reading rather than working it out.
///
/// `load(board:)` **throws** for a file that is not there where the folder-derived
/// `load(folder:)` returned `.empty` (ADR-0025 F2, ADR-0022's own "single most damaging
/// failure mode"): every path this app opens is one a walk found or `createBoard` just
/// wrote, so a missing file means the disk moved under us - a thing to report, not a
/// thing to draw as a blank board.
struct CanvasStore: Sendable {
    /// Resolved at construction for the same reason as `NoteStore.root`.
    let root: URL

    /// The only way this store turns a caller's board path into a `URL` it will read or
    /// write (ADR-0041 §D2). A board path reaches here from a `^[[…]]` marker, which is
    /// typed text, so it is no more trusted than a wikilink.
    ///
    /// Not `private`, unlike `NoteStore.boundary`: `WorkspaceController.fileURL(for:)`
    /// resolves a `.canvas` node's `file` against this same store and must go through the
    /// same guard rather than build a second one beside it.
    let boundary: VaultBoundary

    init(root: URL) {
        let boundary = VaultBoundary(root: root)
        self.boundary = boundary
        self.root = boundary.root
    }

    static let fileExtension = "canvas"

    /// Where a board's file *would* be, for a caller that only asks whether something is
    /// there.
    ///
    /// It delegates to `boundary` rather than resolving the path itself (ADR-0041 §D2),
    /// so it answers about exactly the file `load`, `save` and `createBoard` would touch
    /// and refuses exactly what they refuse. A "does this exist" that resolves a board
    /// path more permissively than the read does is a question answered about a different
    /// file than the one the caller is about to open.
    func url(forBoard board: String) throws -> URL {
        try boundary.url(for: board)
    }

    /// Reads the board at a vault-relative path, failing when the file is not there.
    ///
    /// The failure is the decision (ADR-0025 §D1): a caller that wants "open this board
    /// if it exists" asks which board a folder means and gets an answer that can be
    /// "none" (§D5) - it does not name a path and hope.
    func load(board: String) throws -> CanvasDocument {
        let fileURL = try boundary.url(for: board)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw StoreError.missing(board)
        }
        return try CanvasDocument(data: try Data(contentsOf: fileURL))
    }

    @discardableResult
    func save(_ document: CanvasDocument, board: String) throws -> String {
        let fileURL = try boundary.url(for: board)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let data = try document.encoded()
        try data.write(to: fileURL, options: .atomic)
        return NoteStore.hash(data)
    }

    /// The real contents of the folder holding the open board, split into what the board
    /// already shows and what it does not.
    ///
    /// The folder is derived from the board's own path, so a file dropped on a board
    /// lands beside it whatever the board is called (ADR-0025 §D1).
    ///
    /// SPEC §6.1: files dropped into the folder from Finder appear in a "Nuovi
    /// elementi" tray to be placed by hand. Nothing is positioned automatically,
    /// because a position the user did not choose is noise on a spatial canvas.
    ///
    /// No `.canvas` reaches the tray at all - not the open board's own file, and not a
    /// sibling board (ADR-0025 §D10): the tray offers unplaced items, not a board
    /// switcher. A `.canvas` already placed as a card on some board still draws; this is
    /// about what the tray *offers*, not about what a board *shows*.
    func contents(ofBoard board: String, document: CanvasDocument) -> FolderContents {
        let folder = (board as NSString).deletingLastPathComponent
        let directory = folder.isEmpty
            ? root
            : root.appending(path: folder, directoryHint: .isDirectory)

        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        )) ?? []

        let placed = Set(document.nodes.compactMap { node -> String? in
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
            // One predicate rather than an exception list: no board is an item in the
            // tray (ADR-0025 §D10).
            guard entry.pathExtension.lowercased() != Self.fileExtension else { continue }
            if !placed.contains(relativePath) { unplaced.append(relativePath) }
        }
        return FolderContents(subfolders: subfolders, unplaced: unplaced)
    }

    struct FolderContents: Equatable, Sendable {
        var subfolders: [String]
        /// Real entries the board has no node for yet.
        var unplaced: [String]
    }

    /// Writes an empty board at `<parent>/<name>.canvas` and returns its path
    /// (ADR-0025 §D1).
    ///
    /// It creates no directory and no folder named after the board: `parent` is a folder
    /// the caller picked from the tree, and a board whose folder vanished must fail
    /// loudly rather than resurrect it - the reasoning `createFolder` below already
    /// carries. A `.canvas` that name already belongs to is refused; a *folder* of the
    /// same name is not a collision at all, since a directory and a file may share a
    /// name in one directory.
    func createBoard(named name: String, in parent: String) throws -> String {
        let relativePath = Self.boardFilePath(named: name, in: parent)
        let fileURL = try boundary.url(for: relativePath)
        guard !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            throw StoreError.alreadyExists(relativePath)
        }
        try CanvasDocument.empty.encoded().write(to: fileURL, options: .atomic)
        return relativePath
    }

    /// Whether `createBoard(named:in:)` would accept this name, asked live and without
    /// writing - the relationship `FolderFileOperations.nameIsAvailable` has to
    /// `createFolder` (ADR-0022 §D11), so the creation sheet can refuse a taken name
    /// before the verb runs.
    func boardNameIsAvailable(_ name: String, in parent: String) -> Bool {
        // A name whose path leaves the vault is not a name `createBoard` would write, so
        // the sheet refuses it exactly as it refuses a taken one - the `Bool` this
        // signature already returns says "no" for both reasons.
        guard let fileURL = try? url(forBoard: Self.boardFilePath(named: name, in: parent)) else {
            return false
        }
        return !FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    /// The single spelling of "the file a board called `name` in `parent` would be", so
    /// the check and the write cannot disagree about which file they mean. It takes the
    /// board's own name and never a folder's: the folder→board rule is what ADR-0025 §D1
    /// deletes.
    private static func boardFilePath(named name: String, in parent: String) -> String {
        let fileName = "\(name).\(fileExtension)"
        return parent.isEmpty ? fileName : "\(parent)/\(fileName)"
    }

    /// Every `.canvas` file in the vault, as vault-relative paths, sorted.
    ///
    /// ADR-0021 D10: boards are enumerated on demand rather than carried in
    /// `IndexSnapshot`, which stays a note index. Called when the Workspace browser
    /// appears and on `scanGeneration`, the same trigger the note tree rebuilds on.
    func allBoards() -> [String] {
        walk().boards
    }

    /// Every directory in the vault, as vault-relative paths, sorted - including one
    /// holding no board at all, which is the row the Workspace tree could not draw
    /// before (ADR-0025 §D1/§D2).
    ///
    /// Not `VaultSession.folders`, which derives folders from *note* paths and so omits
    /// a folder holding only boards or only subfolders - precisely the folders a
    /// Workspace user creates (ADR-0022 §D11).
    func allFolders() -> [String] {
        walk().folders
    }

    /// Both lists at once, for the caller that needs both - exactly what `allBoards()`
    /// and `allFolders()` each return, same order and same exclusions, since each of
    /// them is one field of this pair.
    ///
    /// The Workspace tree asked for both in a row and so enumerated the vault twice for
    /// the one answer the walk below already computes in a single pass. Kept beside the
    /// two single-answer accessors rather than replacing them: every other caller wants
    /// one list and would otherwise have to discard the other.
    func foldersAndBoards() -> (folders: [String], boards: [String]) {
        walk()
    }

    /// One walk, both answers, because they are the same walk: `allBoards()` passed
    /// every directory and discarded it, and those directories are exactly what
    /// `allFolders()` needs. A second enumerator would be a second exclusion rule to
    /// keep in step with this one.
    ///
    /// The walk itself is `VaultWalk` since ADR-0041 §D3: it is built from this store's own
    /// `boundary`, and it - not this method - consults `VaultLayout.isExcludedDirectory` and
    /// calls `skipDescendants()`, so `.obsidian`, `.git`, `.trash` and our own `.pergamenum`
    /// are never entered. What is left here is only what this caller wanted: two lists.
    private func walk() -> (folders: [String], boards: [String]) {
        // The two keys this caller used before the unification, kept rather than dropped to
        // the walk's `[]` default: `.isDirectoryKey` follows a symlink to a directory where
        // the URL's own trailing separator does not, and a folder row appearing or
        // disappearing from the Workspace tree is not a change this task is making.
        guard let walk = try? VaultWalk(
            boundary: boundary, keys: [.isDirectoryKey, .nameKey]
        ) else {
            return (folders: [], boards: [])
        }

        var folders: [String] = []
        var boards: [String] = []
        walk.forEach { file in
            if file.isDirectory {
                // The enumerator hands back a *directory* URL, whose path ends in "/",
                // and `VaultWalk.Entry.relativePath` preserves that faithfully - so this
                // would yield "01 Progetti/" where every other folder path in the app,
                // the tree's ids and the selection included, is spelled without one.
                let path = file.relativePath
                folders.append(path.hasSuffix("/") ? String(path.dropLast()) : path)
                return
            }
            guard file.url.pathExtension.lowercased() == Self.fileExtension else { return }
            boards.append(file.relativePath)
        }
        return (folders: Self.sorted(folders), boards: Self.sorted(boards))
    }

    /// `localizedStandardCompare`, so "9 Note" sorts before "10 Note" - the ordering
    /// both sidebars are read in.
    private static func sorted(_ paths: [String]) -> [String] {
        paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
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
