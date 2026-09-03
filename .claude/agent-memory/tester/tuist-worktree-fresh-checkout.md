---
name: tuist-worktree-fresh-checkout
description: A freshly dispatched Pergamenum worktree needs `tuist install` once before `tuist generate` works — generate alone fails with "could not find external dependencies".
metadata:
  type: project
---

Running `tuist generate --no-open` in a brand-new agent worktree (one that has never had
`Tuist/.build` populated) fails immediately:

```
✖ Error
  We could not find external dependencies. Run `tuist install` before you continue.
```

**Why:** `Tuist/Package.swift` declares SPM dependencies (MCP SDK, swift-nio, etc. —
CLAUDE.md's "New dependencies go through Tuist/Package.swift ... not through the Xcode
UI") that must be resolved and checked out per-worktree; a git worktree does not inherit
the sibling checkout's `Tuist/.build`.

**How to apply:** in a fresh worktree, always run `tuist install` (resolves/fetches into
`Tuist/.build/checkouts`, ~7 packages as of PG-018) before the first `tuist generate`.
Only needs doing once per worktree lifetime, not per `generate` call.

See also [[swift-testing-only-testing-gap]] for the next step after generate.
