import Foundation
import Testing
@testable import Pergamenum

/// `CommandActions` was an extraction, not a rewrite (M8).
///
/// Every action in it used to be a closure inside a `Button` in the menu bar, and every
/// `canRun` used to be a `.disabled(...)` beside it. An extraction that quietly changes
/// one of those is the worst kind of refactor: the menus still look right, and a command
/// is enabled or disabled at the wrong moment. This file is the negative control - it
/// asserts the conditions the menu bar had, on a controller with nothing open.

@MainActor
private func actions() -> CommandActions {
    let vault = VaultController()
    let calendar = EventKitStore()
    let capture = CaptureController()
    return CommandActions(
        navigation: Navigation(),
        vault: vault,
        day: DayController(store: calendar, vault: vault),
        calendar: calendar,
        capturePanel: CapturePanel(
            controller: capture,
            session: { vault.session },
            theme: { ThemeEngine().current },
            shortcutCaption: { nil }
        ),
        history: NavigationHistory()
    )
}

@MainActor
@Test func withNoVaultOpenTheCommandsThatNeedOneAreRefused() {
    let actions = actions()
    // Exactly the set the File and Vista menus disabled on `vault.root == nil`.
    for command: ShortcutCommand in [
        .newNote, .newBoard, .dailyNote, .quickTask, .globalCapture, .quickLook,
        .globalSearch, .quickSwitcher, .runConformanceCheck,
    ] {
        #expect(!actions.canRun(command), "«\(command.title)» dovrebbe essere spenta senza vault")
    }
}

@MainActor
@Test func withNoNoteOpenTheCommandsThatActOnOneAreRefused() {
    let actions = actions()
    for command: ShortcutCommand in [.copyLink, .revealInFinder, .insertRelated, .readingMode] {
        #expect(!actions.canRun(command), "«\(command.title)» dovrebbe essere spenta senza nota")
    }
    // `save` is stricter than the others and always was: an open note with nothing
    // changed does not enable it either.
    #expect(!actions.canRun(.save))
}

@MainActor
@Test func withNothingVisitedYetBothArrowsAreRefused() {
    let actions = actions()
    // The wiring, not the history: `NavigationHistoryTests` owns the rules. What this asserts
    // is that the menu asks the history at all - an «Indietro» that is always enabled and does
    // nothing is the same broken promise as an entry pointing at a note that is gone.
    #expect(!actions.canRun(.goBack))
    #expect(!actions.canRun(.goForward))
}

@MainActor
@Test func withNoTaskSelectedOnlyTheToggleIsRefused() {
    let actions = actions()
    #expect(!actions.canRun(.taskToggle))

    // And here is the asymmetry, recorded rather than fixed: the four rescheduling
    // commands act on the selected task and carry no `.disabled` in the Task menu, so
    // they answer true with nothing selected. Making them stricter would be a behaviour
    // change hidden inside an extraction; it is a separate decision with its own reason.
    for command: ShortcutCommand in [.taskToday, .taskTomorrow, .taskPlusTwo, .taskNextWeek] {
        #expect(actions.canRun(command), "«\(command.title)» ha cambiato comportamento nell'estrazione")
    }
}

@MainActor
@Test func theCommandsThatNeverDependOnAnythingAreAlwaysAvailable() {
    let actions = actions()
    for command: ShortcutCommand in [
        .openVault, .pastePlain, .findInNote, .replaceInNote, .insertWikilink,
        .paneNotes, .paneWorkspace, .paneToday, .paneTasks, .paneConformance, .paneDiary,
        .previousDay, .nextDay,
    ] {
        #expect(actions.canRun(command), "«\(command.title)» è diventata condizionata")
    }
}

@MainActor
@Test func theCalendarCommandsFollowTheAccessAndNotTheVault() {
    // Without a granted EventKit access these two are off, exactly as the Calendario
    // menu had them, and opening a vault does not change that.
    let actions = actions()
    #expect(actions.canRun(.newEvent) == actions.calendar.eventAccess.isGranted)
    #expect(actions.canRun(.newReminder) == actions.calendar.reminderAccess.isGranted)
}

@MainActor
@Test func everyCommandInTheCatalogueHasAnAnswer() {
    // `canRun` is total by construction - the switch is exhaustive - and this is what
    // makes the slash menu's filter safe to apply to `allCases`. It also fails to
    // compile, rather than at run time, if a command is added and forgotten.
    let actions = actions()
    for command in ShortcutCommand.allCases {
        _ = actions.canRun(command)
    }
    #expect(ShortcutCommand.allCases.count > 0)
}

@MainActor
@Test func newBoardSwitchesToWorkspaceAndRaisesThePendingFlag() {
    let actions = actions()
    actions.run(.newBoard)
    #expect(actions.navigation.pane == .workspace)
    #expect(actions.vault.consumePendingNewBoard())
    // Consumed once: the Workspace reads it on appear and on change, never twice.
    #expect(!actions.vault.consumePendingNewBoard())
}

// MARK: - ADR-0021 (plan 2026-08-24-workspace-tasks-notes-integration), Task 9
//
// "Aggiungi sotto-task" (UX blueprint's menu bar map): reachable only with a task
// selected, and running it opens the composer already pointed at that task as the
// parent - `vault.taskDraft` non-nil is what `RootView` reads to show the composer
// sheet at all (`RootView.swift`), so asserting `taskDraft?.parent` is asserting the
// state a person would see, not a pixel.

private func makeTask(_ line: String = "- [ ] Capofila", sourcePath: String = "x.md") -> TaskItem {
    TaskParser.parse(line: line, sourcePath: sourcePath, lineIndex: 0)!
}

@MainActor
@Test func addSubtaskIsRefusedWithNoTaskSelectedAndOfferedWithOne() {
    let actions = actions()
    #expect(!actions.canRun(.taskAddSubtask))

    actions.vault.selectedTask = makeTask()
    #expect(actions.canRun(.taskAddSubtask))
}

@MainActor
@Test func runningAddSubtaskOpensTheComposerWithTheSelectedTaskAsParent() {
    let actions = actions()
    let parent = makeTask()
    actions.vault.selectedTask = parent

    actions.run(.taskAddSubtask)

    #expect(actions.vault.taskDraft?.parent == parent)
}

@MainActor
@Test func switchingPaneIsTheOneActionSafeToRunWithNothingOpen() {
    // The only `run` a test can exercise without touching the file system, a panel or
    // EventKit - and it proves the pane lookup in `run` finds the right one rather than
    // silently doing nothing.
    let actions = actions()
    for pane in Navigation.Pane.allCases {
        actions.run(pane.shortcut)
        #expect(actions.navigation.pane == pane, "«\(pane.title)» non è stato raggiunto")
    }
}
