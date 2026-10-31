import Foundation

// ADR-0084 §D1 (PG-386, N3 session A).

/// The lines of a note that link to a title, in order, one entry per link.
///
/// A link counts by `Wikilink.isNoteLink`, the predicate `NoteStore.linkTargets(in:)` keeps a
/// link by, so a row never shows a line the index did not count. The title is matched by
/// `Wikilink.names(_:)`, against the title the link names, as the index keys it
/// (`backlinkIndex`): `[[**T**]]` is a backlink of `T`, and a row counts exactly what the index
/// counts (ADR-0097 §D1, amending ADR-0084 §D1). Code is skipped by the parser;
/// the frontmatter is not body. A note that links only through `related` still has its
/// `## Note correlate` bullet in the body, and that line, reason included, is its context.
enum BacklinkContext {
    static func lines(linking title: String, in text: String) -> [String] {
        let body = NoteDocument.parse(text).body
        return WikilinkParser.links(in: body)
            .filter { $0.isNoteLink && $0.names(title) }
            .map { line(holding: $0.range, in: body) }
    }

    /// The trimmed line a range starts on.
    private static func line(holding range: Range<String.Index>, in text: String) -> String {
        let start = text[..<range.lowerBound].lastIndex(where: LineBreak.isTerminator)
            .map { text.index(after: $0) } ?? text.startIndex
        let end = text[range.lowerBound...].firstIndex(where: LineBreak.isTerminator) ?? text.endIndex
        return text[start..<end].trimmingCharacters(in: .whitespaces)
    }
}

/// One backlink row as a pure value: the note, the line that links, how often, whether the
/// link is structural.
struct BacklinkRow: Equatable, Sendable, Identifiable {
    var id: String { path }
    let title: String
    let path: String
    let firstLine: String?
    let count: Int
    let isStructural: Bool

    /// `related` is the source's frontmatter list as written (`"[[Titolo]]"`), read through
    /// `WikilinkParser` the way `IndexSnapshot` reads it.
    static func make(
        path: String, title: String, text: String, linking target: String, related: [String]
    ) -> BacklinkRow {
        let lines = BacklinkContext.lines(linking: target, in: text)
        return BacklinkRow(
            title: title, path: path, firstLine: lines.first, count: lines.count,
            isStructural: isStructural(related: related, linking: target)
        )
    }

    /// Whether a `related` list names `target`. Also what an unreadable row asks of the index's
    /// copy of that list, so «Rendi strutturale» is not offered for a link that already is.
    static func isStructural(related: [String], linking target: String) -> Bool {
        related.contains { entry in
            WikilinkParser.links(in: entry).contains { $0.names(target) }
        }
    }
}
