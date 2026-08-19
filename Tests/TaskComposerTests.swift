import Foundation
import Testing
@testable import Pergamenum

// The composer of SPEC §7.4: a task can be given a destination note, a scheduled day,
// a due date and a reminder before it is written, and what it writes is the plain
// markdown line of §7.1 - there is no second representation anywhere.

@Test func aComposedTaskIsWrittenInTheMarkerOrderOfTheSpec() {
    let line = TaskParser.line(
        forNewTask: "Richiamare Rossi",
        scheduled: CalendarDate(iso: "2026-08-15"),
        due: CalendarDate(iso: "2026-08-20"),
        reminder: TaskReminder(date: CalendarDate(iso: "2026-08-15")!, hour: 9, minute: 5)
    )
    #expect(line == "- [ ] Richiamare Rossi >2026-08-15 !2026-08-20 @remind(2026-08-15 09:05)")
}

@Test func aComposedTaskWithNoDatesIsJustTheLine() {
    #expect(TaskParser.line(forNewTask: "  Ordinare i supporti  ") == "- [ ] Ordinare i supporti")
}

/// The chips and the typed text can carry the same marker. Writing both produces a
/// line with two `>` dates, which parses back to whichever comes first: a value the
/// user never chose.
@Test func aMarkerTypedByHandIsNotDuplicatedByTheComposer() {
    let line = TaskParser.line(
        forNewTask: "Chiamare il fornitore >2026-09-01 @remind(2026-09-01 08:00)",
        scheduled: CalendarDate(iso: "2026-08-15"),
        due: CalendarDate(iso: "2026-08-20"),
        reminder: TaskReminder(date: CalendarDate(iso: "2026-08-15")!, hour: 9, minute: 0)
    )
    #expect(line == "- [ ] Chiamare il fornitore >2026-09-01 @remind(2026-09-01 08:00) !2026-08-20")
}

/// The two dates are two decisions, and the panel keeps them apart: Programma is the
/// day the task shows up on, Scadenza the day past which it is late.
@Test func programmaAndScadenzaAreWrittenAsTheirOwnMarkers() {
    var draft = VaultController.TaskDraft(text: "Consegnare la relazione")
    #expect(draft.day == nil)

    draft.scheduled = CalendarDate(iso: "2026-08-17")
    draft.due = CalendarDate(iso: "2026-08-20")
    #expect(draft.day == CalendarDate(iso: "2026-08-17"))
    #expect(TaskParser.line(forNewTask: draft.text, scheduled: draft.scheduled, due: draft.due)
        == "- [ ] Consegnare la relazione >2026-08-17 !2026-08-20")
}

/// The day a capture belongs to, for the pane that has to show it: the day it surfaces
/// on, or failing that the day it is due.
@Test func theDayOfADraftFallsBackToTheDueDate() {
    var draft = VaultController.TaskDraft(text: "Solo scadenza", due: CalendarDate(iso: "2026-08-20"))
    #expect(draft.day == CalendarDate(iso: "2026-08-20"))

    draft.scheduled = CalendarDate(iso: "2026-08-15")
    #expect(draft.day == CalendarDate(iso: "2026-08-15"))
}

/// The reminder and the finite recurrence of SPEC §7.1, both set inside the Programma
/// panel, are markers on the same line and nothing else.
@Test func theReminderAndTheRepetitionAreWrittenOnTheLine() {
    let line = TaskParser.line(
        forNewTask: "Rivedere il preventivo",
        scheduled: CalendarDate(iso: "2026-08-17"),
        reminder: TaskReminder(date: CalendarDate(iso: "2026-08-17")!, hour: 8, minute: 30),
        recurrence: TaskRecurrence(completed: 0, total: 3)
    )
    #expect(line == "- [ ] Rivedere il preventivo >2026-08-17 @remind(2026-08-17 08:30) @repeat(0/3)")
}

@MainActor
@Test func aTaskCanBeComposedIntoAChosenNoteRatherThanTheInbox() async throws {
    let vault = try ComposerVault()
    try vault.write(hostNote, to: "01 Progetti/Nexion.md")

    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let draft = VaultController.TaskDraft(
        text: "Misurare la rigidezza",
        destination: .note("01 Progetti/Nexion.md"),
        scheduled: CalendarDate(iso: "2026-08-15"),
        due: CalendarDate(iso: "2026-08-20")
    )
    #expect(controller.captureTask(draft))

    let onDisk = try String(
        contentsOf: vault.root.appending(path: "01 Progetti/Nexion.md"), encoding: .utf8
    )
    #expect(onDisk.contains("- [ ] Misurare la rigidezza >2026-08-15 !2026-08-20"))

    let task = try #require(controller.index.allTasks.first { $0.text.contains("rigidezza") })
    #expect(task.sourcePath == "01 Progetti/Nexion.md")
    #expect(task.scheduled == CalendarDate(iso: "2026-08-15"))
    #expect(task.due == CalendarDate(iso: "2026-08-20"))
    // The inbox is not touched when the composer points somewhere else.
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "00 Inbox/Capture.md").path(percentEncoded: false)
    ))
    controller.close()
}

@MainActor
@Test func aReminderComposedInTheAppIsOnTheLineTheSchedulerReads() async throws {
    let vault = try ComposerVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let before = controller.taskGeneration
    let draft = VaultController.TaskDraft(
        text: "Chiamare Daniela",
        reminder: TaskReminder(date: CalendarDate(iso: "2026-08-15")!, hour: 14, minute: 30)
    )
    #expect(controller.captureTask(draft))

    let task = try #require(controller.index.allTasks.first { $0.text.contains("Daniela") })
    #expect(task.reminder == TaskReminder(date: CalendarDate(iso: "2026-08-15")!, hour: 14, minute: 30))
    // The counter the reminder scheduler watches: without this the notification was
    // only scheduled at the next full rescan, which is to say usually not at all.
    #expect(controller.taskGeneration > before)
    controller.close()
}

@MainActor
@Test func aTaskComposedIntoANoteThatIsNotThereIsRefused() async throws {
    let vault = try ComposerVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let draft = VaultController.TaskDraft(
        text: "Non deve creare niente",
        destination: .note("01 Progetti/Inesistente.md")
    )
    #expect(!controller.captureTask(draft))
    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "01 Progetti/Inesistente.md").path(percentEncoded: false)
    ))
    #expect(controller.problems.contains { $0.contains("Inesistente.md") })
    controller.close()
}

@MainActor
@Test func theLastCaptureIsReadableOnceSoTheViewFollowsTheTask() async throws {
    let vault = try ComposerVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.consumeLastCapture() == nil)
    #expect(controller.captureTask(VaultController.TaskDraft(text: "Senza data")))

    let capture = try #require(controller.consumeLastCapture())
    #expect(capture.scheduled == nil)
    #expect(capture.destination == .inbox)
    // Read once: a second read would move the pane again on an unrelated task write.
    #expect(controller.consumeLastCapture() == nil)
    controller.close()
}

@MainActor
@Test func aNewNoteStartsInTheFolderItWasAskedFor() async throws {
    let vault = try ComposerVault()
    try vault.write(hostNote, to: "01 Progetti/Nexion.md")
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    #expect(controller.noteDraft == nil)
    controller.beginNewNote(in: "01 Progetti")
    #expect(controller.noteDraft?.folder == "01 Progetti")
    #expect(controller.noteDraft?.title.isEmpty == true)

    controller.beginNewNote()
    #expect(controller.noteDraft?.folder.isEmpty == true)
    controller.close()
}

// MARK: Hours on the markers (ADR-0004)

/// A day is what SPEC §7.1 spells; an hour is what a deadline at 15:00 needs. It goes
/// after the date, so a reader that stops at the date still gets the day right.
@Test func anHourIsWrittenAfterItsDate() throws {
    let line = TaskParser.line(
        forNewTask: "Consegnare la relazione",
        scheduled: CalendarDate(iso: "2026-08-17"),
        scheduledTime: TaskTime(hour: 9, minute: 30),
        due: CalendarDate(iso: "2026-08-20"),
        dueTime: TaskTime(hour: 18, minute: 0)
    )
    #expect(line == "- [ ] Consegnare la relazione >2026-08-17 09:30 !2026-08-20 18:00")

    let task = try #require(TaskParser.parse(line: line, sourcePath: "x.md", lineIndex: 0))
    #expect(task.scheduledTime == TaskTime(hour: 9, minute: 30))
    #expect(task.dueTime == TaskTime(hour: 18, minute: 0))
    // The hour comes out of the text with its date, or the task reads "… 09:30 18:00".
    #expect(task.text == "Consegnare la relazione")
}

/// The block is made at the hour the work is planned for, and a deadline stands in
/// only when there is no planned hour: a deadline says when it stops being on time.
@Test func theBlockSlotPrefersThePlannedHourOverTheDeadline() {
    var draft = VaultController.TaskDraft(text: "Montaggio")
    #expect(draft.blockSlot == nil)

    draft.due = CalendarDate(iso: "2026-08-20")
    draft.dueTime = TaskTime(hour: 18, minute: 0)
    #expect(draft.blockSlot?.day == CalendarDate(iso: "2026-08-20"))
    #expect(draft.blockSlot?.time == TaskTime(hour: 18, minute: 0))

    draft.scheduled = CalendarDate(iso: "2026-08-17")
    draft.scheduledTime = TaskTime(hour: 9, minute: 0)
    #expect(draft.blockSlot?.day == CalendarDate(iso: "2026-08-17"))
    #expect(draft.blockSlot?.time == TaskTime(hour: 9, minute: 0))
}

/// A date with no hour makes no block: a block is a span of a day, and a date alone
/// says nothing about where on the day it goes.
@Test func aDraftWithNoHourHasNoSlotToBlockOut() {
    var draft = VaultController.TaskDraft(text: "Senza orario")
    draft.due = CalendarDate(iso: "2026-08-20")
    #expect(draft.blockSlot == nil)
}

@MainActor
@Test func aTaskWithAnHourCanAlsoBecomeABlockOnItsDay() async throws {
    let vault = try ComposerVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    var draft = VaultController.TaskDraft(text: "Collaudo linea 2")
    draft.due = CalendarDate(iso: "2026-08-20")
    draft.dueTime = TaskTime(hour: 15, minute: 0)
    draft.blocksTheDay = true
    #expect(controller.captureTask(draft))

    // The task line, in the note it was captured into.
    let inbox = try String(
        contentsOf: vault.root.appending(path: "00 Inbox/Capture.md"), encoding: .utf8
    )
    #expect(inbox.contains("- [ ] Collaudo linea 2 !2026-08-20 15:00"))

    // And the block, in the daily note of the day it is due - created for the purpose,
    // since planning a day should not depend on having opened it first.
    let daily = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260820.md"), encoding: .utf8
    )
    #expect(daily.contains("## Timeline"))
    #expect(daily.contains("- 15:00-15:30 Collaudo linea 2"))
    #expect(daily.contains("date: 2026-08-20"))
    controller.close()
}

@MainActor
@Test func withoutTheCheckboxNoBlockIsMade() async throws {
    let vault = try ComposerVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    var draft = VaultController.TaskDraft(text: "Solo il task")
    draft.due = CalendarDate(iso: "2026-08-20")
    draft.dueTime = TaskTime(hour: 15, minute: 0)
    #expect(controller.captureTask(draft))

    #expect(!FileManager.default.fileExists(
        atPath: vault.root.appending(path: "Calendar/20260820.md").path(percentEncoded: false)
    ))
    controller.close()
}

@MainActor
@Test func aSecondBlockOnTheSameDayIsPlacedAfterTheFirst() async throws {
    let vault = try ComposerVault()
    let controller = VaultController(recents: .volatile())
    await controller.open(vault.root)

    let day = CalendarDate(iso: "2026-08-20")!
    #expect(controller.addTimeBlock(title: "Primo", on: day, startMinutes: 15 * 60) != nil)
    let second = try #require(controller.addTimeBlock(title: "Secondo", on: day, startMinutes: 15 * 60))

    #expect(second.startMinutes == 15 * 60 + 30)
    let daily = try String(
        contentsOf: vault.root.appending(path: "Calendar/20260820.md"), encoding: .utf8
    )
    #expect(daily.contains("- 15:00-15:30 Primo"))
    #expect(daily.contains("- 15:30-16:00 Secondo"))
    controller.close()
}

// MARK: Fixture

private struct ComposerVault: ~Copyable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-composer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ contents: String, to relativePath: String) throws {
        let url = root.appending(path: relativePath, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}

private let hostNote = """
---
date: 2026-08-11
tags:
  - type-note
---

# Nexion

"""
