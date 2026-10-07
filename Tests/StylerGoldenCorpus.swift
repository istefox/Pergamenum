import Foundation
@testable import Pergamenum

// ADR-0082 §D3, plan docs/plans/pg-385-n2-page.md, Task 1 (PG-385, R-18).
//
// The corpus `StylerGoldenTests.swift` pins, beside it for `file_length`. It is the shape of
// `NoteExportGoldenCorpus`, with its own type because that corpus's `Kind` gives `b` and `c`
// other meanings (a parser fix and a presentation rule; here B is a deliberate change and C a
// regression that blocks the merge).
//
// **Captured, never written by hand.** Every `captured` string was printed by
// `stylerGoldenCapture` (`StylerGoldenTests.swift`'s last test, gated on
// `TEST_RUNNER_STYLER_GOLDEN_CAPTURE=1`) running `MarkdownStyler` as it stood on `3e5df0a6`,
// before a line of it changed, and lives in `StylerGoldenCapturedExport.swift` (the export
// corpus's inputs) and `StylerGoldenCapturedEditor.swift` (the editor's own), split out of this
// file for `file_length`. A case added after the styler moved (E48, S51 to S60) was captured the
// same way, from a detached checkout of `3e5df0a6` carrying only these corpus files. A `captured`
// string is never edited: when the styler moves, a case whose output differs gets a class in
// `changes` (`StylerGoldenChanges.swift`), with the reason and the new `expected`, and a C is
// fixed in the parser or the mapping, never re-captured. The helper stays here so N5 can capture its own constructs the
// same way.
//
// **The canonical form** (G0 item 1): one line per span, `start..<end span` in UTF-16 offsets,
// sorted; then one `hidden start..<end kind` line per span the note editor conceals, through
// `NoteTextView.Coordinator.hiddenKind(for:)`; then one `order a < b` line per pair of
// overlapping spans, in emission order. `spans(in:)` documents that later spans win where they
// overlap, so a sorted list alone could not see a precedence regression.

struct StylerGoldenCase: Sendable, CustomStringConvertible {
    /// How the case's output moved when the styler moved onto the shared parsers (ADR-0082 §D3).
    enum Change: Sendable {
        /// Old and new output are the same bytes.
        case unchanged
        /// The old styler was wrong and the shared grammar is right: class A. `expected` is the
        /// new canonical output.
        case fix(reason: String, expected: String)
        /// A change chosen on purpose for a reason other than a styler defect: class B.
        case deliberate(reason: String, expected: String)
    }

    let name: String
    let markdown: String
    /// What the old styler printed, canonical form. Never edited.
    let captured: String
    let change: Change
    var description: String { name }

    /// What `MarkdownStyler` has to print now: the captured bytes, or the class's own `expected`.
    var expected: String {
        switch change {
        case .unchanged: captured
        case .fix(_, let expected), .deliberate(_, let expected): expected
        }
    }
}

enum StylerGoldenCorpus {
    /// What the old styler printed, by case name: the two captured files beside this one.
    static let capturedOutputs: [String: String] =
        capturedExportOutputs.merging(capturedEditorOutputs) { first, _ in first }

    /// Every input in `inputs`, with the bytes the old styler printed for it.
    static let cases: [StylerGoldenCase] = inputs.map { input in
        StylerGoldenCase(
            name: input.name, markdown: input.markdown,
            captured: capturedOutputs[input.name] ?? "<not captured>",
            change: changes[input.name] ?? .unchanged
        )
    }

    /// The inputs: every `NoteExportGoldenCorpus` body and page by name (never copied), then the
    /// editor's own constructs.
    static var inputs: [(name: String, markdown: String)] {
        exportInputs + editorInputs
    }

    /// E01 to E45, X01 to X09 and the two pages, verbatim from the export corpus.
    static var exportInputs: [(name: String, markdown: String)] {
        (NoteExportGoldenCorpus.bodies + NoteExportGoldenPages.all).map { ($0.name, $0.markdown) }
    }

    /// The canonical text of `MarkdownStyler.spans(in:)`, as the header describes it. Main-actor
    /// isolated only because `NoteTextView.Coordinator.hiddenKind(for:)` is.
    @MainActor
    static func canonical(_ text: String) -> String {
        let styled = MarkdownStyler.spans(in: text)
        func label(_ span: MarkdownStyler.Span) -> String {
            String(describing: span).replacingOccurrences(of: "Pergamenum.", with: "")
        }
        let entries = styled.map { item in
            CanonicalEntry(
                start: text.utf16.distance(from: text.startIndex, to: item.range.lowerBound),
                end: text.utf16.distance(from: text.startIndex, to: item.range.upperBound),
                label: label(item.span), span: item.span
            )
        }
        func line(_ entry: CanonicalEntry) -> String {
            "\(entry.start)..<\(entry.end) \(entry.label)"
        }
        func sorted(_ items: [CanonicalEntry]) -> [CanonicalEntry] {
            items.sorted { lhs, rhs in
                (lhs.start, lhs.end, lhs.label) < (rhs.start, rhs.end, rhs.label)
            }
        }

        var lines = sorted(entries).map(line)
        for entry in sorted(entries) {
            guard let kind = NoteTextView.Coordinator.hiddenKind(for: entry.span) else { continue }
            lines.append("hidden \(entry.start)..<\(entry.end) \(kind)")
        }
        // Emission order, not sorted: it is the order the view applies them in.
        for (earlier, first) in entries.enumerated() {
            for second in entries[(earlier + 1)...] where first.start < second.end && second.start < first.end {
                lines.append("order \(line(first)) < \(line(second))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The editor's own constructs (ADR-0082 §D3)

    static let editorInputs: [(name: String, markdown: String)] = [
        // Inline conventions of the app.
        ("S01", "Riunione #project-av45 con #topic-fisica."),
        ("S02", "Da fare >2026-10-04 e scade !2026-10-09."),
        ("S03", "Chiuso @done(2026-10-01) e @remind(2026-10-05 09:00) e @repeat(1w)."),
        ("S04", "- [ ] aperto\n- [x] fatto\n- [-] annullato\n- [>] rinviato"),
        ("S05", "- [ ] con data >2026-10-04 e tag #project-av45 e !2026-10-09"),
        // Lists.
        ("S06", "- uno\n  - due\n    - tre\n      - quattro"),
        ("S07", "* stella\n+ più\n- trattino"),
        ("S08", "1. uno\n   1. annidato\n2. due\n10. dieci"),
        ("S09", "1) uno\n2) due\n12) dodici"),
        ("S10", "- uno\n\t- tab\n\t\t- due tab\n  \t- misto"),
        ("S11", "\u{FF11}. cifra a larghezza piena\n\u{FF12}) altra"),
        ("S12", "12) dodici\n\n- [ ] 3. non lista"),
        // Quotes, headings, rules.
        ("S13", "> uno\n> > due\n> > > tre"),
        ("S14", ">senza spazio\n>>annidata"),
        ("S15", "#\n##\n######\n#######"),
        ("S16", "# Titolo\n## Sottotitolo\n### Terzo\n#### Quarto\n##### Quinto\n###### Sesto"),
        ("S17", "#tag a inizio riga\n\n#Titolo\n\n# Titolo vero"),
        ("S18", "sopra\n\n---\n\nsotto\n\n***\n\n___\n\n- - -"),
        // Fences, view block, table, frontmatter, anchor.
        ("S19", "```\nsenza lingua # non un titolo\n```\n\ndopo"),
        ("S20", "```swift\nlet x = 1 // commento\nfunc f() {}\n```"),
        ("S21", "```pergamenum-view\nrender: table\nwhere: tag(\"topic-produzione\")\n```\n\ndopo"),
        ("S22", "```swift\nnon chiusa\n# ancora codice"),
        ("S23", "| a | b |\n|:--|--:|\n| 1 | 2 |\n\ndopo"),
        ("S24", "---\ndate: 2026-10-04\ntags:\n  - type-note\n---\n\n# Titolo\n\ncorpo #tag"),
        ("S25", "---\nx\n---\n\ncorpo dopo un blocco di tre trattini"),
        ("S26", "<!-- pergamenum-message: <abc@example.com> -->\n\nTesto."),
        // Wikilinks, embeds, links.
        ("S27", "![[foto.png]] e ![[foto.png|300]] e ![[foto.png|300x200]]"),
        ("S28", "![[foto.png]]\n\n![[Altra nota]]\n\n![alt](foto.png)"),
        ("S29", "[[Nota]] [[Nota|alias]] [[Nota#Sezione]] [[Nota#Sezione|alias]]"),
        ("S30", "[testo con *enfasi* dentro](https://example.com/a_b_c)"),
        ("S31", "[**forte**](https://example.com) e [a](b) e [vuoto]()"),
        // Emphasis, flanking, nesting, unclosed.
        ("S32", "file_name_here"),
        ("S33", "2 * 3 * 4"),
        ("S34", "nome_file_lungo e nome_file_lungo_due"),
        ("S35", "_corsivo_ e __forte__ e *corsivo* e **forte** e ***entrambi***"),
        ("S36", "**forte con *corsivo* dentro** e *corsivo con **forte** dentro*"),
        ("S37", "**non chiuso e *neanche questo e ~~e nemmeno questo e `questo"),
        ("S38", "~~barrato~~ e ~~ non barrato ~~ e `codice` e ``doppio ` tick``"),
        ("S39", "`**non forte**` e **`codice dentro forte`** e [[**nota**]]"),
        // The `>date` rule and its neighbours.
        ("S40", ">2026-10-04 riunione"),
        ("S41", "> 2026-10-04"),
        ("S42", ">2026-02-31"),
        ("S43", "> quote con >2026-10-04 dentro"),
        // Line splitting.
        ("S44", "# Titolo\r\n\r\n- uno\r\n- [ ] due\r\n\r\n> citazione\r\n\r\nfine"),
        ("S45", "prima\u{2028}seconda\u{2028}- elemento dopo separatore"),
        ("S46", "---\r\ndate: 2026-10-04\r\n---\r\n\r\ncorpo"),
        // Everything at once.
        ("S47", """
        ---
        date: 2026-10-04
        tags:
          - type-note
        ---

        # Titolo con [[Nota]] e #tag

        Testo con **forte**, *corsivo*, ~~barrato~~, `codice` e [link](https://x.it).

        - [ ] attività >2026-10-04 !2026-10-09 @remind(2026-10-05)
          - sotto-punto
        1. uno
        2. due

        > citazione con *enfasi*

        ```swift
        let carico = 450
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        ![[foto.png|300]]
        """),
        // A checkbox written in a form the task index does not read (review finding, n2-page R-18):
        // the editor drew each of these as a bullet before the shared grammar took over.
        ("S48", "+ [ ] con più\n  + [x] annidato"),
        ("S49", "-  [ ] due spazi\n*   [x] tre spazi"),
        ("S50", "-\t[ ] tabulazione"),
        // Tab-indented block constructs (review finding, n2-page R-18): the old styler trimmed
        // spaces only before a heading, a quote, a rule or a task; the reading view, the exporter
        // and the task index trim tabs too.
        ("S51", "\t# Titolo rientrato\n\n\t## Secondo"),
        ("S52", "\t> citazione rientrata\n\n\t> > annidata"),
        ("S53", "sopra\n\n\t---\n\nmezzo\n\n\t***\n\nsotto"),
        ("S60", "\t- - -\n\t- lista"),
        ("S54", "\t- [ ] fai\n\t\t- [x] fatto"),
        // A U+2028 or a lone CR is no paragraph break to the editor (review finding, n2-page R-18):
        // TextKit keeps the whole thing in one paragraph and the old styler scanned it as one line,
        // so a run, a tag boundary, a heading's extent and a rule's whole-line test span it.
        ("S55", "a\u{2028}**b\u{2028}c** e `x\u{2028}y` e [l\u{2028}m](u)"),
        ("S56", "x\u{2028}#project-av45 e y\u{2028}>2026-10-04"),
        ("S57", "# titolo\u{2028}secondo\n\n---\u{2028}x\n\n> citazione\u{2028}seguito"),
        ("S58", "a\r**b\rc** e x\r#project-av45\r- non lista"),
        // A delimiter row with no pipe (review finding, n2-page R-18): `---` under a one-column
        // header is the table's delimiter row for the reading view, and a rule on its own.
        ("S59", "| a |\n---\n| 1 |\n\ndopo"),
    ]
}

/// One styled range of `StylerGoldenCorpus.canonical`, in UTF-16 offsets.
private struct CanonicalEntry {
    let start: Int
    let end: Int
    let label: String
    let span: MarkdownStyler.Span
}
