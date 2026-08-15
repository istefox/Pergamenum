import Foundation

/// Tasks as the app asks for them.
///
/// The rewriting is on `VaultSession` (ADR-0007 §D3). What is left here is what only
/// an app has: an editor that may be showing the note a task lives in, a selection the
/// menu commands act on, and the counter that reschedules reminders.
extension VaultController {
    /// The task types keep the names the views and the tests already use.
    typealias TaskChange = VaultSession.TaskChange
    typealias TaskDestination = VaultSession.TaskDestination
    typealias TaskDraft = VaultSession.TaskDraft

    /// Completes, reopens, cancels or reschedules a task by rewriting its source line.
    @discardableResult
    func apply(_ change: TaskChange, to task: TaskItem) -> Bool {
        guard let session else { return false }
        switch session.apply(change, to: task) {
        case .written(let result):
            syncOpenNote(with: result)
            recordTaskWrite()
            return true
        case .stale:
            // The index disagreed with the file. A rescan is the only way back to
            // agreement, and asking the user again is better than guessing.
            Task { await rescan() }
            return false
        case .unchanged, .failed:
            // A task rewrite has nothing it can decline to do, so `unchanged` cannot
            // arrive here; it is spelled out rather than defaulted so that adding a
            // case to the outcome stops the compiler here again.
            return false
        }
    }

    /// Reschedules the selected task by whole days from today, or clears its date.
    @discardableResult
    func rescheduleSelectedTask(daysFromToday: Int?) -> Bool {
        guard let task = selectedTask else { return false }
        let date = daysFromToday.map { CalendarDate.today.adding(days: $0) }
        let changed = apply(.schedule(date), to: task)
        if changed {
            // Re-resolve the task so a second shortcut acts on the rewritten line
            // rather than the stale one it replaced.
            selectedTask = index.allTasks.first { $0.sourcePath == task.sourcePath && $0.text == task.text }
        }
        return changed
    }

    /// Toggles between open and done, which is what a checkbox click means.
    @discardableResult
    func toggle(_ task: TaskItem) -> Bool {
        apply(.state(task.state == .done ? .open : .done), to: task)
    }

    /// Opens the composer on a destination, defaulting to the inbox.
    func beginTaskCapture(into destination: TaskDestination = .inbox) {
        taskDraft = TaskDraft(destination: destination)
    }

    /// Quick capture (SPEC §7.4): appends the composed task to its destination note,
    /// creating the inbox note if it is not there yet.
    @discardableResult
    func captureTask(_ draft: TaskDraft) -> Bool {
        guard let session, let result = session.captureTask(draft) else { return false }
        syncOpenNote(with: result)

        // The block comes after the task line is safely written: a block for a task
        // that failed to be captured is a plan for work nobody recorded.
        if draft.blocksTheDay, let slot = draft.blockSlot {
            addTimeBlock(title: draft.text, on: slot.day, startMinutes: slot.time.minutes)
        }

        lastCapture = draft
        recordTaskWrite()
        return true
    }

    /// Quick capture of a bare line, with no date and no destination but the inbox.
    @discardableResult
    func captureTask(_ text: String) -> Bool {
        captureTask(TaskDraft(text: text))
    }

    /// Reads the last capture once, so the Attività pane can show the view the new
    /// task actually landed in rather than leaving the user looking at an empty list.
    func consumeLastCapture() -> TaskDraft? {
        defer { lastCapture = nil }
        return lastCapture
    }
}
