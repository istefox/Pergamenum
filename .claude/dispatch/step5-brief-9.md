<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=9 lines=354-374 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 9-9

## Task text (verbatim, plan lines 354-374)

### Task 9 — regression fence: transclusion, export and the Viste pane are untouched (R-10, R-11, R-12)

- **Tester** writes `Tests/ViewBlockOutOfScopeTests.swift`:
  - **R-10** — `MarkdownBlocksView`'s `view(for:)` still routes a `code(language: ViewBlock.language, …)`
    block to `RenderedViewBlock` with **neither** new input, and a `TranscludedNoteView` drawing a
    note containing a fence produces the same rendition it does today (assert on the block's inputs,
    not on pixels);
  - **R-11** — `NoteExporter`'s HTML for a note containing a fence is byte-identical to the pre-change
    output. Capture the expected string in the test, not from a golden file this chain writes;
  - **R-12** — `ViewCatalogue`'s cataloguing of a note with one valid and one invalid fence is
    unchanged: names, renderer types, match counts and block locations, including the
    `lineIndex`/`heading` `ViewsPane` opens a note at. `Tests/SidebarTests.swift:65-110` already covers
    part of this and **must stay green unmodified**;
  - the error card still renders on the transclusion path for an unparseable fence — ADR §D7's
    "the error card keeps the surfaces it already has", asserted rather than asserted-by-absence.
- **Coder**: nothing to implement if the design held. The task's real deliverable is the
  **grep evidence** in its report: `MarkdownBlocksView.swift`, `TranscludedNoteView.swift`,
  `NoteExporter.swift`, `ViewsPane.swift` and `ViewCatalogue.swift` appear in `git diff --stat` for
  the whole chain **zero times**. If any of them does, stop and report — the design leaked.
- Budget: `Tests/ViewBlockOutOfScopeTests.swift` (~180 lines)

## File map (from Budget: declarations, tasks 9-9)

- Tests/ViewBlockOutOfScopeTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0033-views-render-live-in-the-editor.md -- fail-closed-to-source rule, transclusion/export/Viste-pane boundary
- SPEC: SPEC.md -- requirement IDs R-10/R-11/R-12
