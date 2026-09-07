<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=7 lines=299-325 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 7-7

## Task text (verbatim, plan lines 299-325)

### Task 7 — wire `viewQuerySource`, live refresh, and click-to-open (R-07, R-09, R-13)

- **Tester** writes `Tests/ViewBlockQuerySourceTests.swift`. Declares `NoteTextView.queries` and the
  two new optional inputs on `RenderedViewBlock` plus `onOpenNote` on the four renderers, all
  defaulted `nil`. Assertions:
  - **live refresh on an index update** (R-13's third named case, R-07): bumping
    `ViewQuerySource.generation` changes the id `RenderedViewBlock`'s `.task(id:)` is keyed on, and the
    store pushes an updated root view carrying it — asserted on the composed id string and on the
    store's `update(_:forOrdinal:)` having been called, without needing a live SwiftUI render;
  - **a keystroke that does not change the fence's source does not change that id** — the assertion
    ADR-0009 §D7 turns into a test, and the one C6/ADR §D3 exist to make possible;
  - a text edit **above** the fence leaves both the host identity and the id unchanged (the same
    property from the store's side, asserted here from the pass's side);
  - **R-09**: with `onOpenNote` non-nil, a table row, a list line, a gallery item and a calendar entry
    each expose a click target carrying the row's title; with it `nil`, none of them do — which is
    today's rendering and is what keeps R-10/R-11 true (four assertions plus four negatives);
  - `NoteTextView` built with no `queries` (the `DiaryView`/`TodayView`/test default) renders the fence
    as source and creates no host.
- **Coder** adds `queries` to `NoteTextView`, passes `viewQuerySource` from
  `EditorColumn+Text.swift:47`'s `editing(_:)`, **rewrites the now-false "unreferenced" comment at
  `:194-198`**, threads `onOpenNote` through `RenderedViewBlock` into the four renderers as an
  optional click target, wires `onEditSource` into the block header beside the existing refresh button
  (ADR §D10), and wires `onOpenNote` in the editor to the same `onFollowLink` door a wikilink uses.
- **`DiaryView.swift` and `TodayView.swift` are not edited.** They keep the `nil` default deliberately
  (ADR Consequences). If a task looks like it needs to edit them, stop and report.
- Budget: `Sources/Features/Editor/NoteTextView.swift`, `Sources/Features/Editor/EditorColumn+Text.swift`, `Sources/Features/Views/RenderedViewBlock.swift`, `Sources/Features/Views/ViewRowRenderers.swift`, `Sources/Features/Views/ViewGridRenderers.swift`, `Tests/ViewBlockQuerySourceTests.swift` (~340 lines)

## File map (from Budget: declarations, tasks 7-7)

- Sources/Features/Editor/EditorColumn+Text.swift
- Sources/Features/Editor/NoteTextView.swift
- Sources/Features/Views/RenderedViewBlock.swift
- Sources/Features/Views/ViewGridRenderers.swift
- Sources/Features/Views/ViewRowRenderers.swift
- Tests/ViewBlockQuerySourceTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0033-views-render-live-in-the-editor.md -- host store live-refresh keying, R-07/R-09
- SPEC: SPEC.md -- requirement IDs for this batch's tests
