import Foundation

// ADR-0082 §D3, plan docs/plans/pg-385-n2-page.md, Task 3 (PG-385, R-18).
//
// The classes of `StylerGoldenCorpus`, split out of `StylerGoldenCorpus.swift` for `file_length`
// (`StylerGoldenCapturedEditor.swift`'s shape). Every `expected` below is the styler's new output
// for a case whose captured output moved; the captured strings themselves live in the two
// `StylerGoldenCaptured*.swift` files and are never edited.

extension StylerGoldenCorpus {
    /// Classes recorded once a case's output moves (Task 3, ADR-0082 §D3). Every difference the
    /// shared grammar made is class A: the old styler was wrong, and the exporter already read the
    /// input right, with one exception: `*corsivo con **forte** dentro*` (the second half of S36,
    /// and E48), which both readers got wrong and the parser's `closingRange` now nests, so the
    /// exporter's output moved for it too (ADR-0082 §D4, E48 class A there). No B at N2; every
    /// `.deliberate` case below (S38's code-span half, and the cases from "N01" on) is N5's
    /// (ADR-0087). S11, S36 and
    /// S45 first came out as C and were fixed before this table was written: S11 and S45 in the
    /// styler's mapping (ASCII ordered digits; the styler's line is the editor's paragraph, so
    /// `lineTokens` is given `LineBreak.isTerminator` and a U+2028 ends none, S55 to S58), S36 in
    /// the parser's `closingRange`.
    static let changes: [String: StylerGoldenCase.Change] = classedChanges
}

/// Pasted reasons and the new `expected` of every classed case, never a captured string.
private let classedChanges: [String: StylerGoldenCase.Change] = [
    "E21": .fix(
        reason: "`2 * 3 * 4` is arithmetic: a `*` followed by a space opens nothing, as the exporter already read it "
            + "(PG-347).",
        expected: #"""
        """#
    ),
    "E23": .fix(
        reason: "`**forte con *corsivo***` closes at the end of the run, so the inner italic is styled and no `*` is "
            + "left over.",
        expected: #"""
        0..<2 emphasisMarker
        0..<23 bold
        12..<13 emphasisMarker
        12..<21 italic
        20..<21 emphasisMarker
        21..<23 emphasisMarker
        hidden 0..<2 emphasis
        hidden 12..<13 emphasis
        hidden 20..<21 emphasis
        hidden 21..<23 emphasis
        order 0..<23 bold < 0..<2 emphasisMarker
        order 0..<23 bold < 21..<23 emphasisMarker
        order 0..<23 bold < 12..<21 italic
        order 0..<23 bold < 12..<13 emphasisMarker
        order 0..<23 bold < 20..<21 emphasisMarker
        order 12..<21 italic < 12..<13 emphasisMarker
        order 12..<21 italic < 20..<21 emphasisMarker
        """#
    ),
    "E25": .fix(
        reason: "An intraword `_` opens nothing: `file_name_here` is a file name, as in the exporter (ADR-0077 §D5).",
        expected: #"""
        17..<26 bold
        29..<36 italic
        """#
    ),
    "E28": .fix(
        reason: "`[1]` is not one of the task index's markers (`TaskParser.state(for:)`): the line is a bullet, as "
            + "the reading view draws it.",
        expected: #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<2 list
        """#
    ),
    "E29": .fix(
        reason: "`[a]` is not one of the task index's markers (`TaskParser.state(for:)`): the line is a bullet, as "
            + "the reading view draws it.",
        expected: #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<2 list
        """#
    ),
    "E42": .fix(
        reason: "The bullet's `*` is the list marker and no longer pairs with the stars after it: `**grassetto**` is "
            + "bold.",
        expected: #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        2..<4 emphasisMarker
        2..<15 bold
        13..<15 emphasisMarker
        hidden 0..<2 list
        hidden 2..<4 emphasis
        hidden 13..<15 emphasis
        order 2..<15 bold < 2..<4 emphasisMarker
        order 2..<15 bold < 13..<15 emphasisMarker
        """#
    ),
    "E48": .fix(
        reason: "S36's second half alone: one italic holding a bold, instead of three italics (the export moved too, "
            + "§D4).",
        expected: #"""
        0..<1 emphasisMarker
        0..<30 italic
        13..<15 emphasisMarker
        13..<22 bold
        20..<22 emphasisMarker
        29..<30 emphasisMarker
        hidden 0..<1 emphasis
        hidden 13..<15 emphasis
        hidden 20..<22 emphasis
        hidden 29..<30 emphasis
        order 0..<30 italic < 0..<1 emphasisMarker
        order 0..<30 italic < 29..<30 emphasisMarker
        order 0..<30 italic < 13..<22 bold
        order 0..<30 italic < 13..<15 emphasisMarker
        order 0..<30 italic < 20..<22 emphasisMarker
        order 13..<22 bold < 13..<15 emphasisMarker
        order 13..<22 bold < 20..<22 emphasisMarker
        """#
    ),
    "S30": .fix(
        reason: "The `_` inside the link's URL is intraword and opens nothing: no italic inside the target.",
        expected: #"""
        0..<1 linkSyntax
        1..<26 linkTarget("https://example.com/a_b_c")
        11..<12 emphasisMarker
        11..<19 italic
        18..<19 emphasisMarker
        26..<54 linkSyntax
        hidden 0..<1 link
        hidden 11..<12 emphasis
        hidden 18..<19 emphasis
        hidden 26..<54 link
        order 11..<19 italic < 11..<12 emphasisMarker
        order 11..<19 italic < 18..<19 emphasisMarker
        order 11..<19 italic < 1..<26 linkTarget("https://example.com/a_b_c")
        order 11..<12 emphasisMarker < 1..<26 linkTarget("https://example.com/a_b_c")
        order 18..<19 emphasisMarker < 1..<26 linkTarget("https://example.com/a_b_c")
        """#
    ),
    "S32": .fix(
        reason: "An intraword `_` opens nothing: `file_name_here` is a file name (PG-347, ADR-0077 §D5).",
        expected: #"""
        """#
    ),
    "S33": .fix(
        reason: "`2 * 3 * 4` is arithmetic: a `*` followed by a space opens nothing (PG-347).",
        expected: #"""
        """#
    ),
    "S34": .fix(
        reason: "An intraword `_` opens nothing: both file names stay plain (ADR-0077 §D5).",
        expected: #"""
        """#
    ),
    "S35": .fix(
        reason: "`***entrambi***` closes at the end of the run: one bold with an italic inside, every `*` concealed.",
        expected: #"""
        0..<9 italic
        12..<21 bold
        24..<25 emphasisMarker
        24..<33 italic
        32..<33 emphasisMarker
        36..<38 emphasisMarker
        36..<45 bold
        43..<45 emphasisMarker
        48..<50 emphasisMarker
        48..<62 bold
        50..<51 emphasisMarker
        50..<60 italic
        59..<60 emphasisMarker
        60..<62 emphasisMarker
        hidden 24..<25 emphasis
        hidden 32..<33 emphasis
        hidden 36..<38 emphasis
        hidden 43..<45 emphasis
        hidden 48..<50 emphasis
        hidden 50..<51 emphasis
        hidden 59..<60 emphasis
        hidden 60..<62 emphasis
        order 24..<33 italic < 24..<25 emphasisMarker
        order 24..<33 italic < 32..<33 emphasisMarker
        order 36..<45 bold < 36..<38 emphasisMarker
        order 36..<45 bold < 43..<45 emphasisMarker
        order 48..<62 bold < 48..<50 emphasisMarker
        order 48..<62 bold < 60..<62 emphasisMarker
        order 48..<62 bold < 50..<60 italic
        order 48..<62 bold < 50..<51 emphasisMarker
        order 48..<62 bold < 59..<60 emphasisMarker
        order 50..<60 italic < 50..<51 emphasisMarker
        order 50..<60 italic < 59..<60 emphasisMarker
        """#
    ),
    "S36": .fix(
        reason: "A single `*` steps over the `**forte**` nested in it: one italic over the run with a bold inside, "
            + "instead of three italics and no bold.",
        expected: #"""
        0..<2 emphasisMarker
        0..<30 bold
        12..<13 emphasisMarker
        12..<21 italic
        20..<21 emphasisMarker
        28..<30 emphasisMarker
        33..<34 emphasisMarker
        33..<63 italic
        46..<48 emphasisMarker
        46..<55 bold
        53..<55 emphasisMarker
        62..<63 emphasisMarker
        hidden 0..<2 emphasis
        hidden 12..<13 emphasis
        hidden 20..<21 emphasis
        hidden 28..<30 emphasis
        hidden 33..<34 emphasis
        hidden 46..<48 emphasis
        hidden 53..<55 emphasis
        hidden 62..<63 emphasis
        order 0..<30 bold < 0..<2 emphasisMarker
        order 0..<30 bold < 28..<30 emphasisMarker
        order 0..<30 bold < 12..<21 italic
        order 0..<30 bold < 12..<13 emphasisMarker
        order 0..<30 bold < 20..<21 emphasisMarker
        order 12..<21 italic < 12..<13 emphasisMarker
        order 12..<21 italic < 20..<21 emphasisMarker
        order 33..<63 italic < 33..<34 emphasisMarker
        order 33..<63 italic < 62..<63 emphasisMarker
        order 33..<63 italic < 46..<55 bold
        order 33..<63 italic < 46..<48 emphasisMarker
        order 33..<63 italic < 53..<55 emphasisMarker
        order 46..<55 bold < 46..<48 emphasisMarker
        order 46..<55 bold < 53..<55 emphasisMarker
        """#
    ),
    "S37": .fix(
        reason: "Unclosed delimiters open nothing: the old styler paired the second `*` of `**non` with the `*` of "
            + "`*neanche`.",
        expected: #"""
        """#
    ),
    "S38": .deliberate(
        reason: "`~~ non barrato ~~` is no strikethrough: a delimiter followed by a space opens nothing, as in "
            + "the exporter (class A, N2). And the code spans follow CommonMark's backtick runs (ADR-0087 §D5): "
            + "``` ``doppio ` tick`` ``` is one span closed by the matching double run, each run an "
            + "`inlineCodeMarker` concealed off the caret.",
        expected: #"""
        0..<2 strikethroughMarker
        0..<11 strikethrough
        9..<11 strikethroughMarker
        34..<35 inlineCodeMarker
        34..<42 code
        41..<42 inlineCodeMarker
        45..<47 inlineCodeMarker
        45..<62 code
        60..<62 inlineCodeMarker
        hidden 0..<2 strikethrough
        hidden 9..<11 strikethrough
        hidden 34..<35 inlineCode
        hidden 41..<42 inlineCode
        hidden 45..<47 inlineCode
        hidden 60..<62 inlineCode
        order 0..<11 strikethrough < 0..<2 strikethroughMarker
        order 0..<11 strikethrough < 9..<11 strikethroughMarker
        order 34..<42 code < 34..<35 inlineCodeMarker
        order 34..<42 code < 41..<42 inlineCodeMarker
        order 45..<62 code < 45..<47 inlineCodeMarker
        order 45..<62 code < 60..<62 inlineCodeMarker
        """#
    ),
    "S51": .fix(
        reason: "A tab before `#` hides no heading: the reading view and the exporter already trimmed tabs.",
        expected: #"""
        0..<19 heading(level: 1)
        1..<3 headingMarker
        21..<32 heading(level: 2)
        22..<25 headingMarker
        hidden 1..<3 heading
        hidden 22..<25 heading
        order 0..<19 heading(level: 1) < 1..<3 headingMarker
        order 21..<32 heading(level: 2) < 22..<25 headingMarker
        """#
    ),
    "S52": .fix(
        reason: "A tab before `>` hides no quote, as in the reading view and the exporter. `> >` is level 1 here, "
            + "as in S13, where those two count level 2 (ADR-0087's accepted spaced-nesting deviation).",
        expected: #"""
        1..<3 blockquoteMarker(level: 1)
        25..<27 blockquoteMarker(level: 1)
        hidden 1..<3 blockquote
        hidden 25..<27 blockquote
        """#
    ),
    "S53": .fix(
        reason: "A tab before `---` or `***` hides no rule: the reading view and the exporter already drew both.",
        expected: #"""
        7..<11 horizontalRule
        20..<24 horizontalRule
        hidden 7..<11 rule
        hidden 20..<24 rule
        """#
    ),
    "S60": .fix(
        reason: "A tab before `- - -` hides no rule either, as for S53: the reading view and the exporter already drew "
            + "it; the old styler trimmed tabs only for a list marker and drew a bullet there.",
        expected: #"""
        0..<6 horizontalRule
        8..<10 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<6 rule
        hidden 8..<10 list
        """#
    ),
    "S54": .fix(
        reason: "A tab-indented `- [ ]` is a task for `TaskParser.parse` (it trims tabs); the old styler drew nothing "
            + "there.",
        expected: #"""
        1..<6 taskMarker(state: TaskItem.State.open)
        13..<18 taskMarker(state: TaskItem.State.done)
        hidden 1..<6 checkbox
        hidden 13..<18 checkbox
        """#
    ),
    "S59": .fix(
        reason: "A pipe-less `---` under a one-column header is the table's delimiter row, as the reading view and "
            + "the exporter read it: one table run, no rule drawn over the row (ADR-0082 §D4).",
        expected: #"""
        0..<15 tableRun
        """#
    ),
    // N5 (ADR-0087 §D5, plan docs/plans/note-workflow-n5.md, Task 3): class B, a deliberate change.
    // Written from the plan's "maps it with `run(...)` to `.highlight` plus two `.highlightMarker`"
    // and `hiddenKind`'s `.highlight`, never captured: the styler does not emit it yet. Every other
    // N5 case whose output will move (the inline code, fence, callout and chip cases) is classed by
    // the task that gives it its spans, against `MarkdownStylerTests`' own assertions.
    "N01": .deliberate(
        reason: "`==b==` is a highlight (ADR-0087 §D5): one `.highlight` run and its two `==` delimiters, which "
            + "the editor conceals off the caret.",
        expected: #"""
        2..<4 highlightMarker
        2..<7 highlight
        5..<7 highlightMarker
        hidden 2..<4 highlight
        hidden 5..<7 highlight
        order 2..<7 highlight < 2..<4 highlightMarker
        order 2..<7 highlight < 5..<7 highlightMarker
        """#
    ),
    // N5 (ADR-0087, plan docs/plans/note-workflow-n5.md, Task 4 to 7): class B, every one deliberate.
    // Each `expected` is `stylerGoldenCapture`'s output once the construct's spans landed.
    "E16": .deliberate(
        reason: "An embed inside a line of prose reads as a chip (ADR-0087 §D9): its `![[` and its `|W]]`/`]]` "
            + "are `embedChipMarker`s, concealed off the caret, and the name stays.",
        expected: #"""
        5..<8 embedChipMarker
        5..<22 linkSyntax
        8..<16 embedTarget("foto.png")
        16..<22 embedChipMarker
        hidden 5..<8 embedChip
        hidden 5..<22 link
        hidden 16..<22 embedChip
        order 5..<22 linkSyntax < 8..<16 embedTarget("foto.png")
        order 5..<22 linkSyntax < 5..<8 embedChipMarker
        order 5..<22 linkSyntax < 16..<22 embedChipMarker
        """#
    ),
    "E20": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret.",
        expected: #"""
        4..<5 inlineCodeMarker
        4..<11 code
        10..<11 inlineCodeMarker
        14..<15 inlineCodeMarker
        14..<21 code
        20..<21 inlineCodeMarker
        hidden 4..<5 inlineCode
        hidden 10..<11 inlineCode
        hidden 14..<15 inlineCode
        hidden 20..<21 inlineCode
        order 4..<11 code < 4..<5 inlineCodeMarker
        order 4..<11 code < 10..<11 inlineCodeMarker
        order 14..<21 code < 14..<15 inlineCodeMarker
        order 14..<21 code < 20..<21 inlineCodeMarker
        """#
    ),
    "N02": .deliberate(
        reason: "`==**x**==` is a highlight around bold (ADR-0087 §D5): one `.highlight` run and its two `==`, "
            + "concealed off the caret, with the bold inside it unchanged.",
        expected: #"""
        0..<2 highlightMarker
        0..<9 highlight
        2..<4 emphasisMarker
        2..<7 bold
        5..<7 emphasisMarker
        7..<9 highlightMarker
        hidden 0..<2 highlight
        hidden 2..<4 emphasis
        hidden 5..<7 emphasis
        hidden 7..<9 highlight
        order 0..<9 highlight < 0..<2 highlightMarker
        order 0..<9 highlight < 7..<9 highlightMarker
        order 0..<9 highlight < 2..<7 bold
        order 0..<9 highlight < 2..<4 emphasisMarker
        order 0..<9 highlight < 5..<7 emphasisMarker
        order 2..<7 bold < 2..<4 emphasisMarker
        order 2..<7 bold < 5..<7 emphasisMarker
        """#
    ),
    "N03": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret.",
        expected: #"""
        0..<1 inlineCodeMarker
        0..<8 code
        7..<8 inlineCodeMarker
        hidden 0..<1 inlineCode
        hidden 7..<8 inlineCode
        order 0..<8 code < 0..<1 inlineCodeMarker
        order 0..<8 code < 7..<8 inlineCodeMarker
        """#
    ),
    "N06": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker, and each body line carries `calloutBody`.",
        expected: #"""
        0..<13 calloutMarker(CalloutKind.warning, fold: Callout.Fold.fixed)
        19..<21 blockquoteMarker(level: 1)
        19..<26 calloutBody(CalloutKind.warning)
        hidden 0..<13 calloutMarker
        hidden 19..<21 blockquote
        order 19..<26 calloutBody(CalloutKind.warning) < 19..<21 blockquoteMarker(level: 1)
        """#
    ),
    "N07": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<9 calloutMarker(CalloutKind.note, fold: Callout.Fold.fixed)
        hidden 0..<9 calloutMarker
        """#
    ),
    "N08": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<8 calloutMarker(CalloutKind.tip, fold: Callout.Fold.fixed)
        hidden 0..<8 calloutMarker
        """#
    ),
    "N09": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<14 calloutMarker(CalloutKind.important, fold: Callout.Fold.fixed)
        hidden 0..<14 calloutMarker
        """#
    ),
    "N10": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<12 calloutMarker(CalloutKind.warning, fold: Callout.Fold.fixed)
        hidden 0..<12 calloutMarker
        """#
    ),
    "N11": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<12 calloutMarker(CalloutKind.caution, fold: Callout.Fold.fixed)
        hidden 0..<12 calloutMarker
        """#
    ),
    "N12": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<11 calloutMarker(CalloutKind.warning, fold: Callout.Fold.fixed)
        hidden 0..<11 calloutMarker
        """#
    ),
    "N13": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<9 calloutMarker(CalloutKind.note, fold: Callout.Fold.fixed)
        hidden 0..<9 calloutMarker
        """#
    ),
    "N14": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker. An unknown type is kept as `other`.",
        expected: #"""
        0..<9 calloutMarker(CalloutKind.other("faq"), fold: Callout.Fold.fixed)
        hidden 0..<9 calloutMarker
        """#
    ),
    "N15": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker, and each body line carries `calloutBody`. The "
            + "`-` sign folds it.",
        expected: #"""
        0..<10 calloutMarker(CalloutKind.tip, fold: Callout.Fold.folded)
        17..<19 blockquoteMarker(level: 1)
        17..<24 calloutBody(CalloutKind.tip)
        hidden 0..<10 calloutMarker
        hidden 17..<19 blockquote
        order 17..<24 calloutBody(CalloutKind.tip) < 17..<19 blockquoteMarker(level: 1)
        """#
    ),
    "N16": .deliberate(
        reason: "`> [!type]` opens a callout (ADR-0087 §D8): one `calloutMarker` over the marker run, concealed "
            + "off the caret, in place of the quote's `>` marker.",
        expected: #"""
        0..<10 calloutMarker(CalloutKind.note, fold: Callout.Fold.fixed)
        hidden 0..<10 calloutMarker
        """#
    ),
    "N19": .deliberate(
        reason: "A closed fence's opening and closing lines are its chrome (ADR-0087 §D6): `fenceOpening` and "
            + "`fenceClosing`, both concealed off the caret.",
        expected: #"""
        0..<8 fenceOpening
        0..<22 codeBlock
        9..<12 codeToken(CodeSyntax.Token.keyword)
        17..<18 codeToken(CodeSyntax.Token.number)
        19..<22 fenceClosing
        hidden 0..<8 fenceOpening
        hidden 19..<22 fenceClosing
        order 0..<22 codeBlock < 9..<12 codeToken(CodeSyntax.Token.keyword)
        order 0..<22 codeBlock < 17..<18 codeToken(CodeSyntax.Token.number)
        order 0..<22 codeBlock < 0..<8 fenceOpening
        order 0..<22 codeBlock < 19..<22 fenceClosing
        """#
    ),
    "S19": .deliberate(
        reason: "A closed fence's opening and closing lines are its chrome (ADR-0087 §D6): `fenceOpening` and "
            + "`fenceClosing`, both concealed off the caret.",
        expected: #"""
        0..<3 fenceOpening
        0..<36 codeBlock
        33..<36 fenceClosing
        hidden 0..<3 fenceOpening
        hidden 33..<36 fenceClosing
        order 0..<36 codeBlock < 0..<3 fenceOpening
        order 0..<36 codeBlock < 33..<36 fenceClosing
        """#
    ),
    "S20": .deliberate(
        reason: "A closed fence's opening and closing lines are its chrome (ADR-0087 §D6): `fenceOpening` and "
            + "`fenceClosing`, both concealed off the caret.",
        expected: #"""
        0..<8 fenceOpening
        0..<46 codeBlock
        9..<12 codeToken(CodeSyntax.Token.keyword)
        17..<18 codeToken(CodeSyntax.Token.number)
        19..<30 codeToken(CodeSyntax.Token.comment)
        31..<35 codeToken(CodeSyntax.Token.keyword)
        43..<46 fenceClosing
        hidden 0..<8 fenceOpening
        hidden 43..<46 fenceClosing
        order 0..<46 codeBlock < 9..<12 codeToken(CodeSyntax.Token.keyword)
        order 0..<46 codeBlock < 17..<18 codeToken(CodeSyntax.Token.number)
        order 0..<46 codeBlock < 19..<30 codeToken(CodeSyntax.Token.comment)
        order 0..<46 codeBlock < 31..<35 codeToken(CodeSyntax.Token.keyword)
        order 0..<46 codeBlock < 0..<8 fenceOpening
        order 0..<46 codeBlock < 43..<46 fenceClosing
        """#
    ),
    "S27": .deliberate(
        reason: "An embed inside a line of prose reads as a chip (ADR-0087 §D9): its `![[` and its `|W]]`/`]]` "
            + "are `embedChipMarker`s, concealed off the caret, and the name stays.",
        expected: #"""
        0..<3 embedChipMarker
        0..<13 linkSyntax
        3..<11 embedTarget("foto.png")
        11..<13 embedChipMarker
        16..<19 embedChipMarker
        16..<33 linkSyntax
        19..<27 embedTarget("foto.png")
        27..<33 embedChipMarker
        36..<39 embedChipMarker
        36..<57 linkSyntax
        39..<47 embedTarget("foto.png")
        47..<57 embedChipMarker
        hidden 0..<3 embedChip
        hidden 0..<13 link
        hidden 11..<13 embedChip
        hidden 16..<19 embedChip
        hidden 16..<33 link
        hidden 27..<33 embedChip
        hidden 36..<39 embedChip
        hidden 36..<57 link
        hidden 47..<57 embedChip
        order 0..<13 linkSyntax < 3..<11 embedTarget("foto.png")
        order 0..<13 linkSyntax < 0..<3 embedChipMarker
        order 0..<13 linkSyntax < 11..<13 embedChipMarker
        order 16..<33 linkSyntax < 19..<27 embedTarget("foto.png")
        order 16..<33 linkSyntax < 16..<19 embedChipMarker
        order 16..<33 linkSyntax < 27..<33 embedChipMarker
        order 36..<57 linkSyntax < 39..<47 embedTarget("foto.png")
        order 36..<57 linkSyntax < 36..<39 embedChipMarker
        order 36..<57 linkSyntax < 47..<57 embedChipMarker
        """#
    ),
    "S39": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret.",
        expected: #"""
        0..<1 inlineCodeMarker
        0..<15 code
        14..<15 inlineCodeMarker
        18..<20 emphasisMarker
        18..<43 bold
        20..<21 inlineCodeMarker
        20..<41 code
        40..<41 inlineCodeMarker
        41..<43 emphasisMarker
        46..<58 linkSyntax
        48..<50 emphasisMarker
        48..<56 bold
        48..<56 linkTarget("nota")
        54..<56 emphasisMarker
        hidden 0..<1 inlineCode
        hidden 14..<15 inlineCode
        hidden 18..<20 emphasis
        hidden 20..<21 inlineCode
        hidden 40..<41 inlineCode
        hidden 41..<43 emphasis
        hidden 46..<58 link
        hidden 48..<50 emphasis
        hidden 54..<56 emphasis
        order 0..<15 code < 0..<1 inlineCodeMarker
        order 0..<15 code < 14..<15 inlineCodeMarker
        order 18..<43 bold < 18..<20 emphasisMarker
        order 18..<43 bold < 41..<43 emphasisMarker
        order 18..<43 bold < 20..<41 code
        order 18..<43 bold < 20..<21 inlineCodeMarker
        order 18..<43 bold < 40..<41 inlineCodeMarker
        order 20..<41 code < 20..<21 inlineCodeMarker
        order 20..<41 code < 40..<41 inlineCodeMarker
        order 48..<56 bold < 48..<50 emphasisMarker
        order 48..<56 bold < 54..<56 emphasisMarker
        order 48..<56 bold < 46..<58 linkSyntax
        order 48..<56 bold < 48..<56 linkTarget("nota")
        order 48..<50 emphasisMarker < 46..<58 linkSyntax
        order 48..<50 emphasisMarker < 48..<56 linkTarget("nota")
        order 54..<56 emphasisMarker < 46..<58 linkSyntax
        order 54..<56 emphasisMarker < 48..<56 linkTarget("nota")
        order 46..<58 linkSyntax < 48..<56 linkTarget("nota")
        """#
    ),
    "S47": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret. A closed fence's opening and closing lines are its chrome (ADR-0087 §D6): "
            + "`fenceOpening` and `fenceClosing`, both concealed off the caret.",
        expected: #"""
        0..<44 frontmatter
        46..<48 headingMarker
        46..<74 heading(level: 1)
        59..<67 linkSyntax
        61..<65 linkTarget("Nota")
        86..<88 emphasisMarker
        86..<95 bold
        93..<95 emphasisMarker
        97..<98 emphasisMarker
        97..<106 italic
        105..<106 emphasisMarker
        108..<110 strikethroughMarker
        108..<119 strikethrough
        117..<119 strikethroughMarker
        121..<122 inlineCodeMarker
        121..<129 code
        128..<129 inlineCodeMarker
        132..<133 linkSyntax
        133..<137 linkTarget("https://x.it")
        137..<152 linkSyntax
        155..<160 taskMarker(state: TaskItem.State.open)
        170..<181 scheduled
        182..<193 due
        194..<213 annotation
        216..<218 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 2)
        230..<233 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        237..<240 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        245..<247 blockquoteMarker(level: 1)
        261..<262 emphasisMarker
        261..<269 italic
        268..<269 emphasisMarker
        271..<279 fenceOpening
        271..<300 codeBlock
        280..<283 codeToken(CodeSyntax.Token.keyword)
        293..<296 codeToken(CodeSyntax.Token.number)
        297..<300 fenceClosing
        302..<331 tableRun
        333..<350 embedRun
        333..<350 linkSyntax
        336..<344 embedTarget("foto.png")
        hidden 46..<48 heading
        hidden 59..<67 link
        hidden 86..<88 emphasis
        hidden 93..<95 emphasis
        hidden 97..<98 emphasis
        hidden 105..<106 emphasis
        hidden 108..<110 strikethrough
        hidden 117..<119 strikethrough
        hidden 121..<122 inlineCode
        hidden 128..<129 inlineCode
        hidden 132..<133 link
        hidden 137..<152 link
        hidden 155..<160 checkbox
        hidden 216..<218 list
        hidden 230..<233 list
        hidden 237..<240 list
        hidden 245..<247 blockquote
        hidden 261..<262 emphasis
        hidden 268..<269 emphasis
        hidden 271..<279 fenceOpening
        hidden 297..<300 fenceClosing
        hidden 333..<350 embed
        hidden 333..<350 link
        order 271..<300 codeBlock < 280..<283 codeToken(CodeSyntax.Token.keyword)
        order 271..<300 codeBlock < 293..<296 codeToken(CodeSyntax.Token.number)
        order 271..<300 codeBlock < 271..<279 fenceOpening
        order 271..<300 codeBlock < 297..<300 fenceClosing
        order 46..<74 heading(level: 1) < 46..<48 headingMarker
        order 46..<74 heading(level: 1) < 59..<67 linkSyntax
        order 46..<74 heading(level: 1) < 61..<65 linkTarget("Nota")
        order 86..<95 bold < 86..<88 emphasisMarker
        order 86..<95 bold < 93..<95 emphasisMarker
        order 97..<106 italic < 97..<98 emphasisMarker
        order 97..<106 italic < 105..<106 emphasisMarker
        order 108..<119 strikethrough < 108..<110 strikethroughMarker
        order 108..<119 strikethrough < 117..<119 strikethroughMarker
        order 121..<129 code < 121..<122 inlineCodeMarker
        order 121..<129 code < 128..<129 inlineCodeMarker
        order 261..<269 italic < 261..<262 emphasisMarker
        order 261..<269 italic < 268..<269 emphasisMarker
        order 333..<350 embedRun < 333..<350 linkSyntax
        order 333..<350 embedRun < 336..<344 embedTarget("foto.png")
        order 59..<67 linkSyntax < 61..<65 linkTarget("Nota")
        order 333..<350 linkSyntax < 336..<344 embedTarget("foto.png")
        """#
    ),
    "S55": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret.",
        expected: #"""
        2..<4 emphasisMarker
        2..<9 bold
        7..<9 emphasisMarker
        12..<13 inlineCodeMarker
        12..<17 code
        16..<17 inlineCodeMarker
        20..<21 linkSyntax
        21..<24 linkTarget("u")
        24..<28 linkSyntax
        hidden 2..<4 emphasis
        hidden 7..<9 emphasis
        hidden 12..<13 inlineCode
        hidden 16..<17 inlineCode
        hidden 20..<21 link
        hidden 24..<28 link
        order 2..<9 bold < 2..<4 emphasisMarker
        order 2..<9 bold < 7..<9 emphasisMarker
        order 12..<17 code < 12..<13 inlineCodeMarker
        order 12..<17 code < 16..<17 inlineCodeMarker
        """#
    ),
    "W01": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret.",
        expected: #"""
        0..<74 frontmatter
        76..<78 headingMarker
        76..<102 heading(level: 1)
        116..<118 emphasisMarker
        116..<125 bold
        123..<125 emphasisMarker
        154..<155 emphasisMarker
        154..<162 italic
        161..<162 emphasisMarker
        165..<168 headingMarker
        165..<182 heading(level: 2)
        184..<186 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        186..<200 linkSyntax
        188..<198 linkTarget("Altra nota")
        232..<235 headingMarker
        232..<241 heading(level: 2)
        254..<255 inlineCodeMarker
        254..<269 code
        268..<269 inlineCodeMarker
        hidden 76..<78 heading
        hidden 116..<118 emphasis
        hidden 123..<125 emphasis
        hidden 154..<155 emphasis
        hidden 161..<162 emphasis
        hidden 165..<168 heading
        hidden 184..<186 list
        hidden 186..<200 link
        hidden 232..<235 heading
        hidden 254..<255 inlineCode
        hidden 268..<269 inlineCode
        order 76..<102 heading(level: 1) < 76..<78 headingMarker
        order 116..<125 bold < 116..<118 emphasisMarker
        order 116..<125 bold < 123..<125 emphasisMarker
        order 154..<162 italic < 154..<155 emphasisMarker
        order 154..<162 italic < 161..<162 emphasisMarker
        order 165..<182 heading(level: 2) < 165..<168 headingMarker
        order 232..<241 heading(level: 2) < 232..<235 headingMarker
        order 254..<269 code < 254..<255 inlineCodeMarker
        order 254..<269 code < 268..<269 inlineCodeMarker
        order 186..<200 linkSyntax < 188..<198 linkTarget("Altra nota")
        """#
    ),
    "W02": .deliberate(
        reason: "A closed fence's opening and closing lines are its chrome (ADR-0087 §D6): `fenceOpening` and "
            + "`fenceClosing`, both concealed off the caret.",
        expected: #"""
        0..<44 frontmatter
        46..<48 headingMarker
        46..<60 heading(level: 1)
        74..<76 emphasisMarker
        74..<83 bold
        81..<83 emphasisMarker
        104..<105 emphasisMarker
        104..<112 italic
        111..<112 emphasisMarker
        118..<120 strikethroughMarker
        118..<129 strikethrough
        127..<129 strikethroughMarker
        139..<141 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        153..<155 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        170..<173 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        183..<186 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        197..<202 taskMarker(state: TaskItem.State.open)
        217..<222 taskMarker(state: TaskItem.State.done)
        234..<239 taskMarker(state: TaskItem.State.cancelled)
        250..<255 taskMarker(state: TaskItem.State.rescheduled)
        266..<268 blockquoteMarker(level: 1)
        282..<284 blockquoteMarker(level: 1)
        299..<307 fenceOpening
        299..<328 codeBlock
        308..<311 codeToken(CodeSyntax.Token.keyword)
        321..<324 codeToken(CodeSyntax.Token.number)
        325..<328 fenceClosing
        330..<397 codeBlock
        330..<397 viewBlockRun
        399..<402 horizontalRule
        404..<457 tableRun
        459..<476 embedRun
        459..<476 linkSyntax
        462..<470 embedTarget("foto.png")
        478..<501 linkSyntax
        481..<491 embedTarget("Altra nota")
        hidden 46..<48 heading
        hidden 74..<76 emphasis
        hidden 81..<83 emphasis
        hidden 104..<105 emphasis
        hidden 111..<112 emphasis
        hidden 118..<120 strikethrough
        hidden 127..<129 strikethrough
        hidden 139..<141 list
        hidden 153..<155 list
        hidden 170..<173 list
        hidden 183..<186 list
        hidden 197..<202 checkbox
        hidden 217..<222 checkbox
        hidden 234..<239 checkbox
        hidden 250..<255 checkbox
        hidden 266..<268 blockquote
        hidden 282..<284 blockquote
        hidden 299..<307 fenceOpening
        hidden 325..<328 fenceClosing
        hidden 399..<402 rule
        hidden 459..<476 embed
        hidden 459..<476 link
        hidden 478..<501 link
        order 299..<328 codeBlock < 308..<311 codeToken(CodeSyntax.Token.keyword)
        order 299..<328 codeBlock < 321..<324 codeToken(CodeSyntax.Token.number)
        order 299..<328 codeBlock < 299..<307 fenceOpening
        order 299..<328 codeBlock < 325..<328 fenceClosing
        order 330..<397 codeBlock < 330..<397 viewBlockRun
        order 46..<60 heading(level: 1) < 46..<48 headingMarker
        order 74..<83 bold < 74..<76 emphasisMarker
        order 74..<83 bold < 81..<83 emphasisMarker
        order 104..<112 italic < 104..<105 emphasisMarker
        order 104..<112 italic < 111..<112 emphasisMarker
        order 118..<129 strikethrough < 118..<120 strikethroughMarker
        order 118..<129 strikethrough < 127..<129 strikethroughMarker
        order 459..<476 embedRun < 459..<476 linkSyntax
        order 459..<476 embedRun < 462..<470 embedTarget("foto.png")
        order 459..<476 linkSyntax < 462..<470 embedTarget("foto.png")
        order 478..<501 linkSyntax < 481..<491 embedTarget("Altra nota")
        """#
    ),
    "X02": .deliberate(
        reason: "Inline code is a pill (ADR-0087 §D5): each backtick run is an `inlineCodeMarker`, concealed off "
            + "the caret.",
        expected: #"""
        0..<1 inlineCodeMarker
        0..<19 code
        18..<19 inlineCodeMarker
        hidden 0..<1 inlineCode
        hidden 18..<19 inlineCode
        order 0..<19 code < 0..<1 inlineCodeMarker
        order 0..<19 code < 18..<19 inlineCodeMarker
        """#
    ),
    "X07": .deliberate(
        reason: "A closed fence's opening and closing lines are its chrome (ADR-0087 §D6): `fenceOpening` and "
            + "`fenceClosing`, both concealed off the caret.",
        expected: #"""
        0..<3 fenceOpening
        0..<25 codeBlock
        22..<25 fenceClosing
        hidden 0..<3 fenceOpening
        hidden 22..<25 fenceClosing
        order 0..<25 codeBlock < 0..<3 fenceOpening
        order 0..<25 codeBlock < 22..<25 fenceClosing
        """#
    ),
]
