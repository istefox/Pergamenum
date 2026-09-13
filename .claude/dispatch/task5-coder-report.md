# Coder Report — Task 5 (R-03): one apply-plan loop, `rename` stops re-implementing `renamePlan`

Worktree: `/Users/stefer/Developer/Pergamenum/.claude/worktrees/agent-a592660e8df5b9672`
Forked from `7d6f340` on `feat/vault-layer-consistency-and-security-cha`. Nothing committed.

## Files modified

- `Sources/Core/Vault/VaultPlanApplication.swift` — the stub body becomes the real loop: write,
  record the path, record `"\(change.path): \(error)"` on a throw, never stop.
- `Sources/Core/Vault/VaultFileChange.swift` — doc comment only: the "TESTER-OWNED INTERFACE /
  only has to compile against the tests" scaffolding note is replaced now that 18 call sites
  depend on it, and the "no typealias" decision (§D4) is recorded where the type lives.
- `Sources/Vault/NoteFileOperations.swift` — `struct FileChange` deleted; 7 local references
  repointed; `rename` reduced to `renamePlan` + move + two `apply` calls.
- `Sources/Vault/FolderFileOperations.swift` — 5 references repointed; `renameFolder`'s two
  loops replaced.
- `Sources/Vault/FolderFileOperations+Move.swift` — 1 reference repointed; `moveFolder`'s loop
  replaced.
- `Sources/Vault/BoardFileOperations.swift` — 4 references repointed; `renameBoard`'s two loops
  and `moveBoard`'s one replaced.
- `Sources/Vault/VaultSession+Files.swift` — `renameNote`'s two loops and `moveNote`'s one
  replaced (the three the brief did not name; the tester found them).

No file under `Tests/` was touched. No `Project.swift` change was needed (both new files are
under the `Sources/Core/**` glob, which is also in `sharedSources`).

## Sub-steps

1. **`FileChange` → `VaultFileChange`, no typealias — done.** `grep -rn "FileChange" Sources/
   Tests/` now returns only `VaultFileChange` plus one test *function name*
   (`FolderFileOperationTests.swift:246`, `…ProducesNoFileChange()`), which is prose, not a type
   reference, and lives in `Tests/` anyway. The staleness table's "19" is 18 type references
   (1 declaration + 17 uses) plus that function name.
2. **`VaultPlanApplication.apply` — done.** Sequential loop, `rewrittenPaths` on success,
   `"\(change.path): \(error)"` on a throw, and the loop continues past a throw.
3. **Call sites replaced — done, nine loops, not six.** `NoteFileOperations.rename` (1),
   `FolderFileOperations.renameFolder` (2), `FolderFileOperations+Move.moveFolder` (1),
   `BoardFileOperations.renameBoard` (2) and `.moveBoard` (1), `VaultSession+Files.renameNote`
   (2) and `.moveNote` (1). Writer closures are the two the brief specifies, plus a third the
   brief could not have specified (see Key decisions).
4. **`rename` = `renamePlan` + move + two `apply`s — done**, exactly ADR-0041 §D5's sketch. The
   `:205-208` doc comment (file moves first, links after, and why) is still there, unedited, with
   four lines appended recording what `renamePlan` now owns.

## Key decisions

- **A third writer closure exists, in `VaultSession+Files`.** The brief names two
  (`store.write` for notes, raw bytes through `store.url(for:)` for `.canvas`). The session's own
  three loops write through `write(_:to:)` and `writeFile(_:to:)` instead, because they run inside
  `transaction(_:)` and must be journalled and gated by `isDryRun`. Substituting either of the
  brief's closures there would have silently dropped the journal entry and broken `--dry-run`, so
  the session keeps its own writer. This is `apply`-takes-the-writer working as §D4 intends, not a
  deviation from it.
- **`BoardFileOperations`' two outcome types carry no `rewrittenPaths`.** `RenameOutcome` and
  `MoveOutcome` have only `newPath` + `failures`, and the loops they replaced recorded nothing
  else. `apply`'s `rewrittenPaths` is therefore dropped at those three call sites, with a comment
  saying so — behaviour unchanged.
- **`rename`'s failure ordering moves, by the ADR's own design.** Before: note-read and note-write
  failures interleaved in `knownPaths` order, board failures last. Now: `plan.failures` (note-read
  + board-plan) first, then note-write, then board-write. That is what §D5's sketch prescribes
  (`Outcome(newPath:failures:)` seeded from the plan). No test asserts the mixed order, and the
  characterization test's case (one unreadable note, no write failure) is identical either way.
- **`repointBoards(from:to:titleChange:into:)` stays.** It is now reached only by `move`, which
  Task 5 does not touch. It is a read-decode-write pass, not one of the six plan-apply copies (the
  tester's list agrees), so removing it would have been out of scope.
- **`VaultSession+TagRename.swift:79` is a tenth loop of the same shape and was left alone.** It
  writes through `write(_:to:)` and records `"\(change.path): \(error.localizedDescription)"` —
  `localizedDescription`, not `error`. Converting it would change its message text, which is a
  behaviour change, not a refactor. It also carries its own `TagRenameChange` type (with an `id`),
  not `VaultFileChange`. Flagging it for whoever owns R-03's follow-up.
- **`VaultSession+BoardDrop.swift:66` confirmed not a loop.** The tester's correction holds: one
  `try write(rewritten, to: path)`, no iteration. The brief's cross-ref does not apply.

## Verification

Command (exactly as the brief specifies), run twice:

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' \
  -derivedDataPath ".build/DerivedData" -only-testing:PergamenumTests test
```

| | run 1 (17:17) | run 2 (17:22) |
|---|---|---|
| exit code | **65** | **65** |
| verdict | `** TEST FAILED **` | `** TEST FAILED **` |
| `✘` assertion failures | **0** | **0** |
| `✔ … passed` lines | 2 309 after restart | **2 892** |
| `Failing tests:` | `drawsABlockThatRunsToMidnight()` | `everythingWrittenInsideATransactionCarriesTheSameID()` |

**The eight tests this task owns are green in both runs**, by name:
`applyingAnEmptyChangeListYieldsAnEmptyOutcome`,
`applyingThreeSucceedingChangesRewritesAllThreeInOrderWithNoFailures`,
`aThrowingMiddleChangeIsRecordedAsAFailureAndTheThirdIsStillAttempted`,
`theFailureStringFormatMatchesTheSixExistingCopiesCharacterForCharacter`,
`multipleFailuresArePreservedInEncounterOrder`,
`renameCharacterization_completeOutcomeAndFinalBytesOfAllThreeNotes`,
`renameCharacterization_targetTitleCollisionThrowsAndWritesNothing`,
`renameCharacterization_repointsACanvasNodeReferencingTheRenamedNoteExactlyAsBefore`.
The characterization suite passing unedited is the whole point of the task: the rename's bytes,
its `newPath`, its exact `rewrittenPaths` order and its exact `failures` array are what they were.

**Run 2's 2 892 passing tests = the 2 884 of Task 4's report + the 8 new tests of this task**, with
zero `✘` in either log. `BoardFileOperationsTests` and `CanvasStoreTests` are inside that count,
unedited.

**Why the exit code is still 65, and why it is not this diff.** Each run lost exactly one test to
`Test crashed with signal segv`, a *different* test each time, and each of the two passed in the
other run. The crash report
(`~/Library/Logs/DiagnosticReports/Pergamenum-2026-09-12-171948.ips`) names the faulting thread as
the queue `it.stefer.pergamenum.watcher`:

```
swift_getObjectType | URL.standardizedFileURL.getter | static VaultScanner.relativePath(of:under:)
| closure #1 in VaultWatcher.handle(absolutePaths:) | Sequence._compactMap | FSEvents callback
```

EXC_BAD_ACCESS, null dereference, in an FSEvents callback — it lands on whichever test happens to
be running. The **identical** faulting stack is in crash reports from `2026-09-12 14:02`,
`2026-09-11 23:11` and `2026-09-08 21:56`, i.e. before this dispatch and before this chain's
Task 3 touched `VaultScanner` at all. Nothing in this diff runs on the watcher queue. Reported,
not fixed: it is outside Task 5's budget and is a real, pre-existing intermittent crash worth its
own task.

Extra check, not required by the brief (the `sharedSources` risk of a new `Sources/Core` type):

```
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' \
  -derivedDataPath ".build/DerivedData" build      → exit 0, ** BUILD SUCCEEDED **
```

Project setup: `tuist install && tuist generate --no-open` → exit 0 (a fresh worktree has no
`Tuist/.build`, so `install` is not optional).

## Drafted commit

```
refactor(vault): one apply-plan loop, and rename stops re-implementing renamePlan

ADR-0041 §D4/§D5, R-03. `NoteFileOperations.FileChange` becomes
`VaultFileChange` in `Sources/Core/Vault/` across all eighteen references,
with no typealias left behind, and `VaultPlanApplication.apply` becomes the
one loop that writes a plan: the path joins `rewrittenPaths` on success,
`"\(change.path): \(error)"` joins `failures` on a throw, and a throw never
stops the changes after it.

Nine hand-copied copies of that loop are gone - `NoteFileOperations.rename`,
`FolderFileOperations.renameFolder` (two), `moveFolder`,
`BoardFileOperations.renameBoard` (two) and `moveBoard`, and
`VaultSession+Files`'s `renameNote` (two) and `moveNote`, the last three of
which the plan had not counted. The writer stays at the call site, one line
long: `store.write` for a note, raw bytes through `store.url(for:)` for a
`.canvas`, and `write`/`writeFile` for the session, whose writes have to be
journalled and stopped by `isDryRun`.

`rename` is now `renamePlan` + move + two `apply` calls. It used to read each
note back from its new path after the move; the plan performs the same
substitution before it, and `NoteRenameCharacterizationTests` - written
against the old implementation and unedited here - pins the bytes, the
`rewrittenPaths` order and the `failures` array that prove the two agree.
```

## Cleanup

- No temporary files, scratch scripts or debug statements were added to the worktree. Build and
  test logs went to the session scratchpad
  (`/private/tmp/claude-501/.../scratchpad/{tuist,test1,test2,perg}.log`) and are outside the
  repository.
- `.build/DerivedData/` was created by the verification run inside the worktree. It is the path
  the brief's command specifies and is gitignored; left in place for the next run.
- No temp branch was created, so nothing to register with `temp-branch-reconcile.sh`.
- One memory shard written: `.claude/agent-memory/coder/topics/adr-0041-task5-watcher-segv-flake.md`
  (the pre-existing watcher crash, so the next agent does not re-diagnose it). `MEMORY.md` not
  touched. **It will not survive the merge-back on its own**: `.gitignore:80` ignores
  `.claude/agent-memory/`, while the shards already in the tree are tracked from before that rule
  — so `git status` does not even list the new file and a `git add -A` snapshot will skip it. The
  orchestrator has to `git add -f` it (or copy it across) if the note is wanted; this agent does
  not run `git add`.

## Plan deviations

1. **Nine loops replaced, not six.** The brief's six plus the three in `VaultSession+Files.swift`
   the tester found. Leaving those three would have left `R-03` half-done in the file the CLI
   reaches.
2. **`VaultSession+BoardDrop.swift` not modified.** The brief lists it as a copy of the pattern; it
   is a single write. Nothing there to replace.
3. **A third writer closure** (`write`/`writeFile`) for the session's three call sites — see Key
   decisions.
4. **Two doc-comment edits beyond pure mechanics**: the `VaultPlanApplication` stub note (it
   described a body that no longer exists) and the `VaultFileChange` tester-scaffolding note. Also,
   the "why the note itself is included" rationale that lived on the deleted loop was moved into
   `renamePlan`, which now owns that iteration, rather than deleted with the code.
5. **The suite is not green, and this report does not claim it is.** Exit 65 both times, from the
   pre-existing watcher SIGSEGV documented above. Zero assertion failures.

## Pattern classification

`ADD` 2 (the relocated rationale, this report) · `REMOVE` 1 (`struct FileChange`) ·
`REPLACE` 10 (the type repointings and the nine loops) · `MODIFY` 2 (two construction-site renames
and one comment correction).
