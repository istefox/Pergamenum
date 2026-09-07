---
name: only-testing-selects-suite-names-not-file-names
description: `-only-testing:PergamenumTests/<FileName>` silently runs nothing for a Swift Testing file - the selector matches `@Suite` type names, and the run still reports TEST SUCCEEDED.
metadata:
  type: project
---

`xcodebuild ... -only-testing:PergamenumTests/ViewBlockRenderingTests` ran **four** tests and
printed `** TEST SUCCEEDED **`, while the file `Tests/ViewBlockRenderingTests.swift` holds six
suites and none of them ran. The four that did run came from a *different* file
(`Tests/ViewBlockHostStoreTests.swift`), whose `@Suite struct` happens to be named
`ViewBlockHostStoreTests` - the only case where the file name and a suite name coincide.

**Why:** the selector's path component is a *type* name, and this repo's Swift Testing files
name their suites after the behaviour under test (`ViewBlockLineHiding`,
`ViewBlockAttachmentSubstitution`, `ViewBlockCaretRescue`, …), never after the file. A file
name that matches nothing is not an error: the selection is empty, the run is green, and the
exit code is 0. Measured 2026-09-07 during PG-099 Tasks 2/5.

**How to apply:** never take a narrow `-only-testing:` run as evidence a named test went green -
check the per-suite `✔ Suite <name> passed` lines and the `Test run with N tests` total against
what the file actually declares. To target a file's tests, pass each `@Suite` name
(`grep -n "@Suite" Tests/<File>.swift`), or run the whole `-only-testing:PergamenumTests` suite
once and grep its log for the suite names - which is what this repo's per-task verification
needs anyway (~2315 tests, ~12 s of testing after the build).

Related: [[pg-099-task4-test-cmd-invocation-refused]], [[waiting-on-long-xcodebuild-runs]]
