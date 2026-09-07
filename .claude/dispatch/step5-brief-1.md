<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=1 lines=127-150 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 1-1

## Task text (verbatim, plan lines 127-150)

### Task 1 — `MarkdownStyler` learns `.viewBlockRun`, closed fences only (R-01, R-02, R-03, R-04, R-08)

- **Tester** writes `Tests/ViewBlockSpanTests.swift` and adds the `case viewBlockRun` declaration to
  `MarkdownStyler.Span` plus the three exhaustive-switch arms (compile-forced, listed in the contract
  table) so the target builds. Assertions, all red against a `viewBlockRuns(in:outside:)` stubbed to
  return `[]`:
  - a closed ```` ```pergamenum-view … ``` ```` fence yields exactly one `.viewBlockRun` covering the
    opening backticks through the closing ones inclusive (R-01);
  - a closed fence with `render: gallery` / `render: calendar` / `render: board` yields one too — the
    span does not read `render:` at all (R-02, R-03, R-04);
  - an **unclosed** ```` ```pergamenum-view ```` at the end of a note yields **no** span (ADR §D6, C5);
  - a ```` ```swift ```` fence yields no span; a ```` ```pergamenum-view ```` fence nested inside an
    outer fence follows `CodeFence.regions`' own alternating grammar and is asserted to whatever that
    grammar answers, **documented in the test rather than asserted from intuition** (ADR Consequences);
  - two fences in one note yield two spans, in document order (SPEC Edge cases);
  - a fence whose body does **not** parse still yields a span here — R-08's refusal happens in Task 5,
    not in the styler, because the styler must not run the query grammar on every keystroke (R-08).
- **Coder** implements `viewBlockRuns(in:outside:)` beside `tableSpans(in:from:outside:)`
  (`MarkdownStyler.swift:441-452`), fed by the `fences` array `spans(in:)` already computes at `:114`,
  appended **after** the `.codeBlock` spans so it wins on overlap (ADR §D14).
- **Contract-staleness:** re-run `Tests/MarkdownStylerTests.swift` in full. `:54` and `:100` must stay
  green **unmodified**; a red there means the span is emitted outside a fence.
- Budget: `Sources/Features/Editor/MarkdownStyler.swift`, `Sources/Features/Editor/MarkdownAttributedText.swift`, `Sources/Features/Workspace/CardTextAttributes.swift`, `Tests/ViewBlockSpanTests.swift` (~180 lines)

## File map (from Budget: declarations, tasks 1-1)

- Sources/Features/Editor/MarkdownAttributedText.swift
- Sources/Features/Editor/MarkdownStyler.swift
- Sources/Features/Workspace/CardTextAttributes.swift
- Tests/ViewBlockSpanTests.swift

## Excluded tasks (not in this batch)

- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/adr/0033-views-render-live-in-the-editor.md -- MarkdownStyler span ordering and fence-scope constraints (ADR §D14)
- SPEC: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/SPEC.md -- requirement IDs R-01..R-04, R-08 for this batch's tests
