import AppKit
import Foundation
import Testing
@testable import Pergamenum

// ADR-0023: A command is named once and rendered twice.
// Plan: docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md, Task 5.
//
// The note row's own Copia link, Cronologia and Applica template (cluster 2, R-03/R-04):
// today these three exist only as menu-bar items acting on "the open note". The context
// menu adds a second entry point on a row that is not necessarily open - "Apri la nota,
// poi esegui l'azione" (SPEC Architecture) - so `CommandActions` gains `run(_:on:)` and
// `canRun(_:on:)`, additive overloads beside the existing `run(_:)`/`canRun(_:)`.
//
// RED (Task 5): `CommandActions.run(_:on:)` is a stub with an empty body and
// `CommandActions.canRun(_:on:)` is a stub that always returns `false`, so every
// assertion below fails on its assertion, not on a build error - except the negative
// control, which the empty-body stub already satisfies (a no-op cannot open a note
// either) and stays as the regression it is meant to be once GREEN lands.

@MainActor
private func makeActions(vault root: URL) async -> CommandActions {
    let vault = VaultController(recents: .volatile(), openTabs: .volatile())
    await vault.open(root)
    let calendarStore = EventKitStore()
    let capture = CaptureController()
    return CommandActions(
        navigation: Navigation(),
        vault: vault,
        day: DayController(store: calendarStore, vault: vault),
        calendar: calendarStore,
        capturePanel: CapturePanel(
            controller: capture,
            session: { vault.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory(),
        pasteboard: .volatile()
    )
}

private let noteA = """
---
date: 2026-08-25
tags:
  - type-note
---

Nota A.
"""

private let noteB = """
---
date: 2026-08-25
tags:
  - type-note
---

Nota B.
"""

// MARK: - R-04: acting on a row that is not the open note opens it first, then acts

@MainActor
@Test func runningNoteHistoryOnAClosedRowOpensItThenShowsHistory() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    try vault.write(noteB, to: "b.md")
    let actions = await makeActions(vault: vault.root)
    actions.vault.openNote(at: "a.md")

    actions.run(.noteHistory, on: "b.md")

    #expect(actions.vault.openNote?.relativePath == "b.md")
    #expect(actions.vault.isShowingHistory)
}

@MainActor
@Test func runningApplyTemplateOnAClosedRowOpensItThenRaisesTheChooser() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    try vault.write(noteB, to: "b.md")
    let actions = await makeActions(vault: vault.root)
    actions.vault.openNote(at: "a.md")

    actions.run(.applyTemplate, on: "b.md")

    #expect(actions.vault.openNote?.relativePath == "b.md")
    #expect(actions.vault.isChoosingTemplate)
}

@MainActor
@Test func runningCopyLinkOnAClosedRowOpensItThenPutsItsLinkOnThePasteboard() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    try vault.write(noteB, to: "b.md")
    let actions = await makeActions(vault: vault.root)
    actions.vault.openNote(at: "a.md")

    actions.run(.copyLink, on: "b.md")

    #expect(actions.vault.openNote?.relativePath == "b.md")
    let link = try #require(PergamenumLink.note(path: "b.md"))
    #expect(actions.pasteboard.string(forType: .string) == link.absoluteString)
}

// MARK: - R-04: no implicit re-open on the note that is already open

@MainActor
@Test func runningNoteHistoryOnTheAlreadyOpenNoteDoesNotReopenIt() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)
    actions.vault.openNote(at: "a.md")
    let focusedID = actions.vault.focusedTab?.id

    actions.run(.noteHistory, on: "a.md")

    #expect(actions.vault.focusedTab?.id == focusedID)
}

// MARK: - R-03: canRun(_:on:) answers for a row without the note open first

@MainActor
@Test func applyTemplateCannotRunWithNoTemplatesFolder() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteB, to: "b.md")
    let actions = await makeActions(vault: vault.root)

    #expect(!actions.canRun(.applyTemplate, on: "b.md"))
}

@MainActor
@Test func applyTemplateCanRunOnceATemplatesFolderHoldsANote() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteB, to: "b.md")
    try vault.write(noteA, to: "Templates/Riunione.md")
    let actions = await makeActions(vault: vault.root)

    #expect(actions.canRun(.applyTemplate, on: "b.md"))
}

@MainActor
@Test func copyLinkAndNoteHistoryCanRunOnAnyRowWithNothingOpen() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteB, to: "b.md")
    let actions = await makeActions(vault: vault.root)

    #expect(actions.canRun(.copyLink, on: "b.md"))
    #expect(actions.canRun(.noteHistory, on: "b.md"))
}

// MARK: - Negative control: a command outside cluster 2 must not open the note

@MainActor
@Test func runOnANonNoteCommandDoesNotOpenTheNote() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteB, to: "b.md")
    let actions = await makeActions(vault: vault.root)

    actions.run(.newBoard, on: "b.md")

    #expect(actions.vault.openNote == nil)
}

// MARK: - Task 6 (ADR-0023 §D6, R-05): the task row's «Aggiungi sotto-task»
//
// `addSubtaskToSelectedTask`'s body turned into a value: `TaskDraft.subtask(of:)` sets
// `parent` and `destination` and nothing else, so the row's context menu and the Task
// menu's own key can both assign the same value instead of duplicating the construction.
//
// RED (Task 6): `TaskDraft.subtask(of:)` is a stub returning `Self()`, so every
// assertion below fails on its equality, not on a build error.

private func makeTask(_ line: String = "- [ ] Capofila", sourcePath: String = "x.md") -> TaskItem {
    TaskParser.parse(line: line, sourcePath: sourcePath, lineIndex: 0)!
}

@Test func subtaskDraftSetsOnlyParentAndDestinationEveryOtherFieldAtItsDefault() {
    let parent = makeTask(sourcePath: "Progetti/A.md")

    let draft = VaultController.TaskDraft.subtask(of: parent)

    var expected = VaultController.TaskDraft()
    expected.destination = .note(parent.sourcePath)
    expected.parent = parent
    #expect(draft == expected)
}

@MainActor
@Test func addingASubtaskFromTheRowAppliesTheSameDraftTheFactoryBuilds() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)
    let parent = makeTask(sourcePath: "a.md")
    actions.vault.selectedTask = parent

    actions.run(.taskAddSubtask)

    #expect(actions.vault.taskDraft == VaultController.TaskDraft.subtask(of: parent))
}

@MainActor
@Test func addingASubtaskWithNoTaskSelectedLeavesTheDraftNil() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)

    actions.run(.taskAddSubtask)

    #expect(actions.vault.taskDraft == nil)
}

// MARK: - ADR-0039: `TaskCommand`'s three actions, on `CommandActions`
//
// The breadcrumb's old defect (ADR-0039 §D1) was a navigation that changed state nobody
// was watching: `vault.openNote(at:)` alone, with no `navigation.pane` change, loads a
// note into a background tab that never comes forward. `.goToNote` closes that in the
// one place every surface now reads from.

@MainActor
@Test func goToNoteOpensTheSourceNoteAndBringsTheNotesPaneForward() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)
    actions.navigation.pane = .tasks
    let task = makeTask(sourcePath: "a.md")

    actions.run(.goToNote, on: task)

    #expect(actions.vault.openNote?.relativePath == "a.md")
    #expect(actions.navigation.pane == .notes)
}

@MainActor
@Test func linkBoardOffersTheTaskToTheWorkspacePickerThroughNavigation() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)
    let task = makeTask(sourcePath: "a.md")

    actions.run(.linkBoard, on: task)

    #expect(actions.navigation.taskPickingBoard == task)
}

@MainActor
@Test func goToBoardResolvesAUniqueBoardStraightToPendingCanvas() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    try vault.write("{}", to: "Progetti/vibrofer-emea.canvas")
    let actions = await makeActions(vault: vault.root)
    let task = makeTask("- [ ] Verifica ^[[vibrofer-emea.canvas]]", sourcePath: "a.md")

    actions.run(.goToBoard, on: task)

    #expect(actions.vault.routeState.pendingCanvas?.path == "Progetti/vibrofer-emea.canvas")
}

@MainActor
@Test func goToBoardOnAnAmbiguousFileNameOpensThePickerInstead() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    try vault.write("{}", to: "Progetti/vibrofer-emea.canvas")
    try vault.write("{}", to: "Archivio/vibrofer-emea.canvas")
    let actions = await makeActions(vault: vault.root)
    let task = makeTask("- [ ] Verifica ^[[vibrofer-emea.canvas]]", sourcePath: "a.md")

    actions.run(.goToBoard, on: task)

    #expect(actions.vault.routeState.pendingCanvas == nil)
    #expect(actions.navigation.taskPickingBoard == task)
}

@MainActor
@Test func goToBoardIsRefusedWithNoBoardAssignedButOfferedWithOne() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)

    #expect(!actions.canRun(.goToBoard, on: makeTask(sourcePath: "a.md")))
    #expect(actions.canRun(.goToBoard, on: makeTask("- [ ] Verifica ^[[x.canvas]]", sourcePath: "a.md")))
}

@MainActor
@Test func linkBoardAndGoToNoteAreAlwaysOffered() async throws {
    let vault = try TemporaryVault()
    try vault.write(noteA, to: "a.md")
    let actions = await makeActions(vault: vault.root)
    let task = makeTask(sourcePath: "a.md")

    #expect(actions.canRun(.linkBoard, on: task))
    #expect(actions.canRun(.goToNote, on: task))
}
