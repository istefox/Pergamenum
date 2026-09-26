# Plan — The ordering guard covers every writer: ADR-0043 §D1–§D8, implemented

- **ADR:** `docs/adr/0043-vault-write-ordering-concurrency-races.md`. Everything below cites it as
  **ADR-0043 §D1…§D10**. ADR-0041 §D9/§D10/§D11/§D12 are cited where this chain extends them.
  No new ADR number is opened: ADR-0043 already decided §D1–§D8 in full, and this plan implements
  that decision rather than re-deriving it. The implementation-note addendum this plan needed to
  record back (the §D8 adoption list, the corrected §D2 cascade inventory, one residual hazard) was
  appended to ADR-0043 as `## Implementation notes (chain 2026-09-13)` and alters none of its
  decisions.
- **Requirement ids.** `SPEC.md`, this chain: `R-01`…`R-20`. Every one is cited by at least one
  task below, and no id outside that set is cited. `R-18`–`R-20` carry `(no-test: …)` in the SPEC,
  which exempts them from the *test* axis only — they are cited by Task 10 like any other id
  (ADR-0138). `PG-150` is a `TODO.md` ledger id, `#259` a GitHub issue number and `§D*` an ADR
  cross-reference; none of the three is ever used as a requirement id.
- **Harness:** **one created, in Task 10** — `scripts/adr-0043-interleaving-check.sh`. Its header
  names this plan's basename (`2026-09-13-vault-write-ordering-adr-0043.md`) and `ADR-0043`, so the
  anchor scan resolves to this feature and not to a precedent citation (ADR-0154). It exists
  because ADR-0043 §D9 makes the five interleaving tests the acceptance criterion and a green suite
  explicitly *not* one: the script asserts the five `@Test` functions exist and ran, and greps the
  three structural invariants (`index.update` reachable only from `apply`, no `writeSynchronously`,
  no `updateIndex`). **Bash 3.2-clean** — no `mapfile`, no associative arrays, no `${var^^}`;
  collect with `arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)`. The standing gate
  stays `.claude/test-cmd`, plus `scripts/uitests.sh` and both connector builds before the merge to
  `main`, per CLAUDE.md.
- **Branch:** `fix/vault-write-ordering-adr-0043` off `main`. Never on `main` directly, never
  force-pushed.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -derivedDataPath "/Users/stefer/Developer/Pergamenum/.build/DerivedData" -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield

> **Unchanged from `.claude/test-cmd`, verified byte-for-byte against it, and it still suffices.**
> All five interleaving tests (`R-11`–`R-15`) are Swift Testing cases in `Tests/`, compiled into
> `PergamenumTests`, picked up with no edit to that file. **Do not narrow it** to
> `-only-testing:PergamenumTests/VaultWriteOrderingTests` as the batch gate: this chain converts 25
> test files to `async`, and a narrowed filter would hide exactly the cascade that makes the chain
> risky. A narrower filter is fine *inside* one task's own red→green loop and never as the gate.
> **Do not widen it** to the whole scheme either: CLAUDE.md's «the UI suite is not in `test-cmd`»
> rule is load-bearing and was paid for once already, in two hours spent hunting an external
> culprit for something the assistant was doing to itself. `scripts/uitests.sh` runs deliberately,
> before the merge, as Task 10 step 6.

EXTERNAL DEPENDENCY: xcodebuild | binary | provisioned: true
EXTERNAL DEPENDENCY: python3 | binary | provisioned: true

> **No new dependency is added by this chain** — no SPM package, no framework, no service, no
> network of any kind. ADR-0043's header says so explicitly («Adds no exception to CLAUDE.md
> principle 2… The whole of this ADR is about the order in which this process touches its own
> files»). The two lines above are the tools the acceptance steps need: `xcodebuild` for every
> build and test, `python3` for `scripts/mcp-smoke.py` at `R-16`. Both are verifiable kinds and G13
> probes them for real.

CODER-MODEL CANDIDATE: opus

> Swift 6 strict concurrency, and the hardest kind: this chain moves four file operations inside an
> `actor`, converts roughly 210 call sites across 46 files from synchronous to `async`, turns a
> `rethrows` scoped-state helper (`transaction`) into an `async` one, changes two SwiftUI closure
> *types* (`ViewQuerySource.move`/`.undo`) to `async`, and then asks for five tests that force a
> suspension-point interleaving deterministically. Every one of the compiled-language hazards of
> ADR-0155 (the retired concept-to-code workflow's ADR, not a Pergamenum one) is present, and the
> defect class being fixed is the one a green suite cannot detect. Not
> a Sonnet job, and the review that raised ADR-0043 says why: «static analysis and a green suite
> cannot demonstrate thread safety».

---

## Order, and why it is this order

ADR-0043's own dependency graph fixes it, and one constraint in it is not obvious:

**§D1 cannot land before §D2.** §D1 deletes `updateIndex(_:at:)` and makes `apply` the only door
onto the index. The synchronous `write` door writes the index with a bare
`index.update(try store.read(relativePath).record, at: relativePath)` (`VaultSession.swift:265`)
and *cannot* be made to route through `apply`, because `apply` will consume an `IndexMutation`
stamped inside an actor and a synchronous function cannot await one. So the sync door has to be
gone before the clock can exist. The mechanical conversion is therefore first — which is also what
ADR-0043's Negative consequences ask for («the plan's task boundaries have to keep the mechanical
changes in separate commits from the behavioural ones»).

1. **Tasks 1–3: the mechanical async cascade (§D2), in three vertical slices.** The split is by
   *feature family*, not by layer, and that is forced: once `captureTask` becomes `async`, every
   one of its callers up to the SwiftUI button must become `async` in the same commit or the target
   does not compile. A horizontal split (all of `Sources/Vault` first, then all of `Sources/App`)
   has no compiling intermediate state. A vertical split does, because the synchronous door
   survives until the *end of Task 3* for the families not yet converted. **Task 3's last step
   deletes it.**
2. **Task 4: the clock and the single index door (§D1).** First commit that changes behaviour.
3. **Task 5: the watcher (§D3) and `readForEditing` (§D4).** Both are index writers §D1 left
   standing; they are done together because §D4 is a deletion that only becomes safe once §D3 has
   stamped the watcher.
4. **Task 6: the journal's «before» (§D5).** Needs §D1's actor-owned write to read in.
5. **Task 7: `selfWrittenHashes` (§D6).** Needs §D1's clock to prune by, and §D3's reconciliation
   to prune from.
6. **Task 8: the hand-off and the prompt (§D7).** Wants §D2's `async saveOpenNote` to be the thing
   it contends with.
7. **Task 9: `expecting:` (§D8).** Needs §D5's in-actor read to compare against, for free.
8. **Task 10: the harness, the sweep, the record.**

Batching suggestion for the orchestrator: `{1} · {2} · {3} · {4} · {5} · {6} · {7} · {8} · {9} · {10}`.
**Nothing in this plan may be fanned out in parallel worktrees.** Tasks 1, 2, 3, 4, 6, 7 and 9 all
edit `VaultSession.swift` and `VaultDisk.swift`; Tasks 3, 5 and 8 all edit
`VaultController+Editing.swift`. Sequential is the only safe order, and a concurrency chain merged
out of order is the exact failure it is meant to prevent.

---

## What changes an observable contract, and every call-site found

Grepped across `Sources/` and `Tests/` on the working tree before this plan was written
(2026-09-13, branch `emdash/strict-steaks-argue-n6z2c`). The coder does not have to discover these.

| Symbol | Change | Call-sites that must move with it |
| --- | --- | --- |
| `VaultSession.write(_:to:) throws` + `writeSynchronously` | **deleted** (§D2) | `VaultSession.swift:252-254`, `:256-290`. Nothing may reference either after Task 3. |
| `VaultSession.write(_:to:)` (the surviving async door) | gains `expecting: String? = nil` (§D8) | Default `nil`, so no existing call site changes shape. Adoption list below. |
| The ~18 internal `try write(…)` sites in `Sources/Vault` | → `try await write(…)`; their enclosing functions become `async` | `+Watching:56` (`append`), `+TimeBlocks:43` (`setTimeBlocks`), `:98` (`dailyNoteBody`), `+Journal:284`, `:292` (`performUndo`), `+Notes:62` (`createNote`), `:191`, `:192` (`addStructuralLink`), `+Diary:43` (`writeDiary`), `+Files:27` (`renameNote`), `+BoardDrop:78` (`moveOnBoard`), `+TagRename:82` (`renameTag`), `+EventNotes:79` (`linkFromDailyNote`), `+SampleViews:29` (`installSampleViews`), `+Tasks:167` (`writeTaskSource`), `:216` (`captureTask`), `:245` (`captureSubtask`). |
| `VaultSession.writeFile`, `moveFile`, `trashFile` | → `async`, then moved inside `VaultDisk` (§D1) | `+Journal:156`, `:52`, `:111` (declarations); `+Files:26-60`, `:74` (callers); `Tests/VaultSessionJournalTests.swift:89`, `:108`, `:121`, `:134`, `:154`, `:155`, `:176`, `:179`, `:192`; `Tests/VaultBoundaryCallSiteTests.swift:112-167`. |
| `VaultSession.transaction(_:_:) rethrows` | → `async rethrows`, `async` body closure | `+Files:22`, `:52`, `:74`; `Tests/VaultSessionJournalTests.swift:40`, `:72`, `:153`. **See the hazard note under Task 3 — this is not purely mechanical.** |
| `VaultPlanApplication.apply(_:writing:)` | **async overload added**, sync one kept | Async overload needed at `VaultSession+Files.swift:26`, `:32`, `:56` and `VaultSession+TagRename.swift:81` (the four that write through `session.write`/`writeFile`). The sync overload stays for `NoteFileOperations:224`, `:230`, `FolderFileOperations:398`, `:404`, `FolderFileOperations+Move:119`, `BoardFileOperations:160`, `:167`, `:280` — those write through `store.write` / raw `Data.write` and are not vault-session writers. `Tests/VaultPlanApplicationTests.swift` must keep passing **unchanged**: if it goes red the sync overload's behaviour changed. |
| `VaultSession.reconcile(_:)` | → `async`, reads inside the actor, returns mutation + changes (§D3) | `VaultController+Watching.swift:23` (already inside `Task { @MainActor }`, `:11`); `Tests/VaultSessionTests.swift:335`, `:339`, `:345`. |
| `VaultSession.updateIndex(_:at:)` | **deleted** (§D1, R-02) | `VaultSession.swift:293-295` (declaration); callers `+Journal:78`, `:86`, `:131`; `+Watching:27`, `:37`; `+WriteOrdering:24`; `VaultController+Tabs.swift:359`. After Task 4, `grep -rn "index\.update" Sources/` must return exactly one line, inside `apply`. |
| `VaultSession.apply(_ outcome:at:) -> Bool` | → `apply(_ mutations: [VaultDisk.IndexMutation]) -> Int` (§D1) | `VaultSession.swift:534`; `Tests/VaultWriteOrderingTests.swift:73`, `:77`. |
| `VaultSession.selfWrittenHashes` | `[String: String]` → `[String: [(sequence: UInt64, hash: String)]]` (§D6) | `VaultSession.swift:78` (declaration), `:264`, `:503`; `+Watching:32`, `:33`; `+Journal:77`, `:129`; `Tests/VaultWriteOrderingTests.swift:46`, `:101`. |
| `VaultController.saveOpenNote()`, `restoreVersion(_:)` | → `async` (§D2) | `CommandActions.swift:178`; `EditorColumn+Text.swift:140`; `NoteTabBar.swift:77`; `EditorColumn+Closing.swift:40`; `VaultController+Editing.swift:46` (internal). Tests: `NoteHistoryTests.swift:267`, `:293`; `NoteTabTests.swift:201`; `VaultTests.swift:413`. **`closeAfterSaving()` is not mechanical — see Task 3.** |
| `VaultController` write facades | → `async`: `createNote`, `renameNote`, `moveNote`, `trashNote`, `captureTask`, `addTimeBlock`, `setTimeBlocks`, `writeDiary`, `eventNote`, `addStructuralLink`, `renameTag`, `undoJournalledWrites`, `installSampleViews`, `moveOnBoard` | SwiftUI/controller call sites: `NoteListPane.swift:201`, `:215`; `NoteRowMenu.swift:36`, `:42`; `VaultBrowser.swift:76`; `NewNoteComposer.swift:211`; `WorkspaceView+Creation.swift:74`; `RelatedLinkSheet.swift:86`; `TaskComposer.swift:168`; `TagBrowserView.swift:304`, `:318`; `SettingsView.swift:52`; `EditorColumn+Text.swift:225`, `:226`; `DayController.swift:263`; `DayController+TaskDrop.swift:63`; `DiaryController.swift:113`; `RecordingsController.swift:412`; `VaultController+Tasks.swift:71`, `:104`; `VaultController+Routes.swift:80`; `VaultController+Notes.swift:83`. |
| `ViewQuerySource.move`, `.undo` | closure **types** become `async`: `(@MainActor (String, Tag?, Tag?) async -> VaultSession.BoardDropOutcome)?` and `(@MainActor (String) async -> Bool)?` | `Sources/Features/Views/ViewQuerySource.swift:25`, `:27` (declarations); `EditorColumn+Text.swift:225`, `:226` (the only construction site with non-nil closures); every renderer that invokes them (`RenderedViewBlock` and the board drop handler — grep `source.move`/`source.undo` before editing; a SwiftUI `.dropDestination` returns `Bool` synchronously and must wrap the call in `Task { }` while returning `true` optimistically, or refuse the drop). **This is a design decision, not a mechanical edit — see Task 2.** |
| `VaultAPI` / `VaultWrites` statics | → `async`: `createNote`, `appendToNote`, `renameNote`, `moveNote`, `trashNote`, `addTask`, `changeTask`, `addTimeBlock` (`undo` already is) | `Sources/CLI/Commands/WriteCommands.swift:12`, `:38`, `:47`, `:56`, `:133`; `Sources/MCPServer/VaultHost.swift:165`, `:177`, `:181`, `:185`, `:231`; `Sources/Connector/VaultCapture.swift:117`, `:152`. **Both front ends are already `async` end to end (ADR-0041 §D9), so this is `await` insertion and nothing structural** — which is the one place this chain is free (ADR-0043, Neutral consequences). |
| `VaultController.readForEditing` | stops calling `session.updateIndex` (§D4) | `VaultController+Tabs.swift:359` — the line is deleted and replaced by nothing. The read at `:358` stays exactly as it is. |
| `VaultController.syncOpenNote(with:)` | dirty branch sets `note.externalChangePending = result.text` (§D7) | Behaviour changes at all nine sites: `VaultController+TimeBlocks.swift:40`, `:61`, `:97`; `+Diary:29`; `+TaskDrop:33`; `+Routes:133`; `+Tasks:20`, `:66`; and the composer's new one (`PraticaEntryComposer.handOff`). |
| `VaultSession.WriteRefusal` | **new** error type (§D8) | New declaration. `CustomStringConvertible` with an Italian description, beside `FileOperationError` in `Sources/Core/Vault/` or as a nested type on `VaultSession` — the coder picks one and states which; it must be `Sendable` and reachable from `Sources/Connector`. |

### The seven test files ADR-0043 names are twenty-five

ADR-0043 §D2 lists seven test files, and that list was correct for the scope it was measuring — the
files that call `saveOpenNote`/`restoreVersion`/`write` *directly*. The full §D2 + §D1 cascade
reaches further, because the wrappers those files call become `async` too. Grepped, with match
counts:

```
 7  Tests/BoardDropTests.swift            1  Tests/TaskDropTests.swift
 1  Tests/CapturePanelTests.swift         1  Tests/TaskMarkerLintTests.swift
29  Tests/CaptureTests.swift              3  Tests/TaskTests.swift
63  Tests/ConnectorTests.swift            3  Tests/VaultBoundaryCallSiteTests.swift
 3  Tests/EventNoteTests.swift            1  Tests/VaultMoveTests.swift
 4  Tests/GuardrailTests.swift           13  Tests/VaultSessionFileOperationsTests.swift
 6  Tests/NoteHistoryTests.swift         13  Tests/VaultSessionJournalTests.swift
 1  Tests/NoteTabTests.swift             10  Tests/VaultSessionTests.swift
 2  Tests/NoteTemplateTests.swift         1  Tests/VaultTests.swift
10  Tests/PraticheConnectorTests.swift    5  Tests/VaultWriteOrderingTests.swift
 3  Tests/RelatedLinkTests.swift         10  Tests/ViewConnectorTests.swift
 3  Tests/StarredTests.swift
10  Tests/TaskComposerTests.swift
 7  Tests/TagRenameTests.swift
```

**Twenty-five files, roughly 210 call sites.** Each task below names the subset it owns. Several of
these tests write and then read the file straight back off disk with no `await` in between — that
sequencing is the thing the sync door guaranteed and `await` now guarantees instead, so an
assertion that was correct stays correct; an assertion that was *accidentally* correct because two
writes happened to be ordered by program flow will fail, and that failure is information, not
noise. **Never re-sequence an assertion to make it pass without saying why in the commit message**
(CLAUDE.md: never disable a test to make a suite pass).

### After any of Tasks 1–4: run the full unit suite, not the vault tests

`VaultSession`, `VaultController` and `VaultDisk` are reached by roughly a fifth of the 231 files
in `Tests/`, and `VaultPlanApplication`/`VaultBoundary` live under `Sources/Core/**`, which both
command-line targets compile. A green `VaultSessionTests` proves nothing about `CaptureTests`,
`ConnectorTests`, `PraticheConnectorTests`, `ViewConnectorTests` or `TaskComposerTests`. Both
connector builds (`perg`, `pergamenum-mcp`) must be run too after every task that touches
`Sources/Core/**` or `Sources/Vault/**`: a file added there that imports SwiftUI breaks them, which
is ADR-0001 §D1 enforcing itself.

---

## Task 1 — Async cascade A: tasks, time blocks, diary (R-03)

Cross-refs: ADR-0043 §D2; ADR-0041 §D9's Negative consequences («`saveOpenNote()` becomes `async`,
which means its four call sites wrap it in `Task { }`»). Mechanical only — **no behaviour change,
no index change, no journal change**. The synchronous door still exists and is still used by the
families Tasks 2 and 3 convert.
Budget: `Sources/Vault/VaultSession+Tasks.swift`, `Sources/Vault/VaultSession+TimeBlocks.swift`,
`Sources/Vault/VaultSession+Diary.swift`, `Sources/App/VaultController+Tasks.swift`,
`Sources/App/VaultController+TimeBlocks.swift`, `Sources/App/VaultController+Diary.swift`,
`Sources/App/VaultController+TaskDrop.swift`, `Sources/App/VaultController+Routes.swift`,
`Sources/Features/Tasks/TaskComposer.swift`, `Sources/Features/Today/DayController.swift`,
`Sources/Features/Today/DayController+TaskDrop.swift`,
`Sources/Features/Diary/DiaryController.swift`, `Sources/Connector/VaultWrites.swift`,
`Sources/Connector/VaultCapture.swift`, `Sources/CLI/Commands/WriteCommands.swift`,
`Sources/MCPServer/VaultHost.swift`, plus 8 test files (~450 lines)

**Tester declares** (ADR-0155 — the tester owns the signature, the coder owns the body; on Swift a
batch that leaves the target unable to build produces no red tests at all):

```swift
extension VaultSession {
    @discardableResult func apply(_ change: TaskChange, to task: TaskItem) async -> WriteOutcome
    func captureTask(_ draft: TaskDraft) async -> WriteResult?
    @discardableResult func setTimeBlocks(_ blocks: [TimeBlock], on day: CalendarDate) async -> WriteOutcome
    func addTimeBlock(title: String, on day: CalendarDate, startMinutes: Int) async -> PlacedTimeBlock?
    @discardableResult func writeDiary(prose: String, entries: [DiaryEntry], on day: CalendarDate) async -> WriteOutcome
}
```

(the exact parameter lists are the ones already on disk — only `async` is added; the tester copies
them rather than retyping them.)

**Coder implements:**

1. `VaultSession+Tasks.swift`: `writeTaskSource`, `apply(_:to:)`, `captureTask`, `captureSubtask`
   become `async`; their `try write(` become `try await write(`. `taskSourceText(for:)` stays
   synchronous (it reads).
2. `VaultSession+TimeBlocks.swift`: `setTimeBlocks`, `addTimeBlock`, `dailyNoteBody` become `async`.
3. `VaultSession+Diary.swift`: `writeDiary` becomes `async`. `readDiary`, `emptyDiaryNote`,
   `diaryNotePath` stay synchronous.
4. Facades in `Sources/App`: `VaultController+Tasks.swift:20`, `:65-66`, `:71`, `:104`;
   `+TimeBlocks.swift:37`, `:53`, `:93`; `+Diary.swift:29`; `+TaskDrop.swift:33`;
   `+Routes.swift:80`. A facade that returns `Bool` keeps returning `Bool` and becomes `async`;
   it does **not** become fire-and-forget.
5. SwiftUI/controller call sites: `TaskComposer.swift:168`, `DayController.swift:263`,
   `DayController+TaskDrop.swift:63`, `DiaryController.swift:113`. Each wraps in
   `Task { @MainActor in … }` where the enclosing context is a synchronous SwiftUI action.
   **Where the `Bool` result drove a branch (`guard vault.setTimeBlocks(…) else { … }`), the branch
   moves inside the `Task`, it is not dropped.**
6. Connector: `VaultWrites.addTask`, `changeTask`, `addTimeBlock` become `async throws`;
   `VaultCapture` follows; `WriteCommands.swift:133` and `VaultHost.swift:231` gain `await` (both
   enclosing contexts are already `async`).

**Tests the tester converts in this task:** `VaultSessionTests.swift` (:84, :199, :207, :218, :232),
`TaskComposerTests.swift` (10), `TaskTests.swift` (3), `TaskDropTests.swift` (1),
`TaskMarkerLintTests.swift` (1), `CaptureTests.swift` (29), `CapturePanelTests.swift` (1),
`ConnectorTests.swift` (the `addTimeBlock`/`addTask`/capture cases only — `createNote` waits for
Task 2).

**Done when:** app target, both connector targets and `PergamenumTests` all build and the full unit
suite is green with no assertion re-sequenced.

## Task 2 — Async cascade B: notes, events, tags, boards, sample views, append (R-03)

Cross-refs: ADR-0043 §D2; ADR-0009 §D5 (`ViewQuerySource.move` is the one write a rendered view
makes). Mechanical, **except one design decision called out below**.
Budget: `Sources/Vault/VaultSession+Notes.swift`, `+EventNotes.swift`, `+TagRename.swift`,
`+BoardDrop.swift`, `+SampleViews.swift`, `+Watching.swift`,
`Sources/Core/Vault/VaultPlanApplication.swift`, `Sources/App/VaultController+Notes.swift`,
`+Files.swift`, `Sources/Features/Views/ViewQuerySource.swift`,
`Sources/Features/Editor/EditorColumn+Text.swift`, `NoteListPane.swift`, `VaultBrowser.swift`,
`NewNoteComposer.swift`, `RelatedLinkSheet.swift`,
`Sources/Features/Workspace/WorkspaceView+Creation.swift`,
`Sources/Features/Tags/TagBrowserView.swift`, `Sources/Features/Settings/SettingsView.swift`,
`Sources/Connector/VaultWrites.swift`, `Sources/CLI/Commands/WriteCommands.swift`,
`Sources/MCPServer/VaultHost.swift`, plus 9 test files (~550 lines)

**Tester declares:**

```swift
extension VaultPlanApplication {
    static func apply(
        _ changes: [VaultFileChange],
        writing: (VaultFileChange) async throws -> Void
    ) async -> Outcome
}

struct ViewQuerySource {
    var move: (@MainActor (String, Tag?, Tag?) async -> VaultSession.BoardDropOutcome)?
    var undo: (@MainActor (String) async -> Bool)?
}
```

**Coder implements:**

1. `VaultSession+Notes.swift`: `createNote`, `dailyNote(for:)`, `addStructuralLink` become `async`.
2. `+EventNotes.swift` (`eventNote`, `linkFromDailyNote`), `+TagRename.swift` (`renameTag`,
   `undoJournalledWrites`), `+BoardDrop.swift` (`moveOnBoard`), `+SampleViews.swift`
   (`installSampleViews`), `+Watching.swift` (`append(text:to:)`) become `async`.
3. **`VaultPlanApplication.apply` gains an `async` overload; the synchronous one stays.** The two
   are resolved by whether the call site says `await`, the same mechanism ADR-0041 §D9 used for
   `write` — and, unlike that case, this is *not* a second door in §D1's sense: `apply` owns no
   state, stamps no clock and touches no index. It is a `for` loop that collects failures. The
   async overload is used at `VaultSession+TagRename.swift:81` here, and at
   `VaultSession+Files.swift:26`, `:32`, `:56` in Task 3. The sync overload keeps its eight
   `store.write`/raw-`Data.write` call sites in the three file-operations types, which are not
   vault-session writers and are out of §D1's scope (they touch no index; the rescan repairs them,
   §D4's own argument). `Tests/VaultPlanApplicationTests.swift` must pass **unchanged**.
4. **`ViewQuerySource.move`/`.undo` become `async` closures.** This is the one genuinely
   non-mechanical edit in the task, and it is a decision rather than a translation: a SwiftUI drop
   handler is synchronous and returns `Bool`. **Decision: the drop handler wraps the call in
   `Task { @MainActor in … }` and returns `true` immediately, reporting any failure through the
   existing problem channel rather than through the return value.** Rejected alternative: keeping
   the closures synchronous by having them enqueue onto a queue the session drains — that is a
   third write door with its own ordering regime, which is the defect this chain exists to remove.
   Rejected alternative: refusing the drop while a write is in flight — ADR-0043 rejects
   in-flight refusal by name («the second caller is usually the user pressing Cmd+S»). Grep
   `source.move`/`source.undo` before editing; if a renderer other than `RenderedViewBlock`
   invokes them, it gets the same treatment.
5. Facades and views: `VaultController+Notes.swift:25`, `:77`, `:83`; `+Files.swift:150`, `:155`,
   `:161`, `:168`; `NoteListPane.swift:201`; `VaultBrowser.swift:76`; `NewNoteComposer.swift:211`;
   `WorkspaceView+Creation.swift:74`; `RelatedLinkSheet.swift:86`; `TagBrowserView.swift:304`,
   `:318`; `SettingsView.swift:52`; `EditorColumn+Text.swift:225`, `:226`.
6. Connector: `VaultWrites.createNote`, `appendToNote` become `async throws`; `VaultCapture:152`;
   `WriteCommands.swift:12`; `VaultHost.swift:165`.

**Tests the tester converts:** `NoteTemplateTests.swift`, `RelatedLinkTests.swift`,
`EventNoteTests.swift`, `TagRenameTests.swift`, `BoardDropTests.swift`, `ViewConnectorTests.swift`,
`GuardrailTests.swift`, `ConnectorTests.swift` (the `createNote`/`appendToNote` cases),
`StarredTests.swift` (partial — the `renameNote`/`moveNote`/`trashNote` cases wait for Task 3).

**Done when:** three targets build, full unit suite green, `Tests/VaultPlanApplicationTests.swift`
untouched and passing.

## Task 3 — Async cascade C: file operations, the journal transaction, the editor's saves — and the synchronous door is deleted (R-03)

Cross-refs: ADR-0043 §D2 (and its instruction that the comment at
`VaultController+Editing.swift:13-19` is **replaced, not deleted**: what it records is that the
conversion fails unless the tests move with it, which is this task's shape); ADR-0016 §D2/§D5 (the
journal's gesture grouping).
Budget: `Sources/Vault/VaultSession.swift`, `Sources/Vault/VaultSession+Journal.swift`,
`Sources/Vault/VaultSession+Files.swift`, `Sources/Vault/VaultSession+Move.swift`,
`Sources/App/VaultController+Editing.swift`, `+Files.swift`, `Sources/App/CommandActions.swift`,
`Sources/Features/Editor/EditorColumn+Text.swift`, `EditorColumn+Closing.swift`, `NoteTabBar.swift`,
`NoteRowMenu.swift`, `NoteListPane.swift`,
`Sources/Features/Recordings/RecordingsController.swift`, `Sources/Connector/VaultWrites.swift`,
`Sources/CLI/Commands/WriteCommands.swift`, `Sources/MCPServer/VaultHost.swift`, plus 10 test files
(~600 lines)

**Tester declares:**

```swift
extension VaultSession {
    @discardableResult
    func transaction<T>(_ command: String, _ body: () async throws -> T) async rethrows -> T
    func moveFile(from oldPath: String, to newPath: String) async throws
    func trashFile(at relativePath: String) async throws
    func writeFile(_ text: String, to relativePath: String) async throws
    func renameNote(at relativePath: String, to newTitle: String) async throws -> NoteFileOperations.Outcome
    func moveNote(at relativePath: String, toFolder folder: String) async throws -> NoteFileOperations.Outcome
    func trashNote(at relativePath: String) async throws -> [String]
    func undo(operation id: String) async -> TagRenameOutcome
}

@MainActor extension VaultController {
    func saveOpenNote() async
    func restoreVersion(_ text: String) async
}
```

**Coder implements:**

1. `transaction(_:_:)` becomes `async rethrows` over an `async` body. **Hazard, recorded rather
   than silently absorbed:** `currentOperation` is scoped state on a `@MainActor` object, and an
   `async` body means two transactions started from two `Task { }`s can now interleave — the
   second trips the existing `assertionFailure("transazione annidata…")` in Debug and, in Release,
   joins the wrong gesture. That is a *pre-existing* consequence of ADR-0041 §D9 (the async door
   already existed) which this task makes reachable from more call sites; it is **not** decided by
   ADR-0043 and is **not** fixed here. Keep the assertion exactly as it is, keep the Release
   fall-through exactly as it is, and file the follow-up (Task 10 step 8). Closing it properly
   means an actor-owned operation stack, which is a design decision and belongs in its own ADR.
2. `moveFile`, `trashFile`, `writeFile` become `async` (still executing on the main actor in this
   task — Task 4 moves them into `VaultDisk`). `renameNote`, `moveNote`, `trashNote` follow, using
   Task 2's async `VaultPlanApplication.apply` overload at `+Files:26`, `:32`, `:56`.
3. `performUndo`, `undo(operation:)` become `async`.
4. `saveOpenNote()` and `restoreVersion(_:)` become `async`. Replace the doc comment at
   `VaultController+Editing.swift:13-19` with one that records what actually happened: the
   conversion needed the tests to move with it, and they did, in this task.
5. **`EditorColumn+Closing.closeAfterSaving()` is not a mechanical edit.** Today it runs
   `vault.focusTab(tab.id); vault.saveOpenNote(); vault.closeTab(tab.id)` in one synchronous
   straight line. With an `async` save, `closeTab` must run **after** the save resumes, inside the
   same `Task { @MainActor in }`, or the tab is gone before the buffer is written and
   `saveOpenNote` writes whatever tab focus landed on instead — a data-loss bug this chain would
   have introduced. Same treatment at `EditorColumn+Text.replacementsApplied()` (`:140`), which
   saves right after an outline move: the save must complete before anything else touches the
   buffer. `CommandActions.swift:178` and `NoteTabBar.swift:77` are plain `Task { }` wraps with no
   ordering requirement.
6. `RecordingsController.swift:412` (`vault.trashNote`), `NoteRowMenu.swift:36`, `:42`,
   `NoteListPane.swift:215` gain `await` inside a `Task { }`, branch preserved.
7. Connector: `VaultWrites.renameNote`, `moveNote`, `trashNote` become `async throws`;
   `WriteCommands.swift:38`, `:47`, `:56`; `VaultHost.swift:177`, `:181`, `:185`.
8. **Last step, once nothing references them: delete `VaultSession.write(_:to:) throws`
   (`:251-254`) and `writeSynchronously` (`:256-290`).** Verify with
   `grep -rn "writeSynchronously" Sources/ Tests/` returning nothing. `Tests/VaultWriteOrderingTests.swift:109`
   mentions it in a comment — that comment is now historically wrong and is rewritten, not left.

**Tests the tester converts:** `VaultTests.swift`, `NoteHistoryTests.swift`, `NoteTabTests.swift`,
`VaultSessionFileOperationsTests.swift`, `VaultSessionJournalTests.swift`,
`VaultBoundaryCallSiteTests.swift`, `VaultMoveTests.swift`, `StarredTests.swift`,
`PraticheConnectorTests.swift`, `VaultWriteOrderingTests.swift`.

**Done when:** three targets build, full unit suite green, `grep -rn "writeSynchronously\|func write(_ text: String, to relativePath: String) throws" Sources/`
returns nothing.

## Task 4 — One clock, stamped where the bytes land; `apply` is the only index door (R-01, R-02, R-11)

Cross-refs: ADR-0043 §D1 and its rejected alternatives (caller-issued sequence, `Mutex`-guarded
clock, sync door bumping `appliedSequence` to a large value — all three rejected, do not revisit);
ADR-0041 §D11; `Sources/Vault/VaultDisk.swift:105-109` (`nextSequence(for:)`, the clock that already
exists and is kept).
Budget: `Sources/Vault/VaultDisk.swift`, `Sources/Vault/VaultSession.swift`,
`Sources/Vault/VaultSession+WriteOrdering.swift`, `Sources/Vault/VaultSession+Journal.swift`,
`Sources/App/VaultController+Tabs.swift`, `Tests/VaultWriteOrderingTests.swift`,
`Tests/VaultDiskTests.swift` (~400 lines)

**Tester declares:**

```swift
extension VaultDisk {
    struct IndexMutation: Sendable {
        let path: String
        let record: NoteRecord?   // nil: there is no file at this path any more
        let sequence: UInt64
    }

    func writeFile(_ text: String, to relativePath: String) async throws -> IndexMutation
    func moveFile(from oldPath: String, to newPath: String) async throws -> [IndexMutation]  // exactly two
    func trashFile(at relativePath: String) async throws -> IndexMutation
}

extension VaultSession {
    @discardableResult
    func apply(_ mutations: [VaultDisk.IndexMutation]) -> Int   // how many were newer than what we had
}
```

**Coder implements:**

1. `IndexMutation` as declared. `DiskWriteOutcome` keeps `hash` and `journalProblem` and carries
   its `IndexMutation` instead of the loose `record`/`sequence` pair.
2. `VaultDisk.writeFile`, `moveFile`, `trashFile`: the `FileManager.moveItem`, the `trashItem` and
   the non-note byte write move inside the actor, each taking its sequence from
   `nextSequence(for:)` **immediately after the disk operation lands** — never before the hop,
   never from the caller. A move returns two mutations, `(oldPath, nil, seq_old)` and
   `(newPath, record, seq_new)`, each stamped from its own path's clock, which is what makes a
   move orderable against a concurrent write to either end of it.
3. `VaultSession.apply(_ mutations:)` replaces `apply(_ outcome:at:)`. For each mutation: drop it
   unless `mutation.sequence > appliedSequence[mutation.path, default: 0]`, otherwise advance the
   counter and write the index. Return the count applied.
4. **Delete `updateIndex(_:at:)` rather than keeping it as a forwarder** (§D1 is explicit about
   this, and gives the reason: a guard a caller may route around is a guard the seventh call site
   will route around). Convert `+Journal:78`, `:86`, `:131` and `+Watching:27`, `:37` to route
   their mutations through `apply`; `+Watching` is finished in Task 5, so a temporary
   `apply([mutation])` with a sequence taken from the actor is acceptable here only if it compiles
   *and* Task 5 lands immediately after.
5. `VaultController+Tabs.swift:359` — see Task 5, which deletes it. If Task 4 must compile before
   Task 5, route it through `apply` temporarily; do not leave a raw `index.update`.
6. `VaultBoundary.url(for:)` is unchanged and every new actor entry point resolves through it
   (§D10), so ADR-0041 §D1's boundary holds by construction.

**Tester writes (R-11), red before step 1:**

`Tests/VaultWriteOrderingTests.swift` — `theOlderMutationFromADifferentWriterIsDropped()`.
Deterministic, no real timing: build two `IndexMutation`s for one path by hand — one a write's
record at `sequence: 2`, one a trash's `record: nil` at `sequence: 1` — and hand them to `apply` in
the inverted order. Assert `apply([newer]) == 1`, then `apply([older]) == 0`, then that
`session.index.note(at: path)` still holds the newer record. **Assert on the drop count, not only
on the end state**, or the test passes by accident when the guard is missing — the existing test at
`:83` makes that point and it still holds. The "sync writer vs async writer" half of R-11 is proved
by the sync writer's *absence*: Task 10's harness greps that `index.update` appears exactly once in
`Sources/`, inside `apply`.

**Done when:** `grep -rn "index\.update" Sources/` returns exactly one line;
`grep -rn "updateIndex" Sources/ Tests/` returns nothing; R-11 green; full unit suite green.

## Task 5 — The watcher reconciles inside the actor, and `readForEditing` stops writing the index (R-04, R-05)

Cross-refs: ADR-0043 §D3, §D4; ADR-0001 §D2.1 (the index is disposable by construction — the whole
of §D4's argument) and §D3.3 (a self-write is recognised by content hash, never a time window).
Budget: `Sources/Vault/VaultSession+Watching.swift`, `Sources/Vault/VaultDisk.swift`,
`Sources/App/VaultController+Watching.swift`, `Sources/App/VaultController+Tabs.swift`,
`Tests/VaultSessionTests.swift`, `Tests/VaultDiskTests.swift` (~250 lines)

**Tester declares:**

```swift
extension VaultSession {
    func reconcile(_ paths: [String]) async -> [ExternalChange]
}

extension VaultDisk {
    /// Reads one changed path, compares against the hashes the session recorded for it,
    /// advances that path's clock, and says both what the index must become and whether
    /// anybody outside this process wrote it.
    func reconcile(
        _ relativePath: String, selfWritten: [(sequence: UInt64, hash: String)]
    ) async -> (mutation: IndexMutation, change: VaultSession.ExternalChange?, matchedSequence: UInt64?)
}
```

(`selfWritten`/`matchedSequence` are §D6's shape; in this task the session may pass `[]` and ignore
`matchedSequence` — Task 7 wires them. The tester declares the final signature now so Task 7 is a
body change, not a second signature migration.)

**Coder implements:**

1. `reconcile(_:)` becomes `async` and delegates each path's read to `VaultDisk`. The full
   `NoteStore.read` (parse, wikilink scan, transclusion scan, task parse, SHA-256) leaves the main
   actor, which is the same cost ADR-0041 §D9 removed from the write path and left on this one.
2. The reconciliation's `IndexMutation` is stamped from the **same clock as every writer**, taken
   inside the actor in the same serialized straight line as the read. This is deliberate and is
   what makes the guard total: the record describes the file as the actor saw it, a later write
   wins, an earlier one loses.
3. A missing path yields `IndexMutation(path:, record: nil, sequence:)` rather than a bare index
   removal.
4. `VaultController+Watching.swift:23` gains `await` — it is already inside
   `Task { @MainActor … }` (`:11`), so this costs no new asynchrony at the call site.
5. **`VaultController+Tabs.swift:359` is deleted and replaced by nothing.** The read at `:358`
   stays byte-for-byte. Update the doc comment at `:350-353`, which currently promises it «puts the
   index back in step».

**Tester writes:** `VaultSessionTests.swift:335-345` gains `await`; a new case asserts that opening
a note through `readForEditing` leaves `session.index` untouched (write a record, mutate the file
behind the session's back, open it for editing, assert the index still holds the recorded value —
the repair is the cold scan's job, not the tab's).

**Done when:** `grep -rn "session\.updateIndex\|updateIndex(" Sources/` returns nothing; full unit
suite green; both connector targets build.

## Task 6 — The journal's «before» is read where the bytes it describes are written (R-06, R-12)

Cross-refs: ADR-0043 §D5 and its rejected alternative (read the «before» from the index — rejected
because the index is a cache and Race 1 is an entire section about it being stale); ADR-0041 §D7
(`NoteStore.text(_:)`, `Sources/Vault/NoteStore+ReadSurface.swift:13`, added for exactly this class
of caller); ADR-0007 §D6 (the dry run must never reach the actor).
Budget: `Sources/Vault/VaultDisk.swift`, `Sources/Vault/VaultSession.swift`,
`Tests/VaultWriteOrderingTests.swift`, `Tests/VaultSessionJournalTests.swift` (~300 lines)

**Tester declares:**

```swift
extension VaultDisk {
    /// What only the main actor knows about a journal entry. Everything the entry says about
    /// the file — hashBefore, textBefore — is filled in inside the actor (§D5).
    struct JournalDescriptor: Sendable {
        let entryID: String
        let timestamp: Date
        let command: String
        let operation: String?
    }

    func write(
        _ text: String, to relativePath: String,
        precomputedHash: String,
        journalDescriptor: JournalDescriptor?,
        journal: WriteJournal?,
        recordsHistory: Bool
    ) async throws -> DiskWriteOutcome
}
```

**Coder implements:**

1. `VaultSession.write` stops calling `read(relativePath)` at the top (`VaultSession.swift:494`).
   It builds a `JournalDescriptor` when — and only when — a journal is armed and this is not a dry
   run, and hands it across. The condition travels with the descriptor rather than being
   re-derived inside the actor, so the actor never reads a file nobody is going to journal.
2. `VaultDisk.write` reads the current bytes itself with `store.text(relativePath)` (not
   `store.read`), hashes them with `NoteStore.hash`, and fills `hashBefore`/`textBefore`
   **immediately before writing the new ones**, inside the same isolation. A path that does not
   exist yet yields `nil` for both, which is what a creation means.
3. `isDryRun` still short-circuits **before** the hop — ADR-0007 §D6's first guardrail is untouched
   and the existing `aDryRunWriteNeverReachesDiskHistoryOrJournal` test must stay green unchanged.
4. Net effect on the main actor is a *reduction*: a full `NoteStore.read` disappears and is
   replaced by a `NoteStore.text` + one hash inside the actor. Do not add anything back.

**Tester writes (R-12), red before step 1:**

`twoOverlappingWritesRecordDifferentJournalBefores()` — deterministic, no real timing. Arm the
journal, then drive the two writes so their prefixes interleave around the hop without relying on
scheduling: the reliable form is to call `disk.write(...)` **directly** for write A, `await` it,
then call it directly for write B, and assert that B's recorded `hashBefore` equals A's
`hashAfter` — under today's code B's descriptor would have carried the pre-A hash because the read
happened on the main actor before A landed. To prove the interleaving rather than mere sequencing,
build both `JournalDescriptor`s up front (that is the whole of what the main actor contributes),
*then* perform the two actor calls; the descriptors provably predate both writes, so a passing
assertion can only come from the actor having read the file itself. Assert: two entries, two
different `hashBefore` values, `entryB.hashBefore == entryA.hashAfter`, and `entryA.textBefore !=
entryB.textBefore`.

**Done when:** R-12 green; `VaultSessionJournalTests` green; `journal undo` on the second of two
overlapping writes restores the first one's text, not the original.

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

## Task 10 — The acceptance harness, the verification sweep, and this chain's own record (R-16, R-17, R-18, R-19, R-20)

Cross-refs: ADR-0043 §D9 («the acceptance criterion is a test that forces the interleaving, never a
green suite»); ADR-0043 §D10 (what this must **not** have changed); CLAUDE.md's pre-merge rules.
Budget: `scripts/adr-0043-interleaving-check.sh`, `docs/adr/0043-vault-write-ordering-concurrency-races.md`,
`TODO.md`, `PROJECT_BRIEF.md` (~200 lines)

1. **Create `scripts/adr-0043-interleaving-check.sh`** — **bash 3.2-clean** (macOS ships 3.2: no
   `mapfile`, no associative arrays, no `${var^^}`; collect with
   `arr=(); while IFS= read -r x; do arr+=("$x"); done < <(cmd)`). Its header comment names
   `docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md` and `ADR-0043`, so the
   anchor resolves to this feature. It asserts, exiting non-zero with a named failure on each:
   - the five `@Test` function names of `R-11`–`R-15` exist in `Tests/`;
   - `grep -c "index\.update" Sources/` is exactly `1`, and that line is inside
     `VaultSession+WriteOrdering.swift`'s `apply` (R-02);
   - `grep -rn "writeSynchronously\|updateIndex" Sources/ Tests/` returns nothing (R-02, R-03);
   - `grep -rn "reloadFocusedNote" Sources/Features/Pratiche/` returns nothing (R-08);
   - the five tests are reported as **passed** in the most recent result bundle, read with
     `xcrun xcresulttool get test-results tests --path <bundle>` — a test that exists but did not
     run is not acceptance. If a bundle path is not supplied the script says so and exits non-zero
     rather than silently skipping the check.
2. **Full unit suite** via `.claude/test-cmd`, unmodified (R-17).
3. **Both connector targets build:**
   `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg -destination 'platform=macOS' build`
   and the same for `pergamenum-mcp`. A file added under `Sources/Core` that imports SwiftUI breaks
   both, which is ADR-0001 §D1 enforcing itself.
4. **`python3 scripts/mcp-smoke.py <binary>` passes, with `scripts/mcp-smoke.py` unmodified** (R-16).
   The MCP tool surface does not change: `tools/list` answers the same names with the same schemas
   (§D10). If the smoke test needs an edit, something in scope was got wrong — stop and report,
   do not edit the smoke test.
5. **Manual `perg` pass**: a `--dry-run` write, a real write, a `journal log`, an `undo`. ADR-0007
   §D6's three guardrails must all still hold: `--allow-write` gating, `dryRun` defaulting to true,
   the journal recording path/hash-before/hash-after/previous-text — §D5 makes the third *more*
   accurate, not different.
6. **`scripts/uitests.sh`** before the merge to `main`, per CLAUDE.md's standing rule. Kill stale
   instances first; read the per-test seconds beside each failure before believing a red run
   (60.2 s names the launch timeout, not the app).
7. **R-18: update ADR-0043's header status line** from «proposed — **decided, not implemented**
   (see §D9)» to record implementation, with the PR number, once R-01–R-17 hold. Nothing else in
   the ADR's decisions changes. Add the release-note line Task 8 step 6 owes: ADR-0001 §D3.4's
   conflict prompt now fires when the app writes a note out from under a dirty buffer, at nine
   call sites, previously silent.
8. **File the three follow-ups this chain surfaced and deliberately did not fix**, as `TODO.md`
   entries with GitHub issues, each naming ADR-0043 and this plan: (a) `transaction`'s
   `currentOperation` is scoped state that now spans a suspension, so two concurrent transactions
   can join the wrong gesture (Task 3 step 1); (b) `readDiary` → user gesture → `writeDiary` is a
   read-modify-write window wider than §D8 can close (Task 9, declined); (c) the tag-rename and
   note-rename batch appliers have the same window at batch scope. None is a regression this chain
   introduces except (a), which ADR-0041 §D9 introduced and this chain widens the reach of.
9. **R-19: close GitHub issue #259** once this chain's PR merges, with `state_reason` set.
10. **R-20: update `TODO.md`'s `PG-150`** (line 11) to reflect completion, in the same shape
    `PG-149` uses — implementation verified in-session, suite counts, `scripts/uitests.sh` result
    with pre-existing failures named. Update `PROJECT_BRIEF.md`'s Status section if the milestone
    line moves.

**Done when:** the harness exits zero; the full unit suite is green; both connectors build;
`scripts/mcp-smoke.py` passes unmodified; `scripts/uitests.sh` shows no new failure; the ADR,
`TODO.md` and issue #259 are updated.

---

## Risks, dependencies and HITL gates

**Risks, highest first:**

1. **The mechanical cascade is three to four times what ADR-0043 measured.** 25 test files, ~210
   call sites, 46 files. Tasks 1–3 are large diffs in which almost every line is uninteresting and
   a handful are not. The mitigation is the vertical split and the rule that no assertion is
   re-sequenced without a stated reason — not speed.
2. **`closeAfterSaving()` and `replacementsApplied()` are data-loss shaped.** An `async`
   `saveOpenNote` whose `closeTab`/next-edit is not sequenced after it writes the wrong buffer or
   closes before the write lands. Called out at Task 3 step 5; it is the single most likely way
   this chain introduces a defect worse than the four it fixes.
3. **`ViewQuerySource.move`/`.undo` becoming `async` changes a SwiftUI closure type.** A
   `.dropDestination` returns `Bool` synchronously; the decided answer (fire a `Task`, return
   `true`, report failures through the problem channel) makes a drop optimistic where it was
   authoritative. It is the right trade under ADR-0043's own rejection of in-flight refusal, and it
   is a behaviour change a reviewer should see named rather than discover.
4. **`transaction`'s `currentOperation` now spans a suspension.** Two overlapping transactions can
   join the wrong journal gesture. Not decided by ADR-0043, not fixed here, filed at Task 10 step 8.
   Flagged rather than absorbed because a journal gesture that groups the wrong writes is the same
   class of defect as Race 2.
5. **§D7 changes behaviour at nine call sites at once.** A prompt that never appeared starts
   appearing, and it will read as a regression the first time it happens. Release note, not only a
   test (ADR-0043's Negative consequences say so explicitly).
6. **§D8's refusals are new failure paths at thirteen call sites.** Each must handle
   `WriteRefusal.movedOn` — a `try?` that swallows it turns a guard into a silent no-op, which is
   the failure mode ADR-0007 §D6 exists to prevent.
7. **A green suite is not acceptance here.** ADR-0043 §D9 is explicit and the review that raised it
   routed all three findings REPORT-ONLY for this reason. If R-11–R-15 are weak — if any of them
   relies on `Task.yield()`, a sleep, or real scheduling — the chain has demonstrated nothing.
8. **Three UI tests are already red on `main`** (`PG-108` and
   `testACornerGripCanStillBeGrabbedWhenZoomedOut`, per `TODO.md` `PG-149`). Do not read them as
   this chain's damage; do not let them hide a fourth.

**Dependencies:** ADR-0041 fully merged (`main`, PR #254 / `42e25ae`) — every file this chain
touches only exists in this shape because of it. No external dependency, no new package, no network.

**HITL gates — human approval required before each:**

- **Commit** of each of Tasks 1–10. Ten commits, one logical change each.
- **Push** of the branch, and **opening the PR**.
- **Merge to `main`** — and `scripts/uitests.sh` must have run first, per CLAUDE.md.
- **Closing GitHub issue #259** (Task 10 step 9).
- **Editing `docs/adr/0043-…md`'s status line** (Task 10 step 7): an ADR edit is a record change.
- **Any deletion beyond the two named functions** (`write(_:to:) throws`, `writeSynchronously`) and
  the three named lines (`updateIndex`, `VaultController+Tabs.swift:359`, the composer's
  `reloadFocusedNote()`). Nothing else in this chain deletes anything.
- **No schema change and no migration exists in this chain** — if one appears to be needed, stop:
  §D10 says `IndexCache.schemaVersion` does not move, and a migration would mean the design was
  misread.
