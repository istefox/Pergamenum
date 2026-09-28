# Fix: Backspace in the pratica timeline excludes the selected message (PG-298)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to `PG-257`'s chain, which has
already merged, and is not this chain's input. The brief is the `PG-298` entry in `TODO.md` (#642).
The acceptance criteria are declared here as ten requirement ids.

The plan was read at `2300f752` (`origin/main`). The branch it was read on, `chore/todo-sync-635`
at `2a41306a`, has the same tree. Every line number below was checked against that tree.

## Acceptance criteria

- **R-01** With a collapsed message row of the pratica timeline selected by a click, Backspace
  excludes that message exactly as «Escludi dalla pratica» from the row's context menu does. The
  body that runs is `PraticaCommandActions.run(.exclude, on:detail:)`, so the message's `.md` and
  its `.eml` sidecar go to the Trash, its `Message-ID` joins `pergamenum-dossier-excluded` in
  `pratica.md`, the row leaves the timeline, and «Annulla Escludi» is offered.
- **R-02** R-01 holds for an expanded message row too.
- **R-03** A Backspace that excludes is answered as handled: no system beep. (no-test: a beep is
  observable neither from XCUITest nor in-process; hand check M1/M2)
- **R-04** Backspace excludes nothing, and leaves the selection as it is, when no row is selected,
  when the selected row is a manual entry («Nota», «Telefonata»), or when the selected id names no
  row of the visible, filtered timeline.
- **R-05** Backspace excludes nothing while keyboard focus is outside the timeline's rows. In the
  top bar's filter field and in the inspector's `pratica.md` editor it deletes a character as
  before. With text selected inside an expanded message's body, it excludes nothing.
- **R-06** One press excludes at most one message. Holding Backspace (key repeat), or pressing it
  again before the timeline reloads, excludes nothing further: not the same message a second time,
  and not a neighbour.
- **R-07** No regression to either menu. «Escludi dalla pratica» from the row's context menu still
  excludes. The attachment chip's AppKit menu (ADR-0069) still opens on a chip, and the three
  tests of `AttachmentChipContextMenuUITests` stay green, unmodified.
- **R-08** Keyboard focus survives a Quick Look preview. After a chip click opened the Quick Look
  panel and Esc closed it, a click on a message row followed by Backspace excludes that message.
- **R-09** The Workspace board's and the editor's Quick Look behave as today. On a board with a
  file card selected, the bare spacebar opens the panel without a click on the board first. An
  embed's preview in the editor opens as before.
- **R-10** The measured cause is recorded. ADR-0070's implementation notes name the probe's
  outcome and the route chosen. When the cause is a trap a future view could fall into (ADR-0070
  §D3 outcome A or B), CLAUDE.md's working agreements gain one entry naming it. (no-test:
  documentation obligation)

## ADR outcome: new ADR

**`docs/adr/0070-timeline-backspace-exclude-route.md`** (status: proposed).

On the three-part test, "hard to reverse" fails: the route is a few lines. The record is written
anyway, because two overrides apply and one project rule requires it:

- **A deliberate deviation from the obvious approach.** `.onKeyPress(.delete)` behind a
  `@FocusState` guard is the obvious SwiftUI shape, and it is what shipped broken. Whatever replaces
  it (a different route, no guard, a Quick Look host that no longer claims focus on one surface)
  will look like something to "fix" back.
- **A change to an integration between components**, if the probe lands on outcome A: the focus
  policy of the Quick Look host that the Workspace board, the editor and the timeline share.
- **CLAUDE.md requires it:** "a new feature carries at most two or three GUI tests, and each one
  is justified in the feature's own ADR". This chain adds two.

## Cause: what the code supports, fact versus assumption

Read, not run. Full evidence with sources is ADR-0070 §Context, F1 to F10.

| Candidate | Source | Status |
|---|---|---|
| C1: `@FocusState isListFocused` never turns true on a row click | ticket | **Assumption.** No code says either way. |
| C2: the selection never reaches `PraticheController` | ticket | **Assumption, weakly contradicted.** The binding reads and writes `selectedEntryID` directly (`PraticaTimelineView.swift:90-95`), whose only other writer is `resetVaultScopedState` (`PraticheController.swift:635`); M9 saw the row highlighted, and the highlight is drawn from that getter. A dropped `.tag` would fall back to the `ForEach` id, which is the same `String`. |
| C3: Backspace never reaches the `List`'s `.onKeyPress`, because the table behind the `List` sends it down `deleteBackward:` | added here | **Assumption.** Apple's documentation says both `onKeyPress` and `onDeleteCommand` act while the view has focus; two reports from 2020/2021 say `onDeleteCommand` on a `List` did not answer the key then. Nothing on macOS 27. |
| C4: the Quick Look host holds first responder when Backspace arrives | added here | **Fact that the code takes focus; assumption that this is the cause.** `QuickLookPresenter.swift:94` makes the host first responder unconditionally when the timeline appears; `:105-108` does it again on every update while `previewURLs` is non-empty, which is from the first chip preview on, for the rest of the session (`PraticaTimelineView.swift:34,54,294-297`, never cleared). The host passes every key but space to `super.keyDown`, which ends in the beep (`:26-37`). Unmeasured: whether a row click takes focus back, and whether an update runs after it. |

C4 is the only candidate with a focus-taking call in the code behind it, and it explains the beep,
both row states and the working context menu. It contradicts only M9's "held key focus", which
does not say how focus was judged. Reading cannot settle any of the four, so **Task 1 is a
diagnosis** with a falsifiable check, and Task 3 is conditional on its result.

## Tasks

Order: Task 1 decides which of Tasks 3 to 5 apply and how. Tasks 2 to 4 are the tester's (every
signature is declared there and the target builds at the end of each), Task 5 is the coder's.

### Task 1 — Measure who holds the key (coder, then orchestrator; throwaway probe; HITL G0) (R-10, R-01, R-02, R-05, R-08)

The probe is never committed. Its only committed output is a paragraph in ADR-0070's
implementation notes.

**Files, temporary (reverted by inverse edits before Task 2):**

- `Sources/Features/Pratiche/PraticaTimelineView.swift`: the probe points 1, 2, 3 and 5 of
  ADR-0070 §D1. That is a local key-down monitor installed in `.onAppear` and removed in
  `.onDisappear` that returns every event unchanged and logs, for key code 51, the class of
  `event.window?.firstResponder`; a log line as the first statement of the `.onKeyPress(.delete)`
  closure (`isListFocused`, `selectedEntryID`, the entry's kind), before the guard; a logging-only
  `.onDeleteCommand` on the same `List`; and `.onChange` of `isListFocused` and of
  `pratiche.selectedEntryID`.
- `Sources/Features/QuickLook/QuickLookPresenter.swift`: probe point 4, one log line in each claim
  (`:94`, `:105-108`) with the class of the first responder it replaces, plus the probe-only
  switch `UserDefaults.standard.bool(forKey: "pg298NoClaim")` that skips both claims.
- `UITests/PG298ProbeUITests.swift` (new, deleted afterwards). Its fixture is
  `AttachmentChipContextMenuUITests.seedFixturePraticaWithAttachment`, copied: one message with a
  placed `nota.txt`, one without attachments. It passes every launch flag that file passes. Run
  `tuist generate --no-open` after adding it and again after deleting it.

Every log line uses `Logger(subsystem: "it.stefer.pergamenum", category: "pg298")` with
`privacy: .public` on each interpolation, or `log show` prints `<private>`.

**Scenarios, one test method each, so each starts from a fresh launch:**

| Id | Steps, after selecting the fixture pratica | Claims |
|---|---|---|
| S1 | Click the message without attachments at `coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5))` of `pratiche-message-<hash>` (the header's trailing `Spacer`, not a button), then `typeKey(.delete, modifierFlags: [])` | on |
| S2 | Expand the same message through `pratiche-message-chevron-<hash>`, click its trailing header area, Backspace | on |
| S3 | Click the chip `pratiche-attachment-<hash>-0`, wait for the panel, Esc, click the other message's trailing area, Backspace | on |
| S1', S2', S3' | As S1 to S3 | off (`-pg298NoClaim YES`) |
| S4 | Click the filter field, type `ab`, Backspace | on |
| S5 | Expand a message, double-click a word of its body, Backspace | on |

In S1 the tester also opens the Modifica menu and records whether «Elimina» is enabled, since the
probe build carries `.onDeleteCommand`.

**Procedure.** `scripts/uitests.sh --status`, then
`scripts/uitests.sh -only-testing:PergamenumUITests/PG298ProbeUITests`, then
`log show --last 30m --style compact --predicate 'subsystem == "it.stefer.pergamenum" AND category == "pg298"'`.
If S5's double-click cannot select body text reliably under XCUITest, S5 is run by hand on a Debug
build (`APP=$(ls -dt .../Pergamenum-*/Build/Products/Debug/Pergamenum.app | head -1)`, then
`open -n "$APP" --args -recentVaults '("<fixture vault>")' -mailStoreRoot <empty dir> -disableCalendar YES -disableUpdater YES`)
with `log stream` running and the same predicate.

**Falsifiable exit criteria.** Task 1 is done when, for every scenario, the log names the first
responder's class at the Backspace and says whether each route ran, and each of S1 to S3' maps onto
exactly one row of ADR-0070 §D3's table (A, B, B0, C, D, E). S1 to S3 are read as the shipped
app; S1' to S3' only finish an A. A scenario whose log lacks these
lines is a broken probe, fixed and rerun; it is never read as an outcome. S4 must show no route
running and the filter reading `a`; S5 records whether a route ran while body text held focus.
Afterwards `git status --short Sources UITests` prints nothing.

**Gate G0 (HITL).** The orchestrator shows Stefano the rows found, then:

- only A, B or C with the claims on, and every A's claims-off run on B, C or E: continue with
  Task 2, and with Task 3 when A is among them;
- B0 or D anywhere, or E in every claims-on scenario (not reproduced): stop. The plan is
  re-planned with Stefano on the evidence (ADR-0070 §D3).

Record the outcome, the Modifica ▸ Elimina state and a short log excerpt in ADR-0070's
implementation notes. `rg -n "pg298" Sources UITests` finds nothing.

**Task 1 done (2026-09-28).** Outcome A with the claims on; with the claims off, a new row F
(no focus at all), and with focus set on selection, B. Stefano chose A + F + B at G0, with G1 and
G2 accepted. Task 3 applies. The probe is reverted; the evidence is in ADR-0070's implementation
notes.

### Task 2 — Declare the Backspace target door and write its red tests (tester) (R-01, R-04, R-06)

The tester owns both signatures; the coder owns the bodies. The target builds at the end of this
task, and every new test fails on an assertion, never on a build error.

**Files, declarations:**

- `Sources/Features/Pratiche/PraticaTimelineModel.swift`:
  `static func deleteKeyTarget(selectedID: String?, in entries: [PraticaTimelineEntry]) -> PraticaTimelineEntry?`,
  returning `nil`.
- `Sources/Features/Pratiche/PraticheController+DeleteKey.swift` (new): an extension of
  `PraticheController` with `func takeDeleteKeyTarget() -> PraticaTimelineEntry?`, returning
  `nil`. A new file rather than `PraticheController.swift`, which is already 641 lines against
  SwiftLint's 400-line `file_length` warning. `selectedEntryID` is a plain `var`
  (`PraticheController.swift:211`), so an extension in another file can clear it.
- `tuist generate --no-open` for the new file.

**Files, tests:** `Tests/PraticaDeleteKeyTests.swift` (new, Swift Testing, `@MainActor` where the
controller is used). The controller is built as `PraticheController(probe: { .granted },
performSync: { _, _ in })` (`PraticaLiveSyncTrashedMidRunTests.swift:76`), with `timeline` and
`details` set directly (`PraticheLedgerDoorTests.swift:131-151`).

- The pure rule:
  - a selected message present in the entries is the target;
  - a selected `.note` and a selected `.call` answer `nil`;
  - no selection answers `nil`;
  - an id absent from the entries answers `nil` (a row the filter hides, or another pratica's
    path: ids are vault-relative paths, `PraticheController+TimelineRead.swift:139`).
- The door:
  - with a visible message selected, it returns that entry and `selectedEntryID` is `nil`
    afterwards;
  - called twice in a row, the second call answers `nil` (R-06);
  - with a manual entry selected, it answers `nil` and `selectedEntryID` is unchanged;
  - with `filter` set so that `filteredTimeline` hides the selected message, it answers `nil` and
    `selectedEntryID` is unchanged.

Expected red: the "is the target" and "returns that entry" cases.

### Task 3 — Only for outcome A: declare the Quick Look focus opt-out and write its red tests (tester) (R-08, R-09)

Skipped entirely unless Task 1 recorded outcome A.

**Files, declarations:** `Sources/Features/QuickLook/QuickLookPresenter.swift`.

- `QuickLookTarget` gains `var claimsFocus: Bool = true`.
- `static func claimsFocusOnUpdate(claimsFocus: Bool, hasURLs: Bool, firstResponderIsText: Bool, isFirstResponder: Bool) -> Bool`
  on `QuickLookTarget`, returning `false`.
- `QuickLookHostView` gains `func claimFocusForPresentation()` and `func handBackFocus()`, both
  empty.
- `func quickLook(urls: [URL], isPresented: Binding<Bool>, claimsFocus: Bool = true) -> some View`
  replaces the two-parameter form, passing `claimsFocus` through. This glue is written here, since
  no test targets it. The three call sites compile unchanged (see "Observable-contract
  staleness").

**Files, tests:** `Tests/QuickLookFocusTests.swift` (new, `@MainActor`).

- `claimsFocusOnUpdate` truth table: `(true, true, false, false)` is `true`, which is today's
  Workspace and editor behaviour (R-09); `(true, false, …)`, `(true, _, true, _)` and
  `(true, _, _, true)` are `false`; every `(false, …)` is `false`.
- Record and hand back, in a never-shown `NSWindow` with a plain container holding a focusable
  `NSView` and a `QuickLookHostView` (the shape of `NoteFindTests.swift:280-293`): with the plain
  view as first responder, `claimFocusForPresentation()` makes the host first responder, and
  `handBackFocus()` makes the plain view first responder again. If another view took first
  responder in between, `handBackFocus()` leaves it there. If the recorded view left the window,
  `handBackFocus()` changes nothing.
- Measured first, kept only if it measures: host
  `Color.clear.quickLook(urls: [tempFile], isPresented: .constant(false), claimsFocus: false)` in
  `HostedView`, `settle()`, and check that no `QuickLookHostView` is the window's first responder,
  while with the default one is. `isPresented` stays `false`, so no panel is ever shown (ADR-0053
  R-15). If the first-responder state cannot be read on `HostedView`'s never-key window, say so in
  the test file's header and rely on the two groups above.

### Task 4 — Two GUI witnesses (tester) (R-01, R-02, R-08, R-07)

**File:** `UITests/PraticheUITests.swift`. `UITests/AttachmentChipContextMenuUITests.swift` is not
touched (R-07).

- `seedFixturePratica()` gains two message files under `email/` and `allegati/nota.txt`, in the
  shape of `AttachmentChipContextMenuUITests.seedFixturePraticaWithAttachment`: one message whose
  `pergamenum-mail-attachments` names `[[nota.txt]]`, one without attachments. The existing
  `testTheTimelineAndInspectorToggleAreAddressable` only checks identifiers and is unaffected.
- A `hash(_:)` helper mirroring `PraticaMessageRow.hash(of:)`, as
  `AttachmentChipContextMenuUITests.hash(_:)` does.
- `testBackspaceExcludesTheSelectedMessageCollapsedAndExpanded` (R-01, R-02): select the pratica;
  click the message without attachments at its trailing header area; Backspace. Assert that
  `pratiche-message-<hash>` stops existing (`waitForNonExistence(timeout: 5)`), that its `.md` is
  gone from `email/`, and that `pratica.md` lists its `Message-ID` under
  `pergamenum-dossier-excluded`. Then expand the other message through its chevron, click its
  trailing header area, press Backspace, and make the same three assertions.
- `testBackspaceStillExcludesAfterAQuickLookPreview` (R-08): click the chip, wait for the panel,
  Esc, click the message without attachments, Backspace, and make the same three assertions.
- Justification for both, per CLAUDE.md, lives in ADR-0070 §D5. Both exclusions move fixture files
  into the real Trash, as `SidebarDeleteUITests` already does.
- Run once: `scripts/uitests.sh -only-testing:PergamenumUITests/PraticheUITests`. Expected: the
  existing test green, both new tests red for the reason Task 1 measured. A red is read from the
  `.xcresult` (`xcrun xcresulttool get test-results summary --path <bundle>`) before anything is
  rerun.

### Task 5 — Bodies and the route (coder) (R-01, R-02, R-03, R-04, R-05, R-06, R-08, R-09)

- `PraticaTimelineModel.deleteKeyTarget` and `PraticheController.takeDeleteKeyTarget` bodies, per
  ADR-0070 §D2: the door applies the rule to `filteredTimeline`, clears `selectedEntryID` only when
  it returns a target, and leaves it alone otherwise.
- `Sources/Features/Pratiche/PraticaTimelineView.swift`:
  - **Route decided at G0 (2026-09-28): outcome A + F + B** (ADR-0070 implementation notes).
    `.onDeleteCommand` replaces `.onKeyPress(.delete)`. Its body is ADR-0070 §D2's lines: the
    door, then `actions.run(.exclude, on: entry, detail: pratiche.details[entry.id])`.
    `.onDeleteCommand` has no result to return, so a `nil` from the door is simply a no-op there.
  - Keep `@FocusState isListFocused` and `.focused($isListFocused)`, but as a setter, not a guard:
    `.onChange(of: pratiche.selectedEntryID) { _, new in if new != nil { isListFocused = true } }`.
    Measured: a row click selects but gives focus to nobody (outcome F); setting the state makes the
    table first responder. S5 showed no route running on selected body text, so no guard is kept.
  - Delete `excludeSelectedRow()` (`:97-110`).
  - Rewrite the comments at `:36-38` and `:78-80` to say which route is used and why, citing
    ADR-0070.
  - For outcome A: `.quickLook(urls: previewURLs, isPresented: $isPreviewing, claimsFocus: false)`
    at `:54`.
- For outcome A, `Sources/Features/QuickLook/QuickLookPresenter.swift`, per ADR-0070 §D4:
  `claimsFocusOnUpdate`'s body; `makeNSView` and `updateNSView` claim only when `claimsFocus`; when
  `isPresented` and `!claimsFocus`, call `claimFocusForPresentation()` before
  `togglePreviewPanel()`; `endPreviewPanelControl(_:)` calls `handBackFocus()`. With
  `claimsFocus == true`, the make and update paths must do exactly what `:94` and `:105-108` do
  today. The reviewer diffs that path.
- `tuist generate --no-open`, then build `Pergamenum`, `perg` and `pergamenum-mcp` (none of these
  files is in `sharedSources`, and the build confirms nothing leaked), then the unit suite.

### Task 6 — Update tests and call-sites asserting the old behaviour, and the records (coder; the CLAUDE.md edit behind G3) (R-07, R-10)

**Call-sites and tests asserting the old behaviour.** Grepped at `2300f752`; rerun
`rg -n "isListFocused|excludeSelectedRow|onKeyPress\(\.delete\)|quickLook\(urls|QuickLookTarget|QuickLookHostView" Sources Tests UITests`
after Task 5 and resolve every hit:

- `quickLook(urls:`: `Sources/Features/Editor/EditorColumnView.swift:100` and
  `Sources/Features/Workspace/WorkspaceView.swift:76` stay on the default, left unchanged on
  purpose (R-09); `Sources/Features/Pratiche/PraticaTimelineView.swift:54` changes in Task 5
  (outcome A only).
- `isListFocused`, `excludeSelectedRow`, `.onKeyPress(.delete)`: code hits are only in
  `PraticaTimelineView.swift` (`:39`, `:77`, `:81-82`, `:100`), all handled in Task 5.
- Tests: no test in `Tests/` or `UITests/` drives Backspace in the timeline or references
  `QuickLookTarget`/`QuickLookHostView`. Nothing asserts the old behaviour, which is why the defect
  went unseen.
- Docs: `docs/adr/0069-attachment-chip-menu-is-hosted-by-appkit.md:259,352` describe the old route
  as history, and stay. The `TODO.md:7` entry is closed by `/ship`, not here.
- `PraticheController.swift:209-210`, `selectedEntryID`'s doc comment: say that the key reads it
  only through `takeDeleteKeyTarget()`, which clears it.

**Records.**

- ADR-0070 implementation notes: the route chosen, any departure from the record, and line drift.
  Status stays `proposed` until the merge (`docs/adr/README.md` §2).
- CLAUDE.md, behind G3: the working-agreement entry of ADR-0070 §D6, for outcome A or B only, and
  a Chain decision index line for ADR-0070.

### Task 7 — Verification and gates (orchestrator, then Stefano) (R-01, R-02, R-03, R-04, R-05, R-06, R-07, R-08, R-09, R-10)

- The full unit suite through the approved command (below), and the three builds. SwiftLint
  reports no new error.
- GUI, through the script only: `scripts/uitests.sh --status`, then
  `-only-testing:PergamenumUITests/PraticheUITests` (R-01, R-02, R-08) and
  `-only-testing:PergamenumUITests/AttachmentChipContextMenuUITests` (R-07). At the merge,
  `--affected` (non-blocking per CLAUDE.md). With outcome A it selects the whole suite, because
  `Sources/Features/QuickLook/` is unmapped (`scripts/uitests.sh:137-157`).
- Hand checks on a Debug build, by Stefano:

| Id | Check | Expected | R |
|---|---|---|---|
| M1 | Click a collapsed message row, Backspace | Excluded, no beep | R-01, R-03 |
| M2 | Expand a message, click its row, Backspace | Excluded, no beep | R-02, R-03 |
| M3 | Select a message, hold Backspace for two seconds | Exactly one message excluded | R-06 |
| M4 | Type in the filter field, Backspace | One character deleted, nothing excluded | R-05 |
| M5 | Backspace in the inspector's `pratica.md` editor | One character deleted, nothing excluded | R-05 |
| M6 | Select a word in an expanded body, Backspace | Nothing excluded | R-05 |
| M7 | Chip click, Quick Look, Esc, click a row, Backspace; then Modifica ▸ Annulla Escludi | Excluded; the undo brings it back | R-08, R-01 |
| M8 | Workspace: select a file card, bare spacebar; editor: preview an embed | The panel opens as before | R-09 |
| M9 | Row menu «Escludi dalla pratica»; right-click a chip | Excluded; the chip's own menu | R-07 |
| M10 | Outcome B only: Modifica ▸ Elimina with the timeline focused, and forward delete | As agreed at G1 | R-01 |

- HITL: commit, push, pull request and merge are Stefano's gates.

## Observable-contract staleness

- Signature: `quickLook(urls:isPresented:)` becomes `quickLook(urls:isPresented:claimsFocus:)`
  with a default (outcome A only). It is source-compatible, and its three call sites are listed in
  Task 6.
- Behaviour: Backspace in a focused timeline starts excluding, which it never did. With outcome B,
  forward delete and possibly Modifica ▸ Elimina do too (G1). No test asserts the old behaviour
  (Task 6's grep).
- Additive: `PraticaTimelineModel.deleteKeyTarget(selectedID:in:)` and
  `PraticheController.takeDeleteKeyTarget()`.
- Run the **full** unit suite after Task 5, not only the new files: `PraticheController` and the
  shared Quick Look host are read by other suites.

## Risks and HITL gates

- **The cause is unmeasured.** Task 1 exists because of that, and its B0, D and E rows stop the
  chain rather than guess (G0).
- **The probe must leave no trace.** It edits two production files and adds a UI-test file.
  Reversal is by inverse edits, since `git checkout --` is denied on this machine, followed by
  `tuist generate`. `git status --short Sources UITests` and `rg -n pg298` are the check.
- **GUI runs take the screen and the pointer.** Task 1, Task 4 and Task 7 each drive the real app
  for several minutes. Stefano should not be at the keyboard, and `--status` is read before each
  run.
- **Fixture files go to the real Trash** in Task 4's two tests, as in `SidebarDeleteUITests`.
- **Outcome A touches a shared component.** The default path must stay equivalent (reviewer diff,
  Task 3's truth table, M8), and the merge's `--affected` becomes a full GUI run.
- **`endPreviewPanelControl` on Esc is an assumption.** Apple's header says it is sent "just before
  stopping its control". If Esc does not stop control, R-08's GUI test stays red and the hand-back
  moves to the panel's close callback (ADR-0070 §D4).
- **The selection clears on every accepted press**, including one whose exclusion then fails (G2).
- **Gates:** G0 after Task 1; G1 before Task 5 if outcome B; G3 for the CLAUDE.md edit in Task 6;
  commit, push, PR and merge. No schema change, no deletion outside the throwaway probe file, no
  release.
- No externally provisioned resource is needed: no network, no service, no credential. The GUI
  runs need the machine's display and Accessibility permission for the UI-test runner, which this
  suite already uses.

## Open for Stefano

- **G1 (only for outcome B).** Forward delete and Modifica ▸ Elimina also exclude. Recommended:
  accept.
- **G2.** Clear the selection after an exclusion rather than move it to the neighbour.
  Recommended: clear.
- **G3.** The CLAUDE.md working-agreement entry (ADR-0070 §D6). Approve the wording at Task 6.

## Test command

`xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
(unchanged: the `Stop` hook runs it every turn, and CLAUDE.md records why it must stay restricted
to `PergamenumTests`). The GUI suite runs only through `scripts/uitests.sh`.
