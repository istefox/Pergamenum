import Foundation
import Testing
@testable import Pergamenum

/// ADR-0057 §D1/§D2/§D3/§D7: the diary's read carries the disk state it came from, the
/// controller records its origin, and no diary write remains unguarded - the guard proves
/// it against another writer, including a creation, and against a vault switch.
///
/// The session-level tests need no controller and no gate: they pin the door itself. The
/// controller-level tests reuse `DiaryWriteDoorTests`' `Gate` shape to force the race
/// deterministically (ADR-0057 §D9).

private func diaryGuardText(_ body: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
private func diaryGuardSession(_ vault: borrowing TemporaryVault) async -> VaultSession {
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()
    return session
}

// MARK: - Session level

@MainActor
@Test func readDiaryReportsAbsentForAMissingDayAndPresentForAWrittenOne() async throws {
    let vault = try TemporaryVault()
    let session = await diaryGuardSession(vault)
    let day = testDay

    // No file yet: `preferring:` supplies the buffer's text (the controller always has
    // one, even for an empty day), so the tuple is non-nil and its `disk` reports the
    // file's own absence, not the buffer's presence.
    #expect(session.readDiary(on: day, preferring: session.emptyDiaryNote(for: day))?.disk == .absent)

    let onDisk = diaryGuardText("Scritta.")
    try vault.write(onDisk, to: "Diario/20260811.md")
    await session.rescan()

    let read = try #require(session.readDiary(on: day))
    #expect(read.disk == .present(hash: NoteStore.hash(Data(onDisk.utf8))))

    // `preferring:` supplies different text for the buffer; `disk` still describes what
    // is on disk, not the buffer (ADR-0057 §D1).
    let preferred = try #require(session.readDiary(on: day, preferring: "Bozza non salvata."))
    #expect(preferred.prose.isEmpty == false)
    #expect(preferred.disk == .present(hash: NoteStore.hash(Data(onDisk.utf8))))
}

/// Red today: the placeholder `writeDiary` ignores `over:` and always writes.
@MainActor
@Test func writeDiaryOverAStaleHashRefusesAndLeavesTheFileUntouched() async throws {
    let vault = try TemporaryVault()
    let session = await diaryGuardSession(vault)
    let day = testDay
    let original = diaryGuardText("Originale.")
    try vault.write(original, to: "Diario/20260811.md")
    await session.rescan()
    let problemsBefore = session.problems.count

    let outcome = await session.writeDiary(
        prose: diaryGuardText("Sovrascritta."), entries: [], on: day, over: .present(hash: "stale-hash")
    )

    guard case .stale = outcome else {
        Issue.record("expected .stale, got \(outcome)")
        return
    }
    #expect(try String(contentsOf: vault.root.appending(path: "Diario/20260811.md"), encoding: .utf8) == original)
    #expect(session.problems.count == problemsBefore)
}

/// Red today, the creation-case sibling: `over: .absent` over a file that exists must
/// refuse too (ADR-0057 §D3 - the shared-folder setup's other in-process writers can
/// create the file between a read and a write).
@MainActor
@Test func writeDiaryOverAbsentOnAnExistingFileRefuses() async throws {
    let vault = try TemporaryVault()
    let session = await diaryGuardSession(vault)
    let day = testDay
    let original = diaryGuardText("Creata da un altro scrittore.")
    try vault.write(original, to: "Diario/20260811.md")
    await session.rescan()

    let outcome = await session.writeDiary(
        prose: diaryGuardText("La mia."), entries: [], on: day, over: .absent
    )

    guard case .stale = outcome else {
        Issue.record("expected .stale, got \(outcome)")
        return
    }
    #expect(try String(contentsOf: vault.root.appending(path: "Diario/20260811.md"), encoding: .utf8) == original)
}

/// Green today: a missing day still writes over `.absent`.
@MainActor
@Test func writeDiaryOverAbsentOnAMissingFileWrites() async throws {
    let vault = try TemporaryVault()
    let session = await diaryGuardSession(vault)
    let day = testDay

    let outcome = await session.writeDiary(
        prose: diaryGuardText("Nuova."), entries: [], on: day, over: .absent
    )

    guard case .written = outcome else {
        Issue.record("expected .written, got \(outcome)")
        return
    }
}

// MARK: - Controller level

/// Red today: with no precondition enforced, this write clobbers the other writer's
/// change instead of refusing.
@MainActor
@Test func anotherWritersChangeDuringAHeldWriteRefusesAndConflicts() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(diaryGuardText("Testo iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)

    let gate = Gate()
    var heldOnce = false
    var didWriteCount = 0
    diary.testOnlyWriteHook = { phase in
        switch phase {
        case .willWrite:
            if !heldOnce {
                heldOnce = true
                await gate.wait()
            }
        case .didWrite:
            didWriteCount += 1
        }
    }

    diary.prose += "Frase mia.\n"
    diary.flush()
    try await waitUntil { heldOnce }

    // Another writer changes the file while this write is held (ADR-0057 §D9).
    let otherWriterText = diaryGuardText("Scritto da un altro processo.")
    try vault.write(otherWriterText, to: "Diario/20260811.md")

    gate.open()
    try await waitUntil { didWriteCount == 1 }

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk == otherWriterText)
    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted, got \(diary.saveState)")
        return
    }
    #expect(controller.problems.count == 1)
    controller.close()
}

/// Red today, the creation variant: a day with no file yet, another writer creates it
/// while this controller's own first write is held.
@MainActor
@Test func anotherWritersCreationDuringAHeldWriteRefusesAndConflicts() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let gate = Gate()
    var heldOnce = false
    var didWriteCount = 0
    diary.testOnlyWriteHook = { phase in
        switch phase {
        case .willWrite:
            if !heldOnce {
                heldOnce = true
                await gate.wait()
            }
        case .didWrite:
            didWriteCount += 1
        }
    }

    diary.prose += "Prima frase del giorno.\n"
    diary.flush()
    try await waitUntil { heldOnce }

    let createdByOther = diaryGuardText("Creato da un altro scrittore.")
    try vault.write(createdByOther, to: "Diario/20260811.md")

    gate.open()
    try await waitUntil { didWriteCount == 1 }

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk == createdByOther)
    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted, got \(diary.saveState)")
        return
    }
    controller.close()
}

/// Green today and required to stay green: the guard that goes red the moment a
/// precondition lands without Task 2's serialization first (ADR-0057, plan Task 2/3
/// ordering note).
@MainActor
@Test func consecutiveOwnSavesOverAnExistingFileNeverConflict() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(diaryGuardText("Iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Riunione", startMinutes: 9 * 60, durationMinutes: 60)
    diary.move(entry, toStart: 14 * 60 + 30)
    diary.resize(diary.entries[0], toDuration: 180)

    try await waitUntil { diaryOnDisk(root)?.contains("- 14:30-17:30 Riunione") == true }
    guard case .conflicted = diary.saveState else {
        controller.close()
        return
    }
    Issue.record("the app's own consecutive saves must never conflict with themselves")
    controller.close()
}

/// Red today: there is no conflicted state to enter yet, so none of these three refusals
/// hold - `flush()` still writes, `show(_:)` still switches, `load()` still re-reads.
@MainActor
@Test func whileConflictedNothingWritesNavigatesOrReloads() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(diaryGuardText("Testo iniziale."), to: "Diario/20260811.md")
    let (diary, controller) = try await makeDiary(vault)

    let gate = Gate()
    var heldOnce = false
    var didWriteCount = 0
    diary.testOnlyWriteHook = { phase in
        switch phase {
        case .willWrite:
            if !heldOnce {
                heldOnce = true
                await gate.wait()
            }
        case .didWrite:
            didWriteCount += 1
        }
    }

    diary.prose += "Frase mia.\n"
    diary.flush()
    try await waitUntil { heldOnce }
    try vault.write(diaryGuardText("Scritto da un altro processo."), to: "Diario/20260811.md")
    gate.open()
    try await waitUntil { didWriteCount == 1 }

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted before exercising the three refusals")
        return
    }

    let onDiskBeforeFlush = diaryOnDisk(root)
    diary.prose += "Altra frase mentre in conflitto.\n"
    diary.flush()
    #expect(didWriteCount == 1)
    #expect(diaryOnDisk(root) == onDiskBeforeFlush)

    diary.show(testDay.adding(days: 1))
    #expect(diary.day == testDay)

    diary.load()
    #expect(diary.prose.contains("Altra frase mentre in conflitto."))
    controller.close()
}

/// Red today: a write whose target vault differs from the origin's is not yet refused.
@MainActor
@Test func aVaultSwitchWithUnsavedTextDoesNotWriteIntoTheOtherVault() async throws {
    let vaultA = try TemporaryVault()
    let vaultB = try TemporaryVault()
    let (diary, controller) = try await makeDiary(vaultA)

    diary.prose += "Testo scritto in A.\n"

    await controller.open(vaultB.root)
    diary.load()

    try await waitUntil { diary.isSettled }
    #expect(diaryOnDisk(vaultB.root) == nil)
    #expect(controller.problems.count == 1)
    #expect(diary.day == testDay)
    controller.close()
}
