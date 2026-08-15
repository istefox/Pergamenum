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
@Test func showsSixToMidnightOnAnOrdinaryDay() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    #expect(diary.firstHour == 6)
    #expect(diary.lastHour == 24)

    diary.add(title: "Mattina", startMinutes: 10 * 60, durationMinutes: 60)
    diary.add(title: "Sera tardi", startMinutes: 22 * 60 + 30, durationMinutes: 60)
    #expect(diary.firstHour == 6)
    #expect(diary.lastHour == 24)
    controller.close()
}

/// The hours come from Impostazioni, one window for the diary and another for the day
/// view, and changing one does not touch the other.
@MainActor
@Test func drawsTheHoursSetInSettings() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    controller.updateSettings { $0.diaryHours = HourWindow(first: 8, last: 18) }
    #expect(diary.firstHour == 8)
    #expect(diary.lastHour == 18)
    #expect(controller.settings.dayHours == .dayDefault)

    // And a block outside those hours widens the grid rather than vanishing behind it.
    diary.add(title: "Sera", startMinutes: 21 * 60, durationMinutes: 90)
    #expect(diary.firstHour == 8)
    #expect(diary.lastHour == 23)
    controller.close()
}

/// An entry before the usual hours must not be invisible: the grid grows up to it.
@MainActor
@Test func growsTheGridToReachAnEntryBeforeTheUsualHours() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    diary.add(title: "Alba", startMinutes: 4 * 60 + 30, durationMinutes: 60)
    diary.add(title: "Cena di lavoro", startMinutes: 20 * 60 + 30, durationMinutes: 90)

    #expect(diary.firstHour == 4)
    // The evening block needs no room made for it: the grid already reaches midnight.
    #expect(diary.lastHour == 24)
    controller.close()
}

/// The last block of the day fits inside the grid rather than falling off the end of
/// it: 23:30 plus an hour is clamped to midnight, and midnight is drawn.
@MainActor
@Test func drawsABlockThatRunsToMidnight() async throws {
    let vault = try DayVault()
    let root = vault.root
    let (diary, controller) = try await makeDiary(vault)

    let entry = diary.add(title: "Chiusura", startMinutes: 23 * 60 + 30, durationMinutes: 60)

    #expect(entry.endMinutes <= diary.lastHour * 60)
    #expect(diary.entries[0].timeText == "23:00-24:00")

    // And it survives the file: written as 23:00-00:00 it would read as ending before
    // it starts, and the last hour of the day would lose everything written in it.
    let onDisk = try #require(diaryOnDisk(root))
    #expect(onDisk.contains("- 23:00-24:00 Chiusura"))
    diary.move(by: 1)
    diary.move(by: -1)
    #expect(diary.entries.count == 1)
    #expect(diary.entries[0].endMinutes == DiaryGrid.dayMinutes)
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
