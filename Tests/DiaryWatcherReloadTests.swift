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

/// PG-360: `origin.file` and the path an external change names are both spelled by the
/// boundary now. With the vault opened through a symlink, the diary must still recognise
/// its own file and reload on an external change (a spelling mismatch would silently
/// ignore it).
@MainActor
@Test func reloadsACleanDayWhenTheVaultIsOpenedThroughASymlink() async throws {
    let vault = try TemporaryVault()
    let link = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .notDirectory)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: vault.root)
    defer { try? FileManager.default.removeItem(at: link) }

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(link)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    controller.didChangeExternally = { [weak diary] path in diary?.externalChange(at: path) }
    try #require(diary.isSettled)

    try vault.write(diaryExternalText("Scritto da un altro processo."), to: "Diario/20260811.md")
    await controller.reconcile(["Diario/20260811.md"])

    #expect(diary.prose.contains("Scritto da un altro processo."))
    controller.close()
}

/// PG-360 regression: a diary folder that leaves the vault (`../Diario`, which Impostazioni
/// accepts) must keep behaving as it did before the boundary spelling: the write is refused
/// by the session's door with its sentence on `problems`, and the text stays in memory. It
/// must not be read as «the file is no longer the one read», whose reload erases the day.
@MainActor
@Test func aDiaryFolderOutsideTheVaultKeepsTheTypedTextAndReportsTheRefusal() async throws {
    let vault = try TemporaryVault()
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.updateSettings { $0.diaryFolder = "../Diario" }
    let diary = DiaryController(vault: controller)
    diary.show(testDay)

    diary.prose += "Frase mia, da non perdere.\n"
    diary.flush()
    try await waitUntil { controller.problems.contains { $0.hasPrefix("diario del") } }

    #expect(diary.prose.contains("Frase mia, da non perdere."))
    #expect(!controller.problems.contains { $0.contains("non è più quello letto") })
    controller.close()
}

/// PG-360 regression: the diary's identity for a day's file is a plain join, never a
/// boundary resolution. With the vault opened through a symlink that stops resolving between
/// the read and the write (volume unmounted, target moved), a resolved spelling would change
/// under the pane, `performWrite` would read «a different file than the one read» and
/// `reload()` would erase the typed day. The write must fail through the session's door and
/// the text must stay.
@MainActor
@Test func aSymlinkThatStopsResolvingKeepsTheTypedText() async throws {
    let vault = try TemporaryVault()
    let link = FileManager.default.temporaryDirectory
        .appending(path: "pergamenum-link-\(UUID().uuidString)", directoryHint: .notDirectory)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: vault.root)
    defer { try? FileManager.default.removeItem(at: link) }

    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(link)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    try #require(diary.isSettled)

    diary.prose += "Frase mia, da non perdere.\n"
    try FileManager.default.removeItem(at: link)
    diary.flush()
    try await waitUntil { diary.isSettled }

    #expect(diary.prose.contains("Frase mia, da non perdere."))
    #expect(!controller.problems.contains { $0.contains("non è più quello letto") })
    controller.close()
}
