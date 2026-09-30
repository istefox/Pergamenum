import Foundation

/// One appointment in the diary: a stretch of a day with a name and a note.
///
/// The diary is the day as it was actually lived, written by hand and owned by nobody
/// else: nothing here is read from or written to EventKit, which is what separates it
/// from the Oggi pane's time blocks. It lives in a markdown file like everything else.
struct DiaryEntry: Identifiable, Equatable, Sendable {
    /// Minted here rather than read from the file.
    ///
    /// Identity has to survive an edit that changes the time and the title at once, and
    /// nothing written in the markdown is stable under that. Rereading a day mints new
    /// ids, which is right: those are new values to everything still holding an old one.
    var id = UUID()
    /// Minutes from midnight, so every calculation on the grid is integer arithmetic.
    var startMinutes: Int
    var durationMinutes: Int
    var title: String
    /// Free text under the entry - what was said, what came out of it - kept as one
    /// indented block in the file so the entry stays one thing.
    var note: String = ""
    var colour: DiaryColour = .blu

    var endMinutes: Int { startMinutes + durationMinutes }

    /// `06:00`
    var startText: String { DiaryGrid.timeText(startMinutes) }
    var endText: String { DiaryGrid.timeText(endMinutes) }
    /// `06:00-07:30`
    var timeText: String { "\(startText)-\(endText)" }

    /// What the timeline shows when the title is empty, so an entry is never invisible.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Senza titolo" : trimmed
    }

    func overlaps(_ other: DiaryEntry) -> Bool {
        startMinutes < other.endMinutes && other.startMinutes < endMinutes
    }
}

/// The five colours an entry may carry.
///
/// Deliberately a closed list of theme tokens rather than free colours: a diary that
/// lets you pick any colour stops matching the app the first time the theme changes,
/// and these five follow the theme like everything else.
enum DiaryColour: String, CaseIterable, Identifiable, Sendable {
    case blu
    case verde
    case giallo
    case rosa
    case grigio

    var id: String { rawValue }

    /// The label in the picker, in the UI's language.
    var label: String { rawValue.capitalized }
}

/// The rules of the diary's grid: where the day starts, how finely it is cut, and how
/// long the shortest entry may be.
enum DiaryGrid {
    /// Every time in the diary lands on a ten-minute mark.
    static let step = 10
    static let minimumDuration = 10
    /// The hours the timeline always shows: the morning through to midnight. It grows
    /// upwards when an entry starts before six, so a 04:30 entry written by hand is
    /// never invisible; downwards there is nowhere to grow, since no entry can end
    /// after the day does.
    static let firstHour = 6
    static let lastHour = 24
    static let dayMinutes = 24 * 60

    /// The durations the composer offers: ten minutes to eight hours, ten at a time.
    static let durations: [Int] = Array(stride(from: minimumDuration, through: 8 * 60, by: step))

    /// The minute marks a start time may fall on, within one hour.
    static let minuteMarks: [Int] = Array(stride(from: 0, to: 60, by: step))

    /// `07:30`, and `24:00` for the end of the day.
    ///
    /// Midnight at the end of a block is written as 24:00, not as 00:00: a block from
    /// 23:00 to 00:00 reads as ending before it starts, and read back it would be
    /// refused - the last hour of the day would lose every block written in it.
    static func timeText(_ minutes: Int) -> String {
        guard minutes != dayMinutes else { return "24:00" }
        return String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    /// Rounds to the nearest ten-minute mark, which is the only granularity the diary
    /// has: dragging produces times a person would actually write down.
    static func snap(_ minutes: Int) -> Int {
        max(0, ((minutes + step / 2) / step) * step)
    }

    /// Rounds down, for the mark a click landed inside rather than the nearest one.
    static func snapDown(_ minutes: Int) -> Int {
        max(0, (minutes / step) * step)
    }

    /// Keeps a duration on the grid and above the floor.
    static func clampDuration(_ minutes: Int) -> Int {
        min(max(snap(minutes), minimumDuration), dayMinutes)
    }

    /// Keeps an entry inside the day it belongs to.
    static func clampStart(_ start: Int, duration: Int) -> Int {
        min(max(0, snap(start)), max(0, dayMinutes - clampDuration(duration)))
    }
}

/// Reads and writes the `## Diario` section of a diary note.
///
/// The format is an ordinary markdown list, so a day stays readable in Obsidian, in a
/// terminal, and on the day this app is not around:
///
/// ```
/// ## Diario
///
/// - 06:00-07:30 Palestra [colore:verde]
///   Panca e trazioni, poi corsa leggera.
/// - 09:00-11:30 Sopralluogo pressa 4
/// ```
///
/// The prose above the section and the section itself are kept apart on purpose: the
/// editor edits the first and the timeline owns the second, so the two can never
/// overwrite each other's work.
enum DiarySection {
    static let heading = "## Diario"

    /// The two halves of a diary note: everything that is not the section, and the
    /// entries that are.
    ///
    /// A line inside the section that is neither an entry nor an entry's note is moved
    /// into the prose rather than dropped. It ends up above the section instead of
    /// inside it, which is a change nobody will like as much as losing the line.
    static func split(_ text: String) -> (prose: String, entries: [DiaryEntry]) {
        var reader = Reader()
        for line in text.components(separatedBy: "\n") { reader.read(line) }
        reader.closeEntry()
        var prose = reader.proseLines.joined(separator: "\n")
        // A prose line keeps its `\r`, so the join gives each one its own break back - except
        // the last, when the section took what followed it: its `"\n"` goes, as in an LF note,
        // and the `\r` left without it goes too (PG-321).
        if !reader.proseReachesTheEnd, prose.last == "\r" { prose.removeLast() }
        return (prose, reader.entries.sorted(by: isBefore))
    }

    /// Reads a diary note one line at a time, deciding for each whether it belongs to
    /// the section or to the prose above it.
    ///
    /// A type rather than a closure over local variables: the loop needs seven pieces of
    /// state and a way to close the entry it is in, and written inline it was longer
    /// than any function in this codebase.
    private struct Reader {
        var proseLines: [String] = []
        var entries: [DiaryEntry] = []
        /// Whether the last line read went to the prose, so that nothing the section took
        /// follows the prose's last line.
        private(set) var proseReachesTheEnd = false
        private var current: DiaryEntry?
        private var noteLines: [String] = []
        private var pendingBlankLines = 0
        private var inSection = false

        /// `line` comes from a `"\n"` split, so a CRLF line still ends in its `\r`. The
        /// section is read without it - a heading, a time or a colour marker followed by `\r`
        /// matched nothing, and a CRLF section was all prose (PG-321) - and a line kept as
        /// prose keeps it, so the prose comes back with its own line breaks.
        mutating func read(_ line: String) {
            let content = line.hasSuffix("\r") ? String(line.dropLast()) : line
            proseReachesTheEnd = false
            guard inSection else {
                if content.trimmingCharacters(in: .whitespaces) == heading {
                    inSection = true
                } else {
                    keepAsProse(line)
                }
                return
            }
            readInsideSection(line, content: content)
        }

        private mutating func keepAsProse(_ line: String) {
            proseLines.append(line)
            proseReachesTheEnd = true
        }

        private mutating func readInsideSection(_ line: String, content: String) {
            // A second `## Diario` heading continues the section instead of closing it: it is
            // the same section again, and its entries join the timeline, so the next write
            // leaves one section. Read as prose it would have hidden them from the timeline,
            // and the next write would have dropped them, since `write` strips a section from
            // the prose it is given. After another heading the section already reopened this
            // way, so this makes the two positions agree.
            if content.hasPrefix("#"), content.trimmingCharacters(in: .whitespaces) == heading {
                closeEntry()
                return
            }
            // Any other heading closes the section: what follows is somebody else's.
            if content.hasPrefix("#") {
                closeEntry()
                inSection = false
                keepAsProse(line)
                return
            }
            if let entry = parseEntryLine(content) {
                closeEntry()
                current = entry
                return
            }
            if current != nil, let noteLine = noteContinuation(content) {
                noteLines.append(contentsOf: Array(repeating: "", count: pendingBlankLines))
                pendingBlankLines = 0
                noteLines.append(noteLine)
                return
            }
            if content.trimmingCharacters(in: .whitespaces).isEmpty {
                pendingBlankLines += 1
                return
            }
            closeEntry()
            keepAsProse(line)
        }

        /// The blank-line count is cleared whether or not there was an entry to close:
        /// the empty line under the heading belongs to the heading, and left counted it
        /// became the first line of the first entry's note.
        mutating func closeEntry() {
            defer {
                current = nil
                noteLines = []
                pendingBlankLines = 0
            }
            guard var entry = current else { return }
            entry.note = noteLines.joined(separator: "\n")
            entries.append(entry)
        }
    }

    static func parse(from text: String) -> [DiaryEntry] { split(text).entries }

    /// The note without its diary section, which is what the editor shows.
    static func prose(of text: String) -> String { split(text).prose }

    /// Puts the section back at the end of the prose.
    ///
    /// The prose is stripped again first: called with a whole note rather than with a
    /// prose half, this would otherwise leave two sections in the file.
    ///
    /// The section takes the note's own line break, and the prose's tail is stripped with
    /// `LineBreak.isTerminator`: a closing `"\r\n"` is one `Character`, which `hasSuffix("\n")`
    /// never matched, so a CRLF diary gained LF-joined blocks on every write (PG-321). A prose
    /// with no line break at all takes `noteBreak`, the break of the whole note it came from:
    /// `split` drops the closing break of the prose, so a one-line prose above the section, or a
    /// note that is only the section, shows none of its own (LF when the caller has no note).
    static func write(_ entries: [DiaryEntry], into prose: String, noteBreak: LineBreak = .lf) -> String {
        let lineBreak = (prose.unicodeScalars.contains("\n") ? LineBreak.detected(in: prose) : noteBreak).characters
        var body = split(prose).prose
        while body.last.map(LineBreak.isTerminator) == true { body.removeLast() }

        guard !entries.isEmpty else { return body.isEmpty ? "" : body + lineBreak }
        let section = render(entries, lineBreak: lineBreak)
        return body.isEmpty ? section + lineBreak : body + lineBreak + lineBreak + section + lineBreak
    }

    private static func render(_ entries: [DiaryEntry], lineBreak: String) -> String {
        var lines = [heading, ""]
        for entry in entries.sorted(by: isBefore) {
            let title = entry.title.trimmingCharacters(in: .whitespaces)
            var line = "- \(entry.timeText)"
            if !title.isEmpty { line += " \(title)" }
            if entry.colour != .blu { line += " [colore:\(entry.colour.rawValue)]" }
            lines.append(line)

            guard !entry.note.isEmpty else { continue }
            for noteLine in entry.note.components(separatedBy: "\n") {
                lines.append(noteLine.isEmpty ? "" : "  " + noteLine)
            }
        }
        return lines.joined(separator: lineBreak)
    }

    /// `- 09:00-11:30 Sopralluogo pressa 4 [colore:verde]`, and nothing else.
    ///
    /// An indented line is never an entry: that is how an entry's own note may contain
    /// a bullet list without the second bullet becoming an appointment.
    private static func parseEntryLine(_ line: String) -> DiaryEntry? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t") else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") || trimmed == "-" else { return nil }

        let content = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        let separator = content.firstIndex(of: " ")
        let times = String(separator.map { content[content.startIndex..<$0] } ?? Substring(content))
        var rest = separator.map { String(content[content.index(after: $0)...]) } ?? ""

        let parts = times.split(separator: "-")
        guard parts.count == 2,
              let start = minutes(from: String(parts[0])),
              let end = minutes(from: String(parts[1])),
              end > start
        else { return nil }

        var colour = DiaryColour.blu
        for candidate in DiaryColour.allCases {
            let marker = "[colore:\(candidate.rawValue)]"
            guard rest.hasSuffix(marker) else { continue }
            colour = candidate
            rest = String(rest.dropLast(marker.count))
            break
        }

        return DiaryEntry(
            startMinutes: start,
            durationMinutes: end - start,
            title: rest.trimmingCharacters(in: .whitespaces),
            colour: colour
        )
    }

    /// An indented line under an entry, with the indent taken off.
    private static func noteContinuation(_ line: String) -> String? {
        if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        return nil
    }

    /// `24:00` is read as the end of the day, and is the only hour past 23 accepted -
    /// it is what this app writes for a block that runs to midnight.
    static func minutes(from text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...59).contains(minute)
        else { return nil }
        if hour == 24 { return minute == 0 ? DiaryGrid.dayMinutes : nil }
        guard (0...23).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    /// Start time first, then title, so a rewrite of an unchanged day is byte-identical.
    private static func isBefore(_ lhs: DiaryEntry, _ rhs: DiaryEntry) -> Bool {
        lhs.startMinutes == rhs.startMinutes
            ? lhs.title < rhs.title
            : lhs.startMinutes < rhs.startMinutes
    }
}
