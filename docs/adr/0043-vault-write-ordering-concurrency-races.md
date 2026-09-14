# ADR-0043: The ordering guard has to cover every writer, not the one that asked for it

- Status: proposed — **decided, not implemented** (see §D9)
- Date: 2026-09-13. Written after reading every file it names, at the line, on the working tree at
  `8b554b1` (`feat/vault-layer-consistency-and-security-cha`, ADR-0041 implemented on the branch,
  PR #254 not yet merged to `main`). Every claim below about this repo's code was read out of
  `Sources/`, not out of the review that raised it.
- **Numbering note:** `0042` is taken. `docs/adr/0042-pratiche-inline-image-placeholders.md` exists
  on `main` (merged via PR #250) and is not present on this feature branch, so a listing of
  `docs/adr/` here stops at `0041` and looks free. It is not. This ADR is `0043`.
- **Relocation note:** drafted at `docs/architecture/ADR-0043-vault-write-ordering-concurrency-races.md`
  (the architect agent's enforced write scope, `test-write-scope.sh`) and relocated by the
  orchestrator to this path, `docs/adr/0043-vault-write-ordering-concurrency-races.md`, where this
  repo's ADRs live (`0001`…`0042`) and which every reference below already assumed. Same convention
  ADR-0029…ADR-0036 and ADR-0040…ADR-0041 carry in their own headers.
- **Extends ADR-0041 §D9, §D10 and §D11. Amends none of them.** Every sentence of those three
  sections is still true of the writer they were written about. What is wrong is their scope: they
  describe one writer, and the vault has six. The distinction is stated exactly in
  §"Relationship to ADR-0041" and is the reason this is a follow-up rather than a correction.
- **Reopens nothing.** No SPEC §14 decision is revisited. No on-disk format changes — not note
  frontmatter (SPEC §4.3's closed four keys), not the tag grammar (§4.4), not JSON Canvas 1.0, not
  `.pergamenum/` layout, not `IndexCache.schemaVersion`. No user-visible feature changes, no new
  setting, no new UI.
- **Adds no exception to CLAUDE.md principle 2.** No network call, no socket, no loopback, no new
  framework that could make one. The whole of this ADR is about the order in which this process
  touches its own files.
- Depends on: **ADR-0041** in full (this is a defect analysis inside that chain's own mechanism),
  **ADR-0001 §D2.3** (files first, index second), **§D3.3** (self-writes are recognised by content
  hash, never by a time window), **§D3.4** (an external change against a dirty buffer is asked
  about, never merged and never discarded), **ADR-0007 §D3** (`VaultSession` owns the vault,
  `VaultController` is the observable facade) and **§D6** (a write is off by default, reversible,
  never silent), **ADR-0016** (the journal's move/removal vocabulary).

---

## Context

ADR-0041 §D9 moved the disk work of a note write onto `VaultDisk`, an actor. §D11 gave that path a
per-path sequence number so an outcome resuming out of order could not move the index backwards,
and §D10 moved the self-written hash to the main actor, before the hop, so an FSEvents batch could
not observe a file whose hash the session had not yet recorded. All three are sound, and all three
are about one function.

An independent review of the implemented branch — Codex, model `gpt-6-astra`, effort high, run
through this repo's `review-triage-fix` skill — returned three CONFIRMED concurrency findings
against it. The skill routed all three to REPORT-ONLY rather than to a coder dispatch, which was
the right call and is worth recording as a rule rather than as an anecdote: **static analysis and a
green suite cannot demonstrate thread safety.** A patch to a concurrency finding, written by an
agent that cannot run the interleaving that produces the failure, is a patch whose only evidence of
correctness is that nothing went red — which is exactly the evidence the defect already passed. The
orchestrator verified each of the three by reading the code before accepting it. So did this ADR,
and the reading turned up a fourth (§"The fourth race, which the three imply") and one false
comment (§D7).

The one sentence that ties them together: **ADR-0041 put one writer behind a serialization point
and gave that writer a clock. The vault has six writers, and five of them are still holding the
pen they always held.**

### What was read in this repository, at the line, before deciding

1. **There are two write doors, not one.** `VaultSession.write(_:to:) throws -> WriteResult`
   (`VaultSession.swift:252`, forwarding to `writeSynchronously` at `:256`) and
   `VaultSession.write(_:to:) async throws -> WriteResult` (`:490`, the ADR-0041 §D9 actor hop).
   Swift resolves them by whether the call site says `await`. The synchronous one writes the index
   with a bare `index.update(try store.read(relativePath).record, at: relativePath)` at `:265` —
   it never touches `appliedSequence`, so it is invisible to §D11's guard, and it is the door
   `saveOpenNote()` uses (`VaultController+Editing.swift:23`, with a doc comment explaining that
   the conversion was tried and reverted). Every keystroke the user saves goes through the
   unsequenced door.
2. **Five call sites mutate the index outside the guard.** `grep -rn "updateIndex(\|index\.update"
   Sources/` returns, besides the guard's own use in `VaultSession+WriteOrdering.swift:24`:
   `VaultSession.swift:265` (the sync write), `VaultSession+Journal.swift:78` and `:86` (a move,
   both halves), `:131` (a trash), `VaultSession+Watching.swift:27` and `:37` (the watcher's
   reconciliation), and `VaultController+Tabs.swift:359` (`readForEditing`, refreshing the row of
   a note the editor just opened). Seven writes to the index; one of them consults the clock.
3. **`selfWrittenHashes` is one slot per path** (`VaultSession.swift:78`, `[String: String]`). It
   was written when a write could not be in flight, because writes were synchronous. Two
   overlapping async writes to one path leave only the second hash recorded, and the first one's
   bytes — if the watcher ever observes them separately — come back unrecognised.
4. **`canOperate(on:)` has eight call sites and exactly one of them crosses a suspension point.**
   `VaultController+Files.swift:39`, `:58`, `:77` and `VaultController+Move.swift:152` are
   synchronous straight lines from the check to the file operation. `PraticaEntryComposer.swift:54`
   is not: two `await`s separate the check from the hand-off it guards. This is a narrow finding,
   not a class-wide one — **today**. It is a class-wide hazard the moment §D1 below makes the rest
   of the file operations async, which is why it is decided here rather than patched there.
5. **`syncOpenNote(with:)`'s doc comment is false, and has been since ADR-0007.**
   `VaultController+Editing.swift:60-78` leaves a dirty buffer alone and says «the watcher will
   raise the question when the write comes back round». It will not: `VaultSession.reconcile`
   recognises the session's own write by hash and drops it before it can become an `ExternalChange`
   (`VaultSession+Watching.swift:32-34`), which is ADR-0001 §D3.3 working exactly as designed. A
   buffer with unsaved edits plus a session write to the same path is a conflict nobody is ever
   told about. This is the mechanism Race 3 rides on, and it is older than Race 3.
6. **Swift publishes no FIFO guarantee for the order an actor picks up enqueued jobs.** ADR-0041
   §D11 already says as much about the *continuations* resuming on the main actor; the same absence
   applies to the jobs themselves. Everything below is designed so that it does not matter: a
   sequence number taken at the instant the bytes land is correct whether or not the runtime
   happens to be FIFO, and a sequence number issued by the caller before the hop is wrong if it
   is not. That asymmetry is the whole of §D1's shape.
7. **The Swift concurrency migration guide names the shape of Race 2 by example.** «Actors do not
   guarantee atomicity across suspension points… critical sections should always be structured to
   run synchronously» — and its counter-example is a function that reads state, awaits, and writes
   back a value derived from the pre-await read. `VaultSession.write`'s `existing` (`:494`) is that
   read, and the journal entry it feeds is that write-back.

### Race 1 — the sequence guard sees one writer out of six

```swift
// Sources/Vault/VaultSession+WriteOrdering.swift:20-26
@discardableResult
func apply(_ outcome: VaultDisk.DiskWriteOutcome, at relativePath: String) -> Bool {
    guard outcome.sequence > appliedSequence[relativePath, default: 0] else { return false }
    appliedSequence[relativePath] = outcome.sequence
    updateIndex(outcome.record, at: relativePath)
    return true
}
```

The guard compares an async outcome's sequence against a counter that only async outcomes advance.
Every other index mutation — the synchronous write, the move, the trash, the watcher, the editor's
open-a-note refresh — calls `updateIndex` directly and leaves `appliedSequence[path]` at whatever
it was, usually `0`.

Three concrete failures, each reachable from ordinary use:

- **A save under a pratica insert.** The user has `pratica.md` open, «Nota» starts
  `PraticaEntryComposer.insert` (async door, ticket 1 at the actor), the main actor is free during
  its suspension, the user presses Cmd+S. `saveOpenNote()` takes the synchronous door: the buffer's
  bytes land on disk and `index.update` writes the buffer's record. The composer's outcome then
  resumes with `sequence: 1 > appliedSequence["pratica.md"] == 0` and applies the *pre-save*
  record over it. The index now describes bytes that are not on disk. Search, backlinks, the task
  lists and every view query read that row until a rescan.
- **A trash under a write.** `trashFile` runs `updateIndex(nil, at: path)` (`:131`) while an async
  write to the same path is suspended. The outcome arrives, passes `1 > 0`, and puts the row back.
  The index lists a note that is in the Finder's Trash.
- **An external edit under a write.** Obsidian writes the file after our bytes land; the watcher's
  `reconcile` applies the external record at `VaultSession+Watching.swift:37` with no sequence; our
  own outcome resumes afterwards and overwrites it with the older record.

None of these corrupts a file. All of them leave the index disagreeing with the disk, silently,
until something rebuilds it — which is a cache doing the one thing ADR-0001 §D2.3 arranged the
write order to prevent.

### Race 2 — two overlapping writes record the same «before», so the journal's history is wrong

```swift
// Sources/Vault/VaultSession.swift:490-534, elided
func write(_ text: String, to relativePath: String) async throws -> WriteResult {
    let existing = (journal != nil && !isDryRun) ? try? read(relativePath) : nil   // :494
    guard !isDryRun else { return WriteResult(path: relativePath, text: text) }
    let hash = NoteStore.hash(Data(text.utf8))
    selfWrittenHashes[relativePath] = hash                                          // :503
    var journalEntry: WriteJournal.Entry?
    if journal != nil {
        journalEntry = WriteJournal.Entry(…, hashBefore: existing?.record.contentHash,
                                          textBefore: existing?.text, …)
    }
    let outcome = try await disk.write(text, to: relativePath, …)                   // :524
    apply(outcome, at: relativePath)
    …
}
```

`existing` is read on the main actor, before the suspension at `:524`. Two writes to the same path,
both started from the main actor — a pratica insert and an editor save, two `Task { }`-wrapped
saves, a connector write and a UI write — interleave like this: A runs its whole synchronous prefix
and suspends at `:524`; the main actor is now free; B runs *its* synchronous prefix, including its
own `read(relativePath)` at `:494`, before A's bytes exist. B's «before» is the same pre-A state A
recorded.

The actor then serialises the two byte writes correctly. The journal does not: it holds two entries
claiming the same `hashBefore` and the same `textBefore`. **`journal undo` on B's entry restores
the original pre-A text**, discarding A's write from the journal's own record of what happened, and
`preflightUndo`'s hash check (`VaultSession+Journal.swift:234`) cannot catch it, because B's
`hashAfter` is genuinely the file's current hash. The undo log is the one structure in this app
whose entire purpose is to be right about a past state, and this makes it confidently wrong.

The same suspension window damages `selfWrittenHashes` (`:503`), which holds one hash per path. A
sets `hash_A`, B overwrites it with `hash_B`. If the actor lands A's bytes last — which no
documented ordering rule forbids — the file on disk hashes to a value the session no longer holds,
the watcher reads it as an external change, and ADR-0001 §D3.4's conflict prompt fires against the
app's own write. That is precisely the hazard ADR-0041 §D10 was written to close; §D10 closes it
for one write at a time, and the data structure it relies on cannot describe two.

### Race 3 — a guard checked before an `await` does not survive it

```swift
// Sources/Features/Pratiche/PraticaEntryComposer.swift:44-68, elided
func insert(_ kind: PraticaEntry.Kind, at timestamp: Date) async {
    …
    guard vault.canOperate(on: notePath) else { return }        // :54 — before any suspension
    let source = try session.read(notePath).text
    let insertion = PraticaEntry.insert(kind: kind, at: timestamp, counterpart: counterpart, in: source)
    try await session.write(insertion.text, to: notePath)       // :61 — suspends
    await mirror(kind, of: pratica, counterpart: counterpart, on: timestamp, session: session)
    pratiche.reloadTimeline(from: vault)
    handOff(insertion, notePath: notePath)                      // :64 — acts on the far side
}

private func handOff(_ insertion: PraticaEntry.Insertion, notePath: String) {
    vault.openChosenNote(at: notePath)
    if vault.openNote?.relativePath == notePath {
        vault.reloadFocusedNote()                               // :109 — unconditional
    }
    …
}
```

`canOperate(on:)` refuses while any tab holds unsaved edits to that note
(`VaultController+Files.swift:18-29`). It is checked once, at `:54`, and the comment at `:105-107`
states the conclusion it licenses: «Safe to replace outright, since `canOperate(on:)` above refused
a dirty tab.» That was true when `insert` was synchronous. It is false now: the two `await`s at
`:61` and `:62` hand the main actor back to the run loop, the person at the keyboard types into the
tab that is open on that very note, and `reloadFocusedNote()` replaces the buffer from disk with no
second look. The typing is gone, with no prompt, no problem recorded and nothing in the journal —
the journal records file writes, and the user's text was never written.

The window is not theoretical. `insert` performs two file writes (the pratica note and the daily
note), and the second one reads and rewrites the daily note; on a vault of any size that is tens of
milliseconds during which the caret is in the note and the app looks idle. And §"What was read"
item 5 explains why nothing catches it afterwards: the watcher cannot raise the question, because
the write it would raise it about is one the session itself made.

### The fourth race, which the three imply

Race 3's call site also reads the note at `:57` and writes a text derived from that read at `:61`.
Nothing between them re-checks that the file still says what the read said. Another writer that
reaches the actor first — an editor save wrapped in `Task { }`, a connector write, the next
`insert` — has its bytes overwritten wholesale by a text composed from a snapshot that predates
them. This is the plain lost-update, and it is the guide's `deposit(pineapples:onto:)` example with
a file instead of an array.

This repository already believes in the cure and has written it twice:
`TaskParser.insertingSubtask(in:below:draft:)` refuses when `lines[parent.lineIndex] !=
parent.rawLine` (`Sources/Core/Tasks/TaskParser.swift:473`), and `preflightUndo` refuses when the
file's current hash is not the one the journal recorded (`VaultSession+Journal.swift:234`). What is
missing is the same guard on the write primitive itself. It is decided in §D8, and it is stated as
the fourth race rather than smuggled into the other three, because a reader who checks this ADR
against the review it came from should be able to see which finding came from where.

## Decision

### §D1 — One clock, stamped where the bytes land; `VaultDisk` becomes the only thing that touches a file in the vault

Every operation that changes a file in the vault — the note write, the non-note `writeFile`, the
`FileManager.moveItem` inside `moveFile`, the `trashItem` inside `trashFile` — moves inside
`VaultDisk`. Each returns its index consequence in one currency:

```swift
extension VaultDisk {
    /// What one path's index row must become, and when that was decided (§D11's clock).
    struct IndexMutation: Sendable {
        let path: String
        let record: NoteRecord?   // nil: there is no file at this path any more
        let sequence: UInt64
    }
}
```

A write returns one. A move returns two — the old path's removal and the new path's record, each
stamped from its own path's clock, which is what makes a move orderable against a concurrent write
to either end of it. `DiskWriteOutcome` keeps `hash` and `journalProblem` and carries its
`IndexMutation` instead of a loose `record`/`sequence` pair.

**The sequence is taken inside the actor, immediately after the disk operation, and that is the
decision.** A number issued by the caller before the hop would record the order in which the main
actor *decided* to write, and Swift documents no guarantee that an actor executes enqueued jobs in
the order they were enqueued. A number taken where the bytes land records the order the bytes
landed, which is the only order the index is trying to agree with. ADR-0041 §D11 already got this
right for the one writer it had; §D1 is that same choice applied to the other five, not a new one.

`VaultSession.apply` becomes the only door onto the index:

```swift
@discardableResult
func apply(_ mutations: [VaultDisk.IndexMutation]) -> Int   // how many were newer than what we had
```

and `updateIndex(_:at:)` (`VaultSession.swift:293`) is **deleted rather than kept as a forwarder**.
This is ADR-0041 §D1's own argument, applied to the index instead of to the boundary: a guard a
caller may route around is a guard the seventh call site will route around, not out of malice but
by omission, and this repo has now documented that exact failure twice (`NoteStore`'s
`assertInsideVault`, ADR-0041 §D1; the `NoteStore` boundary check reachable from two of eleven
sites, CLAUDE.md's working agreements). A raw `index.update` reachable from five places is the same
shape, one layer up.

### §D2 — The synchronous `write` door is retired, and the tests that depend on it are converted in the same task

`write(_:to:) throws` (`VaultSession.swift:252`) and `writeSynchronously` (`:256`) are deleted. The
~20 internal wrappers inside `Sources/Vault` that call them, `VaultController+Editing`'s
`saveOpenNote()` and `restoreVersion(_:)`, and the seven test files that call those synchronously
(`Tests/VaultTests.swift`, `NoteHistoryTests.swift`, `NoteTabTests.swift`, `VaultSessionTests.swift`,
`GuardrailTests.swift`, `NoteTemplateTests.swift`, `RelatedLinkTests.swift`, `ConnectorTests.swift`
— the plan greps and lists them, it does not leave them to be found) all become `async`.

**This is not new scope; it is ADR-0041's own scope, finished.** §D9 planned exactly this, and its
Negative consequences list already states the outcome: «`VaultController+Editing.saveOpenNote()`
becomes `async`, which means its four call sites wrap it in `Task { }`. Each of those is a place
where two saves can now be started out of order. §D11 makes that harmless to the index.» The
implementation kept the synchronous door, with an honest comment giving the reason — the tests that
call it were outside the coder's edit scope under this system's test-authoring restriction. That
was a correct scope decision and it is not an architecture. Two write doors with two ordering
regimes is the largest single instance of Race 1, and no amount of guarding the async door fixes
the writer that does not use it.

The comment at `VaultController+Editing.swift:13-19` («Converting this to the async overload was
tried and reverted») is the record of the attempt and should be replaced, not deleted: what it
records is that the conversion fails unless the tests move with it, which is this task's shape.

### §D3 — The watcher's reconciliation reads inside the actor and takes a stamp

`VaultSession.reconcile(_:)` (`VaultSession+Watching.swift:22-41`) becomes `async` and delegates
its per-path read to `VaultDisk`, which reads, compares against the recorded self-written hashes
(§D6), advances that path's clock and returns the `IndexMutation` plus the `ExternalChange` list
the facade needs. `VaultController.reconcile` already runs inside `Task { @MainActor … }`
(`VaultController+Watching.swift:11`), so this costs no new asynchrony at the call site.

Advancing the clock on a read is deliberate and is what makes the guard total. The reconciliation's
record describes the file as it was at the moment the actor read it; a write that the actor performs
afterwards is newer and must win; a write it performed before is older and must lose. Both follow
from taking the number in the same serialized straight line as the read. As a side effect the
FSEvents path stops doing a full `NoteStore.read` — parse, wikilink scan, transclusion scan, task
parse, SHA-256 — on the main actor for every changed path, which is the same cost ADR-0041 §D9
removed from the write path and left on this one.

### §D4 — `readForEditing` stops writing the index

`VaultController+Tabs.swift:355-371` reads a note for the editor and refreshes its index row. Under
§D1 it is the one remaining writer with no ordering to offer: it is a main-actor read that can be
arbitrarily stale relative to an in-flight write, and stamping it would mean making tab opening and
session restore async for a repair.

It is a repair, and the thing it repairs is disposable by construction (ADR-0001 §D2.1). A row that
disagrees with the file got that way from some change, and after §D1 every change has a stamped
writer: the write path, the move, the trash and the watcher. A change made while the app was not
running is picked up by the cold scan. So the refresh is removed and replaced by nothing. The read
stays exactly as it is.

### §D5 — The journal's «before» is read where the bytes it describes are written

`VaultSession.write` stops reading `existing` on the main actor. It passes the actor only what it
alone knows — the command, the operation id, the entry id and timestamp — as a small `Sendable`
descriptor, and `VaultDisk.write` reads the current bytes itself, immediately before writing the
new ones, inside the same isolation, and fills in `hashBefore` and `textBefore`.

**A journal entry is a claim about a disk transition, and a claim about a transition can only be
made where the transition is serialized.** ADR-0041 §D9 already moved the journal *append* inside
the actor on that reasoning — «the entry and the bytes it describes are written under one
serialization» — and left the half of the entry that describes the «before» outside it. §D5 is that
sentence finished.

It is also cheaper than what it replaces. Today the main actor performs a full `NoteStore.read`
(parse, wikilink scan, transclusion scan, task parse, SHA-256) to obtain a text and a hash; the
actor needs `NoteStore.text(_:)` (`NoteStore+ReadSurface.swift:13`, which ADR-0041 §D7 added for
exactly this class of caller) and one `NoteStore.hash`. One main-actor read disappears and the
remaining work is strictly smaller.

`isDryRun` still short-circuits before the hop, so ADR-0007 §D6's first guardrail is untouched and a
dry run still never reaches the actor. The condition that decides whether to read at all — «a
journal is armed and this is not a dry run» — travels with the descriptor rather than being
re-derived inside the actor, so the actor never reads a file nobody is going to journal.

### §D6 — `selfWrittenHashes` becomes a per-path, sequence-tagged set

```swift
var selfWrittenHashes: [String: [(sequence: UInt64, hash: String)]] = [:]
```

A write appends before the hop (§D10's timing, unchanged: the hash is still computed on the main
actor from text it already holds, still recorded before the file can exist). A reconciliation that
observes a hash in the path's list treats it as this session's own write and drops **every entry
with a sequence at or below the matched one**, which is what keeps the list bounded when FSEvents
coalesces several writes into one callback — the intermediate hashes are never observed separately
and would otherwise leak forever.

The clock §D1 already requires is what makes the pruning exact rather than a heuristic. Without it
the honest options are a growing list or an arbitrary cap, and a cap on this structure is a
suppression window wearing a different hat, which ADR-0001 §D3.3 rejected by name.

### §D7 — A guard checked before an `await` is a filter; the guard goes on the far side, and the answer to a dirty buffer is to ask

Three parts, in order of how load-bearing they are:

1. **`handOff` stops reloading from disk.** `insert` already receives a `WriteResult` from
   `session.write` and discards it. It keeps it and hands it to
   `vault.syncOpenNote(with: result)` — the door that exists for precisely this («puts the editor
   back in step after a write the session made underneath it»,
   `VaultController+Editing.swift:60-78`) and that already asks the right question,
   `!note.hasUnsavedChanges`, on the correct side of the suspension. `reloadFocusedNote()` is not
   the right tool: it re-reads the file, which after §D1 may already have moved on again.
2. **`syncOpenNote(with:)`'s dirty branch stops doing nothing.** It sets
   `note.externalChangePending = result.text`, raising ADR-0001 §D3.4's existing prompt with the
   app's own write as the incoming text. The comment promising that the watcher will raise the
   question is deleted, because §"What was read" item 5 shows it cannot: `reconcile` drops the
   session's own writes by hash, which is §D3.3 working correctly. «Never merge, never discard:
   ask» was written about a person editing in Obsidian; ADR-0007 made this app its own second
   writer, and the rule follows the situation rather than the actor. This changes behaviour at all
   nine `syncOpenNote` call sites (`VaultController+TimeBlocks` ×3, `+TaskDrop`, `+Diary`,
   `+Routes`, `+Tasks` ×2, and the composer's new one) and that is the point: every one of them is
   a session write that can land under a dirty buffer, and today every one of them is silent.
3. **`canOperate(on:)` stays where it is, and stops being read as a guarantee.** It remains a cheap
   early refusal that spares the user a pointless write and a prompt in the common case. The
   comment at `PraticaEntryComposer.swift:105-107` that infers safety from it is deleted. The rule
   worth carrying out of this, and worth stating in CLAUDE.md's working agreements when this ships:
   **a precondition evaluated before an `await` is a filter, not a guard; the guard belongs on the
   same side of the suspension as the action it protects.**

### §D8 — `write` gains an optional expected-hash precondition, opt-in

```swift
func write(_ text: String, to relativePath: String, expecting: String? = nil) async throws -> WriteResult
```

`expecting` is the content hash the caller's text was derived from. The actor compares it against
the file's current hash — the read §D5 already performs, so this costs nothing extra — and throws
`WriteRefusal.movedOn(relativePath)` without writing a byte when they differ.

**Opt-in, defaulting to `nil`, deliberately.** Making it mandatory would turn every blind write —
a new note, a template instantiation, a restore from history, a connector write that means «make
the file say this» — into a failure path no caller is written to handle, for a hazard those callers
do not have. What it is for is the read-modify-write that straddles a suspension: the composer, the
task and timeblock writers, the pratiche sync. Which call sites adopt it is a grep the plan owns
(`session.read(` followed by `session.write(` in the same function, across `Sources/App`,
`Sources/Features` and `Sources/Connector`) and is not guessed at here.

The refusal is a thrown error and not a silent no-op, for ADR-0007 §D6's reason: a write that did
not happen and said nothing is the failure mode the guardrails exist to prevent. The composer's
existing `catch` already reports «La voce non è stata scritta in «\(notePath)»: …» and is the right
answer with no change.

### §D9 — This ADR decides; it does not implement

Nothing in `Sources/` or `Tests/` changes in the commit that adds this file. There is no plan, no
task list, no code and no test here. This is the follow-up the review recommended instead of a
blind patch, and it exists so that four verified races are written down with a decided fix shape
rather than living in a review transcript.

What comes next, in order:

1. A tracking item in `TODO.md` — the next free `PG-` id (`PG-150` against `main` at the time of
   writing; verify before filing, this repo runs parallel chains) — plus a GitHub issue, marked
   `P1`, `[correctness, chain "vault write ordering"]`, **after PR #254 merges**. The whole of this
   ADR is about code that only exists on that branch.
2. A `concept-to-code` chain of its own: SPEC with numbered criteria, implementation plan, then
   Step 5. It is a chain rather than a scoped edit because §D1 and §D2 together touch the same
   ~35 call sites ADR-0041 measured, plus seven test files.
3. **The acceptance criterion is a test that forces the interleaving, never a green suite.**
   `Tests/VaultWriteOrderingTests` already has the shape: it calls `apply` directly to force an
   inversion deterministically rather than hoping a timing test reproduces one. Every decision
   above needs its own such test — a sync writer and an async writer contending for one path (§D1,
   §D2), two overlapping writes whose journal entries must differ (§D5), a reconciliation between
   two writes (§D3, §D6), a buffer dirtied between a write and its hand-off (§D7), a stale
   expected-hash (§D8). A suite that goes green without those tests has demonstrated nothing about
   any of this, which is the same reason the findings were not auto-fixed.

### §D10 — What this does not touch

Stated so a reader does not have to infer it. No on-disk format changes and no schema bump
(`IndexCache.schemaVersion` stays where ADR-0041 left it). No change to the five task views
(ADR-0013 §D6), the board addressing rule (ADR-0025 §D1), the JSON Canvas round-trip
(principle 4), the pratiche sync's rewrite policy (ADR-0036 §D6 as amended by ADR-0040 and
ADR-0042) or the MCP tool surface — `tools/list` answers the same names with the same schemas, and
`scripts/mcp-smoke.py` must pass unmodified. ADR-0007 §D6's three guardrails all stand: `--allow-write`
gating untouched, `dryRun` still defaulting to true and still short-circuiting before any disk
contact, the journal still recording path, hash-before, hash-after and previous text — §D5 makes
the third of those *more* accurate, not different. `VaultBoundary.url(for:)` is unchanged and every
new actor entry point resolves through it, so ADR-0041 §D1's boundary holds by construction rather
than by repetition.

## Relationship to ADR-0041

**§D9 (the disk work moves to one actor) — extended, not amended.** §D9 is true of
`write(_:to:) async`. It is silent about `writeFile`, `moveFile` and `trashFile`, which is why they
still perform their own `FileManager` calls on the main actor. §D1 above brings them in. Nothing
§D9 decided is reversed; its scope grows from «the disk work of a write» to «the disk work».

**§D10 (the hash is computed on the main actor, before the hop) — preserved literally, and made
sufficient for more than one write.** The timing §D10 chose is exactly right and is unchanged: the
hash is still a pure function of text the main actor holds, still recorded before the file can
exist. §D6 changes only the container it is recorded in, because a one-slot-per-path dictionary
cannot describe two writes in flight — a limitation §D10 did not need to consider when the write
path had just become async and nothing else had.

**§D11 (ordering is a per-path sequence the actor stamps) — extended, not amended.** Every word of
§D11 is correct, including its rejection of `Task.detached` fire-and-forget and its insistence that
the number come from the actor. What §D11 could not know is that `apply(_:at:)` would end up as one
of seven writers to `index`. §D1 makes it the only one. §D11's own test remains valid and becomes
one case of several.

**§D12 (`read` stays synchronous) — untouched, and its reasoning survives intact.** §D12's three
reasons — the finding does not name it, the cost is being removed elsewhere, and 25 call sites are
synchronous `@Observable` computed properties SwiftUI evaluates from `body` — are unaffected by
anything here. §D3 and §D5 move two *specific* reads (the watcher's and the journal's) inside the
actor because both already run in async contexts; neither is `VaultSession.read`, which keeps its
signature and its 25 call sites.

**ADR-0001 §D2.3 (files first, index second) — still literal.** The index is still updated
immediately after the write, still never the primary effect of a user action, still disposable. §D1
narrows *which* index updates are possible, not when they happen.

**ADR-0001 §D3.3 and §D3.4 — one strengthened, one widened.** §D3.3's hash recognition survives
§D6's container change intact. §D3.4's prompt now also fires for a write this app made underneath a
dirty buffer (§D7), which is a widening of when it is asked, not a change to what it asks or to the
rule that the app never merges and never discards.

## Alternatives considered

**Issue the sequence number on the main actor, before the hop, and pass it into the actor.**
Rejected, and it is the obvious fix, which is why it is first. It would let the synchronous writers
take a number without awaiting anything and would make §D2 unnecessary. It is wrong because the
number would then record the order in which the main actor *decided* to write, and Swift publishes
no guarantee that an actor executes enqueued jobs in enqueue order. Under any reordering the index
would faithfully record the order of intentions while the disk held the order of outcomes, which is
a guard that reports success while being wrong — strictly worse than no guard, because it would
stop anybody looking.

**Keep both write doors and have the synchronous one bump `appliedSequence` to a large value.**
Rejected. It does not order anything; it makes the synchronous writer win unconditionally, so a
genuinely later async write is dropped and the index goes stale in the opposite direction. Two
writers cannot be ordered by letting one of them cheat.

**Put the clock behind a `Mutex` that both the main actor and the actor can read synchronously.**
Rejected, and this one is genuinely tempting because it preserves the synchronous door. For the
stamp order to equal the disk order, the lock has to cover the byte write as well as the number —
otherwise the window between `store.write` returning and the stamp being taken is itself an
inversion. A lock held across a file write, acquired on the main actor, is the main-actor disk
hitch ADR-0041 §D9 removed, reintroduced under a different name and only under contention, which is
to say exactly when a profile will not show it.

**Refuse overlapping writes to one path — a per-path in-flight set that throws on the second
caller.** Rejected. The second caller is usually the user pressing Cmd+S, and «your save was
refused because a background insert is in flight» is a prompt about a race the user did not cause
and cannot reason about. Serialising is the actor's job and it already does it; the problem was
never that two writes overlap, it is that the bookkeeping could not describe two writes overlapping.

**Make the journal read its «before» from the index instead of from disk.** Rejected. It is the
cheapest possible version of §D5 — the index already holds a `contentHash` per path — and it is
wrong for the reason ADR-0001 §D2.1 makes the index disposable: it is a cache, it can be stale by
construction, and Race 1 is an entire section about it being stale. A journal entry restored from a
cached «before» is an undo that writes bytes nobody ever had.

**Keep `syncOpenNote`'s silent no-op for a dirty buffer and rely on the watcher.** Rejected on the
code: the watcher cannot see it. `reconcile` removes the session's own writes from its output by
hash comparison (`VaultSession+Watching.swift:32-34`), so the question the comment promises is
never asked. Keeping the no-op means keeping a documented behaviour that has never happened.

**Re-check `canOperate(on:)` after the `await` and abort the hand-off when the tab went dirty.**
Rejected. By that point the write has already happened: aborting leaves a heading on disk, a buffer
that does not contain it, and nothing said to anybody — and the buffer's next save silently removes
the heading again. The check cannot be moved earlier either, because the state it asks about is
created during the window. Asking (§D7) is the only answer that loses nothing.

**Make the expected-hash precondition of §D8 mandatory on every write.** Rejected. A new note has
no «before» to expect, a template instantiation means «make this file say this» and a connector
write that must not fail on a concurrent edit is a reasonable thing to want. A mandatory
precondition would add a failure path to every one of ~35 call sites for a hazard that four of them
have. Opt-in with a named error puts the cost where the risk is.

**Fix only Race 3, the one with a reported user-visible symptom.** Rejected. It is the one with
teeth — lost typing, no prompt, no journal entry — and it is a two-line fix in a file that has
nothing to do with the other three. It would also leave the repository with a guard that covers one
of six writers and an ADR (ADR-0041 §D11) claiming that out-of-order application is impossible,
which is the kind of comment that makes the next reader stop looking.

**Do nothing until a defect is observed in use.** Rejected, and stated rather than assumed, because
it is the honest competing position: all four windows are narrow, three of them corrupt only a
rebuildable cache, and this is a single-user offline app. Three answers. The journal one (Race 2)
does not corrupt a cache — it corrupts the record whose only purpose is to be right about the past,
and its failure surfaces as an undo that silently discards a write. «Unlikely» is the argument
ADR-0001 §D3.3 rejected by name when it refused suppression windows, and ADR-0041 §D10 cited that
refusal approvingly nine months later. And the cost of waiting is not zero: every additional writer
added between now and then is written against a guard that looks total.

## Consequences

### Positive

- There is one place in this app that changes a file in the vault, and one place that changes the
  index. Both are doors rather than steps, so the seventh call site inherits the ordering the way
  the eleventh call site inherits ADR-0041 §D1's boundary check — by having no other way in.
- The index and the disk stop being able to disagree as a result of anything this process does.
  Every mutation is stamped in the order the bytes landed, and an older stamp is dropped rather
  than applied.
- `journal undo` becomes correct under concurrency. Today two overlapping writes produce two
  entries claiming the same «before», and undoing the second discards the first; after §D5 each
  entry describes the transition that actually occurred.
- ADR-0001 §D3.4's prompt starts firing in the one case where a conflict was previously guaranteed
  to be silent: the app writing underneath its own dirty buffer (§D7). Nine call sites gain the
  behaviour, not one.
- The watcher's per-path read leaves the main actor (§D3), which removes the same class of cost
  ADR-0041 §D9 removed from the write path and left on the reconciliation path. On a bulk external
  change — an Obsidian sync, a git checkout in the vault — that is the difference between a stutter
  and a freeze.
- `VaultSession.write`'s main-actor prefix gets *smaller*, not larger: the full `NoteStore.read` at
  `:494` disappears into a `NoteStore.text` inside the actor (§D5).
- The two write doors collapse into one, so «which `write` does this call?» stops being a question
  a reader of any call site has to answer.

### Negative

- **The call-site cascade ADR-0041 measured is paid in full**, and it is the reason §D2 was deferred
  once already: ~20 internal wrappers in `Sources/Vault`, `saveOpenNote()` and `restoreVersion(_:)`,
  their four production call sites, and seven test files that today write synchronously and read the
  file straight back off disk. Every one of those tests must `await` and several will need their
  assertions re-sequenced. This is a large, mostly mechanical diff in which a handful of lines
  matter, and the plan's task boundaries have to keep the mechanical changes in separate commits
  from the behavioural ones.
- **`saveOpenNote()` becoming `async` means its four call sites wrap it in `Task { }`,** so two
  saves can be started out of order. §D1 makes that harmless to the index and to the journal; it
  does not make it easy to reason about, and it is a new shape in the editor's hot path.
- **§D7 changes behaviour at nine call sites at once.** A prompt that never appeared will start
  appearing, and one of the nine (the time-block writers) can write a daily note the user is
  editing. That is the correct behaviour and it will read as a regression the first time it
  happens. It needs a line in the release notes, not only a test.
- **§D8's precondition is a new failure mode for callers that adopt it.** «La voce non è stata
  scritta» where previously the write silently won is better, and it is still a refusal the user
  did not ask for and can only resolve by trying again.
- **The four races are not independently shippable.** §D5 and §D6 both need §D1's clock; §D7's
  hand-off wants §D2's async `saveOpenNote` to be the thing it contends with. Splitting them across
  PRs means building the clock twice, which is the same argument ADR-0041 made against splitting
  its own four findings.
- **A concurrency fix whose tests force the interleaving is slow work**, and there is no way to
  make it fast that does not consist of trusting a green suite — which is the thing that let these
  four through.

### Neutral

- No on-disk format changes, so no migration, no version bump, no compatibility window. A vault
  written by the build before this chain and one written after are byte-identical.
- The MCP protocol surface and `perg`'s command surface do not change. Both connectors are already
  `async` end to end (ADR-0041 §D9) and absorb §D1 and §D2 with no structural edit, which is the
  one place this change is free.
- No new file appears in `sharedSources`: `VaultDisk.swift` and `VaultSession+WriteOrdering.swift`
  are already named there (ADR-0007 §D2), and everything §D1 adds lands in those two files or in
  `Sources/Core/**`, which is a full glob.
- The UI does not change, except for §D7's prompt appearing where nothing appeared before.

## Protected-interface proposal

**None, deliberately.** The tempting candidate is `VaultSession.apply` — the sole index door §D1
creates — on the same reasoning ADR-0041 used for `VaultBoundary.url(for:)`: an invariant whose
weakening looks like a simplification in review. It is not proposed, for ADR-0041's own stated
reason for *not* protecting `VaultDisk` and `VaultWalk`: this is internal structure that is about
to move, and the chain that implements this ADR will be refining the signature across several
tasks. An entry added now blocks that chain to protect a function the chain is still writing.

Worth reconsidering after the implementation merges, together with ADR-0041's own deferred
`VaultBoundary.url(for:)` entry — which, per that ADR's recommendation, should also be added after
PR #254 merges and has not been yet.

## References

- ADR-0041 §D9, §D10, §D11, §D12 — `docs/adr/0041-vault-layer-consistency-and-security-cha.md`
- ADR-0001 §D2.1, §D2.3, §D3.3, §D3.4 — `docs/adr/0001-initial-architecture.md`
- ADR-0007 §D3, §D6 — `docs/adr/0007-ai-connector-mcp-over-the-vault.md`
- ADR-0016 §D2, §D3, §D5 — `docs/adr/0016-the-journal-records-a-gesture.md`
- `Sources/Vault/VaultSession.swift:252`, `:256`, `:265`, `:293`, `:490-539` — the two write doors
  and the unguarded index update
- `Sources/Vault/VaultSession+WriteOrdering.swift:20-26` — the guard, and its one caller
- `Sources/Vault/VaultDisk.swift:59-109` — the actor, and `nextSequence(for:)`
- `Sources/Vault/VaultSession+Journal.swift:78`, `:86`, `:131`, `:234` — the move, the trash, and
  the undo preflight whose hash check Race 2 defeats
- `Sources/Vault/VaultSession+Watching.swift:22-41` — reconciliation, and §D3.3's hash suppression
- `Sources/App/VaultController+Editing.swift:13-30`, `:60-78` — the synchronous `saveOpenNote`, and
  `syncOpenNote`'s false comment
- `Sources/App/VaultController+Files.swift:18-29`, `Sources/App/VaultController+Tabs.swift:355-371`
- `Sources/Features/Pratiche/PraticaEntryComposer.swift:44-115` — Race 3, at the line
- `Sources/Core/Tasks/TaskParser.swift:473` — the staleness guard §D8 generalises
- Swift Concurrency Migration Guide, «Atomicity» —
  https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/DataRaceSafety.md —
  «Actors do not guarantee atomicity across suspension points… critical sections should always be
  structured to run synchronously.» Race 2 is that section's counter-example with a file in place
  of an array.
- Review of 2026-09-13 (Codex, `gpt-6-astra`, effort high, via `review-triage-fix`): three CONFIRMED
  findings, all routed REPORT-ONLY by the skill's Swift-concurrency circuit breaker, each verified
  against the code by the orchestrator before acceptance.

## Implementation notes (chain 2026-09-13)

Appended by the implementation chain whose plan is
`docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md`. **Nothing above is altered.**
Three things the plan measured and this ADR asked to have recorded back.

### 1. §D8's adoption list, resolved by the grep §D8 asked the plan to own

`session.read(` followed by `session.write(` in the same function, across `Sources/App`,
`Sources/Features` and `Sources/Connector`, run on the working tree at
`emdash/strict-steaks-argue-n6z2c`. Thirteen call sites adopt `expecting:`.

**Adopt, in the ADR's stated grep scope (9):** `PraticaEntryComposer.insert` (`:57`→`:61`) and
`.mirror` (`:87`→`:91`); `DossierWriter.update` (`:26`→`:32`); `PraticaCommandActions` (`:303`→`:307`);
`PraticheController`'s conversation remap inside `runExclusive` (`:1241`→`:1262`);
`PraticaSyncEngine`'s two patch writes (`:779`→`:878`, `:308`→`:398`) — both need the engine's
injected `write` closure to carry `expecting:`; `RecordingsController.importAccepted`
(`:317`→`:335`); `VaultWrites.undo` (`:277`→`:297`), which keeps its existing pre-`await`
`hashAfter` check for its Italian message and gains `expecting:` as the backstop for the window
that check cannot cover.

`RecordingsController.importAccepted` is **beyond the ADR's named list** and is adopted on merits:
its composed text merges the proposal with `existingNoteText` (ADR-0032 §D9's suppression set), so a
stale read re-imports quotes the note already suppressed, and the two-phase import makes a refusal
clean — phase 2 only runs after phase 1 succeeds, so nothing leaves the machine.

**Adopt inside `Sources/Vault` (4), named in §D8's prose but outside its grep scope:**
`VaultSession+Tasks.apply(_:to:)`, `.captureTask`, `.captureSubtask`, and
`VaultSession+TimeBlocks.setTimeBlocks`/`addTimeBlock`. A refusal at these sites maps onto the
existing `WriteOutcome.stale` case rather than propagating.

**Declined, with reasons, so the next reader does not re-litigate them:** pure reads
(`VaultWrites.summarise`, `VaultController+Routes:132`, `readForEditing:358`, `noteText(at:)`,
`ViewsPane`, `EditorColumn+Text`, `VaultReads`, `VaultViews`); writes that create a file and so
have no «before» (`TemplateSheet`/`NewNoteComposer` → `createNote`, `NuovaPraticaWizard:465`,
`PraticaSyncEngine`'s full render at `:906` — all «make the file say this», which §D8 excludes by
name); and three genuine windows that are **wider** than §D8 can close and are filed as follow-ups
rather than absorbed: `readDiary` → user gesture → `writeDiary`, and the tag-rename and note-rename
batch appliers, whose refusal granularity is a half-renamed vault.

### 2. §D2's cascade is larger than the seven test files §D2 names

§D2's list of seven is correct for what it measured — the files calling `saveOpenNote`,
`restoreVersion` or `write` directly. Once the ~18 internal wrappers become `async`, the transitive
closure is **25 test files and roughly 210 call sites across 46 files**: `BoardDropTests`,
`CapturePanelTests`, `CaptureTests`, `ConnectorTests`, `EventNoteTests`, `GuardrailTests`,
`NoteHistoryTests`, `NoteTabTests`, `NoteTemplateTests`, `PraticheConnectorTests`,
`RelatedLinkTests`, `StarredTests`, `TagRenameTests`, `TaskComposerTests`, `TaskDropTests`,
`TaskMarkerLintTests`, `TaskTests`, `VaultBoundaryCallSiteTests`, `VaultMoveTests`,
`VaultSessionFileOperationsTests`, `VaultSessionJournalTests`, `VaultSessionTests`, `VaultTests`,
`VaultWriteOrderingTests`, `ViewConnectorTests`.

Four second-order surfaces the ADR did not name, all forced by §D2 and none of them a new decision:

- `VaultSession.transaction(_:_:) rethrows` must take an `async` body (6 call sites).
- `VaultPlanApplication.apply(_:writing:)` needs an `async` overload for its four session-level
  callers; the eight `store.write`-level callers keep the synchronous one.
- `ViewQuerySource.move` and `.undo` are **synchronous closure types** (`ViewQuerySource.swift:25`,
  `:27`) and must become `async`, which makes a SwiftUI `.dropDestination` optimistic.
- `EditorColumn+Closing.closeAfterSaving()` and `EditorColumn+Text.replacementsApplied()` sequence
  a save against a tab close and a buffer edit respectively; both must `await` the save before the
  next step or this chain introduces the data loss it exists to prevent.

§D2's scope claim — «this is not new scope; it is ADR-0041's own scope, finished» — still holds.
The measurement was simply short.

### 3. One hazard this chain surfaces and deliberately does not decide

`transaction(_:_:)` sets `currentOperation` on a `@MainActor` object for the duration of its body.
With an `async` body that scope now spans a suspension, so two transactions started from two
`Task { }`s can interleave: the second trips the existing `assertionFailure("transazione
annidata…")` in Debug and, in Release, joins the wrong journal gesture. This is a consequence of
ADR-0041 §D9 rather than of anything decided here, and this chain widens the set of call sites it is
reachable from without closing it. Closing it properly means an actor-owned operation stack, which
is a design decision and belongs in its own ADR. Recorded here, filed as a `TODO.md` follow-up,
**not** fixed in this chain — because a journal gesture that groups the wrong writes is the same
class of defect as Race 2 and deserves the same treatment this ADR gave those four: written down
with a decided shape, not patched blind.
