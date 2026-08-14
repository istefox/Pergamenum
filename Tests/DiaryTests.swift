import Foundation
import Testing
@testable import Pergamenum

// MARK: The file format

@Test func readsAnEntryWithItsTimesAndTitle() {
    let text = """
    ---
    date: 2026-08-14
    ---

    Giornata in reparto.

    ## Diario

    - 09:00-11:30 Sopralluogo pressa 4
    """
    let (prose, entries) = DiarySection.split(text)

    #expect(entries.count == 1)
    #expect(entries[0].startMinutes == 9 * 60)
    #expect(entries[0].durationMinutes == 150)
    #expect(entries[0].title == "Sopralluogo pressa 4")
    #expect(entries[0].colour == .blu)
    // The section is the timeline's, so the editor never sees it.
    #expect(!prose.contains("## Diario"))
    #expect(prose.contains("Giornata in reparto."))
}

@Test func readsTheIndentedLinesUnderAnEntryAsItsNote() {
    let text = """
    ## Diario

    - 09:00-10:00 Riunione
      Presenti Marco e Anna.
      Deciso di rifare il preventivo.
    - 14:00-15:00 Calcoli
    """
    let entries = DiarySection.parse(from: text)

    #expect(entries.count == 2)
    #expect(entries[0].note == "Presenti Marco e Anna.\nDeciso di rifare il preventivo.")
    #expect(entries[1].note.isEmpty)
}

@Test func keepsABlankLineInsideANoteButNotAtItsEnd() {
    let text = """
    ## Diario

    - 09:00-10:00 Riunione
      Primo punto.

      Secondo punto.

    - 14:00-15:00 Calcoli
    """
    let entries = DiarySection.parse(from: text)

    #expect(entries[0].note == "Primo punto.\n\nSecondo punto.")
    #expect(entries.count == 2)
}

/// An indented bullet is part of the note above it. Without this rule a list written
/// inside a note would become a second appointment at the same hour.
@Test func doesNotReadAnIndentedBulletAsASecondEntry() {
    let text = """
    ## Diario

    - 09:00-10:00 Riunione
      - primo punto
      - secondo punto
    """
    let entries = DiarySection.parse(from: text)

    #expect(entries.count == 1)
    #expect(entries[0].note == "- primo punto\n- secondo punto")
}

@Test func readsAndWritesTheColourMarker() {
    let entries = DiarySection.parse(from: "## Diario\n\n- 06:00-07:00 Palestra [colore:verde]")

    #expect(entries[0].colour == .verde)
    #expect(entries[0].title == "Palestra")
    #expect(DiarySection.write(entries, into: "").contains("- 06:00-07:00 Palestra [colore:verde]"))
}

/// Blue is the default, so it is not written: a day of ordinary entries stays a clean
/// markdown list.
@Test func leavesTheDefaultColourOutOfTheFile() {
    let written = DiarySection.write(
        [DiaryEntry(startMinutes: 540, durationMinutes: 60, title: "Riunione")], into: ""
    )
    #expect(!written.contains("colore"))
}

@Test func roundTripsADayWithoutChangingIt() {
    let text = """
    ---
    date: 2026-08-14
    ---

    Prosa del giorno.

    ## Diario

    - 06:00-07:00 Palestra [colore:verde]
      Panca e trazioni.
    - 09:00-11:30 Sopralluogo pressa 4

    """
    let (prose, entries) = DiarySection.split(text)
    let rewritten = DiarySection.write(entries, into: prose)

    #expect(rewritten == text)
    // And again, so a save that changes nothing really changes nothing.
    let (prose2, entries2) = DiarySection.split(rewritten)
    #expect(DiarySection.write(entries2, into: prose2) == text)
}

@Test func takesTheSectionAwayWhenTheLastEntryGoes() {
    let text = "---\ndate: 2026-08-14\n---\n\nProsa.\n\n## Diario\n\n- 09:00-10:00 Riunione\n"
    let (prose, _) = DiarySection.split(text)

    let written = DiarySection.write([], into: prose)
    #expect(!written.contains("## Diario"))
    #expect(written.hasSuffix("Prosa.\n"))
}

/// Nothing the user typed is thrown away, even inside a section this app believes it
/// owns: a line that is neither an entry nor a note comes back as prose.
@Test func keepsALineItCannotUnderstandRatherThanDroppingIt() {
    let text = "## Diario\n\n- 09:00-10:00 Riunione\nnon so cosa sia questa riga\n"
    let (prose, entries) = DiarySection.split(text)

    #expect(entries.count == 1)
    #expect(prose.contains("non so cosa sia questa riga"))
}

@Test func closesTheSectionAtTheNextHeading() {
    let text = """
    ## Diario

    - 09:00-10:00 Riunione

    ## Note correlate

    - [[Qualcosa]]
    """
    let (prose, entries) = DiarySection.split(text)

    #expect(entries.count == 1)
    #expect(prose.contains("## Note correlate"))
    #expect(prose.contains("- [[Qualcosa]]"))
}

@Test func refusesTimesThatAreNotTimes() {
    let text = """
    ## Diario

    - 25:00-26:00 Impossibile
    - 10:00-09:00 All'indietro
    - 09:00 Senza fine
    - 09:00-10:00 Buono
    """
    let entries = DiarySection.parse(from: text)

    #expect(entries.count == 1)
    #expect(entries[0].title == "Buono")
}

@Test func writingIntoAWholeNoteDoesNotLeaveTwoSections() {
    let text = "Prosa.\n\n## Diario\n\n- 09:00-10:00 Riunione\n"
    let written = DiarySection.write(
        [DiaryEntry(startMinutes: 600, durationMinutes: 60, title: "Altro")], into: text
    )

    #expect(written.components(separatedBy: "## Diario").count == 2)
    #expect(!written.contains("Riunione"))
}

// MARK: The grid

@Test func snapsEveryTimeToATenMinuteMark() {
    #expect(DiaryGrid.snap(0) == 0)
    #expect(DiaryGrid.snap(4) == 0)
    #expect(DiaryGrid.snap(5) == 10)
    #expect(DiaryGrid.snap(63) == 60)
    #expect(DiaryGrid.snapDown(69) == 60)
    #expect(DiaryGrid.snapDown(70) == 70)
}

@Test func keepsAnEntryInsideTheDay() {
    #expect(DiaryGrid.clampStart(-30, duration: 60) == 0)
    #expect(DiaryGrid.clampStart(23 * 60 + 50, duration: 60) == 23 * 60)
    #expect(DiaryGrid.clampDuration(3) == 10)
    #expect(DiaryGrid.clampDuration(125) == 130)
}

/// Ten minutes to eight hours, ten at a time - which is what "blocchi di due o tre ore"
/// needs to be offered.
@Test func offersEveryTenMinuteDuration() {
    #expect(DiaryGrid.durations.first == 10)
    #expect(DiaryGrid.durations.contains(120))
    #expect(DiaryGrid.durations.contains(180))
    #expect(DiaryGrid.durations.last == 480)
    #expect(DiaryGrid.durations.allSatisfy { $0 % 10 == 0 })
}

// MARK: Side by side

@Test func putsTwoOverlappingEntriesInTwoColumns() {
    let placements = DiaryLayout.place([
        DiaryEntry(startMinutes: 540, durationMinutes: 120, title: "Riunione"),
        DiaryEntry(startMinutes: 570, durationMinutes: 30, title: "Telefonata"),
    ])

    #expect(placements.count == 2)
    #expect(placements.allSatisfy { $0.columns == 2 })
    #expect(Set(placements.map(\.column)) == [0, 1])
}

@Test func leavesEntriesThatDoNotTouchAtFullWidth() {
    let placements = DiaryLayout.place([
        DiaryEntry(startMinutes: 540, durationMinutes: 60, title: "Mattina"),
        DiaryEntry(startMinutes: 600, durationMinutes: 60, title: "Dopo"),
    ])

    #expect(placements.allSatisfy { $0.columns == 1 && $0.column == 0 })
}

/// A 9-11 with a 9:30-10 inside it and a 10:30-11 after that: all three belong to one
/// cluster, because the first one reaches over both.
@Test func groupsAChainOfOverlapsIntoOneCluster() {
    let placements = DiaryLayout.place([
        DiaryEntry(startMinutes: 540, durationMinutes: 120, title: "Lunga"),
        DiaryEntry(startMinutes: 570, durationMinutes: 30, title: "Dentro"),
        DiaryEntry(startMinutes: 630, durationMinutes: 30, title: "Dopo, ma dentro la lunga"),
    ])

    #expect(placements.allSatisfy { $0.columns == 2 })
    // The two short ones do not touch each other, so they share a column.
    let short = placements.filter { $0.entry.durationMinutes == 30 }
    #expect(short.allSatisfy { $0.column == 1 })
}

@Test func placesNothingForADayWithNoEntries() {
    #expect(DiaryLayout.place([]).isEmpty)
}
