<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md tasks=1,2,3 lines=119-231 -->
# Step 5 Batch Brief -- 2026-09-02-editor-wysiwyg-unification.md -- tasks 1-3

## Task text (verbatim, plan lines 119-231)

### Task 1 — `MarkdownStyler` learns four constructs, and the exhaustive tables learn the spans (R-03)

- Budget: `Sources/Features/Editor/MarkdownStyler.swift`,
  `Sources/Features/Editor/MarkdownAttributedText.swift`,
  `Sources/Features/Workspace/CardTextAttributes.swift`, `Tests/MarkdownStylerTests.swift`
  (~220 lines)

**Tester writes the declarations and the tests together.** In `MarkdownStyler.Span`:
`case blockquoteMarker(level: Int)`, `case strikethroughMarker`, `case horizontalRule`,
`case tableRun` (the last is declared here and only *used* from Task 3 — declaring it now keeps the
exhaustive tables from being edited twice).

**Red first**, in `Tests/MarkdownStylerTests.swift`, using the file's existing `spans(_:)` and
`styled(_:_:)` helpers:

- `> citazione` yields one `.blockquoteMarker(level: 1)` whose styled text is `"> "`; `>> due` yields
  level 2 with `">> "`; `>>>> quattro` yields level 4 — **no cap** (R-03, unbounded);
- `>>>senza spazio` yields a marker too (GFM allows the space to be omitted), with the styled text
  being the `>`s alone;
- `---`, `- - -`, `***`, `___` each yield exactly one `.horizontalRule` covering the whole line;
  `--` yields none; a `---` **on the first line of a note with frontmatter** yields none, because
  `spans(in:)` starts at `bodyStart` (regression guard: the frontmatter delimiter must never become
  a rule);
- `~~testo~~` yields two `.strikethroughMarker`s of `"~~"` each, and still yields `.strikethrough`;
  `~~~~` yields no markers (the `emphasisMarkers` guard's twin: hiding them would collapse the run);
- `[testo](https://x.it)` yields `.linkSyntax` over `[` and over `](https://x.it)`, leaving `testo`
  unspanned — **reusing the existing `.linkSyntax` case**, not a new one (ADR §D1);
- every one of the above written **inside a fence** yields none of these spans (R-09's sibling).

Then update the three exhaustive tables the compiler names: `suppressesSpellCheck` (all four are
syntax → `true`), `MarkdownAttributedText.colorToken(for:)` and `CardTextAttributes.colorToken(for:)`.
Assert in `Tests/MarkdownStylerTests.swift` that `suppressesSpellCheck` answers `true` for each new
case.

**Coder** fills the recognisers. The rule grammar is `MarkdownBlockParser.isRule`'s, reused — if it
has to be made non-private to reuse it, do that rather than restating it.

### Task 2 — the four constructs are concealed, and a concealed link says where it goes (R-03, R-04)

- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`,
  `Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift` (new),
  `Sources/Features/Editor/HorizontalRuleFragment.swift` (new),
  `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/MarkupHidingTests.swift`,
  `Tests/QuoteRenderingTests.swift` (new) (~340 lines)

**Tester** declares `HiddenMarker.Kind` cases `.blockquote`, `.strikethrough`, `.link`, `.rule`
(`.table` is Task 4's), the `quoteParagraph(at:storage:)` signature and `HorizontalRuleFragment`'s
stored properties, and writes the red tests against a delegate driven the way
`Tests/MarkupHidingTests.swift` already drives one:

- `>> due` displays `"▏▏ due"` — one bar per level, **character for character**, the paragraph's
  length unmoved (assert `displayed.length == stored.length`, the R-05-of-ADR-0028 shape);
- a blockquote paragraph containing `**grassetto**` renders both its bars **and** its collapsed `**`
  — the `survivors(among:of:in:)` reuse the list branch needed (`+ListRendering.swift:60`);
- the caret's own paragraph reveals every one of the four (ADR-0018 §D2), asserted through
  `apply(revealedParagraphs:)` exactly as the existing heading tests do;
- a `.rule` paragraph's characters are collapsed to `collapsedFont` and
  `textLayoutFragmentFor:in:` returns a `HorizontalRuleFragment` for it;
- a stale marker — the characters no longer spelling what the last styling pass recorded — collapses
  **nothing**, per marker, not per paragraph (`stillSpells` family, one new arm each);
- a concealed `[[Nota]]` carries `.toolTip` with the resolved title, and a `[testo](url)` carries the
  URL (R-04).

**Coder** fills `stillSpellsABlockquoteMarker`, `…AStrikethroughMarker`, `…ALinkDelimiter`,
`…ARule`, the quote branch, the fragment's `draw(at:in:)`, and the `.toolTip` attribute. In
`NoteTextView+Coordinator.applyStyling`, map the four new spans to their kinds at `:280-287`.

**Hand check before Task 3 (probe 1, ADR §D16):** open a note with all four constructs, hover a
concealed wikilink. If no tooltip appears under TextKit 2, **stop and report** — D3's fallback drops
R-04 rather than adding a tracking-area layer, and that is a decision for the user.

---

## Phase 2 — the table grid (the new mechanism)

> **Recommended gate before Task 4.** ADR §D16 probe 2 — Tab/Shift-Tab between two `NSTextField`s in
> an `NSTextAttachmentViewProvider` view inside a real `CompletingTextView` — is the brainstorm's
> named risk and is untried territory for this codebase. A narrow tracer-bullet probe scoped to
> exactly that question is worth a day here, because a negative result forces the ADR's rejected
> Alternative B or C and that is a different ADR, not a mid-implementation pivot. **Whether to spend
> the probe is the orchestrator's and the user's call at Step 4.5, not this plan's.** Task 3 is
> independent of the answer and can proceed either way.

### Task 3 — one GFM grammar, extracted, with ranges (R-05, R-09, R-10)

- Budget: `Sources/Core/Markdown/GFMTable.swift` (new), `Sources/Core/Markdown/MarkdownBlocks.swift`,
  `Sources/Features/Editor/MarkdownStyler.swift`, `Tests/GFMTableTests.swift` (new) (~300 lines)

**Tester** declares `GFMTable` — a `Sendable` value with `header: [String]`, `alignments`, `rows`,
the source `Range<String.Index>` of the whole table, the range of each **line**, and
`static func runs(in text: String, from: String.Index, outside: [CodeFence.Region]) -> [GFMTable]`
plus `static func parse(_ lines: ArraySlice<String>) -> GFMTable?` and
`func serialised() -> String` — and writes the red tests:

- a two-column table with a header, a delimiter row and two body rows parses, with the source range
  covering exactly those four lines and not the blank line after (R-05);
- the three delimiter forms give `.leading` / `.center` / `.trailing`, matching what
  `MarkdownBlockParser.alignments(in:)` already returns;
- a pipe-containing paragraph with **no** delimiter row parses as nothing (R-10);
- a delimiter row whose column count disagrees with the header parses as nothing (R-10);
- a short row is padded and a long row truncated, GFM's rule, unchanged from `fit(_:to:)`;
- `\|` inside a cell survives the round trip, and a Windows path keeps its backslashes
  (`cells(in:)`'s existing escape rule — assert it, it is easy to lose in an extraction);
- **every one of the above inside a fence yields nothing** (R-09);
- `serialised()` round-trips: `parse(serialised().lines) == self` for each fixture.

Then rewire `MarkdownBlockParser.table(header:consuming:)` to call `GFMTable`, and **do not touch
its tests** — `MarkdownBlock.Table`'s shape does not change, so the existing block-parser assertions
must stay green unmodified. If one needs editing, the extraction changed behaviour and is wrong.

Finally, emit `.tableRun` from `MarkdownStyler.spans(in:)` through a `tableSpans(in:from:outside:)`
pass placed beside `wikilinkSpans(in:from:outside:)` and taking the same `fences` argument.

## File map (from Budget: declarations, tasks 1-3)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 1 2 3 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0029-editor-wysiwyg-unification.md -- delimiter substitution mechanism decisions (D1-D5) for blockquote/strikethrough/link tooltip/hrule
- SPEC: SPEC.md -- requirement IDs for this batch's tests
- CLAUDE.md: CLAUDE.md -- editor WYSIWYG conventions and working agreements
