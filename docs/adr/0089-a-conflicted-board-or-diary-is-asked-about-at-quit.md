# ADR-0089: A conflicted board or diary is asked about at quit

- Status: **accepted**. Merged to `main` via PR #906 (`88a1d614`, 2026-10-05): the quit review
  names a conflicted board or diary day, and only «Non salvare» lets either go.
- Date: 2026-10-05. Written before the implementation, against `05fa8bb2`. `origin/main` is
  `0e2fd436` and differs from it in `TODO.md` only. Every line number below was read from that
  tree.
- **Numbering note.** `0080` is the highest ADR on `origin/main`, so `docs/adr/README.md` §1 gives
  `0081`. But `0081` to `0087` are already assigned to N2–N5 by
  `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` and to `PG-385`–`PG-388` in `TODO.md`. An
  unmerged worktree also holds untracked drafts up to `0088`. This record takes `0089`. Check
  again immediately before the merge.
- Source: `SPEC.md` "A conflicted board or diary is asked about at quit (PG-336)", Approved
  2026-10-05, R-01 to R-12; the `PG-336` entry in `TODO.md` (#729); ADR-0073's gap G-c.
- Extends ADR-0073 (§D1, §D2, §D5, §D6, §D7) and ADR-0066 §D5. Amends none. ADR-0054 §D5,
  ADR-0057 §D6 and ADR-0060 §D2 are unchanged.

## Context

Today a quit over a conflicted board or diary day drops the edits held in memory, with no
question:

- **The order of the quit.** `QuitCoordinator.shouldTerminate()` (`QuitCoordinator.swift:122`)
  first settles the open board (`settleForTermination()`, `:138`). It then builds a `QuitReview`
  from two things only, the dirty note tabs and the Contenitore schede (`:143-147`). An empty
  review skips the question.
- **A conflicted board.** `settleForTermination()` returns without flushing it (ADR-0066 §D5,
  following ADR-0054 §D5). Nothing asks, the reply is `.now`, and the edits in `document` are gone.
- **A conflicted diary.** `isSettled` is false, so the diary phase starts (`:270`). `settle()`
  returns at once, because `performWrite` returns on `.conflicted`. `finish` then replies `true`,
  and the edits in `prose` and `entries` are gone.
- **The only trace** is the problem line recorded when the conflict began (ADR-0054 §D5, ADR-0057
  §D6).

ADR-0073 named this G-c and left it alone, because reviewing these items at quit "would reopen"
ADR-0054 §D5 and ADR-0066 §D5. Read again, the two decisions say less than that:

- ADR-0054 §D5 says that nothing is written over the other writer and nothing is discarded without
  a choice. Its reason for not blocking concerns the window: "refusing to close a window over an
  autosave conflict is worse than the loss it prevents".
- ADR-0066 §D5 says that the quit's settle does not flush a conflicted board.

A question that writes nothing, and lets the app go on one click, keeps both rules. It adds a
choice before a discard that was silent until now.

Reading the tree found three facts that shape the decision:

1. **The open board's controller lives only while the Workspace pane is on screen.**
   - `WorkspaceView` holds `@State var workspace = WorkspaceController()`.
   - `RootView`'s `detail` is a `switch pane`.
   - `VaultController.openBoard` is weak.

   A pane switch or a window close destroys the controller. `.onDisappear` skips the flush for a
   conflicted board (`WorkspaceView.swift:96-105`), and `detach()` runs only when the vault root
   changes (`reattachWorkspace`, `:200`). So such a loss records nothing, although the comment at
   `:97-100` says `detach()` reports it.
2. **The diary's controller is app-level.** `load()` and `show(_:)` keep a conflict, so the Diario
   pane can be shown at any moment and still carries its banner.
3. **«Salva tutto» already ends by re-reading the dirty set** (`notesSaved`, `:237`). Its problem
   line assumes that every leftover is a note.

## Decision

### D1 · The review carries two optional items, and only the quit passes them

`QuitReview` gains `board: Board?` and `diary: DiaryDay?` beside `entries` and `schede`. Both are
defaulted init parameters.

- `Board` holds `path` and the `document` held in memory. It derives `name`, the file name without
  `.canvas`.
- `DiaryDay` holds `day`, `prose` and `entries`.

Both are `Equatable, Sendable` values. They exist only so the snapshot can be compared (D4), and
nothing is persisted. `isEmpty` is false when either is present.

Only the quit passes them, in `shouldTerminate()` and `current`. The vault switch
(`VaultController+VaultSwitch.swift:64/71`) and «Chiudi la colonna» (`+ColumnClose.swift:53/60`)
build the review as before, so neither ever names the board or the diary. The Contenitore schede
already work this way.

The types, their words and the two derivations of D2 live in `Sources/App/QuitReview+Conflicts.swift`.
`QuitReview` stays app-only (ADR-0073 §D9), and nothing enters `Sources/Core`.

### D2 · The coordinator reads the conflicts through the closures it already holds

`WorkspaceController.quitConflict` and `DiaryController.quitConflict` answer the item when
`saveState` is `.conflicted`, and for the board only when `board` is not empty. Otherwise they
answer `nil`.

The coordinator reads the board's item through `vault()?.openBoard` **after**
`settleForTermination()`. A pending save that the settle itself gets refused therefore enters the
question. That is the extension of ADR-0066 §D5: the settle still never writes over a conflict,
and the conflict it leaves behind is now asked about. The diary's item is read through `diary()`.

A board or diary that is pending but not conflicted is not an item. The settle writes the board,
and the diary phase writes the diary, exactly as before.

### D3 · The words

The question builds one ordered list of items (D6). Each item has a singular phrase and a list
line. The board and the diary also have one sentence each:

| Item | Alone in the question | List line | Sentence |
|---|---|---|---|
| Board | `Salvare le modifiche alla board «B» prima di uscire?` | `la board «B»` | `La board «B» è cambiata anche su disco: con «S» Pergamenum resta aperto per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse.` |
| Diary | `Salvare le modifiche al diario del giorno D prima di uscire?` | `il diario del giorno D` | `Il diario del giorno D è cambiato anche su disco: con «S» Pergamenum resta aperto per farti scegliere quale versione tenere, con «Non salvare» le sue modifiche vanno perse.` |

In the table:

- `S` is the alert's own save label, «Salva» or «Salva tutto», as the failed scheda's sentence
  already does.
- `D` is `CalendarDate.italianForm`, the diary header's own form (`DiaryView.swift:89`).
- «del giorno» avoids the elision `dell'11`.

The counted message joins its parts as «a, b e c», for example `1 board, 2 note e 1 diario`. With
two parts the result is byte-identical to today's `1 nota e 1 scheda`.

The eight-line limit applies to the whole list. An item cut off by «e altre K» is still named by
its own sentence.

A review without either item keeps every existing word, for all three occasions.

### D4 · What an answer covers

`uncoveredWork(in:)` extends ADR-0073 §D7 to the two items:

- the notes are uncovered exactly as before, through `uncovered(in:)`;
- a board or diary day is uncovered when it is conflicted now and absent from the snapshot, or
  when it differs from the snapshot's copy. For the board that is path and document; for the day
  it is day, prose and entries.

So a conflict that began after the question cancels the quit, and so does content changed since
the question. The SPEC names two ways a conflict can begin: the diary refused while «Salva tutto»
settles it, and the diary refused during the diary phase after «Non salvare».

The check runs where §D7 already checks notes: at the re-read after «Non salvare», in `lastCheck`,
and through `current` in `notesSaved` and `noteCapElapsed`.

### D5 · The three answers

- **«Salva» and «Salva tutto» never write either item.**
  - The notes are saved as before. The diary settles first (ADR-0073, departure 17), which does
    nothing for a conflicted diary.
  - `notesSaved` re-reads `current`, which now carries the conflicts. The quit is therefore
    cancelled with `.later` followed by `reply(false)`, as for a lone conflicted note today.
  - The notes' problem line is recorded only when notes are left. Each item left adds one line:
    `Uscita annullata: la board «B» ha un conflitto di salvataggio non risolto` or
    `Uscita annullata: il diario del giorno D ha un conflitto di salvataggio non risolto`.
  - The fail-safe cap path adds the same lines.
- **«Non salvare» writes nothing and copies nothing.** When nothing is uncovered, the quit goes on.
  With only a board, the reply is `.now`. With a conflicted diary, the diary phase runs as it does
  today: `.later`, then `settle()` returns at once, then `reply(true)`. The conflicted files stay
  byte-identical, and no file is created.
- **«Annulla» cancels** and reveals the first item, in D6's order.

### D6 · Where a cancel takes the person

One function decides two things: the item a cancel reveals, and the order in which the question
names the items. It is `QuitReview.firstReveal(board:notes:diary:schede:namingTab:) -> Reveal?`. A
cancel therefore always shows the item the question named first.

The order is: the board, the notes, the diary, then the Contenitore schede.

- **This departs from the SPEC's order** (notes, board, diary). The reason is Context fact 1:
  showing any other pane destroys the board's controller, together with the edits the question
  had just protected.
- **The board first costs nothing.** When the board is an item, its pane is on screen, because
  otherwise it would have no controller. Revealing it leaves its banner where it already is.
- **The diary can come after the notes**, because its controller is app-level (fact 2).
- **A note keeps ADR-0073 §D7.** «Annulla» reveals `reveal(nil)`; after a save, the reveal is the
  first unresolved tab.

`Reveal` has four cases: `board`, `note(NoteTab.ID?)`, `diary` and `scheda(String?)`. The
coordinator dispatches them to four closures. The two new ones, `revealBoard` and `revealDiary`,
are required rather than defaulted, as `revealContenitore` is.

In production, all four reveals go through one helper, which does three things in order:

1. reopen the main window;
2. set the pane;
3. give the keyboard back before revealing a tab (ADR-0073, departure 14).

The Contenitore reveal thereby gains the keyboard restore it lacked.

### D7 · What this does not reach: a board that left the screen before the quit

A conflicted board whose controller is already gone cannot be named by the quit. That happens on
a pane switch, and on a window close, which includes the red button on the last window. The loss
also records nothing (Context fact 1). This chain corrects the misleading comment at
`WorkspaceView.swift:97-100`.

The residual, a conflicted board lost on a pane switch or a window close, is recorded as the P2
ledger entry `PG-392` (issue #918). Its remedy is to lift `WorkspaceController` to the vault's lifetime,
in its own ADR. It is not fixed here, for two reasons:

- it changes the board's whole lifecycle: ADR-0066's reset door, `attach`/`detach`, and
  `WindowPlace`'s pending canvas;
- asking on a pane switch or a window close would revisit ADR-0054 §D5's window-close stance,
  which the SPEC puts out of scope.

R-01 therefore holds when Cmd+Q, «Esci», a logout or a restart arrives with the Workspace pane on
screen. For the diary it holds on every termination, the red button included.

### D8 · What stays as it was

- No timer runs while the question is open.
- The 10 s fail-safe note cap and the 2 s fail-open diary cap are unchanged.
- The quit still has one door and one reply.
- ADR-0073 §D7's rule for notes is unchanged.
- The vault switch and «Chiudi la colonna» are unchanged.
- No on-disk format, schema, frontmatter key or protected interface changes.
- No GUI test is added. (Amended 2026-10-07: one is, see the last implementation note.)
- `detach()` is untouched.
- ADR-0054 §D5, ADR-0057 §D6 and ADR-0060 §D2 apply exactly as written.

## Alternatives considered

1. **Write a conflict copy at quit (the SPEC's option C).** Rejected. It puts a file nobody asked
   for into the vault, or beside the diary's day files. It needs a naming rule, a way to find the
   copy again and a cleanup, all to rescue text the person can already choose to keep from the
   banner.
2. **Keep the exit silent and record the loss durably (option A).** Rejected. It documents the loss
   without preventing it, and the problem line recorded when the conflict began already documents
   it.
3. **Let «Salva» write the version held in memory over the other writer.** Rejected. It contradicts
   ADR-0054 §D5, under which nothing is written over the other writer at quit. Keeping the in-memory
   version is the banner's «Mantieni le mie modifiche», chosen on purpose, never implied by a quit.
4. **Make a safety copy under the app's state directory on «Non salvare».** Rejected. It is option
   C moved out of the vault, with the same naming, expiry and discoverability costs. The question
   already says the edits are lost.
5. **Hide «Salva» when nothing in the review can be saved.** Rejected. It changes the alert for a
   lone conflicted note too, which widens the change beyond PG-336.
6. **Pass the items to the vault switch and «Chiudi la colonna» as well.** Rejected. Neither touches
   the board or the diary, and extending them would revisit ADR-0054 §D5's window-close stance and
   ADR-0073's G-a, each a decision of its own.
7. **Reveal in the SPEC's original order: notes, then board, then diary.** Rejected at the plan
   gate (G1, approved 2026-10-05). Whenever notes and a board are both unresolved, showing the Note
   pane destroys the board's controller. The question would then protect the edits only to have
   its own cancel drop them. The SPEC's R-05 and its Decisions bullet were amended to the new order.
8. **Close D7 here by lifting `WorkspaceController` to the vault's lifetime.** Rejected for this
   chain. It is a different decision, with its own risk across the board's lifecycle (D7), and the
   SPEC excludes the window close.
9. **Ask a second question for the board and the diary after the notes' question.** Rejected. It
   breaks ADR-0073 §D2's single question, puts two modal alerts in a row, and would need a second
   coverage snapshot.

## Consequences

### Positive

- A quit no longer drops a conflicted diary day without a choice. The same holds for a conflicted
  board whose pane is on screen.
- One rule now covers a conflicted note, board and diary, so a person learns one behaviour.
- No new file, format, button or setting.
- The problem line names what kept the app open.

### Negative

- «Salva» on a review whose only item is a conflict always cancels. The person resolves the
  conflict on the banner and quits again, which is one more round trip.
- A conflicted board that left the screen before the quit is still lost, and that loss is still
  silent (D7). For the board, the promise is narrower than "every termination".
- The reveal order and the order of the list depart from the original SPEC wording (G1).
- Each quit snapshot copies the `CanvasDocument`. The cost is a value copy per quit, and nothing is
  kept.

### Neutral

- For every review without either item, every word is byte-identical to today, including the vault
  switch and «Chiudi la colonna».
- «Non salvare» with a conflicted diary replies `.later` and then `true`, as the quit already does
  today.

## References

- `SPEC.md` (PG-336), R-01 to R-12.
- ADR-0073 §D1–§D7, G-c, departures 14 and 17.
- ADR-0054 §D5; ADR-0057 §D6; ADR-0060 §D2; ADR-0066 §D5.
- `Sources/App/QuitCoordinator.swift`, `Sources/App/QuitReview.swift`, `Sources/App/PergamenumApp.swift`.
- `Sources/Features/Workspace/WorkspaceView.swift:96-105, 200`.
- `Sources/Features/Diary/DiaryController.swift`.
- Plan: `docs/plans/pg-336-conflicted-board-diary-at-quit.md`.

## Implementation notes

- **G1, the order.** Approved 2026-10-05 as recommended: the board, the notes, the diary, then the
  Contenitore schede, for both the question's list and the cancel's reveal. It lives in one place,
  `QuitReview.firstReveal(board:notes:diary:schede:namingTab:)`; `copy(for:)` builds its list and
  its sentences in the same sequence, and a test pins that the question's first line is the item a
  cancel reveals.
- **D7's ledger entry: `PG-392` (issue #918, G2 open).** The residual (a conflicted board lost
  on a pane switch or a window close) is recorded as that P2 entry, its remedy being to lift
  `WorkspaceController` to the vault's lifetime in its own ADR. `WorkspaceView.swift`'s
  corrected comment cites ADR-0089 §D7 only, so no id needs to reach the code.
- **D3, how the words are built.** `Board` and `DiaryDay` each carry three internal helpers beside
  `leftProblem`: `singularPhrase` («alla board «B»», «al diario del giorno D»), `listLine` («la board
  «B»», «il diario del giorno D») and `sentence(saveLabel:staying:)`. The sentence takes «Pergamenum
  resta aperto» from the occasion's own `staying` word, as the conflicted note's sentence does; since
  only the quit passes the items, the result is the frozen G3 string. `leftProblem` is
  `Uscita annullata: <list line> ha un conflitto di salvataggio non risolto`. The counted message's
  helper spells a plural «diari» for completeness; a review holds at most one diary day, so it is
  never reached.
- **D5, the fail-safe cap's names.** `noteCapElapsed` now falls back to the review's notes when the
  fresh review has no note left (`left.entries.isEmpty`), rather than when it is empty as a whole:
  with only a conflicted board or diary left, the line still names the notes whose save did not end,
  and the board or diary adds its own line beside it. Its reveal is
  `left.firstReveal(namingTab: true) ?? .note(review.entries.first?.tabID)`, today's expression when
  neither item is present.
- **D6, the reveals.** `AppDelegate.revealPaneAfterCancelledQuit(_:thenReveal:)` is the one helper:
  reopen the main window, set the pane, then `QuitFocus.restore(thenReveal:in:)`. The note, board,
  diary and Contenitore reveals all go through it; the Contenitore reveal sets its `selection` after
  the helper returns, and so gains departure 14's keyboard restore.
- **D4/D6, a covered board left by an uncovered reveal.** When a cancel's reveal (the last check,
  or «Non salvare»'s re-read after the question) switches away from the Workspace while a
  conflicted board is still open, `QuitCoordinator.showUncovered` records the board's
  `leftProblem`, because the pane switch destroys the board's controller and its edits with it. The
  line reads «ha un conflitto … non risolto» for edits that are in fact being dropped. Revealing
  `.board` first whenever the board is still conflicted would prevent the loss but changes the
  Uncovered reveal rule of D4/D6, so it is not done.
- **A GUI test, added 2026-10-07 (PG-393 M1/M2).** `QuitReviewUITests.testQuittingWithAConflictedDiaryDayAsksAndWritesNothing`
  opens the Diario, types, rewrites the day file from outside until `diary-conflict-banner` shows,
  then quits twice: «Annulla» keeps the app, the banner and the file, «Non salvare» exits and
  writes nothing. The question's wording, order and count, the last-check cancels and the Problemi
  lines are pinned in-process (`QuitReviewConflictTests`, `QuitConflictLastCheckTests`,
  `QuitConflictScopeTests`); what only a real window shows is AppKit's terminate reaching the
  review with a conflicted item and nothing else dirty, the same gap ADR-0073 §D9 justifies for
  notes. The day stands in for the board, which takes the same `QuitReview.diary`/`.board` path but
  needs a drag to be made dirty. The board's own Cmd+Q and M4's Contenitore cancel stay by hand: the
  harness passes `-disableContenitore YES`, so no schede can be made dirty. The cap of seventeen is
  a decision taken by hand on 2026-09-21 and `scripts/uitests.sh` does not enforce it; the suite
  already stood at 29 tests before this one (30 after), so this note records that the test
  raises a count that was already above the cap, and does not claim the cap holds.
- No other departure from D1 to D8. Nothing in `Sources/Core` or `sharedSources`; `QuitCoordinator`
  and `QuitReview` stay under SwiftLint's 400-line `file_length` warning.
