<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md tasks=2,3 lines=151-212 -->
# Step 5 Batch Brief -- 2026-09-06-pg-099-views-board-renderer-orphaned-by.md -- tasks 2-3

## Task text (verbatim, plan lines 151-212)

### Task 2 — the delegate gains a sixth hidden-line input and a `.viewBlock` marker kind (R-01, R-06)

- **Tester** writes `Tests/ViewBlockRenderingTests.swift`, modelled line for line on
  `Tests/TableRenderingTests.swift` (its `substitutedParagraph` and `laidOutOffsets` helpers are the
  shape to copy, not to import). Declares, so the target builds: `HiddenMarker.Kind.viewBlock`, the
  `stillSpells` arm returning `false`, `apply(viewBlockLines:)`, `apply(viewBlockHosts:)`, and
  `viewBlockParagraph(at:storage:)` **stubbed to return `nil`**. Assertions:
  - with `apply(viewBlockLines:)` given the body and closing-fence offsets, a real offscreen layout
    pass lays out neither (R-01, R-06) — measured through `laidOutOffsets`, the way folding and tables
    already are;
  - **the closing fence line is in the set and is not laid out** (C4) — its own assertion, because
    this is the one place the arithmetic differs from a table's;
  - `apply(viewBlockLines:)` with an empty set clears **only** its own set: a fold registered through
    `apply(hiddenLines:foldedHeadings:)` and a table registered through `apply(tableRows:)` both
    survive it, and each of the other two clears only its own (ADR §D1, the delegate's own header
    rule). Three assertions, one per pair;
  - with `hidesMarkup` false, `viewBlockParagraph(at:storage:)` returns nil (ADR §D12) — **green with
    the stub**, and stays green after Task 5;
  - a `.viewBlock` marker whose recorded range no longer spells a fence draws nothing.
- **Coder** implements `apply(viewBlockLines:)` and `apply(viewBlockHosts:)` on
  `EditorDecorationDelegate`, and widens
  `textContentManager(_:shouldEnumerate:options:)` (`:241-251`) to the union of the three sets. The
  `viewBlockParagraph` body is **Task 5's**, not this one's.
- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`, `Tests/ViewBlockRenderingTests.swift` (~200 lines)

---

## Phase 2 — the gate

### Task 3 — tracer-bullet probe: SwiftUI inside a text attachment (ADR §D16 probes 1–3) (R-01, R-04)

**This is a gate, not a checkpoint. Tasks 4 and 8 are not planned in detail until it has an answer,
and a negative on probe 2 changes Task 8's shape rather than being worked around inside it.**

- Build the smallest real thing: a `ViewBlockAttachment` whose provider's `loadView` assigns an
  `NSHostingView` over a throwaway SwiftUI view holding a `@State` counter, a `Button`, and a
  two-column `.draggable`/`.dropDestination` pair — inside a real `CompletingTextView` inside a real
  `NSWindow`, reached from a fixed trigger word with no grammar behind it (the exact shape ADR-0029's
  Step 4.5 probe used before `EditorDecorationDelegate+TableRendering.swift` replaced it).
- **Probe 1 passes** when the host draws at the size `attachmentBounds` returned, the button responds
  to a click, and the `@State` counter survives a keystroke typed elsewhere in the note (i.e. the host
  instance was not rebuilt).
- **Probe 2 passes** when a card lifts on drag, the destination column highlights, the drop fires with
  the payload, and the text view does not treat the gesture as a text-selection drag.
- **Probe 3 passes** when either the text view keeps first responder through a click on the host, or
  the host takes it and `Esc` / a click in the note return it with a sane caret — never a state where
  keystrokes go nowhere. `TableGridStore.resignToTextView` (`:36-39`) is the wiring to copy if the
  host takes focus.
- **Write the result down**, per probe, in `PROJECT_BRIEF.md` beside the phase — ADR-0010's standard.
  A probe with no written result did not happen.
- **On a probe-2 failure:** report and stop. Task 8 switches to ADR §D16's named fallback (a per-card
  context menu on `ViewBoardRenderer`, offered only when `queries?.move != nil`, writing through the
  identical `ViewQuerySource.move` closure). That is a plan revision at Gate 2, not a coder decision.
- The probe scaffold is deleted in Task 4, exactly as ADR-0029's was — it is a slice of the production
  path, not a parallel one.
- Budget: not estimable — this is an investigative task whose footprint depends on what the first
  probe answers.

---

## Phase 3 — the attachment

## File map (from Budget: declarations, tasks 2-3)

- Sources/Features/Editor/EditorDecorationDelegate.swift
- Tests/ViewBlockRenderingTests.swift

No parseable Budget: for task(s): 3 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/superpowers/plans/2026-09-06-pg-099-views-board-renderer-orphaned-by.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/docs/adr/0033-views-render-live-in-the-editor.md -- delegate enumeration hook rules, table-copy shape (ADR §D1/§D2/§D4), and tracer-bullet gate scope (ADR §D16 probes 1-3)
- SPEC: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-plain-cameras-read-gxgvl/SPEC.md -- requirement IDs R-01, R-04, R-06 for this batch's tests
