<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=3 lines=190-237 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 3-3

## Task text (verbatim, plan lines 190-237)

### Task 3 — the per-marker filter, and the two new inputs (R-01, R-02, R-03, R-05, R-06, R-07, R-10)

In `Sources/Features/Editor/EditorDecorationDelegate.swift`:

- `HiddenMarker.Kind.isInline` — a computed `Bool`, `switch` with **no `default`**, `true` for
  `.emphasis`/`.strikethrough`/`.link` and `false` for the other eight (ADR §D2).
- `nonisolated(unsafe) private var revealedSpans: [Int: [NSRange]] = [:]` and
  `func apply(revealedSpans:) -> Set<Int>` returning the symmetric difference of the **keys**, the
  shape `apply(revealedParagraphs:)` has, so the caller invalidates two paragraphs and not a
  document. No logging (this runs on every arrow key).
- `nonisolated(unsafe) var revealsInlineSpans = false` and a guarded
  `func apply(revealsInlineSpans:)`. **`apply(hiddenMarkers:hidingMarkup:)` is not touched.**
- `static func collapsing(among:paragraphIsRevealed:revealedSpans:) -> [HiddenMarker]` — ADR §D3's
  table, `nil` spans meaning the setting is off.
- The hook's last guard rewritten to call it, and `linkTooltips` fed the **collapsed** set rather
  than the survivors. `guard !collapsing.isEmpty else { return nil }` keeps the empty case
  returning `nil` exactly as today.

**Tester** extends `Tests/MarkupHidingTests.swift` with a new `@Suite` (the existing
`displayedParagraph`/`substitutedParagraph` helpers gain a defaulted `spans:`/`revealsInlineSpans:`
parameter rather than being replaced) and writes the declarations. Red first. At minimum:

- setting **off** + revealed paragraph → hook returns `nil` (R-07, and
  `theHookReturnsNilForARevealedParagraph` stays green **unedited**);
- setting **on** + revealed paragraph + one bold span revealed + a second bold span in the same
  paragraph → exactly the second span's two markers carry `collapsedFont`, the first's do not
  (R-01);
- the same for a `.link` marker pair (R-02);
- caret moved out (empty span table, paragraph still revealed) → every inline marker collapsed
  again (R-03);
- nested: outer + inner markers present, inner span revealed → outer's two collapsed, inner's two
  not (R-05);
- **R-06 by kind**: a paragraph carrying a `.heading` marker and a bold run, revealed, setting on
  → the heading marker is **not** collapsed (paragraph rule) while the bold markers are; a `.rule`
  marker is likewise governed by the paragraph;
- `isInline` answers `false` for all eight block kinds (a compile-checked exhaustive switch plus
  one assertion per kind);
- `apply(revealedSpans:)` returns the changed keys and `[:]` twice returns nothing.

**Coder** fills the bodies. **The list, checkbox, blockquote, table, view-block and embed branches
are not edited** (F4, F7) — if one looks like it needs to be, stop and report.

- Budget: `Sources/Features/Editor/EditorDecorationDelegate.swift`, `Tests/MarkupHidingTests.swift` (~260 lines)

---

## Phase 3 — the setting and the two surfaces

## File map (from Budget: declarations, tasks 3-3)

- Sources/Features/Editor/EditorDecorationDelegate.swift
- Tests/MarkupHidingTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- construct/span semantics + delegate filter (ADR §D2-D5)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs for this task's tests
