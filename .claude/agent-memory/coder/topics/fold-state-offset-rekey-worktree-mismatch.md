---
name: fold-state-offset-rekey-worktree-mismatch
description: Task instructions named a worktree path (agent-a0ea07474da0a1c4d) that did not exist; the dispatch actually ran in a different worktree (agent-a368a375bee3fc0a7) whose HEAD matched the described state anyway
metadata:
  type: project
---

On 2026-09-05, a coder dispatch for the fold-state ordinal-index staleness fix
(`FoldStateOrdinalIndexStalenessTests.swift`, re-keying `NoteTab.foldedEntries` from
ordinal to UTF-16 offset) named worktree
`/Users/stefer/Developer/Pergamenum/.claude/worktrees/agent-a0ea07474da0a1c4d` in its
prompt, but that directory did not exist. The dispatch's actual cwd, and the only path
the worktree-git-guardrail permitted touching, was
`/Users/stefer/Developer/Pergamenum/.claude/worktrees/agent-a368a375bee3fc0a7` — whose
HEAD (`a6505f2 test(editor): pin fold-state ordinal-index staleness bug (red)`) matched
the task's described starting state exactly (the red test already committed, nothing
else pending).

**Why:** the orchestrator's dispatch prompt and the harness's actual worktree
assignment disagreed. Likely cause: the plan/manifest was authored referencing a
worktree name from an earlier planning pass that was since recreated under a new
suffix, and the prompt wasn't regenerated from the live assignment.

**How to apply:** when a dispatch names a worktree path, verify it against `pwd` before
trusting either — don't silently proceed on the named path if it doesn't exist, and
don't silently proceed on the actual cwd without flagging the mismatch either. Report
the discrepancy in the final summary even if the actual cwd's state happens to match
the task description well enough to proceed (as it did here); the orchestrator should
know its dispatch prompts and worktree assignments can drift apart so it can check
whether other in-flight dispatches from the same batch have the same issue.
