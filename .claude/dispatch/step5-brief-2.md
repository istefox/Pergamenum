<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=2 lines=155-189 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 2-2

## Task text (verbatim, plan lines 155-189)

### Task 2 — `MarkupReveal.inlineSpans`: the note-wide table, keyed by paragraph (R-01, R-02, R-04, R-10)

In `Sources/Features/Editor/NoteTextView+Reveal.swift`, beside the untouched
`MarkupReveal.paragraphs`:

```swift
static func inlineSpans(
    in text: String, selection: NSRange, markedRange: NSRange, currentMatch: NSRange?
) -> [Int: [NSRange]]
```

Same three triggers, same `NSNotFound` guard on `markedRange`, same out-of-bounds tolerance as
`add(_:of:to:)`. For each trigger range, walk the paragraphs it touches; for a paragraph
**entirely covered** by a non-empty trigger range, emit one span `NSRange(0, paragraph.length)`
and do not parse (ADR §D5); otherwise call `InlineSpanReveal.revealed` on that paragraph's
substring with the trigger range translated into paragraph-relative coordinates. Values are
paragraph-relative, keyed by paragraph-start offset — `hiddenMarkers`' key space.

**Tester** extends `Tests/MarkupRevealTests.swift` with a second suite and writes the signature
returning `[:]`. Red first. At minimum: a caret in the second paragraph keying only that
paragraph; a selection spanning two paragraphs keying both; a fully-covered middle paragraph
yielding exactly one whole-paragraph span with no parse-dependent content; the find-bar match as a
trigger (R-04's mechanism serving ADR-0018 §D2's fourth trigger); an IME `markedRange` as a
trigger; `NSNotFound` and past-the-end ranges yielding `[:]` and not crashing; and **the
invariant**: for a set of inputs, every key of `inlineSpans` is a member of `paragraphs` for the
same inputs (constraint 3 above — asserted again structurally in Task 7).

**Coder** fills the body.

- Budget: `Sources/Features/Editor/NoteTextView+Reveal.swift`, `Tests/MarkupRevealTests.swift` (~200 lines)

---

## Phase 2 — the delegate

## File map (from Budget: declarations, tasks 2-2)

- Sources/Features/Editor/NoteTextView+Reveal.swift
- Tests/MarkupRevealTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- trigger/paragraph semantics for the note-wide table (ADR §D5)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs R-01,R-02,R-04,R-10 for this task's tests
