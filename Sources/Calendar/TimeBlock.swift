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
enum TimeBlockSection {
    static let heading = "## Timeline"

    /// `- 09:00-10:00 Sopralluogo pressa 4` with an optional `[published]` marker.
    static func parse(from body: String, day: CalendarDate) -> [TimeBlock] {
        guard let sectionRange = body.range(of: heading) else { return [] }
        var blocks: [TimeBlock] = []

        for line in body[sectionRange.upperBound...].components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { break }
            guard trimmed.hasPrefix("-") else { continue }

            let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard let separator = content.firstIndex(of: " ") else { continue }
            let times = String(content[content.startIndex..<separator])
            let rest = String(content[content.index(after: separator)...])

            let parts = times.split(separator: "-")
            guard parts.count == 2,
                  let start = minutes(from: String(parts[0])),
                  let read = minutes(from: String(parts[1])),
                  let end = end(reading: read, after: start)
            else { continue }

            let isPublished = rest.contains("[published]")
            let title = rest
                .replacingOccurrences(of: "[published]", with: "")
                .trimmingCharacters(in: .whitespaces)

            blocks.append(TimeBlock(
                day: day,
                startMinutes: start,
                durationMinutes: end - start,
                title: title,
                sourceTaskID: nil,
                isPublished: isPublished
            ))
        }
        return blocks.sorted { $0.startMinutes < $1.startMinutes }
    }

    /// Rewrites the section, creating it at the end of the note when absent and taking
    /// it away entirely when the last block goes.
    static func write(_ blocks: [TimeBlock], into body: String) -> String {
        guard let sectionRange = body.range(of: heading) else {
            let separator = body.hasSuffix("\n") ? "\n" : "\n\n"
            return blocks.isEmpty ? body : body + separator + render(blocks)
        }

        // The section ends at the next heading, or at the end of the note.
        let afterHeading = body[sectionRange.upperBound...]
        let nextHeading = afterHeading.range(of: "\n#")
        let end = nextHeading?.lowerBound ?? body.endIndex

        var result = body
        guard blocks.isEmpty else {
            result.replaceSubrange(sectionRange.lowerBound..<end, with: render(blocks))
            return result
        }

        // Deleting the last block deletes the section: a bare `## Timeline` heading is
        // not something the user wrote, and leaving it behind means the note keeps a
        // trace of a plan that no longer exists.
        var start = sectionRange.lowerBound
        while start > body.startIndex, body[body.index(before: start)].isWhitespace {
            start = body.index(before: start)
        }
        // One newline closes the paragraph above; nothing at all when the note started
        // with the section.
        result.replaceSubrange(start..<end, with: start == body.startIndex ? "" : "\n")
        return result
    }

    private static func render(_ blocks: [TimeBlock]) -> String {
        guard !blocks.isEmpty else { return heading }
        let lines = blocks
            .sorted { $0.startMinutes < $1.startMinutes }
            .map { block in
                "- \(block.startText)-\(block.endText) \(block.title)"
                    + (block.isPublished ? " [published]" : "")
            }
        return ([heading, ""] + lines).joined(separator: "\n")
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
