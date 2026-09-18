# ADR-0050: The journal gesture travels with the task that writes, not with the session

- Status: proposed, implemented on the same branch (`281-bug-vaultsessiontransactions-current`);
  becomes accepted when that branch merges.
- Date: 2026-09-18. Written on the worktree
  `Pergamenum.worktrees/281-bug-vaultsessiontransactions-current` at `bc80495`, clean tree.
  Every signature, call-site count and line reference below was read out of that tree.
- **Numbering note:** `0049` is the highest under `docs/adr/` and no `0050` exists in any commit
  reachable from `git log --all`. Checked, not assumed.
- Source: GitHub issue **#281**, `TODO.md` **`PG-152`** (P3, correctness). Filed by ADR-0043
  («Implementation notes», item 3) and deliberately left open by ADR-0046 (§D10) and by the
  PG-161 fix, each on the same ground: «closing it properly means an actor-owned operation
  stack, which is a design decision and belongs in its own ADR». This is that ADR. It reaches a
  different shape than the one the issue sketched, and §"Alternatives" says why.
- **Extends ADR-0016 §D1 (the gesture) and ADR-0043 §D2 (the async body). Amends nothing.**
  The gesture keeps its meaning - one id on every write inside a `transaction`, so `undo` given
  that id reverses them all - and the body stays `async`. What changes is *where the id lives*
  for the duration.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format (the journal's line shape is
  untouched: `operation` and `command` are the same two strings, from the same source), no
  frontmatter key, no schema bump (`IndexCache.schemaVersion` stays at 4), no protected-interface
  signature, no JSON payload, no MCP tool surface. No test is disabled, skipped or deleted. Every
  existing test that reads `session.currentOperation` or `session.journalCommand` compiles and
  passes unchanged.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.

---

## Context

### The defect, read out of the code rather than the issue

`VaultSession.transaction(_:_:)` (`Sources/Vault/VaultSession+Journal.swift:40-52` at `bc80495`)
opened a gesture by assigning two instance properties of the `@MainActor` session -
`currentOperation` (the id) and `journalCommand` (the cause) - and closed it in a `defer` that
set the first to `nil` and restored the second to what it had been. The four write doors
(`write`, `writeFile`, `moveFile`, `trashFile`) read both properties at the moment they build
the journal entry or the `VaultDisk.JournalDescriptor` that crosses the actor hop.

Until ADR-0043, the body was synchronous and the scope held: nothing else could run on the main
actor between the assignment and the `defer`. ADR-0043 §D2 made the body `async` so its writes
could `await` the disk actor, and every `await` inside it is a point where the main actor is
handed back to the run loop. The properties stayed where they were. So:

1. Task A enters `transaction("note rename")`: `currentOperation = A`, `journalCommand = "note
   rename"`. Its first write suspends on `disk.write`.
2. Task B, started from a second `Task { }` (a second menu command, a drop, a connector call),
   enters `transaction("note move")` on the main actor. `currentOperation` is `A`, not `nil`.
   In Debug, `assertionFailure("transazione annidata…")` traps the process. In Release the
   guard's fallthrough runs B's body **under A's id and A's command**.
3. In Release, B's body finishes first; its `defer` does not run (the guard returned early), so
   nothing is restored - but had B entered a gesture of its own, its `defer` would have set
   `currentOperation = nil` while A was still open, and A's remaining writes would have carried
   no id at all.
4. `undo(A)` now reverses B's writes too, or misses half of A's. That is the failure a second
   `undo` completes (ADR-0016 §D1's own warning), reached without any programming error at
   either call site.

Three call sites open a gesture today (`VaultSession+Files.swift:26`, `:56`, `:77` - rename,
move, trash), each reachable from the app's menus, from a drag-and-drop, and from `perg`/
`pergamenum-mcp`. None of them is wrong. The scope is.

### What «nested» was ever meant to catch

The guard exists for a *lexically* nested transaction: a `renameNote` that, inside its own
gesture, called something that opened another. That is a programming error and the assertion is
the right answer to it. It was never meant to fire on two unrelated gestures the scheduler
happened to overlap - and it cannot tell the two apart, because a property on the session has no
idea which task set it.

### The three sibling borrowers, named so the reader does not go looking

`VaultSession+TagRename.renameTag` (`:79-85`), `+TaskDrop` (`:77-83`) and `+BoardDrop`
(`:69-75`) perform the same borrow-and-return by hand on `journalCommand` **and on `journal`
itself** around an `await`. They open no gesture (no `currentOperation`), so a second task
overlapping one of them cannot corrupt an `operation` id; it can mislabel a `command` and, for
the `journal` swap, can disarm the journal under the other task's write. That is the same
shape of hazard on a different property and is **out of this ADR's scope** (§D6), named there
as a follow-up rather than absorbed, for the same reason ADR-0043 declined to absorb this one.

---

## Decision

### §D1 — The gesture is a task-local value, bound by `transaction`, read by the write doors

A new `Sources/Core/Vault/JournalGesture.swift` declares

```swift
struct JournalGesture: Equatable, Sendable {
    let operation: String
    let command: String
    @TaskLocal static var current: JournalGesture?
}
```

`transaction(_:_:)` no longer assigns anything on the session. It builds one `JournalGesture`
and runs the body inside `JournalGesture.$current.withValue(gesture) { try await body() }`.
The binding is scoped to the body by the language, on the calling task: it is visible to every
`await` the body makes, to every structured child the body starts, and to every unstructured
`Task { }` created while it is bound (§D3), and it is invisible to every other task, however
many suspensions the body spans. There is no `defer` because there is nothing to undo: when
`withValue` returns - normally or by throwing - the binding is gone.

`currentOperation` becomes a read-only computed property, `JournalGesture.current?.operation`.
`journalCommand` becomes computed over a new private stored property,
`standingJournalCommand`: the getter returns the open gesture's command when the calling task is
inside one and the standing command otherwise; the setter always writes the standing command.
Every existing reader (the four write doors, `VaultAsyncCascadeTests`,
`VaultSessionJournalTests`) keeps its spelling and its meaning.

**Why `Sources/Core/Vault`.** The type is Foundation-only and `Sendable` by construction, so it
compiles into `perg` and `pergamenum-mcp` through the existing `Sources/Core/**` glob with no
`sharedSources` edit (CLAUDE.md, «AI connector»). It sits beside `VaultWriteRefusal`,
`VaultBoundary` and `VaultPlanApplication`: the other things the write path agrees on across
all three targets.

### §D2 — Two gestures open at once on two tasks are two gestures, not a nesting

With the id on the task, the interleaving in §"Context" reads: task A binds `A`; its write
suspends; task B binds `B` on its own task; B's writes carry `B` and `"note move"`; B's binding
ends; A resumes and its remaining writes carry `A` and `"note rename"`. `undo(A)` reverses A's
writes and only A's. Nothing was reset, because nothing was shared.

The nested-transaction guard stays, and becomes *exact*: `JournalGesture.current` is non-`nil`
on entry only if an enclosing `transaction` on this task's own tree bound it, which is the
programming error the assertion was written for. The Release fallthrough - run the body under
the gesture already open - is unchanged, for ADR-0016's reason: refusing a write the user asked
for is the worse wrong.

The command is fixed for the gesture's duration. Assigning `journalCommand` from inside a
transaction body lands on the standing command and is shadowed until the body returns. No call
site does this today (grep: every assignment is outside any `transaction`, in `VaultAPI.arm` and
the three borrowers of §"Context"); the doc comment on the property says so, so the next one
does not try.

### §D3 — What inherits the gesture, decided rather than discovered

Swift's rule, restated here so it is a decision of this ADR and not a fact the next reader has
to verify against the standard library: a task-local value is inherited by structured children
(`async let`, task groups) and **copied into an unstructured `Task { }` created while it is
bound**; `Task.detached` inherits nothing.

This ADR wants exactly that. A `Task { }` started *inside* a rename's body is part of the
rename: its writes belong to the gesture, and `undo` should reverse them with the rest. A `Task { }`
started from a menu handler, a drop delegate or an MCP request while some other task's rename is
suspended is *not* inside it, and does not inherit, because the creating context (the handler)
was never inside the binding. Both halves are pinned by tests (§D5).

### §D4 — `VaultDisk` is not involved

The issue's phrase «actor-owned operation stack» would have put the gesture on `VaultDisk`.
It stays off it. `VaultDisk` already receives, per write, a `JournalDescriptor` built on the
main actor with the caller's `command` and `operation` (ADR-0043 §D5, PG-161's §D5 fix); that
descriptor is built by reading the task-local at the call site, on the task that issued the
write, so it is correct by construction and the actor never needs to know what a gesture is.
Nothing in `VaultDisk.swift` changes.

### §D5 — Acceptance is a test that forces the interleaving, never a green suite

ADR-0043 §D9's rule, applied here. `Tests/VaultTransactionGestureTests.swift` forces the
overlap **deterministically**, with two one-shot gates on the main actor rather than with
timing: the first gesture writes, opens a gate, and holds itself open across an `await`; the
test then runs the entire second gesture to completion on a second task; only then releases
the first. The assertions are the ones §"Context" step 4 would fail: the first gesture's two
writes share one id and one command, the second gesture's write carries a different id and its
own command, `entries(operation:)` returns two and one, and `currentOperation` is `nil` at the
end.

**Run red before green, not inferred.** The same test file was run once against the two
`VaultSession*.swift` files exactly as they are at `bc80495`, with only `JournalGesture.swift`
added so it compiled. The interleaving test trapped the test process at
`VaultSession+Journal.swift:42` with `Fatal error: transazione annidata: «secondo» dentro
«primo»` - the Debug half of §"Context" step 2, verbatim - and the outside-task test recorded
four failed expectations: the write made outside any gesture carried the open gesture's id and
its command `"gesto"` instead of `nil` and the standing `"da sola"`, which is the Release half.
The three edge tests passed on both versions, as they should: they pin behaviour this ADR keeps,
not behaviour it changes. With the fix in place the whole `PergamenumTests` suite is green
(3210 tests), the five included.

Four more pin the edges: a write on the outside task while a gesture is open on another one
carries no id and the standing command; a `Task { }` started inside a gesture writes under it
(§D3); the standing command is untouched after a gesture and `currentOperation` is `nil`; a
body that throws still closes the binding and rethrows.

### §D6 — What this does not touch

Stated so a reader does not have to infer it.

- The three borrow-and-return sites on `journalCommand`/`journal` in `+TagRename`, `+TaskDrop`,
  `+BoardDrop` (§"Context"). Same hazard shape, different property, no `operation` id at stake.
  Converting them means deciding whether `journal` (the armed net) is also task-scoped, which
  changes what «armed» means for the connector's `VaultAPI.arm` and is its own decision. Filed as
  a follow-up, not absorbed.
- `VaultDisk` (§D4), the journal's line shape, `WriteJournal.makeID`, `undo`, the `expecting:`
  precondition (ADR-0043 §D8, ADR-0046), `VaultSession.read`'s synchronous signature (ADR-0043
  §D12), the five task views, the JSON Canvas format, `scripts/mcp-smoke.py`'s expectations, every
  `tools/list` name and schema.
- ADR-0043's «Implementation notes» item 3 and ADR-0046 §D10's line naming `PG-152` as open. Both
  are true of their date and are left as written; this file is the pointer forward.

---

## Alternatives considered

- **An operation stack owned by the session or by `VaultDisk` (the issue's sketch).** Rejected
  on the merits, not on cost. A stack answers the *nesting* question - which gesture is innermost
  - and nesting was never the failure. With two gestures open at once, the top of the stack is
  one of them, and a write from the other task still reads the top and still joins the wrong
  gesture; a `pop` from either task still pops whichever is on top. The information a write
  needs is *which task issued it*, and a stack on any shared object cannot carry that. Putting the
  stack on the actor adds a hop to every gesture open/close for no gain, since the actor's own
  queue interleaves the two tasks' operations exactly as the main actor did.
- **Pass the gesture explicitly through every write door** (`write(_:to:gesture:)`). Rejected: the
  gesture would have to be threaded through `VaultPlanApplication.apply`'s writer closures,
  `writeGuarded`/`writeFileGuarded`, and every helper a transaction body calls - the same
  transitive cascade ADR-0043 measured at ~210 sites, for a value the language already carries
  for free. It would also make «forgot to pass it» a new silent failure, the shape ADR-0041 §D6
  exists to remove.
- **Serialise transactions with an `AsyncSemaphore`/queue on the session, so two can never be
  open at once.** Rejected: it turns a labelling bug into a liveness one (a rename waits on a
  trash that waits on the disk), it changes user-visible ordering for no reason the user asked
  for, and it still leaves `journalCommand` mislabelled by the borrowers of §"Context". The fix
  should make the interleaving *unobservable*, not forbidden.
- **Keep the property and widen the guard to «if open on another task, start a second id
  anyway».** Rejected: there is no way to know «another task» from a property on the session,
  which is the whole finding.
- **Make `journalCommand` a task-local too and delete the stored property.** Rejected for this
  ADR: `VaultAPI.arm` sets the command once for a connector process and expects every write in
  that process to carry it; a task-local set in `arm` would be gone by the time the MCP server's
  request handler ran the write. The two-tier read (gesture first, standing command second) keeps
  `arm`'s contract and the three borrowers' contract intact while giving a gesture a command that
  cannot be overwritten from outside.

---

## Consequences

### Positive

- The interleaving `PG-152` describes cannot be observed: two gestures on two tasks each stamp
  their own id and command on their own writes, whichever order the main actor runs them in.
  `undo` given either id reverses exactly that gesture.
- The nested-transaction assertion stops being a false positive under concurrency and becomes an
  exact check for the programming error it was written for.
- `transaction` loses its `defer` and its borrow-and-return: the binding's own scope is the
  restore. Less state on the session, one less thing a future `async` edit can widen.
- No new surface for the connectors, no manifest edit, no schema bump, no on-disk change.

### Negative

- A task-local is inherited by an unstructured `Task { }` created inside a gesture (§D3). A
  future body that starts a fire-and-forget task *meaning* it to be outside the gesture will find
  it inside. That is the right default for a rename - and the doc comment on
  `JournalGesture.current` names `Task.detached` as the way to opt out - but it is a rule a
  reader has to know.
- `journalCommand` is now computed, and assigning it from inside a gesture body is shadowed until
  the body returns (§D2). No call site does that; the doc comment says not to.
- `currentOperation` is read-only. A test that used to assign it to simulate an open gesture
  cannot; none did.

### Neutral

- The three borrowers of §"Context" keep their hand-rolled borrow-and-return on `journalCommand`
  and `journal`. They are neither better nor worse than before this ADR.
- ADR-0043's five deterministic interleaving tests and `scripts/adr-0043-interleaving-check.sh`
  are untouched and still green.

---

## Protected-interface proposal

None. `JournalGesture` is internal plumbing with three readers, all in `Sources/Vault`; nothing
outside the module, and neither connector's JSON, depends on its shape.

---

## References

- GitHub issue #281; `TODO.md` `PG-152`.
- ADR-0016 §D1 (the gesture, `operation` on the journal entry), §D6 (the transaction).
- ADR-0041 §D9 (the async write door this hazard first became reachable through).
- ADR-0043 §D2 (the async body), §D5 (the journal «before» read inside the actor), §D9 (the
  acceptance rule this ADR's §D5 applies), «Implementation notes» item 3 (where `PG-152` was
  filed).
- ADR-0046 §D10 (left open there on purpose); PG-161 / issue #289 (the `JournalDescriptor` the
  task-local is read into, §D4).
- `Sources/Core/Vault/JournalGesture.swift`, `Sources/Vault/VaultSession.swift`
  (`journalCommand`, `currentOperation`), `Sources/Vault/VaultSession+Journal.swift`
  (`transaction`), `Tests/VaultTransactionGestureTests.swift`.
