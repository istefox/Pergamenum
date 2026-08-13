import Foundation

/// Tasks as SPEC §7 defines them: every change is a rewrite of the markdown line the
/// task lives on, and nothing about a task is stored anywhere else.
///
/// Split from the controller because that type had grown past what one file should
/// hold; the state these methods act on stays in VaultController.swift, since an
/// extension cannot declare stored properties.
extension VaultController {
    /// Completes, reopens, cancels or reschedules a task by rewriting its source line.
    ///
    /// Writes the markdown file, never an index row: the file is the truth, and a task
    /// completed from any view has to change the note it lives in (SPEC §7.3).
    @discardableResult
    func apply(_ change: TaskChange, to task: TaskItem) -> Bool {
        guard let store else { return false }
        do {
            let (_, text) = try store.read(task.sourcePath)
            let newLine: String = switch change {
            case .state(let state):
                TaskParser.line(for: task, settingState: state, today: .today)
            case .schedule(let date):
                TaskParser.line(for: task, scheduledOn: date)
            case .link(let target):
                TaskParser.line(for: task, addingLinkTo: target)
            }

            guard let updated = TaskParser.rewrite(
                text, at: task.lineIndex, expecting: task.rawLine, with: newLine
            ) else {
                // The line moved or changed under us. Rescanning and asking again is
                // the only safe answer; rewriting by line number alone would edit
                // whatever now sits there.
                recordProblem("il task non è più dove risultava: \(task.sourcePath)")
                Task { await rescan() }
                return false
            }

            let hash = try store.write(updated, to: task.sourcePath)
            selfWrittenHashes[task.sourcePath] = hash
            index.update(try store.read(task.sourcePath).record, at: task.sourcePath)

            // Keep an open editor in step rather than leaving it showing the old line.
            if var note = openNote, note.relativePath == task.sourcePath, !note.hasUnsavedChanges {
                note.text = updated
                note.savedText = updated
                replaceOpenNote(note)
            }
            recordTaskWrite()
            return true
        } catch {
            recordProblem("\(task.sourcePath): \(error)")
            return false
        }
    }

    enum TaskChange: Sendable {
        case state(TaskItem.State)
        case schedule(CalendarDate?)
        case link(String)
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
        /// `!YYYY-MM-DD`, past which it is late.
        var due: CalendarDate?
        /// `@remind(YYYY-MM-DD HH:MM)`, set inside the Programma panel.
        var reminder: TaskReminder?
        /// `@repeat(n/N)`, the finite recurrence of SPEC §7.1.
        var recurrence: TaskRecurrence?

        /// The day the task belongs to, for whoever has to put it somewhere: the day it
        /// shows up on, or failing that the day it is due.
        var day: CalendarDate? { scheduled ?? due }

        var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Opens the composer on a destination, defaulting to the inbox.
    func beginTaskCapture(into destination: TaskDestination = .inbox) {
        taskDraft = TaskDraft(destination: destination)
    }

    /// Quick capture (SPEC §7.4): appends the composed task to its destination note,
    /// creating the inbox note if it is not there yet.
    @discardableResult
    func captureTask(_ draft: TaskDraft) -> Bool {
        guard let store, !draft.isEmpty else { return false }
        let relativePath = draft.destination.relativePath

        do {
            let existing = try? store.read(relativePath)
            guard let body = existing?.text ?? inboxTemplate(for: draft.destination) else {
                recordProblem("cattura rapida: «\(relativePath)» non esiste")
                return false
            }

            let line = TaskParser.line(
                forNewTask: draft.text,
                scheduled: draft.scheduled,
                due: draft.due,
                reminder: draft.reminder,
                recurrence: draft.recurrence
            )
            let separator = body.hasSuffix("\n") ? "" : "\n"
            let updated = body + separator + line + "\n"
            let hash = try store.write(updated, to: relativePath)
            selfWrittenHashes[relativePath] = hash
            index.update(try store.read(relativePath).record, at: relativePath)

            // Keep an editor showing that note in step, as `apply` does.
            if var note = openNote, note.relativePath == relativePath, !note.hasUnsavedChanges {
                note.text = updated
                note.savedText = updated
                replaceOpenNote(note)
            }
            lastCapture = draft
            recordTaskWrite()
            return true
        } catch {
            recordProblem("cattura rapida: \(error)")
            return false
        }
    }

    /// Reads the last capture once, so the Attività pane can show the view the new
    /// task actually landed in rather than leaving the user looking at an empty list.
    func consumeLastCapture() -> TaskDraft? {
        defer { lastCapture = nil }
        return lastCapture
    }

    /// The frontmatter a missing inbox note starts from; nil for any other destination,
    /// which is what refuses to create it.
    private func inboxTemplate(for destination: TaskDestination) -> String? {
        guard destination == .inbox else { return nil }
        var frontmatter = Frontmatter.empty
        frontmatter.date = .today
        frontmatter.tags = TagRules.ordered([
            Tag(namespace: .type, value: "note"),
            Tag(namespace: .status, value: "inbox"),
        ])
        return FrontmatterSerializer.render(frontmatter) + "\n"
    }

    /// Quick capture of a bare line, with no date and no destination but the inbox.
    @discardableResult
    func captureTask(_ text: String) -> Bool {
        captureTask(TaskDraft(text: text))
    }
}
