---
name: tuist-install-before-generate-in-agent-worktrees
description: In a fresh agent worktree, `tuist generate` fails until `tuist install` has run once — CLAUDE.md's Commands section lists only generate.
metadata:
  type: project
---

A parallel-agent worktree of this repo starts without `Tuist/.build`, so the very first
`tuist generate --no-open` aborts with "We could not find external dependencies. Run
`tuist install` before you continue." Run `tuist install` first, once, then generate;
there is no `.xcworkspace` in the worktree before that, so `xcodebuild -workspace
Pergamenum.xcworkspace ...` cannot run either.

**Why:** CLAUDE.md's Commands section documents `tuist generate` alone, because in the
main checkout the dependency cache already exists. A worktree forked from HEAD carries
the tracked manifests but not the untracked `Tuist/.build` checkouts.

**How to apply:** any coder/tester dispatch that has to build or run the suite in a fresh
worktree budgets one `tuist install` before the first `tuist generate --no-open`. It is a
restore from `~/.cache/swifterpm`, seconds rather than a network fetch.
