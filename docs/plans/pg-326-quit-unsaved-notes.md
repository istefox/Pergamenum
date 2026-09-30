# Fix: quitting asks before it drops unsaved notes (PG-326)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to PG-138/141/142, which have
already merged, and it is not this chain's input. The brief is the `PG-326` entry in `TODO.md`. The
acceptance criteria are declared here as R-01 to R-18.

The plan was read at `9df450b9` (`origin/main` and `fix/pg-326-quit-unsaved-notes` are the same
commit). Every line number below was checked against that tree. The design, the evidence (F1 to
F11) and the rejected alternatives are in ADR-0073.

## ADR outcome: new ADR

**`docs/adr/0073-quit-reviews-unsaved-notes.md`** (status: proposed). It passes all three parts of
the significance test:

- **Hard to reverse.** The termination protocol and its single reply are shared by the diary and the
  board.
- **Surprising without context.** An app-modal alert run before `.terminateLater`, a cap that
  cancels rather than terminates, and a bulk save that refuses to write a conflicted tab all need
  explaining.
- **A real trade-off.** One question or per-document review; a sheet or an app-modal alert; a
  fail-safe or a fail-open cap.

It extends ADR-0012 §D3, ADR-0060 §D2 and ADR-0066 §D5 and amends none. `CLAUDE.md` also requires
the one GUI test (G2) to be justified in the feature's own ADR.

## Acceptance criteria

- **R-01** With at least one dirty note tab in either column, quitting does not terminate before
  asking. The question covers every dirty tab of both columns, background tabs included, in column
  order and then tab order.
- **R-02** The question's words and buttons follow ADR-0073 §D2:
  - With one note: «Salvare le modifiche a «Titolo» prima di uscire?» and «Salva» / «Non salvare»
    / «Annulla».
  - With several: «Salvare le modifiche a N note prima di uscire?», N counting distinct paths, the
    titles listed (at most eight, then «e altre K»; a title shared by two paths shows the path), and
    «Salva tutto» / «Non salvare» / «Annulla».
  - A conflicted note is named in the informative text.
  - Return is the save button, Escape is «Annulla», Cmd+D is «Non salvare», and «Non salvare» has
    `hasDestructiveAction`.
- **R-03** «Annulla» cancels the quit. Every tab keeps its text and its dirty state, and nothing is
  written. When the main window had been closed, it is reopened on the Note pane. (Window reopening:
  hand check M5.)
- **R-04** «Non salvare» terminates without writing any note file. The board settles and the diary
  phase runs as before (ADR-0060 §D2's 2 s cap).
- **R-05** «Salva» / «Salva tutto» writes every dirty, non-conflicted tab's text to disk before the
  app terminates, tabs in the non-focused column and background tabs included. Each write goes
  through `VaultSession.write(_:to:origin:)` with the tab's id as `origin`, the same write Cmd+S
  makes.
- **R-06** A save that fails during quit cancels the quit (`reply(false)`). The failed tab stays
  open and dirty with its text, a problem naming its path is recorded, the tab is revealed, and
  tabs already saved stay saved.
- **R-07** A dirty tab with a pending external change (banner `.text` or `.deleted`) is never
  written by «Salva tutto». The other tabs are saved, the quit is cancelled, and the conflicted tab
  is revealed with its banner. «Non salvare» discards it like any other.
- **R-08** The dirty set is re-read after every suspension: after the question, before each save
  and before the final reply.
  - A tab that became conflicted because an earlier save in the same batch landed on its path (the
    same note dirty in both columns with different text) is not written, and the quit is cancelled.
  - A dirty tab whose `(tab id, text)` the answer did not cover cancels the quit.
- **R-09** Exactly one reply.
  - After `.terminateLater`, `NSApp.reply(toApplicationShouldTerminate:)` is called exactly once.
  - No timer runs while the question is open.
  - The diary's 2 s cap starts only after the notes phase.
  - The note-save phase has a 10 s fail-safe cap that replies `false` and records a problem, never
    `true`.
- **R-10** With no dirty note tab, quitting behaves exactly as today: the board settles, then
  `.terminateNow` if the diary is settled, otherwise the diary settle races the 2 s cap.
- **R-11** The red button on the last window and a logout, restart or shutdown reach the same
  question, and «Annulla» there keeps the app, or cancels the logout. Probe P1's outcome (ADR-0073
  §D8) is recorded. (no-test: AppKit/SwiftUI session and window lifecycle cannot be driven from a
  test; hand checks M5, M6)
- **R-12** The app opts into neither sudden nor automatic termination: neither
  `NSSupportsSuddenTermination` nor `NSSupportsAutomaticTermination` reads `true` in the app's
  `Info.plist`, and `ProcessInfo.processInfo.automaticTerminationSupportEnabled` is `false` in the
  running app.
- **R-13** One save door. Cmd+S, the «Salva» chip, the tab-close dialog and the quit all run
  `VaultController.saveTab(_:)`, and Cmd+S's behaviour is unchanged (no precondition; a pending
  banner does not block it). The tab-close dialog's «Salva» closes the tab only when the save landed
  or there was nothing to save. On a failed save the tab stays open and dirty.
- **R-14** The note editor's top-bar indicator reads «Non salvato» (G3) while the focused note has
  unsaved changes and «Salvato» otherwise. The Workspace board's indicator is unchanged.
- **R-15** (G4) Cmd+W («Chiudi tab») on a dirty tab raises ADR-0012 §D3's «Salva / Non salvare /
  Annulla» dialog instead of closing. On a clean tab it closes at once, as today.
- **R-16** SPEC §5 states how a note is saved, as a dated amendment citing ADR-0012 §D3 and
  ADR-0073: explicit save, the quit question, and §6.1's autosave applying to boards only. §6.1 line
  235 is not edited. (no-test: documentation obligation)
- **R-17** ADR-0073 carries implementation notes with P1's and P2's outcomes. `CLAUDE.md`'s chain
  decision index gains ADR-0073's entry. `TODO.md` gains entries for ADR-0073's G-a (a vault switch
  keeps the previous vault's tabs), G-b («Chiudi la colonna» drops dirty tabs) and G-c (a conflicted
  board or diary loses its edits at quit), plus F7 if G4 says «file separately». PG-326 is closed at
  ship. (no-test: documentation and process obligation)
- **R-18** (G2) End to end in the running app, one GUI test:
  - Type into a note and press Cmd+Q: the alert appears. «Annulla» leaves the app running with the
    «Salva» chip present.
  - Press Cmd+Q again and answer «Salva»: the app exits and the file holds the typed text.

## Call sites of the contracts that change

Grepped at `9df450b9` across `Sources`, `Tests` and `UITests`.

- **`applicationShouldTerminate` behaviour.** The only site is `Sources/App/PergamenumApp.swift:40`.
  Tests: `Tests/DiarySettleTests.swift` (the `settle()` seam, unchanged) and
  `Tests/WorkspaceLifecycleTests.swift:467` (`settleForTermination()`, unchanged). No test asserts
  quitting with a dirty tab.
- **`saveOpenNote()`.** The signature is unchanged. Callers: `Sources/App/CommandActions.swift:180`,
  `Sources/App/VaultController+Editing.swift:64` (`restoreVersion`),
  `Sources/Features/Editor/NoteTabBar.swift:77`, `Sources/Features/Editor/EditorColumn+Text.swift:142`
  and `Sources/Features/Editor/EditorColumn+Closing.swift:45`, which Task 2 moves to
  `saveAndCloseTab`. Tests: `Tests/NoteTabTests.swift:193` and every other `saveOpenNote` test stay
  green unmodified.
- **The tab-close dialog's «Salva» (`closeAfterSaving`) now closes only on success.** No test
  references `closeAfterSaving`, `UnsavedTabDialog` or `requestClose`.
- **`closeFocusedTab()`, deleted under G4.** Its one caller is `Sources/App/CommandActions.swift:144`.
  No test and no UI test sends Cmd+W or references it.
- **«Salvataggio…» in the note top bar.** The only site is `Sources/Features/Editor/VaultTopBar.swift:40`.
  No test or UI test reads it. `BoardChrome.swift:49`'s «Salvataggio…» is the board's and stays.

A contract change can break tests in unrelated modules, so every task below ends with the full
`PergamenumTests` run (the Stop hook's `.claude/test-cmd`), never only the new file's tests.

## Tasks

Swift is compiled, so in every task the **tester** places the new types and signatures with stub
bodies that build, and writes the tests red against them. The **coder** owns the bodies.

### Task 1: `QuitReview`, the dirty set, the copy and the coverage rule (R-01, R-02, R-07, R-08)

- **Files.** New `Sources/App/QuitReview.swift` and `Tests/QuitReviewTests.swift`.
- **Tester declares**, Foundation-only, no AppKit:
  - `struct QuitReview: Equatable, Sendable` with:
    - a nested `Entry` carrying `tabID: NoteTab.ID`, `relativePath`, `title`, `text` and
      `isConflicted`;
    - `init(columns: [EditorColumn])`, `entries`, `isEmpty` and `saveCandidates`;
    - `copy: Copy`, where `Copy` holds `message`, `informative`, `saveLabel`, `discardLabel` and
      `cancelLabel`;
    - `func uncovered(in now: QuitReview) -> [Entry]`;
    - `enum Answer { case save, discard, cancel }`;
    - `static let noteSaveCap: Duration`.
  - Stub bodies return empty values.
- **Tests.**
  - Entries: dirty tabs of both columns only, in column order then tab order; a clean tab and an
    empty column contribute nothing; `isConflicted` is true for both `.text` and `.deleted` pending
    changes.
  - Copy for one note and for several: N counts distinct paths; the eight-title cap with «e altre
    K»; the path shown for a title shared by two paths; the conflicted sentence.
  - `uncovered`:
    - an unchanged snapshot is covered;
    - a tab whose text changed is uncovered;
    - a newly dirty tab is uncovered;
    - a tab that went clean is not uncovered.
  - `saveCandidates` excludes conflicted entries.
  - `noteSaveCap == .seconds(10)`.
- **Coder:** the bodies. `Sources/App` rather than `Sources/Core`: `NoteTab` is app-only (ADR-0073
  §D9).

### Task 2: the save doors, by tab id, that report what happened (R-05, R-06, R-07, R-08, R-13)

- **Files.**
  - `Sources/App/VaultController+Editing.swift`: `saveTab`, `saveAndCloseTab`, and `saveOpenNote`
    delegating.
  - `Sources/App/VaultController+Tabs.swift`: `revealTab`.
  - New `Sources/App/VaultController+Quit.swift`: `saveForQuit`.
  - `Sources/Features/Editor/EditorColumn+Closing.swift`: `closeAfterSaving` calls
    `saveAndCloseTab`.
  - New `Tests/TabSaveTests.swift` and `Tests/QuitSaveTests.swift`.
- **Tester declares** `enum TabSave: Equatable { case saved, clean, failed(String) }` and:
  - `func saveTab(_ id: NoteTab.ID) async -> TabSave`;
  - `func saveAndCloseTab(_ id: NoteTab.ID) async -> TabSave`;
  - `func revealTab(_ id: NoteTab.ID)`;
  - `struct QuitSaveReport: Equatable { saved, failed, conflicted }` (tab ids);
  - `func saveForQuit(_ review: QuitReview) async -> QuitSaveReport`.
  - All stubbed.
- **Tests** (`TemporaryVault` plus `VaultController(recents: .volatile(), openTabs: .volatile())`,
  the `NoteTabTests` scaffolding):
  - `saveTab` writes a background tab of the **other** column without changing
    `focusedColumnIndex` or any `activeID`. The writer's `savedText` catches up and its `text` is
    kept.
  - `saveTab` returns `.clean` for a clean tab and for an unknown id.
  - `saveTab` returns `.failed` when the note's folder is made read-only (`posixPermissions`,
    restored in a `defer`; precedent in `Tests/AttachmentChipTests.swift`). The tab stays dirty and
    `problems` names the path.
  - `saveAndCloseTab` closes on `.saved` and `.clean`, and leaves the tab open and dirty on
    `.failed`.
  - `revealTab` on a tab of the non-focused column focuses that column and that tab.
  - `saveForQuit`:
    - writes three dirty tabs across two columns;
    - skips a conflicted tab (pending change set through `updateTabs(showing:)`) and reports it;
    - with the same path dirty in both columns with different text, writes the first and reports
      the second as conflicted, and the second's text is not on disk;
    - reports a failure mid-batch and still writes the tabs after it.
  - `NoteTabTests.savingWritesTheFocusedTabAndNotTheOther` stays green unmodified.
- **Coder:** the bodies.
  - `saveTab` finds the tab in any column and writes with `origin: id`, catching into `.failed`
    plus `recordProblem`.
  - `saveOpenNote()` becomes `guard let id = focusedTab?.id else { return }; _ = await saveTab(id)`.
  - `saveForQuit` re-reads `columns` before each write (ADR-0043 §D7).
  - `revealTab` does `focusColumn` then `focusTab`.

### Task 3: `QuitCoordinator`, one reply over three phases (R-01, R-03, R-04, R-06, R-07, R-08, R-09, R-10)

- **Files.**
  - New `Sources/App/QuitCoordinator.swift`.
  - `Sources/App/PergamenumApp.swift`: `AppDelegate.applicationShouldTerminate` maps
    `coordinator.shouldTerminate()` to `NSApplication.TerminateReply`, and the inline two-task race
    and `owesTerminateReply` move into the coordinator, with their doc comment updated.
  - New `Tests/QuitCoordinatorTests.swift`.
- **Tester declares** `@MainActor final class QuitCoordinator` and `enum QuitReply { case now,
  later, cancel }`.
  - `init` takes:
    - `vault: @escaping () -> VaultController?`;
    - `diary: @escaping () -> DiaryController?`;
    - `ask: @escaping (QuitReview) -> QuitReview.Answer`;
    - `reply: @escaping (Bool) -> Void`;
    - `reveal: @escaping (NoteTab.ID?) -> Void`;
    - `sleep: @escaping (Duration) async -> Void`;
    - `saveAll: ((QuitReview) async -> QuitSaveReport)? = nil`, where `nil` means
      `vault.saveForQuit`.
  - `func shouldTerminate() -> QuitReply`, stubbed.
- **Tests** (real `VaultController` and `DiaryController` on a `TemporaryVault`; a fake `ask`; a
  recording `reply`; a `sleep` that records its calls and returns at once, or waits on a gate):
  - No dirty tab, diary settled: `.now`; `ask` and `reply` are never called (R-10).
  - No dirty tab, diary pending: `.later`, then exactly one `reply(true)` once the diary file holds
    the text (R-10, R-09).
  - `sleep` has not been called at the moment `ask` runs (R-09).
  - `.cancel`: `.cancel`, the file is unchanged, the tab is still dirty, `reveal(nil)` is called and
    `reply` is never called (R-03).
  - `.discard`: `.now` with the diary settled, and the file is unchanged (R-04).
  - `.save` with two dirty tabs in two columns: `.later`, both files written, exactly one
    `reply(true)` (R-05, R-09).
  - `.save` with a read-only folder: exactly one `reply(false)`, the tab still dirty, and `reveal`
    receives its id (R-06).
  - `.save` with one conflicted tab: the others are written, then one `reply(false)` and
    `reveal(conflicted id)` (R-07).
  - `ask` changes a tab's text before returning `.discard` (typing that raced the answer): the quit
    is cancelled and the tab revealed (R-08).
  - Save cap: an injected `saveAll` that waits on a gate that never opens, with `sleep` returning at
    once for `noteSaveCap`. Exactly one `reply(false)` and a problem recorded; opening the gate
    afterwards produces no second reply (R-09).
  - Diary cap after a save: the diary still settles and exactly one reply follows (R-09).
- **Coder:** the bodies, in ADR-0073 §D1/§D5/§D6/§D7's order.
  1. The board settles.
  2. Build the review and ask.
  3. Re-read.
  4. Branch on the answer.
  5. Run the diary phase with two independent tasks (ADR-0060 §D2).
  6. Re-read again before `.now` or `reply(true)`.

### Task 4: the AppKit presenter, the window hook, termination support (R-02, R-03, R-11, R-12)

- **Files.**
  - New `Sources/App/QuitReviewAlert.swift`.
  - `Sources/App/VaultController.swift`: an `@ObservationIgnored var reopenMainWindow: (() ->
    Void)?`, beside `openBoard` at `:155`.
  - `Sources/App/RootView.swift`: reads `@Environment(\.openWindow)` and sets
    `vault.reopenMainWindow = { openWindow(id: "main") }` in `.onAppear`.
  - `Sources/App/PergamenumApp.swift`: `appDelegate.navigation = navigation` beside `:278-279`; the
    delegate builds the coordinator with `ask: QuitReviewAlert.ask`, `reply: {
    NSApp.reply(toApplicationShouldTerminate: $0) }` and a `reveal` closure that reopens the
    window, sets `navigation.pane = .notes` and calls `vault.revealTab`.
  - New `Tests/QuitReviewAlertTests.swift` and `Tests/TerminationSupportTests.swift`.
- **Tester declares** `enum QuitReviewAlert { static func make(_ copy: QuitReview.Copy) -> NSAlert;
  static func ask(_ review: QuitReview) -> QuitReview.Answer }`, stubbed, and the
  `reopenMainWindow` property.
- **Tests.**
  - `make` returns buttons in the order save, Annulla, Non salvare, which NSAlert places right to
    left.
  - Titles come from the copy.
  - The key equivalents are `"\r"`, `"\u{1b}"` and `"d"` with `.command`, and «Non salvare» has
    `hasDestructiveAction`.
  - A response maps to its `Answer`.
  - R-12: `Bundle.main` has no `true` for `NSSupportsSuddenTermination` or
    `NSSupportsAutomaticTermination`, and `ProcessInfo.processInfo.automaticTerminationSupportEnabled
    == false`. The unit suite is hosted in the app (`Project.swift`, the tests target depends on the
    app target).
- **Coder:** the bodies. `ask` calls `runModal()` synchronously (ADR-0073 §D3).
- **Probe P1** (ADR-0073 §D8), run by hand on a Debug build: the red button with a dirty tab.
  - Outcome A: the alert appears with no window, and «Annulla» reopens it. Nothing more to do.
  - Outcome B: the app exits unasked. Then `applicationShouldTerminateAfterLastWindowClosed(_:)`
    answers `false` while `QuitReview` is not empty.
  - Record the outcome for Task 8.

### Task 5 (G4): Cmd+W asks ADR-0012 §D3's question (R-15)

- **Files.**
  - `Sources/App/VaultController.swift`: a stored, observed `var closeRequest: NoteTab.ID?` (written
    only through the doors).
  - `Sources/App/VaultController+Tabs.swift`: `requestCloseFocusedTab()`, and delete
    `closeFocusedTab()` at `:81-86`.
  - `Sources/App/CommandActions.swift:143-144`.
  - `Sources/Features/Editor/EditorColumnView.swift`: `.onChange(of: vault.closeRequest)` moves a
    request for a tab of this column into `closing` and clears it.
  - New `Tests/CloseTabRequestTests.swift`.
- **Tester declares** `requestCloseFocusedTab()` and `closeRequest`, stubbed.
- **Tests.**
  - A clean focused tab closes and `closeRequest` stays nil.
  - A dirty focused tab stays open with `closeRequest == its id`.
  - No focused tab: nothing happens.
  - `CommandActions.run(.closeTab)` on a dirty tab leaves it open.
- **Coder:** the bodies. The dialog, its copy and its three buttons are the existing
  `UnsavedTabDialog`, now backed by Task 2's `saveAndCloseTab`.
- If G4 says «file separately», this task is dropped, R-15 moves to the new ledger entry, and Task 8
  files F7.

### Task 6: an honest indicator and SPEC §5 (R-14, R-16)

- **Files.**
  - New `Sources/Features/Editor/NoteSaveIndicator.swift`, a pure copy type in `ConflictBannerCopy`'s
    shape.
  - `Sources/Features/Editor/VaultTopBar.swift:39-44`.
  - `docs/20260811_Pergamenum_SpecApp.md` §5.
  - New `Tests/NoteSaveIndicatorTests.swift`.
- **Tester declares** `struct NoteSaveIndicator: Equatable { let label: String; let symbol: String;
  init(hasUnsavedChanges: Bool) }`, stubbed.
- **Tests.** Dirty gives «Non salvato» and `arrow.triangle.2.circlepath`, or a symbol chosen at G3;
  clean gives «Salvato» and `checkmark.circle`.
- **Coder:**
  - The body, and `VaultTopBar` renders it through `.themedText(.caption, color: .textSecondary)`,
    as now, with no new colour or font.
  - The SPEC §5 bullet, as an `*Emendato 2026-09-29 (ADR-0073).*` note, in the style of lines 20
    and 338. It says:
    - notes save explicitly (Cmd+S, the «Salva» chip, the tab-close dialog, ADR-0012 §D3);
    - quitting with unsaved notes asks «Salva tutto / Non salvare / Annulla» (or G1's
      alternative);
    - §6.1's autosave indicator describes boards.
  - Line 235 is not edited.

### Task 7 (G2): one GUI test for the AppKit seam (R-18)

- **Files.** New `UITests/QuitReviewUITests.swift`.
- **The test.**
  - Launch with `-disableCalendar YES`, `-disableUpdater YES`, `-mailStoreRoot <empty temp dir>`
    and `-recentVaults '("<fixture vault>")'`, a vault the runner created.
  - Open the note and type a line.
  - Press Cmd+Q and wait for the alert, `app.dialogs` or `app.sheets`, whichever the probe shows.
    Press «Annulla»; expect `app.state == .runningForeground` and the «Salva» chip's accessibility
    label present.
  - Press Cmd+Q again and «Salva». Wait for `.notRunning` (≤ 15 s) and read the file from the
    runner's own fixture path.
  - Controls are found by `accessibilityIdentifier`, or by the alert's button titles, which are the
    contract here.
- **Probe P2** (ADR-0073 §D8): record whether `app.terminate()` in another class's teardown reaches
  the delegate with a dirty tab left. If it does, the affected UI tests save or revert before
  teardown. No launch flag disables the review.

### Task 8: the old-behaviour sweep, docs, ledger and verification (R-11, R-17, all)

- **Update tests and call-sites asserting the old behaviour.** Re-run the greps in «Call sites of
  the contracts that change» on the final tree:
  - `rg -n "applicationShouldTerminate|closeFocusedTab|Salvataggio…|closeAfterSaving|saveOpenNote\(\)" Sources Tests UITests`.
  - Update any test or call site still asserting quit-without-asking, a closing «Salva» on failure,
    Cmd+W closing a dirty tab, or «Salvataggio…» on a note. At planning time the greps found none
    in `Tests`/`UITests`.
- **Files.**
  - `docs/adr/0073-quit-reviews-unsaved-notes.md`: implementation notes with P1's and P2's outcomes,
    and every departure from the letter.
  - `CLAUDE.md`: the chain decision index entry for ADR-0073, and one working agreement naming the
    quit door ("a new holder of unsaved state reviews itself in `QuitCoordinator`, never in
    `willTerminateNotification`").
  - `TODO.md`: new entries for G-a (P1), G-b (P2), G-c (P3), plus F7 if G4 says «file separately»;
    PG-326 closed at ship.
- **Verification.**
  - Run the full `PergamenumTests` suite (the Stop hook).
  - Run `scripts/uitests.sh --status`, then `scripts/uitests.sh --affected`. `Sources/App/*` selects
    the whole GUI suite, so this is all 24 tests plus the new one. Diagnose a red from its
    `.xcresult` before rerunning; a 60.2 s failure names the launch timeout, which here would be
    P2's hang.
  - Build `perg` and `pergamenum-mcp`; nothing here is in `sharedSources`, so both must build
    unchanged.
  - Run SwiftLint.
- **Hand checks** on a Debug build over a throwaway vault (`-recentVaults '("…")'`, the latest
  bundle by `ls -dt`):
  - **M1.** One dirty tab, Cmd+Q: «Salva / Non salvare / Annulla». Annulla keeps it; Salva writes
    and exits.
  - **M2.** Three dirty tabs across two columns, one in the background: «Salva tutto» writes all
    three.
  - **M3.** A dirty tab whose file is edited from the Terminal: the alert names it; «Salva tutto»
    saves the rest, the app stays, and the banner shows.
  - **M4.** `chmod a-w` on a dirty note's folder: «Salva», and the app stays, the tab stays dirty
    and Impostazioni › Problemi names the path. Restore the permissions afterwards.
  - **M5.** The red button with a dirty tab: P1's outcome, and «Annulla» brings the window back.
  - **M6.** Log Out with a dirty tab: the same alert, and «Annulla» cancels the logout.
  - **M7.** (G4) Cmd+W on a dirty tab: the tab-close dialog.
  - **M8.** Unsaved diary text plus a dirty note, «Salva tutto»: both reach disk.

## Risks and HITL gates

**Decided at Gate 1/2 (2026-09-29, Stefano):** G1 one alert, G2 one GUI test, G3 «Non salvato»,
G4 Cmd+W in this chain, G5 the SPEC §5 amendment as written. Each gate below keeps its
recommendation as the chosen option.

- **G1, the quit question's shape** (Stefano). Recommended: one alert, «Salva tutto / Non salvare /
  Annulla», listing the notes. Alternative: per-document review, NSDocument's «Rivedi… / Non
  salvare / Annulla» followed by one tab-close dialog per note. Only Task 4's presenter changes.
- **G2, GUI tests.** Recommended: one (Task 7). Alternative: zero, with M1 as the only evidence.
- **G3, indicator wording.** Recommended: «Non salvato». Alternative: «Modifiche non salvate».
- **G4, Cmd+W in this chain.** Recommended: yes (Task 5). Alternative: file F7 as its own P1 entry.
- **G5, the SPEC §5 amendment text**, since SPEC is the authoritative document.
- **Commit, push and merge** are HITL gates as usual. No schema change, deletion of user data,
  deploy or new dependency.
- **Risk: P2.** A UI test's teardown may now hang on the alert. It is measured in Task 7, and the
  remedy is decided in advance (ADR-0073 §D8).
- **Risk: P1 outcome B.** The red button may bypass the delegate. The remedy is decided in advance.
- **Risk: main-actor tasks under `.terminateLater`.** The note saves rely on main-actor tasks running
  while the run loop is in modal panel mode. ADR-0060 §D2's diary settle relies on the same thing,
  and M1/M2 re-verify it for notes.
- **Risk: `@Environment(\.openWindow)` captured in `RootView`** may not reopen a `Window` scene
  whose window was closed. M5 verifies it. The fallback is P1's outcome-B remedy, which never lets
  the window's closing quit the app.
- **External resources:** none. No network, no new entitlement, and no environment variable or port
  is needed before `/build`. M6 needs a logged-in macOS session the tester is willing to log out of.
- **Parallel chains:** `refactor/pg-144-editor-coordinator` holds an unmerged ADR-0071 and touches
  the editor. Check before the merge for conflicts in `EditorColumnView.swift` and
  `EditorColumn+Closing.swift`, and check the ADR number again (`docs/adr/README.md` §1).

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
