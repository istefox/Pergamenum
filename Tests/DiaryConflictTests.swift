import Foundation
import Testing
@testable import Pergamenum

/// ADR-0057 §D6: the two verbs that resolve a diary conflict - «Tieni la mia versione»
/// (`keepLocalDiary()`) and «Ricarica da disco» (`reloadDiaryFromDisk()`).
///
/// None of these can pass today: nothing yet drives `saveState` into `.conflicted`
/// (that is the coder pass's job, Task 3's body), so every test below either fails to
/// reach the conflict it needs and records that fact, or fails the assertion that
/// follows it. Every one of them is meant to go green once the coder pass lands.

private func diaryConflictText(_ body: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n\(body)\n"
}

/// Types a sentence, holds the write at `.willWrite`, lets another writer change the
/// file, then releases - the shared setup every test below needs to reach a conflict.
@MainActor
private func makeConflictedDiary(
    _ vault: borrowing TemporaryVault, seedFile: String? = "Testo iniziale."
) async throws -> (diary: DiaryController, controller: VaultController, didWriteCount: () -> Int) {
    if let seedFile {
        try vault.write(diaryConflictText(seedFile), to: "Diario/20260811.md")
    }
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
    try vault.write(diaryConflictText("Scritto da un altro processo."), to: "Diario/20260811.md")
    gate.open()
    try await waitUntil { didWriteCount == 1 }

    return (diary, controller, { didWriteCount })
}

@MainActor
@Test func keepLocalDiaryWritesThePanesTextAndAdvancesOrigin() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller, didWriteCount) = try await makeConflictedDiary(vault)

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted before exercising keepLocalDiary()")
        return
    }
    let originBefore = diary.origin

    diary.keepLocalDiary()
    try await waitUntil { didWriteCount() == 2 }

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Frase mia."))
    #expect(diary.saveState == .saved)
    #expect(diary.origin != originBefore)
    controller.close()
}

@MainActor
@Test func reloadDiaryFromDiskReplacesProseAndEntriesAndSettles() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller, _) = try await makeConflictedDiary(vault)

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted before exercising reloadDiaryFromDisk()")
        return
    }

    diary.reloadDiaryFromDisk()
    try await waitUntil { diary.isSettled }

    #expect(diary.prose.contains("Scritto da un altro processo."))
    #expect(!diary.prose.contains("Frase mia."))
    #expect(diary.saveState == .saved)

    // The next edit writes over the reloaded file without conflict.
    diary.prose += "Nuova frase dopo il reload.\n"
    diary.flush()
    try await waitUntil { diaryOnDisk(root)?.contains("Nuova frase dopo il reload.") == true }
    guard case .conflicted = diary.saveState else {
        controller.close()
        return
    }
    Issue.record("the edit after a reload must not conflict")
    controller.close()
}

/// One attempt per click, never a loop (ADR-0057 §D6): a third writer landing between
/// `keepLocalDiary()`'s own read and its write is refused again, and produces exactly one
/// `.didWrite` for that attempt.
@MainActor
@Test func keepLocalDiaryReentersConflictWhenAThirdWriterLands() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller, _) = try await makeConflictedDiary(vault)

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted before exercising keepLocalDiary()")
        return
    }

    var thirdWriterLanded = false
    var keepDidWriteCount = 0
    diary.testOnlyWriteHook = { phase in
        switch phase {
        case .willWrite:
            if !thirdWriterLanded {
                thirdWriterLanded = true
                try? vault.write(diaryConflictText("Terzo scrittore."), to: "Diario/20260811.md")
            }
        case .didWrite:
            keepDidWriteCount += 1
        }
    }

    diary.keepLocalDiary()
    try await waitUntil { keepDidWriteCount == 1 }

    guard case .conflicted = diary.saveState else {
        Issue.record("expected to re-enter .conflicted after a third writer landed during keep")
        return
    }
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Terzo scrittore."))
    #expect(keepDidWriteCount == 1)
    controller.close()
}

@MainActor
@Test func conflictOnAnExternallyDeletedFileReloadsEmptyAndDisk() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    try vault.write(diaryConflictText("Testo iniziale."), to: "Diario/20260811.md")
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
    try FileManager.default.removeItem(at: root.appending(path: "Diario/20260811.md"))
    gate.open()
    try await waitUntil { didWriteCount == 1 }

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted after the file was deleted externally")
        return
    }

    diary.reloadDiaryFromDisk()
    try await waitUntil { diary.isSettled }

    #expect(diary.prose == controller.emptyDiaryNote(for: testDay))
    #expect(diary.origin.disk == .absent)
    controller.close()
}

@MainActor
@Test func keepLocalDiaryWritesBackThroughAnAbsentOrigin() async throws {
    let vault = try TemporaryVault()
    let root = vault.root
    let (diary, controller, didWriteCount) = try await makeConflictedDiary(vault, seedFile: nil)

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted after another writer created the file")
        return
    }

    diary.keepLocalDiary()
    try await waitUntil { didWriteCount() == 2 }

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Frase mia."))
    controller.close()
}

@MainActor
@Test func afterEitherVerbShowWorksAgain() async throws {
    let vault = try TemporaryVault()
    let (diary, controller, didWriteCount) = try await makeConflictedDiary(vault)

    guard case .conflicted = diary.saveState else {
        Issue.record("expected .conflicted before exercising keepLocalDiary()")
        return
    }

    diary.keepLocalDiary()
    try await waitUntil { didWriteCount() == 2 }

    guard diary.saveState == .saved else {
        Issue.record("expected .saved after keepLocalDiary()")
        return
    }
    diary.move(by: 1)
    #expect(diary.day == testDay.adding(days: 1))
    controller.close()
}
