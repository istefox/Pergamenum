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
    /// What `MarkdownStyler` printed on `3e5df0a6` for every input of `StylerGoldenCorpus.exportInputs`.
    static let capturedExportOutputs: [String: String] = exportCaptures
}

/// Pasted from `stylerGoldenCapture`, never typed.
private let exportCaptures: [String: String] = [
    "E01": #"""
        0..<13 tag("#project-av45")
        """#,
    "E02": #"""
        """#,
    "E03": #"""
        """#,
    "E04": #"""
        """#,
    "E05": #"""
        0..<55 tableRun
        """#,
    "E06": #"""
        0..<1 blockquoteMarker(level: 1)
        8..<10 blockquoteMarker(level: 1)
        hidden 0..<1 blockquote
        hidden 8..<10 blockquote
        """#,
    "E07": #"""
        0..<3 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        9..<12 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        hidden 0..<3 list
        hidden 9..<12 list
        """#,
    "E08": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        14..<19 taskMarker(state: TaskItem.State.done)
        26..<31 taskMarker(state: TaskItem.State.cancelled)
        42..<47 taskMarker(state: TaskItem.State.rescheduled)
        57..<59 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<5 checkbox
        hidden 14..<19 checkbox
        hidden 26..<31 checkbox
        hidden 42..<47 checkbox
        hidden 57..<59 list
        """#,
    "E09": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        hidden 0..<5 checkbox
        """#,
    "E10": #"""
        7..<10 horizontalRule
        hidden 7..<10 rule
        """#,
    "E11": #"""
        0..<5 horizontalRule
        hidden 0..<5 rule
        """#,
    "E12": #"""
        0..<13 embedRun
        0..<13 linkSyntax
        3..<11 embedTarget("foto.png")
        hidden 0..<13 embed
        hidden 0..<13 link
        order 0..<13 embedRun < 0..<13 linkSyntax
        order 0..<13 embedRun < 3..<11 embedTarget("foto.png")
        order 0..<13 linkSyntax < 3..<11 embedTarget("foto.png")
        """#,
    "E13": #"""
        0..<17 embedRun
        0..<17 linkSyntax
        3..<11 embedTarget("foto.png")
        hidden 0..<17 embed
        hidden 0..<17 link
        order 0..<17 embedRun < 0..<17 linkSyntax
        order 0..<17 embedRun < 3..<11 embedTarget("foto.png")
        order 0..<17 linkSyntax < 3..<11 embedTarget("foto.png")
        """#,
    "E14": #"""
        0..<23 embedRun
        hidden 0..<23 embed
        """#,
    "E15": #"""
        0..<23 linkSyntax
        3..<13 embedTarget("Altra nota")
        hidden 0..<23 link
        order 0..<23 linkSyntax < 3..<13 embedTarget("Altra nota")
        """#,
    "E16": #"""
        5..<22 linkSyntax
        8..<16 embedTarget("foto.png")
        hidden 5..<22 link
        order 5..<22 linkSyntax < 8..<16 embedTarget("foto.png")
        """#,
    "E17": #"""
        0..<23 linkSyntax
        3..<21 embedTarget("https://x.it/a.png")
        hidden 0..<23 link
        order 0..<23 linkSyntax < 3..<21 embedTarget("https://x.it/a.png")
        """#,
    "E18": #"""
        """#,
    "E19": #"""
        0..<3 codeBlock
        """#,
    "E20": #"""
        4..<11 code
        14..<21 code
        """#,
    "E21": #"""
        2..<3 emphasisMarker
        2..<7 italic
        6..<7 emphasisMarker
        hidden 2..<3 emphasis
        hidden 6..<7 emphasis
        order 2..<7 italic < 2..<3 emphasisMarker
        order 2..<7 italic < 6..<7 emphasisMarker
        """#,
    "E22": #"""
        0..<2 strikethroughMarker
        0..<7 strikethrough
        5..<7 strikethroughMarker
        hidden 0..<2 strikethrough
        hidden 5..<7 strikethrough
        order 0..<7 strikethrough < 0..<2 strikethroughMarker
        order 0..<7 strikethrough < 5..<7 strikethroughMarker
        """#,
    "E23": #"""
        0..<2 emphasisMarker
        0..<22 bold
        20..<22 emphasisMarker
        hidden 0..<2 emphasis
        hidden 20..<22 emphasis
        order 0..<22 bold < 0..<2 emphasisMarker
        order 0..<22 bold < 20..<22 emphasisMarker
        """#,
    "E24": #"""
        0..<12 linkSyntax
        2..<6 linkTarget("Nota")
        hidden 0..<12 link
        order 0..<12 linkSyntax < 2..<6 linkTarget("Nota")
        """#,
    "E25": #"""
        4..<10 italic
        17..<26 bold
        29..<36 italic
        """#,
    "E26": #"""
        0..<1 linkSyntax
        1..<3 emphasisMarker
        1..<10 bold
        1..<10 linkTarget("https://x.it")
        8..<10 emphasisMarker
        10..<25 linkSyntax
        hidden 0..<1 link
        hidden 1..<3 emphasis
        hidden 8..<10 emphasis
        hidden 10..<25 link
        order 1..<10 bold < 1..<3 emphasisMarker
        order 1..<10 bold < 8..<10 emphasisMarker
        order 1..<10 bold < 1..<10 linkTarget("https://x.it")
        order 1..<3 emphasisMarker < 1..<10 linkTarget("https://x.it")
        order 8..<10 emphasisMarker < 1..<10 linkTarget("https://x.it")
        """#,
    "E27": #"""
        0..<1 linkSyntax
        1..<8 linkTarget("https://x.it")
        3..<5 emphasisMarker
        3..<8 bold
        6..<8 emphasisMarker
        8..<23 linkSyntax
        hidden 0..<1 link
        hidden 3..<5 emphasis
        hidden 6..<8 emphasis
        hidden 8..<23 link
        order 3..<8 bold < 3..<5 emphasisMarker
        order 3..<8 bold < 6..<8 emphasisMarker
        order 3..<8 bold < 1..<8 linkTarget("https://x.it")
        order 3..<5 emphasisMarker < 1..<8 linkTarget("https://x.it")
        order 6..<8 emphasisMarker < 1..<8 linkTarget("https://x.it")
        """#,
    "E28": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        hidden 0..<5 checkbox
        """#,
    "E29": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        hidden 0..<5 checkbox
        """#,
    "E30": #"""
        0..<16 linkSyntax
        2..<6 linkTarget("Nota")
        19..<44 linkSyntax
        21..<25 linkTarget("Nota")
        hidden 0..<16 link
        hidden 19..<44 link
        order 0..<16 linkSyntax < 2..<6 linkTarget("Nota")
        order 19..<44 linkSyntax < 21..<25 linkTarget("Nota")
        """#,
    "E31": #"""
        0..<9 linkSyntax
        2..<6 linkTarget("Nota")
        hidden 0..<9 link
        order 0..<9 linkSyntax < 2..<6 linkTarget("Nota")
        """#,
    "E32": #"""
        """#,
    "E33": #"""
        0..<1 linkSyntax
        1..<2 linkTarget("javascript:alert(1")
        2..<23 linkSyntax
        hidden 0..<1 link
        hidden 2..<23 link
        """#,
    "E34": #"""
        0..<1 linkSyntax
        1..<2 linkTarget("https://x\"><img src=y")
        2..<26 linkSyntax
        hidden 0..<1 link
        hidden 2..<26 link
        """#,
    "E35": #"""
        0..<15 linkSyntax
        2..<13 linkTarget("Nota d\'Arco")
        hidden 0..<15 link
        order 0..<15 linkSyntax < 2..<13 linkTarget("Nota d\'Arco")
        """#,
    "E36": #"""
        """#,
    "E37": #"""
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        hidden 0..<2 list
        """#,
    "E38": #"""
        """#,
    "E39": #"""
        0..<3 headingMarker
        0..<34 heading(level: 2)
        14..<16 emphasisMarker
        14..<23 bold
        21..<23 emphasisMarker
        26..<34 linkSyntax
        28..<32 linkTarget("Nota")
        hidden 0..<3 heading
        hidden 14..<16 emphasis
        hidden 21..<23 emphasis
        hidden 26..<34 link
        order 0..<34 heading(level: 2) < 0..<3 headingMarker
        order 0..<34 heading(level: 2) < 14..<23 bold
        order 0..<34 heading(level: 2) < 14..<16 emphasisMarker
        order 0..<34 heading(level: 2) < 21..<23 emphasisMarker
        order 0..<34 heading(level: 2) < 26..<34 linkSyntax
        order 0..<34 heading(level: 2) < 28..<32 linkTarget("Nota")
        order 14..<23 bold < 14..<16 emphasisMarker
        order 14..<23 bold < 21..<23 emphasisMarker
        order 26..<34 linkSyntax < 28..<32 linkTarget("Nota")
        """#,
    "E40": #"""
        """#,
    "E41": #"""
        """#,
    "E42": #"""
        0..<1 emphasisMarker
        0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1)
        0..<3 italic
        2..<3 emphasisMarker
        3..<4 emphasisMarker
        3..<14 italic
        13..<14 emphasisMarker
        hidden 0..<1 emphasis
        hidden 0..<2 list
        hidden 2..<3 emphasis
        hidden 3..<4 emphasis
        hidden 13..<14 emphasis
        order 0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1) < 0..<3 italic
        order 0..<2 listMarker(kind: MarkdownStyler.Span.ListKind.bullet, level: 1) < 0..<1 emphasisMarker
        order 0..<3 italic < 0..<1 emphasisMarker
        order 0..<3 italic < 2..<3 emphasisMarker
        order 3..<14 italic < 3..<4 emphasisMarker
        order 3..<14 italic < 13..<14 emphasisMarker
        """#,
    "E43": #"""
        0..<2 headingMarker
        0..<3 heading(level: 1)
        hidden 0..<2 heading
        order 0..<3 heading(level: 1) < 0..<2 headingMarker
        """#,
    "E44": #"""
        2..<7 taskMarker(state: TaskItem.State.open)
        hidden 2..<7 checkbox
        """#,
    "E45": #"""
        0..<3 listMarker(kind: MarkdownStyler.Span.ListKind.ordered, level: 1)
        hidden 0..<3 list
        """#,
    "E46": #"""
        0..<11 scheduled
        """#,
    "E47": #"""
        0..<2 blockquoteMarker(level: 1)
        hidden 0..<2 blockquote
        """#,
    "E48": #"""
        0..<1 emphasisMarker
        0..<14 italic
        13..<14 emphasisMarker
        14..<15 emphasisMarker
        14..<21 italic
        20..<21 emphasisMarker
        21..<22 emphasisMarker
        21..<30 italic
        29..<30 emphasisMarker
        hidden 0..<1 emphasis
        hidden 13..<14 emphasis
        hidden 14..<15 emphasis
        hidden 20..<21 emphasis
        hidden 21..<22 emphasis
        hidden 29..<30 emphasis
        order 0..<14 italic < 0..<1 emphasisMarker
        order 0..<14 italic < 13..<14 emphasisMarker
        order 14..<21 italic < 14..<15 emphasisMarker
        order 14..<21 italic < 20..<21 emphasisMarker
        order 21..<30 italic < 21..<22 emphasisMarker
        order 21..<30 italic < 29..<30 emphasisMarker
        """#,
    "X01": #"""
        0..<2 headingMarker
        0..<19 heading(level: 1)
        hidden 0..<2 heading
        order 0..<19 heading(level: 1) < 0..<2 headingMarker
        """#,
    "X02": #"""
        0..<19 code
        """#,
    "X03": #"""
        0..<1 linkSyntax
        1..<16 linkTarget("https://x.it/?a=1&b=\"2\"&c=\'3\'<4>")
        16..<51 linkSyntax
        hidden 0..<1 link
        hidden 16..<51 link
        """#,
    "X04": #"""
        0..<22 linkSyntax
        2..<20 linkTarget("Nota & <A> \"B\" \'C\'")
        hidden 0..<22 link
        order 0..<22 linkSyntax < 2..<20 linkTarget("Nota & <A> \"B\" \'C\'")
        """#,
    "X05": #"""
        0..<27 embedRun
        0..<27 linkSyntax
        3..<25 embedTarget("foto & <a> \"b\" \'c\'.png")
        hidden 0..<27 embed
        hidden 0..<27 link
        order 0..<27 embedRun < 0..<27 linkSyntax
        order 0..<27 embedRun < 3..<25 embedTarget("foto & <a> \"b\" \'c\'.png")
        order 0..<27 linkSyntax < 3..<25 embedTarget("foto & <a> \"b\" \'c\'.png")
        """#,
    "X06": #"""
        0..<39 tableRun
        """#,
    "X07": #"""
        0..<25 codeBlock
        """#,
    "X08": #"""
        0..<5 taskMarker(state: TaskItem.State.open)
        hidden 0..<5 checkbox
        """#,
    "X09": #"""
        """#,
    "W01": #"""
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
        254..<269 code
        hidden 76..<78 heading
        hidden 116..<118 emphasis
        hidden 123..<125 emphasis
        hidden 154..<155 emphasis
        hidden 161..<162 emphasis
        hidden 165..<168 heading
        hidden 184..<186 list
        hidden 186..<200 link
        hidden 232..<235 heading
        order 76..<102 heading(level: 1) < 76..<78 headingMarker
        order 116..<125 bold < 116..<118 emphasisMarker
        order 116..<125 bold < 123..<125 emphasisMarker
        order 154..<162 italic < 154..<155 emphasisMarker
        order 154..<162 italic < 161..<162 emphasisMarker
        order 165..<182 heading(level: 2) < 165..<168 headingMarker
        order 232..<241 heading(level: 2) < 232..<235 headingMarker
        order 186..<200 linkSyntax < 188..<198 linkTarget("Altra nota")
        """#,
    "W02": #"""
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
        299..<328 codeBlock
        308..<311 codeToken(CodeSyntax.Token.keyword)
        321..<324 codeToken(CodeSyntax.Token.number)
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
        hidden 399..<402 rule
        hidden 459..<476 embed
        hidden 459..<476 link
        hidden 478..<501 link
        order 299..<328 codeBlock < 308..<311 codeToken(CodeSyntax.Token.keyword)
        order 299..<328 codeBlock < 321..<324 codeToken(CodeSyntax.Token.number)
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
        """#,
]
