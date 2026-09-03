# SPEC — Editor WYSIWYG unification (PG-018)

**Topic slug:** editor-wysiwyg-unification

## 1. Objective

Collapse the note editor's two current modes — a source-visible editable view
(`NoteTextView`, TextKit 2, with ADR-0018/0028's partial concealment) and a separate,
non-editable, full block renderer (`MarkdownReadingView`/`MarkdownBlocksView`) toggled
per tab via `isReadingMode` — into a single, always-editable, fully styled view. No
Modifica/Lettura toggle remains. Everything the block renderer draws today, GFM tables
included, must be achievable and editable inside the one surface. The same unification
applies to the Diario pane (ADR-0005 §D2), whose reading half currently sits beside an
unchanged source editor on the same premise this SPEC removes.

## 2. Why (context)

`ADR-0018` ("The editor hides the syntax it can draw") already established the
mechanism — paragraph substitution at identical character length, reveal-on-caret — but
scoped it deliberately to three constructs ("three named constructs, not the rule"):
heading `#`, emphasis `*`/`_`, and inline image/PDF embeds. `ADR-0028` added list
markers on the same mechanism. `SPEC §14` (the project's authoritative spec,
`docs/20260811_Pergamenum_SpecApp.md`) still rules out "live preview completa" as the
highest-cost item in the project, with the stated reasoning "source mode con stile è
sufficiente" — a reasoning this feature directly contests, having now shipped three
years... three weeks of evidence that the mechanism holds for more than three
constructs. `ADR-0005 §D2` built the Diario pane on "the pane sits beside an unchanged
source editor" — a premise this feature removes for the note editor and, per this
session's interview, for the Diario pane as well.

This SPEC's ADR must explicitly supersede `ADR-0005 §D2` and `ADR-0018`'s scope
boundary, and amend `SPEC §14` and (already partially amended this session) `SPEC §5`.

## 3. Scope

**In scope:**
- Extend paragraph-substitution concealment to: blockquote `>` (full nesting), horizontal
  rule `---`, wikilink/link bracket concealment (with hover tooltip showing the resolved
  target), strikethrough `~~`.
- GFM tables as a real, editable cell grid — not a fourth delimiter-hiding case. Once text
  forms a valid table, the raw pipe syntax is no longer directly editable as text; all
  editing (cell content, add/remove row, add/remove column) goes through the grid. A new
  table is created only via a slash-menu/Inserisci command (never by typing raw pipes).
  Pasting a markdown table onto the editor renders it as a grid immediately, matching the
  existing "paste URL → link" pattern (SPEC §5).
- The Diario pane: same unification, its separate rendering half removed, editor becomes
  the single view there too.
- Removal of the per-tab `isReadingMode` toggle and its UI (`NoteTabBar.swift:70`,
  `VaultBrowser.swift:132`).
- `MarkdownReadingView`/`MarkdownBlocksView`: kept, decoupled from the toggle, reserved
  for a future export/print feature (not designed here).
- UI tests that currently exercise the mode toggle (same family as `PG-031`) updated to
  match the new single-mode reality.
- ADR superseding `ADR-0005 §D2` and `ADR-0018`'s "three constructs" boundary; amendment
  of SPEC §14 and (further) SPEC §5.

**Out of scope:**
- Workspace `.text` cards (ADR-0027/0028): already single-mode with no reading toggle,
  nothing to unify there.
- Any new markdown construct beyond the ones named above (e.g. footnotes, definition
  lists) — not part of this app's CommonMark+GFM baseline today.
- Export/print feature design for the retained block renderer.

**Phasing (single ADR, single chain, staged plan):** the implementation plan orders work
by increasing risk — simple delimiter-style constructs first (blockquote, hr, link/wikilink
concealment, strikethrough), then the table grid, then the Diario pane unification last —
each phase verifiable on screen before the next starts, per this project's standing
"one milestone at a time" convention.

## 4. Stack / constraints

- Swift 6, SwiftUI + AppKit (`NSViewRepresentable`), TextKit 2 `NSTextView`
  (`NoteTextView`), macOS 26 Tahoe+.
- Reuses `EditorDecorationDelegate` (`NSTextContentStorageDelegate`) — the existing
  paragraph-substitution mechanism from ADR-0018 §D1 / ADR-0028 §D3. A protected
  interface (`.claude/protected-interfaces`).
- `MarkdownStyler` supplies the `Span` classification the delegate substitutes on; new
  `Span` cases needed for each newly-concealed construct, same shape as the existing
  `.heading`/`.bold`/`.italic`/list cases.
- No new third-party dependency (GRDB is the only one this repo carries; a table grid
  must be built on TextKit 2/AppKit primitives, not a new library).
- File over app: the source markdown stays the single stored representation; a table's
  pipe syntax on disk is the source of truth, the grid is a view over it, exactly as the
  concealed heading `#`/emphasis markers are today.

## 5. Architecture (high level — the ADR resolves the details)

- **Concealment extension (low risk):** four new `Span` cases in `MarkdownStyler`, four
  new hidden-marker branches in `EditorDecorationDelegate`, following the exact shape of
  the existing heading/emphasis/embed cases. Blockquote nesting draws one bar per level.
  Link/wikilink concealment adds a hover-tooltip mechanism (new, not present for the
  three existing constructs, which need none since they reveal on caret instead of
  requiring a hover).
- **Table grid (high risk, new mechanism):** a table's source lines are represented as an
  `NSTextAttachment`-hosted grid view spanning the paragraph range that holds the pipe
  syntax, edited only through that view (cell text fields, row/column add/remove
  commands) — never through direct text editing of the pipe characters. Edits to the grid
  rewrite the corresponding source lines through the same `shouldChangeText`/
  `beginEditing`/`replaceCharacters`/`endEditing` atomic path the embed resize/delete
  mechanisms already use (ADR-0019 precedent), so each structural edit (cell edit, row
  add/remove, column add/remove) is one undo step. Slash-menu "Tabella" command inserts an
  empty N×M table at the caret. A pasted markdown table is recognized and rendered as a
  grid immediately (reuses the existing paste-recognition path SPEC §5 already describes
  for URLs).
- **Diario pane:** its rendering half is removed; the pane hosts the same unified editor
  the note view uses. ADR-0005's other decisions (unrelated to the reading/source split)
  are untouched.
- **Toggle removal:** `isReadingMode`, `NoteTabBar`'s toggle control, and
  `VaultBrowser.swift:132`'s `Toggle` are removed. `MarkdownReadingView`/
  `MarkdownBlocksView` remain in the tree, unreferenced by the toggle, explicitly reserved
  for a future export/print feature.

## 6. Data model

No new persisted state. The markdown source text remains the sole on-disk
representation for every construct in scope, including tables (GFM pipe syntax). No
index schema change (`IndexCache.schemaVersion` untouched — this is a rendering-layer
feature, not a data-layer one).

## 7. UI flows

- Opening any note or Diario entry: single view, always fully styled, always editable.
  No mode indicator, no toggle.
- Typing inside a concealed construct's paragraph reveals its syntax (existing
  ADR-0018 §D2 rule, unchanged, extended to the four new constructs).
- Hovering a concealed link/wikilink shows a tooltip with the resolved target.
- Inserting a table: slash-menu or Inserisci menu command → empty N×M grid at the caret.
- Editing a table: click into a cell to edit its text; row/column add-remove via
  in-grid controls (exact affordance left to the architect/coder, following this app's
  existing embed-resize-handle visual language where applicable).
- Pasting a markdown table: renders as a grid immediately, same turn.

## 8. Edge cases

- A fenced code block containing something that looks like a table (pipes inside
  ```lines```) must never be mistaken for a real table — table recognition only applies
  outside fenced code, same rule the existing code-fence handling already enforces for
  headings.
- A malformed/partial pipe table (inconsistent column counts, no separator row) is left
  as plain text, never force-rendered as a broken grid.
- Undo/redo: each table structural edit (cell edit, row add/remove, column add/remove) is
  exactly one `Cmd+Z` step, matching every other structured edit in this app (outline
  move, embed resize, crop).
- An external edit (FSEvents reload, "Ricarica da disco") replacing note text under an
  open table grid must not corrupt the grid — same reload-replaces-whole-buffer discipline
  ADR-0018 §D3 already establishes for embeds.
- Blockquote nesting (`>`, `>>`, `>>>`, ...) draws one bar per level, unbounded.

## 9. Success criteria

- [ ] R-01 — Opening any note shows one always-editable, fully styled view; no Modifica/Lettura toggle is present anywhere in the note editor UI
- [ ] R-02 — `isReadingMode` and its toggle controls (`NoteTabBar.swift`, `VaultBrowser.swift`) are removed from the codebase
- [ ] R-03 — Blockquote `>` (unbounded nesting), horizontal rule `---`, wikilink/link brackets, and strikethrough `~~` conceal their syntax outside the caret's paragraph, following the same reveal-on-caret rule as headings/emphasis (ADR-0018 §D2)
- [ ] R-04 — A concealed link/wikilink shows its resolved target in a hover tooltip
- [ ] R-05 — A GFM table renders as an editable cell grid; cell content, row add/remove, and column add/remove are each editable through the grid and never through direct text editing of pipe characters
- [ ] R-06 — A new table is created only via a slash-menu/Inserisci command, inserting an empty N×M grid
- [ ] R-07 — Pasting a markdown table onto the editor renders it as an editable grid in the same turn
- [ ] R-08 — Each table structural edit (cell edit, row add/remove, column add/remove) is exactly one `Cmd+Z` undo step
- [ ] R-09 — A fenced code block's pipe-containing lines are never rendered as a table
- [ ] R-10 — A malformed pipe table (inconsistent columns, no separator row) renders as plain text, not a broken grid
- [ ] R-11 — The Diario pane hosts the same unified editor, with no separate reading-mode rendering left beside it
- [ ] R-12 — `MarkdownReadingView`/`MarkdownBlocksView` remain in the codebase, unreferenced by any toggle, with a code comment or ADR note stating they are reserved for a future export/print feature (no-test: this is a documentation/retention decision, not an assertable behavior)
- [ ] R-13 — UI tests exercising the removed mode toggle (the `PG-031` family) are updated to match the single-mode reality; `scripts/uitests.sh` passes before merge (no-test: this criterion is verified by running the existing suite, not by a new assertion)
- [ ] R-14 — The ADR for this feature explicitly states it supersedes `ADR-0005 §D2` and `ADR-0018`'s three-construct scope boundary (no-test: an ADR content requirement, not a runtime behavior)
- [ ] R-15 — `docs/20260811_Pergamenum_SpecApp.md` §14 is amended to reflect that "live preview completa" is no longer excluded, and §5 is updated to drop the two-mode description this session added (no-test: a documentation amendment, not a runtime behavior)
