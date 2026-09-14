<!-- step5-brief: plan=/Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md tasks=1,2,3 lines=174-387 -->
# Step 5 Batch Brief -- 2026-09-13-vault-write-ordering-adr-0043.md -- tasks 1-3

## Task text (verbatim, plan lines 174-387)

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

## File map (from Budget: declarations, tasks 1-3)

- (none declared -- no task in this range carries a parseable Budget:)

No parseable Budget: for task(s): 1 2 3 (absent is not zero -- consult the task text above)

## Excluded tasks (not in this batch)

- Task 4 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 5 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 6 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 7 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 8 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 9 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md
- Task 10 -- see /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

Full plan: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/superpowers/plans/2026-09-13-vault-write-ordering-adr-0043.md

## Context documents (open only for the reason stated -- not read unconditionally)

- ADR: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/docs/adr/0043-vault-write-ordering-concurrency-races.md -- ADR-0043 §D2 mechanical async cascade order and hazard notes
- SPEC: /Users/stefer/emdash/worktrees/Pergamenum-b0385e05/emdash-strict-steaks-argue-n6z2c/SPEC.md -- requirement IDs for this batch's tests
