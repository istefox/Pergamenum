# SPEC — PG-085: compute list nesting depth by CommonMark's content-column rule

**Topic slug:** pg-085-compute-list-nesting-depth-by-com

## Objectives

`MarkdownStyler`'s list-nesting classifier computes a line's level from its own indentation alone
(`level = min(1 + columns / 2, 6)`, one space = one column, one tab = four), independent of any
other line. This disagrees with CommonMark (and Obsidian) whenever a list's actual nesting depends
on a parent item's *content column* — the column where the parent's own text begins, which varies
with marker width (`- ` is 2 columns wide, `12. ` is 4). A list authored inside Pergamenum never
hits this, because Pergamenum's own list-continuation always emits indentation in multiples of the
fixed rule; the gap is only observable on a list pasted in from Obsidian or another editor using
CommonMark-correct indentation.

This chain replaces the fixed-column formula with a genuine CommonMark content-column algorithm,
shared as one pure function between the two places that compute it today.

ADR-0028 (`docs/adr/0028-wysiwyg-markdown-in-workspace.md`), Consequences/Negative, declared this
gap explicitly and declined to close it in that chain: *"The nesting rule is not CommonMark's
(§D1). A list indented three spaces, or one whose nesting depends on the parent's content column,
renders at a level this classifier computes from indentation alone and may disagree with what
Obsidian draws. Nothing is written to disk, so the disagreement is cosmetic and reversible."*

## Scope

**In scope:**
- A new pure, shared function computing CommonMark-correct nesting level from the whole document
  text and a target line's own range — a stack-based algorithm tracking each open list item's
  content column, not a per-line fixed-column formula.
- `MarkdownStyler.swift`'s `listMarkerSpan`/`listMarkerLength` (lines 458-498) call this shared
  function instead of computing `1 + columns/2` inline.
- `EditorDecorationDelegate+ListRendering.swift`'s `stillSpellsAListMarker` (lines 108-134) calls
  the same shared function, re-derived from live characters at layout time exactly as today — the
  no-caching invariant on `HiddenMarker.Kind.list` (documented at
  `EditorDecorationDelegate.swift:37-48` and `NoteTextView+Coordinator.swift` around the
  `hiddenMarker` factory) is preserved unchanged.
- CommonMark's tie-breaking rule: an item whose indentation does not exactly match any open list's
  content column attaches to the deepest open list whose content column is still ≤ the item's
  indentation.
- Tab handling unchanged (1 tab = 4 columns for indentation purposes — CommonMark's own rule,
  already correctly implemented) but folded into the new content-column comparison rather than the
  old fixed-division formula.
- The existing level cap of 6 is preserved — `ListMarkerRendering.paragraphStyle(level:font:)`
  already assumes `level ∈ 1...6`.
- `Tests/MarkdownStylerTests.swift:429-440` and `Tests/MarkupHidingTests.swift:235-241,331`
  rewritten to assert CommonMark-correct expectations (they currently assert the bug as correct
  behavior). New tests for the ticket's own scenarios: 3-space indents, and sibling items under
  ordered markers of different widths (`1. ` vs `12. `) producing different child thresholds.

**Out of scope:**
- `Sources/Core/Editor/ListContinuation.swift`'s own "level" grouping (raw indent-column count,
  used only for Enter-key continuation/renumbering of ordered runs) is architecturally separate
  from rendering depth and is **not touched** by this chain, unless implementation surfaces a
  concrete correctness bug there (not merely a naming/consistency observation).
- No change to `.canvas`/note file content, frontmatter, or index schema — this is a rendering
  fix only, matching ADR-0028's own "nothing is written to disk" framing.
- No change to `ListMarkerRendering.swift`'s glyph selection or paragraph-style geometry beyond
  what a corrected `level` value naturally produces.
- No manual hand-check — pure algorithm/rendering correctness fix, no new UI affordance, fully
  reachable through existing offscreen test infrastructure (`MarkupHidingTests` already drives the
  real `EditorDecorationDelegate` against a bare `NSTextContentStorage`).

## Stack

Swift 6, Foundation-only for the new shared algorithm (no AppKit/SwiftUI dependency — consistent
with `ListContinuation.swift`'s own precedent as a Foundation-only sibling type, and with
`Sources/Core/**`'s constraint of being compiled into both command-line tools with no UI framework
available, ADR-0001 §D1). Swift Testing for new/updated tests.

## Architecture

**New shared function**, in a new file `Sources/Core/Editor/ListNesting.swift` (Foundation-only,
alongside `ListContinuation.swift`, which already models list-run state in the same file family):

```swift
enum ListNesting {
    /// The CommonMark-correct nesting level of a list item, computed by walking the document
    /// text backward from `lineStart` to find every enclosing open list item's own content
    /// column, and comparing this item's indentation against that stack.
    static func level(in text: String, lineStart: String.Index, indent: Int) -> Int
}
```

Both existing call sites invoke this identically, from live characters, at their own separate
times — no caching, no shared mutable state across calls, matching the existing "recompute from
characters, never carry a stale value" invariant:

- `MarkdownStyler.listMarkerSpan` (styling pass, walks `text` — the whole note) calls
  `ListNesting.level(in:lineStart:indent:)` instead of `min(1 + columns / 2, 6)`.
- `EditorDecorationDelegate+ListRendering.stillSpellsAListMarker` (layout-time re-read, already
  receives `storage.string as NSString` — the whole document, not just the current paragraph)
  calls the same function via a thin `String`-bridging call, instead of restating the fixed-column
  formula inline.

**Algorithm** (CommonMark's list-nesting rule, §5.2/§5.3 of the CommonMark spec, restated for this
codebase's single-pass indentation-based grammar rather than a full block-parser):

1. Walk backward from `lineStart` line by line, collecting the run of preceding list-item lines
   that could be this line's ancestors — stop at the first blank line or first non-indented,
   non-list line that closes every open list (a paragraph at column 0 with no list marker).
2. For each collected ancestor line (in document order), compute its own *content column*: its
   indentation width, plus its marker width (`"- "` → 2, `"1. "` → 3, `"12. "` → 4, etc.), i.e.
   the column immediately after the marker and its one mandatory trailing space — this is where a
   CommonMark-conformant child's own indentation must reach or exceed to nest under it.
3. Maintain a stack of open content columns as the walk proceeds forward through the collected
   ancestors: an ancestor whose own indentation is `<` the current stack top's content column pops
   the stack (it closes that list and every deeper one) before its own content column is pushed.
4. The target line's level is `1 +` the number of stack entries whose content column is `≤` the
   target line's own indentation (CommonMark's tie-break: attach to the deepest list whose content
   column still fits), capped at 6.
5. Tabs count as 4 columns for both indentation and content-column arithmetic, matching today's
   behavior (unchanged, confirmed CommonMark-correct).

This is a bounded backward walk (stops at the nearest list-closing boundary, not the whole
document), acceptable given `spans(in:)` and the layout re-read already run a comparable per-line
walk on every keystroke (ADR-0028 §D-Negative already documents "every keystroke... runs one more
full-text pass").

**No change to `Span.listMarker`'s shape** (`kind:` and `level:` fields, `MarkdownStyler.swift:63-
69`) — only how `level` is computed. No change to `ListItem`'s shape
(`EditorDecorationDelegate+ListRendering.swift`) for the same reason.

## Data model

No new persisted data. `ListNesting.level(in:lineStart:indent:)` is a pure function over
`String`/`String.Index` values already in scope at both call sites — no new stored type, no new
`.canvas`/frontmatter key.

## API

Internal only — `ListNesting` is not exposed to `perg`/`pergamenum-mcp` (no connector surface for
markdown rendering internals) and carries no public API of its own beyond the one static function
above, callable from both `Sources/Features/Editor/` and `Sources/Features/Workspace/` (both
already depend on `Sources/Core/Editor/` today via `ListContinuation`).

## UI flows

None — no new UI affordance. Existing rendering (note editor and Workspace `.text` card) is
unchanged in every case except where today's fixed-column classifier and CommonMark's
content-column rule disagree, where the displayed nesting level now matches CommonMark/Obsidian.

## Edge cases

- **Tabs**: 1 tab = 4 columns, unchanged (already CommonMark-correct) — folded into the new
  content-column comparison.
- **Tie-breaking**: an item's indentation between two valid content columns attaches to the
  deepest open list whose content column is still ≤ its own indentation (CommonMark's rule) —
  this is what fixes the ticket's named 3-space-indent scenario.
- **Level cap**: preserved at 6, matching `ListMarkerRendering.paragraphStyle`'s existing
  `level ∈ 1...6` assumption.
- **Ordered markers of different widths** (`1. ` vs `12. `): the content-column algorithm
  naturally produces different child thresholds for these, where the old `1 + columns/2` formula
  did not distinguish marker width at all.
- **A list authored entirely inside Pergamenum**: unaffected — Pergamenum's own
  `ListContinuation`-driven indentation already happens to agree with both the old and new rule
  for content produced by this app's own Enter-key continuation (not verified by a new test in
  this chain, since it is a pre-existing, already-covered path; any regression here would show up
  in the existing `ListContinuationTests.swift` suite, which is untouched).
- **A malformed/ambiguous backward walk** (e.g. a line whose ancestor chain cannot be resolved,
  or that sits at column 0 with no marker of its own): falls through to level 1, the same
  behavior a non-nested list item gets today.

## Success criteria

- [ ] R-01 — `ListNesting.level(in:lineStart:indent:)` exists in `Sources/Core/Editor/ListNesting.swift`, Foundation-only, and implements the CommonMark content-column stack algorithm described above.
- [ ] R-02 — `MarkdownStyler.listMarkerSpan` calls `ListNesting.level` instead of the inline `1 + columns / 2` formula; `listMarkerLength`'s grammar (marker detection itself) is unchanged.
- [ ] R-03 — `EditorDecorationDelegate+ListRendering.stillSpellsAListMarker` calls the same `ListNesting.level` function against live characters at layout time, preserving the existing no-caching invariant on `HiddenMarker.Kind.list` (§D-architecture above).
- [ ] R-04 — A list item indented 3 spaces under a `- ` (2-column-wide) parent renders at level 2 (CommonMark: content column 2, indent 3 ≥ 2 → nests).
- [ ] R-05 — A list item indented 3 spaces under a `12. ` (4-column-wide) parent renders at level 1, not level 2 (CommonMark: content column 4, indent 3 < 4 → does not nest, stays a sibling of the ordered item's own list).
- [ ] R-06 — CommonMark's tie-break rule is exercised by at least one test: an indentation that falls strictly between two open lists' content columns attaches to the deeper one.
- [ ] R-07 — The level cap of 6 is preserved for indentation deep enough to mathematically exceed it.
- [ ] R-08 — `Tests/MarkdownStylerTests.swift:429-440`'s existing assertions are rewritten to assert CommonMark-correct expected levels for the same inputs (2 spaces, 4 spaces, one tab, 20 spaces), not the old fixed-column values.
- [ ] R-09 — `Tests/MarkupHidingTests.swift:235-241,331`'s existing nesting-level assertions against the live `EditorDecorationDelegate` are rewritten to match, confirming the layout-time re-read agrees with the styling-pass computation for the same input.
- [ ] R-10 — A list authored inside Pergamenum via the existing Enter-key continuation (`ListContinuation`) still renders at the same levels it did before this chain — no regression in `Tests/ListContinuationTests.swift` (no-test: ListContinuation.swift itself is explicitly out of scope and untouched by this chain, so this is a non-regression check on an unmodified suite, not a new assertion this chain writes).
- [ ] R-11 — `Sources/Core/Editor/ListContinuation.swift` is not modified by this chain (no-test: a scope boundary confirmed by the diff at commit time, not a runtime behavior a unit test can assert).
- [ ] R-12 — `xcodebuild` build succeeds for all three schemes (`Pergamenum`, `perg`, `pergamenum-mcp`) with the new `Sources/Core/Editor/ListNesting.swift` file added to `sharedSources` if it needs to be reachable from the connectors (verify against `Project.swift`'s existing glob for `Sources/Core/**`).
