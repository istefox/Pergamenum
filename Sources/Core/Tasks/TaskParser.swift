import Foundation

/// Reads and rewrites task lines.
///
/// Rewriting is line-surgical on purpose: completing a task from a task view must
/// change the one thing it means to change and leave the rest of the note - including
/// its indentation, its bullet character and any syntax this parser does not model -
/// exactly as the user wrote it.
enum TaskParser {
    /// Every task in a file, in source order.
    ///
    /// Fenced code blocks are skipped: a shell snippet containing `- [ ]` is not a
    /// task, the same reason `[[ ]]` in bash is not a wikilink.
    static func tasks(in text: String, sourcePath: String) -> [TaskItem] {
        let codeRanges = WikilinkParser.codeRanges(in: text)
        var results: [TaskItem] = []

        var lineStart = text.startIndex
        var lineIndex = 0
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            defer {
                lineIndex += 1
                lineStart = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            }
            guard !codeRanges.contains(where: { $0.contains(lineStart) }) else { continue }

            let line = String(text[lineStart..<lineEnd])
            if let task = parse(line: line, sourcePath: sourcePath, lineIndex: lineIndex) {
                results.append(task)
            }
        }
        return results
    }

    /// Parses one line, returning nil when it is not a task.
    static func parse(line: String, sourcePath: String, lineIndex: Int) -> TaskItem? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let bullet = trimmed.first, bullet == "-" || bullet == "*" else { return nil }

        let afterBullet = trimmed.dropFirst()
        guard afterBullet.hasPrefix(" ["), afterBullet.count >= 4 else { return nil }

        let characters = Array(afterBullet)
        guard characters[3] == "]" else { return nil }
        guard let state = state(for: characters[2]) else { return nil }

        // Everything after `- [x] `.
        let body = String(characters.dropFirst(4)).trimmingCharacters(in: .whitespaces)

        var task = TaskItem(
            sourcePath: sourcePath,
            lineIndex: lineIndex,
            state: state,
            text: "",
            rawLine: line,
            links: [],
            tags: []
        )

        let scheduled = marker(in: body, prefix: ">")
        let due = marker(in: body, prefix: "!")
        task.scheduled = scheduled?.date
        task.scheduledTime = scheduled?.time
        task.due = due?.date
        task.dueTime = due?.time
        task.completed = annotationDate(in: body, name: "done")
        task.reminder = reminder(in: body)
        task.recurrence = recurrence(in: body)
        let annotated = annotatedLinks(in: body)
        // The Workspace marker is an assignment, not a mention: it leaves `links`
        // entirely (ADR-0021 D1), so the plain-wikilink mechanism of SPEC §7.2 keeps
        // meaning "notes and boards this task references" and the two never collide.
        task.workspacePath = annotated.first(where: \.isWorkspace)?.link.target
        task.links = annotated.filter { !$0.isWorkspace && !$0.link.isEmbed }.map(\.link.target)
        task.localID = caretInteger(in: body, name: "id")
        task.parentLocalID = caretInteger(in: body, name: "parent")
        task.tags = tags(in: body)
        task.project = task.tags.first { $0.namespace == .project }
        task.text = displayText(from: body)
        return task
    }

    /// One past the highest `^id(<N>)` in the note, or 1 for a note with none
    /// (ADR-0021 D2). Counts every task line, not only open ones - a done or
    /// cancelled task still occupies its id.
    ///
    /// A scan of the note rather than a persisted counter: an id is read out of the
    /// file, so deleting every derived store loses nothing and a note edited in
    /// Obsidian or by hand keeps working. Goes through `tasks(in:sourcePath:)` so the
    /// fenced-code skip is the same one every other reader gets.
    static func nextLocalID(in text: String) -> Int {
        let highest = tasks(in: text, sourcePath: "").compactMap(\.localID).max() ?? 0
        return highest + 1
    }

    private static func state(for marker: Character) -> TaskItem.State? {
        switch marker {
        case " ": .open
        case "x", "X": .done
        case ">": .rescheduled
        case "-": .cancelled
        default: nil
        }
    }

    /// `>YYYY-MM-DD` or `!YYYY-MM-DD`, with the optional ` HH:MM` of ADR-0004, at a
    /// word boundary.
    ///
    /// The boundary matters: a blockquote `>` and a comparison `x > 3` are not dates,
    /// and neither is the `>` inside an HTML tag.
    private static func marker(
        in body: String, prefix: Character
    ) -> (date: CalendarDate, time: TaskTime?)? {
        let characters = Array(body)
        for index in characters.indices where characters[index] == prefix {
            let precededByBoundary = index == 0 || characters[index - 1] == " "
            guard precededByBoundary, index + 1 + 10 <= characters.count else { continue }
            let candidate = String(characters[(index + 1)..<(index + 1 + 10)])
            if let date = CalendarDate(iso: candidate) {
                return (date, time(in: characters, at: index + 11))
            }
        }
        return nil
    }

    /// The ` HH:MM` that may follow a date marker, read from where the date ends.
    ///
    /// Only a well-formed hour counts: the character after a date is a space in every
    /// task that carries another marker too, and `>2026-08-15 !2026-08-20` must not
    /// read the second marker as an hour.
    private static func time(in characters: [Character], at index: Int) -> TaskTime? {
        guard index + 6 <= characters.count, characters[index] == " " else { return nil }
        return TaskTime(text: String(characters[(index + 1)..<(index + 6)]))
    }

    private static func annotationDate(in body: String, name: String) -> CalendarDate? {
        guard let value = annotationValue(in: body, name: name) else { return nil }
        return CalendarDate(iso: value.trimmingCharacters(in: .whitespaces))
    }

    private static func annotationValue(in body: String, name: String) -> String? {
        guard let start = body.range(of: "@\(name)(") else { return nil }
        guard let end = body.range(of: ")", range: start.upperBound..<body.endIndex) else { return nil }
        return String(body[start.upperBound..<end.lowerBound])
    }

    /// `^id(<N>)` / `^parent(<N>)` (ADR-0021 D1), the caret sibling of
    /// `annotationValue(in:name:)`.
    ///
    /// `range(of:)` finds the first occurrence, so a line carrying two of the same
    /// marker keeps the first and ignores the rest - the rule `marker(in:prefix:)`
    /// already applies to a line carrying two `>` dates.
    private static func caretAnnotation(in body: String, name: String) -> String? {
        guard let start = body.range(of: "^\(name)(") else { return nil }
        guard let end = body.range(of: ")", range: start.upperBound..<body.endIndex) else { return nil }
        return String(body[start.upperBound..<end.lowerBound])
    }

    private static func caretInteger(in body: String, name: String) -> Int? {
        guard let value = caretAnnotation(in: body, name: name) else { return nil }
        return Int(value.trimmingCharacters(in: .whitespaces))
    }

    /// Every wikilink in a body, each paired with whether it is the Workspace marker
    /// `^[[<name>.canvas]]` of ADR-0021 D1.
    ///
    /// The two conditions are deliberately narrow: a `^` immediately before the link
    /// **and** a target ending in `.canvas`, case-insensitively. Anything else -
    /// `^[[Nota]]`, or a caret that merely happens to precede a link in prose - keeps
    /// today's meaning exactly, an ordinary wikilink with a literal caret in front of
    /// it. That is the whole of the backward-compatibility argument, and it costs one
    /// `hasSuffix`.
    private static func annotatedLinks(in body: String) -> [(link: Wikilink, isWorkspace: Bool)] {
        WikilinkParser.links(in: body).map { link in
            guard !link.isEmbed,
                  link.range.lowerBound > body.startIndex,
                  body[body.index(before: link.range.lowerBound)] == "^",
                  link.target.lowercased().hasSuffix(".canvas")
            else { return (link, false) }
            return (link, true)
        }
    }

    private static func reminder(in body: String) -> TaskReminder? {
        guard let value = annotationValue(in: body, name: "remind") else { return nil }
        let parts = value.split(separator: " ")
        guard let first = parts.first, let date = CalendarDate(iso: String(first)) else { return nil }

        guard parts.count > 1 else {
            // A reminder with no time defaults to the start of the day rather than
            // being discarded; the settings hold the user's preferred hour (SPEC §12).
            return TaskReminder(date: date, hour: 9, minute: 0)
        }
        let time = parts[1].split(separator: ":")
        guard time.count == 2, let hour = Int(time[0]), let minute = Int(time[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return TaskReminder(date: date, hour: hour, minute: minute)
    }

    private static func recurrence(in body: String) -> TaskRecurrence? {
        guard let value = annotationValue(in: body, name: "repeat") else { return nil }
        let parts = value.split(separator: "/")
        guard parts.count == 2, let completed = Int(parts[0]), let total = Int(parts[1]), total > 0
        else { return nil }
        return TaskRecurrence(completed: completed, total: total)
    }

    private static func tags(in body: String) -> [Tag] {
        var found: [Tag] = []
        let characters = Array(body)
        var index = 0

        while index < characters.count {
            guard characters[index] == "#",
                  index == 0 || characters[index - 1] == " "
            else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count,
                  characters[end].isLetter || characters[end].isNumber || characters[end] == "-" {
                end += 1
            }
            if let tag = Tag(String(characters[index..<end])) { found.append(tag) }
            index = end
        }
        return found
    }

    /// The task text without its markers, for display.
    ///
    /// Dates, annotations, tags and wikilinks all come out: each is already captured
    /// as a field, and a task view renders it as its own affordance. SPEC §7.2 asks
    /// for every wikilink to be clickable, which a link chip satisfies; leaving the
    /// `[[…]]` in the sentence as well would show the same link twice.
    static func displayText(from body: String) -> String {
        var text = body
        for tag in tags(in: body) {
            text = text.replacingOccurrences(of: "#\(tag.description)", with: "")
        }
        // The Workspace markers go first, caret included: removing `[[X.canvas]]` on
        // its own would strand a `^` mid-sentence (ADR-0021 D1).
        let annotated = annotatedLinks(in: body)
        for entry in annotated where entry.isWorkspace {
            text = text.replacingOccurrences(of: "^" + entry.link.rendered, with: "")
        }
        for entry in annotated where !entry.isWorkspace {
            text = text.replacingOccurrences(of: entry.link.rendered, with: "")
        }
        for pattern in ["@done", "@remind", "@repeat", "^id", "^parent"] {
            while let start = text.range(of: "\(pattern)("),
                  let end = text.range(of: ")", range: start.upperBound..<text.endIndex) {
                text.removeSubrange(start.lowerBound..<end.upperBound)
            }
        }
        text = removeDateMarkers(from: text, prefix: ">")
        text = removeDateMarkers(from: text, prefix: "!")
        // Collapse the gaps the removals leave, without touching the leading
        // indentation, which is not part of the body.
        while text.contains("  ") { text = text.replacingOccurrences(of: "  ", with: " ") }
        // A trailing comma left by a removed link reads as a typo.
        return text
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func removeDateMarkers(from text: String, prefix: Character) -> String {
        var result = text
        while let range = markerRange(in: result, prefix: prefix) {
            result.removeSubrange(range)
        }
        return result
    }

    /// The whole marker, hour included, so removing one leaves no `15:00` stranded in
    /// the middle of a sentence.
    private static func markerRange(in text: String, prefix: Character) -> Range<String.Index>? {
        let characters = Array(text)
        for index in characters.indices where characters[index] == prefix {
            let precededByBoundary = index == 0 || characters[index - 1] == " "
            guard precededByBoundary, index + 1 + 10 <= characters.count else { continue }
            let candidate = String(characters[(index + 1)..<(index + 1 + 10)])
            guard CalendarDate(iso: candidate) != nil else { continue }

            let length = time(in: characters, at: index + 11) == nil ? 11 : 17
            let start = text.index(text.startIndex, offsetBy: index)
            let end = text.index(start, offsetBy: length)
            return start..<end
        }
        return nil
    }

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

    private static func replacingMarker(in line: String, with marker: Character) -> String {
        guard let open = line.firstIndex(of: "["),
              let close = line.range(of: "]", range: open..<line.endIndex)
        else { return line }
        var result = line
        result.replaceSubrange(line.index(after: open)..<close.lowerBound, with: String(marker))
        return result
    }

    private static func removingAnnotation(named name: String, from line: String) -> String {
        var result = line
        while let start = result.range(of: "@\(name)("),
              let end = result.range(of: ")", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(withPrecedingSpace(start.lowerBound..<end.upperBound, in: result))
        }
        return result
    }

    /// Extends a range backwards over one space, so removing a marker does not leave a
    /// double space behind.
    ///
    /// Deliberately not a blanket collapse of double spaces: that also ate the leading
    /// indentation of a nested task, silently reformatting the user's note.
    private static func withPrecedingSpace(
        _ range: Range<String.Index>, in text: String
    ) -> Range<String.Index> {
        guard range.lowerBound > text.startIndex else { return range }
        let before = text.index(before: range.lowerBound)
        return text[before] == " " ? before..<range.upperBound : range
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }
}
