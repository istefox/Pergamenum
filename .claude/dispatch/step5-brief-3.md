<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=7,8,9 lines=577-777 -->
# Step 5 Batch Brief -- 2026-09-13-vault-write-ordering-adr-0043.md -- tasks 7-9

## Task text (verbatim, plan lines 577-777)

## Task 7 — `selfWrittenHashes` becomes per-path and sequence-tagged, pruned by the clock (R-07, R-13)

Cross-refs: ADR-0043 §D6; ADR-0041 §D10 (the hash is computed on the main actor before the hop —
that timing is **preserved literally**, only the container changes); ADR-0001 §D3.3 (a cap on this
structure is a suppression window wearing a different hat, rejected by name).
Budget: `Sources/Vault/VaultSession.swift`, `Sources/Vault/VaultSession+Watching.swift`,
`Sources/Vault/VaultSession+Journal.swift`, `Sources/Vault/VaultDisk.swift`,
`Tests/VaultWriteOrderingTests.swift` (~280 lines)

**Tester declares:**

```swift
extension VaultSession {
    var selfWrittenHashes: [String: [(sequence: UInt64, hash: String)]] { get set }
}
```

**Coder implements:**

1. The container change. A write **appends** before the hop (§D10's timing, unchanged: the hash is
   still a pure function of text the main actor holds, still recorded before the file can exist).
   The sequence it is tagged with is the one the actor will stamp — since the caller cannot know it
   before the hop, record the entry with a provisional key and reconcile it from the returned
   `IndexMutation.sequence` when the outcome resumes, or have `VaultDisk` own the list entirely.
   **The coder picks one and states which in the commit message; the constraint is that no window
   exists in which the file can exist and the session does not hold its hash** — that is the whole
   of §D10 and it must not regress.
2. A reconciliation that matches a hash in the path's list treats it as this session's own write
   and drops **every entry with a sequence at or below the matched one**. This is what keeps the
   list bounded when FSEvents coalesces several writes into one callback: the intermediate hashes
   are never observed separately and would otherwise leak forever. **No cap, no time window.**
3. `+Journal`'s move (`:77`) and trash (`:129`) bookkeeping moves to the same shape.
4. Wire Task 5's `selfWritten:`/`matchedSequence` parameters, which were declared then and stubbed.

**Tester writes (R-13), red before step 1:**

`aReconciliationBetweenTwoWritesAppliesInClockOrderNotCallOrder()` — deterministic. Build the three
mutations by hand with explicit sequences: write A at `1`, the reconciliation's read at `2`, write B
at `3`. Hand them to `apply` in *call* order `[A, B, reconciliation]` and assert the index ends on
B's record, not the reconciliation's; then repeat with `[A, reconciliation, B]` and assert the same.
Second case, for the pruning: record three self-written hashes for one path at sequences 1, 2, 3,
reconcile against the hash at sequence 2, and assert that entries 1 and 2 are gone and 3 remains —
FSEvents coalescing, exactly. **Assert on the list contents, not only on «no external change was
reported»**, or a version that clears the whole list passes.

**Done when:** R-13 green; no `selfWrittenHashes` entry survives a matched reconciliation at or
below its sequence; full unit suite green.

## Task 8 — A guard before an `await` is a filter: the hand-off asks instead of replacing (R-08, R-09, R-14)

Cross-refs: ADR-0043 §D7 (three parts, in order of how load-bearing they are) and its two rejected
alternatives (keep the silent no-op and rely on the watcher — rejected on the code, the watcher
cannot see it; re-check `canOperate` after the `await` — rejected, by then the write has happened);
ADR-0001 §D3.4 («never merge, never discard: ask»); ADR-0036 §D5/§D13 (the composer writes twice and
then hands off).
Budget: `Sources/Features/Pratiche/PraticaEntryComposer.swift`,
`Sources/App/VaultController+Editing.swift`, `Tests/PraticaEntryComposerTests.swift` (or the
existing pratiche test file — grep first), `Tests/NoteTabTests.swift` (~250 lines)

**Coder implements:**

1. **`handOff` stops reloading from disk.** `insert(_:at:)` already receives a `WriteResult` from
   `session.write` and discards it (`PraticaEntryComposer.swift:61`). It keeps it and hands it to
   `handOff`, which calls `vault.syncOpenNote(with: result)` instead of
   `vault.reloadFocusedNote()` (`:108-110`). `reloadFocusedNote()` is the wrong tool here: it
   re-reads the file, which after §D1 may already have moved on again.
2. **The comment at `:105-107` that infers safety from `canOperate(on:)` is deleted** («Safe to
   replace outright, since `canOperate(on:)` above refused a dirty tab»). It was true when `insert`
   was synchronous and is false now.
3. **`canOperate(on:)` stays exactly where it is** (`:54`) as a cheap early refusal that spares the
   user a pointless write and a prompt in the common case. It is not moved, not removed, not
   re-checked after the `await`.
4. **`syncOpenNote(with:)`'s dirty branch stops doing nothing** (`VaultController+Editing.swift:70-78`):
   it sets `note.externalChangePending = result.text`, raising ADR-0001 §D3.4's existing prompt with
   the app's own write as the incoming text. The doc comment at `:67-69` promising that «the watcher
   will raise the question when the write comes back round» is deleted — `reconcile` drops the
   session's own writes by hash (`VaultSession+Watching.swift:32-34`), which is §D3.3 working
   correctly, so the question is never asked.
5. **This changes behaviour at all nine `syncOpenNote` call sites**, and that is the point:
   `VaultController+TimeBlocks.swift:40`, `:61`, `:97`; `+Diary:29`; `+TaskDrop:33`; `+Routes:133`;
   `+Tasks:20`, `:66`; and the composer's new one. No call site opts out.
6. **Release-note line, not only a test** (ADR-0043's own Negative consequences ask for it): a
   prompt that never appeared will start appearing, and one of the nine (the time-block writers)
   can write a daily note the user is editing. Task 10 step 7 files it.

**Tester writes (R-14), red before step 1:**

`dirtyingTheBufferBetweenAWriteAndItsHandOffRaisesTheConflictPrompt()` — deterministic, no real
timing. Open a note in a tab, give it unsaved edits (`note.text != note.savedText`), then call
`syncOpenNote(with: WriteResult(path:, text:))` directly with a different text. Assert
`openNote?.externalChangePending == result.text` **and** that `openNote?.text` is still the user's
unsaved buffer, untouched. A second case drives the composer's own path: construct the composer,
dirty the tab after `insert`'s write has returned, call `handOff`, and assert the same two things —
the forcing mechanism is calling `handOff` directly with a dirtied buffer, never a sleep.

**Done when:** R-14 green; `grep -n "reloadFocusedNote" Sources/Features/Pratiche/` returns
nothing; the nine call sites are unchanged at their own line (the behaviour change lives in
`syncOpenNote`, not in nine edits).

## Task 9 — `write` gains an optional expected-hash precondition, adopted where a read straddles a suspension (R-10, R-15)

Cross-refs: ADR-0043 §D8 and its rejected alternative (make it mandatory — rejected: a new note has
no «before» to expect, and a mandatory precondition adds a failure path to ~35 call sites for a
hazard four of them have); `Sources/Core/Tasks/TaskParser.swift:473` (the staleness guard §D8
generalises); `VaultSession+Journal.swift:234` (`preflightUndo`'s hash check, the other precedent).
Budget: `Sources/Vault/VaultSession.swift`, `Sources/Vault/VaultDisk.swift`,
`Sources/Vault/VaultSession+Tasks.swift`, `+TimeBlocks.swift`,
`Sources/Features/Pratiche/PraticaEntryComposer.swift`, `DossierWriter.swift`,
`PraticaCommandActions.swift`, `PraticheController.swift`, `PraticaSyncEngine.swift`,
`Sources/Features/Recordings/RecordingsController.swift`, `Sources/Connector/VaultWrites.swift`,
`Tests/VaultWriteOrderingTests.swift` (~400 lines)

**Tester declares:**

```swift
extension VaultSession {
    enum WriteRefusal: Error, CustomStringConvertible, Equatable {
        case movedOn(String)
        var description: String { get }   // Italian, names the path
    }

    @discardableResult
    func write(_ text: String, to relativePath: String, expecting: String? = nil) async throws -> WriteResult
}
```

**Coder implements:**

1. `expecting` is the content hash the caller's text was derived from. The actor compares it
   against the file's current hash — **the read §D5 already performs, so this costs nothing
   extra** — and throws `WriteRefusal.movedOn(relativePath)` **without writing a byte** when they
   differ. Default `nil`, so no existing call site changes shape.
2. The refusal is a thrown error, never a silent no-op (ADR-0007 §D6: a write that did not happen
   and said nothing is the failure mode the guardrails exist to prevent).
3. **The adoption list. This is the grep ADR-0043 §D8 says the plan owns** (`session.read(`
   followed by `session.write(` in the same function, across `Sources/App`, `Sources/Features`,
   `Sources/Connector`), run on this tree and resolved here:

   **Adopt (9 call sites):**

   | Call site | Read → write | Why |
   | --- | --- | --- |
   | `PraticaEntryComposer.insert(_:at:)` | `:57` → `:61` | The fourth race, at the line: the ADR names this one by name. `PraticaEntry.insert` composes a text from a snapshot that predates any writer reaching the actor first. |
   | `PraticaEntryComposer.mirror(…)` | `:87` → `:91` | Same shape, same function, and the daily note is the file most likely to have a second writer (time blocks, capture, diary). |
   | `DossierWriter.update(at:session:_:)` | `:26` → `:32` | Parses the note's frontmatter, mutates it, serialises. Becomes `async` in Task 2, so the read now straddles a suspension where it did not before — this chain *creates* the hazard here and must close it in the same chain. |
   | `PraticaCommandActions` (`:303` → `:307`) | `:303` → `:307` | Identical shape to `DossierWriter`, identical reason. |
   | `PraticheController.runExclusive`'s conversation remap | `:1241` → `:1262` | Already `async` today; the read and the write are ~20 lines and one `await` apart. A remap written over a concurrent dossier edit silently loses the edit. |
   | `RecordingsController.importAccepted` | `:317` → `:335` | **Beyond the ADR's named list, adopted with reasons.** The composed text is a merge of the proposal with `existingNoteText` (the dedup suppression set, ADR-0032 §D9). If the note changed between read and write, the merge is stale and re-imports quotes it already suppressed. The two-phase import makes the refusal clean: phase 2 (`POST` of accepted ids) only runs after phase 1 succeeds, so a refusal aborts before anything leaves the machine. `rowErrors[recordingID]` already exists as the report channel. |
   | `PraticaSyncEngine` attachment patch | `:779` read → `:878` write | ADR-0040 §D4's patch path: reads the message note off disk, patches one line, writes it back. Straddles an `await`. |
   | `PraticaSyncEngine` inline-image patch | `:308` read → `:398` write | ADR-0042's `MessageInlineImagePatch`, same shape. Both need the engine's `write` closure to gain an `expecting: String?` parameter. |
   | `VaultWrites.undo(_:id:)` | `:277` → `:297` | It *already* checks staleness (`current.record.contentHash == entry.hashAfter`, `:279`) — and that check is on the wrong side of the `await` at `:297`, which is exactly Race 4. The hash is already in hand, so adoption is one argument. **Keep the existing pre-check**: its Italian message is the one the user should see, and `expecting:` is the backstop for the window the pre-check cannot cover. |

   **Adopt inside `Sources/Vault` (4 call sites) — outside the ADR's stated grep scope but named in
   its own prose («the composer, the task and timeblock writers»):**
   `VaultSession+Tasks.apply(_:to:)` (`taskSourceText` → `writeTaskSource`, `:106`→`:167`),
   `captureTask` (`:194`→`:216`), `captureSubtask` (`:229`→`:245` — it has `TaskParser`'s
   line-match guard, which is computed on the pre-`await` text and so has the same defect),
   `VaultSession+TimeBlocks.setTimeBlocks` (`:30`→`:43`) and `addTimeBlock`/`dailyNoteBody`
   (`:60`/`:90`→`:98`). The existing `WriteOutcome.stale` case is the natural home for the refusal
   at these sites: catch `WriteRefusal.movedOn` and return `.stale` rather than propagating, so the
   existing «il task non è più dove risultava» handling fires.

   **Decline, with the reason stated so the next reader does not re-litigate it:**

   - `VaultWrites.summarise` (`:45`) — reads to compute a diff, writes nothing.
   - `VaultController+Routes.swift:132` — reads then calls `syncOpenNote`, which is not a write.
   - `VaultController+Tabs.readForEditing` (`:358`) — reads only, and Task 5 removes its one
     side effect.
   - `VaultController+Notes.noteText(at:)` (`:49`), `ViewsPane.swift:177`, `:198`,
     `EditorColumn+Text.swift:218`, `:247`, `VaultReads`/`VaultViews` — pure reads.
   - `TemplateSheet.swift:66`, `NewNoteComposer.swift:160` → `vault.createNote` — the read is of a
     *template*, and the write creates a **new** note. A new note has no «before» to expect; §D8
     excludes this case by name.
   - `PraticaSyncEngine`'s full render (`:906`) — `prepared.noteText` is composed from Mail, not
     from the file on disk. «Make the file say this», which §D8 excludes by name.
   - `NuovaPraticaWizard.swift:465` — writes a freshly composed `pratica.md` for a pratica being
     created. No prior state.
   - `VaultSession+Diary.writeDiary` — a genuine window, and **wider** than §D8 can close: the
     prose is read by `readDiary` in one user gesture and written by `writeDiary` in another, with
     a UI round trip between. Plumbing a hash across that is a design change, not an adoption.
     ADR-0001 §D3.4's prompt (now firing at this call site, per Task 8) is the existing answer.
     Recorded as a follow-up in Task 10 step 8, not implemented here.
   - `VaultSession+TagRename.renameTag` / `+Files.renameNote`'s `VaultPlanApplication` writers —
     the `before` text is in hand and adoption is technically possible, but a tag rename is a
     user-confirmed batch whose own preview/apply window is a separate, wider question, and a
     partial refusal mid-batch is a half-renamed vault. Out of scope; the batch already collects
     per-path failures. Recorded as a follow-up.

**Tester writes (R-15), red before step 1:**

`aWriteWithAStaleExpectedHashIsRefusedAndWritesNothing()` — deterministic. Write a note, capture
its hash, write it again through a second call so the file moves on, then call
`write(text, to: path, expecting: <the first hash>)` and assert: it throws
`WriteRefusal.movedOn(path)`, the bytes on disk are still the second write's, the journal gained no
entry, `NoteHistory` gained no snapshot, and `selfWrittenHashes[path]` gained no entry. A second
case asserts the happy path: `expecting:` equal to the current hash writes normally. A third
asserts `expecting: nil` (the default) writes without checking anything.

**Done when:** R-15 green; every adopted site compiles and its error path is handled (not
`try?`-swallowed); full unit suite green.

## File map (from Budget: declarations, tasks 7-9)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 7 8 9 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 1 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 2 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 3 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: docs/adr/0043-vault-write-ordering-concurrency-races.md -- governing ADR for this chain
- SPEC: docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md -- task detail lives in the plan itself
