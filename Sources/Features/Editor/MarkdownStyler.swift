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
        /// The `- [ ]` marker of a task line, and which of the four §7.1 states it is.
        case taskMarker(state: TaskItem.State)
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
        /// `level` is CommonMark's content-column nesting depth (`ListNesting.level`, PG-085),
        /// capped at 6. Carries no range for the item's text and no paragraph range: the view
        /// derives the paragraph itself.
        case listMarker(kind: ListKind, level: Int)
        /// A `>` blockquote marker (ADR-0029 §D1) - one or more `>` characters and, when
        /// written, the single space after the last one. `level` is how many `>` the line
        /// opens with. **Unbounded, on purpose** (R-03): unlike `.listMarker`'s level, which
        /// is capped at 6, the file's own character count *is* the nesting depth here, so
        /// there is nothing to cap.
        case blockquoteMarker(level: Int)
        /// One `~~` delimiter of a `.strikethrough` run - the exact twin of
        /// `.emphasisMarker`, down to the two-sided pair and the "hiding it would collapse
        /// an empty run" guard (ADR-0029 §D1).
        case strikethroughMarker
        /// A whole thematic-break line - `---`, `- - -`, `***`, `___` and their kin - GFM's
        /// three-or-more-of-the-same-character rule, optionally space-separated, covering
        /// the entire line (ADR-0029 §D1). Reuses `MarkdownBlockParser.isRule`'s grammar
        /// rather than restating it, so the reading view and the editor never disagree on
        /// what counts as a rule.
        case horizontalRule
        /// A whole GFM table's source run - header, delimiter and every body row - emitted
        /// by `tableSpans(in:from:outside:)` (Task 3 of plan
        /// `2026-09-02-editor-wysiwyg-unification`). Declared here, alongside the other
        /// three ADR-0029 constructs, so the exhaustive tables below need editing only
        /// once rather than twice.
        case tableRun
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
        result.append(contentsOf: tableSpans(in: text, from: bodyStart, outside: fences))
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
             .taskMarker, .scheduled, .due, .annotation, .headingMarker, .emphasisMarker,
             .listMarker,
             // The four ADR-0029 constructs are markers/whole-syntax runs, not prose -
             // the same reasoning as `.headingMarker`/`.emphasisMarker`/`.listMarker` above.
             .blockquoteMarker, .strikethroughMarker, .horizontalRule, .tableRun:
            true
        // Strikethrough belongs here with bold and italic and not above: `~~` wraps prose,
        // and prose is exactly what a spell checker is for.
        case .heading, .bold, .italic, .strikethrough:
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

        // A thematic break is the whole line and nothing else, so it returns rather than
        // falling through: `- - -` would otherwise also be read as a bullet, which is
        // exactly the precedence `MarkdownBlockParser.Accumulator.take` already applies
        // (it asks `isRule` before `bulletItem`). The grammar is that parser's own,
        // reused rather than restated (ADR-0029 §D1).
        if MarkdownBlockParser.isRule(trimmed) {
            result.append(StyledRange(range: lineRange, span: .horizontalRule))
            return result
        }

        // Unbounded on purpose (R-03): the line's own `>` count *is* the nesting depth,
        // so there is nothing to cap the way `.listMarker`'s level is capped at 6.
        if let quote = blockquoteMarkerLength(in: trimmed) {
            result.append(StyledRange(
                range: absolute(indent, quote.length),
                span: .blockquoteMarker(level: quote.level)
            ))
        }

        result.append(contentsOf: headingSpans(
            in: trimmed, at: lineRange, indent: indent, absolute: absolute
        ))

        let task = taskMarker(in: trimmed)
        if let task {
            result.append(StyledRange(
                range: absolute(indent, task.length),
                span: .taskMarker(state: task.state)
            ))
        }

        // A checkbox line is not a list line (ADR-0028 §D2), and emitting nothing at all
        // for it is the whole of R-06: with no marker to conceal there is no bullet to
        // put in its place, so `- [ ] fai` keeps exactly today's appearance.
        if task == nil, let list = listMarkerSpan(
            inLine: line, at: lineRange.lowerBound, in: text, absolute: absolute
        ) {
            result.append(list)
        }

        if let embed = embedRun(inLine: line) {
            let offset = line.distance(from: line.startIndex, to: embed.lowerBound)
            let length = line.distance(from: embed.lowerBound, to: embed.upperBound)
            result.append(StyledRange(range: absolute(offset, length), span: .embedRun))
        }

        result.append(contentsOf: inlineSpans(in: line, absolute: absolute))
        // Per line rather than per note, unlike `wikilinkSpans`: this way the fence
        // exclusion `spans(in:)` already applies to every line comes for free (R-09),
        // instead of being a second `outside:` argument to keep in step.
        result.append(contentsOf: markdownLinkSpans(in: line, absolute: absolute))
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
            if let delimiter = delimiterSpan(for: span, opening: characters[index]),
               let marker = markerLength(for: span) {
                result.append(contentsOf: delimiterMarkers(
                    at: index, length: length, markerLength: marker, span: delimiter, absolute: absolute
                ))
            }
            // PG-084: a run's own inner content is itself line-shaped text and may contain
            // another marker pair the forward walk below would otherwise never see, since it
            // advances straight past the whole matched `length` - `**~~testo~~**` is one atomic
            // `.bold` match with `~~testo~~` entirely inside it. Recursing through this same
            // entry point on just the inner slice (markers excluded) finds it, offset back into
            // the outer line's coordinates by the closure passed to the recursive call.
            if let marker = markerLength(for: span), length > 2 * marker {
                let innerStart = index + marker
                let innerText = String(characters[innerStart..<(index + length - marker)])
                result.append(contentsOf: inlineSpans(in: innerText) { offset, len in
                    absolute(innerStart + offset, len)
                })
            }
            index += length
        }
        return result
    }

    /// The width of `span`'s own opening/closing delimiter, for the three run spans another
    /// span can nest inside (PG-084). `nil` for every span `inlineSpan(in:at:)` matches
    /// atomically - `.code`, `.tag`, `.scheduled`, `.due`, `.annotation` have no inner content
    /// of their own to recurse into.
    private static func markerLength(for span: Span) -> Int? {
        switch span {
        case .bold, .strikethrough: 2
        case .italic: 1
        default: nil
        }
    }

    /// Which marker span a run's own opening/closing delimiters get, or none when they are
    /// not marked at all.
    ///
    /// `_`/`__` is deliberately excluded from `.bold`/`.italic`, which is why this takes the
    /// opening character rather than only the span: hiding an underscore pair would read as
    /// `nomefilelungo` for `nome_file_lungo`, and `emphasis(_:at:)` parses that as italic
    /// with no word-boundary rule of its own (ADR-0018 §D1, slice 2). `~~` has no such twin
    /// spelling, so `.strikethrough` needs no character test (ADR-0029 §D1).
    private static func delimiterSpan(for span: Span, opening: Character) -> Span? {
        switch span {
        case .bold, .italic: opening == "*" ? .emphasisMarker : nil
        case .strikethrough: .strikethroughMarker
        default: nil
        }
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

    /// Every GFM table's whole source run - header, delimiter and body rows - as one span
    /// each (ADR-0029 §D10; plan `2026-09-02-editor-wysiwyg-unification`, Task 3).
    ///
    /// A note-level pass beside `wikilinkSpans(in:from:outside:)` and taking the same
    /// `fences` argument, because a table is the one construct here that spans several
    /// lines: the per-line walk above cannot see the delimiter row that makes a line of
    /// pipes a header (R-10), and a fence's pipes are never a table (R-09).
    private static func tableSpans(
        in text: String,
        from start: String.Index,
        outside fences: [CodeFence.Region]
    ) -> [StyledRange] {
        GFMTable.runs(in: text, from: start, outside: fences).map {
            StyledRange(range: $0.range, span: .tableRun)
        }
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
/// The opening and closing delimiters of an inline run - `*`/`**` of an emphasis one,
/// `~~` of a strikethrough one - or none when hiding them would collapse the run to
/// nothing (`****`, `~~~~`, adjacent empty pairs). File scope for the same reason as
/// `taskMarker` below (ADR-0018 §D1, slice 2; ADR-0029 §D1 for the second caller).
///
/// The width and the resulting span both come from the caller: `markerLength(for:)` and
/// `delimiterSpan(for:opening:)` are the type's own, and this helper only does the two
/// pieces of arithmetic they leave over.
private func delimiterMarkers(
    at index: Int,
    length: Int,
    markerLength: Int,
    span: MarkdownStyler.Span,
    absolute: (Int, Int) -> Range<String.Index>
) -> [MarkdownStyler.StyledRange] {
    guard length > 2 * markerLength else { return [] }
    return [
        MarkdownStyler.StyledRange(range: absolute(index, markerLength), span: span),
        MarkdownStyler.StyledRange(
            range: absolute(index + length - markerLength, markerLength), span: span
        )
    ]
}

/// A heading line's own span and, unless the heading has no title yet, its `#` marker
/// (ADR-0018 §D1, slice 1).
///
/// File scope for the same reason `listMarkerSpan` and `taskMarker` are: `MarkdownStyler`'s
/// own body is at SwiftLint's length limit, and its per-line walk went over the function
/// limit as well the moment ADR-0029's four constructs joined it. This helper depends on
/// nothing the type carries.
private func headingSpans(
    in trimmed: some StringProtocol,
    at lineRange: Range<String.Index>,
    indent: Int,
    absolute: (Int, Int) -> Range<String.Index>
) -> [MarkdownStyler.StyledRange] {
    guard trimmed.hasPrefix("#") else { return [] }
    let hashes = trimmed.prefix(while: { $0 == "#" }).count
    // A heading needs a space after the hashes; `#tag` at line start is a tag.
    guard hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") else { return [] }

    var result = [MarkdownStyler.StyledRange(range: lineRange, span: .heading(level: hashes))]
    // After the heading span, on purpose: later spans win on overlap, so the marker keeps
    // the heading's font and gets its own colour on top.
    //
    // No marker for "# " or "#   " - a heading with no title yet. Hiding the hashes there
    // would shrink the row to nothing the instant the caret leaves it, which is worse than
    // showing four characters that do nothing yet.
    let hasTitle = trimmed.dropFirst(hashes + 1).contains { $0 != " " }
    if hasTitle {
        result.append(MarkdownStyler.StyledRange(
            range: absolute(indent, hashes + 1), span: .headingMarker
        ))
    }
    return result
}

/// How wide a line's opening `>` run is - the `>`s and the single space after the last
/// one, when it is written - and how many `>`s that is, which is the nesting level.
///
/// Nil when the line does not open a blockquote at all, and nil for a lone `>` immediately
/// followed by an ISO date: `>2026-08-15` is this app's own scheduling marker (SPEC §7.1),
/// already spanned as `.scheduled` by `inlineSpan(in:at:)`, and reading its `>` as a quote
/// bar would conceal the marker's own first character. GFM's "the space may be omitted"
/// still holds for every other spelling, `>>>senza spazio` included.
private func blockquoteMarkerLength(
    in content: some StringProtocol
) -> (length: Int, level: Int)? {
    let carets = content.prefix(while: { $0 == ">" }).count
    guard carets > 0 else { return nil }
    let rest = content.dropFirst(carets)
    if carets == 1, rest.count >= 10, CalendarDate(iso: String(rest.prefix(10))) != nil { return nil }
    return (carets + (rest.hasPrefix(" ") ? 1 : 0), carets)
}

/// The `[` and `](url)` delimiters of a CommonMark `[testo](url)` link, as two
/// `.linkSyntax` spans with the label between them left unspanned (ADR-0029 §D1).
///
/// The existing `.linkSyntax` case, reused rather than a fifth one added: this is the same
/// second-spelling decision ADR-0018 §D3 took for `![alt](file.png)`, and for the same
/// reason - this app's own writers emit the wikilink form, `EditorEdits.markdownLink`
/// excepted, and a vault opened from elsewhere holds both.
///
/// Two forms are skipped rather than matched. `[[Nota]]` is a wikilink and
/// `wikilinkSpans(in:from:outside:)` already owns it, whole run and target alike. An
/// `![alt](foto.png)` is an embed, whose own `.embedRun` span covers the line and whose
/// rendering is `embedParagraph(at:storage:)`'s (ADR-0018 slice 3) - two mechanisms over
/// one run is exactly the overlap this skips.
private func markdownLinkSpans(
    in line: String,
    absolute: (Int, Int) -> Range<String.Index>
) -> [MarkdownStyler.StyledRange] {
    let characters = Array(line)
    var result: [MarkdownStyler.StyledRange] = []
    var index = 0

    while index < characters.count {
        guard characters[index] == "[" else {
            index += 1
            continue
        }
        guard index + 1 < characters.count, characters[index + 1] != "[",
              index == 0 || characters[index - 1] != "!",
              let close = characters[(index + 1)...].firstIndex(of: "]"),
              // An empty label would leave nothing on screen once both delimiters are
              // hidden - the `****` guard's shape, one construct over.
              close > index + 1,
              close + 1 < characters.count, characters[close + 1] == "(",
              let paren = characters[(close + 1)...].firstIndex(of: ")")
        else {
            index += 1
            continue
        }
        result.append(MarkdownStyler.StyledRange(range: absolute(index, 1), span: .linkSyntax))
        result.append(MarkdownStyler.StyledRange(
            range: absolute(close, paren + 1 - close), span: .linkSyntax
        ))
        index = paren + 1
    }
    return result
}

/// The `- `/`* `/`+ `/`12. `/`12) ` marker opening a list item, as a span (ADR-0028 §D1).
///
/// Takes `absolute` the way `emphasisMarkers` above does, and lives at file scope for the
/// same reason `taskMarker` below does: `MarkdownStyler`'s own body is already at its
/// length limit and this helper depends on nothing the type carries.
///
/// It trims tabs as well as spaces, which the caller's own `trimmed` does not: a tab is
/// four columns of nesting, so a tab-indented item has to be seen to be measured. That
/// wider trim is also why the checkbox refusal is restated here rather than left to the
/// caller's `taskMarker(in: trimmed)` guard - `\t- [ ] fai` is a checkbox line this sees
/// and that one cannot (§D2, R-06).
///
/// `lineStart`/`text` are the whole note and this line's own start in it, passed through
/// to `ListNesting.level` (PG-085) for the CommonMark content-column depth - the classifier
/// is no longer line-local, since a child's level depends on its enclosing item's marker
/// width, not just its own indentation.
private func listMarkerSpan(
    inLine line: String,
    at lineStart: String.Index,
    in text: String,
    absolute: (Int, Int) -> Range<String.Index>
) -> MarkdownStyler.StyledRange? {
    let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
    let content = line.dropFirst(indent.count)
    guard taskMarker(in: content) == nil, let marker = listMarkerLength(in: content) else { return nil }

    let columns = indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    let level = ListNesting.level(in: text, lineStart: lineStart, indent: columns)
    return MarkdownStyler.StyledRange(
        range: absolute(indent.count, marker.length),
        span: .listMarker(kind: marker.kind, level: level)
    )
}

/// How long a list marker is - itself and the single space after it - and which kind it is.
///
/// The trailing space is what makes it a marker at all: `-nodash` is a word, `1.no-space`
/// is a version number and a bare `1.` at the end of a line is a sentence. Exactly one
/// space is taken, the way `.headingMarker` takes one out of `#   Titolo`, so a marker
/// written with extra spacing does not swallow the indentation of its own text.
private func listMarkerLength(
    in content: some StringProtocol
) -> (length: Int, kind: MarkdownStyler.Span.ListKind)? {
    guard let first = content.first else { return nil }
    if first == "-" || first == "*" || first == "+" {
        return content.dropFirst().hasPrefix(" ") ? (2, .bullet) : nil
    }
    // The digits are left verbatim in the source on purpose (ADR-0028 §D4): the file's own
    // ordinal is the rendered one, so a multi-digit marker is measured, never normalised.
    let digits = content.prefix(while: { $0.isASCII && $0.isNumber }).count
    guard digits > 0 else { return nil }
    let afterDigits = content.dropFirst(digits)
    guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
    return afterDigits.dropFirst().hasPrefix(" ") ? (digits + 2, .ordered) : nil
}

private func taskMarker(in line: some StringProtocol) -> (length: Int, state: TaskItem.State)? {
    guard line.count >= 5, let first = line.first, first == "-" || first == "*" else { return nil }
    let after = line.dropFirst()
    guard after.hasPrefix(" ["), after.count >= 4 else { return nil }
    let marker = Array(after)[2]
    guard Array(after)[3] == "]" else { return nil }
    let state: TaskItem.State = switch marker {
    case "x", "X": .done
    case ">": .rescheduled
    case "-": .cancelled
    default: .open
    }
    return (5, state)
}
