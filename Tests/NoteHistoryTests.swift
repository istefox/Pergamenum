import Foundation
import Testing
@testable import Pergamenum

// The version-history half of M9 (ADR-0011): what `NoteHistory` keeps on disk and how
// it thins itself, with no view on it yet - that is the next slice, mockup-first.

@Test func recordingWritesASnapshotThatSnapshotsReadsBack() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))

    history.record("prima versione\n", for: "N.md")

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.count == 1)
    #expect(snapshots.first?.text == "prima versione\n")
}

@Test func snapshotsComeBackNewestFirst() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))
    let now = Date()

    history.record("vecchia\n", for: "N.md", at: now.addingTimeInterval(-10))
    history.record("nuova\n", for: "N.md", at: now)

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.map(\.text) == ["nuova\n", "vecchia\n"])
}

@Test func aNoteWithNoHistoryReturnsAnEmptyListNotAnError() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))

    #expect(history.snapshots(for: "Mai salvata.md").isEmpty)
}

// MARK: - Thinning (ADR-0011 D4)

@Test func twoSnapshotsWithinADayBothSurviveThinning() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))
    let now = Date()

    history.record("uno\n", for: "N.md", at: now.addingTimeInterval(-60))
    history.record("due\n", for: "N.md", at: now)

    #expect(history.snapshots(for: "N.md").count == 2)
}

@Test func twoSnapshotsOlderThanADayOnTheSameDayCollapseToOne() throws {
    // Thinning is write-triggered, not a background job: it only re-evaluates "how old
    // is this" against the timestamp of whichever write just happened. Two old snapshots
    // with nothing written since sit exactly as they are - a later write is what makes
    // the comparison happen at all, so this test supplies one.
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))
    let now = Date()
    // Both well past the 24h cutoff, both on the same calendar day.
    let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        .addingTimeInterval(-172_800)   // two days ago
    let evening = morning.addingTimeInterval(3 * 3_600)

    history.record("mattina\n", for: "N.md", at: morning)
    history.record("sera\n", for: "N.md", at: evening)
    // Nothing to collapse yet: from `evening`'s own vantage point, `morning` is three
    // hours old, well inside the 24h window. Only a write further out re-evaluates them.
    #expect(history.snapshots(for: "N.md").count == 2)

    history.record("oggi\n", for: "N.md", at: now)

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.map(\.text) == ["oggi\n", "sera\n"])
}

@Test func twoSnapshotsOlderThanADayOnDifferentDaysBothSurvive() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))
    let now = Date()
    // Pinned like its two siblings rather than measured from whatever time it is: a
    // fixed number of seconds back lands on a wall-clock hour that moves, and a daylight
    // saving transition inside the window would shift which calendar day a snapshot
    // belongs to. That is precisely the class of flake that reddened this suite once.
    let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
    let threeDaysAgo = nine.addingTimeInterval(-259_200)
    let twoDaysAgo = nine.addingTimeInterval(-172_800)

    // Written in the order real writes happen, oldest first, then a write near real
    // `now` to actually trigger the comparison thinning depends on (see the same-day
    // test above for why an unthinned pair needs a later write to be re-evaluated at
    // all).
    history.record("tre giorni fa\n", for: "N.md", at: threeDaysAgo)
    history.record("l'altro ieri\n", for: "N.md", at: twoDaysAgo)
    history.record("oggi\n", for: "N.md", at: now)

    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.map(\.text) == ["oggi\n", "l'altro ieri\n", "tre giorni fa\n"])
}

@Test func recentAndOldSnapshotsThinIndependently() throws {
    // The boundary itself: one snapshot inside the 24h window and two on the same
    // older day - only the older pair collapses.
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))
    let now = Date()
    // Pinned to nine in the morning, as the same-day test above is, and for a reason
    // that cost a red suite: derived straight from `Date()`, `old1` was `now` minus 48
    // hours and `old2` an hour later, so between 23:00 and midnight the pair landed on
    // two different calendar days and thinning correctly kept both. The rule was right;
    // the test only described it for 23 hours out of every 24.
    let old1 = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        .addingTimeInterval(-172_800)
    let old2 = old1.addingTimeInterval(3_600)

    history.record("vecchia 1\n", for: "N.md", at: old1)
    history.record("vecchia 2\n", for: "N.md", at: old2)
    history.record("recente\n", for: "N.md", at: now.addingTimeInterval(-60))

    #expect(history.snapshots(for: "N.md").count == 2)
}

@Test func aStrayUnparseableFileIsSkippedByBothReadingAndThinning() throws {
    let vault = try TemporaryVault()
    let history = NoteHistory(directory: vault.root.appending(path: "history"))
    history.record("buona\n", for: "N.md")

    let noteDir = vault.root
        .appending(path: "history/N.md", directoryHint: .isDirectory)
    try Data("non è un timestamp\n".utf8)
        .write(to: noteDir.appending(path: "non-parseable.md"))

    // The negative control: without the guard, this file would either crash the read
    // or be counted, and the directory holds exactly one recognisable snapshot.
    let snapshots = history.snapshots(for: "N.md")
    #expect(snapshots.count == 1)
    #expect(snapshots.first?.text == "buona\n")
}

// MARK: - The hook into VaultSession.write

@MainActor
@Test func savingANoteThroughTheSessionRecordsAHistorySnapshot() async throws {
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write("contenuto\n", to: "N.md")

    #expect(session.history.snapshots(for: "N.md").count == 1)
}

@MainActor
@Test func aNonMarkdownWriteLeavesNoHistoryBehind() async throws {
    // The scope guard (ADR-0011 D2): a canvas write goes through the same
    // `VaultSession.write`, and must not gain a history directory of its own.
    let vault = try TemporaryVault()
    let session = VaultSession(root: vault.root, stateBase: vault.stateBase)
    await session.rescan()

    // ADR-0041 Task 8: `VaultSession.write` gained an async overload.
    try await session.write("{\"nodes\":[],\"edges\":[]}", to: "Board.canvas")

    #expect(session.history.snapshots(for: "Board.canvas").isEmpty)
}

// MARK: - Il raggruppamento per giorno (M9, il foglio di restore)

/// A gregorian calendar pinned to Rome, so a grouping rule about "today" and
/// "yesterday" is not decided by where the machine running the test happens to be.
private func romanCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Rome") ?? .gmt
    return calendar
}

@Test func todayAndYesterdayBecomeTwoGroupsNewestFirst() throws {
    let calendar = romanCalendar()
    let now = try #require(calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 18, hour: 18, minute: 42)
    ))
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))
    let snapshots = [
        NoteHistory.Snapshot(date: now, text: "tre\n"),
        NoteHistory.Snapshot(date: now.addingTimeInterval(-3_600), text: "due\n"),
        NoteHistory.Snapshot(date: yesterday, text: "uno\n"),
    ]

    let groups = HistoryGrouping.groups(for: snapshots, now: now, calendar: calendar)

    #expect(groups.map(\.title) == ["Oggi", "Ieri"])
    #expect(groups.first?.entries.map(\.snapshot.text) == ["tre\n", "due\n"])
    #expect(groups.last?.entries.map(\.snapshot.text) == ["uno\n"])
}

@Test func anOlderDayIsTitledByItsWeekdayAndDateInItalian() throws {
    let calendar = romanCalendar()
    let now = try #require(calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 18, hour: 18, minute: 42)
    ))
    // Three days back, so neither the "Oggi" nor the "Ieri" arm can claim it.
    let saturday = try #require(calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 15, hour: 9, minute: 30)
    ))

    let groups = HistoryGrouping.groups(
        for: [NoteHistory.Snapshot(date: saturday, text: "x\n")],
        now: now,
        calendar: calendar,
        locale: Locale(identifier: "it_IT")
    )

    #expect(groups.map(\.title) == ["sabato 15 agosto"])
}

@Test func anEmptyHistoryGroupsIntoNothingRatherThanOneEmptyDay() throws {
    let calendar = romanCalendar()
    let now = try #require(calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 18, hour: 18, minute: 42)
    ))

    #expect(HistoryGrouping.groups(for: [], now: now, calendar: calendar).isEmpty)
}

@Test func twoSavesInTheSameSecondStayTwoSelectableRows() throws {
    // The reason `HistoryEntry` is keyed on position and not on the date: both of these
    // parse back to the same second, and selecting by date would merge them into one.
    let calendar = romanCalendar()
    let now = try #require(calendar.date(
        from: DateComponents(year: 2026, month: 8, day: 18, hour: 18, minute: 42)
    ))
    let snapshots = [
        NoteHistory.Snapshot(date: now, text: "seconda\n"),
        NoteHistory.Snapshot(date: now, text: "prima\n"),
    ]

    let groups = HistoryGrouping.groups(for: snapshots, now: now, calendar: calendar)

    #expect(groups.count == 1)
    #expect(groups.first?.entries.map(\.id) == [0, 1])
}

// MARK: - Il ripristino

/// A conformant note to restore versions of. Local to this file: `VaultTests`' own
/// sample is private to that file, and a second copy here is cheaper than widening it.
private let restorableNote = """
---
date: 2026-08-18
tags:
  - type-note
---

Prima versione.
"""

@MainActor
@Test func restoringWritesTheOldTextAndTheEditorFollowsIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(restorableNote, to: "Uno.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "Uno.md")
    let original = try #require(controller.openNote?.text)

    controller.updateOpenNoteText(original + "\n\nSeconda versione.")
    controller.saveOpenNote()

    let versions = try #require(controller.session).history.snapshots(for: "Uno.md")
    let oldest = try #require(versions.last)
    controller.restoreVersion(oldest.text)

    #expect(controller.openNote?.text == oldest.text)
    #expect(controller.openNote?.hasUnsavedChanges == false)
    let onDisk = try #require(controller.session).read("Uno.md")
    #expect(onDisk.text == oldest.text)
}

@MainActor
@Test func restoringOverUnsavedEditsKeepsThemAsTheirOwnVersion() async throws {
    // The negative control for the save-first rule in `restoreVersion`. Without that
    // first save the buffer's text is in no snapshot at all, so restoring would discard
    // it with nothing to go back to - and this test is what fails if someone later
    // decides the extra write is redundant.
    let vault = try TemporaryVault()
    try vault.write(restorableNote, to: "Uno.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile())
    await controller.open(vault.root)
    controller.openNote(at: "Uno.md")
    let original = try #require(controller.openNote?.text)

    controller.updateOpenNoteText(original + "\n\nSalvata.")
    controller.saveOpenNote()

    // Typed but never saved: this is the text that has no snapshot yet.
    let unsaved = original + "\n\nMai salvata, e da non perdere."
    controller.updateOpenNoteText(unsaved)
    #expect(controller.openNote?.hasUnsavedChanges == true)

    let session = try #require(controller.session)
    let before = session.history.snapshots(for: "Uno.md")
    controller.restoreVersion(original)

    let after = session.history.snapshots(for: "Uno.md")
    #expect(controller.openNote?.text == original)
    #expect(after.contains { $0.text == unsaved }, "il buffer non salvato non è finito nella cronologia")
    #expect(after.count > before.count)
}
