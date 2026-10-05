**Requirement set:** `docs/archive/specs/pg-336-conflicted-board-diary-at-quit.SPEC.md` (root `SPEC.md` while this was built)

# PG-336 — A conflicted board or diary is asked about at quit: implementation plan

- **SPEC:** `SPEC.md` at the repository root, "A conflicted board or diary is asked about at quit
  (PG-336)", Status Approved (2026-10-05), R-01 to R-12. Its `## Decisions` and `## Constraints`
  are settled input. No task below reopens them. One fact the SPEC did not have bears on its reveal
  order. It is raised as gate G1 for the human to decide; this plan does not decide it silently.
- **ADR:** new, `docs/adr/0089-a-conflicted-board-or-diary-is-asked-about-at-quit.md`, status
  proposed, number pending G0. The architect's write scope does not reach `docs/adr/`, so the
  full text is returned to the orchestrator, which writes the file before Task 1. Read D3 (the
  words), D4 (what an answer covers) and D6 (the reveal order) before writing code. Those are the
  three a task can silently get wrong by writing the obvious version.
- **Governing ADRs, registered and not reopened:**
  - ADR-0073 §D1 to §D7: one door and one reply, an app-modal question with no timer while it is
    open, «Salva tutto» never writing a conflicted tab, the 10 s fail-safe cap, §D7's coverage
    rule. Also its departures 14 (keyboard back before the reveal) and 17 (the diary settles before
    the notes).
  - ADR-0054 §D5: a conflicted board is resolved only by a choice on its banner, and a window
    close is not refused over it.
  - ADR-0057 §D6: the diary's conflict state, with one door into it.
  - ADR-0060 §D2: the 2 s fail-open diary cap.
  - ADR-0066 §D5: `settleForTermination()` skips a conflicted board.
  - ADR-0067: the landed-change door, untouched.
- **Baseline.** The worktree is on `main` at `05fa8bb2`. `origin/main` is `0e2fd436`, one commit
  ahead, and the difference is `TODO.md` only. The index holds a previous chain's leftovers:
  - `SPEC.md` staged as renamed to `docs/archive/specs/pg-384-n1-seams.SPEC.md`;
  - `docs/plans/pg-384-n1-seams.md` staged as modified;
  - this chain's own `SPEC.md`, untracked.

  Before Task 1:
  1. Create the branch `fix/pg-336-conflicted-board-diary-at-quit` (Conventional Branch).
  2. Decide what happens to the staged PG-384 leftovers. This is a HITL decision, not a task.
  3. Merge `origin/main`. Never rebase, never force.
  4. Run `tuist install` once, then `tuist generate --no-open`.
- **Delivery:** one session, one PR. Two app files change, one app file is new, three test files
  are new, and five existing test files change only where they build a `QuitCoordinator` or share
  helpers.

## SPEC decisions registered (settled, not reopened)

- **Option B.** A conflicted board or diary day joins the quit review. Option C (a conflict copy)
  and option A (a silent exit with a durable record) are rejected.
- **The conflicted note's rule applies to both items.**
  - It is named in the question.
  - «Salva» and «Salva tutto» never write it. They cancel and show its banner.
  - Only «Non salvare» lets it go.
  - Nothing is written over the other writer's bytes.
- **«Non salvare» is a plain discard.** No safety copy is made anywhere.
- **The three buttons stay** when only a conflicted board or diary is in the review.
- **Only the quit passes the two items.** The vault switch and «Chiudi la colonna» build the review
  without them, as with the Contenitore schede.
- **This extends ADR-0054 §D5 and ADR-0066 §D5 and reverses neither.**
  - The board is still not flushed over a conflict at quit.
  - `detach()` is untouched.
  - The ADR extends ADR-0073 and ADR-0066 §D5 and amends none.
- **Constraints.**
  - One reply, one door (`QuitCoordinator`).
  - No timer while the question is open.
  - The 10 s and 2 s caps are unchanged.
  - No format, schema, frontmatter key or protected interface changes.
  - Nothing in `Sources/Core`.
- **Test seams.**
  - Existing seams only: the pure `QuitReview` and the closure-driven `QuitCoordinator`.
  - The controllers' observable save state.
  - No GUI test.

## What reading the current tree added

1. **The open board's controller lives and dies with the Workspace pane.**
   - `WorkspaceView` holds `@State var workspace = WorkspaceController()`.
   - `RootView`'s `detail` is a `switch pane`.
   - `VaultController.openBoard` is `weak`.

   Leaving the pane, or closing the window, destroys the controller. `.onDisappear` skips the flush
   for a conflicted board (`WorkspaceView.swift:96-105`). `detach()` runs only when the vault root
   changes (`reattachWorkspace`, `WorkspaceView.swift:200`), so a pane switch drops a conflicted
   board's edits with no problem line. The comment at `WorkspaceView.swift:97-100` says
   `detach()` reports the loss, which is true only for a vault change. Three consequences:

   - The quit can name a conflicted board only when Cmd+Q, «Esci», a logout or a restart arrives
     while the Workspace pane is on screen. With the red button, the window has already closed and
     the board's controller is gone. That is a window close, which the SPEC puts out of scope.
   - A cancel that shows the Note pane before the board destroys the board the question just
     protected. The SPEC's order, notes then board, does exactly that when both are unresolved
     (G1).
   - The pane-switch loss is a pre-existing silent loss outside this SPEC (G2).
2. **The diary controller is app-level** (`PergamenumApp.init`, `_diary = State(initialValue:)`).
   `load()` and `show(_:)` keep a conflict, so the Diario pane can be shown after any other pane
   and still carries its banner. Its place after the notes is safe.
3. **A conflicted diary already makes today's quit reply `.later`.** It is `!isSettled`, so the
   diary phase starts. `settle()` returns at once, because `performWrite` returns on
   `.conflicted`, and the reply is `reply(true)`. Today's loss is silent under a `.later`, not a
   `.now`. «Non salvare» keeps that path, so with a conflicted diary its reply is `.later` followed
   by `true`.
4. **«Salva» and «Salva tutto» already end in `notesSaved`**, which re-reads `current`. Once
   `current` carries the two conflicts, R-06 follows from the existing rule that «Salva» covers
   nothing it did not save. Only the problem line needs work: it assumes every leftover is a note,
   and with only a board left it would record «note non salvate: » followed by an empty list.
5. **ADR number.** The highest ADR on `origin/main` is 0080, so `docs/adr/README.md` rule 1 gives
   0081. But 0081 to 0087 are already assigned:

   - to N2–N5 by `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` (the table at lines 53-56);
   - to `PG-385` to `PG-388` in `TODO.md`.

   An unmerged worktree also holds untracked drafts numbered 0081 to 0088 (G0).
6. **`QuitCoordinator.init` is called in five places**, and this chain changes its signature.
   `rg -n "QuitCoordinator\(" Sources Tests` finds:

   - `Sources/App/PergamenumApp.swift:78`
   - `Tests/QuitCoordinatorTests.swift:40`
   - `Tests/QuitGapTests.swift:23`
   - `Tests/QuitVanishedSchedaTests.swift:22`
   - `Tests/QuitVaultSwitchTests.swift:211`
7. **`revealContenitoreAfterCancelledQuit` does not give the keyboard back.** Departure 14 was
   applied to the Note pane only. Task 4 routes all four pane reveals through one helper, which
   closes this as a side effect. It is not an R-id; ADR D6 records it.

## Gates (GATE 1/2, before `/build`)

- **G0 — ADR number.**
  - Recommended: 0089, which is free on every ref and in every draft known on 2026-10-05.
  - Alternative: 0081, rule 1 read literally. That forces the roadmap and `TODO.md` to renumber
    N2–N5.
  - Whichever is chosen, check again immediately before the merge (`docs/adr/README.md` §1).
- **G1 — Reveal order and listing order.** This departs from the SPEC's literal order.
  - Recommended: the board, then the notes, then the diary, then the Contenitore schede, for both
    the cancel's reveal and the question's list. The board's controller dies with its pane (finding
    1), so any other order destroys the conflicted board the question just protected.
  - The SPEC's order is the notes, then the board, then the diary.
  - If the SPEC's order is kept, the change is limited to `QuitReview.firstReveal` (static), the
    order of `copy(for:)`'s items, Task 1's order cases and Task 2's `annulla*` tests. ADR D6 then
    records the loss as accepted.
- **G2 — Residual to file, not fixed here.** A conflicted board is lost without a problem line on a
  pane switch or a window close. The red button with a conflicted board is that window-close path,
  so R-01 holds for Cmd+Q, «Esci», logout and restart from the Workspace pane, and the red button
  is covered for the diary only.
  - Recommended: a P2 ledger entry. Its remedy is to lift `WorkspaceController` to the vault's
    lifetime, in its own ADR.
  - The orchestrator files it. Task 6 then writes its id into ADR D7.
- **G3 — Wording.** The frozen strings in Task 1, in Italian, follow the conflicted note's
  sentence. Approve them or change them before Task 1 freezes them in tests.
- **G4 — SPEC §5 amendment.** Recommended: yes, one dated sentence (Task 6). The behaviour is
  user-visible, and §5 is where a reader finds the quit rule.

### Task 1 — Pure review: the two conflict items, their words, coverage and reveal order (R-01, R-02, R-04, R-05, R-06, R-08)
Owner: tester
Files: Tests/QuitReviewConflictTests.swift, Sources/App/QuitReview.swift, Sources/App/QuitReview+Conflicts.swift
Tests: QuitReviewConflictTests.swift, QuitReviewTests.swift
Signatures:
- QuitReview.init — init(columns: [EditorColumn], vanishedSchede: [String] = [], failedSchede: [String] = [], board: QuitReview.Board? = nil, diary: QuitReview.DiaryDay? = nil)
- QuitReview.board — let board: QuitReview.Board?
- QuitReview.diary — let diary: QuitReview.DiaryDay?
- QuitReview.Board — struct Board: Equatable, Sendable { let path: String; let document: CanvasDocument; var name: String { get } }
- QuitReview.DiaryDay — struct DiaryDay: Equatable, Sendable { let day: CalendarDate; let prose: String; let entries: [DiaryEntry] }
- QuitReview.Board.leftProblem — var leftProblem: String { get }
- QuitReview.DiaryDay.leftProblem — var leftProblem: String { get }
- QuitReview.Reveal — enum Reveal: Equatable, Sendable { case board, note(NoteTab.ID?), diary, scheda(String?) }
- QuitReview.Uncovered — struct Uncovered: Equatable, Sendable { let notes: [Entry]; let board: Board?; let diary: DiaryDay?; var isEmpty: Bool { get }; func firstReveal() -> Reveal? }
- QuitReview.uncoveredWork — func uncoveredWork(in now: QuitReview) -> QuitReview.Uncovered
- QuitReview.firstReveal — func firstReveal(namingTab: Bool) -> QuitReview.Reveal?
- QuitReview.firstReveal(board:notes:diary:schede:namingTab:) — static func firstReveal(board: Board?, notes: [Entry], diary: DiaryDay?, schede: [Scheda], namingTab: Bool) -> Reveal?
- WorkspaceController.quitConflict — var quitConflict: QuitReview.Board? { get }
- DiaryController.quitConflict — var quitConflict: QuitReview.DiaryDay? { get }
Red: yes

The tester declares every symbol above. Two kinds of change go in `QuitReview.swift`: the two stored
properties and the two init parameters. The parameters are assigned for real, because assignment
is plumbing, not behaviour. Everything else goes in the new `Sources/App/QuitReview+Conflicts.swift`
as neutral stubs, so the target builds and the tests fail on their assertions:

- `uncoveredWork` returns an empty `Uncovered`;
- both `firstReveal` return `nil`;
- `leftProblem` returns `""`;
- both `quitConflict` return `nil`.

`isEmpty` and `copy(for:)` stay untouched. `Board.name` is real: the file name without `.canvas`.

`Tests/QuitReviewConflictTests.swift` is pure, like `QuitReviewTests.swift`. It builds the columns
by hand (copy that file's two `private` helpers) and the items by memberwise init. Cases:

- **R-01/R-02.** A review with only a board, or only a diary, is not empty.
  `QuitReview(columns:)` with neither keeps `board == nil`, `diary == nil` and today's `isEmpty`.
- **R-04, the words.** These are frozen strings (G3). In them, `X` is the save label and the date
  is `testDay.italianForm`.
  - Lone board, message: `Salvare le modifiche alla board «Bacheca» prima di uscire?`, with the
    save label «Salva».
  - Lone diary, message: `Salvare le modifiche al diario del giorno 11/08/2026 prima di uscire?`
  - List lines: `la board «Bacheca»` and `il diario del giorno 11/08/2026`. A note keeps
    `«Titolo»` and a scheda keeps `«nome»`.
  - Board sentence, one paragraph: `La board «Bacheca» è cambiata anche su disco: con «X»
    Pergamenum resta aperto per farti scegliere quale versione tenere, con «Non salvare» le sue
    modifiche vanno perse.`
  - Diary sentence, one paragraph: `Il diario del giorno 11/08/2026 è cambiato anche su disco: con
    «X» Pergamenum resta aperto per farti scegliere quale versione tenere, con «Non salvare» le sue
    modifiche vanno perse.`
  - The counted message joins its parts as «a, b e c», in the item order: board, notes, diary,
    schede (G1). Board plus two notes plus diary gives `Salvare le modifiche a 1 board, 2 note e 1
    diario prima di uscire?` with «Salva tutto». Board plus one note gives `… a 1 board e 1 nota …`.
    Two parts keep today's `1 nota e 1 scheda` byte for byte.
  - The list lines and the sentences follow the item order too: board, then the notes' lines and
    sentences as today, then diary, then schede.
- **SPEC edge.** A dirty tab on `Diario/20260811.md` plus the diary item names both: `«20260811»`
  and `il diario del giorno 11/08/2026`.
- **R-05, the order (G1).**
  - Board, notes, diary and schede together give `.board`.
  - Notes and diary give `.note(nil)` with `namingTab: false`, and `.note(<first tab>)` with
    `true`.
  - Diary and schede give `.diary`.
  - Schede alone give `.scheda(<first path>)`.
  - An empty review gives `nil`.
  - `Uncovered.firstReveal()` follows the same order and always names the tab.
- **R-06.** The problem lines are frozen:
  - `Uscita annullata: la board «Bacheca» ha un conflitto di salvataggio non risolto`
  - `Uscita annullata: il diario del giorno 11/08/2026 ha un conflitto di salvataggio non risolto`
- **R-08, coverage.** These cases cover the board:
  - The same board (same path and document) in the snapshot and now is covered.
  - A board absent from the snapshot and present now is uncovered.
  - A board whose document differs is uncovered.
  - A board in the snapshot and gone now yields nothing.

  These cases cover the diary:

  - A changed `prose`, `entries` or `day` is uncovered.
  - The same day is covered.

  `Uncovered.notes` equals `uncovered(in:)` for the same pair.
- **The vault-switch and column-close copies are unchanged** for a review that has neither item.
  They are identical to what `QuitReviewTests` already asserts. Do not edit `QuitReviewTests.swift`.

### Task 2 — Coordinator: the question, the three answers, the last check, the reveals and the caps (R-01, R-02, R-03, R-05, R-06, R-07, R-08, R-10, R-11)
Owner: tester
Files: Tests/QuitConflictTests.swift, Tests/QuitTestSupport.swift, Tests/QuitCoordinatorTests.swift, Tests/QuitGapTests.swift, Tests/QuitVanishedSchedaTests.swift, Tests/QuitVaultSwitchTests.swift, Sources/App/QuitCoordinator.swift, Sources/App/PergamenumApp.swift
Tests: QuitConflictTests.swift, QuitCoordinatorTests.swift, QuitGapTests.swift, QuitVanishedSchedaTests.swift, QuitVaultSwitchTests.swift
Signatures:
- QuitCoordinator.init — init(vault: @escaping @MainActor () -> VaultController?, diary: @escaping @MainActor () -> DiaryController?, contenitore: @escaping @MainActor () -> ContenitoreController?, commitEditing: @escaping @MainActor () -> Void, ask: @escaping @MainActor (QuitReview) -> QuitReview.Answer, reply: @escaping @MainActor (Bool) -> Void, reveal: @escaping @MainActor (NoteTab.ID?) -> Void, revealContenitore: @escaping @MainActor (String?) -> Void, revealBoard: @escaping @MainActor () -> Void, revealDiary: @escaping @MainActor () -> Void, sleep: @escaping @MainActor (Duration) async -> Void, saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)? = nil)
- quitConflictedBoard — @MainActor func quitConflictedBoard(_ vault: borrowing TemporaryVault, in controller: VaultController) throws -> (board: WorkspaceController, path: String)
- quitConflictedDiary — @MainActor func quitConflictedDiary(in controller: VaultController, root: URL) async throws -> DiaryController
- AppDelegate.revealBoardAfterCancelledQuit — private func revealBoardAfterCancelledQuit()
- AppDelegate.revealDiaryAfterCancelledQuit — private func revealDiaryAfterCancelledQuit()
Red: yes

**Signature work.**

- The tester adds `revealBoard:` and `revealDiary:` to `QuitCoordinator.init`. They are stored and
  not yet called. Their position is after `revealContenitore:` and before `sleep:`. They are
  required, not defaulted, because the SPEC asks for that, like `revealContenitore`.
- `PergamenumApp.swift:78` passes them through the two private methods above. Their bodies stay
  empty until Task 4.
- The four test construction sites from finding 6 gain the two arguments and nothing else. No
  assertion changes (R-10). `QuitCoordinatorTests`'s `QuitProbe` may record them in two new arrays
  that no existing test reads.

**Shared helpers in `Tests/QuitTestSupport.swift`.** Neither helper changes any existing helper.

- `quitConflictedBoard` follows `WorkspaceLifecycleTests.swift:528`'s `conflictedBoard` shape:
  1. Call `createBoard(named: "Bacheca", in: "")`.
  2. `attach(to:vault:)` the controller, which sets `controller.openBoard`.
  3. Open the board and call `addStickyNote`.
  4. Save a diverged document through a second `CanvasStore`.
  5. Call `flushPendingSave()`.
  6. `#require` that the board is `.conflicted`.

  The caller keeps the returned controller alive: `openBoard` is weak.
- `quitConflictedDiary` follows `DiaryConflictTests.swift:20`'s `makeConflictedDiary` with no
  seed file:
  1. Build `DiaryController(vault:)` and call `show(testDay)`.
  2. Hold the first write at `.willWrite` through `testOnlyWriteHook` and a `Gate`.
  3. Append to `prose`, then call `flush()`.
  4. Write `Diario/20260811.md` from outside.
  5. Open the gate.
  6. `#require` that the diary is `.conflicted`.

  Taking `root: URL` rather than the vault keeps it callable after `quitController` has borrowed
  the vault.

**`Tests/QuitConflictTests.swift`.** It uses its own private probe, which records every reveal in
one ordered log, `enum Shown: Equatable { case note(NoteTab.ID?), board, diary, scheda(String?) }`,
plus `replies`, `asked`, `slept`, `sleptWhenAsked` and per-duration gates (the
`QuitCoordinatorTests` shape). The vault and controller come from `quitController`. Every write
check compares the file's bytes before and after.

- **R-01.** A lone conflicted board is asked about once. `asked[0].board?.path` is the board's
  path, `asked[0].entries` is empty, and `sleptWhenAsked == []`. «Annulla» replies `.cancel`, and
  `shown == [.board]`.
- **R-02.** A lone conflicted diary is asked about. `asked[0].diary?.day == testDay`. «Annulla»
  gives `shown == [.diary]`.
- **R-03.** An attached board with an unsaved edit that is not conflicted is written by the settle.
  There is no question, the reply is `.now`, and `shown` is empty.
- **R-05 (G1).**
  - A board, a dirty note and a diary, answered «Annulla», give `shown == [.board]`.
  - A note and a diary give `shown == [.note(nil)]`, the `reveal(nil)` of today.
- **R-06.**
  - «Salva» on a lone conflicted board replies `.later` and `replies == [false]`. The board's bytes
    are unchanged and the problems contain `board.leftProblem`. No problem contains «note non
    salvate». `shown == [.board]`.
  - «Salva tutto» on a saveable dirty note plus a conflicted diary writes the note to disk and
    leaves the diary's bytes unchanged. `replies == [false]`, and the problems contain the diary's
    line but not the notes' line. `shown == [.diary]`.
- **R-07.**
  - «Non salvare» with a conflicted board, a conflicted diary and a dirty note replies `.later`,
    then `replies == [true]`. The board, the diary and the note are byte-identical. A recursive
    listing of the vault root, hidden files included, is identical before and after. `shown` is
    empty.
  - A lone conflicted board answered «Non salvare» replies `.now`.
- **R-08.**
  - `ask` adds a sticky note to the conflicted board, then returns «Non salvare». The reply is
    `.cancel`, `shown == [.board]`, and the bytes are unchanged.
  - `ask` appends to the conflicted diary's `prose`, then returns «Non salvare». The reply is
    `.cancel` and `shown == [.diary]`.
  - SPEC edge: a diary that is only pending at the question, with its write held on the gate,
    becomes conflicted during the diary phase. The reply is `.later`, then `replies == [false]` and
    `shown == [.diary]`.
  - SPEC edge: the same diary becomes conflicted while «Salva tutto» settles it before the notes.
    `replies == [false]`, `shown == [.diary]`, and the diary's problem line is recorded.
- **R-11.**
  - Every question above runs with `sleptWhenAsked == []`.
  - The «Salva tutto» case ends with `slept == [diaryCap, noteSaveCap]`.
  - After `openAllGates()`, `replies.count` stays 1.
- **Derivations.**
  - `quitConflict` is `nil` for a saved or pending board, for a controller with `board == ""`, and
    for a saved or pending diary.
  - It carries path and document for a conflicted board, and day, prose and entries for a
    conflicted diary.

### Task 3 — QuitReview: the items, the words, coverage and order; the two derivations (R-01, R-02, R-04, R-05, R-06, R-08, R-09)
Owner: coder
Files: Sources/App/QuitReview.swift, Sources/App/QuitReview+Conflicts.swift
Tests: QuitReviewConflictTests.swift, QuitReviewTests.swift, QuitReviewAlertTests.swift, QuitConflictTests.swift
Signatures:
- QuitReview.isEmpty — var isEmpty: Bool { get }
- QuitReview.copy(for:) — func copy(for occasion: Occasion) -> Copy
- QuitReview.uncoveredWork — func uncoveredWork(in now: QuitReview) -> QuitReview.Uncovered
- QuitReview.firstReveal(board:notes:diary:schede:namingTab:) — static func firstReveal(board: Board?, notes: [Entry], diary: DiaryDay?, schede: [Scheda], namingTab: Bool) -> Reveal?
- WorkspaceController.quitConflict — var quitConflict: QuitReview.Board? { get }
- DiaryController.quitConflict — var quitConflict: QuitReview.DiaryDay? { get }
Red: no

Make Task 1 green, and the derivation half of Task 2.

- **`isEmpty`** becomes true only when entries, schede, board and diary are all empty or nil. Its
  other readers, `VaultController+VaultSwitch.swift:65` and `+ColumnClose.swift:54`, build
  without the two items, so their result does not change (R-09).
- **`copy(for:)`** builds one ordered list of items. Each item has a singular phrase (`a «T»`,
  `alla board «B»`, `al diario del giorno D`), a list line and an optional sentence. The order is
  board, notes, diary, schede (G1). The single-item rule, the eight-line limit with «e altre K»,
  the save label and every existing note and scheda string stay as they are.
  `counted(notes:schede:)` generalises to four counts joined as «a, b e c». With two parts it is
  still «a e b», byte-identical.
- **`firstReveal`** (static) is the one place the order lives. `copy(for:)`'s item order must read
  the same sequence, so the cancel always shows the item the question named first (R-05's last
  sentence).
- **`uncoveredWork(in:)`**:
  - `notes` is `uncovered(in:)`;
  - `board` is `now.board` when it is non-nil and differs from `self.board`;
  - `diary` is the same rule for the diary.
- **`quitConflict`** returns `nil` unless `saveState` is `.conflicted`, and, for the board, unless
  `board` is non-empty. It copies `board`/`document`, or `day`/`prose`/`entries`.
- **Location.** The new types, their words and the two controller extensions live in
  `QuitReview+Conflicts.swift`, so `QuitReview.swift` (306 lines) stays under SwiftLint's
  400-line `file_length` warning. Everything is in `Sources/App` and Foundation-only, and nothing
  goes in `Sources/Core` or `sharedSources`.

### Task 4 — QuitCoordinator reads the conflicts, answers, checks and reveals; AppDelegate reveals (R-01, R-02, R-03, R-05, R-06, R-07, R-08, R-11)
Owner: coder
Files: Sources/App/QuitCoordinator.swift, Sources/App/PergamenumApp.swift
Tests: QuitConflictTests.swift, QuitCoordinatorTests.swift, QuitGapTests.swift, QuitVanishedSchedaTests.swift, QuitVaultSwitchTests.swift
Signatures:
- QuitCoordinator.show — private func show(_ reveal: QuitReview.Reveal?)
- QuitCoordinator.current — private var current: QuitReview { get }
- AppDelegate.revealPaneAfterCancelledQuit — private func revealPaneAfterCancelledQuit(_ pane: Navigation.Pane, thenReveal id: NoteTab.ID? = nil)
Red: no

Make Task 2 green. In `QuitCoordinator.swift`:

1. **`shouldTerminate()`** builds its review after `settleForTermination()`, as today, and also
   passes `board: vault?.openBoard?.quitConflict` and `diary: diary()?.quitConflict`. A flush that
   the settle itself gets refused therefore enters the question. This is ADR-0066 §D5 extended.
2. **«Annulla»** calls `show(review.firstReveal(namingTab: false))`. This replaces the
   `entries.isEmpty` branch. With no board or diary it reproduces today's `reveal(nil)` and
   `revealContenitore(first)`.
3. **«Non salvare»** sets `let left = review.uncoveredWork(in: current)`. If `left` is not empty,
   it calls `show(left.firstReveal())` and returns `.cancel`. Otherwise it continues as today
   (`discardEdits`, then `diaryPhase`).
4. **`current`** carries `board:` and `diary:` exactly as in step 1. It still carries no schede.
5. **`notesSaved`**: if `left` is empty, nothing changes. Otherwise it records one line for each
   kind of leftover:

   - `Uscita annullata: note non salvate: …`, only when `left.notes` is not empty;
   - `left.board?.leftProblem`;
   - `left.diary?.leftProblem`.

   It then calls `show(left.firstReveal(namingTab: true))` and `answer(false, …)`.
6. **`noteCapElapsed`** keeps its line. Its names fall back to the review's notes when `left` has
   none. It adds the two `leftProblem` lines when present and calls
   `show(left.firstReveal(namingTab: true) ?? .note(review.entries.first?.tabID))`. With no board or
   diary this is today's expression exactly.
7. **`lastCheck`** uses `covered.uncoveredWork(in: current)` and `show(left.firstReveal())`, then
   the Contenitore check, unchanged. It records no line for a board or diary, the same as for an
   uncovered note: the diary's own conflict entry already recorded one (ADR-0057 §D6).
8. **`show(_:)`** dispatches the four cases to `reveal`, `revealBoard`, `revealDiary` and
   `revealContenitore`.
9. **No new `sleep` and no timer before `ask`.** The two caps and their ordering stay as they are
   (R-11).
10. **Type doc comment.** Phase 2 now names the board and the diary, and says that «Salva» never
    writes them.

In `PergamenumApp.swift`, `revealPaneAfterCancelledQuit` runs, in order: `reopenMainWindow`,
`navigation?.pane = pane`, then `quitFocus.restore(thenReveal: id, in: vault)`. The four reveal
methods route through it:

- the notes reveal with `.notes` and its id;
- the board reveal with `.workspace`;
- the diary reveal with `.diary`;
- the Contenitore reveal with `.contenitore`, then its `selection`. This gains departure 14's
  keyboard restore (finding 7).

`QuitCoordinator.swift` is 337 lines now. Keep the change compact, under the 400-line warning.
`show` stays `private` in that file, because the closures are `private`.

### Task 5 — Scope and premise pins, then the full suite (R-03, R-09, R-10)
Owner: tester
Files: Tests/QuitConflictScopeTests.swift, Tests/QuitBoardLifetimeHostedTests.swift
Tests: QuitConflictScopeTests.swift, QuitBoardLifetimeHostedTests.swift, HostedViewSupport.swift
Signatures:
- VaultController.switchVault — func switchVault(to url: URL, ask: @MainActor (QuitReview) -> QuitReview.Answer = QuitReviewAlert.askBeforeVaultSwitch) async -> Bool
- VaultController.closeColumn — func closeColumn(_ index: Int, ask: @MainActor (QuitReview) -> QuitReview.Answer = QuitReviewAlert.askBeforeColumnClose, saveAll: (@MainActor (QuitReview) async -> QuitSaveReport)? = nil) async -> Bool
- HostedView — final class HostedView<Content: View> (Tests/HostedViewSupport.swift)
Red: no

- **R-09.** Set up a dirty note plus a conflicted board and a conflicted diary, using Task 2's
  helpers.
  - `switchVault(to:ask:)`: the review handed to `ask` has `board == nil` and `diary == nil`. Its
    copy is the vault-switch copy of the notes alone. Answer «Annulla».
  - `closeColumn(_:ask:)` on the column holding the dirty tab, with a second column added: the
    same assertions.
- **Premise pin for G1 and D7, in `QuitBoardLifetimeHostedTests.swift`.**
  1. Host the real `WorkspaceView` behind an `@Observable` flag (`if flag.shown { WorkspaceView() }
     else { Color.clear }`). Use the environment `WorkspaceFitOnOpenHostedTests.swift` uses.
  2. Wait until `vault.openBoard != nil`.
  3. Flip the flag, `await host.settle()`, then `waitUntil { vault.openBoard == nil }`.

  If the controller survives, stop and report rather than adapt: G1's reason and D7's residual
  would both be void.
- **R-03 and R-10.** Run the whole `PergamenumTests` bundle (`.claude/test-cmd`), not only the
  quit files. `QuitReview` and `QuitCoordinator` are shared contracts, so a regression can surface
  in `ColumnCloseTests`, `VaultSwitchTests`, `QuitReviewAlertTests` or `QuitSaveTests`. The GUI
  suite is not run here. `scripts/uitests.sh --affected` runs at merge and does not block it
  (CLAUDE.md).

### Task 6 — The record: ADR-0089's notes, ADR-0073 G-c, CLAUDE.md, SPEC §5, one stale comment (R-12)
Owner: coder
Files: docs/adr/0089-a-conflicted-board-or-diary-is-asked-about-at-quit.md, docs/adr/0073-quit-reviews-unsaved-notes.md, CLAUDE.md, docs/20260811_Pergamenum_SpecApp.md, Sources/Features/Workspace/WorkspaceView.swift
Tests: none
Signatures:
- ADR-0073 G-c closure — "*Closed YYYY-MM-DD as PG-336 (ADR-0089):*" appended to the G-c bullet, in G-b's shape
- CLAUDE.md chain index — "- **ADR-0089** — Closes `PG-336`/#729 and ADR-0073's G-c: …" placed after the ADR-0080 line
- CLAUDE.md QuitCoordinator working agreement — one added sentence: a conflicted board or diary day is named in the question and never written by it (ADR-0089)
- SPEC §5 — "*Emendato YYYY-MM-DD (ADR-0089).*" sentence after the quit bullet's conflicted-note sentence
Red: no

- **ADR-0089.** The orchestrator writes the file from the returned text before Task 1. This task
  fills its `## Implementation notes`: every departure from D1 to D7 that the build made, the G1
  outcome, and the G2 ledger id in D7. The status stays `proposed` until the merge. The flip to
  `accepted`, with the merge hash, is the first docs change after it (`docs/adr/README.md` §2).
- **ADR-0073 G-c.** Append the closure note. Leave the original text in place, as G-b shows.
- **`CLAUDE.md`.**
  - Add the chain-index line, matching the decision G1 took.
  - Add the one sentence to the "A new holder of unsaved state reviews itself in
    `QuitCoordinator`" agreement.
- **SPEC §5 (G4).** Add the Italian sentence: «Lo stesso avviso nomina anche la board del Workspace
  aperta e il giorno del Diario quando sono in conflitto con il disco: «Salva» non li scrive mai,
  l'app resta aperta e mostra il loro avviso; «Non salvare» esce lasciando i file su disco come
  sono.»
- **`WorkspaceView.swift:97-100`.** This is a comment-only correction. `detach()` reports the loss
  only when the vault changes, and a pane switch drops a conflicted board's edits (ADR-0089 D7, the
  G2 entry). No code changes.
- **Check.** Run `git fetch origin`, then `scripts/check-adr-references.py`. It must exit 0. Every
  ADR number cited in the new and edited files is one `docs/adr/` holds, and none is from another
  series.

## Observable contract changes and their call sites

- **`QuitCoordinator.init`** gains two required parameters. All five call sites are listed in
  finding 6 and updated in Task 2. Nothing else constructs it.
- **`QuitReview.init`** gains two defaulted parameters. The two sites in `QuitCoordinator.swift`
  (`shouldTerminate`, `current`) pass them. These four sites stay as they are on purpose (R-09):
  - `VaultController+VaultSwitch.swift:64`
  - `VaultController+VaultSwitch.swift:71`
  - `VaultController+ColumnClose.swift:53`
  - `VaultController+ColumnClose.swift:60`
- **`QuitReview.isEmpty`** widens.
  - Readers outside the coordinator are `VaultController+VaultSwitch.swift:65` and
    `+ColumnClose.swift:54`. Their behaviour does not change, because they never pass the items.
  - Tests asserting `isEmpty` today are in `QuitReviewTests.swift`, and they do not change.
- **`QuitReview.copy`** text is unchanged for every review without the items. It is read by
  `QuitReviewAlert.swift:92/98/104` and asserted by `QuitReviewTests.swift` and
  `QuitReviewAlertTests.swift`, all unchanged.
- **The quit's problem lines.**
  - `Uscita annullata: note non salvate: …` is now recorded only when notes are left. No test
    asserts it today.
  - `… non è terminato` is unchanged (`QuitCoordinatorTests.swift:368`).
  - `Uscita annullata: modifiche alla scheda non salvate` is unchanged
    (`QuitVanishedSchedaTests.swift:106`).
  - Two new lines are added (Task 1).
- **The full unit suite runs after Task 4 and again in Task 5**, not only the new files.

## Risks and HITL gates

- **HITL before `/build`:**
  - G0 to G4 above;
  - creating the branch;
  - the fate of the staged PG-384 leftovers in the index.
- **HITL during and after:** commit, push and the PR merge. No schema change, no deletion and no
  deploy.
- **`tuist generate --no-open`** after Task 1 and Task 2 add files: `QuitReview+Conflicts.swift`
  and three test files. Without it, the build does not see them and the stop-gate reports a
  compiler error that names the wrong cause.
- **The hosted probe (Task 5)** depends on SwiftUI releasing `@State` after a branch is removed.
  `waitUntil` absorbs the lag. A timeout is a finding to report, never a retry loop.
- **The diary conflict setup** relies on `testOnlyWriteHook` and a `Gate`, the deterministic shape
  of `DiaryConflictTests`. Do not replace it with a sleep.
- **Line budgets.** `QuitCoordinator.swift` is 337 lines and `QuitReview.swift` is 306, against
  SwiftLint's 400-line `file_length` warning. Plan the new code into `QuitReview+Conflicts.swift`.
- **What this cannot cover (G2).** A conflicted board whose pane is not on screen at quit no longer
  has a controller. The quit cannot name it, and the edits are gone before Cmd+Q. The red button
  is one such path.
- **Hand checks.** Zero GUI tests, so these are checked by hand on the Debug build, found by
  `WorkspacePath` (CLAUDE.md):
  - **M1.** Cmd+Q from the Workspace pane with a conflicted board. To make one: save the board,
    rewrite its `.canvas` in a text editor, then move a card. The question names the board.
    «Annulla» leaves the banner on screen and the keyboard working.
  - **M2.** The red button with a conflicted diary. The question names the day. «Non salvare»
    exits, and the day file is unchanged.
  - **M3.** «Salva tutto» with a dirty note and a conflicted diary. The note is saved, the app
    stays on Diario with the banner, and Impostazioni → Problemi shows the diary's line.
  - **M4.** A Contenitore cancel gives the keyboard back (finding 7).

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
CHECK-CMD CANDIDATE: NONE

## Build result (2026-10-05)

BUILD · DONE WITH WARNINGS
Files: 12 modified, 13 new (Sources/App: QuitReview+Conflicts.swift, AppDelegate+QuitReveal.swift, QuitCoordinator, QuitReview, PergamenumApp; 9 test files under Tests/; ADR-0089, ADR-0073 G-c note, CLAUDE.md, SPEC §5, WorkspaceView comment)
Tests: 5343 passed, 5 known issues, exit 0
Review: sonnet, safe; opus, safe
Coverage: 12 of 12 R-ids covered (R-01 to R-12), 0 uncovered
Dropped: 4 (fix-hunk 2, nit 1, unlocated 1)
Dispatch: Round 0 (red): tester — Task 1, tester — Task 2
Dispatch: Round 1: coder — MAJOR docs/adr/0089-a-conflicted-board-or-diary-is-asked-about-at-quit.md:192 (reviewer: sonnet, opus), debugger — MINOR Sources/App/QuitCoordinator.swift:322-327 (reviewer: opus)
Dispatch: Round 2: coder — MINOR Sources/App/QuitCoordinator.swift:321 (reviewer: sonnet, opus), coder — MINOR Sources/App/QuitCoordinator.swift:267 (reviewer: sonnet), coder — MINOR docs/adr/0089-a-conflicted-board-or-diary-is-asked-about-at-quit.md:192 (reviewer: sonnet, opus)
Dispatch: Round 3 (sweep): coder — NIT Sources/App/PergamenumApp.swift:1, NIT Tests/QuitConflictTests.swift:1, NIT Sources/App/QuitReview+Conflicts.swift:22, follow-up Tests/QuitConflictTests.swift:259, follow-up Sources/App/QuitCoordinator.swift:271
INFO: review escalated, size: 22 changed files, threshold 20
WARN: G2 ledger entry not filed, ADR-0089 §D7 and implementation notes, the CLAUDE.md index line and the ADR-0073 G-c note say "to be filed" until /project-tasks assigns an id

```text
FIX	swept	**NIT** Sources/App/PergamenumApp.swift:1 — File is 567 lines (was 548), over the 400 file_length warning; the change adds to existing debt. (reviewer: sonnet)
FIX	swept	**NIT** Tests/QuitConflictTests.swift:68 — drain() is a verbatim duplicate of the same helper in QuitCoordinatorTests.swift:73. Move it to Tests/QuitTestSupport.swift, where this chain already shares its helpers. (reviewer: sonnet, opus)
FIX	swept	**NIT** Tests/QuitConflictTests.swift:1 — Tests/QuitConflictTests.swift (550) and Tests/QuitReviewConflictTests.swift (464) exceed the 400-line file_length warning; consider splitting. (reviewer: sonnet, opus)
FIX	swept	**NIT** Sources/App/QuitReview+Conflicts.swift:22 — sentence(saveLabel:staying:) interpolates staying mid-sentence, so it is grammatical only for the quit's Pergamenum resta aperto; a future occasion would read wrong. Fix: give each occasion its own sentence or note the constraint beside the method. (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/QuitConflictTests.swift:259 — The assertion slept == [diaryCap, noteSaveCap] depends on the scheduling order of main-actor tasks; if it turns unstable the cause is queue order, not a regression. (follow-up: tester)
FIX	swept	**MINOR** [other] Sources/App/QuitCoordinator.swift:271 — If the review holds only a conflicted board or diary and no note and the save hangs, Self.names(of: review) returns an empty string and the line reads il salvataggio di  non è terminato; the text has no fallback. Low priority. (follow-up: coder)
DROP	fix-hunk	**MINOR** [wrong-behaviour] Sources/App/QuitCoordinator.swift:376 — showUncovered lets an uncovered note/diary/scheda reveal switch the pane away from a conflicted board that Non salvare had covered, destroying its controller and edits while the app stays open, with a misleading conflitto non risolto problem line. ADR-0089 notes already document it as an accepted trade-off. Fix: when the board is still conflicted and the item is not .board, reveal .board first and drop the extra line. (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [plan-deviation] docs/adr/0089-a-conflicted-board-or-diary-is-asked-about-at-quit.md:192 — ADR-0089 D7 and its implementation notes ship an unfilled placeholder for the P2 ledger entry the plan's G2/Task 6 required. Fix: file the entry and replace both sentences with its id before the merge, or state in TODO.md that it stays open. (reviewer: opus)
DROP	unlocated	**MINOR** [other] Tests/ReleasePipelineTests.swift appcastSelfTestExitsZeroWithOutput: a 0.14 s self-test exceeded its 60 s timeout in the stop-gate run; flaky under machine load. (follow-up: coder)
```
