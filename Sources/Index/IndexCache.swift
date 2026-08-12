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

    private var handle: OpaquePointer?

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

    // MARK: Writing

    /// Replaces the cache with these records.
    ///
    /// One transaction: a cache half-written by an interrupted quit is exactly the
    /// state the version check above cannot detect, so it must never exist.
    @discardableResult
    func save(_ records: [NoteRecord]) -> Bool {
        save(records).isEmpty
    }

    /// The same save, returning what went wrong.
    ///
    /// Reported rather than swallowed: the first version left a zero-byte `cache.db`
    /// behind with nothing to say why, which is indistinguishable from a cache that
    /// was simply never written.
    func save(_ records: [NoteRecord]) -> String {
        guard let database = open(create: true) else {
            return "cache.db non apribile in scrittura"
        }
        defer { sqlite3_close(database) }
        guard prepareSchema(database) else { return "schema: \(message(database))" }

        guard exec(database, "BEGIN IMMEDIATE;"), exec(database, "DELETE FROM notes;") else {
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

    /// Bumped whenever `StoredRecord` changes shape. An older cache is dropped rather
    /// than migrated: it is rebuilt from the vault in a fraction of a second.
    static let schemaVersion: Int32 = 1

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
    var tasks: [StoredTask]
    var modifiedAt: Date
    var byteSize: Int
    var contentHash: String

    init(_ record: NoteRecord) {
        relativePath = record.relativePath
        title = record.title
        frontmatter = StoredFrontmatter(record.frontmatter)
        linkTargets = record.linkTargets
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
