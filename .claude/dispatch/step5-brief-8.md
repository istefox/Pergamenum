<!-- step5-brief: plan=/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md tasks=8 lines=335-419 -->
# Step 5 Batch Brief -- 2026-09-08-word-grained-markdown-reveal-on-caret-in.md -- tasks 8-8

## Task text (verbatim, plan lines 335-419)

### Task 8 — full suite, UI suite, hand check, docs (R-07, R-10, R-11)

1. `tuist generate --no-open`, then the **full unit suite** through `.claude/test-cmd`. Green, and
   green with **no existing test edited** except the two helper signatures named in Task 3.
2. `scripts/uitests.sh` with no arguments, once, before any merge to `main` (CLAUDE.md's rule and
   its price). Kill stale instances first; read the per-test seconds before believing a red — 60.2 s
   names the launch timeout, not the app.
3. **R-11's hand check**, in a Debug build launched with `open -n` on a throwaway vault
   (`-recentVaults '("/path")'`, the plist array form), the newest build found with `ls -dt`:
   with the setting **off**, confirm today's behaviour; with it **on**, walk the caret through
   `**grassetto**`, `[[Nota]]`, `[[Nota reale|testo mostrato]]`, `[testo](https://esempio.it)`,
   `**bold con *corsivo* dentro**` and a two-run paragraph, in the note editor **and** in a
   Workspace `.text` card. Watch specifically for the two named costs (ADR Consequences): the wrap
   point moving as a span reveals, and the caret appearing not to move while crossing a collapsed
   delimiter. Write the result into `PROJECT_BRIEF.md` beside the milestone, the standard
   ADR-0018 §D6 set for a probe that no automated test can answer.
4. Update `CLAUDE.md`: a "Decisions from the word-grained reveal chain (ADR-0037)" section and an
   ADR-0037 line in the chain decision index.

- Budget: `CLAUDE.md`, `PROJECT_BRIEF.md` (~60 lines)

---

## Requirement coverage

| id | tasks |
|---|---|
| R-01 | 1, 2, 3, 5 |
| R-02 | 1, 2, 3, 5 |
| R-03 | 3, 5 |
| R-04 | 1, 2, 5 |
| R-05 | 1, 3 |
| R-06 | 3, 7 |
| R-07 | 3, 4, 5, 7, 8 |
| R-08 | 4 |
| R-09 | 6, 7 |
| R-10 | 1, 2, 3, 8 |
| R-11 | 8 |

Every id the SPEC declares is cited by at least one task; no id is cited that the SPEC does not
declare. The SPEC carries no `(no-test: …)` marker on any criterion; R-11 is a manual verification
by its own wording and is discharged by Task 8's written result, not by an assertion.

---

## Risks and HITL gates

- **The main checkout has uncommitted work in `EditorDecorationDelegate.swift`,
  `EditorDecorationDelegate+CheckboxRendering.swift` and a new `NoteTextView+CheckboxClick.swift`**
  (checkbox-click, in flight on `feature/task-note-board-link-navigation`). This chain rewrites the
  guard at `EditorDecorationDelegate.swift:443`. A textual conflict at merge time is likely and is
  not a defect — but **whoever merges second must re-read D3's filter against the other branch's
  edits**, not resolve by taking one side. Flag it at the merge gate.
- **Typing feel is the acceptance criterion and it has no test.** The wrap point moves more often
  than it did (ADR Consequences), and a reveal that makes the line jump is the failure mode a
  person will report as "it flickers". Only the Task 8 hand check can answer it; if it reads badly,
  the honest outcome is to ship the setting off and say so, not to tune the predicate under time
  pressure.
- **The CommonMark link pairing is the one piece of new grammar** (F2). Two links on one line is
  its real test and it is in Task 1's minimum list. A mispairing reveals the wrong construct or a
  range spanning two of them — visible immediately, but only if someone writes that line.
- **Performance is bounded by argument, not measured.** ADR §D4's case rests on a paragraph being
  one line and on ADR-0018's 5.83 ms/17 KB figure. A pathological single-paragraph note (a
  minified line of tens of KB) would parse that whole line on every arrow key. Unmeasured, named,
  and worth one glance during the hand check on a long note.
- **Phantom spans inside code fences** (ADR §D4). Harmless by construction — a span with no marker
  reveals nothing — but it is a genuine divergence between two parses of the same characters, and
  a future reader assuming they agree will be wrong. Task 1 should include one fenced-`**bold**`
  case documenting the no-op.
- **`VaultSettings` is a shared source** (F5). `SharedSourcesPurityTests` must stay green; if the
  new property ever grows an import, both command-line tool builds break, which is ADR-0001 §D1
  enforcing itself.
- **HITL gates:** commit, push, merge to `main`, and the R-11 hand check itself. No schema change,
  no migration, no deletion, no destructive command, no new dependency anywhere in this chain —
  `Tuist/Package.swift` is not touched.

---

EXTERNAL DEPENDENCY: tuist | binary | provisioned: true
EXTERNAL DEPENDENCY: xcodebuild | binary | provisioned: true

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/.build/DerivedData" -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: opus

## File map (from Budget: declarations, tasks 8-8)

- CLAUDE.md
- PROJECT_BRIEF.md

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 2 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 3 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 4 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 5 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 6 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md
- Task 7 -- see /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

Full plan: /Users/stefer/Developer/Pergamenum_worktrees/feature-word-grained-markdown-reveal/docs/superpowers/plans/2026-09-08-word-grained-markdown-reveal-on-caret-in.md

## Context documents (open only for the reason stated -- not read unconditionally)

- (none passed to this brief)
