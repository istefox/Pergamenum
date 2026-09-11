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
//
// Every declaration below is a tester-declared boundary (ADR-0155 §D1): stubbed to a
// wrong-but-safe constant, never `fatalError`, so a test that calls it exercises a
// real (failing) assertion instead of crashing the process.
enum PraticaEntry {
    /// The two verbs the timeline offers (R-28) - deliberately narrower than
    /// `PraticaTimelineEntry.Kind`, which also carries `.message`: a manual entry can
    /// never be *inserted* as one.
    enum Kind: String, CaseIterable, Equatable, Sendable {
        case note
        case call

        /// The literal word the heading and the daily-note mirror line both carry, and
        /// the one `PraticheController.parseEntryHeading` already matches back
        /// (`tail.hasPrefix("Telefonata")`, `Sources/Features/Pratiche/PraticheController.swift`).
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

    /// `en_US_POSIX` / `"yyyy-MM-dd HH:mm"` - the same pattern
    /// `PraticheController.entryHeadingFormatter` already reads back. A file format,
    /// not a presentation, so it cannot follow the person's locale (that formatter's
    /// own comment).
    ///
    /// The time zone is pinned to GMT for the same reason the locale is pinned, and
    /// `Tests/PraticaEntryTests.swift` requires it: a heading written at `14:06Z` reads
    /// back `14:06` on any Mac, in any zone, which is what makes the file portable and
    /// the round trip through `PraticheController.entryHeadingFormatter` (pinned the
    /// same way, for the same reason) an identity. `DateEntry` and `PlaudTimestamp`
    /// already pin `secondsFromGMT: 0` on their own file-format formatters. The
    /// timeline still *draws* the row in the reader's own zone
    /// (`PraticaRowFormat.time`), as it does for a message's own header date.
    static let headingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// R-28: the midpoint between two neighbouring entries' timestamps, for
    /// «Inserisci qui». Pure arithmetic over the two dates the caller (which rows are
    /// the neighbours) hands it.
    static func midpoint(between first: Date, and second: Date) -> Date {
        Date(timeIntervalSinceReferenceDate:
            (first.timeIntervalSinceReferenceDate + second.timeIntervalSinceReferenceDate) / 2)
    }

    /// Inserts a `## yyyy-MM-dd HH:mm <Kind> · <Controparte>` heading with one blank
    /// body line beneath it (R-28). Manual entries append at the end of `source` - the
    /// timeline's own ascending order is a read-time property (ADR §D5), not something
    /// this insert has to preserve by placement.
    ///
    /// The returned `cursorRange` is the empty body line under the heading, never the
    /// heading itself: the caller resolves it into
    /// `Navigation.jumpToLine(range:ordinal:)`, and a caret on the heading would put
    /// the first thing typed inside the entry's own title.
    static func insert(
        kind: Kind, at timestamp: Date, counterpart: String, in source: String
    ) -> Insertion {
        let heading = "## \(headingFormatter.string(from: timestamp)) \(kind.label) · \(counterpart)"

        // One blank line between whatever the note already says and the new heading,
        // and never two: `pratica.md` is a file a person also reads in Obsidian.
        var text = source
        if !text.isEmpty {
            if !text.hasSuffix("\n") { text += "\n" }
            if !text.hasSuffix("\n\n") { text += "\n" }
        }
        let headingEnd = (text as NSString).length + (heading as NSString).length
        text += heading + "\n\n"
        // Just past the heading's own newline, which is the start of the empty body
        // line - a zero-length range, because nothing is selected, only placed.
        return Insertion(text: text, cursorRange: NSRange(location: headingEnd + 1, length: 0))
    }
}
