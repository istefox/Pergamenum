# ADR-0054: The open board proves what it is writing over

- Status: proposed, on the branch `fix/pg-213`. Accepted when that branch merges to `main`.
- Date: 2026-09-22. Written on the worktree `Pergamenum.worktrees/fix__pg-213` at
  `0b739d8f` (clean tree). Every signature, line number and call-site count below was
  grepped in that tree, not recalled.
- **Numbering note:** `0053` is the highest file under `docs/adr/`, there is no
  `docs/architecture/` directory in this repo, and `git log --all -- 'docs/adr/0054*'`
  returns nothing - so no `0054` exists in any commit reachable from any ref. Checked,
  not assumed.
- Source: `TODO.md` **`PG-099`** (P3, bug, opened 2026-09-07) → issue **#213**. The ticket
  was deliberately left open by Stefano at the close of the rename/move/trash
  silent-failure chain, with the note that a real fix «likely means either flushing every
  open Workspace board's pending save before a rename/move/trash writes board-repoint
  changes, or having `save()` refuse/merge when the on-disk file no longer matches what was
  loaded — needs its own analysis before implementing either». This is that analysis.
- **Extends ADR-0043 §D8 (the opt-in `expecting:` hash precondition) and ADR-0046 §D4/§D5
  (the `refusals` channel and its adoption at the note rename/move board repoints), and
  applies ADR-0052 §D1/§D3's rule (an in-memory document records which file it was read
  from) to its second holder.** It amends none of them: the mechanism is unchanged, what
  changes is how many `.canvas` writers use it.
- **Reopens nothing else.** ADR-0025 §D6 stands: a board write is still not journalled, and
  `BoardFileOperations.swift` stays out of `sharedSources` so no connector reaches it.
  ADR-0026 §D10's flush-before-move stays exactly where it is. No SPEC §14 decision, no
  on-disk format, no frontmatter key, no `IndexCache.schemaVersion` bump (stays 4), no
  protected-interface signature. No test is disabled, skipped or deleted.
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.
- **GUI-test budget: zero.** CLAUDE.md caps a new feature at two or three GUI tests, each
  justified in its own ADR. This one adds none: every decision below is observable on
  `WorkspaceController`, `CanvasStore` and two pure functions, and the race is driven
  deterministically in-process (§D9). The 17-test GUI suite does not grow.

---

## Context

### The defect, read out of the code

`WorkspaceController.save()` (`Sources/Features/Workspace/WorkspaceController.swift:591-606`)
writes the open board through `CanvasStore.save(_:board:)`
(`Sources/Vault/CanvasStore.swift:61-70`), which is a plain synchronous
`Data.write(to:options: .atomic)` with no precondition of any kind. It fires about a second
after every edit (`autosaveDelay`, `:155`, debounced in `scheduleSave()`, `:574-581`).

Nothing invalidates the in-memory `document` (`:100`) when the file changes underneath it.
`VaultWatcher.handle(absolutePaths:)` drops every path whose extension is not `md`
(`Sources/Vault/VaultWatcher.swift:72`), so a `.canvas` write never reaches
`VaultSession.reconcile`. `save()`'s own comment already says so, and treats it as a reason
not to record the hash:

> The hash is deliberately dropped rather than recorded as a self-write: `VaultWatcher`
> reports only `.md` paths, so a `.canvas` write never reaches `VaultSession.reconcile` and
> there is nothing for a recorded hash to be recognised against. The board cannot be
> reloaded under the user by the watcher because the watcher never hears about it.

Every clause of that is true. The conclusion drawn from it - that there is therefore nothing
to guard - is what this ADR reverses: the watcher never hearing about the write is exactly
why the controller has to ask disk itself.

Meanwhile seven writers touch `.canvas` files, and six of them do it without asking the open
board anything, each through its own hand-copied unguarded byte write:

| Writer | Line | Guard |
|---|---|---|
| `BoardFileOperations.renameBoard` | `:167-169` | none |
| `BoardFileOperations.moveBoard` | `:280-282` | none |
| `FolderFileOperations.renameFolder` | `:404-406` | none |
| `FolderFileOperations+Move.moveFolder` | `:119-121` | none |
| `NoteFileOperations.rename` | `:237-239` | none |
| `VaultSession+Tasks.writeTaskSource` | `:196-202` | none, and its comment says the precondition «has nothing to attach to there» |
| `WorkspaceController.save` | `:599` | none |
| `VaultSession.renameNote` / `moveNote` | `VaultSession+Files.swift:34,60` | `writeFileGuarded` (ADR-0046 §D5) |

So ADR-0046 §D5 guarded exactly one of them, the note rename/move pair, because that is the
one the chain it belonged to was about.

### The two directions of the same race

**Direction A, the one PG-099 reports.** A rename repoints an open board's `.canvas` on
disk. The board's in-memory `document` is now stale and *stays* stale - nothing tells it.
The next autosave, whether the one already scheduled or one scheduled thirty seconds later
by an unrelated card drag, writes the whole document back and the repoint is gone. No error,
no indicator, no problem-list line: `save()` succeeded.

**Direction B, the mirror.** `repointBoardsPlan` reads a board's bytes at plan time
(`FolderFileOperations.swift:223-227`); the plan is computed, the file is moved, and only
then are the rewrites performed. A board autosave landing inside that window is overwritten
by the repoint write, which re-encodes the document as it was *before* the user's edit. Same
silence. This is the exact failure ADR-0046 §D1 named and closed for note rename and tag
rename, left open here only because the board and folder verbs were not in that chain's
scope.

A comment in `VaultController+Folders.swift:92-96` records the assumption both directions
rest on: `renameBoard` runs «no `canOperateOnFolder` check, because a `.canvas` is not a file
the editor can hold unsaved edits to». True of the *editor*; false of the app. The Workspace
board holds unsaved edits to a `.canvas` for a second at a time, dozens of times a session.

### What this repo already decided about exactly this shape

Three of its own working agreements, all bought with incidents:

1. **ADR-0052 §D1/§D3, now a CLAUDE.md working agreement:** «A ledger, cache or registry the
   app holds in memory and saves back must record which file it was read from. A writer that
   cannot prove it is writing over the file it loaded reads first.» `WorkspaceController
   .document` is the app's second such holder and records nothing.
2. **ADR-0043 §D7, also a CLAUDE.md working agreement:** «A precondition evaluated before an
   `await` is a filter, not a guard.»
3. **ADR-0041, also a working agreement:** «A security or invariant check exposed as a
   separately-callable assertion gets skipped by the next call site, not maliciously - just
   by omission.» Five hand-copied unguarded `.canvas` writes are that sentence's evidence.

---

## Decision

### §D1 - Flushing every open board is not the fix, and is not extended

ADR-0026 §D10's `flushBoard()` (`WorkspaceView+FolderVerbs.swift:255-258`) stays exactly as
it is, doing exactly what it already does: protecting the board that is *itself* being
renamed, moved or trashed. It is not generalised into «flush every open board before any
repoint write». Three reasons, in order of weight:

1. **It closes the wrong window.** The clobbering write in Direction A is not only the
   *pending* save; it is every *subsequent* one. Once the repoint has landed, the in-memory
   document is stale permanently, because no watcher channel carries `.canvas`. A flush at
   T-0 does nothing about the autosave a card drag schedules at T+30s. A fix that only
   drains the queue leaves the defect fully reachable.
2. **It inverts a dependency ADR-0001 §D1 forbids.** The repoint writers live in
   `Sources/Vault`; `WorkspaceController` lives in `Sources/Features/Workspace`, and
   `CanvasStore.swift` is in `sharedSources`, compiled into `perg` and `pergamenum-mcp`.
   Reaching the open board from a writer means an open-board registry on `VaultSession` that
   every future writer must remember to consult - «a step a caller can forget», the shape
   ADR-0041 exists to remove.
3. **It is a check on the wrong side of the suspension.** Even with a registry, the flush
   runs before a plan-then-write sequence that includes a vault walk; a save scheduled during
   it is not covered. ADR-0043 §D7's rule applies verbatim.

### §D2 - The open board records which bytes its document came from

`WorkspaceController` gains `BoardOrigin`, the marker `LedgerOrigin` is to the pratiche
ledger:

```swift
enum BoardOrigin: Equatable {
    case none
    case loaded(board: String, hash: String, document: CanvasDocument)
}
```

One value, not a path property beside a hash property that can drift apart - the failure
ADR-0052 §D1 names. It carries three things because the reconciliation of §D4 needs all
three: *which* board, the hash of the *bytes* read (not of a re-encoding of them), and the
*document* those bytes decoded to, which is the `base` of a three-way comparison.

`document` stays `private(set)` and gains a single private writer,
`replaceDocument(_:origin:)`, used by `attach` (`:187`), `load` (`:276`), `select` (`:327`),
`detach` (`:214`) and `apply` (`:408`, undo/redo). `mutate` (`:375-388`) does not touch the
origin: an in-memory edit changes nothing about what disk holds. `save()` on success advances
the origin's hash and base document to what it just wrote - `CanvasStore.save` already returns
that hash and the call site at `:599` currently discards it.

Holding the base document costs one `CanvasDocument` per open board. It is a value type of
three arrays, copy-on-write, structurally shared with `document` until the first edit.

### §D3 - `CanvasStore.save` gains `expecting:`, and stays synchronous

```swift
@discardableResult
func save(_ document: CanvasDocument, board: String, expecting: String? = nil) throws -> String
```

When `expecting` is non-nil it is compared against the file's current bytes, read immediately
before the atomic write, and a mismatch throws `VaultWriteRefusal.movedOn(board)` with no
byte moved. `nil` - the default - is the pre-existing unconditional write, so all ten
existing call sites keep their exact shape and behaviour.

The error type is `VaultWriteRefusal` (`Sources/Core/Vault/VaultWriteRefusal.swift`), not a
new one. It is already the currency `VaultPlanApplication.apply` classifies into `refusals`
(`:41,77`), already has the Italian sentence the UI shows
(`«\(path)» è cambiato da quando questa scrittura è partita, non lo tocco`), and lives in
`Sources/Core`, so the shared-sources targets see it.

A read + a compare + a write is not an atomic sequence. Two things make that acceptable and
both are stated rather than implied:

- **In process it is effectively atomic.** The three statements contain no `await`. Every
  other `.canvas` writer in the app is either main-actor-synchronous (`BoardFileOperations`,
  `FolderFileOperations`, `VaultSession+Tasks`, all reached from `@MainActor VaultSession`)
  or the `VaultDisk` actor, reached from the main actor through an `await`. None of them can
  interleave inside a main-actor synchronous run of three statements.
- **Against another process it narrows, it does not close.** Obsidian or an iCloud Drive
  replica can still land between the read and the write. That is the identical limit
  `VaultDisk.writeFile`'s own `expecting` check has (`VaultDisk.swift:327-332`) and it is
  accepted on the same terms.

**Rejected: routing the board write through `VaultSession.writeFile`**, which already carries
this precondition. Two reasons, either sufficient. The door is `async`, and
`flushPendingSave()` (`:585-589`) has four synchronous callers - `load` (`:273`), `select`
(`:324`), `flushBoard()` (`WorkspaceView+FolderVerbs.swift:257`) and `WorkspaceView`'s
`.onDisappear` (`WorkspaceView.swift:88`) - the last two of which are SwiftUI view code
reaching seven sidebar verbs; ADR-0043 measured this exact cascade at three to four times its
own estimate (~210 call sites, 46 files, 25 test files) when it deleted the synchronous note
door. And it would route a board write into the journal path ADR-0025 §D6 deliberately keeps
it out of, while requiring `WorkspaceController` to hold a `VaultSession` it does not have
today (it holds a `CanvasStore` and a weak `VaultController`, `:128,136`).

### §D4 - A refused autosave is reconciled, not dropped and not forced

The refusal branch is not a failure branch. It re-reads the board and asks one pure function
what the external writer did, using the base document §D2 kept:

```swift
extension CanvasDocument {
    enum Reconciliation: Equatable {
        case adopted(CanvasDocument)
        case diverged([String])
    }
    static func reconcile(mine: Self, base: Self, theirs: Self) -> Reconciliation
}
```

The rule, stated in one sentence: **a `.file` node's path is a fact about the filesystem, not
a property of the board, so where disk and memory disagree about one, disk wins - and where
they disagree about anything else, nothing is decided automatically.**

Mechanically: compute the difference between `base` and `theirs`. If every difference is the
`path`/`subpath` of a `.file` node whose id is also in `mine`, apply exactly those paths to
`mine` and answer `.adopted`. Anything else - a node added or removed, an edge changed, a
node's text or geometry changed, a top-level `unknown` key changed - answers `.diverged` with
the node ids or key names that could not be spoken for.

This is a three-way comparison and not a two-way merge on purpose. Two-way cannot work here:
in the PG-099 case `mine` differs from `theirs` in the user's unsaved edit *and* in the
repoint at once, so «they differ only in file paths» is false exactly when the fix is needed,
and «the user drew this arrow» is indistinguishable from «the external writer added this
edge». Keeping `base` makes the verdict exact rather than heuristic, which is the standard
ADR-0043 and ADR-0052 both hold.

On `.adopted`: the controller replaces `document` with the merged one, sets the origin to
`theirs`' hash and document, and retries the save **once**. The user's unsaved edit and the
external repoint both survive, with no interaction and no message. A second refusal means a
third writer landed inside the retry; it is treated as `.diverged` rather than looped.

On `.diverged`: nothing is written, nothing is discarded, and §D5 decides what the person
sees.

### §D5 - A diverged board says so on the board, and is resolved only by a choice

ADR-0001 §D3.4's rule - never merge, never discard: ask - applied to the board, in the shape
the editor already uses for the same situation (`NoteTab.externalChangePending`,
`EditorColumn+Conflict.swift`) rather than by reusing its code, since a board has no tab.

`WorkspaceController.hasUnsavedChanges` (`:120`) becomes a computed `Bool` over a new stored
`saveState`:

```swift
enum SaveState: Equatable { case saved, pending, conflicted(reason: String) }
var hasUnsavedChanges: Bool { saveState != .saved }
```

`hasUnsavedChanges` keeps its name, its type and its meaning, so `BoardChrome.swift:30,35,36`
and the four test assertions on it keep passing unchanged.

While `conflicted`:

- **autosave neither writes nor retries.** `save()` returns early. A retry per edit would
  refuse once a second and fill the problem list.
- **the board's own indicator says so.** `BoardChrome`'s `Salvato`/`Salvataggio…` label gains
  a third state, «Conflitto», with the two verbs attached to it: «Mantieni le mie modifiche»
  (adopt `theirs`' hash as the expectation without touching `document`, so the next save
  writes and wins) and «Ricarica dal disco» (replace `document` and the origin with `theirs`,
  losing the in-memory edit, by explicit choice). Non-modal: an autosave conflict is not a
  reason to seize the window.
- **`recordProblem` still fires,** once per entry into the conflicted state, carrying
  `VaultWriteRefusal.movedOn(board).description` plus the diverged ids - so the failure is in
  Impostazioni → Problemi too, where `DayController`, the editor and `save()`'s existing catch
  block already report.
- **`detach()` gets the last word.** It does not flush - it cancels the pending task
  (`:206-207`) - and the flush that should have happened is `WorkspaceView`'s `.onDisappear`
  (`WorkspaceView.swift:88`), which now returns early for a conflicted board before `detach()`
  runs (`WorkspaceView.swift:183`). That is the one remaining path where the work disappears,
  so `detach()` records a problem naming the board. It does not block the close: refusing to
  close a window over an autosave conflict is worse than the loss it prevents.

`recordProblem` alone was considered and rejected as the whole answer: a person who never
opens Impostazioni sees nothing, keeps editing, closes the window, and the edits die in
`detach()`. That is the silent loss the ticket is about, moved one room over.

### §D6 - Every remaining `.canvas` writer adopts the precondition, through one door

The five hand-copied unguarded byte writes become one:

```swift
extension CanvasStore {
    /// The one guarded write for a planned `.canvas` repoint.
    func writeRepoint(_ change: VaultFileChange) throws
}
```

It compares the file's current bytes against `change.expectedHash`
(`VaultFileChange+ExpectedHash.swift:11`, the expression ADR-0046 §D1 already made canonical),
throws `VaultWriteRefusal.movedOn(change.path)` on a mismatch, and otherwise writes
atomically. `VaultPlanApplication.apply`'s synchronous overload already routes that error into
`refusals` (`:41`), so no plumbing is invented.

`change.expectedHash` is valid at `change.path` in every case, including the board that is
itself moving: `repointBoardsPlan` reads the bytes at the old path and sets `path` to
`writePath`, the post-move location, which by then holds those same bytes
(`FolderFileOperations.swift:241-258`).

`refusals` is added to `BoardFileOperations.RenameOutcome` (`:126-129`) / `MoveOutcome`
(`:241-244`) and `FolderFileOperations.RenameOutcome` (`:340-345`) / `+Move.MoveOutcome`
(`:67-72`) - declared after the existing fields so every memberwise call stays valid, the
compatibility rule ADR-0046 §D4 already used - and surfaced by the four verbs in
`VaultController+Folders.swift` with `VaultWriteRefusal.movedOn(refusal).description`,
copying verbatim what `VaultController+Files.swift:49-51,74-76` already does for note rename
and move.

`VaultSession+Tasks.writeTaskSource` adopts it too, on its board branch: it reads the board,
edits one node's text and saves (`:196-202`), which is the same read-modify-write over an
interval that the open board can write inside.

A refusal never stops the loop and nothing already written is rolled back - ADR-0046 §D3's
rule, unchanged.

### §D7 - `VaultWatcher` is not extended to `.canvas`

The obvious alternative - report `.canvas` paths, let the open board reload on an external
change - is rejected with a specific reason, not a preference. The watcher feeds
`VaultSession.reconcile`, whose self-write suppression matches hashes recorded by
`VaultSession.write`/`writeFile` in `selfWrittenHashes` (ADR-0043 §D10).
`CanvasStore.save` does not go through the session and cannot record there, so **every
autosave would come back as an external change** and reload the board under the person
mid-edit: the same defect pointed the other way, and a worse one, because it fires on the
happy path rather than on a race. Making board writes go through the session to fix that is
§D3's rejected async cascade. The precondition buys the same protection with no second event
channel and no new suppression bookkeeping.

### §D8 - Scope boundary: the note half of the board and folder verbs stays open

`BoardFileOperations.renameBoard` (`:160-162`), `FolderFileOperations.renameFolder`
(`:398-400`) and `NoteFileOperations.rename` (`:231-233`) also rewrite **notes** through an
unguarded `store.write($0.after, to: $0.path)`. The same staleness applies: a note open and
dirty in the editor can have its links rewritten from a plan read before the user's edit, and
these writes do not go through `VaultSession.write`, so `syncOpenNote`'s conflict prompt
(ADR-0043 §D6) never sees them either.

That is a real second defect and it is deliberately **not** fixed here. It is a different
buffer, a different surface and a different refusal message, it needs the same `refusals`
plumbing through outcomes that already have live test assertions on their fields, and folding
it in would roughly double this chain. It is recorded as a follow-up ticket rather than left
unmentioned - the treatment ADR-0046 §D5 gave `PG-161` and ADR-0050 §D6 gave `PG-170`.

Also recorded, and also not acted on: `NoteFileOperations.rename(_:to:knownPaths:)` and
`move(_:toFolder:)` have no caller in `Sources/` at all - `VaultSession+Files` builds a
`NoteFileOperations` (`:13`) but uses only `renamePlan`, `movePlan` and `danglingLinks`. They
are reachable only from `Tests/NoteFileOperationTests.swift` and
`Tests/NoteRenameCharacterizationTests.swift`. A second, unguarded implementation of note
rename that nothing calls is worth a decision of its own; deleting it is not this chain's to
take, since those characterization tests pin bytes deliberately.

### §D9 - Acceptance is a deterministic in-process race test, never a timing test

ADR-0046 §D11's rule, unchanged: no test sleeps, spawns a competing `Task` or races a
debounce. The race is driven by *being* the external writer:

1. open a board, edit it (the debounce is now scheduled and `saveState == .pending`);
2. write the repointed `.canvas` to disk directly, exactly the bytes
   `BoardFileOperations.renameBoard` would have written;
3. call `flushPendingSave()`, which is the same `save()` the debounce would have called;
4. assert the file on disk holds **both** the repointed node path **and** the new card, and
   `saveState == .saved`.

Direction B is driven the same way, at the named seam rather than a re-spelling of it:
`CanvasStore.writeRepoint` is called with a `VaultFileChange` whose `before` is stale, and the
refusal is asserted on `VaultPlanApplication.Outcome.refusals`.

---

## Alternatives considered

1. **Flush every open board before any repoint write** (the ticket's first proposal).
   Rejected: it closes the wrong window - the clobbering save is the *next* one, not the
   pending one, because nothing ever invalidates the in-memory document (§D1.1); it requires
   `Sources/Vault` to reach `Sources/Features/Workspace` through an open-board registry that
   every future writer must remember (§D1.2); and the flush sits on the wrong side of the
   plan-and-write sequence (§D1.3). Kept, unchanged, for the narrow case it already covers.
2. **Refuse and stop there** (the ticket's second proposal, taken literally). Rejected as a
   whole answer: a refusal with no reconciliation leaves the board permanently unsavable -
   every subsequent autosave refuses against the same stale expectation - and the user's work
   dies at `detach()`. Refusal is the mechanism (§D3); §D4 and §D5 are what make it safe.
3. **Reload the board from disk on a refusal.** Rejected: it discards the user's unsaved edit
   silently, which is the same data loss the ticket reports, with the beneficiary swapped.
   Retained only as the explicit «Ricarica dal disco» choice in §D5.
4. **Two-way merge, no base document** (memory wins for everything, disk wins for `.file`
   paths). Rejected: without `base` a difference between memory and disk cannot be attributed
   - «the user drew this arrow» and «the external writer added this edge» are the same
   observation - so the `diverged` verdict would be guesswork exactly where it matters.
   Keeping one extra copy-on-write `CanvasDocument` makes it exact (§D4).
5. **Route the board write through `VaultSession.writeFile`,** which already has `expecting:`.
   Rejected: `flushPendingSave` has four synchronous callers, two of them SwiftUI view code,
   and ADR-0043 measured that async cascade at 3-4x its estimate; and it would put a board
   write into the journal path ADR-0025 §D6 deliberately excludes it from (§D3).
6. **Extend `VaultWatcher` to `.canvas` and reload on external change.** Rejected: the
   watcher's self-write suppression is keyed on `VaultSession`'s own hashes, which
   `CanvasStore.save` cannot record, so every autosave would echo back as an external change
   and reload the board mid-edit - the defect inverted, and on the happy path (§D7).
7. **Extend `canOperate(on:)`'s unsaved-buffer refusal to boards** - refuse a rename while any
   open board is dirty, as the app already refuses one while a note is dirty
   (`VaultController+Files.swift:22-28`). Rejected: a board is dirty for about one second at a
   time, dozens of times a session, so the refusal would fire constantly and for a condition
   the person cannot see or act on; and it makes an unrelated board's state a reason to block
   a note rename. The note rule works precisely because a dirty note is a visible,
   user-controlled state.
8. **Write a side-car copy of the in-memory document on a conflict** and report its path.
   Rejected: it turns a resolvable conflict into a file in the vault the person now has to
   reconcile by hand, and principle 1 means that file is real and permanent. §D5's two verbs
   resolve it in place.

---

## Consequences

### Positive

- The PG-099 loss is closed in both directions: the open board cannot overwrite a repoint it
  did not see, and a repoint cannot overwrite a save that landed after its plan was read.
- In the common case the user sees nothing at all: the repoint and the unsaved edit both
  survive, automatically, because §D4's rule can speak for the only change class the in-app
  writers produce.
- Five hand-copied unguarded `.canvas` writes become one door - ADR-0041 §D4/§D5's move,
  applied to the writes that chain left behind. The next `.canvas` writer inherits the
  precondition instead of needing to remember it.
- The four board and folder verbs gain the `refusals` channel the note verbs already have, so
  «riferimento non aggiornato» stops being the only thing those outcomes can say.
- `VaultWriteRefusal` is now the single currency for «I am not writing over a file that moved
  on» across the note door, the board door, the batch appliers and the board editor.
- Two stale claims in the codebase are corrected rather than left to mislead
  (`VaultPlanApplication.swift:16-19`, `VaultSession+Tasks.swift:186-188`), plus the comment
  in `VaultController+Folders.swift:92-96` asserting that a `.canvas` holds no unsaved edits,
  and `save()`'s own comment at `:594-598`.

### Negative

- `WorkspaceController` gains state it did not have: an origin marker with a base document,
  a three-case save state, and a reconciliation branch in `save()`. The file is at 607 lines;
  the conflict-resolution verbs land in an extension (`WorkspaceController+Conflict.swift`)
  rather than in the body, or SwiftLint's `type_body_length` error threshold becomes the next
  ticket - `PG-202` is open for exactly that on a neighbouring Workspace file.
- A guarded board write costs one extra read per save. A `.canvas` is small and the write is
  debounced to at most one per second per board; this is the same cost ADR-0046 §D5 accepted
  for the board repoints.
- The conflicted state is a new thing a person can be in, and it is sticky until they choose.
  A board left conflicted and forgotten still holds unsaved work - visibly, in the indicator,
  which is the whole point, but visible is not the same as resolved.
- The base document doubles a board's in-memory footprint until the first edit diverges the
  copy-on-write buffers. For any board a person can actually use this is negligible; it is
  recorded because it is real.
- The protection is against in-process writers. Another process writing between the read and
  the write still wins silently (§D3), unchanged from `VaultDisk.writeFile`'s own limit.

### Neutral

- No on-disk format changes. A `.canvas` written after this chain is byte-identical to one
  written before it for the same document.
- `IndexCache.schemaVersion` stays 4. Nothing here is cached.
- No connector surface changes. `CanvasStore.swift` is in `sharedSources` (`Project.swift:105`)
  and gains two additive members with defaulted or new names, so `perg` and `pergamenum-mcp`
  keep compiling and gain no capability; `BoardFileOperations.swift` and
  `FolderFileOperations.swift` stay out of `sharedSources`, so ADR-0025 §D6's exclusion is
  untouched.
- `hasUnsavedChanges` keeps its name, type and meaning, so `BoardChrome` and the four tests
  reading it are untouched by §D5.
- ADR-0026 §D10's `flushBoard()` is untouched.

---

## References

- `TODO.md` `PG-099` → issue #213; branch `fix/pg-213`.
- Plan: `docs/plans/pg-213-workspace-autosave-race.md`.
- ADR-0043 §D5/§D7/§D8/§D10 - the `expecting:` precondition, the read-inside-the-actor rule,
  `selfWrittenHashes`, and «a precondition before an `await` is a filter».
- ADR-0046 §D1/§D3/§D4/§D5/§D11 - `writeGuarded`/`writeFileGuarded`, the `refusals` channel,
  «a refusal never stops the loop», and «no timing-based interleaving test».
- ADR-0052 §D1/§D3 - the origin marker and the one write door, the rule §D2 applies here.
- ADR-0025 §D6 - a board write is not journalled and is not reachable from a connector.
- ADR-0026 §D10 - flush before a move, for the board that is moving.
- ADR-0041 §D2/§D4/§D5 - `VaultBoundary` as a resolver, and one shared apply-plan helper
  replacing drifted copies.
- ADR-0001 §D1/§D3.4 - the layering rule, and «never merge, never discard: ask».
- ADR-0053 - the in-process merge gate these tests are written for.
