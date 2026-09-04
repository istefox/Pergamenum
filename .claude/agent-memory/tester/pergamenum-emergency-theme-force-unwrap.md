---
name: pergamenum-emergency-theme-force-unwrap
description: Adding a new TokenKey case (FontToken/SpacingToken/etc.) in Pergamenum needs a placeholder entry in Theme.emergency too, or a red test crashes the whole xctest process instead of failing an assertion.
metadata:
  type: project
---

`Theme`'s lookups (`Theme.swift`) are `fonts[token] ?? Theme.emergency.fonts[token]!` - the
emergency side is force-unwrapped on the assumption that `Theme.emergency` defines every
`TokenKey` case that exists. Adding a new case to `FontToken`/`SpacingToken`/etc. (e.g.
`FontToken.prose`, `SpacingToken.readable`, ADR-0030 Task 1) does **not** fail to compile if
`Theme.emergency`'s dictionary literal omits it - dictionary literals aren't exhaustiveness-
checked the way `switch` is. It fails at *runtime*, with a `fatalError` from the force-unwrap,
the first time any code (including a tester's own new "does this token resolve" test) asks a
`Theme` for that token while the bundled theme JSON doesn't define it yet either.

**Why it matters more than an ordinary red assertion:** a crashed Swift Testing process takes
the *entire* `xcodebuild test` run down, not just the one test - indistinguishable from a build
failure until you read the log closely, and it destroys the "which of my new assertions are
red for the right reason" signal the whole tester dispatch exists to produce.

**How to apply:** whenever a task adds a new `TokenKey` case, add a placeholder entry for it to
`Theme.emergency`'s literal in the same commit - a value that is obviously not the real design
value (so the "resolves to the *correct* value" assertion still stays red), just present (so the
force-unwrap doesn't fire). Comment it `TESTER STUB` with a pointer to where the coder's real
value belongs. This is a compile/crash-safety edit, not an implementation of the feature, and is
owed even when the task brief says "do not touch `Theme.swift`" for behavioural reasons - see
[[pergamenum-tester-stub-pattern]] for the same reasoning applied to exhaustive `switch`es (the
two budgets overlap: a `Family` case addition needed both).

Adding new `TokenKey` cases also silently turns pre-existing tests red as collateral -
`ThemeEngine`-based tests (`engineLoadsWithoutProblems`, `unreadableUserThemeIsReportedNotFatal`
in `DesignSystemTests.swift`) load the real bundled JSON and will report the new tokens as
missing/inherited the moment the enum case exists, even though nobody touched those test
bodies. Expected, not a regression to chase down - report it as collateral red pending the same
coder task that adds the tokens to the theme JSON files.
