import Foundation

/// Line-rewriting side of `TaskParser`: turning a `TaskItem` (or a still-unwritten
/// draft) back into the exact line text SPEC §7.1 defines, plus the Workspace/
/// sub-task markers of ADR-0021 D9. Split out of `TaskParser.swift` on its own to
/// keep that file's primary type under the project's `type_body_length` limit
/// (`.swiftlint.yml`) - reading and rewriting are two halves of the same file's job,
/// not two responsibilities, so this stays an extension rather than a new type.
extension TaskParser {
    // MARK: Rewriting

    /// Rewrites one task line inside a file's text.
    ///
    /// Returns nil when the line is not the task it was told to change, which is what
    /// stops a stale index from rewriting the wrong line after the note moved on.
    static func rewrite(
        _ text: String,
        at lineIndex: Int,
        expecting original: String,
        with newLine: String
    ) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex), lines[lineIndex] == original else { return nil }
        lines[lineIndex] = newLine
        return lines.joined(separator: "\n")
    }

    /// The line for a task with a new state, preserving indentation, bullet and any
    /// syntax this parser does not model.
    static func line(for task: TaskItem, settingState state: TaskItem.State, today: CalendarDate) -> String {
        var line = replacingMarker(in: task.rawLine, with: state.marker)

        // `@done(...)` follows the state rather than being set by hand: it is the one
        // annotation the app owns.
        line = removingAnnotation(named: "done", from: line)
        if state == .done {
            line = line.trimmingTrailingWhitespace() + " @done(\(today))"
        }
        return line.trimmingTrailingWhitespace()
    }

    /// The line for a task moved to a new day, or with its schedule cleared.
    ///
    /// The hour goes with the day: "domani" said by a reschedule command is a day and
    /// not a time, and carrying the old `09:00` onto it would invent one.
    static func line(
        for task: TaskItem, scheduledOn date: CalendarDate?, at time: TaskTime? = nil
    ) -> String {
        var line = task.rawLine
        if let existing = markerRange(in: line, prefix: ">") {
            line.removeSubrange(withPrecedingSpace(existing, in: line))
        }
        guard let date else { return line.trimmingTrailingWhitespace() }
        return line.trimmingTrailingWhitespace() + " >\(date)" + (time.map { " " + $0.text } ?? "")
    }

    /// The line for a task with a due date set or cleared (`!YYYY-MM-DD`, SPEC §7.1).
    static func line(for task: TaskItem, dueOn date: CalendarDate?) -> String {
        var line = task.rawLine
        if let existing = markerRange(in: line, prefix: "!") {
            line.removeSubrange(withPrecedingSpace(existing, in: line))
        }
        guard let date else { return line.trimmingTrailingWhitespace() }
        return line.trimmingTrailingWhitespace() + " !\(date)"
    }

    /// The line for a task that does not exist yet, in the marker order of SPEC §7.1.
    ///
    /// A marker already typed into the text wins over the one the composer holds: the
    /// two would otherwise both be written, and a line carrying two `>` dates parses
    /// back to whichever the scanner meets first, which is not a choice anyone made.
    static func line(
        forNewTask text: String,
        scheduled: CalendarDate? = nil,
        scheduledTime: TaskTime? = nil,
        due: CalendarDate? = nil,
        dueTime: TaskTime? = nil,
        reminder: TaskReminder? = nil,
        recurrence: TaskRecurrence? = nil
    ) -> String {
        let body = text.trimmingCharacters(in: .whitespaces)
        var line = "- [ ] " + body
        if let scheduled, markerRange(in: body, prefix: ">") == nil {
            line += " >\(scheduled)" + (scheduledTime.map { " " + $0.text } ?? "")
        }
        if let due, markerRange(in: body, prefix: "!") == nil {
            line += " !\(due)" + (dueTime.map { " " + $0.text } ?? "")
        }
        if let reminder, !body.contains("@remind(") { line += " " + reminder.rendered }
        if let recurrence, !body.contains("@repeat(") { line += " " + recurrence.rendered }
        return line
    }

    /// Adds or replaces a wikilink to a note or canvas, which is how "Collega
    /// nota/canvas…" works (SPEC §7.2).
    static func line(for task: TaskItem, addingLinkTo target: String) -> String {
        guard !task.links.contains(target) else { return task.rawLine }
        return task.rawLine.trimmingTrailingWhitespace() + " [[\(target)]]"
    }

    // MARK: - Workspace assignment and sub-tasks (ADR-0021 D9, A9)

    /// A sub-task being composed for `insertingSubtask(in:below:draft:)`: its own text
    /// and the same dates/annotations `line(forNewTask:…)` accepts, independent of the
    /// parent's (R-07's last clause).
    struct SubtaskDraft: Equatable, Sendable {
        var text: String
        var scheduled: CalendarDate?
        var scheduledTime: TaskTime?
        var due: CalendarDate?
        var dueTime: TaskTime?
        var reminder: TaskReminder?
        var recurrence: TaskRecurrence?

        init(
            text: String,
            scheduled: CalendarDate? = nil,
            scheduledTime: TaskTime? = nil,
            due: CalendarDate? = nil,
            dueTime: TaskTime? = nil,
            reminder: TaskReminder? = nil,
            recurrence: TaskRecurrence? = nil
        ) {
            self.text = text
            self.scheduled = scheduled
            self.scheduledTime = scheduledTime
            self.due = due
            self.dueTime = dueTime
            self.reminder = reminder
            self.recurrence = recurrence
        }
    }

    /// Assigns or clears the Workspace marker `^[[<canvas>.canvas]]` (ADR-0021 D9):
    /// replaces any existing one so a task is never assigned twice (R-03, "exactly
    /// one"), and removes it together with its preceding space when `workspacePath`
    /// is nil.
    ///
    /// Removal then append, the shape `line(for:scheduledOn:)` and `line(for:dueOn:)`
    /// already have: the marker is taken out through `withPrecedingSpace` so no double
    /// space is left behind, and the new one goes at the end of the line.
    static func line(for task: TaskItem, assigningWorkspace workspacePath: String?) -> String {
        var line = task.rawLine
        if let existing = workspaceMarkerRange(in: line) {
            line.removeSubrange(withPrecedingSpace(existing, in: line))
        }
        guard let workspacePath else { return line.trimmingTrailingWhitespace() }
        return line.trimmingTrailingWhitespace() + " ^[[\(workspacePath)]]"
    }

    /// Assigns a `^id` to a task that has none yet (ADR-0021 D1/D2, ADR-0049 §D3):
    /// appended once, at the end of the line, the shape `assigningWorkspace` already
    /// has. A task that already carries an `^id` is returned **unchanged** - the
    /// caller decides the new id, through `nextLocalID(in:)`, before calling this, and
    /// this never invents a second one for a task that already has one.
    ///
    /// The staleness guard is `rewrite(_:at:expecting:with:)`'s own, the same one
    /// `insertingSubtask(in:below:draft:)` applies: the caller rewrites with
    /// `expecting: task.rawLine`, so a note that moved on under the caller's feet
    /// refuses rather than overwriting the wrong line.
    static func line(for task: TaskItem, assigningLocalID localID: Int) -> String {
        guard task.localID == nil else { return task.rawLine }
        return task.rawLine.trimmingTrailingWhitespace() + " ^id(\(localID))"
    }

    /// The whole `^[[<name>.canvas]]` marker, caret included, so removing one leaves no
    /// stranded `^` behind - the same reason `markerRange(in:prefix:)` returns the hour
    /// along with the date.
    private static func workspaceMarkerRange(in line: String) -> Range<String.Index>? {
        guard let entry = annotatedLinks(in: line).first(where: \.isWorkspace) else { return nil }
        return line.index(before: entry.link.range.lowerBound)..<entry.link.range.upperBound
    }

    // MARK: - Category assignment (ADR-0047 §D5)

    /// Assigns or clears the task's category tag (SPEC "Task ↔ category", "exactly
    /// one" like the Workspace marker above): removes **every** existing
    /// `#project-*` tag first - the SPEC edge case of a line carrying two is
    /// normalized down to the one just chosen - then appends the new one; `nil`
    /// removes without appending anything.
    static func line(for task: TaskItem, assigningCategory slug: String?) -> String {
        var line = task.rawLine
        while let existing = projectTagRange(in: line) {
            line.removeSubrange(withPrecedingSpace(existing, in: line))
        }
        guard let slug else { return line.trimmingTrailingWhitespace() }
        return line.trimmingTrailingWhitespace() + " #project-\(slug)"
    }

    /// The range of the first `#project-*` tag in `line`, found with the same
    /// boundary check `tags(in:)` (`TaskParser.swift`) uses - preceded by the line
    /// start or a space, so a stray `#` mid-word is never mistaken for one.
    private static func projectTagRange(in line: String) -> Range<String.Index>? {
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            guard characters[index] == "#", index == 0 || characters[index - 1] == " " else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count,
                  characters[end].isLetter || characters[end].isNumber || characters[end] == "-" {
                end += 1
            }
            if let tag = Tag(String(characters[index..<end])), tag.namespace == .project {
                let start = line.index(line.startIndex, offsetBy: index)
                let stop = line.index(line.startIndex, offsetBy: end)
                return start..<stop
            }
            index = end
        }
        return nil
    }

    /// Inserts a sub-task line immediately below `parent`, allocating `^id`/`^parent`
    /// from one `nextLocalID` scan (ADR-0021 D9, A9; R-07). Returns nil when the line
    /// at `parent.lineIndex` is no longer `parent.rawLine` - the same staleness guard
    /// `rewrite(_:at:expecting:with:)` (this file) already applies.
    ///
    /// One scan, not two: a parent with no `^id` takes the next id and the child takes
    /// the one after it, computed from the same starting value. Two separate
    /// `nextLocalID` calls would hand both lines the same number, since the first write
    /// is not on disk when the second is computed.
    ///
    /// The child always gets an `^id` of its own, whether or not the parent needed one
    /// (R-07: "creates a new task line with an auto-assigned `^id`"), so it can become a
    /// parent in turn without a rewrite.
    static func insertingSubtask(in text: String, below parent: TaskItem, draft: SubtaskDraft) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(parent.lineIndex),
              lines[parent.lineIndex] == parent.rawLine
        else { return nil }

        var nextID = nextLocalID(in: text)
        var parentLine = parent.rawLine
        let parentID: Int
        if let existing = parent.localID {
            parentID = existing
        } else {
            parentID = nextID
            nextID += 1
            parentLine = parentLine.trimmingTrailingWhitespace() + " ^id(\(parentID))"
        }
        let childID = nextID

        // Cosmetic only, never read back: the hierarchy is `^parent`, and a note
        // reindented by hand keeps working (ADR-0021 D9).
        let indentation = String(parent.rawLine.prefix(while: { $0 == " " || $0 == "\t" })) + "  "
        let childLine = indentation + line(
            forNewTask: draft.text,
            scheduled: draft.scheduled,
            scheduledTime: draft.scheduledTime,
            due: draft.due,
            dueTime: draft.dueTime,
            reminder: draft.reminder,
            recurrence: draft.recurrence
        ) + " ^parent(\(parentID)) ^id(\(childID))"

        lines[parent.lineIndex] = parentLine
        lines.insert(childLine, at: parent.lineIndex + 1)
        return lines.joined(separator: "\n")
    }
}
