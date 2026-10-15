import Foundation

// ADR-0087 §D12, plan docs/plans/note-workflow-n5.md, Task 1 (R-43).
//
// The export corpus's N5 cases, beside `NoteExportGoldenCorpus.swift` for `file_length`
// (`FormatEdgeCorpus.swift`'s shape). N01 onward pin every construct of R-36 to R-42 that the
// export has an opinion on: the highlight, the nested quote, the callout, the transclusion's
// caption. The last two cases are marked `.unchanged` on purpose: they pin that chips and fence
// chrome are interaction and are not exported (§D12). E05 (alignment) and E16 (an inline embed)
// already pin the other two, and are cited, not duplicated.
//
// These bytes are written from ADR-0087 §D12 and the plan's Task 1 text, not captured from the
// exporter: the exporter does not produce them yet. Class `.a` here means "today's exporter is
// wrong about this construct".

/// Cases N01 onward, rendered through `MarkdownHTML.render(_:)` like the rest of the corpus.
let constructCorpus: [ExportGoldenCase] = [
    ExportGoldenCase(
        "N01", "a ==b== c",
        .a, "`==` highlights: `<mark>` (§D12)",
        #"<p>a <mark>b</mark> c</p>"#
    ),
    ExportGoldenCase(
        "N02", "==**x**==",
        .a, "the wrap order is code, mark, del, em, strong, so strong wraps mark (§D12)",
        #"<p><strong><mark>x</mark></strong></p>"#
    ),
    ExportGoldenCase(
        "N03", "`a==b==`",
        .unchanged, "`==` inside a code span is code, not a highlight (the SPEC's edge case)",
        #"<p><code>a==b==</code></p>"#
    ),
    ExportGoldenCase(
        "N04", "a == b",
        .unchanged, "a `==` followed by a space opens nothing",
        #"<p>a == b</p>"#
    ),
    ExportGoldenCase(
        "N05", "> a\n>> b\n> c",
        .a, "a nested quote exports as a nested blockquote, opened inline with no line breaks (§D12)",
        #"<blockquote><p>a</p><blockquote><p>b</p></blockquote><p>c</p></blockquote>"#
    ),
    ExportGoldenCase(
        "N06", "> [!warning] Forno\n> Corpo",
        .a, "a callout is an aside with a bold title and its body (§D12)",
        #"""
        <aside class="callout-warning">
        <p><strong>Forno</strong></p>
        <p>Corpo</p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N07", "> [!note]",
        .a, "no title: the Italian label is the title, and an empty body adds nothing",
        #"""
        <aside class="callout-note">
        <p><strong>Nota</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N08", "> [!tip]",
        .a, "no title: the Italian label is the title",
        #"""
        <aside class="callout-tip">
        <p><strong>Suggerimento</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N09", "> [!important]",
        .a, "no title: the Italian label is the title",
        #"""
        <aside class="callout-important">
        <p><strong>Importante</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N10", "> [!warning]",
        .a, "no title: the Italian label is the title",
        #"""
        <aside class="callout-warning">
        <p><strong>Avviso</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N11", "> [!caution]",
        .a, "no title: the Italian label is the title",
        #"""
        <aside class="callout-caution">
        <p><strong>Attenzione</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N12", "> [!avviso]",
        .a, "an Italian alias reads as its English kind: class callout-warning, label «Avviso» (§D3)",
        #"""
        <aside class="callout-warning">
        <p><strong>Avviso</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N13", "> [!NOTE]",
        .a, "the keyword is read case-insensitively (§D3)",
        #"""
        <aside class="callout-note">
        <p><strong>Nota</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N14", "> [!faq] Domande",
        .a, "an unknown type exports as callout-other, with its written title (§D12)",
        #"""
        <aside class="callout-other">
        <p><strong>Domande</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N15", "> [!tip]- Chiuso\n> Corpo",
        .a, "a folded callout exports open, with its body (§D12)",
        #"""
        <aside class="callout-tip">
        <p><strong>Chiuso</strong></p>
        <p>Corpo</p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N16", "> [!note] <&\"'",
        .a, "a callout title is escaped once, at emission (ADR-0077 §D2)",
        #"""
        <aside class="callout-note">
        <p><strong>&lt;&amp;&quot;&apos;</strong></p>
        </aside>
        """#
    ),
    ExportGoldenCase(
        "N17", "![[Altra nota]]",
        .a, "a transclusion with no section exports its caption (§D12)",
        #"<p>da «Altra nota»</p>"#
    ),
    ExportGoldenCase(
        "N23", "![[Cartella/Altra nota#Sezione]]",
        .a, "a transclusion's caption names the note, as the editor's does, not the path it was written with (R-43)",
        #"<p>da «Altra nota» › Sezione</p>"#
    ),
    ExportGoldenCase(
        "N18", "#client-acme >2026-10-14",
        .unchanged, "a tag and a scheduling date are chips in the editor and plain text in the export",
        #"<p>#client-acme &gt;2026-10-14</p>"#
    ),
    ExportGoldenCase(
        "N19", "```swift\nlet a = 1\n```",
        .unchanged, "a fence's header and language badge are interaction: it exports as its text, no language",
        #"<pre><code>let a = 1</code></pre>"#
    ),
    ExportGoldenCase(
        "N20", "====",
        .unchanged, "a line of `=` (a setext underline) is no highlight: `==` opens nothing before another `=`",
        #"<p>====</p>"#
    ),
    ExportGoldenCase(
        "N21", "=====",
        .unchanged, "a line of `=` (a setext underline) is no highlight: `==` opens nothing before another `=`",
        #"<p>=====</p>"#
    ),
    ExportGoldenCase(
        "N22", "======",
        .unchanged, "a line of `=` (a setext underline) is no highlight: `==` opens nothing before another `=`",
        #"<p>======</p>"#
    ),
]
