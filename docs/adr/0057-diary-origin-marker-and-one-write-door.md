# ADR-0057: The diary proves what it writes over, one write at a time

- Status: proposed, on the branch `kepler/fix-262-readdiary-writediary-race`. Accepted when that
  branch merges to `main`.
- Date: 2026-09-24. Written on the worktree `Pergamenum-fix-262-readdiary-writediary-race-c08eafa6`
  at `e61dbe2b` (clean tree). Every signature, line number and call-site list below was read or
  grepped in that tree, not recalled.
- **Numbering note:** `0056` is the highest file under `docs/adr/`, and
  `git log --all --oneline -- 'docs/adr/0057*'` returns nothing, so no `0057` exists in any commit
  reachable from a local ref. Checked, not assumed. A parallel worktree that has not pushed yet is
  outside what that check can see.
- Source: `TODO.md` **`PG-153`** (P3, correctness, opened 2026-09-14) → issue **#262**. Filed by
  ADR-0043's implementation notes (item 1, the «Declined» list) as a window «wider than §D8 can
  close», and left there as an open design question. This is that design.
- **Extends ADR-0043 §D8** (the opt-in `expecting:` precondition, adopted at the one call site its
  adoption list declined, plus a creation-case sibling), **applies ADR-0052 §D1/§D3 and ADR-0054
  §D2/§D5** (an in-memory document records which file it came from; a refused save is a named,
  non-modal conflict resolved only by a choice) to a third holder, and **extends ADR-0005 §D7**
  («it saves itself … flushed when the day changes») with one condition: the day is left once
  that flush has landed, and not at all while it is conflicted. It amends none of them.
- **Reopens nothing else.** No SPEC §14 decision, no on-disk format (the diary file is
  byte-identical to what it was for the same prose and entries), no frontmatter key,
  `IndexCache.schemaVersion` stays 4, no protected interface (`.claude/protected-interfaces`
  names none of the symbols touched). No test is disabled, skipped or deleted.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.
- **GUI-test budget: zero.** Every decision below is observable on `DiaryController`,
  `VaultSession` and `VaultDisk` in-process, and the races are forced with gates (§D9). The GUI
  suite does not grow.

---

## Context

### The defect, read out of the code

`VaultSession.readDiary(on:preferring:)` (`Sources/Vault/VaultSession+Diary.swift:21-26`) reads
the day's file and returns its prose and entries. The hash of what it read is available on the
same call - `read(_:)` returns a `NoteRecord` whose `contentHash` (`NoteStore.swift:133`) is
exactly what `expecting:` compares against - and is dropped. `writeDiary(prose:entries:on:)`
(`:39-48`) writes with no precondition at all.

Between the two sits the whole Diario pane. `DiaryController.reload`
(`Sources/Features/Diary/DiaryController.swift:89-110`) seeds `prose`/`entries`, the person reads,
types and drags for as long as they like, and `save()` (`:131-156`) writes the result back. An
external change to the file in that interval is overwritten, silently.

The one conflict signal on the path is `syncOpenNote(with:)`
(`Sources/App/VaultController+Editing.swift:79`, reached from `VaultController+Diary.swift:29`),
and it guards on `note.relativePath == result.path`: it fires only when the diary file also
happens to be the focused note in the editor. `VaultSession+Diary.swift:6-8` says the diary
«never goes through the editor's open-note buffer», which is the normal case. So in the normal
Diario workflow ADR-0001 §D3.4's prompt - the «existing partial answer» `PG-153` names - never
fires.

### A correction to how the ticket frames it

The dispatch brief called `writeDiary` «the only writer left in `Sources/Vault`/`Sources/App`
that does not use `expecting:`». That is not what the tree says. A grep for `write(` without
`expecting:` in `Sources/Vault`, `Sources/App` and `Sources/Features` also returns
`saveOpenNote` and `restoreVersion` (`VaultController+Editing.swift:25,54`),
`VaultSession.append(text:to:)` (`+Watching.swift:74`), `linkFromDailyNote`
(`+EventNotes.swift:79`), the `RelatedLink` pair (`+Notes.swift:196-197`) and the board drop
(`+BoardDrop.swift:78`), among others.

What *is* unique to the diary is narrower and is the actual reason for this ADR: **it is the only
in-memory holder of a `.md` file outside the editor-tab model.** The editor's own unguarded save
is covered by a different mechanism - the watcher reconciles an external change against every tab
showing the path (ADR-0056) and a dirty tab gets the §D3.4 prompt. The single-hop read-then-write
sites above have a window of one actor hop. The diary has neither the watcher's reconciliation
nor a one-hop window: its read and its write are separated by a person.

### Who else writes the diary's file

- **Another process**, always: Obsidian, an iCloud Drive replica, `perg`/`pergamenum-mcp`
  (`VaultWrites.swift:91`'s `append`, `VaultCapture.swift:117`'s `dailyNote(for:)`).
- **This process, in one configuration.** ADR-0005's Consequences keep «`diaryFolder` equal to
  `dailyFolder`» as a supported setup, and then the diary file *is* the daily note. Three
  in-process writers reach it while the Diario pane is on screen: the global capture panel
  (`VaultSession+Tasks.captureTask`, `:223-262`), a time block (`+TimeBlocks.dailyNoteBody`,
  `:100-110`, which also *creates* the file), and an event note's link
  (`+EventNotes.linkFromDailyNote` via `dailyNote(for:)`, `+Notes.swift:78-87`, which creates it
  too). These go through `VaultSession.write`, so the watcher recognises them as this session's
  own writes and drops them (ADR-0043 §"What was read" item 5) - no watcher-based answer could
  ever see them.

The second group is why «no precondition when the file does not exist yet» (the brief's item 1)
is not enough: in the shared-folder setup, a morning capture into today's daily note while the
Diario pane shows an empty today *creates* the file, and the diary's first write - made with no
precondition - silently erases the captured task.

### The controller races itself

`save()` snapshots `day`/`prose`/`entries` and starts a fire-and-forget
`Task { @MainActor in await vault.writeDiary(...) }` (`:149-155`). `scheduleSave()`'s 600 ms
debounce and `entriesChanged()`'s immediate save (`:224-230`) each call it, so two writes can be in
flight at once. `VaultDisk` is an actor, and Swift publishes no FIFO guarantee for the order it
takes enqueued jobs in (ADR-0043 §"What was read" item 6): the older snapshot can land last. Three
defects share this shape, and only the first is in the ticket:

1. **Reordering.** An older snapshot lands after a newer one and the file goes backwards.
2. **The lost keystroke.** `isDirty = false` runs after the write's `await` (`:154`),
   unconditionally. A character typed while the write was in flight is marked clean by a write that
   never contained it, the debounce then finds nothing to do, and the character is on screen and in
   no file. ADR-0043 §D7's rule («a precondition evaluated before an `await` is a filter»), met from
   the other side: a flag cleared after an `await` describes the snapshot, not the state.
3. **The stale re-read.** `show(_:)` (`:74-85`) flushes the day being left and switches day
   synchronously. Coming back to that day before its flush has landed re-reads the file *before*
   the write, and the next save writes the pre-flush text plus the new edit over the flushed
   sentence. `load()`'s `skipDiskReadBecauseJustFlushed` (`:57-71`) covers only the same-day path.

### Why `expecting:` alone is not the fix

Both of two concurrent saves read the same expectation, because the origin only advances when a
write completes. Whichever lands second is refused. `entriesChanged()` saves on every click, so
the sequence `add` → `move` → `resize` - exactly
`DiaryControllerTests.movesAndResizesAnEntryAndWritesBothToTheFile`
(`Tests/DiaryControllerTests.swift:188`) - would raise a conflict against the app's own writes on
every file that already exists, and leave the file on the first snapshot. Chaining expectations
(the second expects the hash the first will write) does not help: if the second lands first it is
refused and the first then lands older data. What is missing is ordering, and a hash cannot supply
it.

### What this repo already decided about exactly this shape

- **ADR-0052 §D1/§D3, a CLAUDE.md working agreement:** a document the app holds in memory and
  saves back records which file it was read from.
- **ADR-0054 §D2/§D5:** the open board's `BoardOrigin`, its `SaveState`, and a conflict shown on
  the surface itself with two verbs, never an automatic discard.
- **ADR-0043 §D7, a working agreement:** the guard goes on the far side of the suspension.
- **ADR-0041, a working agreement:** a check exposed as a separately-callable step gets skipped
  by the next call site - make it the only way to get the thing.

### One more thing found on the way, relevant to §D5

`WorkspaceController.load(board:)` (`WorkspaceController.swift:305-335`) and `select(_:)`
(`:359-379`) leave a conflicted board silently: `flushPendingSave()` → `save()` returns early for
`.conflicted` (`:682`), then the document is replaced and, in `load`, `saveState` is reset to
`.saved` (`:330`) - no problem recorded. ADR-0054 §D5 names `detach()` as «the one remaining path
where the work disappears»; switching board is a second one. Not fixed here (it is ADR-0054's
surface), recorded as a follow-up, and it is the reason §D5 below does not copy that shape.

---

## Decision

### §D1 - The diary's read carries the disk state it came from

```swift
extension VaultSession {
    /// What the diary's file held on disk when it was read.
    enum DiaryDiskState: Equatable, Sendable {
        case absent
        case present(hash: String)
    }

    func readDiary(
        on day: CalendarDate, preferring text: String? = nil
    ) -> (prose: String, entries: [DiaryEntry], disk: DiaryDiskState)?
}
```

`disk` comes from the same `read(_:)` as the text: `record.contentHash` when the file was read,
`.absent` when it was not. A third labelled element rather than a new struct, so every existing
`read.entries`/`read.prose` access keeps compiling.

When the text comes from the editor's buffer (`preferring:`, the diary file open and dirty in a
tab), `disk` is still what is **on disk**. The precondition is a claim about bytes, not about the
buffer; the buffer's own conflict is the editor's, and `syncOpenNote` keeps raising it exactly as
today.

No new hashing primitive: the hash is the one the index already stores.

### §D2 - The controller records an origin, and records the file, not just the hash

```swift
enum DiaryOrigin: Equatable {
    case none
    case read(file: URL, disk: VaultSession.DiaryDiskState)
}
```

`file` is `vault.root` plus `diaryNotePath(for: day)`: *which vault* and *which path*, one value
that cannot drift apart (ADR-0052 §D1's reason for one marker rather than two properties). The
diary controller is app-lifetime (`PergamenumApp.swift:121`) and outlives a vault switch, so a
marker that recorded only a relative path would let a day read in vault A be written into the same
path in vault B - which is what happens today when the Diario pane stays on screen across «Apri
vault…».

Written by: a read (`reload`), a successful write (advanced to
`NoteStore.hash(Data(result.text.utf8))`, the expression `dailyNoteBody` already uses), and the two
resolution verbs of §D6. Never by an in-memory edit: typing changes nothing about what disk holds.
All writers stay in `DiaryController.swift`, so `origin` is `private(set)` and the compiler holds
the rule.

### §D3 - No unguarded diary write remains; the creation case gets a precondition too

```swift
func writeDiary(
    prose: String, entries: [DiaryEntry], on day: CalendarDate, over disk: DiaryDiskState
) async -> WriteOutcome
```

`over` is mandatory - no default, no second unguarded overload - because a defaulted precondition
is ADR-0041's skippable step. `.present(h)` becomes `expecting: h`. `.absent` becomes a new
opt-in parameter on the write door:

```swift
func write(
    _ text: String, to relativePath: String,
    expecting: String? = nil,
    expectingAbsent: Bool = false,
    requiringExistingFolder: Bool = false
) async throws -> WriteResult
```

threaded to `VaultDisk.write(_:to:precomputedHash:expecting:...)` (`VaultDisk.swift:207`) and
checked there, beside the `expecting` check at `:222`, in the same isolation as the write: if the
file **exists**, throw `VaultWriteRefusal.movedOn(relativePath)` with no byte moved. Existence, not
readability: a diary file that is there but cannot be read (not UTF-8) makes `readDiary` return nil,
and an absence test on `textBefore == nil` would then overwrite it - ADR-0052's «never save over a
file you could not read», applied here.

This is the shape PG-168 already chose for `requiringExistingFolder`: a second opt-in parameter
beside `expecting:`, not an extension of it (ADR-0043 §D8's cross-reference note). §D8's exclusion
of creations stands for what it was written about - «make the file say this» writes such as
`createNote` or a template. The diary's first write is not one of those: it is a read-modify-write
whose read found nothing, and its text (`emptyDiaryNote(for:)` plus what was typed) was derived
from that absence.

`expecting` non-nil together with `expectingAbsent: true` is a contradiction; `VaultSession.write`
asserts against it in Debug and lets `expecting` win in Release.

A refusal maps to `WriteOutcome.stale`, the mapping ADR-0043's implementation notes already gave
the task and time-block writers. `writeDiary` does **not** `recordProblem` on a refusal - the
controller does, once, on entering the conflict (§D6) - and keeps recording one on `.failed`.
`VaultController.writeDiary` returns the `WriteOutcome` rather than flattening it to `Bool`, since
its one caller must tell `.stale` from `.failed`.

### §D4 - One write door per controller, serial, with its expectation read on the far side

Every disk write the controller makes goes through one serial chain: a new operation awaits the
previous one before it does anything. At most one write is in flight, ever.

Inside an operation, in this order and after the predecessor has settled:

1. **Snapshot now, not at `save()` time.** The operation writes the current `prose`/`entries`, so
   three saves queued behind a slow one collapse into one write of the latest text, and the ones
   behind it find nothing owed and do nothing. Snapshotting at `save()` time was only needed because
   `show(_:)` changed `day` synchronously under a pending write (`:139-145`'s comment); §D5 removes
   that.
2. **Read the expectation from `origin`**, which the predecessor has already advanced. This is
   ADR-0043 §D7's rule applied to the controller's own state: the expectation is read on the same
   side of the suspension as the write it guards.
3. **Stamp an edit generation.** Every edit increments a counter; the operation records the value
   it snapshotted. On success, the controller is marked clean **only if the counter has not moved
   since** - otherwise it stays pending and the edit that arrived during the write is written by the
   next operation.
4. **Write**, through `writeDiary(... over: origin.disk)`.

`hasContent`'s «a day nobody wrote anything on is not a file» (`:135`) reads `origin.disk` instead
of re-reading the file on the main actor: absent and empty means skip; present means write.

The ordering is the controller's to own, not the session's: the session cannot see the controller's
gestures, and the actor offers no FIFO. Cancellation is not a substitute (§Alternatives 2).

### §D5 - A day is left only once its write has settled, and a conflicted day is not left

`show(_:)` keeps today's synchronous path when nothing is owed and nothing is in flight: `day`
changes and the new day is read at once, which is every navigation through a clean day and every
existing test's setup (`makeDiary` → `show(testDay)`). That condition is one read-only predicate,
`isSettled` (`saveState == .saved` and no write operation queued or running), which is also what a
test waits on before asserting a round trip through the file. When something is owed or in flight,
`show(_:)` flushes and **enqueues the switch behind the flush**. When the switch operation runs:

- the day was refused (§D6) → it stays, conflicted, and the switch is dropped;
- an edit arrived while it waited → it flushes again and re-enqueues itself;
- otherwise → `day` becomes the destination and the new day is read from disk, which by then holds
  the flushed text.

Navigation is relative to the **destination**, not to `day`, so two clicks on «Giorno successivo»
during a flush go two days, and `move(by: 1)` then `move(by: -1)` lands back on the day it left
without re-reading it.

`load()` (the pane reappearing) keeps its three cases, restated in these terms: conflicted →
nothing (the banner stays up); owed or in flight → flush and do not re-read, since memory is what
the write will make the file say (today's `skipDiskReadBecauseJustFlushed`, now the general rule);
otherwise → re-read, which is also what picks up a change another process made while the pane was
away.

The consequence that makes the rest simple: **every refusal is about the day on screen.** One
origin and one conflict state are enough, as for one board in ADR-0054. The alternative - keeping
`show(_:)` synchronous and tracking per-file pending writes, then dragging a refused day back onto
screen - is §Alternatives 8.

A write that fails for any reason other than a refusal (`.failed`: disk full, permissions) settles
too, and the day is left, with the problem recorded - exactly today's behaviour, not widened here.
Pinning the person to a day because the disk is failing would make the diary unusable for the
duration.

### §D6 - A refused write is a conflict in the pane, resolved only by a choice

```swift
enum SaveState: Equatable { case saved, pending, conflicted(reason: String) }
private(set) var saveState: SaveState = .saved
```

It replaces the private `isDirty` (`pending` and `conflicted` both mean «not safely on disk»). On
`.stale`, the controller enters `.conflicted(reason: VaultWriteRefusal.movedOn(path).description)`
- the one door into that state, which records the reason through `vault.recordProblem` once, so it
reaches Impostazioni → Problemi where the other refusals already go.

While conflicted:

- **nothing is written and nothing retries.** Typing and entry edits keep changing memory;
  `save()`/`flush()` return early. A retry per keystroke would refuse per keystroke.
- **the day is not left** (§D5): `show(_:)` refuses, and the toolbar's day navigators and «Vai a
  data» are disabled. The guard is in the controller; the disabled buttons are the affordance.
- **`load()` does not re-read**, so leaving the pane and coming back finds the same conflict.
- **the writing column says so**, in a strip between the header and the editor, shaped like the
  editor's own (`EditorColumn+Conflict.swift`) because the Diario's left column *is* that editor
  (ADR-0029): «Ricarica da disco» and «Tieni la mia versione». Non-modal.

The two verbs, named after ADR-0054's `keepLocalBoard()`/`reloadBoardFromDisk()`:

- **`keepLocalDiary()`, «Tieni la mia versione»,** re-reads only the file's disk state, adopts it
  as the origin without touching memory, and enqueues one write. A third writer landing between
  that read and the write is refused again and re-enters the conflict - one attempt per click,
  never a loop.
- **`reloadDiaryFromDisk()`, «Ricarica da disco»,** re-reads the day and replaces `prose`,
  `entries` and the origin with it, dropping the in-memory edit by explicit choice. An absent file
  reloads as `emptyDiaryNote`.

There is **no automatic reconciliation**, unlike ADR-0054 §D4. That rule could adopt a board
change automatically because the in-app writers produce exactly one decidable change class (a
`.file` node's path). The diary's concurrent writers are another process in the default setup,
with no change class to speak for, and in the shared-folder setup they write the prose half of the
file - the same half the person is typing into in the common dirty state, so a section-wise rule
would answer «diverged» in exactly the case it was built for (§Alternatives 6).

### §D7 - The origin names the vault, and a vault change is reported rather than written through

A write whose target (`vault.root` + `diaryNotePath(for: day)`) differs from `origin.file` is not
performed. If anything was owed, the controller records «modifiche al diario del …, non salvate: il
file non è più quello letto» and reloads the day from the current vault. The view's
`.task { controller.load() }` becomes `.task(id: vault.root) { controller.load() }`, so a vault
switch with the pane on screen reloads at the switch rather than at the next keystroke.

The same rule catches a change to `diaryFolder` in Impostazioni with unsaved diary text: the text is
reported, not written into a path it was never read from. That loss is real and rare, and it is
named here rather than discovered.

### §D8 - Scope boundary: what this chain does not do

- **The watcher is not wired to the Diario pane.** A clean pane showing a day another process
  changed stays stale until the pane is shown again (which re-runs `load()`) or the next edit is
  refused into a conflict. ADR-0054 §D7's reason for refusing the watcher for `.canvas` does not
  apply here - a diary write goes through `VaultSession.write` and is suppressed as a self-write -
  so reloading a clean pane on an external change is a sound follow-up. It is UX, not correctness:
  the precondition is what stops the overwrite, and the watcher cannot see the in-process writers
  anyway. Filed, not built.
- **The other unguarded read-then-write sites in `Sources/Vault`** that ADR-0043's grep scope did
  not reach (`append`, `linkFromDailyNote`, the `RelatedLink` pair, the board drop; and
  `captureTask`'s creation case, which could now adopt `expectingAbsent:`). Each has a one-hop
  window rather than a UI round trip. Named, filed, each needing its own verification.
- **The quit flush.** `DiaryView` flushes on `willTerminateNotification`, but the write is async
  and nothing in `Sources/` delays termination for it (no `applicationShouldTerminate` or
  `terminateLater`, grepped). Whether that write lands before the process exits is **unverified**.
  Unchanged by this chain, named.
- **`WorkspaceController`'s board switch dropping a conflicted board** (§Context). ADR-0054's
  surface; filed.
- **`.failed` writes** keep today's behaviour (§D5).

### §D9 - Acceptance is gate-forced and deterministic, never a timing test

ADR-0043 §D9's and ADR-0046 §D11's rule: no test sleeps against a debounce or races two tasks and
hopes. `DiaryController` gains one test seam, an optional hook called at two points of a write:

```swift
enum DiaryWritePhase: Equatable { case willWrite, didWrite }
@ObservationIgnored var testOnlyWriteHook: (@MainActor (DiaryWritePhase) async -> Void)?
```

nil in production. `.willWrite` is awaited after the operation's snapshot and expectation are
taken and immediately before `writeDiary`; `.didWrite` after `writeDiary` returns **and its outcome
has been acted on** - origin advanced, state set, conflict entered - so a count of `.didWrite`
calls is a count of writes whose consequences are already visible. A test holds a write at
`.willWrite` on a gate and does, while it is held, exactly what a person or another writer would -
types, adds an entry, changes day, writes the file - then releases it and waits on the count of
`.didWrite` calls, which is a fact about writes that finished rather than a guess about time.
Every race in §Context is reproduced this way, red before the change and green after. The `Gate`
latch that `VaultTransactionGestureTests.swift:30` declares privately moves to a shared test file
rather than being copied a second time (ADR-0051 §D2).

---

## Alternatives considered

1. **`expecting:` alone, with no serialization** (the brief's «or show it is already safe»).
   Rejected: two concurrent saves read the same origin, so the second to land is refused - a
   conflict raised against the app's own writes on every `add` → `move` sequence over an existing
   file - and when the older one lands second the file still goes backwards. It turns a silent loss
   into a false alarm; it does not fix the ordering (§Context).
2. **Cancel-and-supersede**: cancel the in-flight save when a newer one starts. Rejected: task
   cancellation is cooperative, and nothing between `writeDiary` and `VaultDisk`'s atomic write
   checks it, so a cancelled write still lands. Cancellation cannot un-write; only ordering can
   stop an older snapshot landing last.
3. **Chain expectations without ordering** (the second save expects the hash of the first save's
   text). Rejected: if the second lands first it is refused, and the first then lands older data.
   The expectation is right only if the order is.
4. **Serialize in `VaultSession` or `VaultDisk`** (a per-path FIFO). Rejected: the actor offers no
   FIFO (ADR-0043 item 6), a queue there would order writes but not the controller's reads of its
   own `origin` between them, and it would impose an ordering regime on every other writer of the
   session for one caller's problem.
5. **Watcher-driven reload and conflict instead of a precondition.** Rejected as the guard: FSEvents
   reports after the fact, so a save landing between another writer and the callback still
   clobbers; and the shared-folder in-process writers are suppressed as self-writes and never
   reported at all. Kept as a UX follow-up on top of the guard (§D8).
6. **Automatic three-way reconciliation by section** (prose vs `## Diario`, ADR-0054 §D4's shape).
   Rejected: the default setup's other writers are other processes with arbitrary change classes,
   and the shared-folder setup's in-process writers change the prose half - the half the person is
   typing into when the controller is dirty - so the rule would answer «diverged» in its own common
   case, at the cost of a base snapshot and a merge function. Worth revisiting only if the
   shared-folder setup becomes the usual one.
7. **No precondition for a day whose file does not exist yet** (the brief's item 1 as proposed).
   Rejected: the shared-folder setup's capture panel, time blocks and event-note link all create
   today's file in-process while the Diario pane can be on screen, and any other process can too;
   the diary's first write would erase what they wrote (§Context).
8. **Keep `show(_:)` synchronous always**, overlay each file's pending write on a re-read, and bring
   a day whose write was refused after it was left back onto the screen. Rejected: per-file pending
   state and a pane that jumps back to a day the person just left, to avoid a wait measured in
   milliseconds. Waiting for the flush gives the same experience with one origin and one conflict.
9. **Let the person leave a conflicted day** and record a problem, as ADR-0054 §D5 does for
   closing a board. Rejected: that trade was made for *closing*, a rare act where refusing is worse
   than the loss. Changing day is a routine click, and allowing it would turn every conflict into a
   one-click silent loss - the shape `WorkspaceController.load(board:)` already has (§Context).

---

## Consequences

### Positive

- The `PG-153` overwrite is closed for every writer the app can prove against: another process,
  and the shared-folder in-process writers - including one creating the file.
- Three older defects in the same controller close with it, each named in §Context: an older
  snapshot landing last, a keystroke typed during a write marked clean and never written, and a day
  re-read before its own flush had landed.
- A diary edited across a vault switch can no longer be written into the other vault.
- No diary write is unguarded, and the precondition is not optional at the diary door, so the next
  caller cannot forget it.
- Diary failures reach the problem list. `DiaryController.problems` (`:29`) has no reader anywhere
  in `Sources/` or `Tests/` (grepped), so today's write failures there are appended to an array
  nobody draws; it is removed and reporting goes through `vault.recordProblem`.

### Negative

- `show(_:)` is no longer synchronous when something is owed: the header changes a few
  milliseconds later, after the write. One existing test asserts the old timing
  (`DiaryControllerTests.writesTheDayBeforeLeavingIt`, `:122-137`) and waits for the day as well;
  three round-trip tests (`readsBackWhatItWrote`, `keepsABlockOfThreeHours`,
  `drawsABlockThatRunsToMidnight`) wait for `isSettled` before navigating, so they still read the
  file back rather than landing on a day that was never left.
- A conflicted day pins the pane: no day navigation until one of the two verbs is chosen. Visible,
  explained, and one click away - but it is a mode the pane did not have.
- `DiaryController` gains a serial chain, an origin, a save state, an edit generation, a
  destination day and a test hook. The file is 315 lines against `file_length`'s 400 warning, and
  its type body measures about 190 code lines (SwiftLint counts neither comments nor blank lines)
  against `type_body_length`'s 250 warning; the change is estimated at 120-160 lines, comments
  included. The read-only timeline geometry and the entry composer move to extensions so every
  writer of `origin`, `saveState`, `prose` and `entries` stays in the declaring file under
  `private(set)`, rather than widening those setters.
- The core write door gains a third opt-in precondition parameter, compiled into `perg` and
  `pergamenum-mcp` (`VaultSession.swift`, `VaultDisk.swift` and `VaultSession+Diary.swift` are all in
  `sharedSources`). Defaulted, so no existing call site changes.
- Against another process the actor's compare-then-write narrows the window and does not close it,
  the same limit every other `expecting:` site and ADR-0054 §D3 already accept.
- A `diaryFolder` change or a vault switch with unsaved diary text reports and drops that text
  (§D7) - at most the typing of the last debounce interval, since every other exit flushes first.

### Neutral

- The file on disk is byte-identical to today's for the same prose and entries.
- `IndexCache.schemaVersion` stays 4; no connector gains a capability (none calls the diary API).
- `syncOpenNote`'s editor prompt is unchanged and still fires when the diary file is the focused
  note.
- ADR-0005 §D7's list of flush moments is unchanged; what changes is that the day switch waits for
  its flush.

---

## References

- `TODO.md` `PG-153` → issue #262; branch `kepler/fix-262-readdiary-writediary-race`.
- Plan: `docs/plans/pg-153-diary-write-guard.md`.
- ADR-0043 §D7/§D8/§D9 and its implementation notes item 1 (the «Declined» list this closes one
  entry of), item 6 of «What was read» (no actor FIFO), item 5 (self-writes never reach the watcher).
- ADR-0054 §D2/§D4/§D5/§D7/§D9 - the origin marker, the reconciliation this ADR declines, the
  conflict state and verbs, the watcher refusal for `.canvas`, gate-free determinism.
- ADR-0052 §D1/§D3 - the origin marker rule; «never save over a file you could not read».
- ADR-0046 §D11, ADR-0050 - no timing-based interleaving test; gate-forced interleavings.
- ADR-0051 §D2 - share a byte-identical test helper rather than copy it.
- ADR-0041 - a precondition the caller cannot skip.
- ADR-0005 §D7 and Consequences - the diary saves itself; the shared-folder setup.
- ADR-0029 - the Diario writing column is the app's one editor.
- ADR-0001 §D3.4 - never merge, never discard: ask.
- PG-168 (`docs/plans/pg-168-sync-write-never-recreates-a-vacated-pratica.md`) - a second opt-in
  precondition beside `expecting:`.
