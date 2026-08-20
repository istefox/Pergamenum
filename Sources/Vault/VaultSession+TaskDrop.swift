import Foundation

/// The second write a gesture makes (ADR-0013 §D5): a task dragged onto a day, or onto an hour.
///
/// It is the board's drop with a different marker, and deliberately so. One task, one file, one
/// write, through `VaultSession.write`, with the journal armed for the length of the gesture and
/// disarmed after - the narrowing of ADR-0007 §D6 that ADR-0012 §D7 took for the tag rename and
/// ADR-0009 §D5 for the board. **No dry run**: a drag that asked for confirmation would not be a
/// drag, and the line the gesture leaves behind carries the way back instead.
///
/// The differential conformance guard is here for the same reason it is on the board: what the
/// note already fails is not the gesture's fault, what the gesture would introduce is refused
/// with the reason. **On this gesture it is structurally silent, and that was measured rather
/// than assumed**: `NoteViolations` judges the name, the frontmatter, the tags and the related
/// section, and a `>` marker rewritten on a body line touches none of the four. It is kept
/// because a third gesture will be measured against this one, and discovering then that the
/// second dropped the guard is worse than a check that never fires.
///
/// Not in `sharedSources`, so neither connector compiles it: a drag is a gesture, and the
/// command line already has `task reschedule` with its own arguments and its own dry run.
extension VaultSession {
    /// What a drop did, or why it did nothing.
    struct TaskDropOutcome: Sendable, Equatable {
        var path: String
        /// The journal id, when something was written. `undoJournalledWrites` takes it back.
        var journalID: String?
        /// The violations the drop would have introduced. Empty when it went through.
        var introduced: [TagViolation] = []
        /// Set when the refusal is not about conformance: a line that moved, a file that would
        /// not read.
        var problem: String?
        /// What was written, so a caller with the editor open on that note can put it back in
        /// step without reading the file a second time.
        var result: WriteResult?

        var didWrite: Bool { journalID != nil }
    }

    /// Moves a task to a day, and to an hour on it when the drop pointed at one.
    ///
    /// `time` nil is a drop on a day: the hour is dropped with the day it belonged to, which is
    /// the rule `TaskParser.line(for:scheduledOn:)` already carries. The block an hour drop
    /// needs is not written here - it belongs to the daily note rather than to the task's own
    /// file, and one write per gesture is the point of §D5.
    func moveTask(_ task: TaskItem, to day: CalendarDate, at time: TaskTime? = nil) -> TaskDropOutcome {
        var outcome = TaskDropOutcome(path: task.sourcePath)
        guard task.scheduled != day || task.scheduledTime != time else { return outcome }

        guard let existing = try? read(task.sourcePath) else {
            outcome.problem = "non riesco a leggere \(task.sourcePath)"
            return outcome
        }

        // Computed here to be judged, and computed again inside `apply` to be written. The
        // duplication buys the one thing worth more than it: a single write path, so a task
        // moved by a drag and a task moved by the menu cannot drift apart.
        let newLine = TaskParser.line(for: task, scheduledOn: day, at: time)
        guard let rewritten = TaskParser.rewrite(
            existing.text, at: task.lineIndex, expecting: task.rawLine, with: newLine
        ) else {
            outcome.problem = "il task non è più dove risultava: \(task.sourcePath)"
            return outcome
        }
        guard rewritten != existing.text else { return outcome }

        let before = violations(path: task.sourcePath, title: existing.record.title, text: existing.text)
        let after = violations(path: task.sourcePath, title: existing.record.title, text: rewritten)
        let introduced = after.tags.filter { !before.tags.contains($0) }
        guard introduced.isEmpty else {
            outcome.introduced = introduced
            return outcome
        }

        let journal = WriteJournal(root: root)
        let entriesBefore = Set(journal.entries().map(\.id))
        let previousJournal = self.journal
        let previousCommand = journalCommand
        self.journal = journal
        journalCommand = "drag → \(day)" + (time.map { " \($0.text)" } ?? "")
        defer {
            self.journal = previousJournal
            journalCommand = previousCommand
        }

        let change: TaskChange = time.map { .scheduleAt(day, $0) } ?? .schedule(day)
        switch apply(change, to: task) {
        case .written(let result):
            outcome.result = result
            outcome.journalID = journal.entries().first { !entriesBefore.contains($0.id) }?.id
        case .stale:
            outcome.problem = "il task non è più dove risultava: \(task.sourcePath)"
        case .unchanged, .failed:
            outcome.problem = "non riesco a scrivere \(task.sourcePath)"
        }
        return outcome
    }
}
