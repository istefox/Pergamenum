<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=6 lines=287-312 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 6-6

## Task text (verbatim, plan lines 287-312)

### Task 6 — the Workspace card wiring (R-09)

The route `hidesMarkup` already travels, one property wider (ADR §D8):
`WorkspaceController.revealsInlineSpans` (a plain `var`, default `false`) ←
`WorkspaceView.applyBoardSettings()` (beside `WorkspaceView.swift:483`) → `StickyTextCard.swift:53`
→ `CardTextView.revealsInlineSpans` (**a defaulted `var`, not a `let`** — six test construction
sites must stay unmodified) → `CardTextView.Coordinator.applyStyling`'s
`decorations.apply(revealsInlineSpans:)` and `CardTextView+Reveal.applyReveal`'s span computation,
still gated on `textView.isEditable` exactly as the paragraph reveal is. `releaseDecorations()`
clears the span table with the rest.

**Tester** extends `Tests/CardConcealmentTests.swift`: with the flag on and a card being edited,
a caret in one of two bold runs collapses only the other's markers; a card at rest reveals nothing
regardless of the flag (R-04 of ADR-0028 is not weakened); `releaseDecorations()` leaves the span
table empty; and — **F1, asserted rather than assumed** — a card containing `~~barrato~~` and
`[[Nota]]` produces no `.strikethrough`/`.link` marker at all, so the flag changes nothing for
them. Red first.

**Coder** wires it. **`CardTextView`'s `hiddenKind` switch is not widened.**

- Budget: `WorkspaceController.swift`, `WorkspaceView.swift`, `StickyTextCard.swift`, `CardTextView.swift`, `CardTextView+Reveal.swift`, `Tests/CardConcealmentTests.swift` (~150 lines)

---

## Phase 4 — the fence around what must not move

## File map (from Budget: declarations, tasks 6-6)

- CardTextView+Reveal.swift
- CardTextView.swift
- StickyTextCard.swift
- Tests/CardConcealmentTests.swift
- WorkspaceController.swift
- WorkspaceView.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- Workspace card scope (ADR §D8)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs for this task's tests
