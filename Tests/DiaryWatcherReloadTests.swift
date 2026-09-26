import Foundation
import Testing
@testable import Pergamenum

/// ADR-0057 §D8, PG-227/#495: a clean Diario pane picks up a change another process made
/// to the day's file, fed by `VaultController.didChangeExternally` into
/// `DiaryController.externalChange(at:)`. These drive `VaultController.reconcile(_:)`
/// directly, the same door the watcher calls, rather than the watcher itself - the FSEvents
/// plumbing has its own coverage and is not what this chain touches.

private func diaryExternalText(_ body: String) -> String {
    "---\ndate: 2026-08-11\ntags:\n  - type-note\n---\n\n\(body)\n"
}

@MainActor
@Test func reloadsACleanDayOnAnExternalChange() async throws {
    let vault = try TemporaryVault()
    let (diary, controller) = try await makeDiary(vault)
    controller.didChangeExternally = { [weak diary] path in diary?.externalChange(at: path) }

    #expect(diary.isSettled)
    try vault.write(diaryExternalText("Scritto da un altro processo."), to: "Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])

    #expect(diary.prose.contains("Scritto da un altro processo."))
    controller.close()
}

/// The precondition machinery, not this reload, owns a dirty day: an external change
/// while there is unsaved local text must not be adopted silently.
@MainActor
@Test func leavesAPendingDayUntouchedOnAnExternalChange() async throws {
    let vault = try TemporaryVault()
    let (diary, controller) = try await makeDiary(vault)
    controller.didChangeExternally = { [weak diary] path in diary?.externalChange(at: path) }

    diary.prose += "Frase mia, non ancora salvata.\n"
    #expect(!diary.isSettled)

    try vault.write(diaryExternalText("Scritto da un altro processo."), to: "Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])

    #expect(diary.prose.contains("Frase mia, non ancora salvata."))
    #expect(!diary.prose.contains("Scritto da un altro processo."))
    controller.close()
}

/// ADR-0064, plan `docs/plans/pg-234-external-deletion.md` Task 2, test 19 (R-01). Red on
/// today's code: `VaultDisk.reconcile`'s missing-path branch reports `change: nil`, so
/// `didChangeExternally` never fires for a deletion and the pane keeps showing the stale text.
@MainActor
@Test func reloadsACleanDayToEmptyOnAnExternalDeletion() async throws {
    let vault = try TemporaryVault()
    let (diary, controller) = try await makeDiary(vault)
    controller.didChangeExternally = { [weak diary] path in diary?.externalChange(at: path) }
    try vault.write(diaryExternalText("Scritto da un altro processo."), to: "Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])
    try #require(diary.prose.contains("Scritto da un altro processo."))

    try vault.remove("Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])

    #expect(diary.prose == controller.emptyDiaryNote(for: testDay))
    #expect(diary.isSettled)
    controller.close()
}

/// Test 20 (§D2, no R). Green today, and a guard: `DiaryController.externalChange(at:)` already
/// refuses to touch a pane with unsettled local text, regardless of what the change turns out to
/// be, so a deletion arriving while a day is pending is a no-op both before and after the fix.
@MainActor
@Test func leavesAPendingDayUntouchedOnAnExternalDeletion() async throws {
    let vault = try TemporaryVault()
    let (diary, controller) = try await makeDiary(vault)
    controller.didChangeExternally = { [weak diary] path in diary?.externalChange(at: path) }
    try vault.write(diaryExternalText("Contenuto iniziale."), to: "Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])
    try #require(diary.prose.contains("Contenuto iniziale."))

    diary.prose += "Frase mia, non ancora salvata.\n"
    #expect(!diary.isSettled)

    try vault.remove("Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])

    #expect(diary.prose.contains("Frase mia, non ancora salvata."))
    #expect(diary.prose.contains("Contenuto iniziale."))
    controller.close()
}
