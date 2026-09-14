<!-- step5-brief-followup: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=1,2,3 (test-conversion follow-up) -->
# Step 5 Batch 1 Follow-up -- convert existing tests to await the now-async writers

## Why this dispatch exists

Batch 1 (Tasks 1-3, ADR-0043 §D2) is otherwise complete: the coder converted the mechanical async
cascade (VaultSession's task/time-block/diary/note/event/tag/board/sample-view/file-operation/
journal writers, the VaultController facades, both connectors, and the SwiftUI call sites) and all
three production targets (Pergamenum, perg, pergamenum-mcp) build cleanly. The original per-task
brief's own "Tests the tester converts in this task" lists were never executed in the first tester
pass — only the new file `Tests/VaultAsyncCascadeTests.swift` was added. This dispatch is exactly
that missing sub-step, isolated so the coder (who is denied test-file edits) never had to touch it.

**Scope is mechanical only: add `await` at call sites that now call an async function, matching the
exact production signature. No assertion is added, removed, weakened, or reordered. No new test is
written. No production file is touched — `test-write-scope.sh`/`coder`-side denial does not apply to
you, but a change outside `Tests/` is still out of scope for this dispatch.**

## Files needing conversion (all under `Tests/`)

Per the original per-task lists in the plan and the coder's own compile-error inventory
(`build-for-testing` with `CONTINUE_BUILDING_AFTER_ERRORS=YES SWIFT_COMPILATION_MODE=wholemodule`),
these files fail to compile because they call now-`async` VaultSession/VaultController/connector
functions without `await`, or construct now-`async` closures/overloads incorrectly:

- `Tests/VaultAsyncCascadeTests.swift` — **only 3 spots**, do not touch anything else in this file:
  - Around line 96-98: the `cascadeAsync({ (blocks: [TimeBlock], day: CalendarDate) in
    session.setTimeBlocks(blocks, on: day) })` closure. `setTimeBlocks` is now `async`, so this
    sync closure no longer compiles. Since production is now genuinely async, this test no longer
    needs the sync/async signature-guard trick for this call — call the async overload directly:
    `let setBlocks = try cascadeAsync({ (blocks: [TimeBlock], day: CalendarDate) async in
    await session.setTimeBlocks(blocks, on: day) })`. Preserve every existing assertion below it.
  - Around line 133-135 and 150-152: the two `cascadeAsync({ (title: String, folder: String, date:
    CalendarDate, category: NoteCategory, topics: [Pergamenum.Tag], body: String) in try
    session.createNote(...) })` closures. `createNote` is now `async throws`. Make the closure
    `async` and `await` the call, same pattern as above. Preserve every existing assertion.
- `VaultSessionJournalTests.swift`, `VaultMoveTests.swift`, `VaultSessionFileOperationsTests.swift`,
  `VaultSessionTests.swift`, `ConnectorTests.swift`, `CaptureTests.swift`, `TaskDropTests.swift`,
  `BoardDropTests.swift`, `TagRenameTests.swift`, `VaultTests.swift`, `NoteHistoryTests.swift`,
  `VaultBoundaryCallSiteTests.swift`, `StarredTests.swift`, `EventNoteTests.swift`,
  `ViewConnectorTests.swift`, `VaultBatchMoveTests.swift`, `RecordingsControllerTests.swift`,
  `NoteTemplateTests.swift`, `GuardrailTests.swift`, `TaskMarkerWriteTests.swift`,
  `TaskMarkerLintTests.swift`, `TaskComposerTests.swift`, `NoteTabTests.swift`,
  `NoteTabGestureTests.swift`, `DossierWriterTests.swift`, `TaskTests.swift`, `URLSchemeTests.swift`,
  `CapturePanelTests.swift`, `RelatedLinkTests.swift`.
- `Tests/VaultWriteOrderingTests.swift:104-120` — currently asserts the async write is "a stub with
  no suspension point of its own (`try writeSynchronously(text, to: relativePath)`)".
  `writeSynchronously` has been deleted (Task 3 step 8, ADR-0043 §D2). Update this test to match
  the write door's real current shape — the single `func write(_ text: String, to relativePath:
  String) async throws` in `Sources/Vault/VaultSession.swift`. Do not weaken what the test is
  checking (that the write actually suspends / goes through the actor); adapt the mechanism the
  test uses to observe that, if the old stub-detection approach no longer applies.
- `Tests/VaultPlanApplicationTests.swift` — leave untouched (ADR-0043 §D3 protects it; the coder
  added an async overload beside the existing sync one, so the sync-facing tests here should
  already still compile against the untouched sync path — confirm this and do not edit unless the
  build actually shows an error here).

## How to find every remaining call site

Do not trust the list above as exhaustive — it is the coder's own inventory from one
`build-for-testing` pass and may miss something. After making the listed edits, run a full
`build-for-testing` (see command below) and fix any newly-surfaced call site the same way: add
`await`, and if the enclosing test function is not already `async`, mark it `async throws` (Swift
Testing `@Test` functions may freely be `async`).

## Verification

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -only-testing:PergamenumTests build-for-testing
```
Iterate until this builds clean, then run:
```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -only-testing:PergamenumTests test
```
**Done when:** the full `PergamenumTests` target builds and the suite runs to completion. Every
test that passed before this batch's async cascade (the ~2965 not touched by this change) must
still pass. The 9 new `VaultAsyncCascadeTests` assertions are expected to now be genuinely GREEN
(the production functions are now really async — this is the batch's success signal, not a
regression to explain away). Report the final pass/fail counts and name any test that is still red
and why (e.g., a genuine behavior question for the orchestrator, not something to paper over).

## Guardrails

- Do not touch any file under `Sources/`.
- Do not weaken, delete, or comment out an assertion to make a test pass. If a test's expectation
  looks wrong given the new async behavior, report it — do not silently change what it asserts.
- Commit is not your job; the orchestrator merges your worktree back.
