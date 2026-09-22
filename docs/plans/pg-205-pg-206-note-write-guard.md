# Fix: the note half of a rename proves what it is writing over, and the performer nothing calls leaves (PG-205 / #402, PG-206 / #403)

No `SPEC.md` governs this task. The repo-root `SPEC.md`, `BRAINSTORM.md` and
`UX-BLUEPRINT.md` belong to an already-merged, unrelated feature and are **not** this chain's
inputs. The requirement ids below are declared by this plan and by nothing else; every task
cites the ones it satisfies and no task cites an id not in this list.

Read out of the worktree `Pergamenum.worktrees/chore-fix` at `a61bd097`, clean tree. Every
line number, call-site list and count below was grepped in that tree, not recalled from the
ticket text.

## ADR outcome — new ADR: `docs/adr/0055-note-write-guard-and-the-dead-rename-performer.md`

Written, `proposed`, accepted when this branch merges.

**Path deviation, stated rather than silently taken.** The architect's write scope names
`docs/architecture/**` for ADRs. That directory does not exist in this repo: all 54 ADRs live
in `docs/adr/NNNN-<slug>.md`, `CLAUDE.md`'s "Chain decision index" links every one of them
there, and `.claude/protected-interfaces` plus a dozen ADR bodies cross-reference that path.
It is written at `docs/adr/0055-…` accordingly — the same deviation ADR-0054's own plan
recorded, for the same reason.

`0054` is the highest file under `docs/adr/`, `docs/architecture/` does not exist, and
`git log --all -- 'docs/adr/0055*'` returns nothing — the number is free, checked, not
assumed.

**Why a new ADR and not a one-line citation of ADR-0054.** The mechanism half of this chain
(extend `expecting:`/`refusals` to three more writers) would fail the significance gate on its
own — it is the adoption of a decision ADR-0054 §D6 and ADR-0046 §D1/§D4 already took, and
adopting a decided mechanism at a new call site does not need its own record. What carries the
ADR is the second half and two findings around it:

- **Hard to reverse.** §D6 deletes three methods and a private helper, and decides that this
  repository has exactly one note-rename performer. Bringing a second one back later is a
  decision, not a patch.
- **Surprising without context.** Three things a future reader would otherwise mis-read: a
  guarded write loop over a list that is permanently empty (`FolderFileOperations`, §D2); three
  methods with eighteen green tests deleted rather than kept; and a guard whose in-process race
  window is *measured as empty* and adopted anyway (§Context, §D4).
- **A real trade-off.** Delete versus keep-and-guard versus give-a-caller, each with reasons on
  both sides; and preflight versus per-write precondition, re-answered for a synchronous
  applier where ADR-0046 §D2's measurement does not apply unchanged.

Two overrides apply on top, either of which alone would carry the record: ADR-0054 §D8
**explicitly parked both tickets as needing their own decision** (a record the project itself
mandates), and §D6 writes down an explicit **no** — no second rename performer, no caller for
one — that a future reader would otherwise be tempted to undo.

ADR-0055 **extends ADR-0054 §D6/§D8 and ADR-0046 §D1/§D3/§D4/§D8**. It **amends nothing** and
**no ADR body is edited by this chain** — ADR-0054 §D8 is answered here, not rewritten there.

## What the code actually looks like, before anything is written

Grepped, not recalled. This is what decides the shape of every task below.

`VaultPlanApplication.apply`'s synchronous overload has eight call sites. Five write a
`.canvas` through the guarded `CanvasStore.writeRepoint` (ADR-0054 §D6). Three write a note
through an unguarded closure:

| Writer | Line | `noteChanges` populated by | Live caller |
|---|---|---|---|
| `BoardFileOperations.renameBoard` | `:164-166` | `renamePlan` `:95-111` | yes — `VaultSession.renameBoard` → `VaultController.renameBoard` |
| `FolderFileOperations.renameFolder` | `:402-404` | **nobody** — `renamePlan` `:172-198` never assigns it; the field's doc comment `:151-154` says so and says why | yes, over an always-empty list |
| `NoteFileOperations.rename` | `:234-236` | `renamePlan` `:106-121` | **no** — nothing in `Sources/` calls this method |

`NoteFileOperations` is constructed in exactly one production file, `VaultSession+Files
.swift:13`, which calls only `renamePlan`, `movePlan` and `danglingLinks`. `rename`, `move`
and `trash` are reached only from `Tests/NoteFileOperationTests.swift` (15 tests) and
`Tests/NoteRenameCharacterizationTests.swift` (3 tests).

The in-process window between the plan and the last write is **empty** on all three paths:
`VaultSession.renameBoard`/`renameFolder` are synchronous `throws`, the synchronous `apply`
overload contains no suspension, and `store.write` is a synchronous `Data.write`. Nothing in
this plan may be justified by an in-process race — see ADR-0055 §Context for what the guard
does and does not buy.

The refusal surface already exists: `VaultController+Folders.swift:48-50` and `:113-115`
already loop `outcome.refusals` and call `recordProblem(VaultWriteRefusal.movedOn(refusal)
.description)`. **No UI work is created by this chain.**

## Requirements

| id | requirement |
|---|---|
| R-01 | Every planned note rewrite in a rename verb goes through one guarded door that refuses a file whose bytes moved on since the plan read them. |
| R-02 | A refused note rewrite is classified into `refusals`, distinct from `failures`, on the same outcome the board half already uses. |
| R-03 | No `VaultPlanApplication.apply` call site in the repository writes through an unguarded `store.write` after this chain. |
| R-04 | A note that vanished between the plan and its turn in the loop is refused, not re-created. |
| R-05 | A refusal never stops the loop and nothing already written is rolled back (ADR-0046 §D3, unchanged). |
| R-06 | `NoteFileOperations.rename`, `move`, `trash` and the private `repointBoards` leave the tree, and every assertion their eighteen tests made is re-pointed at a surface the app actually uses — none is dropped, disabled or skipped. |
| R-07 | The refusal reaches the person through the surfaces that already report the board half's refusals; no new dialog, sheet, button or setting. |
| R-08 | Every comment or doc claim this change makes false is corrected in the same chain. *(no-test: documentation obligation, not assertable)* |
| R-09 | The refusal is pinned by a deterministic test at the writer seam; no test sleeps, races a debounce or spawns a competing `Task` (ADR-0046 §D11, ADR-0054 §D9). |
| R-10 | The residual gap this chain finds and does not fix — `VaultController.reconcile`'s `openNote`-only handling — is filed as its own ticket rather than left unmentioned. *(no-test: process obligation, not assertable)* |

## How the tasks are split between tester and coder

Swift is compiled: a batch that leaves the target unable to build produces no red tests at
all. So in every task below, **the tester's commit carries the type and signature
declarations** (bodies that `fatalError()` or return a placeholder) together with the red
tests; **the coder's commit carries the bodies only**. Where a task lists "Declarations" and
"Bodies" separately that is the split; where it lists only tests, nothing new is declared.

`tuist generate --no-open` after any task that adds or removes a file, before building — the
generated project still lists what is no longer there and the build fails naming the compiler
rather than the cause (CLAUDE.md).

Task order is dependency order: Task 1's door must exist before Tasks 2 and 3 adopt it, and
Task 4's deletion must land before Task 5 corrects the doc claims that enumerate what Task 4
removed.

---

### Task 1 — The one guarded note door (R-01, R-04, R-09)

**Files**
- `Sources/Vault/NoteStore.swift` (append beside `write` at `:137-162`; the file is 197 lines,
  no `file_length` pressure)
- new `Tests/NoteStoreWriteGuardTests.swift`
- `Project.swift` — **nothing to add, confirm and do not edit.** `Sources/Vault/NoteStore.swift`
  is already named in `sharedSources` (`:112`) and `Tests/**` is a glob (`:254`).

**Declarations (tester)**

```swift
extension NoteStore {
    /// The one guarded write for a planned note rewrite (ADR-0055 §D1).
    func writeGuarded(_ change: VaultFileChange) throws
}
```

**Bodies (coder)** — ADR-0055 §D1. Resolve `change.path` through the type's own `boundary`,
read the file's current bytes, compare `current.map(NoteStore.hash)` against
`change.expectedHash` (`Sources/Vault/VaultFileChange+ExpectedHash.swift:11` — use it, never a
second spelling of the hashing rule), throw `VaultWriteRefusal.movedOn(change.path)` on a
mismatch with nothing written, otherwise delegate to the existing
`write(change.after, to: change.path, requiringExistingFolder: true)`.

Three things the body must get exactly right, each with a reason:

- **`requiringExistingFolder: true`, not the default.** The comparison has already proven the
  file is there, so its parent is; passing `true` stops a redundant `createDirectory` from
  silently re-creating a parent vacated in the microseconds since (PG-168's decision,
  `NoteStore.swift:140-149`).
- **A missing file refuses.** `current` is `nil`, `nil` never equals a hash string, so the
  guard fires and no file is created. This is the one behaviour change observable without a
  second writer (ADR-0046 §D8).
- **`VaultWriteRefusal` is referred to unqualified.** A module-qualified
  `Pergamenum.VaultWriteRefusal` does not compile in `perg`/`pergamenum-mcp`, which compile
  this file under a different module name (ADR-0046 §D4).

No SwiftUI import anywhere near this file — it is in `sharedSources` and would break both tool
builds (ADR-0001 §D1).

**Tests** (`Tests/NoteStoreWriteGuardTests.swift`, mirroring `Tests/CanvasStoreTests.swift`'s
`writeRepoint` block):
- a change whose `before` matches the bytes on disk writes `after` and leaves the file holding
  exactly `after`;
- a change whose `before` disagrees throws `VaultWriteRefusal.movedOn(path)` and leaves the
  file **byte-identical** — assert the bytes, not just the throw;
- a change naming a path with no file at all refuses and creates nothing (R-04) — assert
  `!FileManager.default.fileExists` afterwards;
- a change whose path escapes the vault refuses through `boundary`, the way
  `Tests/CanvasStoreTests.swift`'s `writeRepoint` escape test already does for the board door.

Use `TemporaryVault` (`Tests/TemporaryVaultSupport.swift`), never a real vault path.

---

### Task 2 — `BoardFileOperations.renameBoard` adopts it (R-01, R-02, R-03, R-05, R-09)

This is the one writer of the three that both has a production caller and ever writes a byte.

**Files**
- `Sources/Vault/BoardFileOperations.swift` (`:163-176`)
- `Tests/BoardFileOperationsTests.swift` (add beside the existing ADR-0054 §D6 block at
  `:364-422`, which is the template)

**Bodies (coder)** — ADR-0055 §D2. Two lines:

```swift
let notes = VaultPlanApplication.apply(plan.noteChanges, writing: store.writeGuarded)
…
outcome.refusals.append(contentsOf: notes.refusals + boards.refusals)
```

`RenameOutcome.refusals` already exists (`:129-132`), so no struct changes and no memberwise
call breaks. Update the comment at `:171-173` — it currently says only the failures and
refusals of the *board* loop are carried over, which stops being true.

**Tests**
- *the seam*: build a real plan with `vault.operations.renamePlan("A/vecchio.canvas", to:
  "nuovo", knownPaths: [...])` over a vault holding two notes that name the board (one with a
  `^[[A/vecchio.canvas]]` task marker, one with a plain `[[vecchio.canvas]]` link); replace one
  change's `before` with bytes that disagree with disk; drive
  `VaultPlanApplication.apply(changes, writing: store.writeGuarded)`; assert the stale path is
  in `refusals`, **not** in `failures`, its file is byte-identical, and the other note was
  still rewritten (R-05 — the loop does not stop);
- *the whole verb, nothing concurrent*: `renameBoard` over the same vault leaves
  `outcome.refusals.isEmpty`, `outcome.failures.isEmpty`, and both notes rewritten — the
  mirror of `renameNoteWithNothingConcurrentLeavesRefusalsEmpty`
  (`Tests/VaultSessionFileOperationsTests.swift:251`). This is what proves the new writer is
  actually wired in rather than vacuously passing.

**Do not** add an injectable plan parameter to `renameBoard` so a test can force a refusal
end-to-end. ADR-0046 §D11 declined exactly that; the seam one call out is the production loop
and the production writer.

---

### Task 3 — `FolderFileOperations.renameFolder` adopts it (R-01, R-02, R-03)

**Files**
- `Sources/Vault/FolderFileOperations.swift` (`:402-404`, and the doc comment at `:151-154`)
- `Tests/FolderFileOperationTests.swift`

**Bodies (coder)** — ADR-0055 §D2. The same two lines as Task 2, at `:402` and the `refusals`
append below it.

**This loop runs over a list that is always empty, and that is why it is converted rather than
deleted.** `FolderRenamePlan.noteChanges`' doc comment states the guarantee it exists to
spell: «a guarantee spelled as an empty list the performer still writes through is one a future
planner can break loudly rather than silently». Deleting the loop repeals it; leaving it
unguarded means the day a planner does populate that list it inherits an unguarded write.
Extend that doc comment with one sentence naming the door it now writes through, so the next
reader does not file the guarded-empty-loop as dead code.

**Tests** — no new behavioural test is possible or wanted here (there is no input that makes
the list non-empty). Instead:
- keep and re-run the two existing `#expect(plan.noteChanges.isEmpty)` assertions
  (`Tests/FolderFileOperationTests.swift:251`, `:375`) unchanged — they are the guarantee;
- the ADR-0054 §D6 board-refusal tests at `:605-` stay green untouched.

If the coder finds an input that *does* populate `noteChanges`, stop: the grep in this plan's
preamble is wrong and the task needs re-scoping, not a quick test.

---

### Task 4 — The dead performer half of `NoteFileOperations` leaves, and its tests are re-pointed (R-03, R-06)

**This task deletes production code and rewrites two test files. It is behind a HITL gate —
see Risks below. Nothing in it starts before Stefano has approved the deletion.**

**Files**
- `Sources/Vault/NoteFileOperations.swift` — remove `rename(_:to:knownPaths:)` (`:200-247`),
  `move(_:toFolder:)` (`:249-273`), `repointBoards(from:to:titleChange:into:)` (`:275-303`) and
  `trash(_:knownPaths:)` (`:342-362`), plus the now-stale MARK comment block at `:58-66` which
  describes «`rename`, `move` and `trash` above».
- `Tests/NoteFileOperationTests.swift`
- `Tests/NoteRenameCharacterizationTests.swift`
- `Tests/VaultSessionFileOperationsTests.swift`

**What must stay**, each with a live production caller — do not remove any of these by
association: `renamePlan`, `movePlan`, `danglingLinks`, `repointBoardsPlan`,
`repointedDocument`, `boardPaths()`, `exists(_:)`, `Outcome`, `RenamePlan`, `MovePlan`,
`extension CharacterSet { static let pathSlashes }`.

**Call-site grep, run before writing anything** (done for this plan; re-run to confirm nothing
landed since):

```
rg -n "operations\.(rename|move|trash)\(" --type swift
rg -n "NoteFileOperations\(" --type swift
```

Result at `a61bd097`: `NoteFileOperations(` appears in `Sources/Vault/VaultSession+Files
.swift:13` (which calls only `renamePlan`/`movePlan`/`danglingLinks`),
`Tests/NoteFileOperationTests.swift:111`, `Tests/NoteRenameCharacterizationTests.swift:26` and
`Tests/VaultSessionFileOperationsTests.swift:203,233,274`. `.rename(`/`.move(`/`.trash(` on a
`NoteFileOperations` appear **only** in the first two test files, at
`NoteFileOperationTests.swift:149,165,178,191,202,217,229,240,257,275,286,303,319,329,352` and
`NoteRenameCharacterizationTests.swift:85,116,132`. **No production call site exists.**

**The re-pointing rule** (ADR-0055 §D6) — apply it per assertion, not per test:

| the assertion is about | it moves to |
|---|---|
| computed bytes: a link rewritten, a `.canvas` node repointed, a `.text` card followed or deliberately not followed, `failures == ["C.md: non leggibile"]` | `renamePlan` / `movePlan`, asserting on `plan.noteChanges[i].after`, `plan.boardChanges[i].after`, `plan.failures` — no disk write needed, and stronger than reading a file back |
| validation and refusal before anything moves: invalid title, colliding destination, missing note | `renamePlan` / `movePlan`, which already throw before anything moves; the "both files still there" half is true by construction |
| what ends up on disk, and that the file moved | `VaultSession.renameNote` / `moveNote` / `trashNote` in `Tests/VaultSessionFileOperationsTests.swift`, which already carries the `armedSession` harness and the composite-gesture tests at `:34`, `:64`, `:99`, `:117` |
| dangling links after a delete | `NoteFileOperations.danglingLinks`, directly — it is live and is what `VaultSession.trashNote` itself calls |

The nine pure `NoteRename.rewritingLinks` tests at `Tests/NoteFileOperationTests.swift:7-98`
are untouched: they never went near a performer.

`Tests/NoteRenameCharacterizationTests.swift` **keeps its file name**. Its subject was always
the bytes a rename produces (ADR-0041 §D5, Task 5), and `renamePlan` is where those bytes are
computed now; replace its header comment to say so. Its
`renameCharacterization_completeOutcomeAndFinalBytesOfAllThreeNotes` case — the one asserting
`rewrittenPaths` order *and* final on-disk text — goes to
`Tests/VaultSessionFileOperationsTests.swift`, where a performer exists; the other two are pure
plan assertions and stay in place, re-aimed.

**Before/after test count must be stated in the commit message.** Not "18 tests deleted": each
of the eighteen is either re-pointed or shown to be already covered by a named existing test,
and the message says which. A test that turns out to be a genuine duplicate of an existing one
is removed *with its duplicate named* — never silently.

**After the deletion, `rg -n "\.write\(to:" --type swift Sources/ | rg -i canvas` must show no
raw `.canvas` byte write outside `CanvasStore.swift`.** `NoteFileOperations.swift:297` is the
last one and it goes with `repointBoards`.

---

### Task 5 — The claims this chain makes false (R-07, R-08)

**Files**
- `Sources/Core/Vault/VaultPlanApplication.swift` (`:14-22`, and `:3-9`'s header)
- `Sources/Vault/BoardFileOperations.swift` (`:171-173`, done in Task 2 — verify)
- `Sources/Vault/FolderFileOperations.swift` (`:151-154`, done in Task 3 — verify)
- `Sources/App/VaultController+Folders.swift` (`:41-63`, `:106-120` — **read only, confirm no
  change is needed**)

**What changes.** `VaultPlanApplication.Outcome.refusals`' doc comment currently enumerates
«the three still writing a plain `store.write` note (`FolderFileOperations.renameFolder`,
`BoardFileOperations.renameBoard`, `NoteFileOperations.rename`'s own note half) can never
populate this». After Tasks 2–4 all three clauses are false: two adopted the door and the third
does not exist. Rewrite it to say that every synchronous call site now writes through a guarded
door — `store.writeGuarded` for a note, `canvas.writeRepoint` for a `.canvas` — and that both
can populate `refusals`. The header comment at `:3-9` enumerates the six loops this type
replaced, including `NoteFileOperations.rename`'s; correct that list too.

**What must be confirmed and left alone.** `VaultController.renameFolder` (`:45-50`) and
`renameBoard` (`:110-115`) already loop `failures` then `refusals` and report the refusal with
`VaultWriteRefusal.movedOn(refusal).description`, a sentence that names a path and claims
nothing about the kind of file. A note path reads correctly through it. **R-07 is satisfied by
changing nothing here** — read both verbs, confirm, and say so in the commit message rather
than adding a note-specific sentence nobody asked for.

Do **not** edit `docs/adr/0054-…md`. ADR-0055 answers its §D8; the reference runs one way.

---

### Task 6 — The record (R-08, R-10)

**Files**
- `CLAUDE.md` — one line in the "Chain decision index", in the existing shape, pointing at
  `docs/adr/0055-note-write-guard-and-the-dead-rename-performer.md`.
- `TODO.md` — close `PG-205` and `PG-206` with the two-line closure shape the file already uses
  (`- [x] … <!-- closed:… -->` plus an indented sentence naming the ADR and the plan); file the
  new ticket below.
- `docs/adr/0055-…md` — flip `Status:` to accepted **only when the branch merges**, not before.

**The new ticket (R-10)**, filed rather than fixed: `VaultController.reconcile`
(`Sources/App/VaultController+Watching.swift:28`) opens with `guard var note = openNote, note
.relativePath == change.path else { continue }`, so an external change to a **dirty tab that is
not the focused note** — another column, or a background tab in the same column — is dropped
entirely: no reload for a clean buffer, and no ADR-0001 §D3.4 conflict banner for a dirty one,
which will then overwrite the external change on its next save. Found while measuring ADR-0055
§Context. P3, `fix`, not this chain's to take (it changes behaviour on every external-edit path
in the app, not on a rename). ADR-0055 §D5 names it.

**Also record, as a correction rather than a silent fix** (ADR-0055 §Context already does; the
`TODO.md` closure note for `PG-205` should repeat it in one sentence): PG-205's own ticket text
says «`syncOpenNote`'s conflict prompt never sees it». That is true only for a dirty tab that is
not the focused note. A `.md` write does reach `VaultWatcher`, `store.write` records nothing in
`selfWrittenHashes`, so the change arrives at `VaultSession.reconcile` as external and does
reach the editor for `openNote`.

Filing the GitHub issue and closing #402/#403 are human actions at merge, not steps in this
plan.

---

## Verification, beyond the new tests

**Run the full suite, not just the touched files.** `NoteStore`, `NoteFileOperations` and
`VaultPlanApplication` are read by the vault, workspace, task, pratiche and connector suites. A
refusal now reachable where none was before, and three deleted methods, can go red in a module
this chain never opens.

```bash
tuist generate --no-open
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build
xcodebuild -workspace Pergamenum.xcworkspace -scheme pergamenum-mcp -destination 'platform=macOS' build
```

Both tool builds are not optional: `NoteStore.swift` and `NoteFileOperations.swift` are in
`sharedSources`, so Task 1 adds a member and Task 4 removes four that `perg` and
`pergamenum-mcp` compile. A `VaultWriteRefusal` written module-qualified, or a stray SwiftUI
import, fails there and nowhere else (CLAUDE.md, "AI connector").

SwiftLint by hand — it is not on CI (ADR-0044). Task 4 makes `NoteFileOperations.swift`
shorter, so nothing regresses, but confirm rather than assume.

`scripts/uitests.sh --affected` at merge, per CLAUDE.md's merge-gate rule. It is advisory and
does not block. **No GUI test is added by this chain** (ADR-0055's GUI budget: zero).

---

## Risks & HITL gates

- **HITL — the deletion in Task 4 is the gate of this chain.** Four methods leave production
  code and two test files are rewritten. CLAUDE.md: never delete files without explicit
  confirmation, never delete a test to make a suite pass. Show Stefano the exact list of what
  goes and the per-assertion re-pointing table **before** writing the diff. If he prefers to
  keep `trash` (the one whose deletion is not load-bearing for the guard work), Tasks 1–3 and 5
  are unaffected — say so rather than treating the whole task as all-or-nothing.
- **HITL — commit, push, PR, merge.** None of them is this chain's to take. `main` is never
  committed to directly; branch `fix/pg-205-206`, off `main`.
- **HITL — `TODO.md` and `CLAUDE.md` edits (Task 6)** change the project's own record; show the
  diff before writing.
- **Risk: the guard's honest value is smaller than the ticket implies, and the chain must not
  quietly inflate it.** The in-process window is empty on all three paths (measured, ADR-0055
  §Context). If any commit message, comment or test name claims this fixes an in-process race,
  it is wrong. What it fixes: one door instead of three templates, cross-process staleness, and
  a vanished note no longer silently re-created.
- **Risk: a vacuous test.** The Task 2 seam test forces a refusal through `apply` +
  `writeGuarded`, which would pass even if `renameBoard` itself were never converted. The
  "nothing concurrent, refusals empty, both notes rewritten" test is what closes that hole —
  it must actually assert the notes were rewritten, not just that `refusals` is empty.
- **Risk: `NoteStore.writeGuarded` confused with `VaultSession.writeGuarded`.** Same verb, two
  types, two doors (one synchronous and journal-free, one async and journalled). They are not
  interchangeable: a caller in `Sources/Vault`'s file-operations types must use the `NoteStore`
  one, a caller inside a `VaultSession` transaction must use the session one. The ADR states it
  (§D1); a comment at the new declaration should too.
- **Risk: a refusal now reachable where a test assumed it was not.** `Tests/VaultPlan
  ApplicationTests.swift:62-71` pins `failures`' string format character-for-character; nothing
  in this chain touches that format, but a note refusal landing in `failures` instead of
  `refusals` would break it loudly. That is the wanted failure mode, not a regression — if it
  fires, the classification is wrong, not the test.
- **Risk: `tuist generate` after a deletion.** Removing methods needs no regeneration; adding
  `Tests/NoteStoreWriteGuardTests.swift` does. Run it before the first build of Task 1 and
  again after any file is added or removed, or the build fails naming the compiler rather than
  the cause (CLAUDE.md).
- **No externally provisioned resource is needed.** No network, no API key, no OAuth flow, no
  cloud console, no new environment variable, no port, no third-party service. Every test runs
  against a throwaway directory (`TemporaryVault`, `Tests/TemporaryVaultSupport.swift`).
- **No new dependency.** No SPM package, no `Tuist/Package.swift` edit, no `tuist install`, no
  `Project.swift` edit at all — `NoteStore.swift` is already in `sharedSources` (`:112`) and
  `Tests/**` is a glob (`:254`). Confirm both; do not edit.
- **Hand check before merge**, since the guard's live half is cross-process: open a vault in the
  app, rename a board from the Workspace sidebar while a `perg`/`pergamenum-mcp` process holds
  the same vault, and confirm the marker rewrite reports a problem rather than silently
  clobbering. This is a confirmation that the refusal surfaces, not a reproduction of a race —
  do not spend time trying to hit the window.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
