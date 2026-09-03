---
name: waiting-on-long-xcodebuild-runs
description: A pgrep -f wait-loop for an xcodebuild run self-matches its own shell and never exits; this repo's 20-minute UI suite makes that trap routine.
metadata:
  type: project
---

Do not wait for a long `xcodebuild` run with `until ! pgrep -f "<some xcodebuild flag>"; do
sleep N; done`. The waiting shell's own command line contains the pattern, so `pgrep` matches
itself, the loop never terminates, and it survives the run it was waiting on as an orphan
background process. Wait by polling the run's log file (or by letting the background-task
completion notification arrive) instead.

**Why:** measured on 2026-09-03 while running `scripts/uitests.sh` for the ADR-0029 chain. The
full UI suite executed 105 tests in 1237 s (~21 minutes), well past the Bash tool's 2-minute
foreground kill, so the run had to go to the background and be waited on. Two such wait-loops
were created and both had to be killed by hand afterwards.

**How to apply:** in this repo specifically, because the long-run case is routine here rather
than exceptional — the UI suite is deliberately kept out of `.claude/test-cmd` and run
separately, so any coder touching UI-visible code ends up waiting on a background run of it.
The unit suite is fast by comparison (~2000+ tests in well under a minute) and needs none of
this.

Related: [[uitests-full-suite-gate]]
