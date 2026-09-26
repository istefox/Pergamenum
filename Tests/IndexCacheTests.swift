import Foundation
import SQLite3
import Testing
@testable import Pergamenum

/// What this suite needs beyond a throwaway vault: where its cache lives. File-private on
/// purpose, so `TemporaryVault` stays what every other suite shares (ADR-0051 §D4).
private extension TemporaryVault {
    /// Resolved through the real `VaultState` rather than a hand-rolled path, so this suite
    /// exercises the location the app actually writes to (ADR-0017). It lives under
    /// `stateBase`, a sibling of `root`, and is a pure derivation: nothing is created.
    var cacheURL: URL {
        VaultState(id: "cache-vault-test", base: stateBase).cacheFile
    }

    /// Writes junk straight to `cacheURL`, standing in for a damaged or half-written
    /// cache file - `cacheURL` no longer lives under `root`, so this cannot go through
    /// `write(_:to:)`, which is relative to the vault.
    func corruptCache() throws {
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("questo non è un database".utf8).write(to: cacheURL)
    }
}

private let note = """
---
date: 2026-08-12
tags:
  - type-note
  - topic-vibrazioni
aliases:
  - AV-45
---

Corpo con [[Altra nota]].

- [ ] Un task >2026-08-20 #project-vibrofer
"""

@Test func aSavedRecordComesBackWhole() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "01 Progetti/Nota.md")
    let scanned = VaultScanner(root: vault.root).scan()

    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(scanned.records))

    let loaded = cache.load()
    let entry = try #require(loaded["01 Progetti/Nota.md"])
    let record = entry.record.record

    #expect(record.title == "Nota")
    #expect(record.frontmatter.date == CalendarDate(iso: "2026-08-12"))
    #expect(record.frontmatter.tags.map(\.description) == ["type-note", "topic-vibrazioni"])
    #expect(record.frontmatter.aliases == ["AV-45"])
    #expect(record.linkTargets == ["Altra nota"])
    #expect(record.contentHash == scanned.records[0].contentHash)
}

/// Schema 3 (ADR-0009 §D2): the one field M11 was allowed to add, and a cache that
/// cannot carry it would make the gallery re-read the vault on every launch.
@Test func aCachedRecordCarriesItsEmbeddedFiles() throws {
    let vault = try TemporaryVault()
    try vault.write(note + "\n\n![[foto.png]]\n", to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    let record = try #require(cache.load()["Nota.md"]?.record.record)
    #expect(record.embedTargets == ["foto.png"])
    #expect(record.linkTargets == ["Altra nota"])
}

@Test func aCachedTaskKeepsItsDatesAndItsProject() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    let task = try #require(cache.load()["Nota.md"]?.record.record.tasks.first)
    #expect(task.text == "Un task")
    #expect(task.scheduled == CalendarDate(iso: "2026-08-20"))
    #expect(task.project == Tag("project-vibrofer"))
}

@Test func anUnchangedFileIsTakenFromTheCacheInsteadOfBeingRead() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    try vault.write(note, to: "Altra.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    var scanner = VaultScanner(root: vault.root)
    scanner.cached = cache.load()
    let outcome = scanner.scan()

    #expect(outcome.records.count == 2)
    #expect(outcome.reusedFromCache == 2)
}

@Test func aFileEditedSinceTheCacheIsReadAgain() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    // Same path, different contents: the cached row must not win, or the app would
    // show a note that no longer exists in that form.
    try vault.write(note + "\n\nRiga aggiunta dopo la cache.\n", to: "Nota.md")

    var scanner = VaultScanner(root: vault.root)
    scanner.cached = cache.load()
    let outcome = scanner.scan()

    #expect(outcome.reusedFromCache == 0)
    #expect(outcome.records[0].byteSize > cache.load()["Nota.md"]!.byteSize)
}

@Test func aNoteDeletedSinceTheCacheDoesNotComeBack() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    try vault.write(note, to: "Sparita.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    try FileManager.default.removeItem(at: vault.root.appending(path: "Sparita.md"))

    var scanner = VaultScanner(root: vault.root)
    scanner.cached = cache.load()
    let outcome = scanner.scan()

    // The walk is over the vault, not over the cache: a cached row for a file that is
    // gone is simply never reached.
    #expect(outcome.records.map(\.relativePath) == ["Nota.md"])
}

@Test func loadingACacheThatIsNotThereGivesNothing() throws {
    let vault = try TemporaryVault()
    #expect(IndexCache(url: vault.cacheURL).load().isEmpty)
}

@Test func loadingACorruptFileGivesNothingRatherThanHalfAVault() throws {
    let vault = try TemporaryVault()
    try vault.corruptCache()
    // A partial read would be indistinguishable from a vault that had lost notes.
    #expect(IndexCache(url: vault.cacheURL).load().isEmpty)
}

@Test func aCacheFromAnOlderSchemaIsIgnored() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))
    #expect(!cache.load().isEmpty)

    // Simulates the schema moving on: the rows are dropped, not migrated.
    var database: OpaquePointer?
    sqlite3_open(vault.cacheURL.path(percentEncoded: false), &database)
    sqlite3_exec(database, "PRAGMA user_version = 99;", nil, nil, nil)
    sqlite3_close(database)

    #expect(cache.load().isEmpty)
}

/// ADR-0065 §D12 (G1.1): a version 4 row read a CRLF note's frontmatter as empty and counted a
/// `.canvas` link target, so a cache stamped 4 is dropped and rebuilt, never reused.
@Test func aCacheStampedFourIsNotReused() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))
    #expect(!cache.load().isEmpty)

    var database: OpaquePointer?
    sqlite3_open(vault.cacheURL.path(percentEncoded: false), &database)
    sqlite3_exec(database, "PRAGMA user_version = 4;", nil, nil, nil)
    sqlite3_close(database)

    #expect(cache.load().isEmpty)
}

@Test func savingTwiceLeavesOnlyTheSecondSetOfNotes() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Prima.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    try FileManager.default.removeItem(at: vault.root.appending(path: "Prima.md"))
    try vault.write(note, to: "Seconda.md")
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    #expect(Array(cache.load().keys) == ["Seconda.md"])
}

// MARK: - ADR-0021 D4: the three new `TaskItem` fields ride the existing re-parse, no
// schema bump (R-14, R-04). Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 2.
// `StoredTask` is untouched (D4's closing paragraph) - these tests hold that promise, not
// a new field on it.

private let taskMarkerNote = """
- [ ] Padre assegnato ^[[vibrofer-emea.canvas]] ^id(1)
- [ ] Figlio del padre ^parent(1)
"""

@Test func theThreeNewTaskFieldsSurviveASaveAndLoadRoundTripWithNoSchemaBump() throws {
    let vault = try TemporaryVault()
    try vault.write(taskMarkerNote, to: "Progetto.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    let tasks = try #require(cache.load()["Progetto.md"]).record.record.tasks
    #expect(tasks.count == 2)
    #expect(tasks[0].workspacePath == "vibrofer-emea.canvas")
    #expect(tasks[0].localID == 1)
    #expect(tasks[0].parentLocalID == nil)
    #expect(tasks[1].workspacePath == nil)
    #expect(tasks[1].localID == nil)
    #expect(tasks[1].parentLocalID == 1)

    // Literal, so a coder who bumps the schema to carry *this* feature turns this test
    // red (ADR-0021 D4: "There is no schema change, no version bump"). The value itself
    // moved to 4 for an unrelated reason (ADR-0047 §D5, `categorySlug`), and to 5 for
    // another (ADR-0065 §D12, CRLF frontmatter and `.canvas` link targets) - this pin is
    // about ADR-0021 spending no bump of its own, not about the version staying 3
    // forever.
    #expect(IndexCache.schemaVersion == 5)
}

@Test func deletingCacheDbAndRescanningReDerivesTheSameRelationships() throws {
    let vault = try TemporaryVault()
    try vault.write(taskMarkerNote, to: "Progetto.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))
    let beforeTasks = try #require(cache.load()["Progetto.md"]).record.record.tasks

    // "Delete cache.db and rescan" (R-14), taken literally.
    cache.clear()
    #expect(cache.load().isEmpty)

    let rescanned = try #require(
        VaultScanner(root: vault.root).scan().records.first { $0.relativePath == "Progetto.md" }
    )

    #expect(rescanned.tasks.map(\.workspacePath) == beforeTasks.map(\.workspacePath))
    #expect(rescanned.tasks.map(\.localID) == beforeTasks.map(\.localID))
    #expect(rescanned.tasks.map(\.parentLocalID) == beforeTasks.map(\.parentLocalID))
}

@Test func clearingRemovesTheFile() throws {
    let vault = try TemporaryVault()
    try vault.write(note, to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    cache.clear()
    #expect(!FileManager.default.fileExists(atPath: vault.cacheURL.path(percentEncoded: false)))
    #expect(cache.load().isEmpty)
}

// MARK: - The staleness check itself

private func entry(size: Int, modifiedAt: Date) -> IndexCache.Entry {
    IndexCache.Entry(
        record: StoredRecord(NoteRecord(
            relativePath: "x.md", title: "x", frontmatter: .empty, linkTargets: [],
            tasks: [], modifiedAt: modifiedAt, byteSize: size, contentHash: "h"
        )),
        byteSize: size,
        modifiedAt: modifiedAt
    )
}

@Test func sameSizeAndSameSecondCountsAsUnchanged() {
    let when = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(VaultScanner.isUnchanged(entry(size: 120, modifiedAt: when), size: 120, modifiedAt: when))
    // File systems disagree on sub-second precision, so within a second is unchanged.
    #expect(VaultScanner.isUnchanged(
        entry(size: 120, modifiedAt: when), size: 120, modifiedAt: when.addingTimeInterval(0.3)
    ))
}

@Test func aDifferentSizeIsAlwaysAChange() {
    let when = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(!VaultScanner.isUnchanged(entry(size: 120, modifiedAt: when), size: 121, modifiedAt: when))
}

@Test func aLaterModificationIsAChange() {
    let when = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(!VaultScanner.isUnchanged(
        entry(size: 120, modifiedAt: when), size: 120, modifiedAt: when.addingTimeInterval(5)
    ))
}

@Test func aFileWithNoModificationDateIsNeverReused() {
    let when = Date(timeIntervalSince1970: 1_800_000_000)
    // Unknown is not the same as unchanged.
    #expect(!VaultScanner.isUnchanged(entry(size: 120, modifiedAt: when), size: 120, modifiedAt: nil))
}
