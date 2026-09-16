# PG-154 — Batch-scope write guard for the tag-rename and note-rename appliers

- Issue: GitHub **#263**, `TODO.md` **`PG-154`** (P3, correctness, `adr:0043`). The issue body is the
  whole specification. The `SPEC.md`/`BRAINSTORM.md`/`UX-BLUEPRINT.md` in the repository root belong
  to ADR-0043's own completed chain and are **disregarded** here.
- ADR: **`docs/adr/0046-batch-rename-stale-write-refusals.md`** (new, proposed). Read §D2, §D3 and
  §D6 before Task 3 — they are the three a task can silently violate by writing the «obvious» code.
- Governing prior ADRs, registered and not reopened: **ADR-0043** (§D5, §D7, §D8, §D9 and its
  Decline list), **ADR-0041** (§D4/§D5 one apply loop, §D9–§D11 the async write door),
  **ADR-0026 §D6** (all-or-nothing is a property of the decision), **ADR-0016 §D5/§D6**,
  **ADR-0012 §D7**, **ADR-0007 §D3/§D6**, **ADR-0001 §D1** (`Sources/Core` imports no SwiftUI).
- Baseline: worktree `Pergamenum.worktrees/263-tag-rename--note-rename-batch-applie`, branch
  `263-tag-rename--note-rename-batch-applie`, HEAD `43f8321`, clean tree. **The branch name does not
  match CLAUDE.md's Conventional Branch rule** (`fix/pg-154-…` would); it was created by the
  workflow, renaming it is the orchestrator's call and not part of any task below.

## Requirements this plan satisfies

No SPEC exists for this work, so the ids are declared here and every one is cited by at least one
task. They are the issue's four questions plus its deliverables.

| id | Requirement |
|---|---|
| **R-01** | The four batch writer closures pass the hash their `after` was derived from, so a file whose bytes moved on is refused instead of overwritten (issue Q1). |
| **R-02** | A refusal is reported through a channel a caller can branch on, distinct from a disk failure, without changing the existing `failures` string format. |
| **R-03** | Board writes (`writeFile`) are guarded on the same terms as note writes, or the note-rename half of R-01 is incomplete. |
| **R-04** | A mid-batch refusal neither stops the loop nor rolls back what was written, and no preflight pass is added (issue Q2, ADR-0046 §D2/§D3). |
| **R-05** | `renameTag` and `renameNote`/`moveNote` share the mechanism and diverge in how a refusal is reported, for the re-runnability reason (issue Q3, ADR-0046 §D6). |
| **R-06** | Every existing consumer of the two outcome types reports the new channel; none silently drops it (staleness rule). |
| **R-07** | The person sees a refusal on the two surfaces that would otherwise misreport it, and the «Annulla la rinomina» button is not offered for a rename that wrote nothing (issue Q4, ADR-0046 §D7). |
| **R-08** | Acceptance is a deterministic test that forces a refusal at the writer seam, not a green suite, and no test asserts on actor job order (ADR-0046 §D11). |
| **R-09** | The decision is recorded: ADR-0046 accepted, `TODO.md` updated, and the one finding this chain surfaces but does not fix is filed rather than absorbed *(no-test: documentation obligation)*. |

## Standing rules for every task

1. **`TEST-CMD` before Task 1** to establish the baseline, and after every task. A contract change
   here reaches tests in modules that have nothing to do with renaming — run the whole
   `PergamenumTests` target every time, never a per-file selection.
2. **`tuist generate --no-open` before building in any task that adds or removes a file** (Tasks 1
   and 2 add files). The generated project lists files explicitly; skipping this produces an error
   naming the compiler rather than the cause.
3. **`swiftlint --quiet`** after every task; no new violation on a touched file.
4. **Both connector targets build in Tasks 1, 2 and 4**, not only the app:
   `xcodebuild … -scheme perg … build` and `… -scheme pergamenum-mcp … build`. Every file this plan
   touches under `Sources/Vault` and `Sources/Core` is in `sharedSources` (`Project.swift:86-130`),
   so an app-only build proves nothing about them.
5. **The tester owns every new signature.** Swift is compiled: a task whose red tests reference a
   declaration that does not exist yet produces a build failure, not a red test. In each task below,
   the declarations listed under **Declare first** are added with their final signature (and a body
   that compiles — the existing behaviour, unchanged) *before* the assertions are written; the
   behaviour that makes them go green is the task's own second half.
6. **One commit per task**, Conventional Commits, English, `fix(vault):` / `feat(vault):` /
   `test(vault):` as appropriate.
7. **Never disable, skip or delete a test to make the suite pass** (CLAUDE.md). If an existing
   assertion contradicts ADR-0046, stop and report it — do not rewrite it silently.
8. **`scripts/uitests.sh` by hand before the merge to `main`**, not per task. Task 6 touches
   `TagBrowserView`; `UITests/` has no tag-rename coverage (checked: `grep -rln "tag-rename"
   UITests/` returns nothing), so the UI suite is a regression check here, not the acceptance.

---

## Task 1 — The refusal becomes a first-class outcome of the shared apply loop (R-01, R-02, R-04, R-08)

The groundwork every later task builds on, and the only task that touches `Sources/Core`.

**Declare first** (tester, before any assertion):

- `Sources/Core/Vault/VaultWriteRefusal.swift` — **new file.** `enum VaultWriteRefusal: Error,
  CustomStringConvertible, Equatable { case movedOn(String) }`, moved verbatim from
  `Sources/Vault/VaultSession.swift:560-569` with its doc comment and its Italian `description`
  (««\(path)» è cambiato da quando questa scrittura è partita, non lo tocco») unchanged — the string
  is asserted on at `Tests/VaultWriteOrderingBatch3Tests.swift:232`.
- `Sources/Vault/VaultSession.swift` — the `extension VaultSession` at `:555-570` keeps the name:
  `typealias WriteRefusal = VaultWriteRefusal`, **unqualified** (a `Pergamenum.`-qualified spelling
  breaks the `perg`/`pergamenum-mcp` builds, which compile this file under another module name).
- `Sources/Core/Vault/VaultPlanApplication.swift` — `Outcome` gains `var refusals: [String] = []`,
  declared **after** `failures` so every existing memberwise call stays valid.
- `Sources/Vault/VaultFileChange+ExpectedHash.swift` — **new file**, `extension VaultFileChange {
  var expectedHash: String { NoteStore.hash(Data(before.utf8)) } }`, with a comment naming
  `VaultDisk.write`'s own `hashBefore` derivation (`VaultDisk.swift:208-209`) as the expression it
  must keep matching. Under `Sources/Vault` and not `Sources/Core` because it reaches `NoteStore`,
  and therefore **added by hand to `sharedSources` in `Project.swift`** beside the
  `NoteStore+ReadSurface.swift` entry (`:107`), with the same style of comment. This is the only
  `Project.swift` edit in the plan.

**Then implement**

- Both overloads of `VaultPlanApplication.apply` (`:23-37`, `:56-71`) catch `VaultWriteRefusal`
  first and append `change.path` to `refusals`; the general `catch` keeps appending
  `"\(change.path): \(error)"` to `failures`, character for character. **The loop still continues in
  both branches** (ADR-0046 §D3) — the existing doc comment at `:19-22` gets one sentence about the
  refusal branch, not a rewrite.

**Tests** — `Tests/VaultPlanApplicationTests.swift` (extend; the existing five tests stay untouched
and must stay green, `:18-83`):

- a writer throwing `VaultWriteRefusal.movedOn` puts the bare path in `refusals`, nothing in
  `failures`, nothing in `rewrittenPaths`;
- the change after a refusal is still attempted (the §D3 continue, mirroring `:41-60`);
- a refusal and a disk failure in the same batch land in their own collections, in encounter order;
- `#expect(outcome == VaultPlanApplication.Outcome())` at `:20` still compiles and passes — the
  defaulted field is what makes that true;
- the synchronous overload classifies identically.

**Call sites that must keep compiling, verified by grep** — `VaultSession.WriteRefusal` appears at
`Sources/Features/Pratiche/PraticaEntryComposer.swift:71,:104`,
`PraticaLiveSync.swift:330,:417`, `PraticaCommandActions.swift:328`, `DossierWriter.swift:39`,
`Sources/Features/Recordings/RecordingsController+Import.swift:66`,
`Sources/Connector/VaultWrites.swift:300`, `Sources/Vault/VaultSession+TimeBlocks.swift:46`,
`Sources/Vault/VaultSession+Tasks.swift:141,:235,:270`, `Sources/Vault/VaultDisk.swift:212`,
`Tests/VaultWriteOrderingBatch3Tests.swift:222,:232`. **All fifteen resolve through the typealias
and none is edited.** If any one needs editing, the typealias is wrong — stop and report.

---

## Task 2 — `writeFile` gains the same opt-in precondition (R-03, R-08)

**Declare first**

- `Sources/Vault/VaultDisk.swift:260` — `func writeFile(_ text: String, to relativePath: String,
  expecting: String? = nil) async throws -> IndexMutation`.
- `Sources/Vault/VaultSession+Journal.swift:156` — `func writeFile(_ text: String, to relativePath:
  String, expecting: String? = nil) async throws`, forwarding.

**Then implement**

- In `VaultDisk.writeFile`, before `store.write`: when `expecting` is non-nil, read
  `try? store.text(relativePath)`, hash it the same way `write` does, and `throw
  VaultWriteRefusal.movedOn(relativePath)` on a mismatch — **inside the actor**, so no suspension
  separates the read from the write (ADR-0046 §D5). A path with no file yields `nil` and refuses
  (§D8).
- `VaultSession.writeFile`'s main-actor journal read at `:157-159` is **left exactly as it is**. It
  is ADR-0043 §D5's Race 2 shape surviving on the non-note door; Task 7 files it, this task does not
  fix it. Do not "tidy" it in passing.

**Tests** — `Tests/VaultSessionJournalTests.swift` (or a new `Tests/WriteFilePreconditionTests.swift`
if that file is already at the SwiftLint length limit — check before adding):

- `writeFile(…, expecting: <hash of what is on disk>)` writes and journals as before;
- `writeFile(…, expecting: <stale hash>)` throws `VaultWriteRefusal.movedOn(path)`, the file on disk
  is byte-identical to what it was, and **no journal entry was appended** for it;
- `writeFile(…, expecting: <any hash>)` on a path with no file refuses rather than creating it;
- `writeFile(…)` with no `expecting:` is unchanged in every respect (the three existing call sites
  depend on this).

---

## Task 3 — `renameTag` adopts the guard (R-01, R-02, R-04, R-05, R-08)

**Declare first**

- `Sources/Vault/VaultSession+TagRename.swift` — `TagRenameOutcome` gains `var refusals: [String] =
  []`, declared after `failures`, so `TagRenameOutcome(changed:failures:)` at `:84` and
  `TagRenameOutcome(failures:)` at `:127` stay valid.
- `Sources/Vault/VaultSession.swift` (or a new extension in the same file as the appliers — the
  coder picks one home and both appliers use it): the batch writer becomes a **named internal
  function** rather than an anonymous closure, so Task 3's and Task 4's tests can drive the
  production writer directly (ADR-0046 §D11):
  `func writeGuarded(_ change: VaultFileChange) async throws` → `try await write(change.after, to:
  change.path, expecting: change.expectedHash)`, and `func writeFileGuarded(_ change:
  VaultFileChange) async throws` for the board half. Internal, not private: the tests are in the
  same module via `@testable import`.

**Then implement**

- `renameTag` (`:81-83`) hands `writeGuarded` to `VaultPlanApplication.apply` and copies
  `result.refusals` into the outcome. `journalIDs` still comes from reading the journal back
  (`:88-91`) — a refused write appends nothing, so that account stays correct by construction, and
  it must not be changed to remember what was written.
- **No preflight pass is added** (ADR-0046 §D2). If the implementation grows a read loop before the
  apply, it has gone wrong.
- The doc comment at `:56-61` gains a sentence: a note that changed under the batch keeps its own
  text, is named in `refusals`, and re-running the rename finishes the job (§D6).

**Tests** — `Tests/TagRenameTests.swift` (extend; all six existing tests stay green):

- **The acceptance test (R-08):** build `[VaultFileChange]` by hand whose `before` disagrees with
  the bytes on disk for exactly one of three notes, drive it through
  `VaultPlanApplication.apply(changes, writing: session.writeGuarded)`, and assert the two others
  were written, the third was not, its path is in `refusals`, and **its bytes on disk are
  untouched**. Deterministic: no `Task`, no interleaving, no timing.
- `renameTag` end to end with nothing concurrent: `changed`, `journalIDs` and the files are exactly
  what `renamingWritesEveryNoteAndJournalsEachWrite` (`:116-130`) already asserts, and `refusals` is
  empty. This is the plumbing check.
- A note deleted from the vault between the preview and the write is refused, not re-created (§D8) —
  drivable through the same seam as the acceptance test.
- The journal holds no entry for a refused path, so `undoJournalledWrites` on the returned ids puts
  back only what was written (reuses `undoingTheGroupPutsEveryNoteBack`'s shape at `:133-145`).

---

## Task 4 — `renameNote` and `moveNote` adopt the guard, notes and boards (R-01, R-03, R-05, R-08)

**Declare first**

- `Sources/Vault/NoteFileOperations.swift:42-49` — `Outcome` gains `var refusals: [String] = []`,
  after `failures`, so `Outcome(newPath:)` and `Outcome(newPath:failures:)` stay valid.

**Then implement**

- `Sources/Vault/VaultSession+Files.swift:26-34` — the note apply uses `writeGuarded`, the board
  apply uses `writeFileGuarded`; `outcome.refusals` collects both, beside the existing
  `rewrittenPaths`/`failures` merge at `:35-36`.
- `:56-58` — `moveNote`'s board apply, same change. Boards only: a move rewrites no note text.
- **Order is unchanged**: `moveFile` first, then notes, then boards (`:22-37`). Do not add a check
  before `moveFile`; a plan entry for the renamed note carries the **new** path with a `before` read
  from the **old** one, and a naive precondition placed there would compare against a path that does
  not exist yet and refuse every rename. After the move the bytes are the same bytes, so
  `expectedHash` compares correctly at the new path — this is why the guard goes where the writes
  already are and nowhere earlier.
- The doc comment records §D6: a refusal here is a stale wikilink that re-running the rename cannot
  repair, unlike the tag path.

**Tests** — `Tests/VaultSessionFileOperationsTests.swift` (extend; `:41-44`, `:74`, `:83`, `:124`,
`:146` stay green), plus `Tests/StarredTests.swift:106,:120` and `Tests/VaultSessionTests.swift:70`
re-run unchanged:

- a link-rewrite note whose bytes moved on is refused: the file keeps its own text, its path is in
  `refusals`, the renamed file **still moved**, and every other link was rewritten;
- a board whose bytes moved on is refused through `writeFileGuarded`, and the `.canvas` on disk is
  byte-identical (this is Task 2's parameter reaching its real caller);
- `renameNote` with nothing concurrent: `newPath`, `rewrittenPaths` and `failures` exactly as today,
  `refusals` empty;
- the star still follows the note on a partially refused rename (`moveStar` at `:42-44` runs off
  `outcome.newPath`, which a refusal does not change).

---

## Task 5 — Every consumer of the two outcomes reports the new channel (R-02, R-05, R-06)

The staleness task. Grepped on this tree: `renameTag(`/`renameNote(`/`moveNote(` and the two outcome
types have **exactly these consumers**, and each is listed with what it does today.

| Call site | Today | After |
|---|---|---|
| `Sources/App/VaultController+Files.swift:42-44` | `recordProblem("link non aggiornato in \(failure)")` per failure | unchanged for `failures`; each refusal gets its own sentence naming the note and the cause (§D6: this link stays stale) |
| `Sources/App/VaultController+Files.swift:56-70` (`moveNote`) | reads **neither** `failures` nor `refusals` — board-repoint failures are dropped on the floor | reports both. A pre-existing gap, one line, closed here because the new channel would otherwise be dead in this path (ADR-0046 §D7, named as beyond the issue's literal ask) |
| `Sources/Vault/VaultSession+Move.swift:117` (`report(note.failures)` inside `moveItems`) | `recordProblem("riferimento non aggiornato: \(failure)")` | also reports `note.refusals`. `MoveBatchOutcome` itself is **not** changed — it already has its own `refusals`, meaning something else (a batch refused before writing), and conflating the two would break ADR-0026 §D6's distinction |
| `Sources/Connector/VaultWrites.swift:111-116`, `:131-136` | builds `FileMoveSummary(newPath:applied:rewrittenPaths:failures:)` | refusals are **folded into `failures`** with their own sentence. `FileMoveSummary` (`VaultPayloads.swift:192-197`) is `Encodable` and is the JSON `perg` and the MCP tools answer with: no key is added, so no external shape changes |
| `Sources/Features/Tags/TagBrowserView.swift:312-314` | `FinishedRename(old:new:journalIDs:failures:)` | carries refusals too — Task 6 |
| `Sources/Vault/NoteFileOperations.rename` (`:224-234`) | synchronous `store.write` writers | **untouched.** That path cannot produce a refusal (ADR-0046 §D10); leaving `refusals` unmerged there is deliberate, not an omission |

**Tests** — `Tests/ConnectorTests.swift` (the `FileMoveSummary` shape is unchanged; add one case
asserting a refusal reaches `failures` with its sentence) and `Tests/VaultMoveTests.swift:264`'s
neighbourhood for the `moveItems` report path. `Tests/VaultBatchMoveTests.swift` asserts on
`MoveBatchOutcome` and must stay green **unmodified** — if it goes red, the `MoveBatchOutcome`
boundary above was crossed.

---

## Task 6 — What the person sees (R-07)

`Sources/Features/Tags/TagBrowserView.swift` only. No other view changes; `TagRenameSheet.swift` is
untouched.

- `FinishedRename` (`:42-47`) carries `refusals`; `perform(renameOf:to:)` (`:302-316`) passes them.
  Its early-return guard at `:306` already admits a non-empty `failures`; it must admit a non-empty
  `refusals` too, or a wholly refused rename would show the person **nothing at all**.
- `TagRenameBanner` (`:348-375`) gains a refusal count beside «N non scritte», Italian, with the
  paths in its `.help` — the existing pattern at `:358-362`, not a new one.
- **«Annulla la rinomina» is hidden when `journalIDs` is empty.** Today the button is unconditional;
  a rename that wrote nothing would offer an undo of nothing, and `undoJournalledWrites([])` answers
  success and clears the banner. That state becomes reachable for the first time through this
  change, so the fix belongs to it.
- Colours and fonts through tokens only (CLAUDE.md design-system rule); no new string outside the
  view; UI language Italian.

**Tests** — `Tests/TagBrowserTests.swift` (exists; extend it, do not add a UI test). The banner's
undo button already carries `accessibilityIdentifier("undo-tag-rename")` (`:365`), so a UI test
added later has a contract to bind to — **this task adds none**, per standing rule 8.

---

## Task 7 — Record the decision and file what this chain does not fix (R-09)

*(no-test: documentation and process obligation — nothing here is test-assertable.)*

- Flip `docs/adr/0046-batch-rename-stale-write-refusals.md` to **accepted** and append an
  «Implementation notes» section in ADR-0043's own style: the measured call-site counts, anything
  the plan got wrong, and the acceptance tests' names.
- `TODO.md`: tick `PG-154` (`:50`) and `#263` (`:40`).
- **File, do not fix:** `VaultSession.writeFile` still reads its journal «before» on the main actor
  before the actor hop (`VaultSession+Journal.swift:157-159`) — ADR-0043 §D5's Race 2 shape
  surviving on the non-note write door, which §D5 closed for `write` only. New `TODO.md` entry, next
  free `PG-` id (verify against `main` first — this repo runs parallel chains), P3, `[correctness]`,
  referencing ADR-0046 §D5 and ADR-0043 §D5.
- `PROJECT_BRIEF.md` «Status» is **not** touched: this is not a milestone.
- CLAUDE.md's «Chain decision index» gains the ADR-0046 one-liner, and «Decisions from later
  chains» gains its essentials paragraph — the convention every ADR from 0019 on follows.

---

## Risks, dependencies and HITL gates

- **The behaviour change is deliberate and user-visible: a tag rename can now finish partially.**
  ADR-0046 §D6 argues why that is acceptable for the tag path (re-runnable) and reported rather than
  silent for the note path (not re-runnable). If the person would rather keep the clobber, that is a
  decision for them and it belongs at the ADR gate, **before** Task 3 — it is a preference, not a
  fact, and this plan does not answer it on their behalf.
- **A file deleted mid-batch stops being re-created** (§D8). Anyone relying on a tag rename to
  resurrect a note it had already read would see a change. Judged wanted; named so it is not read
  later as a regression.
- **Contract change, so run the whole suite, never a scoped selection.** Three outcome types and one
  error type change shape. The types are reachable from `Sources/App`, `Sources/Features/Tags`,
  `Sources/Features/Pratiche`, `Sources/Connector`, `Sources/CLI` and `Sources/MCPServer`; the tests
  that touch them are `VaultPlanApplicationTests`, `TagRenameTests`, `VaultSessionFileOperationsTests`,
  `VaultSessionTests`, `VaultSessionJournalTests`, `StarredTests`, `VaultMoveTests`,
  `VaultBatchMoveTests`, `NoteRenameCharacterizationTests`, `NoteFileOperationTests`,
  `ConnectorTests`, `VaultWriteOrderingBatch3Tests`, `BoardDropTests`.
- **Both connector targets must build** after Tasks 1, 2 and 4. A new file under `Sources/Vault`
  that a connector needs and that `sharedSources` does not name fails the `perg` link, not the app
  build — the failure CLAUDE.md predicts.
- **`tuist generate --no-open` after the two file additions**, or the build names the compiler
  instead of the cause.
- **Do not fix `PG-152`** (`transaction`'s `currentOperation` across a suspension) in passing. It is
  ADR-0043 §D9's deliberately open hazard and needs its own ADR.
- **The pre-commit `weakening-scan.sh` will report every new Swift Testing test as
  `zero-assertion-test`** — a known systematic false positive on `#expect` (CLAUDE.md). Read the diff
  rather than the finding.
- No externally provisioned resource is needed: no third-party API, no consent flow, no cloud
  console, no new environment variable or port. Everything runs offline against a `TemporaryVault`.
- **HITL gates:** the ADR's acceptance (before Task 3, because Task 3 is the first user-visible
  behaviour change); the commit of each task; the push; the merge to `main`; and the manual
  `scripts/uitests.sh` run before that merge. No schema change, no deletion, no deploy.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield
