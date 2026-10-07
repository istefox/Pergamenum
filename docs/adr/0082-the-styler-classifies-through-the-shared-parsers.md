# ADR-0082: The styler classifies through the shared parsers

- Status: **planned**. Written before the implementation, for `PG-385`/#887 (milestone N2 of the
  note-workflow chain); closes `PG-347`/#762. Flips to `accepted` with the merge of the N2 code PR
  (`docs/adr/README.md` rule 2). §D9's ceiling table is filled from measurement during the build,
  before the merge, at a human gate; until then it reads "to be measured" on purpose.
- Date: 2026-10-04. Written against `48a2d912` (`origin/main` at the same commit). Every line
  number below was read there.
- Number: `0082` was reserved for this record by the dispatch that planned N2 and was checked free
  on every ref on 2026-10-04 (`git log --all -- 'docs/adr/0082*'` printed nothing). Check again
  immediately before the merge (rule 1).
- Source: root `SPEC.md` (Approved 2026-10-04), requirements R-15 to R-19, its decision "the
  keystroke budget's ceiling is set from measurement" and its constraint "one grammar". Background:
  `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 "N2" tasks 4 to 8,
  `docs/20261002_Pergamenum_NoteWorkflowReport.md` R-2 and R-8. Plan: `docs/plans/note-workflow-n2.md`.
- **Extends** ADR-0077 §D1 (the exporter renders from the shared parsers) to the editor's styler,
  ADR-0077 §D5 (parser defects are fixed in the parser) and §D7 (a golden corpus classes every
  difference) to a second consumer, ADR-0028 §D6 (`ListContinuation` owns renumbering) with a
  scoped form, and ADR-0029 §D17 (cards inherit only what their `hiddenKind` switch names) by two
  arms. Amends none.

## Context

The note editor and every other surface disagree about what a note says. `MarkdownStyler`
(`Sources/Features/Editor/MarkdownStyler.swift`, 776 lines) runs its own line walk and its own
inline scanner; of the shared grammar in `Sources/Core/Markdown` it borrows exactly one function,
`MarkdownBlockParser.isRule`. ADR-0077 moved the HTML exporter onto `MarkdownBlockParser.blocks(in:)`
and `MarkdownInlineParser.spans(in:)`, fixed three defects in those parsers (§D5: the intraword `_`
rule, a parsed link label, the task-marker states) and explicitly left the styler alone. The
result is `PG-347`: `file_name_here` exports as plain text and is italicised in the editor
(`emphasis(_:at:)` has no flanking rule), `2 * 3 * 4` differs the same way, and every construct
N5 will add (callouts, highlights, chips) would have to be written twice.

The shared parsers return values without positions (`MarkdownSpan.text`, `MarkdownBlock` cases with
strings), which is what an exporter wants and not what a styler can use: a styler colours ranges of
the text it was given. There is precedent in this codebase for one grammar with a ranged and a
value form: `GFMTable` (ADR-0029 §D10) answers both "where is the table" and "what does it hold".

The keystroke is also unmeasured. `textDidChange` (`NoteTextView+Coordinator.swift:188`) runs, on
every key, `applyStyling` over the whole document, `renumberLists`, which replaces the whole
document with `ListContinuation.renumbered(text)` whenever any marker changes
(`NoteTextView+ListEditing.swift:61-69`), and `growToFitTheText`, which calls
`ensureLayout(for: documentRange)` (`:541-552`). Report R-2 measured nothing and asserted nothing;
the SPEC decided that the cost becomes a number with a ceiling, that N2 measures first, and that
this ADR records the numbers and the ceiling (R-15).

Facts, read on `48a2d912`:

- Every consumer of the styler reads `MarkdownStyler.spans(in:)` and the `Span` enum:
  `NoteTextView+Coordinator.swift:303` (`applyStyling`), `MarkdownAttributedText.swift:55`,
  `CardTextView+Styling.swift:44`, `CardTextAttributes.swift:99`, `InlineSpanReveal.swift:28`;
  nine test files call it directly.
- The styler's per-line order is frontmatter, fences (with `CodeSyntax` tokens), `ListNesting.levels`,
  then per line `isRule`, `PraticaEntryAnchor`, the quote marker, the heading, the task marker, the
  list marker, the embed run, inline spans, markdown links; then wikilinks (`WikilinkParser`),
  tables (`GFMTable`) and view-block runs (`ViewBlock.language`). Fences, tables, frontmatter,
  anchors, view blocks and wikilinks are already recognised by shared Core types; headings, lists,
  tasks, quotes and every inline construct are recognised twice.
- One block-level divergence is known before any corpus: the styler reads a line starting
  `>2026-10-04` as a scheduling token (`blockquoteMarkerLength`, `:630`: one `>` followed by an ISO
  date is not a quote), `MarkdownBlockParser` as a quote (`trimmed.hasPrefix(">")`).
- `_` delimiters are never concealed by the styler (`delimiterSpan(for:opening:)`, `:351-364`)
  because, with no flanking rule, `nome_file_lungo` parsed as italic and hiding its `_` would read
  `nomefilelungo` (ADR-0018 §D1, slice 2). The roadmap attributes this reason to ADR-0030; it is
  ADR-0018's.
- `Tests/NoteListEditingTests.swift` pins the caret one character ahead after a run's trailing
  marker shrinks (49 where 48 is right) and says, in its own comment, that closing the gap should
  update the assertion deliberately. `CardFormattingTests` has the card's twin.
- `growToFitTheText`'s header (`:509-540`) records why it lays out the whole document: without it,
  `usageBoundsForTextContainer` described only the drawn part and the last 187 pt of a forty-line
  note were out of reach; and that `layoutSubtreeIfNeeded` once made the unit suite green over a
  defect still on screen.
- `TodayView.swift:211` and `DiaryView.swift:105` build `NoteTextView` with no `queries`, so a
  `pergamenum-view` fence stays raw there; `EditorColumnView.viewQuerySource` (`EditorColumn+Text.swift:244`)
  is the only `ViewQuerySource` in the app. They pass no `transclusions` either.
- `CardTextView.hiddenKind(for:)` (`CardTextView.swift:359-375`) maps headings, emphasis, embeds,
  lists, checkboxes, strikethrough and link syntax; quotes and rules fall to `default: nil`.

## Decision

### D1. The shared parsers gain a ranged token layer, and their value forms become projections of it

A new file, `Sources/Core/Markdown/MarkdownTokens.swift`, Foundation-only and compiled into `perg`
and `pergamenum-mcp` through the existing `Sources/Core/**` glob, declares:

- `MarkdownBlockParser.lineTokens(in:) -> [MarkdownLineToken]`: one classification per line with
  the ranges of its markers: heading (level, marker, title), list item (bullet or ordered, the
  indentation run, the marker run, the `ListNesting` level), task (state, marker), quote (level,
  marker run), rule, frontmatter, fence open, body and close (through `CodeFence`), table rows
  (through `GFMTable`), message anchor (through `PraticaEntryAnchor`), view-block fence
  (`ViewBlock.language`), blank, paragraph.
- `MarkdownInlineParser.tokens(in:) -> [MarkdownInlineToken]`: the inline scanner, unchanged in its
  rules, reporting ranges: code, embed, wikilink (through `WikilinkParser`), markdown link (label
  parsed recursively, ADR-0077 §D5), strong, emphasis, strikethrough with their delimiter ranges,
  and the app's own conventions as tokens: `#tag`, `>date`, `!date`, `@annotation`.

`MarkdownInlineParser.spans(in:)` and `MarkdownBlockParser.blocks(in:)` keep their signatures and
become projections: the inline projection turns tokens into `MarkdownSpan` values and emits the
app-convention tokens as plain text, exactly as the exporter shows them today; the block
projection is the existing `Accumulator` fed by `lineTokens`. The acceptance for the projection is
that `NoteExportGoldenTests` and the parsers' own suites stay green byte for byte, with one
deliberate exception (§D4).

So there is one grammar: one place decides what a heading, a list marker, a flanking delimiter or a
tag is, and the order in which an inline scanner tries them (code, embed, wikilink, link, emphasis).

### D2. The styler maps tokens onto its unchanged `Span` enum

`MarkdownStyler.spans(in:)` keeps its signature, its `StyledRange` and every case of `Span`, so no
consumer changes. Its body becomes a mapping from `lineTokens` and `tokens` onto `Span`, plus the
`CodeSyntax` token pass inside fences it already makes. Its private recognisers (`emphasis`,
`taskMarker`, `listMarkerSpan`, `headingSpans`, `blockquoteMarkerLength`, the tag, date and
annotation scanners, the line walk) are deleted. Where the styler and the shared scanner disagreed
about precedence, the shared scanner wins and the corpus classes the difference.

`_` emphasis stays unconcealed: the styler applies italic or bold to a `_` run the parser accepts
and keeps its delimiters visible. ADR-0018's reason for not hiding them is gone (the flanking rule
no longer reads `nome_file_lungo` as emphasis), but concealing them is a visible change no N2
criterion asks for. My evaluation: worth doing as a small follow-up once the corpus has landed, low
risk, recorded as a ledger proposal rather than built here.

### D3. A golden corpus captured before the rewrite classes every difference

Before a line of the styler changes, a corpus is captured by running today's `MarkdownStyler` on
`48a2d912` (or the base the build starts from), never written by hand: `Tests/StylerGoldenCorpus.swift`
holds the inputs and the captured output, `Tests/StylerGoldenTests.swift` asserts it. The output of
a case is canonical text: one line per span, `start..<end span`, sorted, plus the hidden-marker
kinds `NoteTextView.Coordinator.hiddenKind(for:)` derives, so the corpus pins what is concealed as
well as what is coloured. Inputs: every markdown input of `NoteExportGoldenCorpus` (E01 to E45 and
the escape cases) verbatim, plus the editor's own constructs: tags, both date tokens, annotations,
every task state, nested bullets and ordered items with spaces and tabs, `1)` markers, nested quotes,
a heading with no title, `#tag` at line start, fences with and without a language, a view block, a
table, frontmatter, a message anchor, embeds with a size suffix, wikilinks with alias and heading,
a link whose label carries emphasis, `file_name_here`, `2 * 3 * 4`, nested and unclosed delimiters.

When the styler moves (§D2), a case whose output changes gets a class, following the SPEC's three
letters:

- **A (fix):** the old styler was wrong and the shared grammar is right (`file_name_here`,
  `2 * 3 * 4`, any other flanking case);
- **B (deliberate):** a change chosen on purpose for a reason other than a styler defect (a
  precedence order where both readings were defensible and the shared scanner's is kept);
- **C (regression):** anything else. A C case blocks the merge; it is fixed in the parser or the
  mapping, never re-captured.

An unchanged case stays unchanged. The class and a one-line reason sit beside each changed case,
the shape `NoteExportGoldenCorpus` already has. The corpus is reused by N5 for its constructs.

### D4. The parser adopts the app's reading of `>date` at the start of a line

A line whose first non-space characters are one `>` immediately followed by an ISO date is a
scheduling token, not a quote, in the shared block grammar, as it has always been in the editor
(the styler's rule, moved, not restated). SPEC (app) §7.1 makes `>YYYY-MM-DD` the scheduling
syntax, and the SPEC of this chain makes the same token the clickable date (N3). `> 2026-10-04`
with a space stays a quote. This is the one place the exporter's output changes;
`NoteExportGoldenCorpus` gains a case for it, classed A for the export, and the styler corpus
shows the case unchanged.

### D5. The keystroke budget: what is measured, how, and what fails

- **What:** one keystroke on a hosted `NoteTextView` holding the note: `insertText("x")` at the
  middle of the text, which runs `textDidChange`'s whole synchronous pipeline (styling, embeds,
  transclusions, renumbering, reveal, grow to fit). The deferred display pass is not included and
  is named as such in the printout.
- **How:** the calling thread's CPU time (`clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`), not
  wall time, because the Stop-hook suite shares the machine with other builds and wall-clock tests
  in this suite have flaked under that load (`PG-331`). The minimum of K runs after one warm-up
  (K = 5 at 50 KB and 200 KB, K = 3 at 1 MB): the noise is one-sided, so the minimum is the
  estimate. Wall time is printed beside it, never asserted.
- **Inputs:** deterministic synthetic notes of 50 KB, 200 KB and 1 MB (UTF-8 bytes) in two
  variants: prose (headings, paragraphs with emphasis, links, tags and dates, nested bullet and
  ordered lists, tasks, quotes) and the same with fences (a code fence every 40 lines or so and a
  `pergamenum-view` fence every 200, with no query source, so the block draws its no-vault branch
  and still hosts its view).
- **Output:** one line per size and variant, `restyle-budget size=<bytes> variant=<prose|fences>
  cpu_ms=<min> wall_ms=<min> runs=<K>`, and the test's own total wall time.
  `scripts/editor-restyle-bench.sh` runs only this suite and prints the six lines as a table.
- **Assertion:** each of the six measurements must stay at or under its ceiling (§D9). The test
  lives in `PergamenumTests`, so the Stop hook runs it every turn (SPEC test seam 3).
- **Order:** the test lands first with the numbers of the code as it is (the "before" column of
  §D9) and provisional ceilings of three times those numbers, so the build stays green while the
  work lands; after the last change it is run again, and the person fixes the final ceilings at a
  gate (proposal: three times the "after" number, rounded up).

### D6. Scoping change one: renumbering rewrites only the edited ordered run

`ListContinuation.renumbered(_:touching:) -> ListContinuation.Renumbering?` returns, for the ordered
runs that contain the edited lines (the edited range widened by one line on each side, so a deleted
separator that merges two runs is seen), the smallest range covering every marker that changes,
its replacement, and a `mapping(_:)` that moves a location through the edit. The editor replaces
only that range through its existing atomic replace, inside the same undo group as the keystroke,
so one edit stays one undo step, and maps the caret through `mapping`. That closes the
one-character gap `NoteListEditingTests` pins: its assertion moves from 49 to 48 deliberately, as
its own comment asks. When no edited range is known (an undo, a programmatic replace), the editor
falls back to the whole-document path, which already answers `nil` when nothing changes.

The card keeps the whole-text path (`renumbered(_:)`, unchanged, sharing the run helpers): a card
holds a few lines, the scoped path buys it nothing, and its twin test keeps pinning its own caret.
An explicit no, recorded so the asymmetry is not read as an oversight.

### D7. Scoping change two: growing to fit lays out the caret's fragment and the viewport

`growToFitTheText(_:revealingCaret:)` keeps its signature and its three steps (ensure layout,
compare the needed height, ask the viewport controller), but ensures layout only for the text
range of the layout fragment holding the selection's end and the range the viewport currently
shows, never `documentRange`. The height comparison then reads `usageBoundsForTextContainer`, which
TextKit 2 keeps for the laid-out part plus its estimate for the rest; the viewport controller lays
out more as the person scrolls, which is what `layoutViewport()` already relies on.

This is the riskiest line of N2, because its header records two earlier fixes that passed the unit
suite and failed in the app. The acceptance is therefore three things together: a hosted test that
types at the end and in the middle of a long note and asserts the caret rectangle inside the
visible rect; a hosted test that scrolls to the end of the document after a keystroke at the top
and asserts the last line fragment is inside the view's bounds; and a hand check on the Debug build
with a 1 MB note (type at the end, Cmd+Down, scroll to the end, click low in the pane).

Two existing tests change meaning and are restated, not weakened silently:
`EditorHeightTests.stylingLeavesTheTextViewTallEnoughForWhatItDraws` and
`theLastLineOfANoteIsInsideTheScrollableArea` assert, right after one keystroke, that the frame is
tall enough for the whole note, which is the whole-document layout this section removes. Under
R-17 the property a person relies on is that the end is reachable when it is approached, so both
are restated as "after the keystroke, bring the end into view, then the last line is inside the
frame". `typingAtTheEndOfANoteBringsTheCaretIntoView` is unchanged and must stay green as is.

If the hand check shows the end out of reach, two fallbacks are on the table, chosen at G-grow and
not built speculatively: scope only above a size threshold (small notes, where the 187 pt defect
was measured, keep the whole-document layout and their two tests unchanged; this departs from
R-17's literal "not the whole document" for small notes, so it needs the person's consent), or
extend the ensured range to the end of the document only when the caret is within one viewport of
it.

### D8. Every surface draws the same spans (R-19)

- Oggi and Diario pass `queries`. The source moves into one factory, `ViewQuerySource.live(for:)`,
  which `EditorColumnView.viewQuerySource` forwards to, so the three hosts cannot build three
  different sources. `onEditQuery` is not passed there: the "Modifica query" control is not drawn in
  those two panes, which `RenderedViewBlock`'s nil-means-no-control rule already handles.
- The `.text` card's `hiddenKind(for:)` gains `.blockquoteMarker → .blockquote` and
  `.horizontalRule → .rule`; the card pushes `ruleColor` from `color.borderSubtle` as the note
  editor does, and the quote paragraph composes onto the card's own paragraph style, so the card's
  line-height multiple survives (ADR-0030 §D6's rule).
- Tables and view blocks stay out of cards: ADR-0029 §D17's `default: nil` arm is the seam and stays.
- Named and not fixed: Oggi and Diario pass no `transclusions` either, so `![[nota]]` stays a link
  there. Proposed as a ledger entry; no N2 criterion covers it.

### D9. The measured numbers and the ceiling

Filled during the build, in this order: "before" by plan Task 2, "after" and "ceiling" by the
plan's last task, the ceiling decided by the person at gate G-ceiling. Milliseconds of main-thread
CPU time per keystroke, minimum of K runs, on the development Mac (model and macOS build named
beside the table when filled).

| Size | Variant | Before | After | Ceiling |
| --- | --- | --- | --- | --- |
| 50 KB | prose | to be measured | to be measured | to be decided |
| 50 KB | fences | to be measured | to be measured | to be decided |
| 200 KB | prose | to be measured | to be measured | to be decided |
| 200 KB | fences | to be measured | to be measured | to be decided |
| 1 MB | prose | to be measured | to be measured | to be decided |
| 1 MB | fences | to be measured | to be measured | to be decided |

## Alternatives considered

- **Port the flanking rule into the styler's own scanner.** Closes `PG-347` in an afternoon and
  keeps two grammars, which is the cause of `PG-347`; N5's constructs would then be written twice
  and the next drift would be found the same way. Rejected.
- **Have the styler consume `spans(in:)` and `blocks(in:)` as they are.** The values carry no
  positions; recovering them by searching the text for each span's string is ambiguous (the same
  word twice in a line) and quadratic on a long note. Rejected.
- **Two walkers sharing the recogniser functions.** Removes duplicated predicates but not
  duplicated precedence, which lives in the walker: the order "code before link before emphasis"
  would still be stated twice. Rejected in favour of §D1's single scanner.
- **Measure with wall-clock time and a mean.** The suite shares the machine with concurrent builds
  (`PG-331`), and a mean absorbs the one-sided noise into the number it reports. Rejected for
  §D5's thread CPU time and minimum.
- **Restyle only the edited paragraph instead of scoping renumbering and layout.** The larger win if
  the budget shows styling itself is the cost, and a larger change: every multi-line construct
  (fences, tables, view blocks, frontmatter, nested lists) makes "the edited paragraph" a range to
  compute. Deferred, not rejected: §D9's numbers decide whether it is needed, and the corpus of
  §D3 is the safety net it would need.
- **Renumber after a short delay instead of in the keystroke.** A deferred rewrite is a second undo
  step and a second `textDidChange`. Rejected.
- **Drop `ensureLayout` and trust the estimate.** That is the state the header's 187 pt measurement
  describes. Rejected.

## Consequences

**Positive.** One grammar: `file_name_here` is plain in the editor as in the export, and N5 adds
each construct once. The keystroke has a number, printed every turn and guarded by a ceiling. On a
long note, a keystroke no longer rewrites every ordered list or lays out text nobody is looking at.
The scoped renumber puts the caret where it belongs.

**Negative.**

- The styler rewrite touches what is concealed on every note; the corpus is the only thing that
  shows a regression before a person does, and it is only as good as its inputs.
- The 1 MB measurement adds seconds to every Stop-hook run; its wall time is printed so the cost is
  visible, and the person can move the 1 MB rows out of the per-turn suite at G-ceiling if it is too
  slow (the SPEC's seam 3 then needs amending, which is a decision, not a default).
- R-17's change carries the risk the header documents; §D7's hand check is not optional.
- The card's renumber keeps the one-character caret gap.

**Neutral.** No file format, schema, protected interface, `Span` case or consumer signature
changes. The exporter's output changes for one input (§D4). The connectors compile the new token
file and behave as before.

## Gates

- **G-corpus:** the classed corpus diff is read by the person before merge; any C blocks it.
- **G-ceiling:** the six ceilings, from the "after" numbers, decided by the person and written into
  §D9 and the test.
- **G-grow:** the 1 MB hand check of §D7 on the Debug build.
- **G-caret:** the deliberate change of the pinned caret assertion from 49 to 48, and the
  restatement of the two `EditorHeightTests` of §D7 (CLAUDE.md: a test is changed only with the
  reason stated first).

## References

- ADR-0077 §D1/§D5/§D7, ADR-0018 §D1, ADR-0028 §D6, ADR-0029 §D10/§D17, ADR-0030 §D6, ADR-0033,
  ADR-0081 (the same milestone).
- `Sources/Features/Editor/MarkdownStyler.swift`, `Sources/Core/Markdown/MarkdownInline.swift`,
  `Sources/Core/Markdown/MarkdownBlocks.swift`, `Sources/Core/Editor/ListContinuation.swift`,
  `Sources/Features/Editor/NoteTextView+Coordinator.swift:188-209, 509-552`,
  `Sources/Features/Editor/NoteTextView+ListEditing.swift:61-69`,
  `Sources/Features/Workspace/CardTextView.swift:359-375`,
  `Sources/Features/Editor/EditorColumn+Text.swift:244`.
- `Tests/NoteExportGoldenCorpus.swift` (the corpus shape), `Tests/NoteListEditingTests.swift`.
- Root `SPEC.md` R-15 to R-19, Decisions, Constraints, Test seams 2 and 3; `PG-347`, `PG-385`.
