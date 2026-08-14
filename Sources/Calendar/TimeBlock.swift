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

    static func timeText(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// The default duration of a block created by dropping a task (SPEC §8.3).
    static let defaultDuration = 30

    /// Snaps a minute value to the nearest quarter hour, which is what makes dragging
    /// produce times a person would actually write down.
    static func snap(_ minutes: Int, to step: Int = 15) -> Int {
        max(0, ((minutes + step / 2) / step) * step)
    }

    /// The first start at or after `preferred` where a block of `duration` sits in no
    /// other block, or nil when the day runs out.
    ///
    /// Placed rather than overlapped: two blocks at the same time say nothing about
    /// what the day actually looks like, which is the whole point of a timeline.
    static func freeStart(from preferred: Int, in blocks: [TimeBlock], duration: Int) -> Int? {
        var start = snap(preferred)
        while blocks.contains(where: { $0.startMinutes <= start && start < $0.endMinutes }) {
            start += max(15, duration)
            guard start < 24 * 60 else { return nil }
        }
        return start
    }

    func overlaps(_ other: TimeBlock) -> Bool {
        day == other.day && startMinutes < other.endMinutes && other.startMinutes < endMinutes
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
                  let end = minutes(from: String(parts[1])),
                  end > start
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

    /// Rewrites the section, creating it at the end of the note when absent.
    static func write(_ blocks: [TimeBlock], into body: String) -> String {
        let rendered = render(blocks)

        guard let sectionRange = body.range(of: heading) else {
            let separator = body.hasSuffix("\n") ? "\n" : "\n\n"
            return blocks.isEmpty ? body : body + separator + rendered
        }

        // The section ends at the next heading, or at the end of the note.
        let afterHeading = body[sectionRange.upperBound...]
        let nextHeading = afterHeading.range(of: "\n#")
        let end = nextHeading?.lowerBound ?? body.endIndex

        var result = body
        result.replaceSubrange(sectionRange.lowerBound..<end, with: rendered)
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

    static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }
}
