import Foundation
import Testing
@testable import Pergamenum

// ADR-0041 (vault layer consistency and security), plan
// docs/superpowers/plans/2026-09-12-vault-layer-consistency-and-security-cha.md, Task 8 -
// R-07 (ordering is a per-path sequence number, §D11), §D10 (the hash is recorded before
// the hop) and the two regressions §D9's own text calls out (ADR-0007 §D6's dry-run
// guardrail, ADR-0001 §D2.3's files-first-index-second invariant).
//
// These tests exercise the single async `VaultSession.write(_:to:)` door, which awaits
// `VaultDisk.write`, and the test-only `apply(_:at:)` seam. Two sequential awaited
// writes observe program order; they do not force inverted actor completions. The
// inversion half of R-07 is therefore manufactured directly through `apply(_:at:)`,
// asserting on the rejected outcome as well as the final index state.

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
    #expect(session.selfWrittenHashes["N.md"]?.last?.hash == NoteStore.hash(Data(second.utf8)))
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
    #expect(session.selfWrittenHashes["N.md"]?.last?.hash == NoteStore.hash(onDisk))
}

// ADR-0043 §D2, Tasks 1-3 (R-03): `VaultSession.write(_:to:)` now has a single
// async throws signature and awaits `disk.write`. The assertion above checks the
// recorded hash after that actor call returns; it does not observe the suspension
// itself or prove that the hash was visible before the actor completed.
// A deterministic interleaving check remains absent here. It needs a test-controlled
// gate at the actor boundary, resumed explicitly by the test, rather than a sleep or
// a race against `Task.yield()`. This mechanical conversion preserves the existing
// assertions and does not claim that they cover that stronger timing guarantee.

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

// MARK: - ADR-0043 Tasks 4-6: contract-first regressions
// The pasted batch brief is the behavioral specification. These tests deliberately use
// its final APIs, with no test-side production stubs or compatibility forwarders.

@MainActor
@Test func theOlderMutationFromADifferentWriterIsDropped() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let record = try NoteStore(root: vault.root).record(
        from: Data(note("Newer write.").utf8), attributes: [:], at: "N.md"
    )
    let newer = VaultDisk.IndexMutation(path: "N.md", record: record, sequence: 2)
    let older = VaultDisk.IndexMutation(path: "N.md", record: nil, sequence: 1)

    // R-01, R-02, R-11: an older trash must not erase a newer writer's record.
    #expect(session.apply([newer]) == 1)
    #expect(session.apply([older]) == 0)
    #expect(session.index.note(at: "N.md") == record)
}

@MainActor
@Test func mutationGuardRejectsZeroAndDuplicatesAndKeepsPathsIndependent() async throws {
    let vault = try TemporaryVault()
    let session = await openSession(vault)
    let store = NoteStore(root: vault.root)
    let first = try store.record(from: Data(note().utf8), attributes: [:], at: "A.md")
    let second = try store.record(from: Data(note().utf8), attributes: [:], at: "B.md")

    // R-02: strictly greater, with zero as the initial counter, independently per path.
    #expect(session.apply([]) == 0)
    #expect(session.apply([.init(path: "A.md", record: first, sequence: 0)]) == 0)
    #expect(session.index.note(at: "A.md") == nil)
    #expect(session.apply([
        .init(path: "A.md", record: first, sequence: 2),
        .init(path: "B.md", record: second, sequence: 1)
    ]) == 2)
    #expect(session.apply([.init(path: "A.md", record: nil, sequence: 2)]) == 0)
    #expect(session.index.note(at: "A.md") == first)
    #expect(session.index.note(at: "B.md") == second)
    #expect(session.apply([.init(path: "A.md", record: nil, sequence: 3)]) == 1)
    #expect(session.apply([.init(path: "A.md", record: first, sequence: 2)]) == 0)
    #expect(session.index.note(at: "A.md") == nil)
}

private func orderingDisk(_ vault: borrowing TemporaryVault) -> VaultDisk {
    VaultDisk(
        store: NoteStore(root: vault.root),
        history: NoteHistory(directory: vault.stateBase.appending(path: "history"))
    )
}

@Test func moveAndReconcileShareEachEndpointsWriteClock() async throws {
    let vault = try TemporaryVault()
    let disk = orderingDisk(vault)
    let first = try await disk.writeFile(note("First."), to: "Old.md")
    let second = try await disk.writeFile(note("Second."), to: "Old.md")
    let absentDestination = await disk.reconcile("New.md", selfWritten: [])
    let mutations = try await disk.moveFile(from: "Old.md", to: "New.md")

    // R-01, R-04: each move endpoint advances its own clock, not a caller's clock.
    #expect(second.sequence == first.sequence + 1)
    #expect(mutations.count == 2)
    let removal = try #require(mutations.first { $0.path == "Old.md" })
    let insertion = try #require(mutations.first { $0.path == "New.md" })
    #expect(removal.record == nil)
    #expect(removal.sequence == second.sequence + 1)
    #expect(insertion.sequence == absentDestination.mutation.sequence + 1)
    #expect(insertion.record?.relativePath == "New.md")
    #expect(insertion.record?.contentHash == NoteStore.hash(Data(note("Second.").utf8)))
    #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: "Old.md").path))
    #expect(try String(contentsOf: vault.root.appending(path: "New.md"), encoding: .utf8) == note("Second."))

    let recreated = try await disk.writeFile(note("Recreated."), to: "Old.md")
    let reconciled = await disk.reconcile("New.md", selfWritten: [])
    #expect(recreated.sequence == removal.sequence + 1)
    #expect(reconciled.mutation.sequence == insertion.sequence + 1)
    #expect(reconciled.mutation.record == insertion.record)
}

@Test func nonNoteWritesAndTrashReturnStampedMutations() async throws {
    let vault = try TemporaryVault()
    let disk = orderingDisk(vault)
    let text = "{\"nodes\":[],\"edges\":[]}"
    let written = try await disk.writeFile(text, to: "Board.canvas")
    #expect(written.path == "Board.canvas")
    #expect(written.sequence > 0)
    #expect(try String(contentsOf: vault.root.appending(path: "Board.canvas"), encoding: .utf8) == text)

    // R-01: trash is another writer on the same path, including non-note files.
    let removed = try await disk.trashFile(at: "Board.canvas")
    #expect(removed.path == "Board.canvas")
    #expect(removed.record == nil)
    #expect(removed.sequence == written.sequence + 1)
    #expect(!FileManager.default.fileExists(atPath: vault.root.appending(path: "Board.canvas").path))
}

@Test func actorFileOperationsRejectPathsOutsideTheBoundary() async throws {
    let vault = try TemporaryVault()
    let disk = orderingDisk(vault)
    try vault.write(note(), to: "Safe.md")
    // Task 4.6: exact boundary error, so an unrelated stub failure cannot pass.
    await #expect(throws: VaultBoundary.Violation.self) {
        try await disk.writeFile("escape", to: "../escape.md")
    }
    await #expect(throws: VaultBoundary.Violation.self) {
        try await disk.moveFile(from: "Safe.md", to: "../escape.md")
    }
    await #expect(throws: VaultBoundary.Violation.self) {
        try await disk.moveFile(from: "../escape.md", to: "Safe.md")
    }
    await #expect(throws: VaultBoundary.Violation.self) {
        try await disk.trashFile(at: "../escape.md")
    }
    #expect(try String(contentsOf: vault.root.appending(path: "Safe.md"), encoding: .utf8) == note())
}

@MainActor
@Test func missingPathReconciliationSupersedesAnEarlierWrite() async throws {
    let vault = try TemporaryVault()
    let disk = orderingDisk(vault)
    let session = await openSession(vault)
    let written = try await disk.writeFile(note(), to: "N.md")
    // R-04: moving the file away simulates an external deletion without any timing.
    try FileManager.default.moveItem(
        at: vault.root.appending(path: "N.md"), to: vault.root.appending(path: "Moved.md")
    )
    let missing = await disk.reconcile("N.md", selfWritten: [])
    #expect(missing.mutation.path == "N.md")
    #expect(missing.mutation.record == nil)
    #expect(missing.mutation.sequence == written.sequence + 1)
    #expect(missing.change == VaultSession.ExternalChange(path: "N.md", content: .deleted))
    #expect(missing.matchedSequence == nil)
    #expect(session.apply([missing.mutation]) == 1)
    #expect(session.apply([written]) == 0)
    #expect(session.index.note(at: "N.md") == nil)
}

@MainActor
@Test func sessionReconciliationReadsExternalBytesAndHandlesMissingPaths() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Original."), to: "N.md")
    let session = await openSession(vault)
    try vault.write(note("External."), to: "N.md")
    // R-04: awaiting the session door returns parsed changes and updates the index.
    let changes = await session.reconcile(["N.md"])
    #expect(changes.map(\.path) == ["N.md"])
    #expect(changes.first?.content == .text(note("External.")))
    #expect(session.index.note(at: "N.md")?.contentHash == NoteStore.hash(Data(note("External.").utf8)))
    try FileManager.default.moveItem(
        at: vault.root.appending(path: "N.md"), to: vault.root.appending(path: "Moved.md")
    )
    let missing = await session.reconcile(["N.md"])
    #expect(missing == [VaultSession.ExternalChange(path: "N.md", content: .deleted)])
    #expect(session.index.note(at: "N.md") == nil)
}

@MainActor
@Test func readForEditingLeavesTheIndexedRecordUntouched() async throws {
    let vault = try TemporaryVault()
    try vault.write(note("Indexed."), to: "N.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile(), pinnedTags: .volatile())
    await controller.open(vault.root)
    let session = try #require(controller.session)
    let recorded = try #require(session.index.note(at: "N.md"))
    // R-05: no suspension between the external write, editing read and assertion.
    // This checks readForEditing's side effects without racing watcher delivery.
    try vault.write(note("External."), to: "N.md")
    let opened = try #require(controller.readForEditing("N.md"))
    #expect(opened.text == note("External."))
    #expect(session.index.note(at: "N.md") == recorded)
}

@MainActor
@Test func twoOverlappingWritesRecordDifferentJournalBefores() async throws {
    let vault = try TemporaryVault()
    let original = note("Original.")
    let firstText = note("First write.")
    let secondText = note("Second write.")
    try vault.write(original, to: "N.md")
    let session = await openSession(vault)
    session.journal = session.journalOnDisk
    let disk = orderingDisk(vault)
    let timestamp = Date(timeIntervalSince1970: 1_789_344_000)
    // R-06, R-12: both descriptors exist BEFORE either actor write lands.
    let descriptorA = VaultDisk.JournalDescriptor(
        entryID: "batch2-write-a", timestamp: timestamp, command: "test", operation: nil
    )
    let descriptorB = VaultDisk.JournalDescriptor(
        entryID: "batch2-write-b", timestamp: timestamp.addingTimeInterval(1), command: "test", operation: nil
    )
    _ = try await disk.write(
        firstText, to: "N.md", precomputedHash: NoteStore.hash(Data(firstText.utf8)),
        journalDescriptor: descriptorA, journal: session.journal, recordsHistory: false
    )
    _ = try await disk.write(
        secondText, to: "N.md", precomputedHash: NoteStore.hash(Data(secondText.utf8)),
        journalDescriptor: descriptorB, journal: session.journal, recordsHistory: false
    )
    let entries = session.journalOnDisk.entries()
    #expect(entries.count == 2)
    let entryA = try #require(entries.first { $0.id == descriptorA.entryID })
    let entryB = try #require(entries.first { $0.id == descriptorB.entryID })
    #expect(entryA.hashBefore == NoteStore.hash(Data(original.utf8)))
    #expect(entryA.hashAfter == NoteStore.hash(Data(firstText.utf8)))
    #expect(entryB.hashAfter == NoteStore.hash(Data(secondText.utf8)))
    #expect(entryA.hashBefore != entryB.hashBefore)
    #expect(entryB.hashBefore == entryA.hashAfter)
    #expect(entryA.textBefore == original)
    #expect(entryB.textBefore == firstText)
    #expect(entryA.textBefore != entryB.textBefore)

    VaultAPI.arm(session, command: "undo_write", dryRun: false)
    _ = try await VaultAPI.undo(session, id: entryB.id)
    #expect(try String(contentsOf: vault.root.appending(path: "N.md"), encoding: .utf8) == firstText)
}

@Test func journalCreationHasNoBeforeImage() async throws {
    let vault = try TemporaryVault()
    let disk = orderingDisk(vault)
    let journal = WriteJournal(directory: vault.stateBase.appending(path: "journal"))
    let text = note("Created.")
    let descriptor = VaultDisk.JournalDescriptor(
        entryID: "batch2-creation", timestamp: Date(timeIntervalSince1970: 1_789_344_000),
        command: "test", operation: nil
    )
    // R-06: a missing file is a creation, not an empty-string before-image.
    _ = try await disk.write(
        text, to: "New.md", precomputedHash: NoteStore.hash(Data(text.utf8)),
        journalDescriptor: descriptor, journal: journal, recordsHistory: false
    )
    #expect(journal.entries().count == 1)
    let entry = try #require(journal.entries().first)
    #expect(entry.hashBefore == nil)
    #expect(entry.textBefore == nil)
    #expect(entry.hashAfter == NoteStore.hash(Data(text.utf8)))
}
