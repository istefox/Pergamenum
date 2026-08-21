import Foundation
import Testing
@testable import Pergamenum

/// `VaultState.migrateIfNeeded`, ADR-0017 §D3: `cache.db` and `thumbnails/` are removed
/// from the vault and rebuilt beside it, never moved (slice 1); `history/` and
/// `ai-journal/` are moved, never rebuilt, because they are not derived from the vault
/// (slice 2, below the slice-1 tests).

@Test func migrationRemovesTheOldCacheFileAndItsSQLiteSidecars() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
    for name in ["cache.db", "cache.db-journal", "cache.db-wal", "cache.db-shm"] {
        try Data("x".utf8).write(to: privateDirectory.appending(path: name))
    }

    let state = VaultState(id: "migration-cache", base: vault.stateBase)
    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    for name in ["cache.db", "cache.db-journal", "cache.db-wal", "cache.db-shm"] {
        let path = privateDirectory.appending(path: name).path(percentEncoded: false)
        #expect(!FileManager.default.fileExists(atPath: path))
    }
    // Removed, not rebuilt here: rebuilding is `rescan`'s job, not the migration's.
    #expect(!FileManager.default.fileExists(atPath: state.cacheFile.path(percentEncoded: false)))
}

@Test func migrationRemovesTheOldThumbnailsDirectory() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let thumbnails = privateDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
    try Data("png".utf8).write(to: thumbnails.appending(path: "abc@320.png"))

    let state = VaultState(id: "migration-thumbs", base: vault.stateBase)
    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: thumbnails.path(percentEncoded: false)))
}

@Test func migrationCreatesTheStateDirectoryAndADescriptorNamingTheStoresDone() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)

    let state = VaultState(id: "migration-descriptor", base: vault.stateBase)
    #expect(state.migrateIfNeeded(from: privateDirectory, root: vault.root).isEmpty)

    #expect(FileManager.default.fileExists(atPath: state.directory.path(percentEncoded: false)))
    let data = try Data(contentsOf: state.descriptor)
    let record = try JSONDecoder().decode(VaultState.Descriptor.self, from: data)
    // All four: "history" and "ai-journal" have nothing to migrate on an empty vault,
    // and nothing-to-do is success (ADR-0017 §D3).
    #expect(record.migrated.sorted() == ["ai-journal", "cache", "history", "thumbnails"])
    #expect(record.root == vault.root.path(percentEncoded: false))
}

/// The regression this migration exists to prevent: keying a store's step on whether
/// the *state directory* already exists would make slice 2's `history`/`ai-journal`
/// step a permanent no-op on any vault slice 1 already touched, because the
/// directory would already be there. Tracking per store in `vault.json` instead means
/// a step already marked done is skipped and a step that is not is still run, in the
/// same call, against the same already-existing directory.
@Test func migrationPicksUpAMissingStepWithoutRepeatingAFinishedOne() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: privateDirectory.appending(path: "cache.db"))
    let thumbnails = privateDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)

    let state = VaultState(id: "migration-partial", base: vault.stateBase)
    // Simulates a state directory that already exists - as it would on the first open
    // after slice 1 shipped - with "cache" already marked done but "thumbnails" not.
    try FileManager.default.createDirectory(at: state.directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    try encoder.encode(VaultState.Descriptor(root: nil, migrated: ["cache"])).write(to: state.descriptor)

    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    // "cache" was already marked done, so its step did not run again: the file it
    // would have removed is still exactly where it was.
    #expect(FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "cache.db").path(percentEncoded: false)
    ))
    // "thumbnails" was not marked done, so its step ran this time.
    #expect(!FileManager.default.fileExists(atPath: thumbnails.path(percentEncoded: false)))

    let record = try JSONDecoder().decode(
        VaultState.Descriptor.self, from: try Data(contentsOf: state.descriptor)
    )
    // "history" and "ai-journal" ran too, this same call, and had nothing to migrate.
    #expect(record.migrated.sorted() == ["ai-journal", "cache", "history", "thumbnails"])
}

@Test func aCacheConflictCopyIsReportedAndLeftAlone() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
    try Data("x".utf8).write(to: privateDirectory.appending(path: "cache.db"))
    try Data("y".utf8).write(to: privateDirectory.appending(path: "cache 2.db"))

    let state = VaultState(id: "migration-conflict", base: vault.stateBase)
    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.contains { $0.contains("cache 2.db") })
    #expect(!FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "cache.db").path(percentEncoded: false)
    ))
    // Left alone, not deleted: an upgrade that removes a file it did not itself write
    // is not a thing this app does (ADR-0017 §D3).
    #expect(FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "cache 2.db").path(percentEncoded: false)
    ))
}

@MainActor
@Test func aFullSessionMovesTheCacheOutOfTheVaultAndTheIndexStillWorks() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\nCorpo.\n", to: "Nota.md"
    )
    let oldCacheURL = vault.root.appending(path: ".pergamenum/cache.db")
    try FileManager.default.createDirectory(
        at: oldCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try Data("stale".utf8).write(to: oldCacheURL)

    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    #expect(session.index.count == 1)
    #expect(!FileManager.default.fileExists(atPath: oldCacheURL.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: session.state.cacheFile.path(percentEncoded: false)))
}

// MARK: - Slice 2: history/ and ai-journal/, moved rather than removed (ADR-0017 §D3)

@Test func migrationMovesAPopulatedHistoryTreeIntact() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let noteHistoryDir = privateDirectory.appending(path: "history/Nota.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: noteHistoryDir, withIntermediateDirectories: true)
    try Data("prima versione\n".utf8).write(to: noteHistoryDir.appending(path: "20260820-101500-ab12.md"))
    try Data("seconda versione\n".utf8).write(to: noteHistoryDir.appending(path: "20260821-091500-cd34.md"))

    let state = VaultState(id: "migration-history", base: vault.stateBase)
    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    #expect(!FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "history").path(percentEncoded: false)
    ))
    let movedDir = state.history.appending(path: "Nota.md", directoryHint: .isDirectory)
    let first = try String(contentsOf: movedDir.appending(path: "20260820-101500-ab12.md"), encoding: .utf8)
    let second = try String(contentsOf: movedDir.appending(path: "20260821-091500-cd34.md"), encoding: .utf8)
    #expect(first == "prima versione\n")
    #expect(second == "seconda versione\n")
}

@Test func migrationMovesTheAIJournalIntact() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let journalDir = privateDirectory.appending(path: "ai-journal", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: journalDir, withIntermediateDirectories: true)
    let line = "{\"id\":\"a\",\"path\":\"N.md\"}\n"
    try Data(line.utf8).write(to: journalDir.appending(path: "journal.jsonl"))

    let state = VaultState(id: "migration-journal", base: vault.stateBase)
    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    #expect(!FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "ai-journal").path(percentEncoded: false)
    ))
    let moved = try String(contentsOf: state.journal.appending(path: "journal.jsonl"), encoding: .utf8)
    #expect(moved == line)
}

/// The regression named in the plan: a vault whose `vault.json` already lists
/// `["cache", "thumbnails"]`, as it would after slice 1 alone, still picks up
/// `history`/`ai-journal` on its next open rather than being skipped forever because
/// the state directory already exists.
@Test func aVaultAlreadyPastSlice1StillPicksUpHistoryAndJournalMigration() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let historyDir = privateDirectory.appending(path: "history/Nota.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
    try Data("vecchia\n".utf8).write(to: historyDir.appending(path: "20260820-101500-ab12.md"))

    let state = VaultState(id: "migration-slice-order", base: vault.stateBase)
    try FileManager.default.createDirectory(at: state.directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(VaultState.Descriptor(root: nil, migrated: ["cache", "thumbnails"]))
        .write(to: state.descriptor)

    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    #expect(!FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "history").path(percentEncoded: false)
    ))
    let record = try JSONDecoder().decode(
        VaultState.Descriptor.self, from: try Data(contentsOf: state.descriptor)
    )
    #expect(record.migrated.sorted() == ["ai-journal", "cache", "history", "thumbnails"])
}

@Test func historyMigrationIsANoOpTheSecondTime() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let historyDir = privateDirectory.appending(path: "history/Nota.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
    try Data("vecchia\n".utf8).write(to: historyDir.appending(path: "20260820-101500-ab12.md"))

    let state = VaultState(id: "migration-idempotent", base: vault.stateBase)
    #expect(state.migrateIfNeeded(from: privateDirectory, root: vault.root).isEmpty)

    // Written straight into the new location after the first migration - the second
    // run must not touch it, and must not report anything new.
    let movedDir = state.history.appending(path: "Nota.md", directoryHint: .isDirectory)
    try Data("nuova\n".utf8).write(to: movedDir.appending(path: "20260821-091500-cd34.md"))

    let second = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(second.isEmpty)
    let entries = try FileManager.default.contentsOfDirectory(atPath: movedDir.path(percentEncoded: false))
    #expect(entries.sorted() == ["20260820-101500-ab12.md", "20260821-091500-cd34.md"])
}

/// The one guarantee D3 exists for: an interrupted move must never lose the only copy.
/// The state directory is made read-only after being created, so neither `moveItem` nor
/// its copy-then-verify-then-remove fallback can create `history/` inside it.
@Test func aFailedHistoryMoveLeavesTheSourceUntouchedAndDoesNotMarkItMigrated() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let historyDir = privateDirectory.appending(path: "history/Nota.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
    try Data("da non perdere\n".utf8).write(to: historyDir.appending(path: "20260820-101500-ab12.md"))

    let state = VaultState(id: "migration-failure", base: vault.stateBase)
    try FileManager.default.createDirectory(at: state.directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o555], ofItemAtPath: state.directory.path(percentEncoded: false)
    )
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: state.directory.path(percentEncoded: false)
        )
    }

    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.contains { $0.contains("history") })
    #expect(FileManager.default.fileExists(
        atPath: historyDir.appending(path: "20260820-101500-ab12.md").path(percentEncoded: false)
    ))
    let record = (try? Data(contentsOf: state.descriptor))
        .flatMap { try? JSONDecoder().decode(VaultState.Descriptor.self, from: $0) }
    #expect(record?.migrated.contains("history") != true)
}

@Test func migrationMergesWithAnAlreadyPopulatedDestination() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let sourceNoteDir = privateDirectory.appending(path: "history/Uno.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: sourceNoteDir, withIntermediateDirectories: true)
    try Data("da uno\n".utf8).write(to: sourceNoteDir.appending(path: "20260820-101500-ab12.md"))

    let state = VaultState(id: "migration-merge", base: vault.stateBase)
    // The destination already holds a snapshot of a different note, as it would after
    // an interrupted previous run, or a vault folder copied onto this one's id.
    let existingNoteDir = state.history.appending(path: "Due.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: existingNoteDir, withIntermediateDirectories: true)
    try Data("da due\n".utf8).write(to: existingNoteDir.appending(path: "20260819-101500-ef56.md"))

    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    #expect(!FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "history").path(percentEncoded: false)
    ))
    let uno = try String(
        contentsOf: state.history.appending(path: "Uno.md/20260820-101500-ab12.md"), encoding: .utf8
    )
    let due = try String(
        contentsOf: state.history.appending(path: "Due.md/20260819-101500-ef56.md"), encoding: .utf8
    )
    #expect(uno == "da uno\n")
    #expect(due == "da due\n")
}

@Test func aHistoryConflictCopyIsReportedAndLeftAlone() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let historyDir = privateDirectory.appending(path: "history/Uno.md", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
    try Data("da uno\n".utf8).write(to: historyDir.appending(path: "20260820-101500-ab12.md"))
    let conflictDir = privateDirectory.appending(path: "history 2", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: conflictDir, withIntermediateDirectories: true)
    try Data("conflitto\n".utf8).write(to: conflictDir.appending(path: "resto.md"))

    let state = VaultState(id: "migration-history-conflict", base: vault.stateBase)
    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.contains { $0.contains("history 2") })
    #expect(!FileManager.default.fileExists(
        atPath: privateDirectory.appending(path: "history").path(percentEncoded: false)
    ))
    // Left alone, not deleted, same as slice 1's conflict copies (ADR-0017 §D3).
    #expect(FileManager.default.fileExists(atPath: conflictDir.path(percentEncoded: false)))
}

// MARK: - The duplicated-vault report (ADR-0017 §D2/§D3)

@Test func twoDifferentRootsSharingAnIDReportADuplicatedVault() throws {
    let vaultA = try TemporaryVault()
    let vaultB = try TemporaryVault()
    let privateA = vaultA.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    let privateB = vaultB.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: privateB, withIntermediateDirectories: true)

    // Both resolve to the same state directory, as they would if the vault folder had
    // been copied and both copies carried the id minted into the first one.
    let stateA = VaultState(id: "shared-id", base: vaultA.stateBase)
    #expect(stateA.migrateIfNeeded(from: privateA, root: vaultA.root).isEmpty)

    let stateB = VaultState(id: "shared-id", base: vaultA.stateBase)
    let problems = stateB.migrateIfNeeded(from: privateB, root: vaultB.root)

    #expect(problems.contains {
        $0.contains(vaultA.root.path(percentEncoded: false)) && $0.contains(vaultB.root.path(percentEncoded: false))
    })
    // The pointer is updated regardless of the report: the next open compares against
    // whichever root opened most recently.
    let record = try JSONDecoder().decode(
        VaultState.Descriptor.self, from: try Data(contentsOf: stateB.descriptor)
    )
    #expect(record.root == vaultB.root.path(percentEncoded: false))
}

@Test func aRenamedRootUpdatesThePointerSilently() throws {
    let vault = try TemporaryVault()
    let privateDirectory = vault.root.appending(path: ".pergamenum", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: privateDirectory, withIntermediateDirectories: true)
    // A path that was never created on disk, standing in for the vault's folder before
    // it was renamed in the Finder.
    let goneRoot = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-gone-\(UUID().uuidString)", directoryHint: .isDirectory)

    let state = VaultState(id: "renamed-vault", base: vault.stateBase)
    try FileManager.default.createDirectory(at: state.directory, withIntermediateDirectories: true)
    try JSONEncoder().encode(VaultState.Descriptor(
        root: goneRoot.path(percentEncoded: false),
        migrated: ["ai-journal", "cache", "history", "thumbnails"]
    )).write(to: state.descriptor)

    let problems = state.migrateIfNeeded(from: privateDirectory, root: vault.root)

    #expect(problems.isEmpty)
    let record = try JSONDecoder().decode(
        VaultState.Descriptor.self, from: try Data(contentsOf: state.descriptor)
    )
    #expect(record.root == vault.root.path(percentEncoded: false))
}
