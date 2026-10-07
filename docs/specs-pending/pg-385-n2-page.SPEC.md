Status: Approved (2026-10-06)

# SPEC — N2 The page, part one: markers in the gutter, a measured keystroke, one grammar (PG-385, absorbs PG-347)

## Destination

A SPEC handed to `/workplan`, built as one mockup PR plus one code PR (about three `/build`
sessions) and shipped in that order. It closes ledger `PG-385` (#887) and `PG-347` (#762), and
flips ADR-0081 and ADR-0082 from proposed to accepted at the code PR's merge.

This is the N2 slice of the note-workflow SPEC approved on 2026-10-04 (milestones N1 to N5, roadmap
`docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §N2). Its requirement numbers R-13 to R-19 are
kept, because ADR-0081, ADR-0082 and the N2 plans cite them. No design decision is reopened; facts
were re-read on `origin/main` @ `9103768f` (2026-10-06), after N1 merged (PR #897, #905).

## Objectives

- A revealed list, heading or quote marker no longer moves the line: the content's horizontal origin
  is the same whether the marker is concealed or revealed, so arrow-down through a nested list moves
  no glyph sideways (R-13, R-14).
- The cost of a keystroke in a long note becomes a number that is measured every turn and guarded by
  a ceiling, and the two whole-document costs the header of the editor already documents are scoped
  (R-15, R-16, R-17).
- The editor has one grammar: the styler classifies through the same block and inline parsers the
  reading surfaces and the HTML export use, so `file_name_here` is plain in the editor as in the
  export (R-18, closes PG-347).
- Oggi, Diario and Workspace cards draw the same spans as the Note pane where ADR-0029 allows it
  (R-19).

## Scope and non-goals

In: roadmap N2 tasks 1 to 8; ADR-0081 (gutter reveal, amends ADR-0028 §D4 and ADR-0018 §D2) and
ADR-0082 (styler over the shared parsers, extends ADR-0077 §D1, closes PG-347); the SPEC (app) §5
amendment the roadmap §4 names for N2.

Out: concealing `_` emphasis delimiters, transclusions in Oggi and Diario, restyling only the edited
paragraph, the cursor and hover work of PG-219 and N3, every construct N5 adds. Detail under Out of
scope.

## Decisions

- **Gutter reveal by indents, the characters stay** — a revealed marker hangs left of a fixed
  content column through the paragraph's own first-line and head indents, measured in the page's body
  face; every `NoteTextView` paragraph starts its content at a `spacing.gutter` token, the container
  inset shrinking by the same amount so the readable width does not move. Rejected: keeping ADR-0028
  §D4's accepted horizontal shift (the defect being fixed); inserting or deleting characters to
  compensate (TextKit 2 forbids changing a paragraph's length mid-layout, ADR-0028); a per-width
  special case (the style would depend on the view's width and restyle on resize).
- **The gutter's value, the heading marker's face, the quote step and the permanent `H2` badge are
  decided by the person on the mockup** — ADR-0081's gates G1 and G2; the proposal is 48 pt, caption
  face, a quote step of 0.75 em, no badge. SPEC §11.1 requires the mockup first, as its own PR.
  Rejected: deciding them in code review (a visible change must be seen on the Debug build first).
- **One token layer in the shared parsers, the styler maps it onto its unchanged `Span` enum** —
  `MarkdownBlockParser` and `MarkdownInlineParser` gain ranged tokens; their value forms become
  projections of them; the styler's private recognisers are deleted and every consumer of `Span`
  stays untouched. Rejected: porting the flanking rule into the styler's scanner (closes PG-347 and
  keeps two grammars, which is its cause); consuming the value forms as they are (no positions, so
  recovery by text search is ambiguous and quadratic); two walkers sharing predicates (precedence
  would still be stated twice).
- **A golden corpus is captured from the old styler before it changes, each difference classed A, B
  or C** — A is a fix, B a deliberate change, C a regression and blocks the merge; a C is fixed in the
  parser or the mapping, never re-captured. Rejected: a hand-written expected output (it would encode
  today's beliefs, not today's behaviour).
- **`>YYYY-MM-DD` at the start of a line is a scheduling token in the shared block grammar** — the
  editor has always read it so, and the app's SPEC §7.1 makes it the scheduling syntax; `> 2026-10-04`
  with a space stays a quote. The exporter's output changes for this one input (class A there).
  Rejected: leaving the parser reading it as a quote (the two surfaces would keep disagreeing).
- **The keystroke budget is measured as thread CPU time, minimum of K runs, and its ceiling is set
  from measurement** — wall time is printed and never asserted (the suite shares the machine with
  concurrent builds, PG-331); the test lands first with the numbers of today's code and provisional
  ceilings, and the person fixes the final six at a gate. This SPEC fixes the method, not the number.
  Rejected: a mean on wall time (one-sided noise leaks into the number); a ceiling guessed up front.
- **Renumbering rewrites only the edited ordered run, inside the keystroke's undo step** — the edited
  lines widened by one line on each side; the caret mapped through the edit, which moves the pinned
  caret assertion from 49 to 48 on purpose. The Workspace card keeps its whole-text path (a card
  holds a few lines). Rejected: renumbering after a delay (a second undo step and a second
  `textDidChange`); scoping the card too (buys it nothing).
- **Growing to fit lays out the caret's fragment plus the viewport, never the document** — with the
  hand check on a 1 MB note as the acceptance that matters, because two earlier fixes to this line
  passed the unit suite and failed in the app; two existing height tests are restated, with the
  reason stated first. Rejected: dropping the layout call and trusting the estimate (the 187 pt
  defect the header documents). If the hand check fails, the fallbacks are chosen at the gate, not
  built speculatively: scope only above a size threshold, or extend to the document end near it.
- **`_` emphasis stays unconcealed** — the styler styles a `_` run the parser accepts and keeps its
  delimiters visible. Rejected: concealing them now (a visible change no N2 criterion asks for; a
  small follow-up once the corpus has landed).
- **Oggi and Diario get one shared query-source factory; cards gain quote and rule concealment** —
  the three hosts cannot build three different sources; tables and view blocks stay out of cards.
  Rejected: copying the source construction into the two panes (drift).
- **No GUI test in N2** — the gutter is proven by hosted in-process tests, the budget by a unit-suite
  test; origin: the repo's merge-gate rule and the chain SPEC's bound on GUI tests.

## Constraints

- **The file never changes shape**; every change is display-only — origin: CLAUDE.md principles 1 and
  4, SPEC §4. No frontmatter, tag, index-schema or protected-interface change.
- **Concealment keeps the character count**; what must look different is drawn by paragraph style or
  layout fragment — origin: ADR-0028, the TextKit 2 design note.
- **One grammar**: new constructs enter the shared parsers first (N5 depends on this) — origin:
  ADR-0077 §D1, roadmap §0.
- **Tokens only**: the gutter is a key in both theme files and in the spacing token type — origin:
  CLAUDE.md design system rule. N1's paragraph-spacing token and heading faces are composed with,
  never replaced.
- **The shared parser files compile into `perg` and `pergamenum-mcp`**, so the token layer imports
  Foundation only — origin: CLAUDE.md, ADR-0001 §D1.
- **A test changes only with its reason stated first** — origin: the repo's rule; applies to the
  pinned caret assertion (49 to 48) and the two height tests.
- **Mockup before code, as its own PR; SPEC (app) amendments are a human gate** — origin: SPEC §11.1.
- **The PG-219 and N3 work edits hover and tracking-area handling in the same coordinator files**;
  N2 owns `textDidChange` and the grow-to-fit routine, and whichever merges second rebases through
  `sync_operation` — origin: user instruction. At this base the PG-219 branch holds no change to
  those files yet.

## Stack

Swift 6, AppKit TextKit 2 (`NSTextView`, paragraph styles, layout fragments), Swift Testing, `perg`
and `pergamenum-mcp` compiling the shared Core files. No new dependency.

## Data model

None. No new storage; one new spacing token. The token layer is in-memory and recomputed per scan.

## API / interfaces

- Shared parsers: a per-line token function and an inline token function reporting ranges; the
  existing value-returning functions keep their signatures and become projections (their suites stay
  green byte for byte, bar the one date-at-line-start case).
- Styler: `spans(in:)`, `StyledRange` and every `Span` case unchanged.
- List continuation: a scoped renumbering that returns the changed range, its replacement and a
  location mapping; the whole-text form stays for the card and as the fallback when no edited range
  is known (an undo, a programmatic replace).
- Grow to fit: same signature, narrower layout.
- Query source: one factory shared by the Note pane and the Oggi and Diario panes.
- Budget: a unit test and a script that runs it alone and prints a table of six lines.

## UI flows

- The mockup page (design gallery): concealed and revealed rows drawn under each other with a guide
  at the content column, for a nested list, H1 to H6, a one- and two-level quote, narrow and readable
  widths, the optional `H2` badge, and three gutter values.
- In the app: caret on a list item, heading or quote reveals its marker in the margin; content does
  not move. At narrow width the whole column moves 24 pt right once, as the mockup shows.

## Edge cases

- Ordered markers: the digits are already in the file; only the indent changes (`1. ` and `12) `
  hang the same way).
- A wrapped list item: the second line aligns under the first line's text in both states.
- An H6 reveals `###### `, the widest run the gutter must hold; a heading with no title.
- A deleted separator that merges two ordered runs is seen by the scoped renumber (hence the one-line
  widening); an undo or a programmatic replace takes the whole-text fallback.
- A long note: type at the end, in the middle, Cmd+Down, scroll to the end, click low in the pane; the
  caret stays visible and the last line is reachable.
- `file_name_here` and `2 * 3 * 4` read as plain text; `nome_file_lungo` is not emphasis.
- A `pergamenum-view` fence in Oggi or Diario renders; there is no "Modifica query" control there.
- A Workspace card keeps its line-height multiple when a quote is concealed.
- A transcluded note's drawn copy keeps no gutter.

## Test seams

Confirmed in the interview (2026-10-06), existing seams first, highest level possible:

1. Pure unit tests in the unit suite for the token layer, the projections, the scoped renumber and
   the ceiling arithmetic.
2. The styler golden corpus, captured on the base the build starts from before any styler change (the
   export corpus's shape), reusing every export corpus input plus the editor's own constructs.
3. The restyle budget test in the suite the Stop hook runs, with a bench script for the table.
4. Hosted-view (in-process) tests for the gutter geometry (content origin equal in both states,
   measured through the real layout), for grow-to-fit on a long note, and for Oggi, Diario and card
   parity.

No GUI test. Human checks: the mockup, the corpus diff, the six ceilings, the 1 MB grow hand check
and the arrow-down hand check, each on the Debug build.

## Success criteria

- [ ] R-13 — For bullet, ordered and task items at every nesting level, the content's horizontal
  origin is identical whether the marker is concealed or revealed.
- [ ] R-14 — The same holds for headings and quotes at the narrow width and at the readable width.
- [ ] R-15 — A restyle budget test measures synthetic notes of 50 KB, 200 KB and 1 MB, with and
  without fences and view blocks, prints the numbers and fails above the ceiling ADR-0082 records.
- [ ] R-16 — Renumbering after an edit rewrites only the edited ordered run, and one edit is one undo
  step.
- [ ] R-17 — Growing the view to fit lays out up to the caret's fragment plus the viewport, not the
  whole document, and the caret stays visible in a long note.
- [ ] R-18 — The styler classifies through the shared block and inline parsers; the golden corpus
  captured before the change classes every difference, none is C; `file_name_here` is plain in the
  editor as in the export (PG-347, #762).
- [ ] R-19 — A `pergamenum-view` fence renders in the Oggi and Diario panes; Workspace cards conceal
  quote and rule markers; tables and view blocks stay out of cards.
- [ ] R-44 — N2 ships as a mockup PR approved on the Debug build, then one code PR; it closes #887 and
  #762, closes ledger `PG-385` and `PG-347`, and flips ADR-0081 and ADR-0082 to accepted with the
  landing evidence, the ceiling table of ADR-0082 §D9 filled (no-test: release process, checked at
  each /ship gate).
- [ ] R-45 — The app, `perg` and `pergamenum-mcp` build after the change, and `scripts/mcp-smoke.py`
  passes because the connectors compile the new token file (no-test: build and smoke script, not a
  unit test).
- [ ] R-46 — SPEC (app) §5 states that block markers reveal in the gutter and that the keystroke
  budget is a measured number with a recorded ceiling; the person approves the wording before it
  lands (no-test: documentation text only, a human gate under SPEC §11.1).

## Not yet specified

_none_ — three values are decided on purpose by measurement or by eye, with a gate each: the gutter
and its companions (mockup), the six ceilings (after the work), and the grow-to-fit fallback if the
hand check fails.

## Out of scope

- **Concealing `_` emphasis delimiters** — a visible change no N2 criterion asks for; proposed as a
  small ledger follow-up once the corpus has landed.
- **Transclusions in Oggi and Diario** — they pass none today, so `![[nota]]` stays a link there;
  named, proposed as a ledger entry.
- **Restyling only the edited paragraph** — the larger win if the budget shows styling itself is the
  cost, and a larger change (every multi-line construct makes "the edited paragraph" a range);
  deferred, not rejected: the measured numbers and the corpus decide whether it is needed.
- **The pointer, hover and cursor work** — PG-219 and N3 own it.
- **Any construct N5 draws** — inline code pills, highlights, fence chrome, callouts, quote bars.
- **On-disk format, frontmatter schema, index schema** — unchanged.

## Domain terms

- **Gutter** — the left margin inside the text column where a revealed block marker hangs; the
  content column starts to its right and does not move.
- **Concealed / revealed** — a block marker is concealed (drawn as a glyph or hidden) unless the caret
  is on its paragraph, where it shows as the file spells it.
- **Golden corpus** — inputs plus the old styler's captured output, so a rewrite is judged against
  behaviour, not belief; differences are classed A (fix), B (deliberate), C (regression).
