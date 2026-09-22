# ADR-0055: The note half of a rename proves what it is writing over, and the performer nothing calls leaves

- Status: proposed, on the branch `fix/pg-205-206`. Accepted when that branch merges to `main`.
- Date: 2026-09-22. Written on the worktree `Pergamenum.worktrees/chore-fix` at `a61bd097`
  (clean tree). Every signature, line number, call-site list and count below was grepped in
  that tree, not recalled from the ticket text or from ADR-0054's own prose.
- **Numbering note:** `0054` is the highest file under `docs/adr/`, there is no
  `docs/architecture/` directory in this repo, and `git log --all -- 'docs/adr/0055*'`
  returns nothing - so no `0055` exists in any commit reachable from any ref. Checked, not
  assumed.
- Source: `TODO.md` **`PG-205`** (P3, fix) → issue **#402** and **`PG-206`** (P4, chore) →
  issue **#403**. Both were opened by ADR-0054 §D8, which named them as the two things that
  chain deliberately left open: the note half of the board and folder rename verbs still
  writing through an unguarded `store.write`, and `NoteFileOperations.rename`/`move` having
  no production caller at all. They ship as one chain because they are the same three lines
  of code: guarding the note half of `NoteFileOperations.rename` and deciding whether that
  method should exist are not separable questions.
- **Extends ADR-0054 §D6/§D8 and ADR-0046 §D1/§D3/§D4/§D8.** The mechanism is unchanged and
  none of it is redesigned: the opt-in hash precondition, the `refusals` channel classified
  apart from `failures`, "a refusal never stops the loop", and "a file that vanished
  mid-batch is refused, not re-created" are all used exactly as those two ADRs built them.
  What changes is how many *note* writers use them, and how many note-rename performers the
  repository has.
- **Amends nothing.** No ADR body is edited. ADR-0054's §D8 is *answered* here, not rewritten
  there; the reference runs one way, from this file to that one.
- **Reopens nothing else.** No SPEC §14 decision, no on-disk format, no frontmatter key, no
  tag grammar, no `IndexCache.schemaVersion` bump (stays 4), no protected-interface
  signature, no JSON payload shape, no MCP tool surface. `VaultAPI.FileMoveSummary` keeps its
  four keys. ADR-0025 §D6 stands: a board write is still not journalled and
  `BoardFileOperations.swift`/`FolderFileOperations.swift` stay out of `sharedSources`.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.
- **GUI-test budget: zero.** Every decision below is observable on `NoteStore`,
  `VaultPlanApplication` and two synchronous file-operations types, and the refusal is forced
  deterministically in-process (§D7). The 17-test GUI suite does not grow.
- Registered and not re-litigated: **ADR-0043 §D7** (a precondition evaluated before an
  `await` is a filter, not a guard), **ADR-0046 §D2** (there is no batch preflight pass),
  **ADR-0046 §D6** (the two appliers share the mechanism and diverge in consequence, because
  one is re-runnable and the other is not), **ADR-0041 §D4/§D5** (one apply-plan loop, one
  door rather than a step a caller can forget), **ADR-0001 §D3.4** (never merge, never
  discard: ask).

---

## Context

### The three writers, read out of the code

`VaultPlanApplication.apply`'s synchronous overload has eight call sites. Five of them write
a `.canvas` through `CanvasStore.writeRepoint`, which ADR-0054 §D6 made the one guarded
repoint door. Three write a note through a hand-spelled closure with no precondition of any
kind:

| Writer | Line | `noteChanges` populated by | Live caller | Guard |
|---|---|---|---|---|
| `BoardFileOperations.renameBoard` | `:164-166` | `renamePlan` `:95-111` - the `^[[old.canvas]]` marker and the plain `[[old.canvas]]` link, in every note that named the board | `VaultSession.renameBoard` → `VaultController.renameBoard` | none |
| `FolderFileOperations.renameFolder` | `:402-404` | **nobody.** `renamePlan` (`:172-198`) assigns `boardChanges` and `failures` and never touches `noteChanges` - the field's own doc comment at `:151-154` says so and says why | `VaultSession.renameFolder` → `VaultController.renameFolder` | none, over an always-empty list |
| `NoteFileOperations.rename` | `:234-236` | `renamePlan` `:106-121` | **none.** Nothing in `Sources/` calls this method | none |

So of the three writers PG-205 names, exactly **one** both has a production caller and ever
writes a byte: `BoardFileOperations.renameBoard`. The second writes an empty list, by
design. The third is dead. That is not a reason to fix less - it is the shape of the fix,
and it is what makes §D6's question unavoidable rather than optional.

### What the guard buys here, measured rather than assumed

ADR-0046 §D2 measured the window for the *async* appliers and found it opens **inside** the
loop, because every `await write` hands the main actor back to the run loop. None of that
applies to these three. `VaultSession.renameBoard` and `renameFolder` are synchronous
`throws` (`VaultSession+Folders.swift`), `VaultPlanApplication.apply`'s synchronous overload
contains no suspension, and `store.write` is a synchronous `Data.write`. The whole gesture -
plan, `moveItem`, N note writes, M board writes - runs as one uninterrupted main-actor
statement sequence. **In-process, the window between the plan and the last write is empty for
the entire batch.**

Said plainly, because the ticket's own wording invites the opposite reading: this guard does
not close an in-process race, because there is no in-process race left to close on these
paths. What it buys is three things, in descending order of weight.

1. **One door instead of three templates.** After this chain, no `VaultPlanApplication.apply`
   call site in the repository writes through an unguarded `store.write`. ADR-0041's rule -
   «a security or invariant check exposed as a separately-callable assertion gets skipped by
   the next call site, not maliciously, just by omission» - is the whole argument, and the
   evidence for it is in this repo's own history: ADR-0054 §D6 replaced five hand-copied
   unguarded `.canvas` writes that all descended from one. Three unguarded note writes are
   three places the next author copies from, and one of them (`FolderFileOperations`) is a
   documented invitation to a future planner to start populating `noteChanges`.
2. **Cross-process staleness.** `perg`, `pergamenum-mcp` and Obsidian write the same vault
   from other processes, and they are the only writers that *can* land inside a
   main-actor-synchronous gesture. This narrows that window; it does not close it, which is
   the identical limit `VaultDisk.write`'s and `CanvasStore.writeRepoint`'s own comparisons
   have, accepted on the same terms (ADR-0054 §D3).
3. **A vanished note is refused, not re-created.** `NoteStore.write` creates the parent
   directory and then the file unconditionally, so a note another process deleted between the
   plan and its turn in the loop is *resurrected* today, holding text derived from bytes
   nobody can see any more. Under the guard it is refused and named. This is ADR-0046 §D8's
   behaviour change, arriving at the three call sites that chain did not reach.

### What the guard does **not** buy, since ADR-0054 §D8's own sentence invites the confusion

§D8 says «a note open and dirty in the editor can still have its links rewritten from a plan
read before the user's edit». Two different things are folded together there, and only one of
them is a staleness race:

- A **dirty buffer** is in memory, not on disk. The plan reads the on-disk bytes and the write
  puts derived bytes back; the hash matches, and the write proceeds - correctly, because the
  marker rewrite is wanted. Nothing this ADR does changes that, and nothing should: refusing
  would leave a stale `^[[vecchio.canvas]]` behind on account of an edit that has not
  happened on disk yet.
- A **saved buffer** is the race. If the person saves between the plan's read and the loop's
  turn at that note, today's write clobbers the save silently. In-process that cannot happen
  on these paths (see above); from `perg` or Obsidian it can, and the guard refuses it.

§D8's second clause - «these writes do not go through `VaultSession.write`, so
`syncOpenNote`'s conflict prompt never sees them either» - is **imprecise, and this ADR
records the correction rather than repeating it**. `VaultWatcher` reports `.md` paths
(`VaultWatcher.swift:72` drops everything else), and `store.write` records nothing in
`selfWrittenHashes`, so a board rename's note rewrite arrives at `VaultSession.reconcile` as
an *external* change and does reach the editor. `VaultController.reconcile`
(`VaultController+Watching.swift:24-38`) then either reloads a clean buffer or raises
ADR-0001 §D3.4's conflict banner on a dirty one. The real gap is narrower and different: that
method opens with `guard var note = openNote, note.relativePath == change.path else
{ continue }`, so an external change to a **dirty tab that is not the focused note** is
dropped on the floor - no reload, no banner, and the buffer will overwrite the rewrite on its
next save. That is a defect of the editor's reconciliation, not of the writers, it predates
this chain, and §D5 files it rather than folding it in.

### The dead performer

`NoteFileOperations.rename(_:to:knownPaths:)`, `move(_:toFolder:)` and `trash(_:knownPaths:)`
have no caller in `Sources/`. Grepped: `NoteFileOperations` is constructed in exactly one
production file, `VaultSession+Files.swift:13`, which calls only `renamePlan`, `movePlan` and
`danglingLinks` on it. The three performers are reached only from
`Tests/NoteFileOperationTests.swift` (15 tests) and `Tests/NoteRenameCharacterizationTests
.swift` (3 tests).

They are not merely unused. `rename` is a **second implementation of note rename** that is
not journalled (no undo group, ADR-0016 §D5), does not update the index, does not move the
note's star (ADR-0012 §D6), never consults `canOperate(on:)`, and records nothing in
`selfWrittenHashes` - so every one of those would be a defect the day it acquired a caller.
The app's real note rename is `VaultSession.renameNote`, which does all five. `trash`
duplicates `danglingLinks`' body verbatim (`:357-361` against `:151-157`). And `move`'s
private helper `repointBoards` (`:281-303`) is the **sixth** hand-copied unguarded `.canvas`
byte write - the one ADR-0054 §D6 did not convert, precisely because nothing calls it. It is
the last raw `document.encoded().write(to:options:.atomic)` on any rename or move path in the
repository (`NoteFileOperations.swift:297`, confirmed by grep against every `.write(to:` in
`Sources/`).

---

## Decision

### §D1 - One guarded note door, `NoteStore.writeGuarded(_:)`, beside `CanvasStore.writeRepoint`

```swift
extension NoteStore {
    /// The one guarded write for a planned note rewrite.
    func writeGuarded(_ change: VaultFileChange) throws
}
```

It resolves `change.path` through the same `boundary` every other `NoteStore` write goes
through, reads the file's current bytes, and compares `current.map(NoteStore.hash)` against
`change.expectedHash` (`VaultFileChange+ExpectedHash.swift:11`, the expression ADR-0046 §D1
already made canonical). A mismatch throws `VaultWriteRefusal.movedOn(change.path)` with no
byte moved. A match delegates to the existing `write(_:to:requiringExistingFolder:)`, so
there stays exactly one place in this type that puts a note's bytes on disk.

`requiringExistingFolder: true`, not the default. The hash comparison has already proven the
file is there, so its parent is there too and `createDirectory` has nothing to do; passing
`true` makes the door say that rather than leaving a redundant, silently-recreating
`createDirectory` on the path. If the parent is vacated in the microseconds between the
comparison and the write, `Data.write` fails with its own ENOENT and the loop records an
ordinary failure - which is PG-168's decision (`NoteStore.swift:140-149`) applied where it
already belongs.

A **missing file is a refusal, not a creation**: `current` is `nil`, `nil` equals no hash, the
comparison fails. This is ADR-0046 §D8 verbatim, and it is the one behaviour change in this
ADR that is observable without a second writer. It is recorded here so a future reader does
not read it as a regression.

It lives in `Sources/Vault/NoteStore.swift`, which is already named in `sharedSources`
(`Project.swift:112`), so `perg` and `pergamenum-mcp` compile it and no `Project.swift` edit
is needed. `VaultWriteRefusal` is in `Sources/Core/Vault/` and must be referred to
**unqualified** - a module-qualified `Pergamenum.VaultWriteRefusal` would not compile in the
two tool targets, which compile these same files under a different module name (ADR-0046
§D4's rule, unchanged).

**On the name.** It is `writeGuarded` and not `writeRepoint`, because a note rewrite is not a
repoint; and it deliberately matches `VaultSession.writeGuarded` (`VaultSession.swift:626`),
which does the same thing through the async journalled door. Two types, one verb, one
meaning, resolved by the receiver. `CanvasStore.writeRepoint` keeps its name: renaming it
would churn five call sites and two test files to buy symmetry in a place where the asymmetry
is honest - one door writes a document, the other writes a note.

### §D2 - Both live note-write closures adopt it, including the one whose list is always empty

```swift
let notes = VaultPlanApplication.apply(plan.noteChanges, writing: store.writeGuarded)
```

at `BoardFileOperations.renameBoard` (`:164`) and `FolderFileOperations.renameFolder`
(`:402`), with `outcome.refusals.append(contentsOf: notes.refusals + boards.refusals)`
replacing the board-only append at both sites. `NoteFileOperations.rename`'s own call site is
not converted - it leaves with the method (§D6).

**The always-empty one is converted rather than deleted, and that is a decision, not an
oversight.** `FolderRenamePlan.noteChanges`' doc comment (`FolderFileOperations.swift:151-154`)
states the reason it exists: «a guarantee spelled as an empty list the performer still writes
through is one a future planner can break loudly rather than silently». Deleting the loop
would repeal that guarantee; leaving it unguarded would mean the day a planner does populate
that list, it inherits an unguarded write - the exact «a step a caller can forget» ADR-0041
exists to remove. Converting it costs one line, changes no behaviour today (`apply` over an
empty array is a no-op), and makes the guarantee arrive guarded.

### §D3 - The refusal reaches the person through the channel that is already there

`VaultController.renameFolder` (`VaultController+Folders.swift:48-50`) and `renameBoard`
(`:113-115`) already loop `outcome.refusals` and call
`recordProblem(VaultWriteRefusal.movedOn(refusal).description)`. That sentence - «`\(path)` è
cambiato da quando questa scrittura è partita, non lo tocco» - names a path and makes no claim
about what kind of file it is, so a note path reads correctly through it with no change.

**No UI work is created by this ADR.** No new sheet, no confirmation, no retry button, no
preference, no new sentence. ADR-0046 §D7's boundary, unchanged.

What *is* recorded, because a future reader comparing the two appliers would otherwise read
it as drift: a refused note rewrite here is **not repairable by repeating the gesture**, for
ADR-0046 §D6's exact reason applied to a board name. Once the board has been renamed,
re-running `renameBoard` computes `from: nuovo.canvas, to: nuovo.canvas`, and
`NoteRename.rewritingLinks` answers `nil` for an unchanged title
(`Tests/NoteFileOperationTests.swift:62-64` pins it), so nothing is rewritten and the refused
marker stays stale permanently. It is reported as a problem naming the note, which is what
`recordProblem` already does - the tag path's «re-run it» remedy does not exist here and is
not claimed.

### §D4 - No batch preflight, no rollback, no automatic retry

ADR-0046 §D2/§D3, inherited whole and restated only so this chain cannot be read as
reopening them. A refusal does not stop the loop; the remaining notes are independent files
whose rewrites are wanted. Nothing already written is rolled back - these verbs are not
journalled at all (ADR-0025 §D6, ADR-0022 §D6), so there is no group to undo, which makes the
question moot rather than merely answered. Nothing is re-read and retried: recomputing `after`
from the new `before` and writing it is the clobber again, one step removed and now invisible.

### §D5 - No buffer-state preflight is added, and the one real editor gap is filed rather than fixed

`VaultController.canOperate(on:)` refuses a *note* rename while that note has a dirty tab, and
`canOperateOnFolder(_:)` refuses a *folder* rename while `openNote` is dirty and inside it.
Neither reaches the N notes a board rename rewrites, and `renameBoard` runs no such check at
all - deliberately, per the comment at `VaultController+Folders.swift:92-96`.

Extending either to «refuse a board rename while any note it would rewrite has a dirty tab» is
rejected on three grounds. It is ADR-0046 §D2's preflight in another costume - a check over N
notes, evaluated before the writes, guarding a window measured above as empty. It blocks on a
condition the person cannot locate: a board rename can touch dozens of notes across the vault
and the refusal would name a file they are not looking at. And the honest answer to a dirty
buffer is not «refuse the rename», it is «tell the editor», which is the channel that already
exists.

That channel has one real gap, found while measuring this chain's Context and **not fixed
here**: `VaultController.reconcile` (`VaultController+Watching.swift:28`) handles only
`openNote`, so an external change to a dirty tab in another column - or to a background tab in
the same column - is skipped entirely, with neither a reload nor ADR-0001 §D3.4's banner. That
is a defect of the editor's reconciliation with its own tab model, it predates this chain by a
long way, it would change behaviour on every external-edit path in the app rather than on a
rename, and folding it in would make this chain about something else. It is filed as its own
ticket, the treatment ADR-0046 §D5 gave `PG-161` and ADR-0054 §D8 gave these two.

### §D6 - The dead performer half of `NoteFileOperations` is deleted

`rename(_:to:knownPaths:)`, `move(_:toFolder:)`, `trash(_:knownPaths:)` and the private
`repointBoards(from:to:titleChange:into:)` leave the file. What stays: `renamePlan`,
`movePlan`, `danglingLinks`, `repointBoardsPlan`, `repointedDocument`, `boardPaths`,
`exists`, `Outcome`, `RenamePlan`, `MovePlan` and `CharacterSet.pathSlashes` - every one of
which has a live production caller.

Three candidate answers existed and two are rejected on their merits.

**Give them a production caller** - rejected, and it was the first thing checked rather than
dismissed. There is no surface that wants them. The app renames a note through
`VaultController.renameNote` → `VaultSession.renameNote`; both connectors reach the same
method through `Sources/Connector/VaultWrites.swift`. A caller for the direct performers
would be a caller that deliberately wants a rename with no journal, no index update, no star
and no self-write bookkeeping, and no such caller is wanted: a synchronous, session-free write
door is precisely what ADR-0043 deleted (`write(_:to:) throws`) for these reasons.

**Keep them and guard them** - rejected, and it is the option this chain's own work makes
worse rather than better. After §D1 the method would carry a plan, a guarded writer, a
`refusals` channel and eighteen green tests, and would still silently skip the journal, the
index and the star. A future author grepping for «how does this app rename a note» would find
it and call it. That is a confident, circular argument built out of a guard that guards the
wrong thing - a trap with better lighting.

**Delete them** - taken. It removes the only second implementation of a rename verb in the
repository, removes the last unguarded `.canvas` byte write on any rename or move path
(§Context), removes a verbatim duplicate of `danglingLinks`, and leaves exactly one answer to
«what renames a note here».

`trash` goes with the other two rather than being left behind, and the reason is stated so the
inclusion is not read as scope creep: it is the same shape (a journal-free second performer
with no caller), its deletion is not load-bearing for the guard work, and leaving one of three
would recreate the same «why is this one still here» question a year from now. If it is
wanted back, it comes back with a caller.

**No test is disabled, skipped or deleted.** Eighteen tests currently drive the three
performers, and every assertion they make is re-pointed at a surface the app actually uses,
none dropped:

- Assertions about **computed bytes** - a link rewritten, a `.canvas` node repointed, a
  `.text` card's wikilink followed or deliberately not followed, an unreadable note reported
  as `"C.md: non leggibile"` - move onto `renamePlan`/`movePlan` and assert on
  `plan.noteChanges[i].after` / `plan.boardChanges[i].after` / `plan.failures`. These get
  *stronger*: they pin the bytes the planner computes rather than the bytes a performer
  happened to write, and they need no disk write at all.
- Assertions about **validation and refusal before anything moves** - an invalid title, a
  colliding destination, a missing note - already throw out of `renamePlan`/`movePlan`, which
  is where they move. Nothing has moved when a plan throws, so the «both files are still
  there» half is true by construction.
- Assertions about **what ends up on disk and what moved** move onto `VaultSession
  .renameNote`/`moveNote`/`trashNote` in `Tests/VaultSessionFileOperationsTests.swift`, which
  already has the session harness and already covers the composite gesture
  (`:34`, `:64`, `:99`, `:117`). The board bytes are identical on that path: it applies the
  same `plan.boardChanges[i].after` through `writeFileGuarded`.
- `danglingLinks` is live and is asserted directly for the two `trash` tests' real content.

`Tests/NoteRenameCharacterizationTests.swift` keeps its name and its file. Its subject was
never `rename`'s loop for its own sake - it was written (ADR-0041 §D5, Task 5) to pin the bytes
a rename produces across a refactor, and `renamePlan` is where those bytes are computed now.

### §D7 - Acceptance is a deterministic refusal at the writer seam, never a green suite

ADR-0046 §D11 and ADR-0054 §D9's rule, unchanged: no test sleeps, spawns a competing `Task` or
races a debounce. The window measured in Context is empty in-process, so a timing test could
not force a refusal even if one were allowed. The refusal is forced by **being** the external
writer, at the named seam:

1. build a real plan through `BoardFileOperations.renamePlan` (or `FolderFileOperations
   .renamePlan`);
2. replace one change's `before` with bytes that deliberately disagree with what is on disk;
3. drive `VaultPlanApplication.apply(changes, writing: store.writeGuarded)` - the production
   loop and the production writer, not a re-spelling of them;
4. assert the refused path is in `Outcome.refusals` and **not** in `failures`, that its file
   is byte-identical to what it was, and that every other change in the batch was still
   written (§D4's no-stop rule).

`NoteStore.writeGuarded` is additionally driven directly for its three own cases: a matching
hash writes, a stale hash refuses and moves nothing, a missing file refuses rather than
creating one (§D1). This is the exact shape `Tests/CanvasStoreTests.swift` already uses for
`CanvasStore.writeRepoint`, and `Tests/VaultSessionFileOperationsTests.swift:196-235` for the
async note door.

---

## Alternatives considered

1. **Leave the three note writers unguarded, since the in-process window is empty.** Rejected,
   and it was a live option - §Context measures the window honestly and the ticket is P3, so
   «do nothing» had to be answered rather than assumed away. It loses on ADR-0041's rule
   rather than on the race: three hand-spelled unguarded writes are three templates, the
   `FolderFileOperations` one is an explicit invitation to a future planner, and the
   cross-process and vanished-file cases are real even if narrow. It also leaves one gesture
   refusing a board repoint and silently clobbering the note rewrite beside it, which is an
   inconsistency a reader has to account for every time they read either half.
2. **Make `expecting:`-style guarding mandatory on `NoteStore.write` itself, so no writer can
   forget it.** Rejected, and it is ADR-0043 §D8's own rejection unchanged: every blind write -
   a new note, a template, a restore from history, a connector «make the file say this» -
   would become a failure path its caller is not written to handle, for a hazard it does not
   have.
3. **Route these three writers through `VaultSession.write`, which already carries the
   precondition and the journal.** Rejected on ADR-0054 §D3's measurement. `VaultSession
   .renameBoard`/`renameFolder` are synchronous `throws` and are called from synchronous
   `VaultController` verbs which are called from SwiftUI view code; making them `async` is the
   cascade ADR-0043 measured at 3-4x its own estimate. It would also put a folder and board
   rename's writes into a journal that ADR-0022 §D6 and ADR-0025 §D6 deliberately keep them
   out of, because `WriteJournal`'s three entry kinds cannot express «rename, then rewrite N
   notes and repoint M boards» as one reversible unit.
4. **Add a preflight pass over the notes a rename would rewrite, refusing the whole gesture if
   any has moved on.** Rejected at §D4, on ADR-0046 §D2's reasoning: it guards the window that
   is empty, cannot see the one that is not, costs a full extra read of every note, and leaves
   a reader believing the operation is atomic when it is not.
5. **Extend `canOperate(on:)`'s dirty-buffer refusal to every note a board rename would
   rewrite.** Rejected at §D5: a preflight in another costume, blocking on a condition the
   person cannot locate, answering a question that belongs to the editor's own external-change
   channel - which already handles the focused note correctly.
6. **Fix `VaultController.reconcile`'s `openNote`-only gap in this chain.** Rejected at §D5 as
   scope, not on merits: it is real, it is filed, and it changes behaviour on every
   external-edit path in the app rather than on a rename.
7. **Keep `NoteFileOperations.rename`/`move`/`trash` and guard them** (§D6). Rejected: it
   leaves a second, journal-free, index-blind rename implementation in the tree, now wearing a
   guard that makes it look safer than it is.
8. **Give `NoteFileOperations.rename`/`move` a production caller** (§D6). Rejected: no surface
   wants an unjournalled, index-blind rename, and the synchronous session-free write door that
   would want one is exactly what ADR-0043 deleted.
9. **Delete the eighteen tests along with the methods.** Rejected outright - CLAUDE.md's rule,
   and independently the right call: their assertions are about `renamePlan`'s arithmetic and
   about what a rename leaves on disk, both of which survive the deletion and are re-pointed at
   §D6.

---

## Consequences

### Positive

- No `VaultPlanApplication.apply` call site in the repository writes through an unguarded
  `store.write` after this chain. The note half and the board half of one gesture now answer
  alike, and the next writer inherits the precondition instead of needing to remember it.
- A note another process deleted mid-gesture is no longer silently re-created with stale text
  (§D1, ADR-0046 §D8's behaviour reaching its last three call sites).
- `NoteFileOperations.swift` loses its second implementation of note rename, a verbatim
  duplicate of `danglingLinks`, and the last unguarded `.canvas` byte write on any rename or
  move path - the sixth writer ADR-0054 §D6 could not reach because nothing called it.
- The repository has exactly one answer to «what renames a note here», which is what makes the
  journal, index, star and self-write-hash invariants properties of the code rather than of
  which method somebody happened to call.
- Two inaccurate claims in the project's own record are corrected rather than left to mislead:
  `VaultPlanApplication.swift:16-21`'s enumeration of which callers can populate `refusals`,
  and ADR-0054 §D8's «`syncOpenNote`'s conflict prompt never sees it», which is true only for a
  dirty tab that is not the focused note (§Context).
- A real, narrower defect is named and filed instead of being absorbed into a sentence nobody
  checks: `VaultController.reconcile` handles only `openNote` (§D5).

### Negative

- A board rename can now end with some notes' markers rewritten and others refused, where
  before it always ended fully applied - by overwriting somebody else's write to get there.
  Unlike the tag path, repeating the gesture does not finish the job (§D3), so the repair is
  manual and the report is what makes it possible.
- One extra read per guarded note write. A rename touches few notes and happens rarely; this is
  the cost ADR-0046 §D5 and ADR-0054 §D6 already accepted for the board half.
- Eighteen tests change file, subject or both. They assert the same things about the same
  bytes, but a reader following `git log` for «what pinned this rename» crosses one
  re-pointing to get there.
- Deleting three methods and a private helper is irreversible by nature. Everything they did is
  reachable through `renamePlan`/`movePlan`/`danglingLinks` plus `VaultSession`, and the
  deletion is behind a HITL gate, but «we might want a synchronous performer one day» is
  genuinely being answered with «no» here.
- The protection is against another process. An in-process writer cannot lose this race on
  these paths today, and if one ever could - if a future change makes a rename verb `async` -
  the guard is what will hold, but nothing in the test suite will have exercised that case
  until then.

### Neutral

- No on-disk format changes, no frontmatter key, no tag grammar, no `IndexCache.schemaVersion`
  bump (stays 4), no journal entry shape. A note written after this chain is byte-identical to
  one written before it for the same change.
- No connector surface changes. `NoteStore.swift` and `NoteFileOperations.swift` are both in
  `sharedSources`; the first gains one additive member and the second loses three members and a
  private helper that neither `perg` nor `pergamenum-mcp` ever called. `VaultAPI
  .FileMoveSummary` keeps its four keys, `scripts/mcp-smoke.py`'s expectations are untouched,
  and every `tools/list` name and schema is unchanged.
- No new file, no new dependency, no `Tuist/Package.swift` edit, no `Project.swift` edit. One
  new test file means `tuist generate --no-open`, nothing more.
- `VaultPlanApplication.Outcome` keeps its three fields and both overloads keep classifying
  identically. `failures`' string format is untouched, so
  `Tests/VaultPlanApplicationTests.swift:62-71`'s character-for-character assertion stands.
- ADR-0054's §D5 conflicted-board state, `BoardOrigin`, `CanvasDocument.reconcile` and
  `WorkspaceController` are not touched at all. This chain is entirely on the note side of the
  same gesture.

---

## Protected-interface proposal

**None.** The candidate is `NoteStore.writeGuarded(_:)`, on the theory that a call site
reverting to the bare `store.write` beside it is the hazard. It does not qualify, for the same
reason ADR-0046 declined to protect `VaultSession.write(_:to:expecting:)`:
`.claude/protected-interfaces` blocks a diff that changes a *signature*, and the hazard here is
a call site choosing a different, still-valid method - which that check cannot see. Protecting
it would buy nothing and would block the next chain that touches `NoteStore`.

---

## References

- `TODO.md` `PG-205` → issue #402, `PG-206` → issue #403; branch `fix/pg-205-206`.
- Plan: `docs/plans/pg-205-pg-206-note-write-guard.md`.
- ADR-0054 §D6 (`writeRepoint`, the one guarded repoint door), §D8 (the scope boundary this
  ADR closes), §D3 (in-process atomicity, and the async cascade that rejects routing through
  the session) - `docs/adr/0054-board-origin-marker-and-canvas-write-preconditions.md`.
- ADR-0046 §D1 (`expectedHash`), §D2 (no preflight), §D3 (a refusal never stops the loop),
  §D4 (`refusals` as its own channel, and the unqualified-typealias rule), §D6 (re-runnable
  versus not), §D8 (a vanished file is refused), §D11 (the writer seam) -
  `docs/adr/0046-batch-rename-stale-write-refusals.md`.
- ADR-0043 §D7 (a precondition before an `await` is a filter), §D8 (the opt-in precondition and
  its rejection of making it mandatory).
- ADR-0041 §D2/§D4/§D5 (a resolver rather than a skippable assertion; one apply-plan loop).
- ADR-0025 §D6, ADR-0022 §D6 (a board and folder verb is not journalled and is not reachable
  from a connector), ADR-0016 §D5 (the journal records a gesture), ADR-0012 §D6 (a star is a
  path).
- ADR-0001 §D3.4 (never merge, never discard: ask).
- `Sources/Vault/NoteStore.swift:137-162`; `Sources/Vault/VaultFileChange+ExpectedHash.swift:11`;
  `Sources/Core/Vault/VaultWriteRefusal.swift`; `Sources/Core/Vault/VaultPlanApplication.swift:11-51`.
- `Sources/Vault/BoardFileOperations.swift:126-177`; `Sources/Vault/FolderFileOperations.swift:146-160`,
  `:336-412`; `Sources/Vault/NoteFileOperations.swift:200-303`.
- `Sources/App/VaultController+Folders.swift:21-32`, `:41-63`, `:106-120`;
  `Sources/App/VaultController+Watching.swift:24-38`; `Sources/App/VaultController+Files.swift:18-34`.
- `Tests/NoteFileOperationTests.swift`, `Tests/NoteRenameCharacterizationTests.swift`,
  `Tests/VaultSessionFileOperationsTests.swift:186-266`, `Tests/BoardFileOperationsTests.swift:364-422`,
  `Tests/FolderFileOperationTests.swift:605-`, `Tests/CanvasStoreTests.swift`.
