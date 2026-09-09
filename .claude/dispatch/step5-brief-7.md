<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=7 lines=313-334 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 7-7

## Task text (verbatim, plan lines 313-334)

### Task 7 — the out-of-scope fence and the invariant (R-06, R-09)

No production code unless a fence fails. A new `Tests/InlineSpanRevealFenceTests.swift`:

- **The invariant** (constraint 3): over a table-driven set of notes and selections, every key of
  `MarkupReveal.inlineSpans` is a member of `MarkupReveal.paragraphs` for the same inputs. This is
  what licenses leaving the list/checkbox/blockquote branches untouched.
- **R-06 by construct, end to end**: a note holding a heading, a bulleted list item, a checkbox
  line, a blockquote, a GFM table and a `pergamenum-view` fence renders identically with the flag
  on and with it off, at the same caret position — same substituted-paragraph lengths, same
  `collapsedFont` ranges, same hidden-line sets.
- **R-07 as a whole-file property**: with the flag off, the delegate's answers for a corpus of
  paragraphs are equal to the answers of a delegate that has never heard of the span table.
- **R-09's boundary** (F1): grep-shaped assertion that `CardTextView`'s switch still maps exactly
  five kinds.
- **Out-of-scope diff fence**: `MarkdownStyler.swift`, the five `EditorDecorationDelegate+*Rendering.swift`
  files, `NoteTextView+EmbedCaret.swift`, `MarkdownBlocksView.swift`, `NoteExporter.swift` and
  everything under `Sources/Core`/`Sources/Connector`/`Sources/CLI`/`Sources/MCPServer` do not
  appear in `git diff --stat` for this chain. Report, do not edit, if one does.

- Budget: `Tests/InlineSpanRevealFenceTests.swift` (~180 lines)

## File map (from Budget: declarations, tasks 7-7)

- Tests/InlineSpanRevealFenceTests.swift

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 8 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/adr/0037-word-grained-markdown-reveal-on-caret-in.md -- invariants and scope fences (ADR full)
- SPEC: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/SPEC.md -- requirement IDs for this task's tests
