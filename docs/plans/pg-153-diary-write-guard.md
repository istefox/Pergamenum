# Fix: the diary proves what it writes over, one write at a time (PG-153 / #262)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to an unrelated feature (pratiche
links, task-side display) and is **not** this chain's input. The dispatch brief is the whole
specification; its five items are quoted in the validation table below, and every task states in
plain words which of them it satisfies. No requirement ids are declared, so none are cited.

Read out of the worktree `Pergamenum-fix-262-readdiary-writediary-race-c08eafa6` at `e61dbe2b`,
branch `kepler/fix-262-readdiary-writediary-race`, clean tree. Every line number, call-site list
and count below was grepped in that tree.

## ADR outcome - new ADR: `docs/adr/0057-diary-origin-marker-and-one-write-door.md`

Written, `proposed`, accepted when this branch merges.

**Path.** The agent default is `docs/architecture/`; that directory does not exist here. All 56
ADRs live in `docs/adr/NNNN-<slug>.md` and `CLAUDE.md`'s chain index links them there, so this one
does too. `0056` is the highest number and `git log --all -- 'docs/adr/0057*'` is empty: free,
checked. A parallel worktree that has not pushed is outside what that check sees (see Risks).

Why a new ADR and not a citation of ADR-0043 or ADR-0054: all three gates hold.

- **Hard to reverse.** A serial write chain, an origin marker naming the vault, a third save
  state with a pinned-day mode, a mandatory precondition on the diary's write door and a new opt-in
  parameter on the core write door compiled into both connectors.
- **Surprising without context.** A future reader finds a `show(_:)` that sometimes switches day
  later than it was asked to, a write door with two different "expect" parameters, and day
  navigation disabled for no visible reason unless the strip is up.
- **A real trade-off.** Serialize vs. `expecting:` alone (the brief's own question), cancel vs.
  order, absent-means-unguarded vs. an absence precondition, automatic reconciliation vs. none,
  leave a conflicted day vs. pin it.

Overrides also apply: ADR-0043's implementation notes explicitly deferred this window to its own
design, the ADR records explicit **no**s a reader would otherwise undo (no watcher wiring, no
automatic reconciliation, no leaving a conflicted day), and it states a constraint invisible in the
code (the shared-folder setup's in-process writers never reach the watcher).

ADR-0057 **extends** ADR-0043 §D8 and ADR-0005 §D7, **applies** ADR-0052 §D1/§D3 and ADR-0054
§D2/§D5, and **amends none**. No existing ADR body is edited by this chain (Task 5 proposes one
optional cross-reference line, the PG-168 precedent, for Stefano to accept or drop).

## The brief, checked against the code

| Brief item | Verdict | Decided in |
|---|---|---|
| 1. `readDiary` captures the hash, nil when the file is absent | **Adopted with a correction.** Absent is a state (`.absent`), and it carries its own precondition (`expectingAbsent:`). «No precondition when absent» would let the diary's first write erase a file another process created, or - in the supported `diaryFolder == dailyFolder` setup - one the app itself created from the capture panel, a time block or an event note while the pane showed an empty day. | ADR §D1, §D3; Tasks 1, 3 |
| 2. `DiaryController` keeps an origin marker, mirroring `BoardOrigin` | **Adopted, widened.** The marker records the file (vault root + path), not only the hash: the controller is app-lifetime and outlives a vault switch, so a relative path alone would let a day read in vault A be written into vault B. | ADR §D2, §D7; Task 3 |
| 3. `writeDiary` passes `expecting:` | **Adopted, made mandatory.** `over:` has no default and there is no unguarded overload. | ADR §D3; Task 3 |
| 4. A refusal becomes a non-modal conflict in the Diario pane, keep-mine and reload-from-disk | **Adopted.** No automatic reconciliation (reason in ADR §D6). Day navigation is disabled while conflicted - a behaviour choice flagged for Stefano below. | ADR §D6; Task 4 |
| 5. Serialize the two concurrent `save()` Tasks, or show `expecting:` alone is safe | **Serialize.** `expecting:` alone is not safe: two in-flight saves read the same expectation, so the app's own `add` → `move` → `resize` sequence (`DiaryControllerTests.swift:188`) would conflict with itself on every existing file, and an older snapshot could still land last. Two more defects of the same shape were found and are fixed by the same change: a keystroke typed during a write is marked clean and never written, and coming back to a day before its flush landed re-reads the pre-flush file. | ADR §D4, §D5; Task 2 |
| Framing: «`writeDiary` is the only writer left without `expecting:`» | **Incorrect.** `saveOpenNote`, `restoreVersion`, `append`, `linkFromDailyNote`, the `RelatedLink` pair and the board drop also write without it. What is unique to the diary is that it is the only in-memory holder of a `.md` file outside the editor-tab model, with a person between its read and its write. | ADR §Context; follow-ups |

## How the tasks are split between tester and coder

Swift is compiled: a batch that leaves the target unable to build produces no red tests at all.
So in every task, **the tester's commit carries the type and signature declarations** together
with the red tests, with placeholder bodies that compile; **the coder's commit carries the bodies**.
A placeholder must not trap in anything a test reads: a `fatalError()` in a property a test polls
takes the whole test process down with it, not just the red test. Return the nearest honest old
value instead (for example `isSettled` returning `!isDirty` until the coder replaces it).

Before the first build in this worktree the workspace does not exist yet: `tuist install` then
`tuist generate --no-open`. Re-run `tuist generate --no-open` after any task that adds a file.

Order is by dependency and is not optional: **Task 2 must land before Task 3.** Adding the
precondition before the writes are serialized turns the existing
`movesAndResizesAnEntryAndWritesBothToTheFile` into a conflict against the app's own writes.

---

### Task 1 - The core write door learns «only if the file is still absent» (brief item 1, the creation case; item 3's door)

**Declarations (tester):**

- `Sources/Vault/VaultSession.swift:544` - `write(_:to:expecting:expectingAbsent:requiringExistingFolder:)`,
  `expectingAbsent: Bool = false` inserted between the two existing opt-in parameters. Threaded to
  the `disk.write(...)` call at `:576`.
- `Sources/Vault/VaultDisk.swift:207` - the descriptor overload (the only one `VaultSession.write`
  calls; the `journalEntry:` overload at `:135` is a test fixture shape and is not touched) gains
  the same parameter.

**Bodies (coder):**

- In `VaultDisk.write`, beside the `expecting` check at `:222`: when `expectingAbsent` is true and
  the file **exists** (`FileManager.fileExists` on `store.url(for:)`, not `textBefore == nil`),
  throw `VaultSession.WriteRefusal.movedOn(relativePath)` before any byte is written. The session's
  existing `catch` already removes the provisional `selfWrittenHashes` entry.
- In `VaultSession.write`: `assert(!(expecting != nil && expectingAbsent))`; in Release `expecting`
  wins. Doc comment extended in the PG-168 paragraph's style.

**Tests (tester), new file `Tests/VaultWriteAbsentPreconditionTests.swift`:**

- a write with `expectingAbsent: true` to an existing file throws `movedOn`, leaves its bytes and
  its index record unchanged, and leaves no self-written hash behind (a later external write to the
  same bytes is still reported by the watcher path the existing `expecting:` tests use);
- to a missing file it writes, creating the folder as today;
- to an existing file that is not UTF-8 it refuses (existence, not readability - ADR §D3);
- with the default `false`, behaviour is unchanged (covered by the existing suite; no new test).

Red on today's code: the parameter does not exist, so the tester's declaration commit makes these
compile and fail (the placeholder ignores the flag and overwrites).

No existing call site changes: the parameter is defaulted. `perg` and `pergamenum-mcp` compile
these files (`sharedSources`), so both tool builds are part of this task's check.

---

### Task 2 - One serial write door in `DiaryController`, and a day left only once its write has landed (brief item 5)

**Test infrastructure first (tester):**

- **New `Tests/GateSupport.swift`** holding the `@MainActor` one-shot latch `Gate` moved verbatim
  from `Tests/VaultTransactionGestureTests.swift:28-44`, made internal; the private declaration
  there is deleted in the same commit (a private and an internal type of the same name in one
  module collide - ADR-0051 §D2). `MailStoreOverride.swift:41`'s `Gate` is a type nested inside
  another type and is unaffected.
- **New `Tests/DiaryTestSupport.swift`** holding `makeDiary(_:)` and `diaryOnDisk(_:)`, internal.
  Today both are declared `private` twice, byte-identical in body, in
  `Tests/DiaryControllerTests.swift:29,40` and `Tests/DiaryComposerTests.swift:9,19`; both private
  copies are deleted (widening one would make the other file's calls ambiguous). `waitUntil` stays
  where it is: it is already internal and used outside the diary tests.

**Declarations (tester), in `Sources/Features/Diary/DiaryController.swift`:**

- `enum DiaryWritePhase: Equatable { case willWrite, didWrite }` and
  `@ObservationIgnored var testOnlyWriteHook: (@MainActor (DiaryWritePhase) async -> Void)?`
  (ADR §D9). The tester also adds the two hook calls into **today's** `save()` Task - `.willWrite`
  right before `vault.writeDiary`, `.didWrite` at the end of both branches - so the red tests below
  exercise the real current code and are genuinely red. Nil in production; no behaviour change.
- `enum SaveState: Equatable { case saved, pending, conflicted(reason: String) }` and
  `private(set) var saveState: SaveState` (the full enum now, so Task 3 adds no case to switch
  over); `var isSettled: Bool` (placeholder `!isDirty`).

**Bodies (coder):**

- Replace `isDirty` with `saveState` plus an **edit generation** counter bumped by every edit
  (`prose`'s `didSet`, `entriesChanged()`), and the generation the file is known to hold.
- **The serial chain.** One stored tail task; a new operation awaits its predecessor before doing
  anything, and clears the tail when it is still the last one. `save()` enqueues an operation
  instead of starting a free `Task`. Inside an operation, after the predecessor: snapshot the
  current `day`/`prose`/`entries` and generation; if nothing is owed, stop; await
  `testOnlyWriteHook?(.willWrite)`; write; mark `.saved` **only if the generation has not moved**,
  otherwise stay `.pending` and enqueue another operation; await `testOnlyWriteHook?(.didWrite)`
  after the outcome has been acted on (ADR §D9). At most one write in flight, ever.
- `isSettled` = `saveState == .saved` and no operation queued or running.
- **`show(_:)`** (ADR §D5): if `isSettled`, today's synchronous path. Otherwise record the
  **destination**, flush, and enqueue a switch operation which, when it runs, stays if the day is
  conflicted, re-flushes and re-enqueues itself if an edit arrived meanwhile, and otherwise sets
  `day` to the destination and reads it. `move(by:)` counts from the destination when one is set.
  A destination equal to the current day clears itself without re-reading.
- **`load()`**: conflicted → nothing; not settled → flush, no re-read; settled → re-read. The
  `skipDiskReadBecauseJustFlushed` parameter and its comment block (`:57-71`, `:78-83`) go, replaced
  by one comment stating the three cases.
- The `.failed` branch records its problem through `vault.recordProblem` (the message text stays
  «diario del …: scrittura non riuscita») and settles as today (ADR §D5).
- `DiaryController.problems` (`:29`) is removed: grepped, no reader in `Sources/` or `Tests/`.
- Snapshot comment at `:139-145` rewritten: the snapshot is taken at operation-run time now, and
  why that is safe (the day cannot change under a pending write).

**Tests (tester), new file `Tests/DiaryWriteDoorTests.swift`,** every race forced with a `Gate`
held at `.willWrite` and settled by counting `.didWrite`, never by sleeping (ADR §D9):

1. *A newer save is never overwritten by an older one.* Add entry A; hold its write; add entry B;
   release; wait for the writes to finish; the file holds A and B. Red today: B's write lands
   first and A's older snapshot lands over it.
2. *A keystroke typed during a write is written too.* Type, flush, hold; type a second sentence;
   release; after the first `.didWrite`, `flush()`; the file eventually holds the second sentence.
   Red today: the second sentence is marked clean by the first write and never written.
3. *A day switch waits for its write.* Type, `move(by: 1)` with the flush held: `day` is still
   `testDay`. Release: `day` becomes the next day and the file holds the sentence. Red today: `day`
   changes synchronously.
4. *Coming back before the flush landed keeps the flushed text.* Start from a file on disk; type;
   `move(by: 1)`, `move(by: -1)` with the flush held; `prose` still holds the sentence; release;
   type more; flush; the file holds both. Red today: `move(by: -1)` re-reads the pre-flush file and
   the next save writes over the sentence.
5. *Two clicks during a flush go two days.* Regression guard for the destination rule, **green on
   today's code** (today switches synchronously) and required to stay green.

**Existing tests whose timing changes (tester, explained here rather than silently edited):**

- `DiaryControllerTests.writesTheDayBeforeLeavingIt` (`:122-137`): add
  `try await waitUntil { diary.day == testDay.adding(days: 1) }` before its last `#expect`. The day
  now changes after the flush lands (ADR §D5); the assertion itself is unchanged.
- `readsBackWhatItWrote` (`:94-120`), `keepsABlockOfThreeHours` (`:208-222`) and
  `drawsABlockThatRunsToMidnight` (`:386-405`): add `try await waitUntil { diary.isSettled }` before
  their `move(by: 1)`. Without it, a write still in flight makes `move(by: 1)`/`move(by: -1)` land
  back on the same day without re-reading, and the test would pass without doing the round trip
  through the file it exists to check. This keeps their meaning; it does not weaken them.
- Every other diary test (`makeDiary`'s `show(testDay)` on a fresh controller,
  `writesNothingForADayNothingWasWrittenOn`, `writesWhatIsOwedBeforeRereadingTheSameDay`,
  `DiaryComposerTests`) takes the settled path and is unchanged.

---

### Task 3 - The read carries its disk state, the controller records its origin, and the write proves it (brief items 1, 2, 3)

**Declarations (tester):**

- `Sources/Vault/VaultSession+Diary.swift`: `enum DiaryDiskState` (ADR §D1); `readDiary` returns
  `(prose:, entries:, disk:)?`; `writeDiary(prose:entries:on:over:) async -> WriteOutcome`, `over`
  mandatory.
- `Sources/App/VaultController+Diary.swift`: the facade's `readDiary(on:)` returns the same triple;
  `writeDiary(prose:entries:on:over:) async -> WriteOutcome` (was `-> Bool`, `@discardableResult`
  kept), returning `.failed` when there is no session.
- `Sources/Features/Diary/DiaryController.swift`: `enum DiaryOrigin` (ADR §D2) and
  `private(set) var origin: DiaryOrigin = .none`.

**Bodies (coder):**

- `VaultSession.readDiary`: `disk` from the same `read(_:)` - `.present(hash: record.contentHash)`
  when the file was read, `.absent` otherwise; when `preferring:` supplies the text, `disk` still
  describes the file on disk (ADR §D1).
- `VaultSession.writeDiary`: `.present(h)` → `expecting: h`; `.absent` → `expectingAbsent: true`. A
  `VaultWriteRefusal` maps to `.stale` **without** `recordProblem`; any other error keeps recording
  one and returns `.failed`.
- `VaultController.writeDiary`: passes `over:` through, keeps `syncOpenNote(with:)` on a result,
  returns the outcome.
- `DiaryController`:
  - `reload` sets `origin = .read(file: root + path, disk:)`, or `.none` with no vault.
  - The write operation (Task 2) reads `origin` **after** its predecessor settled, writes
    `over: origin.disk`, and on success advances `origin` to
    `.present(hash: NoteStore.hash(Data(result.text.utf8)))`.
  - The `hasContent || vault.readDiary(on: day) != nil` guard (`:135`) becomes
    `hasContent || origin.disk != .absent` - no main-actor re-read.
  - On `.stale`: enter `.conflicted(reason:)` through one private door that calls
    `vault.recordProblem` once.
  - While conflicted, `save()`/`flush()` write nothing, `show(_:)` refuses, `load()` does not
    re-read (ADR §D6).
  - Vault or file mismatch (ADR §D7): an operation whose target (current root + path) differs from
    `origin.file` writes nothing; if anything was owed it records «modifiche al diario del …, non
    salvate: il file non è più quello letto» and reloads the day.
- **SwiftLint headroom, a pure move with no signature change:** today the file is 315 lines against
  `file_length`'s 400 warning, and the type body measures about 190 code lines (comments and blank
  lines excluded, as SwiftLint counts them) against `type_body_length`'s 250 warning. Tasks 2-4 add
  an estimated 120-160 lines, comments included. Move the read-only timeline geometry (`:292-314`)
  to `DiaryController+Geometry.swift` and the composer (`:232-290`, `DiaryDraft` and its four
  methods) to `DiaryController+Composing.swift`. Every writer of `origin`, `saveState`, `prose` and
  `entries` stays in the declaring file, so no `private(set)` is widened. `commitDraft()` reaches
  `add`/`update`, both internal; nothing needs widening. Run `tuist generate --no-open` after.
- `VaultSession+Diary.swift:6-8`'s doc comment and `writeDiary`'s («creating the file and its
  folder when they are missing») are extended with the precondition and the refusal.

**Tests (tester), new file `Tests/DiaryWriteGuardTests.swift`:**

- Session level: `readDiary` returns `.absent` for a missing day and
  `.present(hash: NoteStore.hash(<bytes on disk>))` for a written one, still the disk hash when
  `preferring:` supplies different text; `writeDiary(over: .present(stale))` returns `.stale`, leaves
  the file untouched and records no problem; `over: .absent` over an existing file returns `.stale`;
  `over: .absent` over a missing file returns `.written`.
- Controller: type, flush, hold at `.willWrite`, **another writer changes the file**, release → the
  file still holds the other writer's text, `saveState` is `.conflicted`, one problem recorded. Red
  today: the file is overwritten.
- The creation variant: an empty day with no file; type; hold; another writer **creates** the file;
  release → refused, conflicted, the created file intact. Red today.
- Consecutive own saves over an existing file (`add`, `move`, `resize`, each saving immediately)
  **never conflict** and the file ends on the last one. Green today; this is the guard that goes red
  if the precondition ever lands without Task 2's serialization.
- While conflicted: `flush()` produces no `.didWrite` and no byte change; `show(_:)` leaves `day`
  unchanged; `load()` leaves `prose` unchanged.
- Vault switch: read a day in vault A, type, open vault B on the same `VaultController`, `load()` →
  nothing written to B's `Diario/20260811.md`, one problem recorded, the pane shows B's day.

**Update tests and call-sites asserting the old behaviour** (grep:
`rg -n "readDiary|writeDiary" Sources Tests`, run at `e61dbe2b`):

| Site | Change |
|---|---|
| `Sources/App/VaultController+Diary.swift:14-17` | facade returns the triple (above) |
| `Sources/App/VaultController+Diary.swift:26-31` | `over:` parameter, returns `WriteOutcome` |
| `Sources/Features/Diary/DiaryController.swift:102` | `reload` stores `origin` from `diary.disk` |
| `Sources/Features/Diary/DiaryController.swift:135` | guard reads `origin.disk`, no re-read |
| `Sources/Features/Diary/DiaryController.swift:150` | `guard await vault.writeDiary(...)` on a `Bool` becomes a switch on the outcome |
| `Tests/VaultSessionTests.swift:283` | add `over: .absent` (fresh vault, the file does not exist) |
| `Tests/VaultSessionTests.swift:288` | compiles unchanged (`read.entries` on the labelled triple) |
| `Tests/VaultAsyncCascadeTests.swift:114,118` | the function reference now has four parameters; the call at `:118` adds `.absent` |
| `Tests/VaultAsyncCascadeTests.swift:122` | compiles unchanged |

No connector calls the diary API (`rg -n "readDiary|writeDiary" Sources/CLI Sources/MCPServer
Sources/Connector` is empty), so no connector changes; both tool builds still compile
`VaultSession+Diary.swift` and are checked.

---

### Task 4 - The conflict in the pane, and the two verbs that resolve it (brief item 4)

**Declarations (tester):** `keepLocalDiary()` and `reloadDiaryFromDisk()` on `DiaryController`, in
the declaring file (both write `origin`, `prose`, `entries`, `saveState`).

**Bodies (coder):**

- `keepLocalDiary()`, «Tieni la mia versione»: re-read only the disk state of the current day's
  file, adopt it as `origin` without touching `prose`/`entries`, set `.pending`, enqueue one write.
  A refusal re-enters the conflict: one attempt per click, never a loop.
- `reloadDiaryFromDisk()`, «Ricarica da disco»: re-read the day and replace `prose`, `entries` and
  `origin`; an absent file reloads as `emptyDiaryNote` with `origin.disk == .absent`. State
  `.saved`.
- **New `Sources/Features/Diary/DiaryView+Conflict.swift`**: `var conflictBanner: some View`, the
  shape of `EditorColumn+Conflict.swift` - `exclamationmark.triangle.fill` in
  `theme.color(.taskOverdue)`, a caption, `Spacer()`, the two buttons, background
  `theme.color(.accentMuted)`, padding `theme.spacing(.s)`. Tokens only (the binding design-system
  rule). Identifiers: `diary-conflict-banner`, `diary-conflict-reload`, `diary-conflict-keep-local`.
  Caption proposed: «Il diario è cambiato su disco mentre lo stavi scrivendo.» (to confirm, see
  Risks). A separate file because `DiaryView.swift` is 127 lines and the strip would take it past
  the 150-line view guideline.
- `DiaryView.swift`: the strip sits between `header` and the `Divider()` in `writingColumn`, shown
  only when `saveState` is `.conflicted`; `.task { controller.load() }` (`:42`) becomes
  `.task(id: vault.root) { controller.load() }` (ADR §D7).
- `DiaryToolbar.swift`: «Giorno precedente» (`:17`), «Oggi» (`:23`, combined with its existing
  `.disabled(controller.day == .today)`), «Giorno successivo» (`:29`) and «Vai a data» (`:35`)
  disabled while conflicted. The controller's own refusal in `show(_:)` is the guard; the disabled
  buttons are only the affordance. «Nuovo blocco» stays enabled: editing memory while conflicted is
  allowed.

**Tests (tester), new file `Tests/DiaryConflictTests.swift`:**

- keep: after a conflict, `keepLocalDiary()` → the file holds the pane's text, `.saved`, `origin`
  advanced;
- reload: `reloadDiaryFromDisk()` → `prose` and `entries` are the other writer's, `.saved`, the next
  edit writes over the reloaded file without conflict;
- keep with a third writer: the hook writes the file again at `.willWrite` of the keep's write →
  refused, conflicted again, the third writer's bytes intact, exactly one `.didWrite`;
- absent-file cases: the file deleted externally after the read → conflict; reload gives
  `emptyDiaryNote` and `.absent`; keep writes it back through `expectingAbsent`;
- after either verb, `show(_:)` works again.

No GUI test is added (the ADR's budget is zero); the strip's two buttons call these two verbs and
nothing else.

---

### Task 5 - Correct every claim this change makes false, and file what it leaves open (documentation obligation)

Coder, in this branch:

- Doc comments: `DiaryController`'s type comment (the serial door, the origin, the conflict state),
  `load()`/`show(_:)`, `VaultSession+Diary.swift:6-8` and `:38`, `VaultController+Diary.swift:25`,
  the `expectingAbsent` paragraph on `VaultSession.write` and `VaultDisk.write`.
- `rg -n "isDirty|skipDiskReadBecauseJustFlushed|problems" Sources/Features/Diary` returns nothing
  stale.

Proposed for Stefano's decision, not applied by default:

- A one-line cross-reference under ADR-0043 §D8 pointing to ADR-0057, as PG-168 added for
  `requiringExistingFolder`. Editing an accepted ADR's body is Stefano's call; the chain works
  without it.
- A row in the Diario help sheet (`Sources/Features/Help/HelpSheets.swift:104-128`, section «La
  pagina») explaining the strip, copy to be approved.

For the orchestrator at ship time (not in this branch's code):

- `CLAUDE.md` chain index: one ADR-0057 entry.
- Optional working agreement, the other side of ADR-0043 §D7's: «a flag cleared after an `await`
  describes the snapshot, not the state» - the lost-keystroke defect.
- `TODO.md`: close `PG-153`, and file the follow-ups the ADR names in §D8 (next free ids, `PG-227`
  onward at the time of writing):
  1. the Diario pane reloads a clean day on an external change (watcher wiring);
  2. the remaining single-hop unguarded read-then-write sites (`append`, `linkFromDailyNote`, the
     `RelatedLink` pair, the board drop, `captureTask`'s creation case via `expectingAbsent:`);
  3. verify whether the diary's quit flush lands before the process exits;
  4. `WorkspaceController.load(board:)`/`select(_:)` drop a conflicted board silently.

---

### Task 6 - Verification (all brief items)

1. `tuist install && tuist generate --no-open` (the workspace is not generated in this worktree).
2. **The full unit suite**, not only the new files: the diary read/write contract changes, and
   `VaultSession.write` is shared by every writer in the app.
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
3. Both tool builds, since `VaultSession.swift`, `VaultDisk.swift` and `VaultSession+Diary.swift`
   are in `sharedSources`: the `perg` and `pergamenum-mcp` schemes, `build`.
4. SwiftLint on the touched files: no new error, and no new `file_length`/`type_body_length`
   warning on `DiaryController.swift`.
5. `scripts/uitests.sh --status`, then `--affected` at merge (non-blocking, per `CLAUDE.md`'s merge
   gate); `DiaryUITests` is the class a diary change can reach.
6. Hand-check on a throwaway vault (launched with `-recentVaults '("/path")'`, the latest Debug
   build found with `ls -dt`), never on Labs:
   - type in today's diary, append a line to the same file from Terminal, type again: the strip
     appears after the pause, the appended line is still in the file; «Ricarica da disco» shows it;
     repeat and «Tieni la mia versione» writes the pane's text;
   - while the strip is up, the day navigators are disabled;
   - with `diaryFolder` set equal to `dailyFolder` in Impostazioni, open an empty today in the
     Diario, capture a task from the global capture panel, then type in the Diario: the strip
     appears and the captured task is not erased;
   - type a sentence and click «Giorno successivo» then «Giorno precedente» at once: the sentence is
     still there and in the file.

---

## Risks & HITL gates

- **ADR acceptance.** ADR-0057 is `proposed`; Stefano accepts it (or not) before `/build`.
- **User preferences to confirm with Stefano, not decided here:**
  - blocking day navigation while conflicted (ADR §D6, Alternative 9). The alternative - let the
    day change and record a problem - is the one ADR-0054 took for closing a board;
  - the strip's copy: the editor's wording («Ricarica da disco» / «Tieni la mia versione», reused
    here) or the board's wording from ADR-0054 («Mantieni le mie modifiche» / «Ricarica dal
    disco»). The two surfaces already disagree; this plan follows the editor because the Diario
    column is that editor;
  - no mockup: `CLAUDE.md` asks for an approved mockup per milestone screen. This is a strip that
    copies an existing one, not a screen, but whether that exempts it is Stefano's call;
  - the optional ADR-0043 cross-reference line and the help-sheet row (Task 5).
- **Behaviour change visible to the person:** `show(_:)` is no longer synchronous when something is
  owed. The delay is one actor write (milliseconds), but a very slow disk would show it.
- **A vault switch or a `diaryFolder` change with unsaved diary text** reports and drops at most the
  last debounce interval of typing (ADR §D7). Flushing the diary before the old session closes
  would remove even that, but needs `VaultController` to know `DiaryController`, an inverted
  dependency; not done, and worth a line in the follow-ups if Stefano wants it.
- **A test seam in a production type** (`testOnlyWriteHook`), nil in production and
  `@ObservationIgnored`. Same trade ADR-0043 §D9 and ADR-0050 already made.
- **Against another process the window narrows, it does not close** (compare-then-write inside the
  actor), the limit every `expecting:` site shares.
- **ADR number collision** with a parallel worktree that also claims `0057` before this one merges.
  Recheck `docs/adr/` on `main` at ship time and renumber if needed (file name, title, the plan's
  references, the `CLAUDE.md` index line).
- **CI is advisory**, and it does not run the UI suite; a green badge is not the merge gate.
- **HITL gates:** every commit and the push are Stefano's approval, per task. No schema change
  (`IndexCache.schemaVersion` stays 4), no on-disk format change, no deletion of user data, no
  deploy. The test-file deletions in Task 2 are code moves (private helpers moved to shared files),
  shown in the diff.
- **No externally provisioned resource** is needed: no API, no consent flow, no env var or port.
  `tuist install` fetches the already-pinned SPM dependencies.
