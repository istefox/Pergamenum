import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07 (ordering is a per-path sequence number, §D11), §D10 (the hash is recorded before
// the hop) and the two regressions §D9's own text calls out (ADR-0007 §D6's dry-run
// guardrail, ADR-0001 §D2.3's files-first-index-second invariant).
//
// These tests exercise `VaultSession.write(_:to:)`'s new **async** overload - a stub that
// calls the untouched synchronous implementation (see `VaultSession.swift`'s Task 8
// block) - and the test-only `apply(_:at:)` seam (`VaultSession+WriteOrdering.swift`), not
// `VaultDisk` directly; `VaultDiskTests` is where the actor itself is exercised. Because
// this stub has no actor hop of its own, a normal two-awaited-writes scenario cannot
// demonstrate a real inversion - it can only ever observe program order - so the
// inversion half of R-07 is manufactured directly through `apply(_:at:)` instead of
// through timing, exactly as the brief asks for ("assert on the drop, not only on the end
// state, or the test passes by accident when the guard is missing").

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-08-21\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func openSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: - Two writes to the same path, both awaited: the second one wins (the easy half of R-07)

@MainActor
@Test func twoAwaitedWritesToTheSamePathLeaveFileIndexAndHashOnTheSecond() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let second = note("Seconda.")

    try await session.write(note("Prima."), to: "N.md")
    try await session.write(second, to: "N.md")

    let onDisk = try String(contentsOf: vault.root.appending(path: "N.md"), encoding: .utf8)
    #expect(onDisk == second)
    #expect(session.index.note(at: "N.md")?.contentHash == NoteStore.hash(Data(second.utf8)))
    #expect(session.selfWrittenHashes["N.md"] == NoteStore.hash(Data(second.utf8)))
}

// MARK: - The inversion, forced through the seam (the half that actually needs the guard)

@MainActor
@Test func theOlderOutcomeIsDroppedWhenSequencesArriveInverted() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let store = NoteStore(root: vault.root)
    let path = "N.md"

    // Two outcomes for the same path, built independently of any real write - `apply`
    // is what a completed `VaultDisk.write` would hand to `write(_:to:)`, and what matters
    // here is only each one's `sequence`, not how it was produced.
    let olderData = Data(note("Vecchia.").utf8)
    let newerData = Data(note("Nuova.").utf8)
    let olderRecord = try store.record(from: olderData, attributes: [:], at: path)
    let newerRecord = try store.record(from: newerData, attributes: [:], at: path)
    let olderOutcome = VaultDisk.DiskWriteOutcome(
        record: olderRecord, hash: NoteStore.hash(olderData), sequence: 1, journalProblem: nil
    )
    let newerOutcome = VaultDisk.DiskWriteOutcome(
        record: newerRecord, hash: NoteStore.hash(newerData), sequence: 2, journalProblem: nil
    )

    // The true order first: the newer sequence applies cleanly.
    #expect(session.apply(newerOutcome, at: path) == true)
    #expect(session.index.note(at: path)?.contentHash == newerRecord.contentHash)

    // Then the older one arrives late, as an inverted continuation would (§D11).
    let applied = session.apply(olderOutcome, at: path)

    // Asserted on the drop itself, not only on the end state below - a stub with no guard
    // at all (this one) would answer `true` here and this line is what catches that,
    // rather than the test passing by accident because the second assertion alone would
    // also fail loudly enough to notice.
    #expect(applied == false, "un esito con sequenza più vecchia non deve applicarsi")
    #expect(
        session.index.note(at: path)?.contentHash == newerRecord.contentHash,
        "l'indice non deve tornare indietro alla scrittura più vecchia"
    )
}

// MARK: - §D10: the hash recorded is the hash of the bytes actually on disk

@MainActor
@Test func afterAWriteReturnsTheRecordedHashMatchesTheBytesOnDisk() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let text = note("Contenuto.")

    try await session.write(text, to: "N.md")

    let onDisk = try Data(contentsOf: vault.root.appending(path: "N.md"))
    #expect(session.selfWrittenHashes["N.md"] == NoteStore.hash(onDisk))
}

// The stronger form the brief asks for - a task scheduled between the hash assignment and
// the actor's completion already sees the hash recorded - is NOT written here, and that
// gap is deliberate rather than an oversight.
//
// `VaultSession.write`'s async overload is, right now, a stub with no suspension point of
// its own (`try writeSynchronously(text, to: relativePath)`, a synchronous call from an
// async function): there is no `await` inside it for a second task to interleave with, so
// any attempt to observe "does another task see the hash before completion" against this
// stub would either pass vacuously (nothing ever suspends, so there is nothing to race)
// or would have to fabricate a suspension point (e.g. an inserted `Task.yield()`) purely
// for the test's benefit - which is exactly the kind of timing-dependent, non-deterministic
// test this task's own brief rules out ("must be deterministic rather than timed"). Once
// the coder's real `await disk.write(...)` hop exists, this file is the place to add a
// deterministic version of the stronger test - most cleanly with a test-controlled gate
// inside `VaultDisk` that the test resumes explicitly, rather than a race against
// `Task.yield()`. Documented here per the brief's own instruction rather than silently
// left out.

// MARK: - ADR-0007 §D6 regression: a dry run never reaches disk, history or the journal

@MainActor
@Test func aDryRunWriteNeverReachesDiskHistoryOrJournal() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    session.journal = session.journalOnDisk
    session.isDryRun = true
    let text = note("Non deve arrivare su disco.")

    let result = try await session.write(text, to: "N.md")

    #expect(result.text == text)
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "N.md").path(percentEncoded: false)
    ))
    #expect(session.history.snapshots(for: "N.md").isEmpty)
    #expect(session.journalOnDisk.entries().isEmpty)
}

// MARK: - ADR-0001 §D2.3 regression: the index reflects what write wrote, not a later mutation

@MainActor
@Test func theIndexAfterAWriteReflectsWhatWasWrittenNotALaterMutation() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let written = note("Scritta dalla sessione.")

    try await session.write(written, to: "N.md")

    // A second, uncoordinated writer touches the same file right after - a raw write that
    // bypasses the session entirely, the way a `.canvas` editor or the async actor hop
    // itself (once wired in) makes possible. Nothing re-reads the file to build the index
    // record: `write(_:to:)` derives it once, from the bytes it itself wrote, and this
    // mutation must not retroactively change what the index already recorded.
    try Data(note("Mutazione esterna.").utf8).write(
        to: vault.root.appending(path: "N.md"), options: .atomic
    )

    #expect(session.index.note(at: "N.md")?.contentHash == NoteStore.hash(Data(written.utf8)))
}
