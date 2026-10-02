import Foundation
import Testing
@testable import Pergamenum

// PG-282: every VaultDisk write door derives the record it returns from the bytes that landed,
// a kept BOM included, so `byteSize` is the file's own size and not three bytes short.

private let bom = Data([0xEF, 0xBB, 0xBF])

private func bomVault(_ vault: borrowing TemporaryVault, path: String, text: String) throws -> VaultDisk {
    try (bom + Data(text.utf8)).write(to: vault.root.appending(path: path, directoryHint: .notDirectory))
    let store = NoteStore(root: vault.root)
    return VaultDisk(store: store, history: NoteHistory(directory: vault.stateBase.appending(path: "history")))
}

private func sizeOnDisk(_ vault: borrowing TemporaryVault, _ path: String) throws -> Int {
    try Data(contentsOf: vault.root.appending(path: path, directoryHint: .notDirectory)).count
}

private let body = "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\nCorpo.\n"

@Test func theLegacyNoteWriteRecordCountsAKeptBOM() async throws {
    let vault = try TemporaryVault()
    let disk = try bomVault(vault, path: "N.md", text: body)
    let outcome = try await disk.write(
        body + "x", to: "N.md", precomputedHash: NoteStore.hash(Data((body + "x").utf8)),
        journalEntry: nil, journal: nil, recordsHistory: false
    )
    #expect(try outcome.record?.byteSize == sizeOnDisk(vault, "N.md"))
}

@Test func theSessionNoteWriteRecordCountsAKeptBOM() async throws {
    let vault = try TemporaryVault()
    let disk = try bomVault(vault, path: "N.md", text: body)
    let outcome = try await disk.write(
        body + "x", to: "N.md", precomputedHash: NoteStore.hash(Data((body + "x").utf8)),
        journalDescriptor: nil, journal: nil, recordsHistory: false
    )
    #expect(try outcome.record?.byteSize == sizeOnDisk(vault, "N.md"))
}

@Test func theSimpleWriteFileRecordCountsAKeptBOM() async throws {
    let vault = try TemporaryVault()
    let disk = try bomVault(vault, path: "N.md", text: body)
    let mutation = try await disk.writeFile(body + "x", to: "N.md")
    #expect(try mutation.record?.byteSize == sizeOnDisk(vault, "N.md"))
}

@Test func theJournallingWriteFileRecordCountsAKeptBOM() async throws {
    let vault = try TemporaryVault()
    let disk = try bomVault(vault, path: "N.md", text: body)
    let result = try await disk.writeFile(body + "x", to: "N.md", journalDescriptor: nil, journal: nil)
    #expect(try result.mutation.record?.byteSize == sizeOnDisk(vault, "N.md"))
}
