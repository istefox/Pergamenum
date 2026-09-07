---
name: pg-099-task4-test-cmd-invocation-refused
description: A worktree-isolated dispatch cannot run the suite via `bash .claude/test-cmd`; the isolation guardrail refuses the construct, so issue the xcodebuild command CLAUDE.md documents instead.
metadata:
  type: project
---

Running the project suite as `bash .claude/test-cmd > log 2>&1` from an isolated agent worktree
is refused by the worktree-git guardrail: "this command runs bash inside a construct too complex
to verify; what it reads or is handed as shell text cannot be shown not to run git". The refusal
names the fix itself - "split it into plain, separate commands". The equivalent plain command is
the one CLAUDE.md's Commands section already documents, with the `-only-testing:PergamenumTests`
restriction CLAUDE.md's working agreements also state:

    xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum \
      -destination 'platform=macOS' \
      -derivedDataPath /Users/stefer/Developer/Pergamenum/.build/DerivedData \
      -only-testing:PergamenumTests test

**Why:** measured on 2026-09-07 during PG-099 Task 4. The guardrail cannot inspect what an
indirect `bash <file>` will execute, so it blocks the whole call rather than the git part it
cares about. This matters here because the coder contract also forbids *reading* `.claude/test-cmd`
(orchestrator-managed, HITL gate), so the flags have to come from CLAUDE.md, not from the file.

**How to apply:** in any worktree-isolated dispatch in this repo that has to run the unit suite -
write the xcodebuild invocation out directly, in the background with a scratchpad log, rather than
shelling out to the test-cmd file. Do not read the file to recover the flags.

Related: [[waiting-on-long-xcodebuild-runs]], [[tuist-install-before-generate-in-agent-worktrees]]
