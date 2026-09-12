## Tester Report

### Tests added

- `Tests/NoteRenameCharacterizationTests.swift` (new file)
  - `renameCharacterization_completeOutcomeAndFinalBytesOfAllThreeNotes` — the required
    three-note vault: A links to B by title, B links to itself, C is a non-UTF-8 file
    (unreadable). Renames B and asserts the **complete** outcome (`newPath`, exact
    `rewrittenPaths` order, exact `failures`) plus the exact final bytes of all three files.
    Written and confirmed green against the CURRENT, unmodified `NoteFileOperations.rename`
    before the stub types or any other test existed.
  - `renameCharacterization_targetTitleCollisionThrowsAndWritesNothing` — rename onto an
    existing title still throws `FileOperationError.alreadyExists`, both files left untouched.
  - `renameCharacterization_repointsACanvasNodeReferencingTheRenamedNoteExactlyAsBefore` — a
    `.canvas` node naming the renamed note is repointed, `rewrittenPaths` includes the board.
  - These three pin down `rename`'s current (pre-refactor) behavior so the coder's swap to
    `renamePlan` + move + two `VaultPlanApplication.apply` calls can be checked against a fixed
    baseline, per ADR-0041 §D5's one named risk (post-move `readPath` read vs. pre-move
    `writePath` read landing on different bytes).

- `Tests/VaultPlanApplicationTests.swift` (new file)
  - `applyingAnEmptyChangeListYieldsAnEmptyOutcome` — empty in, empty `Outcome` out.
  - `applyingThreeSucceedingChangesRewritesAllThreeInOrderWithNoFailures` — three succeeding
    writes → three `rewrittenPaths` in order, no failures, writer actually invoked for each.
  - `aThrowingMiddleChangeIsRecordedAsAFailureAndTheThirdIsStillAttempted` — the middle
    change's writer throws → two `rewrittenPaths`, one failure naming that path, and the third
    change is still attempted (the shape Task 7 / R-06 will lean on).
  - `theFailureStringFormatMatchesTheSixExistingCopiesCharacterForCharacter` — failure string
    is exactly `"\(change.path): \(error)"`, matching all six originals
    (`NoteFileOperations.swift:247`, `FolderFileOperations.swift:322,330`,
    `BoardFileOperations.swift:164,174,288`).
  - `multipleFailuresArePreservedInEncounterOrder` — two failures both recorded, in order.

- Stubs declared for compilation (tester-owned interface, ADR-0155 §D1 — coder fills the body):
  - `Sources/Core/Vault/VaultFileChange.swift` — `struct VaultFileChange: Equatable, Sendable`
    with `path`/`before`/`after`, exactly the fields `NoteFileOperations.FileChange` already
    carries, same names.
  - `Sources/Core/Vault/VaultPlanApplication.swift` — `enum VaultPlanApplication` with
    `Outcome` (`rewrittenPaths`/`failures`) and `static func apply(_:writing:) -> Outcome`. Body
    deliberately ignores `changes` and returns `Outcome()` unconditionally — this is what keeps
    four of the five `VaultPlanApplicationTests` genuinely red until the coder implements the
    loop (the empty-list test passes against both the stub and the real implementation, which
    is expected and not a weak test — see memory `pergamenum-tester-stub-pattern`).

Neither `NoteFileOperations.rename`/`renamePlan`, `FolderFileOperations.swift`,
`BoardFileOperations.swift`, nor `VaultSession+BoardDrop.swift` production code was touched.

### Run result

Command: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath ".build/DerivedData" -only-testing:PergamenumTests test`

1. **Baseline run** (characterization test only existed, no stub types yet, current unmodified
   `rename`): 2888 passed, 0 failed. All three `renameCharacterization_*` tests green — this is
   the commit-it-green-first step the brief requires.
2. **Full run** (after adding `VaultFileChange`/`VaultPlanApplication` stubs and
   `VaultPlanApplicationTests`): 2892 tests, 7 issues, **exactly 4 failing test functions**, all
   in `VaultPlanApplicationTests` — `applyingThreeSucceedingChangesRewritesAllThreeInOrderWithNoFailures`,
   `aThrowingMiddleChangeIsRecordedAsAFailureAndTheThirdIsStillAttempted`,
   `theFailureStringFormatMatchesTheSixExistingCopiesCharacterForCharacter`,
   `multipleFailuresArePreservedInEncounterOrder` (the 5th, `applyingAnEmptyChangeListYieldsAnEmptyOutcome`,
   correctly passes against the stub too). All three `renameCharacterization_*` tests still
   green. No other test in the suite regressed — `BoardFileOperationsTests` and
   `CanvasStoreTests` in particular stayed fully green, unedited.

### Coverage

- `NoteFileOperations.rename`'s current behavior (link rewrite for a normal note, self-link
  rewrite for the note being renamed, an unreadable third note, board repointing, collision
  refusal) is now pinned by a byte-exact characterization test, ready to catch any drift
  introduced by the `renamePlan`+move+`apply` refactor.
- `VaultPlanApplication.apply`'s full contract — empty input, all-succeed, partial-failure
  with continuation, exact failure-string format, multi-failure ordering — is specified and
  red, ready to drive the coder's implementation.

### Bugs found

None. The current `rename` implementation matches the characterization test's expectations
exactly; no behavioral defect was observed in the unmodified code.

### Requirement IDs covered

- **R-03** (one apply-plan loop, `rename` stops re-implementing `renamePlan`) — both test files.
- **R-06** (referenced by the brief as what Task 7 leans on) — the "third change still
  attempted after a middle failure" test in `VaultPlanApplicationTests` establishes this shape
  now, ahead of Task 7.

No other `R-NN` IDs are addressed by this task's tests; the SPEC's own §9 Success Criteria
section was not consulted since the plan task text (verbatim, ADR-0088) was the authoritative
brief here and named the tests explicitly.

### Sub-steps (executed / left to coder)

Executed (tester):
- Wrote `Tests/NoteRenameCharacterizationTests.swift` and confirmed it green against the
  current, unmodified `rename` before anything else changed.
- Declared `VaultFileChange` and `VaultPlanApplication` (stub body) under `Sources/Core/Vault/`.
- Wrote `Tests/VaultPlanApplicationTests.swift`, confirmed exactly the expected 4 of 5 tests
  are red against the stub.
- Ran the full `PergamenumTests` suite twice (before and after the stubs) and confirmed no
  other test regressed.

Left to coder (per the brief's "Coder implements" list):
1. `NoteFileOperations.FileChange` → `VaultFileChange` across all 19 call sites (no typealias).
2. `VaultPlanApplication.apply`'s real loop, failure-string format, `rewrittenPaths`.
3. The six call sites (`NoteFileOperations`, `FolderFileOperations` ×2, `BoardFileOperations`
   ×3, `VaultSession+Files`/board-drop equivalents) switched to call `apply` with the note
   writer (`try store.write($0.after, to: $0.path)`) or the `.canvas` writer
   (`try Data($0.after.utf8).write(to: try store.url(for: $0.path), options: .atomic)`).
4. `rename` rewritten as `renamePlan` + move + two `apply` calls, preserving its
   `:205-208` doc comment and behavior (checked by the characterization test).
