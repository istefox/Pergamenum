<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=6 lines=269-298 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 6-6

## Task text (verbatim, plan lines 269-298)

### Task 6 — reveal on the fence range, and the re-render on exit (R-05)

- **Tester** extends `Tests/ViewBlockCaretTests.swift` and declares
  `Coordinator.revealedViewBlock(in:) -> NSRange?` stubbed to `nil`. Assertions, the reveal predicate
  first as a **pure** test against a plain `String` (the `MarkupReveal.paragraphs` precedent):
  - a caret on the opening fence line reveals the block (R-05);
  - a caret on a **body** line reveals it too — the assertion C3 exists for, and the one a
    paragraph-keyed reveal cannot satisfy;
  - a caret on the closing fence line reveals it;
  - a caret on the line immediately above and immediately below reveals nothing;
  - a **selection** spanning from outside into the fence reveals it (ADR-0018 §D2 trigger 2 arriving
    by range);
  - a revealed fence produces **no** marker, **no** hidden lines and **no** host — the raw source is on
    screen and the body lines are laid out (R-05);
  - moving the caret back out re-registers all three against the **edited** source: edit the query in
    the revealed state, move out, and the re-rendered block reflects the new `render:` (R-05's second
    half);
  - two fences: revealing one leaves the other drawn (SPEC Edge cases, no shared state).
- **Coder** implements the predicate, wires `applyViewBlocks` to skip a revealed fence, and adds to
  `textViewDidChangeSelection` — after the existing `applyReveal(to:)` — a guarded
  `applyStyling(to:theme:)` when `revealedViewBlock(in:)`'s answer changed since the last call
  (ADR §D5). The guard is a stored `NSRange?`; a note with no fence pays one comparison per arrow key.
- **Watch for re-entrancy:** `applyStyling` sets `isStyling` around its own edit. Confirm no recursion
  through `textDidChange`, and say so in the task report.
- Budget: `Sources/Features/Editor/NoteTextView+ViewBlocks.swift`, `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/ViewBlockCaretTests.swift` (~220 lines)

---

## Phase 4 — the vault behind the block

## File map (from Budget: declarations, tasks 6-6)

- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/NoteTextView+ViewBlocks.swift
- Tests/ViewBlockCaretTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0033-views-render-live-in-the-editor.md -- reveal-on-caret keyed on the fence's whole source range, not per-paragraph (ADR §D4)
- SPEC: SPEC.md -- requirement IDs for this batch's tests
