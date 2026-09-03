# BRAINSTORM — Editor WYSIWYG unification (PG-018)

**Date:** 2026-09-02
**Requirements source:** /Users/stefer/Developer/Pergamenum/SPEC.md
**Techniques applied:** first-principles, assumption-busting, cross-domain analogies, alternatives synthesis, inversion/pre-mortem, adjacent ideas

## Reframed problem (first-principles)

The irreducible outcome is not "one visual mode" — it is a persistent per-cell data model
for GFM tables that stays bidirectionally synced with the pipe-syntax markdown on disk,
with everything else (grid interaction, hover tooltips, concealment of the other four
constructs) built as a view layer on top of that sync. The two-mode toggle is the visible
symptom; the table sync problem is the actual new engineering the ADR must solve — the
other four concealment extensions (blockquote, hr, link, strikethrough) are mechanical
repetitions of an already-proven mechanism (ADR-0018 §D1) and carry no open design
question.

## Challenged assumptions

- "The pipe-syntax markdown must stay the only on-disk representation of a table, the
  grid is always a derived view" — outcome: **retained**, real and immutable. File-over-app
  (CLAUDE.md principle 1) is binding; no second persisted representation for tables, even
  to simplify grid editing.
- "Cell edits must reach the source text on every keystroke" — outcome: **dropped**, per
  the spreadsheet-editor analogy below. Each cell is its own small text-editing scope with
  commit-on-blur/Tab; the source rewrite happens once per cell commit, not per keystroke —
  compatible with, and actually needed by, the interview's existing "one `Cmd+Z` per
  structural edit" requirement (R-08).
- "A table's cell content is authoritative in the grid while editing, and in the text
  otherwise" — outcome: **retained as the working model**, following from the point above:
  the grid is the sole editing surface (SPEC R-05), so there is no dual-authority window to
  reconcile — the source is simply out of date between commits, exactly as any concealed
  paragraph is "out of date" (still holds `#`) until the caret leaves it.

## Approach alternatives

### Alternative A — `NSTextAttachment` hosting a real `NSView` grid
- **Idea:** the table renders as an attachment (ADR-0019 precedent) whose custom view is a
  genuine `NSView` hierarchy with one text field per cell; Tab/Shift-Tab and click move
  focus between cells inside that subview.
- **Axis of difference:** responsibility boundary — table editing is fully delegated to a
  self-contained AppKit subview, the surrounding `NSTextView` only lays out its bounding box.
- **Pros:** one layout mechanism, directly consistent with the existing embed
  attachment/resize-handle precedent; no new coordinate-mapping code.
- **Cons:** nested first-responder management inside a TextKit 2 attachment is exactly the
  pre-mortem's named risk (see below) — undocumented territory for this codebase.
- **Indicative cost/time:** medium-high.

### Alternative B — Floating overlay panel positioned over the table's text range
- **Idea:** the table's text range collapses to placeholder/blank lines; a separate
  `NSPanel`/overlay, positioned via `firstRect(forCharacterRange:)` in board-space
  coordinates (the `FormatBar`/`BoardMarquee` pattern), hosts the actual editable grid.
- **Axis of difference:** deployment model — two separately-positioned surfaces (text hole
  + overlay) instead of one attachment.
- **Pros:** reuses an already-proven geometry pattern in this codebase.
- **Cons:** two sources of visual truth to keep aligned on scroll/resize/zoom; inherits the
  documented `firstRect` zero-rect bug for not-yet-laid-out ranges (ADR-0028's note) — not
  a new risk invented for this brief, an existing one this path would reawaken.
- **Indicative cost/time:** medium.

### Alternative C — Hybrid: static attachment view + on-demand floating cell editor
- **Idea:** the grid renders as a read-only attachment (fast, no permanent subviews); a
  click on a cell pops a small floating single-cell editor (this app's existing
  inline-rename pattern), committing back to the static render on dismiss.
- **Axis of difference:** concurrency/time model — introduces an explicit
  viewing-vs-editing-cell state machine instead of a permanently-live grid.
- **Pros:** minimizes permanently-nested subviews, smallest surface for the pre-mortem's
  focus-management risk.
- **Cons:** a second UI state to design and test explicitly (not needed by A or B); breaks
  the "click into a cell to edit" immediacy the interview described (SPEC §7).
- **Indicative cost/time:** medium.

**User's stated preference across all three dialogue steps: Alternative A**, taken together
with the spreadsheet-editor sync model (commit-on-blur/Tab, not per-keystroke).

## Risks emerged (inversion / pre-mortem)

- **TextKit 2 nested-`NSView` focus/Tab reliability** (flagged as the primary risk) →
  mitigation: the architect should prototype/verify first-responder handoff between cells
  early (candidate for a Step 4.5 tracer-bullet probe on exactly this mechanism, before
  committing to the full table-grid implementation plan) rather than discovering the
  problem mid-plan.
- Concurrent external edit (FSEvents reload) corrupting an open grid → mitigation already
  named in SPEC §8: same reload-replaces-whole-buffer discipline as ADR-0018 §D3 for
  embeds; the architect must state explicitly how an open grid detects and survives a
  buffer replacement mid-edit.
- Performance degradation with large/many tables (real `NSView` per cell has non-trivial
  layout/memory cost) → not selected as the primary pre-mortem risk this round, but worth
  the architect noting as a secondary concern given Alternative A was chosen.

## Adjacent ideas emerged

- Export/print feature reusing the retained `MarkdownReadingView`/`MarkdownBlocksView` —
  **future**, already named explicitly in SPEC R-12/out-of-scope; this brief reconfirms it
  as the natural next use of the renderer this feature deliberately keeps alive.

## Preliminary recommendation

**Preliminary, non-binding:** Alternative A (`NSTextAttachment`-hosted `NSView` grid),
combined with the spreadsheet-editor sync model — cell edits are scoped to the cell's own
text-editing session and rewrite the source only on commit (Tab/blur/Enter), never per
keystroke. This matches the user's explicit choice at every relevant dialogue step and is
the most architecturally consistent with ADR-0019's existing embed/attachment precedent.
The one open engineering risk the architect must resolve before or during planning is
nested first-responder handling between cells inside the attachment's view hierarchy —
recommend evaluating a tracer-bullet probe (ADR-0057, Step 4.5) scoped narrowly to
"can Tab move focus reliably between two cells in an `NSTextAttachment`-hosted `NSView`
inside this app's `NoteTextView`" before the full plan is written, since a negative result
here would force a pivot toward Alternative B or C mid-implementation rather than at
design time.

## Notes for the architect

- The commit-on-blur/cell sync model is new information beyond SPEC.md's §5/§7 (which
  describe click-to-edit but not the commit granularity) — the ADR should state it
  explicitly, and SPEC.md's Architecture/UI-flows sections may need a follow-up amendment
  to match once the ADR settles it.
- Blockquote/hr/link/strikethrough concealment carries no open design question — treat as
  mechanical extension of ADR-0018 §D1, lowest risk, first in the phased plan per SPEC's
  existing phasing decision.
- Consider whether the tracer-bullet probe above is warranted given `chain_path: standard`
  already implies a fresh session before implementation — this is exactly the kind of
  narrow, high-uncertainty mechanism ADR-0057 was designed for.
