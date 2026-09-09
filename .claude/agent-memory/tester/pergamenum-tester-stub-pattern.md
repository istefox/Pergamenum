---
name: pergamenum-tester-stub-pattern
description: How to keep Pergamenum's exhaustive Swift switches compiling when the tester declares a not-yet-implemented enum case or type, per ADR-0155 §D1 (tester owns interface, coder owns body).
metadata:
  type: project
---

Pergamenum's concept-to-code chain (ADR-0155 §D1) dispatches the tester *before* the
coder for a task group: the tester declares the interfaces the red tests need (new enum
cases, new type signatures, new function signatures) and the coder fills bodies. Swift is
compiled and this codebase leans hard on exhaustive `switch` (no `default`) as a
compile-time completeness check (`MarkdownStyler.suppressesSpellCheck`,
`MarkdownAttributedText.colorToken(for:)`, `CardTextAttributes.colorToken(for:)`,
`EditorDecorationDelegate.stillSpells(_:_:at:)` are all examples). Adding a case to an enum
these switch over **must** ship in the same tester commit as an arm for that switch, or
the whole target fails to build and produces zero red — not just zero for the new tests.

Two different moves, both legitimate, and the plan usually tells you which one a given
switch needs:

1. **Complete it for real**, when the plan says so explicitly (e.g. "update the three
   exhaustive tables the compiler names: `suppressesSpellCheck` — all four are syntax →
   `true`"). This is trivial, deterministic mapping the tester can just write; the
   resulting assertion (e.g. "suppressesSpellCheck answers true for each new case") will
   pass immediately, and that's fine — not every assertion needs to start red, only the
   ones that pin down the coder's actual deliverable.
2. **Stub it**, when the arm would require the *behavior under test* to already exist
   (e.g. `stillSpells(.blockquote, ...)` — implementing it for real would require the
   coder's own recogniser). Return the obviously-wrong-but-compiling value (`false`,
   `nil`, `[]`, `""`) with a comment naming which coder-owned function/branch will replace
   it. This is what keeps the *positive* assertions in the new tests genuinely red.

New source files that only exist to hold a stub (e.g. a new
`EditorDecorationDelegate+QuoteRendering.swift` with just
`func quoteParagraph(...) -> NSTextParagraph? { nil }`) are a normal and expected shape for
this repo's tester dispatches — they are the empty branch the coder's task explicitly says
to "fill in", not dead code.

**Verification step that matters**: after writing stubs, build the whole app target first
(`xcodebuild ... build`, no `-only-testing`) to confirm the *exhaustive-switch* edits
alone compile, before running the test target — isolates "did my interface change compile"
from "are my tests red for the right reason".

**A pure stub `static func` on an `@MainActor` class needs `nonisolated`, or a
plain top-level `@Test func` calling it fails to *compile* with "call to main
actor-isolated static method ... in a synchronous nonisolated context"** — not a red
assertion, a build error, easy to misread as "my test file is wrong" when it is really a
one-word fix on the declaration (`NoteTextView.Coordinator` is `@MainActor`; ADR-0030's
`horizontalInset(viewWidth:cap:minimum:isOn:)` needed `nonisolated static func`). Declare
`nonisolated` on any stub that takes only value types and touches no actor state, from the
start, rather than discovering it on the first build.

**A stub that always returns the same fallback value can still leave most of the brief's
"expect 24" cases *accidentally* passing** — only the cases where the correct answer
diverges from the stub's fixed return are genuinely red (readableWidth: the stub always
returned `minimum`/24, so only the `viewWidth 1200 → 240` case failed; the narrow-view,
boundary, `isOn: false`, zero and negative cases all correctly expect 24 too, so they
passed against the stub). This is expected, not a sign the tests are weak — report the
red/green split explicitly rather than assuming "all pass" or "all fail" is the only sane
outcome.

See also [[swift-testing-only-testing-gap]].

## Follow-up: widening an existing function's signature is also a valid tester-declared boundary

Closing a gap left by an earlier batch (e.g. a new `PraticaLedger.PraticaState` field the
coder still needs to *read*) doesn't always need a brand-new type. Adding a defaulted
parameter to an existing function (`PraticheController.readTimeline(praticaPath:vaultRoot:
notInStore: Set<String> = [])`) is the same "wrong-but-safe stub body" move as a new type,
just applied to a signature instead: every existing call site keeps compiling unchanged
(the default absorbs them), the new test can pass the real argument, and the body still
ignores it (hardcoded `isInMail: true`) so the assertion is genuinely red. Before doing
this, grep every call site of the function being widened (`grep -rn "functionName("
Sources/ Tests/`) to confirm the default truly preserves every one of them — this is what
makes it safe rather than a silent behavior change.

## Follow-up: adding an enum case ripples past its own file's exhaustive switches

Adding one case to a widely-consumed enum (`Navigation.Pane`, `ShortcutCommand`) doesn't
stop at that enum's own declared switches. Grep every `switch` over the enum type (or over
`.allCases`) repo-wide before declaring done — an exhaustive switch **with no `default`**
elsewhere in the app (found: `CommandActions+CanRun.swift`'s `canRun(_:)`, `RootView.swift`'s
`detail` switch) breaks the build, while one **with `default: assertionFailure(...)`**
(`CommandActions.swift`'s `runFile`/`runView`/etc.) only breaks at runtime the first time
that case is actually invoked — still worth filling in in the same edit, not left as a
future crash, per ADR-0155 §D1 (leave the target building AND behaving safely, not just
compiling).
