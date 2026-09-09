import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 1 - R-02.
//
// The published-copy protocol, ADR §D2: `Envelope Index` (+ `-wal`, never `-shm`) is
// copied into a staging directory, opened read-write with no `SQLITE_OPEN_CREATE` so
// SQLite recovers the WAL into the copy, `PRAGMA quick_check`ed, then published with
// one atomic directory rename - never opening Mail's live file, never three separate
// renames a crash could interleave.
enum MailStoreCopy {
    /// The four outcomes ADR §D2 designs for. `SQLITE_OPEN_CREATE` is never passed
    /// (`Sources/Core/Email/MailStoreConnection.swift`), which is what makes a missing
    /// store answer `.storeMissing` rather than silently becoming an empty database.
    enum PublishResult: Equatable, Sendable {
        /// A fresh copy was made and published at this generation's directory.
        case published(URL)
        /// The source's modification date matches the already-published generation;
        /// nothing was copied. The URL is that existing, still-valid generation.
        case unchanged(URL)
        /// The copy was torn (Mail wrote between the two file copies) even after the
        /// one retry ADR §D2 step 3 allows.
        case mailIsWriting
        /// `source` holds no `Envelope Index` to copy.
        case storeMissing
    }

    /// `~/Library/Mail/V10/MailData/Envelope Index` - the two components below `source`.
    private static let mailDataDirectoryName = "MailData"
    private static let indexFileName = "Envelope Index"
    /// The write-ahead log beside it. The `-shm` is deliberately absent: it is shared
    /// memory belonging to Mail's own processes, and a stale one beside a fresh
    /// database is worse than none - SQLite rebuilds it (ADR §D2 step 1).
    private static let walSuffix = "-wal"
    /// One published generation per source modification date.
    private static let generationPrefix = "gen-"
    private static let stagingPrefix = ".staging-"
    /// ADR §D2 step 3: "retry once after 2 s". Mail's own write burst is what is being
    /// waited out, so the pause is deliberate rather than incidental.
    private static let retryDelay: TimeInterval = 2
    /// ADR §D2 step 4, the answer to «127,818 rows»: one index build per generation,
    /// off the main actor, in exchange for millisecond per-pratica queries. Possible
    /// only because the copy is ours.
    private static let indexStatements = [
        "CREATE INDEX IF NOT EXISTS pergamenum_messages_conversation ON messages (conversation_id);",
        "CREATE INDEX IF NOT EXISTS pergamenum_messages_sender ON messages (sender);",
    ]

    /// Copies `Envelope Index` (+ `-wal`) found under `source` (a directory shaped
    /// like `~/Library/Mail/V10`, i.e. what `MailStoreLocation.resolve()` returns)
    /// into a fresh generation under `stateDirectory`, skipping the copy when the
    /// source's modification date matches the last published generation.
    ///
    /// Synchronous by design: it copies the whole index (355 MB and 127,677 messages
    /// on this Mac, 2.2 s end to end including both index builds), and sleeps two
    /// seconds on a torn copy, so every caller runs it off the main actor.
    static func publish(from source: URL, into stateDirectory: URL) -> PublishResult {
        let fileManager = FileManager.default
        let sourceIndex = source
            .appending(path: mailDataDirectoryName, directoryHint: .isDirectory)
            .appending(path: indexFileName, directoryHint: .notDirectory)

        guard let indexModifiedAt = modificationDate(of: sourceIndex, fileManager: fileManager) else {
            // No `Envelope Index` under `source`: report it rather than opening
            // anything, which is the whole reason `SQLITE_OPEN_CREATE` is never
            // passed downstream either (ADR §D1).
            return .storeMissing
        }

        // Measured on the live store on 2026-09-09: the `-wal` was fifteen minutes
        // *newer* than the database file. Mail appends new mail to the write-ahead log
        // and only writes the database itself at a checkpoint, so a generation stamped
        // on the database's own date alone would answer `.unchanged` for hours while
        // messages piled up in the very log this copy also takes.
        let walModifiedAt = modificationDate(
            of: sibling(of: sourceIndex, suffix: walSuffix), fileManager: fileManager
        )
        let modifiedAt = max(indexModifiedAt, walModifiedAt ?? indexModifiedAt)

        let generation = stateDirectory.appending(
            path: generationName(for: modifiedAt), directoryHint: .isDirectory
        )
        let publishedIndex = generation.appending(path: indexFileName, directoryHint: .notDirectory)
        if fileManager.fileExists(atPath: publishedIndex.path(percentEncoded: false)) {
            // R-02: the source has not moved since this generation was published.
            return .unchanged(generation)
        }

        // One retry, then the honest answer - never a half-populated reader.
        for attempt in 0...1 {
            if attemptPublish(sourceIndex: sourceIndex, generation: generation, fileManager: fileManager) {
                deleteOtherGenerations(keeping: generation, in: stateDirectory, fileManager: fileManager)
                return .published(generation)
            }
            if attempt == 0 {
                Thread.sleep(forTimeInterval: retryDelay)
            }
        }
        return .mailIsWriting
    }

    // MARK: - One attempt

    /// Copies, recovers, checks and publishes; `false` on any failure, leaving the
    /// previously published generation (if any) untouched.
    private static func attemptPublish(
        sourceIndex: URL, generation: URL, fileManager: FileManager
    ) -> Bool {
        let stateDirectory = generation.deletingLastPathComponent()
        let staging = stateDirectory.appending(
            path: "\(stagingPrefix)\(UUID().uuidString)", directoryHint: .isDirectory
        )
        var published = false
        defer {
            if !published {
                try? fileManager.removeItem(at: staging)
            }
        }

        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)

            let stagedIndex = staging.appending(path: indexFileName, directoryHint: .notDirectory)
            try fileManager.copyItem(at: sourceIndex, to: stagedIndex)

            let sourceWAL = sibling(of: sourceIndex, suffix: walSuffix)
            if fileManager.fileExists(atPath: sourceWAL.path(percentEncoded: false)) {
                try fileManager.copyItem(at: sourceWAL, to: sibling(of: stagedIndex, suffix: walSuffix))
            }

            try recoverAndIndex(stagedIndex)

            // One rename, one syscall (ADR §D2). A generation directory left behind
            // by an interrupted earlier run has no `Envelope Index` in it - the
            // `.unchanged` check above already proved that - so it is stale by
            // definition and goes first.
            if fileManager.fileExists(atPath: generation.path(percentEncoded: false)) {
                try? fileManager.removeItem(at: generation)
            }
            try fileManager.moveItem(at: staging, to: generation)
            published = true
            return true
        } catch {
            return false
        }
    }

    /// ADR §D2 steps 2 to 5, on our own copy: read-write so SQLite replays the `-wal`
    /// into it, integrity-checked, given the two indexes that answer "127,818 rows",
    /// then locked to reads.
    private static func recoverAndIndex(_ index: URL) throws {
        let connection = try MailStoreConnection.open(at: index, readOnly: false)
        defer { connection.close() }

        try connection.quickCheck()
        for statement in indexStatements {
            try run(statement, on: connection)
        }
        // Last, and only after the indexes exist: `query_only` refuses every write
        // statement, including a `CREATE INDEX`.
        try run("PRAGMA query_only = 1;", on: connection)
    }

    private static func run(_ sql: String, on connection: MailStoreConnection) throws {
        let statement = try connection.prepare(sql)
        defer { connection.finalize(statement) }
        while try connection.step(statement) {}
    }

    // MARK: - Generations

    /// The published generation's own name *is* the source's modification stamp, so
    /// "has Mail written since?" is a directory lookup rather than a stored record.
    /// Milliseconds: two publications of the same second must not collide.
    private static func generationName(for modifiedAt: Date) -> String {
        let milliseconds = Int64((modifiedAt.timeIntervalSinceReferenceDate * 1000).rounded())
        return "\(generationPrefix)\(milliseconds)"
    }

    private static func modificationDate(of url: URL, fileManager: FileManager) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private static func sibling(of url: URL, suffix: String) -> URL {
        url.deletingLastPathComponent()
            .appending(path: url.lastPathComponent + suffix, directoryHint: .notDirectory)
    }

    /// Only ever inside `stateDirectory`, and only entries this type wrote: a
    /// generation whose stamp is no longer the source's, or a staging directory an
    /// interrupted run left behind.
    private static func deleteOtherGenerations(
        keeping generation: URL, in stateDirectory: URL, fileManager: FileManager
    ) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: stateDirectory, includingPropertiesForKeys: nil
        ) else { return }

        let kept = generation.lastPathComponent
        for entry in entries {
            let name = entry.lastPathComponent
            guard name != kept,
                  name.hasPrefix(generationPrefix) || name.hasPrefix(stagingPrefix)
            else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }
}
