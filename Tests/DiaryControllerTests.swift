import Foundation
import Testing
@testable import Pergamenum

/// The diary's controller against a real vault on disk: what it writes, when it writes
/// it, and the days it leaves alone.
@MainActor
private func makeDiary(_ vault: borrowing DayVault) async throws -> (DiaryController, VaultController) {
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)
    let diary = DiaryController(vault: controller)
    diary.show(testDay)
    return (diary, controller)
}

/// Takes the root rather than the vault: `DayVault` is noncopyable, and a `#expect`
/// or `#require` that borrows one does not compile - the macro's autoclosure wants a
/// copy.
private func diaryOnDisk(_ root: URL) -> String? {
    try? String(contentsOf: root.appending(path: "Diario/20260811.md"), encoding: .utf8)
}

@MainActor
@Test func writesANewEntryIntoTheDayFile() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Sopralluogo pressa 4", startMinutes: 9 * 60, durationMinutes: 150)

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("## Diario"))
    #expect(onDisk.contains("- 09:00-11:30 Sopralluogo pressa 4"))
    // The frontmatter of any other note the app makes (SPEC §4.3).
    #expect(onDisk.contains("date: 2026-08-11"))
    controller.close()
}

/// Walking through a week must not leave a week of empty files behind.
@MainActor
@Test func writesNothingForADayNothingWasWrittenOn() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.move(by: 1)
    diary.move(by: -1)
    diary.flush()

    #expect(diaryOnDisk(root) == nil)
    let diaryFolder = root.appending(path: "Diario").path(percentEncoded: false)
    #expect(!FileManager.default.fileExists(atPath: diaryFolder))
    controller.close()
}

@MainActor
@Test func writesTheProseOnceTypingStops() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Giornata in reparto.\n"
    diary.flush()

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Giornata in reparto."))
    controller.close()
}

@MainActor
@Test func readsBackWhatItWrote() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Prosa.\n"
    diary.add(title: "Riunione", note: "Presenti Marco e Anna.", startMinutes: 600, durationMinutes: 60, colour: .verde)
    diary.flush()

    diary.move(by: 1)
    diary.move(by: -1)

    #expect(diary.entries.count == 1)
    #expect(diary.entries[0].title == "Riunione")
    #expect(diary.entries[0].note == "Presenti Marco e Anna.")
    #expect(diary.entries[0].colour == .verde)
    #expect(diary.prose.contains("Prosa."))
    controller.close()
}

/// Changing day with a sentence half typed writes it first. This is the path that
/// loses work if it is wrong, so it is the one worth testing.
@MainActor
@Test func writesTheDayBeforeLeavingIt() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Ultima frase.\n"
    diary.move(by: 1)

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Ultima frase."))
    // And the new day starts empty rather than showing the previous one's text.
    #expect(!diary.prose.contains("Ultima frase."))
    controller.close()
}

/// Rereading a day writes what was owed first. The pane reloads whenever it comes back
/// on screen, and a reload that discarded the pending write lost the last sentence.
@MainActor
@Test func writesWhatIsOwedBeforeRereadingTheSameDay() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Frase in sospeso.\n"
    diary.load()

    #expect(diary.prose.contains("Frase in sospeso."))
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Frase in sospeso."))
    controller.close()
}

@MainActor
@Test func snapsEveryEntryToTheTenMinuteGrid() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Chiamata", startMinutes: 9 * 60 + 7, durationMinutes: 23)

    #expect(entry.startMinutes == 9 * 60 + 10)
    #expect(entry.durationMinutes == 20)
    controller.close()
}

@MainActor
@Test func neverMakesAnEntryShorterThanTenMinutes() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Un attimo", startMinutes: 600, durationMinutes: 1)
    diary.resize(entry, toDuration: 0)

    #expect(diary.entries[0].durationMinutes == DiaryGrid.minimumDuration)
    controller.close()
}

@MainActor
@Test func movesAndResizesAnEntryAndWritesBothToTheFile() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Riunione", startMinutes: 9 * 60, durationMinutes: 60)
    diary.move(entry, toStart: 14 * 60 + 30)
    diary.resize(diary.entries[0], toDuration: 180)

    #expect(diary.entries[0].startMinutes == 14 * 60 + 30)
    #expect(diary.entries[0].durationMinutes == 180)
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("- 14:30-17:30 Riunione"))
    controller.close()
}

/// A three-hour block is the case the diary was asked for, and it must survive the
/// round trip through the file unchanged.
@MainActor
@Test func keepsABlockOfThreeHours() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Trasferta", startMinutes: 14 * 60, durationMinutes: 180)
    diary.move(by: 1)
    diary.move(by: -1)

    #expect(diary.entries[0].durationMinutes == 180)
    #expect(diary.entries[0].timeText == "14:00-17:00")
    controller.close()
}

@MainActor
@Test func keepsAnEntryInsideTheDayItBelongsTo() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Notte", startMinutes: 23 * 60 + 30, durationMinutes: 120)
    #expect(entry.endMinutes <= DiaryGrid.dayMinutes)

    diary.move(entry, toStart: -60)
    #expect(diary.entries[0].startMinutes == 0)
    controller.close()
}

@MainActor
@Test func deletingTheLastEntryLeavesTheProseAlone() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.prose += "Prosa che resta.\n"
    let entry = diary.add(title: "Riunione", startMinutes: 600, durationMinutes: 60)
    diary.remove(entry)

    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("Prosa che resta."))
    #expect(!onDisk.contains("## Diario"))
    #expect(diary.entries.isEmpty)
    controller.close()
}

/// The diary allows what the Oggi pane's blocks refuse: a day is written as it was
/// lived, and what was lived overlaps.
@MainActor
@Test func allowsTwoEntriesAtTheSameHour() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Riunione", startMinutes: 540, durationMinutes: 120)
    diary.add(title: "Telefonata", startMinutes: 570, durationMinutes: 30)

    #expect(diary.entries.count == 2)
    #expect(diary.placements.allSatisfy { $0.columns == 2 })
    controller.close()
}

/// A day written by hand in Obsidian is read exactly as the app's own would be.
@MainActor
@Test func readsADayWrittenByHand() async throws {
    let vault = try DayVault()
    try vault.write("""
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    Scritto a mano.

    ## Diario

    - 07:20-08:00 Rassegna [colore:giallo]
      Due articoli sul distretto.
    """, to: "Diario/20260811.md")
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    #expect(diary.entries.count == 1)
    #expect(diary.entries[0].startMinutes == 7 * 60 + 20)
    #expect(diary.entries[0].colour == .giallo)
    #expect(diary.prose.contains("Scritto a mano."))
    controller.close()
}

// MARK: The grid the view draws

@MainActor
@Test func showsSixToTwentyOnAnOrdinaryDay() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    #expect(diary.firstHour == 6)
    #expect(diary.lastHour == 20)

    diary.add(title: "Mattina", startMinutes: 10 * 60, durationMinutes: 60)
    #expect(diary.firstHour == 6)
    #expect(diary.lastHour == 20)
    controller.close()
}

/// An entry outside the usual hours must not be invisible: the grid grows to it.
@MainActor
@Test func growsTheGridToReachAnEntryOutsideTheUsualHours() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Alba", startMinutes: 4 * 60 + 30, durationMinutes: 60)
    diary.add(title: "Cena di lavoro", startMinutes: 20 * 60 + 30, durationMinutes: 90)

    #expect(diary.firstHour == 4)
    #expect(diary.lastHour == 22)
    controller.close()
}

@MainActor
@Test func addsUpTheTimeTheDayAccountsFor() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Uno", startMinutes: 540, durationMinutes: 90)
    diary.add(title: "Due", startMinutes: 660, durationMinutes: 30)

    #expect(diary.totalMinutes == 120)
    controller.close()
}

// MARK: The composer

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
