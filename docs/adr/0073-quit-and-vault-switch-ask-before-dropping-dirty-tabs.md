# ADR-0073: Quit and vault switch ask the tab-close question before a dirty note tab is dropped

- Status: **proposed**. Implementation not on `main` yet; the flip to `accepted` names the PR that
  closes `PG-326`/#693, its merge hash and its date (`docs/adr/README.md` §2).
- Date: 2026-09-29. Written before the implementation, against `91a0801c` (`origin/main`, branch
  `kepler/693-fix/cmd-q-unsaved-note-edits`). Every line number below was read from that tree.
- **Numbering note.** `0072` is the highest ADR on `origin/main`. `0071` is absent from `main` but
  held by two unmerged branches, each with a different record: `refactor/pg-144-editor-coordinator`
  (`0071-editor-coordinator-feature-controllers.md`) and `kepler/feature/contenitore-section-parsing`
  (`0071-contenitore-managed-document-archive.md`, also on `origin`). No local or remote-tracking
  branch holds a `docs/adr/0073*` file, and `git log --all -- 'docs/adr/0073*' 'docs/adr/0074*'` is
  empty (checked 2026-09-29). One of the two `0071` records will have to move, and it may move to
  `0073`: check again immediately before the merge (`docs/adr/README.md` §1).
- Source: the `PG-326` entry in `TODO.md` (#693) and the brief handed to this chain, whose
  acceptance criteria are R-01 to R-07, plus R-08 added on 2026-09-29 when Stefano moved the
  vault-switch path into scope. There is no SPEC for this chain: the repo-root `SPEC.md` belongs to
  `PG-138`/`PG-141`/`PG-142` and is not its input. Plan: `docs/plans/pg-326-quit-unsaved-note-tabs.md`.
- **Extends ADR-0012 §D3 (its question now also guards quit and vault switch), ADR-0060 §D2 (the
  terminate hook gains a phase in front of it; the 2 s cap stays and stays on the diary), ADR-0066
  §D5 (the board still settles on quit, after the question), ADR-0067 §D2 (the `origin` a save
  hands the session) and ADR-0012 §D10 (a vault switch now restores the incoming vault's own tabs).
  Amends ADR-0058 §D1 narrowly: a dirty buffer whose text already equals the incoming text adopts
  it instead of asking (§D4).** No on-disk format, frontmatter key, `IndexCache.schemaVersion`
  (stays 5), protected interface or connector behaviour changes.

## Context

### The defect

Quitting with unsaved edits in a note tab exits with no question, and the edits never reach
disk. Reproduced twice by hand on `1061bcc1`: text typed, the top bar reading «Salvataggio…»,
Cmd+Q, file unchanged. The same loss, by a different route, happens on a vault switch.

### Evidence (facts)

- **F1.** `AppDelegate.applicationShouldTerminate(_:)` (`Sources/App/PergamenumApp.swift:40-53`)
  settles the open board (`vault?.openBoard?.settleForTermination()`), then waits up to 2 s for the
  diary. It never reads `vault.columns`.
- **F2.** Unsaved text lives only in memory, one buffer per tab: `OpenNote.text` against
  `savedText`, `hasUnsavedChanges` (`Sources/Vault/NoteTab.swift:81-92`). The same path can be open
  in two tabs, in either column (`updateTabs(showing:_:)`, `Sources/App/VaultController+Tabs.swift:262-269`).
- **F3.** `saveOpenNote()` (`Sources/App/VaultController+Editing.swift:31-39`) writes the focused
  tab only, through `session.write(_:to:origin:)`, with no `expecting:`. A pending external change
  is overwritten.
- **F4.** The session announces a landed write before `write` returns, and `landed(_:)`
  (`Sources/App/VaultController+TabFollowUps.swift:46-55`) gives the writer tab its `savedText` and
  runs `catchUp(to:)` on every other copy. For a dirty buffer, `catchUp` raises the prompt whatever
  the incoming text is (`NoteTab.swift:118-122`), including when it is byte-identical to the buffer.
- **F5.** Closing a dirty tab asks Salva / Non salvare / Annulla (`Sources/Features/Editor/EditorColumn+Closing.swift:24-79`),
  which is ADR-0012 §D3. No other gesture that drops a buffer asks.
- **F6.** The vault switch has two UI entry points. «Apri cartella note…» runs
  `VaultOpenPanel.chooseVault(into:)` (`Sources/App/VaultOpenPanel.swift:10-19`), reached from
  `CommandActions.run(.openVault)` (`Sources/App/CommandActions.swift:181-182`) and from the two
  empty states in `RootView.swift:361,378`, which show only while no vault is open. «Cartelle
  recenti» calls `vault.open(url)` directly (`Sources/App/VaultCommands.swift:90-95`). The launch
  path calls `open(_:)` only while `root == nil` (`PergamenumApp.swift:306-307`).
- **F7.** `open(_:)` (`Sources/App/VaultController.swift:196-254`) never resets the columns.
  `close()` does (`:265-269`), and nothing in `Sources/` calls `close()`. `restoreTabs()` returns
  early unless the focused column is empty (`Sources/App/VaultController+Session.swift:35`). So after
  a switch, the outgoing vault's tabs, clean and dirty, stay on screen and are resolved by relative
  path against the incoming session; the incoming vault's arrangement is never restored; the next
  `rememberTabs()` records the outgoing tabs under the incoming root; and Cmd+S on a carried tab
  writes its text into the incoming vault at that relative path. This is a static trace, not a hand
  reproduction. The one test that models a switch with tabs,
  `NoteTabGestureTests.twoVaultsRememberTheirOwnTabs` (`Tests/NoteTabGestureTests.swift:311`), calls
  `close()` between its two `open(_:)` calls, which production never does. The brief assumed
  `open(_:)` resets the columns; it does not.
- **F8.** `closedTabPaths` and `recentNotePaths` (`VaultController.swift:85,92`) are reset by
  neither `open(_:)` nor `close()`.
- **F9.** `VaultTopBar.swift:38-45` shows «Salvataggio…» with `arrow.triangle.2.circlepath` whenever
  the focused tab is dirty. No note save is in progress at that moment: notes have no autosave. No
  file under `Tests/` or `UITests/` matches «Salvataggio…» or the note bar's «Salvato» (checked with
  `rg`, 2026-09-29). `BoardChrome.swift:49` keeps its own «Salvataggio…», which is true there.
- **F10.** SPEC line 235 sits in §6.1, the Workspace, and describes the board's indicator. The board
  does autosave after about 1 s (`WorkspaceController.swift:183`). The SPEC states the note save model
  nowhere (`rg "autosalv|Cmd\+S|salva"` over `docs/20260811_Pergamenum_SpecApp.md`). The brief read
  line 235 as a stale claim about notes; it is a correct claim about boards.
- **F11.** The installed macOS 27.0 SDK headers, read 2026-09-29: after `NSTerminateLater` the app
  must call `replyToApplicationShouldTerminate:` with YES or NO once the answer is known
  (`NSApplication.h:314,409`). `NSAlert` gives Escape by default only to a button titled "Cancel" and
  Cmd+D only to "Don't Save" (`NSAlert.h:96`), so Italian titles need explicit key equivalents.
  `hasDestructiveAction` is a supported alert button property (`NSAlert.h:104`, `NSButton.h:88`).
- **F12.** Sparkle's `SPUUserDriver` documentation (sparkle-project.org, read through Context7 on
  2026-09-29): when an install asks the app to quit and the app delays or cancels, Sparkle waits and
  hands the user driver a `retryTerminatingApplication` callback.
- **F13.** `AppDelegate` is AppKit lifecycle and has no unit test (`Tests/DiarySettleTests.swift`
  header). The seams under test are `DiaryController.settle()` and
  `WorkspaceController.settleForTermination()` (`Tests/WorkspaceLifecycleTests.swift`).

## Decision

### §D1 — One question guards every gesture that drops a dirty note tab

ADR-0012 §D3's question, Salva / Non salvare / Annulla, now also guards the quit and the vault
switch. Explicit saving stays (ADR-0012 §D3): nothing is autosaved on quit or on a switch, and
this is a deliberate "no", not an omission. The question is about note tabs only. The Workspace
board autosaves and settles on quit (ADR-0066 §D5). The diary settles on quit (ADR-0060 §D2).

What counts as dirty is one read, `VaultController.unsavedTabs: [NoteTab]`, which returns every
tab in every column with `hasUnsavedChanges`, in column order and then tab order. It lives beside
the other column doors in `VaultController+Tabs.swift`. Quit and switch ask this, never the
focused column alone. `canOperate(on:)` and `updateTabs(showing:)` already follow that rule
(ADR-0056 §D1).

### §D2 — One prompt, one presenter, one decision

- **`UnsavedNotesPrompt`** is a pure value in `Sources/App/UnsavedNotesPrompt.swift`. `init?(tabs:)`
  returns nil for no tabs. It counts **notes, not tabs**: two tabs on one path are one note. Titles
  keep first-appearance order.
  - The message is «C'è una nota con modifiche non salvate» for one note, and «Ci sono N note con
    modifiche non salvate» for more.
  - The informative text lists the titles, at most `listedTitleLimit` (8) of them, then «e altre K»
    («e un'altra» when K is 1, never «e altre 1»), followed by one sentence saying the unsaved
    edits are lost if not saved.
  - The value is unit-tested. The Italian singular and plural are part of the contract.
- **`UnsavedNotesChoice`** is `saveAll`, `discard` or `cancel`.
- **`UnsavedNotesPresenter`** holds two main-actor closures. `ask(_:) -> UnsavedNotesChoice` asks.
  `reportUnsaved(_:)` says the gesture did not go ahead because notes are still unsaved (§D5, §D6).
  Production uses one value, `UnsavedNotesPresenter.alert`, in `Sources/App/UnsavedNotesAlert.swift`,
  the only file that touches AppKit for this. Tests inject closures that record their calls.
- **The alert.** `NSAlert` with `.warning` style. Buttons are added in the order «Salva tutto»,
  «Annulla», «Non salvare»: first is Return, second has an explicit Escape, third has an explicit
  Cmd+D and `hasDestructiveAction` (F11). Before `runModal()` the app is brought forward with
  `NSApp.activate()`, because a quit from the Dock or a logout can arrive while another app is
  frontmost. A quit with unsaved work is a user-triggered path. Only the third button's response
  maps to `.discard`; every other modal response (the second button, or a modal ended by
  `stopModal`/`abortModal`) maps to `.cancel`, so an unrecognised answer keeps the notes.
- **The decision.** `VaultController.unsavedTabsDecision(asking:) -> UnsavedNotesChoice?` returns
  nil, without calling `ask`, when nothing is dirty. Otherwise it calls `ask` exactly once with the
  prompt for `unsavedTabs`. Quit and switch both go through it, so they cannot drift in what they
  ask or when.

### §D3 — «Salva tutto» writes through the Cmd+S door, one path at a time

`VaultController.saveAllUnsavedTabs() async -> Bool` lives in the new
`Sources/App/VaultController+UnsavedTabs.swift`:

1. It takes the distinct paths of `unsavedTabs` at the start, in column-then-tab order.
2. For each path in turn, it reads **again, after every previous `await`** (ADR-0043 §D7), which
   tabs showing that path are dirty now:
   - None: the path is skipped.
   - Two or more, with texts that differ: the path is **refused**. Nothing is written for it, and
     the problem «`<path>`: aperta in più tab con testi diversi, non salvata» is recorded. Picking
     one copy would silently discard the other, which ADR-0001 §D3.4 forbids.
   - Otherwise it writes the first dirty tab's text with
     `session.write(text, to: path, origin: tab.id)`. That is `saveOpenNote()`'s door and its
     `origin` (ADR-0067 §D2), so `landed(_:)` catches every other copy up (ADR-0058 §D2).
3. There is no `expecting:`, the same as Cmd+S (F3). A tab whose buffer has a pending external
   change is written over the disk, exactly as Cmd+S would write it today. The person saw the
   banner and asked to save.
4. A write that throws records «`<path>`: `<error>`» (the shape `saveOpenNote` records) and the loop
   goes on. Every path the person asked to save and that can be saved is saved. The whole call
   still reports failure. This is best-effort execution with an all-or-nothing verdict, ADR-0046
   §D3's rule.
5. It returns `true` only when no path failed or was refused **and** `unsavedTabs` is empty at the
   end. A writer tab that received typing during its own suspension keeps that text unsaved (ADR-0058
   §D3). A tab dirtied meanwhile is another case. Either one is recorded as «`<path>`: modificata
   durante il salvataggio, non salvata» and the call returns `false`. The verdict is about the state
   the gesture will act on, not about the writes attempted.

### §D4 — A dirty buffer that already equals the incoming text adopts it

This amends ADR-0058 §D1. In `OpenNote.catchUp(to:)`, a dirty buffer receiving `.text(t)` with
`t == text` takes `savedText = t`, clears any pending prompt and answers `.adopted`. There is
nothing to ask: the buffer and the disk agree. Every other dirty case still answers `.asked`.

The reason is §D3. Two dirty copies of one path with identical text are written once. Without this
rule, the second copy would get a conflict banner about its own text and would stay dirty, so
`saveAllUnsavedTabs` would report a failure that is not one. Fixing that copy up by hand after the
write is the caller-side catch-up step ADR-0067 §D5 removed. The rule belongs in the one place that
decides dirty against incoming, and there it also covers an external change that happens to equal
the buffer, through `reconcile` (`VaultController+Watching.swift:43`).

### §D5 — Quit: the question first, then notes, then board, then diary

`applicationShouldTerminate(_:)` becomes:

1. **The question comes before anything else.** `vault?.unsavedTabsDecision(asking:
   UnsavedNotesPresenter.alert.ask)` runs before the board settles. A cancelled quit must leave
   everything as it was, and `settleForTermination()` commits an open board text edit (ADR-0066
   §D2, "navigating away confirms").
2. **nil** (nothing dirty, or no vault) and **`.discard`** take today's path, unchanged: the board
   settles synchronously, then `.terminateNow` if the diary is settled, otherwise `.terminateLater`
   with the two racing tasks and the 2 s cap (ADR-0060 §D2). «Non salvare» writes nothing.
3. **`.cancel`** answers `.terminateCancel`. Nothing is settled or written, and every buffer is
   untouched.
4. **`.saveAll`** answers `.terminateLater` and starts a task:
   - It awaits `saveAllUnsavedTabs()`.
   - On `true` it continues with the same board-then-diary sequence as step 2. The board settles,
     then it replies `true` at once if the diary is settled, or else starts the same two racing
     tasks. **The 2 s cap still starts only when the diary phase starts**, so it can never let the
     app quit while a note the person asked to save is unwritten.
   - On `false` it replies `false`, the app stays open, and then it calls `reportUnsaved` with the
     prompt for what is still unsaved.
5. **The save phase has its own cap, and that cap cancels.** A second task replies `false` after
   `noteSaveCap` (10 s), records «Salvataggio delle note non concluso entro 10 s: Pergamenum resta
   aperto» and reports. It never replies `true`. Without it, a disk that does not answer would turn
   «Esci» into a hang, and ADR-0060 §D2 exists to rule that out. With it, a slow disk costs a second
   Cmd+Q, never a lost note. The write still in flight lands later, while the app is open.
6. **One reply per attempt.** The existing `owesTerminateReply` flag becomes a reply keyed by a
   per-call attempt number, and `replyToTerminate(_ shouldTerminate: Bool, attempt:)` answers only
   the current attempt's first caller. A save task that finishes after its cap fired does nothing:
   no settle, no reply. Otherwise a finished save could settle the board or answer a *later* Cmd+Q
   that asked its own question.

### §D6 — Vault switch: the UI goes through one door, and `open(_:)` stops carrying tabs across

- **`VaultController.switchVault(to:presenter:) async -> Bool`** is the vault switch the UI uses.
  1. It asks through `unsavedTabsDecision(asking: presenter.ask)`.
  2. `.cancel` returns `false`. The vault and every buffer stay as they are.
  3. `.saveAll` awaits `saveAllUnsavedTabs()`. On `false` it calls `presenter.reportUnsaved` and
     returns `false`, and the switch does not happen.
  4. nil and `.discard` go ahead.
  5. It then awaits `open(url)` and returns `true`.

  The door asks whatever the target is, the open vault included: re-picking the open folder has
  always rebuilt the session, and it keeps doing so, with the question first.
- **The two UI entry points call it:** `VaultOpenPanel.chooseVault(into:)` (after the folder picker,
  so a cancelled picker asks nothing) and «Cartelle recenti» in `VaultCommands.swift`. Both pass
  `UnsavedNotesPresenter.alert`. The empty-state buttons reach it through `chooseVault` and, with no
  vault open, are never asked anything.
- **`open(_:)` stays presenter-free.** The launch path (`root == nil`, no tabs)
  and 54 test files that build a `VaultController` call it (counted with `rg`, 2026-09-29). A
  presenter parameter would either block a test on a modal or default to discarding, and a default
  of discarding recreates the defect for the next caller.
  The asking lives one level up. The residual cost is named in §D8.
- **`open(_:)` closes the outgoing vault's tabs before it swaps the session.** This fixes F7. After
  the `stateBase` guard, before the outgoing session loses its subscriber (`VaultController.swift:225`),
  `open(_:)` calls a new column door, `closeAllTabsForVaultChange()`, in `VaultController+Tabs.swift`.
  - The door does what `close()` already does to the editor: one empty column, focus on it,
    `endNewNote()`. `close()` calls the same door, so the two cannot drift.
  - It does **not** call `rememberTabs()`. The outgoing vault's arrangement is already on record,
    and every tab door wrote it (ADR-0012 §D10). Writing it here would record an empty arrangement
    over it.
  - `restoreTabs()` then finds the column empty and restores the incoming vault's own tabs.
  - At launch the columns are already empty, so nothing changes there.
  - Without this step, «Non salvare» would discard nothing: the dirty buffers would stay on screen,
    bound to the new vault, waiting for a Cmd+S to write them into it. R-08 needs this step to mean
    what it says.

### §D7 — The note top bar stops claiming a save in progress, and the SPEC states the model

- `VaultTopBar` reads «Non salvato» with `pencil.circle` while the focused tab is dirty, and
  «Salvato» with `checkmark.circle` otherwise. It stays on `.themedText(.caption, color:
  .textSecondary)`, tokens only, and gains the identifier `note-save-indicator` (the board's is
  `board-save-indicator`), so a future test finds it by contract, not by words.
- SPEC §5 gains one bullet stating the note save model: explicit save with Cmd+S, and the question
  before a dirty tab is dropped by a tab close, a quit or a vault switch (ADR-0012 §D3, this ADR).
- SPEC line 235 keeps its claim, which is true of boards (F10). It gains one clause scoping the
  autosave to the board and pointing to §5 for notes. Rewriting it would make the SPEC wrong about
  the Workspace.

### §D8 — Named, not fixed

- `closedTabPaths` and `recentNotePaths` survive a vault switch (F8). Cmd+Shift+T and RECENTI can
  then offer a path of the previous vault in the new one. This is a follow-up issue, filed with the
  PR.
- A future caller of `open(_:)` from the UI that forgets `switchVault` would drop dirty tabs without
  asking. Tabs no longer cross vaults, so that loss would be a missed question, not a write into the
  wrong vault. The plan's verification step checks that `rg -n "\.open\(" Sources/App` shows only
  `switchVault`'s own call and the launch path.
- Whether closing the main window quits the app, and so reaches §D5, is not verified. The manual
  checklist records what happens.
- How `XCUIApplication.terminate()` quits the app is not verified. No UI test types into a note
  editor today (`rg` over `UITests/`, 2026-09-29). A future one that leaves a tab dirty could meet
  the alert at teardown.
- A Sparkle install that asks the app to quit with a dirty tab gets the question too. «Annulla»
  leaves Sparkle waiting with its retry (F12). A logout or restart waits for the answer, as it does
  for any document app.

### §D9 — What is tested where

- **Unit tests (Swift Testing, `TemporaryVault`, the `DiarySettleTests` shape):**
  - `Tests/QuitUnsavedTabsTests.swift` pins `unsavedTabs` (focused, background, other column),
    `saveAllUnsavedTabs()`, §D4's catch-up rule, `UnsavedNotesPrompt` and `unsavedTabsDecision`.
    `saveAllUnsavedTabs()` is pinned for: all written, checked through a fresh `VaultSession`;
    identical copies written once and both clean; divergent copies refused with the other paths
    still written; `false` on a write failure; nothing dirty.
  - `Tests/VaultSwitchUnsavedTabsTests.swift` pins `switchVault` and `open(_:)`'s tab reset. For
    `switchVault`: no question when clean; cancel keeps vault and buffers; save-all writes before
    switching; a failed save aborts and reports; discard switches with the files unchanged. For the
    reset: a switch shows the incoming vault's tabs, and switching back restores the outgoing ones.
- **By hand:** the `AppDelegate` sequencing, the alert's keys and position, and the save-phase cap.
  The plan's checklist covers them against a Debug build on throwaway vaults.
- **Zero new GUI tests.** The one thing they would add is driving an app-modal alert raised inside
  `applicationShouldTerminate`. That means quitting the app under XCUITest, which is exactly the
  teardown path the suite must keep clean (§D8). The GUI suite is a bounded backstop (`CLAUDE.md`).

## Alternatives considered

- **Autosave every dirty tab on quit and on switch, with no question.** This is the common app
  behaviour and the smallest change. Rejected: ADR-0012 §D3 keeps explicit saving and rejects
  autosave-on-close as "a bigger decision than a tab close should make". A quit is no smaller. It
  would also overwrite a pending external change with nobody asked, which ADR-0001 §D3.4 refuses.
- **The `NSDocument` shape: «Rivedi le modifiche…», then one question per note.** Rejected: a note
  tab is not an `NSDocument`, and building the review loop means focusing each tab in each column in
  turn inside `.terminateLater`. That is many clicks and much state for a question the brief settles
  in one. Brief decision D-a, confirmed by Stefano.
- **A SwiftUI `confirmationDialog`, like the tab close.** Rejected: `applicationShouldTerminate`
  has no view. It would have to return `.terminateLater`, post state to a view that may not exist
  (window closed), and reply from that view's button. That is two presenters in practice, one for
  quit and one for the switch menu. An `NSAlert` works from the delegate and from a menu action
  alike, and the switch path already runs `NSOpenPanel.runModal()`.
- **The question inside `open(_:)`.** Rejected (§D6): the launch path and 54 test files call
  it. A presenter parameter either blocks a test on a modal or defaults to discarding, and the
  latter reinstates the defect silently for new callers.
- **Fix identical copies up inside the save loop, after the write.** Rejected (§D4): a caller-side
  catch-up step, the shape ADR-0067 §D5 removed.
- **Pass `expecting:` in `saveAllUnsavedTabs`.** Genuinely safer against a concurrent writer, but
  rejected: Cmd+S passes none (F3), and a refusal at quit would strand the person with a question
  they cannot resolve without leaving the quit. The brief chose consistency with Cmd+S (D-b). A
  guarded note save is a decision for Cmd+S first, and this path would follow it.
- **Stretch the existing 2 s cap over the note saves.** Rejected: that cap replies `true`, so a
  slow disk would quit with notes unwritten, which is the defect itself.
- **No cap on the note save phase.** Rejected (§D5): a hung write would hang «Esci», undoing ADR-0060
  §D2's stated property.
- **Treat a re-pick of the open vault as a no-op.** Considered for safety. Rejected for uniformity:
  it changes what re-picking the folder has always done (rebuild the session, reload settings and
  vocabulary), and the question already protects the buffers.

## Consequences

### Positive

- Quit and vault switch never drop a dirty note tab without asking, in any column.
- One prompt, one presenter and one decision serve both gestures, and ADR-0012 §D3's tab close stays
  as it is.
- A vault switch finally shows the incoming vault's own tabs and leaves the outgoing arrangement on
  record. A carried tab can no longer write into the wrong vault (F7).
- Two identical copies of a note stop raising a conflict about their own text (§D4).
- The top bar stops saying a save is in progress when none is.

### Negative

- A quit can now be refused, by «Annulla», by a failed save or by the save-phase cap. Each refusal
  is explained with a second alert and a recorded problem. The cap's 10 s is a judgement, and a slow
  iCloud write can meet it.
- One more modal on quit for anyone with dirty tabs, and it also holds a logout or a Sparkle install
  until answered.
- `open(_:)` changes for a controller that already has tabs: they close. The six unit tests that
  switch vaults on one controller were read for it (listed in the plan). None asserts carried tabs,
  but the full suite is the check.
- The asking lives at the UI call sites, not in `open(_:)`. It is a door that can be bypassed, and
  a grep check stands in for the compiler (§D8).

### Neutral

- Nothing on disk changes shape. `perg` and `pergamenum-mcp` do not compile `Sources/App` and are
  untouched.
- The board and diary quit paths are byte-for-byte today's when nothing is dirty or «Non salvare»
  is chosen.

## Open for Stefano

- **G1.** The failure alert (`reportUnsaved`) is an addition to D-a, which says only "problem
  recorded". Recommended: keep it. The problem list is in Impostazioni › Avanzate, and a Cmd+Q that
  silently does nothing reads as a hang.
- **G2.** The note save-phase cap: 10 s, and it cancels the quit. Recommended as written.
- **G3.** `open(_:)` closing the outgoing tabs (§D6) goes beyond the brief, which assumed it already
  did. Recommended: yes, since R-08's «Non salvare» is otherwise meaningless.
- **G4.** SPEC: a §5 bullet plus a scoping clause on line 235, instead of rewriting line 235
  (§D7, F10).
- **G5.** §D4 narrows ADR-0058 §D1's dirty branch.
- `CLAUDE.md`'s chain decision index gains an ADR-0073 line after the merge. Not in this chain: the
  brief forbids editing `CLAUDE.md` in it. One possible working agreement, for Stefano to decide:
  a test that models a production flow calls the production door. `twoVaultsRememberTheirOwnTabs`
  called `close()` between two opens, which production never does, and so hid F7.

## References

- `Sources/App/PergamenumApp.swift:40-62` (`applicationShouldTerminate`, `replyToTerminate`),
  `:278-279`, `:306-307`
- `Sources/App/VaultController.swift:196-269` (`open(_:)`, `close()`)
- `Sources/App/VaultController+Tabs.swift:222-269`, `Sources/App/VaultController+Session.swift:34-53`
- `Sources/App/VaultController+Editing.swift:31-39`, `Sources/App/VaultController+TabFollowUps.swift:46-55`
- `Sources/Vault/NoteTab.swift:78-133`
- `Sources/App/VaultOpenPanel.swift:10-19`, `Sources/App/VaultCommands.swift:81-105`,
  `Sources/App/CommandActions.swift:181-182`
- `Sources/Features/Editor/VaultTopBar.swift:38-45`, `Sources/Features/Editor/EditorColumn+Closing.swift`
- `Tests/DiarySettleTests.swift`, `Tests/WorkspaceLifecycleTests.swift`,
  `Tests/NoteTabGestureTests.swift:311`, `Tests/VaultControllerWriteCatchUpTests.swift`
- ADR-0001 §D3.4, ADR-0012 §D3/§D10, ADR-0043 §D7, ADR-0046 §D3, ADR-0056 §D1, ADR-0058 §D1–§D3,
  ADR-0060 §D2, ADR-0066 §D2/§D5, ADR-0067 §D2/§D5
- `docs/20260811_Pergamenum_SpecApp.md` §5, §6.1 (line 235)
- macOS 27.0 SDK: `AppKit.framework/Headers/NSApplication.h`, `NSAlert.h`, `NSButton.h`
- Sparkle `SPUUserDriver` reference, sparkle-project.org
