**Requirement set:** `SPEC.md`

# N5 code PR: the page, part two (R-36 to R-43)

- SPEC: root `SPEC.md`, Approved 2026-10-04, milestone N5 (issue #890), R-36 to R-43, plus the
  chain-wide R-44 and R-45 for this milestone. R-35 (tokens) ships in the mockup PR,
  `docs/plans/note-workflow-n5-mockup.md`, which merges and is approved on the Debug build first.
- ADR outcome: **new ADR**, `docs/adr/0087-the-editor-draws-the-remaining-constructs.md`
  (Proposed). It extends ADR-0029 §D1, amends ADR-0029 §D1's quote bullet and ADR-0077 §D4,
  amends SPEC (app) §5's construct list, and records the SPEC's callout-keyword decision (§D3).
  Section numbers below (§Dn) are that ADR's.
- Base: `48a2d912` (`origin/main`), planned against today's code. **Dependencies, binding:**
  - N2's styler rewrite (ADR-0082, plan `docs/plans/note-workflow-n2.md`, roadmap N2 task 7) must
    be on `main` before Tasks 3 to 7. `MarkdownStyler.spans(in:)` then classifies through
    `MarkdownBlockParser`/`MarkdownInlineParser`, so the constructs Task 2 adds to those parsers
    reach the editor through N2's mapping, not through a second recogniser.
  - ADR-0081 (N2) fixes the quote content column that §D7's indent step reads.
  - N1's R-07 (Cmd+click on `#tag` and `>date`, ADR-0080) must be on `main` before Task 4, whose
    chips ride on those ranges.
  - Line numbers below were read at `48a2d912`. Where N2 moves code, re-grep the named symbol;
    never trust a line.
- Decisions registered from the SPEC, not reopened: callouts write `note`/`tip`/`important`/
  `warning`/`caution`, read `nota`/`suggerimento`/`importante`/`avviso`/`attenzione` as aliases,
  label them in Italian and draw any other type neutral; clickable dates are `>YYYY-MM-DD` tokens
  only; **no GUI tests in N5**, so every drawing assertion below is a hosted (in-process) or pure
  test.
- Token names come from the approved mockup PR: `color.code.inlineBackground`, `color.highlight`,
  `color.quote.bar`, `color.callout.{note,tip,important,warning,caution}`, and the card opacity
  0.08.
- **Observable contracts this PR changes, with their call sites (grepped at `48a2d912`):**
  - `MarkdownBlock.quote([String])` becomes `[QuoteLine]`:
    - `Sources/Core/Markdown/MarkdownBlocks.swift:227`
    - `Sources/Core/Markdown/MarkdownHTML.swift:59`
    - `Sources/Features/Editor/MarkdownBlocksView.swift:61`
    - `Tests/MarkdownReadingTests.swift:77`
  - `MarkdownBlock` gains `.callout`. Its exhaustive switches are `MarkdownHTML.html(for:)` and
    `MarkdownBlocksView`'s block switch. `Tests/NoteOutlineTests.swift:145` (`default`) and
    `ViewBlock.blocks(in:)` (`guard case`) are unaffected.
  - `MarkdownStyler.Span` gains cases. Its exhaustive switches:
    - `MarkdownStyler.swift:166`, `:344`, `:360`
    - `CardTextAttributes.swift:114`, `:205`
    - `InlineSpanReveal.swift:37`
    - `NoteTextView+Coordinator.swift:414`
    - `MarkdownAttributedText.swift:127`, `:228`
    - `CardTextView.swift:360` has `default: nil` and needs no arm.
  - `HiddenMarker.Kind` gains cases: `isInline` (`EditorDecorationDelegate.swift:114`) and the
    re-validation switch (`:776`).
  - `EmbedRendition` gains `.pending`. Its `==` is at `NoteTextView+Embeds.swift:15`, and the
    tests match `.drawn` with `guard case` only.
  - The HTML export changes for `==`, callouts, nested quotes and transclusions, and its stylesheet
    gains rules. Pinned by:
    - E15 (`Tests/NoteExportGoldenCorpus.swift:147`);
    - the W01 and W02 pages (`Tests/NoteExportGoldenTests.swift:26` and `:57`);
    - the R-11 page (`Tests/ViewBlockOutOfScopeTests.swift:152`);
    - the closed element set (`Tests/NoteExportGoldenTests.swift:222`).
  - `EditorCommand.editorEntries` gains «Callout». `Tests/EditorCommandTests.swift:168` derives
    its expectation from the catalogue and stays consistent.

  Tasks 1 and 2 update every one of these. **Run the full `PergamenumTests` suite after each
  task, not only the new files**: the quote payload and the stylesheet are read by tests in
  unrelated modules.

### Task 1 — Core contracts; update tests asserting the old behaviour (R-36, R-37, R-38, R-39, R-40, R-41, R-43)
Owner: tester
Files:
- Sources/Core/Markdown/MarkdownInline.swift
- Sources/Core/Markdown/MarkdownBlocks.swift
- Sources/Core/Markdown/Callout.swift
- Sources/Core/Markdown/FenceChrome.swift
- Sources/Core/Markdown/TransclusionCaption.swift
- Sources/Core/Markdown/MarkdownHTML.swift
- Sources/Features/Editor/MarkdownBlocksView.swift
- Sources/Features/Editor/TableEdit.swift
- Tests/MarkdownConstructParserTests.swift
- Tests/CalloutTests.swift
- Tests/TableEditTests.swift
- Tests/MarkdownReadingTests.swift
- Tests/NoteExportConstructCorpus.swift
- Tests/NoteExportGoldenCorpus.swift
- Tests/NoteExportGoldenTests.swift
- Tests/ViewBlockOutOfScopeTests.swift
Tests: MarkdownConstructParserTests.swift, CalloutTests.swift, TableEditTests.swift, MarkdownReadingTests.swift, NoteExportConstructCorpus.swift, NoteExportGoldenCorpus.swift, NoteExportGoldenTests.swift, ViewBlockOutOfScopeTests.swift
Signatures:
- MarkdownSpan.Style.highlight — case highlight
- MarkdownBlock.QuoteLine — struct QuoteLine: Equatable, Sendable { var level: Int; var text: String }
- MarkdownBlock.quote — case quote([QuoteLine])
- MarkdownBlock.callout — case callout(Callout)
- CalloutKind — enum CalloutKind: Hashable, Sendable { case note, tip, important, warning, caution; case other(String) }
- CalloutKind.init(keyword:) — init(keyword: some StringProtocol)
- CalloutKind.keyword — var keyword: String { get }
- CalloutKind.label — var label: String { get }
- CalloutKind.exportClass — var exportClass: String { get }
- Callout — struct Callout: Equatable, Sendable { var kind: CalloutKind; var title: String?; var fold: Fold; var body: [MarkdownBlock.QuoteLine] }
- Callout.Fold — enum Fold: Equatable, Sendable { case fixed, open, folded }
- Callout.Header — struct Header: Equatable, Sendable { var kind: CalloutKind; var fold: Fold; var title: String?; var markerLength: Int }
- Callout.header(inLine:) — static func header(inLine line: some StringProtocol) -> Header?
- FenceChrome — struct FenceChrome: Equatable, Sendable { var opening: Range<String.Index>; var closing: Range<String.Index>; var body: Range<String.Index>; var language: String?; var lineCount: Int }
- FenceChrome.blocks(in:) — static func blocks(in text: String) -> [FenceChrome]
- FenceChrome.block(containing:in:) — static func block(containing utf16Offset: Int, in text: String) -> FenceChrome?
- FenceChrome.lineCountLabel — var lineCountLabel: String { get }
- TransclusionCaption.text(note:section:) — static func text(note: String, section: String?) -> String
- TableEdit.align — case align(column: Int, GFMTable.Alignment)
- TableEdit.sort — case sort(column: Int, ascending: Bool)
- TableEdit.applied(to:) — func applied(to table: GFMTable) -> GFMTable
- MarkdownBlockParser.blocks(in:) — static func blocks(in body: String) -> [MarkdownBlock]
- MarkdownInlineParser.spans(in:) — static func spans(in text: String) -> [MarkdownSpan]
- MarkdownHTML.render(_:) — static func render(_ markdown: String) -> String
- NoteExport.html(from:title:) — static func html(from text: String, title: String) -> String
Red: yes

**Declarations and shims, nothing more.** The tester declares the signatures above. New files
are Foundation-only, since `Sources/Core/**` compiles into `perg` and `pergamenum-mcp`. Every new
function gets a neutral stub body that compiles and returns a wrong-but-safe value (`nil`, `[]`,
`""`, `.other(String(keyword))`, the input unchanged), never `fatalError`, so the suite runs red
instead of crashing. The `.quote` payload change and the new `.callout` case are made to compile
with shims that keep today's behaviour exactly:

- the parser appends `.quote(quote.map { QuoteLine(level: 1, text: $0) })`;
- `MarkdownHTML` and `MarkdownBlocksView` read `lines.map(\.text)`;
- each draws `.callout` as the quote of its body texts.

`TableEdit.applied(to:)` already returns the table unchanged for an edit it refuses, and that is
the stub for `align` and `sort`. The existing suite stays green; only the new and updated tests are
red.

**`MarkdownConstructParserTests.swift`** (pure):
- **Highlights:**
  - `a ==b== c` gives a `.highlight` span `b`;
  - `` `a==b==` `` is one `.code` span with no highlight (the SPEC's edge case);
  - `a == b == c`, `==a` and `== a==` open nothing;
  - `==**x**==` nests `strong` inside `highlight`.
- **Quotes:**
  - `> a\n>> b\n> > c` gives levels 1, 2, 2;
  - a level-1 quote's texts equal today's (E06's input gives `["citato", "ancora"]` at level 1).
- **Fence chrome:**
  - a closed `swift` fence yields one `FenceChrome` whose `opening`/`closing` are the fence lines
    (line breaks excluded), `body` the code, `language` `swift` and `lineCount` 2;
  - an empty fence counts 0;
  - an unclosed fence and a `pergamenum-view` fence yield none;
  - `block(containing:)` finds a block from an offset in its header, body or closing line, and
    nothing outside;
  - `lineCountLabel` is «1 riga» or «N righe».
- **Caption:** `TransclusionCaption.text(note: "Nota", section: "Sezione")` is
  `da «Nota» › Sezione`; with `section: nil` it is `da «Nota»`.

**`CalloutTests.swift`** (pure):
- **Kinds:**
  - `CalloutKind(keyword:)` maps the five English keywords and the five Italian aliases, in any
    case (`[!WARNING]`), to their case, and anything else to `.other` as written;
  - `keyword` is always the English one for the five;
  - `label` is «Nota», «Suggerimento», «Importante», «Avviso», «Attenzione», and the written type
    capitalised for `.other`;
  - `exportClass` is `callout-<keyword>` or `callout-other`.
- **Header:**
  - `Callout.header(inLine:)` reads `> [!note]`, `> [!note] Titolo`, `>[!tip]- Titolo` and
    `> [!avviso]+`;
  - `markerLength` (UTF-16) covers `>`, the spaces, `[!type]`, the sign and one following space,
    never the title;
  - nil for `> [!]`, `> [note]` and `> > [!note]`.
- **Blocks:**
  - a callout block's body lines carry their level minus one;
  - the run ends at the first non-quote line;
  - a callout line with nothing after it is a callout with an empty body;
  - a `[!type]` at level 2 stays quote text.

**`TableEditTests.swift`**:
- **Align:**
  - `.align(column: 1, .trailing)` changes `alignments[1]` only;
  - the serialised delimiter row is `|---|--:|`;
  - setting a column's current alignment returns the table unchanged, so `commitTable` refuses it
    as a no-op;
  - an out-of-range column is refused.
- **Sort:**
  - `.sort(column:ascending:)` orders body rows by `localizedStandardCompare` (`2` before `10`);
  - empty cells come last in both directions, and equal keys keep their order (stable);
  - the header and the row count are untouched;
  - an out-of-range column is refused.

**`MarkdownReadingTests.swift:77`** is updated to the `QuoteLine` form, plus one nested case.

**Export:** add **`NoteExportConstructCorpus.swift`**, `FormatEdgeCorpus.swift`'s shape, beside the
corpus for `file_length`. `NoteExportGoldenCorpus.bodies` becomes
`decisionTable + escapeCorpus + constructCorpus`, and each case keeps a reason. Cases N01 onward:

- `a ==b== c` → `<p>a <mark>b</mark> c</p>`. The wrap order is `code`, `mark`, `del`, `em`,
  `strong`, so `==**x**==` → `<p><strong><mark>x</mark></strong></p>`.
- `` `a==b==` `` → `<p><code>a==b==</code></p>`, and `a == b` → `<p>a == b</p>`.
- `> a\n>> b\n> c` →
  `<blockquote><p>a</p><blockquote><p>b</p></blockquote><p>c</p></blockquote>`. Nested
  blockquotes open inline with no line breaks, so a level-1 quote keeps E06's bytes.
- `> [!warning] Forno\n> Corpo` → `<aside class="callout-warning">`, a line break,
  `<p><strong>Forno</strong></p>`, a line break, `<p>Corpo</p>`, a line break, `</aside>`.
- One case for each of the five kinds:
  - with no title, the Italian label is the title;
  - with an Italian alias (`[!avviso]`), the class is `callout-warning` and the label «Avviso»;
  - uppercase `[!NOTE]` reads as `note`;
  - an unknown `[!faq] Domande` is `callout-other`;
  - a folded `-` callout exports open with its body;
  - a title holding `<&"'` is escaped once.
- `![[Altra nota#Sezione]]` → `<p>da «Altra nota» › Sezione</p>`. This is **E15 re-captured**:
  its reason names ADR-0087 §D12, and its kind stays `.a`. `![[Altra nota]]` →
  `<p>da «Altra nota»</p>`.
- Unchanged, marked `.unchanged`, pinning that chips and chrome are not exported:
  - `#client-acme >2026-10-14` → `<p>#client-acme &gt;2026-10-14</p>`;
  - a `swift` fence → `<pre><code>…</code></pre>` with no language.
  - E05 (alignment) and E16 (inline embed) already pin the other two and are cited, not
    duplicated.

**`NoteExportGoldenTests.swift`**:
- `allowedElements` gains `mark` and `aside`.
- `allowsAttributes` accepts on `aside` exactly ` class="callout-<k>"` for the six values.
- **Update tests asserting the old stylesheet**: W01's and W02's pages, and
  `ViewBlockOutOfScopeTests.swift`'s R-11 page, gain the stylesheet lines the export adds:

  ```
  mark { background: <highlight>; padding: 0 0.15em; border-radius: 3px; }
  aside { margin: 1em 0; padding: 0.6em 1em; border-left: 3px solid <quote.bar>; border-radius: 6px; background: #F2EFE9; }
  aside.callout-<k> { border-color: <callout.k>; background: <callout.k at 0.08 over #FFFFFF>; }
  ```

  The `aside.callout-<k>` rule is written once per kind. Every `<…>` is `pergamenum-light.json`'s
  approved value. One new test reads the light theme file and asserts that each colour in the
  export stylesheet equals it, so the copies cannot drift silently.

### Task 2 — Core bodies and the export; update call-sites asserting the old behaviour (R-36, R-37, R-38, R-39, R-40, R-41, R-43)
Owner: coder
Files:
- Sources/Core/Markdown/MarkdownInline.swift
- Sources/Core/Markdown/MarkdownBlocks.swift
- Sources/Core/Markdown/Callout.swift
- Sources/Core/Markdown/FenceChrome.swift
- Sources/Core/Markdown/TransclusionCaption.swift
- Sources/Core/Markdown/MarkdownHTML.swift
- Sources/Core/Conventions/NoteExport.swift
- Sources/Features/Editor/TableEdit.swift
Tests: MarkdownConstructParserTests.swift, CalloutTests.swift, TableEditTests.swift, MarkdownReadingTests.swift, NoteExportGoldenTests.swift, ViewBlockOutOfScopeTests.swift
Signatures:
- Callout.header(inLine:) — static func header(inLine line: some StringProtocol) -> Header?
- FenceChrome.blocks(in:) — static func blocks(in text: String) -> [FenceChrome]
- CodeFence.regions(in:) — static func regions(in text: String) -> [Region]
- CodeFence.marks(_:) — static func marks(_ trimmedLine: some StringProtocol) -> Bool
- GFMTable.serialised(lineBreak:) — func serialised(lineBreak: LineBreak = .lf) -> String
- NoteExport.escape(_:) — static func escape(_ text: String) -> String
Red: no

Make Task 1 green with the rules of ADR-0087 §D2, §D3, §D11 and §D12:

- **Inline parser.** `emphasisMarker` gains `("==", .highlight)` before the single-character
  markers, and code spans are still matched first. `opensEmphasis` applies unchanged: no
  whitespace after the opener. The intraword rule stays `_`-only.
- **Block parser.**
  - The quote branch counts the level (`>` each optionally followed by spaces) and strips the
    whole run.
  - A level-1 first line that `Callout.header(inLine:)` accepts turns the run into
    `.callout(Callout)`; the body is the rest of the run, with levels minus one.
  - Replace Task 1's shim at `MarkdownBlocks.swift:227`. `MarkdownBlocks.swift` is 308 lines: the
    quote and callout run handling goes in `MarkdownBlocks+Quote.swift` if it pushes the file past
    400.
- **`FenceChrome`** is built over `CodeFence.regions(in:)` plus `CodeFence.marks` on the last line
  (closed only), excluding `ViewBlock.language`. It is never a second fence grammar.
- **`MarkdownHTML`.** It emits the nested `<blockquote>` and the `aside` exactly as Task 1's cases
  spell them, and the caption through `TransclusionCaption.text`. The callout title and body go
  through `inline(_:)`, so the escape rule of ADR-0077 §D2 holds (escaped once, at emission).
  Replace both Task 1 shims there.
- **`NoteExport.html`** gains the stylesheet lines Task 1 fixed.
- **`TableEdit`.**
  - `align` writes one entry of `alignments`.
  - `sort` reorders `rows` with a stable sort on `localizedStandardCompare`, empties last, and the
    header is untouched.
  - Both leave `range` and `lineRanges` alone, as every case does (the commit re-derives them).
- **Not here:** `MarkdownBlocksView`'s shim is replaced in Task 6. The reading view's real nested
  quote and callout card belong with the editor's, so the two cannot be reviewed apart.

**Build gate:** `perg` and `pergamenum-mcp` build after this task, because every file touched here
is in their `sharedSources` globs (R-45).

### Task 3 — Editor contracts: spans, kinds, fragments, chips, folds, embeds, table menu (R-36, R-37, R-38, R-39, R-40, R-41, R-42)
Owner: tester
Files:
- Sources/Features/Editor/MarkdownStyler.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/MarkdownAttributedText.swift
- Sources/Features/Editor/InlineSpanReveal.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Workspace/CardTextAttributes.swift
- Sources/Features/Editor/InlineChip.swift
- Sources/Features/Editor/InlineChipPainter.swift
- Sources/Features/Editor/ChipLineFragment.swift
- Sources/Features/Editor/CodeFenceFragment.swift
- Sources/Features/Editor/QuoteBarFragment.swift
- Sources/Features/Editor/QuoteGeometry.swift
- Sources/Features/Editor/CalloutTitleFragment.swift
- Sources/Features/Editor/CalloutStyle.swift
- Sources/Features/Editor/CalloutFold.swift
- Sources/Features/Editor/EmbedPlaceholder.swift
- Sources/Features/Editor/EmbedPresentation.swift
- Sources/Features/Editor/NoteTextView+Embeds.swift
- Sources/Features/Editor/TableColumnMenu.swift
- Sources/Features/Editor/NoteTextView+Inputs.swift
- Sources/Vault/NoteTab.swift
- Sources/App/VaultController+Callouts.swift
- Tests/InlineChipTests.swift
- Tests/EditorChipDrawingTests.swift
- Tests/CodeFenceChromeTests.swift
- Tests/QuoteBarDrawingTests.swift
- Tests/CalloutFoldTests.swift
- Tests/CalloutDrawingTests.swift
- Tests/EmbedPresentationTests.swift
- Tests/EmbedDrawingTests.swift
- Tests/TranscludedLineTests.swift
- Tests/TranscludedLineFragmentWidthTests.swift
- Tests/TableColumnMenuTests.swift
- Tests/EditorDecorationSubstitutionTests.swift
- Tests/MarkdownStylerTests.swift
- Tests/MarkdownStylerFixture.swift
- Tests/EditorCommandTests.swift
Tests: InlineChipTests.swift, EditorChipDrawingTests.swift, CodeFenceChromeTests.swift, QuoteBarDrawingTests.swift, CalloutFoldTests.swift, CalloutDrawingTests.swift, EmbedPresentationTests.swift, EmbedDrawingTests.swift, TranscludedLineTests.swift, TranscludedLineFragmentWidthTests.swift, TableColumnMenuTests.swift, EditorDecorationSubstitutionTests.swift, MarkdownStylerTests.swift, MarkdownStylerFixture.swift, EditorCommandTests.swift
Signatures:
- MarkdownStyler.Span.highlight — case highlight
- MarkdownStyler.Span.highlightMarker — case highlightMarker
- MarkdownStyler.Span.inlineCodeMarker — case inlineCodeMarker
- MarkdownStyler.Span.fenceOpening — case fenceOpening(language: String?, lineCount: Int)
- MarkdownStyler.Span.fenceClosing — case fenceClosing
- MarkdownStyler.Span.calloutMarker — case calloutMarker(CalloutKind, fold: Callout.Fold)
- MarkdownStyler.Span.calloutBody — case calloutBody(CalloutKind)
- MarkdownStyler.Span.embedChipMarker — case embedChipMarker
- HiddenMarker.Kind (new cases) — case inlineCode, highlight, fenceOpening, fenceClosing, calloutMarker, embedChip
- NSAttributedString.Key.pergamenumChip — static let pergamenumChip: NSAttributedString.Key
- InlineChip.Style — struct Style: Equatable { var background: NSColor; var leading: NSColor?; var trailing: NSColor?; var symbolName: String? }
- InlineChip.Parts — struct Parts: Equatable, Sendable { var leading: Int; var trailing: Int }
- InlineChip.tagParts(_:) — static func tagParts(_ tag: some StringProtocol) -> Parts?
- InlineChip.dateParts(_:) — static func dateParts(_ token: some StringProtocol) -> Parts?
- InlineChipPainter.rects(for:in:padding:) — static func rects(for range: NSRange, in fragment: NSTextLayoutFragment, padding: CGFloat) -> [CGRect]
- ChipLineFragment — final class ChipLineFragment: NSTextLayoutFragment
- CodeFenceFragment — final class CodeFenceFragment: NSTextLayoutFragment { enum Role: Equatable { case header(language: String?, lineCount: Int), closing }; var role: Role }
- QuoteBarFragment — final class QuoteBarFragment: NSTextLayoutFragment { var level: Int; var callout: (kind: CalloutKind, piece: CalloutPiece)? }
- QuoteGeometry.indent(level:step:) — static func indent(level: Int, step: CGFloat) -> CGFloat
- QuoteGeometry.barOffsets(level:step:) — static func barOffsets(level: Int, step: CGFloat) -> [CGFloat]
- CalloutTitleFragment — final class CalloutTitleFragment: NSTextLayoutFragment { var kind: CalloutKind; var isFolded: Bool?; var calloutOffset: Int }
- CalloutPiece — enum CalloutPiece: Equatable, Sendable { case only, first, middle, last }
- CalloutStyle.backgroundOpacity — static let backgroundOpacity: CGFloat = 0.08
- CalloutKind.colorToken — var colorToken: ColorToken? { get }
- CalloutKind.symbolName — var symbolName: String { get }
- CalloutFold.isFolded(_:toggled:) — static func isFolded(_ fold: Callout.Fold, toggled: Bool) -> Bool
- CalloutFold.hiddenLines(in:toggled:) — static func hiddenLines(in text: String, toggled: Set<Int>) -> Set<Int>
- NoteTab.toggledCallouts — var toggledCallouts: Set<Int>
- NoteTextView.OutlineInputs.toggledCallouts — var toggledCallouts: Set<Int>
- NoteTextView.OutlineInputs.onToggleCallout — var onToggleCallout: ((Int) -> Void)?
- VaultController.toggleCallout(_:) — func toggleCallout(_ offset: Int)
- EmbedRendition.pending — case pending(name: String)
- EmbedPlaceholder.defaultSize — static let defaultSize: CGSize
- EmbedPlaceholder.size(written:column:) — static func size(written: EmbedResize.Written?, column: CGFloat) -> CGSize
- EmbedPresentation — enum EmbedPresentation: Equatable, Sendable { case drawn, chip, transclusion }
- EmbedPresentation.of(target:isWholeLine:) — static func of(target: String, isWholeLine: Bool) -> EmbedPresentation
- EmbedPresentation.symbolName(forTarget:) — static func symbolName(forTarget target: String) -> String
- TableColumnMenu.Entry — enum Entry: Equatable, Sendable { case align(GFMTable.Alignment, isCurrent: Bool); case sort(ascending: Bool) }
- TableColumnMenu.entries(current:) — static func entries(current: GFMTable.Alignment) -> [Entry]
- TableColumnMenu.title(of:) — static func title(of entry: Entry) -> String
- TableColumnMenu.edit(for:column:) — static func edit(for entry: Entry, column: Int) -> TableEdit?
- TranscludedRendition — struct TranscludedRendition: Equatable (relied on; Task 7 removes its header caption)
- NoteTextView.Coordinator.textView(_:menu:for:at:) — func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu?
Red: yes

**Declarations, neutral arms, then red tests.** The tester declares every signature above. Each
new `Span` and `HiddenMarker.Kind` case gets an arm in each exhaustive switch listed in the
header, and every arm draws nothing new:

- a colour arm returns what the nearest existing span returns (`.code` for the code markers,
  `.codeBlock` for the fence lines, `.blockquoteMarker` for callout lines);
- `hiddenKind` returns nil;
- re-validation returns false;
- `isInline` takes its final value (true for `inlineCode`, `highlight` and `embedChip`).

The fragment classes are empty subclasses that the delegate never returns yet.
`CalloutKind.colorToken` and `symbolName` are an extension in `CalloutStyle.swift`, outside
`Sources/Core`, because `ColorToken` is a design-system type that `perg` and `pergamenum-mcp`
do not compile (`sharedSources` globs `Sources/Core/**`). Pure types get
neutral stub bodies, never `fatalError`. `NoteTab.toggledCallouts` and the `OutlineInputs` fields
are stored but unread; `VaultController.toggleCallout` lives in the new `+Callouts` file
(`VaultController+Tabs.swift` is at 396 lines) with an empty body. `EmbedRendition.pending` gets
its `==` arm. Every arm that would need a decision is the coder's, in Tasks 4 to 7. Today's
drawing stays exactly as it is, so the existing suite stays green.

The hosted tests use the in-process family's harness, the one `TransclusionLayoutTests` and
`EditorDecorationSubstitutionTests` use: a `NoteTextView` in a window, `hidesMarkup` on, a theme
from the bundled light file, and layout fragments read back by offset.

- **`InlineChipTests.swift`** (pure, R-42):
  - `tagParts("#client-acme-srl")` is leading 8, trailing 8;
  - a tag outside the SPEC §4.4 pattern (`#idea`) is leading 1, the `#` only, with the rest
    accent;
  - `dateParts(">2026-10-14 10:30")` is leading 1 and trailing the rest;
  - a bare `2026-10-14` gives nil.
- **`EditorChipDrawingTests.swift`** (hosted, R-36, R-42):
  - inline code carries `.pergamenumChip` over its content, its backticks are concealed
    (`collapsedFont`, `.kern` > 0) off the caret, and revealed with the caret in the span;
  - `==x==` likewise with the highlight background;
  - `` `a==b==` `` carries no highlight;
  - a `#client-acme` chip's namespace is in `color.text.secondary` and its value in
    `color.accent.primary`;
  - a `>date` chip keeps its `>` visible;
  - the paragraph's displayed length equals its stored length in every case;
  - a paragraph with chips gets a `ChipLineFragment`, and `InlineChipPainter.rects` returns one
    rect per visual line the range crosses (a pill wrapping across two lines gives two);
  - N1's Cmd+click link attribute is still on the tag and date ranges.
- **`CodeFenceChromeTests.swift`** (hosted, R-37):
  - a closed `swift` fence's opening line gets a `CodeFenceFragment` with
    `.header(language: "swift", lineCount: 2)` and its closing line `.closing`;
  - the caret on either line reveals it (standard fragment, raw backticks);
  - body lines stay in the layout (`shouldEnumerate` true) and accept typed text;
  - an unclosed fence and a `pergamenum-view` fence get no fence fragment;
  - the delegate's `textView(_:menu:for:at:)` adds «Copia il blocco» for an index inside the fence
    and nothing outside it;
  - invoking the item puts exactly the body, no fences, on a private `NSPasteboard`, and the menu's
    other items (Copia, Incolla) are still there.
- **`QuoteBarDrawingTests.swift`** (hosted, R-39):
  - `QuoteGeometry.indent(level: 2, step: s)` is `2 * s` and `barOffsets(level: 3, …)` has three
    increasing values inside the indent;
  - a two-level quoted paragraph that wraps gets a `QuoteBarFragment` with `level == 2`, its text
    in `color.text.secondary`, its content origin at `indent(level: 2, …)`, concealed and revealed
    alike (R-14's invariant, re-asserted for the new drawing);
  - the bar spans the fragment's full height, so two consecutive quoted paragraphs leave no gap
    between bars (the rect union is contiguous).
- **`CalloutFoldTests.swift`** (pure and controller, R-38):
  - `isFolded(.fixed, toggled: true)` is false; `.folded` and `.open` flip with `toggled`;
  - `hiddenLines(in:toggled:)` returns the body-line offsets of `> [!avviso]- T\n> a\n> b` and
    nothing once its title offset is toggled;
  - a `+` callout hides its body only when toggled, and a no-sign callout never does;
  - `VaultController.toggleCallout` inserts and removes the offset in the focused tab's
    `toggledCallouts`, and the file is not dirtied.
- **`CalloutDrawingTests.swift`** (hosted, R-38):
  - a `> [!avviso]- Titolo` line gets a `CalloutTitleFragment` with kind `.warning` and
    `isFolded == true`;
  - its body lines are out of the layout through `shouldEnumerate`, on the same hidden-line set
    folded headings use;
  - a caret placed in a hidden body line is rescued to the title line;
  - an `[!faq]` callout has `colorToken == nil`, so it draws neutral;
  - the three body lines of an open callout get `QuoteBarFragment`s with pieces first, middle and
    last, and a one-line callout gets `only`;
  - a Workspace `CardTextView` colours a callout's title line in `color.callout.warning` and
    conceals nothing on it;
  - the title line's displayed and stored lengths are equal.
- **`EditorCommandTests.swift`**: an entry `callout` inserts `> [!note] ` with `cursorBack: 0`.
- **`EmbedPresentationTests.swift`** (pure, R-40):
  - `size(written: nil, column: 600)` is `defaultSize` clamped to 600;
  - `|300` keeps 300 at the default ratio, and `|300x200` gives 300×200;
  - a written width over the column clamps to it, keeping the ratio;
  - `of(target:isWholeLine:)` is `.drawn` for a whole-line `foto.png` or `a.pdf`, `.chip` for an
    inline `scheda.pdf` and for a whole-line `contratto.docx`, and `.transclusion` for `Nota`;
  - `symbolName` gives distinct symbols for PDF, image and an unknown type.
- **`EmbedDrawingTests.swift`** (hosted, extended, R-40):
  - before `ThumbnailStore` answers, a `![[foto.png|300]]` line already holds an `EmbedAttachment`
    with bounds width 300 (`.pending`), and the line height does not change when `.drawn` arrives
    for a written `WxH`;
  - a pending attachment has no resize handle (`handleColor == nil`);
  - an inline `![[scheda.pdf]]` is concealed except its name and carries a chip.
- **`TranscludedLineTests.swift` / `TranscludedLineFragmentWidthTests.swift`** (extended, R-40):
  - off the caret, the source line's characters are collapsed and the fragment's caption is
    `da «Nota» › Sezione`;
  - with the caret in the line the source shows raw;
  - `reservedHeight` is today's minus the removed header caption's height;
  - an unresolved transclusion is drawn as today.
- **`TableColumnMenuTests.swift`** (pure and hosted, R-41):
  - `entries(current: .leading)` is three aligns, with left ticked, then two sorts;
  - `edit(for: .align(.leading, isCurrent: true), column: 0)` is nil;
  - **hosted:** choosing «Allinea a destra» on column 1 of a grid commits once through
    `commitTable`, so the source's delimiter row reads `--:` there;
  - **hosted:** one `undoManager.undo()` restores the original text exactly, and the same holds for
    «Ordina A→Z»;
  - **hosted:** the column control (`editor-table-column-menu`) and a right-click on a header cell
    both offer the same entries.
- **`EditorDecorationSubstitutionTests.swift`**: each new substitution branch (inline code,
  highlight, fence lines, callout marker, embed chip, transclusion source) keeps the paragraph
  length.
- **`MarkdownStylerTests.swift` / `MarkdownStylerFixture.swift`**: N2's styler golden corpus (the
  file N2's plan names; `MarkdownStylerFixture.swift` today) gains one classed case per new span:
  - `==x==` gives `.highlight` plus two `.highlightMarker`;
  - `` `x` `` gives two `.inlineCodeMarker`;
  - a closed fence gives `.fenceOpening`/`.fenceClosing`, and an unclosed one neither;
  - `> [!tip]- T` gives `.calloutMarker(.tip, fold: .folded)` over its `markerLength`, and
    `.calloutBody(.tip)` per body line;
  - an inline `![[a.pdf|200]]` gives two `.embedChipMarker`.

### Task 4 — Pills and chips: inline code, highlights, tags and dates (R-36, R-42)
Owner: coder
Files:
- Sources/Features/Editor/MarkdownStyler.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/EditorDecorationDelegate+Chips.swift
- Sources/Features/Editor/MarkdownAttributedText.swift
- Sources/Features/Editor/InlineSpanReveal.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/InlineChip.swift
- Sources/Features/Editor/InlineChipPainter.swift
- Sources/Features/Editor/ChipLineFragment.swift
- Sources/Features/Editor/FoldedHeadingFragment.swift
- Sources/Features/Editor/MarkdownBlocksView.swift
- Sources/Features/Workspace/CardTextAttributes.swift
Tests: InlineChipTests.swift, EditorChipDrawingTests.swift, EditorDecorationSubstitutionTests.swift, MarkdownStylerTests.swift
Signatures:
- InlineChipPainter.rects(for:in:padding:) — static func rects(for range: NSRange, in fragment: NSTextLayoutFragment, padding: CGFloat) -> [CGRect]
- NSAttributedString.Key.pergamenumChip — static let pergamenumChip: NSAttributedString.Key
- InlineChip.tagParts(_:) — static func tagParts(_ tag: some StringProtocol) -> Parts?
- InlineChip.dateParts(_:) — static func dateParts(_ token: some StringProtocol) -> Parts?
Red: no

ADR-0087 §D5:

- **Styler.** It maps the shared inline parser's `.highlight` and code spans, which reach it
  through N2's mapping, to `.highlight` plus `.highlightMarker`s and to `.code` plus
  `.inlineCodeMarker`s. Each delimiter's range is read back from the source (a backtick run's
  length varies), never re-recognised.
- **Concealment.** `hiddenKind` maps the two marker spans to `.inlineCode`/`.highlight`. They
  collapse on the generic path with `.kern` equal to the chip padding, and are re-validated against
  the live characters (`` ` `` runs, `==`). Reveal is ADR-0037's span-grained path when its
  setting is on (`InlineSpanReveal` gains the two), paragraph-grained otherwise.
- **Attributes.** `MarkdownAttributedText` sets `.pergamenumChip` with an `InlineChip.Style`:
  - code: `color.code.inlineBackground`, text keeps `color.text.secondary` mono;
  - highlight: `color.highlight`;
  - tag: `color.accent.muted` background, `tagParts` splitting `color.text.secondary` from
    `color.accent.primary`;
  - date: `color.surface.sunken`, with `>` in `color.text.secondary` and the date in
    `color.task.scheduled`.
  Tags and dates get their `.kern` room on the characters either side. N1's link attribute on tag
  and date ranges is left exactly as N1 sets it.
- **Painting.** The delegate returns `ChipLineFragment` instead of the standard fragment for a
  paragraph whose substituted text carries `.pergamenumChip`. `FoldedHeadingFragment` calls
  `InlineChipPainter` before drawing its line. `QuoteBarFragment` and `CalloutTitleFragment` get
  the same call in Task 6, when they are given bodies. Radius is `radius.control`.
- **File length.** `EditorDecorationDelegate.swift` is past 800 lines: the chip branch of the
  substitution and the fragment choice live in `EditorDecorationDelegate+Chips.swift`.
- **Reading view.** `MarkdownBlocksView`'s inline renderer gives `.highlight` the
  `color.highlight` background and inline code the `color.code.inlineBackground` background, so
  the same span reads the same on both surfaces.
- **Cards.** `CardTextAttributes` colours highlight and code the same way. Cards conceal nothing
  new: `CardTextView.hiddenKind`'s `default: nil` stands (ADR-0029 §D17).

### Task 5 — Fence chrome and «Copia il blocco» (R-37)
Owner: coder
Files:
- Sources/Features/Editor/MarkdownStyler.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/EditorDecorationDelegate+FenceRendering.swift
- Sources/Features/Editor/CodeFenceFragment.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/NoteTextView+FenceMenu.swift
Tests: CodeFenceChromeTests.swift, EditorDecorationSubstitutionTests.swift, MarkdownStylerTests.swift, CodeSyntaxTests.swift
Signatures:
- FenceChrome.blocks(in:) — static func blocks(in text: String) -> [FenceChrome]
- FenceChrome.block(containing:in:) — static func block(containing utf16Offset: Int, in text: String) -> FenceChrome?
- CodeFenceFragment — final class CodeFenceFragment: NSTextLayoutFragment
- NoteTextView.Coordinator.textView(_:menu:for:at:) — func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu?
Red: no

ADR-0087 §D6:

- **Spans and concealment.** The styler emits `.fenceOpening(language:lineCount:)` and
  `.fenceClosing` from `FenceChrome.blocks(in:)`, beside today's `.codeBlock`/`.codeToken` spans,
  which keep colouring the body. `hiddenKind` maps them to the two block kinds, collapsed on the
  generic path with a minimum line height so the header row has height. This is
  `HorizontalRuleFragment`'s path; read how the rule line gets its height and reuse it.
- **Drawing.** The fragment choice, re-validated through `CodeFence.marks` on the element's own
  characters, returns `CodeFenceFragment`:
  - the header role draws the badge (the language in `font.caption` on `color.surface.sunken`,
    `radius.control`) and `lineCountLabel` in `color.text.tertiary`;
  - the closing role draws a hairline in `color.border.subtle`.
- **Reveal and body.** A caret on either line reveals it. Body lines get no marker.
- **Menu.** `NoteTextView+FenceMenu.swift` implements the delegate method on the coordinator. When
  `FenceChrome.block(containing: charIndex, in:)` answers, it appends a separator and «Copia il
  blocco», whose action writes `String(text[block.body])` as `.string` to `NSPasteboard.general`;
  otherwise it returns the menu unchanged.
- **Do not edit `CompletingTextView+Pasteboard.swift`** (protected). Its `menu(for:)` reaches
  `super.menu(for:)`, and AppKit asks the delegate from there. The first hosted test in
  `CodeFenceChromeTests` proves the route on this SDK. If it does not hold, stop and report rather
  than touching the protected file.

### Task 6 — Quotes and callouts in the editor, the reading view, cards and the slash menu (R-38, R-39)
Owner: coder
Files:
- Sources/Features/Editor/MarkdownStyler.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift
- Sources/Features/Editor/EditorDecorationDelegate+CalloutRendering.swift
- Sources/Features/Editor/QuoteBarFragment.swift
- Sources/Features/Editor/QuoteGeometry.swift
- Sources/Features/Editor/CalloutTitleFragment.swift
- Sources/Features/Editor/CalloutStyle.swift
- Sources/Features/Editor/CalloutFold.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/NoteTextView+Folding.swift
- Sources/Features/Editor/NoteTextView+Inputs.swift
- Sources/Features/Editor/NoteTextView+CalloutClick.swift
- Sources/Features/Editor/NoteTextView.swift
- Sources/Features/Editor/EditorColumn+Text.swift
- Sources/App/VaultController+Callouts.swift
- Sources/Features/Editor/EditorCommand.swift
- Sources/Features/Editor/MarkdownBlocksView.swift
- Sources/Features/Editor/MarkdownBlocksView+Quote.swift
- Sources/Features/Workspace/CardTextView+Callout.swift
- Sources/Features/Workspace/CardTextAttributes.swift
Tests: QuoteBarDrawingTests.swift, CalloutFoldTests.swift, CalloutDrawingTests.swift, EditorCommandTests.swift, EditorDecorationSubstitutionTests.swift, QuoteRenderingTests.swift, MarkdownReadingTests.swift
Signatures:
- CalloutFold.hiddenLines(in:toggled:) — static func hiddenLines(in text: String, toggled: Set<Int>) -> Set<Int>
- FoldController.apply(to:folded:hidesFrontmatter:theme:) — func apply(to textView: NSTextView, folded: Set<Int>, hidesFrontmatter: Bool = false, toggledCallouts: Set<Int> = [], theme: Theme)
- VaultController.toggleCallout(_:) — func toggleCallout(_ offset: Int)
- CalloutKind.colorToken — var colorToken: ColorToken? { get }
- QuoteGeometry.indent(level:step:) — static func indent(level: Int, step: CGFloat) -> CGFloat
Red: no

ADR-0087 §D7 and §D8.

**Quotes.**

- `quoteParagraph(at:storage:)` stops substituting `▏`. It collapses the `>` run, sets the
  paragraph style's indents from `QuoteGeometry.indent(level:step:)` and colours the text
  `color.text.secondary`.
- `step` is the quote content column ADR-0081 fixed; if it fixed none, it is `spacing.m`.
  Whichever applies, the content origin is equal concealed and revealed (N2's R-14 invariant,
  re-asserted in `QuoteBarDrawingTests`).
- The fragment choice returns `QuoteBarFragment` for a quote paragraph not revealed. It draws one
  bar per level at `barOffsets` in `color.quote.bar`, the fragment's full height, then calls
  `InlineChipPainter`, then draws the line.
- Update `QuoteRenderingTests.swift` where it asserts the `▏` glyph. Those assertions describe the
  amended ADR-0029 §D1 bullet; say so in the test's comment. Do not delete them.

**Callouts.**

- **Spans.** The styler emits `.calloutMarker(kind, fold:)` over `Callout.header(inLine:)`'s
  `markerLength` and `.calloutBody(kind)` per body line, from the shared parser's `.callout` block.
- **Title line.** Its marker collapses on a new block kind with re-validation through
  `Callout.header(inLine:)`. `CalloutTitleFragment` draws:
  - the card's top band (type colour at `CalloutStyle.backgroundOpacity`, `radius.card` corners);
  - the bar;
  - the symbol `CalloutKind.symbolName`;
  - the title in the type colour (semibold `font.prose`), or the Italian `label` when none is
    written;
  - a chevron when `fold != .fixed`.
- **Body lines.** They take `QuoteBarFragment` with `callout: (kind, piece)`, painting their band
  of the card in the type colour.
- **Neutral.** A `nil` `colorToken` means `color.quote.bar` for bar, icon and title, and
  `color.surface.sunken` for the band.
- **Fold.**
  - `FoldController.apply` unions `CalloutFold.hiddenLines(in:toggled:)` into the hidden-line set
    beside the heading folds and the frontmatter (ADR-0078), and `CaretRescue` applies. Its one
    call site, `NoteTextView+Coordinator.swift:185`, passes the tab's `toggledCallouts`; the new
    parameter defaults to empty, so no other caller changes.
  - `OutlineInputs` carries `toggledCallouts` and `onToggleCallout` from the focused `NoteTab`
    (`EditorColumn+Text.swift`).
  - `VaultController.toggleCallout` is `toggleFold`'s shape (`updateFocusedTab`), in its own file.
  - The `onClickInMargin` chain in `NoteTextView.swift` gains `coordinator.toggleCallout(at:in:)`
    after `unfold`, and it claims only a click on a title fragment's chevron.
  - The Diario and Oggi editors pass no `onToggleCallout` and draw the file's default.

**Slash entry.** `EditorCommand.editorEntries` gains `callout` («Callout», keywords `callout`,
`nota`, `avviso`, `note`, `warning`; symbol `exclamationmark.bubble`;
`.insert("> [!note] ", cursorBack: 0)`) after «Citazione». Delete the exclusion comment at
`EditorCommand.swift:41-45`, whose reason no longer holds.

**Reading view.**

- Replace Task 1's shims in `MarkdownBlocksView`. A nested quote draws per-level indentation and
  bars from `QuoteGeometry` in `color.quote.bar`, full height.
- A callout draws as the same card, always open, with the body rendered through the quote view.
- `MarkdownBlocksView+Quote.swift` holds both, so the 272-line view does not cross 400.

**Cards.** `CardTextView+Callout.swift` and `CardTextAttributes` colour a callout's title line in
its type colour and change nothing else on it (R-38). `CardTextView.swift` is at 403 lines and
gains no lines beyond an arm.

### Task 7 — Embed placeholder and chip, transclusion caption, table column menu (R-40, R-41)
Owner: coder
Files:
- Sources/Features/Editor/NoteTextView+Embeds.swift
- Sources/Features/Editor/EmbedAttachment.swift
- Sources/Features/Editor/EmbedPlaceholder.swift
- Sources/Features/Editor/EmbedPresentation.swift
- Sources/Features/Editor/EmbedRun.swift
- Sources/Features/Editor/NoteTextView+EmbedChip.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/NoteTextView.swift
- Sources/Features/Editor/EditorColumn+Text.swift
- Sources/Features/Editor/NoteTextView+Transclusion.swift
- Sources/Features/Editor/TranscludedLineFragment.swift
- Sources/Features/Editor/TableColumnMenu.swift
- Sources/Features/Editor/TableGridView.swift
- Sources/Features/Editor/TableGridView+ColumnMenu.swift
Tests: EmbedPresentationTests.swift, EmbedDrawingTests.swift, EmbedResolutionTests.swift, EmbedContextMenuTests.swift, TranscludedLineTests.swift, TranscludedLineFragmentWidthTests.swift, TransclusionLayoutTests.swift, TableColumnMenuTests.swift, TableGridCommitTests.swift, TableRenderingTests.swift
Signatures:
- EmbedPlaceholder.size(written:column:) — static func size(written: EmbedResize.Written?, column: CGFloat) -> CGSize
- EmbedPresentation.of(target:isWholeLine:) — static func of(target: String, isWholeLine: Bool) -> EmbedPresentation
- TransclusionCaption.text(note:section:) — static func text(note: String, section: String?) -> String
- TableColumnMenu.edit(for:column:) — static func edit(for entry: Entry, column: Int) -> TableEdit?
- NoteTextView.Coordinator.commitTable(_:at:in:) — func commitTable(_ edit: TableEdit, at offset: Int, in textView: NSTextView) -> Bool
Red: no

**Embeds (ADR-0087 §D9).**

- **Pending.** `EmbedTable` records `.pending(name:)` for a renderable embed whose render is in
  flight, instead of leaving it nil. `EmbedAttachment` sizes it through `EmbedPlaceholder` and
  `EmbedResize`'s clamp and draws a box in `color.surface.sunken` with the file name in
  `color.text.tertiary`. The `.drawn` completion replaces it through `setRenditions` as today. It
  gets no handle color, so ADR-0019 §D8's `guard case .drawn` refuses the handle.
- **Chips.** `EmbedPresentation.of` decides drawn, chip or transclusion. A `.chip`, inline or
  whole-line, is concealed by `.embedChip` except its name (the `|W` suffix included in the
  concealment), and carries `.pergamenumChip` with `symbolName` drawn by the painter in the
  leading kern room.
- **Click.** `NoteTextView+EmbedChip.swift` adds `previewChip(at:in:)` to the `onClickInMargin`
  chain. It claims only a plain click on a chip whose paragraph is not revealed, resolves the file
  through `VaultBoundary` (ADR-0041 §D1), and opens it with the column's existing Quick Look
  route (`previewURLs`/`isPreviewingEmbed`, `EditorColumn+Text.swift:40`).
- **Untouched:** `EmbedResize`, the handle and the `|W` write.

**Transclusion caption (§D10).**

- The substitution collapses a transclusion line's characters when it has a rendition and is not
  revealed. `TranscludedLineFragment` draws `TransclusionCaption.text` in the source row in
  `captionColor`.
- `TranscludedRendition` loses its header caption, and `reservedHeight` drops by that height
  (`NoteTextView+Transclusion.swift:200`).
- A click on the caption opens the note through `openTransclusion`, as the header did. An
  unresolved transclusion keeps today's drawing.

**Table column menu (§D11).**

- **Control.** `TableGridView+ColumnMenu.swift` adds a third column control
  (`editor-table-column-menu`, SF Symbol `ellipsis`) beside `addColumnButton`/`removeColumnButton`
  at `columnAnchor`. It sets the same `NSMenu` as each header cell's `menu`, both built from
  `TableColumnMenu.entries(current:)`, with titles «Allinea a sinistra», «Allinea al centro»,
  «Allinea a destra», «Ordina A→Z», «Ordina Z→A».
- **Commit.** An item sends `TableColumnMenu.edit(for:column:)` through the existing
  `commit(_:)`, then `onCommit`, then `commitTable`: one replacement, one undo step, ADR-0029 §D8's
  re-read. A nil edit, the current alignment, writes nothing.
- **Rendering.** The cells already render alignment (`TableGridView+Rendering.alignment`); verify
  the grid re-renders the new alignment after the reload, nothing more.

### Task 8 — SPEC (app) §5, the chain index, builds and the closing checks (R-43, R-44, R-45)
Owner: coder
Files:
- docs/20260811_Pergamenum_SpecApp.md
- CLAUDE.md
- docs/adr/0087-the-editor-draws-the-remaining-constructs.md
- TODO.md
Tests: NoteExportGoldenTests.swift
Signatures:
- MarkdownHTML.render(_:) — static func render(_ markdown: String) -> String
Red: no

- **SPEC (app) §5**, in Italian, per ADR-0087 §D1. The bullet «Costrutti che nascondono la loro
  sintassi» gains:
  - codice inline come pillola (backtick nascosti);
  - evidenziato `==testo==` (`==` nascosti; dentro il codice non è evidenziato);
  - intestazione del fence con linguaggio e numero di righe e riga di chiusura discreta, rivelate
    dal cursore, «Copia il blocco» nel menu contestuale;
  - callout `> [!tipo] Titolo`: parole chiave scritte in inglese (`note`, `tip`, `important`,
    `warning`, `caution`), alias italiani letti, etichette in italiano, tipo sconosciuto neutro,
    ripiegabile con `-`/`+` per tab, mai scritto nel file;
  - citazioni rientrate per livello con barra a tutta altezza;
  - embed con spazio riservato prima della miniatura e chip per gli embed in linea o non
    disegnabili (Anteprima con un clic);
  - didascalia «da «Nota» › Sezione» al posto della riga sorgente di una transclusione;
  - tag e date come chip.

  The «Una tabella GFM è una griglia vera» bullet gains the column menu (allineamento e
  ordinamento, ognuno un solo `Cmd+Z`). Mark the amendment with the date and ADR-0087, the way the
  2026-09-29 amendment is marked.
- **`CLAUDE.md`**: one Chain decision index line for ADR-0087, in the existing lines' shape.
- **ADR-0087** gets implementation notes for any departure from its text found while building.
  The status stays `proposed`. The flip to `accepted` names the merge commit and is the first docs
  change after the merge (`docs/adr/README.md` rule 2), so it is not in this PR.
- **`TODO.md`**: close the N5 ledger entry (its PG id as registered by `/project-tasks roadmap`).
  The PR body says "Closes #890" (R-44).
- **Builds (R-45):** `Pergamenum`, `perg` and `pergamenum-mcp`, each with the `xcodebuild … build`
  line from `CLAUDE.md`. N5 changes nothing under `Sources/MCPServer`, so `scripts/mcp-smoke.py`
  is not required. Say so in the PR body rather than skipping it silently.
- **Full suite:** the whole `PergamenumTests`, not only the new files. `scripts/uitests.sh
  --affected` at merge per `CLAUDE.md`. No GUI test is added.
- **Hand check on the Debug build** (pick it by `WorkspacePath`, `CLAUDE.md`), in light and dark,
  at a narrow and a wide window. Open the roadmap's acceptance note: inline code, a `swift` fence,
  `> [!avviso]-`, `==highlight==`, a nested quote, an inline `![[scheda.pdf]]`, a transclusion and
  a right-aligned column.
  - Every construct reads as such off the caret, and as its syntax with the caret in it.
  - The callout folds and unfolds without dirtying the tab.
  - «Copia il blocco» pastes the body.
  - «Ordina» and «Allinea» undo in one `Cmd+Z`.
  - File › Esporta nota (HTML and PDF) shows the highlight, the callout card and the nested
    quote. The PDF goes through `NSAttributedString(html:)`, so check `aside` and `mark` there by
    eye.

## Risks and HITL gates

- **N2 is a hard prerequisite.** If ADR-0082 lands with a different styler shape (a `Span` enum
  that is not kept, or a parser that hands the editor no ranges), Tasks 3 to 7's span plumbing must
  be re-planned against it. Do not start Task 3 until N2's plan and code are on `main`, and re-grep
  every switch site listed in the header first.
- **The delegate menu route** (`textView(_:menu:for:at:)` reached from the protected
  `menu(for:)`'s `super` call) is AppKit's documented behaviour, but it has not been measured in
  this editor. Task 3's first fence test measures it. If it fails, the fallback is a «Copia» button
  drawn in `CodeFenceFragment`'s header and claimed through `onClickInMargin`. That is a design
  change to bring back to Stefano, not to improvise.
- **Full-height bars across paragraph spacing.** Whether a TextKit 2 layout fragment's frame
  includes `paragraphSpacing` decides whether consecutive quote bars touch. `QuoteBarDrawingTests`
  asserts contiguity. If the frame excludes it, the bar extends by the paragraph's own
  `paragraphSpacing`, read from its style, never a constant.
- **Kerning for chip padding** changes glyph positions, not characters. Selection and caret
  hit-testing at a chip's edge must still land on the right character: covered by
  `EditorChipDrawingTests`, and look at it in the hand check.
- **Pratiche rows** render through `MarkdownBlocksView`, so email bodies with `>>` reply chains
  gain nested bars. This is expected (ADR-0087 consequences). Look at one real pratica in the hand
  check.
- **The export stylesheet** pins three page-level expectations (W01, W02, R-11). They are updated
  in Task 1 on purpose. A reviewer who sees them change elsewhere should treat it as a finding.
- **ADR reference check:** `scripts/check-adr-references.py` will flag ADR-0080 to ADR-0082
  citations until N1 and N2's ADRs are on `main`. They are, by the binding merge order, before this
  PR.
- **File length:** `EditorDecorationDelegate.swift`, `MarkdownStyler.swift` and
  `NoteTextView+Coordinator.swift` are already past the 400 warning. Every new branch goes in a
  `+Aspect.swift` file as listed. None may cross the 1000 error.
- **HITL:** the mockup PR's approval (before this plan starts); commit and push of each branch;
  the merge; the ADR status flip after it. No schema change, no deletion, no deploy, no new
  dependency, no externally provisioned resource.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE
