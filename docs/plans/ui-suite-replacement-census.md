# UI suite replacement: decisions and census

Written 2026-09-21. Follows `ui-suite-determinism-handoff.md` (2026-09-20), whose section 9
questions were put to Stefano in an interview. This file records his answers and the census of
the 89 UI tests the handoff did not cover. The 32 Workspace/Wikilink tests are censused in the
handoff's section 5 and are not repeated here.

Status: interview done, triage not started. No test has been retired, no production code changed.

## 1. Decisions taken by Stefano (2026-09-21)

1. **Goal.** The check that guards a merge must be trustworthy regardless of what the Mac is doing.
   Given up first: full coverage of gestures and layout, then speed.
2. **Direction (revised during the interview).** Replace the full UI suite as a merge gate. The gate
   becomes the unit suite plus in-process tests (AppKit/SwiftUI views hosted in a never-shown window).
   GUI tests survive only as **2 or 3 targeted tests per new feature**, written in the PR that
   introduces the feature. This supersedes the earlier answer "reduced gate with a UI smoke set".
3. **Existing 121 UI tests.** Per-test triage, then retire. Nothing is retired without Stefano's
   explicit approval of the per-test list. A few tests remain, not zero.
4. **Production code.** Small refactors that only create test seams are accepted, provided behaviour
   does not change. One ADR for the whole package of seams.
5. **Machine.** External monitor usually connected during runs. Xcode, GitKraken and chat apps
   (ChatGPT, Mail) stay open. Who opens `/Applications/Pergamenum.app` mid-run is unknown (PG-182).
6. **VM (PG-187).** On hold in favour of the in-process route.
7. **CI runner.** First check whether a GitHub Actions macOS runner with macOS 27 exists (not yet
   checked), then decide.
8. **Priority.** Before new feature work, in stages, each stage a useful stopping point.
9. **`uitests.sh` verdict.** A run disturbed by the machine is recorded as `contaminated`: neither
   green nor red, and it does not block a merge by itself.
10. **Must not be lost** (all four ticked): SwiftUI wiring (the `DisclosureGroup`/`.tag` class of
    defect), real gestures, focus/keyboard/layout, end-to-end flows.

Residual risk to keep visible: decision 2 leaves existing features with no GUI wiring check except
what in-process hosting can cover. `CLAUDE.md` records that the last several merges' real
regressions were found by the UI suite. Hosting Workspace views in-process is not proven
(handoff section 6).

## 2. Totals over all 121 tests

| Category | Handoff (32) | This census (89) | Total |
|---|---|---|---|
| LOGIC | 22 | 19 | 41 |
| HOSTED-VIEW | 5 | 27 | 32 |
| NEEDS-SCREEN | 1 | 41 | 42 |
| GEOMETRY | 4 | 2 | 6 |

Categories: LOGIC (derived state, testable with no view), GEOMETRY (coordinate maths), HOSTED-VIEW
(a real view could be hosted in a never-shown window, events sent directly), NEEDS-SCREEN (real
rendering, focus, menus, drag and drop).

**Provenance and limits.** Produced by three read-only subagents, one per group of files, reading
each test body and grepping `Tests/`. The classifications and every file:line are the subagents'
were spot-checked on 2026-09-21 against the files (11 claims, all held, listed in section 4).
That is a sample, not a proof: re-check the specific claims a retirement rests on. "HOSTED-VIEW" for
SwiftUI views is an assumption, only `ViewQueryEntryPointTests` hosts SwiftUI today.
"Weak" means the name promises more than the body asserts, a negative assertion that cannot fail,
or an assertion true before the action.

## 3. Census (89 tests)

Abbreviations: T/ = `Tests/`, `UT` = unit test.

### 3.1 Group A

| Test | Cat. | Covered by UT today (what is left) | Weak |
|---|---|---|---|
| CompletionPanel:98 AHashInsideAWikilinkOffersTheHeadingsOfThatNote | HOSTED | EditorCompletionTests:202,215,243, CompletionPanelTests:55 (production `noteSections` closure, drawing) | partly: one loop iteration can pass with no panel |
| CompletionPanel:116 AColonOffersEmojiByName | HOSTED | EmojiCompletionTests:23,30 (footer string) | no |
| CompletionPanel:146 ArrowingPastTheVisibleEdgeScrollsTheList | HOSTED (scroll itself NEEDS-SCREEN) | CompletionPanelTests:206 (15 presses, index 15, scroll) | yes: never asserts the scroll |
| CompletionPanel:167 TypingAfterTheLastHeadingReachesTheEndOfTheNote | NEEDS-SCREEN | EditorHeightTests:64,78,100 (its own header says it stays green with the fix removed) | no |
| CompletionPanel:189 TheCompletionPanelOpensOnTheLastLine | GEOMETRY/HOSTED | CompletionPanelPlacementTests:35,57,68,143,171 (real position) | yes: never asserts the panel exists or where |
| Composer:57 ANewNoteIsNamedInTheEditor... | NEEDS-SCREEN | NewNoteDraftTests:34+, VaultSessionTests:30 (`VaultController.createNote`, Return path) | partly |
| Composer:86 TheNewNoteComposerCanBeAbandoned | HOSTED | NewNoteDraftTests:93 (button wiring) | yes: negative, no check that no file was created |
| Composer:100 TheTaskComposerCarriesTheDestination... | HOSTED | TaskComposerTests:38 (view) | yes: asserts absence of an id that does not exist in Sources |
| Composer:117 TheProgrammaPanelListsTheQuickChoices... | HOSTED | DateEntryTests:9 (view-only rows) | no, existence only |
| Composer:140 TheReminderSetInsideTheProgrammaPanel... | NEEDS-SCREEN | TaskComposerTests:61,104 (panel producing the reminder) | partly: prefix only, not the hour |
| Composer:171 AChoiceFurtherOutWritesTheDayItNames | HOSTED | DateEntryTests:9, TaskComposerTests:9 (click to binding) | no; near-duplicate of :224 |
| Composer:194 TheScadenzaPanelIsACalendar... | HOSTED | TaskComposerTests:38 (calendar click, dismissal) | no |
| Composer:224 ATaskComposedWithADateIsWrittenWithThatDate | HOSTED | TaskComposerTests:9,72 | no; near-duplicate of :171 |
| Composer:251 TypingAfterChoosingADate... | NEEDS-SCREEN | none (`ComposerTextField` selection has no accessor) | no; real regression check |
| Composer:283 AttivitaOpensOnTheViewTheCapturedTaskLandedIn | NEEDS-SCREEN | TaskComposerTests:143,51 (private `TasksView.followLastCapture` mapping) | yes: "Inbox" text also matches the always-listed view title |
| Composer:300 TheTaskComposerOpensFromAPaneThatIsNotAttivita | NEEDS-SCREEN | CommandActionTests:38 only (`run(.quickTask)` sets `taskDraft`: nothing) | no |
| DayView:85 VaiADataUsesTheAppsOwnCalendar | HOSTED | none | no |
| DayView:99 VaiADataMovesTheDay | HOSTED | none for `DayController.show` | no |
| DayView:119 ADateTypedIntoVaiADataIsRead | LOGIC | DateEntryTests:40 (sheet applying it) | no |
| DayView:135 TheMonthCanBePutAway... | HOSTED | none (`@AppStorage todayShowsMonth` private) | partly |
| DayView:154 TheMonthFollowsTheDivider... | NEEDS-SCREEN | DateEntryTests:87,100 (divider drag) | partly |
| DayView:190 TheHeaderShowsTheDateTheItalianWay | LOGIC | DateEntryTests:73 (header uses it) | yes: reversed-date check cannot match |
| DayView:208 TheToolbarCapturesANewTask | NEEDS-SCREEN | none for `beginTaskCapture` | partly: never asserts the composer closed |
| DayView:221 TheBellShowsWhatFallsDueNext | HOSTED | TaskViewTests:173 (flag default, card) | partly |
| DayView:248 TheMonthMarksTheDaysSomethingIsDueOn | HOSTED | TaskViewTests:173 (dot drawing) | no |
| DayView:256 TheCompletedFilterBringsFinishedTasksBack | HOSTED | TaskViewTests:203 (toggle binding) | no |
| DesignAndReading:54 TheSidebarNoLongerCarries... | LOGIC | SidebarTests:9,15 (no "Design system" row asserted) | yes: 3 of 5 assertions negative |
| DesignAndReading:66 AThemeFileInTheVaultReachesTheThemePicker | NEEDS-SCREEN | ThemeCustomizationTests:110 (`attach` call site, picker filter) | no |
| DesignAndReading:91 TheDesignSystemPaneEditsTheVaultsOwnThemeFile | NEEDS-SCREEN | ThemeCustomizationTests:97,142 (`resetCustomization` untested) | yes: never edits a colour |
| DesignAndReading:129 NoReadingModeToggleOrMenuEntry... | NEEDS-SCREEN | none | yes: 3 negatives, "shows the source" check is tautological |
| DesignAndReading:159 TheEditorRendersATableAsAGrid... | NEEDS-SCREEN | TableRenderingTests:228 (its comment leaves TextKit hosting to this test) | no |
| EditorCompletion:59 TypingAHashAtTheStartOfALine... | HOSTED | EditorCompletionTests:20 (`textDidChange` with `#tag` not driven) | partly: liveness only |

### 3.2 Group B

| Test | Cat. | Covered by UT today (what is left) | Weak |
|---|---|---|---|
| Diary:56 TheDiarySectionCarriesItsToolbar | NEEDS-SCREEN | actions only: DiaryControllerTests:123, DiaryComposerTests:24 | no, existence only |
| Diary:68 TheEditorIsTheOnlyWritingSurfaceOnScreen | HOSTED | none | yes: negatives on ids that exist nowhere |
| Diary:77 ABlockIsComposedAndWrittenToTheFile | LOGIC | DiaryControllerTests:45, DiaryComposerTests:24 (chain on disk) | no |
| Diary:94 ABlockIsDeletedFromTheTimeline | LOGIC | DiaryControllerTests:239, DiaryTests:121 (x button) | no |
| Diary:110 ABlockIsOpenedAndRenamed | LOGIC | DiaryComposerTests:47 (renamed title on disk) | no |
| Diary:128 ABlockIsDeletedFromItsSheet | LOGIC | DiaryControllerTests:239 (Elimina wiring) | no |
| Diary:141 TypingIsSavedAndSurvivesAChangeOfDay | LOGIC | DiaryControllerTests:79,123,142 | yes: second check reads a file that already held the text |
| Diary:163 TwoBlocksAtTheSameHourAreBothKept | LOGIC | DiaryControllerTests:262, DiaryTests:228 | no |
| Diary:177 DraggingOverEmptyTimeBlocksItOut | GEOMETRY | DiaryTests:200, DiaryComposerTests:24 (`DiaryGeometry` untested, drag maths private) | no |
| Diary:205 ABlockIsMovedByDragging | GEOMETRY | DiaryControllerTests:188 (`snappedDelta` private) | no; hard-codes 120 pt |
| HistoryNavigation:34 TheArrowsAreOffUntilThereIsSomewhereToGo | LOGIC | NavigationHistoryTests:25, CommandActionTests:56 (real observer, `.disabled`) | partly: initial-off checks true with no recorder |
| HistoryNavigation:47 TheArrowsWalkThePanesInOrder | LOGIC | NavigationHistoryTests:35 (`WindowPlace.apply` untested) | yes: comment says 3 panes, body does 2 |
| HistoryNavigation:65 ScrollingTheDayLeavesOneEntry | LOGIC | NavigationHistoryTests:75,89 (`lastDayMoveWasDrift`, `isDrift` untested) | no |
| NoteImage:63 TheEditorDrawsTheEmbeddedPicture... | HOSTED | EmbedCaretTests:285,318, EmbedResolutionTests:66,91 (missing placeholder a11y) | yes: cannot tell drawn from placeholder |
| NoteTree:57 TheSidebarShowsFoldersAndOpensThemOnClick | NEEDS-SCREEN | NoteTreeTests:26,36,46,101 (expand/collapse state private) | mild |
| NoteTree:93 ANoteInAClosedFolderCanStillBeOpened... | NEEDS-SCREEN | NoteTreeTests:87 (private `reveal`, `QuickSwitcher.choose` untested) | yes: tab title can satisfy the last check |
| NoteTree:111 AShortcutChangedInSettings... | NEEDS-SCREEN | ShortcutTests:134,231,243,257 (menu using the store) | mild |
| NoteTree:133 TheSettingsPaneListsEveryCommand... | HOSTED | ShortcutTests:177,35 (single `reset(_:)`) | yes: checks 4 rows |
| NoteTree:161 TheRecorderTakesTheCombinationThatIsPressed | HOSTED | ShortcutTests:14,29,35 (`KeyRecorder` private) | mild |
| Pratiche:168 ThePaneCarriesItsListAndPrimaryActions | HOSTED | none | no, existence only |
| Pratiche:192 TheFullDiskAccessBannerIsAbsent... | LOGIC | PraticheControllerTests:89,96,127 (ENOENT case) | yes: negative passes before any state |
| Pratiche:196 TheFilterRowCarriesTheSenderMenu... | HOSTED | none | no, existence only |
| Pratiche:211 TheTrayIsAbsentWithNoProposals | LOGIC | PraticaTrayTests:105,31,52 (`selectedTray` untested) | yes: negative passes before sync |
| Pratiche:218 TheTimelineAndInspectorToggleAreAddressable | HOSTED | none | yes: half repeats the setup wait |
| Pratiche:224 TheAddNoteAndAddCallEntryPoints... | HOSTED | none | no, existence only |
| Pratiche:232 TheWizardOpensWithItsTitleAndClientFields | HOSTED | PraticaWizardTests:15,25,60 | no, existence only |
| Pratiche:248 RigeneraShowsADiffPreviewAndAnnulla... | NEEDS-SCREEN | PraticaRegenerationTests:67,94, PraticheControllerTests:852-906 | yes: never proves the ready state with a diff |
| SectionToolbars:67 TheNoteSectionCarriesItsCommands | NEEDS-SCREEN | NavigationPaneFocusTests:12,23 | no, existence only |
| SectionToolbars:78 TheOggiSectionCarriesTheCalendarCommands | NEEDS-SCREEN | WeekScaleTests:88, CommandActionTests:98 | partly: negative, wall-clock dependent |
| SectionToolbars:108 TheAttivitaSectionCarriesTheTaskCommands | NEEDS-SCREEN | TaskViewTests:32, CommandActionTests:67 (toolbar `selected` path) | partly: initial-state checks |
| SectionToolbars:126 TheWorkspaceSectionCarriesTheBoardCommands | NEEDS-SCREEN | BoardInteractionTests:223,234,242,255 | yes: initial-state `!isEnabled` |

### 3.3 Group C

| Test | Cat. | Covered by UT today (what is left) | Weak |
|---|---|---|---|
| SidebarMove:83 MovingABoardRowViaTheMenu... R01 | NEEDS-SCREEN | VaultMoveTests:67,206 (menu entries, tree refresh, `items(for:in:)`) | no |
| SidebarMove:109 MovingAFolderRowViaTheMenu... R02 | NEEDS-SCREEN | VaultMoveTests:67 (menu) | no |
| SidebarMove:124 MovingANoteRowViaTheMenu... R03 | NEEDS-SCREEN | VaultSessionFileOperationsTests:83, StarredTests:120 (`VaultController.moveNote` facade) | no |
| SidebarMove:136 MovingANoteSidebarFolderRow... R04 | NEEDS-SCREEN | VaultMoveTests:67,419 (menu) | no |
| SidebarMove:148 MovingViaTheMenuToRadice... R05 | NEEDS-SCREEN | VaultMoveBatchTests:33 ("(radice)" entry, private `canMove`) | no |
| SidebarMove:168 AFoldersOwnMoveMenuDisables... R06 | NEEDS-SCREEN | WorkspaceMultiSelectionTests:127,133,139, VaultMoveBatchTests:44,55 (`parentFolder` rule, `.disabled`) | yes: final assertion true before the action |
| SidebarMove:216 MovingIntoAFolderThatAlreadyHoldsTheName... R07 | NEEDS-SCREEN | VaultMoveBatchTests:118, VaultMoveTests:91 (dialog, `WorkspaceMoveConflict`) | no |
| SidebarMove:239 CmdClickExtendsSelection... R10 | NEEDS-SCREEN | WorkspaceMultiSelectionTests:83,94 (real Cmd-click) | yes: never asserts the second row |
| SidebarMove:256 AMenuMoveWithTwoRowsSelected... R11 | NEEDS-SCREEN | VaultMoveTests:67 (private `effectiveItems`) | no |
| SidebarMove:277 UndoAfterAMenuMove... R12 | NEEDS-SCREEN | VaultMoveTests:206 (Cmd+Z routing to the window's UndoManager) | no |
| SidebarMove:308 DraggingASingleBoardRow... R15 | NEEDS-SCREEN | VaultItemDragTests:34+, VaultMoveTests:67 (`.draggable` to `.dropDestination`) | no |
| SidebarMove:336 DraggingAFolderRow... R15 | NEEDS-SCREEN | VaultMoveTests:67 | no |
| SidebarMove:352 DraggingAMultiRowSelection... R15 | NEEDS-SCREEN | VaultMoveTests:67 (drag carries the whole set) | no |
| SidebarMove:378 UndoAfterTypingInANoteThenMovingABoard... regression | HOSTED | VaultMoveTests:206 (`NoteTextView.dismantleNSView` untested) | yes: survival check only |
| SidebarMove:404 UndoOfADragMove... R15 | NEEDS-SCREEN | VaultMoveTests:206 | no |
| TaskCategories:119 TheCategoriesSectionShowsARegisteredAndAnImplicitRow... | NEEDS-SCREEN | CategoryIndexTests:90 (row rendering, click) | no |
| TaskCategories:151 CreaStaysDisabledWithAnEmptySlug... | LOGIC | CategoryEditorSlugTests:19 (inline `.disabled` predicate) | yes: asserts the problem element exists, not its wording |
| TaskCategories:179 LinkingANoteFromTheCategoryView... | NEEDS-SCREEN | CategoryLintTests:153,192,216,230 (facade, picker guard) | yes: negative right after the click, no wait |
| TaskTime:72 AScadenzaWithAnHour... | NEEDS-SCREEN | TaskComposerTests:199,223 (`TaskTimeRow.defaultTime`, panel flow) | no |
| TaskTime:131 WithoutAnHourTheComposerDoesNotAsk... | LOGIC | TaskComposerTests:216,252 (checkbox absent) | yes: negative passes if the click did nothing |
| TimeBlock:82 ATimeBlockIsInsertedAndCanBeDeleted | NEEDS-SCREEN | DayControllerTests:6,276,307 (menu entry, card rendering) | no |
| TimeBlock:110 ABlockIsDeletedFromTheTimelineToo | NEEDS-SCREEN | DayControllerTests:276,307 (`TimelineBlockBox` untested) | yes: `hover()` unneeded, 2 s negatives |
| TimelineHours:30 EachSectionDrawsItsOwnHours | LOGIC | DiaryControllerTests:324, HourWindowTests:47 (Oggi window private, labels) | yes: half the checks negative, no wait |
| TimelineHours:48 TheDefaultsAreTheHoursTheSectionsAlwaysHad | LOGIC | DiaryControllerTests:306 (Oggi 06 to 22 not pinned; other asserts circular) | no |
| TimelineHours:62 ABlockOutsideTheWindowIsStillDrawn | LOGIC | DiaryControllerTests:324,343, HourWindowTests:21 (parsing the fixture line) | yes: existence only, not position |
| UpdateMenu:68 PergamenumMenuHasACercaAggiornamentiItem... | NEEDS-SCREEN | SparkleUpdateControllerTests:40,57,68,81 (title, placement, `.disabled`) | yes: no adjacency asserted |

### 3.4 Cross-file patterns

- Every file repeats a ~15 to 30 line `setUp`/`tearDown` and the same launch-argument block; only
  `DragSupport.swift` is shared. Date helpers (`iso`, `isoToday`, `compactToday`) are copied across
  several files.
- None of the 89 needs a real calendar or mail fixture, except `PraticheUITests:248`, which needs a
  real sqlite Envelope Index built by `MailStoreFixture`/`EmailFixtureCorpus` in `Tests/`.
- Wall-clock dependence: the diary file name, `suggestedStart` and the Oggi-disabled state read
  `Date()`.
- Two assertions cannot fail as written: `DayViewUITests:200-202` (reversed date) and
  `ComposerUITests:112` (`task-composer-reminder` id). Several `Diary:68` checks target ids that
  exist nowhere.
- Gaps with no unit test at all: `WindowPlace` (`isDrift`, `apply`, `destination`), `DiaryGeometry`,
  `DayController.show`, `beginTaskCapture`, `CommandActions.run(.quickTask)`,
  `ThemeEngine.resetCustomization`, `NoteTextView.dismantleNSView`, `TimelineBlockBox`.

## 3b. Triage approved by Stefano

Recorded only. Nothing below has been executed: retirements and new unit tests belong to the
build phase, after `/spec` and `/plan`.

### DayViewUITests (approved 2026-09-21)

- **Keep** as a targeted test: `testVaiADataMovesTheDay` (`:99`). The only test that goes through
  toolbar, sheet, confirm and header.
- **Retire** (9): `:85` (subsumed by `:99` except `month-back`), `:119` (parsing in
  `DateEntryTests:40`), `:190` (`DateEntryTests:73`; negative half could not fail), `:221`
  (`TaskViewTests:173`), `:248` (`TaskViewTests:173`), `:256` (`TaskViewTests:203`), `:135`, `:154`
  (`DateEntryTests:87,100`), `:208`.
- **Add** two unit tests on existing seams, no production change: `DayController.show(_:)` and
  `beginTaskCapture` setting `taskDraft`.
- **Wiring lost, no in-process cover today:** month toggle persistence (`@AppStorage` private), the
  divider drag, the bell card and its flag default, the due-day dot drawing, the completed-filter
  toggle binding, the toolbar capture button.

### ComposerUITests (approved 2026-09-21)

- **Keep** as targeted tests (2): `testTypingAfterChoosingADateContinuesTheTextInsteadOfReplacingIt`
  (`:251`, focus after a popover closes, no in-process equivalent) and
  `testANewNoteIsNamedInTheEditorAndNotInAFloatingWindow` (`:57`, the only end-to-end new-note path).
- **Convert** (2): `:300` becomes a unit test that `CommandActions.run(.quickTask)` sets `taskDraft`
  (sheet presentation in `RootView` is lost); `:283` needs a production seam, the day-to-view mapping
  of the private `TasksView.followLastCapture` extracted into a pure function, then a unit test.
  That seam goes into the seams ADR.
- **Retire** (7): `:224` (path already exercised by `:251`), `:171` (`DateEntryTests:9`), `:194`
  (`TaskComposerTests:38`), `:140` (`TaskComposerTests:61,104`), `:117` (`DateEntryTests:9`), `:100`
  (existence only, its negative half cannot fail), `:86` (`NewNoteDraftTests:93`).
- **Wiring lost, no in-process cover today:** the reminder page producing the time (default 09:00),
  the Programma panel's `remind`/`repeat`/`choose` rows, the calendar click and popover dismissal
  in Scadenza (PG-072), the Annulla button, the "Fra 2 settimane" click.

### SidebarMoveUITests (approved 2026-09-21)

Bodies from `R07` (`:216`) onward were re-read; `R01` to `R06` were classified from the census, whose
line numbers for that stretch are not yet verified.

- **Keep** as targeted tests (3): `R01` `:83` (basic right-click, Sposta in, tree updated), `R07`
  `:216` (conflict dialog, the `.alert` to `NSAlert` bridge is unreachable in-process), `R12` `:277`
  (Cmd+Z to the window's `UndoManager`, also covers a two-row menu move).
- **Keep until replaced** (1): `:378`, the a853e8e crash regression. Convert to a hosted in-process
  `NoteTextView` test only once that test is shown to reproduce the crash.
- **Convert** (2): `R03` `:124` becomes a unit test of `VaultController.moveNote` (`canOperate`,
  `recordProblem`, rescan, untested today); `R06` `:168` needs a seam, `canMove(to:)` extracted to a
  pure function, then a unit test. That seam goes into the seams ADR.
- **Retire** (9): `R02` `:109`, `R04` `:136`, `R05` `:148`, `R10` `:239`, `R11` `:256` (absorbed by
  R12), and the four `R15` drags `:308`, `:336`, `:352`, `:404`. The drags were the most exposed to
  the machine: PG-180 measured 13 failures in 20 with the pointer moved by anything else, 30 in 30
  on an untouched machine.
- **Wiring lost, no in-process cover today:** `.draggable` to `.dropDestination` and the rule that a
  drag carries the whole lit set (the largest single loss, drag and drop is left with no cover at
  all, a dedicated seam would extract `beginDrag` and the drop closure, not evaluated), the
  "(radice)" entry, `NoteTreeRow`'s menu, the real Cmd-click producing a two-id set.

### WorkspaceOpenStateUITests (approved 2026-09-21)

Line numbers below are the ones read from the file on 2026-09-21 (`:157` to `:425`).

- **Keep** as targeted tests (2): `:157` `testThePaneOpensEmptyAndFillsInOnlyAfterAClick` (click on a
  root row opens a board, no dependence on the accessibility label) and `:204`
  `testSelectingANestedBoardLightsExactlyOneRowInTheTree_R02_R03` (a click on a nested row binds to
  `List(selection:)`, the shape of the `DisclosureGroup`/`.tag` defect in `CLAUDE.md`). `:204` was among
  the reds of 2026-09-20 and its verdict is to be watched: the cause of those reds (focus or label) is
  not confirmed.
- **Convert** (6): `:370`, `:383` (folder card double click) and `:405`, `:425` (breadcrumb ancestor)
  through the new `WorkspaceController.enter(folder:)`, replacing the three copies of "resolve the
  board; if `.unique` select it, else select the folder" (`BoardChrome.swift:55`,
  `BoardCardMenu.swift:209`, `WorkspaceView.swift:210`). The same seam serves
  `WorkspaceIntegrationUITests:153,166`. `:216` through a pure function for the row label
  (`WorkspaceRow.swift:195`). `:251` becomes a unit test, after checking whether
  `WorkspaceCreationTests:37,50` already asserts that no `.canvas` is written.
- **Retire** (7): `:171` (`WorkspaceOpenStateTests:45,208`), `:191` (`WorkspaceTreeTests:83,162,215,223`),
  `:231` (both assertions true before the click), `:282` (`WorkspaceOpenStateTests:80`,
  `WorkspaceTreeTests:97`), `:300` (`WorkspaceTreeTests:112`, `WorkspaceCreationTests:50`), `:318`
  (`WorkspaceTreeTests:57,73`), `:343` (`WorkspaceBrowserToolbarTests:42-60`, enablement only).
- **Wiring lost, no in-process cover today:** the accessibility labels `", aperta"`/`", selezionata"`
  as read from the tree, the folder card double click, the breadcrumb segment click, the «Nuova
  cartella» sheet and its verb, the board row's context menu entries, the view rebuild when returning
  to the pane.

### WorkspaceIntegrationUITests (approved 2026-09-21)

- **Keep** as a targeted test (1): `:153`
  `testSendingANoteFromAnAmbiguousFolderToTheWorkspaceSelectsTheFolderAndRecordsAProblem`. The only
  test of the path menu, `.onChange(of: vault.pendingWorkspacePlacement)`, folder selection and
  `recordProblem`. The file's own header records a real hazard: a flag already non-nil when the view
  mounts loses the hand-off, which no in-process test sees.
- **Convert** (2): `:166` becomes a unit test through `WorkspaceController.enter(folder:)` (the seam
  shared with `WorkspaceOpenStateUITests`) with the problem sentence extracted, using
  `WorkspaceBoardResolverTests:84`. `:75`, the nine-step test, becomes a `VaultSession` walk (write,
  `rescan`, reopen) over pieces already covered by `TaskMarkerTests`, `TaskMarkerWriteTests`,
  `WorkspaceReferenceTests` and `IndexCacheTests`.
- **Retire:** none without a replacement.
- **Wiring lost, no in-process cover today:** capturing a sub-task from the composer, assigning a
  board to a project task, the "Progetti" header progress, the tray's assigned-task count, and the
  duplicate wiring of `:166`.
- **Running tally of tests kept** (2026-09-21, after five files): Day 1, Composer 2, SidebarMove 3
  plus 1 pending replacement, OpenState 2, Integration 1, about 9 or 10. To be compared with the
  "2 or 3 per new feature" regime and possibly capped at the end of the triage.

### WorkspaceBoardUITests (approved 2026-09-21)

All seven are real pointer gestures on the canvas. On 2026-09-20 the 22 Workspace tests rerun alone on
an undisturbed Mac passed 22 of 22, which points at the environment rather than the app.

- **Keep** as a targeted test (1): `:64` `testACornerGripResizesTheCard`. The only test of the
  gesture chain click-to-select then drag on a grip half outside the card (`onTapGesture`,
  `DragGesture`), the exact hit-test regression the file exists for.
- **Convert** (2): `:161` (card inside a group) becomes a unit test over the existing seams
  `beginResize/updateResize/endResize` with flush and reload on `openedWorkspaceController`, no
  production change; today it never observes the selection, only that the card widened. `:100`
  needs the seam already in the plan: `accessibilitySummary(for:)`
  (`BoardContentLayer.swift:239`, private) extracted as a pure function, then a unit test.
- **Retire** (4): `:84` (`BoardInteractionTests:288,298,303,204`), `:111`
  (`WorkspaceControllerToolsTests:87,112,129,146`, `BoardInteractionTests:309,319,325`), `:132`
  (negative assertion, `BoardInteractionTests:332,342,352`), `:147`
  (`BoardInteractionTests:91,103`, `WorkspaceControllerToolsTests:10,36`).
- **Wiring lost, no in-process cover today:** the grip hit at low zoom with a real viewport
  (`zoom(by:in:)`), the arrow tool's `a` key and real drag, the group frame's real hit-testing, the
  accessibility label as read from the tree.

### WorkspaceFocusUITests and WikilinkNavigationUITests (approved 2026-09-21)

- **Keep** as a targeted test (1): Wikilink `:137` `testCommandClickOnAWikilinkNavigatesToTheLinkedNote`.
  The editor's central interaction, exercising the real `AXLink` click with the real modifier flags.
- **Convert** (4): Wikilink `:109` (bold target `**Destinazione**`) through a capturing variant of
  `EmbedEditorFixtures.editor` (it hard-wires `onFollowLink: { _ in }`) and an injectable Cmd-state
  closure in place of `NSEvent.modifierFlags` at `NoteTextView+Coordinator.swift:411`; Wikilink
  `:209` as a unit test of `menu(for:)` (`CompletingTextView+Pasteboard.swift:138-159`) and
  `openLinkFromMenu` (`:168`); Focus `:49` through the derivation of `RootView.swift:67-86`
  (`isFocusedPane`, `sidebarVisibility`) extracted as a pure function on `Navigation`; Focus `:74` as
  a unit test on `Navigation()`, no production change.
- **Retire** (2): Wikilink `:163` (vacuous by its own comment: synthetic clicks never reproduced the
  AppKit gesture) and `:180` (name promises the caret, body only checks "X" is in the text). Both are
  replaced by the plain-click-refused unit test that the injectable Cmd closure makes possible.
- **Seams added to the ADR:** the injectable Cmd-state closure with the capturing editor fixture, and
  the pure focus-derivation function on `Navigation`.
- **Wiring lost, no in-process cover today:** the real `NavigationSplitView` collapse in
  Concentrazione, and the `rightMouseDown(with:)` override (no seam, no `NSEvent` synthesis proven).
- **Tally of tests kept** (after 8 files, 68 of 121 tests triaged): Day 1, Composer 2, SidebarMove 3
  plus 1 pending, OpenState 2, Integration 1, Board 1, Wikilink 1, about 11 or 12.

### DiaryUITests (approved 2026-09-21)

Bodies re-read from `:56` to `:227` on 2026-09-21.

- **Keep** as a targeted test (1): `:77` `testABlockIsComposedAndWrittenToTheFile`, the only
  end-to-end of the section's core action (toolbar, sheet, Salva, timeline, file on disk).
- **Convert** (4): `:110` (rename) as a unit test over `edit/update/commitDraft` asserting the file,
  since `DiaryComposerTests:47` stops in memory; `:163` (two blocks at the same hour) as a unit test
  with two `add` calls asserting both lines on the file; `:177` and `:205` (drag to block out, drag to
  move) through a seam: the drag maths, currently private (`DiaryTimeline.range(of:)`,
  `minutes(at:)`, `DiaryEntryCard.snappedDelta`, `dragThreshold`), extracted as pure functions in
  `DiaryGeometry`, which has no test today. The seam goes into the seams ADR, and the hard-coded 120
  points (duplicating the private `hourHeight = 60`) disappears.
- **Retire** (5): `:56` (existence only, `DiaryToolbar` has no seam), `:68` (two negatives on ids
  that exist nowhere in `Sources/`, two positives that are existence checks), `:94`
  (`DiaryControllerTests:239`, `DiaryTests:121`), `:128` (`DiaryControllerTests:239`), `:141`
  (`DiaryControllerTests:79,123,142`; its second check reads a file that already held the text).
- **Wiring lost, no in-process cover today:** the link between the diary's `NSTextView` and
  `prose` (a hosted `NoteTextView` in a never-shown window could cover it, not evaluated), the
  toolbar items, the remove x on a block, the sheet's Elimina button, the real drag gestures.

### PraticheUITests (approved 2026-09-21)

Header note: lines 7-11 say the file must "build for testing and never run" by an agent. That is a
2026-09-09 dispatch instruction and is stale, `scripts/uitests.sh` runs it as part of the 121 tests.
It goes away with the file's retirement.

- **Keep** as a targeted test (1): `:218` `testTheTimelineAndInspectorToggleAreAddressable`. Through
  `selectFirstPratica()` it is the selection wiring of the pane: a click on a list row, the selection,
  the timeline.
- **Convert** (3), all on existing seams, no production change: `:248` (Rigenera) as a unit test that
  after `dismissRegeneration` the note file is byte-identical, the ADR-0036 §D21 guarantee that
  nothing is touched on Annulla, next to `PraticaRegenerationTests:67,94` and
  `PraticheControllerTests:852-906`; `:192` as a unit test of `FullDiskAccessProbe.state` with `ENOENT`
  giving `.granted`, untested today; `:211` as a unit test of `PraticheController.selectedTray`,
  untested today. `:248` currently needs a real sqlite Envelope Index from `MailStoreFixture`.
- **Retire** (4): `:168`, `:196`, `:224` (existence of identifiers only, no cover), `:232`
  (`PraticaWizardTests:15,25,60` for state and path).
- **Wiring lost, no in-process cover today:** that the pane's controls (new pratica, refresh, filter
  row, sender menu, attachments toggle, add note, add call) are present and reachable, the wizard
  opening and its fields, the Rigenera menu to sheet to Annulla path, the banner and the tray strip
  as drawn.

### SectionToolbarsUITests and HistoryNavigationUITests (approved 2026-09-21)

- **Keep** as a targeted test (1): History `:47` `testTheArrowsWalkThePanesInOrder`, which uses the real
  history observer, the toolbar arrows and replay suppression. Its comment says "three panes forward,
  three back, three forward"; the body does two panes, one back and one forward. The name promises
  more than the body asserts and should be reconciled when it is next touched.
- **Convert** (1): History `:65` as a unit test on `WindowPlace` (a struct of testable controllers):
  `DayController.moveSpan` sets `lastDayMoveWasDrift`, `WindowPlace.isDrift` reads it, five advances
  and one `goBack` leave the pane. It also adds the first coverage of `WindowPlace.apply`, which no
  file under `Tests/` mentions. No production change.
- **Retire** (5): History `:34` (`CommandActionTests:56`, `NavigationHistoryTests:25`; its two initial
  checks are true with no recorder attached) and the four `SectionToolbarsUITests`: `:67` Note
  (`NavigationPaneFocusTests:12,23`), `:78` Oggi (`WeekScaleTests:88`, `CommandActionTests:98`; the same
  toolbar is in `DayViewUITests:99`), `:108` Attività (`TaskViewTests:32`, `CommandActionTests:67`),
  `:126` Workspace (`BoardInteractionTests:223,234,242,255`).
- **Wiring lost, no in-process cover today:** that the toolbars of Note, Oggi, Attività and Workspace
  carry their items, the enabled state of the task buttons on a selected task (the `selected`
  predicate is private), the "Nuovo promemoria" entry in the Calendario menu. `ToolbarContent` has no
  seam.
- **Tally of tests kept** (93 of 121 tests triaged, 12 of the 22 test files): Day 1, Composer 2,
  SidebarMove 3 plus 1 pending replacement, OpenState 2, Integration 1, Board 1, Wikilink 1, Diary 1,
  Pratiche 1, History 1, about 14 or 15.

### TaskCategoriesUITests, TaskTimeUITests, TimeBlockUITests, TimelineHoursUITests (approved 2026-09-21)

- **Keep** as targeted tests (2), both for the recent categories feature (ADR-0047, PG-166):
  `TaskCategories:119` (row layout, a greedy `Color.clear` once let the row eat the sidebar and only
  `frame.height < 60` pins it, plus the click that opens the category view) and `:179` (PG-166 flow:
  picker from the category view, `pergamenum-category` key written, "Vai alla nota" offered). `:179`'s
  first check is a negative with no wait and should be fixed when the file is next touched.
- **Convert** (5): `TaskCategories:151` through a seam, the `.disabled(name.isEmpty || slugProblem
  != nil)` predicate of `CategoryEditor` (`:88`) extracted as a pure function, then a unit test;
  `TaskTime:72` as a unit test of `TaskTimeRow.defaultTime` (09:00, untested today) next to
  `TaskComposerTests:199,223`; `TimelineHours:48` as a unit test pinning `HourWindow.dayDefault`
  (06 to 22) and `.diaryDefault` (06 to 24), today unpinned or circular; `:62` as a unit test that
  loads a diary containing `- 21:00-22:00 Serata` and checks the window reaches 22; `:30` through a
  seam, `DayTimeline.hours` (private) made a pure function, the Diario half already in
  `DiaryControllerTests:324`.
- **Retire** (3): `TaskTime:131` (negative, passes if the click did nothing; `TaskComposerTests:216,252`),
  `TimeBlock:82` (`DayControllerTests:6,276,307`) and `:110` (`DayControllerTests:276,307`).
- **Wiring lost, no in-process cover today:** the «Inserisci Blocco Tempo» menu entry, the
  `blocks-card` and `remove-block` controls, the x on a timeline block (`TimelineBlockBox` has no
  test), the composer's hour popover and block checkbox flow (PG-072), the `Crea` button actually
  disabled, the hour labels as drawn.
- **Tally of tests kept** (103 of 121 triaged): about 16 or 17. The cap on survivors is still to be
  decided at the end of the triage.

### CompletionPanelUITests and EditorCompletionUITests (approved 2026-09-21)

- **Keep** (0): none as a targeted GUI test.
- **Convert** (4): `CompletionPanel:98` as a unit test of the heading provider (`Transclusion.excerpt`,
  title included: "Prove in laboratorio", "Campioni", "Durezza", "Strumenti"); `:116` as unit tests of
  the emoji catalogue search ("bers" finds "bersaglio") and of the insertion (Return writes the glyph
  and removes the typed `:bers`); `:146` as a unit test of the selection movement (15 down arrows
  reach the sixteenth entry, its assertion is already pure logic); `EditorCompletion:59` as a HOSTED
  test through `EmbedEditorTestSupport` inserting `## Titolo\n#area-training\n`, where the crash is
  the failure. Kept as a GUI test until that HOSTED replacement exists (a853e8e-style regression).
- **Retire** (2): `:167` (its own header says it stays green with the fix removed; `EditorHeightTests`
  is the in-process cover, to be checked in `/plan` that it covers the long styled note) and `:189`
  (weak: asserts the trigger text arrived and the app is alive, never the panel;
  `CompletionPanelPlacementTests`).
- **To verify in `/plan`:** that `EditorHeightTests` covers the long-note case and whether a
  heading-provider unit test already exists.
- **Wiring lost, no in-process cover today:** the panel drawn with its rows and footer ("scrivi per
  filtrare"), the emoji glyph as drawn, the list scrolling with the selection (only ever in a
  screenshot, never asserted), the crash path with a real panel on screen.
- **Tally of tests kept** (109 of 121 triaged): unchanged, about 16 or 17. `EditorCompletion:59` is a
  keep-until-replaced, like `SidebarMove:378`.

### NoteTreeAndShortcutsUITests (approved 2026-09-21)

- **Keep** (1): `:111` (a shortcut changed in settings is the one the menu answers to: Cmd+J opens
  the quick switcher, Cmd+O no longer does). The store-to-menu-bar wiring (`MenuCommands`) has no
  in-process cover. Its `Thread.sleep(1)` before the negative check should become a wait on absence
  when the file is next touched.
- **Convert** (2): `:93` as a unit test of the set of folders to expand for a revealed note
  (`NoteTree.ancestors(of:)` plus `reveal.folder`, `NoteListPane.swift:196` and `:567`), through a
  seam: the computation extracted as a pure function; `:161` through a seam, the event-to-outcome
  step of the recorder in `ShortcutSettings` (record / cancel with Esc / clear with Backspace)
  extracted as a pure function, then a unit test.
- **Retire** (2): `:57` (chevron clicked by a fixed 7 pt pixel offset; the structure is `NoteTree`'s)
  and `:133` (`ShortcutTests:124,134,177` cover default, override and reset; `:209` covers the
  catalogue the pane is generated from).
- **To verify in `/plan`:** that `NoteTree` has structure tests already and that the recorder can be
  extracted with no change of behaviour.
- **Wiring lost, no in-process cover today:** the chevron toggle, `@State expanded` receiving the
  reveal set, the settings pane rows as drawn, the real event monitor of the recorder.
- **Tally of tests kept** (114 of 121 triaged): about 17 or 18.

### DesignAndReadingUITests, NoteImageUITests, UpdateMenuUITests (approved 2026-09-21)

- **Keep** (0): none as a targeted GUI test.
- **Convert** (4): `Design:66` (a theme file in the vault's `.pergamenum/themes/` reaches the picker and,
  chosen, names it) as a unit test of vault-theme loading and selection; `Design:91` (the Design
  system pane: colour wells, «Ripristina» removes `personalizzato.json`) as a unit test on the token
  catalogue and on the reset in `ThemeCustomizationTests`; `Design:159` (a GFM table is a grid) as a
  HOSTED test that the attachment is a `TableGridView` carrying the `editor-table` identifier, on top
  of `TableRenderingTests`; `NoteImage:63` (a drawn embed and a `.missing` placeholder carry the
  labels "Pressa 4" and "assente.png") through a seam, the label computation of
  `CompletingTextView+Accessibility` extracted as a pure function, then a unit test.
- **Retire** (3): `Design:54` (negatives on three sidebar labels; passes on an empty sidebar),
  `Design:129` (negative on a removal already done by ADR-0029; the source-in-editor half is
  `NSTextView.value`) and `UpdateMenu:68` (`UpdaterConfigurationTests`; the click was never covered,
  it is verified by hand against a real appcast, plan Task 10).
- **To verify in `/plan`:** that vault-theme loading, selection and the reset are already covered in
  `DesignSystemTests`/`ThemeCustomizationTests`, and that the embed label is extractable with no
  change of behaviour.
- **Wiring lost, no in-process cover today:** the theme popup (`popUpButtons["Tema"]`), the Settings
  pane and its «Ripristina» button as drawn, the embed picture as Quick Look draws it, the
  «Cerca Aggiornamenti…» item in the real menu bar.
- **Tally of tests kept** (121 of 121 triaged): 17 kept as targeted GUI tests, plus 2
  keep-until-replaced (`SidebarMove:378`, `EditorCompletion:59`), so 19 on day one and 17 once those
  two have a HOSTED replacement. Counted per file: DayView 1, Composer 2, SidebarMove 3,
  WorkspaceOpenState 2, WorkspaceIntegration 1, WorkspaceBoard 1, Wikilink 1, Diary 1, Pratiche 1,
  History 1, TaskCategories 2, NoteTreeAndShortcuts 1. The earlier running tallies ("16 or 17",
  "17 or 18") were approximations and are superseded by this line.
- **Cap decided by Stefano, 2026-09-21:** 17 targeted GUI tests at steady state (19 on day one, the
  two keep-until-replaced going away once their HOSTED replacements exist). No further cut of the
  existing ones. Rule for the future: at most 2 or 3 GUI tests per new feature, and each new GUI test
  is justified in the feature's ADR.

## 4. Next steps

1. Spot-check done 2026-09-21, read from the files. Held: `task-composer-reminder`, `diary-preview`
   and `diary-layout` appear nowhere in `Sources/` or `Tests/` (only `task-composer-reminder-badge`
   exists); `DayViewUITests:200-202` builds `yyyyddMM` while the compact form is `yyyyMMdd`;
   `SidebarMove:168`'s last assertion (`Parent` exists) is true before the action;
   `PraticheUITests:192` is a bare negative with no state; `VaultMoveTests:67,206` and
   `DateEntryTests:73` exist with matching names; `WindowPlace` and `DiaryGeometry` appear in no file
   under `Tests/`. Not verified: `ComposerUITests:283`, whether the "Inbox" text also matches the
   sidebar's view title (needs the accessibility tree). Worth knowing before retiring the SidebarMove
   group: its R-07 comment documents a real SwiftUI `.alert` to `NSAlert` bridging limit that only a
   UI test found.
2. Triage per file done 2026-09-21: 121 of 121, every file approved by Stefano (section 3b), cap on
   survivors decided (17).
3. Runner check done 2026-09-21, read from `actions/runner-images` (`README.md` and
   `images/macos/xcode-27-arm64-Readme.md`, main branch): a macOS 27 hosted runner exists, label
   `xcode-27` (or `xcode-27-xlarge`), arm64, marked *public preview* (issue #14404). Image version
   20260912.0186.1, macOS 27.0 (26A5406e), Xcode 27.0 (27A266a, default), SDK macosx27.0. Local machine:
   macOS 27.0 (26A428), Xcode 27.0 (27A266a). `.github/workflows/ci.yml:46` already uses `xcode-27`.
   **Not verified:** that the runner gives an unlocked GUI session with the Accessibility and
   automation permissions `XCUIApplication` needs, so whether the UI suite can run there at all is
   open. It would need a trial run, which is a `/plan` item, not a decision for now.
4. Who launches the installed app (PG-182), read from the unified log with Stefano's permission,
   2026-09-21 (`/usr/bin/log show`; in zsh a bare `log` is a builtin, not the tool). One occurrence
   found in the last 24 h: the installed `it.stefer.pergamenum` (pid 89477) was spawned by launchd at
   2026-09-20 22:35:31.728 with `launching: launch job demand`, i.e. through a LaunchServices open
   request, in the middle of a UI run (drag events from `testmanagerd` still in flight), 20 ms before
   `xcodebuild` sent SIGTERM to the debug instance (pid 89436, ran 7042 ms). It stayed alive until
   2026-09-21 08:00:50. Ruled out from the log: `scripts/release.sh:320` (`tell application
   "Pergamenum" to quit`, not running then) and the Plaud agent (nothing in that window). **Not
   proven: the sender.** The focus loop of `scripts/uitests.sh:402` ran `osascript` System Events
   calls at 22:35:30.0 and 22:35:31.07, the last one 0.66 s before the spawn; System Events resolves
   an app by name but is not known to launch it, so it is a suspect by timing only. The default log
   does not carry the requester of a LaunchServices open. **Proposal for `/plan`:** when
   `scripts/uitests.sh` sees an installed copy appear, dump the surrounding 10 s of
   `launchd`/`launchservicesd` into the evidence bundle, so the next occurrence names its sender; and
   try a run with the focus loop off to test the timing suspicion.
5. `/spec` then `/plan` then `/build`, in separate sessions for plan and build. One ADR for the
   package of seams. `scripts/uitests.sh` `contaminated` verdict and the `CLAUDE.md` rule change
   are their own stages.
