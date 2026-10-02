import Foundation

// ADR-0036 (A pratica is a folder that fills itself from a copy of Mail's index, and
// never from Mail), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 7 - R-28,
// ADR §D5.
//
// `Sources/Features/Pratiche/PraticaTimelineModel.swift`'s own header names this file's
// declaration: "Task 7 owns `PraticaEntry.insert(kind:at:in:)` and the manual-entry
// heading grammar." §D5 fixes what it may and may not do: "the timeline's only writes
// are: insert one heading (one atomic `VaultSession.write`), and the daily-note line
// (R-29)" - so this stays a pure text transform. The write itself, and resolving the
// returned range into `Navigation.jumpToLine(range:ordinal:)`'s ordinal via
// `NoteOutline.entries(in:)`, are the coder's.
enum PraticaEntry {
    /// The two verbs the timeline offers (R-28) - deliberately narrower than
    /// `PraticaTimelineEntry.Kind`, which also carries `.message`: a manual entry can
    /// never be *inserted* as one.
    enum Kind: String, CaseIterable, Equatable, Sendable {
        case note
        case call

        /// The literal word the heading and the daily-note mirror line both carry, and
        /// the one `PraticaManualEntries.heading(_:)` matches back
        /// (`tail.hasPrefix(Kind.call.label)`, `Sources/Core/Pratiche/PraticaManualEntries.swift`).
        var label: String {
            switch self {
            case .note: "Nota"
            case .call: "Telefonata"
            }
        }
    }

    /// What inserting a heading changes (R-28): the whole new source of `pratica.md`,
    /// and where the caret lands - the body line under the new heading, in `text`'s own
    /// UTF-16 offsets, ready for the coder to resolve into
    /// `Navigation.jumpToLine(range:ordinal:)`.
    struct Insertion: Equatable, Sendable {
        var text: String
        var cursorRange: NSRange
    }

    /// `en_US_POSIX` / `"yyyy-MM-dd HH:mm"` in GMT - the formatter behind the heading's date
    /// and time digits, both ways (`headingTimestamp(_:in:)` and `PraticaManualEntries.parse`,
    /// ADR-0076 §D1). A file format, not a presentation, so it cannot follow the person's locale.
    ///
    /// PG-367 (2026-10-01): a heading is written in the writer's own zone, followed by that
    /// zone's offset (`## 2026-06-10 16:06 +02:00 Telefonata · …`), so the digits on disk are
    /// the time the person saw when they wrote it, and the offset makes the instant exact on any
    /// Mac. The digits go through this GMT formatter shifted by the offset rather than through a
    /// formatter set to the zone, so one shared formatter serves every zone. A heading with no
    /// offset - every heading written before PG-367, and the connectors' own fixtures - keeps
    /// meaning UTC, so nothing already on disk moves. The timeline still *draws* the row in the
    /// reader's own zone (`PraticaRowFormat.time`), as it does for a message's own header date.
    static let headingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// The heading's timestamp: `yyyy-MM-dd HH:mm ±hh:mm`, the wall-clock time in `timeZone` and
    /// its offset at that instant, so a summer heading in Rome says `+02:00` and a winter one
    /// `+01:00` (PG-367). `PraticaManualEntries.heading(_:)` reads it back to the same minute.
    static func headingTimestamp(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let offset = timeZone.secondsFromGMT(for: date)
        let wallClock = headingFormatter.string(from: date.addingTimeInterval(TimeInterval(offset)))
        return "\(wallClock) \(UTCOffset.text(offset))"
    }

    /// R-28: the midpoint between two neighbouring entries' timestamps, for
    /// «Inserisci qui». Pure arithmetic over the two dates the caller (which rows are
    /// the neighbours) hands it.
    static func midpoint(between first: Date, and second: Date) -> Date {
        Date(timeIntervalSinceReferenceDate:
            (first.timeIntervalSinceReferenceDate + second.timeIntervalSinceReferenceDate) / 2)
    }

    /// Inserts a `## yyyy-MM-dd HH:mm ±hh:mm <Kind> · <Controparte>` heading with one blank
    /// body line beneath it (R-28), the time in `timeZone` (`headingTimestamp(_:in:)`, PG-367;
    /// injected so a test does not depend on the Mac's zone). Manual entries append at the
    /// end of `source` - the timeline's own ascending order is a read-time property (ADR §D5),
    /// not something this insert has to preserve by placement.
    ///
    /// The returned `cursorRange` is the empty body line under the heading, never the
    /// heading itself: the caller resolves it into
    /// `Navigation.jumpToLine(range:ordinal:)`, and a caret on the heading would put
    /// the first thing typed inside the entry's own title.
    ///
    /// With an `anchor` (a Message-ID, ADR-0076 §D1, R-03) the heading is followed by the anchor
    /// line and then the empty body line, and the caret still lands on the body line. An id
    /// `PraticaEntryAnchor.line(for:)` cannot spell writes a free entry, byte-identical to the
    /// call without an anchor.
    static func insert(
        kind: Kind, at timestamp: Date, counterpart: String, anchor: String? = nil,
        timeZone: TimeZone = .current, in source: String
    ) -> Insertion {
        var heading = "## \(headingTimestamp(timestamp, in: timeZone)) \(kind.label) · \(counterpart)"

        // One blank line between whatever the note already says and the new heading,
        // and never two: `pratica.md` is a file a person also reads in Obsidian.
        // In the note's own line break, tested with `LineBreak.isTerminator`: a `"\r\n"` pair
        // is one `Character`, which `hasSuffix("\n")` never matched, so a CRLF note gained
        // two blank lines and bare LFs (PG-318).
        let lineBreak = LineBreak.detected(in: source).characters
        // The anchor line rides on the heading, so the caret offset below lands past both.
        if let line = anchor.flatMap(PraticaEntryAnchor.line(for:)) { heading += lineBreak + line }
        var text = source
        if !text.isEmpty {
            if text.last.map(LineBreak.isTerminator) != true { text += lineBreak }
            if text.dropLast().last.map(LineBreak.isTerminator) != true { text += lineBreak }
        }
        let headingEnd = (text as NSString).length + (heading as NSString).length
        text += heading + lineBreak + lineBreak
        // Just past the heading's own line break, which is the start of the empty body
        // line - a zero-length range, because nothing is selected, only placed.
        return Insertion(
            text: text,
            cursorRange: NSRange(location: headingEnd + (lineBreak as NSString).length, length: 0)
        )
    }

    /// Who an entry anchored to a message is with (ADR-0076 §D1, R-03): the sender of a received
    /// message, else the first recipient that is not one of `ownAddresses`, else the first Cc -
    /// `MessageDocument.counterpart`'s rule, spelled as `EmailAddress.displayText`. Nil when the
    /// message names nobody.
    static func counterpart(
        ofMessage frontmatter: MessageDocument.MailFrontmatter, ownAddresses: Set<String>
    ) -> String? {
        MessageDocument.counterpart(
            direction: frontmatter.direction,
            from: EmailHeaderParser.parseAddress(frontmatter.from),
            to: frontmatter.to.compactMap(EmailHeaderParser.parseAddress),
            cc: frontmatter.cc.compactMap(EmailHeaderParser.parseAddress),
            ownAddresses: ownAddresses
        )?.displayText
    }
}
