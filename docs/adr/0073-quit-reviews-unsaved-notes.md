# ADR-0073: Quitting reviews unsaved notes first: one question, one save door, one reply

- Status: **proposed**. Implementation not on `main` yet; flip to `accepted` with the PR, the merge
  commit's short hash from `git log --first-parent main` and the date as the first docs change after
  the merge (`docs/adr/README.md` §2).
- Date: 2026-09-29. Written before the implementation, against `9df450b9` (`origin/main` and
  `fix/pg-326-quit-unsaved-notes` are the same commit). Every line number below was read from that
  tree.
- **Numbering note.** `0072` is the highest ADR on `origin/main`. No local or remote-tracking branch
  holds a `docs/adr/0073*` file (checked 2026-09-29 with `git ls-tree` over every ref). Two unmerged
  worktrees hold an ADR-0071 of their own; that collision is theirs. Check again immediately before
  the merge (`docs/adr/README.md` §1).
- Source: the `PG-326` entry in `TODO.md`, which is the brief. There is no SPEC for this chain: the
  repo-root `SPEC.md` belongs to PG-138/141/142 (merged) and is not its input. Plan:
  `docs/plans/pg-326-quit-unsaved-notes.md`, which declares R-01 to R-18.
- **Extends ADR-0012 §D3 (closing a dirty tab asks), ADR-0060 §D2 (the quit hook and its 2 s diary
  cap), ADR-0066 §D5 (the board settles first on quit), ADR-0058 §D3 and ADR-0067 §D2 (the writer is
  named by tab id). Amends none.** Explicit saving (ADR-0012 §D3) is not reopened. No on-disk
  format, frontmatter key, `IndexCache.schemaVersion` or protected interface changes.

## Context

### The defect

Notes save explicitly: Cmd+S, the tab strip's «Salva» chip, or «Salva» in the dialog that closing a
dirty tab raises. Quitting asks nothing. With a dirty tab open, Cmd+Q exits in about a second and the
edits never reach disk. Reproduced twice by hand on a Debug build of `1061bcc1` over a throwaway
vault (`TODO.md`, PG-326).

### Evidence (facts, read at `9df450b9`)

- **F1.** `AppDelegate.applicationShouldTerminate(_:)` (`Sources/App/PergamenumApp.swift:40-54`)
  calls `vault?.openBoard?.settleForTermination()`, then returns `.terminateNow` when the diary is
  settled, or `.terminateLater` racing `diary.settle()` against a 2 s sleep, the first to finish
  calling `replyToTerminate()` (`:58-62`, guarded by `owesTerminateReply`). Nothing in it reads a
  note tab.
- **F2.** A tab's buffer is `NoteTab.note` (`Sources/Vault/NoteTab.swift:78-92`):
  `hasUnsavedChanges` is `text != savedText`, and `externalChangePending` is non-nil while the
  conflict banner is waiting for an answer (ADR-0064 §D3). Tabs live in
  `VaultController.columns` (`Sources/App/VaultController.swift:46`), one or two columns.
- **F3.** `saveOpenNote()` (`Sources/App/VaultController+Editing.swift:31-39`) writes the
  **focused** tab through `session.write(_:to:origin:)` with no precondition, and on failure records
  a problem and returns `Void`. The caller cannot tell whether anything landed.
- **F4.** `focusTab(_:)` reaches only the focused column (`VaultController+Tabs.swift:208-216`).
  Saving a tab of the other column means focusing that column first.
- **F5.** The writer's catch-up is found by id, in every column (`VaultController+TabFollowUps.swift:46-55`):
  the tab named by `origin` takes `savedText`; every other tab on the same path runs
  `catchUp(to:)`, which raises the banner on a dirty buffer (`NoteTab.swift:118-135`). Two dirty tabs
  on one path therefore cannot both be saved silently: the second becomes conflicted when the first
  lands.
- **F6.** The tab-close dialog's «Salva» (`Sources/Features/Editor/EditorColumn+Closing.swift:39-49`)
  awaits `saveOpenNote()` and then calls `closeTab` **unconditionally**: a save that fails closes the
  tab anyway, and the edits go with it.
- **F7.** Cmd+W is «Chiudi tab» (`ShortcutCommand.closeTab`, `KeyBinding("w", .command)`), run by
  `CommandActions.runTab` (`Sources/App/CommandActions.swift:143-144`) as
  `vault.closeFocusedTab()`, which calls `closeTab` directly (`VaultController+Tabs.swift:83-86`).
  The dialog ADR-0012 §D3 asks for is raised only by the tab chip's close button
  (`EditorColumnView.swift:74`, `requestClose`). Cmd+W on a dirty tab discards it without asking.
- **F8.** The main scene is a single `Window("Pergamenum", id: "main")` (`PergamenumApp.swift:256`)
  and the delegate does not implement `applicationShouldTerminateAfterLastWindowClosed`. Apple's
  SwiftUI `Window` documentation (fetched 2026-09-29): «If your app uses a single window as its
  primary scene, the app quits when the window closes.» The red button is a quit, reached after the
  window has already gone.
- **F9.** AppKit, fetched 2026-09-29: `.terminateLater` «causes Cocoa to run the run loop in the
  modal panel mode until your app subsequently calls `reply(toApplicationShouldTerminate:)`» and «is
  for delegates that need to provide document modal alerts (sheets) in order to decide whether to
  quit». `NSDocumentController.reviewUnsavedDocuments(...)` is «called when the user chooses the
  Quit menu command, and also when the computer power is being turned off», which is AppKit's own
  evidence that power-off and logout reach the same terminate path.
- **F10.** The built Debug `Info.plist` (DerivedData, 2026-09-29) declares neither
  `NSSupportsSuddenTermination` nor `NSSupportsAutomaticTermination`. Per `ProcessInfo`'s
  documentation the sudden-termination counter starts at 1 (disabled) and automatic termination has
  no effect without the opt-in. Nothing in `Sources/` calls `enableSuddenTermination`.
- **F11.** `NSAlert.addButton(withTitle:)` (fetched 2026-09-29): the first button gets Return, a
  button titled «Cancel» gets Escape, «Don't Save» gets Cmd+D. The defaults key on English titles, so
  «Annulla» and «Non salvare» get none unless they are assigned.

### The ledger's second claim, corrected

PG-326 says SPEC line 235 «still says "autosalvataggio continuo, ~1 s", which ADR-0012 replaced».
Line 235 is §6.1, the **Workspace** top bar, and the board does autosave about a second after a
change (ADR-0022 F10, `WorkspaceController.autosaveDelay`). The line is right about what it
describes. The actual drift is two things. SPEC §5 (the editor) says nothing about how a note is
saved, so §6.1's sentence is the only saving rule a reader finds. And the note editor's top bar
borrowed the board's wording: `VaultTopBar.swift:40` shows «Salvataggio…» ("saving…") for a dirty
note, when nothing is saving it. That label is what the reproduction read as an autosave in
progress.

### Found while reading, outside this defect

- **G-a. A vault switch keeps the previous vault's tabs.** `open(_:)` (`VaultController.swift:196`)
  never resets `columns`, `close()` (`:257`) has no production caller, and `restoreTabs()` returns
  early when the focused column has tabs (`VaultController+Session.swift:35`). A dirty tab of vault A
  saved after switching to B is written into B at the same relative path. Read, not run. Not a quit
  path; recommended as its own P1 entry.
- **G-b. «Chiudi la colonna» drops the column's tabs, dirty ones included, without asking**
  (`MenuCommands.swift:41`, `VaultController+Tabs.swift:189-194`).
- **G-c. A conflicted board and a conflicted diary lose their in-memory edits at quit.**
  `settleForTermination()` skips a conflicted board (ADR-0066 §D5) and the diary's `performWrite`
  returns on `.conflicted`. Both follow earlier decisions (ADR-0054 §D5 for the board: "refusing to
  close a window over an autosave conflict is worse than the loss it prevents"). Reviewing them at
  quit would reopen those decisions, so this record leaves them alone.
- **G-d.** Cmd+S over a banner that is still waiting writes the buffer over the other writer's
  bytes, because `saveOpenNote()` has no precondition (a blind write in ADR-0043 §D8's sense). That
  is existing behaviour and stays as it is here. §D5 only keeps the quit's own bulk answer from
  doing it without being asked.

## Decision

### §D1 · One door: every termination reviews the dirty note tabs before anything replies

`applicationShouldTerminate(_:)` stays the one hook, and it delegates to a `@MainActor`
`QuitCoordinator` (`Sources/App/QuitCoordinator.swift`). Its order:

1. The board settles, synchronously, as today (ADR-0066 §D5).
2. **The notes phase.** A pure `QuitReview` (`Sources/App/QuitReview.swift`) is built from
   `vault.columns`: every tab in every column with `hasUnsavedChanges`, column order then tab order,
   each entry carrying its tab id, path, title, the text shown, and whether it is conflicted
   (`externalChangePending != nil`). When it is empty, the coordinator behaves exactly as today's
   delegate (R-10). Otherwise it asks (§D2), and the answer decides the rest (§D4, §D5).
3. **The diary phase.** It is unchanged (ADR-0060 §D2) and starts only after the notes phase has
   finished.

Cmd+Q, «Esci da Pergamenum», the red button on the last window (F8) and logout, restart or shutdown
(F9) all arrive through `terminate:`, so they share this door with no code of their own. The
remaining question is whether the red button really does, and §D8 settles it with a probe.

### §D2 · What quitting asks: one question for all the dirty notes (HITL G1)

**Recommended, pending G1: one app-modal alert, «Salva tutto / Non salvare / Annulla».**

- One dirty note: «Salvare le modifiche a «Titolo» prima di uscire?», buttons «Salva» / «Non
  salvare» / «Annulla». These are the tab-close dialog's words (ADR-0012 §D3), so the question does
  not change language between closing a tab and quitting.
- Several: «Salvare le modifiche a N note prima di uscire?», with the titles listed in the
  informative text (at most eight, then «e altre K»; a title shared by two different paths shows
  the path), buttons «Salva tutto» / «Non salvare» / «Annulla». N counts notes, not tabs: the same
  note open in both columns is one line.
- A conflicted note is named in the informative text before anything is decided: «"Titolo" è
  cambiata anche su disco: Pergamenum resta aperto per farti scegliere quale versione tenere.»
- Return saves, Escape is «Annulla», and «Non salvare» carries `hasDestructiveAction`. The key
  equivalents are assigned explicitly, because NSAlert's defaults key on English titles (F11).

**Why one question.** A quit is one decision about one moment. The usual case, one or two dirty
notes, is answered with one keystroke. The notes are listed, so nothing is decided blind.

**The alternative, per-document review (the NSDocument convention).** The question would read «Ci
sono N note non salvate. Vuoi rivederle prima di uscire?», with «Rivedi… / Non salvare / Annulla».
«Rivedi» walks the notes one at a time with the tab-close dialog, and «Annulla» at any step cancels
the quit. It fits a person who wants to keep some notes and drop others at quit time. It costs N
sheets for N notes, and it is a second flow to build and test. With G1 answered that way, §D3's
presenter runs the per-note loop instead, and everything in §D4 to §D8 stands unchanged.

**Rejected: autosave on quit without asking.** ADR-0012 §D3 already declined this: it "would remove
the risk and quietly end explicit saving, which is a bigger decision than a tab close should make".
A quit is not a better place to make it.

### §D3 · The question is an `NSAlert` run app-modally before any `.terminateLater`

`QuitReviewAlert` (`Sources/App/QuitReviewAlert.swift`) builds an `NSAlert` from the copy §D2 names
and calls `runModal()` synchronously, inside `applicationShouldTerminate`, before the coordinator has
returned anything. Three consequences follow:

- **No timer is running while the person reads.** The 2 s diary cap is started only by the diary
  phase, after the answer, so it cannot cut the question short.
- **It works with no window.** On the red-button path (F8) the window is gone before the delegate is
  asked. A sheet would have nothing to attach to, and a SwiftUI `.confirmationDialog` has no view to
  hang from.
- **There is no dependence on SwiftUI rendering under `.terminateLater`.** Whether a SwiftUI
  presentation draws while the run loop is in modal panel mode was not verified, and this route does
  not need to know.

Rejected: a sheet on the main window (`beginSheetModal(for:)`) under `.terminateLater`. F9 says
AppKit supports it, but it needs a second presentation for the no-window path, and it puts the
question inside the reply window, which is exactly where the cap composition becomes fragile.

The alert draws no colour and no font of its own, so the token rule (`CLAUDE.md`, Design system) has
nothing to check. It is a system alert, as the tab-close dialog already is.

### §D4 · One save door, by tab id, that says what happened

`VaultController.saveTab(_ id: NoteTab.ID) async -> TabSave`
(`Sources/App/VaultController+Editing.swift`) finds the tab in **any** column by id, returns `.clean`
when it is not dirty or no longer exists, and otherwise writes `note.text` through
`session.write(_:to:origin: id)`. It returns `.saved` or `.failed(String)`, and records the problem
as `saveOpenNote()` does today. `TabSave` is `enum { saved, clean, failed(String) }`.

- `saveOpenNote()` becomes `guard let id = focusedTab?.id; _ = await saveTab(id)`. Its signature,
  its five call sites and Cmd+S's behaviour are unchanged: no precondition, and a pending banner does
  not stop Cmd+S (G-d).
- The writer's catch-up needs nothing new: `origin: id` already routes it by id across columns (F5).
- The tab-close dialog's «Salva» closes the tab only on `.saved` or `.clean` (F6). On `.failed` the
  tab stays open and dirty, and the problem is recorded. This is the same rule §D5 applies to quit:
  a save that did not land never drops the buffer.

The door does no focusing, so saving a background tab no longer needs the focus dance
`closeAfterSaving` performs. `closeAfterSaving` keeps its `focusTab` step, though, because the
dialog is about the tab in front of the person.

### §D5 · «Salva tutto»: sequential, re-read after every suspension, never past a conflict

`VaultController.saveForQuit(_ review: QuitReview) async -> QuitSaveReport`
(`Sources/App/VaultController+Quit.swift`):

- It re-reads `columns` before each write (ADR-0043 §D7: the set read before an `await` is a filter,
  not a guard) and saves, in the review's order, each entry that is **still** dirty and **not**
  conflicted.
- A conflicted tab is never written by the bulk answer. That covers a tab conflicted from the start
  and one that became conflicted because an earlier save in the same batch landed on its path (F5).
- The report lists what was saved, what failed and what was left conflicted.

The coordinator lets the app terminate only when a fresh `QuitReview` built after the saves is
empty. Anything else is answered `reply(false)`, and three things follow: the first unresolved tab is
revealed (§D7), a problem is recorded naming the notes left unsaved, and the notes already saved
stay saved. «Salva tutto» therefore saves everything that can be saved, and a quit never leaves a
buffer on the floor.

### §D6 · One reply, three phases, two caps with opposite polarity

- The question is not capped. It waits for the person (§D3).
- The note saves run under `.terminateLater` with a **fail-safe** cap, `QuitReview.noteSaveCap = 10
  s`. When it elapses, the coordinator replies `false` (cancel), not `true`, and records «Uscita
  annullata: il salvataggio di "Titolo" non è terminato». This is ADR-0060 §D2's reasoning ("a
  disk that does not answer must not turn «Esci» into a hang") with the polarity reversed. The
  diary's text can be retried after a cap, while a note buffer lost to a terminate cannot.
  Without the cap, a hung write would leave the app stuck in modal panel mode, and the person's
  only way out would be Force Quit, which loses everything. Ten seconds leaves room for an
  iCloud-backed write, and it is short enough that a hang does not pass for a crash.
- The diary phase keeps its fail-open 2 s cap and its two independent tasks (ADR-0060 §D2's reason
  against a task group stands). It starts after the notes phase.
- **Exactly one reply.** `owesTerminateReply` moves into the coordinator. `reply(_:)` is the only
  path to `NSApp.reply(toApplicationShouldTerminate:)`, and it is a no-op once used, so whichever of
  the note cap, a failed save, the diary settle or the diary cap comes first decides, and every
  later caller finds the debt paid.
- **The last check before letting go.** Immediately before `.terminateNow` or `reply(true)`, the
  coordinator rebuilds `QuitReview`. A dirty tab that the answer did not cover (§D7) turns the reply
  into a cancel. Keystrokes should not reach the editor in modal panel mode; the check does not rely
  on that.

### §D7 · What an answer covers, and what a cancelled quit shows

- «Non salvare» covers the snapshot the question showed: each entry's tab id **and** text. At reply
  time, a dirty tab whose `(id, text)` is not in that snapshot is uncovered work and cancels the quit.
- «Salva tutto» covers nothing it did not save (§D5).
- «Annulla» returns `.terminateCancel`. Tabs, texts and dirty states are untouched and nothing is
  written.
- Any cancel, whether «Annulla», a failed save, a conflict, the cap or uncovered work, **reveals**:
  the main window is reopened if it was closed (the red-button path), the Note pane is selected, and
  the first unresolved tab is brought to the front of its column. That is a new door,
  `VaultController.revealTab(_:)`, which does `focusColumn` then `focusTab`, since `focusTab` alone
  stays in the focused column (F4). Reopening goes through the `OpenWindowAction` that `RootView`
  reads from `@Environment(\.openWindow)` and hands to `VaultController` as an observation-ignored
  hook, the same shape as `openBoard` (ADR-0066 §D5): it serves the quit path alone.

### §D8 · The other termination paths, and the two measurements this record cannot make

- **Logout, restart, shutdown** reach `terminate:` (F9) and so this door. Annulla there cancels the
  logout. This can only be checked by hand (M6 in the plan).
- **Sudden and automatic termination** are off (F10). A unit test pins it, because the moment either
  is switched on, the system may kill the process without asking the delegate anything. The test
  asserts that neither `Info.plist` key reads `true` and that
  `ProcessInfo.processInfo.automaticTerminationSupportEnabled` is `false` in the hosted test run.
- **Probe P1, red button with a dirty tab** (Debug build, a log line in the coordinator). Outcome A,
  expected from F8: the delegate is asked after the window is gone, the alert shows with no window,
  and «Annulla» reopens the window with the tab still dirty. Nothing more to do. Outcome B: the
  delegate is not asked, and the app exits. Then the delegate implements
  `applicationShouldTerminateAfterLastWindowClosed(_:)` and answers `false` while `QuitReview` is not
  empty: the app stays running without a window, and the next Cmd+Q, logout or Dock reopen meets the
  buffers intact. Record the outcome in this ADR's implementation notes.
- **Probe P2, `XCUIApplication.terminate()` with a dirty tab.** Apple's documentation says only
  that "an appropriate platform-specific mechanism terminates the process". If a UI test's teardown
  reaches the delegate, a test that leaves a note dirty would now hang on the alert until the launch
  timeout, the 60.2 s signature. Remedy decided in advance: that test saves or reverts its note
  before teardown. **No launch flag switches the review off.** A flag that disables the safety net is
  the one thing a UI suite must not need, unlike `-disableUpdater`, which keeps a network feature
  out of a test.

### §D9 · The seams, and the tests they allow

- `QuitReview` is pure and Foundation-only. It holds the snapshot, the copy of §D2, the coverage
  rule of §D7 and the caps. It lives in `Sources/App` rather than `Sources/Core` because it reads
  `NoteTab`, which is app-only (`NoteTab.swift` extends `VaultController`), and no connector needs
  it. `ConflictBannerCopy` is the precedent for copy decided outside a view (ADR-0053's seam shape).
- `QuitCoordinator` takes everything AppKit-shaped as closures: `ask`, `reply`, `reveal`, `sleep`.
  It returns its own `QuitReply { now, later, cancel }`, which the delegate maps to
  `NSApplication.TerminateReply`. The tests drive it with a fake `ask`, a recording `reply` and an
  instant `sleep`, over a real `VaultController` on a `TemporaryVault`. `DiarySettleTests`' header
  calls the delegate method itself "not unit-testable"; this puts all of it except the mapping
  behind a seam.
- `QuitReviewAlert.make(_:)` builds the `NSAlert` without running it, so a test reads the button
  titles, their order, their key equivalents and `hasDestructiveAction`.
- **GUI tests (HITL G2): one, recommended.** The defect lives exactly where no in-process test
  reaches: AppKit's terminate calling the delegate, which calls the review. One method in
  `UITests/QuitReviewUITests.swift` covers it. It types into a note, sends Cmd+Q, expects the alert,
  answers «Annulla», and expects the app still running with the «Salva» chip present. Then it sends
  Cmd+Q again, answers «Salva», waits for `.notRunning`, and reads the file. The class passes
  `-disableCalendar YES`, `-disableUpdater YES` and `-mailStoreRoot <fixture>`, as every UI-test file
  must, and finds controls by `accessibilityIdentifier` or by the alert's own buttons. The
  alternative, zero GUI tests and hand check M1 alone, is what shipped PG-326.

### §D10 · The indicator stops saying «Salvataggio…», and SPEC §5 states how a note is saved

- `VaultTopBar`'s label reads its words from a pure `NoteSaveIndicator`
  (`Sources/Features/Editor/NoteSaveIndicator.swift`): «Non salvato» with a dirty note, «Salvato»
  otherwise (HITL G3 on the wording; «Modifiche non salvate» is the longer alternative). The glyph
  stays. The board's «Salvataggio…» in `BoardChrome` is untouched, because there it is true.
- SPEC §5 gains one bullet with a dated amendment note: a note is saved explicitly (Cmd+S, the
  «Salva» chip, the tab-close dialog, ADR-0012 §D3). Quitting with unsaved notes asks «Salva tutto /
  Non salvare / Annulla» (this record), and the Workspace's autosave in §6.1 applies to boards, not
  notes. Line 235 is left as it is (see Context).

### §D11 · Cmd+W asks, as ADR-0012 §D3 already said it should (HITL G4)

Recommended in this chain, pending G4. Cmd+W runs `vault.requestCloseFocusedTab()`, which closes a
clean tab at once and, for a dirty one, sets `VaultController.closeRequest` (the tab id,
observable). The column holding that tab moves it into its own `closing` state and clears it. That
raises the existing `UnsavedTabDialog`, the same one the chip's close button raises. No new dialog
and no new copy. `closeFocusedTab()` loses its only production caller and is deleted, together with
its doc comment, which claimed the question had already been answered.

Why here: this record's claim is that no gesture drops a dirty note without asking. With F7 left
open, that claim would be false on the day it merges, and the fix reuses a dialog that already
exists. If G4 says «file separately», §D11 moves to the ledger entry, and this record names F7 as
open in the same way it names G-a to G-c.

G-a (vault switch), G-b («Chiudi la colonna») and G-c (conflicted board or diary at quit) are filed
as their own ledger entries and are not decided here.

## Alternatives considered

- **Per-document review (NSDocument's «Review Changes…»).** A real candidate, kept open as G1's
  alternative (§D2). It was not recommended because it takes N sheets for N notes and needs a second
  flow. It stays viable, and choosing it changes only the presenter.
- **Save silently on quit.** Rejected (§D2): it ends explicit saving by the back door, which
  ADR-0012 §D3 declined.
- **SwiftUI dialog driven by observable state, presented under `.terminateLater`.** Rejected
  (§D3). There is no window on the red-button path. The rendering was not verified in modal panel
  mode. And the cap would have to be suspended around a question that lives inside the reply window.
- **Keep the app alive after the last window closes while any note is dirty
  (`applicationShouldTerminateAfterLastWindowClosed` → `false`) as the primary design.** Not chosen
  as the default, because it makes the red button behave differently depending on state, while §D1
  already routes it through the same door as Cmd+Q. It stays as P1's outcome-B remedy (§D8).
- **Give the quit save a hash precondition (`expecting:` the hash of `savedText`).** Rejected. After
  «Tieni la mia versione», `savedText` deliberately differs from the disk, and after a deletion it
  is `""` (ADR-0064 §D5), so the precondition would refuse exactly the saves the person had just
  chosen, and quitting would loop. The conflicted-tab rule of §D5 protects the other writer's bytes
  without it, and the remaining window, an external write the watcher has not reported yet, is the
  one Cmd+S already has.
- **One `TaskGroup` for the notes and the diary under one cap.** Rejected for ADR-0060 §D2's reason
  (a group waits out a write that ignores cancellation), and because the two phases need caps of
  opposite polarity (§D6).

## Consequences

### Positive

- Quitting never drops a dirty note without asking. The same holds on every path that reaches
  `terminate:`, and on a failed or refused save, a conflict, a hang and work typed after the answer.
- The tab-close dialog's «Salva» stops closing a tab whose save failed (F6). This is a latent loss
  closed in passing.
- One save door by id: the quit and Cmd+S cannot drift, and a background tab can be saved without
  moving the focus.
- The logic that used to be untestable delegate code (`DiarySettleTests`' header) is now under unit
  tests, except for a three-line mapping.

### Negative

- Quitting with unsaved notes takes one more keystroke than it did. That is the point, but it is
  also new friction for someone used to the old ~1 s exit.
- A cancelled quit caused by the save cap can leave a write still in flight that lands later. It is
  harmless (the tab catches up through ADR-0067's door), but the problem message says the save "did
  not finish", and it may finish after all.
- Two tabs on one path with **identical** dirty text: the second becomes conflicted when the first
  lands (F5), and the quit stops at its banner although nothing differs. This is rare, since two
  columns rarely hold the same typed text, and it loses nothing. It is left as it is, because
  changing `catchUp(to:)`'s rule is ADR-0058 §D1's decision, not this one's.
- The UI suite may need teardown changes if P2 shows `terminate()` reaching the delegate (§D8).

### Neutral

- `Sources/App/*` selects the whole GUI suite under `scripts/uitests.sh --affected`
  (`classes_for_path`'s `*` arm), so this chain's merge run is the full 24 tests plus the new one.
- No file format, schema, connector or protected interface changes. `perg` and `pergamenum-mcp`
  compile nothing this record adds.

## Implementation notes

Written by the implementation pass of 2026-09-29, on `fix/pg-326-quit-unsaved-notes`. Gates G1 to G5
were decided at Gate 1/2 as recommended (plan, «Risks and HITL gates»): one alert, one GUI test,
«Non salvato», Cmd+W in this chain, the SPEC §5 text.

**Probes.**

**Pending verification. P1, P2 and R-18 have not been run, and no outcome is recorded for any of
them.** Each needs a person at a Debug build or a run of the GUI suite, and neither was available to
the implementation pass. R-17 (these notes carry P1's and P2's outcomes) is therefore not met yet,
and PG-326 stays open until it is. PG-334 and PG-335 track G-a and G-b, not these checks.

- **P1 (red button with a dirty tab, R-11): pending, hand check on a Debug build (plan M5).** Outcome
  B's remedy (`applicationShouldTerminateAfterLastWindowClosed(_:)` answering `false` while
  `QuitReview` is not empty) is **not** implemented. The fix loop of 2026-09-29 asked whether it could
  ship unconditionally, correct under outcome A as well. The answer is no, for two reasons. Under
  outcome A, answering `false` means AppKit never calls `terminate:` for the red button. The
  question §D1 routes that gesture to would never be asked: the window would close and the app would
  stay running with no window and no question. That is the design Alternatives rejected as the
  default ("the red button behaves differently depending on state"), and shipping it would override
  §D1 and R-11 before the measurement that is supposed to decide between them. Second, whether
  SwiftUI's single-`Window` quit asks the adaptor's `applicationShouldTerminateAfterLastWindowClosed`
  at all has not been verified here: SwiftUI owns `NSApp.delegate` and forwards to the adaptor. A
  unit test would pin the predicate without showing that it is ever consulted. The remedy therefore
  waits for P1. Record the outcome here.
- **P2 (`XCUIApplication.terminate()` with a dirty tab): pending, first `scripts/uitests.sh` run.**
  `QuitReviewUITests` itself ends with the app gone and guards its own teardown with
  `app.state != .notRunning`. Record the outcome of that run here. A 60.2 s failure in another class
  is the sign that `terminate()` reaches the delegate.
- **R-18 (the GUI test): pending, written but never run.** See departure 10.

**Measured.** The unit suite hosted in the app reads
`ProcessInfo.processInfo.automaticTerminationSupportEnabled == false`, and the app's `Info.plist`
carries neither `NSSupportsSuddenTermination` nor `NSSupportsAutomaticTermination`
(`TerminationSupportTests`, green).

**Departures from the letter.**

1. **Quotation marks.** §D2 and §D6 write the conflicted sentence and the cap's problem with
   straight quotes («"Titolo" è cambiata…»), which reads as the ADR's own nesting. The app writes
   «Titolo», the house style of the tab-close dialog and of §D2's own one-note message.
2. **Informative text.** §D2 does not word it for one note. Both forms end with «Uscendo senza
   salvare, le modifiche vanno perse.», the tab-close dialog's sentence («Chiudendo la tab…») for a
   quit; several notes are listed one per line above it, and each conflicted note adds its sentence
   below it.
3. **Problem wording.** A save phase that leaves work records «Uscita annullata: note non salvate:
   «A», «B»» (§D5 asks only that it name them); the cap records «Uscita annullata: il salvataggio di
   «A» non è terminato» (§D6). A failed write also records its own `path: error` problem through
   `saveTab`.
4. **Closure types are `@MainActor`.** The plan's `QuitCoordinator.init` lists plain closure types.
   Every one is `@MainActor`, since the coordinator and everything it calls is. The delegate builds
   the coordinator on first use in a getter, not as a `lazy var`: Swift 6 refuses the async `sleep`
   closure in a lazy initializer («default argument cannot be both main actor-isolated and
   @concurrent»).
5. **`saveTab` with no session.** A dirty tab with no open vault answers `.failed`, not `.clean`: a
   `.clean` would let a quit go on over a buffer nothing wrote.
6. **`saveAndCloseTab` checks the buffer after the save.** Besides `.failed`, a tab still dirty after
   a `.saved` (text typed while the write was suspended) stays open. §D4's rule, «a save that did
   not land never drops the buffer», applied to the part of the buffer the save did not take.
7. **Seams added beside the plan's.** `QuitReview.notes`/`Note`/`displayName(of:among:)`/
   `listedTitleLimit` (the copy's own derivation, reused by the coordinator's problems),
   `QuitCoordinator.diaryCap`, `VaultController.tab(withID:)` (a lookup across columns, used by
   `saveTab`, `saveForQuit` and the tests) and `takeCloseRequest(forColumn:)`, the door through which
   a column clears `closeRequest`.
8. **A stale cap cannot answer a later quit.** Every `shouldTerminate()` bumps an attempt counter,
   and every cap, save and settle task checks it before replying: a cancelled quit's 10 s or 2 s
   task still sleeping when the person quits again finds a different attempt and does nothing.
9. **Cmd+W from another pane.** `closeRequest` is taken with `.onChange(…, initial: true)`, so a
   Cmd+W pressed on a dirty tab while another pane is shown raises the dialog when the Note pane
   next appears, instead of being lost.
10. **The GUI test was written, not run** (the implementation brief excluded the GUI suite). Its
    alert lookup tries `app.dialogs` first and falls back to `app.sheets`.
11. **An open field editor ends before anything is read (fix loop, 2026-09-29).** A GFM table cell
    being typed in reaches the note's text only in `TableGridView.controlTextDidEndEditing`, so a
    review built with the cell still open missed it. A clean note then quit with `.now` and lost the
    cell, and a dirty one was saved without it. `QuitCoordinator` gains a fifth AppKit-shaped closure,
    `commitEditing`, beside §D9's four. It is required, not defaulted. `shouldTerminate()` calls it
    first, before the board settles, so a card commit the resign triggers is flushed by that settle
    and not left in an autosave debounce the quit does not wait on. The delegate passes
    `makeFirstResponder(nil)` on the key window and on the main window when they differ, because a
    sheet in front of the main window is key while the cell behind it keeps its field editor.
    `QuitCoordinatorTests` pins it with two tests: a clean note whose open cell commits is asked
    about, and the review already holds the cell; «Salva tutto» writes the cell.
12. **The «Salva» chip has an identifier.** `NoteTabBar`'s unsaved chip carries
    `accessibilityIdentifier("note-save-chip")`, and `QuitReviewUITests` finds it by that
    identifier, not by its title (§D9, `CLAUDE.md`'s UI-test rule). The alert's buttons are still
    found by title (plan Task 7).
13. **A tab of a previous vault is never written by the quit (fix loop, 2026-09-29).** G-a is real
    on this path: after a vault switch vault A's dirty tabs stay open, and «Salva tutto», the Return
    default, would have written each one's text to its relative path in vault B with no precondition,
    overwriting or creating files there. PG-334 (the general vault-switch fix) stays out of scope; this
    record only keeps the quit's own bulk answer from extending the defect to every background tab of
    both columns. The seam is the root a tab belongs to, `NoteTab.previousVaultRoot` (symlinks resolved and standardized, compared
    through `URL.vaultKey`, the key `RecentVaults`, `OpenTabsStore`, `PinnedTagsStore` and the session id
    already use, since the open panel hands `open(_:)` an unresolved URL and Recents a resolved one; nil
    for a tab of the open vault, with `isFromPreviousVault` derived from it), recorded by
    `VaultController.open(_:)` on every tab still open when a vault with a *different* key replaces the session, only
    while the tab has no record yet (the first time it is found foreign), and cleared there when that
    same root opens again, so A, B, A leaves a tab of A unmarked and able to save into A (a Bool that
    only `showing(_:)` cleared kept refusing an A tab after the return; review finding, 2026-09-29).
    Reopening the same vault marks nothing, and `showing(_:)` clears the record, since it builds a fresh
    tab for a note of the current vault. It is rule R-07's shape applied to a
    second reason: `QuitReview.Entry.isFromPreviousVault` keeps such an entry out of `saveCandidates`,
    and the refusal itself lives in `saveTab(_:)`, the one save door, which writes nothing and
    returns `.failed` with a recorded problem for such a tab - so Cmd+S, the «Salva» chip and the
    close dialog's «Salva», the very paths a cancelled quit points the person to, inherit it and no
    call site can forget it (a check in `saveForQuit` alone left all three writing into the new
    vault; fix loop, 2026-09-29). `saveForQuit` derives `QuitSaveReport.foreign` from the flag: a
    refused save of a flagged tab is `foreign`, not `failed`. The fresh review after the save still
    holds it, so the quit is cancelled, the tab revealed and the notes named (§D7), and the
    question's text names the note and says it is not saved into this vault. The question counts notes by (root, path), not path alone: a previous vault's `Nexion.md` and the open vault's are two notes, and the foreign copy is named with its folder, `Nexion.md (A)`.
    «Non salvare» is unchanged. Rejected: recording the vault root on every tab at creation (nine call
    sites build tabs; the one place a foreign tab can appear is `open(_:)`), and refusing the quit
    outright at `open(_:)` (a person switching vaults with a dirty tab is PG-334's decision). Pinned by
    `QuitVaultSwitchTests`: the mark, the same-vault case, the A, B, A return (saves into A, reported saved) and A, B, C, B (still foreign), `showing(_:)`, «Salva tutto» writing nothing
    into B (an existing file untouched, a missing one not created), and the coordinator cancelling and
    revealing.
14. **The keyboard goes back after a cancelled quit (fix loop, 2026-09-29).** `commitEditing` made
    the key and main windows resign their first responder on every quit, «Annulla» included, and
    nothing gave it back, so keystrokes after a cancelled quit did not reach the note. `QuitFocus`
    (`Sources/App/QuitFocus.swift`) records each window's first responder before the resign and
    `revealAfterCancelledQuit` restores it **before** the reveal, through one door,
    `QuitFocus.restore(thenReveal:in:)` (the plain `restore()` is private) - every cancel path reaches
    `reveal`, so that is the one place. The order is load-bearing: `revealTab` only moves the model
    (`focusedColumnIndex`) and the revealed column takes the keyboard later, from
    `EditorColumnView`'s `onChange(of: focusedColumnIndex)`; a synchronous restore run after it made the
    old column's editor first responder, `CompletingTextView.becomeFirstResponder` called `onTakeFocus`
    and moved the focus back to that column in the same transaction, so the `onChange` never fired and
    the revealed tab sat in front in one column while the keyboard, Cmd+S and «Salva» acted on the
    other. Restoring first, the reveal is the last word and the `onChange` fires. (An earlier draft of
    this departure claimed the opposite, that the restored view never overrides the reveal; that was
    true only of a reveal that had already taken a first responder, which the reveal alone never does.)
    It restores only a **view still in that window**, never a field editor (the shared editor is
    detached once its cell ends), and only into a window that is still **without** a first responder.
    A quit that goes ahead never restores. Pinned by `QuitFocusTests` on windows built in the test
    and never shown, including a two-column test with a `CompletingTextView` that moves the focus the
    way production does; the delegate's wiring is not covered by a unit test and has not been run in
    the app.

## References

- `TODO.md` PG-326; plan `docs/plans/pg-326-quit-unsaved-notes.md`.
- ADR-0012 §D3, ADR-0043 §D7/§D8, ADR-0053, ADR-0054 §D5, ADR-0058 §D1/§D3, ADR-0060 §D2,
  ADR-0064 §D3/§D5, ADR-0066 §D5, ADR-0067 §D2.
- Apple documentation, fetched 2026-09-29 through the documentation JSON endpoints:
  `NSApplicationDelegate.applicationShouldTerminate(_:)`, `NSApplication.TerminateReply.terminateLater`,
  `NSApplication.reply(toApplicationShouldTerminate:)`,
  `NSDocumentController.reviewUnsavedDocuments(withAlertTitle:cancellable:delegate:didReviewAllSelector:contextInfo:)`,
  `NSAlert.addButton(withTitle:)`, `NSAlert.runModal()`, `ProcessInfo.disableSuddenTermination()`,
  `ProcessInfo.automaticTerminationSupportEnabled`, SwiftUI `Window`, `XCUIApplication.terminate()`.
