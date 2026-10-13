**Requirement set:** `docs/archive/specs/pg-392-board-controller-vault-lifetime.SPEC.md` (root `SPEC.md` while this was built)

# Plan — PG-392: a conflicted Workspace board outlives the pane and the window (#918)

`SPEC.md` at this worktree's root is the PG-392 SPEC (Approved 2026-10-07, R-01 to R-10).
Everything below was read on `29bb3aa0` on 2026-10-07. That commit is both `origin/main` and the
tip of `feature/pg-392-board-controller-vault-lifetime`.

**ADR outcome: one new ADR, `docs/adr/0091-the-board-controller-lives-with-the-vault.md`
(proposed), written with this plan.** It qualifies on all three counts:

- **Hard to reverse.** The owner of a stateful controller moves from a view to the app's facade.
  The quit, the vault switch, the window history and the folder verbs all come to depend on it.
- **Surprising without context.** A reader finds a Workspace object on `VaultController`, a
  presenter count on the board, and a pane leave that keeps some boards and drops others.
- **A real trade-off.** An app-level holder, a `RootView` `@State`, a lazy optional, keeping every
  board and refusing the pane switch were all on the table.

The override applies too. The record amends ADR-0089 §D7/§D8 and ADR-0066's attach/detach
ownership, and SPEC R-10 asks for it.

- **Number.** 0091 was checked free on every local and remote-tracking ref on 2026-10-07. The
  highest on `main` is 0090. Check again immediately before the merge (`docs/adr/README.md` rule 1).
- **What it amends.** ADR-0089 §D7, §D8 and its implementation note on "a covered board left by an
  uncovered reveal"; ADR-0066 §D2, §D5 and its Consequences bullet on the weak reference.
- **What it extends.** ADR-0054 §D5, ADR-0060 §D3, ADR-0073 §D7, ADR-0089 §D1 to §D6. It reverses
  none of them.

## Baseline

- **Staged before this plan.** `git status` shows the PG-219 chain's archive step already staged:
  - `SPEC.md` renamed to `docs/archive/specs/pg-219-pointer-feedback.SPEC.md`;
  - `docs/plans/pg-219-pointer-feedback.md` with its first line repointed to that archive.

  The new `SPEC.md`, this plan and ADR-0091 are untracked. Committing the archive step, here or
  separately, is gate G0.
- **No GUI test.** The SPEC rules it out. ADR-0089 added none, and the GUI suite is a bounded
  backstop (`CLAUDE.md`, merge gate).

## Registered from the SPEC, not reopened

- **One owner.** The controller is created once, with `VaultController`, and owned strongly.
  `openBoard` becomes that reference. A separate app-level holder was rejected.
- **Attach and detach follow the vault,** whether or not the pane is mounted.
- **A pane leave settles by state.**
  - Saved: released, so the pane re-enters on its empty state.
  - Pending: flushed, then judged by the outcome.
  - Conflicted: kept, with its document, its origin and its banner.

  Keeping every board, and refusing the switch, were both rejected.
- **The vault switch is asked and names the conflicted board.**
  - «Salva» never writes the board, cancels and reveals.
  - «Annulla» cancels.
  - Only «Non salvare» proceeds.

  The person chose this at the interview, against the recommendation to leave the board out. It is
  not reopened here.
- **The open-board path is derived,** and the window history keeps reading it.
- **Constraints.**
  - ADR-0054 §D5, ADR-0089, ADR-0066 and ADR-0052's cross-vault lesson hold.
  - A check made before an `await` is a filter, not a guard.
  - The diary and «Chiudi la colonna» are unchanged.
  - No on-disk format, schema, frontmatter key or protected interface changes.
  - `perg` and `pergamenum-mcp` build and behave unchanged.

## What reading the code established

- **`CanvasStore.save` is synchronous** (`WorkspaceController+Saving.swift:29-33`). The leave's
  flush has no suspension point, so the SPEC's "re-entry during the flush" is, in practice, SwiftUI
  delivering the new `onAppear` before the old `onDisappear`. The presenter count models exactly
  that, and the decision is read after the flush (ADR-0091 §D3).
- **`attach` resets the board.** It must never run on a pane appearance again, or it would wipe
  the board the leave kept. `attachWorkspace()` runs on every `.onAppear` today
  (`WorkspaceView.swift:97-100`), and it is deleted.
- **`select(nil)` is already the release.** Every board shown goes through `open(board:)`, which
  sets `current = .board(path)` (`WorkspaceController.swift:267-270`). So `select(nil)` after a
  saved flush reaches its folder/nil branch, and its conflict guard cannot fire.
- **The switch's words need a mid-sentence clause.** `QuitReview.Words.staying` for
  `.vaultSwitch` is «La cartella note resta aperta» (`QuitReview.swift:313-318`). The board
  sentence interpolates it mid-sentence (`QuitReview+Conflicts.swift:24-27`). Used as is, it
  would read «con «Salva» La cartella note resta aperta». ADR-0091 §D5 adds a mid-sentence form
  and keeps the quit's bytes.
- **`refusal(forAll:)` always answers the note's sentence** for a refused folder
  (`VaultController+Move.swift:173`). That matters only once D8 (gate G1) adds a second reason.
- **The test helpers build their own board.** `QuitTestSupport.quitConflictedBoard` attaches its
  own `WorkspaceController` and relies on `attach` registering it as `openBoard`
  (`Tests/QuitTestSupport.swift:76-100`). After D1 nothing registers, so the helper must use
  `controller.openBoard`, which `open(_:)` has already attached.
- **`problems` belongs to the session.** A line `close()` records after `session = nil` is lost.
  Tests that read a detach's line call `controller.openBoard.detach()`, or `open(b)`, never
  `close()`.
- **Unverified: whether `HostedView` delivers `onDisappear`.** `onAppear` fires in the harness:
  `QuitBoardLifetimeHostedTests` waits on the attach it triggers. No hosted test in the repository
  depends on `onDisappear`. Task 2 measures this before relying on it.

## Gates

- **G0 (HITL).** Commit the staged PG-219 archive step: in this branch's first commit, or in its
  own `docs:` commit first. Run `tuist install` once per fresh worktree, and
  `tuist generate --no-open` after Tasks 1, 3 and 6 add files. Re-check ADR number 0091 before the
  merge. Land the plan and the ADR with the build, not in a docs-only PR first (PG-340).
- **G1 (HITL): include ADR-0091 §D8?** It adds the folder-verb guard against stranding a kept
  conflicted board. **Recommended: include** (Tasks 6 and 7). Declined: Tasks 6 and 7 do not run,
  §D8 is struck, and the residual is named in ADR-0091 and filed as a ledger entry.
- **G2 (HITL): the frozen Italian strings.**
  - Switch, message for a board alone: `Salvare le modifiche alla board «B» prima di aprire
    un'altra cartella note?` (`QuitReview.copy`'s existing composition, no new code).
  - Switch, board sentence: `La board «B» è cambiata anche su disco: con «Salva» la cartella note
    resta aperta per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno
    perse.` The same shape with «Salva tutto» for more than one item.
  - Switch, cancel line: `Apertura di un'altra cartella note annullata: la board «B» ha un
    conflitto di salvataggio non risolto`.
  - Column close, cancel line, for completeness and never reached (the column close passes no
    board): `Chiusura della colonna annullata: la board «B» ha un conflitto di salvataggio non
    risolto`.
  - Folder refusal (G1 only): `risolvi le modifiche non salvate della board «B» nel Workspace prima
    di rinominare o eliminare la cartella`.
  - Every quit string stays byte-identical, pinned in Task 3.
- **G3 (HITL): one dated sentence in the app SPEC?** Add it to `docs/20260811_Pergamenum_SpecApp.md`
  §5, beside ADR-0089's: a conflicted board survives a pane switch, and the vault switch names it.
  **Recommended: yes.** It is documentation only (Task 8).
- **G4 (HITL, explain before acting): five existing tests are changed on purpose, none disabled.**
  - `QuitBoardLifetimeHostedTests` is ADR-0089's premise pin. Its own header says that if it goes
    red, the ADR needs another look. ADR-0091 is that look. The test is rewritten in place to pin
    the inverse premise.
  - `QuitConflictScopeTests`' first test asserted that the switch never names a board. R-06
    reverses that.
  - `QuitConflictScopeTests`' third test detached the board so the switch would ask nothing. Its
    switch half becomes "a conflicted diary alone asks nothing".
  - `QuitConflictLastCheckTests.aCoveredBoardLeftByAnUncoveredRevealRecordsItsLine` asserted a
    compensating line for a loss that no longer happens (ADR-0091 §D7).

  Each change is stated in Task 2 with its reason.
- **Commit, push, PR (HITL).** As always.

## Tasks

The order is binding. Tasks 1 to 3 are testers that leave the target building and their tests red.
Tasks 4 and 5 make them green. Tasks 6 and 7 run only if G1 is approved. Task 8 closes.

### Task 1 — Tester: the controller's owner, its rebind and its leave (R-01, R-02, R-03, R-04, R-07, R-08)
Owner: tester
Files: Sources/App/VaultController.swift, Sources/App/VaultController+Board.swift, Sources/App/QuitCoordinator.swift, Sources/Features/Workspace/WorkspaceController.swift, Sources/Features/Workspace/WorkspaceController+Lifecycle.swift, Sources/Features/Workspace/WorkspaceView.swift, Tests/BoardControllerLifetimeTests.swift, Tests/WindowPlaceTests.swift
Tests: BoardControllerLifetimeTests.swift, WindowPlaceTests.swift
Signatures:
- VaultController.openBoard — `let openBoard: WorkspaceController` (stored in `VaultController.swift`, replacing `@ObservationIgnored weak var openBoard: WorkspaceController?`, assigned `WorkspaceController()` in `init`)
- VaultController.openBoardPath — `var openBoardPath: String? { get }` (computed, new file `Sources/App/VaultController+Board.swift`; the stored `var openBoardPath: String?` at `VaultController.swift:81` is deleted; neutral body `nil`)
- VaultController.rebindBoard — `func rebindBoard(to url: URL)` (same new file; neutral body empty)
- WorkspaceController.panePresenters — `var panePresenters = 0` (stored in `WorkspaceController.swift`, internal, with a comment naming `WorkspaceController+Lifecycle.swift` as its writer)
- WorkspaceController.enterPane — `func enterPane()` (`WorkspaceController+Lifecycle.swift`; neutral body empty)
- WorkspaceController.leavePane — `func leavePane()` (same file; neutral body empty)
- WorkspaceController.attach — `func attach(to store: CanvasStore, thumbnails: ThumbnailStore? = nil, vault: VaultController? = nil)` (relied on, signature unchanged; the registration at `:152-154` is deleted)
- WorkspaceController.detach — `func detach()` (relied on, signature unchanged; the line at `:193` is deleted)
- WorkspaceController.quitConflict — `var quitConflict: QuitReview.Board? { get }` (relied on, unchanged)
- VaultController.open — `func open(_ url: URL) async` (relied on, unchanged)
- VaultController.close — `func close()` (relied on, unchanged)
- WindowPlace.destination — `var destination: Destination { get }` (relied on, unchanged)
Red: yes

**The declarations, and only what they force to compile.** All bodies are neutral, and nothing
uses `fatalError`.

- `openBoard` becomes a non-optional `let`, which forces four compile-only edits:
  - the four `vault?.openBoard?.` sites in `QuitCoordinator.swift` (`:146`, `:157`, `:353`, `:380`)
    become `vault?.openBoard.`;
  - `attach`'s registration (`WorkspaceController.swift:152-154`) is deleted;
  - `detach`'s `if vault?.openBoard === self { … }` (`:193`) is deleted;
  - `openBoardPath` loses its setter, so the view's mirror (`WorkspaceView.swift:119-127`, the
    `.onChange(of: workspace.board)` that writes it) is deleted.
- Nothing else in `WorkspaceView` changes here. Its `@State` controller stays until Task 4, so the
  app is knowingly inconsistent between Tasks 1 and 4.
- Run `tuist generate --no-open` after adding the two new files.

**`Tests/BoardControllerLifetimeTests.swift`, new.** Every test opens a real `VaultController` on
a `TemporaryVault` (`VaultController(recents: .volatile(), openTabs: .volatile())`) and works on
`controller.openBoard`. These are not hosted tests, so `addStickyNote` is allowed. Each test ends
with `controller.close()`.

1. `theBoardControllerIsCreatedWithTheVaultControllerAndNeverReplaced` (R-01). Take
   `let first = controller.openBoard` before `open`. Then open A, enter, leave, enter, open B and
   close. `controller.openBoard === first` holds throughout.
2. `openingAVaultBindsTheBoardToItsStoreWithNoBoardOpen` (R-07).
   - After `open(a)`: `openBoard.store?.root.vaultKey == a.root.vaultKey`, `board == ""`,
     `saveState == .saved` and `openBoardPath == nil`.
   - `enterPane()` is never called, so the pane was never mounted.
3. `aSavedBoardIsReleasedOnLeave` (R-03).
   - Create a board, `open(board:)`, `enterPane()`, then `leavePane()`.
   - Afterwards `board == ""`, `current == nil` and `!isShowingBoard`.
   - `openBoard.store` is still attached, and no problem line was added.
4. `aPendingBoardIsFlushedOnLeaveAndThenReleased` (R-03). Open a board, add a card (`.pending`),
   enter, then leave. The file on disk now holds the card, and the board is released.
5. `aPendingBoardWhoseFlushIsRefusedOnLeaveIsKeptConflicted` (R-03, edge case 2).
   - Open a board, add a card, and save a diverged document through a second `CanvasStore`.
   - Enter, then leave. `saveState` is `.conflicted`, `board` still names the path and
     `document` still holds the card.
6. `aConflictedBoardKeepsItsDocumentOriginAndStateAcrossALeave` (R-02).
   - Make `openBoard` conflicted (the Task 2 helper, or the same steps inline). Capture
     `document`, `origin` and `saveState`.
   - Run enter, leave, enter. All three are equal afterwards, `quitConflict != nil`, and the leave
     records no problem line.
7. `aReentryBeforeTheLeaveDoesNotReleaseTheBoard` (R-04).
   - Open a pending board and call `enterPane()` twice, the second being the new appearance.
   - Then `leavePane()`: the card is on disk, but `board` still names the path.
   - A second `leavePane()` releases it.
8. `aLeaveWithNoAppearanceLeftNeverCountsBelowZero`. Run `leavePane()` with no enter. Then
   `enterPane()` and `leavePane()` on an open saved board: it is released, so the count was
   clamped at zero.
9. `openingAnotherVaultRebindsWithNoBoardAndNothingFromTheOld` (R-07, ADR-0052).
   - Open A, open a board in A and add a card, leaving it pending with the pane never entered.
   - Then `await controller.open(b.root)`, the mechanism, not `switchVault`, so D2 is isolated.
   - Afterwards:
     - `openBoard.store?.root.vaultKey == b.root.vaultKey`;
     - `board == ""`, the document is empty, `saveState == .saved` and `!canUndo`;
     - A's file holds the card;
     - nothing named after A's board exists in B.
10. `reopeningTheOpenVaultLeavesTheBoardUntouched`. Make `openBoard` conflicted in A, then
    `await controller.open(a.root)`. It is still conflicted, on the same `board`, with the same
    `store` instance.
11. `closeDetachesTheBoard`. Open a board, then `close()`. `store == nil` and `board == ""`.
12. `aSecondDetachRecordsNothing`.
    - Make `openBoard` conflicted, then `openBoard.detach()`. One line is added, and `saveState`
      is `.saved`.
    - A second `openBoard.detach()` adds no line.
13. `detachRecordsTheLossWhenItsOwnFlushIsRefused` (ADR-0091 §D2).
    - Open a board, add a card, and save a diverged document externally.
    - `openBoard.detach()` adds the refusal's line and the «…aveva un conflitto di salvataggio non
      risolto…» line.
14. `aPendingBoardWhoseWriteFailsIsKeptOnLeave` (R-03, "release iff saved").
    - Put the board in `Progetti/`, open it and add a card.
    - Inside `withReadOnlyFolder(root, "Progetti")`, run enter and leave. `saveState` is still
      `.pending` and `board` still names the path.
    - If the store's write does not fail on a read-only folder, record that in this plan and drop
      the test. Do not fake the failure.

**`Tests/WindowPlaceTests.swift`, added to (R-08).**

- `destinationOnTheWorkspacePaneNamesTheBoardTheControllerShows`. Use
  `navigation.pane = .workspace` and `openBoard.open(board: X)`. `destination ==
  .workspaceBoard(X)`.
- `destinationIsThePaneOnceALeaveReleasedTheBoard`. Open X, enter, then leave. `destination ==
  .pane(.workspace)`. This is the stale-mirror defect of ADR-0091 §Context.
- `aHistoryStepToABoardOpensItThroughThePendingRoute`.
  - `place.apply(.workspaceBoard(X))`, then what the view's `openPendingCanvas()` does:
    `consumePendingCanvasRoute()` and `openBoard.openRoute((X, nil), viewport: .zero)`.
  - `openBoardPath == X` and `destination == .workspaceBoard(X)`.
- The existing `applyAWorkspaceBoardSwitchesToWorkspaceAndQueuesIt` stays as it is.

### Task 2 — Tester: update tests and call-sites asserting the old behaviour (R-01, R-02, R-06, R-08, R-09)
Owner: tester
Files: Tests/QuitTestSupport.swift, Tests/QuitConflictTests.swift, Tests/QuitConflictScopeTests.swift, Tests/QuitConflictLastCheckTests.swift, Tests/QuitBoardLifetimeHostedTests.swift, Tests/WorkspaceFitOnOpenHostedTests.swift
Tests: QuitConflictTests.swift, QuitConflictScopeTests.swift, QuitConflictLastCheckTests.swift, QuitConflictCapTests.swift, QuitConflictDerivationTests.swift, QuitBoardLifetimeHostedTests.swift, WorkspaceFitOnOpenHostedTests.swift
Signatures:
- quitConflictedBoard — `func quitConflictedBoard(_ vault: borrowing TemporaryVault, in controller: VaultController) throws -> (board: WorkspaceController, path: String)` (signature unchanged; body uses `controller.openBoard` instead of a new `WorkspaceController()`, `attach` dropped)
- VaultController.openBoard — `let openBoard: WorkspaceController` (relied on, Task 1)
- WorkspaceController.enterPane — `func enterPane()` (relied on, Task 1)
- WorkspaceController.leavePane — `func leavePane()` (relied on, Task 1)
Red: yes

**The grep, run on `29bb3aa0`.** Every site that asserts or depends on the old contract:

- **`openBoard` as a weak optional the board registers itself into:**
  - `Sources/App/QuitCoordinator.swift:146, 157, 353, 380` (compile glue, Task 1);
  - `Sources/Features/Workspace/WorkspaceController.swift:154, 193` (Task 1);
  - `Tests/QuitBoardLifetimeHostedTests.swift:8, 13, 56, 60, 62`;
  - `Tests/QuitConflictScopeTests.swift:20, 61`;
  - `Tests/QuitTestSupport.swift:72, 75, 82-83`;
  - `Tests/WorkspaceFitOnOpenHostedTests.swift:11, 75`;
  - `Tests/QuitConflictTests.swift:85-86`.
- **`openBoardPath` as a stored mirror:**
  - written at `Sources/Features/Workspace/WorkspaceView.swift:126` (deleted, Task 1);
  - read at `Sources/App/WindowPlace.swift:37` (unchanged);
  - described at `Sources/App/NavigationHistory.swift:23` and `WindowPlace.swift:32-36` (Task 4).
  - No test writes it.
- **The switch never naming a board:** `Tests/QuitConflictScopeTests.swift:31, 37-40, 111-118`.
- **The compensating quit line:** `Tests/QuitConflictLastCheckTests.swift:40-63`, and the
  `leftProblem` read at `Sources/App/QuitCoordinator.swift:381` (Task 5).
- **`attach(to:…vault:)` from a test-owned controller.** These are unaffected: they read their own
  controller, never `openBoard`, and `close()`'s detach of `openBoard` is idempotent.
  - `CanvasRoundTripTests:155`;
  - `QuitConflictDerivationTests:18, 37`;
  - `WorkspaceAutosaveRaceTests:21, 433`;
  - `WorkspaceDocumentCreationTests:53`;
  - `WorkspaceEnterFolderTests:237`;
  - `WorkspaceLifecycleTests:495, 538, 622`;
  - `WorkspaceOpenStateFixture:77`;
  - `WorkspaceOpenStateTests:120`.

  Rerun them in Task 8, not edit them.

**The edits.**

1. **`QuitTestSupport.quitConflictedBoard`.**
   - Drop `let board = WorkspaceController()` and its `attach`. Use
     `let board = controller.openBoard`, already attached by `quitController`'s `open`.
   - Keep `store.createBoard`, `board.open(board:)`, the sticky note, the external diverged save
     and the flush.
   - Rewrite the header (`:71-75`): `openBoard` is owned by the vault controller, not weak.
2. **`QuitConflictTests.anUnsavedButNotConflictedBoardIsWrittenBySettleWithoutAQuestion`
   (`:79-104`).** Use `controller.openBoard` instead of its own controller and attach. The
   assertions are unchanged.
3. **`QuitConflictScopeTests`.**
   - Test 1 becomes `theVaultSwitchQuestionNamesTheNotesAndTheBoardNeverTheDiary` (R-06, R-09):
     - `review.board == board.quitConflict`, and `review.diary == nil`;
     - the text contains «Bacheca» and not «diario»;
     - `copy != QuitReview(columns: controller.columns).copy(for: .vaultSwitch)`;
     - both conflicts are still waiting.
     - The `controller.openBoard === board` lines stay; they are now true by construction.
   - Test 2 (column close) is unchanged. The column close passes no board (R-09).
   - Test 3 is split in two:
     - `aConflictedBoardAndDiaryAloneAskNothingAtAColumnClose`: today's first half, unchanged.
     - `aConflictedDiaryAloneAsksNothingAtAVaultSwitch` (R-09): a vault with a conflicted diary
       only and no board. The switch asks nothing and returns true.
4. **`QuitConflictLastCheckTests`.** Rename `aCoveredBoardLeftByAnUncoveredRevealRecordsItsLine`
   to `aCoveredBoardLeftByAnUncoveredRevealStaysConflictedAndRecordsNothing`.
   - `!controller.problems.contains { $0.contains(boardProblem) }`.
   - `controller.openBoard.quitConflict != nil`.
   - The bytes are unchanged and the reveal is not `.board`.
5. **`QuitBoardLifetimeHostedTests`, rewritten in place (G4).** The header states that ADR-0091
   inverts the premise this file pinned. The hosted harness allows file cards only, using
   `placeFile` as `WorkspaceFitOnOpenHostedTests` does. Text cards need `CommandActions`, and
   through it `EventKitStore`.
   - **Step 0, the measurement.** Show the pane, open a saved board on `controller.openBoard`,
     then hide the pane (`flag.shown = false`, `host.settle()`). Whether `board == ""` follows
     tells whether `HostedView` delivers `onDisappear`. Record the answer in this plan under
     "Build notes".
     - If it does not, tests (c) and (d) below assert only what holds without it.
     - The release itself stays pinned by Task 1's direct `leavePane()` tests.
   - **(a) `theBoardControllerIsTheSameObjectAcrossALeaveAndAReentry` (R-01).**
     `controller.openBoard` is identical before the hide and after the show, and the view drew
     from it.
   - **(b) `aConflictedBoardSurvivesALeaveAndComesBackConflicted` (R-02).**
     - A file card, then an external diverged save, then a flush makes the board conflicted.
     - Hide, then show. `saveState` is still `.conflicted`, and `document` and `origin` are
       unchanged.
     - No accessibility lookup: the banner is `BoardTopBar` reading `saveState`, which this
       pins.
   - **(c) `aCleanBoardIsReleasedToTheEmptyStateOnLeave` (R-03).** After the hide, `board == ""`.
     After the show, `!isShowingBoard`. This depends on step 0.
   - **(d) `aCanvasRouteParkedOnAColdPaneOpensWhenThePaneMounts` (R-08, edge case 5).** With the
     pane hidden, set the route as `pergamenum://canvas` does: `routeState.pendingCanvas` through
     the route handler, or `WindowPlace.apply(.workspaceBoard(X))`. Show the pane. Then
     `controller.openBoardPath == X`.
   - Every test keeps `#expect(host.neverShown)` and `#expect(host.refusals.isEmpty)`.
6. **`WorkspaceFitOnOpenHostedTests`.** Rewrite the header at `:9-13`, and change `:75` to
   `let workspace = controller.openBoard`.

Most of these are red until Task 4. Until then `open(_:)` binds nothing and the view still shows
its own controller. 3 and 4 stay red until Task 5.

### Task 3 — Tester: the vault switch names the board, and the quit reaches it off screen (R-05, R-06, R-09)
Owner: tester
Files: Sources/App/VaultController.swift, Sources/App/QuitReview+Conflicts.swift, Tests/VaultSwitchBoardTests.swift, Tests/QuitConflictOffScreenTests.swift
Tests: VaultSwitchBoardTests.swift, QuitConflictOffScreenTests.swift, QuitReviewConflictTests.swift, VaultSwitchTests.swift
Signatures:
- VaultController.revealOpenBoard — `@ObservationIgnored var revealOpenBoard: (() -> Void)?` (stored in `VaultController.swift`, beside `reopenMainWindow`)
- QuitReview.Board.leftProblem(for:) — `func leftProblem(for occasion: QuitReview.Occasion) -> String` (`QuitReview+Conflicts.swift`; neutral body `""`)
- QuitReview.Board.leftProblem — `var leftProblem: String { get }` (relied on; stays the quit's line, byte-identical)
- VaultController.switchVault — `func switchVault(to url: URL, ask: @MainActor (QuitReview) -> QuitReview.Answer = QuitReviewAlert.askBeforeVaultSwitch) async -> Bool` (relied on, signature unchanged)
- QuitReview.copy(for:) — `func copy(for occasion: Occasion) -> Copy` (relied on, unchanged)
- QuitReview.init — `init(columns: [EditorColumn], vanishedSchede: [String] = [], failedSchede: [String] = [], board: Board? = nil, diary: DiaryDay? = nil)` (relied on, unchanged)
- ConflictProbe.coordinator — the existing `QuitTestSupport.swift` probe (relied on, unchanged)
Red: yes

**`Tests/VaultSwitchBoardTests.swift`, new (R-06).** Use `quitController(a)`, a second
`TemporaryVault` as B, and the Task 2 helper. Each test sets
`controller.revealOpenBoard = { revealed += 1 }`.

1. **The pure copy.**
   - `QuitReview(columns: [], board: b).copy(for: .vaultSwitch)`:
     - message `Salvare le modifiche alla board «Bacheca» prima di aprire un'altra cartella
       note?`;
     - the informative contains G2's board sentence, with «la cartella note resta aperta»;
     - `leftProblem(for: .vaultSwitch)` is G2's line;
     - `leftProblem(for: .quit) == leftProblem`.
   - The `.quit` copy of the same review is pinned literally: «… prima di uscire?» and «con «Salva»
     Pergamenum resta aperto per farti scegliere…». Every quit string stays byte-identical.
2. **`theSwitchNamesAConflictedBoardWithThePaneMounted`.**
   - `enterPane()` on the conflicted board, then `switchVault(to: b) { .cancel }`.
   - Asked once, with `review.board == openBoard.quitConflict` and `review.diary == nil`.
   - Afterwards: the root is A, the board is still conflicted, no line was added, `revealed == 0`
     («Annulla»).
3. **`theSwitchNamesAConflictedBoardWithThePaneLeft`.** The same, after `enterPane()` and
   `leavePane()`.
4. **`theSwitchNamesAConflictedBoardWhosePaneWasNeverMounted`.** The same, with no
   `enterPane()`.
5. **`salvaCancelsTheSwitchRecordsTheBoardLineAndRevealsIt`.**
   - Answer `.save`. The switch returns false and the root is A.
   - The problems contain the switch's board line. `revealed == 1`. The board is still
     conflicted, and its file's bytes are unchanged.
6. **`salvaTuttoWithANoteAndTheBoardSavesTheNoteAndRevealsTheBoard`.**
   - A dirty note plus the board, answered `.save`.
   - The note is on disk. Only the board line is added, and no «note non salvate» line.
     `revealed == 1`.
7. **`nonSalvareLetsTheSwitchGoAndWritesNothingToTheBoardFile`.**
   - Answer `.discard`. The switch returns true and the root is B.
   - A's board file is byte-identical. `openBoard` is bound to B with `board == ""` and
     `.saved`.
   - B's problems contain `detach()`'s loss line (ADR-0091 §Consequences, neutral, pinned).
8. **`aBoardChangedDuringTheQuestionCancelsTheSwitch`.** The `ask` closure adds a card, then
   returns `.discard`. The switch returns false, the line is recorded and `revealed == 1`.
9. **`aPendingBoardIsWrittenBeforeTheQuestionAndAsksNothing`.** A pending card only. Nothing is
   asked, the switch returns true, and A's file holds the card.
10. **`aPendingBoardRefusedByTheSwitchsSettleIsAsked`.** A pending card plus an external diverged
    save. The question names the board.
11. **`reopeningTheOpenVaultAsksNothingAboutTheBoard`.** `switchVault(to: a)` asks nothing, and
    the board is still conflicted.
12. **`aFirstOpenAsksNothing`.** A fresh `VaultController` with no vault:
    `switchVault(to: a)` asks nothing and returns true.

**`Tests/QuitConflictOffScreenTests.swift`, new (R-05).** Use `quitController`, the Task 2
helper, `enterPane()` and `leavePane()` to stand for "the pane left", and `ConflictProbe`.

1. **`aQuitWithTheBoardPaneLeftNamesTheConflictedBoard`.** Answer `.cancel`.
   `probe.asked.first?.board == openBoard.quitConflict`.
2. **`salvaWithTheBoardPaneLeftCancelsAndRevealsTheBoard`.** Answer `.save`. The result is
   `.cancel`, `probe.shown == [.board]`, `boardProblem` is recorded, and the bytes are unchanged.
3. **`salvaTuttoWithANoteAndTheBoardPaneLeftSavesTheNoteAndRevealsTheBoard`.** The note is on
   disk, the result is `.cancel`, and `shown == [.board]`.
4. **`nonSalvareWithTheBoardPaneLeftLetsTheQuitGoAndWritesNothing`.** The result is `.now`, and
   the board file's bytes are unchanged.

`QuitReviewConflictTests` and `VaultSwitchTests` are not edited. Task 5 must keep them green
byte-for-byte, because no review without a board changes.

### Task 4 — Coder: one owner, attach and detach on the vault, the leave (R-01, R-02, R-03, R-04, R-07, R-08)
Owner: coder
Files: Sources/App/VaultController.swift, Sources/App/VaultController+Board.swift, Sources/Features/Workspace/WorkspaceController.swift, Sources/Features/Workspace/WorkspaceController+Lifecycle.swift, Sources/Features/Workspace/WorkspaceView.swift, Sources/App/NavigationHistory.swift, Sources/App/WindowPlace.swift
Tests: BoardControllerLifetimeTests.swift, WindowPlaceTests.swift, QuitBoardLifetimeHostedTests.swift, WorkspaceFitOnOpenHostedTests.swift, QuitConflictTests.swift, QuitConflictCapTests.swift, QuitConflictDerivationTests.swift, WorkspaceLifecycleTests.swift, WorkspaceAutosaveRaceTests.swift
Signatures:
- VaultController.openBoardPath — `var openBoardPath: String? { openBoard.board.isEmpty ? nil : openBoard.board }`
- VaultController.rebindBoard — `func rebindBoard(to url: URL)`: `openBoard.detach()` then `openBoard.attach(to: CanvasStore(root: url), thumbnails: thumbnails, vault: self)`
- WorkspaceController.enterPane — `func enterPane()`
- WorkspaceController.leavePane — `func leavePane()`
- WorkspaceView.workspace — `var workspace: WorkspaceController { vault.openBoard }` (replaces `@State var workspace = WorkspaceController()`)
Red: no

**ADR-0091 §D1 to §D4.**

- **`VaultController.open(_:)`.**
  - Compute `let rebinds = outgoing?.vaultKey != incoming` beside `outgoing`
    (`VaultController.swift:260-261`). This is true on the first open, false on a same-vault
    reopen.
  - After `thumbnails = ThumbnailStore(...)` (`:277`) and before `recents.remember`/`await
    rescan()`: `if rebinds { rebindBoard(to: url) }`.
  - No `await` between `session = newSession` and the rebind. The bail branch (`:219-225`)
    returns before either.
- **`close()`.** Call `openBoard.detach()` first, before `watcher?.stop()` and `session = nil`, so
  any line lands in the closing vault's list.
- **`detach()`.**
  - `guard store != nil else { return }` at the top.
  - After `settleBoardEditing()`: flush unless already conflicted. Then, if `saveState` is
    `.conflicted` (before or after the flush), record the existing loss line, once.
  - End with `saveState = .saved` after `board = ""`.
  - The rest of the order (`saveTask` cancel, refit cancel, clears, `history.reset()`) is
    unchanged.
- **`enterPane()`.** `panePresenters += 1`.
- **`leavePane()`.**
  1. `panePresenters = max(0, panePresenters - 1)`.
  2. `settleForTermination()`.
  3. `guard panePresenters == 0, saveState == .saved else { return }`.
  4. `select(nil)`.

  The state is read after the flush, and there is no `await` anywhere in it. The doc comment says
  why the count exists: the appear/disappear order across a remount.
- **`WorkspaceView`.**
  - `var workspace: WorkspaceController { vault.openBoard }`.
  - `.onAppear { workspace.enterPane(); checkPendingNewBoard() }` and
    `.onDisappear { workspace.leavePane() }`.
  - Delete `attachWorkspace()`, `reattachWorkspace(to:)` and `.onChange(of: vault.root)`.
  - Replace the disappear comment (`:102-107`) with one sentence pointing at `leavePane()` and
    ADR-0091 §D3. R-10 names this comment.
  - `.task { openPendingCanvas() }` and its `onChange` stay.
- **Doc comments (ADR-0091 §D7).**
  - `VaultController.openBoard` and `openBoardPath`.
  - `WorkspaceController.vault` (`:99-105`): the vault owns the board now; the back-reference is
    weak to avoid a cycle.
  - `attach`'s doc, `detach`'s comments and `settleForTermination()`'s doc.
  - `NavigationHistory.swift:20-24` and `WindowPlace.swift:31-36`: no mirror; the path is read
    from the controller.
- Run `tuist generate --no-open` if Task 1 has not already been followed by one.
- **Stale incremental build.** Changing `WorkspaceView`'s stored layout (`@State` to computed) is
  the shape of the `initializeWithCopy` crash in `CLAUDE.md`. If the test host crashes at launch,
  check the `.o` timestamps. Move this worktree's own `Pergamenum-*` DerivedData (found by
  `WorkspacePath`) to the Trash before believing a red.

### Task 5 — Coder: the switch asks, the words, the hook, the quit's compensating line (R-05, R-06)
Owner: coder
Files: Sources/App/VaultController+VaultSwitch.swift, Sources/App/VaultController.swift, Sources/App/QuitReview.swift, Sources/App/QuitReview+Conflicts.swift, Sources/App/QuitCoordinator.swift, Sources/App/PergamenumApp.swift
Tests: VaultSwitchBoardTests.swift, QuitConflictOffScreenTests.swift, QuitConflictScopeTests.swift, QuitConflictLastCheckTests.swift, QuitReviewConflictTests.swift, VaultSwitchTests.swift, QuitVaultSwitchTests.swift, QuitConflictTests.swift
Signatures:
- QuitReview.Board.leftProblem(for:) — `func leftProblem(for occasion: QuitReview.Occasion) -> String`
- QuitReview.Words.stayingClause — `let stayingClause: String` (private struct, new member)
- VaultController.revealOpenBoard — `@ObservationIgnored var revealOpenBoard: (() -> Void)?` (wired in `PergamenumApp`)
Red: no

**ADR-0091 §D5 to §D7.**

- **`switchVault(to:ask:)`**, after the preflight (`VaultController+VaultSwitch.swift:58-63`):
  1. Call `openBoard.settleForTermination()`.
  2. Build `let review = QuitReview(columns: columns, board: openBoard.quitConflict)`.
  3. `.cancel` returns false, with no reveal. `.save` awaits `saveForQuit(review)`. The
     `session === leaving` re-check is unchanged.
  4. Build `let now = QuitReview(columns: columns, board: openBoard.quitConflict)`.
  5. Compute what is left:
     - for `.save`: `QuitReview.Uncovered(notes: now.entries, board: now.board, diary: nil)`;
     - for `.discard`: `review.uncoveredWork(in: now)`.
  6. If `!left.isEmpty`:
     - record the existing notes line only when `left.notes` is non-empty;
     - record `left.board?.leftProblem(for: .vaultSwitch)` when present;
     - switch on `left.firstReveal()`: `.board` calls `revealOpenBoard?()`, `.note(id)` calls
       `revealTab(id)` as today;
     - return false.
  - Everything after is unchanged. `open(url)`'s rebind detaches the covered board.
  - Update the method's doc comment: the board is asked about, and the diary is not.
- **`QuitReview.Words`.**
  - Add `stayingClause`, a mid-sentence form:
    - quit: «Pergamenum resta aperto», byte-identical;
    - vaultSwitch: «la cartella note resta aperta»;
    - columnClose: «la colonna resta aperta».
  - `sentences(noteNames:saveLabel:staying:)` passes `stayingClause` to `board.sentence` and
    `diary.sentence`. The notes' two sentences keep `staying`, so every review without a board or
    diary is byte-identical.
- **`QuitReview.Board.leftProblem(for:)`.**
  - `.quit`: `Uscita annullata: …`, the existing text.
  - `.vaultSwitch`: `Apertura di un'altra cartella note annullata: …`.
  - `.columnClose`: `Chiusura della colonna annullata: …`.
  - `leftProblem` returns `leftProblem(for: .quit)`.
  - The diary's `leftProblem` is untouched.
- **`QuitReview+Conflicts.swift`.**
  - Header (`:3-5`): the quit passes both, the switch passes the board, the column close neither.
  - `firstReveal`'s doc (`:94-97`): the board leads because it is listed first, not because
    another reveal destroys it.
- **`QuitCoordinator.showUncovered`** becomes `show(left.firstReveal())`. Delete the
  `leftProblem` line (`:380-382`) and correct `lastCheck`'s doc (`:320-325`).
- **`PergamenumApp`'s window `.onAppear`** (`:368-373`): `vault.revealOpenBoard = { [weak
  appDelegate] in appDelegate?.revealBoardAfterCancelledQuit() }`. `appDelegate` is the
  `@NSApplicationDelegateAdaptor(AppDelegate.self)` instance (`PergamenumApp.swift:130`), a class
  reference, so the capture is weak and the facade holds no strong reference to the delegate.
- **The doc comment on `revealOpenBoard`** names its one production writer and that it is nil in
  tests unless set.

### Task 6 — Tester: folder verbs refuse over a kept board with unsaved edits, gate G1 (R-02)
Owner: tester
Files: Sources/App/VaultController+Folders.swift, Tests/BoardFolderVerbGuardTests.swift
Tests: BoardFolderVerbGuardTests.swift, VaultControllerReconcileTests.swift, VaultMoveTests.swift
Signatures:
- VaultController.unsavedBoardInFolderRefusal — `static func unsavedBoardInFolderRefusal(named name: String) -> String` (`VaultController+Folders.swift`, beside `unsavedNoteInFolderRefusal`; neutral body `""`)
- VaultController.canOperateOnFolder — `func canOperateOnFolder(_ relativePath: String) -> Bool` (relied on, signature unchanged)
- VaultController.renameFolder — `func renameFolder(at relativePath: String, to newName: String) -> String?` (relied on)
- VaultController.trashFolder — `func trashFolder(at relativePath: String) -> Bool` (relied on)
- VaultController.moveItems — `func moveItems(_ items: [VaultItemRef], into destination: String, undo: UndoManager?) async -> VaultSession.MoveBatchOutcome` (relied on)
- WorkspaceController.settleForVerb — `func settleForVerb() -> Bool` (relied on, unchanged)
Red: yes

**Runs only if G1 is approved.** Write `Tests/BoardFolderVerbGuardTests.swift` with the board
«Bacheca» in `Progetti/`, made conflicted on `controller.openBoard` and left with
`enterPane()`/`leavePane()`.

1. `renamingTheFolderOfAKeptConflictedBoardIsRefusedNamingTheBoard`. `renameFolder` returns
   nil, the folder is unmoved, and the problems contain
   `unsavedBoardInFolderRefusal(named: "Bacheca")`. This is G2's text, pinned literally.
2. `trashingTheFolderOfAKeptConflictedBoardIsRefused`. `trashFolder` returns false, and nothing
   goes to the Trash.
3. `movingTheFolderOfAKeptConflictedBoardIsRefusedWithTheBoardsSentence`.
   `outcome.refusals == [board sentence]`, not the note's.
4. `aConflictedBoardOutsideTheFolderDoesNotRefuse`. The folder is renamed.
5. `aDirtyNoteInTheFolderStillGivesTheNotesSentence`. The note's check runs first, and
   `unsavedNoteInFolderRefusal` is unchanged.
6. `theWorkspacesOwnVerbIsNotRefusedTwice`.
   - A board with a pending edit, the pane entered (on screen).
   - Run `openBoard.settleForVerb()` (true), then `renameFolder`. It succeeds, and only the
     verb's own lines are recorded.

### Task 7 — Coder: the folder guard, gate G1 (R-02)
Owner: coder
Files: Sources/App/VaultController+Folders.swift, Sources/App/VaultController+Move.swift
Tests: BoardFolderVerbGuardTests.swift, VaultControllerReconcileTests.swift, VaultMoveTests.swift, VaultSessionFolderOperationsTests.swift
Signatures:
- VaultController.unsavedBoardInFolderRefusal — `static func unsavedBoardInFolderRefusal(named name: String) -> String`
- VaultController.folderRefusal — `func folderRefusal(_ relativePath: String) -> String?` (new, internal, in `VaultController+Folders.swift`; answers the sentence without recording it, read by `canOperateOnFolder` and by `refusal(forAll:)` in `+Move`)
Red: no

**Runs only if G1 is approved. ADR-0091 §D8.**

- **`folderRefusal(_:)`.**
  - Return the note's sentence when a dirty tab lies in the folder. That check is first, and
    unchanged.
  - Otherwise return `unsavedBoardInFolderRefusal(named:)` when `openBoard.hasUnsavedChanges`
    and `openBoard.board` equals the trimmed folder or starts with `folder + "/"`. The name is
    the board's file name without `.canvas`, as `QuitReview.Board.name` spells it.
  - Otherwise return nil.
- **`canOperateOnFolder(_:)`** records `folderRefusal`'s answer and returns whether there was
  none.
- **`refusal(forAll:)`.** Its `.folder` case calls `folderRefusal`, records the answer and returns
  it. It never reads `problems.last`, which PG-083 removed on purpose.
- Update the doc on `refusal(forAll:)` (`VaultController+Move.swift:160-168`). A folder can now
  be refused for a board too.

### Task 8 — Coder: the record, the amendments, verification (R-09, R-10)
Owner: coder
Files: docs/adr/0091-the-board-controller-lives-with-the-vault.md, docs/adr/0089-a-conflicted-board-or-diary-is-asked-about-at-quit.md, docs/adr/0066-workspace-board-lifecycle-one-reset-door.md, docs/adr/0073-quit-reviews-unsaved-notes.md, docs/adr/INDEX.md, CLAUDE.md, docs/20260811_Pergamenum_SpecApp.md, docs/plans/pg-392-board-controller-vault-lifetime.md
Tests: VaultSwitchBoardTests.swift, BoardControllerLifetimeTests.swift, QuitConflictOffScreenTests.swift
Signatures:
- ADR-0091 — `docs/adr/0091-the-board-controller-lives-with-the-vault.md`, status `proposed` until the merge, then `accepted` with the merge hash (docs/adr/README.md rule 2)
- head note — `**Amended 2026-10-07 (ADR-0091):** …` (the form ADR-0089 already uses on the ADRs it amends)
Red: no

**Documentation (R-10, no test).**

- **Head notes,** each body untouched:
  - **ADR-0089.** §D7's residual is closed, because the controller lives with the vault. §D8's
    "the vault switch is unchanged" and "`detach()` is untouched" are superseded by ADR-0091
    §D2/§D5. §D6's "destroys its controller" rationale is replaced by §D7's. The implementation
    note on a covered board left by an uncovered reveal no longer records a line.
  - **ADR-0066.** §D5: `openBoard` is owned, not weak, and is neither set by `attach` nor cleared
    by `detach`. §D2 gains the pane leave (ADR-0091 §D3). The Consequences bullet "weak and serves
    the quit path alone" is superseded.
  - **ADR-0073.** The last sentence of G-c ("still lost; it is ledger entry `PG-392`") is closed by
    ADR-0091.
- **`docs/adr/INDEX.md`.**
  - Correct ADR-0089's summary (`:116`, "its ledger entry to be filed (ADR-0089 §D7)") to say the
    residual is `PG-392`, closed by ADR-0091.
  - Append one long-form ADR-0091 summary at the end of "Chain decision index".
- **`CLAUDE.md` `## ADR index`.** Paste the ADR-0091 line `scripts/adr-index.py` prints, and
  confirm with `scripts/adr-index.py --check`.
- **G3, if approved.** One dated sentence in `docs/20260811_Pergamenum_SpecApp.md` §5, beside the
  ADR-0089 sentence (`:208-220`).
- **ADR-0091 Implementation notes.** Record:
  - the G1/G2/G3 outcomes;
  - the `HostedView` `onDisappear` measurement;
  - Task 1 test 14's outcome;
  - every departure.
- **PG-392 closes with the PR.**
  - The PR body carries `Closes #918`.
  - The `TODO.md` ledger line moves in the project's usual post-merge sync, not on this branch
    (parallel chains conflict there).

**Verification (R-09).**

- The full unit suite (TEST-CMD below), not only the new files. The contract changes reach
  `QuitConflict*`, `VaultSwitch*`, `WindowPlace*`, the hosted Workspace tests and every test that
  opens a `VaultController`.
- Build `perg` and `pergamenum-mcp`: `xcodebuild -workspace Pergamenum.xcworkspace -scheme perg
  -destination 'platform=macOS' build`, and the same for `pergamenum-mcp`. Run
  `scripts/mcp-smoke.py` only if `Sources/MCPServer` was touched; it should not be.
- Run `scripts/check-adr-references.py` (after `git fetch origin`) and
  `scripts/adr-index.py --check`.
- Run SwiftLint on the touched Swift files only, read-only. It is a review step, not a gate (see
  CHECK-CMD).
- At merge, run `scripts/uitests.sh --status`, then `--affected`. It is advisory and does not block
  (`CLAUDE.md` merge gate). The Workspace classes are the likely selection.
- Run the hand checks below on this worktree's Debug build, found by `WorkspacePath` as `CLAUDE.md`
  shows.

## Hand checks (no GUI test)

On this worktree's Debug build, with a throwaway vault (`-recentVaults '("/path")'`).

To make a board conflicted:

1. Open the board.
2. Add a card.
3. Within a second, edit the `.canvas` in a text editor: change a text node, or add a node with a
   new id.
4. Edit the board again in the app.

The top bar reads «Conflitto» with its two buttons.

1. **R-02.** Make a board conflicted, go to Note, then back to Workspace. The same board shows,
   with the banner.
2. **R-03.** On a clean board, go to Note and back. The empty Workspace state shows. Back and
   forward still reach the board.
3. **R-05.** Make a board conflicted, go to Note, then press Cmd+Q.
   - The question names «la board «…»».
   - «Salva» cancels and shows the Workspace and the banner.
   - Press Cmd+Q again: «Non salvare» quits, and the `.canvas` keeps the other writer's bytes.
4. **R-05, red button.** The same, closing the last window with the red button.
5. **R-06.** Make a board conflicted, go to Note, then use «Apri cartella note…» on another vault.
   - The question names the board.
   - «Annulla» stays put.
   - «Salva» stays put and reveals the board.
   - «Non salvare» opens the other vault, with the empty Workspace and no stale board.
6. **R-08.** With the app quit, open `pergamenum://canvas?file=<board>.canvas` from Terminal with
   `open`. The board opens.

## Risks and HITL gates

- **The HostedView `onDisappear` delivery is unverified.** Task 2's step 0 measures it. Whatever
  the answer, the release is pinned at the controller level (Task 1).
- **The appear/disappear pairing is SwiftUI's.** An unpaired `onAppear` keeps a clean board instead
  of releasing it. That is the safe direction (ADR-0091 §Consequences), and the hand check R-03
  would show it.
- **`attach` on appear would wipe a kept board.** Task 4 deletes the call. A reviewer should grep
  `attach(to:` in `WorkspaceView*.swift` and find nothing.
- **Isolation of the `let`'s initial value.** `VaultController` and `WorkspaceController` are both
  `@MainActor`. Assigning in `init` avoids any question over isolated default values.
- **A stale incremental build** after the `@State` to computed change: the crash recipe and fix are
  in Task 4.
- **File-length debt.** `WorkspaceController.swift` is 609 lines and `VaultController.swift` 444,
  both past the 400-line warning. Additions stay in `+Lifecycle`, `+Board` and `+VaultSwitch`; the
  two main files gain stored properties only.
- **Contract changes beyond the new files.** The full unit suite runs in Task 8. A shared contract
  (`openBoard`, `openBoardPath`, the switch's review) can break a test in an unrelated module.
- **Parallel chains.** Re-check ADR 0091 and `docs/adr/INDEX.md` against `origin/main` before the
  merge. `TODO.md` is not edited here.
- **HITL:** G0 to G4 above, and every commit, push and PR. There is no schema change, no deletion
  of user data and no deploy.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

There is no `.claude/check-cmd`. `ci.yml` does not run SwiftLint (its header says the whole-repo
run fails by design on seven types, per `.swiftlint.yml`), so a whole-repo `swiftlint lint` would
fail on documented debt every turn. SwiftLint on the touched files stays a review step (Task 8).

## Build notes

Filled in by /build: the `HostedView` `onDisappear` measurement (Task 2 step 0), Task 1 test 14's
outcome, the gate answers, and the verification results.

Gate answers (2026-10-08, at /build): G1 include §D8 (Tasks 6 and 7 run); G2 strings approved as
written; G3 yes (one dated sentence in the app SPEC §5); G4 confirmed (four existing tests changed on
purpose, none disabled). G0 is left to /ship.

**Task 2 step 0, the `HostedView` `onDisappear` measurement (2026-10-08, red phase).** The step as
written (hide the pane, see whether `board == ""` follows) cannot be read before Task 4, because
until then `WorkspaceView` still shows its own `@State` controller and nothing binds
`controller.openBoard`. It was measured one level down instead: a plain view carrying
`.onAppear`/`.onDisappear` counters, shown and then hidden through `PaneFlag` in the same harness.
Result: **`HostedView` delivers both.** `appeared == 1` after `settle()`, `disappeared == 1` after
`flag.shown = false` and a second `settle()`
(`QuitBoardLifetimeHostedTests.theHarnessDeliversOnDisappearWhenAViewLeavesTheTree`, kept as a
pin). So tests (c) and (d) assert the pane leave itself, not a weakened form. What this does not
prove is `WorkspaceView`'s own `.onDisappear` reaching `leavePane()`; (c) answers that once Task 4
wires it.

**Task 1 test 14 (read-only folder).** The store's write does fail on a read-only folder:
`CanvasStore.save` throws `NSCocoaErrorDomain 513` (mktemp, errno 13) inside
`withReadOnlyFolder(root, "Progetti")`, `attemptSave` records `salvataggio di Progetti/Piano.canvas:
…` and leaves `saveState == .pending`. Measured with a throwaway probe on a directly attached
controller (since removed). The test is kept, and it asserts that line too, so a leave that never
attempted the write cannot pass it.

**Departures from the plan's text, red phase.**

- Task 3 `QuitConflictOffScreenTests` tests 2 and 3 say "the result is `.cancel`". A «Salva» answer
  is asynchronous at the quit (`QuitConflictTests.salvaOnALoneConflictedBoard…` pins `.later`, then
  the reply `false`), so they assert `.later` and `replies == [false]`, the same contract for a
  board on screen.
- Task 1 test 10 says "the same `store` instance". `CanvasStore` is a value type, so the test
  compares `store?.root` before and after.
- `QuitBoardLifetimeHostedTests` gained one test beyond (a) to (d), the step 0 pin above.
- `WindowPlaceTests` boards are created at the vault root: `CanvasStore.createBoard(in:)` fails
  when the parent folder does not exist, and those tests build an empty vault.

**Green phase (Tasks 4, 5, 7, 8, 2026-10-08).** Test (c),
`aCleanBoardIsReleasedToTheEmptyStateOnLeave`, passes once Task 4 wires `.onDisappear` to
`leavePane()`: `WorkspaceView`'s own disappear reaches the leave in the hosted harness. Departures
from the plan's text, each recorded in ADR-0091's Implementation notes:

- `detach()` calls `flushPendingSave()` unconditionally (`save()` already skips a conflicted
  board), then reads the conflict.
- `QuitCoordinator.showUncovered` is deleted; its two callers call `show(left.firstReveal())`.
- `QuitReview.sentences` takes `words: Words` instead of `staying:`.
- The switch's cancel lines and reveal live in a private `recordSwitchCancel(leaving:)`.
- `folderRefusal(_:)` ignores an empty `board`.
- ADR-0073's head note is a bullet in its head list, the shape that head already has.

## Build result (2026-10-10)

BUILD · DONE WITH WARNINGS
Files: 43 paths changed or added (16 Sources, 17 Tests, 10 docs, the plan and SPEC.md)
Tests: PergamenumTests 5700 passed, 0 failed, 17 (coverage)
Review: sonnet, safe to merge; opus, safe to merge
Coverage: STALE-WAIVER R-10 (R-01 to R-09 covered by tests, R-10 is documentation)
Deferred: 1 (needs-spec 1)
Dropped: 10 (fix-hunk 3, post-sweep 3, nit 4)
Dispatch: Round 0 (red): tester — Task 1, tester — Task 2, tester — Task 3, tester — Task 6
Dispatch: Round 1: coder — WorkspaceController+Lifecycle.swift:134 (reviewer: sonnet, opus), debugger — WorkspaceController+Lifecycle.swift:558 (reviewer: sonnet), coder — VaultController+Move.swift:165 (reviewer: opus)
Dispatch: Round 2: coder — ADR-0091.md:144 (reviewer: sonnet, opus), coder — BoardControllerLifetimeTests.swift:137 (reviewer: sonnet), coder — VaultController.swift:281, VaultController.swift:262, VaultController+Move.swift:179, WorkspaceView.swift:240, WorkspaceController+Lifecycle.swift:156, BoardLifetimeCoverageTests.swift:37 (reviewer: opus)
Dispatch: Round 1 (sweep): coder — C1, C2, C3 and every AUTO line
Dispatch: Round 2 (sweep): coder — VaultController+Move.swift:113 (3 MINOR, reviewer: sonnet, opus), ADR-0091.md:476 (reviewer: sonnet), VaultController+Move.swift:121 (follow-up: coder)
WARN: R-10 has a stale (no-test: …) exemption in SPEC.md, a test names it
WARN: debugger report for round 1 lost to an API error (the fix is in the tree, the suite is green)
INFO: review escalated, size: 38 changed files, threshold 20
NEXT: /ship

```text
DEFER	needs-spec	**MINOR** [other] Tests/QuitConflictScopeTests.swift:118-137 — A conflicted diary at a vault switch is now pinned as "asks nothing and proceeds" with no ledger entry for the deferral the SPEC promised. Fix: file the ticket and cite it from the test comment. (reviewer: opus)
FIX	swept	**NIT** docs/20260811_Pergamenum_SpecApp.md:221 — The reflowed autosave sentence trails the ADR-0091 amendment and leaves a 134-character line where the file wraps at about 98. (reviewer: sonnet, opus)
FIX	swept	**NIT** docs/adr/INDEX.md:116 — ADR-0089 entry still says only the quit passes the board, never the vault switch, and keeps the "another pane destroys the controller" rationale, both superseded by ADR-0091 D5 and D7. (reviewer: sonnet)
FIX	swept	**NIT** Sources/App/VaultController+Folders.swift:57-58 — The doc still says canOperateOnFolder records this exact sentence, now one of two. Say "the note's sentence". (reviewer: opus)
FIX	swept	**NIT** Sources/App/VaultController+Folders.swift:65-66 — The refusal sentence says "prima di rinominare o eliminare la cartella" but is also returned for a move; it mirrors the note sentence's existing mismatch, so changing it is a copy decision. (reviewer: opus)
FIX	swept	**MINOR** [style] Sources/App/VaultController+Folders.swift:40-42 — "never refused twice" is false when settleForVerb flush fails and leaves .pending: the new hasUnsavedChanges branch then refuses the Workspace own verb. Fix: state that case in the comment and in ADR-0091 D8, or decide explicitly whether .pending should refuse there. (reviewer: opus)
FIX	swept	**NIT** Sources/App/QuitReview+Conflicts.swift:132 — The .columnClose branch of leftProblem(for:) and the columnClose stayingClause are unreachable in production (column close passes no board) and exist only for tests. (reviewer: sonnet)
FIX	swept	**MINOR** [style] docs/adr/0091-the-board-controller-lives-with-the-vault.md:155 — ADR cites CLAUDE.md for the "precondition before an await is a filter" rule (also line 329 for the willTerminateNotification warning), but both live in .claude/rules/vault-writes.md. Fix: cite that file. (reviewer: sonnet)
FIX	swept	**MINOR** [style] Sources/App/QuitReview.swift:77-78 — board doc comment still says only the quit passes one, contradicted by switchVault and the amended QuitReview+Conflicts header. Fix: say the quit and the vault switch pass one. (reviewer: opus)
FIX	swept	**NIT** Tests/WorkspaceDocumentCreationTests.swift:51 — Comment cites WorkspaceView.attachWorkspace, deleted by this change. Say the vault controller open(_:) binds the board. (reviewer: sonnet)
FIX	swept	**NIT** docs/adr/0091-the-board-controller-lives-with-the-vault.md:125-129 — D3 list of what the release does omits the leavePane tool/isToolLocked reset, which only Departures mentions. (reviewer: opus)
FIX	swept	**NIT** Sources/App/AppDelegate+QuitReveal.swift:23-25 — The doc names only the cancelled quit and the quit reader; the cancelled vault switch now calls it through revealOpenBoard. (reviewer: opus)
DROP	post-sweep	**MINOR** [other] Sources/App/PergamenumApp.swift:204 — init of PergamenumApp is 62 lines against 50, pre-existing (follow-up: coder)
FIX	swept	**MINOR** [other] Sources/App/PergamenumApp.swift:368-373 — the vault.revealOpenBoard wiring and AppDelegate.revealBoardAfterCancelledQuit() are glue no automated test reaches; hand check R-06 covers the real path (follow-up: tester)
FIX	swept	**MINOR** [other] Sources/App/VaultController+Move.swift:109 — attemptInverse (undo/redo of a batch with a board) builds a .board ref and passes it to refusal(forAll:) without settleForVerb(); a pending autosave could land on the path just left, not verified at runtime, confidence medium (follow-up: coder)
FIX	swept	**MINOR** [other] Sources/Features/Editor/NoteListPane.swift:536 — performMove and NoteTreeRow.swift:122 accept any VaultItemDrag, boards included, and call vault.moveItems without settleForVerb(); reachability unknown, confidence low (follow-up: coder)
FIX	swept	**MINOR** [other] Sources/App/VaultController.swift:221 — line of 125 characters over line_length, already like that before this task (follow-up: coder)
FIX	swept	**MINOR** [other] Tests/BoardControllerLifetimeTests.swift:473 — file_length warning (limit 400), grown with the four round-2 tests (follow-up: coder)
FIX	swept	**MINOR** [wrong-behaviour] Sources/App/VaultController+Move.swift:113 — settleForVerb() refuses only a conflict, so a failed flush leaves the board pending and the undo still moves its file (refusal(forAll:) ignores .board refs), stranding the unsaved edits; the comment and ADR claim the pending edit is written before the move. Fix: also refuse when openBoard.hasUnsavedChanges and openBoard.board is one of the step .board refs, or document the failed-write case; add a read-only-folder test. (reviewer: sonnet)
FIX	swept	**MINOR** [other] docs/adr/0091-the-board-controller-lives-with-the-vault.md:476 — The Fixed paragraph says the edit is written before the file moves, but the move runs in a later Task { await performInverse } with awaits between destination groups, so the settle is a filter, not a guard; the batch residual does not cover the undo path. Fix: name the Task hop and the inter-group awaits as a residual. (reviewer: sonnet)
FIX	swept	**MINOR** [other] Sources/App/VaultController+Move.swift:113 — The settle triggers only for .board refs; a .folder ref holding the open board with a pending edit is refused by folderRefusal instead of flushed, and the undo step is consumed. Fix: settle whenever any ref in the step contains openBoard.board. (reviewer: sonnet)
FIX	swept	**MINOR** [other] Sources/App/VaultController+Move.swift:113 — The undo settle/refusal is asked of whichever board is open, so an unrelated kept conflicted board consumes the undo step and records a line naming it. Fix: scope the check to the moved board. (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/App/VaultController+Move.swift:121 — performInverse: undoing a move does not re-open the open board on the path where the file returns; the forward path calls followMove, the undo does not, so the board stays on a path that is gone and its next edit turns conflicted unresolvably; predates ADR-0091 (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Sources/App/VaultController.swift:455 — file_length 455 against 400, already 444 on HEAD (follow-up: coder)
DROP	fix-hunk	**MINOR** [other] docs/adr/0091-the-board-controller-lives-with-the-vault.md:467 — The undo-settle Residual says the autosave can land on the path just left, but CanvasStore.save(expecting:) refuses a missing file, so the board stays pending and followMove open(board:) then replaces the document and drops the in-window edit with only a write-failure line. Fix: rewrite the paragraph with the real mechanism and loss. (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [other] Tests/BoardMoveUndoSettleTests.swift:200 — No test pins performInverse followMove after a multi-group undo where one group fails, the sibling-prefix boundary of carriesOpenBoard (Progetti vs Progetti-altro), or the refusal path on redo. Fix: add those three tests. (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [other] Sources/App/VaultController+Move.swift:116 — A refused inverse consumes the undo step (NSUndoManager popped it, nothing re-registers), so after the conflict is resolved the move can never be undone and the next Cmd+Z reverses an earlier move. Fix: name it in ADR-0091 Residual list, or keep the step on the undo stack across a refusal. (reviewer: opus)
DROP	post-sweep	**MINOR** [other] Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift:41 — the forward path has the same hole as the undo had: if settleForVerb() lets a pending board through because the flush failed, moving a .board ref goes ahead and refusal(forAll:) ignores .board, so the file moves away from the unsaved edits (follow-up: coder)
```
