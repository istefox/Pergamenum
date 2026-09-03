# ADR-0029: One editor, always editable, and a table is a grid

- Status: proposed
- Date: 2026-09-02. Written after reading every file it names, at the line, on the working tree
  at `bbe09a9`. The mechanisms below are the ones already in this repository plus two SDK hooks
  it has never called; both are quoted from `MacOSX26.5.sdk` rather than recalled, and the
  claims that could not be read out of either are named as probes in D16.
- **Supersedes ADR-0005 §D2** (*"the source keeps every character of its syntax and its
  styling, exactly as the Note pane's editor does, and the rendering is a second view of the
  same text"*) — the Diario pane's second view is removed and its source is no longer literal.
  ADR-0005's other seven decisions are untouched.
- **Supersedes ADR-0018's scope boundary** — *"three named constructs, not the rule"* (§Supersedes)
  and the five exclusions of §D4. ADR-0018's **mechanism** (§D1 substitution at identical length,
  §D2 reveal-on-caret with four triggers, §D3 the display-only principle, §D5 the caret rules,
  §D7 the one setting) is not superseded and not amended: this ADR is that mechanism applied to
  five more constructs plus one that needed a second hook.
- **Amends SPEC §14** — *«Live preview completa | Esclusa v1 | Voce di costo massima; source mode
  con stile è sufficiente»*. ADR-0018 amended this narrowly and kept the ruling standing for
  everything it did not name. This ADR retires the row. **Amends SPEC §5**, whose two-mode
  description was written this session with a closing note flagging this chain; the note is what
  the amendment removes. Neither file is edited by this ADR (Task 8 of the plan).
- Depends on: **ADR-0018 §D1/§D2/§D3/§D5/§D7**, **ADR-0019 §D2/§D7** (the attachment-bounds hook
  and `replaceAtomically`), **ADR-0028 §D2/§D4** (character-for-character substitution and the
  «never insert, never collapse» rule), **ADR-0010 §D2/§D3** (which `![[…]]` is a file and which
  is a note — untouched here), `docs/20260817_TextKit2_live_editing.md` for every measurement
  ADR-0018 quotes and this one relies on.

## Context

**Two views of one note, and only one of them can be typed into.** `NoteTab.isReadingMode`
(`NoteTab.swift:19`) picks between `editing(note)` and `reading(note)` in
`EditorColumnView.swift:66-70`. Reading draws `MarkdownReadingView`
(`EditorColumn+Text.swift:177`), which is where a GFM table, a blockquote's bar, a horizontal
rule and a strikethrough have been correctly drawn since M1 — and where nothing can be edited.
The toggle is reachable from four places: the tab bar's segmented picker
(`NoteTabBar.swift:69-80`), the toolbar (`VaultBrowser.swift:132-137`), the Vista menu
(`MenuCommands.swift:44-46`) and `ShortcutCommand.readingMode` with its `Cmd+Shift+M` default
(`ShortcutCommand.swift:70`, `:275`).

**What ADR-0018 actually proved, and what it deliberately did not claim.** Its D4 lists five
exclusions with a reason each, and three of those reasons have since expired:

- *«Tables drawn as a grid — out of reach at sane cost, and the study says so: the fragment would
  have to lay out a grid over a length-preserved run.»* That sentence assumes the grid must live
  inside **one** length-preserved paragraph. It need not: the delegate already owns a second hook
  that removes a paragraph from the layout entirely (`textContentManager(_:shouldEnumerate:options:)`,
  `EditorDecorationDelegate.swift:167-174`), which is how folding works. A table's continuation
  lines can simply not be enumerated, and the whole grid drawn against the header line alone.
  That is D4 below, and it costs no new mechanism at all.
- *«`[[nota]]` — the completion after `[[` writes into that range, and a hidden delimiter under an
  open completion panel is the interaction with the most moving parts in the editor.»* True, and
  answered by D2's own reveal rule: the completion panel only ever opens with the caret inside the
  link being typed, and the caret's paragraph is revealed by construction. The hazard cannot occur.
- *«`- [ ]` task markers — reachable and a separate decision.»* Already taken and shipped since
  (`EditorDecorationDelegate+CheckboxRendering.swift`).

The two exclusions that stand — `#tag` (a value, not punctuation) and code fences (inside a fence
markdown is not markdown) — are **not** reopened here.

**Three constraints, all load-bearing, all read rather than assumed.**

1. `NSTextContentManager.h:120`: *"The attributed string for a custom text paragraph must have
   range.length."* A displayed paragraph may differ from the stored one in attributes and never in
   length. Every substitution below is length-preserving by construction.
2. `EditorDecorationDelegate` cannot be `@MainActor` — Swift 6 refuses both conformances
   (`EditorDecorationDelegate.swift:25-26`) — so it holds plain values handed in from the
   Coordinator. It owns no `NSTextView` and must own no view. `renditions`, `embedRenditions` and
   `hiddenMarkers` are three existing instances of that crossing.
3. *"a `\n` at size 0.01 still breaks the line, so a folded section would be a stack of empty rows"*
   (`EditorDecorationDelegate.swift:17-18`). Measured in this project. It is why hiding a whole line
   is a different hook from hiding a delimiter, and it is what kills the obvious table design (D4's
   first rejection).

**Two SDK hooks this repo has never called**, both quoted from `MacOSX26.5.sdk`:

> `NSTextAttachment.h:90-91` — When YES, the text attachment tries to use a text attachment view
> returned by `-viewProviderForParentView:location:textContainer:`. **YES by default**
>
> `NSTextAttachment.h:106-125` — `NSTextAttachmentViewProvider` … `initWithTextAttachment:parentView:textLayoutManager:location:` … *"This is where subclasses should create their custom view hierarchy"* … `tracksTextAttachmentViewBounds`: *"If YES, `-attachmentBoundsForAttributes:…` consults the text attachment view provider for determining the bounds instead of using -bounds. NO by default"*
>
> `NSAttributedString.h:238` — `NSToolTipAttributeName; // NSString, default nil: no tooltip`

The first is the SDK's own answer to *"put a real view in the text"*, and it takes a `parentView` —
so the grid is a genuine subview of the text view, in the key-view loop, rather than a rectangle
someone has to keep aligned by hand. The second is a tooltip with no tracking area. Neither has
been exercised here, which is why D16 exists.

**What is already measured in this project and removes work from this decision.**
`Tests/EmbedAttachmentProbeTests.swift` (ADR-0018 §D6 probe 6) established that an
`NSTextAttachment` living **only in the substituted paragraph** is asked for its bounds and its
image, and asked exactly once. ADR-0019 §D8 probe 1 then established that a non-default
`attachmentBounds` return actually sizes the line. So the attachment machinery works against a
paragraph that exists nowhere in the backing store — which is the entire premise of D4.

## Decision

**D1. Four delimiter constructs join ADR-0018's mechanism, and the "three constructs" boundary is
retired rather than widened a fourth time.**

`MarkdownStyler` gains four `Span` cases beside `.headingMarker`/`.emphasisMarker`/`.listMarker`,
produced by the same walk `spans(in:)` already performs:

- **`.blockquoteMarker(level:)`** — the run of `>`s opening a line and the single space after the
  last one. Drawn by **substituting each `>` with `▏` (U+258F)**, character for character, and
  collapsing the trailing space — ADR-0028 §D2's mechanism verbatim. One bar per level, unbounded,
  **because the file's own characters are the count**: there is no depth to cap and no table to go
  stale, exactly the argument ADR-0028 §D4 makes for leaving an ordered list's digits verbatim.
- **`.strikethroughMarker`** — the exact twin of `.emphasisMarker`, produced by the same
  `emphasisMarkers`-shaped helper, collapsed by the same generic 0.01pt path.
- **`.linkSyntax`, already emitted** (`MarkdownStyler.swift:407`) and today only coloured, becomes
  a hidden marker. A second recogniser is added beside the wikilink one for CommonMark
  `[testo](url)`, which `MarkdownStyler` does not recognise at all today — the same second-spelling
  decision ADR-0018 §D3 took for `![alt](file.png)`, for the same reason: this app's own writers
  emit only one form (`EditorEdits.markdownLink` is the exception, and it emits the CommonMark
  one on paste), and a vault opened from elsewhere holds both.
- **`.horizontalRule`** — a whole line of three or more `-`, `*` or `_`, per
  `MarkdownBlockParser.isRule`'s grammar reused rather than restated.

**A rule is the one construct a substitution cannot serve, and it gets the fallback ADR-0018 §D3
already named.** Three characters cannot span a column however they are drawn, so the run is
collapsed to `collapsedFont` by the generic path and the line is drawn by a custom
`NSTextLayoutFragment` — the shape `FoldedHeadingFragment` and `TranscludedLineFragment` are two
working instances of, and the fit is exact because a `---` line *is* a whole paragraph with nothing
else on it, unlike every mid-line delimiter this mechanism was built for.

Rejected: **substituting `---` with three `─` glyphs.** It obeys the length rule and draws a rule
three characters wide, which reads as a typo rather than as a separator.

Rejected: **a fifth construct, callouts (`> [!nota]`).** Out of scope by the SPEC and by
`EditorCommand.swift:41-44`'s own standing note: the renderer has no callout, and drawing one in
the editor would make the editor promise something no other surface keeps.

**D2. ADR-0018 §D4's refusal of `[[nota]]` is answered by D2's existing reveal rule, not overruled
by fiat.**

The stated hazard is a hidden delimiter under an open completion panel. `CompletingTextView` opens
that panel from `textDidChange`, with the caret inside the `[[…` being typed; ADR-0018 §D2's first
trigger reveals the caret's own paragraph. A link being completed is therefore drawn in full,
brackets included, for the whole life of the panel. There is no state to add and no ordering to
get right — the interaction the exclusion was protecting cannot reach a collapsed run.

The second half of §D4's argument — *"the target is the readable part and hiding the brackets buys
almost nothing"* — is what this ADR overrules, and it overrules it on one ground only: with every
other construct drawn, four brackets around every note reference is the loudest remaining syntax on
screen.

**D3. A concealed link's target is an `NSToolTipAttributeName` on the substituted paragraph, and
nothing else.**

`.toolTip` carries the resolved target — the note's title where `vault.index.resolve` finds one,
the raw target where it does not, the URL for a CommonMark link — applied over the same range the
brackets were collapsed on. It is rebuilt on every layout pass with the paragraph it lives in, so
it cannot go stale, cannot survive the text it describes and needs no invalidation: ADR-0018 §D3's
*"it does not outlive the pass that made it"* argument, one attribute lower.

Rejected: **`NSView.addToolTipRect(_:owner:userData:)`**, AppKit's other tooltip route. It needs a
rect, so it needs geometry recomputed on every layout pass, every scroll and every window resize —
the second-copy-of-TextKit's-geometry problem ADR-0019 §D5 already rejected an `NSView` handle over.

The claim that `NSTextView` honours `.toolTip` under TextKit 2 is not verifiable from the header
and is D16's probe 1. Failing it, the tooltip is dropped to a **Consequence** and R-04 is refused
rather than bought with a tracking-area layer: a hover hint is not worth a geometry mirror.

**D4. A table is one attachment in its header line's paragraph, and its remaining lines are not
enumerated at all. Two hooks, one construct, no new mechanism.**

For a source range that `GFMTable` (D10) recognises as a table:

- the **header line's paragraph** is substituted: its first character becomes `\u{FFFC}` carrying a
  `TableAttachment`, the rest of the line is collapsed to `collapsedFont`. Length preserved, one
  character out and one in — the embed branch's own arithmetic (`EditorDecorationDelegate.swift:339`);
- the **delimiter row and every body row** are reported `false` from
  `textContentManager(_:shouldEnumerate:options:)`. They are not in the layout, so they occupy no
  height, draw nothing, and — the part that matters most — **the caret cannot enter them**, which
  ADR-0018's Consequences already state as measured for folding: *"the folded lines are not in the
  layout at all, so `NSTextSelectionNavigation` never walks into them."* R-05's "never through
  direct text editing of pipe characters" is therefore a property of the layout rather than a rule
  the caret code has to keep.

Rejected: **collapsing the body rows to 0.01pt instead of hiding them.** The delegate's own header
records the measurement that kills it: a `\n` at 0.01pt still breaks the line, so the grid would sit
above a stack of thin empty rows.

Rejected: **a floating `NSPanel` over the table's text range** (the brainstorm's Alternative B).
Two surfaces to keep aligned on scroll, resize and window move, and it reawakens the
`firstRect(forCharacterRange:)` zero-rect defect this repo has already documented for ranges TextKit 2
has not laid out — which, at the end of a long note, is exactly where a table is.

Rejected: **a static render plus an on-demand single-cell editor** (Alternative C). A second UI
state machine to design and test, in exchange for avoiding a risk D16 probes for a day.

**D5. The hidden-line set gains a second producer and stays two separate inputs.**

`apply(hiddenLines:foldedHeadings:)` is folding's, set from `NoteFolding.layout`, and it *replaces*
the set. Tables cannot write through it: two producers on one setter is precisely what the
delegate's own header forbids — *"four features … kept as four separate inputs so none can quietly
depend on another's state."* A fifth input, `apply(tableRows:)`, is added, and
`textContentManager(_:shouldEnumerate:options:)` answers against the union of the two sets.

Two consequences the coder must handle and neither is optional. `applyFolding`'s early return
(`guard decorations.isFolding || !folded.isEmpty`) does not cover tables, so the table pass has its
own guard and its own change check. And `rescueCaret(in:from:)` has a table twin: a caret left
inside a row that has just become hidden has nowhere to be drawn and nowhere to type; it goes to the
table's header offset, which is where a person would look for it.

**D6. The grid is an `NSView` behind `NSTextAttachmentViewProvider`, created and owned on the main
actor by the Coordinator, and handed to the attachment as a finished value.**

`TableAttachment: NSTextAttachment` overrides `viewProviderForParentView:location:textContainer:`
and returns a provider whose `loadView` assigns a `TableGridView` **it was given**, never one it
builds. The view is created by `TableGridStore`, a `@MainActor` type on the Coordinator, keyed by
the table's identity, exactly as `EmbedTable` is owned by the Coordinator and hands
`EditorDecorationDelegate` finished `EmbedRendition` values (`NoteTextView+Coordinator.swift:77`,
`decorations.apply(embeds:)`). The delegate carries a reference and calls nothing.

Three things follow, and each is the reason for the shape:

- **`tracksTextAttachmentViewBounds = true`**, so the line's height comes from the grid's own frame
  rather than from a number pushed in — ADR-0019 §D2's argument for the negotiation hook over
  `attachment.bounds`, one level up.
- **The same view instance is returned across layout passes.** A grid rebuilt on every pass would
  lose first responder on every keystroke that triggers a styling pass, which is every keystroke.
  Identity is the store's whole job.
- **The grid's edits reach the buffer through a closure the Coordinator sets**, the
  `NoteTextView.wire(_:to:)` shape (`onEmbedResize`, `onEmbedMenu`, `claimsCommand`) and for the
  reason `claimsCommand`'s comment gives: *"this view has exactly one owner, and a closure makes
  that owner's identity a non-issue."*

Rejected: **the Coordinator positioning grid subviews itself from TextKit geometry.** ADR-0019 §D5
rejected exactly this for the resize handle — *"a second copy of geometry TextKit already owns, kept
in step by hand"* — and the view provider is the SDK's own answer to it.

**D7. A cell is its own editing session; the source is rewritten once per commit, never per
keystroke, and always through `replaceAtomically`.**

Typing in a cell touches no `NSTextStorage`. On commit — Tab, Shift-Tab, Enter, or the cell losing
focus — one `replaceAtomically(range, with: rewritten, in: textView)` over the table's **whole
source range**, with the table re-serialised from its parsed model. That is `NoteTextView+EmbedCaret.swift:101`'s
existing call, whose own comment names it *"the only mechanism either of this feature's two writes
may use"* and whose discipline is `shouldChangeText` first: R-08 (one `Cmd+Z` per structural edit)
is a property of there being exactly one edit, not a rule anyone keeps. Add-row, remove-row,
add-column and remove-column are the same single call with a different model.

`didChangeText()` then runs the chain that already exists (`textDidChange` → `applyStyling` →
`applyEmbeds` → `applyTransclusions` → `renumberLists` → `applyReveal` → `growToFitTheText`), so the
rewritten pipes are re-parsed, the grid store is asked for the same view again, and the caret lands
in the next cell on the same runloop pass.

Rejected: **per-keystroke sync.** Forty undo steps for one cell, and a re-parse of the whole note per
character typed in a table.

**D8. Every write re-reads the table's characters first, and a commit whose table has moved is
abandoned rather than applied.**

`TableGridView` holds a source range computed by a *styling* pass; a commit happens in a later pass.
Between them the buffer may have been replaced wholesale — an FSEvents reload, the conflict banner's
«Ricarica da disco», or `updateNSView`'s own `textView.string = text` when the model diverges. The
rule is the `stillSpells…` family's, restated for a fifth kind: `GFMTable.parse` is re-run over the
live characters at the recorded range, and the commit proceeds **only** if it still yields a table of
the same shape. Otherwise the edit is dropped and the grid is rebuilt from whatever the new text says
on the next pass.

That is the whole of SPEC §8's reload case, and it is the same answer ADR-0018 §D3 gave: *"the
question does not arise"* — nothing about a table outlives the pass that drew it, so there is no
mapping for a reload to invalidate. `replaceAtomically`'s own stale-range guard is the second lock
behind this one.

**D9. `hidesMarkup` off restores today's editor exactly, tables included, and that is the escape
hatch this ADR ships with rather than a setting it adds.**

`VaultSettings.hidesMarkup` (default `true`, `VaultSettings.swift:140`) already gates every
substitution: `textContentStorage(_:textParagraphWith:)` returns nil at its first line without it.
The table branch, the new enumeration refusal and the rule fragment all sit behind the same flag and
**no second toggle is added**. Off, the pipes are ordinary text and directly editable — which is also
the honest answer to *"what if the grid cannot do what I need"*, and the reason R-05's "only through
the grid" is a statement about the default configuration rather than about the file.

**D10. One GFM grammar, extracted once, read by both surfaces.**

`MarkdownBlockParser`'s table recognition (`MarkdownBlocks.swift:128-205`: `table(header:consuming:)`,
`alignments(in:)`, `cells(in:)`, `fit(_:to:)`) is `private` and returns values with no ranges. The
editor needs ranges. Rather than a second recogniser — which ADR-0018 §D1 rejected for exactly this
reason, *"the characters that are hidden and the characters that are coloured come out of one pass
over one string"* — the grammar moves to `Sources/Core/Markdown/GFMTable.swift`, Foundation only,
and `MarkdownBlockParser` calls it. `Sources/Core/**` is a `sharedSources` glob
(`Project.swift:73`), so the file compiles into `perg` and `pergamenum-mcp`: **an `import AppKit`
or `import SwiftUI` there breaks both tool builds**, which is ADR-0001 §D1 enforcing itself.

Two SPEC edge cases fall out of this and cost nothing:

- **R-09 (a fence's pipes are never a table).** `MarkdownStyler.spans(in:)` computes `fences` first
  and the table pass takes them the way `wikilinkSpans(in:from:outside:)` already does — one
  argument, the same argument, the same guard.
- **R-10 (a malformed table stays plain text).** `alignments(in:)` returns nil for a delimiter row
  that is not one, and `table(header:consuming:)` already *"consumes nothing unless it returns a
  table"*. No span, no attachment, no hidden rows: the pipes are prose.

**D11. No new insert command, and no size picker.**

`EditorCommand.table` already exists (`EditorCommand.swift:78-81`, `:182-187`), is already offered by
the slash menu, and is already what the Inserisci menu writes — one copy, *"so the two cannot drift
into producing different markdown for the same command."* It writes a 2×1 skeleton, that skeleton is
a valid GFM table, and it therefore renders as a grid the moment it lands. R-06 is satisfied by a
command that already ships.

Rejected: **an N×M size chooser sheet.** A second UI to design, mock up and test, for a shape the
grid's own add-row/add-column controls produce in two clicks. N and M come from the grid.

**D12. R-07 (a pasted table renders as a grid) requires no change to the paste path, and
`CompletingTextView+Pasteboard.swift` is not touched.**

That file is a declared protected interface (`.claude/protected-interfaces` line 3). It needs no
edit: `paste(_:)` falls through to `super.paste(sender)` for text that is neither a URL nor an image,
the pipes land in the buffer as characters, `textDidChange` fires, `applyStyling` recognises the
table and the grid is drawn — in the same turn, which is exactly what R-07 asks for. The
"paste URL → link" pattern R-07 cites as its model is a *rewrite* on paste; this needs none, because
a markdown table pasted as markdown is already the form the file stores.

**D13. The toggle is removed everywhere, `ShortcutCommand.readingMode` included, and an orphaned
key binding is already tolerated.**

`ShortcutCommand`'s raw values are the keys of the overrides file and ADR-0005 §D8 is right that a
case must not *move*. Removing one is a different operation, and `ShortcutStore.decode` already
handles it: `guard let command = ShortcutCommand(rawValue: id) else { continue }`
(`ShortcutStore.swift:137`). A user who rebound `Cmd+Shift+M` loses that entry silently, which is
correct — the command it named no longer exists.

**D14. `MarkdownBlocksView` is not dead code after this change; only `MarkdownReadingView` is.
SPEC R-12's premise is corrected, not its decision.**

R-12 retains both views as *"unreferenced by any toggle."* Grepped: `MarkdownBlocksView` has a
second, live caller — `TranscludedNoteView.swift:104` draws every `![[nota]]` rendition through it
(ADR-0010 §D3), and `:192` uses its `noteURL(_:)`. It stays load-bearing and is not annotated as
reserved for anything. `MarkdownReadingView` is the wrapper that genuinely loses both of its call
sites (`EditorColumn+Text.swift:177`, `DiaryView.swift:117`) and is the one that gets R-12's comment.

Named honestly rather than glossed: the export feature R-12 reserves it for **already exists** and
does not use it — `NoteExporter` renders HTML and PDF through `NoteExport.html(from:title:)`
(`NoteExporter.swift:43-47`), a separate generator. So `MarkdownReadingView` is retained as dead code
for a *print/preview* surface nobody has designed. That is the user's decision and this ADR keeps it;
it is recorded here so the next reader does not mistake the retention for a live dependency.

**D15. The Diario pane loses its preview half and the `Layout` picker that switched between them.**

`DiaryController.Layout` (`.editor`/`.preview`/`.both`, `DiaryController.swift:34`, `:61`) and the
toolbar picker that sets it (`DiaryToolbar.swift:47-55`) go with `DiaryView.preview`. The writing
column becomes the editor, full width, beside `DiaryTimeline` — which is untouched, as are ADR-0005's
D1, D3, D4, D5, D6, D7 and D8. `DiaryView`'s own header comment states the superseded premise
verbatim (`DiaryView.swift:7-13`) and is rewritten with the rest.

`NoteTextView` is built on three surfaces, not two — `EditorColumn+Text.swift:43`, `DiaryView.swift:98`
and `TodayView.swift:191` — and every one of them inherits this ADR for free, the Oggi pane included,
which has no reading half to remove and needs no change at all.

**D16. Four probes, a pass criterion each, and one of them is a gate rather than a check.**

1. **`NSToolTipAttributeName` in a substituted paragraph.** Apply `.toolTip` over a collapsed
   `[[` range and hover. **Passes** when the tip appears within the system delay and names the
   resolved target. Failing, D3's fallback: the tooltip is dropped and R-04 is refused.
2. **Nested first responder inside an attachment view — the gate.** Two `NSTextField`s in a
   `TableGridView` behind `NSTextAttachmentViewProvider`, in a real `CompletingTextView` in a real
   window. **Passes** when: clicking a cell makes it first responder; Tab moves to the next cell and
   Shift-Tab to the previous; Tab from the last cell and Escape both return first responder to the
   text view with a sane caret; and the completion panel and format bar do not open while a cell has
   focus. **This is the brainstorm's named risk and it is the one probe that must be answered before
   the table tasks are planned in detail** — a negative result forces Alternative B or C, which is a
   different ADR and not a mid-implementation pivot. It is a candidate for a tracer-bullet probe
   (Step 4.5); *whether* to spend one is the orchestrator's and the user's call, not this ADR's.
3. **`tracksTextAttachmentViewBounds` sizes the line.** ADR-0019 §D8 probe 1 established this for a
   returned rect; this is the view-driven variant. **Passes** when a 3-row grid's line fragment is as
   tall as the grid and the note below it starts underneath.
4. **Undo coalescing across a commit.** Type in a cell, Tab, type in the next, Cmd+Z twice.
   **Passes** when each Cmd+Z reverses exactly one cell's commit and no reveal or styling pass has
   opened an undo group of its own. ADR-0018 §D6 probe 4's own note applies: *"the one most likely to
   fail quietly and the one a user would report as 'undo does nothing'."*

Probes 1, 2 and 3 cannot be answered offscreen. They are hand checks with a written result, held to
ADR-0010's standard — *"neither is a reason to decide differently; both are reasons not to claim the
feature works until someone has clicked there"* — and the result of each goes into
`PROJECT_BRIEF.md` beside its phase.

**D17. The Workspace `.text` card inherits none of this, and that is enforced by a switch it already
owns rather than by scope discipline.**

ADR-0028 §D1 made the card reuse `EditorDecorationDelegate` *directly*, deliberately, so the two
surfaces cannot diverge on the rendering rule. So a new branch in that delegate would reach the card
too — and the SPEC puts the card out of scope. The seam that makes "out of scope" structurally true
is `CardTextView.swift:285-312`: the card fills `hiddenMarkers` from **its own**
`switch styled.span { … default: nil }`, and a kind that switch never produces is a branch the
delegate never takes for a card. The card's switch is left exactly as it is, so:

- **blockquote, rule, link and strikethrough concealment do not appear in cards.** Whether they
  should is a later decision with ADR-0028's own argument available to it, not a side effect of this
  one;
- **a card can never instantiate a table grid**, which matters more than the others: a card's text
  view is deallocated on every culling-rect crossing (ADR-0028's R-11, the `a853e8e` crash class),
  and a live `NSView` hierarchy with first responder inside one is that crash wearing a new hat.
  `apply(tableRows:)` is a second input the card never fills, and the `.table` kind is one it never
  emits — two independent reasons, which is the right number for this one.

**If a task looks like it needs to edit `CardTextView.swift`, stop and report.** The only exception
is the compiler forcing it: `MarkdownStyler.Span` gains cases and
`CardTextAttributes.colorToken(for:)` is exhaustive, so that table must learn the new spans and give
them a colour. Learning a colour is not the same as mapping a kind.

## Alternatives considered

**A1. A floating `NSPanel` grid positioned over the table's collapsed text range.** The
brainstorm's Alternative B. Reuses `FormatBarPanel`/`BoardMarquee`'s proven geometry pattern and
keeps the text view free of subviews entirely. **Rejected:** two surfaces of visual truth to keep
aligned on scroll, window resize and pane split, and it depends on
`firstRect(forCharacterRange:)`, which this repo has already documented returning a zero rectangle
for a range TextKit 2 has not laid out — reliably true at the end of a long note, and a zero rect
clamps a panel to the screen corner instead of failing loudly. That is an existing defect this path
would reawaken, not a new risk invented against it.

**A2. A read-only attachment render plus an on-demand floating single-cell editor.** The
brainstorm's Alternative C, and the smallest surface for D16 probe 2's risk: no permanently-nested
responders at all. **Rejected:** it introduces an explicit viewing-vs-editing state machine that
neither other option needs, it has to be designed and tested as its own UI, and it removes the
"click into a cell and type" immediacy SPEC §7 describes. The risk it avoids is bought for a day of
probing instead.

**A3. Deleting a table's pipe lines from the buffer and reconstituting them on save.** muya's and
Vditor's design, and the one that makes grid editing trivial. **Rejected on principle 1 and on
ADR-0018 §D1's own rejection of the same idea:** the editor's text would stop being the file's text,
`textDidChange` would hand a mutilated string to `VaultController.updateOpenNoteText`, and
`VaultSession.write` would put it on disk, into `NoteHistory` and into `WriteJournal.textBefore`,
with nothing downstream inspecting what it was given.

**A4. A second table recogniser in the editor layer, leaving `MarkdownBlockParser` alone.** Cheaper
by one refactor of a `Sources/Core` file that two command-line tools compile, and lower risk to the
connector builds. **Rejected:** two grammars for one syntax will disagree, and the surface where
they disagree is a transcluded note (`MarkdownBlocksView`, D14) drawing a table the editor refuses,
or the reverse. ADR-0018 §D1 already took this decision once, for markers.

**A5. A per-editor "WYSIWYG" setting, so the old source-visible editor survives as a mode.**
Would make the change fully revertible from the UI, which is what ADR-0018 §D7 bought for itself.
**Rejected:** `hidesMarkup` **is** that setting and already exists (D9); adding a second one would
need a name nobody can write, and ADR-0018 §D7's own argument against two toggles applies unchanged
— *"a person who wants pictures drawn but delimiters visible is describing an implementation split,
not a preference."*

**A6. Keeping the Modifica/Lettura toggle and only adding the concealment extensions.** The
smallest possible change: no removals, no test churn, no Diario work, and reading mode stays as the
place a table is drawn correctly. **Rejected:** it is the status quo this SPEC exists to remove, and
it leaves the app with two renderings of one note that will drift — nested blockquotes are already
an instance (D14's consequence below). The toggle is not a feature, it is the absence of one.

**A7. Extending `MarkdownStyler` with a full block-level parse so the editor and the renderer share
one document model.** Architecturally the cleanest end state: one parse, one model, two views.
**Rejected as out of scope and out of proportion:** `MarkdownStyler` is a range classifier that runs
on every keystroke of every note (5.83 ms on a 17 KB note, measured), and turning it into a block
parser is a rewrite of the editor's hot path in service of a renderer this ADR is retiring from the
editing surface. The shared piece this feature actually needs is the table grammar alone (D10).

## Consequences

**Positive**

- **The file is still the file, and still by construction.** Nothing in this ADR writes into
  `NSTextStorage` outside `replaceAtomically`, and every display transform lives in a substituted
  paragraph the SDK requires to be the same length or in a paragraph removed from the layout. So
  `textView.string` is still the note, `VaultSession.write` still receives markdown, `NoteHistory`
  and `WriteJournal.textBefore` still snapshot markdown, and the connectors' `undo` keeps comparing
  hashes of the same bytes. That is why D4 refuses a buffer-side grid and D8 refuses a durable
  mapping.
- **Three of the four new delimiter constructs cost one span case and one branch each.** Blockquote
  reuses ADR-0028's substitution, strikethrough reuses ADR-0018's collapse, link reuses both. Only
  the rule needs a fragment, and two working fragments already exist to copy.
- **R-09 and R-10 are free.** The fence guard is an argument `wikilinkSpans` already takes; the
  malformed-table refusal is `alignments(in:)` returning nil, already written and already tested.
- **R-07 is free and touches no protected interface.**
- **The Oggi pane gains the whole feature without a line of change** (`TodayView.swift:191`).
- **One switch reverts everything**, including the table grid, and it is a switch that already
  exists and already ships on.

**Negative**

- **`EditorDecorationDelegate` grows a fifth and sixth concern** — a table branch in the
  substitution hook and a second producer for the enumeration hook — against a header that already
  had to be rewritten from "two features" to "four". It will cross SwiftLint's `type_body_length`
  again; the split follows the established shape (`EditorDecorationDelegate+TableRendering.swift`,
  beside `+ListRendering` and `+CheckboxRendering`).
- **This repo has never put a live `NSView` inside its text.** ADR-0019 §D5 rejected one for the
  resize handle and ADR-0018's survey found no precedent in five open-source editors for anything
  like it in a native text widget. D16 probe 2 exists because of that, and it is a real gate: a
  negative result costs this ADR its D4.
- **A grid holds real subviews, so a note with many tables pays real layout and memory.** No
  measurement exists. The mitigation is structural rather than promised: the store is keyed by table
  identity and the viewport layout controller only asks for providers on laid-out fragments, so an
  off-screen table has no view. It is named here as unmeasured, not as handled.
- **The editor and `MarkdownBlocksView` will disagree about nested blockquotes.**
  `MarkdownBlockParser`'s quote accumulator strips exactly one `>` (`MarkdownBlocks.swift:239`), so a
  transcluded note showing `>>> testo` draws one bar where the editor draws three. Introduced by this
  feature, filed as debt, deliberately not fixed here — the renderer's nesting depth is a separate
  decision and this SPEC's non-goals forbid new constructs.
- **`MarkdownReadingView` becomes dead code with a comment saying it is not** (D14). It compiles, it
  is tested by nothing, and it will rot until the print feature that justifies it is designed.
- **The four UI tests that click `app.radioButtons["Lettura"]` must be rewritten, not deleted** —
  `DesignAndReadingUITests` `:117`, `:156`, `:174` (via `openNoteInReadingMode`) and
  `NoteImageUITests:55`. Two of them assert real behaviour that survives (a table is drawn; an embed
  is drawn) and must be re-pointed at the editor; the third asserts keyboard scrolling in a view that
  no longer exists on that path.
- **A person who rebound `Cmd+Shift+M` loses the binding silently** (D13). Tolerated by
  `ShortcutStore.decode`, and the alternative — a migration for a personal app's one orphaned key —
  is not worth writing.
- **Renaming a note by editing its `[[…]]` brackets stops being possible while they are concealed**
  — the caret's paragraph reveals them (D2), so the operation survives, but it now requires the caret
  to be on that line first. The same price ADR-0018 §D5 named for the drawn embed, smaller.

**Neutral**

- **`IndexCache.schemaVersion` is not touched and cannot be.** This is a rendering-layer feature; no
  index field, no frontmatter key, no `.pergamenum/` file, no migration. The protected interface stays
  silent.
- **`VaultAPI`/`VaultPayloads` and both connectors are untouched.** `perg` and `pergamenum-mcp` read
  and write markdown; a table's pipes are markdown before and after.
- **Obsidian compatibility is unchanged** (principle 4): every construct in scope is CommonMark or
  GFM, written exactly as it was, and the grid writes back the same pipe syntax it read.
- **The find bar keeps counting matches inside collapsed runs and revealing only the current one** —
  ADR-0018 §D2's fourth trigger, unchanged, now reaching four more constructs. A match inside a
  *hidden table row* is a new case and answers the same way it does for a folded section: counted,
  not shown, until something reveals it. Named rather than discovered.
- **The unit suite can cover the spans, the grammar and the range arithmetic, and nothing else.**
  Everything interactive is on screen, which is what `scripts/uitests.sh` before every merge already
  exists for, with `-disableCalendar YES` and `accessibilityIdentifier` rather than prose.
- **SPEC §14's row and §5's closing note both stop being true when the last phase ships**, and the
  amendment is debt filed the way ADR-0017 §D5 and ADR-0018 filed theirs.

## References

- `docs/adr/0005-the-diary-is-a-pane-of-its-own.md` §D2 (superseded), §D1/§D3–§D8 (untouched)
- `docs/adr/0010-transclusion-is-a-view-of-another-note.md` §D2, §D3
- `docs/adr/0018-the-editor-hides-the-syntax-it-can-draw.md` §D1, §D2, §D3, §D4 (boundary
  superseded), §D5, §D6, §D7
- `docs/adr/0019-embed-drag-resize.md` §D2, §D5, §D7, §D8
- `docs/adr/0028-wysiwyg-markdown-in-workspace.md` §D2, §D4
- `docs/20260817_TextKit2_live_editing.md` — every measurement ADR-0018 quotes
- `docs/20260811_Pergamenum_SpecApp.md` §5, §14 (to be amended; not edited by this ADR)
- `SPEC.md` (PG-018) R-01 … R-15; `BRAINSTORM.md` (2026-09-02) Alternatives A/B/C
- SDK, `MacOSX26.5.sdk`: `NSTextContentManager.h:118-120`, `NSTextAttachment.h:43`, `:86-93`,
  `:106-127`, `NSTextLayoutFragment.h:106-107`, `NSAttributedString.h:238`
- Source read for this ADR: `EditorDecorationDelegate.swift`, `+ListRendering`, `+CheckboxRendering`,
  `MarkdownStyler.swift`, `MarkdownBlocks.swift`, `NoteTextView.swift`, `+Coordinator`, `+EmbedCaret`,
  `EditorColumnView.swift`, `EditorColumn+Text.swift`, `NoteTabBar.swift`, `VaultBrowser.swift`,
  `MenuCommands.swift`, `CommandActions.swift`, `ShortcutCommand.swift`, `ShortcutStore.swift`,
  `EditorCommand.swift`, `CompletingTextView+Pasteboard.swift`, `DiaryView.swift`,
  `DiaryController.swift`, `DiaryToolbar.swift`, `TranscludedNoteView.swift`, `NoteExporter.swift`,
  `MarkdownBlocksView+Table.swift`, `Project.swift`, `.claude/protected-interfaces`
