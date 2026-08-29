import Foundation

/// Classifies spans of a note's source for the editor to style.
///
/// SPEC §5 asks for "source mode improved": the syntax stays visible and gets styled,
/// rather than being hidden the way a live preview would. ADR-0018 §D1 narrows that for
/// three cases across its three slices - a heading's `#` marker, a `*`/`**` emphasis
/// delimiter, and a whole line that is only an image/PDF embed - each of which the
/// view may draw differently from the raw source, by a rule of its own (a marker
/// reveals on caret, a drawn embed does not - D5). This classifier still never removes
/// or replaces characters - it only says what each range *is*, and it is the view that
/// decides how, or whether, that looks using theme tokens.
enum MarkdownStyler {
    enum Span: Equatable, Sendable {
        /// The whole `---` block at the top of the file.
        case frontmatter
        case heading(level: Int)
        /// The `#`s of a heading, and the single space after them (ADR-0018 §D1, slice 1).
        /// The level is already on `.heading`, so this carries no payload of its own.
        case headingMarker
        case bold
        case italic
        /// One `*` or `**` delimiter of a `.bold`/`.italic` run (ADR-0018 §D1, slice 2).
        /// `_`/`__` are deliberately excluded - hiding them would read as
        /// `nomefilelungo` for `nome_file_lungo`, which `emphasis(_:at:)` already parses
        /// as italic with no word-boundary rule.
        case emphasisMarker
        /// `~~testo~~`. Added with the format bar (M8), and it closes a real gap rather than
        /// adding a style: `MarkdownInlineParser` has rendered strikethrough in Lettura since
        /// the reading view existed, and the editor left it plain - the same text looking
        /// formatted on one surface and not on the other.
        case strikethrough
        case code
        /// The `[[` `]]` `#` `|` punctuation inside a wikilink.
        case linkSyntax
        /// The target part of a wikilink, which is what a click follows.
        case linkTarget(String)
        /// The file name inside `![[foto.png]]`. Separate from `linkTarget` because it
        /// leads to a file, not to a note: clicking it used to ask the vault for a note
        /// called "foto.png" and, finding none, do nothing at all.
        case embedTarget(String)
        /// The whole embed of a line that is nothing else - `![[foto.png]]` or
        /// `![alt](foto.png)` (ADR-0018, slice 3). Recognised by `embedRun(inLine:)`,
        /// which also decides the file/note split `.embedTarget` above never had to: a
        /// bare `![[nota]]` stays a transclusion and never reaches this case (D4). Carries
        /// no attributes of its own yet - the collapse into a preview is Step 3's.
        case embedRun
        /// An inline `#tag` in the body.
        case tag(String)
        /// A whole fenced code block, opening and closing backticks included.
        case codeBlock
        /// One token inside a fenced block, from the local grammar.
        case codeToken(CodeSyntax.Token)
        /// The `- [ ]` marker of a task line.
        case taskMarker(done: Bool)
        /// A `>2026-08-15` scheduling marker.
        case scheduled
        /// A `!2026-08-20` due date.
        case due
        /// `@done(...)`, `@remind(...)`, `@repeat(...)`.
        case annotation
        /// A bullet (`-`/`*`/`+`) or ordered (`N.`/`N)`) list marker (ADR-0028 §D1).
        enum ListKind: Equatable, Sendable { case bullet, ordered }
        /// The marker and its trailing space - `- `, `* `, `+ `, `12. `, `12) ` - starting
        /// after the line's own indentation, never on a checkbox line (ADR-0028 §D2).
        /// `level` is `1 + indentColumns / 2` (a space is one column, a tab four), capped
        /// at 6. Carries no range for the item's text and no paragraph range: the view
        /// derives the paragraph itself (Task 3). Declaration only for now - the tester
        /// owns the shape, the coder owns `spans(inLine:at:in:)`'s recognition of it
        /// (plan `2026-08-29-wysiwyg-markdown-in-workspace.md`, Task 1).
        case listMarker(kind: ListKind, level: Int)
    }

    struct StyledRange: Equatable, Sendable {
        var range: Range<String.Index>
        var span: Span
    }

    /// Returns the styled ranges of a whole note, in no particular order. Ranges may
    /// nest (a wikilink inside a heading); the view applies them in the order given,
    /// so later spans win where they overlap.
    static func spans(in text: String) -> [StyledRange] {
        var result: [StyledRange] = []

        let bodyStart = frontmatterRange(in: text).map { range -> String.Index in
            result.append(StyledRange(range: range, span: .frontmatter))
            return range.upperBound
        } ?? text.startIndex

        // Fences first, because everything below has to know where they are. Inside one,
        // markdown is not markdown: `# rigenera` is a shell comment and not a tag,
        // `>2026-01-01` is a SQL predicate and not a scheduling marker, and a lone `*` is
        // a wildcard that used to pair with the next one half a note away.
        let fences = CodeFence.regions(in: text).filter { $0.range.lowerBound >= bodyStart }
        for fence in fences {
            result.append(StyledRange(range: fence.range, span: .codeBlock))
            for span in CodeSyntax.spans(in: text[fence.body], language: fence.language) {
                result.append(StyledRange(range: span.range, span: .codeToken(span.token)))
            }
        }

        for lineRange in lineRanges(in: text, from: bodyStart) {
            guard !fences.contains(where: { $0.range.overlaps(lineRange) }) else { continue }
            let line = String(text[lineRange])
            result.append(contentsOf: spans(inLine: line, at: lineRange, in: text))
        }

        result.append(contentsOf: wikilinkSpans(in: text, from: bodyStart, outside: fences))
        return result
    }

    /// Whether a span is syntax rather than prose, and so must not be spell-checked (M8).
    ///
    /// A spell checker reads a note's *source*, where `[[Curva di compressione]]` is a file
    /// name, `#project-pergamenum` is a namespaced tag, `>2026-08-15` is a date and a `sh`
    /// fence is a program. Underlining all of it is what makes a checker on a markdown editor
    /// something the user turns off again within a minute, so the editor tells AppKit to skip
    /// these ranges.
    ///
    /// Headings, bold and italic are deliberately absent: they wrap real words, and those are
    /// exactly the words worth checking.
    static func suppressesSpellCheck(_ span: Span) -> Bool {
        switch span {
        case .frontmatter, .code, .codeBlock, .codeToken,
             .linkSyntax, .linkTarget, .embedTarget, .embedRun, .tag,
             .taskMarker, .scheduled, .due, .annotation, .headingMarker, .emphasisMarker:
            true
        // Strikethrough belongs here with bold and italic and not above: `~~` wraps prose,
        // and prose is exactly what a spell checker is for.
        //
        // `.listMarker` is a placeholder arm only, kept here (not moved to the `true`
        // group above) so `MarkdownStylerTests.listMarkerSuppressesSpellCheck` is red for
        // the right reason - the coder moves it in Task 1's "Then implement" step.
        case .heading, .bold, .italic, .strikethrough, .listMarker:
            false
        }
    }

    /// Sorts and merges ranges, joining the ones that overlap or touch.
    ///
    /// `spans(in:)` returns overlapping ranges by design - a wikilink inside a heading is two
    /// of them - and the spell-check delegate is asked about a range on every word AppKit
    /// checks. Merging once, when the note is styled, turns each of those questions into a
    /// walk over a handful of ranges instead of over every span in the note.
    static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var merged: [NSRange] = []
        for range in ranges.sorted(by: { $0.location < $1.location }) {
            guard let last = merged.last, range.location <= NSMaxRange(last) else {
                merged.append(range)
                continue
            }
            let end = max(NSMaxRange(last), NSMaxRange(range))
            merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
        }
        return merged
    }

    /// The `---`-delimited block, only when it opens on the very first line.
    private static func frontmatterRange(in text: String) -> Range<String.Index>? {
        guard text.hasPrefix("---") else { return nil }
        let afterOpening = text.index(text.startIndex, offsetBy: 3)
        guard let closing = text.range(of: "\n---", range: afterOpening..<text.endIndex) else { return nil }
        return text.startIndex..<closing.upperBound
    }

    private static func lineRanges(in text: String, from start: String.Index) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = start
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            if lineStart < lineEnd { ranges.append(lineStart..<lineEnd) }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }
        return ranges
    }

    private static func spans(
        inLine line: String,
        at lineRange: Range<String.Index>,
        in text: String
    ) -> [StyledRange] {
        var result: [StyledRange] = []

        /// Maps an offset inside `line` back to an index into `text`.
        func absolute(_ offset: Int, _ length: Int) -> Range<String.Index> {
            let start = text.index(lineRange.lowerBound, offsetBy: offset)
            let end = text.index(start, offsetBy: length)
            return start..<end
        }

        let trimmed = line.drop(while: { $0 == " " })
        let indent = line.count - trimmed.count

        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            // A heading needs a space after the hashes; `#tag` at line start is a tag.
            if hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") {
                result.append(StyledRange(range: lineRange, span: .heading(level: hashes)))
                // After the heading span, on purpose: later spans win on overlap, so the
                // marker keeps the heading's font and gets its own colour on top.
                //
                // No marker for "# " or "#   " - a heading with no title yet. Hiding the
                // hashes there would shrink the row to nothing the instant the caret leaves
                // it, which is worse than showing four characters that do nothing yet.
                let hasTitle = trimmed.dropFirst(hashes + 1).contains { $0 != " " }
                if hasTitle {
                    result.append(StyledRange(
                        range: absolute(indent, hashes + 1),
                        span: .headingMarker
                    ))
                }
            }
        }

        if let marker = taskMarker(in: trimmed) {
            result.append(StyledRange(
                range: absolute(indent, marker.length),
                span: .taskMarker(done: marker.done)
            ))
        }

        if let embed = embedRun(inLine: line) {
            let offset = line.distance(from: line.startIndex, to: embed.lowerBound)
            let length = line.distance(from: embed.lowerBound, to: embed.upperBound)
            result.append(StyledRange(range: absolute(offset, length), span: .embedRun))
        }

        result.append(contentsOf: inlineSpans(in: line, absolute: absolute))
        return result
    }

    private static func inlineSpans(
        in line: String,
        absolute: (Int, Int) -> Range<String.Index>
    ) -> [StyledRange] {
        var result: [StyledRange] = []
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            guard let (length, span) = inlineSpan(in: characters, at: index) else {
                index += 1
                continue
            }
            result.append(StyledRange(range: absolute(index, length), span: span))
            // After the run span, on purpose - later spans win on overlap (ADR-0018 §D1).
            if characters[index] == "*", span == .bold || span == .italic {
                result.append(contentsOf: emphasisMarkers(at: index, length: length, span: span, absolute: absolute))
            }
            index += length
        }
        return result
    }

    /// What starts at `index`, if anything does.
    ///
    /// A table rather than a loop with the recognisers inlined in it, which is what this was
    /// until strikethrough became the sixth: each arm answers «how long, and what», the loop
    /// above only walks. Splitting them is what keeps either of the two readable.
    private static func inlineSpan(
        in characters: [Character], at index: Int
    ) -> (Int, Span)? {
        switch characters[index] {
        case "*", "_":
            return emphasis(characters, at: index)
        case "~":
            return strikethroughLength(characters, from: index).map { ($0, .strikethrough) }
        case "`":
            guard let end = characters[(index + 1)...].firstIndex(of: "`") else { return nil }
            return (end - index + 1, .code)
        case "#":
            // An inline tag, not a heading: it must be preceded by whitespace or start the
            // line, or `C#` and a URL fragment would both become tags.
            let precededByBoundary = index == 0 || characters[index - 1] == " "
            guard precededByBoundary, let length = tagLength(characters, from: index) else { return nil }
            return (length, .tag(String(characters[index..<(index + length)])))
        case ">", "!":
            return dateMarkerLength(characters, from: index)
                .map { ($0, characters[index] == ">" ? .scheduled : .due) }
        case "@":
            return annotationLength(characters, from: index).map { ($0, .annotation) }
        default:
            return nil
        }
    }

    private static func strikethroughLength(_ characters: [Character], from index: Int) -> Int? {
        guard index + 1 < characters.count, characters[index + 1] == "~" else { return nil }
        var cursor = index + 2
        while cursor + 1 < characters.count {
            if characters[cursor] == "~", characters[cursor + 1] == "~" {
                return cursor + 2 - index
            }
            cursor += 1
        }
        return nil
    }

    private static func emphasis(_ characters: [Character], at index: Int) -> (Int, Span)? {
        let marker = characters[index]
        let isDouble = index + 1 < characters.count && characters[index + 1] == marker
        let markerLength = isDouble ? 2 : 1
        let searchStart = index + markerLength

        guard searchStart < characters.count else { return nil }
        var cursor = searchStart
        while cursor < characters.count {
            if characters[cursor] == marker {
                if isDouble {
                    guard cursor + 1 < characters.count, characters[cursor + 1] == marker else {
                        cursor += 1
                        continue
                    }
                    return (cursor + 2 - index, .bold)
                }
                return (cursor + 1 - index, .italic)
            }
            cursor += 1
        }
        return nil
    }

    /// Length of a `#namespace-value` run, or nil when what follows is not a tag.
    private static func tagLength(_ characters: [Character], from index: Int) -> Int? {
        var cursor = index + 1
        while cursor < characters.count {
            let character = characters[cursor]
            guard character.isLetter || character.isNumber || character == "-" else { break }
            cursor += 1
        }
        let length = cursor - index
        guard length > 1 else { return nil }
        return Tag(String(characters[index..<cursor])) == nil ? nil : length
    }

    /// Length of `>YYYY-MM-DD` or `!YYYY-MM-DD`.
    private static func dateMarkerLength(_ characters: [Character], from index: Int) -> Int? {
        let dateLength = 10
        guard index + dateLength < characters.count + 1,
              index + 1 + dateLength <= characters.count
        else { return nil }
        let candidate = String(characters[(index + 1)..<(index + 1 + dateLength)])
        return CalendarDate(iso: candidate) == nil ? nil : dateLength + 1
    }

    /// Length of `@name(...)`.
    private static func annotationLength(_ characters: [Character], from index: Int) -> Int? {
        var cursor = index + 1
        while cursor < characters.count, characters[cursor].isLetter { cursor += 1 }
        guard cursor > index + 1, cursor < characters.count, characters[cursor] == "(" else { return nil }
        guard let close = characters[cursor...].firstIndex(of: ")") else { return nil }
        return close + 1 - index
    }

    private static func wikilinkSpans(
        in text: String,
        from start: String.Index,
        outside fences: [CodeFence.Region]
    ) -> [StyledRange] {
        var result: [StyledRange] = []
        for link in WikilinkParser.links(in: String(text[start...])) {
            // The parser worked on a slice; shift its indices back onto the full text.
            let offset = text.distance(from: text.startIndex, to: start)
            let sliceStart = text.index(text.startIndex, offsetBy: offset)
            let lower = text.index(sliceStart, offsetBy: String(text[start...]).distance(
                from: String(text[start...]).startIndex, to: link.range.lowerBound
            ))
            let upper = text.index(sliceStart, offsetBy: String(text[start...]).distance(
                from: String(text[start...]).startIndex, to: link.range.upperBound
            ))

            // `[[Curva]]` written inside a code fence is a wikilink in an example, not a
            // link to follow: making it clickable would take a person out of the note.
            guard !fences.contains(where: { $0.range.overlaps(lower..<upper) }) else { continue }

            result.append(StyledRange(range: lower..<upper, span: .linkSyntax))

            // The target sits after the opening brackets; styling it separately is
            // what makes only the title look clickable.
            let openingLength = link.isEmbed ? 3 : 2
            let targetStart = text.index(lower, offsetBy: openingLength)
            if let targetEnd = text.index(targetStart, offsetBy: link.target.count, limitedBy: upper) {
                result.append(StyledRange(
                    range: targetStart..<targetEnd,
                    span: link.isEmbed ? .embedTarget(link.target) : .linkTarget(link.target)
                ))
            }
        }
        return result
    }
}

/// The `- [ ]`/`- [x]`/`- [>]`/`- [-]` marker at the start of a task line (SPEC §7.1), and
/// the `*` bullet variant.
///
/// File scope rather than a nested `private static func`: `MarkdownStyler`'s own body
/// reached SwiftLint's length limit the moment the heading marker (ADR-0018 §D1) added a
/// few lines to it, and this helper depends on nothing the type itself carries.
/// The opening and closing `*`/`**` of an emphasis run, or none when hiding them would
/// collapse the run to nothing (`****`, adjacent empty `**`). File scope for the same
/// reason as `taskMarker` below (ADR-0018 §D1, slice 2).
private func emphasisMarkers(
    at index: Int,
    length: Int,
    span: MarkdownStyler.Span,
    absolute: (Int, Int) -> Range<String.Index>
) -> [MarkdownStyler.StyledRange] {
    let markerLength = span == .bold ? 2 : 1
    guard length > 2 * markerLength else { return [] }
    return [
        MarkdownStyler.StyledRange(range: absolute(index, markerLength), span: .emphasisMarker),
        MarkdownStyler.StyledRange(
            range: absolute(index + length - markerLength, markerLength), span: .emphasisMarker
        )
    ]
}

private func taskMarker(in line: some StringProtocol) -> (length: Int, done: Bool)? {
    guard line.count >= 5, let first = line.first, first == "-" || first == "*" else { return nil }
    let after = line.dropFirst()
    guard after.hasPrefix(" ["), after.count >= 4 else { return nil }
    let state = Array(after)[2]
    guard Array(after)[3] == "]" else { return nil }
    return (5, state == "x" || state == "X")
}
