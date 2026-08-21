import Foundation
import Testing
@testable import Pergamenum

/// `VaultState.migrateIfNeeded`, slice 1's half of ADR-0017 §D3: `cache.db` and
/// `thumbnails/` are removed from the vault and rebuilt beside it, never moved.
/// `history/` and `ai-journal/` join this in slice 2 and are untouched here.

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
    #expect(record.migrated.sorted() == ["cache", "thumbnails"])
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
    #expect(record.migrated.sorted() == ["cache", "thumbnails"])
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
