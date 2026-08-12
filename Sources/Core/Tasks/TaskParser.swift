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

        task.scheduled = date(in: body, prefix: ">")
        task.due = date(in: body, prefix: "!")
        task.completed = annotationDate(in: body, name: "done")
        task.reminder = reminder(in: body)
        task.recurrence = recurrence(in: body)
        task.links = WikilinkParser.links(in: body).filter { !$0.isEmbed }.map(\.target)
        task.tags = tags(in: body)
        task.project = task.tags.first { $0.namespace == .project }
        task.text = displayText(from: body)
        return task
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

    /// `>YYYY-MM-DD` or `!YYYY-MM-DD`, at a word boundary.
    ///
    /// The boundary matters: a blockquote `>` and a comparison `x > 3` are not dates,
    /// and neither is the `>` inside an HTML tag.
    private static func date(in body: String, prefix: Character) -> CalendarDate? {
        let characters = Array(body)
        for index in characters.indices where characters[index] == prefix {
            let precededByBoundary = index == 0 || characters[index - 1] == " "
            guard precededByBoundary, index + 10 < characters.count + 1,
                  index + 1 + 10 <= characters.count
            else { continue }
            let candidate = String(characters[(index + 1)..<(index + 1 + 10)])
            if let date = CalendarDate(iso: candidate) { return date }
        }
        return nil
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
        for link in WikilinkParser.links(in: body) {
            text = text.replacingOccurrences(of: link.rendered, with: "")
        }
        for pattern in ["@done", "@remind", "@repeat"] {
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

    private static func markerRange(in text: String, prefix: Character) -> Range<String.Index>? {
        let characters = Array(text)
        for index in characters.indices where characters[index] == prefix {
            let precededByBoundary = index == 0 || characters[index - 1] == " "
            guard precededByBoundary, index + 1 + 10 <= characters.count else { continue }
            let candidate = String(characters[(index + 1)..<(index + 1 + 10)])
            guard CalendarDate(iso: candidate) != nil else { continue }

            let start = text.index(text.startIndex, offsetBy: index)
            let end = text.index(start, offsetBy: 11)
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
    static func line(for task: TaskItem, scheduledOn date: CalendarDate?) -> String {
        var line = task.rawLine
        if let existing = markerRange(in: line, prefix: ">") {
            line.removeSubrange(withPrecedingSpace(existing, in: line))
        }
        guard let date else { return line.trimmingTrailingWhitespace() }
        return line.trimmingTrailingWhitespace() + " >\(date)"
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
