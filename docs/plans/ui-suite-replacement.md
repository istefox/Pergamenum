# Implementation plan — Replace the UI suite as the merge gate

Status: plan, written 2026-09-21 on the worktree `Pergamenum.worktrees/main-2`, branch
`chore/ui-suite-replacement`, against `SPEC.md` (Approved 2026-09-21) and
`docs/plans/ui-suite-replacement-census.md` (triage approved file by file, 2026-09-21).

Nothing here has been executed. No production file, no test file and no script was modified
while writing this plan; every file:line below was read off this tree, not recalled.

Inputs registered as settled, not reopened: every bullet of the SPEC's `## Decisions`
(replace rather than reduce the gate; per-test triage then retire; stage order; the 17
survivors are not a blocking gate; retirement deletes from source; the 60 s unit budget; one
ADR for the seam package; a seam changes no behaviour; the four disturbance signals; the
`contaminated` classification and its single rerun; exit codes 0/1/2; one PR per functional
area; the cap of 17 is informational; VM on hold), and every bullet of `## Constraints`.

---

## 1. ADR outcome

**New ADR: `docs/adr/0053-test-seams-for-the-in-process-merge-gate.md`**, written and
Accepted as the first act of stage 2 (Task 4), before any production file is touched.

Number checked, not assumed: `0052` is the highest file under `docs/adr/`, and
`git log --all --oneline -- 'docs/adr/0053*'` returns nothing, so no `0053` exists in any
commit reachable from any ref.

Why an ADR is warranted rather than skipped: the three-part gate holds and the project
mandates the record independently.

- *Hard to reverse.* Twelve production sites change shape, and 104 GUI tests are deleted
  behind them. Once the GUI tests are gone, a seam reverted is cover lost with nothing left
  to notice it.
- *Surprising without context.* A future reader meets `NSEvent.modifierFlags` replaced by an
  injectable closure, three call sites of a resolver switch collapsed into one controller
  method, and a private `accessibilitySummary` turned into a free function, with nothing in
  the code saying these were done for testability rather than for behaviour.
- *A real trade-off.* Each seam had genuine alternatives: keep the GUI test, retire on logic
  cover alone, or synthesise the event instead of injecting the state. The census records the
  reasoning per test; the ADR has to record the rule that governs all twelve.
- *Override, independent of the above:* SPEC **R-09** requires exactly this ADR, Accepted
  before the first production refactor. It is a record the project mandates.

**Not written now, deliberately.** The SPEC places its writing at the start of stage 2, after
stage 1 has shipped and after the R-08 hosting prototype has an outcome — and that outcome
belongs in its Context (it decides which converted tests become hosted and which stay GUI).
This repo's ADR house style also requires every signature and line reference to be read off
the tree the ADR is written on (`docs/adr/0052…` head note); writing it today against a tree
that stage 1 will move would mean re-verifying all of it anyway. What would have been lost by
waiting — the verified seam inventory — is instead preserved in §4 below, so Task 4 transcribes
rather than re-derives.

No existing ADR governs this work. ADR-0044 (§D6) and ADR-0051 (§D8) touch
`scripts/uitests.sh` but decide CI scope and helper duplication, not the verdict model; ADR-0044
explicitly defers the pre-merge rule to `CLAUDE.md`, which stage 3 amends. Neither is superseded
by this chain: ADR-0044's decision that CI covers three builds plus the unit suite is unchanged,
and stage 3 changes the `CLAUDE.md` rule ADR-0044 points at, not ADR-0044's own decision. Task 4
states that relationship in the new ADR's head rather than editing either file.

---

## 2. The census entries marked "to verify in `/plan`"

Verified against the files on this tree, 2026-09-21. Most entries held; three held only in
part, two did not hold. Nothing here changes the approved triage; two conversions turn out to
need no new test, and two need larger ones than the census implied.

| # | Census claim | Verdict | What was read |
|---|---|---|---|
| 1 | `EditorHeightTests` covers the long-note case (`CompletionPanel:167` retirement) | **Held, with the caveat the census already recorded** | `Tests/EditorHeightTests.swift:58-61` builds a 40-paragraph note ending in a heading, in a 600×700 window; `:64`, `:78` and `:100` assert height, the last line inside the scrollable area, and the caret after typing at the end. Its own header (`:15-20`) says it stays green with `layoutViewport()` removed — the postcondition is held, the app-level defect is not. That is the basis the retirement was approved on. |
| 2 | A heading-provider unit test already exists (`CompletionPanel:98`) | **Did not hold** | The three `CompletionPanelTests` call sites (`:59`, `:121`, `:198`) and `EditorCompletionTests:189` all **stub** `noteSections` with a literal closure. The production provider is `NoteTextView.swift:259-266` (`transclusions?.resolve` → `NoteOutline.entries` filtered to `.heading` → `entry.title`) and nothing tests it. The conversion must write that test for real. |
| 3 | `NoteTree` has structure tests already (`NoteTree:93`) | **Held, and wider than expected** | `Tests/NoteTreeTests.swift` carries 15 structure tests, and `:87` already pins `NoteTree.ancestors(of:)` itself. What is uncovered is only the union at `Sources/Features/Editor/NoteListPane.swift:196` (`ancestors(of: reveal.folder) + [reveal.folder]`) and its sibling at `:567`. The seam is therefore one small pure function over an already-tested primitive, not a new tree algorithm. |
| 4 | The shortcut recorder can be extracted with no change of behaviour (`NoteTree:161`) | **Held** | `Sources/Features/Settings/ShortcutSettings.swift:159-186`: `handle(_:)` reads only `event.modifierFlags`, `event.keyCode` and `charactersIgnoringModifiers` (through `key(for:)`, `:193-205`), and its four outcomes are cancel (keyCode 53, no modifiers), clear (51, no modifiers), record a valid `KeyBinding`, ignore. A pure `(keyCode, flags, charactersIgnoringModifiers) -> Outcome` function leaves the view holding only `stop()`/`onRecord`. Nothing else in `handle` touches view state. |
| 5 | Vault-theme **loading** is covered (`Design:66`) | **Held** | `Tests/ThemeCustomizationTests.swift:110` `aVaultThemeReachesTheEngineOnceTheVaultIsAttached`. |
| 6 | Theme **selection** is covered (`Design:66`) | **Held at engine level, not at the picker** | `Tests/DesignSystemTests.swift:133`, `:150`, `:158` cover selection, fallback and persistence; `ThemeCustomizationTests:136` covers `detachVault`. The `Picker("Tema")` at `Sources/Features/Settings/SettingsView.swift:100` reads `engine.themes`, whose filtering lives at `ThemeEngine.swift:114` and `:296` — the list as the picker sees it is untested. The conversion adds that assertion at engine level. |
| 7 | The **reset** is covered in `ThemeCustomizationTests` (`Design:91`) | **Did not hold at engine level** | `ThemeCustomizationTests:97` covers `ThemeCustomization.remove` (the file), and `:259` only mentions the engine in a comment. `ThemeEngine.resetCustomization()` (`ThemeEngine.swift:241-252`) — which also clears `customizationProblem`, drops `selection == .named(ThemeCustomization.id)` back to `.followSystem` and reloads — is untested. The conversion must cover it. |
| 8 | The embed label is extractable with no change of behaviour (`NoteImage:63`) | **Held** | `Sources/Features/Editor/CompletingTextView+Accessibility.swift:129`: `let label = embed.alt ?? embed.target`, with `embed` from `Attachment.embed(inLine:)` at `:117`. A pure `(line) -> String?` function, no view state. |
| 9 | `WorkspaceCreationTests:37,50` already assert that no `.canvas` is written (`OpenState:251`) | **Held** | `Tests/WorkspaceCreationTests.swift:37` `createFolderShowsNoNewCanvasThroughAllBoards` compares `allBoards()` before and after and names both spellings of the file that must not appear; `:50` covers the tree row. **Consequence: `OpenState:251`'s replacement already exists** — its PR deletes the GUI test and cites those two, adding no new unit test. |
| 10 | Not from the "to verify" lists but load-bearing: `CompletionPanelTests:206` covers "15 presses, index 15, scroll" (`CompletionPanel:146`) | **Did not hold (coverage column only)** | `:206` is `theArrowKeysWalkTheListAndStopAtItsEnds` over a **3**-item list, checking the two ends. The census's *action* for `:146` is unaffected — it already asks for a new unit test with 15 down arrows — but the conversion cannot lean on `:206` as an existing replacement. |
| 11 | Also load-bearing: the emoji conversion (`CompletionPanel:116`) | **Already covered, both halves** | `Tests/EmojiCompletionTests.swift:23` asserts `:bers` offers exactly `🎯 bersaglio`; `:30` asserts Return writes the glyph and nothing else; `Tests/EmojiCatalogueTests.swift` covers the search ranking in nine tests. **Its PR deletes the GUI test citing these, adding no new test.** |
| 12 | `SidebarMoveUITests` line numbers for `R01`–`R06`, flagged unverified in the census | **Held, every one** | `:83` R01, `:109` R02, `:124` R03, `:136` R04, `:148` R05, `:168` R06, `:216` R07, `:239` R10, `:256` R11, `:277` R12, `:308`/`:336`/`:352`/`:404` R15, `:378` regression — exactly as censused. |
| 13 | `ComposerUITests:283`'s "Inbox" also matches an always-listed view title (census §4, "not verified") | **Confirmed at source level** | `Sources/Index/IndexSnapshot.swift:223-236`: `TaskView.inbox.title == "Inbox"`, and the five views are always in the sidebar (`TasksView`, SPEC §7.4). The assertion at `ComposerUITests:294` is an unscoped `app.staticTexts["Inbox"].exists`, so the sidebar row satisfies it whatever view is shown. Only the AX tree can prove the row is exposed as a `staticText`, but the test is a **convert**, so the question dies with it. |

**Arithmetic check of the whole triage, done because the retirements rest on it.** Per-file
`func test` counts on this tree: 121 across 22 files, matching the SPEC. Summed from §3b of the
census: 17 keep + 42 convert (including the two keep-until-replaced, `SidebarMove:378` and
`EditorCompletion:59`) + 62 retire = 121, and 42 + 62 = 104 leave the GUI suite, leaving 17.
Every per-file subtotal also closes against its file's own test count. The SPEC's totals are
exact, not rounded.

---

## 3. Decisions this plan takes, that the SPEC delegated

### D-1. The external-monitor detector is `system_profiler SPDisplaysDataType -json`

Measured on this machine (macOS 27.0, Apple M5 Max) on 2026-09-21:

- `/usr/sbin/system_profiler -json SPDisplaysDataType` — **0.31 s**, exits 0, no privilege
  needed. Its `SPDisplaysDataType[].spdisplays_ndrvs[]` array holds one entry per display;
  the built-in one carries `"spdisplays_connection_type": "spdisplays_internal"` and an
  external one does not carry that key at all. With the LG monitor attached (the machine's
  usual state, census §1.5) it returns two entries, one internal, one not.
- `/usr/sbin/ioreg -c IODisplayConnect -r -d 1` — **0 matches**. The legacy class is not
  populated here.
- `/usr/sbin/ioreg -rc AppleCLCD2` — **0 matches**. Not populated either.
- `ioreg` does expose `IOMobileFramebufferShim` (5 instances) and `AppleDisplayManager`, but
  neither count corresponds to the two real displays, so neither is a usable proxy.
- A compiled `CGGetActiveDisplayList` helper would be exact, but adding a binary to a shell
  script is out of proportion for one signal, and the SPEC rules out rewriting the runner.

**Rule:** an external monitor is present when at least one entry of `spdisplays_ndrvs`, across
all GPUs, lacks `spdisplays_connection_type == "spdisplays_internal"`. Parsed with `python3`
(the repo already ships `scripts/appcast.py` and `scripts/mcp-smoke.py`, so python3 is not a new
dependency); the text form is *not* used, because the external display prints no
`Connection Type` line at all and counting displays by indentation is fragile.

**Sampled twice, not polled:** once immediately before `xcodebuild test` and once immediately
after it. That costs ~0.6 s and covers all three cases the SPEC's edge-case list names —
connected throughout (both samples see it), connected partway (the second sees it), disconnected
partway (the first sees it). A per-second poll beside the focus loop would burn 0.3 s of CPU per
second for a signal that does not change on that timescale.

**Injectable, like the verdict directory already is:** `UITESTS_FAKE_DISPLAYS` overrides the
detector so `--self-test` can fabricate the signal with no display attached, the same shape as
the existing `UITESTS_VERDICT_DIR` (`scripts/uitests.sh:132-135`).

### D-2. The launch-log evidence for R-06 is `/usr/bin/log show`

Verified on this machine: `/usr/bin/log show --last 10s --style compact --predicate 'process ==
"launchd" OR process == "launchservicesd"'` runs in **1.7 s** with no privilege and prints
exactly the `launching: launch job demand` lines the census's PG-182 investigation used
(§4.4). Absolute path is mandatory: in zsh a bare `log` is a shell builtin, not the tool
(census §4.4, and the machine-level rule in the tools notes).

Captured into the run's evidence directory beside the `.xcresult` when
`partition_instances` first reports an installed copy that was not there before the run. The
window is `--last 10s` taken at the moment of detection, which is the "about 10 seconds around
that moment" R-06 asks for, minus the future — the log cannot be read forward. Recorded as a
limitation in the file's own header, not papered over.

### D-3. `classes_for_path` is maintained in the PR that deletes a class

Newly surfaced during planning, reconciled against the SPEC rather than added as scope. Ten
`UITests/*UITests.swift` files disappear over stages 2 and 3, and **five of them are named by
hand** in `scripts/uitests.sh:105-124`: `WorkspaceFocusUITests`, `TaskTimeUITests`,
`TimeBlockUITests`, `TimelineHoursUITests`, `UpdateMenuUITests`. Those five need a mapping edit
when they go. The other five — `SectionToolbarsUITests`, `CompletionPanelUITests`,
`EditorCompletionUITests`, `DesignAndReadingUITests`, `NoteImageUITests` — appear nowhere in
`classes_for_path`, so their deletion needs none.

A mapping naming a class that no longer exists makes `--affected` pass `-only-testing` for
nothing, which is the zero-test run R-05 now classifies as an error rather than a red —
detected, but only after a wasted run.

No new requirement is needed: this is the mapping half of R-10's own proof mechanism and of
R-16's deletions. Every PR that removes the last test of a mapped class updates
`classes_for_path` in the same commit, and the plan says so in each task. Stated here rather
than left implicit because nothing in the SPEC names the mapping.

### D-4. Stage-2 PR order

Seven PRs, one functional area each, inside the SPEC's "roughly six to eight". Two criteria,
in this order:

1. **Dependency.** A seam shared by two areas lands with the area that owns it. The R-08
   prototype (Task 3) and the ADR (Task 4) precede all seven.
2. **Cost of the R-10 proof.** `--affected` maps `Sources/Features/Editor/**`,
   `Sources/App/**`, `Sources/Features/Settings/**`, `Sources/DesignSystem/**` and
   `Sources/Index/**` to `ALL` (`classes_for_path`'s final `*)` case), so a seam in any of
   them costs a **full** proof run. Those PRs go later, when stage 2's own deletions have
   already shortened the suite; the PRs whose proof is a partial run go first. At ~13 s a test,
   each full run deferred past ten deletions is about two minutes cheaper, and — more to the
   point — is one fewer full machine-dependent run early on, when the `contaminated` verdict is
   still young.

| PR | Area | Converts | Seams | R-10 proof |
|---|---|---|---|---|
| 1 | Workspace tree & board | 10 | `enter(folder:)`, row label, board a11y summary | partial (5 Workspace classes + SidebarMove) |
| 2 | Diary | 4 | `DiaryGeometry` drag maths | partial (5 day/diary classes) |
| 3 | Pratiche | 3 | none | partial (`PraticheUITests`) |
| 4 | Sidebar move | 2 | `canMove(to:)` unification | full (`NoteTreeRow.swift` is unmapped) |
| 5 | Editor: completion, embeds, wikilink, focus, teardown | 11 | Cmd-state closure, focus derivation, embed label | full |
| 6 | Day, tasks & time | 8 | capture-landing mapping, category disable predicate, `DayTimeline.hours` | full |
| 7 | Settings & design system | 4 | note-tree reveal set, shortcut recorder outcome | full |

Total 42, matching the SPEC's convert count exactly.

Two placements worth stating out loud. `SidebarMove:378` (the a853e8e crash regression, one of
the two keep-until-replaced) is deleted in **PR 5**, not PR 4, although its file is
`SidebarMoveUITests.swift`: its subject is `NoteTextView.dismantleNSView`, its replacement is a
hosted editor test, and it must not be deleted until that test is shown to reproduce the crash.
The PR notes the file it was deleted from and the area it belonged to. `EditorCompletion:59`,
the other keep-until-replaced, is deleted in the same PR for the same reason. The Editor PR is
also the largest on purpose: splitting it would buy a second full proof run and nothing else.

---

## 4. Seam inventory, verified on this tree

Task 4 transcribes this into ADR-0053; every site below was read today. The SPEC's prose list
in `## API / interfaces` enumerates ten; the census names **twelve**. R-09 ("lists every seam of
the census") governs, so the ADR carries twelve and the SPEC needs no change — the two extra are
#11 and #12, which the census introduced in its `NoteTreeAndShortcutsUITests` entry after the
SPEC's prose was drafted.

| # | Seam | Verified site | Shape after | Serves |
|---|---|---|---|---|
| 1 | Enter a folder from the Workspace controller | `BoardChrome.swift:55`, `BoardCardMenu.swift:209`, `WorkspaceView.swift:210` — three copies of `switch WorkspaceBoardResolver.board(…)` / `.unique → select(.board)` | one `WorkspaceController.enter(folder:)`, three call sites | OpenState `:370`, `:383`, `:405`, `:425`; Integration `:166` |
| 2 | Workspace row label | `WorkspaceRow.swift:194-204`, `private var accessibilityLabel` | pure `(kind, name, boardCount, isSelected) -> String` | OpenState `:216` |
| 3 | Board card accessibility summary | `BoardContentLayer.swift:239`, `private func accessibilitySummary(for:)`, used at `:78` | pure `(CanvasNode) -> String` | Board `:100` |
| 4 | Cmd state at the editor coordinator | `NoteTextView+Coordinator.swift:411`, `guard NSEvent.modifierFlags.contains(.command)` | injectable closure defaulting to `NSEvent.modifierFlags`, plus a capturing variant of `Tests/EmbedEditorTestSupport.swift:58` (which hard-wires `onFollowLink: { _ in }`) | Wikilink `:109`; the `:163`/`:180` retirements rest on the plain-click-refused test it enables |
| 5 | Focus derivation on navigation | `RootView.swift:67-86`, `isFocusedPane` and `sidebarVisibility` | pure function on `Navigation` | Focus `:49` |
| 6 | Task view a capture lands in | `TasksView.swift:66-75`, the `switch capture.day` inside `followLastCapture` | pure `(day, today) -> IndexSnapshot.TaskView` | Composer `:283` |
| 7 | Whether a row can move to a destination | `WorkspaceRow+Move.swift:141` **and** `NoteTreeRow.swift:204` — two copies of `destination != parentFolder && WorkspaceBrowser.canDrop(items, onFolder:)` | one pure function, both call sites | SidebarMove `:168` |
| 8 | Diary drag geometry | `DiaryTimeline.swift:147` `range(of:)`, `:197` `minutes(at:)`, `:18` `dragThreshold`, `DiaryEntryCard.swift:168` `snappedDelta`; `hourHeight = 60` duplicated at `DiaryTimeline.swift:15` | moved into the existing `DiaryGeometry` (`DiaryEntryCard.swift:7`), taking scalars rather than a `DragGesture.Value` so a test needs no gesture | Diary `:177`, `:205` |
| 9 | Category editor disable predicate | `CategoryEditor.swift:88`, `.disabled(name.trimmed.isEmpty \|\| slugProblem != nil)` | pure function beside the existing `slugProblem(slug:isCreating:)` at `:295` | TaskCategories `:151` |
| 10 | The day timeline's hours | `DayTimeline.swift:21`, `private var hours: HourWindow` | pure function; the Diario half is already covered by `DiaryControllerTests:324` | TimelineHours `:30` |
| 11 | Note-tree reveal expansion set | `NoteListPane.swift:196` and `:567` | pure `(revealed path) -> Set<String>` over the already-tested `NoteTree.ancestors(of:)` (`NoteTreeTests:87`) | NoteTree `:93` |
| 12 | Shortcut recorder event-to-outcome | `ShortcutSettings.swift:159-186` `handle(_:)` plus `:193-205` `key(for:)` | pure `(keyCode, flags, charactersIgnoringModifiers) -> .cancel / .clear / .record(KeyBinding) / .ignore` | NoteTree `:161` |

**Placement constraint, per seam.** Seam #6's natural home, `IndexSnapshot.TaskView`, is in
`Sources/Index/IndexSnapshot.swift`, which **is** in `sharedSources` (`Project.swift:93`) — so
it must stay Foundation-only or it breaks both connector builds (ADR-0001 §D1, which CLAUDE.md
records as having caught three inverted dependencies the first time it ran). The mapping is
pure date logic, so this is satisfiable; the ADR states it. No other seam lands in a shared
path: #1–#3 and #7–#10 are under `Sources/Features/**`, #4, #11 and #12 likewise, #5 under
`Sources/App/**`, none of them shared.

---

## 5. Tasks

### Task 1 — Stage 1a: make the verdict logic addressable and drive it from `--self-test` (R-07)

Red first: the self-test exists and fails before the logic it asserts is written.

Files: `scripts/uitests.sh`.

- Split the classification currently inlined at `:538-557` (`record_verdict`) into named
  functions that take their inputs as arguments rather than reading globals: the signal set,
  the failure list, the executed count, the rerun outcome. Nothing about the current behaviour
  changes in this task — green stays green, red stays red.
- Add the injectable seams the self-test needs, on the existing `UITESTS_VERDICT_DIR` model
  (`:132-135`): `UITESTS_FAKE_DISPLAYS` for the monitor detector (D-1), and a way to feed a
  fabricated log path and a fabricated rerun result.
- Add `--self-test`, modelled on `scripts/appcast.py --self-test` (`scripts/appcast.py:281-296`:
  a list of named checks, a count printed, non-zero on the first failure). Offline, no build,
  no GUI, no `xcodebuild`, writing only into a `mktemp -d` verdict directory. It asserts:
  R-03's classifications (no reds → green whatever the signals; reds with no signal → red;
  reds with a signal → contaminated plus one rerun; rerun green → green; rerun red with no
  signal → red; rerun disturbed → contaminated), R-04's three exit codes and the rule that
  `contaminated` is not "verified", and R-05's zero-test error state.
- `--self-test` refuses to combine with other arguments, like `--status` and `--affected` do
  (`:275-281`).

Shell constraints that apply and have bitten this machine before: bash 3.2, so no `mapfile`,
no associative arrays, no `${var^^}`; the script's own `set -euo pipefail` header stays; `grep`
here is `ugrep -G`.

### Task 2 — Stage 1b: the four signals, the `contaminated` verdict, the rerun, the exit codes (R-01, R-02, R-03, R-04, R-05, R-06)

Files: `scripts/uitests.sh`.

- **Detect the four signals** (R-02). *Installed copy appeared mid-run*: already computed at
  `:565-570` via `partition_instances`, currently only printed — it becomes a recorded signal.
  *Launch failure or timeout*: already recognised at `:472-477` and `:496` — the same two tells
  become a signal. *Focus taken*: `FOCUS_LOG` is already written at `:408` and summarised at
  `:572-576` — a non-empty log becomes a signal. *External monitor*: new detector per D-1,
  sampled before and after the run.
- **Record `contaminated`** (R-01) in the same per-tree file `record_verdict` already writes
  (`:538-557`), adding a `reasons=` field holding zero or more of the four, with `result` now
  taking three values. The file stays the flat `key=value` form `verdict_field` reads.
- **Classify and rerun** (R-03): reds with at least one signal reruns **only the failed tests**,
  once, reusing the existing rerun machinery at `:498-531` (which today reruns only launch
  failures — that narrower rule stays, and the new one sits beside it rather than replacing it,
  since a launch failure is retried even with no other signal). Rerun green → `green`; rerun red
  with no signal → `red`; rerun disturbed again → stays `contaminated`.
- **Exit codes** (R-04): 0/1/2. `--status` prints the result and its reasons through
  `show_verdict` (`:198-210`), and neither `status_report`'s verified test (`:232-235`) nor
  `last_verified_ancestor`'s scan (`:145-155`) accepts anything but `green` — both already test
  for `= green`, so both are correct by construction, and the task adds a self-test check that
  pins that rather than trusting it.
- **Zero tests is an error** (R-05, PG-194): `record_verdict` currently writes `result=red` when
  `executed` is 0 (`:546-547`). It instead reports the error, writes **no** verdict and leaves
  the tree's existing one untouched.
- **Launch evidence** (R-06, PG-182): per D-2, on first detection of an installed copy that was
  not running before the run, `/usr/bin/log show --last 10s` for `launchd`/`launchservicesd` into
  the evidence directory beside the `.xcresult`.
- The census's second PG-182 proposal — a trial run with the focus loop off, to test the timing
  suspicion against `:402`'s `osascript` calls — is **not** part of this task. It is a
  hand-experiment for Stefano, noted in §7.

Acceptance: `scripts/uitests.sh --self-test` green, and one real `--affected` run on this branch
showing a verdict recorded with its reasons.

### Task 3 — Stage 2 opener: the hosting prototype (R-08, R-14, R-15)

Files: `Tests/HostedViewPrototypeTests.swift` (new), `Tests/HostedViewSupport.swift` (new);
`Project.swift` needs no edit (`Tests/**` is a glob), but `tuist generate` runs after the files
appear.

- One SwiftUI view and one Workspace view, each in its own never-shown window, events sent
  directly. Four files in `Tests/` already host SwiftUI through `NSHostingView`
  (`ViewQueryEntryPointTests.swift:249,269`, `ViewBlockHostStoreTests`,
  `ViewBlockQuerySourceTests`, `CompletionPanelPlacementTests`), and `EditorHeightTests.swift:46-55`
  already builds an `NSWindow` with `window.layoutIfNeeded()` and `defer { window.orderOut(nil) }`
  and never calls `makeKeyAndOrderFront` — so the SwiftUI half has precedent and the harness copies
  it. The unproven half is the Workspace view (`BoardContentLayer`, zoom/pan, a live
  `openedWorkspaceController`).
- R-15 is a property of the harness, not of each test: no `makeKeyAndOrderFront`, no
  `NSApp.activate`, no EventKit, no Mail store, no updater. The existing launch-flag discipline
  (`-disableCalendar`, `-disableUpdater`, `-mailStoreRoot`) has no equivalent in-process, so the
  harness must reach none of those three subsystems at all; the test asserts that by construction
  (it builds the view with injected state, never the app).
- **Record the outcome** in this plan's own §8 and in ADR-0053's Context before any dependent
  test is converted. If the Workspace half fails, the tests that depend on it stay GUI and the
  cap of 17 rises only with Stefano's approval, test by test (SPEC decision, R-08) — that is a
  HITL gate, §7.
- Measure the unit suite's wall time before and after (R-14, budget 60 s, about 18 s today).

### Task 4 — Stage 2: ADR-0053, Accepted before the first production refactor (R-09)

Files: `docs/adr/0053-test-seams-for-the-in-process-merge-gate.md` (new).

Structure per this repo's house style (see `docs/adr/0052…` head): Status, Date with the tree
it was read on, numbering note, Source, what it extends/amends, what it reopens (nothing), then
Context / Decision / Alternatives considered / Consequences / References.

It must carry, at minimum:

- The rule: **a seam changes no behaviour**, and its proof is `--affected` on the seam commit
  before the GUI test is deleted — green, or contaminated then green on the rerun (R-10).
- All **twelve** seams of §4 above, each with its verified site, its shape after, and the test
  it serves. The SPEC's prose names ten; §4 explains the two extra and why no SPEC change is
  needed.
- The placement constraint on seam #6 (`sharedSources`, Foundation-only, ADR-0001 §D1).
- The two unifications that are more than extractions — #1 (three copies to one) and #7 (two
  copies to one) — and why unifying is behaviour-preserving here.
- The R-08 prototype's outcome, and which converted tests stay GUI because of it.
- Its relationship to ADR-0044 §D6 and ADR-0051 §D8 (neither superseded; the `CLAUDE.md` rule
  ADR-0044 defers to is amended in stage 3).
- That a seam found later amends this ADR rather than getting its own.
- **Accepted** status is Stefano's, not the implementer's: HITL gate, §7.

### Task 5 — Stage 2: seven PRs, one functional area each (R-10, R-11, R-12, R-13, R-14, R-15)

Order and contents per D-4. Every PR, without exception: writes its replacement tests first
(red), lands the seam, proves the seam with `--affected` on the seam commit **before** deleting
anything (R-10), deletes its converted GUI tests in the same PR (R-11), lists in its description
each deleted test with its census entry and the wiring lost (R-13), updates `classes_for_path`
if it removed the last test of a mapped class (D-3), runs `tuist generate` if a file appeared or
disappeared, and re-measures the unit suite against the 60 s budget (R-14).

**What "red first" means in Swift, since a missing declaration is not a red.** A test calling a
pure function that does not exist yet does not fail — the target does not build, and a batch that
does not build produces no red at all. So for every seam the **declaration** lands with the test:
the new signature, with a body that simply calls the private implementation still in place. The
test then fails on its assertion, which is a real red. Collapsing the old call sites into the new
seam — the part that can change behaviour — is the separate step that follows, and it is what
`--affected` proves neutral.

**PR 1 — Workspace tree & board.** Seams #1, #2, #3. Files:
`Sources/Features/Workspace/{BoardChrome,BoardCardMenu,WorkspaceView,WorkspaceRow,BoardContentLayer}.swift`,
`Sources/Features/Workspace/WorkspaceController*.swift`; tests added under `Tests/`; deletes from
`UITests/WorkspaceOpenStateUITests.swift` (`:216`, `:251`, `:370`, `:383`, `:405`, `:425`),
`UITests/WorkspaceIntegrationUITests.swift` (`:75`, `:166`),
`UITests/WorkspaceBoardUITests.swift` (`:100`, `:161`). `:251` needs **no new test** — cite
`WorkspaceCreationTests:37,50` (§2 row 9). `:161` uses the existing
`beginResize/updateResize/endResize` seams with flush and reload, no production change. `:75`
becomes a `VaultSession` walk over `TaskMarkerTests`, `TaskMarkerWriteTests`,
`WorkspaceReferenceTests`, `IndexCacheTests` ground.

**PR 2 — Diary.** Seam #8. Files: `Sources/Features/Diary/{DiaryTimeline,DiaryEntryCard}.swift`;
new `Tests/DiaryGeometryTests.swift` (R-12: `DiaryGeometry` appears in no file under `Tests/`
today); deletes `UITests/DiaryUITests.swift` `:110`, `:163`, `:177`, `:205`. The hard-coded
120 pt at `:205` disappears with the seam.

**PR 3 — Pratiche.** No seam, no production change. New unit tests for
`FullDiskAccessProbe.state` with `ENOENT`, `PraticheController.selectedTray`, and the
`dismissRegeneration` byte-identity guarantee (ADR-0036 §D21) beside
`PraticaRegenerationTests:67,94`; the last uses the existing `MailStoreFixture`/
`EmailFixtureCorpus` in `Tests/`. Deletes `UITests/PraticheUITests.swift` `:192`, `:211`, `:248`.

**PR 4 — Sidebar move.** Seam #7, unifying both copies. Files:
`Sources/Features/Workspace/WorkspaceRow+Move.swift`, `Sources/Features/Editor/NoteTreeRow.swift`;
new unit tests for the pure `canMove` and for `VaultController.moveNote` (`canOperate`,
`recordProblem`, rescan — untested today); deletes `UITests/SidebarMoveUITests.swift` `:124`,
`:168`.

**PR 5 — Editor: completion, embeds, wikilink, focus, teardown.** Seams #4, #5, and the embed
label. Files: `Sources/Features/Editor/{NoteTextView+Coordinator,CompletingTextView+Accessibility}.swift`,
`Sources/App/RootView.swift` (+ wherever the `Navigation` derivation lands),
`Tests/EmbedEditorTestSupport.swift` (capturing variant). Replacement tests: the real heading
provider (§2 row 2 — it does not exist today), the 15-press selection movement (§2 row 10 — the
existing `:206` does not cover it), the hosted `#tag`-insertion crash test for
`EditorCompletion:59`, the hosted `TableGridView`/`editor-table` attachment test for
`Design:159`, the embed-label test, the plain-click-refused wikilink test, the `menu(for:)` /
`openLinkFromMenu` test, and the hosted `NoteTextView` teardown test that must **reproduce the
a853e8e crash** before `SidebarMove:378` is deleted. Deletes: `CompletionPanelUITests` `:98`,
`:116` (cite `EmojiCompletionTests:23,30` — no new test, §2 row 11), `:146`;
`EditorCompletionUITests:59`; `NoteImageUITests:63`; `DesignAndReadingUITests:159`;
`WikilinkNavigationUITests` `:109`, `:209`; `WorkspaceFocusUITests` `:49`, `:74`;
`SidebarMoveUITests:378`. Three files go entirely — `WorkspaceFocusUITests`,
`EditorCompletionUITests`, `NoteImageUITests` — of which only the first is in
`classes_for_path` and needs the mapping edit (D-3).

**PR 6 — Day, tasks & time.** Seams #6, #9, #10. Files:
`Sources/Index/IndexSnapshot.swift` (Foundation-only, `sharedSources`),
`Sources/Features/Tasks/{TasksView,CategoryEditor}.swift`, `Sources/Features/Today/DayTimeline.swift`.
Replacement and added tests (R-12): `DayController.show(_:)`, `beginTaskCapture` setting
`taskDraft`, `CommandActions.run(.quickTask)`, the capture-landing mapping,
`WindowPlace.isDrift`/`apply`/`destination` (named in no file under `Tests/` today),
`TaskTimeRow.defaultTime` (09:00), `HourWindow.dayDefault`/`.diaryDefault`, the diary window
reaching 22:00 from `- 21:00-22:00 Serata`, and the category disable predicate. Deletes
`ComposerUITests` `:283`, `:300`; `HistoryNavigationUITests:65`; `TaskCategoriesUITests:151`;
`TaskTimeUITests:72`; `TimelineHoursUITests` `:30`, `:48`, `:62`. `TimelineHoursUITests` goes
entirely → `classes_for_path` edit. Building both connectors is part of this PR's check, since
it touches a shared file.

**PR 7 — Settings & design system.** Seams #11, #12. Files:
`Sources/Features/Editor/NoteListPane.swift`, `Sources/Features/Settings/ShortcutSettings.swift`.
Replacement tests: the reveal expansion set, the recorder's four outcomes, the vault-theme list
as the picker sees it (§2 row 6), and `ThemeEngine.resetCustomization()` (§2 row 7 — untested
today, so this is a real new test and not a citation). Deletes
`NoteTreeAndShortcutsUITests` `:93`, `:161`; `DesignAndReadingUITests` `:66`, `:91`.

### Task 6 — Stage 3: the 62 retirements and the cap in `--status` (R-16, R-17)

Files: the twelve surviving `UITests/*UITests.swift` files and the six deleted here;
`scripts/uitests.sh`. `Project.swift` is untouched (`UITests/**` is a glob) but `tuist generate`
runs after the deletions, per the working agreement about git operations that remove a file.

- Delete the 62 in the census's approved per-file groups, one commit per group, **only after**
  stage 2's replacements exist: DayView 9, Composer 7, SidebarMove 9, WorkspaceOpenState 7,
  WorkspaceBoard 4, Wikilink 2, Diary 5, Pratiche 4, SectionToolbars+History 5, TaskCategories
  group 3, CompletionPanel 2, NoteTree 2, Design group 3. Sums to 62, checked.
- Files that disappear entirely here: `SectionToolbarsUITests`, `TimeBlockUITests`,
  `UpdateMenuUITests`, `CompletionPanelUITests`, `DesignAndReadingUITests`, `TaskTimeUITests`.
  Three of them — `TimeBlockUITests`, `UpdateMenuUITests`, `TaskTimeUITests` — are in
  `classes_for_path` and need the mapping edit (D-3); the other three are not.
- Afterwards, exactly **17** tests across **12** files: DayView 1, Composer 2, SidebarMove 3,
  WorkspaceOpenState 2, WorkspaceIntegration 1, WorkspaceBoard 1, Wikilink 1, Diary 1,
  Pratiche 1, HistoryNavigation 1, TaskCategories 2, NoteTreeAndShortcuts 1. Counted, not
  assumed: this equals the census's own per-file tally.
- `--status` prints the GUI test count against the cap of 17 (R-17). Counted from the source
  (`grep -c '    func test' UITests/*UITests.swift`, which returns 121 on this tree today), not
  from a hard-coded number. Informational only: no check fails above the cap (SPEC decision).
- One full `scripts/uitests.sh --force` run of the 17 survivors closes this task, as the last
  full run the old rule will ever require.

### Task 7 — Stage 3: the rule change (R-18, R-19)

Files: `CLAUDE.md`, `PROJECT_BRIEF.md`, `TODO.md`, `scripts/uitests.sh` (its header), and the
plan template that carries the future-feature rule.

- R-18 (no-test: documentation obligation, checked by review): `CLAUDE.md` states that the merge
  gate is the unit suite plus in-process tests; that the 17 GUI tests run through `--affected` at
  merge and do not block; that the full 17 run before a release; that `contaminated` is neither
  green nor red; and that a new feature carries at most 2 or 3 GUI tests, justified in its ADR.
- R-19 (no-test: documentation obligation, checked by review): the existing text that now
  contradicts the above is **amended in place, not left beside it**. Named, so none is missed —
  in `CLAUDE.md`'s "Working agreements": «The UI suite runs before every merge to `main`, through
  `scripts/uitests.sh`» and its PG-033 paragraph; «The whole suite is run once by whoever merges
  to `main`; every other session reads the verdict»; and in the "Git conventions" section the CI
  paragraph's closing sentence about the UI suite being «where the last several merges' real
  regressions were». The PG-033 history stays as history — what changes is the obligation, not
  the record of why it existed.
- `PROJECT_BRIEF.md` and `TODO.md` also name the pre-merge run; they are updated in the same PR
  for consistency, which is housekeeping under R-19, not new scope.
- `scripts/uitests.sh`'s own header (`:12-14`, «The written rule is in CLAUDE.md: the suite runs
  before every merge to `main`») is amended to match, or it contradicts the file it points at.

---

## 6. Observable-contract changes and their call sites

Three contracts change. Call sites were grepped across the whole repo before this section was
written, not left for the implementer to discover.

**(a) `scripts/uitests.sh`'s exit code gains the value 2, and the verdict file gains `reasons=`
with `result` taking three values.** Machine call sites: **none**. Grepping `uitests.sh` across
`*.md`, `*.sh`, `*.yml`, `*.json` and `.claude/test-cmd` finds only prose — `CLAUDE.md`,
`PROJECT_BRIEF.md`, `TODO.md`, `SPEC.md`, `.github/workflows/ci.yml:11` (a comment), the ADRs
and plans under `docs/`, stale briefs under `.claude/dispatch/`, and the script itself. Nothing
invokes it programmatically and nothing branches on its exit code, so the only consumers are a
human's shell and `--status`. The verdict format's only readers are inside the script
(`verdict_field`, `show_verdict`, `status_report`, `last_verified_ancestor`,
`record_verdict`) and `UITESTS_VERDICT_DIR` appears nowhere else in the repo. Tasks 1 and 2
update all of them; the self-test pins `last_verified_ancestor` and `status_report` against
accepting a `contaminated` verdict as verified.

**(b) Twelve production declarations change shape (§4).** Each is `private` today except the two
duplicated pairs; the call sites are the ones named in §4, each verified. Seams #1 and #7 change
the *number* of call sites (3→1 and 2→1), so their PRs must show the deleted copies in the diff.
After PR 6, both connectors (`perg`, `pergamenum-mcp`) must build, because
`Sources/Index/IndexSnapshot.swift` is in `sharedSources`.

**(c) Ten `UITests/*UITests.swift` files disappear.** Their names are a contract for
`classes_for_path` (`scripts/uitests.sh:105-124`), which maps five of the ten by name; see D-3.

**Run the full test suite, not just the touched module's tests, after every one of these.** A
seam is by definition reachable from more than the test that motivated it — seam #7's second
copy is in a different feature from the first, and seam #6 lands in a file both command-line
tools compile.

---

## 7. Risks, dependencies and HITL gates

**HITL gates — each is Stefano's, never the implementer's.**

- Every commit, every push, every PR merge (global rule and `CLAUDE.md`).
- **ADR-0053 moving to Accepted** (Task 4). The SPEC requires it Accepted before the first
  production refactor; acceptance is a decision, not a step.
- **Raising the cap of 17** (Task 3, Task 5). If a view cannot be hosted, its test stays GUI and
  the cap rises test by test with Stefano's approval — never silently.
- **Any retirement not already in the approved census** (Task 6). The census is the approval; a
  new candidate needs a new one.
- **Deleting the ten UI-test files** (Tasks 5 and 6): permanent deletions, confirmed before they
  happen.
- Stage boundaries: stages 1, 2 and 3 are each a stopping point, and the next does not start
  without a decision to continue.

**Risks.**

- **The Workspace half of R-08 may fail.** Four `Tests/` files already host SwiftUI, so that half
  is near-certain; a board view with a live controller, zoom and pan is not. If it fails, PR 1's
  four `enter(folder:)` conversions still stand (they are controller-level, not view-level), but
  `Board:100`/`:161` and the OpenState label test may have to stay GUI. This is the SPEC's own
  named risk and its named remedy.
- **The largest single loss is drag and drop.** The census says so plainly: after the four R15
  retirements, `.draggable`→`.dropDestination` and "a drag carries the whole lit set" have no
  cover at all, and a dedicated seam extracting `beginDrag` and the drop closure was considered
  and not evaluated. Those four were also the tests most damaged by the machine (PG-180: 13
  failures in 20 with the pointer disturbed, 30/30 clean on an untouched Mac), which is why they
  go — but the loss is real and should be re-read before Task 6 deletes them.
- **`SidebarMove:378` and `EditorCompletion:59` are crash regressions.** Neither may be deleted
  until its hosted replacement is shown to reproduce the crash. A replacement that passes
  against both the fixed and the broken code proves nothing; PR 5 must demonstrate red-on-revert.
- **The full proof runs are themselves machine-dependent.** Four of the seven PRs cost a full
  `--affected` run (D-4), and those runs are exactly what this chain exists to distrust. Stage 1
  first is what makes them readable: a disturbed proof run reads as `contaminated` and is rerun,
  not as a seam that changed behaviour.
- **`scripts/uitests.sh` refuses to run beside another `xcodebuild`** (`:355-358`), and the Stop
  hook builds the unit suite at the end of **every** turn. A proof run has to be started when no
  turn is closing, or it fails on a condition that is not about the code. Ask
  `scripts/uitests.sh --status` first, always.
- **PG-182's cause stays unknown.** R-06 collects evidence; it promises no cause. The census's
  second proposal — one run with the focus loop (`:396-414`) disabled, to test whether its own
  `osascript` calls are the launch trigger — is **not** in this plan's tasks and is offered to
  Stefano as a hand-experiment. Raising it here rather than doing it silently: it would mean
  running the suite in a deliberately altered configuration, which is his call.
- **Externally provisioned resources: none.** Nothing in this work needs a third-party API, a
  consent flow, a cloud console, a new env var or a port. `system_profiler` and `/usr/bin/log`
  are both present on this machine and both run without privilege, verified today. The only
  new tool dependency is `python3`, already used by two scripts in `scripts/`.
- **Out of scope, confirmed not drifted in:** the Tart VM (PG-187), the GUI suite in CI, a
  rewrite of the runner, PG-195, a check that fails above the cap, enforcing the full 17 inside
  `scripts/release.sh`, and changing what the 17 survivors assert (the two known defects — a
  negative check with no wait at `TaskCategories:179`, a `Thread.sleep(1)` at
  `NoteTreeAndShortcuts:111`, plus `History:47`'s comment promising three panes where the body
  does two — are fixed only when those files are next touched).
- **Surfaced during planning, deliberately not added:** running `scripts/uitests.sh --self-test`
  in CI. It is offline, needs no GUI and would take a second — but the SPEC does not ask for it,
  and "the GUI suite in CI" is out of scope. Raised for Stefano, not planned.

---

## 8. To be filled in during the build

- **R-08's outcome, per view kind, before any dependent test is converted (Task 3).** Filled in
  2026-09-21 on `chore/pg169-fase1-fase2` at `0b0947a`, macOS 27.0 / Xcode 27.0. Four tests in
  `Tests/HostedViewPrototypeTests.swift` (0.92 s together, run alone) over the harness in
  `Tests/HostedViewSupport.swift`, all passing inside `PergamenumTests`. The window is a titled
  `NSWindow` subclass that refuses key and main status, laid out once and never ordered in. It
  also turns `orderFront`, `orderFrontRegardless`, `makeKeyAndOrderFront`, `order(_:relativeTo:)`
  and `sendEvent` (bar AppKit's own bookkeeping events) into a recorded issue that does nothing,
  which the fourth test pins; `NSApp.activate` is not intercepted, so R-15 is held as far as a
  type can hold it and not beyond. Every test asserts `neverShown` (not visible, not key,
  `NSApp.isActive` and `NSApp.keyWindow` as they were). **Partly proven: the Workspace half
  hosts, draws and takes key equivalents; it does not take the pointer.**

  | View kind | Hosts and lays out | Drawn, read back offscreen | Key equivalent | Mouse (uncommitted probe) |
  |---|---|---|---|---|
  | SwiftUI: `RenameNoteSheet`, injected theme | yes | yes (more than one colour) | yes: Esc fires the `.cancelAction` button, `onCancel` once; Return confirms nothing while the title is unchanged (default action disabled) | not reached: 126 clicks over the sheet's frame triggered no button |
  | Workspace chrome: `BoardToolbar` over `openedWorkspaceController` | yes | not read | yes: bare `l` then `t` set `workspace.tool` to `.link` then `.text`; `z`, which no tool owns, is not handled and changes nothing | not tried separately |
  | Workspace board: `BoardContentLayer`, two link cards, zoom and pan applied as `WorkspaceView.swift:357-366`, live `WorkspaceController`, a `VaultController` with no vault open | yes | yes, and the picture changes when the controller's zoom and pan change (8 then 6 distinct sampled colours, PNGs differ) | none bound on this layer | not reached: a click, a zoom-corrected click and a four-step drag, sent to the view `hitTest` names and to the hosting view's own recognisers, changed neither the selection nor the card's frame |
  | Workspace board holding a text card | **not built; stays GUI** (decided 2026-09-21, below) | | | |

  **What is in the tree and what is not.** The four tests pin the positive results: a sheet and a
  board host and draw, a key equivalent reaches a `.keyboardShortcut` button, a bare letter moves
  the live controller, and the board redraws when zoom and pan change. The figures and negative
  results the tests do not assert (126 clicks over the sheet's frame and no button fired, the
  click, the zoom-corrected click and the four-step drag on the board, empty `gestureRecognizers`
  and `trackingAreas`, the 8 then 6 distinct sampled colours) were read by an uncommitted probe
  that is not in the tree and was not kept. They cannot be replayed from the repository, and a
  test asserting that something does not work would go red on the day it starts to work; whoever
  needs one of them re-measures it. The zoom and pan wrapper is a replica: `HostedBoard`, in the
  test file, copies the two modifiers of `WorkspaceView.swift:357-366` by hand and
  `WorkspaceView` itself was not hosted, so the redraw test pins that `BoardContentLayer`
  redraws for the controller's zoom and pan, not that `WorkspaceView` applies them the same way.
  It opens with a control, two snapshots at unchanged state that must be equal, so the difference
  it then asserts is the zoom and pan and not the snapshot's own noise.

  Why the mouse does not arrive, measured (by that probe): `hosting.gestureRecognizers` is empty,
  `trackingAreas` is empty, `acceptsFirstMouse` is false, the board's hosting view has no
  subviews (SwiftUI draws none of its own) so `hitTest` can only answer with the hosting view, and
  the SwiftUI accessibility tree in-process is one childless group. The only remaining route to
  a SwiftUI gesture is `NSWindow.sendEvent` or `NSApp.sendEvent`, which is what makes a window
  key and visible, so it was not tried: R-15 forbids it. This says nothing about an AppKit view inside a SwiftUI one:
  the prototype sent no event to an `NSTextView`, and no file in `Tests/` does today (`mouseDown`
  appears there in comments only).

  Why no text-card board: `StickyTextCard` reads `@Environment(CommandActions.self)`, and a
  missing observable object is a fatal error that ends the whole test process (seen once, in a
  probe). `CommandActions.init` takes a concrete `EventKitStore` (`CommandActions.swift:28,48`)
  whose `init()` reads EventKit's authorization status and observes `.EKEventStoreChanged`
  (`CalendarService.swift:59`, `:95-98`), and R-15 says no hosted test reads calendar state.
  The unit suite already builds `EventKitStore()` in ordinary tests (`RowCommandTests.swift:25`,
  `CommandActionTests.swift:16`, `CalendarTests.swift:275`), so whether R-15's wording reached
  that was raised for Stefano. **Decided by Stefano, 2026-09-21: R-15 stays strict.** No hosted
  test constructs an `EventKitStore`, so a board with a text card stays a GUI test and the cap of
  17 does not rise on its account. Whether such a board would host once `CommandActions` is
  supplied was not measured, and now does not need to be.

  What follows for the plan. None of Task 5's conversions is designed through a SwiftUI pointer
  gesture (PR 1 goes through `enter(folder:)`, the two pure functions and the resize seams on
  `openedWorkspaceController`; PR 2, 3, 4, 6 and 7 through pure functions and controllers), so
  the fallback this plan's own §7 names for the Workspace half (`Board:100`, `Board:161` and the
  OpenState label test staying GUI) does not trigger, and **the cap of 17 does not rise on this
  evidence**. What stays GUI is what already is: `Board:64` (the grip resize is the pointer
  chain), `OpenState:157` and `:204` (a click on a `List(selection:)` row), and the accessibility
  label as read from the
  tree, whose text seam #2 tests and whose attachment (`WorkspaceRow.swift:180`) nothing in-process
  can. PR 5's hosted tests host AppKit views the prototype did not measure (`#tag` insertion,
  `TableGridView`, the embed label, the wikilink plain-click, `menu(for:)`, the `NoteTextView`
  teardown); their precedent is `Tests/EditorHeightTests.swift:49-55`, each is proven by its own
  PR, and one that cannot be hosted stays GUI under the SPEC edge case (HITL gate, §7).
- **The unit suite's wall time after each stage-2 PR, against the 60 s budget (R-14).** After
  Task 3, the stage's opener, the approved command
  (`-only-testing:PergamenumTests`, exit 0 in all four runs):

  | | Tests | Swift Testing | xcodebuild testing phase |
  |---|---|---|---|
  | Before (clean tree at `0b0947a`) | 3350 in 181 suites | 20.913 s | 36.941 s |
  | After Task 3, first run | 3354 in 182 suites | 23.275 s | 38.081 s |
  | After Task 3, second run | 3354 in 182 suites | 20.606 s | 33.902 s |
  | After the review fixes (finished tree) | 3354 in 182 suites | 19.835 s | 33.578 s |
  | After PR 1, seams filled, call sites not yet collapsed | 3383 in 182 suites | 21.041 s | 36.111 s |
  | After PR 1 (finished tree) | 3383 in 182 suites | 21.593 s | 36.313 s |

  The four new tests took about 0.8 s as first written (0.808 s alone, 0.794 s inside the full
  run) and about 0.9 s after the review fixes added the refusal checks and the stability control
  (0.915 s alone, 0.908 s inside the full run). The after-runs differ from each other by up to
  3.4 s (Swift Testing) and 4.5 s (testing phase), more than the tests cost, and the last two are
  below the baseline on both measures: the difference Task 3 makes is smaller than this machine's
  run-to-run spread, so no cost is claimed beyond the 0.9 s. Against the 60 s budget the two measures over the three after-runs are Swift Testing's
  own 19.8 to 23.3 s and the `xcodebuild` testing phase's 33.6 to 38.1 s, both inside it. R-14
  does not define which of the two counts; against the larger the margin is about 22 s. The
  "about 18 s today" of Task 3 was not what this tree measured: 20.9 s before the task. The rows
  for PRs 2 to 7 are still to be added, one per PR.

  **PR 1** (Workspace tree and board, 2026-09-21, same tree and machine) adds 29 tests in five
  files and no suite, all free functions: 3354 to 3383. Their own reported durations sum to about
  0.06 s in the finished run, the longest being the `VaultSession` walk at 0.017 s. The two
  after-runs are 21.0 s and 21.6 s for Swift Testing and 36.1 s and 36.3 s for the testing phase,
  1.8 s and 2.7 s above the last Task 3 row, which is inside the 3.4 s and 4.5 s spread measured
  there, so no cost is claimed beyond the 0.06 s. The run that first went red (25 of the 29 tests
  failing on their `#expect`, no build error) took 20.887 s and 37.053 s and is not an after-row.
  Against the 60 s budget the margin over the larger measure is about 24 s. Every run exited 0
  except that red one.
- **Any converted test whose replacement could not be written, and the cap conversation it
  triggered (SPEC edge case).** None in PR 1 (2026-09-21): all ten of its conversions (`OpenState`
  `:216`, `:251`, `:370`, `:383`, `:405`, `:425`; `Integration` `:75`, `:166`; `Board` `:100`,
  `:161`) were written, through `enter(folder:)`, the two pure functions and the existing entry
  points, and none needed a pointer event on a hosted view or a text-card board, so the cap of 17
  did not rise. ADR-0053 was accepted by Stefano on 2026-09-21 and its text now says so. The
  GUI tests these ten replace are still in `UITests/`: deleting them waits for the `--affected`
  proof on a committed seam (R-10), and what each loses is listed test by test in the R-13
  hand-over of PR 1 rather than here. The other question, whether R-15's "reads calendar state"
  reaches the `EventKitStore()` a text-card board needs, was decided on 2026-09-21 (above): it
  does, R-15 stays strict, and the cap of 17 does not rise on its account.

---

## Test command

`TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

`TEST-CMD MODE: brownfield`

This is `.claude/test-cmd` verbatim, and the `-only-testing:PergamenumTests` restriction is
load-bearing rather than tidy: the `Stop` hook runs it at the end of every turn, and with the UI
tests in there each turn terminated the app the person at the keyboard was using and left an
instance holding the global hot key. It must not be widened by this work — and under this SPEC
it never needs to be, since the hosted tests join `PergamenumTests`.

Stage 1 changes only a shell script, which that command does not exercise. Its own check is
`scripts/uitests.sh --self-test` (Task 1, R-07): offline, no build, no GUI, seconds. It is run by
hand in stage 1's PRs; it is **not** added to `.claude/test-cmd`, because a per-turn hook that
runs a script whose job is to describe the machine is the shape of problem the hook restriction
already exists to prevent.
