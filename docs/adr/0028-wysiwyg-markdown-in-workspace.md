# ADR-0028 — WYSIWYG markdown rendering (lists + concealment) unified across Nota and Workspace

- **Date:** 2026-08-29
- **Chain:** `wysiwyg-markdown-in-workspace` (concept-to-code, standard path)
- **SPEC:** `/Users/stefer/Developer/Pergamenum/SPEC.md`
- **Plan:** `docs/superpowers/plans/2026-08-29-wysiwyg-markdown-in-workspace.md`
- **Supersedes:** ADR-0027 §D10 («the card never conceals markdown markers»), for heading,
  emphasis and list markers only. **Partially reopens:** ADR-0027 §D1's reuse line — the card
  now shares one AppKit class with the note editor, `EditorDecorationDelegate`, and §D3 below
  says exactly why that one and nothing else. **Builds on:** ADR-0018 (source-mode styling,
  marker concealment and the reveal-on-caret rule), ADR-0027 (the card's own `NSTextView`).

## Status

Proposed — awaiting Gate 2.

## Context

Two gaps are shared by the note editor and the Workspace `.text` card. Neither surface draws a
list as anything other than flat text, because `MarkdownStyler` has no list span at all
(ADR-0027 C6 recorded this and deliberately left it). And the card conceals nothing: ADR-0027
§D10 wrote that exclusion down with its reason, which was scope, not principle. This feature
closes both, and reverses §D10 for the card.

### What the SPEC says, against what the source says

Eight claims checked against the tree at `4623c7d`. Six needed correcting; four of those change
the design.

**C1. «Nota always shows the markers, dimmed … a partial concealment exists via
`EditorDecorationDelegate`». Understated, and the understatement matters.** Concealment in Nota
is not partial-as-in-experimental: it is on by default. `VaultSettings.hidesMarkup` defaults to
`true` (`VaultSettings.swift:140`, `:215`), it is a user-visible setting
(`EditorSettings.swift:19-20`), and with it on a heading's `#` and an emphasis run's `*`/`**`
are already hidden outside the caret's own paragraph (`EditorDecorationDelegate.swift:191-231`).
What is never concealed is *everything else*, lists included, because there is no span to
conceal. The consequence for this feature is §D10: the new behaviour belongs behind that same
switch on both surfaces, not beside it.

**C2. «`LineFormat` already renumbers an ordered run at toggle time — auto-continuation reuses
that arithmetic instead of duplicating it». False.** `LineFormat.toggled(.numbered)` numbers the
lines *the selection touches*, from 1, by their position in the selection
(`LineFormat.swift:62`, `:87` — `ordinal: offset + 1`). It has no notion of where a list run
begins or ends, does not look at the line above the selection, and does not know a run's own
start number. R-08 asks for something that function cannot do and was never meant to do. A new
pure type is required (§D6); `LineFormat` is left untouched.

**C3. UI flow 5, «click the disclosure control of a heading (mirroring Nota)». There is no such
control in Nota.** Folding is triggered from the outline sidebar: `OutlinePane.swift:66` draws a
chevron per heading entry and toggles `vault.foldedEntries`. The only in-text fold interaction
is a click on the *badge* of an already-folded heading, which unfolds it
(`NoteTextView+Transclusion.swift:161-173`, PG-021). A card has no outline sidebar, so «mirroring
Nota» has to be read as «mirroring the fold list», not «mirroring a control that does not
exist» (§D9).

**C4. R-06, «shows only its existing checkbox glyph». There is no checkbox glyph.** A task line
is drawn as its own characters — `- [ ]` — coloured through `.taskMarker(done:)` →
`.taskOpen`/`.taskDone` (`MarkdownAttributedText.swift:126`, `CardTextAttributes.swift:191`).
Nothing substitutes a box or a tick anywhere in either text surface. R-06 is therefore satisfied
by *not* emitting a list span on a checkbox line, so that line keeps exactly today's appearance
(§D5). Drawing a real checkbox is a different feature and is not in this SPEC.

**C5. «`FormattingTextView`/`CardTextView` need an equivalent concealment mechanism».
Overstated.** The card's text view already is a TextKit 2 view built by
`FormattingTextView.scrollableTextView()` (`CardTextView.swift:46`) with a live
`NSTextContentStorage` behind it. Wiring a content-storage and a layout-manager delegate onto it
is two lines, and the note editor already shows which two (`NoteTextView.swift:148-149`). What
the card is missing is a *delegate*, not a mechanism — which is what makes §D3 a reuse decision
rather than a porting exercise.

**C6. «the same transient model Nota already uses» for fold state. True, and keyed
differently.** Nota's fold set lives on the open tab, by outline-entry ordinal
(`EditorColumn+Text.swift:95`, `NoteTextView.swift:96`), and is never written to disk. A card
has no tab; the equivalent is a table on `WorkspaceController` keyed by node id, cleared in
`attach` — which is the line that actually enforces R-09's «resets when the board is reopened»
(§D9).

Two claims checked out and are relied on below. `MarkdownStyler` still has no list span (the
word «list» appears once, in a comment at `:381`). And `EditorDecorationDelegate` is genuinely
unfenced: `.claude/protected-interfaces` holds three entries, and the editor one is
`Sources/Features/Editor/CompletingTextView+Pasteboard.swift`, a different file.

### Three constraints the SPEC could not know

**The displayed paragraph may not change length.** `EditorDecorationDelegate`'s embed branch
records `NSTextContentManager.h:120`'s own constraint and keeps it by swapping one character for
one character (`:283-285`). A bullet cannot be *inserted* in front of a list item; it can only
*replace* something already there. This single fact decides §D3's whole rendering model.

**The note editor's Enter is already claimed, twice.** `CompletingTextView.doCommand(by:)` gives
the completion panel first refusal on Return, and otherwise consults a `claimsCommand` closure
set from `NoteTextView.swift:207` (`:240`). That closure is the existing seam — the embed caret
commands already use it — so list continuation needs no edit to `CompletingTextView.swift` and
cannot steal Return from the completion panel.

**A card's text view is deallocated constantly.** Every crossing of
`BoardContentLayer.visibleNodes`' culling rect destroys and rebuilds one, which is why
ADR-0027 §D2 gave it a private `UndoManager` and a `dismantleNSView` purge after commit
`a853e8e`. Any per-view state this feature adds — a delegate, a fold table, a revealed set —
inherits that lifetime and must not outlive it (R-11).

## Decision

Add one list span to the shared classifier, and give the card the note editor's existing
decoration delegate rather than a second copy of it. Everything new that is pure goes to
`Sources/Core/Editor/`; everything new that is AppKit goes beside the delegate that already
does this work.

### D1 — One list span in `MarkdownStyler`, marker-sized, carrying kind and nesting level

```
case listMarker(kind: ListKind, level: Int)   // ListKind: .bullet | .ordered
```

The span covers the marker and its trailing space — `- `, `* `, `+ `, `12. `, `12) ` — starting
after the line's indentation, exactly the shape `.headingMarker` already has. It carries no
range for the item's text and no paragraph range: the view derives the paragraph with
`NSString.paragraphRange(for:)`, which the styling walk already computes for every hidden marker
(`NoteTextView+Coordinator.swift:272-274`). The classifier keeps its contract from ADR-0018 —
it says what a range is and never replaces a character.

Nesting level is `1 + indentColumns / 2`, a space counting one column and a tab four, capped at
six. This is **not** CommonMark's rule, which measures the parent item's content column and
would need the whole list's state to answer a single line. The simplification is written into
the file: this classifier is line-local by construction, and a two-space step is what every note
in this vault and every card this app writes actually uses.

### D2 — A checkbox line is not a list line

`spans(inLine:)` already computes `taskMarker(in: trimmed)` before anything else on the line
(`MarkdownStyler.swift:202`). When it returns non-nil, no list span is emitted at all. This is
the whole of R-06: with no list span there is no marker to conceal and no bullet to substitute,
so `- [ ] fai qualcosa` renders on a card and in a note exactly as it does today, at rest and
in editing alike (C4 — there is no checkbox glyph to show «only»). `LineFormat` already draws
the same line in the same place (`isChecklistLine`, `:220-228`); the two rules are now stated
twice in two files, and that is accepted rather than extracted, because `MarkdownStyler` is not
in `sharedSources` and `LineFormat` is (`Project.swift:73`).

### D3 — The card reuses `EditorDecorationDelegate`; it is not forked

The card's `CardTextView.Coordinator` builds one `EditorDecorationDelegate`, assigns it to
`textView.textContentStorage?.delegate` and `textView.textLayoutManager?.delegate` (C5's two
lines), and fills four of its inputs: `hiddenMarkers` from its own styling walk, `hidesMarkup`,
`revealedParagraphs`, and — for R-09 — `hiddenLines`/`foldedHeadings`. The transclusion and
embed tables stay empty; both of their branches return nil on an empty table before touching
anything else, so a card pays nothing for machinery it does not use.

This reopens ADR-0027 §D1's line («share the Foundation-only logic, none of the AppKit
classes») for exactly one class, and the reasons that line was drawn do not apply to it.
`CompletingTextView` was rejected there because it is a view with about forty note-specific
inputs and eight extension files, one of them a protected interface.
`EditorDecorationDelegate` is none of those things: it is a delegate that holds plain values,
takes no view and no theme, is already driven from a test without a window
(`MarkupHidingTests.swift:28-55`), and is not in `.claude/protected-interfaces`. The SPEC
itself flags the difference and leaves the choice here.

The positive argument is stronger than the absence of an obstacle. What this delegate holds
*is* the rendering rule — which markers vanish, when they come back, what a bullet looks like.
Two copies of that rule is two answers to «how does this app draw a list», and R-02, R-03 and
R-06 are all statements that the two surfaces agree. The one thing that must stay separate is
the *look* of a span, and that is already separate and stays so: `MarkdownAttributedText` for
the note, `CardTextAttributes` for the card, untouched by this decision (ADR-0027 §D1's real
prize, the card's non-monospaced bold, is not at risk here).

`MarkupReveal.paragraphs(in:selection:markedRange:currentMatch:)`
(`NoteTextView+Reveal.swift:17`) is reused the same way and for the same reason: it is offset
arithmetic over an `NSString`, it already answers ADR-0018 §D2's four triggers, and a card
needs three of them.

### D4 — A list marker is *substituted*, never collapsed, and the indent becomes a paragraph style

A new branch in `EditorDecorationDelegate.textContentStorage(_:textParagraphWith:)`, beside the
embed branch and under the same length rule:

- the leading indentation run is drawn in `collapsedFont` (the 0.01pt font the heading and
  emphasis markers already use) and replaced by a real `NSParagraphStyle` — `firstLineHeadIndent`
  and `headIndent` proportional to the span's level, `headIndent` one bullet-width further so a
  wrapped item aligns under its own text rather than under its bullet (R-05);
- an unordered marker's `-`/`*`/`+` is replaced by `•` — **one character out, one character in**,
  the paragraph's length unmoved, which is the only way a bullet can exist here at all (the
  length constraint above);
- an ordered marker is left exactly as written. The source's own digits *are* the rendered
  ordinal; there is nothing to conceal and nothing to invent. This is what couples R-02 to R-08:
  an ordered list renders correctly precisely because the file is kept contiguous (§D6), not
  because the view counts.
- the marker's trailing space is kept in both cases, so the glyph does not touch the item's text.

Collapsing the whole marker to nothing — the obvious extension of the heading rule — is
rejected in §A2: an unordered item would become prose with no bullet and no indent, which is
worse than showing the dash.

A revealed paragraph (the caret's own, in editing) gets none of this: no substitution, no
paragraph style, the raw source as written. The item therefore shifts horizontally as the caret
enters and leaves it. That is the motion a heading's `#` reappearing already produces today and
it is accepted for the same reason: the revealed line must be the file's line, not a styled
approximation of it.

### D5 — The note editor is edited by this chain; the protected file is not

Three files under `Sources/Features/Editor/` change: `MarkdownStyler.swift` (§D1),
`EditorDecorationDelegate.swift` (§D4, plus `HiddenMarker.Kind.list` and its `stillSpells` arm),
and `NoteTextView+Coordinator.swift`'s span→kind map (`:265-270`, a `default: nil` switch that
gains one arm). `MarkdownAttributedText.colorToken(for:)` gains an arm because it has no
`default` and must stay exhaustive. `CompletingTextView.swift` and every `+` extension of it are
untouched, `CompletingTextView+Pasteboard.swift` above all: Enter is claimed through the
`claimsCommand` seam that file's neighbour already exposes (§D7).

ADR-0027's «not one file under `Sources/Features/Editor/` is edited» was a property of *that*
feature, whose requirements were all about a canvas card. This feature's requirements name Nota
explicitly (R-03, R-07, R-08), so the fence moves back to where the interface check actually
draws it.

### D6 — `ListContinuation`, a new pure type, owns Enter and renumbering

`Sources/Core/Editor/ListContinuation.swift`, Foundation only (the `sharedSources` glob compiles
it into `perg` and `pergamenum-mcp`, so an `import AppKit` there breaks both connector builds
rather than itself — `InlineFormat.swift`'s own header warning). Two entry points:

- `newline(in:at:) -> (text: String, selection: NSRange)?` — nil when the caret is not inside a
  list item, which is how a caller falls through to AppKit's ordinary Return. Non-nil in three
  cases: a bullet item continues as `- ` at the same indentation; an ordered item continues as
  the next number; a checkbox item continues as an empty `- [ ] `. An item whose text is empty
  does the opposite: the prefix is removed and the line becomes an ordinary paragraph (R-07).
- `renumbered(_:) -> String?` — nil when nothing changes. Every ordered run is renumbered
  contiguously **from its own first item's number**, never from 1. That rule is CommonMark's
  (a list starts at its first item's ordinal) and it is also what makes the pass safe to run
  after an arbitrary edit: a run deliberately started at `3.` stays at 3, only its successors
  are corrected. A run ends at a line that is not an ordered item at that level — which is what
  makes `1. uno` followed by `- due` two runs of one item each, as the SPEC's edge case requires.

`newline` returns text that is **already renumbered**, so a continuation is one string
replacement and therefore one undo step (R-12). `LineFormat.toggled(.numbered)` keeps its
selection-local numbering unchanged (C2): it emits `1., 2., 3.` over the touched lines, which
this pass then reads as a run starting at 1 and leaves alone.

### D7 — Enter is taken at the seam each surface already has

The card: `FormattingTextView` overrides `insertNewline(_:)`, calls `ListContinuation.newline`,
and applies the result through its existing `replaceWholeText(with:selecting:)` — the same
one-edit-per-press idiom `toggleInlineFormat`/`toggleLineFormat` already use
(`FormattingTextView.swift:110-117`). A nil result calls `super`.

The note: the closure at `NoteTextView.swift:207` assigned to `CompletingTextView.claimsCommand`
gains `#selector(insertNewline(_:))`. That closure is consulted only when the completion panel
is hidden (`CompletingTextView.swift:239-241`), so Return still picks a completion when one is
offered, and `CompletingTextView.swift` itself is not edited.

The renumber-after-deletion half of R-08 runs from each surface's existing `textDidChange`,
applying `renumbered` only when it returns non-nil. AppKit's `groupsByEvent` puts that follow-up
edit in the same undo group as the deletion that provoked it, so Cmd+Z takes back both at once
(R-12); the plan asserts this rather than assuming it.

### D8 — The card's concealment state is a function of `isEditable`, and of nothing else

At rest (`isEditable == false`) the card publishes an empty revealed set: every marker is hidden,
which is R-04's «WYSIWYG vero». While editing it publishes
`MarkupReveal.paragraphs(...)`, so the caret's paragraph shows its own source and every other
paragraph stays rendered (R-03). This keeps ADR-0027 §D3's rule intact — one component, two
states, `isEditable` the only difference — and it means the answer to «what does a card look
like» never depends on a second variable that could disagree with the first.

`CardTextView.dismantleNSView` clears the delegate's tables alongside the undo purge it already
performs, so a card culled mid-edit leaves nothing behind (R-11).

### D9 — Fold is a card command with a heading submenu, plus the badge click while editing

Nota folds from a list of headings (`OutlinePane`, C3). A card has no sidebar, so its list of
headings is a submenu: one new `CardCommand.foldHeadings`, offered only on a `.text` node,
rendered by both the context menu and `BoardCardControls` from the one catalogue ADR-0023 §D1
established — the same submenu shape `.color`, `.resize`, `.textColor` and `.textAlign` already
use (`BoardCardMenu.swift:191-194`). Each row is a heading of that card, checked when its section
is folded, toggling on selection. The collapse itself is `NoteFolding.layout(in:foldedEntries:)`
and the badge is `FoldedHeadingFragment`, both reused unchanged: the first is Foundation-only in
`Sources/Core/Markdown/`, the second is a layout fragment that takes its colours as inputs.

While the card is being edited, a click on a folded heading's badge unfolds it, mirroring
PG-021. The hit test is ~12 lines re-stated in `FormattingTextView` rather than extracted from
`NoteTextView+Transclusion.swift`'s `decoration(at:in:claimedBy:)` — the same deliberate
duplication ADR-0027 §D1 accepted for `replaceWholeText`, and for the same reason: extracting it
means editing the note editor's view layer for a card's benefit.

At rest the text view is not selectable and the board's own gestures own every click
(`BoardContentLayer.selectionGestures(enabled:)`), so there is no in-text affordance at rest and
none is invented — the submenu is reachable in both states, which the badge is not.

Fold state lives on `WorkspaceController` as `[nodeID: Set<Int>]` of outline-entry ordinals,
`@ObservationIgnored`-free so the card redraws, cleared in `attach` and never written to a
`.canvas` file. R-09's «resets when the board is reopened» is that one line, not a promise.

### D10 — The whole feature lives behind the existing `hidesMarkup` setting, on both surfaces

`vault.settings.hidesMarkup` already governs concealment in Nota and defaults to true (C1). The
card reads the same value, carried in by `WorkspaceView.applyBoardSettings()` — the existing
route for `boardShowsGrid`/`boardSnapsToGrid` (`WorkspaceView.swift:474-477`) — onto
`WorkspaceController.hidesMarkup`, which `StickyTextCard` passes down to `CardTextView`. The
`onChange(of: vault.settings)` at `:380` already re-applies it when the setting changes.

With the setting off, both surfaces show raw source, list markers included. R-02, R-03 and R-04
are therefore statements about the default configuration, and that is deliberate: a second,
card-only switch would be a second answer to one question, and a user who has asked to see their
markdown source has asked on behalf of the whole app.

### D11 — ADR-0027 §D10 is reversed for heading, emphasis and list markers, and for nothing else

A card conceals exactly three kinds of marker. `#tag`, `[[wikilink]]` syntax, `- [ ]`, a code
fence and an embed run stay drawn as their own characters, dimmed by `CardTextAttributes` as
today, per the SPEC's own non-goals. A card still draws no embed preview and no transclusion:
those inputs to the shared delegate are never filled on a card (§D3), which is a stronger
guarantee than a rule somebody has to remember.

### D12 — Nothing on disk changes, and nothing is proposed for `.claude/protected-interfaces`

No new persisted key, no `.canvas` schema change, no `JSONCanvas.swift` edit, no index field,
`IndexCache.schemaVersion` untouched (`.canvas` files are not in the index at all), and
`VaultAPI.LintFinding` untouched (no connector-facing change of any kind). Every list this
feature renders was already written as `- item` / `1. item` and is still written that way after
it (R-10). The two new pure types are internal and no external caller depends on them, so no
protected-interface entry is proposed by this chain.

## Alternatives considered

**A1 — Fork a card-scoped `CardDecorationDelegate` instead of reusing the note editor's.** The
SPEC offers this as one of two options and ADR-0027 §D1's precedent points at it. **Rejected
because the thing that would be duplicated is the rendering rule itself.** Two implementations
of «what a hidden marker is, when it comes back, what a bullet looks like» is exactly the drift
R-02/R-03/R-06 are written to prevent — those requirements are assertions that a note and a card
agree, and the cheapest way to keep them true is to have one object that can answer. The
argument that carried §D1 in ADR-0027 does not transfer: `CompletingTextView` is a view with
forty inputs and a protected extension, `EditorDecorationDelegate` is a bag of values with no
view, no theme and an existing windowless test harness. The two surfaces keep looking different
where it matters — the attribute tables stay separate and untouched.

**A2 — Conceal a list marker the way a heading marker is concealed, by collapsing it to a 0.01pt
font.** The smallest possible change: one more kind in the existing table, no substitution
branch, no paragraph style. **Rejected because it renders an unordered list as prose.** With the
`- ` gone and the indentation gone, `- primo` and `primo` are the same line on screen, and R-02
asks for a bullet, not for an absence. It also loses nesting entirely (R-05), since the only
thing expressing depth would have been the collapsed spaces.

**A3 — Draw the bullet with a custom `NSTextLayoutFragment` per list line, the way
`FoldedHeadingFragment` draws its badge.** Real drawing, arbitrary glyph size, no length
constraint to respect. **Rejected on cost and on redundancy.** It needs a fragment instance for
every list line in every note and card, and it does not remove the marker characters — those
would *still* need the collapse pass, so the fragment is added work on top of a mechanism that
already produces the right answer. The substitution does the hiding and the drawing in one
place. This alternative is the right one if a future feature ever needs a glyph wider than the
source it replaces, and it is recorded here for that reason.

**A4 — Use `NSTextList`/`NSParagraphStyle.textLists`, AppKit's own list machinery.** It exists,
it draws markers, it renumbers, and `NSTextView` has automatic list editing built on it.
**Rejected on the file format.** That machinery owns the marker: it decides what is drawn and
inserts its own marker text into the storage on Return, which is a second writer of the file's
characters and a direct contradiction of principle 1 and of `MarkdownStyler`'s «never replaces a
character» contract. A markdown source editor cannot hand the authority over `1. ` to a
framework that writes RTF list attributes.

**A5 — Conceal by mutating the storage: delete the markers, keep the raw source in a shadow
string.** The simplest thing that renders correctly, and how a naive WYSIWYG editor is built.
**Rejected outright.** The text view's storage is the file's text on both surfaces — the card
commits `editingTextDraft` straight into the node, the note writes its storage to disk. A
concealment that deletes characters is a feature that eats notes on the first bug in its
restore path.

**A6 — Renumber every ordered run from 1 on each pass.** Simpler arithmetic, no need to read a
run's first ordinal. **Rejected because it overwrites the author.** A list deliberately written
`3. / 4. / 5.` — a continuation of something above it, an excerpt — would be snapped to 1 on the
next keystroke, and there would be no way to write it at all. Renumbering from the run's own
first number is both CommonMark's rule and the only version of R-08 that is safe to run after an
arbitrary edit.

**A7 — Give the card its own concealment setting, independent of `hidesMarkup`.** It would let
someone keep source mode in notes and WYSIWYG on cards, which is a defensible preference.
**Rejected as a second answer to one question.** The setting is called «hide markup», it is
already user-visible, and two switches with overlapping meanings is a settings screen nobody can
reason about. If the split is ever wanted, it is a settings feature with its own SPEC, not a
side effect of this one.

**A8 — Put fold on an in-text disclosure chevron drawn beside every heading.** What the SPEC's
UI flow 5 literally describes, and the most discoverable option. **Rejected on the card's own
event model, twice.** At rest the card's text view is not selectable and the board's selection
and drag gestures own every click, so a chevron there would be dead at exactly the moment a
reader wants it; and drawing it needs a custom layout fragment for every heading line (A3's
cost) merely to host a hit target. The submenu works in both states, reuses the catalogue the
card already renders twice, and mirrors what Nota actually does — fold from a list of headings
(C3).

**A9 — Extend `LineFormat` with the continuation and run-renumbering arithmetic, as the SPEC's
Architecture section directs.** One file instead of two, and the marker parsing is already
written there. **Rejected because the two are different shapes.** `LineFormat` answers «what do
these selected lines become when a button is pressed», with no knowledge of the lines around the
selection; continuation and run-renumbering are both questions about the *run* a line belongs to,
which starts above the selection and ends below it. Bolting the second onto the first would make
a 300-line file that answers two unrelated questions and would put R-08's run detection in reach
of the format bar's toggle, where it does not belong. The marker-recognition duplication between
them is real and is accepted; it is ~40 lines of digit-and-delimiter scanning, and both files are
in `Sources/Core/Editor/` where a later extraction is cheap if a third caller ever appears.

**A10 — Ship lists without concealment on either surface (rendering only), leaving §D10
standing.** Half the feature, a third of the risk, and it would still close the more visible
gap. **Rejected because rendering a list without concealing its marker is not possible here.**
The bullet *is* the concealment: there is no place to draw a `•` except in the marker's own
character. The two halves the SPEC presents as separable are one mechanism (§D4), and a chain
that shipped only the first would ship nothing.

## Consequences

### Positive

- One object answers «how is a marker hidden» for both surfaces, so R-02, R-03 and R-06 — all
  of them assertions that a note and a card agree — hold by construction rather than by two
  implementations being kept in step.
- `MarkupReveal`, `NoteFolding` and `FoldedHeadingFragment` are reused with no edit at all, so
  the caret rules, the section-extent rule and the badge a person already knows arrive on the
  card already correct and already tested.
- The concealment work is testable offscreen. `MarkupHidingTests` already drives the real
  delegate against a bare `NSTextContentStorage` and asserts both the laid-out frames and the
  storage length; every new rendering rule in §D4 is measurable the same way, with no window,
  no board and no UI test.
- `ListContinuation` is Foundation-only, so R-07 and R-08 are unit-tested against plain strings
  and are reachable from a connector later if `perg` ever gains a list command.
- The file on disk is untouched in every direction (§D12): no key, no schema, no index, no
  connector payload. A vault opened in Obsidian after this feature is byte-identical to one
  opened before it.
- The card's fold lands on the existing command catalogue, so it inherits `BoardCardControls`,
  the context menu, accessibility identifiers and `CardCommandTests`' exhaustive coverage
  without new plumbing.

### Negative

- **`Sources/Features/Editor/` is now in this chain's blast radius**, which ADR-0027 was written
  to avoid. Five files there change, and the note editor is the app's most load-bearing view.
  The mitigation is narrow and stated (§D5): the protected file and every `CompletingTextView`
  extension stay untouched, and Enter is taken through an existing seam.
- **A list item shifts horizontally when the caret enters it**, because the reveal drops the
  substituted paragraph style along with the substituted glyph (§D4). Today's heading markers
  already do this, so it is a known motion rather than a new one, but a list makes it visible on
  many more lines.
- **The nesting rule is not CommonMark's** (§D1). A list indented three spaces, or one whose
  nesting depends on the parent's content column, renders at a level this classifier computes
  from indentation alone and may disagree with what Obsidian draws. Nothing is written to disk,
  so the disagreement is cosmetic and reversible.
- **Every keystroke on both surfaces now runs one more full-text pass** — `renumbered` scanning
  for a non-contiguous ordered run — on top of the styling walk that already runs. Notes are
  small and the existing walk is accepted as imperceptible; this is a second one of the same
  order, and it is the first thing to look at if typing ever feels heavy.
- **The card's text view gains two delegate assignments and a table of hidden markers per
  visible card**, on top of ADR-0027's «one `NSTextView` per visible `.text` card». The cost
  scales with the culling rect, and `BoardGeometry.drawsPlaceholder(at:)` still caps the worst
  case below a quarter zoom.
- **`CardCommand` grows to thirteen cases**, which updates four exhaustive test fixtures in the
  same commit (the plan lists them) and makes the card's context menu longer again.

### Neutral

- `LineFormat` is not edited, and its selection-local numbering (C2) coexists with the run-based
  pass: a toggle emits `1., 2., 3.`, which the new pass reads as a run starting at 1 and leaves
  alone. Two rules that never disagree in practice, both now written down.
- The checkbox rule is stated in two files (`MarkdownStyler` and `LineFormat`, §D2) because one
  is in `sharedSources` and the other is not. Accepted duplication, recorded rather than
  extracted.
- The card's fold has an affordance at rest (the submenu) that Nota does not have, and Nota has
  one (the outline sidebar) that the card does not. Both fold; neither mirrors the other's
  surface, and C3 is why.
- With `hidesMarkup` off, this feature is invisible on both surfaces (§D10). That is the
  setting's meaning, and it makes «turn concealment off» the complete rollback for the rendering
  half of this chain.
- `.text` node content is unchanged in shape, so ADR-0027 §D4's `pergamenum-textColor` and
  `pergamenum-textAlign` keep working underneath the spans exactly as they do now — the base
  attributes still sit under everything the styler adds.

## References

- SPEC: `/Users/stefer/Developer/Pergamenum/SPEC.md` (R-01 … R-12)
- ADR-0018 `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` — §D1 the marker-hiding
  mechanism and the paragraph-relative marker table, §D2 the four reveal triggers.
- ADR-0023 `docs/adr/0023-universal-command-surface-parity.md` — §D1 one command catalogue read
  by both the context menu and the control bar (§D9 above).
- ADR-0027 `docs/adr/0027-unificare-nota-e-testo-in-un-solo-strume.md` — §D1 the card's own text
  view and attribute table, §D2 the card's private undo manager and dismantle purge, §D3
  `isEditable` as the only difference between the two states, §D6 `LineFormat`, §D10 the
  exclusion this ADR reverses.
- `Sources/Features/Editor/EditorDecorationDelegate.swift:283-285` — the displayed paragraph's
  length constraint (`NSTextContentManager.h:120`), which decides §D4.
- `Sources/Features/Editor/CompletingTextView.swift:239-241` and `NoteTextView.swift:207` — the
  `claimsCommand` seam Enter is taken through (§D7).
- `Sources/Features/Editor/OutlinePane.swift:66` and `NoteTextView+Transclusion.swift:161-173` —
  how folding is actually triggered in Nota (C3).
- `Sources/Vault/VaultSettings.swift:140` — `hidesMarkup` defaults to true (C1, §D10).
- `Tests/MarkupHidingTests.swift:28-55` — the windowless harness every new rendering rule is
  measured with.
- `.claude/protected-interfaces` — three entries, none of them touched (§D12).
