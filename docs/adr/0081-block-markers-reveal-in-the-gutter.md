# ADR-0081: Block markers reveal in the gutter

- Status: **proposed**. Written before the implementation, for `PG-385`/#887 (milestone N2 of the
  note-workflow chain). Flips to `accepted` with the merge of the N2 code PR, never with the mockup
  PR (`docs/adr/README.md` rule 2).
- Date: 2026-10-04. Written against `48a2d912` (`origin/main` at the same commit). Every line
  number below was read there.
- Number: `0081` was reserved for this record by the dispatch that planned N2 and was checked free
  on every ref on 2026-10-04 (`git log --all -- 'docs/adr/0081*'` printed nothing). Check again
  immediately before the merge (rule 1).
- Source: root `SPEC.md` (Approved 2026-10-04), requirements R-13 and R-14; background in
  `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 "N2" and
  `docs/20261002_Pergamenum_NoteWorkflowReport.md` R-1. Plans:
  `docs/plans/note-workflow-n2-mockup.md` (mockup PR) and `docs/plans/note-workflow-n2.md`
  (code PR). Assumes N1 (`docs/plans/note-workflow-n1.md`) merged first.
- **Amends** ADR-0028 §D4 (the last paragraph: "A revealed paragraph gets none of this ... The
  item therefore shifts horizontally ... accepted") and ADR-0018 §D2 (what "reveal" draws, for
  list, heading and quote paragraphs only; the four triggers are unchanged). **Extends** ADR-0029
  §D1 (where a quote's bars sit), ADR-0030 §D6 (the readable-width inset gains a gutter it is
  measured against) and ADR-0019 §D2 (a full-width decoration reads its column at drawing time).
  Amends nothing else.

## Context

Arrow down through a nested list and every item jumps sideways as the caret enters it. The cause
is one sentence of ADR-0028 §D4: a revealed paragraph "gets none of this: no substitution, no
paragraph style, the raw source as written", so `listParagraph(at:storage:)`
(`EditorDecorationDelegate+ListRendering.swift:25`) returns `nil` for the caret's paragraph, the
indent its concealed twin carried by paragraph style disappears, the collapsed leading whitespace
comes back at its source width, and the content moves by the difference. Headings do the same
through the generic collapse path (the `## ` that was 0.01 pt wide is drawn at heading size in
front of the title), and quotes through `quoteParagraph` (`EditorDecorationDelegate+QuoteRendering.swift`),
which also returns `nil` when revealed. ADR-0028 accepted the motion because "the revealed line
must be the file's line". The person who uses the editor every day reports it as the most
distracting thing on the page (report R-1); the SPEC makes "the content's horizontal origin is
identical whether the marker is concealed or revealed" a criterion (R-13 for list items at every
level, R-14 for headings and quotes at the narrow and the readable width).

Measured facts this decision rests on, all read on `48a2d912`:

- `NSParagraphStyle.firstLineHeadIndent` and `headIndent` are documented "always nonnegative"
  (`NSParagraphStyle.h`, MacOSX27.0 SDK, lines 210 and 229). A marker can therefore hang left of
  the content only if the content itself sits at a positive indent inside the text container.
- The roadmap's sketch for headings and quotes (`firstLineHeadIndent = headIndent − width(marker)`)
  needs a negative first-line indent for any paragraph whose content starts at the container's
  edge, which is every heading and every top-level quote today. It cannot be implemented as
  written. A band of container width to the left of the content column, reserved for markers, is
  required: this ADR calls it the gutter.
- The readable-width inset (`NoteTextView.Coordinator.horizontalInset(viewWidth:cap:minimum:isOn:)`,
  `NoteTextView+Coordinator.swift:627`) is `max(24, (W − 720) / 2)`; `lineFragmentPadding` is 5.
  Below a 768 pt wide view, and always with «Larghezza leggibile» off, there are 24 + 5 points to
  the left of the text, not enough for `###### `.
- `ListMarkerRendering.paragraphStyle(level:font:basedOn:)` (`ListMarkerRendering.swift:56`) sets
  `firstLineHeadIndent = 1.5 em × depth` and `headIndent = first + 0.75 em`, and the 0.75 em is
  "deliberately not measured" (`:85-88`). A concealed item's content therefore starts at
  `first + width("• ")`, which equals `headIndent` only by luck of the face; wrapped lines and the
  first line already disagree by a fraction of a point to a few points.
- A task line is not a list line (ADR-0028 §D2) and its checkbox is never revealed
  (`EditorDecorationDelegate+CheckboxRendering.swift:21`), so a task's content never moves today.
- Four places read "the column" as the text container's width minus the line fragment padding:
  `HorizontalRuleFragment.ruleWidth` (`HorizontalRuleFragment.swift:33`),
  `TranscludedLineFragment.containerWidth` (`TranscludedLineFragment.swift:82`),
  `NoteTextView+Transclusion.swift:119` and `EmbedResize.swift:62`. Table and view-block
  attachments size themselves from `proposedLineFragment`.
- `EditorDecorationDelegate` is shared by the note editor (Nota, Oggi, Diario all host
  `NoteTextView`) and the Workspace `.text` card (`CardTextView.swift:138-139`, ADR-0028).

## Decision

### D1. Every paragraph of a `NoteTextView` starts its content at a gutter

A new spacing token, `spacing.gutter`, in both theme files and in `SpacingToken`. Its value is
decided at the mockup gate (G1 below); the proposal is 48 pt, which holds `###### ` in the marker
face of §D4 with room to spare and is `spacing.xl` plus `spacing.s`.

Every paragraph a `NoteTextView` lays out carries `firstLineHeadIndent = headIndent = G` and
`tailIndent = −G` in its base paragraph style. The base style is built once, where it is built
today: `MarkdownAttributedText.StyleContext` gains a `gutter` (default `0`), and
`NoteTextView.Coordinator.applyStyling` passes the token's value. Every style composed later with
`basedOn:` (headings, list items, the line-height multiple of ADR-0030 §D6) inherits the indents
for free. A transcluded note's drawn copy (`MarkdownAttributedText.attributed(_:theme:links:)`)
keeps `gutter: 0`.

The text container inset becomes `max(0, readableInset − G)` on both sides, computed by one pure
function beside `horizontalInset`, which is left unchanged. The arithmetic, at G = 48:

| View | Today: content from the view's left edge | After |
| --- | --- | --- |
| ≥ 816 pt wide, readable width on | `(W − 720) / 2 + 5` | identical: inset shrinks by G, indent adds G |
| 768 to 816 pt | `(W − 720) / 2 + 5` | `53`, the column narrows by up to 24 pt a side |
| < 768 pt, or readable width off | `29` | `53`, the column narrows by 24 pt a side |

The right edge mirrors the left through `tailIndent`, so the style never depends on the view's
width: a window resize changes the inset, as today, and never restyles the note. At readable width
nothing a person can see moves for concealed text; at narrow width the whole column moves 24 pt
right, which the mockup shows on purpose.

### D2. A list item hangs its marker from a measured content column, revealed or not

The content column of a list item at level `L` (1...6, `ListNesting`'s level) is
`C(L) = G + 1.5 em × L + 0.75 em`, the same arithmetic as today plus the gutter. Wrapped lines sit
at `headIndent = C(L)`. The first line starts at `firstLineHeadIndent = max(0, C(L) − w)`, where `w`
is the measured width, in the page's body face, of the run actually displayed before the content:

- concealed bullet: `• ` (the substituted glyph and its space);
- revealed bullet: `- ` (or `* `, `+ `, as the file spells it);
- ordered, either state: the file's digits, delimiter and space, `1. ` or `12) `.

So the content of the first line and of every wrapped line starts at exactly `C(L)` in both states.
`w` is measured with the font, not assumed (the 0.75 em constant stays as the default when no
measurement is given, which keeps `ListMarkerRendering`'s pinned arithmetic tests valid), and
memoised per (run, face) on the delegate, since a page lays out the same few runs thousands of
times.

The leading indentation run stays drawn in `collapsedFont` **in both states**. The revealed line
shows the file's marker characters exactly as written (the `-` not the `•`, the digits) and keeps
the level's position; it does not show the raw spaces or tabs in front of the marker. This is the
one place where the revealed line is not character-for-character the file's line, and it is a
deliberate deviation from ADR-0028 §D4's rationale: the level is still visible (it is the hanging
position), Tab and Shift+Tab change it through the list commands, and a raw run of spaces drawn at
source width is precisely what moves the content.

`listParagraph(at:storage:)` therefore no longer returns `nil` for a revealed paragraph: it applies
the style and, when revealed, substitutes nothing. `ListMarkerRendering.paragraphStyle` gains
`gutter:` and `hanging:` parameters (both defaulted) instead of a `revealed:` flag: the hanging
width is the only thing the state changes, so the state is not a parameter of the arithmetic.

Task items: a task line keeps ADR-0028 §D2's own layout (raw indentation, `- [` collapsed, the
checkbox glyph, never revealed), shifted by G like every paragraph. It satisfies R-13 already,
since nothing in it is revealed, and a test pins that it stays so. Putting tasks on the list
column `C(L)` is **not** done here; see Consequences.

### D3. A quote hangs its bars, and its revealed `>` run, the same way

A quote at level `Q` puts its content at `C_q(Q) = G + 0.75 em × Q`. Concealed, the displayed run
is ADR-0029 §D1's one `▏` per `>` with the separating spaces collapsed; revealed, it is the file's
`> > ` run. Both hang to `C_q(Q)` through `max(0, C_q(Q) − w)`. Wrapped lines sit at `C_q(Q)`. The
step per level (0.75 em) is part of gate G1: the mockup may set it to 0, which puts the quote's text
on the body column and its bars wholly in the gutter.

### D4. A heading hangs its revealed `#` run in a smaller face

Concealed, a heading's content already starts at G (the `#` run is 0.01 pt wide). Revealed, the
`#` run and its space are drawn in the marker face, `font.caption` in `color.textTertiary` (the
colour headingMarker already takes), and hang: `firstLineHeadIndent = max(0, G − w)`. A smaller
face is not decoration: `###### ` at H6's 17 pt is estimated at 60 to 70 pt and would need a
gutter wider than the margin it sits in; at the caption face the estimate is 40 to 45 pt. Both are
estimates, not measurements. A test measures and asserts that the gutter holds `###### ` in the
marker face, so a theme that enlarges `font.caption` or shrinks the gutter fails loudly rather than
shifting headings again. The face reaches the non-`@MainActor` delegate as a pushed value, the way
`checkboxFont` does (ADR-0030 §D5), through a new `ProseTypography.gutterMarker(_:)`.

A heading is handled by a new branch of the substitution hook
(`EditorDecorationDelegate+HeadingRendering.swift`), active only when the delegate's gutter is
greater than zero and the paragraph is revealed. Changing a run's font is an attribute change, so
the paragraph keeps its stored length (the constraint of `NSTextContentManager.h:120`).

### D5. The optional permanent heading badge is a gate, not a default

The mockup draws a variant where a concealed heading shows a dim `H2` label in the gutter, so the
level of a heading is readable without moving the caret. If the person approves it at G1, it is
drawn by the heading's layout fragment, in the gutter, in `font.caption` and `color.textTertiary`,
for concealed headings only (revealed, the `##` itself is there). A folded heading already has its
own fragment (`FoldedHeadingFragment`); the badge drawing is one helper both fragments call, so a
folded heading keeps its badge. If the person does not approve it, nothing of this section is
built and the plan's task drops its sub-step. Either way the characters of the file are untouched.

### D6. Where there is no gutter, only lists hang

The Workspace `.text` card has no gutter: its delegate keeps `gutter = 0`. A list item still hangs,
because its own indentation (`C(1) = 2.25 em`) leaves room for any marker but a very long ordinal;
a heading or a quote in a card keeps today's revealed shift, because hanging needs room to the left
of the content and a card has none. This is an explicit no, recorded so nobody "fixes" it: a card
is a few lines wide and a 48 pt band inside it would cost more than the motion it saves. Wherever
`max(0, …)` clamps (a card's `1234. `, a quote nested five deep in the editor), the content moves by
the overflow only, never by the whole run.

### D7. Full-width decorations read the column, not the container

The rule line, the transcluded note, the transclusion's reserved width and the embed resize limit
all measured "container width minus padding". With a gutter, that is G too wide on each side. One
definition replaces the four: a pure `EditorGutter.columnSpan(containerWidth:padding:style:)` that
returns the leading offset and the width between `headIndent` and `−tailIndent` of the paragraph
style in force. The two fragments read the style of their own paragraph at drawing time
(ADR-0019 §D2's reason: a number pushed in goes stale on the next resize); the two coordinator
sites read the gutter from the theme they already resolve. Table and view-block attachments size
from `proposedLineFragment`; whether that rectangle already excludes the indents is not known from
the headers, so a hosted test pins that their drawn frame stays inside the column, and if it does
not they adopt `columnSpan` too.

### D8. What this ADR does not change

The four reveal triggers of ADR-0018 §D2, its per-paragraph invalidation, ADR-0037's span-grained
reveal (inline spans only, unaffected), the checkbox's never-revealed rule, the substitution length
rule, `HiddenMarker.Kind`, `MarkdownStyler.Span`, the file on disk. No GUI test (SPEC constraint):
the acceptance is hosted-view geometry tests plus the mockup and one hand check on the Debug build.

## Alternatives considered

- **Shift the whole text view frame left when a marker is revealed.** Moves every line of the note,
  not one, and setting this view's frame from inside a layout pass is exactly what cost the Diario
  everything typed into it (`growToFitTheText`'s header, `NoteTextView+Coordinator.swift:509-532`).
  Rejected.
- **Draw the revealed marker from a layout fragment in the margin and keep the characters
  collapsed.** It looks right and moves nothing, but the characters the caret is walking over are
  0.01 pt wide: the caret is invisible on the marker, a selection of `## ` is a zero-width
  highlight, and Find lands on nothing (the very reasons ADR-0018 §D2 reveals at all). Rejected.
- **A negative first-line indent, as the roadmap sketched.** Not expressible: the SDK clamps both
  head indents to nonnegative values. Rejected on fact, not taste.
- **A gutter for headings only, lists left as ADR-0028 has them.** Lists are where the motion is
  worst (every item of a nested list, on every arrow key) and the list column needs no gutter at
  all, since a list item already has its own indent; leaving them out keeps the larger half of the
  defect. Rejected.
- **A gutter only on paragraphs that carry a block marker.** Body text, headings and lists would
  start at different x positions, so a concealed heading would sit 48 pt to the left or right of
  the paragraph under it. The column has to be one column. Rejected.
- **Keep the heading's `#` run at heading size and widen the gutter to fit it.** An estimated 70 pt of
  margin on every note, at every width, to serve a marker that is on screen only while the caret
  sits on a heading. Rejected in favour of §D4's smaller face; G1 can still revisit the face.

## Consequences

**Positive.** Arrow keys through a nested list, a heading or a quote move nothing horizontally. A
wrapped list item aligns under its own text exactly rather than by a 0.75 em guess. The column has
one definition, so the rule, the transcluded note and the embed limit cannot drift from the text.

**Negative.**

- At narrow widths (below 816 pt at G = 48, and always with «Larghezza leggibile» off) the column
  moves right by `G − 24` and narrows by as much on each side. In the Diario pane, the narrowest
  host, that is visible; the mockup shows it before anything is built.
- In a revealed list item, the caret steps over the collapsed leading whitespace one invisible
  character at a time (Arrow-left from the start of the content takes one press per indent
  character before it leaves the marker). The checkbox has had the same property since it became
  never-revealed.
- Measuring the displayed marker run costs one text measurement per distinct (run, face), memoised;
  it runs in the layout pass, not in the styling pass, so ADR-0082's restyle budget does not see it.
- A revealed heading's `#` run is smaller than its title, which reads as a label rather than as the
  file's text; G1 decides whether that is acceptable.

**Neutral.**

- Task items stay off the list column. Mixed lists (bullets and tasks at the same level) keep today's
  ragged left edge. My evaluation: aligning tasks to `C(L)` is worth doing, small, and in the spirit
  of this ADR, but it changes ADR-0028 §D2's "a checkbox line keeps exactly today's appearance" and
  the checkbox's collapsed runs, which no SPEC criterion asks for; it is proposed as a ledger entry,
  not built in N2.
- `_` emphasis, inline spans and every other marker reveal exactly as before.
- The `.text` card changes only for lists (they hang) and, through ADR-0082's R-19 work, gains quote
  and rule concealment.

## Gates

- **G1 (mockup, before any view code):** the gutter's value; the heading marker face; the quote step
  (0.75 em or 0); the narrow-width shift accepted as drawn.
- **G2 (mockup):** the permanent `H2` badge, yes or no (§D5).
- **G3 (hand check on the Debug build, before merge):** Arrow-down through a ten-item nested list,
  a heading of each level and a two-level quote at a narrow and a readable width; no glyph moves
  horizontally. Oggi and Diario at their usual size.

## References

- ADR-0018 §D2, ADR-0028 §D2/§D4, ADR-0029 §D1/§D17, ADR-0030 §D5/§D6, ADR-0019 §D2, ADR-0037,
  ADR-0082 (the same milestone).
- `NSParagraphStyle.h` (MacOSX27.0 SDK) lines 210 and 229; `NSTextContentManager.h:120`.
- `Sources/Features/Editor/ListMarkerRendering.swift`, `EditorDecorationDelegate+ListRendering.swift`,
  `EditorDecorationDelegate+QuoteRendering.swift`, `EditorDecorationDelegate+CheckboxRendering.swift`,
  `MarkdownAttributedText.swift`, `NoteTextView+Coordinator.swift:541-631`,
  `HorizontalRuleFragment.swift`, `TranscludedLineFragment.swift`, `EmbedResize.swift`.
- Root `SPEC.md` R-13, R-14; roadmap §2 N2 tasks 1 to 3; report R-1.
