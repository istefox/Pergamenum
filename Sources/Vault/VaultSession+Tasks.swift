import Foundation

/// Tasks as SPEC §7 defines them: every change is a rewrite of the markdown line the
/// task lives on, and nothing about a task is stored anywhere else.
extension VaultSession {
    enum TaskChange: Sendable {
        case state(TaskItem.State)
        case schedule(CalendarDate?)
        case due(CalendarDate?)
        /// A day *and* the hour on it, which only a gesture that pointed at an hour can
        /// mean. Separate from `schedule` because `TaskParser` already draws the line:
        /// "domani" said by a reschedule command is a day and not a time, and carrying
        /// an hour onto it would invent one.
        case scheduleAt(CalendarDate, TaskTime)
        case link(String)
        /// Assigns or clears the task's Workspace marker `^[[<canvas>.canvas]]`
        /// (ADR-0021 D9). Replaces any existing marker rather than appending a second.
        case workspace(String?)
    }

    /// Where a captured task is written (SPEC §7.4).
    ///
    /// The inbox note is created on demand because it is the destination the app
    /// chooses by default; any other note has to exist already, since inventing a note
    /// from a task composer is how a vault fills with files nobody meant to create.
    enum TaskDestination: Hashable, Sendable {
        case inbox
        case note(String)

        static let inboxPath = "00 Inbox/Capture.md"

        var relativePath: String {
            switch self {
            case .inbox: Self.inboxPath
            case .note(let path): path
            }
        }
    }

    /// A task being composed: its text, where it goes, and its three dates.
    struct TaskDraft: Equatable, Sendable {
        var text = ""
        var destination = TaskDestination.inbox
        /// `>YYYY-MM-DD`, the day it surfaces on.
        var scheduled: CalendarDate?
        /// The hour on that day, when the panel set one (ADR-0004).
        var scheduledTime: TaskTime?
        /// `!YYYY-MM-DD`, past which it is late.
        var due: CalendarDate?
        /// The hour it is due at, when the panel set one.
        var dueTime: TaskTime?
        /// Whether the task also becomes a block on its day's timeline.
        ///
        /// Only ever true with an hour to put it at: a block is a span of a day, and a
        /// date with no time says nothing about where on the day it goes.
        var blocksTheDay = false
        /// `@remind(YYYY-MM-DD HH:MM)`, set inside the Programma panel.
        var reminder: TaskReminder?
        /// `@repeat(n/N)`, the finite recurrence of SPEC §7.1.
        var recurrence: TaskRecurrence?
        /// The task this draft becomes a sub-task of (ADR-0021 D9, A9). Nil composes an
        /// ordinary top-level task exactly as before; set, `captureTask` routes through
        /// `TaskParser.insertingSubtask(in:below:draft:)` and writes into the parent's
        /// own note rather than the draft's destination - `^id` is note-local (D2), so a
        /// sub-task filed anywhere else would point at nothing.
        var parent: TaskItem?

        /// The day the task belongs to, for whoever has to put it somewhere: the day it
        /// shows up on, or failing that the day it is due.
        var day: CalendarDate? { scheduled ?? due }

        /// The day and hour a block would be made at, when the draft has both. The
        /// scheduled hour wins: it is where the work is meant to happen, while a
        /// deadline is when it stops being on time.
        var blockSlot: (day: CalendarDate, time: TaskTime)? {
            if let scheduled, let scheduledTime { return (scheduled, scheduledTime) }
            if let due, let dueTime { return (due, dueTime) }
            return nil
        }

        var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }

        /// ADR-0023 §D6 (plan 2026-08-25-universal-command-surface-parity, Task 6): the
        /// draft «Aggiungi sotto-task» builds, as a value both entry points can assign -
        /// the Task menu through `CommandActions`, the task row's own context menu
        /// directly. A value rather than a body, because "the same draft from two places"
        /// is a thing a test can say as an equality.
        ///
        /// The destination is set to the parent's own note even though `captureTask`
        /// ignores it for a draft with a parent: `^id` is note-local (ADR-0021 D2), so the
        /// sub-task can only go where the parent is, and a composer whose header said
        /// "Inbox" while writing somewhere else would be lying about it.
        static func subtask(of parent: TaskItem) -> Self {
            Self(destination: .note(parent.sourcePath), parent: parent)
        }
    }

    /// Completes, reopens, cancels or reschedules a task by rewriting its source line.
    ///
    /// Writes the markdown file, never an index row: the file is the truth, and a task
    /// completed from any view has to change the note it lives in (SPEC §7.3).
    ///
    /// Returns what was written, so a caller with an editor open on that note can put
    /// it back in step.
    @discardableResult
    func apply(_ change: TaskChange, to task: TaskItem) -> WriteOutcome {
        do {
            let text = try taskSourceText(for: task)
            let newLine: String = switch change {
            case .state(let state):
                TaskParser.line(for: task, settingState: state, today: .today)
            case .schedule(let date):
                TaskParser.line(for: task, scheduledOn: date)
            case .due(let date):
                TaskParser.line(for: task, dueOn: date)
            case .scheduleAt(let date, let time):
                TaskParser.line(for: task, scheduledOn: date, at: time)
            case .link(let target):
                TaskParser.line(for: task, addingLinkTo: target)
            case .workspace(let path):
                TaskParser.line(for: task, assigningWorkspace: path)
            }

            guard let updated = TaskParser.rewrite(
                text, at: task.lineIndex, expecting: task.rawLine, with: newLine
            ) else {
                // The line moved or changed under us. Rescanning and asking again is
                // the only safe answer; rewriting by line number alone would edit
                // whatever now sits there.
                recordProblem("il task non è più dove risultava: \(task.sourcePath)")
                return .stale
            }

            return .written(try writeTaskSource(updated, for: task))
        } catch {
            recordProblem("\(task.sourcePath): \(error)")
            return .failed
        }
    }

    /// The text a task's line-rewrite is computed against: the note's own body for a
    /// note-sourced task, or the owning `.text` node's own body for a board-sourced one
    /// (ADR-0025's board/note separation, plan Section 5) - never the whole `.canvas`
    /// file, whose JSON `TaskParser.rewrite`'s line-surgical `components(separatedBy:
    /// "\n")` was never meant to see.
    private func taskSourceText(for task: TaskItem) throws -> String {
        guard task.sourcePath.hasSuffix(".\(CanvasStore.fileExtension)") else {
            return try read(task.sourcePath).text
        }
        guard let nodeID = task.nodeID else {
            throw TaskSourceError.missingNodeID(task.sourcePath)
        }
        let document = try CanvasStore(root: root).load(board: task.sourcePath)
        guard let node = document.nodes.first(where: { $0.id == nodeID }),
              case .text(let nodeText) = node.kind
        else {
            throw TaskSourceError.nodeNotFound(task.sourcePath, nodeID)
        }
        return nodeText
    }

    /// Writes a rewritten task line back to its owning file: `write(_:to:)` for a note,
    /// or the owning node inside its `.canvas` board for a board-sourced task - the one
    /// resolution point the plan asks for, so every caller of `apply` gets it for free.
    private func writeTaskSource(_ updated: String, for task: TaskItem) throws -> WriteResult {
        guard task.sourcePath.hasSuffix(".\(CanvasStore.fileExtension)") else {
            return try write(updated, to: task.sourcePath)
        }
        guard let nodeID = task.nodeID else {
            throw TaskSourceError.missingNodeID(task.sourcePath)
        }
        let canvasStore = CanvasStore(root: root)
        var document = try canvasStore.load(board: task.sourcePath)
        guard let index = document.nodes.firstIndex(where: { $0.id == nodeID }) else {
            throw TaskSourceError.nodeNotFound(task.sourcePath, nodeID)
        }
        document.nodes[index].kind = .text(updated)
        try canvasStore.save(document, board: task.sourcePath)
        return WriteResult(path: task.sourcePath, text: updated)
    }

    enum TaskSourceError: Error {
        case missingNodeID(String)
        case nodeNotFound(String, String)
    }

    /// Quick capture (SPEC §7.4): appends the composed task to its destination note,
    /// creating the inbox note if it is not there yet.
    ///
    /// A draft carrying a parent takes the other route instead (ADR-0021 D9): the line
    /// is inserted below that parent, in the parent's own note, through the same
    /// `read` → rewrite → atomic `write` path.
    @discardableResult
    func captureTask(_ draft: TaskDraft) -> WriteResult? {
        guard !draft.isEmpty else { return nil }
        if let parent = draft.parent { return captureSubtask(draft, below: parent) }
        let relativePath = draft.destination.relativePath

        do {
            let existing = try? read(relativePath)
            guard let body = existing?.text ?? inboxTemplate(for: draft.destination) else {
                recordProblem("cattura rapida: «\(relativePath)» non esiste")
                return nil
            }

            let line = TaskParser.line(
                forNewTask: draft.text,
                scheduled: draft.scheduled,
                scheduledTime: draft.scheduledTime,
                due: draft.due,
                dueTime: draft.dueTime,
                reminder: draft.reminder,
                recurrence: draft.recurrence
            )
            let separator = body.hasSuffix("\n") ? "" : "\n"
            return try write(body + separator + line + "\n", to: relativePath)
        } catch {
            recordProblem("cattura rapida: \(error)")
            return nil
        }
    }

    /// Inserts a composed draft as a sub-task of `parent` (ADR-0021 D9, A9; R-07).
    ///
    /// Returns nil when the parent's line has moved on since it was read, which is the
    /// same refusal `apply(_:to:)` gives for the same reason: inserting against a line
    /// index that no longer holds the line it was read from would file the sub-task
    /// under whatever now sits there.
    private func captureSubtask(_ draft: TaskDraft, below parent: TaskItem) -> WriteResult? {
        do {
            let (_, text) = try read(parent.sourcePath)
            let draft = TaskParser.SubtaskDraft(
                text: draft.text,
                scheduled: draft.scheduled,
                scheduledTime: draft.scheduledTime,
                due: draft.due,
                dueTime: draft.dueTime,
                reminder: draft.reminder,
                recurrence: draft.recurrence
            )
            guard let updated = TaskParser.insertingSubtask(in: text, below: parent, draft: draft) else {
                recordProblem("il task non è più dove risultava: \(parent.sourcePath)")
                return nil
            }
            return try write(updated, to: parent.sourcePath)
        } catch {
            recordProblem("sotto-task: \(error)")
            return nil
        }
    }

    /// The frontmatter a missing inbox note starts from; nil for any other destination,
    /// which is what refuses to create it.
    private func inboxTemplate(for destination: TaskDestination) -> String? {
        guard destination == .inbox else { return nil }
        var frontmatter = Frontmatter.empty
        frontmatter.date = .today
        frontmatter.tags = TagRules.initialTags(for: .capture)
        return FrontmatterSerializer.render(frontmatter) + "\n"
    }
}
