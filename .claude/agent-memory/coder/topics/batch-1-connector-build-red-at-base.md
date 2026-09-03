---
name: connector-build-red-at-base
description: perg and pergamenum-mcp fail to build on this branch for a pre-existing sharedSources gap, not because of current work
metadata:
  type: project
---

As of 2026-09-03, on `docs/pg-089-close-wont-fix` (base `88caaa0`), `xcodebuild -scheme perg`
and `-scheme pergamenum-mcp` both **fail** with `value of type 'IndexSnapshot' has no member
'tagUsage'` / `requires that 'IndexSnapshot' conform to 'ViewCorpus'`. The app target and the
whole unit suite are green.

**Why:** commit `b2659db` ("refactor(app): split … IndexSnapshot … into extension files")
created `Sources/Index/IndexSnapshot+Search.swift`, which is where `tagUsage` and the
`ViewCorpus` conformance now live. `Project.swift`'s `sharedSources` still names only
`Sources/Index/IndexSnapshot.swift` file-by-file (that directory is *not* a `**` glob, unlike
`Sources/Core/**`), so the connectors compile half of `IndexSnapshot`. Nothing to do with
markdown, the editor, or ADR-0029.

**How to apply:** if a connector build is red while working in this repo, check
`sharedSources` in `Project.swift` for a file added by a recent split *before* suspecting your
own change. The one-line fix is adding `"Sources/Index/IndexSnapshot+Search.swift"` to that
list — deliberately left undone here because it is unrelated breakage outside the dispatched
task. Verify with `xcodebuild -scheme perg …` before trusting this note; it is a bug report,
not a standing property.
