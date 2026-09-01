# Upstream request: allow `status-*` beyond `status-inbox` (tag.md 5.1)

**Repo to change:** `harness-system` (NOT this repo). This file only prepares the request;
nothing here should be actioned against Pergamenum's own source.

**Tracking:** `PG-030` in `Pergamenum/TODO.md`. Blocked pending this change.

## Problem

Pergamenum's Workspace boards can group by any tag namespace via `group: tag("<glob>")`
(ADR-0009). A board grouped by `status-*` is fully implemented — columns render, and
dragging a card between columns rewrites the note's `status-*` tag through the same
journalled, differential-lint-checked write every other board drop uses (ADR-0009 §D5,
amended 2026-08-20).

It refuses every drop anyway, because `tag.md` 5.1 forbids a note from carrying any
`status-*` tag except `status-inbox`. The board's own linter guard is differential (it
only refuses a drop that *introduces* a new violation), so this isn't a bug in the guard —
the vocabulary itself currently has no legal destination status for a card to move to.

Per this project's principle 5 ("harness conformance... that repo stays the single source
of truth: when a convention changes, the app config is updated, never the other way
round"), Pergamenum cannot and should not work around this locally — no local exception,
no second vocabulary. The fix has to happen in `tag.md` itself.

## What's needed

1. Decide the legal `status-*` vocabulary for a client/project workflow with more than one
   state (`status-inbox` is not enough for M11's acceptance criterion: "a client board
   dragged between statuses"). Whatever states make sense for the domain — the workflow this
   unblocks is the "Clienti attivi" (active clients) board.
2. Update `tag.md` §5.1 to permit that set instead of `status-inbox` alone.
3. Regenerate `vocabolari.json` in Pergamenum's `.pergamenum/` config from the updated
   `tag.md` — principle 5's normal sync step, not a one-off.

## Effect once done

- A `status-*`-grouped board's drag-to-move stops being refused; M11's acceptance criterion
  becomes reachable.
- No code change needed in Pergamenum itself: `WorkspaceBoard`'s drop-rewrite path
  (ADR-0009 §D5) already handles multi-status and no-status notes correctly and is already
  gated on the vocabulary/lint check generically, not on a `status-*`-specific exception.
- `PG-030` closes once `vocabolari.json` is regenerated and a real drag is verified on a
  `status-*` board.

## Not needed once this lands

Nothing in ADR-0009 needs re-opening: §D5's amendment already anticipated this exact case
("a board by `status-*` refuses its own drops until the harness says a note may carry a
status - which is principle 5 working"). This request is that "until".
