import Foundation
import Testing
@testable import Pergamenum

// ADR-0095 §D3 and §D4 (planned), plan docs/plans/no-whole-note-term-on-the-update-path-pg-406.md, Task 2
// (PG-406). R-08: typing restarts the pause, the pause settles the unsaved marks of every tab in every
// column, and save, close and quit never wait for it.
//
// The pause is a `ManualPauseScheduler` fired by hand, so no test waits on a timer (ADR-0043 §D9); the one
// exception is `taskPauseSchedulerRunsTheLastActionOnceAfterTheInterval`, which is the timer's own test.

private let original = "---\ndate: 2026-10-13\ntags:\n  - type-note\n---\n\nCorpo.\n"
private let edited = original + "Un'altra riga.\n"
private let editedElsewhere = original + "Scritta nell'altra colonna.\n"

/// A controller over a vault with one note, `A.md`, and the pause the caller passes. The watcher is
/// stopped, so the only reconciliation a test sees is one it calls itself.
@MainActor
private func controller(_ vault: borrowing TemporaryVault, pause: some PauseScheduler) async throws -> VaultController {
    try vault.write(original, to: "A.md")
    let controller = VaultController(recents: .volatile(), openTabs: .volatile(), typingPause: pause)
    await controller.open(vault.root)
    controller.watcher?.stop()
    controller.watcher = nil
    controller.openNote(at: "A.md")
    return controller
}

/// Counts what a real `TaskPauseScheduler` ran, by label.
@MainActor
private final class Ran {
    var labels: [String] = []
}

@MainActor
@Suite struct UnsavedMarkPauseTests {
    @Test func typingRestartsThePause() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }

        controller.updateOpenNoteText(original + "1")
        controller.updateOpenNoteText(original + "12")
        controller.updateOpenNoteText(original + "123")

        #expect(pause.restarts == 3)
        #expect(pause.isPending)
        #expect(controller.unsavedMarkChecks == 0, "a keystroke ran the exact compare")
    }

    @Test func firingThePauseClearsAnUndoneBuffer() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }

        controller.updateOpenNoteText(edited)
        controller.updateOpenNoteText(original)
        #expect(controller.openNote?.hasUnsavedChanges == true, "the mark went off before the pause")

        pause.fire()

        #expect(controller.openNote?.hasUnsavedChanges == false)
        #expect(controller.unsavedMarkChecks == 1)
    }

    @Test func firingThePauseLeavesADirtyBufferAsItWas() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }
        controller.updateOpenNoteText(edited)
        let before = controller.columns

        pause.fire()

        #expect(controller.columns == before)
        #expect(controller.openNote?.hasUnsavedChanges == true)
        #expect(controller.openNote?.text == edited)
    }

    @Test func thePauseSettlesEveryColumn() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }
        controller.splitEditor()
        try #require(controller.columns.count == 2)
        try #require(controller.focusedColumnIndex == 1)

        // Column 1: typed and undone back. Column 0: typed and left dirty.
        controller.updateOpenNoteText(edited)
        controller.updateOpenNoteText(original)
        controller.focusColumn(0)
        controller.updateOpenNoteText(editedElsewhere)
        try #require(controller.columns[1].tabs.first?.note.hasUnsavedChanges == true, "the mark went off before the pause")

        pause.fire()

        #expect(controller.columns[1].tabs.first?.note.hasUnsavedChanges == false)
        #expect(controller.columns[0].tabs.first?.note.hasUnsavedChanges == true)
        #expect(controller.columns[0].tabs.first?.note.text == editedElsewhere)
        #expect(controller.unsavedMarkChecks == 2, "one exact compare for each tab whose mark was on")
    }

    // Green today: a save links the revisions at once (ADR-0095 §D3) and never needs the pause.
    @Test func aSaveClearsTheMarkWithoutThePause() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }
        controller.updateOpenNoteText(edited)
        try #require(controller.openNote?.hasUnsavedChanges == true)

        await controller.saveOpenNote()

        #expect(controller.openNote?.hasUnsavedChanges == false)
        #expect(controller.unsavedMarkChecks == 0)
        #expect(quitOnDisk(vault.root, "A.md") == edited)
    }

    // Save, close and quit decide on the exact answer (ADR-0095 §D3, ADR-0073 departure 15): a buffer
    // undone back to its saved text is clean for all three before the pause has run.
    @Test func closeAndQuitDecideOnTheExactAnswer() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }
        let id = try #require(controller.focusedTab?.id)
        controller.updateOpenNoteText(edited)
        controller.updateOpenNoteText(original)
        try #require(pause.isPending, "the pause already ran")

        #expect(QuitReview(columns: controller.columns).isEmpty)
        #expect(await controller.saveTab(id) == .clean)
        controller.requestCloseFocusedTab()
        #expect(controller.closeRequest == nil, "a clean buffer raised the close dialog")
        #expect(controller.tab(withID: id) == nil)
        #expect(controller.unsavedMarkChecks == 0, "the decision went through the pause check")
    }

    // A settle left pending would walk the columns of a vault that is gone: closing the vault and
    // switching to another one both drop it.
    @Test func closingTheVaultCancelsThePause() async throws {
        let vault = try TemporaryVault()
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        controller.updateOpenNoteText(edited)
        try #require(pause.isPending)

        controller.close()

        #expect(!pause.isPending, "the settle survived the close")
    }

    @Test func switchingVaultCancelsThePause() async throws {
        let vault = try TemporaryVault()
        let other = try TemporaryVault()
        try other.write(original, to: "B.md")
        let pause = ManualPauseScheduler()
        let controller = try await controller(vault, pause: pause)
        defer { controller.close() }
        // Typed and undone back: clean by the exact answer, so the switch asks nothing.
        controller.updateOpenNoteText(edited)
        controller.updateOpenNoteText(original)
        try #require(pause.isPending)

        let switched = await controller.switchVault(to: other.root) { _ in .cancel }

        #expect(switched)
        #expect(!pause.isPending, "the settle survived the vault switch")
    }

    // The timer's own test, the one place a test waits on the clock: three restarts inside the
    // interval run the third action once and neither of the others.
    @Test func taskPauseSchedulerRunsTheLastActionOnceAfterTheInterval() async throws {
        let scheduler = TaskPauseScheduler(interval: .milliseconds(20))
        let ran = Ran()

        scheduler.restart { ran.labels.append("first") }
        scheduler.restart { ran.labels.append("second") }
        scheduler.restart { ran.labels.append("third") }

        let deadline = ContinuousClock.now + .seconds(2)
        while ran.labels.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ran.labels == ["third"])

        try await Task.sleep(for: .milliseconds(100))
        #expect(ran.labels == ["third"], "the pause ran again after it had fired")
    }
}
