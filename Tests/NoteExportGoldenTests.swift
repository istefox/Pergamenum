import Foundation
import Testing
@testable import Pergamenum

// ADR-0077 §D2, §D4 and §D7, plan docs/plans/pg-147-core-app-shell-structure.md, Tasks 1 and 3
// (PG-147, structure-NoteExport.swift-c0f).
//
// The HTML export pinned byte for byte: the body of every case in `NoteExportGoldenCorpus`, and
// two whole pages through `NoteExport.html(from:title:)`. W01 is `NoteExportTests.swift`'s note
// (frontmatter plus a `## Note correlate` section), W02 carries one block of each kind. The
// expectations follow the corpus's rule: captured from the old exporter, changed only for class
// A. Beside them, three properties no single expected string can show: nothing is escaped twice,
// the body uses only §D4's elements and attributes, and the four task glyphs.

enum NoteExportGoldenPages {
    static let all: [ExportGoldenCase] = [
        ExportGoldenCase(
            "W01", relatedNote, title: "Curva di trasmissibilità",
            .unchanged, "the frontmatter and `## Note correlate` stay out",
            #"""
            <!DOCTYPE html>
            <html lang="it">
            <head>
            <meta charset="utf-8">
            <title>Curva di trasmissibilità</title>
            <style>
            body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 42em;
                   margin: 3em auto; padding: 0 1.5em; color: #1c1c1e; }
            h1, h2, h3 { line-height: 1.25; }
            code { font: 0.9em ui-monospace, SFMono-Regular, monospace;
                   background: #f2f2f7; padding: 0.1em 0.3em; border-radius: 3px; }
            pre { background: #f2f2f7; padding: 1em; border-radius: 6px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { margin: 0; padding-left: 1em; border-left: 3px solid #d1d1d6; color: #48484a; }
            table { border-collapse: collapse; }
            th, td { border: 1px solid #d1d1d6; padding: 0.4em 0.7em; text-align: left; }
            </style>
            </head>
            <body>
            <h1>Curva di trasmissibilità</h1>
            <p>Il supporto <strong>AV-45</strong> ha una frequenza propria di <em>4,2 Hz</em>.</p>
            <h2>Metodo</h2>
            <p>Misura con <code>accelerometro</code> triassiale.</p>
            </body>
            </html>
            """#
        ),
        ExportGoldenCase(
            "W02", kitchenSink, title: "Scheda AV-45",
            .a, "strikethrough, the four task glyphs, a rule, an aligned column, embeds as their names",
            #"""
            <!DOCTYPE html>
            <html lang="it">
            <head>
            <meta charset="utf-8">
            <title>Scheda AV-45</title>
            <style>
            body { font: 16px/1.6 -apple-system, system-ui, sans-serif; max-width: 42em;
                   margin: 3em auto; padding: 0 1.5em; color: #1c1c1e; }
            h1, h2, h3 { line-height: 1.25; }
            code { font: 0.9em ui-monospace, SFMono-Regular, monospace;
                   background: #f2f2f7; padding: 0.1em 0.3em; border-radius: 3px; }
            pre { background: #f2f2f7; padding: 1em; border-radius: 6px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { margin: 0; padding-left: 1em; border-left: 3px solid #d1d1d6; color: #48484a; }
            table { border-collapse: collapse; }
            th, td { border: 1px solid #d1d1d6; padding: 0.4em 0.7em; text-align: left; }
            </style>
            </head>
            <body>
            <h1>Scheda AV-45</h1>
            <p>Il supporto <strong>AV-45</strong> ha una frequenza di <em>4,2 Hz</em> e un <del>vecchio</del> valore.\#
            </p>
            <ul>
            <li>primo punto</li>
            <li>secondo punto</li>
            </ul>
            <ol>
            <li>passo uno</li>
            <li>passo due</li>
            </ol>
            <ul>
            <li>☐ da verificare</li>
            <li>☑ verificato</li>
            <li>⊟ annullato</li>
            <li>▷ rinviato</li>
            </ul>
            <blockquote><p>Una citazione su due righe.</p></blockquote>
            <pre><code>let carico = 450</code></pre>
            <pre><code>render: table
            where: tag(&quot;topic-produzione&quot;)</code></pre>
            <hr>
            <table>
            <thead><tr><th>Grandezza</th><th style="text-align: right">Valore</th></tr></thead>
            <tbody><tr><td>Carico</td><td style="text-align: right">450 daN</td></tr></tbody>
            </table>
            <p>foto.png</p>
            <p>Altra nota</p>
            </body>
            </html>
            """#
        ),
    ]

    static let relatedNote = """
    ---
    date: 2026-08-12
    tags:
      - type-note
    related:
      - "[[Altra nota]]"
    ---

    # Curva di trasmissibilità

    Il supporto **AV-45** ha una frequenza propria di *4,2 Hz*.

    ## Note correlate

    - [[Altra nota]] — sorgente dei dati di carico

    ## Metodo

    Misura con `accelerometro` triassiale.
    """

    static let kitchenSink = """
    ---
    date: 2026-09-30
    tags:
      - type-note
    ---

    # Scheda AV-45

    Il supporto **AV-45** ha una frequenza di *4,2 Hz* e un ~~vecchio~~ valore.

    - primo punto
    - secondo punto

    1. passo uno
    2. passo due

    - [ ] da verificare
    - [x] verificato
    - [-] annullato
    - [>] rinviato

    > Una citazione
    > su due righe.

    ```swift
    let carico = 450
    ```

    ```pergamenum-view
    render: table
    where: tag("topic-produzione")
    ```

    ---

    | Grandezza | Valore |
    |:--|--:|
    | Carico | 450 daN |

    ![[foto.png|300]]

    ![[Altra nota#Sezione]]
    """
}

@Test(arguments: NoteExportGoldenCorpus.bodies)
func exportedBodyMatchesTheGolden(_ golden: ExportGoldenCase) {
    let html = MarkdownHTML.render(golden.markdown)
    #expect(html == golden.expected, "\(golden.name): \(html.debugDescription)")
}

@Test(arguments: NoteExportGoldenPages.all)
func exportedPageMatchesTheGolden(_ golden: ExportGoldenCase) {
    let html = NoteExport.html(from: golden.markdown, title: golden.title ?? golden.name)
    #expect(html == golden.expected, "\(golden.name): \(html.debugDescription)")
}

// MARK: - Properties of the whole corpus

/// Every page the corpus exports, whole.
private var exportedPages: [String] {
    NoteExportGoldenPages.all.map { NoteExport.html(from: $0.markdown, title: $0.title ?? $0.name) }
}

/// Every body the corpus exports: a body case's output, and what a page holds inside `<body>`.
private var exportedBodies: [String] {
    NoteExportGoldenCorpus.bodies.map { MarkdownHTML.render($0.markdown) } + exportedPages.map { page in
        let start = page.range(of: "<body>\n")?.upperBound ?? page.startIndex
        let end = page.range(of: "\n</body>")?.lowerBound ?? page.endIndex
        return String(page[start..<end])
    }
}

/// Every `<` in `html`, as the tag it opens: its name and what follows the name, or nil for a
/// `<` that opens no tag.
private func tags(in html: String) -> [(name: String, attributes: String)?] {
    var result: [(name: String, attributes: String)?] = []
    var rest = html[...]
    while let open = rest.firstIndex(of: "<") {
        let after = rest[rest.index(after: open)...]
        guard let close = after.firstIndex(of: ">") else {
            result.append(nil)
            break
        }
        let inner = after[..<close]
        let body = inner.hasPrefix("/") ? inner.dropFirst() : inner
        let name = body.prefix { $0.isLetter || $0.isNumber }
        result.append(name.isEmpty ? nil : (String(name), String(body.dropFirst(name.count))))
        rest = after[after.index(after: close)...]
    }
    return result
}

/// ADR-0077 §D4's elements.
private let allowedElements: Set<String> = [
    "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "code",
    "table", "thead", "tbody", "tr", "th", "td", "hr", "strong", "em", "del", "a",
]

/// Whether a tag's attributes are the ones §D4 allows it: `href` on `a`, one of two fixed
/// alignments on `th`/`td`, nothing anywhere else, and nothing at all on a closing tag.
private func allowsAttributes(_ attributes: String, on name: String) -> Bool {
    if attributes.isEmpty { return true }
    switch name {
    case "a":
        let value = attributes.dropFirst(#" href=""#.count).dropLast()
        return attributes.hasPrefix(#" href=""#) && attributes.hasSuffix(#"""#) && !value.contains("\"")
    case "th", "td":
        return [#" style="text-align: center""#, #" style="text-align: right""#].contains(attributes)
    default:
        return false
    }
}

/// Each entity escaped twice, beside the entity a note must write out for it to be the correct
/// single escape instead (X09: `&amp;` in the note is `&amp;amp;` in the page).
private let doubleEscapes: [(doubled: String, written: String)] = [
    ("&amp;amp;", "&amp;"), ("&amp;lt;", "&lt;"), ("&amp;gt;", "&gt;"),
    ("&amp;quot;", "&quot;"), ("&amp;apos;", "&apos;"),
]

private func occurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

@Test func nothingIsEscapedTwiceAndNoBracketIsLeftOver() {
    let bodies = NoteExportGoldenCorpus.bodies.map { ($0.markdown, MarkdownHTML.render($0.markdown)) }
    let exports = bodies + zip(NoteExportGoldenPages.all.map(\.markdown), exportedPages)
    for (markdown, html) in exports {
        // A doubled entity is right only as often as the note itself wrote the entity out; any
        // more is a string that went through `NoteExport.escape` twice.
        for (doubled, written) in doubleEscapes {
            #expect(
                occurrences(of: doubled, in: html) <= occurrences(of: written, in: markdown),
                "\(doubled) in \(html.debugDescription)"
            )
        }
    }
    for body in exportedBodies {
        for tag in tags(in: body) {
            #expect(tag.map { allowedElements.contains($0.name) } == true, "a stray `<` in \(body.debugDescription)")
        }
    }
}

@Test func theBodyUsesOnlyTheClosedElementSet() {
    for body in exportedBodies {
        for tag in tags(in: body).compactMap({ $0 }) {
            #expect(allowedElements.contains(tag.name), "<\(tag.name)> in \(body.debugDescription)")
            #expect(allowsAttributes(tag.attributes, on: tag.name), "<\(tag.name)\(tag.attributes)>")
        }
        // Outside the escaped `href` values, which may quote anything the note wrote (E34).
        let markup = body.replacingOccurrences(of: #"="[^"]*""#, with: #"="""#, options: .regularExpression)
        for forbidden in ["<img", "src=", "<script", "<link", "<iframe"] {
            #expect(!markup.contains(forbidden), "\(forbidden) in \(body.debugDescription)")
        }
        #expect(markup.range(of: #" on[a-z]+="#, options: .regularExpression) == nil, "\(body.debugDescription)")
    }
}

@Test func theFourTaskGlyphs() {
    // Gate G0: `☐` and `☑` as before, `⊟` (U+229F) for cancelled and `▷` (U+25B7) for
    // rescheduled. Neither reads as done, and done text is not struck (ADR-0077 §D6).
    #expect(MarkdownHTML.render("- [ ] a\n- [x] b\n- [X] c\n- [-] d\n- [>] e") == """
        <ul>
        <li>\u{2610} a</li>
        <li>\u{2611} b</li>
        <li>\u{2611} c</li>
        <li>\u{229F} d</li>
        <li>\u{25B7} e</li>
        </ul>
        """)
}
