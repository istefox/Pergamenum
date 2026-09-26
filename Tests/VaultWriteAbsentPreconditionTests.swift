import Foundation
import Testing
@testable import Pergamenum

/// `VaultSession.write(_:to:expectingAbsent:)` (ADR-0057 §D3, Task 1): the creation-case
/// sibling of `expecting:` - a write that only lands when the file is not there yet.
///
/// These pin the door on its own, with no `DiaryController` involved: `Tests/DiaryWriteGuardTests.swift`
/// exercises the diary's own adoption of it.
private func absentPreconditionText(_ body: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func absentPreconditionSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

/// Red on today's code: `expectingAbsent` is threaded through but ignored by the
/// placeholder body, so the write lands instead of being refused.
@MainActor
@Test func writeExpectingAbsentToAnExistingFileRefusesAndLeavesItUntouched() async throws {
    let vault = try TemporaryVault()
    let session = await absentPreconditionSession(vault)
    let original = absentPreconditionText("Originale.")
    try vault.write(original, to: "Nota.md")
    await session.rescan()
    let recordBefore = session.index.note(at: "Nota.md")

    await #expect(throws: VaultSession.WriteRefusal.movedOn("Nota.md")) {
        try await session.write(absentPreconditionText("Sovrascritta."), to: "Nota.md", expectingAbsent: true)
    }

    #expect(try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8) == original)
    #expect(session.index.note(at: "Nota.md") == recordBefore)
    #expect((session.selfWrittenHashes["Nota.md"] ?? []).isEmpty)

    // A later external write to the same path is still reported by the watcher path the
    // existing `expecting:` tests use - the refused write above left no self-written hash
    // that would make the reconciler mistake the next external change for its own.
    let external = absentPreconditionText("Esterna.")
    try vault.write(external, to: "Nota.md")
    let changes = await session.reconcile(["Nota.md"])
    #expect(!changes.isEmpty)
}

/// Green today: a missing path still writes, creating its folder, exactly as with no
/// precondition at all.
@MainActor
@Test func writeExpectingAbsentToAMissingFileWritesAndCreatesItsFolder() async throws {
    let vault = try TemporaryVault()
    let session = await absentPreconditionSession(vault)

    try await session.write(absentPreconditionText("Nuova."), to: "Cartella/Nota.md", expectingAbsent: true)

    let text = try String(contentsOf: vault.root.appending(path: "Cartella/Nota.md"), encoding: .utf8)
    #expect(text == absentPreconditionText("Nuova."))
}

/// Red on today's code: existence, not readability, is what `expectingAbsent` refuses on
/// (ADR-0057 §D3) - a file that is there but not valid UTF-8 must not be silently
/// overwritten by a write that read it as "absent".
@MainActor
@Test func writeExpectingAbsentToAnExistingNonUTF8FileRefuses() async throws {
    let vault = try TemporaryVault()
    let session = await absentPreconditionSession(vault)
    let url = vault.root.appending(path: "Binaria.md")
    try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)

    await #expect(throws: VaultSession.WriteRefusal.movedOn("Binaria.md")) {
        try await session.write(absentPreconditionText("Sovrascritta."), to: "Binaria.md", expectingAbsent: true)
    }

    let bytesOnDisk = try Data(contentsOf: url)
    #expect(bytesOnDisk == Data([0xFF, 0xFE, 0x00, 0x01]))
}

// MARK: - ADR-0063 §D4.5: the same precondition on the `.canvas` door

@MainActor
private func armedAbsentPreconditionSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = await absentPreconditionSession(vault)
    // Armed exactly as a connector arms it, so a refused write can be shown to journal nothing.
    session.journal = session.journalOnDisk
    session.journalCommand = "t"
    return session
}

/// Red on today's code: the `.canvas` door takes `expectingAbsent` but the placeholder
/// ignores it, so the board is overwritten instead of the creation being refused.
@MainActor
@Test func writeFileExpectingAbsentOverAnExistingFileRefuses() async throws {
    let vault = try TemporaryVault()
    let session = await armedAbsentPreconditionSession(vault)
    try vault.write("{\"nodes\":[]}", to: "B.canvas")
    let journalBefore = session.journalOnDisk.entries().map(\.id)

    await #expect(throws: VaultWriteRefusal.movedOn("B.canvas")) {
        try await session.writeFile("{\"nodes\":[],\"x\":1}", to: "B.canvas", expectingAbsent: true)
    }

    #expect(try String(contentsOf: vault.root.appending(path: "B.canvas"), encoding: .utf8) == "{\"nodes\":[]}")
    #expect(session.journalOnDisk.entries().map(\.id) == journalBefore)
}

/// Green today: on a free path the creation writes and is journalled as a creation.
@MainActor
@Test func writeFileExpectingAbsentOnAFreePathWrites() async throws {
    let vault = try TemporaryVault()
    let session = await armedAbsentPreconditionSession(vault)

    try await session.writeFile("{\"nodes\":[]}", to: "B.canvas", expectingAbsent: true)

    #expect(try String(contentsOf: vault.root.appending(path: "B.canvas"), encoding: .utf8) == "{\"nodes\":[]}")
    let entry = try #require(session.journalOnDisk.entries().last)
    #expect(entry.path == "B.canvas")
    #expect(entry.textBefore == nil)
}
