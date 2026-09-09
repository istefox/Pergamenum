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
    static let headingFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// R-28: the midpoint between two neighbouring entries' timestamps, for
    /// «Inserisci qui». Pure arithmetic over the two dates the caller (which rows are
    /// the neighbours) hands it.
    ///
    /// RED stub: always returns `first`, unchanged - a test pinning the actual
    /// midpoint fails on the assertion rather than by crashing.
    static func midpoint(between first: Date, and second: Date) -> Date {
        first
    }

    /// Inserts a `## yyyy-MM-dd HH:mm <Kind> · <Controparte>` heading with one blank
    /// body line beneath it (R-28). Manual entries append at the end of `source` - the
    /// timeline's own ascending order is a read-time property (ADR §D5), not something
    /// this insert has to preserve by placement.
    ///
    /// RED stub: returns `source` completely unchanged, with a zero-length cursor at
    /// its very end - wrong for every case, never a crash.
    static func insert(
        kind: Kind, at timestamp: Date, counterpart: String, in source: String
    ) -> Insertion {
        Insertion(text: source, cursorRange: NSRange(location: (source as NSString).length, length: 0))
    }
}
