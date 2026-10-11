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
    /// exporter's output moved for it too (ADR-0082 §D4, E48 class A there). No B. S11, S36 and
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
    "S38": .fix(
        reason: "`~~ non barrato ~~` is no strikethrough: a delimiter followed by a space opens nothing, as in the "
            + "exporter.",
        expected: #"""
        0..<2 strikethroughMarker
        0..<11 strikethrough
        9..<11 strikethroughMarker
        34..<42 code
        45..<47 code
        54..<61 code
        hidden 0..<2 strikethrough
        hidden 9..<11 strikethrough
        order 0..<11 strikethrough < 0..<2 strikethroughMarker
        order 0..<11 strikethrough < 9..<11 strikethroughMarker
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
        reason: "A tab before `>` hides no quote, as in the reading view and the exporter (`> >` is level 1, as in "
            + "S13).",
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
]
