import Foundation

/// A block of time on the day's timeline (SPEC §8.3).
///
/// Blocks live in the daily note, not in a database: a line under a `## Timeline`
/// heading, so the plan survives the app exactly like everything else. Publishing a
/// block to the Apple calendar is a separate, per-block choice.
struct TimeBlock: Equatable, Sendable, Identifiable {
    var id: String { "\(day.compactForm)-\(startMinutes)-\(title)" }

    var day: CalendarDate
    /// Minutes from midnight, so arithmetic on the timeline is integer arithmetic.
    var startMinutes: Int
    var durationMinutes: Int
    var title: String
    /// The task this block was dragged from, when it came from one.
    var sourceTaskID: String?
    /// True once it has been written to the Apple calendar.
    var isPublished: Bool

    var endMinutes: Int { startMinutes + durationMinutes }

    /// `HH:MM`
    var startText: String { TimeBlock.timeText(startMinutes) }
    var endText: String { TimeBlock.timeText(endMinutes) }

    /// `09:00`, and `24:00` for a block that runs to midnight - the diary's own rule,
    /// shared rather than copied, so the two timelines cannot disagree about the end of
    /// the day again (ADR-0075 §D1).
    static func timeText(_ minutes: Int) -> String {
        DiaryGrid.timeText(minutes)
    }

    /// The default duration of a block created by dropping a task (SPEC §8.3).
    static let defaultDuration = 30

    /// The lengths a block may be asked for, in minutes: the one statement of the range
    /// the settings clamp to and the connectors refuse outside of (ADR-0075 §D4).
    static let durationRange: ClosedRange<Int> = 5...480

    /// Snaps a minute value to the nearest quarter hour, which is what makes dragging
    /// produce times a person would actually write down.
    static func snap(_ minutes: Int, to step: Int = 15) -> Int {
        max(0, ((minutes + step / 2) / step) * step)
    }

    /// Where a block goes and how long it can be there.
    struct Slot: Equatable, Sendable {
        let start: Int
        let duration: Int
    }

    /// The first free stretch at or after `preferred` that is at least `minimum` long,
    /// with the block's length cut to fit it, or nil when the day runs out
    /// (ADR-0075 §D2).
    ///
    /// Placed rather than overlapped: two blocks at the same time say nothing about
    /// what the day actually looks like, which is the whole point of a timeline. A start
    /// inside a block moves to that block's end exactly, so a hand-written `09:00-09:10`
    /// leaves 09:10 usable; a stretch shorter than `minimum` is passed over, not refused;
    /// midnight closes the day. A block with no length is ignored rather than trusted,
    /// so every step moves the start strictly forward.
    static func freeSlot(from preferred: Int, in blocks: [TimeBlock], duration: Int, minimum: Int) -> Slot? {
        let dayEnd = 24 * 60
        let placed = blocks.filter { $0.durationMinutes > 0 }
        var start = snap(preferred)
        while start < dayEnd {
            if let containing = placed.first(where: { $0.startMinutes <= start && start < $0.endMinutes }) {
                start = containing.endMinutes
                continue
            }
            let next = placed
                .filter { $0.startMinutes > start }
                .min { $0.startMinutes < $1.startMinutes }
            let run = min(next?.startMinutes ?? dayEnd, dayEnd) - start
            if run >= minimum {
                return Slot(start: start, duration: min(duration, run))
            }
            guard let next else { return nil }
            start = next.endMinutes
        }
        return nil
    }

    func overlaps(_ other: TimeBlock) -> Bool {
        day == other.day && startMinutes < other.endMinutes && other.startMinutes < endMinutes
    }

    /// The same block at another hour, or nil when the day has no room left for it.
    ///
    /// `others` is the day without this block in it: a block always overlaps itself, and
    /// asking `freeSlot` to avoid the place it is leaving would push every move down by
    /// its own length.
    ///
    /// Placed with `freeSlot` rather than dropped exactly where the pointer let go,
    /// which is the rule every other way of making a block already follows: two blocks
    /// at the same time say nothing about what the day looks like. The minimum is the
    /// block's own length, so a move never shortens it - that would be a resize nobody
    /// asked for - and never lands on top of the next block either (ADR-0075 §D2).
    static func moved(_ block: TimeBlock, toStart start: Int, among others: [TimeBlock]) -> TimeBlock? {
        let duration = block.durationMinutes
        let wanted = min(max(0, snap(start)), 24 * 60 - duration)
        guard wanted >= 0,
              let slot = freeSlot(from: wanted, in: others, duration: duration, minimum: duration)
        else { return nil }

        var moved = block
        moved.startMinutes = slot.start
        return moved
    }

    /// The same block, longer or shorter. Never under a quarter of an hour, never past
    /// midnight, and never through the block underneath: the bottom edge stops where the
    /// next one starts, because an overlap pulled open by hand is the same overlap
    /// `moved` refuses to create.
    static func resized(_ block: TimeBlock, toDuration duration: Int, among others: [TimeBlock]) -> TimeBlock {
        let next = others
            .filter { $0.startMinutes >= block.endMinutes || $0.startMinutes > block.startMinutes }
            .map(\.startMinutes)
            .filter { $0 > block.startMinutes }
            .min()
        let ceiling = min(next ?? 24 * 60, 24 * 60) - block.startMinutes

        var resized = block
        resized.durationMinutes = min(max(15, snap(duration)), max(15, ceiling))
        return resized
    }
}

/// Reads and writes the `## Timeline` section of a daily note.
///
/// The format is a markdown list, so the note stays readable in Obsidian and the plan
/// is not lost the day this app is not around.
///
/// The section is the line that is exactly `## Timeline`, outside a code fence
/// (`MarkdownSection`, R-10): a search for the heading's text took `### Timeline` or
/// `## Timeline riunione` for the plan, read its list as the day's blocks and overwrote it.
enum TimeBlockSection {
    static let heading = "## Timeline"

    /// `- 09:00-10:00 Sopralluogo pressa 4` with an optional `[published]` marker.
    ///
    /// A line inside a code fence is not a block (`MarkdownSection.lines(below:in:)`): a note that
    /// shows the format in an example under `## Timeline` does not get the example as its plan.
    /// No `#` stops the walk either: `section` already ends at the next heading outside a fence,
    /// so a `#` line inside it is a fenced one (`# comment` in a shell block), and stopping at it
    /// dropped every block listed after the fence - which `write` then deleted.
    static func parse(from body: String, day: CalendarDate) -> [TimeBlock] {
        guard let section = MarkdownSection.range(under: heading, in: body) else { return [] }
        return MarkdownSection.lines(below: section, in: body)
            .compactMap { line -> TimeBlock? in
                guard !line.isCode, let entry = entry(from: line.text(in: body)) else { return nil }
                return TimeBlock(
                    day: day,
                    startMinutes: entry.start,
                    durationMinutes: entry.end - entry.start,
                    title: entry.title,
                    sourceTaskID: nil,
                    isPublished: entry.isPublished
                )
            }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    /// One block line, read.
    private struct Entry {
        let start: Int
        let end: Int
        let title: String
        let isPublished: Bool
    }

    /// One block line read, or nil for any other line.
    private static func entry(from line: String) -> Entry? {
        // A CRLF line keeps its `\r` through a `"\n"` split, and `.whitespaces` does not
        // take it: the title would carry it, and `write` would put it back before its own
        // line break (PG-318).
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-") else { return nil }

        let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        guard let separator = content.firstIndex(of: " ") else { return nil }
        let times = String(content[content.startIndex..<separator])
        let rest = String(content[content.index(after: separator)...])

        let parts = times.split(separator: "-")
        guard parts.count == 2,
              let start = minutes(from: String(parts[0])),
              let read = minutes(from: String(parts[1])),
              let end = end(reading: read, after: start)
        else { return nil }

        let title = rest
            .replacingOccurrences(of: "[published]", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Entry(start: start, end: end, title: title, isPublished: rest.contains("[published]"))
    }

    /// Rewrites the block lines of the section, creating it at the end of the note when
    /// absent and taking it away entirely when the last block goes and nothing else is in it.
    ///
    /// Anything else the section holds - a line of prose, a fenced example, a list line that is
    /// not a block - is the person's and stays: the blocks are written where the first one
    /// was, what stood above it stays above, and what stood below or between blocks follows
    /// the list. Rewriting the whole section dropped all of it on every time-block write.
    static func write(_ blocks: [TimeBlock], into body: String) -> String {
        // The section takes the note's own line break, and every test for one is made with
        // `LineBreak.isTerminator`: a `"\r\n"` pair is one `Character`, so `hasSuffix("\n")`
        // and a search for `"\n#"` never matched in a CRLF note, where the section then ran to
        // the end of the note and a rewrite replaced every heading after it (PG-318).
        let lineBreak = LineBreak.detected(in: body).characters
        guard let section = MarkdownSection.range(under: heading, in: body) else {
            let separator = body.last.map(LineBreak.isTerminator) == true ? lineBreak : lineBreak + lineBreak
            return blocks.isEmpty ? body : body + separator + render(blocks, lineBreak: lineBreak)
        }

        // The section ends at the line break before the next heading, or at the end of the note.
        let end = MarkdownSection.contentEnd(in: body, section: section)
        let kept = otherLines(in: body, section: section)

        var result = body
        guard blocks.isEmpty, kept.above.isEmpty, kept.below.isEmpty else {
            // The writer's own lines (heading, blocks, the blank between groups) take the note's
            // break; a line the person wrote keeps the ending it had, so a mixed note stays mixed
            // (ADR-0065 §D3). The whole section is replaced, the break before the next heading
            // included, so the last line's ending is not counted twice.
            var text = heading + lineBreak
            for group in [kept.above, blockLines(blocks).map { Kept(text: $0, terminator: lineBreak) }, kept.below]
            where !group.isEmpty {
                text += lineBreak
                for line in group { text += line.text + line.terminator }
            }
            if section.upperBound < body.endIndex {
                // A heading follows: one blank line stays between the section and it.
                text += lineBreak
            } else if blocks.isEmpty == false, kept.below.isEmpty {
                // The section ran to the end of the note and ended with a block line: as before,
                // the writer adds no trailing break of its own.
                text.removeLast(lineBreak.count)
            }
            result.replaceSubrange(section.lowerBound..<section.upperBound, with: text)
            return result
        }

        // Deleting the last block deletes the section: a bare `## Timeline` heading is
        // not something the user wrote, and leaving it behind means the note keeps a
        // trace of a plan that no longer exists.
        var start = section.lowerBound
        while start > body.startIndex, body[body.index(before: start)].isWhitespace {
            start = body.index(before: start)
        }
        // One newline closes the paragraph above; nothing at all when the note started
        // with the section.
        result.replaceSubrange(start..<end, with: start == body.startIndex ? "" : lineBreak)
        return result
    }

    /// A line of the section that `write` keeps: its text without a CRLF line's `\r`, and the
    /// ending it had, `\r` and `\n` as they stood, so a kept line is written back byte for byte.
    private struct Kept {
        let text: String
        let terminator: String
    }

    /// The section's lines that are not blocks, split at its first block line, with the blank lines
    /// at either end of a group dropped: `write` puts one blank line between groups itself.
    private static func otherLines(
        in body: String, section: Range<String.Index>
    ) -> (above: [Kept], below: [Kept]) {
        let scalars = body.unicodeScalars
        var above: [Kept] = []
        var below: [Kept] = []
        var seenBlock = false
        for line in MarkdownSection.lines(below: section, in: body) {
            var text = line.text(in: body)
            var terminator = ""
            if text.hasSuffix("\r") {
                text.removeLast()
                terminator = "\r"
            }
            if line.range.upperBound < scalars.endIndex, scalars[line.range.upperBound] == "\n" {
                terminator += "\n"
            }
            let kept = Kept(text: text, terminator: terminator)
            if !line.isCode, entry(from: text) != nil {
                seenBlock = true
            } else if seenBlock {
                below.append(kept)
            } else {
                above.append(kept)
            }
        }
        return (withoutBlankEnds(above), withoutBlankEnds(below))
    }

    private static func withoutBlankEnds(_ lines: [Kept]) -> [Kept] {
        let isBlank: (Kept) -> Bool = { $0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.firstIndex(where: { !isBlank($0) }),
              let last = lines.lastIndex(where: { !isBlank($0) })
        else { return [] }
        return Array(lines[first...last])
    }

    private static func blockLines(_ blocks: [TimeBlock]) -> [String] {
        blocks
            .sorted { $0.startMinutes < $1.startMinutes }
            .map { block in
                "- \(block.startText)-\(block.endText) \(block.title)"
                    + (block.isPublished ? " [published]" : "")
            }
    }

    private static func render(_ blocks: [TimeBlock], lineBreak: String) -> String {
        guard !blocks.isEmpty else { return heading }
        return ([heading, ""] + blockLines(blocks)).joined(separator: lineBreak)
    }

    /// `HH:MM`, with `24:00` as the end of the day - the diary's own reader, shared
    /// (ADR-0075 §D1). Where a `24:00` may stand is `parse`'s business, not this one's.
    static func minutes(from text: String) -> Int? {
        DiarySection.minutes(from: text)
    }

    /// The end a line means, given its start, or nil when the line is not a block
    /// (ADR-0075 §D1).
    ///
    /// A start at `24:00` begins nothing. An end of `00:00` after any start is a block
    /// that ran to midnight, written the way this app used to write it. An end before
    /// the start is a line that wrapped past midnight only when the length it implies is
    /// one a block could have been given; anything longer is a typo, not a wrap, and
    /// stays malformed. Nothing is rewritten here: the corrected form reaches the file on
    /// the next write of the section.
    private static func end(reading end: Int, after start: Int) -> Int? {
        let dayEnd = 24 * 60
        guard start < dayEnd else { return nil }
        if end == 0, start > 0 { return dayEnd }
        if end > 0, end < start {
            return end + dayEnd - start <= TimeBlock.durationRange.upperBound ? dayEnd : nil
        }
        return end > start ? end : nil
    }
}
