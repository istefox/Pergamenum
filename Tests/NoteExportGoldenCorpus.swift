import Foundation

// ADR-0077 §D7, plan docs/plans/pg-147-core-app-shell-structure.md, Task 1 (PG-147,
// structure-NoteExport.swift-c0f).
//
// The corpus `NoteExportGoldenTests.swift` pins, beside it rather than in it for `file_length`
// (`FormatEdgeCorpus.swift`'s shape). E01 to E45 are the inputs of the plan's decision table,
// verbatim; X01 to X08 put `&`, `<`, `>`, `"` and `'` everywhere a note can hold text, and X09
// writes the entities themselves out, which must come back escaped once, not left alone.
//
// Task 1 captured every expected string by running `MarkdownHTML` as it stood on `1535c2d9`,
// never by hand. Task 3 moved the exporter onto the shared parsers and changed only the class-A
// expectations, each re-captured from the new renderer and checked against ADR-0077 and the
// plan's decision table; B, C and unchanged cases keep Task 1's bytes. An old/new difference
// without a class is a finding, not an expectation to update (§D7).

struct ExportGoldenCase: Sendable, CustomStringConvertible {
    /// How the case's expectation moved when the exporter moved onto the parsers (ADR-0077 §D7).
    enum Kind: Sendable {
        /// The old exporter was wrong; the expectation changed.
        case a
        /// The parser was wrong and §D5 fixed it; the old bytes stand.
        case b
        /// The parsed value differs from what the export shows, and a §D3 or §D6 presentation
        /// rule keeps the old bytes.
        case c
        /// Both grammars already agreed.
        case unchanged
    }

    let name: String
    let markdown: String
    /// Nil for a body case; the page's title for a whole-page case.
    let title: String?
    let kind: Kind
    let reason: String
    let expected: String
    var description: String { name }

    init(
        _ name: String, _ markdown: String, title: String? = nil,
        _ kind: Kind, _ reason: String, _ expected: String
    ) {
        self.name = name
        self.markdown = markdown
        self.title = title
        self.kind = kind
        self.reason = reason
        self.expected = expected
    }
}

enum NoteExportGoldenCorpus {
    /// Rendered through `MarkdownHTML.render(_:)`.
    static let bodies = decisionTable + escapeCorpus
}

/// E01 to E45, outside the enum's body for `type_body_length`.
private let decisionTable: [ExportGoldenCase] = [
    ExportGoldenCase(
        "E01", "#project-av45 in corso\n\nTesto.",
        .a, "a tag at the start of a line is not a heading",
        #"<p>#project-av45 in corso</p>\#n<p>Testo.</p>"#
    ),
    ExportGoldenCase(
        "E02", "#Titolo",
        .a, "a hash with no space after it is a tag, not a heading",
        #"<p>#Titolo</p>"#
    ),
    ExportGoldenCase(
        "E03", "####### troppo",
        .a, "seven hashes are not a heading",
        #"<p>####### troppo</p>"#
    ),
    ExportGoldenCase(
        "E04", "| solo | riga |\n\nTesto.",
        .a, "a table needs its delimiter row",
        #"<p>| solo | riga |</p>\#n<p>Testo.</p>"#
    ),
    ExportGoldenCase(
        "E05", "| a | b | c |\n|:--|:-:|--:|\n| 1 | 2 |\n| x | y | z | w |",
        .a, "rows fit the header's width, and the delimiter row aligns the columns",
        #"""
        <table>
        <thead><tr><th>a</th><th style="text-align: center">b</th><th style="text-align: right">c</th></tr></thead>
        <tbody><tr><td>1</td><td style="text-align: center">2</td><td style="text-align: right"></td></tr><tr>\#
        <td>x</td><td style="text-align: center">y</td><td style="text-align: right">z</td></tr></tbody>
        </table>
        """#
    ),
    ExportGoldenCase(
        "E06", ">citato\n> ancora",
        .a, "a quote needs no space after its marker",
        #"<blockquote><p>citato ancora</p></blockquote>"#
    ),
    ExportGoldenCase(
        "E07", "1) primo\n2) secondo",
        .a, "`1)` numbers a list",
        #"<ol>\#n<li>primo</li>\#n<li>secondo</li>\#n</ol>"#
    ),
    ExportGoldenCase(
        "E08", "- [ ] da fare\n- [x] fatto\n- [-] annullato\n- [>] rinviato\n- normale",
        .a, "cancelled and rescheduled tasks keep their state, and a plain bullet is its own list",
        #"""
        <ul>
        <li>☐ da fare</li>
        <li>☑ fatto</li>
        <li>⊟ annullato</li>
        <li>▷ rinviato</li>
        </ul>
        <ul>
        <li>normale</li>
        </ul>
        """#
    ),
    ExportGoldenCase(
        "E09", "- [ ]attaccato",
        .a, "the task index counts a box with no space after it, so the export does too",
        #"<ul>\#n<li>☐ attaccato</li>\#n</ul>"#
    ),
    ExportGoldenCase(
        "E10", "sopra\n\n---\n\nsotto",
        .a, "`---` between paragraphs is a rule",
        #"<p>sopra</p>\#n<hr>\#n<p>sotto</p>"#
    ),
    ExportGoldenCase(
        "E11", "* * *",
        .a, "`* * *` is a rule, not an emphasised bullet",
        #"<hr>"#
    ),
    ExportGoldenCase(
        "E12", "![[foto.png]]",
        .a, "an embed exports as its name, with no stray `!`",
        #"<p>foto.png</p>"#
    ),
    ExportGoldenCase(
        "E13", "![[foto.png|300]]",
        .a, "an embed's size suffix is never its label",
        #"<p>foto.png</p>"#
    ),
    ExportGoldenCase(
        "E14", "![didascalia](foto.png)",
        .a, "an image exports as its alt text",
        #"<p>didascalia</p>"#
    ),
    ExportGoldenCase(
        "E15", "![[Altra nota#Sezione]]",
        .a, "a transclusion exports as its reference",
        #"<p>Altra nota</p>"#
    ),
    ExportGoldenCase(
        "E16", "Vedi ![[foto.png|300]] qui.",
        .a, "an inline embed shows its name, not its size suffix",
        #"<p>Vedi foto.png qui.</p>"#
    ),
    ExportGoldenCase(
        "E17", "![[https://x.it/a.png]]",
        .a, "a remote embed shows its target, with no stray `!`",
        #"<p>https://x.it/a.png</p>"#
    ),
    ExportGoldenCase(
        "E18", "![alt](https://x.it/a.png)",
        .a, "a remote image is a link, with no stray `!`",
        #"<p><a href="https://x.it/a.png">alt</a></p>"#
    ),
    ExportGoldenCase(
        "E19", "```",
        .a, "an unclosed empty fence is an empty code block",
        #"<pre><code></code></pre>"#
    ),
    ExportGoldenCase(
        "E20", "Usa `[[x]]` e `a*b*c`.",
        .a, "nothing inside a code span is markup",
        #"<p>Usa <code>[[x]]</code> e <code>a*b*c</code>.</p>"#
    ),
    ExportGoldenCase(
        "E21", "2 * 3 * 4",
        .a, "a whitespace-flanked `*` opens nothing",
        #"<p>2 * 3 * 4</p>"#
    ),
    ExportGoldenCase(
        "E22", "~~via~~",
        .a, "`~~` strikes through",
        #"<p><del>via</del></p>"#
    ),
    ExportGoldenCase(
        "E23", "**forte con *corsivo***",
        .a, "nested emphasis comes out well-formed",
        #"<p><strong>forte con </strong><strong><em>corsivo</em></strong></p>"#
    ),
    ExportGoldenCase(
        "E24", "[[Nota|a#b]]",
        .a, "an alias is not cut at `#`",
        #"<p>a#b</p>"#
    ),
    ExportGoldenCase(
        "E25", "file_name_here e __forte__ e _lieve_",
        .a, "`__` and `_` emphasise, an intraword `_` does not (needs §D5's first correction)",
        #"<p>file_name_here e <strong>forte</strong> e <em>lieve</em></p>"#
    ),
    ExportGoldenCase(
        "E26", "[**forte**](https://x.it)",
        .b, "a styled link label, which the parser now reads (§D5)",
        #"<p><a href="https://x.it"><strong>forte</strong></a></p>"#
    ),
    ExportGoldenCase(
        "E27", "[a **b**](https://x.it)",
        .b, "a partly styled link label is one anchor (§D5)",
        #"<p><a href="https://x.it">a <strong>b</strong></a></p>"#
    ),
    ExportGoldenCase(
        "E28", "- [1] Rossi, 2020",
        .b, "`[1]` is not a task marker (§D5)",
        #"<ul>\#n<li>[1] Rossi, 2020</li>\#n</ul>"#
    ),
    ExportGoldenCase(
        "E29", "- [a] voce",
        .b, "`[a]` is not a task marker (§D5)",
        #"<ul>\#n<li>[a] voce</li>\#n</ul>"#
    ),
    ExportGoldenCase(
        "E30", "[[Nota#Sezione]] e [[Nota#Sezione|come qui]]",
        .c, "a section link shows its note's title, an alias shows itself (§D3)",
        #"<p>Nota e come qui</p>"#
    ),
    ExportGoldenCase(
        "E31", "[[Nota|]]",
        .c, "an empty alias shows the title (§D3)",
        #"<p>Nota</p>"#
    ),
    ExportGoldenCase(
        "E32", "riga uno\n  riga due\nriga tre",
        .c, "a paragraph's lines join with one space (§D6)",
        #"<p>riga uno riga due riga tre</p>"#
    ),
    ExportGoldenCase(
        "E33", "[t](javascript:alert(1))",
        .unchanged, "a refused scheme exports as its label (PG-124)",
        #"<p>t)</p>"#
    ),
    ExportGoldenCase(
        "E34", "[x](https://x\"><img src=y)",
        .unchanged, "a quote cannot leave the href (PG-124)",
        #"<p><a href="https://x&quot;&gt;&lt;img src=y">x</a></p>"#
    ),
    ExportGoldenCase(
        "E35", "[[Nota d'Arco]] l'articolo",
        .unchanged, "an apostrophe is `&apos;`",
        #"<p>Nota d&apos;Arco l&apos;articolo</p>"#
    ),
    ExportGoldenCase(
        "E36", "~~~\ncodice\n~~~",
        .unchanged, "a `~~~` fence is recognised by neither side",
        #"<p>~~~ codice ~~~</p>"#
    ),
    ExportGoldenCase(
        "E37", "- uno\ncontinua",
        .unchanged, "a line with no marker ends the list",
        #"<ul>\#n<li>uno</li>\#n</ul>\#n<p>continua</p>"#
    ),
    ExportGoldenCase(
        "E38", "Frequenza < 5 Hz & carico > 400 daN",
        .unchanged, "prose is escaped",
        #"<p>Frequenza &lt; 5 Hz &amp; carico &gt; 400 daN</p>"#
    ),
    ExportGoldenCase(
        "E39", "## Titolo con **forte** e [[Nota]]",
        .unchanged, "a heading keeps its inline markup",
        #"<h2>Titolo con <strong>forte</strong> e Nota</h2>"#
    ),
    ExportGoldenCase(
        "E40", "https://vibrofer.it e <https://x.it>",
        .unchanged, "a bare or angle-bracketed URL stays text",
        #"<p>https://vibrofer.it e &lt;https://x.it&gt;</p>"#
    ),
    ExportGoldenCase(
        "E41", "<script>alert(1)</script>",
        .unchanged, "raw HTML is escaped",
        #"<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>"#
    ),
    ExportGoldenCase(
        "E42", "* **grassetto** voce",
        .unchanged, "a `*` bullet with bold text",
        #"<ul>\#n<li><strong>grassetto</strong> voce</li>\#n</ul>"#
    ),
    ExportGoldenCase(
        "E43", "# T\r\n\r\npara\r\n",
        .unchanged, "a CRLF note carries no carriage return into the page",
        #"<h1>T</h1>\#n<p>para</p>"#
    ),
    ExportGoldenCase(
        "E44", "  - [ ] rientrato",
        .unchanged, "an indented task",
        #"<ul>\#n<li>☐ rientrato</li>\#n</ul>"#
    ),
    ExportGoldenCase(
        "E45", "1. [x] numerato",
        .unchanged, "a numbered list draws no task box",
        #"<ol>\#n<li>[x] numerato</li>\#n</ol>"#
    ),
]

/// X01 to X08: every character `NoteExport.escape` replaces, in each place a note can hold text.
/// X09: a note that writes `&amp;` or `&lt;` literally.
private let escapeCorpus: [ExportGoldenCase] = [
    ExportGoldenCase(
        "X01", "# A & B <c> \"d\" 'e'",
        .unchanged, "escaped once in a heading",
        #"<h1>A &amp; B &lt;c&gt; &quot;d&quot; &apos;e&apos;</h1>"#
    ),
    ExportGoldenCase(
        "X02", "`a & b <c> \"d\" 'e'`",
        .unchanged, "escaped once in a code span",
        #"<p><code>a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;</code></p>"#
    ),
    ExportGoldenCase(
        "X03", "[a & <b> \"c\" 'd'](https://x.it/?a=1&b=\"2\"&c='3'<4>)",
        .unchanged, "escaped once in a link's label and in its href",
        #"""
        <p><a href="https://x.it/?a=1&amp;b=&quot;2&quot;&amp;c=&apos;3&apos;&lt;4&gt;">a &amp; &lt;b&gt; &quot;c\#
        &quot; &apos;d&apos;</a></p>
        """#
    ),
    ExportGoldenCase(
        "X04", "[[Nota & <A> \"B\" 'C']]",
        .unchanged, "escaped once in a wikilink",
        #"<p>Nota &amp; &lt;A&gt; &quot;B&quot; &apos;C&apos;</p>"#
    ),
    ExportGoldenCase(
        "X05", "![[foto & <a> \"b\" 'c'.png]]",
        .a, "escaped once in an embed's name, with no stray `!`",
        #"<p>foto &amp; &lt;a&gt; &quot;b&quot; &apos;c&apos;.png</p>"#
    ),
    ExportGoldenCase(
        "X06", "| a & b | <c> |\n|---|---|\n| \"d\" | 'e' |",
        .unchanged, "escaped once in a table cell",
        #"""
        <table>
        <thead><tr><th>a &amp; b</th><th>&lt;c&gt;</th></tr></thead>
        <tbody><tr><td>&quot;d&quot;</td><td>&apos;e&apos;</td></tr></tbody>
        </table>
        """#
    ),
    ExportGoldenCase(
        "X07", "```\na & b <c> \"d\" 'e'\n```",
        .unchanged, "escaped once in a fence",
        #"<pre><code>a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;</code></pre>"#
    ),
    ExportGoldenCase(
        "X08", "- [ ] a & b <c> \"d\" 'e'",
        .unchanged, "escaped once in a task's text",
        #"<ul>\#n<li>☐ a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;</li>\#n</ul>"#
    ),
    ExportGoldenCase(
        "X09", "Scrivi &amp; per &, e &lt;b&gt; per <b>.",
        .unchanged, "an entity the note writes out is text, escaped once like the rest",
        #"<p>Scrivi &amp;amp; per &amp;, e &amp;lt;b&amp;gt; per &lt;b&gt;.</p>"#
    ),
]
