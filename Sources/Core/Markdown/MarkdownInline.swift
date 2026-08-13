import Foundation

/// A run of text inside a block, with what it is.
///
/// The parser hands back spans rather than an `AttributedString` so the styling can
/// come from the theme's own tokens in the view, and so the parse can be checked
/// without rendering anything.
struct MarkdownSpan: Equatable, Sendable {
    enum Style: Hashable, Sendable {
        case strong
        case emphasis
        case code
        case strikethrough
    }

    enum Link: Equatable, Sendable {
        /// `[[Nota]]` or `[[Nota|testo]]`: a note in this vault, by title.
        case note(title: String)
        /// `[testo](url)`: anything else, opened by the system.
        case url(String)
    }

    var text: String
    var styles: Set<Style> = []
    var link: Link?
}

enum MarkdownInlineParser {
    /// Splits one paragraph's text into styled runs.
    ///
    /// Deliberately small: bold, italic, inline code, strikethrough, wikilinks and
    /// markdown links, which is what the vault's notes actually contain. Anything it
    /// does not recognise stays visible as written rather than disappearing, which is
    /// the failure that matters in a reading view - a renderer that silently swallows
    /// syntax it cannot parse loses the user's text.
    static func spans(in text: String) -> [MarkdownSpan] {
        var result: [MarkdownSpan] = []
        var plain = ""
        var index = text.startIndex

        func flush() {
            guard !plain.isEmpty else { return }
            result.append(MarkdownSpan(text: plain))
            plain = ""
        }

        while index < text.endIndex {
            if let match = match(at: text[index...]) {
                flush()
                result.append(contentsOf: match.spans)
                index = match.end
                continue
            }
            plain.append(text[index])
            index = text.index(after: index)
        }
        flush()
        return result
    }

    /// What the text starts with, if it starts with anything at all.
    private struct Match {
        var spans: [MarkdownSpan]
        var end: String.Index
    }

    private static func match(at rest: Substring) -> Match? {
        // Code first: inside backticks nothing else is markup.
        code(at: rest) ?? wikilink(at: rest) ?? link(at: rest) ?? emphasis(at: rest)
    }

    private static func code(at rest: Substring) -> Match? {
        guard rest.hasPrefix("`"), let close = rest.dropFirst().range(of: "`") else { return nil }
        let inner = String(rest.dropFirst()[..<close.lowerBound])
        return Match(spans: [MarkdownSpan(text: inner, styles: [.code])], end: close.upperBound)
    }

    private static func wikilink(at rest: Substring) -> Match? {
        guard rest.hasPrefix("[["), let close = rest.dropFirst(2).range(of: "]]") else { return nil }
        let inner = String(rest.dropFirst(2)[..<close.lowerBound])
        let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let title = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let label = parts.count > 1 ? String(parts[1]) : title
        return Match(
            spans: [MarkdownSpan(text: label, link: .note(title: title))],
            end: close.upperBound
        )
    }

    private static func link(at rest: Substring) -> Match? {
        // An embed renders as its own label in reading mode; the file itself is
        // reachable from the editor and from Quick Look.
        let body = rest.hasPrefix("![") ? rest.dropFirst() : rest
        guard body.hasPrefix("["), let parsed = markdownLink(in: body) else { return nil }
        return Match(
            spans: [MarkdownSpan(text: parsed.label, link: .url(parsed.target))],
            end: parsed.end
        )
    }

    private static func emphasis(at rest: Substring) -> Match? {
        guard let (marker, style) = emphasisMarker(at: rest),
              opensEmphasis(rest, marker: marker),
              let close = closingRange(of: marker, in: rest.dropFirst(marker.count))
        else { return nil }

        let inner = String(rest.dropFirst(marker.count)[..<close.lowerBound])
        // Nested runs keep their own styling: **testo con *corsivo*** is one strong
        // span containing an emphasised one.
        let nested = spans(in: inner).map { span -> MarkdownSpan in
            var styled = span
            styled.styles.insert(style)
            return styled
        }
        return Match(spans: nested, end: close.upperBound)
    }

    private static func emphasisMarker(at rest: Substring) -> (String, MarkdownSpan.Style)? {
        if rest.hasPrefix("**") { return ("**", .strong) }
        if rest.hasPrefix("__") { return ("__", .strong) }
        if rest.hasPrefix("~~") { return ("~~", .strikethrough) }
        if rest.hasPrefix("*") { return ("*", .emphasis) }
        if rest.hasPrefix("_") { return ("_", .emphasis) }
        return nil
    }

    /// Whether a marker opens a span at all.
    ///
    /// `2 * 3 * 4` is arithmetic, not emphasis: a marker followed by a space opens
    /// nothing. Without this the parser ate both asterisks and rendered "2  3  4",
    /// which is the one thing a reading view must never do - lose the text.
    private static func opensEmphasis(_ rest: Substring, marker: String) -> Bool {
        guard let next = rest.dropFirst(marker.count).first else { return false }
        return !next.isWhitespace
    }

    /// Finds the marker that closes a span.
    ///
    /// A run longer than the marker closes at the END of the run: in
    /// `**forte con *corsivo***` the first `**` found sits inside the final `***`,
    /// and stopping there would leave a stray asterisk and lose the inner emphasis.
    private static func closingRange(of marker: String, in haystack: Substring) -> Range<String.Index>? {
        var search = haystack
        while let found = search.range(of: marker) {
            // A marker preceded by a space closes nothing, symmetrically with the
            // opening rule.
            if haystack[..<found.lowerBound].last?.isWhitespace == true {
                search = haystack[found.upperBound...]
                continue
            }
            guard let markerCharacter = marker.first else { return found }
            var end = found.upperBound
            while end < haystack.endIndex, haystack[end] == markerCharacter {
                end = haystack.index(after: end)
            }
            guard haystack.distance(from: found.lowerBound, to: end) > marker.count else { return found }
            return haystack.index(end, offsetBy: -marker.count)..<end
        }
        return nil
    }

    /// `[label](target)`, and where it ends.
    private struct ParsedLink {
        var label: String
        var target: String
        var end: String.Index
    }

    private static func markdownLink(in rest: Substring) -> ParsedLink? {
        guard let labelEnd = rest.dropFirst().range(of: "]") else { return nil }
        let label = String(rest.dropFirst()[..<labelEnd.lowerBound])
        let afterLabel = rest[labelEnd.upperBound...]
        guard afterLabel.hasPrefix("("), let close = afterLabel.dropFirst().range(of: ")")
        else { return nil }
        let target = String(afterLabel.dropFirst()[..<close.lowerBound])
        return ParsedLink(label: label, target: target, end: close.upperBound)
    }
}
