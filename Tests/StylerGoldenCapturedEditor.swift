import Foundation

// ADR-0082 §D3, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385, R-18).
//
// Part of the corpus `StylerGoldenCorpus.swift` declares, split out of it for `file_length`
// (`NoteExportGoldenCorpus.swift`'s shape). **Captured, never written by hand:** every string
// below was printed by `stylerGoldenCapture` (`StylerGoldenTests.swift`) running `MarkdownStyler`
// as it stood on `3e5df0a6`, and pasted unchanged. The helper prints one list; its `E`, `X` and
// `W` entries go in `StylerGoldenCapturedExport.swift`, its `S` entries in
// `StylerGoldenCapturedEditor.swift`. A captured string is never edited (header of
// `StylerGoldenCorpus.swift`).

extension StylerGoldenCorpus {
    /// What `MarkdownStyler` printed on `3e5df0a6` for every input of `StylerGoldenCorpus.editorInputs`.
    static let capturedEditorOutputs: [String: String] = editorCaptures
}

/// Pasted from `stylerGoldenCapture`, never typed.
private let editorCaptures: [String: String] = [
    "S01": #"""
        9..<22 tag("#project-av45")
        27..<40 tag("#topic-fisica")
        """#,
    "S02": #"""
        8..<19 scheduled
        28..<39 due
        """#,
    "S03": #"""
        7..<24 annotation
        27..<52 annotation
        55..<66 annotation
        """#,
    "S04": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        13..<18 taskMarker(state: TaskItem.State.done)
        25..<30 taskMarker(state: TaskItem.State.cancelled)
        41..<46 taskMarker(state: TaskItem.State.rescheduled)
        hidden 0..<5 checkbox
        hidden 13..<18 checkbox
        hidden 25..<30 checkbox
        hidden 41..<46 checkbox
        """#,
    "S05": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        15..<26 scheduled
        33..<46 tag("#project-av45")
        49..<60 due
        hidden 0..<5 checkbox
        """#,
    "S06": #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        8..<10 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 2)
        18..<20 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 3)
        30..<32 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 4)
        hidden 0..<2 list
        hidden 8..<10 list
        hidden 18..<20 list
        hidden 30..<32 list
        """#,
    "S07": #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        9..<11 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        15..<17 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<2 list
        hidden 9..<11 list
        hidden 15..<17 list
        """#,
    "S08": #"""
        0..<3 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        10..<13 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 2)
        22..<25 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        29..<33 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        hidden 0..<3 list
        hidden 10..<13 list
        hidden 22..<25 list
        hidden 29..<33 list
        """#,
    "S09": #"""
        0..<3 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        7..<10 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        14..<18 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        hidden 0..<3 list
        hidden 7..<10 list
        hidden 14..<18 list
        """#,
    "S10": #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        7..<9 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 2)
        15..<17 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 3)
        28..<30 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 3)
        hidden 0..<2 list
        hidden 7..<9 list
        hidden 15..<17 list
        hidden 28..<30 list
        """#,
    "S11": #"""
        """#,
    "S12": #"""
        0..<4 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        12..<17 taskMarker(state: TaskItem.State.open)
        hidden 0..<4 list
        hidden 12..<17 checkbox
        """#,
    "S13": #"""
        0..<2 blockquoteMarker(level: 1)
        6..<8 blockquoteMarker(level: 1)
        14..<16 blockquoteMarker(level: 1)
        hidden 0..<2 blockquote
        hidden 6..<8 blockquote
        hidden 14..<16 blockquote
        """#,
    "S14": #"""
        0..<1 blockquoteMarker(level: 1)
        14..<16 blockquoteMarker(level: 2)
        hidden 0..<1 blockquote
        hidden 14..<16 blockquote
        """#,
    "S15": #"""
        """#,
    "S16": #"""
        0..<2 headingMarker
        0..<8 heading(level: 1)
        9..<12 headingMarker
        9..<23 heading(level: 2)
        24..<28 headingMarker
        24..<33 heading(level: 3)
        34..<39 headingMarker
        34..<45 heading(level: 4)
        46..<52 headingMarker
        46..<58 heading(level: 5)
        59..<66 headingMarker
        59..<71 heading(level: 6)
        hidden 0..<2 heading
        hidden 9..<12 heading
        hidden 24..<28 heading
        hidden 34..<39 heading
        hidden 46..<52 heading
        hidden 59..<66 heading
        order 0..<8 heading(level: 1) < 0..<2 headingMarker
        order 9..<23 heading(level: 2) < 9..<12 headingMarker
        order 24..<33 heading(level: 3) < 24..<28 headingMarker
        order 34..<45 heading(level: 4) < 34..<39 headingMarker
        order 46..<58 heading(level: 5) < 46..<52 headingMarker
        order 59..<71 heading(level: 6) < 59..<66 headingMarker
        """#,
    "S17": #"""
        29..<31 headingMarker
        29..<42 heading(level: 1)
        hidden 29..<31 heading
        order 29..<42 heading(level: 1) < 29..<31 headingMarker
        """#,
    "S18": #"""
        7..<10 horizontalRule
        19..<22 horizontalRule
        24..<27 horizontalRule
        29..<34 horizontalRule
        hidden 7..<10 rule
        hidden 19..<22 rule
        hidden 24..<27 rule
        hidden 29..<34 rule
        """#,
    "S19": #"""
        0..<36 codeBlock
        """#,
    "S20": #"""
        0..<46 codeBlock
        9..<12 codeToken(CodeSyntax.Token.keyword)
        17..<18 codeToken(CodeSyntax.Token.number)
        19..<30 codeToken(CodeSyntax.Token.comment)
        31..<35 codeToken(CodeSyntax.Token.keyword)
        order 0..<46 codeBlock < 9..<12 codeToken(CodeSyntax.Token.keyword)
        order 0..<46 codeBlock < 17..<18 codeToken(CodeSyntax.Token.number)
        order 0..<46 codeBlock < 19..<30 codeToken(CodeSyntax.Token.comment)
        order 0..<46 codeBlock < 31..<35 codeToken(CodeSyntax.Token.keyword)
        """#,
    "S21": #"""
        0..<67 codeBlock
        0..<67 viewBlockRun
        order 0..<67 codeBlock < 0..<67 viewBlockRun
        """#,
    "S22": #"""
        0..<35 codeBlock
        """#,
    "S23": #"""
        0..<29 tableRun
        """#,
    "S24": #"""
        0..<44 frontmatter
        46..<48 headingMarker
        46..<54 heading(level: 1)
        hidden 46..<48 heading
        order 46..<54 heading(level: 1) < 46..<48 headingMarker
        """#,
    "S25": #"""
        0..<9 frontmatter
        """#,
    "S26": #"""
        0..<46 messageAnchor
        hidden 0..<46 messageAnchor
        """#,
    "S27": #"""
        0..<13 linkSyntax
        3..<11 embedTarget("foto.png")
        16..<33 linkSyntax
        19..<27 embedTarget("foto.png")
        36..<57 linkSyntax
        39..<47 embedTarget("foto.png")
        hidden 0..<13 link
        hidden 16..<33 link
        hidden 36..<57 link
        order 0..<13 linkSyntax < 3..<11 embedTarget("foto.png")
        order 16..<33 linkSyntax < 19..<27 embedTarget("foto.png")
        order 36..<57 linkSyntax < 39..<47 embedTarget("foto.png")
        """#,
    "S28": #"""
        0..<13 embedRun
        0..<13 linkSyntax
        3..<11 embedTarget("foto.png")
        15..<30 linkSyntax
        18..<28 embedTarget("Altra nota")
        32..<48 embedRun
        hidden 0..<13 embed
        hidden 0..<13 link
        hidden 15..<30 link
        hidden 32..<48 embed
        order 0..<13 embedRun < 0..<13 linkSyntax
        order 0..<13 embedRun < 3..<11 embedTarget("foto.png")
        order 0..<13 linkSyntax < 3..<11 embedTarget("foto.png")
        order 15..<30 linkSyntax < 18..<28 embedTarget("Altra nota")
        """#,
    "S29": #"""
        0..<8 linkSyntax
        2..<6 linkTarget("Nota")
        9..<23 linkSyntax
        11..<15 linkTarget("Nota")
        24..<40 linkSyntax
        26..<30 linkTarget("Nota")
        41..<63 linkSyntax
        43..<47 linkTarget("Nota")
        hidden 0..<8 link
        hidden 9..<23 link
        hidden 24..<40 link
        hidden 41..<63 link
        order 0..<8 linkSyntax < 2..<6 linkTarget("Nota")
        order 9..<23 linkSyntax < 11..<15 linkTarget("Nota")
        order 24..<40 linkSyntax < 26..<30 linkTarget("Nota")
        order 41..<63 linkSyntax < 43..<47 linkTarget("Nota")
        """#,
    "S30": #"""
        0..<1 linkSyntax
        1..<26 linkTarget("https://example.com/a_b_c")
        11..<12 emphasisMarker
        11..<19 italic
        18..<19 emphasisMarker
        26..<54 linkSyntax
        49..<52 italic
        hidden 0..<1 link
        hidden 11..<12 emphasis
        hidden 18..<19 emphasis
        hidden 26..<54 link
        order 11..<19 italic < 11..<12 emphasisMarker
        order 11..<19 italic < 18..<19 emphasisMarker
        order 11..<19 italic < 1..<26 linkTarget("https://example.com/a_b_c")
        order 11..<12 emphasisMarker < 1..<26 linkTarget("https://example.com/a_b_c")
        order 18..<19 emphasisMarker < 1..<26 linkTarget("https://example.com/a_b_c")
        order 49..<52 italic < 26..<54 linkSyntax
        """#,
    "S31": #"""
        0..<1 linkSyntax
        1..<3 emphasisMarker
        1..<10 bold
        1..<10 linkTarget("https://example.com")
        8..<10 emphasisMarker
        10..<32 linkSyntax
        35..<36 linkSyntax
        36..<37 linkTarget("b")
        37..<41 linkSyntax
        44..<45 linkSyntax
        50..<53 linkSyntax
        hidden 0..<1 link
        hidden 1..<3 emphasis
        hidden 8..<10 emphasis
        hidden 10..<32 link
        hidden 35..<36 link
        hidden 37..<41 link
        hidden 44..<45 link
        hidden 50..<53 link
        order 1..<10 bold < 1..<3 emphasisMarker
        order 1..<10 bold < 8..<10 emphasisMarker
        order 1..<10 bold < 1..<10 linkTarget("https://example.com")
        order 1..<3 emphasisMarker < 1..<10 linkTarget("https://example.com")
        order 8..<10 emphasisMarker < 1..<10 linkTarget("https://example.com")
        """#,
    "S32": #"""
        4..<10 italic
        """#,
    "S33": #"""
        2..<3 emphasisMarker
        2..<7 italic
        6..<7 emphasisMarker
        hidden 2..<3 emphasis
        hidden 6..<7 emphasis
        order 2..<7 italic < 2..<3 emphasisMarker
        order 2..<7 italic < 6..<7 emphasisMarker
        """#,
    "S34": #"""
        4..<10 italic
        22..<28 italic
        """#,
    "S35": #"""
        0..<9 italic
        12..<21 bold
        24..<25 emphasisMarker
        24..<33 italic
        32..<33 emphasisMarker
        36..<38 emphasisMarker
        36..<45 bold
        43..<45 emphasisMarker
        48..<50 emphasisMarker
        48..<61 bold
        59..<61 emphasisMarker
        hidden 24..<25 emphasis
        hidden 32..<33 emphasis
        hidden 36..<38 emphasis
        hidden 43..<45 emphasis
        hidden 48..<50 emphasis
        hidden 59..<61 emphasis
        order 24..<33 italic < 24..<25 emphasisMarker
        order 24..<33 italic < 32..<33 emphasisMarker
        order 36..<45 bold < 36..<38 emphasisMarker
        order 36..<45 bold < 43..<45 emphasisMarker
        order 48..<61 bold < 48..<50 emphasisMarker
        order 48..<61 bold < 59..<61 emphasisMarker
        """#,
    "S36": #"""
        0..<2 emphasisMarker
        0..<30 bold
        12..<13 emphasisMarker
        12..<21 italic
        20..<21 emphasisMarker
        28..<30 emphasisMarker
        33..<34 emphasisMarker
        33..<47 italic
        46..<47 emphasisMarker
        47..<48 emphasisMarker
        47..<54 italic
        53..<54 emphasisMarker
        54..<55 emphasisMarker
        54..<63 italic
        62..<63 emphasisMarker
        hidden 0..<2 emphasis
        hidden 12..<13 emphasis
        hidden 20..<21 emphasis
        hidden 28..<30 emphasis
        hidden 33..<34 emphasis
        hidden 46..<47 emphasis
        hidden 47..<48 emphasis
        hidden 53..<54 emphasis
        hidden 54..<55 emphasis
        hidden 62..<63 emphasis
        order 0..<30 bold < 0..<2 emphasisMarker
        order 0..<30 bold < 28..<30 emphasisMarker
        order 0..<30 bold < 12..<21 italic
        order 0..<30 bold < 12..<13 emphasisMarker
        order 0..<30 bold < 20..<21 emphasisMarker
        order 12..<21 italic < 12..<13 emphasisMarker
        order 12..<21 italic < 20..<21 emphasisMarker
        order 33..<47 italic < 33..<34 emphasisMarker
        order 33..<47 italic < 46..<47 emphasisMarker
        order 47..<54 italic < 47..<48 emphasisMarker
        order 47..<54 italic < 53..<54 emphasisMarker
        order 54..<63 italic < 54..<55 emphasisMarker
        order 54..<63 italic < 62..<63 emphasisMarker
        """#,
    "S37": #"""
        1..<2 emphasisMarker
        1..<16 italic
        15..<16 emphasisMarker
        hidden 1..<2 emphasis
        hidden 15..<16 emphasis
        order 1..<16 italic < 1..<2 emphasisMarker
        order 1..<16 italic < 15..<16 emphasisMarker
        """#,
    "S38": #"""
        0..<2 strikethroughMarker
        0..<11 strikethrough
        9..<11 strikethroughMarker
        14..<16 strikethroughMarker
        14..<31 strikethrough
        29..<31 strikethroughMarker
        34..<42 code
        45..<47 code
        54..<61 code
        hidden 0..<2 strikethrough
        hidden 9..<11 strikethrough
        hidden 14..<16 strikethrough
        hidden 29..<31 strikethrough
        order 0..<11 strikethrough < 0..<2 strikethroughMarker
        order 0..<11 strikethrough < 9..<11 strikethroughMarker
        order 14..<31 strikethrough < 14..<16 strikethroughMarker
        order 14..<31 strikethrough < 29..<31 strikethroughMarker
        """#,
    "S39": #"""
        0..<15 code
        18..<20 emphasisMarker
        18..<43 bold
        20..<41 code
        41..<43 emphasisMarker
        46..<58 linkSyntax
        48..<50 emphasisMarker
        48..<56 bold
        48..<56 linkTarget("nota")
        54..<56 emphasisMarker
        hidden 18..<20 emphasis
        hidden 41..<43 emphasis
        hidden 46..<58 link
        hidden 48..<50 emphasis
        hidden 54..<56 emphasis
        order 18..<43 bold < 18..<20 emphasisMarker
        order 18..<43 bold < 41..<43 emphasisMarker
        order 18..<43 bold < 20..<41 code
        order 48..<56 bold < 48..<50 emphasisMarker
        order 48..<56 bold < 54..<56 emphasisMarker
        order 48..<56 bold < 46..<58 linkSyntax
        order 48..<56 bold < 48..<56 linkTarget("nota")
        order 48..<50 emphasisMarker < 46..<58 linkSyntax
        order 48..<50 emphasisMarker < 48..<56 linkTarget("nota")
        order 54..<56 emphasisMarker < 46..<58 linkSyntax
        order 54..<56 emphasisMarker < 48..<56 linkTarget("nota")
        order 46..<58 linkSyntax < 48..<56 linkTarget("nota")
        """#,
    "S40": #"""
        0..<11 scheduled
        """#,
    "S41": #"""
        0..<2 blockquoteMarker(level: 1)
        hidden 0..<2 blockquote
        """#,
    "S42": #"""
        0..<1 blockquoteMarker(level: 1)
        hidden 0..<1 blockquote
        """#,
    "S43": #"""
        0..<2 blockquoteMarker(level: 1)
        12..<23 scheduled
        hidden 0..<2 blockquote
        """#,
    "S44": #"""
        0..<2 headingMarker
        0..<8 heading(level: 1)
        12..<14 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        19..<24 taskMarker(state: TaskItem.State.open)
        32..<34 blockquoteMarker(level: 1)
        hidden 0..<2 heading
        hidden 12..<14 list
        hidden 19..<24 checkbox
        hidden 32..<34 blockquote
        order 0..<8 heading(level: 1) < 0..<2 headingMarker
        """#,
    "S45": #"""
        """#,
    "S46": #"""
        0..<26 frontmatter
        """#,
    "S47": #"""
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
        121..<129 code
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
        271..<300 codeBlock
        280..<283 codeToken(CodeSyntax.Token.keyword)
        293..<296 codeToken(CodeSyntax.Token.number)
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
        hidden 132..<133 link
        hidden 137..<152 link
        hidden 155..<160 checkbox
        hidden 216..<218 list
        hidden 230..<233 list
        hidden 237..<240 list
        hidden 245..<247 blockquote
        hidden 261..<262 emphasis
        hidden 268..<269 emphasis
        hidden 333..<350 embed
        hidden 333..<350 link
        order 271..<300 codeBlock < 280..<283 codeToken(CodeSyntax.Token.keyword)
        order 271..<300 codeBlock < 293..<296 codeToken(CodeSyntax.Token.number)
        order 46..<74 heading(level: 1) < 46..<48 headingMarker
        order 46..<74 heading(level: 1) < 59..<67 linkSyntax
        order 46..<74 heading(level: 1) < 61..<65 linkTarget("Nota")
        order 86..<95 bold < 86..<88 emphasisMarker
        order 86..<95 bold < 93..<95 emphasisMarker
        order 97..<106 italic < 97..<98 emphasisMarker
        order 97..<106 italic < 105..<106 emphasisMarker
        order 108..<119 strikethrough < 108..<110 strikethroughMarker
        order 108..<119 strikethrough < 117..<119 strikethroughMarker
        order 261..<269 italic < 261..<262 emphasisMarker
        order 261..<269 italic < 268..<269 emphasisMarker
        order 333..<350 embedRun < 333..<350 linkSyntax
        order 333..<350 embedRun < 336..<344 embedTarget("foto.png")
        order 59..<67 linkSyntax < 61..<65 linkTarget("Nota")
        order 333..<350 linkSyntax < 336..<344 embedTarget("foto.png")
        """#,
    "S48": #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        16..<18 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 2)
        hidden 0..<2 list
        hidden 16..<18 list
        """#,
    "S49": #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        17..<19 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<2 list
        hidden 17..<19 list
        """#,
    "S50": #"""
        """#,
    "S51": #"""
        """#,
    "S52": #"""
        """#,
    "S53": #"""
        """#,
    "S54": #"""
        """#,
    "S55": #"""
        2..<4 emphasisMarker
        2..<9 bold
        7..<9 emphasisMarker
        12..<17 code
        20..<21 linkSyntax
        21..<24 linkTarget("u")
        24..<28 linkSyntax
        hidden 2..<4 emphasis
        hidden 7..<9 emphasis
        hidden 20..<21 link
        hidden 24..<28 link
        order 2..<9 bold < 2..<4 emphasisMarker
        order 2..<9 bold < 7..<9 emphasisMarker
        """#,
    "S56": #"""
        20..<31 scheduled
        """#,
    "S57": #"""
        0..<2 headingMarker
        0..<16 heading(level: 1)
        25..<27 blockquoteMarker(level: 1)
        hidden 0..<2 heading
        hidden 25..<27 blockquote
        order 0..<16 heading(level: 1) < 0..<2 headingMarker
        """#,
    "S58": #"""
        2..<4 emphasisMarker
        2..<9 bold
        7..<9 emphasisMarker
        hidden 2..<4 emphasis
        hidden 7..<9 emphasis
        order 2..<9 bold < 2..<4 emphasisMarker
        order 2..<9 bold < 7..<9 emphasisMarker
        """#,
    "S59": #"""
        0..<15 tableRun
        6..<9 horizontalRule
        hidden 6..<9 rule
        order 6..<9 horizontalRule < 0..<15 tableRun
        """#,
    "S60": #"""
        1..<3 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        8..<10 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 1..<3 list
        hidden 8..<10 list
        """#,
]
