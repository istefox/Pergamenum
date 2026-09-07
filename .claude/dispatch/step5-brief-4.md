<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=5 lines=240-268 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 5-5

## Task text (verbatim, plan lines 240-268)

### Task 5 — the Coordinator's `applyViewBlocks` pass, and the caret rescue (R-01, R-02, R-03, R-08, R-13)

- **Tester** extends `Tests/ViewBlockRenderingTests.swift` and adds
  `Tests/ViewBlockCaretTests.swift`. Declares `Coordinator.applyViewBlocks(to:runs:markers:&)`,
  `Coordinator.clearViewBlocks()`, `EditorDecorationDelegate.viewBlockRun(in:atParagraphStart:)`
  (`static`, `NSString`, UTF-16 — the `tableRun(in:atParagraphStart:)` shape, usable from both a
  non-actor drawing pass and a `@MainActor` one), all stubbed. Assertions:
  - **attachment creation from a valid fence** (R-13's first named case): after a styling pass, the
    opening fence paragraph's substituted copy carries a `ViewBlockAttachment` at offset 0 and
    `collapsedFont` over the rest, and the paragraph's **length is unchanged** (R-01, R-02, R-03 —
    one assertion per renderer keyword, since the pass must not read `render:`);
  - **fallback to raw text on an unparseable fence** (R-13's second named case): a fence whose body
    fails `ViewBlock.parse` produces **no marker, no attachment and no hidden lines** — the paragraph
    is returned `nil` and the body stays in the layout (R-08, ADR §D7);
  - an unclosed fence produces nothing at all (C5);
  - with `hidesMarkup` false the pass registers nothing **and clears what it registered before**
    (ADR §D12 — the `clearTables()` trap, which reaches the enumeration refusal too);
  - `Tests/ViewBlockCaretTests.swift`: a caret placed programmatically inside a body line that the
    pass then hides is moved to the opening fence line's offset, after the storage transaction
    closes, never inside it (ADR §D15, `tableCaretRescue`'s twin).
- **Coder** writes `Sources/Features/Editor/NoteTextView+ViewBlocks.swift` (the `applyTables` shape:
  `markers` `inout`, its own guard, its own change check on the hidden-line set, its own
  `apply(viewBlockLines:)`/`apply(viewBlockHosts:)` calls, called from `applyStyling` **before**
  `storage.endEditing()`) and
  `Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift` (the substitution branch
  and the static re-read). The host refresh and the caret rescue run **after** the transaction closes,
  beside `refreshTableGrids`.
- Budget: `Sources/Features/Editor/NoteTextView+ViewBlocks.swift`, `Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift`, `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `Tests/ViewBlockRenderingTests.swift`, `Tests/ViewBlockCaretTests.swift` (~420 lines)

## File map (from Budget: declarations, tasks 5-5)

- Sources/Features/Editor/EditorDecorationDelegate+ViewBlockRendering.swift
- Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/NoteTextView+ViewBlocks.swift
- Tests/ViewBlockCaretTests.swift
- Tests/ViewBlockRenderingTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0033-views-render-live-in-the-editor.md -- attachment creation gate, fallback-to-source rule, closed-fence precondition (ADR §D6/§D7)
- SPEC: SPEC.md -- requirement IDs for this batch's tests
