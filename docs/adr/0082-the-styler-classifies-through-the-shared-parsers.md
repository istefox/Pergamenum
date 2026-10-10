# ADR-0082: The styler classifies through the shared parsers

- Status: **planned**. Written before the implementation, for `PG-385`/#887 (milestone N2 of the
  note-workflow chain); closes `PG-347`/#762. Flips to `accepted` with the merge of the N2 code PR
  (`docs/adr/README.md` rule 2). §D9's table is measured (2026-10-10, finished tree with the `wikilinkSpans` fix);
  its six ceilings were decided by the person at G-ceiling on 2026-10-10.
- Date: 2026-10-04. Written against `48a2d912` (`origin/main` at the same commit). Every line
  number below was read there. Re-read on `9103768f` (2026-10-06), after N1 (#897, #905); line
  numbers corrected there.
- Number: `0082` was reserved for this record by the dispatch that planned N2 and was checked free
  on every ref on 2026-10-04 (`git log --all -- 'docs/adr/0082*'` printed nothing). Check again
  immediately before the merge (rule 1).
- Source: root `SPEC.md` (Approved 2026-10-04), requirements R-15 to R-19, its decision "the
  keystroke budget's ceiling is set from measurement" and its constraint "one grammar". Background:
  `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 "N2" tasks 4 to 8,
  `docs/20261002_Pergamenum_NoteWorkflowReport.md` R-2 and R-8. Plan: `docs/plans/pg-385-n2-page.md`
  (which supersedes `docs/plans/note-workflow-n2.md`).
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
`ensureLayout(for: documentRange)` (`:530-541`). Report R-2 measured nothing and asserted nothing;
the SPEC decided that the cost becomes a number with a ceiling, that N2 measures first, and that
this ADR records the numbers and the ceiling (R-15).

Facts, read on `48a2d912`:

- Every consumer of the styler reads `MarkdownStyler.spans(in:)` and the `Span` enum:
  `NoteTextView+Coordinator.swift:284` (`applyStyling`), `MarkdownAttributedText.swift:55`,
  `CardTextView+Styling.swift:44`, `CardTextAttributes.swift:100`, `InlineSpanReveal.swift:28`;
  ten test files call it directly.
- The styler's per-line order is frontmatter, fences (with `CodeSyntax` tokens), `ListNesting.levels`,
  then per line `isRule`, `PraticaEntryAnchor`, the quote marker, the heading, the task marker, the
  list marker, the embed run, inline spans, markdown links; then wikilinks (`WikilinkParser`),
  tables (`GFMTable`) and view-block runs (`ViewBlock.language`). Fences, tables, frontmatter,
  anchors, view blocks and wikilinks are already recognised by shared Core types; headings, lists,
  tasks, quotes and every inline construct are recognised twice.
- One block-level divergence is known before any corpus: the styler reads a line starting
  `>2026-10-04` as a scheduling token (`blockquoteMarkerLength`, `:630`: one `>` followed by an ISO
  date is not a quote), `MarkdownBlockParser` as a quote (`trimmed.hasPrefix(">")`).
- `_` delimiters are never concealed by the styler (`delimiterSpan(for:opening:)`, `:359`)
  because, with no flanking rule, `nome_file_lungo` parsed as italic and hiding its `_` would read
  `nomefilelungo` (ADR-0018 §D1, slice 2). The roadmap attributes this reason to ADR-0030; it is
  ADR-0018's.
- `Tests/NoteListEditingTests.swift` pins the caret one character ahead after a run's trailing
  marker shrinks (49 where 48 is right) and says, in its own comment, that closing the gap should
  update the assertion deliberately. `CardFormattingTests` has the card's twin.
- `growToFitTheText`'s header (`:498-529`) records why it lays out the whole document: without it,
  `usageBoundsForTextContainer` described only the drawn part and the last 187 pt of a forty-line
  note were out of reach; and that `layoutSubtreeIfNeeded` once made the unit suite green over a
  defect still on screen.
- `TodayView.swift:216` and `DiaryView.swift:110` build `NoteTextView` with no `queries`, so a
  `pergamenum-view` fence stays raw there; `EditorColumnView.viewQuerySource` (`EditorColumn+Text.swift:248`)
  is the only `ViewQuerySource` in the app. They pass no `transclusions` either.
- `CardTextView.hiddenKind(for:)` (`CardTextView.swift:368-383`) maps headings, emphasis, embeds,
  lists, checkboxes, strikethrough and link syntax; quotes and rules fall to `default: nil`.

## Decision

### D1. The shared parsers gain a ranged token layer, and their value forms become projections of it

A new file, `Sources/Core/Markdown/MarkdownTokens.swift`, Foundation-only and compiled into `perg`
and `pergamenum-mcp` through the existing `Sources/Core/**` glob, declares:

- `MarkdownBlockParser.lineTokens(in:readsFrontmatter:endsLine:) -> [MarkdownLineToken]`: one
  classification per line with the ranges of its markers (frontmatter read only when asked, the
  line split overridable by the caller, §D2): heading (level, marker), list item (bullet or
  ordered, the indentation run, the marker run, the `ListNesting` level), task
  (`.task(state:marker:level:)`: state, marker, the `ListNesting` level), quote (level, marker
  run), rule, frontmatter, fence open (with its language, so a view-block fence is one whose
  language is `ViewBlock.language`), body and close (through `CodeFence`), table rows (through
  `GFMTable`), message anchor (through `PraticaEntryAnchor`), blank, paragraph.
- `MarkdownInlineParser.tokens(in:) -> [MarkdownInlineToken]`: the inline scanner, unchanged in its
  rules but one (`closingRange` steps a single marker over a nested `**`/`__` pair, §D4),
  reporting ranges: code, embed, wikilink (through `WikilinkParser`), markdown link (label
  parsed recursively, ADR-0077 §D5), strong, emphasis, strikethrough with their delimiter ranges,
  and the app's own conventions as tokens: `#tag`, `>date`, `!date`, `@annotation`.

`MarkdownInlineParser.spans(in:)` and `MarkdownBlockParser.blocks(in:)` keep their signatures and
become projections: the inline projection turns tokens into `MarkdownSpan` values and emits the
app-convention tokens as plain text, exactly as the exporter shows them today; the block
projection is the existing `Accumulator` fed by `lineTokens`. The acceptance for the projection is
that `NoteExportGoldenTests` and the parsers' own suites stay green byte for byte, with the
exceptions §D4 records (the decided `>date` reading and a nested-strong fix found during the build).

The block projection keeps the parser's own line split (`Character.isNewline`) and its trimming (all
whitespace, tabs included), and reads a body rather than a note: a leading `---` is a rule there,
which is why `lineTokens` reads frontmatter only when asked (`readsFrontmatter:`, default `false`)
and only the styler asks. `embedRun(inLine:)` stays app-side (`EmbedRun.swift`); the styler's mapping
calls it, so `Sources/Core` gains no dependency on the app. `MarkdownTokens.swift` came to 273 lines,
under the 400 at which the plan would have split it by parser, so it was not split.

So there is one grammar: one place decides what a heading, a list marker, a flanking delimiter or a
tag is, and the order in which an inline scanner tries them (code, embed, wikilink, link, emphasis).

### D2. The styler maps tokens onto its unchanged `Span` enum

`MarkdownStyler.spans(in:)` keeps its signature, its `StyledRange` and every case of `Span`, so no
consumer changes. Its body becomes a mapping from `lineTokens` and `tokens` onto `Span`, plus the
`CodeSyntax` token pass inside fences it already makes. Its private recognisers (`emphasis`,
`taskMarker`, `listMarkerSpan`, `headingSpans`, `blockquoteMarkerLength`, the tag, date and
annotation scanners, the line walk) are deleted. Where the styler and the shared scanner disagreed
about precedence, the shared scanner wins and the corpus classes the difference.

**The styler's line is the editor's paragraph (review, 2026-10-06).** `lineTokens(in:)` splits on
`Character.isNewline`, the reading view's split (PG-317), so U+2028, U+2029 and a lone `"\r"` end a
line there. TextKit keeps all of them inside one paragraph, and the old styler, which split on `"\n"`
and `"\r\n"` only (`LineBreak.isTerminator`), read that paragraph as one line: a `**` run, a code
span or a link matched across the separator, `x` U+2028 `#project-av45` was no tag, a heading or
quote span covered its whole paragraph, and a block marker after the separator was prose. An
earlier round kept only the last of these (S45) by treating a line not started after a terminator
as prose, which left the other four moved without a class. The cause is the split, not the
mapping, so `lineTokens(in:readsFrontmatter:endsLine:)` takes the line terminator as a parameter,
defaulting to `isNewline`, and the styler passes `LineBreak.isTerminator`. `blocks(in:)` and
`spans(in:)` of the parsers, and so the exporter and the reading views, keep their split byte for
byte. The alternative, accepting the shared split and classing S55 to S58 as A, was rejected on
evidence: a separator inside a paragraph is typed text the editor draws unbroken, so a run that
visibly spans it is the user's intent, and no reading view or exporter consideration requires the
editor to break it. S55 to S58 pin the five behaviours, captured from `3e5df0a6` and unchanged.

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
kinds `NoteTextView.Coordinator.hiddenKind(for:)` derives, and after them one `order a < b` line per
pair of overlapping spans in emission order, so the corpus pins what is concealed as well as what is
coloured and in which order the styler lets a later span win (a sorted list alone cannot see a
precedence regression). Inputs: every markdown input of `NoteExportGoldenCorpus` (E01 to E45 and
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
the shape `NoteExportGoldenCorpus` already has, in a type of the styler corpus's own
(`StylerGoldenCase`): the export corpus's `Kind` gives `b` and `c` other meanings
(`NoteExportGoldenCorpus.swift:18-28`). A `captured` output is never edited: the captured strings
live in `StylerGoldenCapturedExport.swift` and `StylerGoldenCapturedEditor.swift`, and a case that
moved carries its class, its reason and its new `expected` in `StylerGoldenChanges.swift`. The
corpus is reused by N5 for its constructs.

### D4. The parser adopts the app's reading of `>date` at the start of a line

A line whose first non-space characters are one `>` immediately followed by an ISO date is a
scheduling token, not a quote, in the shared block grammar, as it has always been in the editor
(the styler's rule, moved, not restated). SPEC (app) §7.1 makes `>YYYY-MM-DD` the scheduling
syntax, and the SPEC of this chain makes the same token the clickable date (N3). `> 2026-10-04`
with a space stays a quote. This is the one *decided* change to the exporter's output;
`NoteExportGoldenCorpus` gains a case for it, classed A for the export, and the styler corpus
shows the case unchanged. The reading reaches every consumer of `blocks(in:)`, not only the
exporter: `MarkdownHTML.swift:20`, `MarkdownReadingView.swift:59`, `TranscludedNoteView.swift:106`,
`PraticaEntryRow.swift:113`, `PraticaMessageRow.swift:191` and `PratichePane+Inspector.swift:68` all
read `>2026-10-04 x` as a paragraph now. `ViewBlock.swift:267` reads code blocks only and is
unaffected.

**A second exporter change, found during the build (2026-10-06).** Moving the styler onto the
shared scanner made the styler corpus's S36, `**forte con *corsivo* dentro** e *corsivo con
**forte** dentro*`, come out as a C: the scanner closed a single `*` at the first star of a
nested `**`, so the editor drew three italics and no bold. The fix went where §D3 says a C is
fixed, in the parser: `MarkdownInlineParser.closingRange` steps a single marker over a `**` (or
`__`) pair nested inside it (`nestedStrongEnd`). Because the exporter reads the same scanner, its
output moved for that input too. Evidence that the old export was wrong, not a reading worth
keeping: on `3e5df0a6` `*corsivo con **forte** dentro*` exported as
`<p><em>corsivo con *</em>forte** dentro*</p>`, an italic that swallowed a star and two stray
`**` and `*` left as text; it now exports as nested emphasis with no star left over. The rule is
kept. `NoteExportGoldenCorpus` gains E48 for that input, classed A; the styler corpus carries E48
with the same class, and `MarkdownProjectionTests` pins the projection directly. The root
`SPEC.md`, which says the exporter's output changes for "this one input", needs the person's
amendment to name the second; this record does not edit the SPEC.

**A styler-only change found in review (2026-10-06), no exporter change.** A delimiter row with no
pipe under a one-column header (`| a |` then `---`) is a table's delimiter row in the shared block
grammar, as it already was for the reading view and the exporter on `3e5df0a6` (both check a table
before a rule). The old styler read that one line twice: a `.tableRun` over the table and a
`.horizontalRule`, concealed as a rule, over the `---`. The token layer classifies the line once,
as `.tableRow`, so the editor now emits the table run alone. The styler corpus gains S59 for the
input, captured on `3e5df0a6`, classed A.

**A delegate-side change found in review (2026-10-06), no styler or exporter change.**
`EditorDecorationDelegate.stillSpellsARule`, the layout-time check that a `.rule` entry still
spells a rule, now trims the line's surrounding blanks (`.whitespaces`, tabs included) before it
asks `isRule`, as the rule fragment's own branch already did, so the tab-indented rules the token
layer now marks (S53's `\t---` and `\t***`, S60's `\t- - -`) are concealed as well as drawn; it
changes what the editor conceals, not what the styler emits, so it leaves no trace in the corpus
and is pinned in `MarkupHidingTests` instead.

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
- **Outside the measurement:** in the app a keystroke runs the pipeline at least twice, and only the
  first pass is measured. `textDidChange` (`NoteTextView+Coordinator.swift:188-222`) is the measured
  one. The SwiftUI update that the binding write triggers then runs `runPasses`
  (`NoteTextView+Update.swift:55-71`): styling, embeds, transclusions, folding, matches, reveal and
  `growToFitTheText`, unconditionally. A renumbering keystroke re-enters `textDidChange` a third
  time through `replaceAtomically`'s `didChangeText()` (`NoteTextView+EmbedCaret.swift:101-113`).
  So a keystroke in the app costs about two pipelines. The double pass is named here and proposed as
  a ledger entry, not fixed in N2; measuring it would double the scope of the six-line contract.
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

The edited range is recorded by the coordinator's
`textView(_:shouldChangeTextInRanges:replacementStrings:)` (`NoteTextView+ListEditing.swift`), which
both `insertText` and `replaceAtomically` pass through, and handed to
`renumberLists(in:touching:)`. With no range the fallback keeps today's clamped caret (49), pinned
by a test of its own. `mapping(_:)` is exact per rewritten digit run: a location after a shrunk
`10.` moves back one, a location between two rewritten runs moves by the first run's delta only, and
a location inside a rewritten run stays inside it. A misnumbered run elsewhere is left alone until
it is edited, which is R-16's «only the edited ordered run».

The card keeps the whole-text path (`renumbered(_:)`, unchanged, sharing the run helpers): a card
holds a few lines, the scoped path buys it nothing, and its twin test keeps pinning its own caret.
An explicit no, recorded so the asymmetry is not read as an oversight.

### D7. Scoping change two: growing to fit lays out the caret's fragment and the viewport

**Withdrawn 2026-10-10, at G-grow. `growToFitTheText` lays out the whole document again.** The
hand check on a 50 KB note in the Release build found what the section's own risk paragraph feared:
Cmd+Down, then a click on a line, scrolled the note to text far above the click (section 62 for
section 104) and left the whole note selected, which the next key replaces. The cause is the pairing
of this section with the editor's passes: `applyStyling` rewrites every attribute and invalidates the
layout of the whole note on every update, and a click runs the passes, so everything above the
viewport became an estimate again. The estimate is shorter than the real height, so the same scroll
offset showed earlier text, and the mouse, still down, sat over other text and extended the
selection. The same sequence on the tree before N2 (`3e5df0a6`, Release) places the caret on the
clicked line. Two tests pin it, both red without the whole-document layout and green with it:
`thePassesAClickRunsLeaveTheViewOnTheSameText` and
`afterTheKeystrokePassesNoHeightInTheNoteIsAnEstimate`. The person chose, from the alternatives
(restore, try a scroll anchor, merge and fix later), to restore. The text below is kept as the
record of the design that was tried; the cost it was meant to remove goes to the per-paragraph
restyle task, which stops invalidating the whole note and so makes an estimate harmless. The
measured price of the restoration is the third "after" in §D9, inside the approved ceilings.

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

`growToFitTheText` has three callers and all three take the scoped path:
`NoteTextView+Coordinator.swift:209` (`textDidChange`), `:384` (the view-block height callback) and
`NoteTextView+Update.swift:71` (`runPasses`). The restatement, with its reason said first (§D7
removes the whole-document layout the two tests relied on): each drops its own test-side
`ensureLayout(for: documentRange)` after the keystroke (`EditorHeightTests.swift:71`, `:86`), brings
the end into view the way the app does (`moveToEndOfDocument(nil)`, then
`textViewportLayoutController.layoutViewport()`, never `layoutSubtreeIfNeeded`), and asserts its own
property: the first, `frame.height >= usageBoundsForTextContainer.height + 2 × verticalInset` as
TextKit reports it at that moment; the second, that the last line's fragment `maxY` is at or below
`frame.height`. The private fixture gains `textView.delegate = coordinator`.

**What the hosted scope test does not prove (review, 2026-10-06).** `EditorGrowToFitScopeTests`
measures one `growToFitTheText` call, not a whole keystroke: it records which layout fragments
that call requests and finds none between the middle of a 2,000-line note and its last paragraph.
The rest of the keystroke still lays out far more than that: the review measured `applyStyling`
alone requesting fragments for about 1,250 of the 2,000 paragraphs on every key, and the
`runPasses` re-pass of §D5 is outside the test as well. So the test pins that `growToFitTheText`
no longer forces `documentRange`, which is R-17's literal subject, and says nothing about the
cost of a keystroke in a 1 MB note or about whether its end stays reachable. That is still the
G-grow hand check below, which remains the real acceptance of this section; the keystroke's whole
cost is §D9's number.

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
  editor does, and the quote paragraph composes onto the card's own paragraph style, so the card's own
  paragraph style (its alignment) survives and a card gains no page line height (ADR-0030 §D10).
  With gutter 0 the quote branch sets no style in a card (ADR-0081 §D6).
- `CardTextView.hiddenKind(for:)` had seven arms and `InlineSpanRevealFenceTests` pinned exactly
  seven (`:323-354`); it pins nine now, quote and rule, restated with its reason said first and
  joined to G-caret.
- The doc comments that stated the old fact (Oggi and Diario pass no `queries`) are corrected:
  `NoteTextView+Inputs.swift:83-86`, `EditorColumn+Text.swift:244-247`,
  `ViewBlockQuerySourceTests.swift:354-358` and `:382-391`, `NoteTextView+Coordinator.swift:396-400`
  and `CardTextAttributes.swift:222-232`.
- Tables and view blocks stay out of cards: ADR-0029 §D17's `default: nil` arm is the seam and stays.
- Named and not fixed: Oggi and Diario pass no `transclusions` either, so `![[nota]]` stays a link
  there. Proposed as a ledger entry; no N2 criterion covers it.

### D9. The measured numbers and the ceiling

Filled during the build, in this order: "before" by plan Task 1 (`docs/plans/pg-385-n2-page.md`),
"after" by the plan's last task (Task 8), and the ceiling decided by the person at gate
G-ceiling. Milliseconds of main-thread CPU time per keystroke, minimum of K runs, on the
development Mac (model and macOS build named beside the table when filled).

| Size | Variant | Before | After | Ceiling |
| --- | --- | --- | --- | --- |
| 50 KB | prose | 1469.68 | 198.43 | proposed 596 (current literal 4410) |
| 50 KB | fences | 1421.30 | 225.34 | proposed 677 (current literal 4264) |
| 200 KB | prose | 21556.50 | 911.37 | proposed 2735 (current literal 64670) |
| 200 KB | fences | 19969.66 | 1066.64 | proposed 3200 (current literal 59909) |
| 1 MB | prose | 646462.33 (one cold run) | 6308.79 | proposed 18927 (current literal 1939387) |
| 1 MB | fences | 655081.13 (one cold run) | 11843.73 | proposed 35532 (current literal 1965244) |

"Before" measured on 2026-10-06 by `scripts/editor-restyle-bench.sh` on the untouched tree (`3e5df0a6`
plus only the red-phase stubs, which change no behaviour): Mac model `Mac17,7` (Apple M5 Max),
macOS 27.0.1 (build 26A434), Debug build, `xcodebuild` with `-only-testing:PergamenumTests/EditorRestyleBudgetTests`.
The four rows up to 200 KB are the minimum of 5 runs after one warm-up. The two 1 MB rows are **one
cold run with no warm-up** (`--large-only --runs 1 --no-warmup`): a keystroke in a 1 MB note costs
about eleven minutes on the untouched code, so K=3 plus a warm-up would be about three quarters of an
hour per row. Provisional ceilings in `Tests/RestyleBudgetSupport.swift` are three times these
numbers, rounded up. The cost is roughly quadratic in the note's size (50 KB to 200 KB is 14 times
for 4 times the size; 200 KB to 1 MB is 30 times for 5 times), which is what §D6 and §D7 aim at. The
two 1 MB cases ran only with `RESTYLE_BUDGET_1MB=1` (`scripts/editor-restyle-bench.sh --large`), so
the per-turn suite then measured four rows, not six (now two, see "Which rows run every turn"
below). Wall time added to the suite by those four rows on the untouched code: 320 s on the first
run and 426 s on a second one, nearly all of it
the two 200 KB rows. That second run, made while other builds were running on the same Mac, measured
2354.16, 1776.56, 24152.07 and 28446.27 ms for 50 KB fences, 50 KB prose, 200 KB fences and 200 KB
prose: up to 1.7 times the first run's numbers, so the 3 times factor of the provisional ceilings is
the least that holds against load on this machine.

**The "after" column is the one taken on 2026-10-10, with the `wikilinkSpans` fix** (commit
`b2c58d1c`): `scripts/editor-restyle-bench.sh --large`, the same Mac and build, the four rows up to
200 KB the minimum of 5 runs after one warm-up and the two 1 MB rows the minimum of 3 runs after one
warm-up (the 1 MB rows are no longer a half-hour job: 109 s for the whole script). The first "after",
below, was taken on 2026-10-07 before the fix and is kept because it is what the two scopings alone
did. The fix is not one of N2's tasks: a hand check on a 50 KB note on 2026-10-10 found the editor
unusable (seconds of lag per key), a profile of the open pass and of a typed keystroke put nearly all
of `MarkdownStyler.spans(in:)` in `wikilinkSpans`, which measured every link from the start of the note
(four walks over the whole text per link, quadratic), and it now walks only the gap since the previous
link. The ceiling column below is computed on these final numbers.

The first "after", measured on 2026-10-07 by `scripts/editor-restyle-bench.sh` on the tree
with plan Tasks 1 to 8 and before the fix (plan Tasks 1 to
8 in, branch `feat/pg-385-n2-gutter`), on the same Mac: `Mac17,7` (Apple M5 Max), macOS 27.0.1 (build
26A434), Debug build. The four rows up to 200 KB are the minimum of 5 runs after one warm-up. The two
1 MB rows are **one cold run with no warm-up** (`--large-only --runs 1 --no-warmup`), as the "before"
rows are: 520.3 s and 537.7 s of thread CPU time, 2,172 s of wall time for the pair, build and
fixtures included. An earlier "after" taken on 2026-10-06 with Tasks 1 to 4 only gave 1594.41, 1538.71,
25848.71 and 21648.63 ms for the four small rows; the 1 MB rows then were ended twice by a SIGTERM
from outside the test (514 s and 336 s in) and gave no number. Both of those readings were taken
while other sessions were building on the Mac; the 2026-10-10 numbers are the ones to read.
**The third "after", 2026-10-10, with the whole-document layout restored** (§D7 withdrawn): the same
script, Mac and build, `--large`. 50 KB prose 287.62 ms and fences 298.60 (were 198.43 and 225.34),
200 KB prose 1166.25 and fences 1367.33 (were 911.37 and 1066.64), 1 MB prose 7960.66 and fences
12725.48 (were 6308.79 and 11843.73): 26% to 45% more than with the scoped layout, every row under its
approved ceiling (596, 677, 2735, 3200, 18927, 35532), so G-ceiling stands as decided. The ceiling
column below is still three times the second "after".

The ceiling column is three times the final "after" (2026-10-10), rounded up to a whole millisecond
(the rule of the provisional literals, which were three times "before"), as approved at G-ceiling and
now held by `RestyleBudget.ceilings` in `Tests/RestyleBudgetSupport.swift`.

Two things about the bench itself, found while taking these numbers. The script's guard
(`pgrep -fl 'xcodebuild.*Pergamenum'`) also matches the command line of a *waiting shell* that another
session left polling for `xcodebuild`, so on a Mac with such a shell the guard refuses indefinitely
with no build running; the numbers above were taken with a copy of the script whose guard matches the
`xcodebuild` executable only, after checking that none was running. The measurement lines and the
`xcodebuild` invocation are the script's, unchanged. The script's own guard now does the same
(`pgrep -x xcodebuild`, then a check that the process's arguments name `Pergamenum`), so a
polling shell no longer blocks it. Before the `wikilinkSpans` fix a 1 MB keystroke cost about nine
minutes of CPU and the pair was a half-hour job; it is about two minutes now, still worth running quiet.

What the "after" says. The two scopings (§D6, §D7) did not move the number: the first "after"
(2026-10-07) is at or under the "before" by 1% to 21%, inside the load noise the "before" paragraph
measured (up to 1.7 times between two "before" runs), because the benchmark keystroke, a letter typed
at the end of a paragraph, changes no ordered run and the whole-document layout was not where its cost
lay. The cost was the whole-document restyle, and inside it one function: with `wikilinkSpans` made
linear a keystroke costs 7.4 times less at 50 KB (1459 to 198 ms), 22 times less at 200 KB (20439 to
911 ms) and 85 times less at 1 MB (537673 to 6309 ms). That is a real gain, and it is a fix of a
quadratic walk, not of the design: the keystroke still re-tokenizes and restyles the whole note, so
its cost is still proportional to the note, and 198 ms at 50 KB (Debug; the Release app is faster)
is still too slow to type in at speed: a hand check of the Release build on 2026-10-10 found a 50 KB
note barely usable after the fix. A keystroke has to cost under about 20 ms whatever the note's size,
which only the alternative "restyle only the edited paragraph" can give: a profile of a typed
keystroke in a 50 KB note puts 46% of `textDidChange` in the per-line inline parse, 15% in the
wikilink parse, 13% in the block tokenizer and 10% in the transclusion scan, all over the whole
text, plus a second styling pass in `runPasses`. My evaluation: it is worth its own chain, with §D3's
corpus as its safety net and a property test (random edits, incremental equals full restyle); the
person decided on 2026-10-10 to run it as a separate task started at once, not inside N2. §D6 still
stands on its own grounds (one undo step and the right caret for a renumber); §D7 was withdrawn at
G-grow, its reason in the section itself.

**Which rows run every turn: a proposal for G-ceiling.** At these costs the six rows cannot all run
in the per-turn suite: on the untouched tree and on the first "after" the four rows up to 200 KB added 320 to 426 s of wall time to one run of the budget
suite (397 s on the first "after"; about 15 s now with the fix), nearly all of it the two 200 KB rows, and the Stop
hook kills the whole suite at 600 s. So, as built and approved by the person at G-ceiling on 2026-10-10:

- **Every turn:** the two 50 KB rows, asserted against their ceilings: 14 s and 16 s of wall time
  in a full run of `PergamenumTests` on 2026-10-06 (5,550 tests, 250 s).
- **On demand:** the two 200 KB rows and the two 1 MB rows, still asserted against their ceilings
  whenever they run, through `scripts/editor-restyle-bench.sh` (the 200 KB rows on every run of the
  script, the 1 MB rows with `--large` or `--large-only`). The proposal is to run the script before
  merging any change to the editor's keystroke pipeline.
- **The switches,** the test's own environment variables (`Tests/RestyleBudgetSupport.swift`;
  `xcodebuild` hands them to the test process with the `TEST_RUNNER_` prefix stripped, and the script
  sets them):
  - `RESTYLE_BUDGET_200KB=1`: the 200 KB rows (`RestyleBudget.includesMediumNotes`);
  - `RESTYLE_BUDGET_1MB=1` or `only`: the 1 MB rows beside the others, or alone
    (`includesLargeNotes`);
  - `RESTYLE_BUDGET_RUNS=N`: N measured runs per row instead of K (`--runs N`), for a row too slow
    to repeat;
  - `RESTYLE_BUDGET_NO_WARMUP=1`: no warm-up keystroke (`--no-warmup`), for the same reason.

This departs from the letter of the root `SPEC.md`, whose summary says the cost "is measured every
turn" and whose R-15 names the three sizes: the test still measures all three, but only the 50 KB
rows every turn. The SPEC needs the person's amendment for it; this record does not edit it.

**Decided at G-ceiling, 2026-10-10.** The person approved the six ceilings as proposed in the table
(three times the final "after", rounded up: 596, 677, 2735, 3200, 18927 and 35532 ms) and the split
above (the two 50 KB rows every turn, the others on demand). `RestyleBudget.ceilings` in
`Tests/RestyleBudgetSupport.swift` holds them, so a return to the old quadratic cost fails the
per-turn suite at 50 KB (the provisional literals, three times "before", sat 19 to 307 times above
the measured cost and would not have caught it). The SPEC amendment that goes with the split was
approved the same day.

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
- The budget's large rows are slow (minutes before the `wikilinkSpans` fix, seconds after it): only
  the 50 KB rows run every turn and the 200 KB and 1 MB rows run on demand through the bench script.
  The person approved that at G-ceiling on 2026-10-10 and the SPEC's §5 was amended the same day.
- R-17's change carries the risk the header documents; §D7's hand check is not optional.
- The card's renumber keeps the one-character caret gap.

**Neutral.** No file format, schema, protected interface, `Span` case or consumer signature
changes. The exporter's output, and with it that of every other `blocks(in:)` and `spans(in:)`
consumer §D4 names, changes for two inputs (§D4: `>date` at the start of a line, E46,
and a strong run nested in an italic one, E48). The connectors compile the new token file and
behave as before.

## Gates

- **G-corpus:** the classed corpus diff is read by the person before merge; any C blocks it.
- **G-ceiling:** which rows run every turn (§D9's proposal: the 50 KB rows, the others on demand)
  and the six ceilings, from the "after" numbers, decided by the person and written into
  §D9 and the test.
- **G-grow:** the 1 MB hand check of §D7 on the Debug build.
- **G-caret:** the deliberate change of the pinned caret assertion from 49 to 48, the
  restatement of the two `EditorHeightTests` of §D7, and `InlineSpanRevealFenceTests`' arm count
  from 7 to 9 (§D8) (CLAUDE.md: a test is changed only with the reason stated first).

## Implementation notes

Written at the code PRs (#921 for plan Tasks 1 to 5, the gutter PR for Tasks 6 to 8), 2026-10-07. The
decision above is unchanged; this records what was built and where, the corpus result, and what the
build left open. Status stays `planned` until the merge.

**Where it landed.**

- New: `Sources/Core/Markdown/MarkdownTokens.swift` (the token layer both parsers and the styler share,
  §D1 and §D2). Changed: `MarkdownStyler.swift` (the mapping from tokens to spans, §D2),
  `NoteTextView+ListEditing.swift` and `CardTextView+ListEditing.swift` (the scoped
  `renumberLists(in:touching:)`, §D6), `NoteTextView+Coordinator.swift` (the scoped
  `growToFitTheText`, §D7), `ViewQuerySource+Live.swift` (`ViewQuerySource.live(for:)`, the one factory
  Oggi, Diario and the note editor share, §D8) and `CardTextView.swift` (`hiddenKind`, 7 to 9 cases).
- Tests: `Tests/StylerGoldenTests.swift` with `StylerGoldenCorpus.swift`,
  `StylerGoldenCapturedEditor.swift`, `StylerGoldenCapturedExport.swift` (the captured outputs, never
  edited) and `StylerGoldenChanges.swift` (the classed differences); `StylerSharedGrammarTests.swift`,
  `MarkdownStylerBlockTests.swift`, `ListRenumberScopeTests.swift`, `ListRenumberRecordingTests.swift`,
  `EditorGrowToFitScopeTests.swift`, `EditorRestyleBudgetTests.swift` with `RestyleBudgetSupport.swift`;
  the bench is `scripts/editor-restyle-bench.sh`.

**The corpus, per class (§D3).** 119 cases captured before the change (`StylerGoldenCorpus`).
98 cases' output is byte-identical after it. The other 21 moved, and every one is **class A** (the
old styler was wrong; the exporter or the reading view already read the input as the new styler does):
`E21`, `E23`, `E25`, `E28`, `E29`, `E42`, `E48`, `S30`, `S32`, `S33`, `S34`, `S35`, `S36`, `S37`,
`S38`, `S51`, `S52`, `S53`, `S54`, `S59`, `S60`. **Class B: 0. Class C: 0.** Three cases (`S11`, `S36`,
`S45`) first came out as C and were fixed before the table was written: `S11` and `S45` in the
styler's mapping (ASCII ordered digits; `lineTokens` is given `LineBreak.isTerminator`, so a U+2028
ends none), `S36` in the parser's `closingRange`. The reason for each of the 21 is in
`StylerGoldenChanges.swift`, next to its new `expected`. The exporter's output moved for exactly
two inputs, as §D4 said it would: `E48` and the second half of `S36` (a strong run nested in an
italic one). G-corpus is the person's to read.

**The budget (§D9).** Measured on the finished tree with the `wikilinkSpans` fix: 7 to 85 times
cheaper than before, still proportional to the note (table above). The ceilings in
`Tests/RestyleBudgetSupport.swift` are the six decided at G-ceiling on 2026-10-10.

**Follow-ups, proposed as ledger entries and not built in N2.**

- `_` concealment: `_` emphasis delimiters stay unconcealed (§D2, `delimiterSpan(for:opening:)`); the
  parser now has the flanking rule that made them safe to hide, so concealing them is a decision
  for its own record.
- Transclusions in Oggi and Diario: they pass no `transclusions` (Context), so `![[nota]]` stays a
  link there; §D8 gave them the view query source only.
- Tasks on the list column (ADR-0081 Neutral): a task's checkbox keeps its own column.
- The `runPasses` double pass (§D5, "Outside the measurement"): a keystroke in the app runs the
  pipeline at least twice, and the budget measures `textDidChange` only. Fixing it would change what
  the six numbers mean, so it needs its own record and its own "before".
- Restyle only the edited paragraph (Alternatives, deferred): the "after" says the whole-document
  restyle is where the cost lies, so it is the change that would move these rows. Evaluation: worth
  its own chain with §D3's corpus as the safety net.

**Gates.** Decided on 2026-10-10: G-ceiling (the six ceilings), G-corpus (the classed diff, 21 A, 0 B,
0 C) and G-caret (the 49 to 48 caret assertion, the two `EditorHeightTests`, the arm count 7 to 9,
each with its reason in the test). Open: G-grow (§D7's hand check, which the editor's per-keystroke
cost still blocks at 50 KB and above, see §D9) and ADR-0081's G3.

## References

- ADR-0077 §D1/§D5/§D7, ADR-0018 §D1, ADR-0028 §D6, ADR-0029 §D10/§D17, ADR-0030 §D6, ADR-0033,
  ADR-0081 (the same milestone).
- `Sources/Features/Editor/MarkdownStyler.swift`, `Sources/Core/Markdown/MarkdownInline.swift`,
  `Sources/Core/Markdown/MarkdownBlocks.swift`, `Sources/Core/Editor/ListContinuation.swift`,
  `Sources/Features/Editor/NoteTextView+Coordinator.swift:188-222, 498-541`,
  `Sources/Features/Editor/NoteTextView+ListEditing.swift:61-69`,
  `Sources/Features/Workspace/CardTextView.swift:368-383`,
  `Sources/Features/Editor/EditorColumn+Text.swift:248`.
- `Tests/NoteExportGoldenCorpus.swift` (the corpus shape), `Tests/NoteListEditingTests.swift`.
- Root `SPEC.md` R-15 to R-19, Decisions, Constraints, Test seams 2 and 3; `PG-347`, `PG-385`.
