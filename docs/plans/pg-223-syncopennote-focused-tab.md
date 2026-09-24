# Fix: an in-process write, a save and a restore reach every tab that shows the note (PG-223 / #461)

No `SPEC.md` governs this task. The `SPEC.md`, `BRAINSTORM.md` and `UX-BLUEPRINT.md` at the repo
root belong to an unrelated feature that has already merged ("pratiche links task side"). They are
**not** inputs to this chain. There are no R-ids: each task names instead the part of issue #461 it
closes (the table below).

Read from the worktree `Pergamenum-461-pg-223-syncopennote-focused-tab-c08eafa6` at `2e529c14`,
with a clean tree. Every line number and call-site list below was grepped in that tree, not taken
from the ticket text.

## Before `/build`: bring the branch up to `origin/main` (orchestrator, HITL)

This branch is **5 commits behind `origin/main`** (`git log HEAD..origin/main`: `adc7297a` ADR-0057
diary write guard, `242b9073`, `b0131440`, `60d0cdbd`, `896526c7`).

- `origin/main` already has `docs/adr/0057-…`, so this chain's ADR is numbered **0058**.
- Main's `Sources/App/VaultController+Diary.swift` changed the signature of `writeDiary`. Its
  `syncOpenNote(with:)` call is still in the same shape, so nothing in this plan depends on it.
- None of the files this plan edits were changed on main (`VaultController+Editing.swift`,
  `+Tabs.swift`, `+Watching.swift`, `+Notes.swift`, `VaultSession+Notes.swift`, `NoteTab.swift`),
  so no code conflicts are expected. `TODO.md` and `CLAUDE.md` may conflict textually.

After updating the branch, in a fresh worktree run `tuist install` and then
`tuist generate --no-open`. `Pergamenum.xcworkspace` does not exist in this worktree yet, so the
test command below cannot run until those two commands have.

## ADR outcome: new ADR, `docs/adr/0058-in-process-writes-reach-every-tab.md`

The ADR is written, with status `proposed`, and is accepted when this branch merges.

**Path deviation, stated rather than silently taken.** The architect's write scope names
`docs/architecture/**`, but that directory does not exist in this repo. Every ADR lives at
`docs/adr/NNNN-<slug>.md`, and CLAUDE.md's chain index links them there. ADR-0054's and ADR-0055's
plans recorded the same deviation.

**Why a new ADR and not a §D8 added to ADR-0056.** The project's convention for a gap that a
previous ADR parked is a new record that closes it. ADR-0055 closed ADR-0054 §D8 that way, and
ADR-0056 closed ADR-0055 §D5 the same way. Neither edited the earlier ADR's body. ADR-0056 is
merged (PR #453) and is part of the history. Adding a §D8 to it would rewrite a merged record
without saying so. ADR-0058 therefore **closes ADR-0056 §D7.3, extends ADR-0056 §D1/§D2 and
ADR-0043 §D7, and amends neither**. This is the same "extends X, amends neither" form ADR-0056 used.

**Why an ADR at all.** A bug fix on its own could fail the significance gate, because it is easy to
reverse. Three overrides apply:

- ADR-0056 §D7.3 deliberately parked this as its own ticket, so the project itself requires a
  record.
- §D3 deliberately departs from the obvious approach. The tab that saved is found by id after the
  `await`, rather than as the focused tab, and it is exempt from the rule every other copy gets. A
  reader would be tempted to "simplify" either choice back.
- §D6 and §D7 are explicit "no" decisions: `bufferText` stays focused-only, and the writers that
  never catch the editor up are left out.

The ADR also records a real trade-off: whether `saveOpenNote` is even in scope (Alternative 2), and
a session-level hook versus per-call-site catch-up (Alternative 4).

## The parts of #461 this plan closes

| Label | Part | Where |
|---|---|---|
| **P1** | `syncOpenNote(with:)` reaches every tab that shows the path. This is the issue's first sentence. | `VaultController+Editing.swift:79-90` |
| **P2** | "`saveOpenNote()` has the sibling shape". This is the issue's second sentence. Decided in ADR-0058 §D3: **in scope**. The *target* stays the focused tab, as every one of its five callers requires. The *effects* reach every copy of the path, and the tab that saved is found by id after the `await`. | `:22-32` |
| **P3** | `restoreVersion(_:)`: the same shape, found in this chain between the two ranges the issue cites. | `:48-62` |
| **P4** | `addStructuralLink` / `reloadFocusedNote()`: the same shape plus a discarded dirty buffer, found in this chain. | `VaultController+Notes.swift:67-85`, `VaultController+Tabs.swift:300-308` |
| **P5** | The record (ADR-0058) and the follow-ups it names (§D7, Alternative 5). | `docs/`, `CLAUDE.md` |

The issue also cites `:93-104` (`acceptExternalChange` / `keepLocalVersion`). ADR-0058 §D6 leaves
them unchanged on purpose: since ADR-0056 §D7.2 they already act on the tab whose banner was
clicked.

## How the work is split between tester and coder

Swift is compiled and type-checked, so **the tester owns every new or changed signature and the
coder owns the bodies**. Task 1 therefore declares:

- `catchUp(to:)`, with an empty body;
- `syncOpenNote(with:savedBy:)`, with an empty body;
- the new return type of `VaultSession.addStructuralLink`, with `written: []` returned everywhere.

Task 1 also makes the smallest change at the one caller that keeps it compiling. After Task 1 the
target **builds**, and the new tests are **red on their assertions**, not red because the build
failed.

While Task 1 is red, `.claude/test-cmd`'s Stop hook will report red at the end of each turn. That
is expected and does not mean anything has regressed.

---

### Task 1: Tester. Signatures, fifteen red tests, and the staleness sweep (closes: nothing yet; provides P1–P4's acceptance)

**Files**

- `Sources/Vault/NoteTab.swift`: inside `VaultController.OpenNote`, next to `hasUnsavedChanges`
  (`:89`), declare `mutating func catchUp(to incoming: String)` with an **empty body**. Give it a
  one-line doc comment naming ADR-0058 §D1.
- `Sources/App/VaultController+Editing.swift`: declare
  `func syncOpenNote(with result: VaultSession.WriteResult, savedBy writer: NoteTab.ID)` with an
  **empty body**, directly under `syncOpenNote(with:)` (`:79-90`). Make it `internal`, not
  `private`: the tests call it through `@testable import`.
- `Sources/Vault/VaultSession+Notes.swift:166-203`: change the return type of `addStructuralLink`
  from `Bool` to `(created: Bool, written: [WriteResult])` and keep `@discardableResult`. In the
  body, every `return true` becomes `return (true, [])` and every `return false` becomes
  `return (false, [])`. **`written` stays empty. Filling it is Task 4.**
- `Sources/App/VaultController+Notes.swift:77-79`: a compile fix only, reading `.created` from the
  tuple. **Keep** the `reloadFocusedNote()` line at `:83` exactly as it is.
- New file `Tests/VaultControllerWriteCatchUpTests.swift`, with the fifteen tests listed in ADR-0058
  §Acceptance.
- Run `tuist generate --no-open` for the new test file.

**How to write the tests.** Follow the shapes already in use:

- The fixture helper and the "two columns, refocus the first" setup from
  `Tests/VaultControllerReconcileTests.swift:17-31`, `:35-58`.
- For "a column showing an unrelated note, so the other column really is in the background", use
  `:210-228` of the same file.
- For a dirty background tab in the same column, use `updateTab(backgroundID)` (`:100` of the same
  file).
- For direct calls with a hand-built `VaultSession.WriteResult(path:text:)`, use
  `Tests/VaultWriteOrderingBatch3Tests.swift:117-151`.
- For the two-note structural-link fixture, use `Tests/RelatedLinkTests.swift:134-155`.

Test-specific notes:

- **Test 8** (end to end) runs through `await controller.toggle(task)`, with `task` taken from
  `controller.index.allTasks`. The note is open only in the column that does not have the focus.
- **Test 11** drives the seam directly:
  1. Dirty `A.md` and record its tab id.
  2. `openNoteInNewTab(at: "B.md")`, which moves the focus to B.
  3. `syncOpenNote(with: WriteResult(path: "A.md", text: <A's text>), savedBy: aID)`.
  4. Assert that A's tab is clean and has no prompt, that the focus is still on B, and that B's
     text and path have not changed.
- **Test 13** passes `restoreVersion` a literal text that no tab holds, so it cannot pass by
  accident before the fix. `restoreVersion` writes whatever text it is given.
- None of the tests uses a timer, a sleep or a gate. Where the timing of an `await` matters, the
  test calls the post-`await` half directly (ADR-0058 §D3; ADR-0046 §D11).

**Staleness sweep: update the tests and call sites that assert the old behaviour.** Three
observable contracts change: the reach of `syncOpenNote` and `saveOpenNote`, the return type of
`VaultSession.addStructuralLink`, and the deletion of `reloadFocusedNote`. A grep of the whole
repo, done while writing this plan, found:

- `syncOpenNote(with:)`: ten production call sites (ADR-0058 Context table), plus
  `Tests/VaultWriteOrderingBatch3Tests.swift:129,146`. The comment at
  `Tests/TaskComposerTests.swift:341` is about `selectedTask`, not about tabs, and needs no change.
- `saveOpenNote()`: `CommandActions.swift:180`, `EditorColumn+Text.swift:142`,
  `NoteTabBar.swift:77`, `EditorColumn+Closing.swift:45`, `VaultController+Editing.swift:50`, plus
  the tests `NoteHistoryTests.swift:267,293`, `VaultTests.swift:371` and `NoteTabTests.swift:201`.
- `restoreVersion(_:)`: `Sources/Features/Editor/VaultBrowser+History.swift:60`, plus the tests
  `NoteHistoryTests.swift:271,302`.
- `VaultSession.addStructuralLink`: one caller, `VaultController+Notes.swift:77`. No test calls it
  directly: `RelatedLinkTests.swift:143,172,189` call the controller's method, whose `Bool`
  signature does not change. No connector calls it; `rg` over `Sources/Connector`, `Sources/CLI`
  and `Sources/MCPServer` returns nothing.
- `reloadFocusedNote()`: one caller, `VaultController+Notes.swift:83`. No test uses it.

**None of these asserts the focused-only behaviour.** The only multi-tab test that goes through an
in-process writer is `NoteTabTests.savingWritesTheFocusedTabAndNotTheOther`, and it checks a tab
showing a *different* path, which stays true. So the sweep's expected result is "no existing test
changes". If an existing test turns red for any reason other than the intended widening, **stop and
report it. Do not edit it to make it pass** (CLAUDE.md: never disable or rewrite a test to make a
suite pass).

**Done when**

- `Pergamenum`, `perg` and `pergamenum-mcp` all build. The last two are needed because
  `VaultSession+Notes.swift` is in `sharedSources`.
- Tests 1–6 and 8–15 are red on assertions, and test 7 is green.
- Every existing test in `PergamenumTests` is green.

---

### Task 2: Coder. One per-buffer rule, used by `syncOpenNote` and `reconcile` (closes: P1)

**Files:** `Sources/Vault/NoteTab.swift`, `Sources/App/VaultController+Editing.swift`,
`Sources/App/VaultController+Watching.swift`, `Sources/App/VaultController+Tabs.swift` (doc
comments only).

- Write the body of `catchUp(to:)` as ADR-0058 §D1 specifies.
  - Dirty buffer: set `externalChangePending` and leave `text`/`savedText` alone.
  - Clean buffer: set `text` and `savedText` to the incoming text and set `externalChangePending`
    to `nil`. Clearing the prompt here is deliberate (§D1, last paragraph).
- `syncOpenNote(with:)` becomes one call:
  `updateTabs(showing: result.path) { $0.note.catchUp(to: result.text) }` (§D2). It no longer
  calls `replaceOpenNote`, and it does not call `rememberTabs()`. Keep the existing ADR-0043 §D7
  paragraph of its doc comment. Add one paragraph saying that it reaches every tab showing the path
  in every column, and why: a self-hashed write never reaches the watcher.
- In `reconcile` (`VaultController+Watching.swift:33-41`), the closure body becomes
  `tab.note.catchUp(to: change.text)`.
- Fix the doc comments this task makes false:
  - `VaultController+Editing.swift:3-9` (the file header claims every method reaches the buffer
    through `replaceOpenNote` or `updateFocusedTab`);
  - `VaultController+Tabs.swift:257-260` (the list of what `updateTabs` is for gains "an in-process
    write").

**Done when:** tests 1–8 are green, and so are all nine tests in
`Tests/VaultControllerReconcileTests.swift` and both `syncOpenNote` tests in
`Tests/VaultWriteOrderingBatch3Tests.swift`.

---

### Task 3: Coder. `saveOpenNote` and `restoreVersion` (closes: P2, P3)

**Files:** `Sources/App/VaultController+Editing.swift`.

**`saveOpenNote()`** (ADR-0058 §D3):

- Before the `await`, read `focusedTab` and keep both its `id` and its note.
- Write `note.text` to `note.relativePath`, which is unchanged.
- After the `await`, call `syncOpenNote(with: result, savedBy: id)`. **Stop calling
  `replaceOpenNote`.**
- Failures are still reported through `recordProblem`, exactly as they are today.

**The body of `syncOpenNote(with:savedBy:)`** goes through `updateTabs(showing: result.path)`:

- On the tab where `tab.id == writer`, set `savedText = result.text` and
  `externalChangePending = nil`. **Do not touch `text`.**
- On every other tab, apply `catchUp(to: result.text)`.

The doc comment should say it is the post-`await` half of the save, exposed on purpose for the
tests (ADR-0046 §D11's reason), and that the writer is found by id rather than by focus (CLAUDE.md,
"A precondition evaluated before an `await` is a filter, not a guard").

**`restoreVersion(_:)`** (ADR-0058 §D4):

- Read `openNote?.relativePath` **before** `await saveOpenNote()`.
- Write the past version to that path.
- Call `syncOpenNote(with: result)`, which covers the writer's own tab too.
- Delete the re-read at `:51-52` and the `replaceOpenNote` call.
- Keep the doc comment's save-first paragraph. Add a sentence saying that a buffer still dirty
  after the save gets the prompt rather than being overwritten.

**Done when:** tests 9–13 are green, and so are `Tests/NoteHistoryTests.swift`'s two restore tests,
`Tests/NoteTabTests.swift`'s `savingWritesTheFocusedTabAndNotTheOther`, and `Tests/VaultTests.swift`'s
`editsAndSavesANoteWithoutCorruptingIt`.

---

### Task 4: Coder. `addStructuralLink` reports its writes, and `reloadFocusedNote` is removed (closes: P4)

**Files:** `Sources/Vault/VaultSession+Notes.swift`, `Sources/App/VaultController+Notes.swift`,
`Sources/App/VaultController+Tabs.swift`.

- In `VaultSession.addStructuralLink`, fill `written` with each write's own `WriteResult`, in
  order, as it lands: source first (`:196`), then target (`:197`). The success path returns
  `(true, written)` and the `catch` returns `(false, written)`, so a target write that fails
  after the source landed still reports the source (ADR-0058 §D5).
- Leave the two early returns before any write (`:173-180`) returning `(false, [])`.
- Leave the "atomic by construction" doc comment as it is (§D5, last paragraph).
- In `VaultController.addStructuralLink`, loop over `written` and call `syncOpenNote(with:)` for
  each result, then return `created`.
  - Delete the `reloadFocusedNote()` line and the comment above it (`:80-83`). That comment
    explains a door that is about to disappear.
  - Update the method's doc comment (`:67-68`) to say it catches up every tab showing either note.
- Delete `reloadFocusedNote()` and its doc comment from `VaultController+Tabs.swift:300-308`.
  First, repeat `rg -n "reloadFocusedNote" Sources Tests` in the updated branch. If it finds a
  caller that was not there at `2e529c14`, **stop and report**; do not delete.

**Done when:** tests 14–15 are green, all three `Tests/RelatedLinkTests.swift` tests are green, and
all three schemes build.

---

### Task 5: Verification (closes: the acceptance for P1–P4)

1. Run the full unit suite with `TEST-CMD CANDIDATE` below. Run the whole suite, not only the new
   file: `syncOpenNote` has ten callers in six extensions and one feature, and a change in how far
   a contract reaches can break a test in a module that only shares that contract.
2. Build all three schemes: `Pergamenum`, `perg` and `pergamenum-mcp` (CLAUDE.md § Commands).
   `scripts/mcp-smoke.py` is **not** required, because `Sources/MCPServer` is not touched.
3. Run `swiftlint lint` on the touched files only:
   - `Sources/Vault/NoteTab.swift`
   - `Sources/Vault/VaultSession+Notes.swift`
   - `Sources/App/VaultController+{Editing,Watching,Tabs,Notes}.swift`
   - `Tests/VaultControllerWriteCatchUpTests.swift`

   The whole tree fails SwiftLint by design, on seven types (`.github/workflows/ci.yml:12`).
4. Run `scripts/uitests.sh --status`, then `--affected` at merge time. This does not block the
   merge (CLAUDE.md's merge-gate rule). This chain's GUI-test budget is zero.
5. **Hand check by Stefano (HITL)**, on a Debug build started with
   `open -n "$(ls -dt …/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1)"` against a
   throwaway vault:
   1. Split the editor with the same note in both columns, focus the left one, and tick a task in
      that note from the Attività pane. The right column updates.
   2. Make the left copy dirty and press Cmd+S. The right copy, which is clean, updates.
   3. Make both copies dirty and save the left one. The right one shows the conflict banner.
   4. On a dirty note, use «Nota correlata…» → «Collega». The unsaved text stays, and the banner
      offers the linked version.

---

### Task 6: The record (closes: P5)

**Files:** `docs/adr/0058-in-process-writes-reach-every-tab.md` (already written), `CLAUDE.md`.

- Add one entry for **ADR-0058** to CLAUDE.md's "Chain decision index", straight after ADR-0056's
  entry, in the same form as the existing ones: "Closes `PG-223`/#461 …, extends …, amends neither
  → path".
- Correct ADR-0058 itself if the implementation departs from it. Record the correction as its own
  paragraph and do not edit the decision text silently.
- The `TODO.md` status for `PG-223` is **not** edited in this chain. It changes in the usual
  post-merge `chore/todo-sync-*` PR, the same way #486 and #488 were synced.
- **Handed to the orchestrating session, not done here:**
  - File the follow-up ticket for ADR-0058 §D7: seven writers that never catch the editor up. The
    recommended structural fix is a post-write notification from `VaultSession.write`.
  - Ask Stefano the open preference in ADR-0058 Alternative 5 (save-first versus a banner for
    «Collega» on a dirty note).

---

## Risks & HITL gates

- **HITL: updating the branch to `origin/main`** before `/build`. This is a git history operation
  and the orchestrator or Stefano decides between merge and rebase. The ADR number (0058) assumes
  it happens.
- **HITL: commit, push, PR, merge.** None is done by this plan.
- **HITL: Stefano's hand check** (Task 5, step 5). The milestone rule is that he verifies what
  ships.
- **No schema change, no file deletion, no on-disk format change.** One method,
  `reloadFocusedNote`, is deleted from the code (Task 4). It is not a file, and its only caller is
  replaced in the same task.
- **Risk: more banners.** A dirty background copy now gets ADR-0001 §D3.4's prompt where it used to
  be overwritten silently later. This is intended (ADR-0058, Negative consequences). The first time
  Stefano sees one on a tab he was not looking at, it may read as a regression.
- **Risk: the change to `reconcile`'s clean branch.** It now also clears a stale prompt (§D1). The
  nine reconcile tests cover it. If a reviewer disagrees, removing that one line reverts only that
  part.
- **Risk: `VaultSession+Notes.swift` is shared.** A new return type the connectors never read
  still has to compile under `perg` and `pergamenum-mcp`. Task 1 builds both, so a break shows up
  before any coder task starts.
- **Dependency: ADR-0057 on main** changed `writeDiary`'s call site. That call to `syncOpenNote` is
  still in the same shape, and ADR-0058 widens ADR-0057's Neutral line about it (ADR-0058,
  Neutral).
- **No external dependency.** No library, SDK or service is involved: the change is confined to
  `VaultController` and `VaultSession` in-process. Context7 was not needed.
- **Not in scope, named instead** (ADR-0058 §D7):
  - renaming a note, where links are rewritten in other notes;
  - `renameTag`;
  - `undoJournalledWrites`;
  - `moveOnBoard`;
  - `ensuringLocalID` in the Pratiche code;
  - the composer's diary mirror;
  - Plaud re-import.

  All of these leave every tab stale, not only background tabs.

## TEST-CMD

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

This command is identical to `.claude/test-cmd`. It needs `tuist install && tuist generate --no-open`
first, because `Pergamenum.xcworkspace` is generated and is not present in this fresh worktree
(checked), and again after Task 1 adds the new test file. `Project.swift` declares the unit-test
target `"\(projectName)Tests"` = `PergamenumTests` (`:248-254`, sources `Tests/**`).
