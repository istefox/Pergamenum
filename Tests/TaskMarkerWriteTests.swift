import Foundation
import Testing
@testable import Pergamenum

// ADR-0021 ("A task carries its Workspace and its place in a project as caret markers in
// its own line, and nothing new is stored anywhere else"), §D9 and §A9. Plan
// `docs/superpowers/plans/2026-08-24-workspace-tasks-notes-integration.md`, Task 3: the two
// writes - assigning a Workspace and inserting a sub-task - both going through the existing
// `read` → rewrite → atomic `write` path (R-03, R-07, R-09).
//
// `TaskParser.line(for:assigningWorkspace:)` and `TaskParser.insertingSubtask(in:below:draft:)`
// are signature-only stubs as of this commit (`Sources/Core/Tasks/TaskParser.swift`): the first
// returns its line unchanged, the second returns nil unconditionally. Every test below is
// expected to fail red on its assertions, not to fail to compile - the coder's Task 3 work
// fills in the replace-or-append/clear logic and the two-line insert this file already encodes
// as assertions. One exception, by construction rather than by oversight: the staleness test
// (`insertingASubtaskReturnsNilWhenTheParentLineHasMovedOn`) asserts a nil result, which the
// unconditional-nil stub already satisfies - the same "guard tests may already read green"
// note `Tests/TaskMarkerTests.swift`'s own header carries for Task 1/2.
//
// R-09's own test needs no stub and no new production code at all (ADR-0021 D5: "there is no
// code path from 'every sub-task is done' to `@done` on the parent"). It is a green test today
// and stays green after Task 3 - the test itself is what makes the absence of a cascade
// verifiable.

private func task(_ line: String, in path: String = "Nota.md", at index: Int = 0) -> TaskItem {
    TaskParser.parse(line: line, sourcePath: path, lineIndex: index)!
}

// MARK: - `TaskParser.line(for:assigningWorkspace:)` (ADR-0021 D9; R-03)

@Test func assigningWorkspaceAddsTheMarkerToALineWithNone() {
    let t = task("- [ ] Verifica disegno")
    let updated = TaskParser.line(for: t, assigningWorkspace: "vibrofer-emea.canvas")
    #expect(updated == "- [ ] Verifica disegno ^[[vibrofer-emea.canvas]]")
}

@Test func assigningWorkspaceReplacesAnExistingMarkerRatherThanAppendingASecond() {
    // R-03: "writes exactly one `^[[...]].canvas` marker". A user reassigning the board
    // gets one marker, not two.
    let t = task("- [ ] Verifica disegno ^[[vecchio-progetto.canvas]]")
    let updated = TaskParser.line(for: t, assigningWorkspace: "nuovo-progetto.canvas")
    #expect(updated == "- [ ] Verifica disegno ^[[nuovo-progetto.canvas]]")
    #expect(
        updated.components(separatedBy: "^[[").count - 1 == 1,
        "più di un marcatore Workspace sulla riga: \(updated)"
    )
}

@Test func assigningNilWorkspaceClearsTheMarkerWithNoDoubleSpaceLeftBehind() {
    let t = task("- [ ] Verifica disegno ^[[vibrofer-emea.canvas]] >2026-09-01")
    let updated = TaskParser.line(for: t, assigningWorkspace: nil)
    #expect(updated == "- [ ] Verifica disegno >2026-09-01")
    #expect(!updated.contains("  "), "doppio spazio lasciato dalla rimozione: \(updated)")
}

@Test func assigningNilWorkspaceOnATrailingMarkerLeavesNoTrailingWhitespace() {
    let t = task("- [ ] Verifica disegno ^[[vibrofer-emea.canvas]]")
    let updated = TaskParser.line(for: t, assigningWorkspace: nil)
    #expect(updated == "- [ ] Verifica disegno")
}

@Test func assigningWorkspaceLeavesEveryOtherPartOfTheLineByteIdentical() {
    // Indentation, bullet, `>`/`!`/`@` markers and a plain wikilink all survive
    // untouched; only the Workspace marker's target changes.
    let original = "  * [ ] Task complesso >2026-09-01 !2026-09-10 @remind(2026-09-01 09:00)"
        + " [[Nota]] ^[[vecchio.canvas]]"
    let t = task(original)
    let updated = TaskParser.line(for: t, assigningWorkspace: "nuovo.canvas")
    #expect(
        updated == "  * [ ] Task complesso >2026-09-01 !2026-09-10 @remind(2026-09-01 09:00)"
            + " [[Nota]] ^[[nuovo.canvas]]"
    )
}

// MARK: - `TaskParser.insertingSubtask(in:below:draft:)` (ADR-0021 D9, A9; R-07)

@Test func insertingASubtaskAssignsAFreshIDToAParentThatHadNone() throws {
    let note = """
    - [ ] Progetto padre
    - [ ] Task non correlato
    """
    let tasks = TaskParser.tasks(in: note, sourcePath: "Progetto.md")
    let parent = try #require(tasks.first { $0.text == "Progetto padre" })
    #expect(parent.localID == nil)

    let updated = try #require(TaskParser.insertingSubtask(
        in: note, below: parent, draft: TaskParser.SubtaskDraft(text: "Misurare la rigidezza")
    ))

    let updatedTasks = TaskParser.tasks(in: updated, sourcePath: "Progetto.md")
    let updatedParent = try #require(updatedTasks.first { $0.text == "Progetto padre" })
    #expect(updatedParent.localID == 1)

    // Parent and child ids come from one scan (ADR-0021 D9): `nextLocalID` was 1 before
    // either write, so the parent takes it and the child takes 2.
    let child = try #require(updatedTasks.first { $0.text == "Misurare la rigidezza" })
    #expect(child.parentLocalID == 1)
    #expect(child.localID == 2)
}

@Test func insertingASubtaskLeavesAnExistingParentIDUntouched() throws {
    let note = """
    - [ ] Progetto padre ^id(2)
    - [ ] Altro task
    """
    let tasks = TaskParser.tasks(in: note, sourcePath: "Progetto.md")
    let parent = try #require(tasks.first { $0.localID == 2 })

    let updated = try #require(TaskParser.insertingSubtask(
        in: note, below: parent, draft: TaskParser.SubtaskDraft(text: "Sotto-task")
    ))

    // The parent's own line is byte-identical, not merely equal in meaning.
    let lines = updated.components(separatedBy: "\n")
    #expect(lines[parent.lineIndex] == parent.rawLine)

    let updatedTasks = TaskParser.tasks(in: updated, sourcePath: "Progetto.md")
    let child = try #require(updatedTasks.first { $0.text == "Sotto-task" })
    #expect(child.parentLocalID == 2)
    // R-07: "creates a new task line with an auto-assigned `^id`" - always, whether or
    // not the parent needed one assigned too.
    #expect(child.localID == 3)
}

@Test func insertingASubtaskPlacesItImmediatelyBelowIndentedTwoSpacesPastTheParent() throws {
    let note = """
    - [ ] Progetto padre
    - [ ] Task successivo, non deve spostarsi
    """
    let tasks = TaskParser.tasks(in: note, sourcePath: "Progetto.md")
    let parent = try #require(tasks.first { $0.text == "Progetto padre" })

    let updated = try #require(TaskParser.insertingSubtask(
        in: note, below: parent, draft: TaskParser.SubtaskDraft(text: "Sotto-task")
    ))

    let lines = updated.components(separatedBy: "\n")
    #expect(lines.count == 3)
    #expect(lines[0].hasPrefix("- [ ] Progetto padre"))
    #expect(lines[1].hasPrefix("  - [ ] Sotto-task"), "figlio non indentato di 2 spazi: \(lines[1])")
    #expect(lines[2] == "- [ ] Task successivo, non deve spostarsi")
}

@Test func insertingASubtaskIndentsRelativeToAnAlreadyIndentedParent() throws {
    // Parent-indent + 2, not a fixed 2: an already-nested parent pushes the child
    // further in (cosmetic only, never read back - the hierarchy is `^parent`).
    let note = "  - [ ] Progetto annidato"
    let tasks = TaskParser.tasks(in: note, sourcePath: "Progetto.md")
    let parent = try #require(tasks.first)

    let updated = try #require(TaskParser.insertingSubtask(
        in: note, below: parent, draft: TaskParser.SubtaskDraft(text: "Sotto-task")
    ))

    let lines = updated.components(separatedBy: "\n")
    #expect(lines[1].hasPrefix("    - [ ] Sotto-task"), "indentazione errata: \(lines[1])")
}

@Test func insertingASubtaskCarriesTheDraftsOwnDatesIndependentOfTheParents() throws {
    let note = "- [ ] Progetto padre >2026-09-01 !2026-09-05"
    let tasks = TaskParser.tasks(in: note, sourcePath: "Progetto.md")
    let parent = try #require(tasks.first)

    let draft = TaskParser.SubtaskDraft(
        text: "Sotto-task",
        scheduled: CalendarDate(iso: "2026-10-01"),
        due: CalendarDate(iso: "2026-10-05"),
        reminder: TaskReminder(date: CalendarDate(iso: "2026-10-01")!, hour: 9, minute: 0),
        recurrence: TaskRecurrence(completed: 0, total: 2)
    )
    let updated = try #require(TaskParser.insertingSubtask(in: note, below: parent, draft: draft))

    let updatedTasks = TaskParser.tasks(in: updated, sourcePath: "Progetto.md")
    let child = try #require(updatedTasks.first { $0.text.contains("Sotto-task") })
    #expect(child.scheduled == CalendarDate(iso: "2026-10-01"))
    #expect(child.due == CalendarDate(iso: "2026-10-05"))
    #expect(child.reminder == TaskReminder(date: CalendarDate(iso: "2026-10-01")!, hour: 9, minute: 0))
    #expect(child.recurrence == TaskRecurrence(completed: 0, total: 2))

    // The parent's own dates are untouched: the two are independent (R-07's last clause).
    let updatedParent = try #require(updatedTasks.first { $0.text == "Progetto padre" })
    #expect(updatedParent.scheduled == CalendarDate(iso: "2026-09-01"))
    #expect(updatedParent.due == CalendarDate(iso: "2026-09-05"))
}

@Test func insertingASubtaskReturnsNilWhenTheParentLineHasMovedOn() {
    // Same guard style as `TaskParser.rewrite(_:at:expecting:with:)`
    // (`Sources/Core/Tasks/TaskParser.swift:303`): a `TaskItem` captured before the
    // note changed under it must not blindly insert against a line index that no
    // longer holds the line it was read from.
    let originalNote = "- [ ] Progetto padre"
    let staleParent = TaskParser.tasks(in: originalNote, sourcePath: "Progetto.md")[0]

    let changedNote = "- [ ] Progetto padre rinominato"
    let result = TaskParser.insertingSubtask(
        in: changedNote, below: staleParent, draft: TaskParser.SubtaskDraft(text: "Sotto-task")
    )
    #expect(result == nil)
    #expect(changedNote == "- [ ] Progetto padre rinominato", "il testo stale non deve cambiare")
}

@Test func insertingASubtaskLeavesEveryOtherLineFrontmatterAndTrailingNewlineByteIdentical() throws {
    // The parent already carries `^id(5)`, so its own line is byte-identical too - this
    // test isolates "the rest of the note is untouched" from "the parent may gain an
    // id", which is asserted on its own above.
    let note = """
    ---
    date: 2026-08-11
    tags:
      - type-note
    ---

    Corpo con testo libero.

    - [ ] Non correlato
    - [ ] Progetto padre ^id(5)
    - [ ] Successivo

    """
    let tasks = TaskParser.tasks(in: note, sourcePath: "Progetto.md")
    let parent = try #require(tasks.first { $0.localID == 5 })

    let updated = try #require(TaskParser.insertingSubtask(
        in: note, below: parent, draft: TaskParser.SubtaskDraft(text: "Sotto-task")
    ))

    let originalLines = note.components(separatedBy: "\n")
    let updatedLines = updated.components(separatedBy: "\n")

    // Exactly one line was inserted.
    #expect(updatedLines.count == originalLines.count + 1)
    // Frontmatter and every line up to and including the parent's own are untouched.
    #expect(Array(updatedLines[0...parent.lineIndex]) == Array(originalLines[0...parent.lineIndex]))
    // The tail after the inserted child matches the original tail exactly, including
    // the empty trailing element `components(separatedBy:)` produces for a trailing
    // newline.
    #expect(
        Array(updatedLines[(parent.lineIndex + 2)...]) == Array(originalLines[(parent.lineIndex + 1)...])
    )
}

// MARK: - R-09: no completion cascade, in either direction

@MainActor
@Test func completingEveryChildLeavesTheParentByteIdenticalWithNoAutoDoneWrite() async throws {
    let vault = try TemporaryVault()
    try vault.write(
        """
        ---
        date: 2026-08-11
        tags:
          - type-note
        ---

        - [ ] Progetto padre ^id(1)
        - [ ] Figlio uno ^parent(1)
        - [ ] Figlio due ^parent(1)
        """,
        to: "Progetto.md"
    )
    let session = VaultSession(
        root: vault.root,
        stateBase: vault.stateBase,
        bundledVocabulary: Bundle.pergamenumResources.url(forResource: "vocabolari", withExtension: "json")
    )
    await session.rescan()

    let parentBefore = try #require(session.index.allTasks.first { $0.localID == 1 })
    #expect(!parentBefore.rawLine.contains("@done"))

    let children = session.index.allTasks.filter { $0.parentLocalID == 1 }
    #expect(children.count == 2)

    for child in children {
        guard case .written = await session.apply(.state(.done), to: child) else {
            Issue.record("la scrittura del figlio non è avvenuta: \(session.problems)")
            return
        }
    }

    // Every child is now done…
    let doneChildren = session.index.allTasks.filter { $0.parentLocalID == 1 }
    #expect(doneChildren.allSatisfy { $0.state == .done })

    // …and the parent's own line never moved: no `@done` cascade (ADR-0021 D5, R-09).
    let parentAfter = try #require(session.index.allTasks.first { $0.localID == 1 })
    #expect(parentAfter.rawLine == parentBefore.rawLine, "il padre non è rimasto invariato")
    #expect(!parentAfter.rawLine.contains("@done"))
}
