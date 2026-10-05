**Requirement set:** `SPEC.md`

# N2 code PR: the page, part one (markers in the gutter, a measured keystroke, one grammar)

- SPEC: root `SPEC.md`, Approved 2026-10-04, milestone N2 (issue #887, ledger `PG-385`; absorbs
  `PG-347`/#762). This PR satisfies R-13 to R-19.
- **Assumes N1 merged first** (`docs/plans/note-workflow-n1.md`), and the N2 mockup PR
  (`docs/plans/note-workflow-n2-mockup.md`) merged and approved on the Debug build. Planned
  against `48a2d912`; nothing below depends on an N1 detail. Where N1 and N2 touch the same files
  (`TokenKeys.swift`, both theme JSONs, `Theme.swift` for N1's `spacing.paragraph`;
  `ProseTypography.swift` and `MarkdownAttributedText.swift` for N1's paragraph spacing and H5/H6
  faces) the branch is cut after N1's merge and composes with what N1 left, never replaces it.
- ADR outcome: two new records, both Proposed, landing with this PR:
  `docs/adr/0081-block-markers-reveal-in-the-gutter.md` (R-13, R-14; amends ADR-0028 §D4 and
  ADR-0018 §D2 for list, heading and quote paragraphs) and
  `docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md` (R-15 to R-19; extends
  ADR-0077 §D1, closes `PG-347`, records the budget method, the two scoping changes and, once
  measured, the ceiling).
- Registered from the SPEC, not reopened: one PR per milestone; mockups first; the ceiling is set
  from measurement and ADR-0082 records it; concealment keeps the character count; one grammar;
  tokens only; no format, schema or protected-interface change; no GUI test in N2; the styler
  golden corpus is captured before the rewrite (test seam 2); the budget test runs in the suite the
  Stop hook runs (seam 3); the gutter reveal is proven by hosted tests (seam 4).
- Order, and why: Task 1 captures the baseline (corpus and budget) on untouched code, which both
  SPEC seams require. The grammar and the keystroke path (Tasks 2 to 4) go first because they are
  the larger risk and need no mockup answer; the gutter (Tasks 5 and 6) needs G1/G2's answers;
  surface parity (Task 7) is independent; the last measurement (Task 8) must see every change.
- Compiled language: each `Red: yes` tester task declares the types and stub bodies its tests are
  written against, so the target builds and the tests fail on behaviour, not on compilation.

## Call-sites of the contracts this PR changes (observable-contract rule)

Grepped on `48a2d912` with `rg` over `Sources` and `Tests`. Each is handled by the task named.

- `ListContinuation.renumbered(_:)`: `Sources/Features/Editor/NoteTextView+ListEditing.swift:62`
  (moves to the scoped form, Task 4); `Sources/Features/Workspace/CardTextView+ListEditing.swift:39`
  (stays, ADR-0082 §D6); `Tests/ListContinuationTests.swift:152-197` (stay green, the old function
  is unchanged); `Tests/NoteListEditingTests.swift:273` and `Tests/CardFormattingTests.swift:520`.
- `renumberLists(in:)`: `NoteTextView+Coordinator.swift:198`, `NoteTextView+ListEditing.swift:61`,
  `Tests/NoteListEditingTests.swift:275` (the pinned caret assertion moves 49 → 48, Task 2, gate
  G-caret); the card's own `renumberLists` (`CardTextView.swift:259`, `CardFormattingTests.swift:522`)
  is untouched.
- `growToFitTheText(_:revealingCaret:)`, signature unchanged, behaviour scoped:
  `NoteTextView+Coordinator.swift:209` and `:395`, `NoteTextView+Update.swift:70`;
  `Tests/EditorHeightTests.swift` (`stylingLeavesTheTextViewTallEnoughForWhatItDraws` and
  `theLastLineOfANoteIsInsideTheScrollableArea` restated, Task 2, gate G-caret;
  `typingAtTheEndOfANoteBringsTheCaretIntoView` unchanged).
- `horizontalInset(viewWidth:cap:minimum:isOn:)`, unchanged: its one caller
  (`NoteTextView+Coordinator.swift:600`) now feeds `EditorGutter.containerInset`;
  `Tests/ReadableWidthTests.swift` stays green as is. `minimumHorizontalInset` at
  `Sources/Features/Editor/NoteTextView.swift:94` (the initial inset) moves to the gutter-aware
  value (Task 6).
- `ListMarkerRendering.paragraphStyle(level:font:basedOn:)` gains defaulted `gutter:`/`hanging:`:
  its caller `EditorDecorationDelegate+ListRendering.swift`; `Tests/MarkupHidingListTests.swift:291`
  and `:310` and `Tests/ListIndentFontInvariantTests.swift:85-88` stay green through the defaults.
- "Revealed returns nil" tests: `Tests/MarkupHidingListTests.swift:185` changes meaning (Task 5);
  `Tests/MarkupHidingTests.swift:49` (heading) and `Tests/QuoteRenderingTests.swift:87` (quote) stay
  green because their delegate has no gutter (ADR-0081 §D6), and gain gutter siblings.
- `MarkdownStyler.spans(in:)`, signature and `Span` unchanged: consumers
  `NoteTextView+Coordinator.swift:303`, `MarkdownAttributedText.swift:55`,
  `CardTextView+Styling.swift:44`, `CardTextAttributes.swift:99`, `InlineSpanReveal.swift:28`; nine
  test files (`MarkdownStylerTests`, `MarkdownStylerBlockTests`, `MarkdownStylerFixture`,
  `ListNestingForwardPassTests`, `ViewQueryOutOfScopeTests`, `MarkdownAttributedTextTests`,
  `ListNestingTests`, `SpellCheckTests`, `ViewBlockSpanTests`) must stay green or show up as a
  classed corpus difference.
- `CardTextView.Coordinator.hiddenKind(for:)`: `Tests/InlineSpanRevealFenceTests.swift` reads this
  switch's source text (ADR-0037 §D8 amendment); the two new arms of Task 7 must keep it green.
- Tests asserting absolute horizontal positions in a `NoteTextView` fixture, which the gutter can
  move (reviewed in Task 5): `MessageAnchorEditorTests`, `CheckboxToggleTests`,
  `EditorControllerReadTimingRemainingTests`, `FoldBadgeClickTests`, `TranscludedLineTests`,
  `EmbedResizeGestureTests`, `CompletionPanelPlacementTests` and the fixture
  `EmbedEditorTestSupport`. `CardFoldBadgeTests` is a card (no gutter).

**Run the full `PergamenumTests` suite after Tasks 3, 4, 6 and 7, not only the new files**: the
styler and the base paragraph style feed every surface, and a contract change here breaks tests in
modules that only share it.

### Task 1 — Capture the baseline: styler golden corpus and restyle budget, before any change (R-15, R-18)
Owner: tester
Files:
- Tests/StylerGoldenCorpus.swift
- Tests/StylerGoldenTests.swift
- Tests/RestyleBudgetSupport.swift
- Tests/EditorRestyleBudgetTests.swift
- Tests/ScrolledEditorFixture.swift
- Tests/EditorHeightTests.swift
- scripts/editor-restyle-bench.sh
- docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md
Tests: StylerGoldenTests.swift, EditorRestyleBudgetTests.swift, EditorHeightTests.swift
Signatures:
- StylerGoldenCase — struct StylerGoldenCase: Sendable, CustomStringConvertible { let name: String; let markdown: String; let kind: Kind; let reason: String; let expected: String }
- StylerGoldenCase.Kind — enum Kind: Sendable { case a, b, c, unchanged }
- StylerGoldenCorpus.cases — static let cases: [StylerGoldenCase]
- StylerGoldenCorpus.render — static func render(_ text: String) -> String
- SyntheticNote.make — static func make(bytes: Int, withFences: Bool) -> String
- RestyleBudget.Case — struct Case: Hashable, Sendable, CustomStringConvertible { let bytes: Int; let withFences: Bool }
- RestyleBudget.ceilingMilliseconds — static let ceilingMilliseconds: [RestyleBudget.Case: Double]
- RestyleBudget.measureKeystroke — @MainActor static func measureKeystroke(on editor: ScrolledEditor, runs: Int) -> (cpuMilliseconds: Double, wallMilliseconds: Double)
- ScrolledEditor — @MainActor struct ScrolledEditor { let textView: CompletingTextView; let coordinator: NoteTextView.Coordinator; let window: NSWindow }
- editorInAWindow — @MainActor func editorInAWindow(_ body: String, size: CGSize = CGSize(width: 600, height: 700)) -> ScrolledEditor
- MarkdownStyler.spans — static func spans(in text: String) -> [MarkdownStyler.StyledRange] (relied on)
- NoteTextView.Coordinator.hiddenKind — static func hiddenKind(for span: MarkdownStyler.Span) -> HiddenMarker.Kind? (relied on)
- NoteExportGoldenCorpus.bodies — static let bodies: [ExportGoldenCase] (relied on)
- scripts/editor-restyle-bench.sh — `scripts/editor-restyle-bench.sh` (no arguments; runs only the budget suite through xcodebuild, prints one row per size and variant from the `restyle-budget` lines, exits with xcodebuild's status)
Red: no

Everything in this task runs on the code as it stands; nothing under `Sources` changes.

**Corpus (ADR-0082 §D3).** `StylerGoldenCorpus.render(_:)` turns `MarkdownStyler.spans(in:)` into
canonical text: one line per span, `start..<end <span>` in UTF-16 offsets, sorted by start, end and
the span's description, followed by the hidden-marker kinds `NoteTextView.Coordinator.hiddenKind(for:)`
derives for each. The inputs are every `NoteExportGoldenCorpus.bodies` markdown verbatim plus the
editor cases ADR-0082 §D3 lists (S-numbered, at least the constructs named there, including
`file_name_here`, `2 * 3 * 4`, `>2026-10-04 riunione` at line start, `> 2026-10-04` with a space,
tabs and spaces in nested lists, every task state, a view block, a table, frontmatter and a message
anchor). Every `expected` is captured by running `render` on this base, never typed by hand; every
case starts as `.unchanged` with an empty reason. `StylerGoldenTests` asserts each case and, as the
export corpus does, that no case is `.c`.

**Fixture.** Move `EditorHeightTests`'s private `editorInAWindow` and its `Editor` struct, unchanged
in behaviour, into `Tests/ScrolledEditorFixture.swift` as `editorInAWindow`/`ScrolledEditor`, with
`textView.delegate = coordinator` added so `insertText` drives the real delegate path. The three
`EditorHeightTests` stay as they are and must stay green here.

**Budget (ADR-0082 §D5).** `SyntheticNote.make` is deterministic (no randomness, no dates from the
clock). `measureKeystroke` inserts `"x"` at the middle of the text with
`insertText(_:replacementRange:)`, times it with `clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`
and with `ContinuousClock`, after one warm-up, and returns the minimum of `runs`. The suite is one
`@MainActor` struct, `.serialized`, with one test per size and variant (K = 5 at 50 and 200 KB,
K = 3 at 1 MB), each printing `restyle-budget size=<bytes> variant=<prose|fences> cpu_ms=<x>
wall_ms=<y> runs=<K>` and asserting `cpu_ms <= ceilingMilliseconds[case]`. Run it three times on a
quiet machine, record the minimum of the three in ADR-0082 §D9's "Before" column with the Mac model
and macOS build, and set each provisional ceiling to three times that number, rounded up, with a
comment naming ADR-0082 §D9 as the place the final value is decided. Print the suite's own total
wall time too: if it exceeds 30 s on this machine, say so in the report (it then runs every turn).

### Task 2 — Red tests for the token layer, the scoped renumber and the scoped grow (R-16, R-17, R-18)
Owner: tester
Files:
- Sources/Core/Markdown/MarkdownTokens.swift
- Sources/Core/Editor/ListContinuation.swift
- Sources/Features/Editor/NoteTextView+ListEditing.swift
- Tests/MarkdownTokensTests.swift
- Tests/MarkdownStylerTests.swift
- Tests/NoteExportGoldenCorpus.swift
- Tests/ListContinuationTests.swift
- Tests/NoteListEditingTests.swift
- Tests/EditorGrowToFitScopeTests.swift
- Tests/EditorHeightTests.swift
Tests: MarkdownTokensTests.swift, MarkdownStylerTests.swift, NoteExportGoldenTests.swift, ListContinuationTests.swift, NoteListEditingTests.swift, EditorGrowToFitScopeTests.swift, EditorHeightTests.swift
Signatures:
- MarkdownLineToken — struct MarkdownLineToken: Equatable, Sendable { let kind: Kind; let line: Range<String.Index>; let indent: Range<String.Index>?; let marker: Range<String.Index>?; let content: Range<String.Index> }
- MarkdownLineToken.Kind — enum Kind: Equatable, Sendable { case blank, paragraph, heading(level: Int), listItem(ordered: Bool, level: Int), task(state: TaskItem.State, level: Int), quote(level: Int), rule, frontmatter, fenceOpen(language: String?), fenceBody, fenceClose, tableRow, messageAnchor }
- MarkdownInlineToken — struct MarkdownInlineToken: Equatable, Sendable { let kind: Kind; let range: Range<String.Index>; let delimiters: [Range<String.Index>]; let target: Range<String.Index>? }
- MarkdownInlineToken.Kind — enum Kind: Equatable, Sendable { case code, strong, emphasis, strikethrough, wikilink, embed, link, tag, scheduled, due, annotation }
- MarkdownBlockParser.lineTokens — static func lineTokens(in text: String) -> [MarkdownLineToken]
- MarkdownInlineParser.tokens — static func tokens(in text: Substring) -> [MarkdownInlineToken]
- ListContinuation.Renumbering — struct Renumbering: Equatable, Sendable { let range: NSRange; let replacement: String; func mapping(_ location: Int) -> Int }
- ListContinuation.renumbered(_:touching:) — static func renumbered(_ text: String, touching edited: NSRange) -> ListContinuation.Renumbering?
- NoteTextView.Coordinator.renumberLists — func renumberLists(in textView: NSTextView, touching edited: NSRange? = nil)
- NoteTextView.Coordinator.growToFitTheText — func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false) (relied on, unchanged)
- editorInAWindow — @MainActor func editorInAWindow(_ body: String, size: CGSize) -> ScrolledEditor (relied on)
Red: yes

Declarations with stub bodies (`[]`, `nil`, the identity mapping; `renumberLists(in:touching:)`
keeps today's whole-document body and ignores `touching`), so the target builds and only behaviour
is red. The token types sit in `Sources/Core/Markdown/MarkdownTokens.swift`, Foundation only: the
file is compiled into `perg` and `pergamenum-mcp` by the `Sources/Core/**` glob, so build both
schemes once (`xcodebuild ... -scheme perg build`, `-scheme pergamenum-mcp build`). The field names
above are the contract the tests use; refine them here if a test shows a better shape, and record
the change in the task report, since Task 3 implements against this file.

Tests, all red until Task 3 or Task 4:

- `MarkdownTokensTests`: per line kind, the marker, indent and content ranges, the list level
  matching `ListNesting.levels`; inline tokens with their delimiter ranges; precedence (code before
  emphasis, a link label parsed recursively); the flanking rule (`file_name_here` and `2 * 3 * 4`
  give no emphasis token); the app tokens (`#tag`, `>2026-10-04`, `!2026-10-04`, `@annotation`); a
  line starting `>2026-10-04` is a paragraph with a scheduling token, `> 2026-10-04` a quote
  (ADR-0082 §D4); and the projection property: for every `NoteExportGoldenCorpus` input,
  `MarkdownInlineParser.spans`/`MarkdownBlockParser.blocks` equal what they return today
  (captured, as in Task 1, before the change).
- `MarkdownStylerTests`: `file_name_here` yields no `.italic` span (PG-347); `2 * 3 * 4` yields no
  emphasis.
- `NoteExportGoldenCorpus`: one new case for `>2026-10-04 riunione` at line start, kind `.a`,
  reason "ADR-0082 §D4", expected bytes written from the decision (a paragraph, not a quote).
- `ListContinuationTests`: `renumbered(_:touching:)` covers only the run holding the edit when two
  runs exist; a deleted separator line merges two runs and both renumber; a nested run is renumbered
  and its parent left alone when only the child was edited; `mapping` moves a caret after a shrunk
  marker by the shrink and leaves a caret before the range alone; `nil` when nothing changes.
- `NoteListEditingTests`: `renumberListsAfterARunsTrailingItemShrinksLeavesTheCaretOneCharacterAhead`
  asserts 48, and its name and comment are corrected to say the gap is closed (ADR-0082 §D6, gate
  G-caret, the change the test's own comment asks for); a new test edits run A in a note with runs A
  and B and records, through an `NSTextStorageDelegate` on the fixture, that the renumber's edited
  range lies inside run A; `deletingAMiddleItemOfAnOrderedRunRenumbersTheRestAndOneUndoRestoresBoth`
  stays as is and must stay green (one edit, one undo step).
- `EditorGrowToFitScopeTests` (new, on `editorInAWindow`): a note of 3000 paragraphs, a keystroke at
  the top, then the layout fragment at the document's end is not `.layoutAvailable` (no
  whole-document layout); typing at the end and in the middle keeps the caret rectangle inside
  `visibleRect`; after a keystroke at the top, `scrollToEndOfDocument(nil)` then the last line's
  fragment `maxY` is within the text view's frame.
- `EditorHeightTests`: `stylingLeavesTheTextViewTallEnoughForWhatItDraws` and
  `theLastLineOfANoteIsInsideTheScrollableArea` restated as ADR-0082 §D7 says: after the keystroke,
  bring the end into view, then assert. Each keeps a comment naming the 187 pt defect it guards and
  why the precondition moved. These two may stay green before Task 4; they are restated here so
  Task 4 does not have to touch a test.

### Task 3 — The shared token layer, the projections, and the styler over them (R-18)
Owner: coder
Files:
- Sources/Core/Markdown/MarkdownTokens.swift
- Sources/Core/Markdown/MarkdownInline.swift
- Sources/Core/Markdown/MarkdownBlocks.swift
- Sources/Features/Editor/MarkdownStyler.swift
- Tests/StylerGoldenCorpus.swift
Tests: StylerGoldenTests.swift, MarkdownTokensTests.swift, MarkdownStylerTests.swift, MarkdownStylerBlockTests.swift, NoteExportGoldenTests.swift, ListNestingTests.swift, ListNestingForwardPassTests.swift, ViewBlockSpanTests.swift, ViewQueryOutOfScopeTests.swift, SpellCheckTests.swift, MarkdownAttributedTextTests.swift, InlineSpanRevealFenceTests.swift
Signatures:
- MarkdownBlockParser.lineTokens — static func lineTokens(in text: String) -> [MarkdownLineToken] (relied on)
- MarkdownInlineParser.tokens — static func tokens(in text: Substring) -> [MarkdownInlineToken] (relied on)
- MarkdownInlineParser.spans — static func spans(in text: String) -> [MarkdownSpan] (unchanged signature, now a projection)
- MarkdownBlockParser.blocks — static func blocks(in body: String) -> [MarkdownBlock] (unchanged signature, now a projection)
- MarkdownStyler.spans — static func spans(in text: String) -> [MarkdownStyler.StyledRange] (unchanged signature)
Red: no

ADR-0082 §D1, §D2 and §D4. Move the inline scanner's rules into `tokens(in:)` with ranges and make
`spans(in:)` project them (app tokens as plain text). Make the block `Accumulator` consume
`lineTokens(in:)`. Fences through `CodeFence`, tables through `GFMTable`, frontmatter through
`NoteFrontmatter`, anchors through `PraticaEntryAnchor`, wikilinks through `WikilinkParser`, list
levels through `ListNesting.levels`, task states through `TaskParser.state(for:)`, the line-start
date through the same `CalendarDate(iso:)` test the styler uses today (`MarkdownStyler.swift:630`).
Then rewrite `MarkdownStyler.spans(in:)` as a mapping from tokens to the unchanged `Span` cases,
keeping its `CodeSyntax` pass inside fences and its view-block runs, and delete its private
recognisers. `_` delimiters stay unconcealed (ADR-0082 §D2). `MarkdownStyler.swift` should shrink;
if any file crosses SwiftLint's `file_length`, split by aspect (`Type+Aspect.swift`, ADR-0045's
rule).

Then classify the corpus: run `StylerGoldenTests`, and for every case whose output changed set its
kind and a one-line reason, re-capturing `expected` only for `.a` and `.b`. A difference that is
neither a styler defect nor a deliberate choice is `.c`: fix the parser or the mapping until it is
gone, never re-capture it. The export corpus must stay byte-identical except the one case Task 2
added. Build `perg` and `pergamenum-mcp` before reporting. The classed diff is read by the person at
gate G-corpus.

### Task 4 — Scope the keystroke: renumber the edited run, lay out the caret and the viewport (R-16, R-17)
Owner: coder
Files:
- Sources/Core/Editor/ListContinuation.swift
- Sources/Features/Editor/NoteTextView+ListEditing.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
Tests: ListContinuationTests.swift, NoteListEditingTests.swift, EditorGrowToFitScopeTests.swift, EditorHeightTests.swift, CardFormattingTests.swift, EditorRestyleBudgetTests.swift, ViewBlockRenderingTests.swift, TableCaretTests.swift
Signatures:
- ListContinuation.renumbered(_:touching:) — static func renumbered(_ text: String, touching edited: NSRange) -> ListContinuation.Renumbering? (relied on)
- NoteTextView.Coordinator.renumberLists — func renumberLists(in textView: NSTextView, touching edited: NSRange? = nil) (relied on)
- NoteTextView.Coordinator.textView(_:shouldChangeTextIn:replacementString:) — func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool
- NoteTextView.Coordinator.growToFitTheText — func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false) (unchanged signature)
Red: no

ADR-0082 §D6 and §D7.

Renumbering: implement `renumbered(_:touching:)` on the existing private run helpers (`orderedRun`,
`renumberEdit`), widening the edit by one line each side; keep `renumbered(_:)` exactly as it is for
the card. The coordinator records the edited range in post-edit coordinates from
`textView(_:shouldChangeTextIn:replacementString:)` (always returning `true`, never rejecting an
edit), consumes it in `textDidChange` before `renumberLists` replaces anything (the replace itself
calls the same delegate method), and passes it as `touching`; `nil` means the whole document, which
is also the fallback for an undo or a programmatic replace. Replace only `Renumbering.range`
through `replaceAtomically`, inside the keystroke's undo group, and set the caret through
`mapping`.

Grow to fit: ensure layout for the caret fragment's text range and the viewport's range, never
`documentRange`; keep the height comparison and `layoutViewport()`; rewrite the doc comment's last
paragraph, which today defends the whole-document layout, to say what is laid out now and why, and
keep its history of the three failed alternatives. The folding, transclusion and view-block passes
that hand `growToFitTheText` around (`:395`, `NoteTextView+ViewBlocks.swift`) keep calling it
unchanged.

Run `EditorRestyleBudgetTests` and report its numbers next to Task 1's; do not change a ceiling.
If `EditorGrowToFitScopeTests` cannot be made green without laying out the whole document, stop
and report: the fallbacks of ADR-0082 §D7 are a decision for gate G-grow, not for this task.

### Task 5 — Red tests for the gutter and for surface parity (R-13, R-14, R-19)
Owner: tester
Files:
- Sources/DesignSystem/TokenKeys.swift
- Sources/DesignSystem/Theme.swift
- Resources/Themes/pergamenum-light.json
- Resources/Themes/pergamenum-dark.json
- Sources/DesignSystem/ProseTypography.swift
- Sources/Features/Editor/EditorGutter.swift
- Sources/Features/Editor/ListMarkerRendering.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/MarkdownAttributedText.swift
- Sources/Features/Editor/ViewQuerySource+Live.swift
- Sources/Features/Today/TodayView.swift
- Sources/Features/Diary/DiaryView.swift
- Tests/EditorGutterTests.swift
- Tests/GutterRevealGeometryTests.swift
- Tests/MarkupHidingListTests.swift
- Tests/QuoteRenderingTests.swift
- Tests/CardBlockMarkerTests.swift
- Tests/DailySurfaceQueriesTests.swift
- Tests/DesignSystemTests.swift
Tests: EditorGutterTests.swift, GutterRevealGeometryTests.swift, MarkupHidingListTests.swift, QuoteRenderingTests.swift, CardBlockMarkerTests.swift, DailySurfaceQueriesTests.swift, DesignSystemTests.swift
Signatures:
- SpacingToken.gutter — case gutter = "spacing.gutter"
- EditorGutter.containerInset — static func containerInset(readableInset: CGFloat, gutter: CGFloat) -> CGFloat
- EditorGutter.indented — static func indented(_ style: NSParagraphStyle?, gutter: CGFloat) -> NSParagraphStyle
- EditorGutter.hangingIndent — static func hangingIndent(column: CGFloat, marker: CGFloat) -> CGFloat
- EditorGutter.quoteColumn — static func quoteColumn(level: Int, font: NSFont, gutter: CGFloat) -> CGFloat
- EditorGutter.columnSpan — static func columnSpan(containerWidth: CGFloat, padding: CGFloat, style: NSParagraphStyle?) -> (leading: CGFloat, width: CGFloat)
- ListMarkerRendering.paragraphStyle — static func paragraphStyle(level: Int, font: NSFont, basedOn: NSParagraphStyle? = nil, gutter: CGFloat = 0, hanging: CGFloat? = nil) -> NSParagraphStyle
- ListMarkerRendering.contentColumn — static func contentColumn(level: Int, font: NSFont, gutter: CGFloat) -> CGFloat
- ProseTypography.gutterMarker — static func gutterMarker(_ theme: Theme) -> NSFont
- EditorDecorationDelegate.gutter — nonisolated(unsafe) var gutter: CGFloat
- EditorDecorationDelegate.markerFont — nonisolated(unsafe) var markerFont: NSFont?
- MarkdownAttributedText.StyleContext.init — init(theme: Theme, links: Bool, gutter: CGFloat = 0)
- ViewQuerySource.live — @MainActor static func live(for vault: VaultController) -> ViewQuerySource
- TodayView.editorInputs — @MainActor static func editorInputs(for vault: VaultController, notePath: String) -> NoteTextView.VaultInputs
- DiaryView.editorInputs — @MainActor static func editorInputs(for vault: VaultController, notePath: String) -> NoteTextView.VaultInputs
- CardTextView.Coordinator.hiddenKind — static func hiddenKind(for styled: MarkdownStyler.StyledRange) -> HiddenMarker.Kind? (relied on)
Red: yes

Starts only after the mockup gate: the gutter value, the heading marker face, the quote step and
the `H2` badge answer come from G1/G2 and are written into this task's report before anything
else. The token goes into `SpacingToken`, both theme JSONs and `Theme.emergency`'s spacings (a key
missing from the emergency palette crashes the test process rather than failing a test, PG-225),
with the approved value. Stubs: `EditorGutter` returns `0`/the input style/`(0, containerWidth)`,
`ListMarkerRendering.paragraphStyle` keeps today's body and ignores the two new parameters,
`gutterMarker` returns the caption face, the two delegate properties default to `0`/`nil`,
`StyleContext` ignores `gutter`, `ViewQuerySource.live` returns a source with no rows and
generation `0`, the two `editorInputs` return today's inputs (no `queries`), and the two views call
them so the views' own code is the code under test. `DesignSystemTests` gains the new key in
whatever list of keys it checks in both themes.

Tests, all red until Task 6 or Task 7:

- `EditorGutterTests` (pure): `containerInset` is `max(0, readableInset − gutter)` at 24, 48 and 300;
  `indented` sets first/head indent to the gutter and `tailIndent` to its negative and composes onto
  an incoming `lineHeightMultiple`; `hangingIndent` clamps at zero; `contentColumn` is
  `gutter + 1.5 em × level + 0.75 em` with the level clamped to 1...6; `columnSpan` excludes both
  indents; and the gutter of `Theme.emergency` holds `###### ` measured in `gutterMarker`'s face
  (ADR-0081 §D4).
- `GutterRevealGeometryTests` (in-process, a styled `NoteTextView` coordinator on an offscreen
  scrolled fixture, the reveal set driven through `EditorDecorationDelegate.apply(revealedParagraphs:)`):
  the x of the first content character, read through `enumerateTextSegments`, is equal within
  0.5 pt concealed and revealed for bullet, ordered (`1.` and `10.`) and task items at levels 1 to
  6 (R-13), and for headings H1 to H6 and quotes at levels 1 to 3 (R-14), each at a narrow view
  (the container inset from `containerInset(readableInset: 24, …)`) and a readable one (a 1200 pt
  view); a wrapped list item's second line starts at the same x as its first line's content; a task
  line's content x is the same in both states (ADR-0081 §D2). If G2 approved the badge: a concealed
  heading's layout fragment draws in the gutter and a revealed one does not.
- `MarkupHidingListTests`: `theHookReturnsNilForARevealedListParagraph` is replaced by
  `aRevealedListParagraphKeepsItsStyleAndHangsItsSourceMarker` (the revealed paragraph is not nil,
  keeps the concealed twin's `headIndent`, shows `-` not `•`, keeps the indentation run collapsed);
  the replaced test's name and reason go in the task report (ADR-0081 §D2 amends the behaviour it
  pinned). The arithmetic tests at `:291` and `:310` are untouched.
- `QuoteRenderingTests`: a gutter sibling of `theHookReturnsNilForARevealedBlockquoteParagraph`
  (with a gutter, a revealed quote hangs `> > ` to `quoteColumn`); the existing test stays, since a
  delegate with no gutter keeps returning `nil` (ADR-0081 §D6).
- `CardBlockMarkerTests`: the card's `hiddenKind` maps `.blockquoteMarker` to `.blockquote` and
  `.horizontalRule` to `.rule`, and still maps `.tableRun` and `.viewBlockRun` to `nil` (ADR-0029
  §D17); a card's quote paragraph keeps the card's `lineHeightMultiple`; a `---` paragraph in a card
  is laid out by a `HorizontalRuleFragment`.
- `DailySurfaceQueriesTests`: `TodayView.editorInputs` and `DiaryView.editorInputs` carry a non-nil
  `queries`, whose generation equals `EditorColumnView.viewQueryGeneration(for:)` for the same
  controller (the controller built as `IndexGenerationFollowUpTests` builds one).

Review, do not pre-emptively edit, the absolute-x tests listed in the call-site section: run them
against a stub that applies the token's gutter, and restate only those whose assertion is about an
absolute x the gutter legitimately moves, each with its reason in the report.

### Task 6 — The gutter column, and list, heading and quote markers hanging in it (R-13, R-14)
Owner: coder
Files:
- Sources/Features/Editor/EditorGutter.swift
- Sources/Features/Editor/ListMarkerRendering.swift
- Sources/Features/Editor/EditorDecorationDelegate.swift
- Sources/Features/Editor/EditorDecorationDelegate+ListRendering.swift
- Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift
- Sources/Features/Editor/EditorDecorationDelegate+HeadingRendering.swift
- Sources/Features/Editor/MarkdownAttributedText.swift
- Sources/Features/Editor/NoteTextView.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/HorizontalRuleFragment.swift
- Sources/Features/Editor/TranscludedLineFragment.swift
- Sources/Features/Editor/NoteTextView+Transclusion.swift
- Sources/Features/Editor/EmbedResize.swift
- Sources/Features/Editor/FoldedHeadingFragment.swift
- Sources/DesignSystem/ProseTypography.swift
Tests: EditorGutterTests.swift, GutterRevealGeometryTests.swift, MarkupHidingListTests.swift, MarkupHidingTests.swift, QuoteRenderingTests.swift, ListIndentFontInvariantTests.swift, ReadableWidthTests.swift, EditorDecorationSubstitutionTests.swift, TranscludedLineFragmentWidthTests.swift, TranscludedLineTests.swift, EmbedResizeGestureTests.swift, ViewBlockRenderingTests.swift, FoldBadgeClickTests.swift, MessageAnchorEditorTests.swift
Signatures:
- EditorGutter — enum EditorGutter (relied on, declared in Task 5)
- ListMarkerRendering.paragraphStyle — static func paragraphStyle(level: Int, font: NSFont, basedOn: NSParagraphStyle? = nil, gutter: CGFloat = 0, hanging: CGFloat? = nil) -> NSParagraphStyle (relied on)
- EditorDecorationDelegate.headingParagraph — func headingParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph?
- NoteTextView.Coordinator.applyReadableWidth — func applyReadableWidth(to textView: NSTextView) (unchanged signature)
Red: no

ADR-0081 §D1 to §D7, with G1/G2's answers. In order:

1. Base style: `StyleContext` composes `EditorGutter.indented` onto its base when `gutter > 0`;
   `applyStyling` passes `parent.theme.spacing(.gutter)` and pushes `gutter`, `markerFont`
   (`ProseTypography.gutterMarker`) onto the delegate beside `checkboxFont`.
   `applyReadableWidth` assigns `EditorGutter.containerInset(readableInset: horizontalInset(...),
   gutter:)`; the initial inset at `NoteTextView.swift:94` uses the same function. The card
   (`CardTextView`) passes no gutter.
2. Lists: `contentColumn` and the measured hanging width (the displayed run `• `, `- ` or the
   ordinal, measured in `proseFont`, never in the run's own face: `ListIndentFontInvariantTests`
   records why), memoised per run and face on the delegate. `listParagraph` stops returning `nil`
   when revealed: it applies the style, collapses the indentation run, and substitutes the glyph
   only when concealed.
3. Quotes: the same shape with `quoteColumn`, only when `gutter > 0`.
4. Headings: a new `EditorDecorationDelegate+HeadingRendering.swift` branch, ahead of the generic
   collapse in the hook, active only when `gutter > 0` and the paragraph is revealed: the `#` run in
   `markerFont`, `firstLineHeadIndent = hangingIndent(column: gutter, marker: w)`. If G2 approved
   the badge, one drawing helper used by the heading's fragment and by `FoldedHeadingFragment`, for
   concealed headings only; if not, skip this sub-step and leave `FoldedHeadingFragment` untouched.
5. Full-width decorations: the rule and transcluded-line fragments read `columnSpan` from their own
   paragraph's style at drawing time; `NoteTextView+Transclusion.swift:119` and
   `EmbedResize.swift:62` use it with the gutter the coordinator already resolves. If
   `GutterRevealGeometryTests` or `ViewBlockRenderingTests` show a table or view-block attachment
   wider than the column, size it from `columnSpan` too (ADR-0081 §D7).

Every substitution keeps the paragraph's length (`EditorDecorationSubstitutionTests` stays green).
Hand check G3 on the Debug build (`CLAUDE.md`'s DerivedData recipe picks this worktree's build):
Arrow-down through a ten-item nested list, H1 to H6 and a two-level quote, narrow and readable,
Nota, Oggi and Diario, light and dark; no glyph moves horizontally.

### Task 7 — Oggi and Diario render view fences; cards conceal quotes and rules (R-19)
Owner: coder
Files:
- Sources/Features/Editor/ViewQuerySource+Live.swift
- Sources/Features/Editor/EditorColumn+Text.swift
- Sources/Features/Today/TodayView.swift
- Sources/Features/Diary/DiaryView.swift
- Sources/Features/Workspace/CardTextView.swift
- Sources/Features/Workspace/CardTextView+Styling.swift
Tests: DailySurfaceQueriesTests.swift, CardBlockMarkerTests.swift, IndexGenerationFollowUpTests.swift, ViewBlockQuerySourceTests.swift, ViewBlockOutOfScopeTests.swift, CardConcealmentTests.swift, CardRoundTripTests.swift, InlineSpanRevealFenceTests.swift
Signatures:
- ViewQuerySource.live — @MainActor static func live(for vault: VaultController) -> ViewQuerySource
- EditorColumnView.viewQuerySource — var viewQuerySource: ViewQuerySource (unchanged, now forwards to `ViewQuerySource.live(for:)`)
- TodayView.editorInputs — @MainActor static func editorInputs(for vault: VaultController, notePath: String) -> NoteTextView.VaultInputs
- DiaryView.editorInputs — @MainActor static func editorInputs(for vault: VaultController, notePath: String) -> NoteTextView.VaultInputs
- CardTextView.Coordinator.hiddenKind — static func hiddenKind(for styled: MarkdownStyler.StyledRange) -> HiddenMarker.Kind?
Red: no

ADR-0082 §D8. Move the body of `EditorColumnView.viewQuerySource` into `ViewQuerySource.live(for:)`
and forward to it; `viewQueryGeneration(for:)` stays where `IndexGenerationFollowUpTests` reads it.
The factory is an extension in its own file under `Sources/Features/Editor`, not in
`Sources/Features/Views/ViewQuerySource.swift`, whose header says the renderer has no vault behind
it and must not grow one; correct the "still the app's only `ViewQuerySource`" sentence in
`EditorColumn+Text.swift`'s doc comment, which three surfaces now make false.
`TodayView` and `DiaryView` build their `VaultInputs` through `editorInputs`, which sets `queries`;
everything else they pass today (drop, paste, thumbnails) is kept, and `onEditQuery` and
`transclusions` stay unset (ADR-0082 §D8 names the missing transclusions as a follow-up). The
card's `hiddenKind` gains the two arms; `CardTextView+Styling.swift` pushes `ruleColor` from
`color.borderSubtle` as the note coordinator does (`NoteTextView+Coordinator.swift:344`) and the
quote paragraph composes onto the card's own paragraph style. Keep the `default: nil` arm, which
is ADR-0029 §D17's seam and what `InlineSpanRevealFenceTests` reads.

Hand check on the Debug build: a `pergamenum-view` fence in today's daily note renders in Oggi and
in the Diario; a card holding `> citazione` and `---` conceals both and draws the rule.

### Task 8 — Re-measure, fix the ceiling, and close the gates (R-15, R-17)
Owner: tester
Files:
- Tests/RestyleBudgetSupport.swift
- docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md
- docs/adr/0081-block-markers-reveal-in-the-gutter.md
Tests: EditorRestyleBudgetTests.swift
Signatures:
- RestyleBudget.ceilingMilliseconds — static let ceilingMilliseconds: [RestyleBudget.Case: Double] (relied on)
- scripts/editor-restyle-bench.sh — `scripts/editor-restyle-bench.sh` (relied on)
Red: no

Run `scripts/editor-restyle-bench.sh` three times on a quiet machine and record the minimum per row
in ADR-0082 §D9's "After" column. Propose ceilings (three times "After", rounded up) and stop for
gate G-ceiling: the person decides the six numbers; write them into §D9 and into
`ceilingMilliseconds`, replacing the provisional values and their comment. Record in ADR-0081 the
answers G1 and G2 gave (gutter value, marker face, quote step, badge) and the result of the G3 hand
check, and in ADR-0082 the result of the G-grow hand check on a 1 MB note (type at the end,
Cmd+Down, scroll to the end, click low in the pane), as implementation notes under each ADR, not as
edits to their decisions. Then run the full `PergamenumTests` suite, build `perg` and
`pergamenum-mcp`, run `scripts/mcp-smoke.py` (the shared parsers are compiled into the server),
and `scripts/uitests.sh --affected` per the merge-gate rule.

## Risks & HITL gates

- **N1 merges first; the mockup PR merges and is approved first.** Task 5 cannot start without
  G1/G2's answers. The theme files, `TokenKeys.swift` and `Theme.swift` are touched by N1
  (`spacing.paragraph`) and N5 (callout and highlight colours) as well: cut from `main` after N1, and
  expect N5 to rebase onto this PR.
- **Gate G-corpus (Task 3):** the person reads the classed styler corpus diff; any `.c` blocks the
  merge. The rewrite changes what is concealed on every note, and the corpus is the only thing that
  sees a regression before a person does.
- **Gate G-caret (Task 2), test changes stated before they are made:** the pinned caret assertion
  in `NoteListEditingTests` moves 49 → 48 (its own comment asks for this once the gap closes);
  `EditorHeightTests.stylingLeavesTheTextViewTallEnoughForWhatItDraws` and
  `theLastLineOfANoteIsInsideTheScrollableArea` are restated to "after the end is brought into
  view" because R-17 removes the whole-document layout they presuppose; `MarkupHidingListTests`'s
  "revealed returns nil" test is replaced because ADR-0081 amends the behaviour it pinned. None is
  disabled or weakened beyond the stated change.
- **Gate G-grow (Task 4/Task 8):** R-17 is the riskiest line of N2. `growToFitTheText`'s header
  records two earlier fixes that passed the unit suite and failed in the app, so the 1 MB hand check
  on the Debug build is required. If it fails, the fallbacks are a size threshold (which departs
  from R-17's literal wording for small notes and needs the person's consent) or extending the
  layout to the end only near it; neither is built speculatively.
- **Gate G-ceiling (Task 8):** the six ceiling numbers are the person's decision. The 1 MB rows add
  seconds to every Stop-hook run; if the suite's printed wall time is too high, moving those rows
  out of the per-turn suite amends SPEC test seam 3 and is a decision, not a default.
- **Gate G3 (Task 6):** the by-hand check that nothing moves, in Nota, Oggi and Diario.
- **Two worktrees edit `NoteTextView+Coordinator.swift`:** N2 owns `textDidChange`,
  `applyStyling`, `growToFitTheText` and `applyReadableWidth`; N3 owns the hover and tracking areas.
  The second to merge rebases.
- The shared parsers are compiled into `perg` and `pergamenum-mcp`: Tasks 2, 3 and 8 build both
  schemes; a Foundation-only rule break (an AppKit import in `Sources/Core`) fails both.
- ADR-0081/0082 land with this PR, so `main` never reads them `proposed` without their
  implementation; flip both to `accepted` with the merge hash in the first docs change after merge.
- Commit, push and merge are the human's, at `/ship`. No schema change, no deletion of user data,
  no external resource. Branch suggestion: `feature/n2-page-part-one`.
- Proposed ledger entries, not built here (my evaluation in each ADR): conceal `_` delimiters now
  that the flanking rule makes it safe (ADR-0082 §D2); put task lines on the list column
  (ADR-0081, Consequences); pass `transclusions` in Oggi and Diario (ADR-0082 §D8). The roadmap's
  attribution of the `_` rule to ADR-0030 is wrong (it is ADR-0018 §D1, slice 2); ADR-0082 says so.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE
