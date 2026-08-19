import Foundation
import Testing
@testable import Pergamenum

/// The diary's composer: the sheet that names a block, and what it writes when it is
/// confirmed. Split from `DiaryControllerTests` to keep both files inside the length
/// SwiftLint allows.
@MainActor
private func makeDiary(_ vault: borrowing DayVault) async throws -> (DiaryController, VaultController) {
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    return (diary, controller)
}

/// Takes the root rather than the vault: `DayVault` is noncopyable, and a `#expect`
/// or `#require` that borrows one does not compile.
private func diaryOnDisk(_ root: URL) -> String? {
    try? String(contentsOf: root.appending(path: "Diario/20260811.md"), encoding: .utf8)
}

@MainActor
@Test func composesAnEntryAtTheTimeThatWasClicked() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.compose(startMinutes: 15 * 60 + 20, durationMinutes: 120)
    let draft = try #require(diary.draft)
    #expect(!draft.isExisting)
    #expect(draft.entry.startMinutes == 15 * 60 + 20)
    #expect(draft.entry.durationMinutes == 120)

    diary.draft?.entry.title = "Cantiere"
    diary.commitDraft()

    #expect(diary.draft == nil)
    #expect(diary.entries.count == 1)
    #expect(diary.entries[0].title == "Cantiere")
    controller.close()
}

/// Editing changes the entry that was opened rather than adding a second one, even
/// when the time and the title both change.
@MainActor
@Test func editingAnEntryReplacesItRatherThanAddingAnother() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Riunione", startMinutes: 540, durationMinutes: 60)
    diary.edit(entry)
    diary.draft?.entry.title = "Riunione con il cliente"
    diary.draft?.entry.startMinutes = 11 * 60
    diary.commitDraft()

    #expect(diary.entries.count == 1)
    #expect(diary.entries[0].title == "Riunione con il cliente")
    #expect(diary.entries[0].startMinutes == 11 * 60)
    controller.close()
}

@MainActor
@Test func cancellingTheComposerWritesNothing() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.compose(startMinutes: 600)
    diary.draft?.entry.title = "Mai salvato"
    diary.cancelDraft()

    #expect(diary.draft == nil)
    #expect(diary.entries.isEmpty)
    #expect(diaryOnDisk(root) == nil)
    controller.close()
}

/// The diary and the daily note are different files: writing one must not touch the
/// other, whatever is in it.
@MainActor
@Test func leavesTheDailyNoteAlone() async throws {
    let vault = try DayVault()
    try vault.write(dayNoteWithProse, to: "Calendar/20260811.md")
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Riunione", startMinutes: 600, durationMinutes: 60)

    let daily = try String(
        contentsOf: root.appending(path: "Calendar/20260811.md"), encoding: .utf8
    )
    #expect(daily == dayNoteWithProse)
    controller.close()
}

/// The Oggi pane's blocks and the diary's entries live in different files and different
/// sections, and neither parser may claim the other's lines.
@MainActor
@Test func doesNotConfuseATimeBlockWithADiaryEntry() async throws {
    let vault = try DayVault()
    try vault.write("""
    ---
    date: 2026-08-11
    ---

    ## Timeline

    - 09:00-09:30 Blocco del piano [published]

    ## Diario

    - 10:00-11:00 Quello che è successo
    """, to: "Diario/20260811.md")
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    #expect(diary.entries.count == 1)
    #expect(diary.entries[0].title == "Quello che è successo")
    // The Timeline section is not the diary's to rewrite, so it stays in the prose.
    #expect(diary.prose.contains("- 09:00-09:30 Blocco del piano [published]"))
    controller.close()
}
