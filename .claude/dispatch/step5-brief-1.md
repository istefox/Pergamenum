<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=1 lines=121-154 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 1-1

## Task text (verbatim, plan lines 121-154)

### Task 1 — `InlineSpanReveal`: what a construct is, and which one the caret is in (R-01, R-02, R-04, R-05, R-10)

New file `Sources/Features/Editor/InlineSpanReveal.swift`, an `enum` namespace with no state and
two static functions, both taking a plain `String` paragraph:

```swift
static func constructs(inParagraph paragraph: String) -> [NSRange]
static func revealed(inParagraph paragraph: String, touchedBy range: NSRange) -> [NSRange]
```

- `constructs` runs `MarkdownStyler.spans(in: paragraph)` and keeps, converted to UTF-16
  `NSRange` with `NSRange(_:in:)`: every `.bold`/`.italic`/`.strikethrough` range as-is; every
  `.linkSyntax` range whose text starts with `[[` as-is; and each `.linkSyntax` range that is
  exactly `[`, joined to the **next** `.linkSyntax` range starting with `](` (F2). Sorted by
  location. Duplicates removed.
- `revealed` applies ADR §D5: for `range.length == 0`, the containing spans are those with
  `s ≤ p ≤ NSMaxRange(span)` (**closed** interval — the SPEC's adjacency edge case) and only those
  of minimum length are returned, ties included; for `range.length > 0`, every span with
  `NSIntersectionRange(span, range).length > 0` is returned, with **no** innermost filtering.

**Tester** writes `Tests/InlineSpanRevealTests.swift` plus both signatures returning `[]`. Red
first. At minimum: `**grassetto**` alone; two bold runs in one line with the caret in the first
(the R-01 multi-span case); `~~barrato~~`; `[[Nota]]`; `[[Nota reale|testo mostrato]]`;
`[testo](https://x.y)` reconstructed whole; **two CommonMark links on one line** revealing only
the one touched (the pairing's real test); `**bold con *italic* dentro**` with the caret in the
inner run returning the inner range only, and with the caret in `bold con ` returning the outer
only (R-05); a caret exactly at the first `*` and exactly after the last `*` both revealing
(adjacency); a selection across two runs returning both (R-04); a line with no construct returning
`[]`; an out-of-bounds and an `NSNotFound` range returning `[]` without crashing.

**Coder** fills both bodies. No `MarkdownStyler` edit.

- Budget: `Sources/Features/Editor/InlineSpanReveal.swift`, `Tests/InlineSpanRevealTests.swift` (~300 lines)

## File map (from Budget: declarations, tasks 1-1)

- Sources/Features/Editor/InlineSpanReveal.swift
- Tests/InlineSpanRevealTests.swift

## Excluded tasks (not in this batch)

- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- construct/span semantics (ADR §D2, §D4, §D5)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs R-01,R-02,R-04,R-05,R-10 for this task's tests
