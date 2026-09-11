<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=5 lines=261-286 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 5-5

## Task text (verbatim, plan lines 261-286)

### Task 5 — the note editor wiring (R-01, R-02, R-03, R-04, R-07)

- `NoteTextView`: `var revealsInlineSpans = false`, passed at all three production sites
  (`EditorColumn+Text.swift:47` from `vault.settings`, `DiaryView.swift:88`, `TodayView.swift:192`
  — all three, so the Diario and Oggi editors behave like the main one).
- `NoteTextView+Coordinator.applyStyling`: `decorations.apply(revealsInlineSpans: parent.revealsInlineSpans)`
  beside `apply(hiddenMarkers:hidingMarkup:)` and **before `storage.endEditing()`** (F6, and the
  same placement rule `applyTables`/`applyViewBlocks` already follow).
- `NoteTextView+Reveal.applyReveal`: compute `MarkupReveal.inlineSpans(...)` when
  `parent.revealsInlineSpans` and `[:]` otherwise; keep it in a new `lastRevealedSpans` beside
  `lastRevealed`; the early return now requires **both** to be unchanged; union the two change
  sets and invalidate each changed paragraph once, through the existing
  `storage.edited(.editedAttributes, range: paragraph, changeInLength: 0)` loop. Never the whole
  document.

**Tester** adds a suite driving a real `NoteTextView` coordinator + `NSTextView` (the shape
`Tests/MarkupHidingTests.swift:970` and `Tests/ViewBlockCaretTests.swift:52` already use): with
the flag on and the caret inside one of two bold runs, the delegate's span table names exactly one
paragraph and one range; moving the caret out empties it; flipping the flag off empties it;
`applyReveal` called twice with an unmoved caret invalidates nothing the second time (the early
return still holds). Red first.

**Coder** wires it.

- Budget: `NoteTextView.swift`, `NoteTextView+Coordinator.swift`, `NoteTextView+Reveal.swift`, `EditorColumn+Text.swift`, `DiaryView.swift`, `TodayView.swift`, `Tests/MarkupHidingTests.swift` (~180 lines)

## File map (from Budget: declarations, tasks 5-5)

- DiaryView.swift
- EditorColumn+Text.swift
- NoteTextView+Coordinator.swift
- NoteTextView+Reveal.swift
- NoteTextView.swift
- Tests/MarkupHidingTests.swift
- TodayView.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- delegate wiring + applyStyling push point (ADR §D6)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs for this task's tests
