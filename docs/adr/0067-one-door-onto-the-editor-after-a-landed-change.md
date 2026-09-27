# ADR-0067: One door onto the editor after a landed change

- Status: **proposed**. Not on `main`; it flips to `accepted` with the merge PR and its
  first-parent merge hash (`docs/adr/README.md` rule 2).
- Date: 2026-09-26. Written before the implementation, against `3fcde6f0` (tree clean apart from
  `SPEC.md`). `origin/main` is `1e09448e`. Its net difference from this tree is `TODO.md` alone,
  so every line number below holds on both.
- **Numbering note.** 0065 is the highest ADR on this branch and on `origin/main`. This chain
  writes two ADRs, 0066 (this one) and 0067 (Pratiche sync integrity, its companion). No ref
  holds a `docs/adr/0066*` or `docs/adr/0067*` today (`git log --all` is empty for both). Both
  numbers are rechecked immediately before the merge. If another chain lands 0066 or 0067
  first, both files are renumbered with `git mv` and entered in the register, per the README.
- **Renumbering note (2026-09-27).** Written and committed as ADR-0066 (`34346cda`). PR #598 landed
  ADR-0066 (Workspace board lifecycle) on `main` first, so this record moved to 0067 and its
  companion to 0068 before this branch merged. Every citation of this decision in the branch
  follows it; main's ADR-0066 is untouched.
- **Path note.** The architect's write scope names `docs/architecture/**`. That directory does not
  exist in this repo. Every ADR lives at `docs/adr/NNNN-<slug>.md`, the path `CLAUDE.md`'s chain
  index links. ADR-0054, 0055, 0058 and 0064 recorded the same deviation.
- Source: `SPEC.md` (Approved 2026-09-26), issue **#571** (`PG-257`, Audit Fable chain 4). The
  decision itself is ROADMAP Chain 16 item 1, pulled forward into this chain by the user.
- **Extends ADR-0058 §D1/§D2/§D3 and ADR-0064 §D3/§D4. Closes ADR-0058 §D7. Amends one clause of
  ADR-0058 §D6:** the name `syncOpenNote` stops being kept (§D5 below). The per-buffer rule
  (`OpenNote.catchUp(to:)`), the writer-by-id rule and `closeTabs(_:ofVanishedNote:)` stay the
  only rules. What changes is who calls them. It is no longer each writer, one call site at a
  time. It is one handler the session calls for every change it lands.
- **Reopens nothing else.** No on-disk format, no frontmatter key, `IndexCache.schemaVersion`
  stays 5, and no protected interface changes. `VaultSession.write` gains one defaulted
  parameter in a shared file. `perg` and `pergamenum-mcp` never pass it and never subscribe,
  so they build unchanged and behave unchanged (§D4).

## Context

A write this app makes itself is self-hashed, so `VaultSession.reconcile` drops it and the
watcher never reports it (ADR-0043 §D3.3, working as designed). The caller's catch-up is
therefore a tab's only chance to hear of it. ADR-0058 made that catch-up reach every tab
(§D2) and settled the per-buffer rule (§D1). It kept the catch-up as a step each writer
performs by hand, and §D7 named seven writers that never perform it:

- the note-rename link rewrite;
- `renameTag`;
- `undoJournalledWrites`;
- `moveOnBoard`;
- Pratiche `ensuringLocalID`;
- the composer's diary mirror;
- the Plaud re-import.

ADR-0058 §D7 recommended a post-write notification from `VaultSession.write`. It left open one
product question for that design: whether forty dirty tabs get forty banners or one summary.

Measured at `3fcde6f0`:

- **Twelve explicit `syncOpenNote(with:)` calls.**
  - `VaultController+TimeBlocks.swift:40`, `:61`, `:97`
  - `+Categories.swift:86`
  - `+Notes.swift:82`
  - `+Diary.swift:35`
  - `+TaskDrop.swift:33`
  - `+Editing.swift:64`
  - `+Tasks.swift:20`, `:66`
  - `+Routes.swift:180`
  - `Features/Pratiche/PraticaEntryComposer.swift:130`
- **The editor's own save** at `+Editing.swift:33`, through `syncOpenNote(with:savedBy:)`.
- **Six manual follow-ups after a move or a trash.**
  - `VaultController+Files.swift:54`, `:79` (inside `Task { await rescan(); movedNote(...) }`)
  - `+Files.swift:106` (`trashedNote`)
  - `+Folders.swift:64`, `:89`
  - `+Move.swift:184` (`follow`)
- **Nine Pratiche writers go around the session entirely.** Raw `FileManager` moves, copies,
  trashes, restores and two `try? text.write` calls. ADR-0068 routes them through the session.
  Once routed, they need exactly the catch-up this ADR makes automatic. Since ADR-0064, the
  watcher reads a raw move as an external deletion and closes the tab.

"A step a caller can forget" is the shape `CLAUDE.md`'s working agreement names: a check exposed
as a separately callable step gets skipped by the next call site, by omission. ADR-0041's
resolver pattern answers it: make the step the only way the value is obtained. For a
write, the value is "the change landed". The session is the one place that knows that.

## Decision

### §D1 — The session announces every landed change, synchronously, to one subscriber

`VaultSession` gains a **landed change**, one of three cases:

```swift
enum LandedChange: Equatable, Sendable {
    case written(WriteResult, origin: UUID?)
    case moved(from: String, to: String)
    case trashed(String)
}
```

It also gains one subscriber, `@ObservationIgnored var landedChangeSubscriber: (@MainActor
(LandedChange) -> Void)?`, and one internal `announce(_:)` that calls it. The stored property
sits in `VaultSession`'s class body in `VaultSession.swift`, because a stored property cannot
live in an extension. The enum, `announce` and the generation below go in a new shared file,
`Sources/Vault/VaultSession+LandedChanges.swift`, added by hand to `sharedSources` in
`Project.swift` because `VaultSession.write` calls it.

**Where it is announced.** Only after the change is real. The index has been updated (`apply`)
and the self-write bookkeeping reconciled. A subscriber that reads the index or the disk
during delivery therefore finds both agreeing with the change.

| Door | File | Announces | When |
|---|---|---|---|
| `write(_:to:expecting:expectingAbsent:requiringExistingFolder:origin:)` | `VaultSession.swift` | `.written(result, origin:)` | after `apply([mutation])`, before `return` |
| `moveFile(from:to:)` | `VaultSession+Journal.swift` | `.moved(from:to:)` | after the journal record, last |
| `trashFile(at:)` | `VaultSession+Journal.swift` | `.trashed(path)` | after the journal record, last |
| `renameFolder` | `VaultSession+Folders.swift` (app-only) | one `.moved` per carried note | after the note-id relocation |
| `trashFolder` | `VaultSession+Folders.swift` (app-only) | one `.trashed` per trashed note path | after the note-id forget |
| `moveItems`, folder case | `VaultSession+Move.swift` (app-only) | one `.moved` per carried note | after `folderOperations.moveFolder` |
| `restoreFromOutside(_:to:)` (ADR-0068 §D3) | `VaultSession+LandedChanges.swift` | `.written(result, origin: nil)` | after `apply` |

The three folder doors move or trash with raw `FileManager` calls through `FolderFileOperations`,
not through `moveFile`/`trashFile`. They already return `movedNotes`/`trashedNotePaths`, which is
exactly what the six manual follow-ups iterated. A folder is not something an editor tab shows.
Its notes are, so each carried note is announced. Undo and redo of a batch move go through the
same doors (`performInverse`), so they announce too, the same way the ledger relocation already
follows both directions (`VaultController+Move.swift:186`).

**Where nothing is announced.**

- **A rehearsal.** Every door returns before the disk touch when `isDryRun` is set, so it
  returns before the announcement too.
- **A refused write or a failed disk operation.** Both throw before `apply`.
- **The `.canvas` door, `writeFile`.** No editor tab shows a `.canvas` file, and boards have
  their own origin and conflict model (ADR-0054).
- **The `.eml` sidecars and attachment bytes.** These never pass through the session
  (ADR-0068 §D1, SPEC Out of scope).

**Delivery is synchronous.** The subscriber runs on the main actor, inside the door, before the
door returns to its caller. No keystroke can land between the write and the catch-up. That is
the window in which a clean tab's next save would revert the write.

### §D2 — The writer is named by its caller, never inferred

`write` gains `origin: UUID? = nil`. The session never interprets it. It only echoes the value
back in `.written`. `saveOpenNote()` passes the writer tab's id, which it already captures
before the `await` (ADR-0058 §D3). Every other writer passes nothing.

The handler (§D3) applies ADR-0058 §D3 to the tab whose `id` equals `origin` and still shows the
path. That tab takes `savedText` only and has its prompt cleared. It keeps any text typed during
the suspension, and it never gets a prompt for its own save. Every other tab showing the path
gets ADR-0058 §D1's `catchUp(to: .text(result.text))`. `restoreVersion(_:)` passes no origin,
which is ADR-0058 §D4's own rule. After a restore the writer gets §D1 like everyone else: a buffer
still dirty after the save is asked, never overwritten.

### §D3 — One handler on the controller: `landed(_:)`

`VaultController.landed(_ change: VaultSession.LandedChange)` is `internal`, so a test can call
it with a hand-built change. That is the same reason ADR-0058 §D3 gave for
`syncOpenNote(with:savedBy:)`, the method it replaces. It lives in
`VaultController+TabFollowUps.swift`, beside `closeTabs(_:ofVanishedNote:)`, which it calls.

- **`.written(result, origin)`.** Through `updateTabs(showing: result.path)`: the origin tab takes
  §D2's writer rule, every other tab takes `catchUp(to: .text(result.text))`. This is the body of
  `syncOpenNote(with:savedBy:)`, unchanged. With `origin == nil`, it is the body of
  `syncOpenNote(with:)`.
- **`.moved(from, to)`.** `recentNotePaths` follows, as `movedNote` did. Every tab showing `from`,
  in every column, is handled by its own state:
  - **Clean tab.** It takes a fresh `readForEditing(to)`, as `movedNote` did.
  - **Dirty tab.** It keeps its `text`, its `savedText` and any pending prompt. Only
    `relativePath` and `title` follow.

  This is a deliberate widening. Before, `movedNote` replaced a dirty buffer with the disk
  read, and that was safe only because every app move refuses a dirty note first
  (`canOperate(on:)`). The Pratiche moves ADR-0068 routes through `moveFile` have no such
  refusal. Discarding a dirty buffer is what ADR-0001 §D3.4 forbids. The app's own move verbs
  keep their refusal, so for them nothing observable changes.
- **`.trashed(path)`.** ADR-0064's rule, the one `reconcile(_:)` already applies to a `.deleted`
  external change. Each tab showing the path answers `catchUp(to: .deleted)`:
  - `.vanished` tabs (clean) close together through `closeTabs(_:ofVanishedNote:)`.
  - `.asked` tabs (dirty) get the «Scarta ed elimina» / «Tieni la mia versione» banner.

  `closeTabs` is then called for the path even with no ids, so it leaves `closedTabPaths` and
  `recentNotePaths` (ADR-0064 §D4). A trash reaches a tab twice: once here and once through the
  watcher, since `trashFile` records no absence marker (ADR-0064 §D6, R-09). The second arrival
  finds either no tab or a tab already asking the same question, so the tab closes once and is
  asked once. Before, `trashedNote` closed every tab regardless of state. The app's own trash
  verbs refuse a dirty note first, so the difference is reachable only from Pratiche.

### §D4 — The subscription follows the controller's session, and only it

`VaultController.open(_:)` clears the outgoing session's `landedChangeSubscriber` before it
replaces `session`, then installs the handler on the new one. `close()` clears it. The installed
closure captures the controller and the session weakly and guards `self.session === session`
before calling `landed(_:)`. A write still completing on a session being left can then never
reach the next vault's tabs. That is ADR-0052's cross-vault lesson, applied to the editor.

`perg` and `pergamenum-mcp` never install a subscriber, so `announce` is a nil-check there. Neither
connector gains behaviour, and no JSON shape changes.

### §D5 — The explicit steps are deleted, not kept beside the door

Keeping `syncOpenNote(with:)` beside the door would leave exactly the step a caller can forget.
It would also deliver twice to the writers that remember it. The following are deleted as
callable steps:

- `syncOpenNote(with:)`, `syncOpenNote(with:savedBy:)` (`VaultController+Editing.swift:92`,
  `:113`);
- `movedNote(from:to:)`, `trashedNote(at:)` (`VaultController+TabFollowUps.swift:14`, `:25`).

Their bodies become `landed(_:)`'s three branches. All twelve `syncOpenNote(with:)` sites and all
six manual follow-ups listed in Context are removed. The save site stops calling anything after
the write: it passes `origin:` instead. The rename paths at `+Files.swift:54` and `:79` keep their
`Task { await rescan() }` and lose only the follow-up inside it. `.moved` now arrives from
`moveFile`, after `apply` has put the new path in the index, so `readForEditing(to)` no longer
depends on the rescan having run.

`PraticaEntryComposer.handOff(_:notePath:result:)` loses its `result:` parameter. The write in
`insert` has already caught every open copy up by the time `handOff` runs. `handOff` only opens
the note and places the caret.

This retires the one clause of ADR-0058 §D6 that kept the name `syncOpenNote`. The rest of §D6
stands: `bufferText(for:)`, `noteText(at:)`, `acceptExternalChange()` and `keepLocalVersion()`
stay as they are. `VaultSession.addStructuralLink` keeps its `(created:, written:)` return
(ADR-0058 §D5). The controller no longer reads `written` for a catch-up, but the return still
reports which writes landed when the second one fails.

### §D6 — A per-path landed generation, observable

`VaultSession` gains `private(set) var landedGenerations: [String: UInt64]`. It is observed, not
`@ObservationIgnored`. `landedGeneration(at:) -> UInt64` returns 0 for a path never touched.
`announce` bumps it for every path a change touches: the written path, both ends of a move, or
the trashed path. It lives with the session and is never persisted.

It exists for one reader today, the Pratiche inspector (ADR-0068 §D16, SPEC item 15), which keys
its reload on the selected `pratica.md`'s generation. It is a UI signal, not a clock. The
per-path sequence ADR-0043 §D1 stamps inside `VaultDisk` stays the only ordering authority. That
sequence is actor-isolated and advances on every read the watcher makes. Neither property suits a
view.

### §D7 — Many dirty tabs, one banner each

ADR-0058 §D7 asked whether a batch writer should raise one banner per dirty tab or a single
summary. The approved SPEC's edge case answers it: a write that lands while another tab on the
same path is dirty gives that tab the ADR-0001 §D3.4 prompt, the same as an external change. A
batch (`renameTag` over forty notes open dirty in forty tabs) therefore raises forty inline
banners, one per tab, each on its own tab. No summary surface is added. This ADR records the
rule so a later reader does not take its absence for an oversight. It is flagged to Stefano for
confirmation at review (gate G1 in the plan), because ADR-0058 §D7 framed it as a product
question.

### §D8 — What the door deliberately does not reach

- **Boards.** Out of scope (SPEC). `WorkspaceController` keeps ADR-0054's `BoardOrigin` and
  conflict model. The quit-flush gap for boards is #506.
- **The Diario pane.** `DiaryController` holds its own buffer behind ADR-0057's origin marker and
  its own write door. It is not an editor tab and does not subscribe. An editor tab showing the
  daily note is caught up like any other tab.
- **Binary files.** No byte door exists on the session (SPEC Out of scope).

## Alternatives considered

1. **Keep the explicit calls and add the hook only for the writers that forget.** Rejected (SPEC
   Decisions). It halves nothing. Every new writer must still decide which camp it is in, and a
   writer that calls `syncOpenNote` after a write the hook already delivered prompts a dirty tab
   twice for the same change.
2. **Deliver through `NotificationCenter` or an `AsyncStream`.** Rejected on the delivery timing.
   Both deliver on a later turn of the run loop or a consumer task. A keystroke can land between
   the write and the catch-up, and a clean tab's next save then reverts the write, which is the
   exact defect ADR-0058 closed. `NotificationCenter` is also process-global and untyped, so two
   windows' sessions would need their own filtering. An `AsyncStream` needs a consumer task tied
   to the controller's lifetime and a `finish()` on every exit. The closure matches the three
   hooks `VaultController` already uses (`didRelocateFolders`, `didTrashFolder`,
   `didChangeExternally`).
3. **Identify the writer through a task-local, as ADR-0050 does for the journal gesture.**
   Rejected. A task-local is implicit: every write made inside the save's task scope would carry
   the writer's id, including any write a future pre-save step makes to another path. Someone
   reading `saveOpenNote` would also not see the parameter the whole rule depends on. An explicit
   defaulted argument costs one parameter and is visible at the only call site that passes it.
4. **Identify the writer through an in-flight registry keyed by path.** Rejected. Two tabs showing
   the same path can both save and overlap across the actor hop. A path-keyed registry then has
   to guess which save a result belongs to, and a guess here is a false prompt or a lost one.
5. **Announce from `VaultDisk`.** Rejected. The actor has no main-actor subscriber, and the index
   is applied on the session after the hop. An announcement before `apply` would let the `.moved`
   handler's `readForEditing(to)` read an index that does not hold the new path yet.
6. **Observation only: tabs watch the generation (§D6) and re-read the disk.** Rejected. ADR-0058
   §D1 catches a tab up to the write's own result, never to a re-read. The disk may already have
   moved on again (`composerHandOffUsesItsWriteResultInsteadOfRereadingDisk` pins this).
   Observation also delivers on the next run-loop turn, which is alternative 2's defect.

## Consequences

### Positive

- Every writer that goes through the session catches the editor up, including the seven ADR-0058
  §D7 named and the Pratiche writers ADR-0068 routes through the session. A new writer is covered
  by construction.
- Eighteen hand-kept call sites and four public steps disappear.
- A move or trash made from Pratiche now follows or closes the tab. Before, the watcher saw an
  external deletion.
- ADR-0058 §D7's open product question has a recorded answer (§D7).

### Negative

- **The handler runs on the write path.** Its cost is O(open tabs) per landed change, paid inside
  every write, and a batch of N writes pays it N times. That is well under the disk hop each write
  already makes.
- **`landedGenerations` is observed as one property.** A view reading any entry re-evaluates on
  every landed change in the vault. The only reader is `PratichePane`, and a Pratiche sync
  writing fifty messages re-evaluates its body fifty times while the pane is visible. That is
  accepted. A per-path observable box is the follow-up if a measurement ever says otherwise.
- **Tests that called the four deleted methods move to `landed(_:)`.** One test's premise changes
  meaning (`composerHandOffPreservesEditsMadeAfterTheWriteReturned`,
  `Tests/VaultWriteOrderingBatch3Tests.swift:155`). Under a synchronous door, text typed after
  the write returned is typed on a buffer already caught up. It is an ordinary unsaved edit and
  no prompt is owed. The prompt case is re-expressed as "dirty before the write lands". The plan
  names the change so the test is rewritten, never disabled.
- **«Rigenera» now closes a clean tab showing the message note it regenerates** (ADR-0068 §D1).
  The trash is announced, then the rewrite lands on a path no tab shows any more. A dirty tab is
  asked instead, and the rewrite then turns its question into «Ricarica da disco».

### Neutral

- The connectors build and behave unchanged. No format, schema or protected interface moves.
- `closeTabs(_:ofVanishedNote:)` stays the one door a tab closes through for a vanished file.
  The door, the watcher and the banner all reach it.

## Acceptance

Zero GUI tests (SPEC Constraints). Every test is in `PergamenumTests`, most of them in a new
`Tests/VaultControllerLandedChangeTests.swift` driving a real `VaultController` on a
`TemporaryVault`, both columns open.

- A session write reaches a clean tab in the other column and a clean background tab (R-01).
- A session write raises the prompt on a dirty tab and leaves its text alone (R-01).
- The editor's own save: the writer tab gets no prompt, and text typed during the suspension stays
  unsaved (R-02). Checked through `landed(.written(result, origin: writerID))` after typing, which
  is ADR-0058 test 12's shape, and through a real `saveOpenNote()`.
- A move re-points a clean tab in both columns and keeps a dirty tab's buffer. A trash closes a
  clean tab, asks a dirty one, and a later watcher `.deleted` for the same path closes nothing
  more (R-03).
- A dry-run write, move and trash, and a refused write, announce nothing. Checked with a recording
  subscriber on a bare session (R-05).
- After `open(_:)` to a second vault, a write on the first session reaches no tab of the second
  (§D4).
- `landedGeneration(at:)` advances on a write, a move (both ends) and a trash, and not on a
  rehearsal (§D6, used by R-21).
- One test per writer family from ADR-0058 §D7, plus a Pratiche link write, each catching an open
  tab up with no explicit call (R-06).
- `rg -n "syncOpenNote|movedNote\(|trashedNote\(" Sources` finds nothing (R-04). The deletion
  makes this compile-enforced.
- `perg` and `pergamenum-mcp` build, and `scripts/mcp-smoke.py` passes (R-05).

## References

- `SPEC.md` (Approved 2026-09-26), issue #571 / `PG-257`; ROADMAP Chain 16 item 1, Chain 4 item 2.
- ADR-0001 §D3.4; ADR-0041 §D10; ADR-0043 §D1/§D3; ADR-0050; ADR-0052; ADR-0054; ADR-0057;
  ADR-0058 §D1–§D7; ADR-0064 §D3/§D4/§D6; ADR-0068 (companion).
- `CLAUDE.md` working agreements: "a security or invariant check exposed as a separately-callable
  assertion gets skipped"; "a precondition evaluated before an `await` is a filter".
