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

    #expect(controller.newNote == nil)
    controller.beginNewNote(in: "01 Progetti")
    #expect(controller.newNote?.folder == "01 Progetti")
    #expect(controller.newNote?.title.isEmpty == true)

    controller.beginNewNote()
    #expect(controller.newNote?.folder.isEmpty == true)
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
