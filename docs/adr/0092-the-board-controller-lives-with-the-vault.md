# ADR-0092: The Workspace board controller lives with the vault, not with its pane

- Status: **proposed**. Not on `main`: written with its plan, before the implementation.
- Date: 2026-10-07. Written against `29bb3aa0`, which is both `origin/main` and the tip of
  `feature/pg-392-board-controller-vault-lifetime`. Every line number below was read from that
  tree.
- **Numbering note.** `0090` is the highest ADR on `origin/main`. No local or remote-tracking ref
  holds a `docs/adr/0091*` file (checked 2026-10-07 with `git ls-tree` over every ref). This record
  takes `0091`. Check again immediately before the merge (`docs/adr/README.md` §1).
- Source: `SPEC.md` "A conflicted Workspace board outlives the pane and the window (PG-392,
  #918)", Approved 2026-10-07, R-01 to R-10. Plan:
  `docs/plans/pg-392-board-controller-vault-lifetime.md`. No brainstorm or UX blueprint belongs to
  this chain: the `BRAINSTORM.md` and `UX-BLUEPRINT.md` at the repository root are PG-018's and
  Pratiche's.
- **Amends** ADR-0089 §D7, §D8 and its implementation note "a covered board left by an uncovered
  reveal", and ADR-0066 §D2 and §D5 with the Consequences bullet on the weak reference.
  **Extends** ADR-0054 §D5, ADR-0060 §D3, ADR-0073 §D7 and ADR-0089 §D1 to §D6. Reverses none of
  them.

## Context

ADR-0089 made the quit ask about a conflicted Workspace board. It named the case it could not reach
(§D7): a board whose pane has left the screen has no controller left to ask about. Today:

- **The view creates the controller.** `WorkspaceView` holds
  `@State var workspace = WorkspaceController()` (`WorkspaceView.swift:33`). `RootView`'s detail is
  a `switch pane` (`RootView.swift:273`), so a pane switch destroys the view and the controller
  with it.
- **The vault only borrows it.** `VaultController.openBoard` is `weak` (`VaultController.swift:163`).
  `attach` sets it (`WorkspaceController.swift:154`) and `detach` clears it (`:193`).
- **A conflicted board leaves with the view.** `.onDisappear` flushes unless the board is
  conflicted (`WorkspaceView.swift:101-112`). A conflicted board's edits go with the controller, and
  nothing records the loss.
- **Attach and detach depend on the view being mounted.** `attach` runs on `.onAppear`, and
  `detach` then `attach` on `.onChange(of: vault.root)` (`:97-100`, `:143`, `:201-213`). A vault
  switch made from another pane detaches nothing, because the controller is already gone.
- **The vault switch never names the board.** `switchVault(to:ask:)`
  (`VaultController+VaultSwitch.swift:46`) builds its review from the editor columns alone
  (`:64`, `:71`), as ADR-0089 §D1 decided.
- **The open-board path is a mirror that goes stale.** `openBoardPath`
  (`VaultController.swift:81`) is written by the view (`WorkspaceView.swift:125-127`) and read by
  `WindowPlace.destination` (`WindowPlace.swift:37`). Nothing clears it when the pane leaves. After
  a pane switch and a return through the sidebar, the screen shows the empty Workspace while
  `destination` still names the last board.
- **The quit compensates for the loss.** `QuitCoordinator.showUncovered`
  (`QuitCoordinator.swift:375-384`) records a board's `leftProblem` whenever a cancel's reveal
  switches away from a conflicted board the answer covered, because the switch destroys the
  controller (ADR-0089, implementation notes).

Five facts read in the tree shape the decision:

1. **The board's save is synchronous.** `CanvasStore.save(_:board:expecting:)` is not `async`, and
   `flushPendingSave()` calls it directly (`WorkspaceController+Saving.swift:29-33`). A flush has
   no suspension point inside it.
2. **A save over a file that moved refuses.** With an expectation, `CanvasStore.save` refuses a
   missing or changed file and never recreates it. «Mantieni le mie modifiche» and «Ricarica dal
   disco» both read the file again (`WorkspaceController+Conflict.swift:17`, `:34`), so they stay
   stuck while the file is gone.
3. **`.canvas` paths never reach `VaultWatcher`** (ADR-0054 §D7). A board kept in memory hears of
   no outside edit.
4. **The app has one window, one `VaultController` and one vault.** The diary's controller is
   already app-level (`PergamenumApp.swift:161`), and its conflict survives every pane switch.
5. **Problem lines belong to the session.** `recordProblem` forwards to `session?.recordProblem`.
   A line recorded after `session = newSession` (`VaultController.swift:272`) lands in the new
   vault's list. Today `reattachWorkspace` runs after that assignment too.

## Decision

### D1 · One controller, created and owned by the vault controller

`VaultController` declares `let openBoard = WorkspaceController()`. It is created with the vault
controller, never nil and never replaced.

`WorkspaceView` no longer creates a controller. Its `workspace` becomes a computed property that
reads `vault.openBoard` from the environment, so the view cannot show any controller other than the
one the quit and the switch read. `WorkspaceView()` keeps its empty initialiser, so `RootView` and
the hosted-view tests keep their shape.

`attach` no longer registers the controller (`WorkspaceController.swift:154`), and `detach` no
longer clears the registration (`:193`). Nothing assigns `openBoard`. A test that builds its own
`WorkspaceController` and attaches it with `vault:` still reports its problems to that vault, but
it is no longer `openBoard`.

`WorkspaceController` keeps its weak `vault` reference. The vault now owns the controller, and the
weak back-reference is what stops the two from holding each other.

### D2 · Attach and detach follow the vault

- **Opening another vault.** `open(_:)` rebinds the controller when the vault it opens is not the
  one already open. It compares by `vaultKey`, as the method already does (`:260-261`). The rebind
  is `detach()`, then `attach(to: CanvasStore(root: url), thumbnails: thumbnails, vault: self)`.
  It runs after `session = newSession` and `thumbnails = …` (`:272`, `:277`) and before
  `await rescan()`, in one synchronous stretch.
  - `detach()` flushes a pending board through its own store, which still names the vault being
    left. ADR-0052's rule therefore holds: nothing read from vault A is written into vault B.
  - The loss line `detach()` records for a conflicted board lands in the new vault's list, as it
    does today (fact 5).
- **Reopening the same vault.** There is no rebind. The controller, its board and its conflict are
  untouched. This is today's behaviour, and it is the SPEC's edge case "a conflicted board whose
  vault is the one being switched to is not in play". Only the thumbnail cache follows: the board
  is pointed at the `ThumbnailStore` `open(_:)` has just built (implementation notes, Departures).
- **A bail.** When `open(_:)` cannot resolve the state base, it returns before the rebind. The
  controller stays bound to the vault that stays open.
- **Closing.** `close()` detaches first. It has no production caller; the tests use it as cleanup.
- **`detach()` becomes idempotent.** It returns at once when no store is attached, so a second call
  records nothing: no line with an empty board name. Once the board is gone it also leaves
  `saveState` at `.saved`, so a detached controller never reads as conflicted.
- **`detach()` reads the conflict after its flush.** Today it decides the loss line before the
  flush, so a flush that its own refusal turns conflicted is cleared with only the refusal's line.
  The vault now detaches whether or not the pane is mounted, so `detach()` is the switch's last
  word on the board, and it records the loss line for that case too.
- **The view stops attaching.** `attachWorkspace()`, `reattachWorkspace(to:)` and
  `.onChange(of: vault.root)` are deleted from `WorkspaceView`.

### D3 · Leaving the pane settles, flushes, then releases only a saved board

The controller gets two doors. The view calls them, and nothing else does:

- `enterPane()`, from `.onAppear`, counts one more appearance of the pane (`panePresenters`).
- `leavePane()`, from `.onDisappear`, counts one fewer, never below zero. It then runs what
  `settleForTermination()` runs: settle, then flush unless conflicted. Last, it **reads the state
  after the flush** and releases the board only when no appearance is left and
  `saveState == .saved`.

The release is `select(nil)`'s existing folder/nil branch (`WorkspaceController.swift:281-310`). It
is reached only for a saved board, so its conflict guard never fires and it records nothing. It
empties `board`, `document` and `contents`, sets `origin` to `.none` and `current` to nil, and drops
the selection, the owed refit and the history. After it, `leavePane()` puts the tool back to
`.select` and sets `isToolLocked` to false, so a drawing tool armed before the leave does not draw
on the next board opened. The store, the thumbnails and the vault stay attached. With nothing shown
(`current` already nil), the release does nothing, which is also right.

What each state does on a leave:

- **Saved:** released. The pane comes back on its empty state, as today, and no clean board stays in
  memory to go stale (fact 3).
- **Pending:** flushed, then judged by the outcome.
  - A write that lands ends `.saved`, and the board is released.
  - A write that is refused enters `.conflicted` through its one door (ADR-0054 §D5), and the board
    is kept.
  - A write that fails stays `.pending` with its problem line, and the board is kept. The rule is
    "release if and only if saved".
  - That kept pending board is not named by the quit or the switch. `quitConflict` answers only
    for `.conflicted` (ADR-0089 §D2). The quit retries the write in its settle, the switch in its
    settle and again in `open(_:)`'s `detach()`. When the retries fail too, the edits are dropped
    with only the write-failure line.
    This is a named residual of this record, to be filed (ledger entry filed after the merge
    by /project-tasks). Widening
    `quitConflict` to a failed pending board is an ADR-0089 §D2 decision, out of scope here.
- **Conflicted:** kept, with its document, its origin and its banner. `BoardTopBar`'s save indicator
  reads `saveState`, so the banner is back as soon as the pane is.

**A re-entry during the flush.** The flush is synchronous (fact 1), so nothing interleaves inside
it. What can happen is that SwiftUI delivers the new appearance's `onAppear` before the old one's
`onDisappear`. The count is then still one after the decrement, and the board is not released. The
decision reads `panePresenters` and `saveState` after the flush, on the same side of any future
suspension point as the release. That is `.claude/rules/vault-writes.md`'s rule on a precondition
read before an `await`.

**The settle is new on this path.** Today's `onDisappear` only flushes, so a text or title draft
open at a pane switch was dropped with the controller. It is now committed. This is ADR-0066 §D2's
rule ("every leave path settles, then flushes, then resets") applied to the one leave it did not
cover.

**A window close is not a leave** in the SPEC's sense: it reaches the quit (ADR-0073 §D1). If
`onDisappear` runs first, the same rule applies, and a conflicted board is kept for the quit to
name.

**Coming back to a kept board** shows it. Zoom and pan are not restored: the board view's
`onAppear` fits the board it shows (`WorkspaceView+Board.swift:55-59`), as it does for any board.

### D4 · The open board's path is derived

`openBoardPath` becomes a computed property: `openBoard.board`, or nil when that is empty. It lives
in a new file, `Sources/App/VaultController+Board.swift`. The view's `.onChange(of: workspace.board)`
mirror is deleted.

`WindowPlace` does not change. It reads the same property, which is now always true:

- after a pane leave that released the board, `destination` on the Workspace pane reads
  `.pane(.workspace)`, which is what the screen shows. The stale `.workspaceBoard(last)` is gone;
- history back and forward to a board, and a `pergamenum://canvas` route parked before the pane
  mounts, open their board through `pendingCanvas` exactly as before.

### D5 · The vault switch names a conflicted board

`switchVault(to:ask:)` keeps its signature, its preflight, its re-entry guard and its early return
for the same vault or no vault. For a different vault, after the preflight:

1. **Settle the board.** `openBoard.settleForTermination()` writes an edit still inside the ~1 s
   debounce, into the vault it belongs to. A write refused now enters the question. This is ADR-0089
   §D2's reasoning, applied to the switch.
2. **Build the review with the board.** The review is
   `QuitReview(columns: columns, board: openBoard.quitConflict)`. The diary is not passed: the SPEC
   leaves the diary at a switch out of scope.
3. **«Annulla»** cancels with no reveal, as the switch already does.
4. **«Salva» / «Salva tutto»** saves the notes through `saveForQuit`, which never writes the board
   (ADR-0089 §D5). After the `await`, the session is compared again, as today, and the review is
   read again with the board. Whatever is left cancels the switch: unsaved notes, and a board that
   is still conflicted.
5. **«Non salvare»** covers what the question showed, through `uncoveredWork(in:)` (ADR-0089 §D4).
   A board that is conflicted now and was not in the snapshot, or has changed since, cancels. A
   covered board lets the switch go on. `open(_:)`'s `detach()` then drops it without writing,
   which is ADR-0054 §D5's last word, and its existing loss line records what was dropped.
6. **A cancel** records one line per kind of item left:
   - the notes' existing line, when notes are left;
   - `Apertura di un'altra cartella note annullata: la board «B» ha un conflitto di salvataggio non
     risolto`, when the board is.

   It then reveals the first item in ADR-0089 §D6's order: the board through D6's hook, a note
   through `revealTab` as today.

**The words** follow ADR-0089 §D3, with the switch's own:

- the message: `Salvare le modifiche alla board «B» prima di aprire un'altra cartella note?`;
- the switch's existing sentence on what not saving loses;
- the board sentence, with the switch's clause.

The board and diary sentences put their `staying` clause mid-sentence
(`QuitReview+Conflicts.swift:21-27`). The switch's `staying` word opens a sentence: «La cartella
note resta aperta». `QuitReview`'s private `Words` therefore gains a mid-sentence form:

- for the quit, «Pergamenum resta aperto», unchanged, so every quit string stays byte-identical;
- for the switch, «la cartella note resta aperta».

`QuitReview.Board` gains `leftProblem(for:)`. The existing `leftProblem` is its quit case. These
strings are gate G2.

The first launch, and a switch with no vault open, still go straight to `open(_:)` and ask nothing.

### D6 · The switch reveals the board through a declared hook

`VaultController` gains `@ObservationIgnored var revealOpenBoard: (() -> Void)?`. It has the shape
of `reopenMainWindow` and `didChangeExternally`: declared on the facade, nil in every test that does
not set it, wired once in production.

`PergamenumApp`'s window `.onAppear`, where `appDelegate.vault` is set
(`PergamenumApp.swift:368-373`), sets it to call `AppDelegate.revealBoardAfterCancelledQuit()`
(`AppDelegate+QuitReveal.swift:25`). A cancelled switch therefore reveals exactly as a cancelled
quit does: the main window, then the Workspace pane, then the keyboard restore. The restore does
nothing when nothing was resigned (`QuitFocus.restore`). The facade imports no AppKit and never
reaches for `NSApp.delegate`.

### D7 · What the new lifetime makes obsolete

- **The quit's compensating line goes.** `QuitCoordinator.showUncovered` no longer records the
  board's `leftProblem`. A reveal that switches away from a covered conflicted board no longer
  destroys it (D3), so there is no loss to report. The board stays conflicted, and the next quit
  names it again.
- **ADR-0089 §D6's order stays, with a different reason.** The order is still the board, the notes,
  the diary, the schede. The board no longer comes first because any other reveal destroys it. It
  comes first because it is the item listed first, and §D6 decides one order for both the list and
  the reveal. The doc comment on `QuitReview.firstReveal(board:notes:diary:schede:namingTab:)` says
  so.
- **The comments that describe the old lifetime are corrected:**
  - `WorkspaceView`'s disappear handler (`WorkspaceView.swift:102-107`), the comment R-10 names;
  - `VaultController.openBoard` and `openBoardPath`;
  - `attach`, `detach`, `WorkspaceController.vault` and `settleForTermination()`;
  - the header of `QuitReview+Conflicts.swift` and the doc comment of `QuitCoordinator.lastCheck`;
  - `NavigationHistory.swift:20-24` on `workspaceBoard`, and `WindowPlace.swift:31-36`;
  - the headers of `Tests/QuitTestSupport.swift` and `Tests/WorkspaceFitOnOpenHostedTests.swift`.

### D8 · Folder verbs refuse while the open board has unsaved edits under the folder (gate G1)

A kept board can now sit off screen while another pane renames, moves or trashes a folder that
holds its `.canvas`. The Note pane, the Contenitore and Pratiche all reach `renameFolder`,
`trashFolder` or `moveItems` with a folder. The file moves, `board` keeps naming the old path, and
neither banner verb can read it (fact 2). The conflict becomes unresolvable: the shape ADR-0060
closed for the Workspace's own verbs with `canLeaveOpenBoardForVerb()`.

The decision:

- `canOperateOnFolder(_:)` is the one guard all three verbs already pass. After its dirty-tab check
  it also refuses while `openBoard.hasUnsavedChanges` (pending or conflicted) and the open board
  lies inside the folder. It records the board's own sentence, not the note's.
- `refusal(forAll:)` answers the sentence that was actually recorded. Today it always answers the
  note's sentence for a refused folder (`VaultController+Move.swift:173`).
- The Workspace's own verbs do not change. `settleForVerb()` flushes or refuses first, so for a
  board whose flush lands the guard never fires twice on their path. `settleForVerb()` refuses only
  `.conflicted`: a flush whose write fails leaves the board `.pending`, and the folder guard then
  refuses the verb with the board's sentence. That is the safe direction, since the file stays
  where the unsaved edits point.
- A saved board is never in the way: a saved board off screen has been released (D3).
- `refusal(forAll:)` asks before the batch's `await`, and a batch that awaits a note move before
  it moves a folder leaves a window where the check is only a filter. Named residual,
  implementation notes.

If G1 is declined, D8 is dropped and the stranded conflict becomes a named residual of this record,
filed as its own ledger entry.

### D9 · What stays as it was

- **ADR-0054 §D5.** Nothing is written over the other writer, nothing is discarded without a
  choice, and neither a window close nor a pane switch is refused over a conflict.
- **ADR-0060.** `load(board:)` and `select(_:)` still refuse to leave a conflicted board. A history
  step or a `pergamenum://canvas` route to another board, while a kept board is conflicted, is
  refused with that same line. This is today's behaviour with the pane on screen. The route is
  consumed, not parked again, and `openRoute` resolves its card only on the board it opened, so a
  refused route selects nothing on the kept board and reports no missing card. SPEC R-08's "open
  the same boards as before" therefore holds except while a board is kept conflicted: before this
  record a cold pane had a fresh controller and no board to refuse from.
- **ADR-0089 for the quit.** The review, the words, the coverage, the caps and the order are the
  same. The quit now reaches the board whichever pane is showing.
- **The rest.** The diary, «Chiudi la colonna», the 10 s and 2 s caps, every on-disk format,
  schema, frontmatter key and protected interface. `perg` and `pergamenum-mcp` compile none of the
  files this changes.
- **Not added.** Zoom and pan are not remembered per board, and no board is reopened at launch.
- **No GUI test.** The leave is driven through `enterPane()`/`leavePane()` and the hosted-view
  harness, the switch through its injectable `ask`.

## Alternatives considered

1. **A separate app-level holder**, `@State` in `PergamenumApp` beside `DiaryController`. Rejected
   by the SPEC: one window and one vault give it nothing to hold that `VaultController` does not.
   The quit and the switch already reach the board through `VaultController`. A second owner would
   need wiring in both directions and its own observer of vault changes, and "an observer must be
   alive when the vault changes" is the condition that lost the board.
2. **Move the `@State` up to `RootView`.** Rejected. It is still a view lifetime, ended by a window
   close, and attach and detach would still depend on a mounted view.
3. **Create the controller lazily, on the first visit to the pane.** Rejected. `@Observable` does
   not support `lazy`, and an optional created on demand brings back a "no controller" state that
   the quit, the switch and the derived path would each have to handle. The eager cost is one empty
   controller per `VaultController`.
4. **Keep every board on a leave.** Rejected by the SPEC. A clean board kept in memory goes stale
   (fact 3), and its next edit raises a conflict nobody made.
5. **Refuse the pane switch while the board is conflicted.** Rejected by the SPEC. It cannot cover a
   window close, and it revisits ADR-0054 §D5.
6. **Decide the release from `navigation.pane`, read after the flush.** Rejected. The controller
   does not know the navigation, so the view would have to hand it a closure. The SPEC drives a
   re-entry through the controller's own leave step, and a count the controller owns supports that
   with no view at all.
7. **An `async` leave, with a token re-checked after the write.** Rejected. The write is synchronous
   (fact 1). An `async` leave started from `onDisappear` runs after the view is gone, with nothing
   awaiting it: the `willTerminateNotification` shape `.claude/rules/vault-writes.md` warns
   against.
8. **Four other ways to reveal the board after a cancelled switch.** All rejected:
   - A required `reveal` parameter on `switchVault`. About thirty calls in `VaultSwitchTests.swift`
     pass `ask` as a trailing closure, and a new trailing parameter changes which closure that
     syntax binds to.
   - Returning a reveal for the caller to act on. Three callers (`VaultOpenPanel`,
     `VaultCommands`, the launch task) would each have to dispatch on it.
   - Routing through `pendingCanvas`. The route reopens the board through `load(board:)`, which
     refuses a conflicted board and records a refusal line for a board that is already open.
   - Reaching `NSApp.delegate` from the facade. It is an AppKit dependency nothing declares, and a
     test cannot replace it.
9. **A discard door for «Non salvare» at a switch**, so that `detach()` records no loss line.
   Rejected. A door that throws away a conflicted board's edits is one more way to lose them, and
   the line `detach()` records is true.
10. **Keep the stored mirror and clear it on a leave.** Rejected. It is a second copy of a value the
    controller already holds, and it has already gone stale once.
11. **Leave the board out of the switch question** and rely on `detach()`'s loss line. Rejected by
    the person at the SPEC interview, against the recommendation; registered here, not reopened.
12. **For D8, accept the stranded conflict and name it.** The fallback if G1 is declined.

## Consequences

### Positive

- A conflicted board survives a pane switch and a cancelled reveal. The quit names it on every
  termination, the red button included, and the vault switch names it too. ADR-0089 §D7's residual
  is closed.
- `WindowPlace.destination` stops reporting a board that is not on screen.
- A draft open at a pane switch is committed instead of dropped.
- The quit no longer records a loss line for a loss that no longer happens.

### Negative

- `VaultController` now owns a Workspace object, window-level state beyond `columns`. ADR-0066 called
  the weak reference acceptable because it served the quit alone. The strong one serves the quit,
  the switch and the window's history, and it is the price of R-01.
- A folder verb from the Note pane, the Contenitore or Pratiche can now be refused because of a
  board the person is not looking at (D8). The sentence names the board.
- A kept board is fitted again on re-entry.
- A board kept `.pending` after a failed write is named by neither the quit nor the switch (D3).
  Each retries the write and, when the retry fails too, drops the edits with only the write-failure
  line. Named residual, to be filed (ledger entry filed after the merge by /project-tasks);
  closing it widens ADR-0089 §D2.
- Every `VaultController` a test builds also builds an empty `WorkspaceController`, and every
  `open(_:)` attaches it to a `CanvasStore`, which does no file I/O at construction beyond resolving
  the root's symlinks.
- If SwiftUI ever delivered an `onAppear` without its `onDisappear`, the count would stay above zero
  and a clean board would be kept instead of released. That failure is the safe direction: a kept
  board still saves with `expecting:`, so a stale one turns conflicted rather than overwriting.

### Neutral

- At a switch, «Non salvare» over a conflicted board records `detach()`'s existing loss line in the
  new vault's list, and it does not come back with the old vault (implementation notes, Residual).
- Reopening the same vault keeps the board and its conflict but points it at the new
  `ThumbnailStore` instance (`useThumbnails(_:)`), so the board renders through the vault's current
  cache. Its in-memory renders start empty, as they did when a cold pane attached the new instance.
- Every quit string is byte-identical. For a review without a board, every switch string is
  byte-identical too.

## References

- `SPEC.md` (PG-392, #918), R-01 to R-10.
- ADR-0089 §D1 to §D8 and its implementation notes; ADR-0066 §D1, §D2, §D5; ADR-0054 §D5, §D7;
  ADR-0060; ADR-0052; ADR-0073 §D1, §D7 and G-c.
- `Sources/Features/Workspace/WorkspaceView.swift:33, 97-127, 143, 201-213`.
- `Sources/Features/Workspace/WorkspaceController.swift:144-206, 267-333`;
  `WorkspaceController+Lifecycle.swift:97-120`; `WorkspaceController+Saving.swift:29-125`.
- `Sources/App/VaultController.swift:74-81, 159-165, 211-311`; `VaultController+VaultSwitch.swift`;
  `VaultController+Folders.swift:27-44`; `VaultController+Move.swift:169-178`.
- `Sources/App/QuitCoordinator.swift:146, 157, 320-384`; `QuitReview.swift:298-325`;
  `QuitReview+Conflicts.swift`; `AppDelegate+QuitReveal.swift`; `PergamenumApp.swift:368-373`;
  `WindowPlace.swift:24-44`; `NavigationHistory.swift:20-25`.
- Plan: `docs/plans/pg-392-board-controller-vault-lifetime.md`.

## Implementation notes

The landing evidence for the status line is written at the merge.

**Gate outcomes (2026-10-08).**

- **G1, approved.** §D8 is in: `VaultController.folderRefusal(_:)` answers the sentence,
  `canOperateOnFolder(_:)` records it, and `refusal(forAll:)` records and returns the same one.
- **G2, approved as written.** The switch's message, board sentence and cancel line, the column
  close's cancel line and the folder refusal are the plan's text, pinned literally in
  `VaultSwitchBoardTests` and `BoardFolderVerbGuardTests`. Every quit string is byte-identical.
- **G3, approved.** One dated sentence in `docs/20260811_Pergamenum_SpecApp.md` §5, beside
  ADR-0089's.
- **G4, confirmed.** Four existing tests changed on purpose, none disabled (plan, Task 2).

**Measured.**

- **`HostedView` delivers `onDisappear`.** A plain view in the harness gets both `onAppear` and
  `onDisappear` (`QuitBoardLifetimeHostedTests.theHarnessDeliversOnDisappearWhenAViewLeavesTheTree`).
  `WorkspaceView`'s own `.onDisappear` reaches `leavePane()`:
  `aCleanBoardIsReleasedToTheEmptyStateOnLeave` sees `board == ""` after the pane is hidden.
- **A pending board whose write fails is kept on a leave.** `CanvasStore.save` throws
  `NSCocoaErrorDomain 513` in a read-only folder, `attemptSave` records its line and leaves
  `.pending`, and `leavePane()` keeps the board (`aPendingBoardWhoseWriteFailsIsKeptOnLeave`, plan
  Task 1 test 14, kept).

**Residual.**

- **A failed pending board is kept but not named** (§D3). `QuitReview+Conflicts.swift`'s
  `quitConflict` guards on `.conflicted`, so the quit's review and the switch's review both leave
  it out. The quit retries the write in `settleForTermination()`; the switch retries it there and
  again in `rebindBoard` → `detach()`. When the retries fail, the edits are dropped with only
  `attemptSave`'s write-failure line, and
  `detach()`'s loss line, read for `.conflicted`, does not fire. To be filed (ledger entry filed
  after the merge by /project-tasks); naming it at the quit and the switch is an ADR-0089 §D2
  decision, not taken here.
- **The switch's loss line lands in the new vault's list** (§D2, Neutral). `rebindBoard` runs
  after `session = newSession`, so the line `detach()` records for a conflicted board of vault A,
  dropped by «Non salvare», is in B's problems and is not there when A opens again. Not moved:
  problems live on the session in memory (`VaultSession.problems`), so detaching before the
  assignment would record the line in A's session, which is released by that same assignment and
  shown nowhere. `VaultSwitchBoardTests.nonSalvareLetsTheSwitchGoAndWritesNothingToTheBoardFile`
  pins B's list on purpose (plan, Task 4). Keeping the line with A needs per-vault problem storage,
  outside this record.
- **A batch move's board check can be a filter** (§D8). `refusal(forAll:)` runs before
  `await session.moveItems`, and nothing asks again after it. `VaultSession` is `@MainActor`, and
  its folder move is synchronous, so a batch whose folders come before any note has no suspension
  between the check and the move. A `.note` item ahead of a `.folder` item does: `moveNote` is
  awaited, and a board edited during that suspension, inside a folder the batch moves next, is
  left naming a path that has gone. The dirty-note check that was there before has the same shape.
  Asking again after the `await` is too late, since the folder has already moved. Asking before
  each folder needs a check handed into `VaultSession.moveItems`, which the connectors share
  (ADR-0007), and that is outside this record. `renameFolder` and `trashFolder` are synchronous
  and are not affected.
- **The undo's settle is a filter for the move it precedes** (review sweep, 2026-10-10).
  `attemptInverse` settles and checks synchronously inside `undo()`, but the moves run later, in
  `performInverse`, behind a `Task { @MainActor in … }` hop and one `await session.moveItems` per
  destination group. A board edited in that window, after the settle and before its group moves
  (or opened then, when the step carries a folder that holds it), is moved with a pending edit,
  and the autosave can land on the path just left (ADR-0022 §F10). It has the shape of the batch
  residual above: asking again after an `await` is too late for a group already moved, and asking
  before each group needs a check handed into `VaultSession.moveItems`, which the connectors share
  (ADR-0007). The window is one run-loop turn plus the moves themselves; it is named, not closed.
- **A `pergamenum://canvas` route refused by a kept conflicted board is consumed** (§D9). It is
  not parked again: a parked route would make `WindowPlace.destination` name a board that is not
  on screen (§D4), and nothing would open it once the conflict is resolved while the pane stays
  mounted. The person gets ADR-0060's line, which says why and what to do.

**Verified in the review sweep (2026-10-10).**

- **The undo of a batch move can carry a `.board` ref, and the open board can be unsaved then.**
  `attemptInverse` rebuilds every item of the step with its forward kind, so the undo of a
  Workspace browser's board move hands `refusal(forAll:)` a `.board` ref that no
  `settleForVerb()` preceded. Edit ▸ Annulla reaches the window's `UndoManager` from any pane, so
  the step can run while the board just moved is pending inside the ~1 s debounce or kept
  conflicted. Fixed: `attemptInverse` runs `openBoard.settleForVerb()` first when a ref of the step
  carries the open board, the board itself or a folder that holds it (`carriesOpenBoard`, the
  folder-prefix rule `folderRefusal` uses), and asks nothing of an open board the step does not
  carry, so an unrelated conflicted board neither consumes the step nor records a line. The settle
  flushes a pending edit into the file inside the `undo()` call, and a conflicted board refuses the
  step with ADR-0060's line, registering nothing. A flush whose write fails leaves the board
  pending, since `settleForVerb()` refuses only a conflict: a folder that holds it is then refused
  by `folderRefusal`, and a `.board` ref is refused with the same frozen board sentence, so the
  file never moves away from unsaved edits that point at it. Once the moves have run, the undo
  follows the open board to where it landed through `followMove`, as the forward door in
  `WorkspaceView+FolderVerbs` does, so its next save is not aimed at a path that has gone; that
  gap was older than this record (`BoardMoveUndoSettleTests`). These checks run before the moves
  and are a filter, not a guard: see "The undo's settle is a filter" under **Residual.** above.
- **The note tree's drop destinations never receive a board.** `NoteListPane.performMove` and
  `NoteTreeRow`'s `.dropDestination(for: VaultItemDrag.self)` accept any payload, but a board row
  is drawn only by the Workspace browser, inside `WorkspaceView`, and `RootView`'s detail is a
  `switch pane` in the app's one `Window`: the note tree and the Workspace browser are never on
  screen together. The note tree's own rows build only `.note` and `.folder` items
  (`NoteListPane.swift:379`, `NoteTreeRow.swift:109, 227`), and a folder that holds the kept board
  is refused by §D8. Verified non-issue; no settle added there.
- **The `revealOpenBoard` wiring is not testable in the unit suite.** It is set in the window's
  `.onAppear` in `PergamenumApp`, and `AppDelegate.revealBoardAfterCancelledQuit()` drives
  `NSApp`'s windows; neither runs without the app's scene on screen. Hand check R-06 (plan, "Hand
  checks") covers the real path. The facade side, a cancelled switch calling `revealOpenBoard`, is
  pinned in the unit suite (`VaultSwitchBoardTests`, `BoardLifetimeCoverageTests`).

**Departures.**

- **`detach()` calls `flushPendingSave()` unconditionally** rather than "flush unless conflicted".
  The behaviour is the same: `save()` already returns on `.conflicted` (ADR-0054 §D5). The conflict
  is read after it, as §D2 decides.
- **`QuitCoordinator.showUncovered` is deleted**, not reduced to one line: both its callers now
  call `show(left.firstReveal())`.
- **`QuitReview.sentences` takes the occasion's `Words`** instead of a `staying:` string, so it
  can hand `stayingClause` to the board and diary sentences and `staying` to the notes'.
- **The switch's cancel lines and reveal** are a private `recordSwitchCancel(leaving:)` in
  `VaultController+VaultSwitch.swift`, beside `switchVault(to:ask:)`.
- **`folderRefusal(_:)` ignores an empty `board`**, so an unsaved state with nothing open can
  never refuse a folder at the vault root.
- **`detach()` also puts the tool back to `.select` and unlocks it**, as a releasing
  `leavePane()` does: the controller outlives a vault switch now, and an armed drawing tool would
  otherwise draw on the next vault's first board.
- **Reopening the same vault calls `useThumbnails(_:)`**, a setter that re-points the board at the
  new `ThumbnailStore` and touches nothing else (§D2).
- **The red phase's own departures** (`.later` for «Salva» at the quit, `store?.root` compared
  for a value-type store, the extra step 0 pin, boards at the vault root in `WindowPlaceTests`)
  are in the plan's "Build notes".
