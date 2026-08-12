import Foundation
import SQLite3
import Testing
@testable import Pergamenum

private struct CacheVault: ~Copyable {
    let root: URL
    let cacheURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheURL = root.appending(path: ".pergamenum/cache.db")
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
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
    let vault = try CacheVault()
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

@Test func aCachedTaskKeepsItsDatesAndItsProject() throws {
    let vault = try CacheVault()
    try vault.write(note, to: "Nota.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    let task = try #require(cache.load()["Nota.md"]?.record.record.tasks.first)
    #expect(task.text == "Un task")
    #expect(task.scheduled == CalendarDate(iso: "2026-08-20"))
    #expect(task.project == Tag("project-vibrofer"))
}

@Test func anUnchangedFileIsTakenFromTheCacheInsteadOfBeingRead() throws {
    let vault = try CacheVault()
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
    let vault = try CacheVault()
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
    let vault = try CacheVault()
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
    let vault = try CacheVault()
    #expect(IndexCache(url: vault.cacheURL).load().isEmpty)
}

@Test func loadingACorruptFileGivesNothingRatherThanHalfAVault() throws {
    let vault = try CacheVault()
    try vault.write("questo non è un database", to: ".pergamenum/cache.db")
    // A partial read would be indistinguishable from a vault that had lost notes.
    #expect(IndexCache(url: vault.cacheURL).load().isEmpty)
}

@Test func aCacheFromAnOlderSchemaIsIgnored() throws {
    let vault = try CacheVault()
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

@Test func savingTwiceLeavesOnlyTheSecondSetOfNotes() throws {
    let vault = try CacheVault()
    try vault.write(note, to: "Prima.md")
    let cache = IndexCache(url: vault.cacheURL)
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    try FileManager.default.removeItem(at: vault.root.appending(path: "Prima.md"))
    try vault.write(note, to: "Seconda.md")
    #expect(cache.save(VaultScanner(root: vault.root).scan().records))

    #expect(Array(cache.load().keys) == ["Seconda.md"])
}

@Test func clearingRemovesTheFile() throws {
    let vault = try CacheVault()
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
