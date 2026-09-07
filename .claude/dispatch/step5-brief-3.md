<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=4 lines=213-239 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 4-4

## Task text (verbatim, plan lines 213-239)

### Task 4 — `ViewBlockAttachment` and `ViewBlockHostStore`, keyed by ordinal (R-01, R-02, R-03, R-06)

- **Tester** writes `Tests/ViewBlockHostStoreTests.swift` and declares `ViewBlockHostStore`
  (`@MainActor`, `host(for ordinal: Int, in textView: NSTextView) -> NSHostingView<…>`,
  `hosts(for ordinals: [Int], in:) -> [Int: NSHostingView<…>]`, `update(_ root:, forOrdinal:)`) and
  `ViewBlockAttachment` with its `height` constant, all stubbed. Assertions:
  - **the same host instance comes back for the same ordinal across calls** (ADR §D3) — the property
    that keeps the query from re-running, asserted by identity (`===`), not by equality;
  - **the host survives a changed paragraph offset** — ask for ordinal 0, then ask again after the
    note gained a line above the fence, and get the same instance. This is the assertion that
    distinguishes this store from `TableGridStore` and it is the one that must never be relaxed
    (C6, ADR §D3);
  - **`hosts(for:in:)` prunes**: an ordinal absent from the array is dropped, and a note that loses a
    fence does not accumulate a host;
  - **two identical fences in one note get two distinct hosts** (ADR §D3's rejection of a source-text
    key) — an `NSView` has one superview;
  - `attachmentBounds(…)` returns `proposedLineFragment.width` × the constant height, **independent of
    the content** (R-06, ADR §D8) — asserted at two different proposed widths and with two different
    stub result sets.
- **Coder** implements both, plus the provider (`tracksTextAttachmentViewBounds = true`,
  `loadView` assigning the host **it was given**), copying `TableAttachment.swift` for shape and
  diverging only where D3 and D8 say to. The root view is
  `ScrollView { RenderedViewBlock(…) }.environment(\.theme, theme)` — **the `ScrollView` lives here,
  never inside `RenderedViewBlock`** (ADR §D8, and R-10/R-11 depend on it).
- Deletes the Task 3 probe scaffold.
- Budget: `Sources/Features/Editor/ViewBlockAttachment.swift`, `Sources/Features/Editor/ViewBlockHostStore.swift`, `Tests/ViewBlockHostStoreTests.swift` (~260 lines)

## File map (from Budget: declarations, tasks 4-4)

- Sources/Features/Editor/ViewBlockAttachment.swift
- Sources/Features/Editor/ViewBlockHostStore.swift
- Tests/ViewBlockHostStoreTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0033-views-render-live-in-the-editor.md -- attachment mechanism, delegate ownership split, host store keying rule (ADR §D3)
- SPEC: SPEC.md -- requirement IDs for this batch's tests
