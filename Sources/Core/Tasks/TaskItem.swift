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
    /// The hour written after that day, when there is one: `>YYYY-MM-DD HH:MM`.
    var scheduledTime: TaskTime?
    /// `!YYYY-MM-DD`: past this it is late.
    var due: CalendarDate?
    /// The hour the task is due at, when it has one: `!YYYY-MM-DD HH:MM`.
    var dueTime: TaskTime?
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

    /// `^[[<name>.canvas]]` (ADR-0021 D1): the one Workspace this task is assigned to.
    /// Not one of `links` - assignment is a different fact from "this task mentions
    /// that board" and has its own field so the two never collide.
    var workspacePath: String? = nil
    /// `^id(<N>)` (ADR-0021 D1, D2): this task's identifier within its own note.
    /// Never reused across notes and never persisted anywhere but the line itself.
    var localID: Int? = nil
    /// `^parent(<N>)` (ADR-0021 D1, D2): the `^id` of this task's parent, in the same
    /// note. A `^parent` that names no `^id` in the same file is not an error at parse
    /// time - the linter is what notices (R-12).
    var parentLocalID: Int? = nil

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

/// How many of a project's sub-tasks are done, out of how many there are
/// (ADR-0021 D5). Returned by `IndexSnapshot.progress(ofProject:)`.
///
/// A struct rather than a tuple: `TaskGroup` carries it and is `Equatable`, and a
/// tuple would break that synthesis.
struct TaskProgress: Equatable, Sendable {
    var done: Int
    var total: Int
}

/// An hour of the day, as it is written after a `>` or `!` date.
///
/// SPEC §7.1 spells both markers as a bare `YYYY-MM-DD`, and this adds an optional
/// ` HH:MM` after it (ADR-0004). The extension is readable by anything that already
/// reads the marker: a parser that stops at the date - Obsidian, or a Pergamenum
/// older than this - still gets the day right and leaves the hour in the task text.
struct TaskTime: Equatable, Sendable, Comparable, Hashable {
    var hour: Int
    var minute: Int

    /// Clamped rather than failable: the hour comes from a picker or from a parsed
    /// string that was already validated, and a call site that cannot fail is one
    /// that never force-unwraps.
    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// `HH:MM` exactly, refusing anything else. This is the parsing door.
    init?(text: some StringProtocol) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// Minutes from midnight, the unit the timeline works in.
    var minutes: Int { hour * 60 + minute }

    var text: String { String(format: "%02d:%02d", hour, minute) }

    static func < (lhs: TaskTime, rhs: TaskTime) -> Bool { lhs.minutes < rhs.minutes }
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
