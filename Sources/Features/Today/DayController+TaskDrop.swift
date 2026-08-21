import Foundation

/// The drag that writes (ADR-0013 §D5), on the controller the three scales share.
///
/// Its own file because `DayController` is the day view's whole model and was already at
/// the length the linter allows a type to be: the drop is one subject and it moves
/// together, like the vault's own `VaultController+TaskDrop.swift` beside it.
extension DayController {
    /// A task dragged onto a day, and onto an hour of it when the drop pointed at one
    /// (ADR-0013 §D5).
    ///
    /// The task is read out of the index before the write and used after it, because the
    /// write leaves the index one scan behind: `addBlock` wants the task's text and its
    /// id, and both are what the row was drawn from.
    ///
    /// The block is written only on the day the timeline is showing, which is the only
    /// day an hour can be dropped on. A week column has no hours, so a drop there moves
    /// the task and blocks out nothing.
    @discardableResult
    func drop(_ payload: TaskDragPayload, on target: CalendarDate, at time: TaskTime? = nil) -> Bool {
        let task = vault.task(at: payload.path, line: payload.lineIndex)
        let outcome = vault.dropTask(
            sourcePath: payload.path, lineIndex: payload.lineIndex, on: target, at: time
        )

        if let problem = outcome.problem {
            lastDrop = Drop(summary: problem, journalID: nil, isRefusal: true)
            return false
        }
        if !outcome.introduced.isEmpty {
            let reasons = ConformanceText.lines(
                NoteViolations(
                    name: [], frontmatter: [], tags: outcome.introduced,
                    relatedMissingInSection: [], relatedMissingInFrontmatter: []
                )
            )
            lastDrop = Drop(
                summary: "Non spostato: \(reasons.joined(separator: ", "))",
                journalID: nil,
                isRefusal: true
            )
            return false
        }
        guard outcome.didWrite else { return false }

        if let time, let task, target == day {
            _ = addBlock(from: task, preferredStart: time.minutes)
        }
        reload()
        lastDrop = Drop(
            summary: "Spostato al \(target.italianForm)" + (time.map { ", \($0.text)" } ?? ""),
            journalID: outcome.journalID,
            isRefusal: false
        )
        return true
    }

    /// Puts back what the last drop wrote. The block an hour drop added stays: it is a
    /// thing on a day now, and removing it silently would undo more than the move.
    @discardableResult
    func undoLastDrop() -> Bool {
        guard let id = lastDrop?.journalID else { return false }
        let undone = vault.undoJournalledWrites([id]).failures.isEmpty
        lastDrop = nil
        if undone { reload() }
        return undone
    }
}
