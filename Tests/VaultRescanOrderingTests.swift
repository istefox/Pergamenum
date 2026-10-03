import Foundation
import Testing
@testable import Pergamenum

// PG-374: `VaultSession.rescan` walks the disk off the main actor and then replaces the index
// wholesale. Every other index writer goes through `apply`'s per-path sequence guard (ADR-0043
// §D1); the replacement did not, so a mutation the index took while the walk ran was undone by
// it. `ContenitoreRouteTests`' pair-move test most likely failed this way once in a full run (the
// cause was never reproduced): the rename's fire-and-forget rescan overlapped the move, and the
// route then found no scheda at the new path.

private func note(_ body: String = "Corpo.") -> String {
    "---\ndate: 2026-10-02\ntags:\n  - type-note\n---\n\n\(body)\n"
}

/// Holds the session's next rescan past its walk, short of replacing the index: `reached` opens
/// once it is held there, and it stays held until the test opens `release`.
@MainActor
private func holdRescan(_ session: VaultSession) -> (reached: Gate, release: Gate) {
    let reached = Gate()
    let release = Gate()
    session.rescanGate = {
        reached.open()
        await release.wait()
    }
    return (reached, release)
}

/// The two mutations `moveFile` applies, manufactured so the walk cannot have seen them: the
/// moved note must stay and its old path must stay gone once the rescan lands.
@MainActor
@Test func aMoveTheIndexTakesDuringARescanIsNotUndoneByIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    let moved = try NoteStore(root: vault.root).record(from: Data(note().utf8), attributes: [:], at: "B.md")

    let (reached, release) = holdRescan(session)
    let scan = Task { await session.rescan() }
    // The rescan is held past its walk and short of replacing the index; the mutations land there.
    await reached.wait()
    #expect(session.apply([
        .init(path: "A.md", record: nil, sequence: 1),
        .init(path: "B.md", record: moved, sequence: 1)
    ]) == 2)
    release.open()
    await scan.value

    #expect(session.index.note(at: "B.md") == moved)
    #expect(session.index.note(at: "A.md") == nil)
}

/// The guard must stay narrow: a path the index did not touch during the walk is still replaced
/// by what the walk read (a file added and a file removed outside the app), while the path the
/// index did touch keeps its newer record.
@MainActor
@Test func aRescanStillAppliesWhatItReadForPathsTheIndexDidNotTouch() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    try vault.write(note("Gone."), to: "Gone.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    #expect(session.index.note(at: "Gone.md") != nil)
    try vault.remove("Gone.md")
    try vault.write(note("Added."), to: "Added.md")
    let moved = try NoteStore(root: vault.root).record(from: Data(note().utf8), attributes: [:], at: "B.md")

    let (reached, release) = holdRescan(session)
    let scan = Task { await session.rescan() }
    await reached.wait()
    #expect(session.apply([
        .init(path: "A.md", record: nil, sequence: 1),
        .init(path: "B.md", record: moved, sequence: 1)
    ]) == 2)
    release.open()
    await scan.value

    #expect(session.index.note(at: "Added.md") != nil)
    #expect(session.index.note(at: "Gone.md") == nil)
    #expect(session.index.note(at: "B.md") == moved)
    #expect(session.index.note(at: "A.md") == nil)
}

/// The guard keys on a sequence that CHANGED during the walk, not on one that merely exists: a
/// path the app wrote before the rescan began still takes the walk's read, so an edit made to it
/// outside the app is not rolled back to the stale record the index holds.
@MainActor
@Test func aRescanStillTakesTheWalksReadForAPathWrittenBeforeItStarted() async throws {
    let vault = try TemporaryVault()
    try vault.write(note(), to: "A.md")
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    // Written through `apply`, so `appliedSequence["A.md"]` is set before the rescan starts.
    let written = try NoteStore(root: vault.root).record(from: Data(note().utf8), attributes: [:], at: "A.md")
    #expect(session.apply([.init(path: "A.md", record: written, sequence: 1)]) == 1)
    // An edit outside the session: the index record is now stale against the disk.
    try vault.write(note("Vedi [[Altra]]."), to: "A.md")

    let (reached, release) = holdRescan(session)
    let scan = Task { await session.rescan() }
    await reached.wait()
    // Nothing touches the session while the rescan is held.
    release.open()
    await scan.value

    #expect(session.index.note(at: "A.md")?.linkTargets == ["Altra"])
}
