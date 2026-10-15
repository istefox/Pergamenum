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
        /// `==testo==` (ADR-0087 §D2): opened and closed by `~~`'s rule, never inside a code span.
        case highlight
    }

    enum Link: Equatable, Sendable {
        /// `[[Nota]]` or `[[Nota|testo]]`: a note in this vault, by title.
        case note(title: String)
        /// `[testo](url)`: anything else, opened by the system.
        case url(String)
        /// `![[foto.png]]` or `![[foto.png|300]]`: an embed, by its reference - the part before
        /// `|`, so a size suffix never shows (ADR-0065 §D9.2, R-17).
        case embed(target: String)
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
    ///
    /// A projection of the token scanner (ADR-0082 §D1): the app's own conventions - `#tag`,
    /// `>date`, `!date`, `@annotation` - are not looked for here, so they stay plain text merged
    /// with their neighbours, exactly as the exporter has always shown them.
    static func spans(in text: String) -> [MarkdownSpan] {
        project(scan(text[...], conventions: false, startsAtBoundary: true), over: text[...])
    }

    /// The inline constructs of `text`, in the order the scanner finds them: each construct, then
    /// the ones inside it (an emphasis run's content, a link's label, a wikilink's interior).
    /// Unlike `spans(in:)`, the app's own conventions are tokens here: `#tag`, `>date`, `!date`
    /// and `@annotation` (ADR-0082 §D1).
    ///
    /// Takes a `Substring` so a line of a note is scanned in place: every range indexes the note.
    static func tokens(in text: Substring) -> [MarkdownInlineToken] {
        var result: [MarkdownInlineToken] = []
        func flatten(_ nodes: [Node]) {
            for node in nodes {
                result.append(node.token)
                flatten(node.children)
            }
        }
        flatten(scan(text, conventions: true, startsAtBoundary: true))
        return result
    }

    // MARK: The scanner

    /// One construct the scanner found, and the constructs inside it.
    private struct Node {
        var token: MarkdownInlineToken
        var children: [Node] = []
    }

    /// The one inline walk both readers share. `conventions` adds the app's own tokens;
    /// `startsAtBoundary` says whether the first character may open a `#tag`, which needs a space
    /// or the start of the run before it.
    private static func scan(_ text: Substring, conventions: Bool, startsAtBoundary: Bool) -> [Node] {
        var nodes: [Node] = []
        var index = text.startIndex
        var previous: Character?
        // The character before the current run of `_`: CommonMark reads a delimiter run as a
        // whole, so the second `_` of `a__b` is as intraword as the first (ADR-0077 §D5).
        var beforeRun: Character?

        while index < text.endIndex {
            let character = text[index]
            if character != "_" || previous != "_" { beforeRun = previous }
            let boundary = index == text.startIndex ? startsAtBoundary : previous == " "
            if let node = match(at: text[index...], after: beforeRun, conventions: conventions, boundary: boundary) {
                nodes.append(node)
                let end = node.token.range.upperBound
                previous = text[text.index(before: end)]
                index = end
                continue
            }
            previous = character
            index = text.index(after: index)
        }
        return nodes
    }

    /// What the text starts with, if it starts with anything at all.
    ///
    /// `previous` is the character before `rest` (before its run of `_`), nil at the start.
    private static func match(
        at rest: Substring, after previous: Character?, conventions: Bool, boundary: Bool
    ) -> Node? {
        // Code first: inside backticks nothing else is markup.
        // An embed before the wikilink and link fallbacks: neither reads `![[`, so the `!` was
        // left behind as plain text beside a note link (ADR-0065 §D9.2, R-17).
        if let node = code(at: rest, after: previous) ?? embed(at: rest)
            ?? wikilink(at: rest, conventions: conventions)
            ?? link(at: rest, conventions: conventions)
            ?? emphasis(at: rest, after: previous, conventions: conventions) {
            return node
        }
        return conventions ? convention(at: rest, boundary: boundary) : nil
    }

    private static func embed(at rest: Substring) -> Node? {
        guard rest.hasPrefix("![["), let close = rest.dropFirst(3).range(of: "]]") else { return nil }
        let open = rest.startIndex..<rest.dropFirst(3).startIndex
        let inner = rest[open.upperBound..<close.lowerBound]
        let target = String(inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
            .trimmingCharacters(in: .whitespaces)
        return Node(token: MarkdownInlineToken(
            range: rest.startIndex..<close.upperBound, kind: .embed(target: target, syntax: [open, close])
        ))
    }

    /// A code span opens with a run of backticks and closes at the next run of exactly as many,
    /// CommonMark's rule, so ``` `` a ` b `` ``` is one span whose delimiters are the two `` `` ``
    /// runs (ADR-0087 §D5). A run with no partner is text, as a whole: the scanner's next step is
    /// inside that run, and `previous` refuses it there.
    private static func code(at rest: Substring, after previous: Character?) -> Node? {
        guard rest.first == "`", previous != "`" else { return nil }
        let open = rest.prefix(while: { $0 == "`" })
        var search = rest[open.endIndex...]
        while let found = search.firstIndex(of: "`") {
            let close = search[found...].prefix(while: { $0 == "`" })
            if close.count == open.count {
                return Node(token: MarkdownInlineToken(
                    range: rest.startIndex..<close.endIndex,
                    kind: .code(delimiters: [open.startIndex..<open.endIndex, close.startIndex..<close.endIndex])
                ))
            }
            search = search[close.endIndex...]
        }
        return nil
    }

    /// A wikilink's interior is scanned for the emphasis it may carry (`[[**Nota**]]`, issue #188),
    /// never for the app's conventions: a `#` there names a section, not a tag.
    private static func wikilink(at rest: Substring, conventions: Bool) -> Node? {
        guard rest.hasPrefix("[["), let close = rest.dropFirst(2).range(of: "]]") else { return nil }
        let open = rest.startIndex..<rest.dropFirst(2).startIndex
        let inner = rest[open.upperBound..<close.lowerBound]
        let title = String(inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)[0])
            .trimmingCharacters(in: .whitespaces)
        return Node(
            token: MarkdownInlineToken(
                range: rest.startIndex..<close.upperBound, kind: .wikilink(target: title, syntax: [open, close])
            ),
            children: conventions ? scan(inner, conventions: false, startsAtBoundary: false) : []
        )
    }

    private static func link(at rest: Substring, conventions: Bool) -> Node? {
        // An embed renders as its own label in reading mode; the file itself is
        // reachable from the editor and from Quick Look.
        let body = rest.hasPrefix("![") ? rest.dropFirst() : rest
        guard body.hasPrefix("["), let parsed = markdownLink(in: body) else { return nil }
        let open = rest.startIndex..<parsed.label.lowerBound
        let close = parsed.label.upperBound..<parsed.end
        return Node(
            token: MarkdownInlineToken(
                range: rest.startIndex..<parsed.end, kind: .link(url: parsed.target, syntax: [open, close])
            ),
            // The label is markdown too, so `[**forte**](url)` is strong and linked (ADR-0077 §D5).
            children: scan(rest[parsed.label], conventions: conventions, startsAtBoundary: false)
        )
    }

    private static func emphasis(at rest: Substring, after previous: Character?, conventions: Bool) -> Node? {
        guard let (marker, style) = emphasisMarker(at: rest),
              opensEmphasis(rest, marker: marker, after: previous),
              let close = closingRange(of: marker, in: rest.dropFirst(marker.count))
        else { return nil }

        let open = rest.startIndex..<rest.dropFirst(marker.count).startIndex
        let delimiters = [open, close]
        let kind: MarkdownInlineToken.Kind = switch style {
        case .strong: .strong(delimiters: delimiters)
        case .strikethrough: .strikethrough(delimiters: delimiters)
        case .highlight: .highlight(delimiters: delimiters)
        default: .emphasis(delimiters: delimiters)
        }
        // Nested runs keep their own styling: **testo con *corsivo*** is one strong
        // span containing an emphasised one.
        return Node(
            token: MarkdownInlineToken(range: rest.startIndex..<close.upperBound, kind: kind),
            children: scan(rest[open.upperBound..<close.lowerBound], conventions: conventions, startsAtBoundary: true)
        )
    }

    // MARK: The app's own conventions

    /// `#tag`, `>2026-08-15`, `!2026-08-20` or `@done(...)`, moved here from the editor's styler
    /// so the grammar has one home (ADR-0082 §D2). Each is atomic: what it covers is read as
    /// nothing else.
    private static func convention(at rest: Substring, boundary: Bool) -> Node? {
        guard let first = rest.first else { return nil }
        let length: Int?
        let kind: MarkdownInlineToken.Kind
        switch first {
        case "#":
            // An inline tag, not a heading: it must be preceded by a space or start the run, or
            // `C#` and a URL fragment would both become tags.
            guard boundary else { return nil }
            length = tagLength(rest)
            kind = .tag(String(rest.prefix(length ?? 0)))
        case ">", "!":
            length = CalendarDate(iso: String(rest.dropFirst().prefix(10))) == nil ? nil : 11
            kind = first == ">" ? .scheduled : .due
        case "@":
            length = annotationLength(rest)
            kind = .annotation
        default:
            return nil
        }
        guard let length else { return nil }
        return Node(token: MarkdownInlineToken(
            range: rest.startIndex..<rest.index(rest.startIndex, offsetBy: length), kind: kind
        ))
    }

    /// Length of a `#word` run: the hash and the letters, digits and hyphens after it.
    ///
    /// The token is the hashtag as written. Whether it names a tag of the vocabulary is
    /// `Tag(_:)`'s question (SPEC §4.4, T-01), asked by whoever draws it: `#varie` is a hashtag
    /// with no namespace, and the editor styles it as nothing.
    private static func tagLength(_ rest: Substring) -> Int? {
        let run = rest.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
        return run.isEmpty ? nil : run.count + 1
    }

    /// Length of `@name(...)`, through the first closing parenthesis.
    private static func annotationLength(_ rest: Substring) -> Int? {
        let name = rest.dropFirst().prefix(while: \.isLetter)
        guard !name.isEmpty, name.endIndex < rest.endIndex, rest[name.endIndex] == "(",
              let close = rest[name.endIndex...].firstIndex(of: ")")
        else { return nil }
        return rest.distance(from: rest.startIndex, to: close) + 1
    }

    // MARK: The value projection

    /// `nodes` turned into the runs `spans(in:)` returns: the text between them plain, each
    /// construct by its own rule.
    private static func project(_ nodes: [Node], over text: Substring) -> [MarkdownSpan] {
        var result: [MarkdownSpan] = []
        var cursor = text.startIndex
        for node in nodes {
            let range = node.token.range
            if cursor < range.lowerBound { result.append(MarkdownSpan(text: String(text[cursor..<range.lowerBound]))) }
            result.append(contentsOf: spans(of: node, in: text))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result.append(MarkdownSpan(text: String(text[cursor...]))) }
        return result
    }

    private static func spans(of node: Node, in text: Substring) -> [MarkdownSpan] {
        switch node.token.kind {
        case .code(let delimiters):
            let code = text[delimiters[0].upperBound..<delimiters[1].lowerBound]
            return [MarkdownSpan(text: String(code), styles: [.code])]
        case .embed(let target, _):
            return [MarkdownSpan(text: target, link: .embed(target: target))]
        case .wikilink(let title, let syntax):
            let inner = text[syntax[0].upperBound..<syntax[1].lowerBound]
            let parts = inner.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            return [MarkdownSpan(text: parts.count > 1 ? String(parts[1]) : title, link: .note(title: title))]
        case .link(let url, let syntax):
            // An empty label keeps its one empty span, as before, rather than losing the link.
            let label = project(node.children, over: text[syntax[0].upperBound..<syntax[1].lowerBound])
            return (label.isEmpty ? [MarkdownSpan(text: "")] : label).map { span in
                var linked = span
                linked.link = .url(url)
                return linked
            }
        case .strong(let delimiters), .emphasis(let delimiters), .strikethrough(let delimiters),
             .highlight(let delimiters):
            let style: MarkdownSpan.Style = switch node.token.kind {
            case .strong: .strong
            case .strikethrough: .strikethrough
            case .highlight: .highlight
            default: .emphasis
            }
            return project(node.children, over: text[delimiters[0].upperBound..<delimiters[1].lowerBound]).map { span in
                var styled = span
                styled.styles.insert(style)
                return styled
            }
        case .tag, .scheduled, .due, .annotation:
            // Never scanned for here; plain text if ever met.
            return [MarkdownSpan(text: String(text[node.token.range]))]
        }
    }

    // MARK: Links

    /// `[label](target)`, and where it ends.
    private struct ParsedLink {
        var label: Range<String.Index>
        var target: String
        var end: String.Index
    }

    private static func markdownLink(in rest: Substring) -> ParsedLink? {
        guard let labelEnd = rest.dropFirst().range(of: "]") else { return nil }
        let label = rest.dropFirst().startIndex..<labelEnd.lowerBound
        let afterLabel = rest[labelEnd.upperBound...]
        guard afterLabel.hasPrefix("("), let close = afterLabel.dropFirst().range(of: ")")
        else { return nil }
        let target = String(afterLabel.dropFirst()[..<close.lowerBound])
        return ParsedLink(label: label, target: target, end: close.upperBound)
    }
}
