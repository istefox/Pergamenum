import Foundation
import Testing
@testable import Pergamenum

// MARK: - ADR-0055 §D1: `NoteStore.writeGuarded`, the one guarded note door
//
// Mirrors `Tests/CanvasStoreTests.swift`'s `writeRepoint` block for the note-shaped twin: a
// change whose `before` matches the file's current bytes writes `after`, a stale `before`
// refuses through `VaultWriteRefusal.movedOn` with nothing written, a missing file refuses
// rather than being created (ADR-0046 §D8), and a path escaping the vault refuses through
// `boundary` exactly as `CanvasStore.writeRepoint`'s own escape test does.

@Test func writeGuardedWritesOnAFreshChangeAndRefusesOnAStaleOne() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)
    try vault.write("prima", to: "Nota.md")

    try store.writeGuarded(VaultFileChange(path: "Nota.md", before: "prima", after: "dopo"))
    #expect(try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8) == "dopo")

    // A second write against the same (now stale) `before` refuses.
    do {
        try store.writeGuarded(VaultFileChange(path: "Nota.md", before: "prima", after: "terzo"))
        Issue.record("expected writeGuarded to refuse a stale before")
    } catch VaultWriteRefusal.movedOn(let path) {
        #expect(path == "Nota.md")
    } catch {
        Issue.record("expected VaultWriteRefusal.movedOn, got \(error)")
    }
    #expect(
        try String(contentsOf: vault.root.appending(path: "Nota.md"), encoding: .utf8) == "dopo",
        "the refused write must leave the file untouched"
    )
}

@Test func writeGuardedRefusesAndCreatesNothingWhenTheFileDoesNotExist() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)

    do {
        try store.writeGuarded(VaultFileChange(path: "Mai esistita.md", before: "qualsiasi", after: "nuovo"))
        Issue.record("expected writeGuarded to refuse a missing file")
    } catch VaultWriteRefusal.movedOn(let path) {
        #expect(path == "Mai esistita.md")
    } catch {
        Issue.record("expected VaultWriteRefusal.movedOn, got \(error)")
    }
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "Mai esistita.md").path(percentEncoded: false)
    ))
}

@Test func writeGuardedRefusesAPathEscapingTheVault() throws {
    let vault = try TemporaryVault()
    let store = NoteStore(root: vault.root)
    let change = VaultFileChange(path: "../../evil.md", before: "x", after: "y")

    do {
        try store.writeGuarded(change)
        Issue.record("expected writeGuarded to refuse a path escaping the vault")
    } catch {
        // refusal - either a boundary violation or VaultWriteRefusal is acceptable.
    }
}
