# ADR-0053: The seams that let the unit suite replace the UI suite as the merge gate

- Status: **Accepted**, 2026-09-21, by Stefano ("accetto", after reading the Proposed draft and
  the review fixes). Written by the implementer; acceptance is the HITL gate of
  `docs/plans/ui-suite-replacement.md` §7, and SPEC R-09 required it before the first
  production refactor, which is Task 5's PR 1.
- Date: 2026-09-21. Written on the worktree `Pergamenum.worktrees/chore__pg169-fase1-fase2`,
  branch `chore/pg169-fase1-fase2`, at `0b0947a`; the only changes on the tree are
  `Tests/HostedViewPrototypeTests.swift`, `Tests/HostedViewSupport.swift`, §8 of the plan and
  this file. Every file:line, signature and count below was read out of that tree today, not
  carried over from the plan; where it differs from the plan, §D2 says so.
- **Numbering note:** `0052` is the highest file under `docs/adr/`, and
  `git log --all --oneline -- 'docs/adr/0053*'` returns nothing, so no `0053` exists in any
  commit reachable from any ref. Checked, not assumed.
- Source: `SPEC.md` (Approved 2026-09-21) R-08, R-09, R-10, R-15;
  `docs/plans/ui-suite-replacement.md` §4 (the seam inventory) and Tasks 3 and 4;
  `docs/plans/ui-suite-replacement-census.md` (triage approved file by file, 2026-09-21).
- **Applies ADR-0001 §D1 and ADR-0007's shared-sources rule to two of the seams (§D4); depends
  on, and amends none of, ADR-0044 §D6 and ADR-0051 §D8 (§D6).** Neither is superseded. The
  `CLAUDE.md` rule ADR-0044 defers to is amended in stage 3 (plan Task 7), not here.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key, no
  `IndexCache.schemaVersion` bump (stays 4), no protected-interface signature: none of the
  sites in §D2 is one. This ADR deletes no test. The 104 GUI deletions belong to Tasks 5 and 6,
  each behind its own gate (plan §7).
- **Adds no exception to CLAUDE.md principle 2.** Nothing here gains a network path.

---

## Context

### Stage 1 has shipped

Stage 1 (plan Tasks 1 and 2: the `contaminated` verdict, the four disturbance signals, the
single rerun of the failed tests, exit code 2 and `--self-test`) is in `main`: commit `9bf3651`,
`feat(scripts): record a contaminated verdict for disturbed UI runs`, PR #364.
`bash scripts/uitests.sh --self-test` runs 63 offline checks and passes on this tree
(run today). This ADR does not redo any of it and depends on it: §D1's proof reads «green, or
contaminated then green on the rerun», and only stage 1 makes «contaminated» a verdict a run can
report.

### Why production code changes at all

The SPEC replaces the UI suite as the merge gate with the unit suite plus in-process tests. Of
the 121 GUI tests, 17 stay as targeted tests, 42 are converted (a unit or hosted test written,
then the GUI test deleted) and 62 are retired outright: 104 leave the GUI suite. A conversion
can reach what the GUI test observed only where the decision sits in a place a test can call.
Where it sits inside a view's `body`, a private member, or a closure over a global
(`NSEvent.modifierFlags`), the replacement cannot reach it without a change to the production
file. That change is a seam.

Three things make it worth an ADR rather than twelve commit messages. It is hard to reverse:
once the GUI test is deleted, a reverted seam is cover lost with nothing left to notice it. It is
surprising without context: a reader who meets an injectable closure where `NSEvent.modifierFlags`
used to be, or three call sites of a resolver switch collapsed into one method, will not see that
this was done for testability. And each seam had real alternatives (§Alternatives considered).

### What the hosted-view prototype decided (R-08)

SPEC R-08 asks for a prototype that hosts one SwiftUI view and one Workspace view in a
never-shown window with events sent directly, its outcome recorded before any dependent test is
converted. It was built on this tree (`Tests/HostedViewPrototypeTests.swift`, four tests, 0.92 s
together, over `Tests/HostedViewSupport.swift`) and measured on macOS 27.0 / Xcode 27.0. The full
record, with the unit suite's wall time before and after, is plan §8; the outcome is:

| View kind | Hosts and lays out | Drawn, read offscreen | Key equivalent | Mouse (uncommitted probe) |
|---|---|---|---|---|
| SwiftUI: `RenameNoteSheet` | yes | yes | yes (Esc fires `.cancelAction`; Return refused while unchanged) | not reached |
| Workspace chrome: `BoardToolbar`, live `WorkspaceController` | yes | not read | yes (bare `l`, `t` set `workspace.tool`) | not tried separately |
| Workspace board: `BoardContentLayer`, zoom and pan, live controller | yes | yes, and redrawn when zoom or pan change | none bound | not reached (click, zoom-corrected click, drag) |
| Workspace board with a text card | not built; stays GUI (decided 2026-09-21, below) | | | |

**What is in the tree and what is not.** The four tests pin the positive results: a sheet and a
board host and draw, a key equivalent reaches a `.keyboardShortcut` button, a bare letter moves the
live controller, and the board redraws when zoom and pan change. The figures and negative results
the tests do not assert (126 clicks over the sheet's frame and no button fired, the click, the
zoom-corrected click and the four-step drag on the board, empty `gestureRecognizers` and
`trackingAreas`, the 8 then 6 distinct sampled colours) were read by an uncommitted probe that is
not in the tree and was not kept. They cannot be replayed from the repository, and a test asserting
that something does not work would go red on the day it starts to work; a reader who needs one of
them re-measures it. The zoom and pan wrapper is a replica: `HostedBoard`, in the test file, copies
the two modifiers of `WorkspaceView.swift:357-366` by hand and `WorkspaceView` itself was not
hosted, so the redraw test pins that `BoardContentLayer` redraws for the controller's zoom and pan,
not that `WorkspaceView` applies them the same way. It opens with a control, two snapshots at
unchanged state that must be equal, so the difference it then asserts is the zoom and pan and not
the snapshot's own noise.

**Partly proven.** The Workspace half hosts, draws and takes key equivalents; it does not take
the pointer. A mouse event handed to the hosting view reaches no SwiftUI tap, double tap, drag or
`Button`: the hosting view holds no gesture recognizer and no tracking area, the board's hosting
view has no subviews, and the SwiftUI accessibility tree in-process is one childless group. The
one remaining route, `NSWindow.sendEvent`, is what makes a window key and visible; R-15 forbids
it and it was not tried. A board holding a text card was not built: `StickyTextCard` reads
`@Environment(CommandActions.self)`, whose init takes a concrete `EventKitStore`
(`CommandActions.swift:28,48`) that reads EventKit's authorization status and observes
`.EKEventStoreChanged` on init (`CalendarService.swift:59`, `:95-98`), and R-15 says no hosted
test reads calendar state. The unit suite already builds `EventKitStore()` in ordinary tests
(`RowCommandTests.swift:25`, `CommandActionTests.swift:16`, `CalendarTests.swift:275`), and Stefano
decided on 2026-09-21 that this does not loosen R-15: it stays strict, no hosted test constructs an
`EventKitStore`, and a board with a text card stays a GUI test (§Open for Stefano at acceptance,
item 3). The prototype sent no event to an AppKit view inside a SwiftUI one, and no file in
`Tests/` does today.

---

## Decision

### §D1 - A seam changes no behaviour, and the proof is `--affected` on the seam commit

A **seam** is a change to a production file made only so that a test can reach a decision which
today sits inside a view, a closure or a private member. After it, for every input the old code
could receive, the same result and the same effects happen in the same order. Where an input
exists for which the old and the new shape differ, it is named in §D2, and it must be one the
code cannot receive; a change that alters a reachable input is not a seam and needs its own ADR.

The proof is not the replacement test, which is written by the seam's own author and so proves
only that the new function does what its author thinks. It is `scripts/uitests.sh --affected` run
on the commit that collapses the call sites into the seam, **before** the GUI tests it serves are
deleted (R-10). The result is one of two:

- **green**, or
- **contaminated, then green on the single rerun** (stage 1's verdict: reds that coincided with a
  disturbance signal, rerun once).

A red is a defect in the seam until it is diagnosed from the run's `.xcresult` bundle
(`xcrun xcresulttool get test-results summary --path <bundle>`, CLAUDE.md working agreements),
never rerun until it turns green.

Each seam lands in two steps, so that a red exists (plan Task 5, «what "red first" means in
Swift»): first the **declaration**, with the replacement test, the new signature and a body that
simply calls the private implementation still in place, so the test fails on its assertion and
not on a build error; then the **collapse** of the call sites into it, which is the step that can
change behaviour and the one `--affected` proves neutral.

**No test-only door.** No `#if DEBUG` hatch, no setter that only a test uses, no widening whose
only reader is a test: the seam is the production path, so a test that exercises it exercises what
ships. This is ADR-0052 §D9's rule («the seam is the production door») applied to every seam
here.

`--affected` maps `Sources/Features/Editor/**` (which holds `NoteTreeRow.swift`, #7, and
`NoteListPane.swift`, #11), `Sources/Vault/NoteTree.swift` (#11), `Sources/App/**`,
`Sources/Features/Settings/**`, `Sources/DesignSystem/**` and `Sources/Index/**` to the whole
suite, so seams in those paths cost a full proof run. `NoteTree.swift` is not among the
`Sources/Vault` files `classes_for_path` names, so it falls to that function's default arm, which
is the whole suite for every path it does not name. Plan D-4 orders the PRs so the partial-proof
ones come first. A PR that removes
the last test of a class the runner names by hand updates `classes_for_path` in the same commit
(plan D-3).

### §D2 - The seams, each read off this tree

Thirteen sites, not twelve. The plan's §4 inventory lists twelve; the thirteenth, #13, is named
by the census (`NoteImage:63`), by plan §2 row 8 and by Task 5's PR 5, and left out of §4's table.
R-09 says this ADR lists every seam of the census, so it is here and marked. Line numbers agree
with the plan's to within the doc-comment line or two where the plan's range started early; none
moved.

Cost column: **P** = partial `--affected` proof, **F** = full (§D1). **F (via PR 6)** marks a seam
whose own file maps to a partial run (#9 under `Sources/Features/Tasks/`, #10 under
`Sources/Features/Today/`) but which ships in PR 6 with #6, whose home,
`Sources/Index/IndexSnapshot.swift`, maps to the whole suite: the proof run is per PR, so it is
full for all three.

| # | Seam | Verified site (2026-09-21) | PR | Proof | Serves |
|---|---|---|---|---|---|
| 1 | Enter a folder from the controller | `BoardChrome.swift:55`, `BoardCardMenu.swift:209`, `WorkspaceView.swift:210` | 1 | P | OpenState `:370`, `:383`, `:405`, `:425`; Integration `:166` |
| 2 | Workspace row label | `WorkspaceRow.swift:195-203`, used at `:180` | 1 | P | OpenState `:216` |
| 3 | Board card accessibility summary | `BoardContentLayer.swift:239-254`, used at `:78` | 1 | P | Board `:100` |
| 4 | Cmd state at the editor coordinator | `NoteTextView+Coordinator.swift:410-413` | 5 | F | Wikilink `:109`; `:163`, `:180` retire on it |
| 5 | Focus derivation on navigation | `RootView.swift:67-70`, `:76-87` | 5 | F | Focus `:49` |
| 6 | Task view a capture lands in | `TasksView.swift:66-75` | 6 | F | Composer `:283` |
| 7 | Whether a row can move to a destination | `WorkspaceRow+Move.swift:141-143`, `NoteTreeRow.swift:204-206` | 4 | F | SidebarMove `:168` |
| 8 | Diary drag geometry | `DiaryTimeline.swift:15,18,139-141,147,197`, `DiaryEntryCard.swift:7,27,168` | 2 | P | Diary `:177`, `:205` |
| 9 | Category editor disable predicate | `CategoryEditor.swift:88`, beside `:295` | 6 | F (via PR 6) | TaskCategories `:151` |
| 10 | The day timeline's hours | `DayTimeline.swift:21-26` | 6 | F (via PR 6) | TimelineHours `:30` |
| 11 | Note-tree reveal expansion set | `NoteListPane.swift:196`, `:565-568` | 7 | F | NoteTree `:93` |
| 12 | Shortcut recorder event-to-outcome | `ShortcutSettings.swift:160-185`, `:193-200` | 7 | F | NoteTree `:161` |
| 13 | Drawn embed's label | `CompletingTextView+Accessibility.swift:117`, `:129` | 5 | F | NoteImage `:63` |

**#1. `WorkspaceController.enter(folder:)`.** Three copies of `switch
WorkspaceBoardResolver.board(inFolder:among:)` become one method,
`@discardableResult func enter(folder: String) -> WorkspaceBoardResolution`: resolve against
`store?.allBoards() ?? []`, `.unique(path)` selects `.board(path: path.value)`, anything else
selects `folder.isEmpty ? nil : .folder(folder)`, and the resolution is returned. The board list
is still read in the gesture, never in `body`. The three copies are not identical; §D3 sets out
how the seam accounts for each. The sentence `placePendingNote` records
(`WorkspaceView.swift:215-220`, two arms: ambiguous, none) becomes a pure function beside the
resolver, moved verbatim: the census asks for it so `Integration:166` can be a unit test, and the
plan's §4 row did not name it.

**#2. Row label.** `private var accessibilityLabel` becomes a pure `(kind, name, boardCount,
isSelected) -> String`; the property calls it. The `.accessibilityLabel(...)` attachment at
`:180` stays, and stays unreachable in-process (R-08: the accessibility tree is empty there); only
the string is tested.

**#3. Board card summary.** Pure `(CanvasNode, isFolder: Bool) -> String`. **Drift from the plan,
which wrote `(CanvasNode) -> String`:** the `.file` arm reads the disk through
`workspace.subfolder(for: node)`, so the function is not pure over the node alone. The call site
passes `workspace.subfolder(for: node) != nil`, evaluated in the same arm at the same moment.

**#4. Cmd state.** The guard in `textView(_:clickedOnLink:at:)`, `guard
NSEvent.modifierFlags.contains(.command)`, reads an injectable `() -> NSEvent.ModifierFlags`
defaulting to `{ NSEvent.modifierFlags }`. It is called **at the moment the delegate method runs**,
not captured at init: the comment above the method says the check is live for exactly that reason.
The test half is a capturing variant of `Tests/EmbedEditorTestSupport.swift:58`, which hard-wires
`onFollowLink: { _ in }`. **Not in the plan:** `CardTextView.swift:313` holds an identical guard
for the Workspace card's text view. It serves no test in this chain and is left as it is.

**#5. Focus derivation.** `isFocusedPane` (`(navigation.isWorkspaceFocused && pane == .workspace)
|| (navigation.isNotesFocused && pane == .notes)`) reads only `navigation`, since
`RootView.swift:39` defines `pane` as `navigation.pane`. It moves onto `Navigation`
(`Sources/App/Navigation.swift:11`) and `sidebarVisibility` keeps its `Binding` and reads it.

**#6. Capture landing.** Pure `(day: CalendarDate?, today: CalendarDate) ->
IndexSnapshot.TaskView`: `nil` gives `.inbox`, a day `<= today` gives `.today`, else `.upcoming`.
`followLastCapture` calls it. §D4 constrains where it may live.

**#7. `canMove`.** Two copies unify into one; §D3.

**#8. Diary geometry.** The drag maths moves into the existing `DiaryGeometry`
(`DiaryEntryCard.swift:7`), which appears in no file under `Tests/` today: `range(of:)`, the
threshold decision at `DiaryTimeline.swift:139-141` (`abs(translation.height) > dragThreshold`
chooses the dragged span or the 60-minute default) and `snappedDelta`, taking scalars rather than a
`DragGesture.Value` so a test needs no gesture. Beyond the plan: `DiaryTimeline.minutes(at:)`
(`:197-200`) is character for character `DiaryGeometry.minute(atY:)` (`:27`), the same rounding
and the same clamp to `DiaryGrid.dayMinutes - DiaryGrid.step`, and `minute(atY:)` reads only
`firstHour` and `hourHeight`, the two values the timeline already builds a `DiaryGeometry` from
for its cards (`:33-36`). The seam deletes the private copy and calls the geometry's, built the
same way; `hourHeight = 60` (`:15`) then feeds one computation.

**#9. Disable predicate.** `name.trimmingCharacters(in: .whitespaces).isEmpty || slugProblem !=
nil` becomes a pure function beside `static func slugProblem(slug:isCreating:)`. The trim is
`.whitespaces`, not `.whitespacesAndNewlines`, and the function keeps it; the same trim at `:121`
gates a different thing (showing the problem text) and is left alone.

**#10. Day timeline hours.** `hours` is not a function of `window` alone: it also reads
`timedEvents`, `minutes(from:)` and `duration(of:)`, all private to the view and all over
`CalendarEvent` (`Sources/Calendar/CalendarEvent.swift:9`, not a shared source). The pure function
takes the already-converted start and end minutes and lives app-side. The Diario half is covered
already (`DiaryControllerTests:324`).

**#11. Reveal set.** The two sites give different shapes: revealing a folder unions its ancestors
**and the folder itself** (`:196`), revealing a note unions its ancestors only (`:567`). One
pure function over the already-tested `NoteTree.ancestors(of:)` (`NoteTreeTests:87`) has to say
which, so it takes `(path, isFolder)`. The `showsFolders` and `selectedRows` writes stay in the
view. The test `:93` reaches the note case. §D4 constrains where it may live.

**#12. Recorder outcome.** `handle(_:)` reads only `modifierFlags`, `keyCode` and
`charactersIgnoringModifiers`. The pure function is `(keyCode, flags,
charactersIgnoringModifiers) -> .cancel | .clear | .record(KeyBinding) | .ignore`, and `handle`
applies it. **The order of the rules is the behaviour and is preserved:** Esc with no modifier
(keyCode 53) cancels, Backspace with no modifier (51) clears, then `key(for:)`, then an invalid
binding is ignored, else record. Each outcome keeps its effects in order: `stop()` first, then
`onRecord`.

**#13. Embed label.** `let label = embed.alt ?? embed.target` (`:129`), with `embed` from
`Attachment.embed(inLine:)` (`:117`), becomes a pure function of the embed; the accessibility
element keeps calling it. The census wants the two labels of `NoteImage:63` (a drawn embed,
«Pressa 4», and a `.missing` placeholder, «assente.png») tested through it.

### §D3 - #1 and #7 are unifications, not extractions, and why that is safe

An extraction moves code without changing how many copies exist. #1 and #7 replace several copies
with one, which is the only place a seam could change behaviour by picking the wrong copy. Both
are safe for the reasons below, and both are exactly what §D1's proof is for.

**#1, three copies to one.** They are not identical, and the seam does not pretend they are.

- `BoardTopBar.open(ancestor:)` (`BoardChrome.swift:50-61`) guards `folder.isEmpty` **first** and
  answers `select(nil)` without asking the resolver: the root breadcrumb means «nothing selected»,
  and the resolver, asked about `""`, would answer for the vault root's own board (that is what
  `placePendingNote` wants of it). The guard is a different rule, so it **stays at the call site**
  and is not folded into `enter(folder:)`. Behaviour unchanged.
- `BoardCardMenu.enter(_:)` (`:208-215`) has the same switch with no guard. For every non-empty
  folder the shape after is identical. For `""` the old code, on `.ambiguous` or `.notFound`,
  selected `.folder("")`, a spelling ADR-0025 §D3 says the app never produces; the shape after
  selects `nil`, the spelling §D3 names. That is the one input on which old and new differ. It is
  a folder card's own path; whether a card can carry the empty path is **not proven here**, so the
  PR that lands #1 adds a test on `""` and names the result in its description (§D1: an input
  named, and either unreachable or reported).
- `placePendingNote` (`WorkspaceView.swift:205-232`) is the only copy that reports. Its else-arm
  already reads `folder.isEmpty ? nil : .folder(folder)`, which is the shape `enter(folder:)`
  takes for everyone. It calls `enter`, then records the problem from the returned resolution,
  select before report, as today.

**#7, two copies to one.** `WorkspaceRow+Move.swift:141` and `NoteTreeRow.swift:204` are the same
expression, `destination != parentFolder && WorkspaceBrowser.canDrop(items, onFolder:
destination)`, over different items (`effectiveItems`, the row's multi-selection, versus
`[reference]`) and different spellings of `parentFolder` (from `reference.path`, from `node.id`,
both `deletingLastPathComponent`). The one function takes `items`, `destination` and
`parentFolder`; each call site passes its own. It sits beside `canDrop`
(`WorkspaceBrowser+Tree.swift:260`, `nonisolated static`). Nothing about either site's arguments
changes, so nothing about either answer can. The drop-target highlight at `:88` and `:126` calls
`canDrop` directly and is not touched.

### §D4 - Placement: what is in `sharedSources` stays Foundation-only

`perg` and `pergamenum-mcp` compile the same files as the app, named in `sharedSources`
(`Project.swift`), with no second module: a file there that imports SwiftUI or AppKit breaks both
tool builds (ADR-0001 §D1, which CLAUDE.md records as having caught three inverted dependencies
the first time it ran). Two seams touch such a file.

- **#6** wants `IndexSnapshot.TaskView`'s home, `Sources/Index/IndexSnapshot.swift`, which is in
  `sharedSources` (`Project.swift:93`). The mapping is date logic over `CalendarDate`
  (`Sources/Core/Conventions/Frontmatter.swift:52`), so it can stay Foundation-only, and it does:
  no new import, no view type in its signature.
- **#11**, **drift from the plan, which said no other seam lands in a shared path**: if the
  reveal function sits beside `NoteTree.ancestors(of:)` it lands in `Sources/Vault/NoteTree.swift`,
  which is in `sharedSources` (`Project.swift:121`). This ADR places it there anyway: it is
  string logic over the type it belongs to and the existing test is already `NoteTreeTests:87`.
  Foundation-only, additive, no signature already there changes. The consequence is on the PR: PR
  7 builds both connectors (`xcodebuild -scheme perg` and `-scheme pergamenum-mcp`,
  CLAUDE.md Commands) as well as the app, because the CI check would otherwise be the first
  to say so.

No other seam lands in a shared path: #1-#3 and #7-#10 and #13 are under `Sources/Features/**`,
#4, #11's call site and #12 likewise, #5 under `Sources/App/**`.

### §D5 - What the R-08 outcome leaves as GUI tests

- **The cap of 17 does not rise on this evidence.** None of Task 5's conversions is designed
  through a SwiftUI pointer gesture: PR 1 goes through `enter(folder:)`, the two pure functions and
  the existing `beginResize`/`updateResize`/`endResize` seams on `openedWorkspaceController`; PRs 2,
  3, 4, 6 and 7 through pure functions and controllers. The fallback the plan's own §7 names for
  the Workspace half (`docs/plans/ui-suite-replacement.md:527-531`: `Board:100`, `Board:161` and
  the OpenState label test staying GUI if that half failed) does not trigger.
- **What stays GUI is what already did:** `Board:64`, the grip resize, which is the pointer
  gesture chain; `OpenState:157` and `:204`, a click on a `List(selection:)` row. The wiring
  lost with the retirements stays lost where the census lists it, among it the accessibility
  label as read from the tree: seam #2 tests the string and nothing in-process can test that it is
  attached.
- **PR 5 hosts AppKit views, which the prototype did not measure**: `#tag` insertion
  (`EditorCompletion:59`), `TableGridView` (`Design:159`), the embed label, the wikilink
  plain-click, `menu(for:)` and the `NoteTextView` teardown that must reproduce the a853e8e crash
  before `SidebarMove:378` is deleted. Their precedent is `Tests/EditorHeightTests.swift:49-55`;
  each is proven by its own PR (red on revert for the two crash regressions), and one that cannot
  be hosted stays GUI under the SPEC's edge case, the cap conversation with Stefano.
- **A board holding a text card stays a GUI test.** Stefano decided on 2026-09-21 that R-15 stays
  strict and no hosted test constructs an `EventKitStore` (§Open for Stefano at acceptance,
  item 3), and `StickyTextCard` needs `CommandActions`, which needs one. No planned conversion
  needs such a board, so the cap of 17 does not rise on its account.

### §D6 - Relationship to ADR-0044 §D6 and ADR-0051 §D8

**ADR-0044 §D6** decides that the UI suite does not go on CI, names the trigger for revisiting it
(`PG-076` and `PG-108` closed and two consecutive green full runs) and describes the current rule
as «run by hand, before every merge to `main`, per CLAUDE.md». This chain leaves the decision and
the trigger as they are: the GUI suite still does not go on CI, and nothing here reopens it. What
changes is the rule §D6 points at. Stage 3 (plan Task 7, R-18 and R-19) amends `CLAUDE.md`, not
ADR-0044: after it, §D6's phrase «before every merge to `main`, per CLAUDE.md» describes a rule
`CLAUDE.md` no longer states, and whether ADR-0044 then takes a head scope note (ADR-0047 §D12's
remedy for eleven earlier ADRs) is Task 7's call, not decided here. One effect worth stating: the
replacement tests join `PergamenumTests`, which ADR-0044 §D5 already runs on CI, so they run
there, advisory (§D11). The hosted tests have never run on the CI runner, and the one harness
call with no precedent in the unit suite is `cacheDisplay`; ADR-0044 §D13's «the first run is
discovery» applies to them.

**ADR-0051 §D8** decides that `uitests.sh`'s two kill loops stay doubled and files their
asymmetry as its own entry. Nothing in this chain's tasks touches those loops (a rewrite of the
runner is out of scope, plan §7), and §D8 stands. `--self-test` covers the verdict logic only.

### §D7 - A seam found later amends this ADR

A thirteenth or fourteenth site found during Task 5, or a shape change to one of these, is an
**amendment to this file**, not a new ADR (SPEC decision: one ADR for the seam package). It is a
dated note at the head of this file giving the site, the shape after, the test it serves, its
proof cost and the reason it was not found earlier. The rule of §D1 applies to it unchanged, and
it is committed with the PR that needs it, before that PR's seam commit.

---

## Alternatives considered

- **Keep the GUI suite as the gate and only add the `contaminated` verdict.** Settled by the
  SPEC («replace rather than reduce»); stage 1 is what remains of this alternative, and it stays.
- **Retire on logic cover alone, with no seam.** Rejected: for the 42 converted tests the
  decision the GUI test observed sits where no existing test reaches it. Retiring without the seam
  is losing the cover, which is what the census's «wiring lost» lists record for the cases where
  that trade was taken on purpose.
- **Synthesise the event instead of extracting the decision** (drive the SwiftUI gesture
  in-process). Rejected by the R-08 outcome: a mouse event does not reach a SwiftUI gesture in a
  hosted view, and the one route that might, `sendEvent`, is what R-15 forbids.
- **A test-only door** (`#if DEBUG` accessor, a member widened for a test's benefit). Rejected:
  ADR-0052 §D9. A test through a door that ships tests what ships; a test through a hatch tests
  the hatch.
- **One ADR per seam.** Rejected by the SPEC: twelve records of one rule; a later seam amends this
  one (§D7).
- **Extract #1 and #7 copy by copy rather than unify.** Rejected: three tests of one rule would
  pin three copies that already disagree (§D3). Unifying is what the census asked for, and
  what §D1's proof is designed to check.
- **Host with `sendEvent` in a window that cannot become key.** Rejected: R-15 is a constraint on
  the calls, not on their expected effect, and this machine's `Stop` hook runs the target at the
  end of every turn (CLAUDE.md, working agreements).

---

## Consequences

### Positive

- The decision a GUI test observed becomes a function a unit test calls in milliseconds, and the
  proof that the extraction changed nothing is the very GUI test about to be deleted, run once.
- Two places where the app carried a rule in duplicate (`enter(folder:)`'s three copies,
  `canMove`'s two, and `DiaryTimeline.minutes(at:)` beside `DiaryGeometry.minute(atY:)`) end with
  one.
- The hosted-view harness exists and is proven for SwiftUI chrome, a Workspace board and key
  equivalents. It holds R-15 as far as a type can and not beyond: the window refuses key and main,
  and `orderFront`, `orderFrontRegardless`, `makeKeyAndOrderFront`, `order(_:relativeTo:)` and
  `sendEvent` (bar AppKit's own bookkeeping events) record an issue and do nothing, which a test
  pins; `neverShown` checks the effects afterwards. `NSApp.activate` is not intercepted and
  `NSApp.sendEvent` only for an event it routes to that window, so those stay a matter of review.
- The unit suite stays inside R-14's 60 s on both measures the runs report. Swift Testing's own
  figure was 20.9 s before Task 3 and 20.6 s, 23.3 s and 19.8 s in the three runs after it (the
  last after the review fixes); the `xcodebuild` testing phase was 36.9 s before and 33.9 s,
  38.1 s and 33.6 s after. R-14 does not define which of the two counts; against the larger,
  38.1 s, the margin is about 22 s. The four new tests cost about 0.9 s, below the run-to-run
  spread (plan §8).

### Negative

- Thirteen production files change shape for testability, and nothing in the code says so
  beyond a comment. §D1's proof and this ADR are what stand in for it.
- Four of the seven PRs cost a full `--affected` proof run, on a machine the chain exists to
  distrust; stage 1's `contaminated` verdict is what makes those runs readable.
- #1 has one input on which old and new differ on paper (§D3), and #3's shape is not the plan's.
- The drag-and-drop loss the census names is real and is not answered by a seam: `.draggable`
  to `.dropDestination`, and «a drag carries the whole lit set», have no in-process cover.
- SwiftUI pointer gestures stay uncovered in-process (R-08), so the 17 kept GUI tests carry every
  gesture chain the seams do not reach.

### Neutral

- No on-disk change, no schema bump, no protected interface, no new dependency.
- The connectors are untouched except for the two additive Foundation-only functions of §D4.
- `Project.swift` needs no edit for the new test files (`Tests/**` is a glob); `tuist generate`
  runs after a file appears.

---

## Open for Stefano at acceptance

Accepting this ADR accepts the shapes above. These are the places it departs from, or adds to,
the plan, so they could be overturned here and not in a PR. Stefano accepted the ADR on
2026-09-21 as written, which settles items 1 and 2 as stated below; item 3 was decided the same
day, ahead of the acceptance. All three are recorded so the ADR does not read as if it were still
asking:

1. **#13 is listed.** Plan §4 says twelve; the census, plan §2 row 8 and Task 5 PR 5 name the
   embed label. Delete the row if twelve was meant.
2. **#1 keeps the empty-folder guard at `BoardChrome`** and returns the resolution so
   `placePendingNote` can report; **#3 takes `isFolder`**; **#8 also deletes `minutes(at:)`**;
   **#4 leaves `CardTextView.swift:313` alone**; **#11 is placed on `NoteTree`**, in a shared
   path (§D4).
3. **R-15 and `EventKitStore`. Decided by Stefano, 2026-09-21.** The question was whether «no
   hosted test reads calendar state» reaches the `EventKitStore()` a text-card board needs, given
   the unit suite builds one already. It does: R-15 stays strict and no hosted test constructs an
   `EventKitStore`. A board with a text card (`StickyTextCard` needs `CommandActions`, which needs
   an `EventKitStore`) therefore stays a GUI test, and the cap of 17 does not rise on its account.

---

## References

- `SPEC.md`, Approved 2026-09-21: R-08 to R-15, «Seams are accepted only if behaviour is
  unchanged».
- `docs/plans/ui-suite-replacement.md`: §4 (the seam inventory), Tasks 3 and 4, D-3 and D-4,
  §7 (risks and gates), §8 (the prototype outcome and the unit-suite times).
- `docs/plans/ui-suite-replacement-census.md`: the per-file triage, the «wiring lost» lists.
- `Tests/HostedViewPrototypeTests.swift`, `Tests/HostedViewSupport.swift`: the prototype.
- `Tests/EditorHeightTests.swift:49-55`: the never-shown-window precedent the harness copies.
- ADR-0001 §D1 (`docs/adr/0001-initial-architecture.md`): folder-enforced layers.
- ADR-0007 (`docs/adr/0007-ai-connector-mcp-over-the-vault.md`): the shared sources the two
  connectors compile.
- ADR-0025 §D3 (`docs/adr/0025-workspace-folder-board-separation.md`): `.folder("")` is never
  produced; the root is `select(nil)`.
- ADR-0044 §D5, §D6, §D11, §D13 (`docs/adr/0044-github-actions-ci.md`): what CI runs, the UI suite
  off CI and its trigger, advisory, and «the first run is discovery».
- ADR-0047 §D12 (`docs/adr/0047-task-categories-and-the-end-of-the-obsid.md`): the head scope note
  as the remedy for an earlier ADR whose premise moved.
- ADR-0051 §D8 (`docs/adr/0051-tests-gallery-and-scripts-share-one-helper-each.md`): the kill loops
  stay doubled.
- ADR-0052 §D9 (`docs/adr/0052-pratiche-ledger-marker-and-one-write-door.md`): no test-only door.
