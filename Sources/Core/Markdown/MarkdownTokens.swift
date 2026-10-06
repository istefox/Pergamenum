import Foundation

// The ranged token layer of the shared markdown grammar (ADR-0082 §D1, PG-385, R-18).
//
// One place decides what a heading, a list marker, a task, a quote, a rule or a fence is, and
// both readers ask it: `MarkdownBlockParser.blocks(in:)` projects these tokens onto the values the
// reading view and the exporter draw, and `MarkdownStyler.spans(in:)` maps them onto the ranges the
// editor colours. The inline half lives beside its scanner in `MarkdownInline.swift`.
//
// Foundation only: this file compiles into `perg` and `pergamenum-mcp` (ADR-0001 §D1).

/// One line of a note, classified, with the ranges of its markers. `range` is the line without its
/// terminator, so a CRLF line never carries the `\r`.
struct MarkdownLineToken: Equatable, Sendable {
    let range: Range<String.Index>
    let kind: Kind

    enum Kind: Equatable, Sendable {
        case blank, paragraph, frontmatter, rule, messageAnchor, tableRow, fenceBody, fenceClose
        case fenceOpen(language: String?)
        case heading(level: Int, marker: Range<String.Index>)
        case listItem(ordered: Bool, indentation: Range<String.Index>, marker: Range<String.Index>, level: Int)
        /// `level` is the line's list nesting depth, as a list item's: the editor draws a box
        /// the task index does not read as the bullet it is, at that depth.
        case task(state: TaskItem.State, marker: Range<String.Index>, level: Int)
        case quote(level: Int, marker: Range<String.Index>)
    }
}

/// One inline construct, with the ranges of its delimiters. Every range indexes the string the
/// scanned `Substring` was taken from, so a token found in a mid-note line is valid in the note.
struct MarkdownInlineToken: Equatable, Sendable {
    let range: Range<String.Index>
    let kind: Kind

    enum Kind: Equatable, Sendable {
        case code(delimiters: [Range<String.Index>])
        case strong(delimiters: [Range<String.Index>])
        case emphasis(delimiters: [Range<String.Index>])
        case strikethrough(delimiters: [Range<String.Index>])
        /// `[[Nota]]`: `syntax` is the opening `[[` and the closing `]]`.
        case wikilink(target: String, syntax: [Range<String.Index>])
        /// `[testo](url)`, or `![alt](file)`: `syntax` is the opening `[` (or `![`) and the
        /// closing `](url)`, so the label is what lies between them.
        case link(url: String, syntax: [Range<String.Index>])
        /// `![[foto.png|300]]`: `target` is the reference before `|`; `syntax` is `![[` and `]]`.
        case embed(target: String, syntax: [Range<String.Index>])
        /// `#word` at the start of a run or after a space, as written; `Tag(_:)` says whether it
        /// names a tag of the vocabulary.
        case tag(String)
        case scheduled
        case due
        case annotation
    }
}

extension MarkdownBlockParser {
    /// One classification per line of `text`, in order. Frontmatter is read only when asked: the
    /// block projection is given a body, where a leading `---` is a rule.
    ///
    /// The line split is `Character.isNewline`, the parser's own (PG-317): every separator
    /// `CharacterSet.newlines` names ends a line, and a `"\r\n"` pair is one `Character`, so it
    /// ends one line and no range ever carries its `\r`. A caller whose own notion of a line is
    /// narrower passes it as `endsLine`: the editor's styler passes `LineBreak.isTerminator`, since
    /// TextKit keeps a U+2028 or a lone `"\r"` inside one paragraph and the styler has always read
    /// that paragraph as one line. Precedence is the reading view's: a fence
    /// swallows everything to its closing line, a pipe line followed by a delimiter row opens a
    /// table, and only then is a line a blank, a rule, a heading, a task, a list item, a quote, a
    /// Pratiche anchor or prose.
    static func lineTokens(
        in text: String, readsFrontmatter: Bool = false, endsLine: (Character) -> Bool = \.isNewline
    ) -> [MarkdownLineToken] {
        let ranges = lineRanges(in: text, endsLine: endsLine)
        var tokens: [MarkdownLineToken] = []
        tokens.reserveCapacity(ranges.count)

        var index = 0
        if readsFrontmatter, let frontmatter = NoteFrontmatter.range(in: text) {
            while index < ranges.count, ranges[index].lowerBound < frontmatter.upperBound {
                tokens.append(MarkdownLineToken(range: ranges[index], kind: .frontmatter))
                index += 1
            }
        }

        // Computed once per note (PG-139): a list line's level is a lookup, never a backward walk.
        // Filled on the first list or task line, so a note without one pays no forward pass.
        var cachedLevels: [String.Index: Int]?
        func levels() -> [String.Index: Int] {
            if let cachedLevels { return cachedLevels }
            let computed = ListNesting.levels(in: text)
            cachedLevels = computed
            return computed
        }
        while index < ranges.count {
            let range = ranges[index]
            let line = text[range]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if CodeFence.marks(trimmed) {
                let language = CodeFence.language(declaredBy: trimmed)
                tokens.append(MarkdownLineToken(range: range, kind: .fenceOpen(language: language)))
                index += 1
                while index < ranges.count {
                    let closes = CodeFence.marks(text[ranges[index]].trimmingCharacters(in: .whitespaces))
                    tokens.append(MarkdownLineToken(range: ranges[index], kind: closes ? .fenceClose : .fenceBody))
                    index += 1
                    if closes { break }
                }
                continue
            }

            if let rows = tableLines(header: trimmed, after: index, in: text, ranges: ranges) {
                for row in index..<(index + rows) {
                    tokens.append(MarkdownLineToken(range: ranges[row], kind: .tableRow))
                }
                index += rows
                continue
            }

            tokens.append(MarkdownLineToken(
                range: range, kind: kind(of: line, trimmed: trimmed, in: text, levels: levels)
            ))
            index += 1
        }
        return tokens
    }

    /// The lines of `text`, split as `blocks(in:)` has always split them (`endsLine` defaults to
    /// `\.isNewline`): the same ranges
    /// `split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)` would cut, so an
    /// empty text is one empty line and a trailing terminator leaves an empty last line.
    private static func lineRanges(in text: String, endsLine: (Character) -> Bool) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while true {
            guard let end = text[start...].firstIndex(where: endsLine) else {
                ranges.append(start..<text.endIndex)
                return ranges
            }
            ranges.append(start..<end)
            start = text.index(after: end)
        }
    }

    /// How many lines a table starting at `ranges[index]` takes, header included, or nil when the
    /// line opens none. `GFMTable.parsed` decides; it is handed only the lines it can read - the
    /// delimiter row, then every line up to the first blank or pipe-less one - so a note does not
    /// become an array of strings for the sake of one pipe.
    ///
    /// The delimiter row is checked against the header's column count first, with the test
    /// `parsed` itself applies, and the rows are collected only when it passes: a run of pipe
    /// lines with no delimiter row (a pasted log, an ASCII diagram) would otherwise copy every
    /// following line once per line of the run, on every keystroke.
    private static func tableLines(
        header trimmed: String, after index: Int, in text: String, ranges: [Range<String.Index>]
    ) -> Int? {
        guard trimmed.contains("|"), index + 1 < ranges.count else { return nil }
        let delimiter = String(text[ranges[index + 1]])
        guard let alignments = GFMTable.alignments(in: delimiter.trimmingCharacters(in: .whitespaces)),
              alignments.count == GFMTable.cells(in: trimmed).count
        else { return nil }
        var rest = [delimiter]
        var next = index + 2
        while next < ranges.count {
            let line = String(text[ranges[next]])
            rest.append(line)
            let row = line.trimmingCharacters(in: .whitespaces)
            if row.isEmpty || !row.contains("|") { break }
            next += 1
        }
        guard let parsed = GFMTable.parsed(header: trimmed, rest: rest[...]) else { return nil }
        return 1 + parsed.bodyLines
    }

    /// What one line outside a fence and a table is.
    ///
    /// The markers are read on the line as typed, trailing spaces included, which is how the editor
    /// has always read them: `- ` and `## ` are a list item and a heading the moment they are
    /// typed. A reading view has nothing to draw for an empty one, so `blocks(in:)` keeps such a
    /// line as the text it is.
    private static func kind(
        of line: Substring, trimmed: String, in text: String, levels: () -> [String.Index: Int]
    ) -> MarkdownLineToken.Kind {
        if trimmed.isEmpty { return .blank }
        if isRule(trimmed) { return .rule }
        let content = line.firstIndex { !isBlank($0) } ?? line.endIndex
        let body = line[content...]
        if let marker = headingMarker(in: body) {
            return .heading(level: line.distance(from: content, to: marker.upperBound) - 1, marker: marker)
        }
        // From the forward pass (PG-139), asked for only here, on a list or task line: `levels`
        // keys every line it reads as a list line, task lines included, so the backward walk runs
        // only for a line it does not key (an indentation of other blanks than spaces and tabs).
        func level() -> Int {
            let columns = line[..<content].reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            return levels()[line.startIndex] ?? ListNesting.level(in: text, lineStart: line.startIndex, indent: columns)
        }
        if let task = taskMarker(in: body) { return .task(state: task.state, marker: task.marker, level: level()) }
        if let marker = listMarker(in: body) {
            let ordered = !(body.first == "-" || body.first == "*" || body.first == "+")
            return .listItem(ordered: ordered, indentation: line.startIndex..<content, marker: marker, level: level())
        }
        if let quote = quoteMarker(in: body) { return .quote(level: quote.level, marker: quote.marker) }
        if body.hasPrefix("<!--"), PraticaEntryAnchor.messageID(inLine: line) != nil { return .messageAnchor }
        return .paragraph
    }

    /// Whether a character is the indentation `trimmingCharacters(in: .whitespaces)` removes.
    private static func isBlank(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.whitespaces.contains)
    }

    /// The `#`s of a heading and the one space after them. `#tag` is a tag, not a heading, and
    /// seven hashes are prose: the hashes have to be followed by a space within six.
    private static func headingMarker(in body: Substring) -> Range<String.Index>? {
        let hashes = body.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let space = body.index(body.startIndex, offsetBy: hashes)
        guard space < body.endIndex, body[space] == " " else { return nil }
        return body.startIndex..<body.index(after: space)
    }

    /// `- [x]`, the bullet through the closing bracket, when the box holds one of the task index's
    /// own markers (`TaskParser.state(for:)`, ADR-0077 §D5): `- [1] Rossi, 2020` is a bullet.
    private static func taskMarker(in body: Substring) -> (state: TaskItem.State, marker: Range<String.Index>)? {
        guard let rest = afterBullet(body) else { return nil }
        let box = rest.drop(while: isBlank)
        guard box.first == "[", box.count >= 3 else { return nil }
        let markIndex = box.index(after: box.startIndex)
        let closing = box.index(after: markIndex)
        guard box[closing] == "]", let state = TaskParser.state(for: box[markIndex]) else { return nil }
        return (state, body.startIndex..<box.index(after: closing))
    }

    /// The text after a `-`, `*` or `+` bullet and its space, or nil when the line is not one.
    private static func afterBullet(_ body: Substring) -> Substring? {
        guard let first = body.first, first == "-" || first == "*" || first == "+" else { return nil }
        let rest = body.dropFirst()
        guard rest.first == " " else { return nil }
        return rest.dropFirst()
    }

    /// A bullet (`- `) or an ordered marker (`12. `, `12) `) and its one space. The digits are the
    /// file's own, measured and never normalised (ADR-0028 §D4).
    private static func listMarker(in body: Substring) -> Range<String.Index>? {
        if afterBullet(body) != nil {
            return body.startIndex..<body.index(body.startIndex, offsetBy: 2)
        }
        let digits = body.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.endIndex < body.endIndex else { return nil }
        let delimiter = body[digits.endIndex]
        guard delimiter == "." || delimiter == ")" else { return nil }
        let space = body.index(after: digits.endIndex)
        guard space < body.endIndex, body[space] == " " else { return nil }
        return body.startIndex..<body.index(after: space)
    }

    /// The opening `>` run and the one space after its last `>`, when written, and how many `>`
    /// that is. GFM lets the space go, so `>>annidata` is a level-2 quote.
    ///
    /// One `>` immediately followed by an ISO date is not a quote: `>2026-08-15` is this app's own
    /// scheduling token (SPEC §7.1, ADR-0082 §D4), moved here from the styler so the reading view,
    /// the exporter and the editor read it alike. `> 2026-10-04`, with the space, stays a quote,
    /// and so does `>2026-02-31`, which is no date.
    private static func quoteMarker(in body: Substring) -> (level: Int, marker: Range<String.Index>)? {
        let carets = body.prefix(while: { $0 == ">" })
        guard !carets.isEmpty else { return nil }
        let rest = body[carets.endIndex...]
        if carets.count == 1, CalendarDate(iso: String(rest.prefix(10))) != nil { return nil }
        let end = rest.first == " " ? rest.index(after: rest.startIndex) : rest.startIndex
        return (carets.count, body.startIndex..<end)
    }
}
