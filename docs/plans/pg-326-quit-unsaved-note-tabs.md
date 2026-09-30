# Fix: quit and vault switch ask before dropping unsaved note tabs (PG-326, #693)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to `PG-138`/`PG-141`/`PG-142` and is
not this chain's input. The brief for `PG-326` (`TODO.md` line 7, #693) is the requirement set. The
coordinator's scope change of 2026-09-29 added R-08. The plan was read at `91a0801c`
(`origin/main`, branch `kepler/693-fix/cmd-q-unsaved-note-edits`), and every line number below was
checked against that tree.

## Decisions already taken (registered, not reopened)

- **D-a** (confirmed). On quit with at least one dirty note tab in any column, one modal alert comes
  before anything else, with «Salva tutto» / «Non salvare» / «Annulla».
  - Annulla answers `.terminateCancel`.
  - Non salvare takes today's board-and-diary path, unchanged.
  - Salva tutto answers `.terminateLater` and awaits `saveAllUnsavedTabs()`. On success the board
    and diary settle as today, then the reply is `true`. On failure the reply is `false`, the app
    stays open, and a problem is recorded.
  - The 2 s cap stays on the diary phase only and never lets the app quit with a note unwritten.
  - No autosave on quit (ADR-0012 §D3).
- **D-b.** `VaultController.unsavedTabs` spans every column. `saveAllUnsavedTabs()` writes through
  `session.write(_:to:origin: tab.id)`.
  - Divergent dirty copies of one path are refused and a problem is recorded.
  - A pending external change is overwritten, as Cmd+S overwrites it today.
  - A write that reaches later tabs through `landed(_:)` is handled deterministically (ADR-0073 §D4).
- **D-c** (confirmed). The top bar's «Salvataggio…» becomes «Non salvato». The SPEC gets corrected;
  see "Facts that differ from the brief" for where.
- **D-d** (reversed by Stefano, 2026-09-29). The vault switch is in scope. It asks the same single
  question through one shared presenter and decision, and becomes R-08.

## Acceptance criteria

- **R-01** Cmd+Q with a dirty tab in any column (focused, background, other column) shows the
  prompt. With no dirty tab the quit is unchanged: immediate, or the existing diary wait. (Unit tests
  cover `unsavedTabs` and the decision. The `AppDelegate` wiring is checked by hand, M1–M4 and M9.)
- **R-02** «Annulla» cancels the quit, and every buffer is untouched. (Unit test for the decision.
  Wiring by hand, M2 and M8b.)
- **R-03** «Salva tutto» writes every dirty tab to disk before the app exits. A failed or refused
  write keeps the app open, with the problem recorded. (Unit tests for `saveAllUnsavedTabs()`.
  Wiring by hand, M5 and M7.)
- **R-04** «Non salvare» quits with the files unchanged on disk. (Unit test: the decision itself
  writes nothing. Wiring by hand, M6.)
- **R-05** Board and diary termination behave as today (ADR-0060 §D2, ADR-0066 §D5). (no-test:
  `AppDelegate` is AppKit lifecycle, `Tests/DiarySettleTests.swift` header. The existing
  `WorkspaceLifecycleTests` and `DiarySettleTests` stay green, unmodified. By hand, M8.)
- **R-06** The top-bar label no longer claims a save in progress, and the SPEC states the note save
  model that ADR-0012 §D3 decided. (no-test: a label and a documentation obligation. By hand, M10.)
- **R-07** Swift Testing unit tests, on `TemporaryVault` like `DiarySettleTests`, pin `unsavedTabs`
  (focused, background, other column) and `saveAllUnsavedTabs()`:
  - every dirty tab written, checked through a fresh `VaultSession`;
  - `false` on a write failure;
  - `false` on divergent copies of one path.

  The alert and `AppDelegate` wiring are covered by the manual checklist. No new GUI tests.
- **R-08** A vault switch («Apri cartella note…», «Cartelle recenti») with a dirty tab in any column
  shows the same prompt.
  - «Annulla» leaves the vault and every buffer as they are.
  - «Salva tutto» writes every dirty tab before the switch; a failed save aborts the switch.
  - «Non salvare» switches.
  - There is no prompt when every tab is clean, and none at launch.

## Facts that differ from the brief

Stefano should see both of these at G0.

- **`open(_:)` does not reset the columns** (ADR-0073 F7). It has no column reset
  (`VaultController.swift:196-254`), `close()` has one (`:265-269`) with no caller in `Sources/`, and
  `restoreTabs()` returns early unless the focused column is empty (`VaultController+Session.swift:35`).
  The consequences:
  - After a switch the outgoing vault's tabs stay on screen, resolved against the new session.
  - The incoming vault's tabs are never restored.
  - A Cmd+S on a carried tab writes into the new vault.

  This is a static trace, not reproduced by hand. `NoteTabGestureTests.twoVaultsRememberTheirOwnTabs`
  (`Tests/NoteTabGestureTests.swift:311`) models a switch by calling `close()` between two opens,
  which production never does. R-08's «Non salvare» needs the reset to mean anything, so Task 4 adds
  it (ADR-0073 §D6, gate G3).
- **SPEC line 235 is about the Workspace board, and it is true** (ADR-0073 F10). It sits in §6.1.
  The board autosaves after about 1 s (`WorkspaceController.swift:183`). The SPEC describes the note
  save model nowhere. Task 6 adds a §5 bullet and a scoping clause on line 235 instead of rewriting
  it (gate G4).

## ADR outcome: new ADR

**`docs/adr/0073-quit-and-vault-switch-ask-before-dropping-dirty-tabs.md`** (status: proposed).

The three-part test passes. The quit and switch protocol, and the amended catch-up rule, cost real
work to reverse. The ordering (question before the board settles, a save cap that cancels, the tab
reset inside `open(_:)`) would surprise a reader. Real alternatives exist: autosave on quit, the
`NSDocument` review loop, a SwiftUI dialog, the question inside `open(_:)`. Two overrides apply as
well:

- an explicit "no" a reader would be tempted to undo: no autosave on quit;
- a constraint invisible in the code: the diary's 2 s cap must never cover the note saves.

The record extends ADR-0012 §D3 and §D10, ADR-0060 §D2, ADR-0066 §D5 and ADR-0067 §D2, and amends
ADR-0058 §D1 narrowly (§D4). The number is `0073`: `0072` is the highest on `origin/main`, and two
unmerged branches (`refactor/pg-144-editor-coordinator`, `kepler/feature/contenitore-section-parsing`)
each hold a different `0071`. Recheck before the merge.

## Ownership rule (Swift is compiled)

- The tester's task declares every signature its tests need, with a body that compiles and keeps
  today's behaviour or returns a neutral value, so the target builds at the end of each tester task.
- Behaviour tests are red until the coder's task. Tests of an unchanged or neutral behaviour are
  green from the start, and each such test is marked below.
- The coder owns the bodies, plus any symbol no test needs (`UnsavedNotesPresenter.alert`,
  `closeAllTabsForVaultChange()`).

## Setup

- Run `tuist install` once if this is a fresh worktree.
- Run `tuist generate --no-open` after every task that adds a file (Tasks 1, 2 and 4).
- Before Task 1, merge `origin/main` into the branch if it has moved. None of the files below is
  touched by the in-flight chains read on 2026-09-29.
- **Coordinate first.** Two other local branches carry this issue's name:
  - `fix/pg-326-quit-saves-dirty-notes`, checked out in the `Pergamenum-pergamenum-bugs` worktree;
  - `fix/pg-326-quit-unsaved-notes`, checked out in `/Users/stefer/Developer/Pergamenum`.

  Neither has a commit of its own (`git log`, 2026-09-29). Their uncommitted state was not
  inspected, being outside this session's scope. Confirm nobody else is building PG-326 before
  Task 1.

## Tasks

Tasks 1 and 2 belong to the tester, Tasks 3 to 7 to the coder, and Task 8 to the orchestrator and
then Stefano.

### Task 1 — Declare the quit surface and write its red tests (tester) (R-01, R-02, R-03, R-04, R-07)

Files:

- **Create `Sources/App/UnsavedNotesPrompt.swift`** (Foundation only, no AppKit):
  - `enum UnsavedNotesChoice: Equatable, Sendable { case saveAll, discard, cancel }`.
  - `struct UnsavedNotesPrompt: Equatable, Sendable` with `let titles: [String]`,
    `init?(tabs: [NoteTab])` (stub: `nil`), `var message: String` (stub: `""`),
    `var informativeText: String` (stub: `""`), `static let listedTitleLimit = 8`.
  - `struct UnsavedNotesPresenter` with `var ask: @MainActor (UnsavedNotesPrompt) -> UnsavedNotesChoice`
    and `var reportUnsaved: @MainActor (UnsavedNotesPrompt?) -> Void`.
- **Modify `Sources/App/VaultController+Tabs.swift`**: add `var unsavedTabs: [NoteTab]` (stub: `[]`)
  in the "doors onto the tabs" extension.
- **Create `Sources/App/VaultController+UnsavedTabs.swift`**:
  - `func unsavedTabsDecision(asking ask: (UnsavedNotesPrompt) -> UnsavedNotesChoice) -> UnsavedNotesChoice?`
    (stub: `nil`);
  - `func saveAllUnsavedTabs() async -> Bool` (stub: `true`, writes nothing).
- **Create `Tests/QuitUnsavedTabsTests.swift`**, with a header naming PG-326, #693 and ADR-0073,
  and the `DiarySettleTests` note that `AppDelegate` is not unit-testable. Tests:
  - `unsavedTabsIsEmptyWhileEveryTabIsClean`: green from the start.
  - `unsavedTabsListsTheFocusedDirtyTab`,
    `unsavedTabsListsADirtyBackgroundTabOfTheFocusedColumn` and
    `unsavedTabsListsADirtyTabInTheOtherColumn` (R-01). Use `splitEditor()`, `focusColumn(_:)`,
    `focusTab(_:)` and `updateOpenNoteText(_:)`, then move the focus away before reading.
  - `theDecisionAsksNothingWhenNoTabIsDirty` (R-01): the recording closure is never called. Green
    from the start.
  - `theDecisionAsksOnceAndReturnsTheAnswer` (R-01, R-02): parameterised over the three choices.
    `ask` is called exactly once, with a prompt naming the dirty note, and the buffers are untouched
    afterwards.
  - `choosingDiscardWritesNothing` (R-04): with a dirty tab and `ask` returning `.discard`, the file's
    bytes are unchanged. Green from the start: it pins that the decision never writes.
  - `aPromptForNoTabsIsNil`: green from the start.
  - `aPromptCountsNotesNotTabs`: two tabs on one path give one title, and the message is «C'è una
    nota con modifiche non salvate».
  - `aPromptForTwoNotesUsesThePluralAndKeepsTheirOrder`: «Ci sono 2 note con modifiche non
    salvate», titles in column-then-tab order.
  - `aPromptListsAtMostEightTitlesThenHowManyMore`: ten notes give eight titles, then «e altre 2».
  - `catchUpOnADirtyBufferThatAlreadyEqualsTheIncomingTextAdoptsIt` (R-03, ADR-0073 §D4): the
    answer is `.adopted`, `savedText == text`, and `externalChangePending == nil`, with a pending
    `.text` set beforehand.
  - `saveAllWritesEveryDirtyTabInEveryColumn` (R-03, R-07): three dirty tabs (focused, background,
    other column). The call returns `true`. `VaultSession(root:stateBase:)` plus `rescan()` reads
    each file back with the buffer's text, and `unsavedTabs` is empty.
  - `saveAllWritesTwoIdenticalDirtyCopiesOnceAndLeavesBothClean` (R-03): the same path in both
    columns with the same typed text. The call returns `true`, both tabs are clean, and neither has
    `externalChangePending`.
  - `saveAllRefusesDivergentCopiesOfOnePathAndStillWritesTheOthers` (R-03, R-07). Set up two dirty
    copies of `A.md` with different text, plus a dirty `B.md`. Expected:
    - the call returns `false`;
    - `A.md`'s bytes are unchanged, and both buffers are untouched;
    - `controller.problems` has a line naming `A.md`;
    - `B.md` is written.
  - `saveAllReturnsFalseAndKeepsTheBufferWhenAWriteFails` (R-03, R-07). The note lives in `Sub/`.
    Set `Sub` to `0o555` with a `defer` back to `0o755`, the `RecordingsControllerTests.swift:210`
    technique. Expected: `false`, a problem naming the path, and the buffer still dirty with its text.
  - `saveAllWritesADirtyTabOverAPendingExternalChangeAsCmdSDoes` (R-03): the file ends with the
    buffer's text.
  - `saveAllWithNothingDirtyWritesNothingAndReturnsTrue`: green from the start.

Then run `tuist generate --no-open`, build, and run `.claude/test-cmd`. The target builds, and every
test not marked green is red for the reason named.

### Task 2 — Declare the switch door and write its red tests (tester) (R-08, R-07)

Files:

- **Modify `Sources/App/VaultController+UnsavedTabs.swift`**: add
  `func switchVault(to url: URL, presenter: UnsavedNotesPresenter) async -> Bool`. The stub is
  today's behaviour: `await open(url); return true`.
- **Create `Tests/VaultSwitchUnsavedTabsTests.swift`**, with two `TemporaryVault`s and
  `OpenTabsStore.volatile()`. The recording presenter's `reportUnsaved` counts its calls. Tests:
  - `aCleanSwitchAsksNothingAndOpensTheOtherVault` (R-08): `ask` is never called, and `root` is B's.
    Green from the start.
  - `aSwitchShowsTheIncomingVaultsOwnTabsNotTheOutgoingOnes` (R-08). Seed B's remembered
    arrangement through the same store, using a second controller that opens B and `B.md`. The first
    controller has `A.md` open in A. After the switch its tabs are exactly `["B.md"]`. Red today
    (F7).
  - `switchingBackRestoresTheOutgoingVaultsTabs` (R-08): A with `A.md`, switch to B, open `B.md`,
    switch back to A. The tabs are exactly `["A.md"]`. Red today: the carried tab and `B.md` both
    stay.
  - `cancellingTheSwitchKeepsTheVaultAndEveryBuffer` (R-08). With `ask` returning `.cancel`:
    - the call returns `false`;
    - `root` is still A's, and the buffer's text is identical;
    - the file's bytes are unchanged.
  - `saveAllWritesEveryDirtyTabBeforeTheSwitch` (R-08). With `.saveAll` and a dirty tab in each
    column, a fresh `VaultSession` on A reads both texts, `root` is B's, and the call returns `true`.
  - `aFailedSaveAbortsTheSwitchAndReportsWhatIsStillUnsaved` (R-08). With `0o555` as in Task 1:
    - the call returns `false`;
    - `root` is still A's, and the buffer is intact;
    - `reportUnsaved` is called once, with a prompt naming the note.
  - `discardSwitchesAndLeavesTheOutgoingFileUnchanged` (R-08). With `.discard`, A's bytes are
    unchanged, `root` is B's, and no tab shows A's dirty text. Red today (F7).
  - `openingAVaultOnAFreshControllerRestoresItsTabs` (R-08, "no prompt at launch"): `open(_:)` takes
    no presenter, and the remembered tabs come back. Green from the start.

Then run `tuist generate --no-open`, build, and run `.claude/test-cmd`.

### Task 3 — Bodies for the quit surface (coder) (R-01, R-02, R-03, R-04, R-07)

Files:

- **`Sources/Vault/NoteTab.swift`**: `catchUp(to:)` gains ADR-0073 §D4's branch. A dirty buffer
  receiving `.text(t)` with `t == text` adopts it: `savedText = t`, `externalChangePending = nil`,
  answer `.adopted`. Update the doc comment's `.asked` bullet to say so.
- **`Sources/App/VaultController+Tabs.swift`**: `unsavedTabs` returns every column's tabs, in order,
  filtered by `note.hasUnsavedChanges`. The file is at 358 lines; stay under SwiftLint's 400.
- **`Sources/App/UnsavedNotesPrompt.swift`**: the prompt body follows ADR-0073 §D2. It dedupes by
  path, keeps first-appearance order, and has the singular and plural messages, the eight-title cap
  and «e altre K», plus one closing sentence.
- **`Sources/App/VaultController+UnsavedTabs.swift`**:
  - `unsavedTabsDecision` returns `UnsavedNotesPrompt(tabs: unsavedTabs).map(ask)`. That is one
    call, and never a call when nothing is dirty.
  - `saveAllUnsavedTabs()` follows ADR-0073 §D3 exactly:
    - distinct paths snapshotted at the start;
    - the dirty tabs of each path re-read after every `await`;
    - divergent copies refused, with «`<path>`: aperta in più tab con testi diversi, non salvata»;
    - otherwise `session.write(text, to: path, origin: tab.id)`, with no `expecting:`;
    - a throw recorded as «`<path>`: `<error>`» and the loop continues;
    - at the end, every still-dirty tab not already reported is recorded as «`<path>`: modificata
      durante il salvataggio, non salvata»;
    - the return is `failures.isEmpty && unsavedTabs.isEmpty`.
  - Nothing after a write catches a tab up by hand. `landed(_:)` does that (ADR-0067 §D5).

Every Task 1 test is green, and the rest of `.claude/test-cmd` too.

### Task 4 — The vault switch (coder) (R-08)

Files:

- **`Sources/App/VaultController+Tabs.swift`**: add `func closeAllTabsForVaultChange()`. It sets one
  empty `EditorColumn`, `focusedColumnIndex = 0` and `endNewNote()`, and **does not call
  `rememberTabs()`** (ADR-0073 §D6). Its doc comment says why.
- **`Sources/App/VaultController.swift`**:
  - `open(_:)` calls the door after the `stateBase` guard (`:207-210`) and before the outgoing
    session loses its subscriber (`:225`).
  - `close()` replaces `:265-269` with the same call.
  - Keep the file at or under 400 lines (396 today). Put the explanation on the door, not here.
- **`Sources/App/VaultController+UnsavedTabs.swift`**: the `switchVault` body follows ADR-0073 §D6:
  - decide through `unsavedTabsDecision(asking: presenter.ask)`;
  - `.cancel` returns `false`;
  - `.saveAll` awaits `saveAllUnsavedTabs()`, and on `false` calls
    `presenter.reportUnsaved(UnsavedNotesPrompt(tabs: unsavedTabs))` and returns `false`;
  - nil and `.discard` go on to `await open(url)` and return `true`.
- **Create `Sources/App/UnsavedNotesAlert.swift`** (AppKit, `@MainActor`), which adds
  `extension UnsavedNotesPresenter { static var alert: UnsavedNotesPresenter }`:
  - `ask`: `NSApp.activate()`, then an `NSAlert` with `.warning`, `messageText = prompt.message` and
    `informativeText = prompt.informativeText`.
  - Buttons are added as «Salva tutto» (first, Return), «Annulla» (second, `keyEquivalent = "\u{1b}"`)
    and «Non salvare» (third, `keyEquivalent = "d"` with `.command`, `hasDestructiveAction = true`).
    `.alertFirstButtonReturn` maps to `.saveAll`, `.alertThirdButtonReturn` to `.discard`, anything
    else (the second button, or a modal ended by `stopModal`/`abortModal`) to `.cancel`.
  - `reportUnsaved`: an informational `NSAlert`, «Alcune note non sono state salvate», listing the
    prompt's titles, or a generic sentence when the prompt is nil. It points to Impostazioni ›
    Avanzate › Problemi and has one «OK» button.
  - The file carries no hardcoded color or font: `NSAlert` draws in system style, the same as
    `VaultOpenPanel`'s `NSOpenPanel`.
- **`Sources/App/VaultOpenPanel.swift:18`**: `Task { await controller.switchVault(to: url,
  presenter: .alert) }`, after the picker. Update the comment at `:15-17`.
- **`Sources/App/VaultCommands.swift:92`**: `Task { await vault.switchVault(to: url, presenter: .alert) }`.
- Run `tuist generate --no-open`.

Every Task 2 test is green. The six vault-switching tests listed under "Observable-contract
staleness" stay green, unmodified.

### Task 5 — The quit wiring (coder) (R-01, R-02, R-03, R-04, R-05)

File: **`Sources/App/PergamenumApp.swift`**, `AppDelegate`, following ADR-0073 §D5:

- Move today's body (`:41-52`) unchanged into one private method that returns the
  `TerminateReply`. It settles the board, then answers `.terminateNow` if the diary is settled, or
  `.terminateLater` with the two racing tasks and the 2 s cap. This is the nil and `.discard` path.
- `applicationShouldTerminate(_:)` first calls
  `vault?.unsavedTabsDecision(asking: UnsavedNotesPresenter.alert.ask)`.
  - `.cancel` answers `.terminateCancel` and settles nothing.
  - `.saveAll` answers `.terminateLater` and starts:
    - A save task. It awaits `vault.saveAllUnsavedTabs()`. On `true`, and only if its attempt still
      owes the reply, it continues with the board settle, then the diary phase: an immediate reply
      if the diary is settled, otherwise the same two racing tasks. On `false` it replies `false`,
      then calls `UnsavedNotesPresenter.alert.reportUnsaved(UnsavedNotesPrompt(tabs: vault.unsavedTabs))`.
    - A cap task. After `noteSaveCap` (`.seconds(10)`) it records «Salvataggio delle note non
      concluso entro 10 s: Pergamenum resta aperto», replies `false` and reports. It **never**
      replies `true`.
- Replace `owesTerminateReply` and `replyToTerminate()` with a per-call attempt number and
  `replyToTerminate(_ shouldTerminate: Bool, attempt: Int)`, which answers only the current attempt,
  once.
  - The diary phase's two tasks pass `true`.
  - A save task that finishes after its cap fired does nothing: no settle, no reply.
- Rewrite the method's doc comment (`:27-39`) to state the order (question, notes, board, diary),
  why the question comes before the board settle (ADR-0066 §D2), and why the note phase's cap
  cancels while the diary's lets the quit proceed.

No unit test (F13). Covered by M1–M9.

### Task 6 — The label and the SPEC (coder) (R-06)

Files:

- **`Sources/Features/Editor/VaultTopBar.swift:38-45`**: «Non salvato» with `pencil.circle` when the
  focused tab is dirty, and «Salvato» with `checkmark.circle` otherwise. Keep
  `.themedText(.caption, color: .textSecondary)` and add `.accessibilityIdentifier("note-save-indicator")`.
  `rg` found no test that matches either string (2026-09-29). `BoardChrome.swift:49`'s «Salvataggio…»
  is true for boards and stays.
- **`docs/20260811_Pergamenum_SpecApp.md`** (no-test: documentation obligation):
  - Add one bullet in §5, after the «Il carattere della nota…» bullet (ends at line 205): «**Una
    nota si salva esplicitamente** (ADR-0012 §D3, ADR-0073): Cmd+S o il pulsante della barra delle
    tab; niente autosalvataggio. Una tab con modifiche non salvate non viene mai persa senza
    chiedere: chiudere la tab, uscire dall'app o cambiare cartella note chiedono «Salva» / «Salva
    tutto», «Non salvare», «Annulla». La barra superiore mostra «Non salvato» finché la nota non è
    scritta.»
  - Line 235: after «(autosalvataggio continuo, ~1 s dopo ogni modifica; l'indicatore mostra lo
    stato di scrittura su disco)» append «— vale per la board; le note si salvano esplicitamente,
    §5». The Workspace claim stays, because it is true (F10).

### Task 7 — Update tests, call-sites and comments asserting the old behaviour (coder) (R-05, R-07, R-08)

The list is found by grep, below. Do only what it names, then run the **full** unit suite.

- `catchUp(to:)` contract (§D4). Call sites are `VaultController+TabFollowUps.swift:52,92` and
  `VaultController+Watching.swift:43`.
  - Rewrite the doc comment at `VaultController+TabFollowUps.swift:33-45`, which says "a buffer with
    unsaved changes raises the conflict prompt", to name the equal-text exception.
  - No existing test asserts `.asked` for an incoming text equal to the buffer. Every
    `externalChangePending == .text(...)` assertion (`VaultControllerWriteCatchUpTests.swift:71,118,152,228,321`,
    `VaultControllerLandedChangeTests.swift:116`, `VaultControllerReconcileTests.swift:55,109,128`,
    `VaultWriteOrderingBatch3Tests.swift:133,186`, `VaultControllerExternalDeletionTests.swift:107,116`)
    uses a distinct text. Leave them unchanged, and if one goes red, stop and report rather than
    edit it.
- `open(_:)` no longer carries tabs across a switch (§D6). These tests call `open(_:)` twice on one
  controller, found by a per-function scan of `Tests/`:
  - `IndexGenerationTests.swift:117`, `PraticheLedgerDoorTests.swift:872`,
    `RecordingsControllerTests.swift:94` and `VaultControllerCacheCleanupTests.swift:63` open no tab.
  - `NoteTabGestureTests.swift:311` calls `close()` in between, so the reset is a no-op there.
  - `VaultControllerLandedChangeTests.swift:278` opens `A.md` in each vault with the same text, and
    still passes, now testing what its name says.

  All six are expected green and unmodified. The `open(_:)` doc comment (`VaultController.swift:196`)
  gains one sentence: it closes the outgoing tabs without asking, and the UI goes through
  `switchVault`.
- Call sites of the switch: after Task 4, `rg -n "\.open\(" Sources/App` shows only `switchVault`'s
  own `await open(url)` and the launch path (`PergamenumApp.swift:307`).
- The top-bar label: no test or UI test references it (`rg "Salvataggio|\"Salvato\"" Tests UITests`
  is empty).
- `applicationShouldTerminate`: no test references it.
- `Sources/Features/Editor/EditorColumn+Closing.swift:3-8`: the header gains one line saying the
  same question guards quit and vault switch (ADR-0073).

### Task 8 — Verification and records (orchestrator, then Stefano) (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08)

1. Run `tuist generate --no-open`, then build `Pergamenum`, `perg` and `pergamenum-mcp`. The last two
   do not compile `Sources/App` and must build unchanged.
2. Run `.claude/test-cmd`, which is the **full** `PergamenumTests` suite, not only the two new files.
   A contract change (§D4, §D6) can redden an unrelated file.
3. Run SwiftLint on the touched files: no new `file_length` or `type_body_length` findings.
4. Run `git fetch origin && scripts/check-adr-references.py`.
5. Run `scripts/uitests.sh --status`, then `scripts/uitests.sh --affected` at merge time (CLAUDE.md
   merge gate). A `contaminated` verdict is rerun, not acted on.
6. Walk the manual checklist below on a Debug build. Stefano runs it (HITL).
7. Just before the merge, recheck the ADR number (`docs/adr/README.md` §1).
8. After the merge, follow "Closure" below.

## Observable-contract staleness

The contracts that change, and what the grep found (2026-09-29, at `91a0801c`):

| Contract | Changed by | Call-sites and tests found |
|---|---|---|
| `OpenNote.catchUp(to:)`: dirty and equal now adopts | Task 3 | `VaultController+TabFollowUps.swift:52,92`, `VaultController+Watching.swift:43`. Tests: `VaultControllerWriteCatchUpTests.swift:69,81,97` (unit), plus the assertion sites in Task 7, all with distinct texts |
| `VaultController.open(_:)`: closes the outgoing tabs | Task 4 | Production: `VaultOpenPanel.swift:18`, `VaultCommands.swift:92` (both moved to `switchVault`), `PergamenumApp.swift:307` (launch, empty columns). Tests: 54 files build a `VaultController` and call it, and 6 call it twice on one controller (Task 7) |
| `VaultController.close()`: same reset through the new door | Task 4 | No caller in `Sources/`. Tests call it in teardown, and the behaviour is identical |
| `VaultTopBar` label text and icon | Task 6 | None in `Tests/` or `UITests/` |
| `AppDelegate.applicationShouldTerminate(_:)` sequencing | Task 5 | None (F13) |

Run the full unit suite after the change, not only `QuitUnsavedTabsTests` and
`VaultSwitchUnsavedTabsTests`.

## Manual verification checklist (Debug build, throwaway vaults)

Setup. Quit or ignore the installed Pergamenum. If it is running, it keeps the global hot key and
the Debug instance only warns. The Debug build shares the `it.stefer.pergamenum` defaults domain, so
the throwaway vaults' tab arrangements are remembered there, which is harmless.

```bash
tuist generate --no-open
xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' build
APP=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1)
BASE=$(mktemp -d)
mkdir -p "$BASE/A/Sub" "$BASE/B" "$BASE/state" "$BASE/mail"
for f in "$BASE/A/Uno.md" "$BASE/A/Due.md" "$BASE/A/Sub/Tre.md" "$BASE/B/Bi.md"; do
  cat > "$f" <<'EOF'
---
date: 2026-09-29
tags:
  - type-note
---

Testo originale.
EOF
done
open -n "$APP" --args -recentVaults "(\"$BASE/A\", \"$BASE/B\")" -stateBase "$BASE/state" \
  -mailStoreRoot "$BASE/mail" -disableCalendar YES -disablePlaud YES -disableUpdater YES
shasum "$BASE"/A/*.md "$BASE"/A/Sub/*.md     # take before and after each "unchanged" check
```

Relaunch between checks with the same `open -n` line. Press every Cmd+Q in the Debug instance, with
it frontmost.

- **M1** (R-01). No dirty tab, Diario untouched, Cmd+Q: the app quits at once and no alert appears.
- **M2** (R-01, R-02, R-06). Type in `Uno`, then Cmd+Q. The alert reads «C'è una nota con modifiche
  non salvate» and lists «Uno». Press Esc: the app stays, the text is still there, and the top bar
  reads «Non salvato».
- **M3** (R-01). Dirty `Uno`, then open `Due` in a new tab (Cmd+Click) and leave it clean in front.
  Cmd+Q shows the alert naming «Uno».
- **M4** (R-01). Split the editor, dirty a tab in the right column, focus the left one. Cmd+Q shows
  the alert.
- **M5** (R-03). Dirty `Uno` and `Due`: the alert reads «Ci sono 2 note…» and lists both. Press
  Return («Salva tutto»). The app quits, and `cat "$BASE/A/Uno.md" "$BASE/A/Due.md"` shows both
  edits.
- **M6** (R-04). Dirty `Uno`, take `shasum`, Cmd+Q, press Cmd+D («Non salvare»). The app quits and
  `shasum` is unchanged.
- **M7** (R-03). Dirty `Tre` (in `Sub/`), run `chmod 555 "$BASE/A/Sub"`, Cmd+Q, «Salva tutto». The
  app stays open, a second alert names «Tre», and Impostazioni › Avanzate › Problemi has the line.
  Run `chmod 755 "$BASE/A/Sub"`, then Cmd+Q, «Salva tutto»: the app quits and the file has the edit.
- **M8** (R-05). With no dirty note, edit a board card's text in the Workspace and press Cmd+Q within
  1 s: the `.canvas` has the edit after relaunch. Type a sentence in Diario and press Cmd+Q at once:
  today's diary file has it.
- **M8b** (R-02, R-05). Start editing a board card's text, dirty a note, Cmd+Q, «Annulla». The card
  is still in edit mode and nothing was settled.
- **M9** (R-01). Dirty `Uno`, bring Finder to the front, then choose Pergamenum's Dock menu ▸ Esci.
  The alert appears in front.
- **M10** (R-06). Type in a note: «Non salvato» with the pencil icon. Cmd+S: «Salvato» with the
  check.
- **M11** (R-08). Dirty `Uno`, then File ▸ Cartelle recenti ▸ B: the alert appears. «Annulla»: still
  in A, and the buffer is intact.
- **M12** (R-08). Repeat M11 with «Salva tutto»: `Uno.md` has the edit, B opens, and only B's tabs
  show (none of A's).
- **M13** (R-08). Repeat M11 with «Non salvare»: `shasum` of `Uno.md` is unchanged, and B opens with
  B's tabs. Switch back to A: A's tabs return, clean, read from disk.
- **M14** (R-08). Dirty `Uno`, File ▸ Apri cartella note…, cancel the picker: no alert, nothing
  changes. Repeat and pick B: the alert appears after the picker.
- **M15** (R-08). Repeat M7's `chmod 555` with a switch to B and «Salva tutto»: the app stays in A,
  the second alert names «Tre», and the buffer is intact. Run `chmod 755` afterwards.
- **M16** (R-08). Relaunch with tabs remembered: no alert at launch.
- **M17** (R-08). With every tab clean, switch A to B: no alert, B's tabs show, A's are gone.
- **M18b** (R-01, ADR-0073 §D5 step 7). With a dirty tab, close the main window with its close
  button: the alert appears; «Annulla» brings the main window back with the tab still dirty, and
  the alert does not reappear.
- **M18** (observation, no R). With a dirty tab, close the main window with its close button and
  record what happens: the app stays with the buffer, or it quits through the alert. File an issue
  only if the buffer is lost without a question.

## Risks and HITL gates

- **G0: plan approval.** D-a and D-c are confirmed and D-d is reversed. Take G1 to G5 together, from
  ADR-0073 §"Open for Stefano":
  - **G1**: the failure alert.
  - **G2**: the 10 s note save cap, which cancels.
  - **G3**: `open(_:)` closes the outgoing tabs (F7).
  - **G4**: the SPEC correction's shape.
  - **G5**: §D4 amends ADR-0058 §D1.

  If G1 is declined, drop `reportUnsaved` and its two call sites and nothing else changes. If G2 is
  declined, drop the cap task, and a hung disk can then hang «Esci».
- **Parallel work on the same issue.** See Setup. Two branches named for PG-326 exist, and both are
  checked out.
- **ADR number.** `0071` is claimed twice in flight, and one of those records may move to `0073`.
  Recheck just before the merge and renumber with `git mv` and a dated note if needed.
- **The `.terminateLater` window.** `saveAllUnsavedTabs()` runs on the main actor while AppKit waits
  for the reply. ADR-0060 §D2's diary settle already depends on that being serviced. M5 and M7
  confirm it for notes.
- **Reentrancy during `runModal()`.** Main-actor work such as a watcher reconcile or a landed change
  can run while the alert is up. The decision reads `unsavedTabs` before asking, and
  `saveAllUnsavedTabs()` reads them again after every `await` (§D3), so a change in between is acted
  on and never overwritten blind.
- **Test hosts.** `.claude/test-cmd` hosts the unit suite in the real app. Its own `VaultController`
  never has a dirty tab, because tests build their own, so the alert cannot appear there. How xctest
  ends the host was not verified: if `.claude/test-cmd` starts hanging at teardown after this change,
  look here first. For the GUI suite, no UI test types into a note editor today (ADR-0073 §D8). A new
  one that leaves a tab dirty would meet the alert at `terminate()`.
- **SwiftLint budget.** `VaultController.swift` is at 396 lines and `VaultController+Tabs.swift` at 358.
- **External behaviours.** Sparkle's install-on-quit meets the question, and «Annulla» leaves it
  waiting with its retry (F12). A logout waits for the answer.
- **HITL:**
  - commit, push and PR (branch `kepler/693-fix/cmd-q-unsaved-note-edits`, Conventional Commits);
  - merge;
  - the ADR status flip after the merge;
  - filing the follow-up issue;
  - the `CLAUDE.md` chain-index line (not in this plan).

  No schema change, no deletion, no deploy.

## Closure

- The PR body carries `Closes #693`. `project-tasks` closes `PG-326` in `TODO.md` after the merge,
  not in the PR.
- The first docs change after the merge flips ADR-0073 to `accepted`, with the PR, the first-parent
  merge hash and the date (`docs/adr/README.md` §2).
- File one follow-up issue at merge: `closedTabPaths` and `recentNotePaths` survive a vault switch,
  so Cmd+Shift+T and RECENTI can offer the previous vault's paths (ADR-0073 §D8, F8). The
  vault-switch data loss the brief named as D-d is not a follow-up any more: R-08 closes it.

## Test command

`TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

`TEST-CMD MODE: brownfield`. This is the command already pinned in `.claude/test-cmd`, unchanged: it
must stay restricted to `PergamenumTests` (CLAUDE.md). The GUI suite runs only through
`scripts/uitests.sh`.
