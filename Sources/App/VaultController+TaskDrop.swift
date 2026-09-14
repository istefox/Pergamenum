import Foundation

/// What the app adds to the session's drop: the index that turns a dragged row back into a task,
/// the daily note an hour drop also touches, and the editor that may be showing either of them.
extension VaultController {
    /// A task dragged onto a day of the week or the month, or onto an hour of the timeline
    /// (ADR-0013 §D5).
    ///
    /// The task is resolved from the index by its file and its line, which is the same pair the
    /// dragged row carried: a row drawn from a scan that has since moved on resolves to nothing
    /// and is refused by name, rather than rewriting whatever now sits on that line.
    ///
    /// One write, which is the whole of §D5's promise: the `>` marker in the task's own file.
    /// The block an hour drop also asks for is written by `DayController`, because a block lives
    /// in the daily note and belongs to the day on screen rather than to the task - and because
    /// only the marker is journalled, so «Annulla» puts the task back where it was and leaves
    /// the block for the person to remove. Taking one away silently is not what undoing a move
    /// means.
    @discardableResult
    func dropTask(
        sourcePath: String, lineIndex: Int, on day: CalendarDate, at time: TaskTime? = nil
    ) async -> VaultSession.TaskDropOutcome {
        var outcome = VaultSession.TaskDropOutcome(path: sourcePath)
        guard let session else { return outcome }
        guard let task = task(at: sourcePath, line: lineIndex) else {
            outcome.problem = "il task non è più dove risultava: \(sourcePath)"
            return outcome
        }

        outcome = await session.moveTask(task, to: day, at: time)
        guard outcome.didWrite else { return outcome }

        if let result = outcome.result { syncOpenNote(with: result) }
        // A write the app made itself does not come back through the watcher (ADR-0001), so the
        // views that count tasks are told here. Without it the row stays on the day it left.
        recordTaskWrite()
        Task { await rescan() }
        return outcome
    }

    /// The task a dragged row named, or nil when the index has moved on since it was drawn.
    func task(at sourcePath: String, line lineIndex: Int) -> TaskItem? {
        index.allTasks.first { $0.sourcePath == sourcePath && $0.lineIndex == lineIndex }
    }
}
