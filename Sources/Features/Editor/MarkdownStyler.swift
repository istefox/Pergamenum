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
        /// `_`/`__` are deliberately excluded and stay visible (ADR-0082 §D2): the shared
        /// grammar's flanking rule keeps `nome_file_lungo` plain, but concealing a `_` run the
        /// parser accepts is a visible change no criterion has asked for yet.
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
        /// A whole Pratiche anchor line, `<!-- pergamenum-message: <Message-ID> -->`, surrounding
        /// whitespace included (ADR-0076 §D9, R-20) - `PraticaEntryAnchor.messageID(inLine:)`'s
        /// grammar, asked rather than restated. The rule's shape: one span over the whole line,
        /// concealed on ADR-0029's whole-line path. Path-agnostic: the styler knows no note, and
        /// only this feature writes the line.
        case messageAnchor
        /// A whole GFM table's source run - header, delimiter and every body row - emitted
        /// by `tableSpans(of:outside:)` (Task 3 of plan
        /// `2026-09-02-editor-wysiwyg-unification`). Declared here, alongside the other
        /// three ADR-0029 constructs, so the exhaustive tables below need editing only
        /// once rather than twice.
        case tableRun
        /// A whole `pergamenum-view` fence's source run - opening backticks through
        /// closing ones, inclusive - emitted by `viewBlockRuns(outside:)` below
        /// (ADR-0033 §D1; plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`,
        /// Task 1). **Closed fences only**: an unclosed one at the end of a note yields no
        /// span at all, so typing the opening backticks never takes the rest of the note
        /// out of the layout mid-keystroke (ADR §D6). The span never reads `render:` -
        /// which renderer a fence names is Task 5's concern, not the classifier's.
        case viewBlockRun
    }

    struct StyledRange: Equatable, Sendable {
        var range: Range<String.Index>
        var span: Span
    }

    /// Returns the styled ranges of a whole note, in no particular order. Ranges may
    /// nest (a wikilink inside a heading); the view applies them in the order given,
    /// so later spans win where they overlap.
    ///
    /// The classification is the shared grammar's (ADR-0082 §D2): one `lineTokens` pass says
    /// what each line is, one `tokens(in:)` pass per line says what is inside it, and this only
    /// maps both onto `Span`. The editor, the reading view, the exporter and the connectors
    /// therefore read a note alike: `file_name_here` is plain everywhere (PG-347).
    static func spans(in text: String) -> [StyledRange] {
        var result: [StyledRange] = []

        let bodyStart = NoteFrontmatter.range(in: text).map { range -> String.Index in
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

        // Both lists are in document order, so one cursor walks the fences beside the lines.
        // A line is what TextKit draws as one paragraph, so it ends at "\n" and "\r\n" only: a
        // U+2028 or a lone "\r" stays inside it, and a run, a tag boundary or a heading's extent
        // reads across it, as the editor's own per-line walk always did (ADR-0082 §D2).
        let tokens = MarkdownBlockParser.lineTokens(in: text, readsFrontmatter: true, endsLine: LineBreak.isTerminator)
        var fence = 0
        for token in tokens {
            if token.kind == .frontmatter || token.kind == .blank { continue }
            while fence < fences.count, fences[fence].range.upperBound <= token.range.lowerBound { fence += 1 }
            if fence < fences.count, fences[fence].range.lowerBound < token.range.upperBound { continue }
            result.append(contentsOf: spans(of: token, in: text))
        }

        result.append(contentsOf: wikilinkSpans(in: text, from: bodyStart, outside: fences))
        result.append(contentsOf: tableSpans(of: tokens, outside: fences))
        // After every `.codeBlock` span above, so a `.viewBlockRun` wins on overlap
        // (ADR-0033 §D14) - `spans(in:)`'s own header rule that later spans win.
        result.append(contentsOf: viewBlockRuns(outside: fences))
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
             .blockquoteMarker, .strikethroughMarker, .horizontalRule, .tableRun,
             // A whole fence's own source run, the same shelf as `.tableRun` immediately
             // above and for the identical reason (ADR-0033 §D1, Task 1).
             .viewBlockRun,
             // A Message-ID is an identifier, not prose (ADR-0076 §D9).
             .messageAnchor:
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

    /// One line's spans: its block marker, then a whole-line embed, then what is inside it.
    ///
    /// The order is the old per-line walk's, kept because later spans win where they overlap: the
    /// marker first, the inline runs (each followed by its own delimiters, then by what it
    /// contains), and the CommonMark links last.
    private static func spans(of token: MarkdownLineToken, in text: String) -> [StyledRange] {
        let line = text[token.range]
        var result = blockSpans(of: token, in: text)
        // A thematic break and a Pratiche anchor are the whole line and nothing else.
        switch result.first?.span {
        case .horizontalRule?, .messageAnchor?: return result
        default: break
        }

        // Every embed spelling holds `![`; asking only then keeps a long note's lines cheap.
        if line.contains("![") {
            let lineText = String(line)
            if let embed = embedRun(inLine: lineText) {
                let start = text.index(
                    token.range.lowerBound, offsetBy: lineText.distance(from: lineText.startIndex, to: embed.lowerBound)
                )
                let end = text.index(start, offsetBy: lineText.distance(from: embed.lowerBound, to: embed.upperBound))
                result.append(StyledRange(range: start..<end, span: .embedRun))
            }
        }

        let inline = MarkdownInlineParser.tokens(in: line)
        for item in inline { result.append(contentsOf: spans(of: item, in: text)) }
        // Last, as they always were: a link's delimiters win over a run that overlaps them.
        for item in inline { result.append(contentsOf: linkSpans(of: item, in: text)) }
        return result
    }

    /// A line's block marker, by the shared grammar's classification of it (ADR-0082 §D2).
    private static func blockSpans(of token: MarkdownLineToken, in text: String) -> [StyledRange] {
        var result: [StyledRange] = []
        let line = text[token.range]
        switch token.kind {
        // A thematic break and a Pratiche anchor are the whole line and nothing else (ADR-0029
        // §D1, ADR-0076 §D9): the comment's `-->` and the id's `<`/`@` are read as nothing more.
        case .rule:
            return [StyledRange(range: token.range, span: .horizontalRule)]
        case .messageAnchor:
            return [StyledRange(range: token.range, span: .messageAnchor)]
        // Unbounded on purpose (R-03): the line's own `>` count *is* the nesting depth,
        // so there is nothing to cap the way `.listMarker`'s level is capped at 6.
        case .quote(let level, let marker):
            result.append(StyledRange(range: marker, span: .blockquoteMarker(level: level)))
        case .heading(let level, let marker):
            result.append(StyledRange(range: token.range, span: .heading(level: level)))
            // After the heading span, on purpose: later spans win on overlap, so the marker
            // keeps the heading's font and gets its own colour on top.
            //
            // No marker for "# " or "#   " - a heading with no title yet. Hiding the hashes
            // there would shrink the row to nothing the instant the caret leaves it, which is
            // worse than showing four characters that do nothing yet.
            if line[marker.upperBound...].contains(where: { $0 != " " }) {
                result.append(StyledRange(range: marker, span: .headingMarker))
            }
        case .task(let state, let marker, let level):
            // The token layer takes the reading view's wider box (a `+` bullet, any blank run
            // before `[`); the task index, `stillSpellsATaskMarker` and `checkboxStateOffset` take
            // only `-`/`*`, one space, `[?]`. A line outside that form is no task here, and its
            // bullet is the list marker the editor has always drawn for it.
            let spelled = text[marker]
            if spelled.count == 5, spelled.first != "+" {
                result.append(StyledRange(range: marker, span: .taskMarker(state: state)))
            } else {
                let bullet = marker.lowerBound..<text.index(marker.lowerBound, offsetBy: 2)
                result.append(StyledRange(range: bullet, span: .listMarker(kind: .bullet, level: level)))
            }
        // A checkbox line is never a list line (ADR-0028 §D2): the token layer says `.task`
        // for it, so `- [ ] fai` keeps its own appearance and gets no bullet.
        //
        // Ordered digits are ASCII here, though the token layer takes any `isNumber`: the
        // editor's own list machinery (`stillSpellsAListMarker`, `ListNesting`,
        // `ListContinuation`) counts ASCII digits only, so `１. ` is drawn as the text it is.
        case .listItem(let ordered, _, let marker, let level):
            if ordered, !text[marker].prefix(while: { $0 != "." && $0 != ")" }).allSatisfy(\.isASCII) { break }
            let kind: Span.ListKind = ordered ? .ordered : .bullet
            result.append(StyledRange(range: marker, span: .listMarker(kind: kind, level: level)))
        default:
            break
        }
        return result
    }

    /// An inline token as spans: a run, then its two delimiters when hiding them leaves something
    /// on screen (`****` and `~~~~` keep theirs). Wikilinks and embeds are not mapped here:
    /// `wikilinkSpans` reads them through `WikilinkParser`, as the index does; CommonMark links
    /// are `linkSpans(of:)`'s.
    private static func spans(of token: MarkdownInlineToken, in text: String) -> [StyledRange] {
        let range = token.range
        // `_` and `__` keep their markers on screen (`underscoreEmphasisHasNoMarkerSpan`).
        let starMarker: Span? = text[range.lowerBound] == "*" ? .emphasisMarker : nil
        switch token.kind {
        case .code:
            return [StyledRange(range: range, span: .code)]
        case .strong(let delimiters):
            return run(range, .bold, delimiters: delimiters, markedBy: starMarker)
        case .emphasis(let delimiters):
            return run(range, .italic, delimiters: delimiters, markedBy: starMarker)
        case .strikethrough(let delimiters):
            return run(range, .strikethrough, delimiters: delimiters, markedBy: .strikethroughMarker)
        // A hashtag is a tag only when the vocabulary says so (T-01): `#varie` has no namespace.
        case .tag(let tag):
            return Tag(tag) == nil ? [] : [StyledRange(range: range, span: .tag(tag))]
        case .scheduled:
            return [StyledRange(range: range, span: .scheduled)]
        case .due:
            return [StyledRange(range: range, span: .due)]
        case .annotation:
            return [StyledRange(range: range, span: .annotation)]
        case .wikilink, .link, .embed:
            return []
        }
    }

    /// A run and its two delimiters. `marker` is nil for `_`/`__`, which stay unconcealed
    /// (ADR-0082 §D2): the shared grammar's flanking rule no longer reads `nome_file_lungo` as
    /// emphasis, which was ADR-0018 §D1's reason for keeping them, but hiding them is a visible
    /// change of its own, proposed apart. `~~` has no twin spelling (ADR-0029 §D1).
    private static func run(
        _ range: Range<String.Index>, _ span: Span, delimiters: [Range<String.Index>], markedBy marker: Span?
    ) -> [StyledRange] {
        var result = [StyledRange(range: range, span: span)]
        // After the run span, on purpose - later spans win on overlap (ADR-0018 §D1). None when
        // hiding them would collapse the run to nothing.
        if let marker, let opening = delimiters.first, let closing = delimiters.last,
           opening.upperBound < closing.lowerBound {
            result.append(StyledRange(range: opening, span: marker))
            result.append(StyledRange(range: closing, span: marker))
        }
        return result
    }

    /// The `[` and `](url)` delimiters of a CommonMark `[testo](url)` link, as two `.linkSyntax`
    /// spans, plus the label between them as a `.linkTarget` span carrying the raw href (issue
    /// #188 / R-03, R-04) - the same span case a wikilink's target already uses, so
    /// `MarkdownAttributedText`/`CardTextAttributes` need no new arm to make this label clickable.
    ///
    /// Two forms are skipped. An `![alt](foto.png)` is an embed, whose own `.embedRun` span covers
    /// the line and whose rendering is `embedParagraph(at:storage:)`'s (ADR-0018 slice 3). An
    /// empty label would leave nothing on screen once both delimiters are hidden - the `****`
    /// guard's shape, one construct over.
    private static func linkSpans(of token: MarkdownInlineToken, in text: String) -> [StyledRange] {
        guard case .link(let url, let syntax) = token.kind, let opening = syntax.first, let closing = syntax.last,
              text[opening.lowerBound] == "[", opening.upperBound < closing.lowerBound
        else { return [] }
        var result = [StyledRange(range: opening, span: .linkSyntax)]
        if !url.isEmpty {
            result.append(StyledRange(range: opening.upperBound..<closing.lowerBound, span: .linkTarget(url)))
        }
        result.append(StyledRange(range: closing, span: .linkSyntax))
        return result
    }

    /// Every GFM table's whole source run - header, delimiter and body rows - as one span
    /// each (ADR-0029 §D10; plan `2026-09-02-editor-wysiwyg-unification`, Task 3).
    ///
    /// Read off the `.tableRow` tokens `lineTokens` already classified, never a second scan of
    /// the note (ADR-0082 §D2): the token layer has seen the delimiter row that makes a line of
    /// pipes a header (R-10). One table is one run of consecutive rows - GFM ends a table at a
    /// blank or pipe-less line, which can open no other, so two tables never touch - and a run
    /// any line of which a fence covers is no table (R-09), `GFMTable.runs`'s own rule.
    private static func tableSpans(
        of tokens: [MarkdownLineToken],
        outside fences: [CodeFence.Region]
    ) -> [StyledRange] {
        var result: [StyledRange] = []
        var index = 0
        while index < tokens.count {
            guard tokens[index].kind == .tableRow else {
                index += 1
                continue
            }
            var end = index + 1
            while end < tokens.count, tokens[end].kind == .tableRow { end += 1 }
            let rows = tokens[index..<end]
            if !rows.contains(where: { row in fences.contains { $0.range.overlaps(row.range) } }),
               let first = rows.first, let last = rows.last {
                result.append(StyledRange(range: first.range.lowerBound..<last.range.upperBound, span: .tableRun))
            }
            index = end
        }
        return result
    }

    /// Every **closed** `pergamenum-view` fence's whole source run - opening backticks
    /// through closing ones, inclusive - as one `.viewBlockRun` span each (ADR-0033 §D1;
    /// plan `2026-09-06-pg-099-views-board-renderer-orphaned-by`, Task 1).
    ///
    /// Filters `fences` (already computed by `spans(in:)` at the call site, the same array
    /// `tableSpans(of:outside:)` above takes) to `ViewBlock.language` and to a fence
    /// that is genuinely **closed**: a `CodeFence.Region` synthesised for an unclosed fence
    /// has `body.upperBound == range.upperBound == text.endIndex`, which a closed one never
    /// does, since a real closing fence line sits after the body. The span does not read
    /// `render:` at all; which renderer a fence names is Task 5's concern.
    private static func viewBlockRuns(
        outside fences: [CodeFence.Region]
    ) -> [StyledRange] {
        fences
            .filter { $0.language == ViewBlock.language }
            .filter { $0.body.upperBound != $0.range.upperBound }
            .map { StyledRange(range: $0.range, span: .viewBlockRun) }
    }

    private static func wikilinkSpans(
        in text: String,
        from start: String.Index,
        outside fences: [CodeFence.Region]
    ) -> [StyledRange] {
        var result: [StyledRange] = []
        // The slice and the base index are the same for every link in the note, and both
        // are a walk over the whole text: built here once rather than four times per link,
        // which is what the shift below used to cost.
        let slice = String(text[start...])
        let offset = text.distance(from: text.startIndex, to: start)
        let sliceStart = text.index(text.startIndex, offsetBy: offset)
        for link in WikilinkParser.links(in: slice) {
            // The parser worked on a slice; shift its indices back onto the full text.
            let lower = text.index(sliceStart, offsetBy: slice.distance(
                from: slice.startIndex, to: link.range.lowerBound
            ))
            let upper = text.index(sliceStart, offsetBy: slice.distance(
                from: slice.startIndex, to: link.range.upperBound
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
                // The range/length above is `link.target`'s literal source length, always - the
                // payload carried for a note link is `resolvedTitle`, so a target styled bold
                // in-place (`[[**Nota**]]`) still resolves to the note actually titled "Nota"
                // rather than to a literal "**Nota**" nothing matches (issue #188 follow-up).
                // An embed's target is a file name, never emphasis-wrapped in practice, and
                // `NoteRename`'s `range: link.range` rewrite already depends on `target` staying
                // the literal bracket interior elsewhere, so only this payload changes.
                result.append(StyledRange(
                    range: targetStart..<targetEnd,
                    span: link.isEmbed ? .embedTarget(link.target) : .linkTarget(link.resolvedTitle)
                ))
            }
        }
        return result
    }
}
