<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md tasks=7,8 lines=341-389 -->
# Step 5 Batch Brief -- 2026-09-02-editor-wysiwyg-unification.md -- tasks 7-8

## Task text (verbatim, plan lines 341-389)

### Task 7 — the Diario pane hosts the same editor and nothing beside it (R-11)

- Budget: `Sources/Features/Diary/DiaryView.swift`, `Sources/Features/Diary/DiaryController.swift`,
  `Sources/Features/Diary/DiaryToolbar.swift`, `Tests/DiaryControllerTests.swift`,
  `UITests/DiaryUITests.swift` (~180 lines)

Remove `DiaryController.Layout` and `layout`, the toolbar picker (`:47-55`), `DiaryView.preview` and
the `body(for:)` switch; `writingColumn` becomes header, divider, editor. Grep `diary-layout` and
`diary-preview` in `UITests/` **first** and re-point every hit at `diary-editor`. Rewrite
`DiaryView.swift:7-13`, which states ADR-0005 §D2's superseded premise verbatim.

Two things stay exactly as they are: `DiaryTimeline` and everything in ADR-0005 §D3–§D8, and the
600 ms debounce plus the four flush triggers (§D7) — `growToFitTheText`'s own comment records that
the diary is where a re-entrant SwiftUI update once cost everything typed into it
(`NoteTextView+Coordinator.swift:370-376`). Do not touch that path while removing a sibling view.

### Task 8 — the documents, and the UI suite (R-12, R-13, R-14, R-15)

- Budget: `docs/20260811_Pergamenum_SpecApp.md`, `PROJECT_BRIEF.md`, `CLAUDE.md`,
  `docs/adr/0029-editor-wysiwyg-unification.md` (~120 lines)

- **`docs/20260811_Pergamenum_SpecApp.md` §14**: retire the *«Live preview completa | Esclusa v1 |
  Voce di costo massima; source mode con stile è sufficiente»* row, citing ADR-0029. **§5**: remove
  the two-mode description and its closing note flagging this chain as in progress (R-15). *This is
  the only task that edits that file; nothing earlier may.*
- Confirm the ADR states its supersessions explicitly (R-14) — it does, in its header; this task is
  the check, not a rewrite.
- Add ADR-0029 to `CLAUDE.md`'s **Chain decision index** and a "Decisions from the editor WYSIWYG
  unification chain" section, matching the eight already there.
- Update `PROJECT_BRIEF.md` with the four probe results from D16.
- **Run `scripts/uitests.sh` with no arguments** (R-13). An argument *replaces* the selection rather
  than adding to it. Kill stale instances first and read the per-test seconds before believing a red
  run — 60.2 s names the launch timeout, not a defect (CLAUDE.md).

---

## TEST-CMD CANDIDATE

```
TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
```

The UI suite is deliberately **not** in this command (CLAUDE.md: it runs at the end of every turn
through the `Stop` hook, and the UI tests terminate the app the person at the keyboard is using).
`scripts/uitests.sh` runs once, in Task 8.

No external dependency: this feature calls no third-party API, no cloud console and no consent flow.
Nothing to declare.

## File map (from Budget: declarations, tasks 7-8)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 7 8 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md

Full plan: /Users/stefer/Developer/Pergamenum/docs/superpowers/plans/2026-09-02-editor-wysiwyg-unification.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0029-editor-wysiwyg-unification.md -- Diario pane single-editor hosting decisions and D14 dead-code retention rationale
- SPEC: SPEC.md -- requirement IDs for this batch's tests
- CLAUDE.md: CLAUDE.md -- editor WYSIWYG conventions, UI-test working agreements, uitests.sh gate
