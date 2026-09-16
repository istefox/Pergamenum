# ADR-0046: A batch rename refuses the file that moved on, one file at a time, and says which

- Status: accepted (see the plan at `docs/plans/pg-154-tag-rename-note-rename-batch-scope-write-guard.md`)
- Date: 2026-09-15. Written on the worktree `Pergamenum.worktrees/263-tag-rename--note-rename-batch-applie`
  at `43f8321`, clean tree. Every line number, signature and call-site count below was read out of
  that tree, not recalled from the issue text or from ADR-0043's own prose.
- **Numbering note:** `0045` is the highest under `docs/adr/` and no `0046` exists in any commit
  reachable from `git log --all`. Checked, not assumed.
- Source: GitHub issue **#263**, `TODO.md` **`PG-154`** (P3, correctness). The issue body is the
  whole specification. The `SPEC.md`/`BRAINSTORM.md`/`UX-BLUEPRINT.md` in the repository root
  belong to ADR-0043's own completed chain and are disregarded here.
- **Extends ADR-0043 §D8. Amends nothing.** §D8's mechanism — `write(_:to:expecting:)` and
  `WriteRefusal.movedOn` — is used exactly as it was designed, at four call sites §D8's own
  adoption grep deliberately declined (ADR-0043, «Implementation notes», «Declined, with
  reasons»: «the tag-rename and note-rename batch appliers, whose refusal granularity is a
  half-renamed vault»). This ADR decides that granularity.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key, no tag grammar,
  no schema bump (`IndexCache.schemaVersion` stays where ADR-0041 left it), no protected-interface
  signature, no JSON payload shape (`VaultAPI.FileMoveSummary` keeps its four keys), no MCP tool
  surface. No test is disabled, skipped or deleted.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.
- Registered and not re-litigated: **ADR-0043** (§D5 the journal's «before» is read where the bytes
  land, §D7 a precondition before an `await` is a filter, §D8 the opt-in hash precondition, §D9's
  acceptance rule and its `PG-152` residual hazard), **ADR-0041** (§D4/§D5 one apply-plan loop,
  §D9/§D10/§D11 the async write door, the pre-hop hash and the per-path sequence), **ADR-0026 §D6**
  (all-or-nothing is a property of the *decision*, not of the execution), **ADR-0016 §D5/§D6** (the
  gesture, and undo's all-or-none), **ADR-0007 §D6** (the three write guardrails, and the rule that
  a write which did nothing and said nothing is the failure), **ADR-0012 §D7** (the tag rename and
  its group undo).

---

## Context

`VaultSession+TagRename.renameTag` and `VaultSession+Files.renameNote`/`moveNote` each compute a
plan — a list of `VaultFileChange(path, before, after)` — and then hand it to
`VaultPlanApplication.apply`, whose writer closure calls the vault's one write door. Every `after`
in that list is a pure function of the `before` beside it. Neither applier tells the write door so:

```swift
// VaultSession+TagRename.swift:81
let result = await VaultPlanApplication.apply(fileChanges) {
    try await write($0.after, to: $0.path)          // no `expecting:`
}
// VaultSession+Files.swift:26 and :32
let notes  = await VaultPlanApplication.apply(plan.noteChanges)  { try await write($0.after, to: $0.path) }
let boards = await VaultPlanApplication.apply(plan.boardChanges) { try await writeFile($0.after, to: $0.path) }
```

So a note that changes after its `before` was read is overwritten with text derived from bytes that
are no longer on disk. The edit is gone and nothing says so — ADR-0007 §D6's named failure mode,
and precisely the read-modify-write straddling a suspension that ADR-0043 §D8 built `expecting:`
for.

### Where the window actually is, measured rather than assumed

This matters because it decides between the two candidate designs, and the intuitive answer is
wrong.

`tagRenamePreview` (`VaultSession+TagRename.swift:39-54`) reads every affected note
**synchronously**, on the main actor, with no suspension inside the loop. `renameTag` calls it at
`:64` and reaches the first `await write` at `:81` with no suspension in between. `renamePlan`
(`NoteFileOperations.swift:80-122`) is likewise synchronous, and `renameNote` reaches its first
suspension at `await moveFile` (`VaultSession+Files.swift:24`) — one hop after the plan.

Therefore:

- **The window between the plan and the *first* write is, in-process, empty.** No other main-actor
  job can run there. Only a second process — Obsidian, `perg`, `pergamenum-mcp` on the same vault —
  can write in it, and only inside a window of microseconds.
- **The window that matters opens *inside* the loop.** Every `await write` in the batch hands the
  main actor back to the run loop. The editor's save, a task write, a timeblock write, a pratiche
  sync or the watcher's reconciliation can all run between file 3 and file 4, and file 7's `before`
  — read before any of it — is by then arbitrarily old. The batch is its own race window, and it
  widens with every file in it.
- The sheet the person confirms is **not** part of that window: `renameTag` recomputes the preview
  itself at apply time (`:64`), so the bytes it writes are derived from a read taken after the
  button was pressed, not from the ones the sheet drew. The intent the person approved is «rename
  this tag», not «write these exact bytes», and re-reading is the correct reading of it. Nothing in
  this ADR changes that.

### What `VaultController.canOperate(on:)` does and does not cover

`VaultController+Files.swift:18-29` refuses a rename while *the renamed note* has a dirty tab. It
does not reach the N link-rewrite notes of a rename, it does not exist at all on the tag-rename
path, and it is evaluated before an `await` — ADR-0043 §D7's filter, not a guard. It is not the
answer here and is left exactly as it is.

### What the batch already collects

`VaultPlanApplication.Outcome` is `{rewrittenPaths, failures}` and the loop never stops on a throw
(`VaultPlanApplication.swift:16-37`): «the changes are independent files and a rename that gave up
halfway would leave the vault half-rewritten with nothing said about the rest». The failure string
format `"\(change.path): \(error)"` is pinned character-for-character by
`Tests/VaultPlanApplicationTests.swift:62-71`.

`VaultSession+Move.MoveBatchOutcome` (`:24-51`) already draws, for the batch *move*, the exact
distinction this ADR needs for the batch *rename*: `refusals` is «the batch could not commit at
all», `failures` is «this item passed every pre-write rule and then failed on disk», and its doc
comment states the rule this ADR follows — «the all-or-nothing of §D6 is a property of the
decision, not a promise the file system can be held to once the writing has started».

---

## Decision

### §D1 — All four batch writer closures adopt `expecting:`

`renameTag`'s note writer, `renameNote`'s note writer, `renameNote`'s board writer and `moveNote`'s
board writer each pass the hash of the `before` their `after` was computed from:

```swift
try await write($0.after, to: $0.path, expecting: $0.expectedHash)
```

`expectedHash` is `NoteStore.hash(Data(before.utf8))` — the same expression `VaultDisk.write`
compares against (`VaultDisk.swift:208-213`, `store.text` → `Data(text.utf8)` → `NoteStore.hash`),
so the two sides of the comparison are computed the same way by construction. It is declared once,
as `extension VaultFileChange { var expectedHash: String }`, not spelled four times: a second copy
of the hashing rule is a second place for it to stop matching `VaultDisk`'s.

This is ADR-0043 §D8 used exactly as designed. No new precondition primitive is built.

### §D2 — There is no batch preflight pass, and this is the decision the issue's question 2 turns on

The tempting design — read every path, compare every hash, and refuse the whole batch before
writing a byte — is rejected, and it is rejected on ADR-0043 §D7's own reasoning rather than on
cost.

A preflight sits on the far side of N suspension points from the writes it claims to guard. As
measured in Context, the window it *can* see (plan → first write) is in-process empty, and the
window the refusals will actually come from (write *k* → write *k+1*) is one it cannot see at all.
It would therefore pass, the loop would start, and a refusal would arrive from inside the loop
anyway — leaving exactly the partial batch the preflight was sold as preventing, plus a full extra
read of every file in the batch, plus a reader who now believes the operation is atomic. **A check
that is evaluated before the `await` it protects is a filter, not a guard** (ADR-0043 §D7, quoted in
CLAUDE.md's working agreements). Buying the appearance of atomicity without the substance is worse
than not buying it, because it stops anybody looking.

### §D3 — A refusal does not stop the loop, and nothing already written is rolled back

The loop continues, as it does today: the remaining files are independent, their renames are wanted,
and stopping would enlarge the un-renamed remainder for no benefit.

Nothing is rolled back either. The machinery to do it does exist and would even work —
`undoJournalledWrites` (`VaultSession+TagRename.swift:108`) refuses the group only if a member's
current hash no longer matches its journal entry's `hashAfter`, and the members of a
partially-refused batch were just written, so `preflightUndo` would clear them. It is refused on
merits, not on feasibility:

1. It discards work the person explicitly asked for — thirty-eight correct renames undone on
   account of two unrelated notes — to protect content the rename never touched.
2. A rollback is itself N writes that can fail. A rollback that fails halfway has no third level to
   fall back to and leaves a state no journal group describes: strictly worse than the state it was
   trying to improve.
3. The undo already exists as an *offer*, not an automatism: ADR-0012 §D7's banner, still on
   screen, with the journal ids of exactly what was written. Whether to take it is the person's
   decision, and this ADR does not make it for them.

The batch is therefore all-or-nothing in its **decision** and best-effort in its **execution** —
ADR-0026 §D6's rule, applied to the other batch verb.

### §D4 — A refusal is a distinct channel, not another failure string

`VaultPlanApplication.Outcome` gains a third collection:

```swift
struct Outcome: Equatable, Sendable {
    var rewrittenPaths: [String] = []
    var failures: [String] = []
    var refusals: [String] = []     // paths whose bytes moved on; never written
}
```

Both overloads classify identically: a caught `WriteRefusal` appends `change.path` to `refusals`,
every other error appends `"\(change.path): \(error)"` to `failures` as before. `failures`' format
is untouched, so no existing assertion changes (`Tests/VaultPlanApplicationTests.swift:62-71`), and
the synchronous overload's eight `store.write`-level callers simply never populate `refusals`,
because `store.write` cannot throw that error.

The distinction is not cosmetic. «This note could not be written» and «this note changed under me,
so I did not write it» have different causes, different Italian sentences and — per §D6 — different
severities; `VaultController+Files.swift:42` currently prints one sentence for anything in
`failures`, and a refusal read through that sentence («link non aggiornato in …») would name the
symptom while hiding the cause.

**`WriteRefusal` moves to `Sources/Core/Vault/` to make that classification possible.** `apply`
lives in `Sources/Core` and cannot catch a type declared in `Sources/Vault`. The enum is a path and
a sentence with no `VaultSession` dependency, so it moves out as a top-level `VaultWriteRefusal`
and `VaultSession` keeps a nested `typealias WriteRefusal = VaultWriteRefusal`. All fifteen existing
references — `catch let refusal as VaultSession.WriteRefusal` in six files, `catch is …` in four,
`throw VaultSession.WriteRefusal.movedOn` in `VaultDisk`, two in `Tests` — compile unchanged. The
alias is written unqualified on purpose: a module-qualified `Pergamenum.WriteRefusal` would not
compile in the `perg` and `pergamenum-mcp` targets, which compile these same files under a
different module name (CLAUDE.md, «AI connector»).

The alternative of adding a seventh apply loop under `Sources/Vault` to avoid touching Core is
rejected: ADR-0041 §D4/§D5 deleted six copies of that loop, and adding one back to dodge a
ten-line type move would undo that.

### §D5 — `writeFile` gains the same opt-in precondition, for the board half

`renameNote` and `moveNote` write `.canvas` documents through `writeFile`
(`VaultSession+Journal.swift:156`), which has no precondition at all, so without this the board half
of a note rename stays unguarded and §D1 would be half a decision. `writeFile` and
`VaultDisk.writeFile` both gain `expecting: String? = nil`, and the comparison happens **inside the
actor**, immediately before `store.write`, where no suspension can separate the read from the write.

`VaultDisk.writeFile` currently performs no read at all, so unlike §D8's note path this costs one
extra read per guarded board write. A rename touches few boards and happens rarely; the cost is
accepted rather than engineered around.

**What this deliberately does not do:** `VaultSession.writeFile` still reads its journal «before» on
the main actor before the hop (`:157-159`), which is ADR-0043 §D5's Race 2 shape surviving on the
non-note door — §D5 moved that read inside the actor for `write` only. It is a real finding, it is
**not** fixed here, and it is filed as its own follow-up. Folding it in would change what the
journal records for every board write in the app, which is a decision about the journal and not
about batch renames. Adding `expecting:` in front of it introduces no new inconsistency: a refusal
throws before any write, so a stale `existing` is discarded with everything else.

### §D6 — The two appliers share the mechanism and diverge in consequence, because one is re-runnable and the other is not

Same `expecting:`, same `refusals` channel, same no-rollback rule. What differs is what a refusal
*means*, and the sentences and severities follow from that:

- **`renameTag` is idempotent and re-runnable.** Running it again on a partially renamed vault
  computes a fresh preview and renames exactly the remainder; nothing is applied twice, nothing is
  lost. A refusal is therefore fully recoverable by repeating the gesture, and the honest report is
  a count plus the paths: «2 cambiate durante la rinomina».
- **`renameNote` is not.** Once the file has moved, `oldTitle` is derived from the *new* file name
  (`NoteFileOperations.swift:88`), so a second `renameNote` computes `from: X, to: X`, rewrites
  nothing, and the links that were refused stay stale permanently. A refusal there is a wikilink.md
  W-08 breakage that the person cannot repair by repeating the gesture, so it is reported as a
  problem naming the note and the cause, not as a count.

`moveNote` sits with `renameNote` — same shape, boards only, no note text (a wikilink names a note
by title, not by path). The asymmetry is stated here rather than discovered later, because a future
reader looking at two appliers with one mechanism and two report styles would otherwise read it as
drift.

### §D7 — The UI boundary: two named surfaces, no new dialog, no new setting

This does not stop at the `VaultSession` API. The outcome shapes carry what a caller needs, but two
existing surfaces would misreport a refusal if left alone, and one of them would misreport it as a
success:

1. **`TagBrowserView`** (`:302-316`, `:69-80`, `:348-375`) — the banner gains the refusal count with
   the paths in its `.help`, beside the existing «N non scritte». And «Annulla la rinomina» is
   hidden when `journalIDs` is empty: with every note refused, today's banner offers to undo a
   rename that never happened, and `undoJournalledWrites([])` answers success. That button becomes
   reachable for the first time through this change, so hiding it belongs to this change.
2. **`VaultController.renameNote`** (`:42-44`) — refusals get their own sentence instead of «link
   non aggiornato in …». `VaultController.moveNote` (`:56-70`) reads neither `failures` nor
   `refusals` today: its board-repoint failures are dropped on the floor. That is a pre-existing
   gap, it is one line, and leaving it would make the new channel dead on arrival in that path, so
   it is closed here and named as beyond the issue's literal ask.

Nothing else is UI: no new sheet, no confirmation, no retry button, no preference. `TagRenameSheet`
is untouched.

### §D8 — A file that vanished mid-batch is refused, not re-created

`VaultDisk.write` compares `hashBefore` (`String?`) with `expecting`; a path with no file yields
`nil`, which equals no hash, so the write is refused. Today a tag rename **re-creates** a note
deleted or moved between the preview and its turn in the loop, because `write` creates what is not
there. Under §D1 it refuses and names it. This is a behaviour change, it is wanted, and it is
recorded here so it is not read later as a regression.

### §D9 — A dry run still refuses nothing for staleness

`write` short-circuits before the actor when `isDryRun` (`VaultSession.swift:500`), which is
ADR-0007 §D6's first guardrail, so the precondition — which lives inside the actor — is never
evaluated on a rehearsal. A `perg --dry-run note rename` therefore reports what the real run would
do *absent* a concurrent writer. This is the property §D8's existing thirteen call sites already
have, it is not made worse here, and it is stated rather than silently inherited: a rehearsal's
whole window is synchronous, so there is nothing for it to observe anyway.

### §D10 — What this does not touch

- `FolderFileOperations` and `BoardFileOperations`' five synchronous apply loops, and
  `NoteFileOperations.rename`'s own two (`:224`, `:230`). They write through `store.write`, outside
  the journal and outside the async write door; there is no `expecting:` on that path to adopt.
  Their `refusals` stays empty. Bringing them in means bringing them through `VaultSession` first,
  which is the older debt `VaultSession+TagRename.swift:8-9` already names.
- `moveFile`'s own `exists`/`!exists` checks (`VaultSession+Journal.swift:63-66`) — a §D7 filter,
  left alone: `FileManager.moveItem` refuses an occupied destination natively, and a vanished source
  throws `FileOperationError` before any write in the batch.
- `transaction(_:_:)`'s `currentOperation` spanning a suspension — ADR-0043 §D9's `PG-152`, still
  open, still not patched blind here.
- `VaultSession.read`'s synchronous signature (ADR-0043 §D12), the index schema, the journal entry
  shape, the five task views (ADR-0013 §D6), the JSON Canvas round-trip, `scripts/mcp-smoke.py`'s expectations, and
  every `tools/list` name and schema.

### §D11 — Acceptance is a test that forces a refusal at the writer seam, never a green suite

ADR-0043 §D9's rule, applied to this change. The refusal is forced **deterministically, without
relying on interleaving**: a test builds a `[VaultFileChange]` whose `before` deliberately disagrees
with the bytes on disk and drives it through the same production writer the appliers hand to
`VaultPlanApplication.apply`. That is the shape ADR-0043 §D9 itself prescribes — «it calls `apply`
directly to force an inversion deterministically rather than hoping a timing test reproduces one».

No timing-based interleaving test is written, and the reason is ADR-0043's own: «Swift publishes no
guarantee that an actor executes enqueued jobs in enqueue order» (Alternatives considered). A test
that enqueues a competing `Task` and expects it to land between file *k* and file *k+1* would be
asserting on exactly that non-guarantee. To keep the seam drivable, the writer both appliers use is
named — an internal function on `VaultSession`, not an anonymous closure — so the test drives the
production code path rather than a re-spelling of it.

---

## Alternatives considered

**Preflight the whole batch, refuse it entirely if any file moved on, write nothing.** Rejected;
reasoned in full at §D2. In one line: it guards the one window that is empty and cannot see the one
that is not, so it delivers the appearance of atomicity and none of it. This was the issue's own
third candidate and the one that looked most attractive before the suspension points were counted.

**Roll the batch back through `undoJournalledWrites` when any file refuses.** Rejected; reasoned at
§D3. It is technically available — and that is why it is answered on merits rather than dismissed —
but it discards work that succeeded to protect content the operation never touched, and a rollback
that fails midway has no further net.

**Stop the loop at the first refusal and report what is done so far.** Rejected. It converts one
refused file into an arbitrarily large un-renamed remainder, for no gain: the remaining files are
independent of the refused one, their `before` is no more stale than it was a millisecond earlier,
and the person's intent covers them. It would also contradict `VaultPlanApplication.apply`'s
documented contract (`:19-22`), which six deleted loops all shared.

**Do nothing: accept the clobber, since the window is narrow.** Rejected, and it was a live option —
the issue is filed P3 and the mechanism has been available since ADR-0043 without these call sites
adopting it. It loses because the window is not narrow: it is the whole duration of a forty-note
batch, it is widest exactly when the operation matters most, the thing it destroys is a person's
edit to a note they are looking at, and the loss is silent. ADR-0007 §D6 names that combination as
the failure the guardrails exist for.

**Make `expecting:` mandatory on `write`, so no batch can forget it.** Rejected, and it is ADR-0043
§D8's own rejection, unchanged: every blind write — a new note, a template, a restore from history,
a connector «make the file say this» — would become a failure path its caller is not written to
handle, for a hazard it does not have.

**Add a second, guarded apply loop under `Sources/Vault` instead of extending the Core one.**
Rejected at §D4: ADR-0041 §D4/§D5 exists to have exactly one of these loops, and a seventh added to
avoid moving a ten-line enum would undo that deliberately.

**Re-read and retry the refused files automatically once the batch finishes.** Rejected. Recomputing
`after` from the new `before` and writing it is the clobber again, one step removed and now
invisible to the person, since the retry would succeed and report nothing. For `renameTag` the
person can re-run the gesture themselves and get exactly this, knowingly; for `renameNote` a retry
cannot work at all (§D6). A guard whose remedy is to try again without asking is not a guard.

---

## Consequences

### Positive

- The four highest-fan-out writers in the app stop being able to silently destroy a concurrent edit.
  A tag rename over forty notes is the largest single batch of writes this app performs, and it was
  the only one still writing blind.
- A note deleted or moved during a batch is no longer silently re-created (§D8).
- The report gains a cause, not just a count: `refusals` tells a caller «this changed under me» in a
  form it can branch on, in the same shape `MoveBatchOutcome` already uses for the batch move, so
  the two batch verbs answer alike.
- A real bug becomes unreachable at the same time: the «Annulla la rinomina» button offered after a
  rename that wrote nothing (§D7).
- `WriteRefusal` in `Sources/Core/Vault/` puts the refusal beside `VaultFileChange` and
  `VaultPlanApplication`, which is where the batch vocabulary already lives.

### Negative

- A tag rename can now end partially applied where before it always ended fully applied — by
  overwriting somebody's edit to get there. The person must re-run it to finish. This is the trade
  the ADR makes deliberately, and §D6's re-runnability is what makes it acceptable for the tag path
  and not merely tolerable.
- A refused link rewrite during a *note* rename leaves a stale wikilink that repeating the gesture
  cannot fix (§D6). It is reported, and repairing it is manual.
- One extra read per guarded board write (§D5).
- Fifteen references to `VaultSession.WriteRefusal` now resolve through a typealias, which is one
  more indirection for a reader following the type to its declaration. The alias exists so that the
  move costs no call-site churn; the cost is paid in that indirection.
- `VaultSession`'s batch writer becomes a named internal function so a test can drive it (§D11) —
  production shape adjusted for testability, in the narrowest way that avoids a test-only parameter
  on a public verb.

### Neutral

- No on-disk change, no schema bump, no format change, no new dependency, no new file in
  `sharedSources` beyond the two named in the plan, no network.
- The connectors' JSON is unchanged: refusals are folded into `FileMoveSummary.failures` with their
  own sentence rather than adding a key, so `perg note rename --json` and the MCP `note_rename`
  tool answer the same shape they always did.
- A dry run behaves exactly as before (§D9).
- The synchronous `apply` overload gains a `refusals` field that its eight callers can never
  populate. Carried anyway, because one `Outcome` type with two contracts is the drift this
  codebase keeps refusing.

---

## Protected-interface proposal

**None.** The candidate is `VaultSession.write(_:to:expecting:)` — an argument whose omission at a
call site looks like a simplification, which is the shape ADR-0041 used to justify protecting
`VaultBoundary.url(for:)`. It does not qualify: `.claude/protected-interfaces` blocks a diff that
changes a *signature*, and the hazard here is a call site quietly dropping an argument the signature
still offers, which that check cannot see. Protecting it would buy nothing and would block the next
chain that touches the write door. ADR-0043's own deferred proposals stand as they are.

---

## References

- ADR-0043 §D5, §D7, §D8, §D9 and «Implementation notes» §1's Decline list —
  `docs/adr/0043-vault-write-ordering-concurrency-races.md`
- ADR-0041 §D4, §D5, §D9, §D10, §D11 — `docs/adr/0041-vault-layer-consistency-and-security-cha.md`
- ADR-0026 §D6 — `docs/adr/0026-drag-and-drop-board-files-into-workspace.md`
- ADR-0016 §D5, §D6 — `docs/adr/0016-the-journal-records-a-gesture.md`
- ADR-0012 §D7 (tag rename, group undo) and ADR-0007 §D3, §D6
- `Sources/Core/Vault/VaultPlanApplication.swift:11-14`, `:16-37`, `:56-71` — the outcome and both loops
- `Sources/Core/Vault/VaultFileChange.swift:12-16`
- `Sources/Vault/VaultSession.swift:497-550`, `:560-569` — the write door and `WriteRefusal`
- `Sources/Vault/VaultDisk.swift:197-250`, `:260-267` — the precondition, and the unguarded `writeFile`
- `Sources/Vault/VaultSession+TagRename.swift:39-54`, `:63-92`, `:108-131`
- `Sources/Vault/VaultSession+Files.swift:16-46`, `:48-67`
- `Sources/Vault/VaultSession+Journal.swift:61-100`, `:156-186`, `:220-262`
- `Sources/Vault/VaultSession+Move.swift:24-51`, `:81-157` — `MoveBatchOutcome`'s refusals/failures split
- `Sources/Vault/NoteFileOperations.swift:42-49`, `:80-122`, `:127-139`
- `Sources/App/VaultController+Files.swift:18-29`, `:38-54`, `:56-70`
- `Sources/Features/Tags/TagBrowserView.swift:69-80`, `:302-334`, `:348-375`
- `Sources/Connector/VaultWrites.swift:99-140`; `Sources/Connector/VaultPayloads.swift:192-197`
- `Tests/VaultPlanApplicationTests.swift`, `Tests/TagRenameTests.swift`,
  `Tests/VaultSessionFileOperationsTests.swift`, `Tests/VaultWriteOrderingBatch3Tests.swift:200-235`
- GitHub issue #263; `TODO.md` `PG-154`

---

## Implementation notes (chain 2026-09-15)

Appended by the implementation chain whose plan is
`docs/plans/pg-154-tag-rename-note-rename-batch-scope-write-guard.md`. **Nothing above is altered.**
Four things the plan measured or found beyond what §D1–§D11 wrote down, in the order they surfaced.

### 1. §D4's fifteen-reference count, re-measured

Grepped on the finished tree rather than recalled: sixteen pre-existing `VaultSession.WriteRefusal`-
qualified call sites (`catch let refusal as …` in `PraticaEntryComposer.swift` ×2,
`PraticaLiveSync.swift` ×2, `DossierWriter.swift`, `PraticaCommandActions.swift`,
`RecordingsController+Import.swift`; `catch is …` in `VaultSession+TimeBlocks.swift`,
`VaultSession+Tasks.swift` ×3, `VaultWrites.swift`; `throw … .movedOn` in `VaultDisk.swift`; two in
`Tests/VaultWriteOrderingBatch3Tests.swift`, two in `Tests/VaultSessionJournalTests.swift`), one more
than §D4's own count. All sixteen compiled unchanged against the `typealias`, exactly as predicted;
the discrepancy is bookkeeping, not a missed call site.

### 2. `VaultSession+Journal.writeFile`'s catch-all would have swallowed the new type

§D5 widens `VaultDisk.writeFile`'s precondition but does not spell out the forwarding shape at
`VaultSession+Journal.swift`'s own `writeFile`, which already wraps every `VaultDisk` error into
`FileOperationError` through a catch-all. Left as a plain forward, that catch-all would have caught
`VaultWriteRefusal` too, so every board refusal would have landed in `VaultPlanApplication.Outcome
.failures` as an ordinary error instead of `.refusals` — §D4's whole distinction, defeated silently
for exactly the writer §D5 exists to guard. Fixed with an explicit `catch let refusal as
VaultWriteRefusal { throw refusal }` ahead of the catch-all, mirroring the shape `VaultSession.write`
already has for the same reason.

### 3. Widening `writeFile` broke a cascade test through a Swift default-parameter trap

`Tests/VaultAsyncCascadeTests.swift` captures `session.writeFile` as a bare function value through a
variadic-generic cascade helper. Swift's default-argument sugar (`expecting: String? = nil`, §D5)
does not survive a method captured as a closure value rather than called directly, so widening the
signature left that one call site short an argument. Not named in §D5 or in ADR-0043's own §D2
cascade measurement, since it is specific to widening a signature a test already captured this way,
not to the async cascade itself. Fixed by passing `nil` explicitly at the one call site.

### 4. §D11's seam recurs three calls further out than the writer, and two of the three cannot be closed

Task 5 asked for a deterministic case proving a refusal reaches `FileMoveSummary.failures` with its
sentence (`Tests/ConnectorTests.swift`) and for the `moveItems` report path
(`Tests/VaultMoveTests.swift:264`'s neighbourhood); Task 6 asked `Tests/TagBrowserTests.swift` for
the same at the browser's boundary. All three inherit §D11's own constraint — the plan-then-write
window is empty in-process — one or more calls further from the writer than `writeGuarded`/
`writeFileGuarded` sit, and none of the three exposes an injectable plan to force a genuine refusal
through:

- `VaultAPI.renameNote`/`moveNote`'s fold (`outcome.failures + outcome.refusals.map { … }`) was
  extracted into one named, testable `VaultAPI.foldedFailures(_:)` — the same "production shape
  adjusted for testability" move §D11 already made for the two guarded writers — and driven directly
  with a hand-built `NoteFileOperations.Outcome` in `Tests/ConnectorTests.swift`.
- `VaultSession+Move.swift`'s `moveItems` has no equivalent seam: `report(_:)` is a private,
  one-line-per-item `recordProblem` call already proven correct by the adjacent, untouched
  `report(note.failures)` assertions, and `report(note.refusals)` calls that same function with a
  field `Tests/VaultSessionFileOperationsTests.swift`'s Task 4 tests already prove `moveNote`
  populates correctly. No test was added to `Tests/VaultMoveTests.swift` for this one line — the two
  already-proven pieces compose, and a third, integration-level test cannot be written without racing
  a concurrent `Task`, which §D11 forbids by name.
- `TagBrowserView`'s `FinishedRename`/`TagRenameBanner`/`perform(renameOf:to:)` stay `private`, and
  standing rule 8 for this chain added no UI test. `Tests/TagBrowserTests.swift` instead pins
  `VaultController.renameTag`/`undoJournalledWrites` — the view's only source for `refusals` — as the
  bare pass-through of `VaultSession.TagRenameOutcome` it is, so a future change that starts
  reconstructing the outcome there and drops the field fails here rather than only on screen.
