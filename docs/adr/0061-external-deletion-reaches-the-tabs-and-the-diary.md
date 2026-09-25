# ADR-0061: An external deletion reaches the editor tabs and the Diario pane, not just the index

- Status: **proposed**, on the branch `kepler/crea-roadmap-per-fix`. Accepted when that branch
  merges to `main`. **§D6 confirmed by Stefano at gate G1 (2026-09-25)**: the absence-marker fix
  on `VaultSession.moveFile`, not Alternative 4b.
- Date: 2026-09-25. Written **before** the implementation, against `5531f72` (tree clean apart
  from `SPEC.md`). Every line number below was read from that tree. None is recalled from the
  ticket.
- **Base note.** `origin/main` (`390613f`) is 12 commits ahead of this branch, but its net
  difference from this tree is `TODO.md` alone: the merge of PR #519 dropped the whole of PR #515
  (`5a6dec9`, ADR-0060 and 16 other files) from `main`. `origin/fix/restore-pr515-adr0057-followups`
  (`88e91de`, unmerged when this was written) puts it back. Of the files this ADR cites, that
  branch touches three: `DiaryController.swift` (`settle()`, added after `:162`),
  `VaultSession+Watching.swift` (`append`, from `:65`) and `PergamenumApp.swift` (34 lines added
  at `:14`, which moves the diary wiring cited below from `:128` to `:162`). No other cited line
  moves.
- **Numbering note.** `0059` is the highest ADR on this branch and on `origin/main` today. `0060`
  (`0060-adr0057-followups-five-write-sites-quit-flush-board-navigation.md`) was merged by #515,
  lost by #519 and is carried by the restore branch. No ref has a `docs/adr/0061*` (`git log --all
  -- 'docs/adr/0061*'` is empty). This chain lands after the restore, or the sequence shows a gap.
- **Path note:** the architect's write scope names `docs/architecture/**`. That directory does not
  exist in this repo; every ADR lives at `docs/adr/NNNN-<slug>.md` and `CLAUDE.md`'s chain index
  links them there. ADR-0054, 0055 and 0058's plans recorded the same deviation.
- Source: `SPEC.md` (Approved 2026-09-25), `TODO.md` **`PG-234`** → issue **#511** (#518 was a
  duplicate promotion of the same ticket, closed).
- **Extends ADR-0043 §D3/§D6, ADR-0056 §D3 and ADR-0058 §D1. Amends none.** The reconciliation
  still reads inside the actor and advances the clock on every read (§D3); the self-written list
  keeps its shape and pruning rule (§D6); `updateTabs(showing:_:)` and the per-buffer rule stay the
  only doors. What changes is that a vanished file is a result those doors can carry.
- **Reopens nothing else.** No on-disk format, no frontmatter key, `IndexCache.schemaVersion` stays
  4, no protected interface. `ExternalChange` changes shape in a shared file
  (`VaultSession+Watching.swift`) and `VaultSession.moveFile` records one more entry
  (`VaultSession+Journal.swift`, shared too); neither connector reads either, so both are built as
  part of acceptance (R-08) and gain no behaviour.
- **GUI-test budget: zero.** Everything below is observable on `VaultDisk`, `VaultSession`,
  `VaultController` and `DiaryController` in-process; the banner's wording is lifted into a value a
  unit test reads (§D5, ADR-0053's seam shape).
- `BRAINSTORM.md` and `UX-BLUEPRINT.md` at the repo root belong to two unrelated, already-shipped
  features (PG-018 editor WYSIWYG, Pratiche). They are not inputs here and no alternative below
  comes from them.

---

## Context

### The missing-path branch reports nothing

`VaultDisk.reconcile(_:selfWritten:)` (`Sources/Vault/VaultDisk.swift:434-450`) reads a path the
watcher reported. When the read fails it returns the index mutation and `change: nil`
(`:437-443`), for a path that is gone and for one that is present but unreadable alike. So an
external deletion updates the index and reaches nobody else:

- `VaultController.reconcile(_:)` (`Sources/App/VaultController+Watching.swift:29-39`) never sees
  it. A clean tab keeps showing a note that no longer exists; a dirty one is never asked, and its
  next save silently recreates the file.
- `didChangeExternally?(change.path)` (`:37`) never fires for it, so `DiaryController
  .externalChange(at:)` (`Sources/Features/Diary/DiaryController.swift:104-107`, ADR-0057 §D8,
  wired by `PergamenumApp.swift:128`) never reloads a clean pane to the empty day `reload()`
  (`:134-155`) already knows how to show.

The SPEC settles the shape of the fix and it is registered here, not reopened: `ExternalChange`
carries `.text(String)` or `.deleted` (SPEC Decision 1); a clean tab closes (Decision 2); a dirty
one gets «Scarta ed elimina» / «Tieni la mia versione» (Decision 3); the diary needs only the
signal (Decision 5).

### What was measured while planning, and changes the picture

**An in-app move's vacated source is a deletion to the watcher, and its follow-up runs after
several `await`s.** SPEC Decision 4 rules out self-suppression for deletions because an in-app
trash closes its tabs synchronously in `trashedNote(at:)` before the watcher can arrive. That
argument is about the trash. A rename or a move leaves its old path just as absent, and its tab
follow-up is not synchronous:

| Performer | Physical move | Follow-up |
|---|---|---|
| `VaultController.renameNote` (`VaultController+Files.swift:38-61`) | first thing inside `session.renameNote`'s transaction (`VaultSession+Files.swift:26-29`), followed by every awaited link and board rewrite (`:30-34`) | `Task { await rescan(); movedNote(...) }` (`:52-55`): after the rewrites *and* after a detached full scan (`VaultSession.swift:323-347`) |
| `VaultController.moveNote` (`:64-86`) | `VaultSession+Files.swift:56-59`, then board repoints | same `Task`, `:77-80` |
| a batch or its undo (`VaultController+Move.swift:53,146`) | one `session.moveNote` per note (`VaultSession+Move.swift:118`) | `follow(_:)` (`:182-192`), after the whole batch |

`VaultWatcher` runs with `kFSEventStreamCreateFlagNoDefer` and a 0.2 s latency
(`VaultWatcher.swift:13,141`). The installed SDK header (`FSEvents.h`, read 2026-09-25) says of
that flag: «if more than latency seconds have elapsed since the last event, your app will receive
the event immediately». Its callback enqueues `reconcile` on the main actor (`VaultController
+Watching.swift:10-14`), which runs at the first suspension of the rename. With the missing branch
reporting `.deleted`, that reconcile closes the renamed note's clean tab (every tab is clean:
`canOperate(on:)` refuses otherwise), and the later `movedNote` finds no tab showing the old path
(`VaultController+Tabs.swift:311-313`) and does nothing. **Renaming or moving an open note would
close its tab.** Today it does not, only because the missing branch reports nothing.

This is not hypothetical in the suite either: `Tests/VaultControllerMoveNoteTests.swift:81`
(`moveNoteMovesTheFileRescansAndFollowsTheOpenTabToItsNewPath`) opens a tab, moves the note through
`controller.moveNote`, and waits for the tab to follow, with a live watcher started by
`controller.open` (`VaultController.swift:224`). It would race exactly this way. **Not run;
inferred from the code above.**

The trash does not have the problem, for a reason that is about outcome rather than order: its
follow-up (`trashedNote`) and the deletion handling of §D4 produce the same end state, whichever
runs first. A move's follow-up (`movedNote`) repoints the tab; a close cannot be undone into a
repoint.

**«Missing» covers two states that are not deletions.** The branch's own comment says it also
catches a file «unreadable for a reason other than absence (e.g. invalid UTF-8)». And with Optimize
Mac Storage on, iCloud Drive can leave `.Nota.md.icloud` where `Nota.md` was, which
`VaultScanner.evictedNoteName(from:)` (`VaultScanner.swift:174-180`) already treats as a normal
state of a supported setup (principle 6). Reporting either as `.deleted` would close a tab, or
offer «Scarta ed elimina», for a note that still exists.

**Three existing assertions pin the old contract.** `Tests/VaultWriteOrderingTests.swift:281`
(`missing.change == nil`), `:303` (`missing.isEmpty`) and `Tests/VaultSessionTests.swift:398`
(`reconcile(["N.md"]).isEmpty` after a removal) assert exactly what R-07 changes. They are
rewritten to the new contract, not deleted (plan gate G2).

---

## Decision

### §D1 - `ExternalChange` carries a `Content` (SPEC Decision 1, registered)

```swift
extension VaultSession {
    struct ExternalChange: Equatable, Sendable {
        enum Content: Equatable, Sendable {
            case text(String)
            case deleted
        }
        let path: String
        let content: Content
    }
}
```

No convenience `text` accessor is added: every reader switches on `content`, so a new case can
never be read as an empty string by a caller that forgot about it.

### §D2 - «Deleted» means absent: not unreadable, not evicted

`VaultDisk.reconcile`'s failed-read branch keeps producing the same `IndexMutation` (record `nil`,
the clock advanced exactly once) and decides the reported change on **existence**, the rule
ADR-0057 §D3 already applies to `expectingAbsent`:

- nothing at the path and no iCloud placeholder for it → `.deleted`;
- a file at the path that cannot be read, or an iCloud placeholder where the note was → `nil`, as
  today;
- a path that fails the vault boundary → `nil`, as today.

The placeholder's name is derived next to `VaultScanner.evictedNoteName(from:)`, so the naming rule
lives in one file, both directions.

### §D3 - One pending value per buffer, and `catchUp` says what it did

`OpenNote.externalChangePending` becomes `VaultSession.ExternalChange.Content?` (the SPEC left the
shape to the plan): `nil` no conflict, `.text(s)` the existing prompt, `.deleted` the new one. Not
two optionals: a buffer holding both an incoming text and a deletion flag is a state no banner can
render and no resolution verb can settle, and this codebase has already paid twice for two
variables that could disagree (ADR-0024's `WorkspaceSelection`, ADR-0047's `TaskPaneSelection`).

`catchUp(to:)` takes a `Content` and returns what it did:

| Buffer | `.text(s)` | `.deleted` |
|---|---|---|
| dirty | `pending = .text(s)` → `.asked` | `pending = .deleted` → `.asked` |
| clean | adopt `s`, clear `pending` → `.adopted` | touch nothing → `.vanished` |

Newest wins on a dirty buffer: a deletion replaces a pending text, and a recreation replaces a
pending deletion with `.text`, so the banner always describes the disk as of the last reconcile
(the SPEC's accepted race). The in-process callers (`syncOpenNote(with:)`,
`syncOpenNote(with:savedBy:)`) pass `.text(result.text)` and ignore the result; `.vanished` cannot
come from a write.

### §D4 - A vanished clean tab closes through the trash's own door

`VaultController.reconcile` collects the ids `catchUp` answered `.vanished` for, inside
`updateTabs(showing:_:)`, and closes them afterwards (ids first, then close: `trashedNote`'s own
reason, `VaultController+Tabs.swift:319-320`). The closing goes through one door extracted from
`trashedNote(at:)` (`:317-331`), which closes the given tabs and removes the path from
`closedTabPaths` and `recentNotePaths`; `trashedNote` becomes that door applied to every tab
showing the path. The door runs for every `.deleted` change, even when no tab was clean, so the
two lists never keep a row that opens nothing: an externally deleted note is no more worth offering
back with Cmd+Shift+T, or listing in RECENTI, than a trashed one.

`didChangeExternally?(change.path)` still fires for every change, `.deleted` included, after the
tabs are settled. That call is the whole of R-01: `DiaryController` needs no change.

### §D5 - The banner branches on the pending kind; the two verbs keep their names

- The banner's message and two button labels come from one value built from the pending
  `Content` (ADR-0053's seam shape: a decision that sits in a view's `body` is lifted to where a
  unit test can read it). `.text` gives today's three strings; `.deleted` gives new copy (final
  wording in `/build`, SPEC «Not yet specified») with «Scarta ed elimina» and «Tieni la mia
  versione». The view renders only what that value says.
- **«Scarta ed elimina»** is `acceptExternalChange()` on a `.deleted` pending: the focused tab (the
  banner's column is focused first, ADR-0056 §D7.2) closes through §D4's door. Nothing is written.
- **«Tieni la mia versione»** is `keepLocalVersion()` on a `.deleted` pending: the prompt is cleared
  **and `savedText` becomes `""`**, the honest value for «what the disk last held» once the disk
  holds nothing. Without it, a buffer the person undid back to its saved text before clicking is
  clean, `saveOpenNote()`'s guard (`VaultController+Editing.swift:29`) skips it, and the tab sits on
  a missing file with nothing that can save it, which is the state SPEC Decision 2 rejected. With
  it, a non-empty buffer stays dirty, Cmd+S recreates the file through the unguarded write the SPEC
  relies on (`:32`), and closing the tab asks first. For a dirty buffer, the case the SPEC
  describes, it changes nothing observable.

### §D6 - A move's vacated source is this session's own absence (pending gate G1)

`VaultSession.moveFile(from:to:)` (`VaultSession+Journal.swift:66-106`), the one door every in-app
note move passes (rename, move, batch, the undo of either), records the source path in the
**existing** `selfWrittenHashes` list under an absence marker:

- recorded **before** the actor hop, after the guards and the dry-run return, with a provisional
  sequence, exactly as `write` records its hash (ADR-0041 §D10: a watcher racing the change must
  never find the disk changed before the session holds its own record of it); corrected to the
  removal mutation's sequence after the hop (`VaultDisk.moveFile` stamps one for the old path,
  `VaultDisk.swift:391`); removed if the move throws;
- matched only in §D2's absent branch, and pruned by the same «every entry at or below the matched
  sequence» rule as any hash (ADR-0043 §D6);
- a value `NoteStore.hash` can never produce, and **not** `""`, which `moveFile` already uses as a
  fallback hash for the new path when the moved file yields no record (`:88`).

A matched absence reports nothing and applies nothing, like a matched hash: the move already
applied its removal, and `movedNote` is the tab's only follow-up, as `syncOpenNote` is for a write
(ADR-0058's rule, applied to the other half of a move).

Two differences from a hash follow from what an absence is, and both are decided here:

- **A stale absence is dropped once the path is found present.** A hash describes particular bytes,
  so a leftover one almost never matches anything else; an absence matches every later absence of
  that path. If the watcher never reports the vacated path (an FSEvents drop that ends in a rescan,
  not a per-path reconcile), a marker left in the list would later swallow a real external deletion
  of a note recreated there. So an **unmatched** reconciliation of a path drops that path's absence
  entries whose sequence is below the reconciliation's own: the disk was read after the vacancy
  they describe and did not find it. The sequence bound keeps a provisional marker (numbered from
  `UInt64.max` down) out of reach of a reconciliation that read the disk before the move landed.
- **Consumed once, like a hash.** A second delivery of the same vacated path after the first one
  matched, and before `movedNote` runs, would be reported and would close the tab. Nothing writes
  the vacated path during a rename or move, and FSEvents coalesces within its latency, so this is
  named, not engineered around.

`trashFile` is **unchanged**: `selfWrittenHashes.removeValue(forKey:)` stays (`:143`), no marker,
so an in-app trash still reaches the watcher as `.deleted`, exactly as SPEC Decision 4 and R-09
state. The asymmetry is the Context's outcome argument, not an oversight.

**Why this is gated.** SPEC Decision 4 rejects «self-write suppression for the deletion signal».
§D6 is not the parallel `selfDeletedPaths` set that Decision rejects, it adds nothing for the
trash, and a move's source is arguably not a deletion; but the Decision's reasoning never
considered moves, so its author confirms before it binds. If G1 is declined, Alternative 4b
replaces it; accepting the regression is not an option (it would turn an existing test flaky, and
this project never disables a test to get a suite green).

### §D7 - Named here and not fixed

- **An external rename closes the tab instead of following it.** Finder, Obsidian or `perg note
  rename` produce a vanished path and a new one; nothing pairs them. A follow-up could pair a
  `.deleted` with a new path in the same batch whose content hash equals the vanished row's last
  indexed hash. Today the tab stays on a dead path and its next save recreates the old name, so
  closing is not a regression.
- **Pratiche «Escludi» and «Sposta in…» move or trash a message's `.md` through `FileManager`
  directly** (`PraticaFileOperations.swift:48,166`) and call neither `trashedNote` nor
  `movedNote`. After this chain the watcher closes a clean tab on such a message (an improvement
  over a dead path); following it after «Sposta in…» would need `movedNote` from that file.
- **An in-process move of the diary's day file does not reach the Diario pane** (§D6 suppresses
  it; today nothing reaches it either). ADR-0058 §D7's recommended post-write notification from the
  session is the follow-up that would cover it, with every other in-process writer.
- **A second deletion event for the same path, arriving after «Tieni la mia versione» and before
  the save,** raises the banner again. The file is still absent, so the banner is not wrong, and the
  save clears it (`syncOpenNote(with:savedBy:)`, `VaultController+Editing.swift:117`).
- **An empty note** kept through «Tieni la mia versione» stays clean (`"" == ""`) and is not
  recreated until something is typed.
- **A clean tab disappears without a word.** Whether an external deletion of the note on screen
  should also record a sentence in the problems list is a UX preference the SPEC did not ask for;
  left to Stefano.
- **`.canvas` and `WorkspaceController`**, the recovery UI, and self-suppression for the trash:
  out of scope by the SPEC.

---

## Alternatives considered

1. **Deletion as `text: ""`** (SPEC Decision 1's rejected option). Indistinguishable from a file
   another writer emptied, which must be adopted as text.
2. **Two optionals on `OpenNote`** (`externalChangePending: String?` plus a deletion flag). Less
   churn: ten existing `#expect(... == <text>)` assertions and one constructor would compile
   untouched. Rejected for §D3's reason: it makes a both-set state representable, and the churn is
   mechanical.
3. **Report `.deleted` for every failed read** (the SPEC's literal «missing-path branch»). Rejected
   by §D2: it would close a tab or offer «Scarta ed elimina» for a file that is there but not UTF-8,
   or evicted to iCloud.
4. **For the move race (§D6):**
   - **a. Accept it.** Renaming or moving an open note closes its tab; `VaultControllerMoveNoteTests
     .swift:81` becomes flaky. Rejected.
   - **b. Relocation claims on `VaultController`.** Each async relocation performer (`renameNote`,
     `moveNote`, `moveItems` and its inverse) records the source paths before calling the session
     and releases them after its `movedNote`; `reconcile` does not close a tab whose path is
     claimed. Keeps the deletion signal flowing to the Diario pane for in-app moves, and touches no
     shared file. Rejected as the default because it is a claim every present and future relocation
     performer must remember to take and release on every exit path, including a `Task` that
     outlives the call: CLAUDE.md's «a check exposed as a separately-callable step gets skipped by
     the next call site, by omission». §D6 sits at the one door every move already passes. It is
     the fallback if G1 is declined.
   - **c. Call `movedNote` before `rescan()`.** Narrows the window without closing it: the
     rename's own link and board rewrites, and every note of a batch, still `await` after the
     physical move.
   - **d. A parallel `selfDeletedPaths` set covering the trash too** (SPEC Decision 4's rejected
     option). §D6 differs on both counts: no second structure, and nothing for the trash.
5. **Leave the clean tab open with a «file missing» indicator** (SPEC Decision 2's rejected
   option).
6. **Keep the banner's wording inline in the view.** R-04 could then be checked only by a GUI test,
   and the GUI suite is a bounded backstop, not where a new test lands (CLAUDE.md, merge-gate rule).

---

## Consequences

### Positive

- A clean Diario pane reloads to the empty day when its file is deleted by another process, as
  ADR-0057 §D8 meant to (R-01).
- A clean tab on an externally deleted note closes in every column (R-03); a dirty one is asked,
  with a question that makes sense for a missing file (R-04), and the answer is honoured without a
  new write door (R-05, R-06).
- The first time the watcher can tell the app a note is gone, it cannot mistake an unreadable or
  evicted note for one.
- Renaming and moving an open note keep following it, under a signal that would otherwise have
  broken them.

### Negative

- Seventeen mechanical test edits (ten `.text(...)` wrappers on `externalChangePending`
  comparisons, one constructor, three `catchUp(to:)` calls, three reads of `ExternalChange.text`),
  plus three assertions rewritten to a new contract (gate G2).
- `VaultSession`'s three provisional-sequence helpers widen from `private` to `internal` so
  `VaultSession+Journal.swift` can use them, one comment each naming the reader (ADR-0045's
  convention).
- An external rename closes the tab instead of following it (§D7).
- The Diario pane still does not hear of an in-process move of its file (§D7, unchanged from
  today).

### Neutral

- `moveFile` still records the new path's hash **after** the hop (`:92`). Losing that race reports
  the new path as an external text change that no tab shows yet, which is harmless; §D6 does not
  touch it.
- The index is unaffected: the failed-read branch produces the same mutation it always did.
- The connectors compile both changed shared files and read neither `ExternalChange` nor
  `selfWrittenHashes`.

---

## Acceptance

Written by the plan's red-test task before any body changes (`docs/plans/pg-234-external-deletion.md`).
No test sleeps, polls a timer, or races two tasks and hopes (ADR-0043 §D9). Where the order of two
events matters, the test performs them in that order through the doors the watcher and the
performer use. A test that builds a `VaultController` stops the watcher `open` starts
(`controller.watcher?.stop()`), so the only reconciliation it sees is the one it calls.

- Disk and session: an absent path reports `.deleted` and drops the row (R-07); an unreadable
  file and an iCloud placeholder report nothing (§D2); a path `session.moveFile` vacated reports
  nothing and leaves no marker behind, a failed move leaves no marker, a stale marker is dropped
  once the path is found present so a later real deletion is reported, and a trashed path still
  reports `.deleted` (§D6, R-09).
- Controller: clean tabs close in both columns and leave `closedTabPaths`/`recentNotePaths`
  (R-03); a dirty tab gets `.deleted` with its text untouched, and a pending text is replaced by it
  and back (R-04, §D3); «Scarta ed elimina» closes without writing (R-06); «Tieni la mia versione»
  then a save recreates the file, including from a buffer undone to clean (R-05, §D5); the banner
  value for `.deleted` never says «Ricarica da disco» (R-04); a session move followed by the
  watcher's reconcile and then `movedNote` leaves the tab following the note (§D6); a trash
  followed by the watcher's reconcile, in either order against `trashedNote`, ends in the same
  state (R-09).
- Diario: a clean pane reloads to the empty day; a pane with a pending edit is untouched (R-01,
  R-02).
- `Pergamenum`, `perg` and `pergamenum-mcp` build (R-08); the whole `PergamenumTests` bundle is
  green, not only the new files.

---

## References

- `SPEC.md` (Approved 2026-09-25), R-01…R-09, Decisions 1-5.
- ADR-0001 §D3.4 (ask, never merge or discard); ADR-0041 §D10 (record before the hop); ADR-0043
  §D3/§D6/§D9; ADR-0045 (widening convention); ADR-0053 (seams); ADR-0054 §D7 (`.canvas`, out of
  scope); ADR-0056 §D1/§D3/§D7.2; ADR-0057 §D3/§D8; ADR-0058 §D1/§D7.
- `FSEvents.h`, `kFSEventStreamCreateFlagNoDefer` and `kFSEventStreamEventFlagItemRenamed`, read
  from the installed Xcode SDK on 2026-09-25.
