import Foundation

// ADR-0076 §D1 (PG-338): the only reader of `pratica.md`'s manual-entry grammar. The app's
// timeline and both connectors parse through it, so the grammar, the anchor and the ids the
// app builds from `ordinal`/`occurrence` cannot drift apart again (ADR-0076 F1).
//
// Foundation-only on purpose: it compiles into `perg` and `pergamenum-mcp` through the
// `Sources/Core/**` glob.

/// One manual entry of `pratica.md`: a `## yyyy-MM-dd HH:mm [±hh:mm] <Kind> · <Controparte>`
/// heading and every line under it up to the next `## ` heading or the end of the file.
struct PraticaManualEntry: Equatable, Sendable {
    var kind: PraticaEntry.Kind
    /// The heading's instant: its digits read through `PraticaEntry.headingFormatter`, less the
    /// heading's offset when it carries one, as UTC when it does not (PG-356).
    var date: Date
    /// The heading's tail: everything after the time and the offset, e.g. `Telefonata · Mario Rossi`.
    var subject: String
    /// Everything after the tail's first ` · `, which may itself contain ` · `.
    var counterpart: String
    /// The Message-ID of the anchor line directly under the heading, angle brackets included,
    /// or nil for a free entry (R-01).
    var anchor: String?
    /// The entry's lines, the position-one anchor line excluded, joined by LF and trimmed.
    var body: String
    /// The entry's index among the entries of the file, in file order.
    var ordinal: Int
    /// How many earlier entries share this heading's minute: the app's id suffix.
    var occurrence: Int
    /// UTF-16, in the full source, frontmatter included: from the heading's first character to
    /// the start of the next `## ` line, or to the end of the source.
    var blockRange: NSRange
    /// UTF-16, in the full source: the anchor line's own characters, surrounding whitespace
    /// included, its line break excluded. Nil when the entry carries no anchor.
    var anchorLineRange: NSRange?
}

enum PraticaManualEntries {
    /// One physical line of the source: its content (no terminator) and where it sits.
    struct Line {
        var content: String
        /// UTF-16 location of the line's first character in the full source.
        var location: Int
        /// UTF-16 length of the content, the terminator excluded.
        var length: Int
        /// UTF-16 length of the terminator: 2 for CRLF, 1 for LF, 0 at the end of the source.
        var terminatorLength: Int

        var end: Int { location + length + terminatorLength }
    }

    /// Every manual entry of `source`, in file order. A `## ` line that is not an entry heading
    /// ends the open entry and opens nothing; the lines under it belong to no entry.
    static func parse(_ source: String) -> [PraticaManualEntry] {
        struct OpenEntry {
            var heading: Heading
            var start: Int
            var lines: [Line] = []
        }
        var entries: [PraticaManualEntry] = []
        var open: OpenEntry?
        var sourceEnd = 0

        func flush(endingAt end: Int) {
            guard let current = open else { return }
            open = nil
            let first = current.lines.first
            let anchor = first.flatMap { PraticaEntryAnchor.messageID(inLine: $0.content) }
            let bodyLines = (anchor == nil ? current.lines : Array(current.lines.dropFirst()))
            let occurrence = entries.filter { $0.date == current.heading.date }.count
            entries.append(PraticaManualEntry(
                kind: current.heading.kind,
                date: current.heading.date,
                subject: current.heading.subject,
                counterpart: current.heading.counterpart,
                anchor: anchor,
                body: bodyLines.map(\.content).joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                ordinal: entries.count,
                occurrence: occurrence,
                blockRange: NSRange(location: current.start, length: end - current.start),
                anchorLineRange: anchor == nil ? nil : first.map { NSRange(location: $0.location, length: $0.length) }
            ))
        }

        for line in bodyLines(of: source) {
            sourceEnd = line.end
            if line.content.hasPrefix("## ") {
                flush(endingAt: line.location)
                if let heading = heading(line.content) { open = OpenEntry(heading: heading, start: line.location) }
                continue
            }
            open?.lines.append(line)
        }
        flush(endingAt: sourceEnd)
        return entries
    }

    /// The body of `source` (everything after the frontmatter block) split into lines, each
    /// addressed in the full source. The body is a verbatim suffix of the source
    /// (`NoteDocument.body`), so its offset is the difference of the two UTF-16 lengths.
    static func bodyLines(of source: String) -> [Line] {
        let body = NoteDocument.parse(source).body
        var location = source.utf16.count - body.utf16.count
        let raw = body.components(separatedBy: "\n")
        var lines: [Line] = []
        lines.reserveCapacity(raw.count)
        for (index, piece) in raw.enumerated() {
            let isLast = index == raw.count - 1
            let hasCR = !isLast && piece.hasSuffix("\r")
            let content = hasCR ? String(piece.dropLast()) : piece
            let length = content.utf16.count
            let terminator = isLast ? 0 : (hasCR ? 2 : 1)
            lines.append(Line(content: content, location: location, length: length, terminatorLength: terminator))
            location += length + terminator
        }
        return lines
    }

    struct Heading {
        var kind: PraticaEntry.Kind
        var date: Date
        var subject: String
        var counterpart: String
    }

    /// `## 2026-06-10 16:06 +02:00 Telefonata · Mario Rossi`, or the legacy
    /// `## 2026-06-10 14:06 Telefonata · Mario Rossi`. Anything else under `##` is an ordinary
    /// heading of the note and answers nil.
    ///
    /// PG-356: a third token that is exactly `±hh:mm` (`UTCOffset.seconds`) is the zone the
    /// digits were written in, and never part of the subject or the kind; a heading without one
    /// is read as UTC, which is what every heading written before PG-356 means. An offset with
    /// nothing after it is not an entry, as a date and a time with nothing after them are not.
    static func heading(_ line: String) -> Heading? {
        guard line.hasPrefix("## ") else { return nil }
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let digits = PraticaEntry.headingFormatter.date(from: "\(parts[0]) \(parts[1])")
        else { return nil }
        var tail = String(parts[2])
        var date = digits
        let tokens = tail.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        // Two edge cases accepted on purpose: a heading that is only timestamp plus offset is
        // not an entry, and a hand-written subject starting with a `±hh:mm` token now reads as an offset.
        if let first = tokens.first, let offset = UTCOffset.seconds(first) {
            guard tokens.count == 2 else { return nil }
            tail = tokens[1].trimmingCharacters(in: .whitespaces)
            date = digits.addingTimeInterval(-TimeInterval(offset))
        }
        return Heading(
            kind: tail.hasPrefix(PraticaEntry.Kind.call.label) ? .call : .note,
            date: date,
            subject: tail,
            counterpart: tail.components(separatedBy: " · ").dropFirst().joined(separator: " · ")
        )
    }
}

/// The anchor line's codec (ADR-0076 §D1, R-01): `<!-- pergamenum-message: <Message-ID> -->`.
enum PraticaEntryAnchor {
    static let prefix = "<!-- pergamenum-message: "
    static let suffix = " -->"

    /// The anchor line for `messageID`, or nil when the id is empty or holds `-->`, a CR or an
    /// LF: none of those survives the round trip through `messageID(inLine:)`.
    static func line(for messageID: String) -> String? {
        guard !messageID.isEmpty,
              !messageID.contains("-->"),
              !messageID.unicodeScalars.contains(where: { $0 == "\r" || $0 == "\n" })
        else { return nil }
        return prefix + messageID + suffix
    }

    /// The Message-ID an anchor line carries, verbatim, or nil when `line` is not one. Surrounding
    /// whitespace is allowed; the prefix and the suffix are exact, and the id must not be empty.
    static func messageID(inLine line: some StringProtocol) -> String? {
        let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix), trimmed.hasSuffix(suffix),
              trimmed.utf16.count > prefix.utf16.count + suffix.utf16.count
        else { return nil }
        let id = String(trimmed.dropFirst(prefix.count).dropLast(suffix.count))
        return id.isEmpty ? nil : id
    }
}
