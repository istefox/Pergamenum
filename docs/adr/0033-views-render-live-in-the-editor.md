# ADR-0033: A view renders in the editor, in an attachment that hosts the renderer it already had

- Status: proposed
- Date: 2026-09-06. Written after reading every file it names, at the line, on the working tree
  at `dfcccb8`. Two claims that could not be read out of the source or the SDK are named as
  probes in D16.
- **Relocation note:** this file is written at `docs/architecture/ADR-0033-…` because that is the
  architect's write scope; the orchestrator relocates it to
  `docs/adr/0033-views-render-live-in-the-editor.md`, which is where this repo's ADRs live and
  which is the path every reference below assumes. Same convention ADR-0029's plan header records.
- **Does not supersede ADR-0009.** Its query grammar (§D3), its closed field table (§D2), its
  no-materialisation rule (§D6), its cost rule (§D7) and its board write semantics (§D5, both
  amendments included) are carried forward unchanged and are not reopened. What this ADR decides is
  *where the result is drawn and what a click on it does* — §D5's own "renderers stay in
  `Features/Views/` and see only the evaluated result" is the sentence this ADR keeps by reusing
  those renderers rather than writing second ones.
- **Does not supersede ADR-0029.** It is that ADR's §D4/§D5/§D6 mechanism applied to a sixth
  construct, with three deliberate divergences, each argued at the point it is made: the host store's
  key (D3), the reveal rule (D4), and the closed-fence precondition (D6). ADR-0029 §D17's
  Workspace-card exclusion is reaffirmed, not weakened (D13).
- Depends on: **ADR-0009 §D1/§D2/§D4/§D5/§D6/§D7**, **ADR-0029 §D4/§D5/§D6/§D9/§D17**,
  **ADR-0018 §D1/§D2/§D3/§D5** (the substitution mechanism and the reveal rule this one diverges
  from in exactly one place), **ADR-0019 §D2/§D7** (the attachment-bounds negotiation and
  `replaceAtomically` — the latter is *not* needed here, and D11 says why),
  **ADR-0010 §D3** (`MarkdownBlocksView` as the transclusion renderer, untouched),
  **ADR-0014 §D4** (`onDayChange`, already inside `RenderedViewBlock`).

## Context

**What broke, and it is a regression rather than a gap.** PG-012 shipped all four renderers on
2026-08-20 — `ViewTableRenderer`, `ViewGalleryRenderer`, `ViewCalendarRenderer`, `ViewBoardRenderer`,
all reached through `RenderedViewBlock` — inside the editor's Lettura half. ADR-0029 removed Lettura
on 2026-09-02/03 and did not re-point `RenderedViewBlock` at the unified editor. Grepped on the
working tree: `RenderedViewBlock` has **one** call site in the whole repository,
`MarkdownBlocksView.swift:70`, and `MarkdownBlocksView`'s own live callers are
`TranscludedNoteView.swift:104` (the `![[nota]]` read-only rendition) and `NoteExporter`'s HTML path.
Neither is the editor. So a `pergamenum-view` fence in an open note is fenced source text and
nothing else, and there is no reachable surface in the running app where a board card can be dragged.

ADR-0029 anticipated this to the letter and left the door open rather than closing it.
`EditorColumn+Text.swift:194-198` still carries `viewQuerySource`, unreferenced, with the comment
*"It is the app's only `ViewQuerySource`, so whichever surface renders an in-note `pergamenum-view`
fence next will want exactly this."* This ADR is that surface. The evaluator, the four renderers, the
board's guarded write, the `onDayChange` re-evaluation and the query source itself are all already
written, tested and merged. **Nothing in the query layer is being built here.**

**Three findings that correct the SPEC's own premises**, all read from the source before this ADR was
written, and all load-bearing:

1. **R-09 is not a restoration, it is net-new.** `ViewRowRenderers.swift` and
   `ViewGridRenderers.swift` contain no `Link`, no `Button`, no `onTapGesture` and no `openURL` —
   grepped, zero hits across both files. A table row's title is drawn in `.accentPrimary`, which
   *looks* like a link and has never been one. Lettura did not open a note from a view row either.
   So "clicking a row navigates to the linked note" is a new capability this chain adds, not
   behaviour ADR-0029 took away, and it costs a new optional input threaded through the renderers.
2. **R-08 and ADR-0009 §D1 point in opposite directions, and the conflict is real rather than
   apparent.** §D1 is explicit: *"A block that does not parse renders as an error naming the line,
   never as an empty result."* R-08 asks for the opposite in the editor: no attachment, plain fenced
   text, no error UI. D7 resolves it and states what is given up.
3. **The SPEC's reveal rule and its own layout rule collide if reveal is keyed the way ADR-0018 keys
   it.** ADR-0018 §D2's revealed set is a set of *paragraph* offsets. The fence's body lines are out
   of the layout, so the caret cannot be in one; the only paragraph it can be in is the opening
   fence. The moment reveal brings the body back and the caret moves down into it, the opening fence
   is no longer the caret's paragraph, the block re-hides, and the caret is inside a paragraph that
   has just left the layout again. That is a loop, not an edge case. D4 changes the key.

**Two constraints from ADR-0029's Context that still hold verbatim and are not re-derived here:**
a displayed paragraph may not change length (`NSTextContentManager.h:120`), and
`EditorDecorationDelegate` cannot be `@MainActor` (Swift 6 refuses both conformances,
`EditorDecorationDelegate.swift:25-26`), so it owns no view and is handed finished values —
`renditions`, `embedRenditions` and `tableViews` are three existing instances of that crossing.

**One thing this repo has done once and would now do a second time, differently.** ADR-0029 §D6 put
a real `NSView` in the text through `NSTextAttachmentViewProvider`, and its §D16 probe 2 was a gate
on the whole design. That gate was passed and the mechanism shipped (`TableAttachment.swift`,
`TableGridStore.swift`). What was **not** answered then, and is not answered by it now, is whether an
`NSHostingView` — SwiftUI, with `@State`, `.task`, and a `.draggable`/`.dropDestination` pair —
behaves inside that same provider. D16 is the probe list for exactly that gap, and its second entry
is a gate on R-04 in the same sense probe 2 was a gate on ADR-0029's D4.

## Decision

**D1. A closed `pergamenum-view` fence is one attachment on its opening-fence paragraph; its body
lines and its closing fence line leave the layout entirely. Two hooks, no new mechanism.**

For a fence region `CodeFence.regions(in:)` reports with `language == ViewBlock.language`, whose body
parses (D7) and which is closed (D6):

- the **opening fence line's paragraph** is substituted: its first character becomes `\u{FFFC}`
  carrying a `ViewBlockAttachment`, the rest of the line is collapsed to `collapsedFont`. One
  character out, one in, the paragraph's own length unmoved — `embedParagraph`'s arithmetic and
  `tableParagraph`'s, reused rather than restated;
- **every body line and the closing fence line** are reported `false` from
  `textContentManager(_:shouldEnumerate:options:)`. They occupy no height, draw nothing, and the
  caret cannot walk into them — ADR-0018's own measured property of that hook.

The closing fence line is in the hidden set and the table's analogue has no equivalent of it: a
table ends at its last body row, a fence ends at a line of backticks that would otherwise sit
under the drawn view as a stray ``` ``` ```. Naming it here because it is the one place the
arithmetic differs from `applyTables`'s and it is the kind of difference a coder copies past.

**D2. The attachment's view is an `NSHostingView` over the `RenderedViewBlock` that already exists.
The four renderers are not rewritten in AppKit, and there is no second implementation of anything.**

`ViewBlockAttachment: NSTextAttachment` overrides `viewProvider(for:location:textContainer:)` exactly
as `TableAttachment` does, returns a provider whose `loadView` assigns a host **it was given**, and
sets `tracksTextAttachmentViewBounds = true`. The host is an `NSHostingView` whose root view is

```
ScrollView { RenderedViewBlock(source:notePath:vaultRoot:thumbnails:queries:onEditSource:onOpenNote:) }
    .environment(\.theme, theme)
```

built and owned by the Coordinator on the main actor, handed to `EditorDecorationDelegate` as a
finished `[Int: NSView]` keyed by paragraph offset — the crossing `apply(tableViews:)` already makes.
The delegate carries a reference and calls nothing.

This is the decision the whole ADR turns on, and the argument for it is not convenience. The four
renderers are ~800 lines of theme-tokened SwiftUI with an evaluated-result contract, a board write
path with a differential lint guard, an empty state, an error state and a day-change observer. A
second, AppKit rendering of them would be two answers to every question ADR-0009 §D5 already
answered once — and the surface where they would disagree is a transcluded note showing a board the
editor draws differently, which is the exact failure ADR-0029 §D10 refused for the table grammar and
ADR-0018 §D1 refused for markers. One renderer, two hosts.

**D3. The host store is keyed by the fence's ordinal within the note, not by its paragraph offset.
This is a deliberate divergence from ADR-0029 §D6's `TableGridStore`, and the reason is ADR-0009 §D7.**

`TableGridStore` keys by header offset and prunes to the identities the current pass found, so an
edit *above* a table drops its grid and builds a new one. For a grid that costs a re-layout, which is
nothing. For a view block it costs a **query evaluation**: a fresh SwiftUI view runs
`RenderedViewBlock`'s `.task(id:)` from scratch, `ViewEvaluator.evaluate` walks the index, and a
`text()` term reads every candidate file. Per keystroke typed above the fence. ADR-0009 §D7 is
explicit that a view evaluates *"on open, on an explicit refresh, and on a watcher change … debounced,
never per keystroke"*, so an offset key would break a decision this ADR is not entitled to reopen.

`ViewBlockHostStore` therefore keys by ordinal — the fence is the note's first, second, third
`pergamenum-view` block — which is stable under every edit that does not add or remove a block, and
unique, which a source-text key would not be for two identical fences in one note (and an `NSView`
has one superview, so a shared host is not a cosmetic collision but a broken layout). On each styling
pass the store **pushes a new root view into the existing host** rather than building one; SwiftUI
diffs it, and `.task(id: "\(source)|\(generation)|\(reloads)")` re-runs only when one of those three
actually changed. Inserting a fence above another shifts ordinals and re-evaluates the shifted one
once, which is correct and rare.

Rejected: **keying by offset, for symmetry with `TableGridStore`.** Symmetry is not worth a query per
keystroke, and the two stores are not the same kind of object: one vends a view whose content is the
note's own characters, the other vends a view whose content is a computation over the vault.

Rejected: **keying by the fence body's hash.** Unique enough in practice, not unique in principle,
and the failure mode is one `NSView` asked to be in two places.

**D4. Reveal is keyed on the fence's whole source range against the live selection, not on
`revealedParagraphs`. ADR-0018 §D2's mechanism is untouched; this construct simply does not use it.**

`applyViewBlocks` asks one question per fence: does `textView.selectedRange()` intersect this fence's
source range (opening line through closing line, inclusive)? If yes, the fence is revealed — no
attachment, no hidden lines, the raw source on screen and directly editable. If no, it is drawn.

The reason is Context finding 3: a paragraph-keyed reveal cannot survive the caret moving from the
opening fence line into the body it just revealed. A range-keyed one can, because the answer stays
`true` for every position inside the block. This is the only construct in the editor whose reveal
spans paragraphs, and it is the only one whose *hidden* extent does too — the two facts are the same
fact, which is why the key has to move with it.

ADR-0018 §D2's four triggers are not reimplemented and not replaced. A non-empty selection crossing
into the fence intersects its range and reveals it, which is trigger 2 arriving by a different road;
an IME composition and a find match do the same, since both are ranges. What is deliberately *not*
inherited is the per-paragraph granularity, and nothing else.

**D5. A selection change that crosses a fence boundary re-runs `applyStyling`, guarded by a change
check. No second, lighter pass is introduced.**

`textViewDidChangeSelection` already calls `applyReveal`. It gains one more call: recompute which
fence (if any) the selection is inside, and when that answer differs from the last one, call
`applyStyling(to:theme:)`. That pass already runs on every keystroke and is measured at 5.83 ms on a
17 KB note; a boundary crossing happens on the order of once per navigation, not once per arrow key,
and the guard is an `NSRange?` comparison.

Rejected: **a separate `refreshViewReveal(to:)` that recomputes only the hidden-line set and the
markers.** It would be a second producer of the same three values (`hiddenMarkers`, the hidden-line
set, the host map) that has to stay in step with `applyStyling` forever. The delegate's own header
forbids exactly this shape for its five inputs, and the argument transfers: one pass, called twice.

**D6. Only a closed fence renders. An unclosed one is left entirely alone, source and layout.**

`CodeFence.regions(in:)` runs an unclosed fence to the end of the text, deliberately and correctly —
*"while someone is typing the opening backticks, every note is briefly a note with an unclosed
fence."* Under D1 that would put the whole rest of the note out of the layout the instant somebody
typed ``` ```pergamenum-view ```. So a region qualifies only when its last line is a fence marker.
While the block is being written the note behaves exactly as it does today, and the attachment
appears when the closing backticks land — which is also when `ViewBlock.parse` first has a chance of
succeeding, so the two preconditions come true together rather than fighting.

**D7. A block that does not parse gets no attachment, and its source stays on screen. ADR-0009 §D1's
error card is not removed; it keeps the surfaces it already has.**

R-08 and §D1 genuinely conflict (Context finding 2) and this is the resolution, with what it costs
stated rather than glossed:

- §D1's actual fear is an **empty result silently standing in for a broken query** — *"an empty list
  is indistinguishable from a vault that lost its notes."* Raw fenced source is not an empty list; it
  is the most specific thing the surface can show, and it is the only surface where the reader can
  fix it in place.
- Mechanically it is also the only consistent answer: every other branch of
  `textContentStorage(_:textParagraphWith:)` returns `nil` when there is nothing to draw
  (`embedParagraph` with no rendition, `tableParagraph` with a stale marker), leaving the raw
  characters. A view block that drew an error card would be the one construct in the editor that
  substitutes something on failure.
- **What is given up, named:** the line number and the reason. In the editor the person sees that the
  block did not render and not why. The error card survives unchanged in the transclusion and export
  paths (`MarkdownBlocksView`, untouched), and the Viste pane reports the failure with its reason
  (`ViewsPane.swift`'s `entry(...)` failure branch, untouched). If the missing reason proves to be
  the thing people actually stumble on, the answer is a later decision with a measurement behind it,
  not a card grafted on now against an explicit success criterion.

**D8. Fixed height, at the proposed line fragment's own width, with the `ScrollView` at the host site
and never inside `RenderedViewBlock`.**

The provider's `attachmentBounds(for:location:textContainer:proposedLineFragment:position:)` returns
`CGRect(origin: .zero, size: CGSize(width: proposedLineFragment.width, height: ViewBlockAttachment.height))`
— the width TextKit is offering for this line, so the block spans the readable column ADR-0030 §D6
established and follows it when the pane is resized, and a constant height so the note's layout below
the block does not move as a result set grows or shrinks (R-06).

`RenderedViewBlock` gets no scroll view of its own. The wrapper lives in the root view the Coordinator
builds, which is the one place that knows this host is height-bounded; the transclusion and export
paths keep drawing the block at its natural height exactly as today (R-10, R-11).

Rejected: **an intrinsic, content-driven height.** It is what the table grid does and it is wrong
here: a board of forty cards would be a screen and a half of attachment in the middle of a note, and
the height would change under the reader on every vault change, which is R-06 read backwards.

Rejected: **reusing ADR-0019's user-resizable handle.** The SPEC already refuses it and the reason
holds: that handle persists a size into the note's own text as an Obsidian `|W` suffix, which has no
spelling for a fence and would be a new syntax in a file format this project shares with another app.

**D9. `RenderedViewBlock` gains exactly two optional inputs, both defaulted `nil`, and gains nothing
else. R-10 and R-11 are then true by construction rather than by care.**

- `onEditSource: (() -> Void)?` — drawn as one more control in the header row that already holds the
  refresh button, and the answer to "how does the caret get into a fence the attachment covers"
  (D10).
- `onOpenNote: ((String) -> Void)?` — threaded to `ViewTableRenderer`/`ViewListRenderer`,
  `ViewGalleryRenderer` and `ViewCalendarRenderer`, which today draw an accent-coloured title with no
  click target at all (Context finding 1). R-09.

Both default to `nil`, and `nil` means the control is not drawn and the row is not clickable — which
is exactly today's rendering. `MarkdownBlocksView.swift:70` passes neither and is not edited;
`TranscludedNoteView` and `NoteExporter` are not edited. The three files the SPEC puts out of scope
stay out of it, and their behaviour is unchanged because the new behaviour is opt-in at the call site
that opts in.

**D10. The caret enters a fence by an affordance inside the block, and by the arrow keys, and both
land on the opening fence line.**

An attachment spanning the column leaves no useful place to click for the caret, so "click into the
fence's raw text" needs a door. `onEditSource` sets the selection to the opening fence line's offset;
D4's range test then answers `true`, D5's guard fires, and the next pass draws the source. Arrowing
down from the line above lands on the same offset and does the same thing, with no code at all.

Rejected: **a double-click on the attachment's background.** The block's own content claims clicks
(R-09, and the board's cards claim drags), so a background double-click is a target that shrinks to
nothing as a result set fills the block.

**D11. Nothing here writes to the note's characters, and `replaceAtomically` is not called.**

ADR-0029 §D7/§D8 exist because a table's grid edits the note's own text. A view block's content is a
query result: the only write in the whole feature is the board's `status-*` tag rewrite, which goes
through `ViewQuerySource.move` → `VaultSession.write` → journal and undo, exactly as ADR-0009 §D5
already specified and as `ViewBoardRenderer` already implements. It writes to *another* note's
frontmatter, never to the buffer this editor holds. So there is no commit path, no stale-range guard,
no shape re-validation and no `Cmd+Z` coalescing question: the whole of §D7/§D8's machinery has no
counterpart here, and saying so is what stops someone building one by analogy.

The one place the buffer is touched is the substitution, which is display-only and lives inside the
displayed paragraph — ADR-0018 §D3, unchanged. `textView.string` is still the note.

**D12. The whole feature sits behind `VaultSettings.hidesMarkup`. No second toggle.**

`hidesMarkup` off restores the fence as literal text, which is today's behaviour and the escape hatch
if anything below misbehaves — ADR-0029 §D9's argument, and ADR-0018 §D7's before it: *"a person who
wants pictures drawn but delimiters visible is describing an implementation split, not a preference."*
The gate must reach the enumeration refusal as well as the substitution, or the body lines would stay
out of the layout with the backticks visible above them — the same trap `applyTables`'s own
`clearTables()` guard exists for.

**D13. Workspace `.text` cards inherit none of this, and the seam is the one ADR-0029 §D17 already
built rather than scope discipline.**

`CardTextView.swift`'s own `switch styled.span { … default: nil }` never produces a `.viewBlock` kind,
so the delegate never takes that branch for a card. The card's switch is left exactly as it is. The
one edit the compiler forces is `CardTextAttributes.colorToken(for:)` learning a colour for the new
span, which is a colour and not a kind mapping — §D17's own distinction, restated because this is the
second chain to meet it.

The reason matters more here than it did for the table: a card's text view is deallocated on every
culling-rect crossing (ADR-0028 R-11, the `a853e8e` crash class), and an `NSHostingView` running a
`.task` that reads the index is a worse thing to deallocate mid-flight than a grid of text fields.
**If a task looks like it needs to edit `CardTextView.swift`, stop and report.**

**D14. `MarkdownStyler` gains one span, `.viewBlockRun`, produced by the walk it already performs.**

The `.tableRun` precedent exactly: the fence regions are computed first (`MarkdownStyler.swift:114`)
and a region whose language is `ViewBlock.language` and whose last line closes it emits one span over
its whole source range. Like `.tableRun` it maps to **no** `HiddenMarker.Kind` in
`Coordinator.hiddenKind(for:)` — a run spanning several paragraphs cannot be a marker anchored to one
— and `applyViewBlocks` is what splits it into the opening line's own `.viewBlock` marker and the
lines that leave the layout.

The span is emitted *after* the `.codeBlock` span the fence loop already appends, so it wins on
overlap where the two disagree, which is the ordering `spans(in:)` documents for every other
construct.

**D15. `rescueCaret`'s third twin: a caret inside a body line that has just left the layout goes to
the opening fence line's offset.**

`applyFolding` has one, `applyTables` has one (`tableCaretRescue`), and this pass needs the same for
the same reason — a caret in an un-enumerated paragraph is an insertion point with nowhere to be
drawn and nowhere to type. It runs after the storage's editing transaction closes, never inside it,
which is where `refreshTableGrids` already puts its own.

In practice D4 makes this nearly unreachable (a caret inside the fence keeps it revealed), and
"nearly" is the reason it is written anyway: a programmatic selection — a find match, an outline
jump, `onScrollApplied` — can put the caret in a body line without going through the reveal path.

**D16. Four probes. The second is a gate on R-04 in the sense ADR-0029 §D16 probe 2 was a gate on its
D4, and it is answered before the board task is planned in detail rather than during it.**

1. **`NSHostingView` inside `NSTextAttachmentViewProvider`.** A trivial SwiftUI view with a `@State`
   counter and a `Button` in a host returned by `loadView`, in a real `CompletingTextView` in a real
   window. **Passes** when the view draws at the size `attachmentBounds` returned, the button responds
   to a click, and the `@State` survives a keystroke elsewhere in the note (i.e. the host instance was
   not rebuilt).
2. **SwiftUI drag-and-drop inside that host — the gate.** `ViewBoardRenderer`'s real
   `.draggable(_:)`/`.dropDestination(for:)` pair, dragging a card between two columns, inside the
   host, inside the text view. **Passes** when the drag starts (the card lifts), the destination
   column highlights, the drop fires `onDrop` with the payload, and the text view does not treat the
   gesture as a text selection drag. **A negative result costs R-04 its gesture, not the chain:** the
   named fallback is a per-card context menu on `ViewBoardRenderer`'s card, offered only when
   `queries?.move != nil`, writing through the identical `ViewQuerySource.move` closure — ADR-0009
   §D5's write reached by a different verb. That fallback is additive and invisible to the
   transclusion path, which passes no `queries` and so offers neither.
3. **First responder and the keyboard.** Click a card, then type. **Passes** when either the text view
   keeps first responder, or the host takes it and `Esc`/a click in the note returns it with a sane
   caret — never a state where keystrokes go nowhere. `TableGridStore.resignToTextView`'s shape is the
   fallback wiring if the host takes focus.
4. **Height stability under a changing result set.** With a board open, change a `status-*` tag in
   another note. **Passes** when the block's content updates (R-07) and the note's text below the
   block does not move by a pixel (R-06).

Probes 1–3 cannot be answered offscreen. They are hand checks with a written result, held to
ADR-0010's standard, and each result goes into `PROJECT_BRIEF.md` beside its phase. Probe 4 is
partly a unit assertion (the returned bounds are constant) and partly a hand check (that the drawn
layout agrees).

## Alternatives considered

**A1. Reimplement the four renderers as AppKit views inside the attachment.** No SwiftUI hosting at
all, so probes 1–3 disappear and the whole gate with them, and the result is an `NSView` hierarchy of
exactly the kind ADR-0029 §D6 already proved works in this position. **Rejected:** it produces a
second rendering of every view in the app — two tables, two galleries, two calendars, two boards,
with two empty states, two error states and two implementations of ADR-0009 §D5's *Senza stato*
column and its differential lint guard. The surface where they would first disagree is a transcluded
note beside the editor showing the same block twice, differently. ADR-0018 §D1 and ADR-0029 §D10 both
refused a second implementation of a smaller thing than this, and the cost here is an order of
magnitude larger. The gate is bought for a day of probing instead.

**A2. Rasterise the rendered block to an `NSImage` and draw it as an `EmbedAttachment`.** The cheapest
possible path and the one with no new mechanism whatsoever: `ImageRenderer` over the SwiftUI view,
one picture, the embed branch's existing arithmetic, no hosting view, no focus question, no drag
question. **Rejected:** it fails R-04 and R-09 outright — a picture has no drop target and no
clickable row — and it fails R-07 in spirit, since a raster is a materialised result and would have
to be re-rendered on every change to stay honest. It also reintroduces exactly the "view that has not
run and view that found nothing look alike" problem `RenderedViewBlock`'s header comment says the
row count exists to prevent. It is a report, and ADR-0009 §D5's own sentence is *"a board that cannot
be dragged is a report."*

**A3. A floating `NSPanel` positioned over the fence's collapsed range.** Keeps the text view free of
subviews entirely, reuses `FormatBarPanel`/`BoardMarquee`'s proven geometry, and SwiftUI in a panel
is something this repo does routinely and confidently (`CapturePanel`, `CompletionPanel`,
`FormatBarPanel`). **Rejected on ADR-0029 A1's own two grounds, both of which apply here harder:**
two surfaces of visual truth to keep aligned on scroll, window resize and pane split; and a
dependency on `firstRect(forCharacterRange:)`, which this repo has documented returning a zero
rectangle for a range TextKit 2 has not laid out — reliably true at the end of a long note, and a
zero rect clamps a panel to the screen corner instead of failing loudly (CLAUDE.md's own working
agreement records this trap). A view block is *taller* than a format bar, so the misalignment would
be more visible, not less.

**A4. Leave the editor alone and make the Viste pane the interactive surface, NotePlan's Folder Cards
model.** The SPEC itself researched this and found NotePlan's board is a separate, non-inline
surface; `ViewsPane` already exists, already catalogues every view in the vault, and could grow a
detail pane that renders the selected one. Zero editor risk, zero TextKit work, no probe.
**Rejected:** it does not restore what was lost. ADR-0009 §D1's whole argument for a view being a
fenced block in an ordinary note is that *"a project index page carries its own board"* — the board
belongs beside the prose that explains it, and a pane elsewhere in the window is a different feature
that happens to show the same rows. The SPEC also decides this explicitly and on its own merits
rather than by NotePlan comparison, and this ADR is not entitled to re-decide it. Worth recording
that the option is cheap and remains available if D16's gate goes badly for reasons the named
fallback does not cover.

**A5. Restore Lettura mode for this one construct — a per-note preview reachable from a command.**
The literal undo of the regression, and the smallest diff: `MarkdownReadingView` is still in the tree
(ADR-0029 §D14 retained it), so re-pointing a command at it is a handful of lines. **Rejected:** it
reverses ADR-0029's central decision — *"the toggle is not a feature, it is the absence of one"* —
and reintroduces two renderings of one note that will drift, which that ADR's own A6 already refused.
It would also make the *editor* the only surface where a view does not run, which is the state this
SPEC exists to end.

**A6. Key `ViewBlockHostStore` by paragraph offset, exactly as `TableGridStore` does.** One store
shape for both attachment features, one thing to learn, and the pruning logic could very nearly be
shared. **Rejected:** D3's argument — an offset key rebuilds the host on every keystroke typed above
the fence, and rebuilding the host re-runs the query. ADR-0009 §D7 forbids per-keystroke evaluation
and this ADR does not have the standing to amend it. The symmetry is worth less than the decision it
would break.

**A7. Reveal through ADR-0018 §D2's existing `revealedParagraphs` set, with no new rule.** Reuses a
mechanism that is measured, tested and shared by five constructs, and adds nothing.
**Rejected:** Context finding 3 — the set is keyed by paragraph, the caret can only ever be in the
fence's opening paragraph while the block is drawn, and the moment reveal lets it move into the body
the block re-hides underneath it. The loop is structural, not a bug to be fixed inside the existing
key.

**A8. Render every fence, and simply refuse to draw the ones that do not parse, without the
closed-fence precondition of D6.** One fewer condition to compute and to test. **Rejected:** an
unclosed fence runs to the end of the text by `CodeFence.regions`' own deliberate design, so the
first three characters of ``` ```pergamenum-view ``` would take the rest of the note out of the
layout for as long as it took to type the rest of the line. The parse failure would *usually* save it
— an empty body has no `render:` — but "usually" is not a property to build a layout on, and the two
conditions cost one comparison each.

## Consequences

**Positive**

- **A regression closes with no new query-layer code at all.** `ViewEvaluator`, `ViewBlock`,
  `ViewQuerySource`, all four renderers and the board's guarded write are used exactly as merged.
  `viewQuerySource`, written and left standing by ADR-0029 §D13 for precisely this, is wired rather
  than written.
- **One rendering of a view exists in the app, and it is structurally impossible for a second to
  appear**, because the editor and the transclusion path hand the same SwiftUI view different inputs
  rather than drawing different views.
- **R-10 and R-11 are true by construction, not by discipline.** The new inputs are optional and
  default to today's behaviour; `MarkdownBlocksView`, `TranscludedNoteView` and `NoteExporter` are not
  in the diff at all, which is a grep a reviewer can run rather than a claim to trust.
- **R-06 is free and exact.** A constant height returned from `attachmentBounds` cannot move the text
  below it, whatever the result set does.
- **The Oggi and Diario panes are unaffected and cost nothing to leave that way** — they build
  `NoteTextView` without a `queries` input, which defaults to `nil`, and a fence there stays the
  source it is today.
- **`hidesMarkup` reverts the entire feature**, and it is a switch that already exists and already
  ships on.
- **The board write, its journal, its undo and its vocabulary guard are reached unchanged**, so the
  one dangerous thing in this feature is the one thing that is not new.

**Negative**

- **This repo has never put SwiftUI inside its text.** ADR-0029 proved a plain `NSView` works there;
  an `NSHostingView` with `@State`, `.task` and drag-and-drop is a strictly larger claim, and D16's
  probes 1–3 exist because none of it can be read out of a header. Probe 2 can cost R-04 its gesture.
- **A view now evaluates when a note is opened in the editor, not only when the Viste pane is
  visited.** ADR-0009 §D7 permits this ("on open") and priced it, but the number it priced was
  measured on a two-note vault, and a `text()` term reads every candidate file synchronously on the
  main actor inside `.task`. Named as unmeasured on a real vault, not as handled. The mitigation that
  exists is structural: D3's ordinal key means the query does not re-run per keystroke, and TextKit's
  viewport layout only asks for a provider on a laid-out fragment, so a fence far below the fold has
  no host and no task.
- **A note with several large view blocks pays several `NSHostingView` hierarchies.** No measurement
  exists. Same shape as ADR-0029's own admission about tables, one order of magnitude heavier per
  instance.
- **The editor loses the parse error's line and reason** (D7). The block simply does not render.
  Filed as a known cost with two surfaces that still report it, not as debt to fix silently.
- **`EditorDecorationDelegate` grows a seventh concern and a sixth enumeration producer.** It will
  cross `type_body_length` again; the split follows the established shape,
  `EditorDecorationDelegate+ViewBlockRendering.swift` beside `+TableRendering`, `+QuoteRendering`,
  `+ListRendering`, `+CheckboxRendering`.
- **`textViewDidChangeSelection` can now trigger a full styling pass** (D5). Guarded by an `NSRange?`
  comparison, so a note with no view block pays one comparison per arrow key — but the worst case is a
  restyle on a navigation, where before it was never.
- **R-09 is new behaviour arriving as if it were a restoration.** Anyone reading the SPEC's framing
  will believe clicking a view row used to work. It never did, and the renderers gain their first
  click target in this chain.
- **A fence nested inside another fence follows `CodeFence.regions`' alternating-marker grammar**,
  which is the same grammar that colours it today, so the editor's rendering and the editor's
  colouring agree — but `ViewCatalogue` tracks nesting separately for the Viste pane, and the two can
  in principle disagree about a pathological note. Named rather than discovered; not fixed here,
  because unifying them is a `Sources/Core` change with two connectors behind it and no reported case.

**Neutral**

- **`IndexCache.schemaVersion` stays 3.** No index field, no frontmatter key, no `.canvas` property,
  no `.pergamenum/` file, no migration. This is a presentation-layer feature end to end.
- **No protected interface is touched.** `IndexCache.schemaVersion`, `VaultAPI.LintFinding`,
  `CompletingTextView+Pasteboard.swift` and `ImportNaming.recordingNoteTitle` are all outside this
  diff; `interface-check.sh` must stay silent for the whole chain.
- **`Sources/Connector` and `Sources/Core` are untouched except for one span case in
  `MarkdownStyler`** — which lives under `Sources/Features/Editor`, not `Sources/Core`, so neither
  connector build is affected. `perg view run` and the MCP `view` tools answer exactly as before.
- **Obsidian compatibility is unchanged** (principle 4). The fence is written exactly as it was and
  Obsidian keeps showing it as an inert code block, which ADR-0009 §D1 says is the correct behaviour
  for a reader that cannot run it.
- **Principle 2 is untouched.** Nothing here opens a socket; the two named network exceptions
  (ADR-0031 Sparkle, ADR-0032 Plaud loopback) are not extended and not referenced.
- **The find bar keeps counting matches inside a hidden fence body and revealing only the current
  one** — ADR-0018 §D2's fourth trigger, and under D4 a current match inside the fence range reveals
  the whole block rather than one paragraph of it, which is the more useful answer.
- **`MarkdownReadingView` stays dead code with its ADR-0029 §D14 comment.** This chain does not
  revive it and does not delete it; the print/preview surface it is reserved for is still undesigned.
- **The unit suite can cover the span, the range arithmetic, the hidden-line sets, the reveal
  predicate, the closed-fence precondition and the returned bounds — and nothing interactive.**
  Everything in D16 is on screen, which is what `scripts/uitests.sh` before every merge and R-14's
  hand-check exist for.

## References

- `docs/adr/0009-views-are-queries-over-the-index.md` §D1, §D2, §D3, §D4, §D5 (both amendments), §D6, §D7
- `docs/adr/0010-transclusion-is-a-view-of-another-note.md` §D3
- `docs/adr/0014-a-view-can-say-today.md` §D4 (`onDayChange`)
- `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` §D1, §D2, §D3, §D5
- `docs/adr/0019-embed-drag-resize.md` §D2, §D5, §D7
- `docs/adr/0028-wysiwyg-markdown-in-workspace.md` §D1, R-11 (the card culling-rect crash class)
- `docs/adr/0029-editor-wysiwyg-unification.md` §D4, §D5, §D6, §D9, §D10, §D13, §D14, §D16, §D17, A1, A6
- `docs/adr/0030-editor-page-typography-noteplan.md` §D6 (the readable-width inset the block's width follows)
- `SPEC.md` (PG-099) R-01 … R-15
- SDK, `MacOSX26.5.sdk`: `NSTextAttachment.h:86-93`, `:106-127`, `NSTextContentManager.h:118-120`
- Source read for this ADR: `RenderedViewBlock.swift`, `ViewsPane.swift`, `ViewQuerySource.swift`,
  `ViewBoardRenderer.swift`, `ViewRowRenderers.swift`, `ViewGridRenderers.swift`, `ViewCatalogue.swift`,
  `DayChange.swift`, `ViewBlock.swift`, `CodeFence.swift`, `MarkdownBlocksView.swift`,
  `MarkdownStyler.swift`, `MarkdownAttributedText.swift`, `EditorDecorationDelegate.swift`,
  `+TableRendering`, `NoteTextView.swift`, `+Coordinator`, `+Tables`, `+Reveal`, `TableAttachment.swift`,
  `TableGridStore.swift`, `EditorColumn+Text.swift`, `Tests/TableRenderingTests.swift`,
  `Tests/EmbedEditorTestSupport.swift`, `.claude/protected-interfaces`, `.claude/test-cmd`
