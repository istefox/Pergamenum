import Foundation
import SQLite3

/// The on-disk index of SPEC §12, in `.pergamenum/cache.db`.
///
/// SQLite through the system library rather than a package: it is already on every
/// Mac, the schema is four columns, and a dependency added for that would have to be
/// carried for the life of the app.
///
/// The cache is an optimisation and never the source of truth. Every row carries the
/// file's size and modification date, and a row whose file has changed is discarded
/// rather than trusted: the vault is the truth, and an index that disagreed with it
/// would be worse than no index at all (SPEC §1, "file over app").
struct IndexCache {
    let url: URL

    /// One cached note: the record, plus what it was when it was cached.
    struct Entry: Codable, Sendable {
        var record: StoredRecord
        var byteSize: Int
        var modifiedAt: Date
    }

    /// One cached board's tasks (PG-074, plan Section 4) - its own table, never a row in
    /// `notes`: a `.canvas` masquerading as a `StoredRecord` would surface as a false note in
    /// search, backlinks, the note tree and the connectors, reversing ADR-0025's board/note
    /// separation (plan decision 2).
    struct BoardEntry: Codable, Sendable {
        var record: StoredBoardTaskRecord
        var byteSize: Int
        var modifiedAt: Date
    }

    init(url: URL) {
        self.url = url
    }

    // MARK: Reading

    /// Reads the whole cache, keyed by path. Returns nothing at all when the file is
    /// missing, unreadable or written by a different schema: a partial read would be
    /// indistinguishable from a vault that had lost notes.
    func load() -> [String: Entry] {
        guard let database = open(create: false) else { return [:] }
        defer { sqlite3_close(database) }
        guard schemaVersion(of: database) == Self.schemaVersion else { return [:] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database, "SELECT path, payload FROM notes;", -1, &statement, nil
        ) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var entries: [String: Entry] = [:]
        let decoder = JSONDecoder()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathText = sqlite3_column_text(statement, 0),
                  let blob = sqlite3_column_blob(statement, 1)
            else { continue }
            let length = Int(sqlite3_column_bytes(statement, 1))
            let data = Data(bytes: blob, count: length)
            guard let entry = try? decoder.decode(Entry.self, from: data) else { continue }
            entries[String(cString: pathText)] = entry
        }
        return entries
    }

    /// Reads every cached board's tasks, keyed by the board's own path - `load()`'s sibling,
    /// same version guard, same "missing means empty rather than partial" reasoning. A schema
    /// version that fails the guard already made `load()` return nothing; this mirrors it
    /// rather than being called from inside it, so a caller that wants only notes never pays
    /// for a table it does not read.
    func loadBoardTasks() -> [String: BoardEntry] {
        guard let database = open(create: false) else { return [:] }
        defer { sqlite3_close(database) }
        guard schemaVersion(of: database) == Self.schemaVersion else { return [:] }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database, "SELECT path, payload FROM boardTasks;", -1, &statement, nil
        ) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var entries: [String: BoardEntry] = [:]
        let decoder = JSONDecoder()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let pathText = sqlite3_column_text(statement, 0),
                  let blob = sqlite3_column_blob(statement, 1)
            else { continue }
            let length = Int(sqlite3_column_bytes(statement, 1))
            let data = Data(bytes: blob, count: length)
            guard let entry = try? decoder.decode(BoardEntry.self, from: data) else { continue }
            entries[String(cString: pathText)] = entry
        }
        return entries
    }

    // MARK: Writing

    /// Replaces the cache with these records.
    ///
    /// One transaction: a cache half-written by an interrupted quit is exactly the
    /// state the version check above cannot detect, so it must never exist.
    @discardableResult
    func save(_ records: [NoteRecord], boardTasks: [BoardTaskRecord] = []) -> Bool {
        save(records, boardTasks: boardTasks).isEmpty
    }

    /// The same save, returning what went wrong.
    ///
    /// Reported rather than swallowed: the first version left a zero-byte `cache.db`
    /// behind with nothing to say why, which is indistinguishable from a cache that
    /// was simply never written.
    func save(_ records: [NoteRecord], boardTasks: [BoardTaskRecord] = []) -> String {
        guard let database = open(create: true) else {
            return "cache.db non apribile in scrittura"
        }
        defer { sqlite3_close(database) }
        guard prepareSchema(database) else { return "schema: \(message(database))" }

        guard exec(database, "BEGIN IMMEDIATE;"),
              exec(database, "DELETE FROM notes;"),
              exec(database, "DELETE FROM boardTasks;")
        else {
            return "transazione: \(message(database))"
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database, "INSERT INTO notes (path, payload) VALUES (?, ?);", -1, &statement, nil
        ) == SQLITE_OK else {
            _ = exec(database, "ROLLBACK;")
            return "insert: \(message(database))"
        }
        defer { sqlite3_finalize(statement) }

        let encoder = JSONEncoder()
        for record in records {
            let entry = Entry(
                record: StoredRecord(record),
                byteSize: record.byteSize,
                modifiedAt: record.modifiedAt
            )
            guard let data = try? encoder.encode(entry) else { continue }

            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, record.relativePath, -1, Self.transient)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(data.count), Self.transient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                let reason = message(database)
                _ = exec(database, "ROLLBACK;")
                return "\(record.relativePath): \(reason)"
            }
        }

        var boardStatement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database, "INSERT INTO boardTasks (path, payload) VALUES (?, ?);", -1, &boardStatement, nil
        ) == SQLITE_OK else {
            _ = exec(database, "ROLLBACK;")
            return "insert board: \(message(database))"
        }
        defer { sqlite3_finalize(boardStatement) }

        for record in boardTasks {
            let entry = BoardEntry(
                record: StoredBoardTaskRecord(record),
                byteSize: record.byteSize,
                modifiedAt: record.modifiedAt
            )
            guard let data = try? encoder.encode(entry) else { continue }

            sqlite3_reset(boardStatement)
            sqlite3_bind_text(boardStatement, 1, record.relativePath, -1, Self.transient)
            _ = data.withUnsafeBytes { bytes in
                sqlite3_bind_blob(boardStatement, 2, bytes.baseAddress, Int32(data.count), Self.transient)
            }
            guard sqlite3_step(boardStatement) == SQLITE_DONE else {
                let reason = message(database)
                _ = exec(database, "ROLLBACK;")
                return "\(record.relativePath): \(reason)"
            }
        }
        return exec(database, "COMMIT;") ? "" : "commit: \(message(database))"
    }

    private func message(_ database: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(database))
    }

    /// Removes the file, for "svuota cache" (SPEC §12, Avanzate).
    func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: SQLite plumbing

    /// Bumped whenever `StoredRecord` changes shape - **or its meaning**. An older cache
    /// is dropped rather than migrated: it is rebuilt from the vault in a fraction of a
    /// second, and principle 3 says nothing is lost by discarding it.
    ///
    /// 2 (ADR-0010 §D7): `linkTargets` now counts transcluded notes, so version 1 rows
    /// understate a note's links - wrong about what a column means, not repairable by a
    /// field addition. 3 (ADR-0009 §D2): adds `embedTargets`, for M11's gallery - the only
    /// schema change that milestone was permitted, spent once.
    ///
    /// 4 (ADR-0047 §D5): adds `StoredRecord.categorySlug`, since `StoredFrontmatter` keeps
    /// none of `foreignKeys` and a reused record would otherwise lose `pergamenum-category`
    /// from the second scan onward. This chain gets no second bump (ADR-0047 "Risks"). 5
    /// (ADR-0065 §D12): meaning only - version 4 rows hold an empty frontmatter for a CRLF note
    /// and count `.canvas` link targets.
    static let schemaVersion: Int32 = 5

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func open(create: Bool) -> OpaquePointer? {
        if !create, !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return nil
        }
        if create {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
        var database: OpaquePointer?
        let flags = create ? (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path(percentEncoded: false), &database, flags, nil) == SQLITE_OK
        else {
            if let database { sqlite3_close(database) }
            return nil
        }
        return database
    }

    private func prepareSchema(_ database: OpaquePointer) -> Bool {
        exec(database, "CREATE TABLE IF NOT EXISTS notes (path TEXT PRIMARY KEY, payload BLOB NOT NULL);")
            && exec(database, "CREATE TABLE IF NOT EXISTS boardTasks (path TEXT PRIMARY KEY, payload BLOB NOT NULL);")
            && exec(database, "PRAGMA user_version = \(Self.schemaVersion);")
    }

    private func schemaVersion(of database: OpaquePointer) -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK
        else { return -1 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : -1
    }

    private func exec(_ database: OpaquePointer, _ sql: String) -> Bool {
        sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
    }
}

/// A `NoteRecord` in a form that can be written down.
///
/// A separate type rather than `Codable` on `NoteRecord` itself: the record is shaped
/// for the app, and making it directly encodable would tie the on-disk format to every
/// future change to it. This one changes only with the schema version above.
struct StoredRecord: Codable, Sendable {
    var relativePath: String
    var title: String
    var frontmatter: StoredFrontmatter
    var linkTargets: [String]
    /// Added by M11, the one schema change ADR-0009 §D2 permits it. Defaulted so a row
    /// this field is missing from decodes rather than taking the whole cache down with
    /// it - the version guard already discards those rows, and a decoder that also
    /// refused would make the guard the only thing standing between a shape change and
    /// an empty index.
    var embedTargets: [String] = []
    /// Added by schema 4 (ADR-0047 §D5). Defaulted for the reason `embedTargets` is: a
    /// row this field is missing from decodes rather than taking the whole cache down.
    var categorySlug: String?
    var tasks: [StoredTask]
    var modifiedAt: Date
    var byteSize: Int
    var contentHash: String

    init(_ record: NoteRecord) {
        relativePath = record.relativePath
        title = record.title
        frontmatter = StoredFrontmatter(record.frontmatter)
        linkTargets = record.linkTargets
        embedTargets = record.embedTargets
        categorySlug = record.categorySlug
        tasks = record.tasks.map(StoredTask.init)
        modifiedAt = record.modifiedAt
        byteSize = record.byteSize
        contentHash = record.contentHash
    }

    var record: NoteRecord {
        NoteRecord(
            relativePath: relativePath,
            title: title,
            frontmatter: frontmatter.frontmatter,
            linkTargets: linkTargets,
            embedTargets: embedTargets,
            categorySlug: categorySlug,
            tasks: tasks.compactMap(\.task),
            modifiedAt: modifiedAt,
            byteSize: byteSize,
            contentHash: contentHash
        )
    }
}

struct StoredFrontmatter: Codable, Sendable {
    var date: String?
    var tags: [String]
    var aliases: [String]
    var related: [String]

    init(_ frontmatter: Frontmatter) {
        date = frontmatter.date?.description
        tags = frontmatter.tags.map(\.description)
        aliases = frontmatter.aliases
        related = frontmatter.related
    }

    var frontmatter: Frontmatter {
        var result = Frontmatter.empty
        result.date = date.flatMap { CalendarDate(iso: $0) }
        result.tags = tags.compactMap(Tag.init)
        result.aliases = aliases
        result.related = related
        return result
    }
}

struct StoredTask: Codable, Sendable {
    var rawLine: String
    var sourcePath: String
    var lineIndex: Int

    init(_ task: TaskItem) {
        rawLine = task.rawLine
        sourcePath = task.sourcePath
        lineIndex = task.lineIndex
    }

    /// Re-parsed from the line rather than stored field by field, so a cached task can
    /// never disagree with what the parser would say about the same line today.
    var task: TaskItem? {
        TaskParser.parse(line: rawLine, sourcePath: sourcePath, lineIndex: lineIndex)
    }
}

/// A `BoardTaskRecord` in a form that can be written down - `StoredRecord`'s sibling, one row
/// per board rather than per note (plan Section 4).
struct StoredBoardTaskRecord: Codable, Sendable {
    var relativePath: String
    var tasks: [StoredBoardTask]
    var modifiedAt: Date
    var byteSize: Int
    var contentHash: String

    init(_ record: BoardTaskRecord) {
        relativePath = record.relativePath
        tasks = record.tasks.map(StoredBoardTask.init)
        modifiedAt = record.modifiedAt
        byteSize = record.byteSize
        contentHash = record.contentHash
    }

    var record: BoardTaskRecord {
        BoardTaskRecord(
            relativePath: relativePath,
            tasks: tasks.compactMap(\.task),
            modifiedAt: modifiedAt,
            byteSize: byteSize,
            contentHash: contentHash
        )
    }
}

/// `StoredTask`'s sibling for a board-sourced task: the same re-parse-from-`rawLine` rule, plus
/// `nodeID` - `TaskParser.parse(line:sourcePath:lineIndex:)` has no parameter for it, so it is
/// carried alongside the three re-parsed fields and set on the result afterward.
struct StoredBoardTask: Codable, Sendable {
    var rawLine: String
    var sourcePath: String
    var lineIndex: Int
    var nodeID: String?

    init(_ task: TaskItem) {
        rawLine = task.rawLine
        sourcePath = task.sourcePath
        lineIndex = task.lineIndex
        nodeID = task.nodeID
    }

    var task: TaskItem? {
        guard var task = TaskParser.parse(line: rawLine, sourcePath: sourcePath, lineIndex: lineIndex)
        else { return nil }
        task.nodeID = nodeID
        return task
    }
}
