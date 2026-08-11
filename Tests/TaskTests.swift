import Foundation
import Testing
@testable import Pergamenum

/// The syntax block of SPEC §7.1, verbatim.
private let syntaxNote = """
---
date: 2026-08-11
tags:
  - type-note
---

## Task

- [ ] Testo del task
- [ ] Task pianificato >2026-08-15
- [ ] Task con scadenza !2026-08-20
- [ ] Task con promemoria @remind(2026-08-15 09:00)
- [ ] Task ricorrente finito @repeat(1/10)
- [ ] Task di progetto per [[Nota indice progetto]] #project-pergamenum
- [ ] Task con nota collegata, vedi [[Trasmissibilità e rapporto di frequenza]]
- [ ] Task con canvas collegato, vedi [[Progetto X.canvas]]
- [x] Task completato @done(2026-08-11)
- [>] Task ripianificato (spostato a data futura)
- [-] Task annullato
"""

@Test func parsesEveryFormOfTheSpecSyntaxBlock() {
    let tasks = TaskParser.tasks(in: syntaxNote, sourcePath: "Nota.md")
    #expect(tasks.count == 11)

    #expect(tasks[0].state == .open)
    #expect(tasks[1].scheduled == CalendarDate(iso: "2026-08-15"))
    #expect(tasks[2].due == CalendarDate(iso: "2026-08-20"))
    #expect(tasks[3].reminder == TaskReminder(date: CalendarDate(iso: "2026-08-15")!, hour: 9, minute: 0))
    #expect(tasks[4].recurrence == TaskRecurrence(completed: 1, total: 10))
    #expect(tasks[5].project == Tag("project-pergamenum"))
    #expect(tasks[5].links == ["Nota indice progetto"])
    #expect(tasks[6].links == ["Trasmissibilità e rapporto di frequenza"])
    #expect(tasks[7].links == ["Progetto X.canvas"])
    #expect(tasks[8].state == .done)
    #expect(tasks[8].completed == CalendarDate(iso: "2026-08-11"))
    #expect(tasks[9].state == .rescheduled)
    #expect(tasks[10].state == .cancelled)
}

@Test func stripsMarkersFromTheDisplayedText() {
    let tasks = TaskParser.tasks(in: syntaxNote, sourcePath: "Nota.md")
    #expect(tasks[1].text == "Task pianificato")
    #expect(tasks[3].text == "Task con promemoria")
    #expect(tasks[8].text == "Task completato")
    // Tags come out too: they are captured as fields and rendered as chips, so
    // leaving them inline would show them twice.
    #expect(tasks[5].text == "Task di progetto per")
    // Wikilinks come out of the sentence and are rendered as link chips instead:
    // SPEC §7.2 wants every wikilink clickable, and showing it inline as well would
    // present the same link twice.
    #expect(tasks[6].text == "Task con nota collegata, vedi")
    #expect(tasks[6].links == ["Trasmissibilità e rapporto di frequenza"])
}

@Test func recordsWhereEachTaskLives() {
    let tasks = TaskParser.tasks(in: syntaxNote, sourcePath: "01 Progetti/Nota.md")
    #expect(tasks[0].sourcePath == "01 Progetti/Nota.md")
    // Line indices must be absolute in the file, or a rewrite lands on the wrong line.
    #expect(tasks[0].lineIndex == 8)
    #expect(tasks[0].id == "01 Progetti/Nota.md#8")
}

@Test func acceptsIndentedAndStarBullets() {
    let note = "  - [ ] Annidato\n* [ ] Con asterisco\n\t- [x] Con tab"
    let tasks = TaskParser.tasks(in: note, sourcePath: "x.md")
    #expect(tasks.count == 3)
    #expect(tasks[2].state == .done)
}

@Test(arguments: [
    "- [] Senza spazio",
    "- Testo normale",
    "-[ ] Senza spazio dopo il trattino",
    "Testo con - [ ] in mezzo",
    "",
])
func rejectsLinesThatAreNotTasks(_ line: String) {
    #expect(TaskParser.parse(line: line, sourcePath: "x.md", lineIndex: 0) == nil)
}

@Test func ignoresTasksInsideCodeBlocks() {
    // A shell snippet with a checkbox is not a task, the same reason `[[ ]]` in bash
    // is not a wikilink.
    let note = """
    - [ ] Vero task

    ```markdown
    - [ ] Esempio nella documentazione
    ```

    - [x] Altro vero task
    """
    let tasks = TaskParser.tasks(in: note, sourcePath: "x.md")
    #expect(tasks.map(\.text) == ["Vero task", "Altro vero task"])
}

@Test func doesNotMistakeAQuoteForASchedule() {
    let task = TaskParser.parse(line: "- [ ] Confronta se x > 3 allora", sourcePath: "x.md", lineIndex: 0)
    #expect(task?.scheduled == nil)
    let malformed = TaskParser.parse(line: "- [ ] Task >2026-8-1", sourcePath: "x.md", lineIndex: 0)
    #expect(malformed?.scheduled == nil)
}

@Test func rejectsAMalformedReminderRatherThanGuessing() {
    let bad = TaskParser.parse(line: "- [ ] Task @remind(2026-08-15 25:99)", sourcePath: "x.md", lineIndex: 0)
    #expect(bad?.reminder == nil)
    // A reminder with no time is kept, defaulted, rather than discarded.
    let noTime = TaskParser.parse(line: "- [ ] Task @remind(2026-08-15)", sourcePath: "x.md", lineIndex: 0)
    #expect(noTime?.reminder?.date == CalendarDate(iso: "2026-08-15"))
}

// MARK: - State

@Test func computesOverdueAgainstADay() {
    let task = TaskParser.parse(line: "- [ ] Task !2026-08-10", sourcePath: "x.md", lineIndex: 0)!
    #expect(task.isOverdue(on: CalendarDate(iso: "2026-08-11")!))
    #expect(!task.isOverdue(on: CalendarDate(iso: "2026-08-10")!))

    let done = TaskParser.parse(line: "- [x] Task !2026-08-10", sourcePath: "x.md", lineIndex: 0)!
    // A completed task is never late.
    #expect(!done.isOverdue(on: CalendarDate(iso: "2026-08-11")!))
}

@Test func treatsARescheduledTaskAsStillOpen() {
    #expect(TaskItem.State.rescheduled.isOpen)
    #expect(TaskItem.State.open.isOpen)
    #expect(!TaskItem.State.done.isOpen)
    #expect(!TaskItem.State.cancelled.isOpen)
}

// MARK: - Rewriting

private let today = CalendarDate(iso: "2026-08-11")!

@Test func completingATaskPreservesEverythingElseOnTheLine() {
    let raw = "    - [ ] Rivedere la curva #project-x >2026-08-15 [[Nota]]"
    let task = TaskParser.parse(line: raw, sourcePath: "x.md", lineIndex: 3)!
    let line = TaskParser.line(for: task, settingState: .done, today: today)

    #expect(line.hasPrefix("    - [x] "))
    #expect(line.contains("#project-x"))
    #expect(line.contains(">2026-08-15"))
    #expect(line.contains("[[Nota]]"))
    #expect(line.hasSuffix("@done(2026-08-11)"))
}

@Test func reopeningATaskRemovesTheCompletionDate() {
    let raw = "- [x] Fatto @done(2026-08-01)"
    let task = TaskParser.parse(line: raw, sourcePath: "x.md", lineIndex: 0)!
    let line = TaskParser.line(for: task, settingState: .open, today: today)
    #expect(line == "- [ ] Fatto")
}

@Test func reschedulingReplacesTheExistingDate() {
    let raw = "- [ ] Task >2026-08-15 coda"
    let task = TaskParser.parse(line: raw, sourcePath: "x.md", lineIndex: 0)!

    let moved = TaskParser.line(for: task, scheduledOn: CalendarDate(iso: "2026-08-20")!)
    #expect(moved.contains(">2026-08-20"))
    #expect(!moved.contains(">2026-08-15"))
    #expect(moved.contains("coda"))

    let cleared = TaskParser.line(for: task, scheduledOn: nil)
    #expect(!cleared.contains(">2026-08"))
}

@Test func schedulingATaskThatHadNoDateAppendsIt() {
    let task = TaskParser.parse(line: "- [ ] Task", sourcePath: "x.md", lineIndex: 0)!
    #expect(TaskParser.line(for: task, scheduledOn: today) == "- [ ] Task >2026-08-11")
}

@Test func addingALinkIsIdempotent() {
    let task = TaskParser.parse(line: "- [ ] Task [[Nota]]", sourcePath: "x.md", lineIndex: 0)!
    #expect(TaskParser.line(for: task, addingLinkTo: "Nota") == "- [ ] Task [[Nota]]")
    #expect(TaskParser.line(for: task, addingLinkTo: "Altra") == "- [ ] Task [[Nota]] [[Altra]]")
}

@Test func rewritesOnlyTheExpectedLine() {
    let text = "riga 0\n- [ ] Task\nriga 2"
    let rewritten = TaskParser.rewrite(text, at: 1, expecting: "- [ ] Task", with: "- [x] Task")
    #expect(rewritten == "riga 0\n- [x] Task\nriga 2")
}

@Test func refusesToRewriteWhenTheLineMovedOn() {
    // A stale index must not rewrite whatever now sits at that line number.
    let text = "riga 0\naltro contenuto\nriga 2"
    #expect(TaskParser.rewrite(text, at: 1, expecting: "- [ ] Task", with: "- [x] Task") == nil)
    #expect(TaskParser.rewrite(text, at: 99, expecting: "- [ ] Task", with: "- [x] Task") == nil)
}

@Test func aCompletedTaskRoundTripsThroughItsOwnRewrite() {
    let original = "- [ ] Task con [[Nota]] #project-x !2026-08-20"
    let task = TaskParser.parse(line: original, sourcePath: "x.md", lineIndex: 0)!
    let completedLine = TaskParser.line(for: task, settingState: .done, today: today)

    let reparsed = TaskParser.parse(line: completedLine, sourcePath: "x.md", lineIndex: 0)!
    #expect(reparsed.state == .done)
    #expect(reparsed.completed == today)
    #expect(reparsed.links == ["Nota"])
    #expect(reparsed.project == Tag("project-x"))
    #expect(reparsed.due == CalendarDate(iso: "2026-08-20"))
}

// MARK: - Task views and rewriting on disk

private struct TaskVault: ~Copyable {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "pergamenum-tasks-\(UUID().uuidString)", directoryHint: .isDirectory)
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

private let taskNote = """
---
date: 2026-08-11
tags:
  - type-note
---

- [ ] Senza data
- [ ] Oggi >2026-08-11
- [ ] In ritardo !2026-08-05
- [ ] Fra tre giorni >2026-08-14
- [ ] Fra un mese >2026-09-20
- [ ] Di progetto #project-pergamenum
- [x] Gia fatto @done(2026-08-10)
- [ ] Collegato a [[Curva di trasmissibilità]]
"""

@MainActor
@Test func sortsTasksIntoTheFiveViews() async throws {
    let vault = try TaskVault()
    try vault.write(taskNote, to: "Note.md")

    let controller = VaultController()
    await controller.open(vault.root)
    let day = CalendarDate(iso: "2026-08-11")!

    // Inbox: no date, no project.
    #expect(controller.index.tasks(for: .inbox, on: day).map(\.text) == ["Senza data", "Collegato a"])
    // Today includes the overdue one: a task that slipped is what the day view exists
    // to surface (SPEC §7.3 rules out moving it silently).
    #expect(Set(controller.index.tasks(for: .today, on: day).map(\.text)) == ["Oggi", "In ritardo"])
    // Upcoming is the next seven days, so the one a month out is excluded.
    #expect(controller.index.tasks(for: .upcoming, on: day).map(\.text) == ["Fra tre giorni"])
    #expect(controller.index.tasks(for: .byProject, on: day).map(\.text) == ["Di progetto"])
    // Every view is open tasks only; the completed one appears in none of them.
    #expect(controller.index.tasks(for: .all, on: day).count == 7)
    controller.close()
}

@MainActor
@Test func findsTheTasksLinkingToANote() async throws {
    let vault = try TaskVault()
    try vault.write(taskNote, to: "Note.md")

    let controller = VaultController()
    await controller.open(vault.root)
    // SPEC §7.2: the wikilink is the link, navigable in both directions.
    #expect(controller.index.tasks(linkingTo: "Curva di trasmissibilità").count == 1)
    #expect(controller.index.tasks(linkingTo: "curva di trasmissibilità").count == 1)
    #expect(controller.index.tasks(linkingTo: "Inesistente").isEmpty)
    controller.close()
}

@MainActor
@Test func completingATaskRewritesItsSourceNote() async throws {
    let vault = try TaskVault()
    try vault.write(taskNote, to: "Note.md")

    let controller = VaultController()
    await controller.open(vault.root)
    let task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    #expect(controller.toggle(task))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk.contains("- [x] Oggi >2026-08-11 @done("))
    // Everything else in the note is untouched.
    #expect(onDisk.contains("- [ ] Senza data"))
    #expect(onDisk.contains("date: 2026-08-11"))
    controller.close()
}

@MainActor
@Test func reschedulingWritesTheNewDate() async throws {
    let vault = try TaskVault()
    try vault.write(taskNote, to: "Note.md")

    let controller = VaultController()
    await controller.open(vault.root)
    let task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    #expect(controller.apply(.schedule(CalendarDate(iso: "2026-08-20")!), to: task))
    let onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Oggi >2026-08-20"))
    #expect(!onDisk.contains(">2026-08-11\n"))
    controller.close()
}

@MainActor
@Test func refusesToRewriteATaskThatMovedOnDisk() async throws {
    let vault = try TaskVault()
    try vault.write(taskNote, to: "Note.md")

    let controller = VaultController()
    await controller.open(vault.root)
    var task = try #require(controller.index.allTasks.first { $0.text == "Oggi" })

    // Simulate a stale index entry: the line number is right, the content is not.
    task.rawLine = "- [ ] Qualcosa di completamente diverso"
    #expect(!controller.apply(.state(.done), to: task))

    let onDisk = try String(contentsOf: vault.root.appending(path: "Note.md"), encoding: .utf8)
    #expect(onDisk == taskNote)
    controller.close()
}

@MainActor
@Test func quickCaptureAppendsToTheInbox() async throws {
    let vault = try TaskVault()
    let controller = VaultController()
    await controller.open(vault.root)

    #expect(controller.captureTask("Richiamare Rossi"))
    #expect(controller.captureTask("Ordinare i supporti"))

    let onDisk = try String(contentsOf: vault.root.appending(path: "00 Inbox/Capture.md"), encoding: .utf8)
    #expect(onDisk.contains("- [ ] Richiamare Rossi"))
    #expect(onDisk.contains("- [ ] Ordinare i supporti"))
    // The capture note itself is conformant: type-note plus status-inbox (tag.md 5.1).
    #expect(onDisk.contains("- type-note"))
    #expect(onDisk.contains("- status-inbox"))

    let day = CalendarDate(iso: "2026-08-11")!
    #expect(controller.index.tasks(for: .inbox, on: day).count == 2)
    controller.close()
}

@MainActor
@Test func quickCaptureIgnoresEmptyInput() async throws {
    let vault = try TaskVault()
    let controller = VaultController()
    await controller.open(vault.root)
    #expect(!controller.captureTask("   "))
    controller.close()
}
