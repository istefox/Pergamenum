<!-- step5-brief-followup2: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=1,2,3 (fire-and-forget-race follow-up) -->
# Step 5 Batch 1 Follow-up #2 -- deterministic tests for fire-and-forget async handlers

## Why this dispatch exists

The previous follow-up converted ~30 test files to `await` the now-async VaultSession/
VaultController writers, and that suite mostly passes. But four test files still fail — not from
a missed `await`, but because several SwiftUI-facing/AppKit-facing call sites the coder converted
in Task 1-3 cannot themselves be made `async` (a synchronous SwiftUI action, and `NSUndoManager`'s
`registerUndo`/`undo()`/`redo()` API, which is fundamentally callback-based). The coder's own
design decision there (documented in `VaultController+Move.swift:62-64` and
`DiaryController.swift:113-114`, `DayController.swift:151-152,264-265`) was to kick off the real
write in a detached, un-awaited `Task { @MainActor in ... }` from inside the synchronous handler.
That is a legitimate production design for a fire-and-forget UI action, but it means a test that
calls the handler and immediately inspects disk/state now races the write.

**Failing tests, all from this exact race** (confirmed by reading the production call sites, not
guessed):
- `Tests/DiaryControllerTests.swift` — calls into `DiaryController.flush()`/`add()`/etc., which
  call the private `save()`, which spawns an un-tracked `Task { @MainActor in await
  vault.writeDiary(...) }` (`DiaryController.swift:115`). Failing: `writesANewEntryIntoTheDayFile`,
  `writesTheProseOnceTypingStops`, `readsBackWhatItWrote`, `writesTheDayBeforeLeavingIt`,
  `writesWhatIsOwedBeforeRereadingTheSameDay`, `movesAndResizesAnEntryAndWritesBothToTheFile`,
  `keepsABlockOfThreeHours` (if present), `deletingTheLastEntryLeavesTheProseAlone`,
  `drawsABlockThatRunsToMidnight`, `aDayWithoutANoteGetsOneOnlyWhenSomethingIsWrittenToIt`,
  `blockingOutADayNeverOpensTheNoteInTheEditor` — one of these also throws a hard runtime crash
  (`Fatal error: Index out of range` in `ContiguousArrayBuffer.swift`) that kills the whole test
  host process partway through the suite; find which specific assertion triggers array access on
  stale/mid-write state and fix the race there too, same technique.
- `Tests/DayControllerTests.swift` — calls into `DayController.write(_:)`
  (`DayController.swift:264`, the timeblock writer) or `openDailyNote()` (`:151`), both the same
  detached-`Task` shape. Failing: `aBlockUsesTheTaskHourAndTheDurationFromSettings`,
  `aBlockIsRemovedFromTheNoteItLivesIn`, `turnsATaskIntoABlockAndWritesItIntoTheNote`,
  `publishingEveryBlockReportsHowManyWent`, `publishingWritesTheEventAndMarksTheBlock`,
  `doesNotPublishTheSameBlockTwice`, `placesASecondBlockAfterTheFirstRatherThanOnTopOfIt`.
- `Tests/WeekScaleTests.swift` — `aBlockWrittenOnTheDayReachesTheWeeksColumn` goes through the same
  `DayController.write(_:)` path.
- `Tests/VaultMoveTests.swift` — `manager.undo()`/`manager.redo()` synchronously invoke a closure
  registered via `undo.registerUndo(withTarget:)` (`VaultController+Move.swift:65-69`) whose body
  is `Task { @MainActor in await controller.moveInverse(...) } ` — `undo()`/`redo()` return before
  that Task finishes. Failing: `aBatchThatFailsMidwayStillRegistersAnUndoForWhatDidMove`,
  `undoingAMoveRestoresEveryPathInOneStepAndRedoMovesThemAgain`,
  `undoRefusesAndRecordsAProblemWhenTheMovedItemHasBeenRenamedSince`. Note: `controller.moveItems`
  itself is properly `async` and already correctly `await`-ed — only the `manager.undo()`/
  `manager.redo()` calls that follow it race.

## What to do — test-only, deterministic, no polling-forever

**You may only edit files under `Tests/`. Do not touch anything under `Sources/`.**

For each failing assertion that checks a side effect of a fire-and-forget `Task`, do not simply
add `await` to the triggering call (it is not `async` — that is the whole problem). Instead, add a
small, local, test-only polling helper and use it to wait for the expected condition to become
true before asserting, with a firm timeout so a real regression still fails fast rather than
hanging:

```swift
/// Waits for `condition` to become true, checking every 5ms, up to `timeout`. Fails via
/// `Issue.record` (not a crash) if the timeout elapses first, so a genuine regression still
/// reports as a failed assertion rather than a hang.
func waitUntil(
    timeout: Duration = .seconds(2), sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("condition never became true within \(timeout)", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}
```

Place this once (e.g. in a small new file `Tests/Support/WaitUntil.swift`, or inline at the top of
each affected file if you prefer not to add a new file — your call) and use it like:

```swift
controller.flush()
await waitUntil { diaryOnDisk(root: root, day: day) != nil }
#expect(diaryOnDisk(root: root, day: day)?.entries.count == 1)   // existing assertion, unchanged
```

or for the undo case:

```swift
manager.undo()
await waitUntil { exists("A/x.md", at: root) }
#expect(exists("A/x.md", at: root))   // existing assertion, unchanged
#expect(!exists("B/x.md", at: root))
```

**Do not change what any assertion checks.** The polling wait goes *before* the existing
`#expect`/`#require` lines, never replacing or loosening them. If a test has no observable
condition to poll on that would tell you the fire-and-forget Task has completed (e.g., an
assertion that is purely about `controller.problems` being empty — a negative that stays true
whether or not the Task has run) then a short fixed wait (`try? await Task.sleep(for:
.milliseconds(50))`) is acceptable ONLY as a last resort — prefer polling a real condition
wherever one exists.

## If a test genuinely cannot be made deterministic without touching production

Some cases may need a production-side seam (e.g., exposing the write `Task`'s handle so a test can
`await` it directly, which would be more correct than polling). If you hit one where polling would
be flaky or dishonest about what's being tested, **do not invent a production change yourself** —
stop, leave that specific test as-is (or skip it with a comment, never delete it), and name it
precisely in your report as blocked, with the exact production file/line where a seam would need
to be added and what shape it should take. The orchestrator will route that to the coder.

## The crash

Find the exact assertion in `DiaryControllerTests.swift` whose stale-state read triggers
`Fatal error: Index out of range` in `ContiguousArrayBuffer.swift`. This is almost certainly the
same race (reading `entries` or a derived array before the write task's completion has updated
controller state) — the `waitUntil` fix above should resolve it too, but do not assume: rerun and
confirm the crash is gone, not just quieter.

## Verification

```bash
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -only-testing:PergamenumTests test
```
Run it more than once if you touch a timing-sensitive test — a fix that passes once but is still
racy is not done. **Done when:** the full `PergamenumTests` target passes with no crash, across at
least two consecutive runs of the four affected files (you may scope `-only-testing` to just those
four files for the repeat-run check to save time, then run the full suite once at the end).

## Guardrails

- Do not touch any file under `Sources/`.
- Do not weaken, delete, comment out, or skip an assertion to make a test pass.
- Do not add a fixed `sleep` longer than strictly needed as a substitute for polling a real
  condition, except the last-resort case described above.
- Commit is not your job; the orchestrator merges your worktree back.
