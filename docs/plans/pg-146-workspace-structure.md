# PG-146 — Workspace structure: four splits, one grip, one tray view, and a verdict on every sub-item

- Issue: `TODO.md` `PG-146` (P3, chain "workspace"), GitHub #246. The brief is the ledger entry and
  its indented Findings line. There is no SPEC: the repo-root `SPEC.md` belongs to the PG-259
  day-boundary chain and is not this chain's input. There are no R-ids. Each task cites the PG-146
  sub-item it closes, by the finding id the entry uses.
- ADR: **none new**. ADR-0045 §D1–§D3 governs every split here unchanged. ADR-0075 §D3 is the reason
  for `structure-ViewBoardRenderer.swift-c3e`'s Close. See "ADR outcome".
- Governing prior ADRs, registered and not reopened:
  - ADR-0045: the obligation is the error threshold (§D1); a type splits into `Type+Aspect.swift`
    extensions of itself (§D2); `private` widens only where the split requires it, with one comment
    naming the file that reads it, and a member whose callers all move with it stays `private` (§D3);
  - ADR-0054 §D4/§D5, ADR-0060 and ADR-0066: the board's guarded save, its reconciliation, the
    `.conflicted` state and the leave paths. Task 1 moves that code verbatim and changes none of it;
  - ADR-0027 §D1/§D3, ADR-0028 §D1/§D8, ADR-0029 §D17 and ADR-0037's §D8 amendment: the card's text
    view, and the card's own hidden-kind switch ending in `default: nil`. Task 4 keeps that switch
    card-owned and in `CardTextView.swift`;
  - ADR-0020: crop grips reuse the resize grip's visual language. Task 5 makes that one view;
  - ADR-0023 and ADR-0070: no task touches a command catalogue, a context menu's catalogue or a
    delete-key route;
  - ADR-0075 §D3: Today's drop banner must never change height;
  - the design-token rule: no task adds a colour or a font; moved code keeps its token reads.
- Read at `bbf1bb1e`, this branch's HEAD (clean tree, 2026-09-30). `origin/main` is now `585458c1`;
  the two differ only in `Project.swift` (marketing version) and `TODO.md`, none of the files below.
  No remote branch touches any file below (every `origin/*` branch checked with
  `git diff --name-only origin/main...<branch>`). Lint findings come from `swiftlint 0.65.1` and the
  repo's `.swiftlint.yml`. The "after" lengths were measured on scratch copies with the moved range
  deleted, outside the repository. None of these numbers is recalled from the ledger (2026-09-12),
  which predates ADR-0054, 0060, 0066 and 0074.
- Branch: `refactor/pg-146-workspace-structure` (already cut).

## Verdict on every sub-item

The lint table on `bbf1bb1e`, for every file in scope. Nothing in scope is at an error; the one type
within reach of one is `WorkspaceController` (349 against 350).

| File | Findings |
|---|---|
| `WorkspaceController.swift` | `file_length` 767; `type_body_length` 349 |
| `WorkspaceView.swift` | `file_length` 503; `type_body_length` 313 |
| `FormattingTextView.swift` | `file_length` 597; `type_body_length` 280 |
| `CardTextView.swift` | `file_length` 520; `cyclomatic_complexity` 13 at `:364` (`applyStyling`) |
| `BoardTray.swift` | `function_parameter_count` 7 at `:97` |
| `WorkspaceBrowser.swift`, `BoardHandles.swift`, `BoardCropEditor.swift`, `ViewBoardRenderer.swift`, `TaskDropBanner.swift`, `TodayView.swift` | none |
| `DayController.swift` (c3e's other side, not edited) | `file_length` 406 |

| Sub-item | Measured on `bbf1bb1e` | Verdict |
|---|---|---|
| `structure-WorkspaceController.swift-52b` | 767 lines, class body 349, one line under the error. The ledger's 607/273 is stale. `Tool` (`:13-69`) and `// MARK: Saving` (`:667-766`) are self-contained. Saving's four `private` helpers have no caller outside the section; its only outside contacts are `scheduleSave()`, called from Editing (`:467`, `:499`), and `saveTask`, cancelled in `detach()` (`:248-249`). Editing (`:451-522`) writes `private var history`: moving it would widen the board's undo history. A new `WorkspaceTool.swift` would rename a type spelled `WorkspaceController.Tool` in `BoardChrome.swift`, `WorkspaceController+Tools.swift` and `Tests/WorkspaceControllerTests.swift`; declaring `Tool` inside `extension WorkspaceController` keeps the spelling. After: body about 237, file about 610. | **Do**, Task 1. `Tool` joins its tap classification in the existing `+Tools`; Saving gets `+Saving`; Editing stays. The `file_length` warning stays, per ADR-0045 §D1. |
| `structure-WorkspaceView.swift-f8e` | 503 lines, struct body 313. The ledger's 358 predates `+Toolbar`, which has since taken the toolbar. What is left is the Board section (`:279-501`). It reads three `@State private` properties (`viewportSize`, `modifiers`, `pinchOrigin`), and `mainContent` places `board`. Also found: `grid` draws with a literal `24` (`:443`), while `WorkspaceController.gridStep` (`WorkspaceController.swift:584-587`) documents itself as the one constant for the drawn grid and the snap grid, and `WorkspaceController+Duplicate.swift:40-41` says they are the same constant. After: 280 lines, body about 163. | **Do**, Task 2, with the grid reading `gridStep`. |
| `structure-WorkspaceBrowser.swift-ac5` | 346 lines, no finding. The two sheet views already live in `WorkspaceFolderSheets.swift` (`NewWorkspaceSheet`, `RenameWorkspaceSheet`). What remains in `body` (`:109-222`) is four presentation modifiers (`.sheet` twice, `.confirmationDialog`, `.alert`) with their closures, and they have to attach to this type's view. Moving them into an extension would widen `@State private var creating` (`:75`) and clear nothing. | **Close.** No finding, and the move widens state for nothing. |
| `structure-CardTextView.swift-05d` and `-d6d` | 520 lines; `applyStyling(to:)` is at cyclomatic complexity 13 (`:364`), and its function body is within the limit. The styling cut is `configure` (`:343-352`), `applyStyling` (`:354-436`), `releaseDecorations` (`:438-458`), `baseAttributes` (`:485-504`) and the `CardTextStyle.Alignment` extension (`:507-520`). **A source-reading fence:** `Tests/InlineSpanRevealFenceTests.swift:327-354` opens `Sources/Features/Workspace/CardTextView.swift`, finds the literal `let kind: HiddenMarker.Kind? = switch styled.span {` and counts the `case .` lines up to the next `}`. So the switch stays in that file as a card-owned static, and that is also what takes the complexity down. It is never `NoteTextView.Coordinator.hiddenKind(for:)`, because ADR-0029 §D17 needs the card's own `default: nil`. The move widens `hiddenMarkers`' setter and `isStyling`. After: about 392 lines. | **Do**, Task 4. |
| `structure-FormattingTextView.swift-fd1` | 597 lines, class body 280. The pointer block (`:164-392`) covers the fold-badge click, Cmd+click, the right-click link menu, the checkbox click and `lineIndex(atParagraphOffset:in:)`. It uses no `private` member declared outside it, nothing outside it uses its `private` members, and it holds no stored property. Wikilink completion (`:421-534`) holds `private var wikilinkDismissedLocation` and `private(set) var wikilinkCompletion`: moving it would widen both. After: 368 lines, body about 150, both warnings gone. | **Do**, Task 3. One file, `FormattingTextView+Clicks.swift` (the audit's own name), with nothing widened. The audit's three files are not needed. |
| `structure-BoardHandles.swift-5b2` | No finding. `CropHandleView` (`BoardCropEditor.swift:141-191`) repeats `ResizeHandleView`'s grip (`BoardHandles.swift:22-58`): the two sizes, the rounded square, the double frame, the content shape and the hover push/pop. It lacks the `onDisappear` pop that `ResizeHandleView` (`:47-56`) calls "not belt and braces". Crop mode ends on Return or Escape (`WorkspaceView.swift:371-377`), which removes the crop grips without an `onHover(false)`; that is the same shape as the resize case the comment describes. The positions differ (`targetSize / 2 + …` against `rect.minX + …`), and so do the gestures. | **Do**, Task 5. One grip view carries the look and the cursor; each caller keeps its gesture and its position. |
| `structure-BoardTray.swift-0f2` | `traySection` takes 7 parameters (`:97`); it has two call sites (`:134`, `:166`) and no state of its own. | **Do**, Task 6, as a private `TraySection` view with the memberwise initialiser. |
| `structure-ViewBoardRenderer.swift-c3e` | 251 lines, no finding. The duplication the audit read has since diverged. (1) Today's banner is now `TaskDropBanner` (47 lines), a fixed-height slot that `TaskDropBannerTests` hosts and measures, because a banner growing above Today's `HSplitView` mid-drop aborted the app (PG-259, ADR-0075 §D3). The board's banner grows on purpose (`.fixedSize(horizontal: false, vertical: true)`, `:172`), has no padding or background, undoes through `queries?.undo` rather than a controller, and uses other identifiers (`undo-board-drop`, against `undo-task-drop` and `task-drop-banner`). (2) Today's success path composes a partial success, moved but block refused, that is at once a refusal and undoable (`DayController+TaskDrop.swift:48-68`); the board has no such case. (3) The outcome types differ (`TaskDropOutcome`, `BoardDropOutcome`), and both live in `Sources/Vault`, compiled into `perg` and `pergamenum-mcp`. What is still identical is the three-field `Drop` struct and two branches of about ten lines. Their only shared substance is one `NoteViolations(name: [], frontmatter: [], tags: …, relatedMissingInSection: [], relatedMissingInFrontmatter: [])` construction, and that one is repeated at **seven** sites across six features, not two. | **Close.** A shared `DropBanner` would either impose ADR-0075 §D3's height constraint on a banner with no split view under it, or parameterise that constraint away in the one view a crash fix depends on. A shared `WriteDropOutcome` would cross into `Sources/Vault` for about twenty lines. The real duplication is the `NoteViolations` construction: a follow-up (Open for Stefano). |

## ADR outcome: no new ADR

**ADR-0045 governs Tasks 1 to 4 and 6 unchanged.** Each is a `Type+Aspect.swift` move or a same-file
extraction under §D2, and each widening follows §D3. This chain meets none of the three significance
tests on its own:

- it is easy to reverse;
- it is not surprising to a reader, since ADR-0045 already explains the shape;
- it involves no real trade-off: in every case the alternative is the ledger's own suggestion,
  rejected in the verdict table for a measured reason.

None of the override cases applies either:

- no security boundary moves;
- the one constraint that is invisible in the code, the fence test that reads `CardTextView.swift`
  as text, is recorded where a reader meets it: in the comment on the card's `hiddenKind(for:)` (Task 4);
- the two Closes are "not worth it" verdicts with measured reasons, recorded in `TODO.md` (Task 7),
  which is where the PG-147 chain recorded its own.

**Task 5 needs no ADR.** It makes ADR-0020's "the crop grips reuse the resize grip's visual language"
literal. The cursor pop it adds to the crop grip is the pop `ResizeHandleView` already documents; it
is a defect fix, not a decision.

**c3e's Close cites ADR-0075 §D3.** That ADR is the reason the two banners must stay apart.

## Standing rules for every task

1. **No red phase, and no new API that a test calls.** This is a structure chain. The evidence is
   the suite green before and after, the lint table and the counts. The new types (`BoardGripView`,
   `TraySection`) and the new static (`CardTextView.Coordinator.hiddenKind(for:)`) are called by
   production code only. Task 5 is the one behaviour change, and why it has no automated test is
   stated there.
2. **Moved code is byte-identical.** The only edits that are not moves are the ones each task lists.
   Review every task with `git diff --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change`:
   anything that is neither dimmed nor on the task's list is a finding.
3. **Every widening carries its comment** (ADR-0045 §D3): one comment per member, or one covering a
   contiguous run, naming the file that reads it. Each task gives the exact wording.
4. **`tuist generate --no-open` after a file is added** (Tasks 1 to 4), before building.
   `Project.swift` is not edited: the app target globs `Sources/**` (`Project.swift:259`). No
   `Sources/Features` file is in `sharedSources`, so `perg` and `pergamenum-mcp` are unaffected and
   their builds are not required.
5. **Lint before and after** each touched file with `swiftlint lint --quiet`, filtered to the files,
   and record the table in the commit body. No new finding anywhere. No `swiftlint:disable`. No
   change to `.swiftlint.yml`.
6. **Counts never drop, and here they stay equal**, because no task adds or removes a test. Run
   `rg -c '@Test' Tests | awk -F: '{s+=$2} END {print s}'` and the same count for
   `#expect\(|#require\(`. The baseline on `bbf1bb1e` is **4736** and **12727** grep occurrences.
7. **No test is edited except in comments**, and only the comments each task names. If
   `InlineSpanRevealFenceTests` goes red, the switch has moved or its first line has changed: put it
   back, never edit the test. If any other test goes red, stop and report; in a pure move that
   means something did not move verbatim.
8. **The scope fence.** Every source edit stays in `Sources/Features/Workspace/`, and test edits are
   comment-only. That keeps `scripts/uitests.sh --affected` at the four Workspace classes
   (`scripts/uitests.sh:153-154`). An edit anywhere else in `Sources` (Editor, App, Core, Views,
   Today) is out of this chain; each one found is carried to the follow-up.
9. **Tests to run:** the full `PergamenumTests` after every task (TEST-CMD below), not only the
   suites named. `scripts/uitests.sh` does not run per task.
10. **One commit per task**, Conventional Commits. Each commit is a HITL gate (CLAUDE.md), with the
    diff shown.

## Before Task 1: the baseline (orchestrator)

1. `git fetch origin`. `origin/main` (`585458c1`) is past `bbf1bb1e` by a marketing-version bump and
   a `TODO.md` sync. Merge it into the branch; never rebase, never force. The pre-push merge-integrity
   hook (ADR-0061/0062) checks the merge. Then run `tuist generate --no-open` for the new
   `Project.swift`.
2. `tuist install` once for the worktree, then `tuist generate --no-open`.
3. Record: TEST-CMD green; the two counts; the lint table above, re-run and pasted.
4. `scripts/uitests.sh --status`. The ledger asks for `WorkspaceBoardUITests` and
   `WorkspaceOpenStateUITests` "before and after". "Before" is the verdict the script holds for
   `main`'s tree: record it, and do not start a 25-minute run to produce one. "After" is `--affected`
   at merge (Task 7), which selects both.

---

### Task 1 — WorkspaceController: `Tool` beside its tap behaviour, saving in its own file (coder) (closes `structure-WorkspaceController.swift-52b`)

**Files:**

- `Sources/Features/Workspace/WorkspaceController.swift`;
- `WorkspaceController+Tools.swift`;
- `WorkspaceController+Saving.swift` (new);
- `WorkspaceController+Gestures.swift`, one comment line;
- `WorkspaceView+Creation.swift`, one comment;
- `Tests/WorkspaceAutosaveRaceTests.swift`, comment only.

**The moves:**

- **`Tool`.** Move `:13-69` (its doc comment included) into `WorkspaceController+Tools.swift`, as
  `extension WorkspaceController { enum Tool … }`, above the existing
  `extension WorkspaceController.Tool`. The spelling `WorkspaceController.Tool` does not change.
  `var tool: Tool = .select` (`:123`) stays where it is.
- **The `+Tools` header.** Rewrite it: the file holds the tool catalogue and its tap classification
  (ADR-0045 §D2). Drop "only because that file's type body is already over the length SwiftLint
  errors on", which is not true today.
- **Saving.** Move `// MARK: Saving` (`:667-766`) verbatim into `WorkspaceController+Saving.swift`:
  `scheduleSave()`, `flushPendingSave()`, `save()`, `attemptSave(store:allowingRetry:)`,
  `reconcileAfterRefusal(store:)` and `enterConflicted(reason:)`. Give the file a header naming
  ADR-0054 §D4/§D5 as what the code implements, and ADR-0045 as why it is a file of its own.
  - `save`, `attemptSave`, `reconcileAfterRefusal` and `enterConflicted` stay `private`: all their
    callers move with them (§D3.3).
  - `scheduleSave()` becomes internal, with the comment: "Not `private`: `mutate` and `apply(_:)` in
    `WorkspaceController.swift` (`// MARK: Editing`) schedule through it."
  - `saveTask` (`:181`) becomes an internal `var`, with the comment: "Not `private`: `scheduleSave()`
    and `flushPendingSave()` in `WorkspaceController+Saving.swift` own it; `detach()` here cancels
    it." The shape is `pendingRefit`/`refitTask`'s (`:184-192`).
  - `autosaveDelay` (`:182-183`) leaves the main file. It becomes
    `private static let autosaveDelay = Duration.seconds(1)` in `+Saving.swift`, with its
    "Autosave delay of SPEC §6.1" comment. `scheduleSave` captures it as
    `Task { [autosaveDelay = Self.autosaveDelay] in … }`, so the closure body stays as it is. If
    strict concurrency objects to reading a main-actor static there, declare it
    `nonisolated private static let`; `Duration` is `Sendable`.
- **Editing stays** (`:451-522`): it writes `private var history`.

**Two stale comments:**

- The doc comment of `panOrigin` is split across two files. Its tail (`/// the drag translation.`) sits
  at `WorkspaceController.swift:589`; its head sits at `WorkspaceController+Gestures.swift:72`, above
  a blank line. Rejoin it on `panOrigin` as "Pan at the moment the background drag began, held here
  for the same reason as the drag translation.", and delete the dangling line in `+Gestures`.
- `WorkspaceView+Creation.swift:18`: "(WorkspaceController.swift)" becomes
  "(`WorkspaceController+Tools.swift`)". `Tests/WorkspaceAutosaveRaceTests.swift:176`: "in
  `WorkspaceController.swift`" becomes "in `WorkspaceController+Saving.swift`". Comment only.

Run `tuist generate --no-open`.

**Done when:**

- `type_body_length` no longer appears for `WorkspaceController.swift` (measured at about 237). Its
  `file_length` warning (about 610) is recorded in the commit body as accepted under ADR-0045 §D1;
- neither extension file has a finding;
- `rg -n "enum Tool\b" Sources` lists `WorkspaceController+Tools.swift` only;
- the suite is green. The suites that exercise this most closely are `WorkspaceControllerTests`,
  `WorkspaceControllerToolsTests`, `WorkspaceAutosaveRaceTests`, `WorkspaceLifecycleTests`,
  `WorkspaceAfterAwaitTests` and `QuitCoordinatorTests`.

**Commit:** `refactor(workspace): move Tool beside its tap behaviour and saving into its own file`.

### Task 2 — WorkspaceView: the board in its own file (coder) (closes `structure-WorkspaceView.swift-f8e`)

**Files:**

- `Sources/Features/Workspace/WorkspaceView.swift`;
- `WorkspaceView+Board.swift` (new);
- comments only in `WorkspaceView+Toolbar.swift`, `BoardFormatBar.swift` and
  `Tests/HostedViewPrototypeTests.swift`.

**The move:** `// MARK: Board` (`:279-501`) goes verbatim into `extension WorkspaceView` in the new
file:

- `board`, `boardBackground(in:)`, `cropKeyboardShortcuts`, `floatingControls` and `pinchGesture`;
- `propose(import:at:)`, `applyBoardSettings()`, `grid` and `backgroundGesture(in:)`;
- `canvasPoint(from:)`, which is already internal because `+Drawing` reads it.

Every moved `private` member stays `private` except `board`: its reader, `mainContent`, stays behind.

**Widenings, with comments:**

- `board` becomes internal: "Not `private`: `mainContent` in `WorkspaceView.swift` places it."
- `@State viewportSize`, `modifiers` and `pinchOrigin` (`:29-36`) become internal, under one comment
  over the run, the `NoteListPane` shape: "Not `private`, on this property and the two below: the
  board that writes and reads them is in `WorkspaceView+Board.swift`, and `private` is file scope.
  `viewportSize` is also read here, by `openPendingCanvas()`."

**The one non-move edit:** `grid` draws with `WorkspaceController.gridStep` instead of the literal
`24` (`:443`). The value is the same. It makes `gridStep`'s own doc comment and
`WorkspaceController+Duplicate.swift:40-41` true. `WorkspaceController+Import.swift:53`'s `24` is
an import stagger, not the grid; leave it.

**Header and citations:**

- The `WorkspaceView.swift` header (`:3-11`) now says six files. It names `WorkspaceView+Board`,
  says this file keeps the view's state and its body, and keeps the "internal rather than `private`"
  sentence.
- Citations of the moved code, rewritten to name a member instead of a line:
  - `BoardFormatBar.swift:198-199` becomes the `board` ZStack in `WorkspaceView+Board.swift`;
  - `WorkspaceView+Toolbar.swift:60` becomes "`mainContent`'s `&&` (`WorkspaceView.swift`)";
  - `Tests/HostedViewPrototypeTests.swift:20` becomes "the way `WorkspaceView+Board.swift`'s `board`
    places it".

Run `tuist generate --no-open`.

**Done when:**

- `WorkspaceView.swift` has no finding (measured at 280 lines and a body of about 163), and neither
  has `+Board.swift`;
- `rg -n "24 \* workspace\.zoom" Sources` is empty;
- the suite is green. The closest suites are `WorkspaceFitOnOpenHostedTests`,
  `HostedViewPrototypeTests`, `BoardFormatBarTests`, `BoardInteractionTests` and `BoardDragSnapTests`.

**Commit:** `refactor(workspace): move the board into WorkspaceView+Board`. The body names the
`gridStep` edit as the one non-move.

### Task 3 — FormattingTextView: clicks in their own file (coder) (closes `structure-FormattingTextView.swift-fd1`)

**Files:** `Sources/Features/Workspace/FormattingTextView.swift` and `FormattingTextView+Clicks.swift`
(new).

- Move `:164-392` verbatim into `extension FormattingTextView`, both `// MARK:` headings included:
  - the `mouseDown`, `rightMouseDown` and `menu(for:)` overrides;
  - `followLinkIfPresent(at:)`, `openLinkFromMenu(_:)` and `PendingLinkClick`;
  - `claimsFoldBadge(at:)`, `entry(atHeadingOffset:in:)`, `claimsCheckbox(at:)` and
    `checkboxStateOffset(in:)`;
  - `lineIndex(atParagraphOffset:in:)`.
- Overriding an Objective-C `NSView` method in an extension is allowed, and
  `FormattingTextView+CursorRects.swift` already overrides four that way.
- **Nothing widens.** Every `private` in the range stays `private`, and the range holds no stored
  property.
- `FormattingTextView.lineIndex(atParagraphOffset:in:)` keeps its spelling; it is read at
  `Tests/CRLFLineWalkTests.swift:224-228`.
- The new file's header says three things: it is an ADR-0045 size split that widens nothing; the
  wikilink completion stays in `FormattingTextView.swift` because it holds two access-limited stored
  properties; and `CompletingTextView+Pasteboard.swift` is the note editor's sibling, never shared
  (the main file's header rule).
- Run `tuist generate --no-open`.
- **Not edited:** `Sources/Features/Editor/CompletingTextView.swift:112` and
  `MarkdownAttributedText.swift:25` cite `FormattingTextView.swift` for `claimsCheckbox` and
  `followLinkIfPresent`. Both are outside the scope fence and go to the follow-up.

**Done when:**

- neither file has a finding (measured at 368 lines and a body of about 150);
- `--color-moved` shows the range as a pure move;
- the suite is green. The closest suites are `FoldBadgeClickTests`, `CardFoldTests`,
  `CRLFLineWalkTests`, `WikilinkClickNavigationTests`, `CardFormattingTests` and
  `CardWikilinkCompletionTests`.

**Commit:** `refactor(workspace): move FormattingTextView's click handling into +Clicks`.

### Task 4 — CardTextView: the styling pass in its own file, the card's switch as its own function (coder) (closes `structure-CardTextView.swift-05d`, `structure-CardTextView.swift-d6d`)

**Files:**

- `Sources/Features/Workspace/CardTextView.swift`;
- `CardTextView+Styling.swift` (new);
- `CardTextView+Teardown.swift`, one header paragraph;
- `CardTextView+Fold.swift`, one comment.

**The move.** The new file holds `extension CardTextView.Coordinator` with:

- `configure(_:editable:)` (`:343-352`);
- `applyStyling(to:)` (`:354-436`);
- `releaseDecorations()` (`:438-458`);
- `baseAttributes` (`:485-504`), still `private`, because both its readers move.

It also holds `private extension CardTextStyle.Alignment` (`:507-520`).

**The switch stays.** The kind switch (`:374-388`) becomes a static on `Coordinator`, still in
`CardTextView.swift`:
`static func hiddenKind(for styled: MarkdownStyler.StyledRange) -> HiddenMarker.Kind?`.

- The body is today's switch with its **first line byte-identical**:
  `let kind: HiddenMarker.Kind? = switch styled.span {`. The seven `case .` lines and the ADR-0037
  comment inside stay unchanged, then `default: nil`, `}` and `return kind`.
- `applyStyling` calls `Self.hiddenKind(for: styled)`.
- The shape is fixed by `InlineSpanRevealFenceTests.theSwitchMapsExactlySevenNonNilKinds`, which reads
  that line out of that file. The test is not edited.
- The comment on it: "Not `private`: `applyStyling(to:)` in `CardTextView+Styling.swift` calls it.
  Kept in this file because `InlineSpanRevealFenceTests` reads this switch out of it (ADR-0037 §D8
  amendment), and kept the card's own because its `default: nil` is ADR-0029 §D17's seam."

**Widenings, with comments:**

- `hiddenMarkers` (`:214`) goes from `private(set) var` to `var`. Keep the doc comment and add:
  "Setter not `private`: its two writers, `applyStyling(to:)` and `releaseDecorations()`, are in
  `CardTextView+Styling.swift`, and nothing else writes it."
- `isStyling` (`:231`) goes from `private var` to `var`: "Not `private`: `applyStyling(to:)` in
  `CardTextView+Styling.swift` raises it, and `textDidChange` here reads it."
- `isUpdatingView` stays `private`: its readers stay.

**Comments that follow the move:**

- `CardTextView+Teardown.swift:10-13`: `releaseDecorations()` now lives in `CardTextView+Styling.swift`
  beside `applyStyling`, the table's other writer. The setter was widened for that move (ADR-0045 §D3)
  and the comment on `hiddenMarkers` names both writers.
- `CardTextView+Fold.swift:28`: "(`CardTextView.swift`, the two lines above …)" becomes
  "(`CardTextView+Styling.swift`, …)".

**Budget.** The budget is thin, about 392 lines. If `CardTextView.swift` still counts over 400 once
the comments are written, `matchFocus(_:editable:)` (`:460-483`) moves into the new file too. It
reads nothing `private`.

**Not done:** the nine-line marker append walk has the same shape as the one in
`NoteTextView+Coordinator.applyStyling`, and it stays duplicated. That is the editor's file, ADR-0074
has just restructured it, and touching it selects the whole GUI suite.

Run `tuist generate --no-open`.

**Done when:**

- `CardTextView.swift` has no `file_length` and no `cyclomatic_complexity` finding, and
  `CardTextView+Styling.swift` has none;
- `rg -n "hiddenMarkers = " Sources/Features/Workspace` lists `CardTextView+Styling.swift` only;
- `InlineSpanRevealFenceTests` is green and unedited;
- the suite is green. The closest suites are `CardTextViewTests`, `CardConcealmentTests`,
  `CardRoundTripTests`, `CardFoldTests`, `ViewQueryOutOfScopeTests` and `BoardFormatBarTests`.

**Commit:** `refactor(workspace): move the card's styling pass into CardTextView+Styling`.

### Task 5 — One grip for resize and crop (coder) (closes `structure-BoardHandles.swift-5b2`)

**Files:** `Sources/Features/Workspace/BoardHandles.swift` and `BoardCropEditor.swift`.

- **The new view.** A new internal `struct BoardGripView: View` goes in `BoardHandles.swift`, beside
  `ResizeHandleView`. Its inputs are `handle: BoardGeometry.Handle` and `zoom: CGFloat`. It holds
  `@Environment(\.theme) private var theme`, `@State private var isHovering` and the
  `visualSize`/`targetSize` pair. Its body is `ResizeHandleView`'s drawing, from `RoundedRectangle`
  down to `.onDisappear` (`:31-56`), moved with its comments:
  - the `.surfaceCard` fill and the `.canvasSelection` stroke;
  - both frames and the content shape;
  - `onHover` push/pop, and the `onDisappear` pop.
- **`ResizeHandleView.body`** becomes
  `BoardGripView(handle: handle, zoom: workspace.zoom).highPriorityGesture(resizeGesture).position(…)`,
  and keeps its two comments (priority; gesture before `.position`). It keeps `targetSize` for its own
  position, and drops `theme`, `isHovering` and `visualSize`.
- **`CropHandleView.body`** becomes the same shape with `gripGesture` and its own position. It drops
  `theme`, `visualSize` and `targetSize`.
- **The behaviour change.** A crop grip now pops its cursor when it disappears. Nothing else about a
  pixel, a gesture or a token read changes.
- **No automated test.** `NSCursor`'s stack and SwiftUI's hover tracking cannot be reached from an
  in-process test, and XCUITest cannot read the cursor. Hand check H1 is the evidence.

**Done when:**

- neither file has a finding;
- `rg -n "RoundedRectangle\(cornerRadius: visualSize" Sources` has one hit, in `BoardGripView`;
- the suite is green. The closest suites are `BoardResizeInsideGroupTests`, `CanvasCropTests` and
  `BoardInteractionTests`;
- H1 is done.

**Commit:** the type comes from H1's "before" half, run on Task 4's build:

- if the stuck cursor reproduces: `fix(workspace): pop the crop grip's cursor when crop mode ends
  under the pointer`;
- if it does not: `refactor(workspace): draw the resize and crop grips with one view`, and the body
  says the pop is kept for parity with `ResizeHandleView`.

### Task 6 — The tray's section as a view (coder) (closes `structure-BoardTray.swift-0f2`)

**File:** `Sources/Features/Workspace/BoardTray.swift` only.

- **The struct.** `traySection(…)` (`:87-125`, its doc comment included) becomes
  `private struct TraySection<Rows: View>: View` in the same file, below `BoardTray`. It holds:
  - `@Environment(\.theme) private var theme`;
  - six `let`s, in today's parameter order;
  - `@ViewBuilder let rows: Rows`.
- **No explicit `init`.** The memberwise one takes `@ViewBuilder rows: () -> Rows`, and a hand-written
  seven-parameter `init` would bring the same warning back.
- **The body** is today's function body byte for byte, with `rows()` becoming `rows`.
- **The call sites** (`:134`, `:166`) change `traySection(` to `TraySection(` and nothing else: the
  arguments, the trailing closure, the `.task(id:)` after them and every accessibility identifier
  stay byte-identical.
- **ADR-0045's rejected alternative does not apply.** It turned steps of a large view that held
  `@State` into new view structs, and the extraction would have moved that state's identity.
  `TraySection` holds no state, and each section's refresh trigger stays at its call site.

**Done when:**

- `BoardTray.swift` has no finding;
- the suite is green. The closest suites are `BoardTrayRefreshTests`, `WorkspaceIntegrationWalkTests`
  and `IndexGenerationFollowUpTests`;
- H2 is done.

**Commit:** `refactor(workspace): make the tray's section a view`.

### Task 7 — Close-out (orchestrator, with the coder for the comment rewrite) (closes `PG-146`; records `-ac5` and `-c3e` as closed)

- **Line citations the splits made wrong**, inside the scope fence, comment-only. Rewrite each to name
  a member, not a line:
  - `BoardFormatBar.swift:128`;
  - `CardCommand.swift:82`;
  - `WorkspaceController+Duplicate.swift:6` and `:41` (after Task 2, `:41` names
    `WorkspaceController.gridStep`);
  - `Tests/CardCommandTests.swift:169`;
  - `Tests/CardTextStyleCommandTests.swift:11` (`setColor(_:forNodeIDs:)` lives in
    `WorkspaceController+Nodes.swift`).

  One commit: `docs(workspace): cite members, not line numbers, where the splits moved them`.
- **Stale-reference greps.** Each must be empty, or name only what is listed:
  - `rg -n "(WorkspaceController|WorkspaceView|CardTextView|FormattingTextView)\.swift:[0-9]" Sources/Features/Workspace Tests`
    lists only two lines:
    - `Tests/NoteEditorTeardownTests.swift:22`, if it still points at `let undoManager`; rewrite it if
      not;
    - `Tests/WorkspaceEnterFolderTests.swift:262`, a historical "moved verbatim" note;
  - `rg -n "func traySection|private\(set\) var hiddenMarkers|24 \* workspace\.zoom|held here for the same reason as$" Sources`;
  - `rg -n "enum Tool\b" Sources`, which lists `+Tools` only.
- **`TODO.md`:** `PG-146` becomes `[x]`, with each sub-item's verdict (six done, two closed, each
  with its reason) and the PR number. Add the follow-up's ledger entry if Stefano agrees (below).
- **Final verification:**
  - TEST-CMD green;
  - both counts equal to the baseline;
  - the lint table before and after, in the PR body;
  - `scripts/check-adr-references.py` after `git fetch`. No ADR changes, and it costs nothing.
- **At merge:** `scripts/uitests.sh --status`, then `--affected`. It selects `WorkspaceBoardUITests`,
  `WorkspaceIntegrationUITests`, `WorkspaceOpenStateUITests` and `SidebarMoveUITests`, the two the
  ledger names among them. The result is advisory (CLAUDE.md merge gate).
- **After merge:** close GitHub #246. There is no ADR status to flip.

**Commit:** `docs: close PG-146`.

## Observable-contract staleness

No HTTP status, output format, schema, response shape or accessibility identifier changes. Most
contracts below move files without changing their spelling. **Run the full `PergamenumTests` after
each task**, not only the suites named: a move can break a suite that never names the moved symbol.

| Contract | Task | Production call sites | Test call sites |
|---|---|---|---|
| `WorkspaceController.Tool` declaration moves to `+Tools`; spelling, cases and members unchanged | 1 | `WorkspaceController.swift:123` (`tool`), `BoardChrome.swift`, `WorkspaceView+Creation.swift`, `WorkspaceController+Tools.swift` | `WorkspaceControllerTests.swift` (12 lines), `WorkspaceControllerToolsTests.swift`, `HostedViewPrototypeTests.swift:97-105` (through `workspace.tool`) |
| `scheduleSave()` and `saveTask`: `private` becomes internal; the save behaviour is unchanged | 1 | `WorkspaceController.swift:248-249`, `:467`, `:499`; `WorkspaceController+Saving.swift` | none (they were `private`); the behaviour is covered by `WorkspaceAutosaveRaceTests`, `WorkspaceLifecycleTests` and `QuitCoordinatorTests` |
| `WorkspaceView.board` and three `@State`: `private` becomes internal | 2 | `WorkspaceView.swift` (`mainContent`, `openPendingCanvas`), `WorkspaceView+Board.swift` | none |
| The board grid's step reads `WorkspaceController.gridStep` (24, unchanged) | 2 | `WorkspaceView+Board.swift` (new reader); `WorkspaceController+Gestures.swift:41`, `+Duplicate.swift:43-44` | `BoardDragSnapTests` (7), `BoardInteractionTests` (2), `CanvasDuplicateTests` (2), `DragSnapEquivalencePinTests` (1); none asserts the drawn grid (hand check H2) |
| `FormattingTextView.lineIndex(atParagraphOffset:in:)` and `followLinkIfPresent(at:)` move to `+Clicks`; spelling unchanged | 3 | `FormattingTextView+Clicks.swift` | `CRLFLineWalkTests.swift:224-228`; `WikilinkClickNavigationTests.swift:26` (a comment) |
| `CardTextView.Coordinator.hiddenMarkers`: the setter goes from `private(set)` to internal; the getter is unchanged | 4 | `CardTextView+Styling.swift` (the two writers) | readers only: `CardRoundTripTests`, `CardConcealmentTests`, `ViewQueryOutOfScopeTests`, `InlineSpanRevealFenceTests` |
| `CardTextView.Coordinator.hiddenKind(for:)` (new internal static); the switch text is unchanged | 4 | `CardTextView+Styling.swift` | `InlineSpanRevealFenceTests.swift:327-354` reads the source line (**unedited**) |
| The crop grip's cursor is popped on disappear (**behaviour**) | 5 | `BoardCropEditor.swift` (`CropHandleView`), via `BoardGripView` | none possible in-process (hand check H1) |
| `BoardTray` sections: view structure only; identifiers `board-assigned-tasks`, `board-referenced-notes` and `-header` unchanged | 6 | `BoardTray.swift` | `WorkspaceIntegrationWalkTests.swift`, `BoardTrayRefreshTests.swift`, `IndexGenerationFollowUpTests.swift`; `UITests/WorkspaceIntegrationUITests.swift` |

## Risks and HITL gates

**Risks**

- **A move that changes behaviour under a green suite.** Mitigations: rule 2's `--color-moved` review;
  every non-move edit listed per task; and the full suite after each task.
- **Eight access levels widen:**
  - Task 1: two members;
  - Task 2: four members;
  - Task 4: one setter and one flag, plus one new internal static.

  Each carries its ADR-0045 §D3 comment. The one with teeth is `hiddenMarkers`: its `private(set)`
  used to make the compiler enforce "`applyStyling` and `releaseDecorations` are the only writers",
  and after Task 4 a convention enforces it. Task 4's grep checks it once. A reviewer who wants that
  guarantee back is choosing to keep the styling pass in `CardTextView.swift`, which leaves 05d open.
- **`Tool`'s isolation.** A nested type does not inherit the enclosing class's `@MainActor`, whether it
  is declared in the body or in an extension. `Tool` is `Sendable` and has no isolated member, so the
  move changes nothing. The Swift 6 build confirms it.
- **The static `autosaveDelay`.** Task 1 gives the fallback (`nonisolated private static let`) if
  strict concurrency objects.
- **`CardTextView.swift`'s thin line budget** (about 392). Task 4's contingency is `matchFocus`.
- **The fence test reads source text.** Renaming the switch's first line, reformatting it or moving it
  out of `CardTextView.swift` turns it red. Task 4 fixes the line, and rule 7 forbids editing the
  test.
- **The crop cursor fix has no automated test.** H1, run before and after, is the evidence, and it
  decides the commit type.
- **The GUI suite at merge.** It runs the four Workspace classes, not all of them, because rule 8
  keeps every source edit inside `Sources/Features/Workspace/`. It is advisory.
- **Merge conflicts with parallel chains.** They are expected only in `TODO.md`: merge `origin/main`
  in, never force. No remote branch touched these files at read time.

**Dependencies.** Nothing external: no third-party API, consent flow, cloud console, environment
variable or port. No new SPM dependency. Tuist 4, the Xcode 27 toolchain and `swiftlint 0.65.1` are
already required.

**HITL gates. None of them is the implementing agent's to pass:**

- **G0: approve this plan.** That covers the six Do and two Close verdicts, the no-ADR outcome, Task
  4's widening of `hiddenMarkers`' setter, and Task 5's behaviour change.
- **The baseline merge of `origin/main`.** It is a merge commit.
- **Each task's commit**, with its diff.
- **Hand checks, on a Debug build of this worktree.** Pick the build by its `WorkspacePath`, not by
  the newest modification time, launch it with `open -n`, and use a throwaway vault through
  `-recentVaults '("/path")'`.
  - **H1 (Task 5; its "before" half on Task 4's build):**
    - put an image card into crop mode and rest the pointer on a crop grip until the resize cursor
      shows;
    - press Return, then move the pointer over the board: the cursor must be the arrow. Repeat, ending
      crop mode with Escape;
    - then select a card, hover a resize grip and check the cursor. Drag to resize, with and without
      Shift (aspect kept).
  - **H2 (Tasks 2 and 6):**
    - with the grid on and snapping on, drag a card at 50%, 100% and 200% zoom: it lands on the drawn
      grid lines;
    - pinch to zoom, Option+drag to pan, drag a marquee;
    - the tray's two sections show their header, count badge, empty sentence and rows as before, and
      a task in «TASK ASSEGNATI» toggles.
  - **H3 (Tasks 3 and 4), in a text card being edited:**
    - a click on a folded heading's badge unfolds it;
    - a click on a task's checkbox toggles it;
    - Cmd+click on a wikilink navigates;
    - a right-click on a link offers «Apri collegamento» first;
    - the card's colour and alignment still apply, and markup hides and reveals as before.
- **At merge:** `scripts/uitests.sh --status`, then `--affected`.
- **Push, the pull request, the merge to `main`,** and the closing of #246.
- **Nothing here authorises:**
  - editing `InlineSpanRevealFenceTests` or any assertion;
  - a `swiftlint:disable`, or a threshold change;
  - an edit in `Sources` outside `Sources/Features/Workspace/`;
  - an edit to `.claude/protected-interfaces`.

  If a task cannot meet its bar without one of these, stop and report.

## Open for Stefano

- **Follow-up on `NoteViolations`.** Recommended now, as its own PR right after this one (the "P4s get
  fixed now" rule). `NoteViolations` would default its five remaining fields to `[]`, the way
  `taskMarkers` and `categories` already are. Each of the seven single-axis construction sites would
  then write only the axis it sets:
  - `ViewBoardRenderer.swift:141`;
  - `DayController+TaskDrop.swift:34`;
  - `ContenitoreCommand.swift:189`;
  - `NoteRowMenu.swift:109`;
  - `WorkspaceFolderSheets.swift:318`;
  - `ConformanceText.swift:132`;
  - `VaultController+Conformance.swift:16`.

  That is c3e's real duplication. The same PR would carry the stale comments this chain leaves
  outside its fence:
  - `CompletingTextView.swift:112`;
  - `MarkdownAttributedText.swift:25`;
  - `VaultController+Notes.swift:189`;
  - a misplaced doc comment at `NoteTextView+Coordinator.swift:396-406`, which sits above
    `hiddenKind(for:)` but describes `hiddenMarker(_:at:paragraphStart:)` (`:473`).

  It touches `Sources/Core` and the editor, so it needs the `perg` and `pergamenum-mcp` builds, and
  `--affected` selects the whole GUI suite (about 25 minutes). Keeping it separate is what holds this
  chain's GUI run at four classes.
- **The two drop banners stay different on purpose** (c3e). If you want the board's banner to look
  like Today's (padding, background, fixed height), that is a UI change with its own mockup under the
  design-system rule, not part of this refactor. Say so if you want it filed.

---

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

TEST-CMD MODE: brownfield

This is `.claude/test-cmd` verbatim, and it deliberately stays as it is. It runs through the `Stop`
hook at the end of every turn, and CLAUDE.md records why `-only-testing:PergamenumTests` is
load-bearing. It covers every suite this plan relies on, all of them unit or in-process hosted-view
tests. The rest runs at the gates above and is never wired into the hook:

```bash
scripts/uitests.sh --status && scripts/uitests.sh --affected   # at merge, advisory
```
