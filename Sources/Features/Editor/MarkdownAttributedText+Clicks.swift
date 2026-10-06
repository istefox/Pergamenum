import AppKit

/// The click a tag or a date run carries (n1-seams R-12, R-13): its URL, built and decoded
/// beside the note and embed URLs in `MarkdownAttributedText.swift`, and the attributes the
/// styling passes merge onto the run.
extension MarkdownAttributedText {
    static let tagHost = "tag"
    static let dayHost = "day"

    /// A tag's click URL, built the way `noteURL(for:)` builds a note's, on a host of its own
    /// so a tag never decodes as a note of the same name.
    static func tagURL(for tag: Tag) -> URL {
        url(host: tagHost, item: URLQueryItem(name: "name", value: tag.description))
    }

    /// A day's click URL, its ISO date as the query item.
    static func dayURL(for day: CalendarDate) -> URL {
        url(host: dayHost, item: URLQueryItem(name: "date", value: day.description))
    }

    /// The click URL a tag or date span carries, or nil when the span is no click target
    /// (n1-seams R-12, R-13). A `.tag` is one when `Tag(_:)` parses it - the one door for the
    /// closed schema, with or without its `#`. A `.scheduled`/`.due` is one when what follows
    /// its `>`/`!` in `source` is a real `CalendarDate`. An `.annotation` (`@done(…)`,
    /// `@remind(…)`, `@repeat(…)`) and every other span are not.
    static func clickURL(for span: MarkdownStyler.Span, source: Substring) -> URL? {
        switch span {
        case .tag(let name):
            return Tag(name).map(tagURL(for:))
        case .scheduled, .due:
            return CalendarDate(iso: String(source.dropFirst())).map(dayURL(for:))
        // Exhaustive on purpose, as `ProseParagraphSpacing.shapesItsLine` is: a new span has to
        // say whether it is a click target rather than fall silently into "no".
        case .annotation, .frontmatter, .heading, .headingMarker, .bold, .italic, .emphasisMarker,
             .strikethrough, .strikethroughMarker, .code, .codeToken, .codeBlock, .linkSyntax,
             .linkTarget, .embedTarget, .embedRun, .tableRun, .viewBlockRun, .listMarker,
             .taskMarker, .blockquoteMarker, .horizontalRule, .messageAnchor:
            return nil
        }
    }

    /// The click half of a tag or date run (n1-seams R-12, R-13): `clickable`'s link without its
    /// colour, so the run keeps the token colour its span already has. Empty
    /// for every span `clickURL(for:source:)` answers nil for. Shared with the Workspace card's
    /// table, which merges it the same way.
    static func clickAttributes(
        for span: MarkdownStyler.Span, source: Substring
    ) -> [NSAttributedString.Key: Any] {
        guard let url = clickURL(for: span, source: source) else { return [:] }
        return [.editorLink: url]
    }
}
