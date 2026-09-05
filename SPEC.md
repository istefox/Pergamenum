# SPEC — Outline index row double-click toggles heading fold

**Topic slug:** outline-double-click-fold-toggle

**Date:** 2026-09-05

## Objectives

The sidebar's INDICE panel (`OutlinePane.swift`) already lets a person fold/unfold a heading's
section by clicking its chevron (`chevron(for:at:)`). That hit target is 12pt wide and requires
precise aim — reported directly by the user: "devo cliccare talmente preciso che spesso non mi
prende il comando" (the click frequently misses). This SPEC adds a second, larger gesture:
double-clicking the row's own text toggles the same fold, without changing what a single click
does (select/jump to that heading in the editor).

## Scope

- `Sources/Features/Editor/OutlinePane.swift`: `button(_:at:isCurrent:)`, the row's text button
  that currently only calls `onSelect` on click.
- No change to `chevron(for:at:)`, `foldable`, `hiddenByFold`, drag-and-drop
  (`beginDrag`/`HeadingDraggable`), or any file outside `OutlinePane.swift`.
- No change to the note editor's own fold-badge click path
  (`NoteTextView+Transclusion.unfold(at:in:)`) — this SPEC is sidebar-only.

## Out of scope

- Any change to single-click behavior (`onSelect`, jump-to-heading).
- Any change to the chevron's own hit target size or shape.
- Any change to fold state storage (already offset-keyed since the `fold-state-offset-rekey`
  fix on this same branch).

## UI flow

1. Person double-clicks a heading row's text (title, not the chevron) in INDICE.
2. If the row is `foldable` (has content under it) and is a `.heading` entry: the same fold
   toggle the chevron performs runs, using the entry's own UTF-16 offset.
3. If the row is not foldable, or is an `.embed` entry: double-click is a no-op for folding —
   it still performs whatever the single click's first tap already does (selection), since two
   taps of a `Button` cannot be suppressed without also suppressing its normal single-tap action
   for every other click in the same gesture.
4. Single click continues to select/jump exactly as today, on every row.

## Edge cases

- Double-click on a non-foldable heading (nothing to hide): no fold toggle, no error, no visual
  change beyond whatever single-click selection already produces.
- Double-click on an `.embed` row: no fold toggle (embeds have no `chevron` shown today either).
- Rapid alternating single/double clicks: must not desync from the chevron's own toggle state,
  since both write through the same `vault.toggleFold(offset)` / read the same
  `vault.foldedEntries`.

## Success criteria

- [ ] R-01 — Double-clicking a foldable heading row's text in INDICE toggles that heading's
      fold state, identically to clicking its chevron (same `vault.toggleFold(offset)` call,
      same offset).
- [ ] R-02 — Single-click behavior (`onSelect`, row selection/jump) is unchanged for every row,
      foldable or not, heading or embed.
- [ ] R-03 — Double-clicking a non-foldable row or an `.embed` row does not toggle any fold
      state and does not crash or misbehave.
- [ ] R-04 — The chevron button's own behavior (`chevron(for:at:)`) is unchanged byte-for-byte.
- [ ] R-05 — Full existing unit suite (2150 tests as of this branch) stays green; a new test
      pins the double-click-toggles-fold behavior.
