# Handoff: making the UI checks deterministic (or replacing the full UI suite as a merge gate)

Written 2026-09-20 at the end of a long working session. Author: the previous Claude session.
Audience: the next Claude session, and Stefano.

## 0. Read this first: how to start this session

**Do not implement anything yet.** Your first job is to interview Stefano about this problem,
using the questions in section 9, one group at a time. The previous session reached a shared
diagnosis and a census of the tests, but Stefano has not yet chosen a direction, and several
choices are his alone (the merge rule in `CLAUDE.md`, whether UI tests may be replaced by unit
tests, whether production code may gain new seams).

**Do not work on `main` and do not work in the main checkout** (`/Users/stefer/Developer/Pergamenum`).
Stefano said so explicitly. When work starts, create a worktree and a feature branch, for example:

```
git -C /Users/stefer/Developer/Pergamenum worktree add /Users/stefer/Developer/Pergamenum.worktrees/<slug> -b <type>/<slug> origin/main
```

then run the session from that worktree. This handoff file itself is untracked in the main
checkout (see section 8 for why that matters) and is meant to be read, not edited there.

Workflow per Stefano's global rules: a non-trivial change (new production seams, a rule change)
goes `/spec` then `/plan` then `/build` then `/ship`, with `/plan` and `/build` in separate
sessions; native plan mode is enough for scoped edits. HITL gate before commit, push, merge.
Chat with Stefano is in Italian; code, commits and files are in English.

## 1. The problem in plain words

`scripts/uitests.sh` runs 121 UI tests (about 26 minutes) and `CLAUDE.md` makes that run a
precondition of every merge to `main`. In practice its verdict depends on the state of the
computer, not only on the code: another app coming to the front, an external monitor, a copy of
the installed app opening by itself, the XCTest automation mode timing out. A red that means
"the machine was disturbed" reads exactly like a red that means "the app is broken", and
Stefano's conclusion at the end of the session was: this kind of check is too sensitive to the
state of the machine.

His two follow-up questions, which define this task:

1. What checks could replace the complete UI suite?
2. Can a good part of the checks done through the GUI be made deterministic?

The previous session answered both in outline and ran a census (section 5). The decision on
direction is open.

## 2. Evidence from 2026-09-20 (all times local, all from this repo)

| Time | Run | Result | Interference seen |
|---|---|---|---|
| 11:22 | full, earlier session | 108/120, 12 red | external monitor (PG-188); installed app appeared (PG-182, third time) |
| 13:23 | full, tree `d0c81b0` | 98/120, 22 red, all in Workspace classes plus one Wikilink | GitKraken took focus 24 times; `/Applications/Pergamenum.app` (PID 60195) appeared mid-run |
| 14:12 | the same 22 tests alone | **22/22 green**, 376 s | installed app closed, other apps minimised; focus taken 4 times (Finder) |
| 14:36 | full | 0 tests executed, `red (full)` recorded | XCTest: "Timed out while enabling automation mode" after 74 s |
| 21:13 | `TaskCategoriesUITests` (2 tests) | 2/2 green, 23.8 s | focus taken twice (Xcode, ChatGPT) |
| 22:18 | full, tree `2da15a8` (HEAD `eb45398`) | 121 tests, **21 red**, 1559 s, `red (full)` recorded 22:45 | installed app started **22:35:31**, PID 89477, parent `launchd`, not a login item, not a launch agent; Xcode took focus 19 times |

Facts:
- The last green full run was on `main` at `b74d561` (2026-09-20, 120/120, 1439 s, recorded in PG-184).
- The same failing set (Workspace classes) appeared twice, both times in a run where the installed
  app appeared mid-run. The 22 alone, without it, all passed.
- In the 22:18 run every class that ran before 22:35 passed. Per-class start times were
  **estimated** from cumulative test durations in the `.xcresult` (about 1.5 minutes of error),
  and `WikilinkNavigationUITests` sits on the boundary. There are no per-test timestamps.
- Who launches the installed app is unknown (PG-182). A Plaud launch agent exists
  (`it.stefer.plaud-service`); whether it opens Pergamenum was **not checked**.

Hypotheses, not established:
- The installed app taking activation is the main cause of the Workspace reds.
  The mechanism could be focus/key-window loss (one failing message is "Neither element nor any
  descendant has keyboard focus", which is a key-window symptom, not an app-logic failure) or
  contention for the app's global hot key (`Sources/Features/Capture/GlobalHotkey.swift`).
  Neither was isolated.
- PG-188 (external monitor) was not excluded on the evening runs: the display setup was not checked.

## 3. What the failing assertions depend on (from reading the code, nothing was run)

- **"la riga workspace-board-... non riporta lo stato selezionato"** (9 OpenState tests via
  `assertExactlyOneRowSelected`, `UITests/WorkspaceOpenStateUITests.swift:149-150`): queries
  `identifier == X AND label ENDSWITH ', aperta'` inside `workspace-tree`. In several of these
  tests the earlier assertion "Nessuna board aperta" passes, so the click and the controller state
  worked; what fails is the accessibility-label query. The label is built in
  `Sources/Features/Workspace/WorkspaceRow.swift:195-203`; the file's own comments at `:156-178`
  document a label/value trap. Inferred, not proven.
- **Grip resize tests** (`WorkspaceBoardUITests.swift:64, 84, 161`): all three need a selecting
  click first (`onTapGesture`, `BoardContentLayer.swift:92-99`), then a drag starting on a grip that
  is only drawn when selected (`:108, :165`), through `DragGesture(minimumDistance:0, .global)`
  (`BoardHandles.swift:69-87`). The grip size maths is already unit-tested. The two group tests that
  passed are the ones that never do the first click (inferred).
- **"lo zoom è fermo a 37% dopo 2 click"** (`WorkspaceBoardUITests.swift:276`, inside
  `zoomOutBelowPlaceholder`): not a clamp (`zoomRange` 0.05...4.0). Either the second click did not
  reach the button or the accessibility value did not refresh.
- **"la sidebar dell'app non è tornata"** (`WorkspaceFocusUITests.swift:67`): the first click hid the
  sidebar, so the toggle works; the state derivation (`RootView.swift:76-86`) is a one-liner.
  Points to real rendering or the second click not registering.
- **"Neither element nor any descendant has keyboard focus"**: emitted by XCUI keyboard synthesis
  (`typeText`, `typeKey`). Candidate lines: `WorkspaceBoardUITests.swift:115`,
  `WorkspaceIntegrationUITests.swift:218/227/326/334/370-371`, `WorkspaceOpenStateUITests.swift:267`.
  Which test emitted it was not identified.

## 4. Options considered so far (none chosen)

1. **Isolate the machine: run the UI suite in a Tart macOS 27 VM (PG-187).** A separate handoff
   already exists: `docs/plans/pg-187-tart-vm-ui-suite-handoff.md` (10 unverified assumptions, a
   step plan starting with an ad-hoc-signed `build-for-testing` on the host, stop criteria).
   Cost: hours, real chance of not working. Nothing was downloaded or installed.
2. **Make the verdict honest.** `scripts/uitests.sh` already knows when an installed copy appears,
   when focus is stolen and when automation times out. It could record a `contaminated` verdict
   instead of `red (full)` and not count it as green or red. Covers PG-194 (a run with 0 tests
   recorded as `red (full)` replaced the informative verdict in `--status`) and the diagnostic side
   of PG-182 and PG-186. No new machinery on the Mac.
3. **Change the rule in `CLAUDE.md`** ("the UI suite runs before every merge to `main`"). Keep the
   full run as a periodic check, gate merges on the unit suite plus `--affected` plus a small UI
   smoke set. This is Stefano's decision (he introduced the rule after three tests sat red
   unnoticed, PG-033).
4. **Make most UI checks deterministic by moving them in-process** (section 6).
5. **Unverified idea:** run the UI suite on a GitHub Actions macOS runner (a clean machine). Whether
   a runner with macOS 27 exists was **not checked**. CI today (ADR-0044) builds three targets and
   runs `PergamenumTests` only.

The previous session's recommendation: option 2 first (cheap, removes noise), then option 4, then
option 1 only if residual noise stays high; option 3 depends on how much the rule costs Stefano.

## 5. Census of the 32 Workspace/Wikilink UI tests

Produced by a read-only subagent, then spot-checked by the previous session (seven references
verified against the files: test names and lines, three copies of the resolver-then-select switch,
the row-label function, the `NSEvent.modifierFlags` gate, no NSEvent synthesis in `Tests/`, test counts
per file). It ran nothing. Abbreviations: W/ = `Sources/Features/Workspace/`, T/ = `Tests/`.

Categories: LOGIC (derived state, testable with no view), GEOMETRY (coordinate maths), HOSTED-VIEW
(real view in an unshown window, events sent directly), NEEDS-SCREEN (real rendering or focus).
Counts: LOGIC 22, HOSTED-VIEW 5, GEOMETRY 4, NEEDS-SCREEN 1.
Of the 21 red on 2026-09-20 22:18: 16 LOGIC, 3 GEOMETRY, 1 HOSTED-VIEW, plus one OpenState failure
inferred to be R08 (NEEDS-SCREEN). The breakdown of which 11 of 15 OpenState tests failed was
inferred, not read from a result bundle.

| Test (file:line) | Cat. | Seam today | Covered by unit test today |
|---|---|---|---|
| Board:64 GripResizesTheCard | GEOMETRY | W/WorkspaceController+Gestures.swift:120-150 `beginResize/updateResize/endResize`; W/BoardGeometry.swift:82 | maths yes (T/BoardInteractionTests.swift:12,19,27,50); controller commit to file no |
| Board:84 GripZoomedOut | GEOMETRY | BoardGeometry.swift:52,43,46,262 | yes (BoardInteractionTests:288,298,303,204); `zoom(by:in:)` with a real viewport no |
| Board:100 ZoomedOutLabel | LOGIC | NO SEAM: private `accessibilitySummary(for:)`, W/BoardContentLayer.swift:239 | branch yes (:204); label string no |
| Board:111 ArrowToolConnects | LOGIC | Gestures.swift:166-202; W/WorkspaceController+Nodes.swift:152 | yes (T/WorkspaceControllerToolsTests.swift:87,112,129,146; BoardInteractionTests:309,319,325) |
| Board:132 DraggingMiddleOfGroup | GEOMETRY | W/BoardHandles.swift:124 `GroupFrameShape` | yes (BoardInteractionTests:332,342,352); UI test is a negative assertion that passes vacuously |
| Board:147 GroupMovesByFrame | LOGIC | BoardGeometry.swift:157; Gestures.swift:13-59 | yes (BoardInteractionTests:91,103; WorkspaceControllerToolsTests:10,36) |
| Board:161 CardInsideGroup | GEOMETRY | BoardHandles.swift:124; BoardGeometry.swift:64; Gestures.swift:110 | shape yes; select and resize commit no |
| Focus:49 ConcentrazioneHides | LOGIC | `Navigation.isWorkspaceFocused` (Sources/App/Navigation.swift:156); NO SEAM for the derivation in RootView.swift:67-86 | flag independence only (T/NavigationPaneFocusTests.swift:11-40) |
| Focus:74 TrayStateUntouched | LOGIC | `Navigation()` | no |
| Integration:75 BrowserBoardDashboardSurviveRestart | LOGIC | session-level walk: `WorkspaceReferences.notes(in:)`, `TaskParser+Writes.swift:229,142`, `IndexSnapshot.swift:197,204,213`, `VaultSession.rescan` (:323); strings in W/BoardTray.swift:129 and Sources/Features/Tasks/TasksView+List.swift:215 are NO SEAM | pieces yes (T/TaskMarkerTests, TaskMarkerWriteTests, WorkspaceReferenceTests, IndexCacheTests); end-to-end reopen no |
| Integration:153 NoteToAmbiguousFolder | LOGIC | NO SEAM: private `placePendingNote` W/WorkspaceView.swift:210; `VaultController.swift:306,312,280` | resolver yes (T/WorkspaceBoardResolverTests.swift:60); hand-off and problem text no |
| Integration:166 NoteToFolderWithNoBoards | LOGIC | same | resolver yes (:84); hand-off no |
| OpenState:157 PaneOpensEmpty | LOGIC | `WorkspaceController.attach/open(board:)` | yes (T/WorkspaceOpenStateTests.swift:45,63) |
| OpenState:171 LeavingAndReturning | LOGIC | `attach/detach`; view rebuild `WorkspaceView.swift:25,176-179` | logic yes (:45,208); view rebuild no |
| OpenState:191 FolderOwnsBoardRow | LOGIC | W/WorkspaceTree.swift `build`; W/WorkspaceBrowser+Tree.swift | yes (T/WorkspaceTreeTests.swift:83,162,215,223) |
| OpenState:204 SelectingNestedBoardLightsOneRow | LOGIC | `opening(...)` W/WorkspaceBrowser+Tree.swift:222; label NO SEAM W/WorkspaceRow.swift:195-203 | logic yes (T/WorkspaceMultiSelectionTests.swift, WorkspaceTreeTests:189-203); label no |
| OpenState:216 BoardLessFolderClosesBoard_R04 | LOGIC | `select(.folder)` W/WorkspaceController.swift:310-330 | yes (WorkspaceOpenStateTests:151; WorkspaceMultiSelectionTests:52); label no |
| OpenState:231 BoardLessFolderOpensNoBoardNoSheet_R05 | LOGIC | `select(.folder)` | partly; **near-vacuous**: both assertions already true before the click |
| OpenState:251 CreatingFolder_R01 | LOGIC | `CanvasStore.createFolder` (Sources/Vault/CanvasStore.swift:249); NO SEAM for the verb (W/WorkspaceView+FolderVerbs.swift) | store yes (T/WorkspaceCreationTests.swift:37,50); view verb no |
| OpenState:282 TwoBoardsOneFolder_R03 | LOGIC | `WorkspaceTree.build`, `open(board:)`, `opening` | yes (WorkspaceOpenStateTests:80; WorkspaceTreeTests:97) |
| OpenState:300 EmptyFolderRow_R10 | LOGIC | `CanvasStore.allFolders()`, `build`, `select` | yes (WorkspaceTreeTests:112; WorkspaceOpenStateTests:151; WorkspaceCreationTests:50) |
| OpenState:318 RootLevelCanvas_R11 | LOGIC | `build`, `identifier(for:)` | yes (WorkspaceTreeTests:57,73; WorkspaceOpenStateTests:135) |
| OpenState:343 BoardContextMenu_R08 | NEEDS-SCREEN | NO SEAM: hardcoded Buttons W/WorkspaceRow.swift:284-285 | enablement only (T/WorkspaceBrowserToolbarTests.swift:42-60) |
| OpenState:370 DblClickAmbiguousFolderCard | LOGIC | W/BoardCardMenu.swift:179 `BoardCardActions.open`, private `enter` :208 | resolver and `select` yes; `BoardCardActions.open` on a folder card no |
| OpenState:383 DblClickFolderCardNoBoards | LOGIC | same | same |
| OpenState:405 BreadcrumbAmbiguousAncestor | LOGIC | NO SEAM: private `open(ancestor:)` W/BoardChrome.swift:50-61 | breadcrumb segments yes (WorkspaceOpenStateTests:224,240,255); click routing no |
| OpenState:425 BreadcrumbNotFoundAncestor | LOGIC | same | same |
| Wikilink:109 CmdClickBoldWikilink | HOSTED-VIEW | `performLinkNavigation` Sources/Features/Editor/NoteTextView+Coordinator.swift:418; gate `:410-411` reads live `NSEvent.modifierFlags` | styling and URL yes (T/MarkdownStylerTests.swift:200; MarkdownAttributedTextTests:263-323); navigation no |
| Wikilink:137 CmdClickWikilink | HOSTED-VIEW | same | same |
| Wikilink:163 PlainClickAfterPriorClick | HOSTED-VIEW | `textView(_:clickedOnLink:at:)` :410-413 | no; vacuous in UI by its own comment |
| Wikilink:180 PlainClickPlacesCaret | HOSTED-VIEW | `CompletingTextView+Pasteboard.swift:23-47` | no; the body only checks "X" is in the text, "PlacesTheCaret" is not asserted |
| Wikilink:209 RightClickApriCollegamento | HOSTED-VIEW | `menu(for:)` `CompletingTextView+Pasteboard.swift:138-159`, `openLinkFromMenu` :168; `rightMouseDown` override has NO SEAM | no |

Tests whose name promises more than the body asserts, or that pass vacuously: Focus:49 (asserts two
of the three panels, the tray is never rendered in that fixture), Focus:74 (structural), OpenState:231
(R05), Board:132 (negative), Board:161 (never observes selection, only that the card widened),
Board:84 (the "grabbable when zoomed out" maths is a unit test already), Wikilink:163 and :180,
Integration:75 (nine UI steps with `continueAfterFailure = false`, one failure hides the rest).

## 6. What "deterministic" would look like here

Already proven in this repo: 12 files in `Tests/` host real AppKit views in a window that is never
ordered front (`EditorHeightTests` `:31-57`, `CompletionPanelPlacementTests` `:15-30`,
`TableCaretTests` `:68-75` via `doCommand(by:)`, `EmbedResizeGestureTests` `:120-160` "directly, no
NSEvent synthesis", `EmbedEditorTestSupport` `:48-70`), and one hosts SwiftUI
(`NSHostingView<NoteTextView>`, `ViewQueryEntryPointTests` `:249-283`). The controller harness is
`openedWorkspaceController(rootURL:)` and `CanvasTemporaryRoot` in `T/CanvasTestSupport.swift`.

NOT proven: hosting `BoardContentLayer`, `WorkspaceRow` or `RootView` in-process (would need a
`VaultController` environment and a theme); a synthetic right-mouse `NSEvent` with `menu(for:)`
offscreen; whether `NSTextView.mouseDown` blocks in-process. No test in `Tests/` synthesizes an
`NSEvent` or calls `mouseDown(with:)`.

Seams that would unlock the most tests (the census's ranking):
1. New `WorkspaceController.enter(folder:)`, replacing three copies of "resolve the board; if
   `.unique` select the board, else select the folder": `W/BoardChrome.swift:55`,
   `W/BoardCardMenu.swift:209`, `W/WorkspaceView.swift:210`. Unlocks the two breadcrumb tests, the two
   folder-card tests, and (with the problem sentence extracted) the two Integration hand-off tests.
   Production code, and it removes a real duplication (ADR-0025 says `WorkspaceBoardResolver` is
   the one place; the three switches around it are what drifts).
2. Existing seams, new tests only, no production change: `beginResize/updateResize/endResize` plus
   flush and reload on `openedWorkspaceController` (three Board tests); `Navigation()` for the
   tray/focus invariant; `BoardCardActions.open` with a folder card; a `VaultSession` walk (write,
   `rescan`, reopen) for the Integration:75 test.
3. Extract the row label (`WorkspaceRow.swift:195`) and the card summary (`BoardContentLayer.swift:239`)
   into pure functions: removes the accessibility-tree dependency of the nine
   `assertExactlyOneRowSelected` tests and ZoomedOutLabel.
4. Editor: a capturing variant of `EmbedEditorFixtures.editor` (it hard-wires `onFollowLink: { _ in }`)
   plus an injectable Cmd-state closure instead of `NSEvent.modifierFlags` at
   `NoteTextView+Coordinator.swift:411`. Without injection the plain-click negative test depends on
   Stefano not holding Cmd during the run.
5. `RootView.isFocusedPane` / `sidebarVisibility` (`RootView.swift:67-86`) into a pure function on
   `Navigation`. The `NavigationSplitView` collapse itself stays NEEDS-SCREEN.

A caution that must not be lost: moving logic into unit tests does not cover the SwiftUI wiring.
`CLAUDE.md` records a wiring defect that a state test cannot see: a `DisclosureGroup` label is not a
`List(selection:)` row, so `.tag` on it silently binds nothing. A couple of UI tests for "a click on
a tree row really selects it" should stay. `CLAUDE.md` also says the last several merges' real
regressions were found in the UI suite, so a full replacement is not on the table; a tiering is.

Not deterministic by nature: real drawing, TextKit 2 lazy layout (`firstRect(forCharacterRange:)` is
a zero rectangle for a range not yet laid out), real gesture synthesis, the real key-window and
focus chain, menu bar and context menus, system drag-and-drop.

Existing hermeticity flags every UI test file must keep passing: `-disableCalendar YES`,
`-disableUpdater YES`, `-mailStoreRoot <fixture>`. A candidate new one: a launch flag that turns off the
global hot key so a second instance cannot contend for it, plus a fixed window position on the main
display (would remove the PG-188 external monitor effect). Not verified to fix the Workspace reds.

## 7. Related ledger entries (`TODO.md`)

- PG-182: a copy of `/Applications/Pergamenum.app` appears mid-run (four observations now, today two).
- PG-183: the Stop hook replays a cached failure until a 300 s TTL when only gitignored files change
  (`tuist generate`); the hook lives in vibe-coding-lean, outside this repo. Observed again today.
- PG-185, issue #343: proves the shared UI verdict of #338 on real runs. Real so far: a `partial`
  verdict, a `red (full)` verdict, the refusal to start with the installed app open, no verdict on a
  dirty tree. Still unproven: a green `full` verdict, a skipped repeat run, the lock across two
  sessions. **Closes only on a green full run.**
- PG-186: focus stolen during runs (Mail, GitKraken, Finder, Xcode, ChatGPT observed); cause of reds not
  confirmed.
- PG-187: the Tart VM spike (fog entry), handoff in `docs/plans/`.
- PG-188, issue #348: `uitests.sh` does not handle a second monitor.
- PG-194: a 0-test run is recorded as `red (full)` and replaces the informative verdict.

## 8. Repo and machine state at handoff

- `main` at `eb45398` (PR #360), clean except two untracked files under `docs/plans/`: this handoff
  and `pg-187-tart-vm-ui-suite-handoff.md`. Only one worktree exists (the main checkout); all other
  worktrees were removed by Stefano during the session after checking their tips were in `origin/main`.
- Merged today from this session: #338 (shared UI-suite verdict, `scripts/uitests.sh` + `CLAUDE.md`),
  #344 and #358 (ledger syncs). #358 added PG-194 and closed PG-174.
- Unit suite: about 3300 tests in about 21 s, green. The Xcode project is regenerated (`tuist generate
  --no-open`) after every pull that adds or removes files.
- **A full UI run writes a verdict only on a clean tree.** An untracked file in the main checkout
  (like the two handoffs) makes the tree dirty, so the run's verdict is not recorded and #343 cannot
  close. The previous session moved the untracked file out of the repo for the duration of the run and
  restored it afterwards, with an `EXIT` trap. `scripts/uitests.sh --status` shows what is verified.
- Running the script: `scripts/uitests.sh` takes `-only-testing:PergamenumUITests/<Class>[/<test>]`
  arguments that **replace** the selection. In zsh an argument list held in a variable is not word-split:
  build a real array. It refuses to start with `/Applications/Pergamenum.app` open. A red is diagnosed from
  its bundle first: `xcrun xcresulttool get test-results summary --path <bundle>` and
  `... get test-results tests --path <bundle>`, before anything is rerun.
- Do not run anything that builds while the Stop hook may be running one on the same tree if it can be
  avoided; the hook runs the unit suite at the end of every turn.

## 9. Questions to ask Stefano before proposing a design

Ask these in Italian, one group at a time, and record the answers before any planning.

1. **Goal.** What must the check that guards a merge give you: a fast answer (minutes), a trustworthy
   answer regardless of what the Mac is doing, or full coverage of gestures and layout? Which of the
   three do you give up first?
2. **The rule.** Are you willing to amend the `CLAUDE.md` rule "the UI suite runs before every merge to
   `main`" (for instance: unit suite plus `--affected` plus a small UI smoke set as the merge gate, the
   full suite periodic)? What would make you comfortable with that: a schedule, a nightly run, a
   number of merges?
3. **Replacing tests.** Around 12 of the 22 LOGIC UI tests are already covered by unit tests. Is it
   acceptable to remove or retire a UI test when an equivalent unit test exists (your global rule forbids
   disabling a test to make a suite pass, so this needs your explicit yes, and probably a per-test list
   you approve)? Or should the UI tests stay and only be made robust?
4. **Production code.** Are you fine with small refactors of production code only to create test seams
   (`WorkspaceController.enter(folder:)`, pure label functions, an injectable Cmd-state closure)? Does
   any of this need an ADR in your view?
5. **The machine.** Do you use an external monitor during test runs? Who or what opens
   `/Applications/Pergamenum.app` while a run is going: do you use it while runs happen, or does
   something else (Plaud service, a URL scheme link, Sparkle, Raycast) open it? Which apps are open
   during a run?
6. **The VM.** Is PG-187 (Tart VM) still wanted, as the real fix for isolation, or shelved in favour of
   the in-process route? Do you accept a multi-hour spike with a real chance of failing?
7. **CI.** Do you want the UI suite on a GitHub Actions macOS runner if one with macOS 27 exists
   (unchecked), and are you willing to pay its minutes?
8. **Priority.** How does this compare with feature work: how much time is this worth, and is a partial
   result (say, only the Workspace files migrated) a good stopping point?
9. **`uitests.sh`.** Is a `contaminated` verdict (installed app appeared, automation timeout, focus
   stolen) the right treatment for runs disturbed by the machine, and should such a run ever block a
   merge?
10. **What you do not want** to lose from the UI suite under any option: which regressions has it
    caught that you would never want to find by hand?

After the answers, propose at most two options with costs, and let Stefano choose before writing a
`SPEC.md` or a plan.

## 10. Sources

- The session transcript: `/Users/stefer/.claude/projects/-Users-stefer-Developer-Pergamenum/825185a6-f756-4a17-be9c-1b1ec1026b33.jsonl`
- Test run logs and result bundles of 2026-09-20 in `/var/folders/mr/_0ld8xhs7w3gvkg17t84pjcw0000gn/T/`,
  names `pergamenum-uitests-20260920-*` (13:23 `132314`, 14:12 `141212`, 22:18 `221850`); they may be
  cleaned by the system.
- `docs/plans/pg-187-tart-vm-ui-suite-handoff.md`, `scripts/uitests.sh`, `CLAUDE.md` (working agreements
  on UI tests), `TODO.md` (entries in section 7).
- Not verified: the cause of the Workspace reds (installed app, focus, monitor), whether a macOS 27 runner
  exists on GitHub Actions, the in-process feasibility of hosting the Workspace views, who launches the
  installed app, which 11 of 15 OpenState tests failed in the last run.
