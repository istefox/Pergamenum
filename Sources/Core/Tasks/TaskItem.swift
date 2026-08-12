import Foundation

/// One task line, as SPEC §7.1 defines it.
///
/// The whole syntax is ASCII and lives inside ordinary markdown, so a task written in
/// Obsidian is a task here and the reverse. Nothing about a task is stored outside
/// the note that contains it.
struct TaskItem: Equatable, Sendable, Identifiable {
    enum State: Equatable, Sendable {
        case open
        case done
        /// `- [>]`, moved to a later date.
        case rescheduled
        /// `- [-]`, dropped.
        case cancelled

        var marker: Character {
            switch self {
            case .open: " "
            case .done: "x"
            case .rescheduled: ">"
            case .cancelled: "-"
            }
        }

        /// Whether the task still wants doing. A rescheduled task does.
        var isOpen: Bool { self == .open || self == .rescheduled }
    }

    /// Vault-relative path of the note or `.canvas` the task lives in.
    var sourcePath: String
    /// Zero-based line index within that file.
    var lineIndex: Int

    var state: State
    /// The text with its markers removed, which is what a task view shows.
    var text: String
    /// The whole original line, so a rewrite can preserve indentation and bullet.
    var rawLine: String

    /// `>YYYY-MM-DD`: the day it should surface on.
    var scheduled: CalendarDate?
    /// `!YYYY-MM-DD`: past this it is late.
    var due: CalendarDate?
    /// `@done(YYYY-MM-DD)`.
    var completed: CalendarDate?
    /// `@remind(YYYY-MM-DD HH:MM)`.
    var reminder: TaskReminder?
    /// `@repeat(n/N)`: finite recurrence, n done of N.
    var recurrence: TaskRecurrence?

    /// Wikilink targets in the task text. SPEC §7.2 makes these the link between a
    /// task and a note or a canvas - there is no separate syntax.
    var links: [String]
    /// `#project-*`, at most one is meaningful.
    var project: Tag?
    /// Every tag on the line.
    var tags: [Tag]

    var id: String { "\(sourcePath)#\(lineIndex)" }

    /// Late relative to a given day: due before it and still open.
    func isOverdue(on day: CalendarDate) -> Bool {
        guard state.isOpen, let due else { return false }
        return due < day
    }

    /// Whether this task should appear on a given day's note (SPEC §7.3: the task
    /// stays in its own note and is shown by reference).
    func isScheduled(on day: CalendarDate) -> Bool {
        scheduled == day
    }
}

struct TaskReminder: Equatable, Sendable {
    var date: CalendarDate
    var hour: Int
    var minute: Int

    var rendered: String {
        String(format: "@remind(%@ %02d:%02d)", date.description, hour, minute)
    }
}

struct TaskRecurrence: Equatable, Sendable {
    var completed: Int
    var total: Int

    var rendered: String { "@repeat(\(completed)/\(total))" }
    var isFinished: Bool { completed >= total }
}
