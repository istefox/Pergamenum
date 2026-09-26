import Foundation
import Testing
@testable import Pergamenum

// ADR-0064 (external deletion reaches the editor tabs and the Diario pane), plan
// `docs/plans/pg-234-external-deletion.md` Task 2. Disk- and session-level coverage for R-07 and
// for §D2/§D6's guardrails: a missing path is a deletion, an unreadable-but-present or an
// iCloud-evicted one is not, and a path this session moved away through `VaultSession.moveFile`
// is not reported either (gate G1, ADR-0064 §D6).
//
// No sleep, no timer, no racing two tasks (ADR-0043 §D9). A deletion is always
// `TemporaryVault.remove(_:)`, straight through `FileManager`, never a session door - so it never
// lands in `selfWrittenHashes` and always reaches `reconcile` as a real external change.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-09-25\ntags:\n  - type-note\n---\n\n\(body)\n"
}

private func externalDeletionDisk(_ vault: borrowing TemporaryVault) -> VaultDisk {
    VaultDisk(
        store: NoteStore(root: vault.root),
        history: NoteHistory(directory: vault.stateBase.appending(path: "history"))
    )
}

@MainActor
private func externalDeletionSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: - Disk level (§D2)

/// Red on today's code: the missing-path branch still returns `change: nil` (R-07's own gap).
@Test func anAbsentPathIsReportedDeleted() async throws {
    let vault = try TemporaryVault()
    let disk = externalDeletionDisk(vault)
    let written = try await disk.writeFile(note(), to: "N.md")
    try vault.remove("N.md")

    let result = await disk.reconcile("N.md", selfWritten: [])

    #expect(result.change == VaultSession.ExternalChange(path: "N.md", content: .deleted))
    #expect(result.mutation.record == nil)
    #expect(result.mutation.sequence == written.sequence + 1)
    #expect(result.matchedSequence == nil)
}

/// Green today, and a guard against the literal "report `.deleted` for every failed read"
/// alternative ADR-0064 §D2 rejects: a file that is there but not valid UTF-8 is not a deletion.
@Test func anUnreadableFileIsNotADeletion() async throws {
    let vault = try TemporaryVault()
    let disk = externalDeletionDisk(vault)
    let url = vault.root.appending(path: "Binaria.md")
    try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: url)

    let result = await disk.reconcile("Binaria.md", selfWritten: [])

    #expect(result.change == nil)
}

/// Green today, and a guard: an iCloud eviction placeholder (`VaultScanner.evictedNoteName`)
/// left where the note was is a normal state of a supported setup (principle 6), not a deletion.
@Test func anICloudPlaceholderIsNotADeletion() async throws {
    let vault = try TemporaryVault()
    let disk = externalDeletionDisk(vault)
    _ = try await disk.writeFile(note(), to: "Nota.md")
    try vault.remove("Nota.md")
    try vault.write("qualcosa", to: ".Nota.md.icloud")

    let result = await disk.reconcile("Nota.md", selfWritten: [])

    #expect(result.change == nil)
}

// MARK: - Session level (R-07, §D6)

/// Red on today's code: same gap as the disk-level test, one layer up - the session must also
/// drop the index row.
@MainActor
@Test func theSessionReportsADeletionAndDropsTheRow() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "N.md")
    let session = await externalDeletionSession(vault)
    try vault.remove("N.md")

    let changes = await session.reconcile(["N.md"])

    #expect(changes == [VaultSession.ExternalChange(path: "N.md", content: .deleted)])
    #expect(session.index.note(at: "N.md") == nil)
}

/// Red on today's code: `moveFile` records no absence marker for the vacated source at all
/// today, so the first assertion already fails (ADR-0064 §D6, gate G1).
@MainActor
@Test func aPathThisSessionMovedAwayIsNotReported() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = await externalDeletionSession(vault)

    try await session.moveFile(from: "A.md", to: "B.md")

    #expect(!(session.selfWrittenHashes["A.md"] ?? []).isEmpty, "nessuna voce registrata oggi per il percorso lasciato libero")

    let changes = await session.reconcile(["A.md"])

    #expect(changes.isEmpty)
    #expect((session.selfWrittenHashes["A.md"] ?? []).isEmpty)
}

/// Red on today's code: the final reconcile after a real removal still reports nothing, the
/// same R-07 gap every other test here pins.
@MainActor
@Test func aFailedMoveLeavesNoAbsenceBehind() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = await externalDeletionSession(vault)

    await #expect(throws: (any Error).self) {
        try await session.moveFile(from: "A.md", to: "../fuori.md")
    }
    #expect((session.selfWrittenHashes["A.md"] ?? []).isEmpty)

    try vault.remove("A.md")
    let changes = await session.reconcile(["A.md"])

    #expect(changes == [VaultSession.ExternalChange(path: "A.md", content: .deleted)])
}

/// Red on today's code: the recreation half already reports `.text` today (no marker involved),
/// but the final removal still reports nothing.
@MainActor
@Test func aStaleAbsenceIsDroppedOnceThePathIsFoundPresent() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = await externalDeletionSession(vault)

    try await session.moveFile(from: "A.md", to: "B.md")

    let recreated = note("Ricreata.")
    try vault.write(recreated, to: "A.md")
    let textChange = await session.reconcile(["A.md"])
    #expect(textChange == [VaultSession.ExternalChange(path: "A.md", content: .text(recreated))])

    try vault.remove("A.md")
    let deletionChange = await session.reconcile(["A.md"])
    #expect(deletionChange == [VaultSession.ExternalChange(path: "A.md", content: .deleted)])
}

/// Red on today's code: R-09's ordering argument needs the watcher to still see a trash as a
/// deletion, which today's missing-path branch never reports.
@MainActor
@Test func aTrashedPathIsStillReportedDeleted() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = await externalDeletionSession(vault)

    try await session.trashFile(at: "A.md")

    let changes = await session.reconcile(["A.md"])

    #expect(changes == [VaultSession.ExternalChange(path: "A.md", content: .deleted)])
}
