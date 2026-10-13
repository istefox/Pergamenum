**Requirement set:** `SPEC.md`

# No term proportional to the note on the SwiftUI path of a keystroke (PG-406)

- **SPEC:** root `SPEC.md`, "No term proportional to the note on the SwiftUI path of a keystroke (PG-406)", Status
  Approved (2026-10-12), R-01 to R-13. Its `## Decisions`, `## Constraints` and `## Test seams` are settled
  input, and no task below reopens them. `/ship` archives it under `docs/archive/specs/`.
- **ADR outcome: new ADR**, `docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md`, written
  `planned` (the SPEC's "ADR needed" constraint, R-12).
  - It extends ADR-0094 §D9, keeps ADR-0073's departure 15 on the exact answer (D3), and adds the outline as an
    ADR-0091 §D6 holder under §D3's rule and §D8's kill switch, with no new invalidation case (D6). It keeps
    ADR-0001 §D1, ADR-0007, ADR-0012 §D3, ADR-0047 §D10, ADR-0065 §D1.2, ADR-0074 §D1 and ADR-0082 §D7 and §D9.
  - It settles the SPEC's two design items: the revision's uniqueness, a process-wide atomic counter drawn on every
    assignment (D1), and the pause, a restartable main-actor task injected through `VaultController.init` (D4).
    The third "Not yet specified" item, where a term the post-fix profile finds goes, is Task 7 step 5.
  - **Number.** `0095`. On 2026-10-12 `origin/main` is `93c17096`, whose highest ADR is `0094`, and no ref holds
    `0095` or higher (`git ls-tree` over every local and remote ref). **Re-check right before the docs PR merges
    and again before the code PR merges** (`docs/adr/README.md` rule 1); `docs/spec-pg-387-n4-birth-of-note` is
    in flight and may take a number. If `0095` is taken, renumber the file, its heading, every reference in this
    plan and in code comments, and the index lines.
  - **A second ADR-0095 draft is in the working tree**, `docs/adr/0095-a-keystrokes-update-compares-a-revision-not-the-note.md`
    (written by another writer at the same time, pointing at a plan `docs/plans/keystroke-update-path-pg-406.md`).
    Exactly one of the two may go into the docs PR. This plan answers to the `what-follows-a-keystroke` file. The
    other is not this plan's to delete; the person decides at PLAN APPROVAL.
  - It flips to `accepted` in the first docs change after the code PR merges and G-ceiling-406 and G-hand-405 are
    answered (rule 2).
  - **`CLAUDE.md`'s `## ADR index` needs one line**, pasted from `scripts/adr-index.py` with the docs PR:
    `- ADR-0095 — What follows a keystroke compares a revision, not the note`. Until then
    `scripts/adr-index.py --check` reports it missing.
- **Governing ADRs, registered and not reopened:**
  - ADR-0094: §D1 to §D3 (the `OffsetRanges` shape and `StorageEdit`'s rule), §D9 and "Ledger entries" (`ModelSync`).
  - ADR-0091: §D3 the invalidation rule, §D6 every holder shifts itself, §D8 the kill switch, §D9 the surfaces
    and the card.
  - ADR-0073: departure 15 (catch-up on a dirty buffer whose text is the incoming one), §D4 the save door.
  - ADR-0082: §D7, the Release hand check by the person; §D9, the bench and the person's ceilings.
  - ADR-0074 §D1: the outline is a controller of its own. ADR-0045: a widened `private` names its reader.
- **Baseline.** `main` at `93c17096`, which is `origin/main`. `SPEC.md`, this plan and both ADR-0095 drafts are
  untracked.
- **Delivery.**
  - A docs PR carries `SPEC.md`, this plan, ADR-0095 and the index line. Its body says "refs PG-406".
  - One code PR on `fix/no-whole-note-term-on-the-update-path-pg-406`, cut from `main` after the docs branch lands,
    built in one `/build` session. Its body carries `Closes #990` and no other closing keyword, negated or not
    (the PR #964 incident).
  - If the context runs short, split after Task 3: Tasks 1 to 3 are green and self-contained (the bench row, the
    revision, the mark and the pause).
  - Run `tuist install` and `tuist generate --no-open` before the first task, and again after every task that adds
    a file (Tasks 1, 2, 4 and 5).

## SPEC decisions registered (settled, not reopened)

- **Perimeter: every whole-note term on the SwiftUI path of a keystroke.** This plan reads it as also covering the
  members reading the tree found that the SPEC does not name: `canRun(.save)`, the pane's `text` input and its
  own observed reads, the coordinator's caret scan, the category row's parse and Diario's compare (see "What
  reading the tree added", items 2 to 6). Each is decided at PLAN APPROVAL (Risks).
- **Mechanism: a revision on the buffer, plus narrow inputs.** Fixing `OpenNote ==` alone, narrow inputs alone and
  the revision alone were rejected.
- **Outline: an incremental store in the shape of ADR-0094's holders,** rebuilt on a structural change and every
  time under `-editorFullRestyle YES`. A reparse at idle and a lazy parse on caret change were rejected.
- **Dirty flag: exact, verified when typing pauses.** `hasUnsavedChanges` is true when the revisions differ; it
  may read dirty late and never reads clean while the texts differ; save, close and quit decide on the exact
  compare. Dirty by revision alone and exact on every keystroke were rejected.
- **Acceptance: a bench row through SwiftUI, counters and the Release hand check.** The ceilings are the person's.
- **The find bar keeps its linear recompute while open.**
- **Constraints carried into every task:** behaviour unchanged (typing, caret, undo, IME, renumbering, reveal); the
  stored paragraph's length kept; the golden corpus (119 cases) byte-identical; `ModelSync` keeps its meaning;
  the 1 MB hand check on Release, by the person; no SwiftUI under `Sources/Core`; a restated test is named with
  its reason before it changes.

## What reading the tree added (`93c17096`)

1. **`OpenNote` is built directly in 46 places in 22 test files** and once in the sources
   (`VaultController+Tabs.swift:400`). No source or test compares two `OpenNote`, `NoteTab` or `EditorColumn`
   values with `==`; only `openNote == nil`. An explicit `init` with the memberwise labels keeps all of them
   compiling (ADR-0095 §D2).
2. **`canRun(.save)` reads `hasUnsavedChanges`** (`CommandActions+CanRun.swift:35`), and it is evaluated per body:
   by the File menu (`VaultCommands.swift:102`) and by the column for every app entry of the slash menu
   (`EditorColumn+Text.swift:185` -> `EditorCommand.all(canRun:)`, `EditorCommand.swift:214`). It reads the mark.
3. **The sidebar pane holds the note three ways.** It takes `text: String` (`OutlinePane.swift:21`), it reads
   `vault.currentOutlineEntry` and `vault.foldedEntries` in its own body (`:69`, `:155-162`, `:203`), so it is
   invalidated by every keystroke through Observation whatever its inputs, and `foldable`
   (`:187-189` -> `NoteFolding.foldableEntries(in:)`) calls `line(of:)` once per heading, each a walk over every
   line (`NoteFolding.swift:211-218`): quadratic.
4. **The coordinator finds the caret's entry by a linear scan** over every entry, on every selection change
   (`NoteTextView+Coordinator.swift:228`), from ranges the column parses per body (`EditorColumn+Text.swift:147-149`).
5. **The inspector's category row parses the whole note** per evaluation of the inspector's body
   (`VaultBrowser.swift:254`; `NoteDocument.parse` -> `FrontmatterSource.document(from:)`, which splits the whole
   text at `FrontmatterSource.swift:109-110`).
6. **Diario compares the whole prose on every binding write** (`DiaryController.swift:26-31`,
   `guard prose != oldValue, isLoaded`, the compare first), both sides foreign strings the editor wrote.
7. **Oggi and Diario do not host the editor column.** R-10's premise is inaccurate: each builds `NoteTextView`
   directly (`TodayView.swift:215-219`, `DiaryView.swift:109-110`). Oggi binds through `updateOpenNoteText`, so the
   revision and the mark reach it unchanged; Diario binds its own `prose`. R-10's intent, the same behaviour on
   both, is what Tasks 4 and 5 deliver.
8. **The decision sites and the display sites of `hasUnsavedChanges`** (grep on `93c17096`):
   - decision, to the exact answer: `CommandActions.swift:151`, `VaultController+Tabs.swift:106`,
     `QuitReview.swift:97`, `VaultController+Quit.swift:31`, `VaultController+Files.swift:34`,
     `VaultController+Folders.swift:31`, `VaultController+TabFollowUps.swift:76`, `VaultController+Editing.swift:59`
     and `:93`, `EditorColumn+Closing.swift:26`, `NoteTab.swift:143` (`catchUp`);
   - display, on the mark: `NoteTabBar.swift:77` and `:210`, `VaultTopBar.swift:30` and `:42`,
     `CommandActions+CanRun.swift:35`.
9. **Where `text` and `savedText` are assigned:** `VaultController.swift:358-365` (`updateOpenNoteText`),
   `VaultController+Editing.swift:151-152` (`acceptExternalChange`), `:170` (`keepLocalVersion`, `savedText = ""`),
   `VaultController+TabFollowUps.swift:51` (the writer's catch-up), `NoteTab.swift:149-150` (`catchUp`). With a
   `didSet` on `text` every one of them makes a new revision without being touched; only the ones that know the
   texts are equal link the revisions (ADR-0095 §D3).
10. **The save path keeps one storage.** `saveTab` reads `note.text` before its `await`
    (`VaultController+Editing.swift:60`) and `VaultSession.write` builds `WriteResult(path:text:)` from that value
    and announces it before returning (`VaultSession.swift:702-706`), so the writer's catch-up can link with a
    compare that costs nothing when nothing was typed (ADR-0095 §D4).
11. **`NoteTab.foldedEntries` holds offsets that are never shifted** (`NoteTab.swift:22`); a fold whose heading moves
    is dropped by `foldedOrdinals(ofOffsets:in:)` today. That behaviour stays (`PG-402` is outside); the store's
    `ordinals(ofOffsets:)` answers the same.
12. **What builds `OutlineInputs` and `OutlinePane` outside the column:** `FoldBadgeClickTests.swift:28`,
    `EditorControllerReadTimingRemainingTests.swift:107` and `:254` (both pass `outlineRanges:` and `foldedEntries:`
    ordinals), `NoteTextViewUpdatePinsTests.swift:67` (neither, unaffected), `ScrolledEditorFixture.swift:153-159`
    (`fold(heading:)` writes an ordinal into `outline.foldedEntries`), and `OutlinePaneFoldableOffsetTests.swift:17`
    (the only test `OutlinePane(…)`). `OutlineEntryCallbackFiresOnChangeOnly` (`:241-275`) sets `textView.string`
    and moves the caret with no styling pass, so the coordinator's private store must build itself on first read.
13. **`StructureMap.fences` are `CodeFence.regions(in:)` over the whole text** (`StructureMap.swift:72-82`), the
    regions `NoteOutline.entries(in:)` skips by, and a `.lines` decision never starts inside the frontmatter zone
    (`RestyleScope.swift:139`). The splice can read both from the absorbed map.
14. **The edit replay writes the binding before the styling** (`NoteTextView+EditReplay.swift:25-28`): the live tab's
    revision is the new one when the splice stamps the store.
15. **The shared delimiter test is array-based.** `FrontmatterSource.closingDelimiterIndex(in: [String])`
    (`FrontmatterSource.swift:101`) has seven callers (`MessageFrontmatterPatch.swift:28`, `TagRename.swift:19`,
    `:117`, `:152`, `ViewCatalogue.swift:77`, `FrontmatterSource.swift:120`, `:325`); they keep it unchanged, and it
    calls the new sequence form so the delimiter test stays one.
16. **Size limits.**

    | File | Lines (warn 400 / error 1000) | Plan |
    | --- | --- | --- |
    | `NoteTextView+Coordinator.swift` | 923, class body near `type_body_length` | one stored `outlineFeed` in the class, methods in a new `NoteTextView+Outline.swift` |
    | `VaultController.swift` | 455 | stored properties only (the pause, its counter, the store registry); methods in two new extension files |
    | `DiaryController.swift` | 432 | `editorWrote(_:)` and the counter only |
    | `OutlinePane.swift` | 334 | shrinks: `text`, `entries`, `foldableOffset` and the fold walk leave |
    | `ScrolledEditorFixture.swift` | 666 | one helper restated, one snapshot field |

17. **Where the new types compile.** `TextRevision`, `OpenNote` (`Sources/Vault/NoteTab.swift`), the pause, the
    store and the map are app-only (not in `sharedSources`, `Project.swift:87`). The two additions under
    `Sources/Core` (`NoteOutline.entry(inLine:)`, `NoteDocument.frontmatter(in:)`) import Foundation only and reach
    `perg` and `pergamenum-mcp` unused. The app target globs `Sources/**`, so new files need only `tuist generate`.

## Requirement coverage

| Requirement | Tasks |
| --- | --- |
| R-01 | 1, 6, 7 |
| R-02 | 4, 5, 6 |
| R-03 | 2, 3 |
| R-04 | 4, 5 |
| R-05 | 4, 5 |
| R-06 | 4, 5 |
| R-07 | 4, 5 |
| R-08 | 2, 3 |
| R-09 | 2, 3, 4, 5, 6 |
| R-10 | 4, 5 |
| R-11 | 6, 7 |
| R-12 | 7 |
| R-13 | 7 |

## Order

1. The update-path row lands first, and every "before" is measured on the old code (Task 1).
2. The revision, the mark and the pause: red (Task 2), then green with every dirty call site (Task 3).
3. The outline store, the narrow inputs and the counters: red (Task 4), then green (Task 5).
4. The call sites, the full suite, the "after" numbers and the Release profile (Task 6).
5. The ADR's numbers and pointers, the index, the ledger, the gates and the number re-check (Task 7).

### Task 1 — Tester: the update-path bench row, and every "before" measured on the old code (R-01)
Owner: tester
Files: Tests/UpdatePathFixture.swift, Tests/RestyleBudgetSupport+Update.swift, Tests/EditorUpdatePathBudgetTests.swift, scripts/editor-restyle-bench.sh
Tests: EditorUpdatePathBudgetTests.swift, EditorRestyleBudgetTests.swift, HostedViewSupport.swift
Signatures:
- RestyleBudget.includesUpdateRows — `static var includesUpdateRows: Bool { get }`
- RestyleBudget.updateLine — `static func updateLine(_ c: Case, cpuMs: Double, wallMs: Double, runs: Int) -> String`
- UpdatePathFixture — `@MainActor final class UpdatePathFixture { init(_ c: RestyleBudget.Case) async throws; let vault: VaultController; let textView: CompletingTextView; let coordinator: NoteTextView.Coordinator; var host: HostedView<AnyView> { get }; func keystroke(); func tearDown() }`
- scripts/editor-restyle-bench.sh — flag `--update`, exporting `TEST_RUNNER_RESTYLE_BUDGET_UPDATE=1` and adding `-only-testing:PergamenumTests/EditorUpdatePathBudgetTests`; a fifth table from lines matching `^restyle-budget-update size=`
Red: no

Test code and the bench script only, run before any other task, so its numbers are the old code's (R-01).

**The fixture.** `UpdatePathFixture` is the first test to host `EditorColumnView`; nothing in `Tests/` does today.

- A `TemporaryVault` holding `Nota.md` = `RestyleBudget.syntheticNote(bytes:variant:)`. A
  `VaultController(recents: .volatile(), openTabs: .volatile())`, `await open(root)`, `openNote(at: "Nota.md")`.
- `Navigation()`, `CommandActions` built as `NoteRevealTests.swift:14-33` builds them (the `EventKitStore()`
  precedent), `ShortcutStore(defaults:isOverridden:)` over a throwaway suite as `LinkFollowMenuTests.swift:51`, and
  the theme through `\.theme` as the other hosted tests set it.
- `HostedView(EditorColumnView(columnIndex: 0).environment(…), size:)`, then `settle()`. The text view is the one
  `CompletingTextView` under the host; its `delegate` is the coordinator. Assert `host.neverShown` and
  `host.refusals.isEmpty` (`HostedViewSupport.swift:159`, `:196`).
- `keystroke()` types `x` at the end of the middle paragraph (`RestyleBudget.insertionPoint(in:)`, tracking the
  offset as the note grows, as `JumpScenario` does) through `insertText(_:replacementRange:)`, then makes SwiftUI
  run its update before returning: first `host`'s `layoutSubtreeIfNeeded()`, and if that does not run it, one
  turn of the main run loop. Report which one works. The proof the update ran is `coordinator.restyleLog.skipped`
  advancing by exactly one (`updateNSView`'s `runPasses` finds nothing to restyle); a keystroke whose update did
  not run fails the test rather than measuring nothing.

**The line.** `restyle-budget-update size=<bytes> variant=<prose|fences> cpu_ms=<min> wall_ms=<min> runs=<K>`. It
starts `restyle-budget-update`, so no other table's pattern matches it.

**`EditorUpdatePathBudgetTests.swift`, `@Suite(.serialized)`:**

- `theUpdateLineHasTheSixFieldsTheBenchScriptGreps` pins
  `restyle-budget-update size=51200 variant=fences cpu_ms=4.10 wall_ms=5.20 runs=5`.
- `theFixtureRunsSwiftUIsUpdateAfterEveryKeystroke`, always on, at 50 KB fences: over three keystrokes,
  `restyleLog.incremental` and `restyleLog.skipped` each advance by one per key and `full` does not; the model's
  text (`vault.openNote?.text`) ends the middle paragraph with the `x`s typed so far.
- `aKeystrokeThroughSwiftUIsUpdateIsPrinted(_ c: RestyleBudget.Case)`, `.enabled(if:
  RestyleBudget.includesUpdateRows)`, arguments `RestyleBudget.activeCases`:
  `RestyleBudget.minimum(runs:warmUp:) { fixture.keystroke() }`, then print `updateLine`. Nothing is asserted on
  time until G-ceiling-406 (Task 7).

**`scripts/editor-restyle-bench.sh`:**

- `--update` exports `TEST_RUNNER_RESTYLE_BUDGET_UPDATE=1` and appends
  `-only-testing:PergamenumTests/EditorUpdatePathBudgetTests` to `extra`, as `--jump` does.
- A fifth table, "through SwiftUI's update (printed, never asserted):", with `size`, `variant`, `cpu_ms`,
  `wall_ms`, `editor_ms` (the first table's `cpu_ms` for the same size and variant, found with `grep` over
  `$lines`), `share_ms` (`cpu_ms - editor_ms`, through `awk`) and `runs`. bash 3.2: no associative arrays.
- The header comment's switch list gains `RESTYLE_BUDGET_UPDATE=1` and the fifth table's line format.

**The "before" measurements (R-01).** On the development Mac, on this task's tree, nothing else building:

- `scripts/editor-restyle-bench.sh --runs 9 --update`
- `scripts/editor-restyle-bench.sh --large-only --runs 3 --update`

Report both outputs verbatim, with `sw_vers`, `xcodebuild -version` and the Mac model. Task 7 writes them into
ADR-0095. If a 1 MB update keystroke on the old code runs past several seconds per key, say so and report the
runs you could take.

### Task 2 — Tester: the revision, the mark and the pause, declared and red (R-03, R-08, R-09)
Owner: tester
Files: Sources/Vault/TextRevision.swift, Sources/Vault/NoteTab.swift, Sources/Vault/OpenNote+Revision.swift, Sources/App/PauseScheduler.swift, Sources/App/VaultController.swift, Sources/App/VaultController+UnsavedMarks.swift, Tests/ManualPauseScheduler.swift, Tests/TextRevisionTests.swift, Tests/UnsavedMarkTests.swift, Tests/UnsavedMarkPauseTests.swift, Tests/UnsavedMarkSourceGuardTests.swift, Tests/VaultControllerExternalDeletionTests.swift
Tests: TextRevisionTests.swift, UnsavedMarkTests.swift, UnsavedMarkPauseTests.swift, UnsavedMarkSourceGuardTests.swift, VaultControllerExternalDeletionTests.swift, ManualPauseScheduler.swift
Signatures:
- TextRevision — `struct TextRevision: Hashable, Sendable { static func next() -> TextRevision }`
- OpenNote.init — `init(relativePath: String, title: String, text: String, savedText: String, externalChangePending: VaultSession.ExternalChange.Content? = nil)`
- OpenNote.revision — `private(set) var revision: TextRevision`
- OpenNote.savedRevision — `private(set) var savedRevision: TextRevision`
- OpenNote.hasUnsavedChanges — `var hasUnsavedChanges: Bool { get }`
- OpenNote.differsFromSaved — `var differsFromSaved: Bool { get }`
- OpenNote.adopt — `mutating func adopt(_ text: String)`
- OpenNote.recordWrite — `mutating func recordWrite(_ written: String)`
- OpenNote.settleUnsavedMark — `@discardableResult mutating func settleUnsavedMark() -> Bool`
- PauseScheduler — `@MainActor protocol PauseScheduler: AnyObject { func restart(_ action: @escaping @MainActor () -> Void); func cancel() }`
- TaskPauseScheduler — `@MainActor final class TaskPauseScheduler: PauseScheduler { init(interval: Duration = .milliseconds(500)) }`
- VaultController.init — `init(recents: RecentVaults = RecentVaults(), openTabs: OpenTabsStore = OpenTabsStore(), pinnedTags: PinnedTagsStore = PinnedTagsStore(), typingPause: any PauseScheduler = TaskPauseScheduler())`
- VaultController.typingPause — `@ObservationIgnored let typingPause: any PauseScheduler`
- VaultController.unsavedMarkChecks — `@ObservationIgnored private(set) var unsavedMarkChecks: Int`
- VaultController.settleUnsavedMarks — `func settleUnsavedMarks()`
- ManualPauseScheduler — `@MainActor final class ManualPauseScheduler: PauseScheduler { var restarts: Int { get }; var isPending: Bool { get }; func fire() }`
Red: yes

**Declarations with neutral bodies, never `fatalError`.** `TextRevision.swift` imports Foundation and
`Synchronization` and carries a header naming ADR-0095 §D1; `next()` answers one constant value. `revision` and
`savedRevision` are stored on `OpenNote` in `NoteTab.swift` (a stored property cannot live in an extension), the
explicit `init` sets both to `next()`; the methods sit in `OpenNote+Revision.swift`. `hasUnsavedChanges` keeps
today's body, `differsFromSaved` answers `text != savedText`, `adopt` assigns both texts, `recordWrite` assigns
`savedText`, `settleUnsavedMark()` answers `false`. `TaskPauseScheduler.restart` and `cancel` do nothing;
`settleUnsavedMarks()` does nothing. The stored pause and counter go in `VaultController.swift`, the method in
`VaultController+UnsavedMarks.swift`. Every existing construction compiles unchanged.

**`ManualPauseScheduler`** records the last action, counts `restarts`, and runs the pending action once on `fire()`.

**`TextRevisionTests.swift` (R-03):**

- `nextNeverRepeats`: ten thousand draws are distinct.
- `nextIsUniqueAcrossTasks`: draws from several concurrent tasks are distinct.

**`UnsavedMarkTests.swift`, pure `OpenNote` (R-03, R-08):**

- `everyAssignmentToTheTextMakesANewRevision`: assigning a different text, the same string again, `catchUp(to:
  .text(…))` and `adopt(_:)` each change `revision`.
- `twoBuffersThatDifferInTextNeverShareARevision`: the split-editor shape. A buffer copied, then each copy edited
  differently: the two revisions differ from each other and from the original. Two buffers built separately with
  the same text differ too.
- `equalityReadsTheRevisionNotTheText`: a copy equals its original; after `text = text` it does not; two buffers
  built separately with equal fields are unequal.
- `aBufferBuiltWithEqualTextsIsClean` and `aBufferBuiltWithDifferentTextsIsDirty`, both readings.
- `anUndoBackKeepsTheMarkOnUntilSettled`: an edit turns the mark on; assigning `savedText`'s value back leaves the
  mark on and `differsFromSaved` false; `settleUnsavedMark()` answers `true` and the mark is off.
- `settlingADirtyBufferChangesNothing`: answers `false`, the mark stays on, `revision` and `savedRevision` unchanged.
- `recordWriteLinksOnlyWhenTheBufferHoldsTheWrittenText`: the written string itself links; a buffer edited after
  the text was read stays marked.
- `theMarkNeverReadsCleanWhileTheTextDiffers`: a seeded random sequence of edits, undo-backs, `adopt`, `recordWrite`
  with and without a match, `savedText = ""`, `catchUp`, `settleUnsavedMark()`; after each step, `!hasUnsavedChanges`
  implies `text == savedText`, and `differsFromSaved == (text != savedText)`.
- `catchUpDecidesOnTheExactAnswer` (departure 15): a buffer edited and undone back, not settled, catches up to a
  different `.text` as `.adopted`; a buffer that really differs gets `.asked`. Green on today's code, and it stays
  the guard that keeps `catchUp` off the mark.

**`UnsavedMarkPauseTests.swift`, a `VaultController` with a `ManualPauseScheduler` over a `TemporaryVault` (R-08):**

- `typingRestartsThePause`: three `updateOpenNoteText` calls, `restarts == 3`, `unsavedMarkChecks == 0`.
- `firingThePauseClearsAnUndoneBuffer`: edit, edit back to the opened text: the mark is on; `fire()`: off, one check.
- `firingThePauseLeavesADirtyBufferAsItWas`: `columns` equal before and after, the mark on.
- `thePauseSettlesEveryColumn`: split, undo back in column 1, type in column 0, `fire()`: column 1 is clean.
- `aSaveClearsTheMarkWithoutThePause`: edit, `saveOpenNote()`: off, `unsavedMarkChecks == 0`. Green today.
- `closeAndQuitDecideOnTheExactAnswer`: undo back, no `fire()`: `QuitReview(columns:)` is empty, `saveTab` answers
  `.clean`, `requestCloseFocusedTab` closes without a dialog.
- `taskPauseSchedulerRunsTheLastActionOnceAfterTheInterval`: a real `TaskPauseScheduler(interval: .milliseconds(20))`
  restarted three times runs only the third action, once, polled for up to two seconds, then still once 100 ms later.

**`UnsavedMarkSourceGuardTests.swift`** (the `resolvedRepoRoot()` pattern of `IncrementalRestyleSurfacesTests`):

- each decision file of item 8 reads `differsFromSaved` and not `hasUnsavedChanges` at the named site
  (`NoteTab.swift`'s `catchUp` body included);
- `OpenNote`'s `static func ==` exists and its body names neither `text` nor `savedText`.

**One restated test (R-09).** `VaultControllerExternalDeletionTests.swift:183-185`, `aBufferUndoneToCleanCanStillBeKeptAndSaved`,
undoes back to the saved text and requires a clean buffer at once. Insert `controller.settleUnsavedMarks()` before
the `#require`, with a comment naming ADR-0095 §D3: the mark clears at the pause now, and the test's point
(`keepLocalVersion` on a deleted note turns a clean buffer dirty) is unchanged. Green before Task 3 and after it.
No other test asserts clean after an undo back (grep of the 84 `hasUnsavedChanges` lines in 23 test files); if
Task 3 turns another red for that reason only, it stops and reports rather than restating.

### Task 3 — Coder: the revision, the mark, the pause and every dirty call site (R-03, R-08, R-09)
Owner: coder
Files: Sources/Vault/TextRevision.swift, Sources/Vault/NoteTab.swift, Sources/Vault/OpenNote+Revision.swift, Sources/App/PauseScheduler.swift, Sources/App/VaultController.swift, Sources/App/VaultController+UnsavedMarks.swift, Sources/App/VaultController+Editing.swift, Sources/App/VaultController+TabFollowUps.swift, Sources/App/VaultController+Tabs.swift, Sources/App/VaultController+Quit.swift, Sources/App/VaultController+Files.swift, Sources/App/VaultController+Folders.swift, Sources/App/QuitReview.swift, Sources/App/CommandActions.swift, Sources/Features/Editor/EditorColumn+Closing.swift
Tests: TextRevisionTests.swift, UnsavedMarkTests.swift, UnsavedMarkPauseTests.swift, UnsavedMarkSourceGuardTests.swift, VaultControllerWriteCatchUpTests.swift, VaultControllerExternalDeletionTests.swift, VaultControllerLandedChangeTests.swift, QuitCoordinatorTests.swift, QuitGapTests.swift, TabSaveTests.swift, ColumnCloseTests.swift, CloseTabRequestTests.swift, NoteTabTests.swift, VaultTests.swift
Signatures:
- OpenNote.== — `static func == (lhs: VaultController.OpenNote, rhs: VaultController.OpenNote) -> Bool`
- (relies on every signature of Task 2)
Red: no

1. **`TextRevision.next()`**: one `private static let counter = Atomic<UInt64>(0)`,
   `wrappingAdd(1, ordering: .relaxed).newValue`. No lock, no actor.
2. **`OpenNote`** (ADR-0095 §D1 to §D3):
   - `var text: String { didSet { revision = .next() } }`; `var savedText: String { didSet { savedRevision = .next() } }`.
   - The explicit `init` draws one revision for `text`, and sets `savedRevision` to it when `text == savedText`,
     otherwise to a second draw. Observers do not run in `init`.
   - `hasUnsavedChanges`: `revision != savedRevision`. `differsFromSaved`: `false` when equal, else `text != savedText`.
   - `adopt(_:)`: assigns both texts, then `savedRevision = revision`. `recordWrite(_:)`: assigns `savedText`, then
     links when `text == written`. `settleUnsavedMark()`: when the mark is on and `text == savedText`, links and
     answers `true`; otherwise answers `false` and changes nothing.
   - `==` by hand, over `relativePath`, `title`, `revision`, `savedRevision`, `externalChangePending`.
   - `catchUp(to:)`: `differsFromSaved` where it read `hasUnsavedChanges`; the `.text` branch calls `adopt`.
3. **Call sites.** Every decision site of item 8 reads `differsFromSaved`. `acceptExternalChange` calls `adopt`.
   The writer branch of `caughtUp(with:savedBy:)` (`VaultController+TabFollowUps.swift:51`) calls
   `recordWrite(result.text)`. `keepLocalVersion` is unchanged (its fresh `savedRevision` is the truth).
4. **The pause.** `TaskPauseScheduler` cancels the pending `Task` and starts
   `Task { @MainActor in try? await Task.sleep(for: interval); guard !Task.isCancelled else { return }; action() }`.
   `updateOpenNoteText` restarts `typingPause` with `{ [weak self] in self?.settleUnsavedMarks() }` after the
   tab update. `settleUnsavedMarks()` walks `columns` and their `tabs`, and for each tab whose mark is on counts one
   check, settles a copy of the note and writes the tab back only when `settleUnsavedMark()` answered `true`.
5. **Run** the four Task 2 suites, then the save, quit, close and catch-up suites listed in `Tests:`, then the full
   unit suite (`.claude/test-cmd`). A red is diagnosed before anything changes.

### Task 4 — Tester: the outline store, the narrow inputs and the counters, declared and red (R-02, R-04, R-05, R-06, R-07, R-09, R-10)
Owner: tester
Files: Sources/Core/Markdown/NoteOutline.swift, Sources/Core/Conventions/FrontmatterSource.swift, Sources/Features/Editor/OutlineMap.swift, Sources/Features/Editor/OutlineStore.swift, Sources/Features/Editor/OutlinePaneInputs.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView+DerivedState.swift, Sources/Features/Editor/ModelSync.swift, Sources/Features/Editor/FindSession.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Diary/DiaryController.swift, Sources/Vault/NoteTab.swift, Sources/App/VaultController.swift, Sources/App/VaultController+OutlineStores.swift, Tests/UpdatePathFixture.swift, Tests/ScrolledEditorFixture.swift, Tests/OutlineMapTests.swift, Tests/OutlineMapPropertyTests.swift, Tests/OutlineStoreTests.swift, Tests/OutlinePaneInputsTests.swift, Tests/NarrowInputsTests.swift, Tests/BoundedFrontmatterTests.swift, Tests/UpdatePathCounterTests.swift, Tests/SurfaceParityUpdateTests.swift, Tests/UpdatePathSourceGuardTests.swift, Tests/OutlinePaneFoldableOffsetTests.swift, Tests/FoldBadgeClickTests.swift, Tests/EditorControllerReadTimingRemainingTests.swift
Tests: OutlineMapTests.swift, OutlineMapPropertyTests.swift, OutlineStoreTests.swift, OutlinePaneInputsTests.swift, NarrowInputsTests.swift, BoundedFrontmatterTests.swift, UpdatePathCounterTests.swift, SurfaceParityUpdateTests.swift, UpdatePathSourceGuardTests.swift, OutlinePaneFoldableOffsetTests.swift, FoldBadgeClickTests.swift, EditorControllerReadTimingRemainingTests.swift, IncrementalRestyleHostedTests.swift, IncrementalStylerModel.swift, DiaryTestSupport.swift
Signatures:
- NoteOutline.LineEntry — `struct LineEntry: Equatable, Sendable { var kind: NoteOutline.Entry.Kind; var title: String }`
- NoteOutline.entry(inLine:) — `static func entry(inLine trimmed: String) -> LineEntry?`
- NoteDocument.frontmatter(in:) — `static func frontmatter(in text: String) -> Frontmatter`
- OutlineMap — `struct OutlineMap: Equatable, Sendable { init(); init(text: String) }`
- OutlineMap.Entry — `struct Entry: RangedEntry, Sendable { var range: NSRange; var kind: NoteOutline.Entry.Kind; var title: String; var terminatorLength: Int }`
- OutlineMap.Item — `struct Item: Equatable, Sendable { var range: NSRange; var kind: NoteOutline.Entry.Kind; var title: String; var level: Int }`
- OutlineMap.entries — `var entries: OffsetRanges<Entry> { get }`
- OutlineMap.items — `var items: [Item] { get }`
- OutlineMap.rebuild — `mutating func rebuild(text: String)`
- OutlineMap.apply — `mutating func apply(_ edit: StorageEdit)`
- OutlineMap.splice — `mutating func splice(_ text: NSString, in dirty: NSRange, fences: OffsetRanges<StructureMap.Fence>)`
- OutlineMap.lastEntry — `func lastEntry(atOrBefore offset: Int) -> Int?`
- OutlineMap.ordinals — `func ordinals(ofOffsets offsets: Set<Int>) -> Set<Int>`
- OutlineMap.level — `func level(ofEntry ordinal: Int) -> Int`
- OutlineMap.isFoldable — `func isFoldable(_ ordinal: Int) -> Bool`
- OutlineRow — `struct OutlineRow: Equatable, Sendable { var kind: NoteOutline.Entry.Kind; var title: String; var level: Int; var isFoldable: Bool }`
- OutlineRowsSource — `enum OutlineRowsSource: Equatable { case store(ObjectIdentifier, generation: Int); case fresh(TextRevision) }`
- OutlineTally — `struct OutlineTally: Equatable, Sendable { var rebuilds: Int; var splices: Int; var shifts: Int }`
- OutlineStore — `@MainActor @Observable final class OutlineStore { init(); init(text: String); private(set) var rows: [OutlineRow]; private(set) var generation: Int; var map: OutlineMap { get }; var describes: TextRevision? { get }; var tally: OutlineTally { get } }`
- OutlineStore.rebuild — `func rebuild(text: String)`
- OutlineStore.apply — `func apply(_ edit: StorageEdit)`
- OutlineStore.splice — `func splice(_ text: NSString, in dirty: NSRange, fences: OffsetRanges<StructureMap.Fence>)`
- OutlineStore.stamp — `func stamp(_ revision: TextRevision?)`
- OutlineStore.rows(describing:text:) — `func rows(describing revision: TextRevision, text: String) -> (rows: [OutlineRow], source: OutlineRowsSource)`
- OutlineStore.foldedOrdinals — `func foldedOrdinals(ofOffsets offsets: Set<Int>, describing revision: TextRevision, text: String) -> Set<Int>`
- OutlineStore.foldableOffset — `func foldableOffset(ofEntry ordinal: Int) -> Int?`
- OutlineStore.lineRange — `func lineRange(ofEntry ordinal: Int) -> NSRange?`
- OutlinePaneInputs — `struct OutlinePaneInputs: Equatable { var rows: [OutlineRow]; var source: OutlineRowsSource; var notePath: String; var currentEntry: Int?; var foldedOrdinals: Set<Int>; var hiddenByFold: Set<Int> { get } }`
- NoteTextView.OutlineInputs — `var store: OutlineStore?; var currentRevision: (() -> TextRevision?)?; var foldedOffsets: Set<Int>`
- DerivedStateSnapshot.outline — `var outline: [OutlineMap.Item]`
- VaultController.outlineStore — `func outlineStore(forColumn id: EditorColumn.ID) -> OutlineStore`
- NoteTab.ChipFace — `struct ChipFace: Equatable, Sendable { let id: UUID; let title: String; let relativePath: String; let isPreview: Bool; let isUnsaved: Bool }`
- NoteTab.chipFace — `var chipFace: ChipFace { get }`
- ModelSync.compares — `private(set) var compares: Int; mutating func countCompare()`
- FindSession.updates — `@ObservationIgnored private(set) var updates: Int`
- DiaryController.editorWrote — `func editorWrote(_ prose: String)`
- DiaryController.proseCompares — `@ObservationIgnored private(set) var proseCompares: Int`
- EditorColumnView.init — `init(columnIndex: Int, find: FindSession = FindSession())`
- UpdatePathFixture.init — `init(_ c: RestyleBudget.Case, typingPause: any PauseScheduler = ManualPauseScheduler(), find: FindSession = FindSession()) async throws`
Red: yes

**Declarations with neutral bodies, never `fatalError`.** The two `Sources/Core` additions import Foundation only:
`entry(inLine:)` answers `nil` and `entries(in:)` does not call it yet; `frontmatter(in:)` answers `.empty`.
`OutlineMap` holds one `OffsetRanges<Entry>` that `init(text:)` leaves empty; every mutation is a no-op, every
query answers empty, `nil`, `1` or `false`. `OutlineStore` holds one map and empty `rows`; `rows(describing:text:)`
answers `([], .fresh(revision))`. `OutlinePaneInputs.==` compares `source`, `notePath`, `currentEntry` and
`foldedOrdinals`, never `rows` (the declared semantics, written by the tester), and `hiddenByFold` answers `[]`.
The three `OutlineInputs` fields are added beside `outlineRanges` and `foldedEntries`, which stay until Task 5 removes
them. `DerivedStateSnapshot.outline` is filled with `[]`. `outlineStore(forColumn:)` answers a new store every call
(no registry yet); the registry's stored property goes in `VaultController.swift`, the method in
`VaultController+OutlineStores.swift`. `chipFace` answers a face with an empty title. The counters never move;
`editorWrote(_:)` assigns `prose`. `EditorColumnView.init` seeds `_find` with `State(initialValue:)`, the one
complete body here. `UpdatePathFixture` gains the two parameters and passes them on.

**Restated tests, named with their reason (R-09).** Each keeps its scenario and its expected outcome; only the
input shape changes, because ADR-0095 §D7 removes the ranges and the ordinals from `OutlineInputs`:

- `FoldBadgeClickTests.swift:21-28` and `EditorControllerReadTimingRemainingTests.swift:102-107`: drop
  `outlineRanges:`, pass `foldedOffsets:` the heading's offset (0 for `# Uno`, so the value does not change).
- `EditorControllerReadTimingRemainingTests.swift:250-254` (`OutlineEntryCallbackFiresOnChangeOnly`): drop
  `outlineRanges:`. The coordinator's own store answers (ADR-0095 §D6, built on first read).
- `ScrolledEditorFixture.swift:153-159` (`fold(heading:)`): write the heading's UTF-16 offset into
  `outline.foldedOffsets` instead of its ordinal into `foldedEntries`. `RestyleTwin.differences` compares
  `outline` and `RestyleTwin.emptyFields` names it when empty.
- `OutlinePaneFoldableOffsetTests.swift`: the three cases move to `OutlineStore(text:).foldableOffset(ofEntry:)`
  with the same texts and the same expected answers, because the pane no longer holds the text.

These go red now and green in Task 5.

**`OutlineMapTests.swift` (R-06, R-07):** a fixed corpus: headings 1 to 6, `#tag` lines, embeds on their own line,
remote and inline embeds, CRLF lines, a heading as the last line with and without a terminator, headings inside
backtick and tilde fences and inside a `pergamenum-view` fence, a frontmatter block holding `# x`, a setext
heading. For each: `OutlineMap(text:).items` equals `NoteOutline.entries(in:)` converted (`NSRange(_:in:)`,
kind, title, level); `ordinals(ofOffsets:)` equals `foldedOrdinals(ofOffsets:in:)` for every entry offset plus
two that name nothing; `isFoldable` over the ordinals equals `NoteFolding.foldableEntries(in:)`;
`lastEntry(atOrBefore:)` equals `lastIndex { $0.location <= caret }` for every caret position.

**`OutlineMapPropertyTests.swift` (R-06):** `EditGenerator`'s seeded random sequences
(`IncrementalStylerModel.swift`), structural atoms included (opening and closing a fence and a `pergamenum-view`
fence, frontmatter delimiters, setext underlines, `#` at a line start), at least as many sequences as
`IncrementalStylerPropertyTests` runs. Each edit is driven the way the coordinator drives it: `StorageEdit` into
`apply`, then `RestyleScope`'s decision; `.lines(dirty)` absorbs and splices with the absorbed map's fences,
`.full` rebuilds. After every edit, `items` equals the converted `NoteOutline.entries(in:)` and the three
equalities above hold. A second pass sets the kill switch's shape (rebuild every edit, no shift) and asserts the
same. A failure prints the seed and the edit.

**`OutlineStoreTests.swift` (R-06, R-07):** `rows` equals the rows derived from `NoteOutline.entries(in:)` and
`foldableEntries(in:)` after every edit of a short random sequence; `generation` moves only when `rows` changes
(typing inside a paragraph leaves it); `tally` counts one shift per `apply`, one splice per `splice`, one rebuild per
`rebuild`; `rows(describing:text:)` answers the store's rows with `.store(ObjectIdentifier(store), generation:)`
when stamped with that revision, and freshly parsed rows with `.fresh(revision)` otherwise, without changing the
store; `foldableOffset(ofEntry:)` is `nil` for an embed and a heading with nothing under it.

**`OutlinePaneInputsTests.swift` (R-07):** equal when only `rows` differ under one source; unequal when the store
identity differs with an equal generation (the two columns' stores); `hiddenByFold` equals the pane's former
walk (`OutlinePane.swift:202-215`) over the same rows and ordinals, on nested sections and embeds.

**`NarrowInputsTests.swift` (R-04):** after a first edit, `chipFace` before and after a second edit is equal and
`isUnsaved` is true; a rename changes it. `NoteDocument.frontmatter(in:)` is covered by the next file.

**`BoundedFrontmatterTests.swift`:** `NoteDocument.frontmatter(in:) == NoteDocument.parse(text).frontmatter` over:
no block, a closed block, an empty block, CRLF lines, a leading U+FEFF, `---` with trailing spaces, an unclosed
block, `---` not on line 0, `pergamenum-category` among foreign keys, and a 1 MB body after a closed block.

**`UpdatePathCounterTests.swift`, hosted through `UpdatePathFixture`, arguments `RestyleBudget.activeCases` (the two
50 KB cases by default, the 200 KB and 1 MB ones when the bench switches are set) (R-02, R-04, R-05):**

- `aPlainKeystrokeComparesNoTextAndParsesNoOutline`: over five keystrokes, `coordinator.modelSync.compares` moves by
  0, the column store's `tally.rebuilds` by 0 and `splices` by 1 per key, `find.updates` by 0 (bar closed),
  `vault.unsavedMarkChecks` by 0, `restyleLog.skipped` by 1 per key, the mark on, the pause pending.
- `aFenceKeystrokeRebuildsTheStoreOnce`: the keystroke that opens a fence (`RestyleBudget`'s fallback scenario
  shape) rebuilds the store exactly once.
- `aModelReplacedFromOutsideCountsOneCompare`: `vault.updateOpenNoteText(other)` outside the view, then the forced
  update: `compares` moves by 1 and the view holds `other` (ADR-0094 §D9's meaning, kept).
- `withTheBarOpenEachKeystrokeRecomputesTheMatches` (R-05): an injected `FindSession`, opened on a query the note
  holds; per keystroke `updates` moves by 1 and the matches equal `NoteFind.run` over `vault.openNote!.text`.
- `theStoreEqualsTheParseAfterEachKeystroke` (R-06): the column store's `map.items` equals the converted parse.
- `theCaretEntryIsReportedAfterAKeystrokeThatMakesAHeading` (R-07): typing `#` and a space at the start of a
  paragraph above the caret reports the new entry without a further caret move.

**`SurfaceParityUpdateTests.swift` (R-10):**

- Oggi: a hosted `NoteTextView` bound exactly as `TodayView.swift:217-219` binds it, over a `VaultController` with a
  `ManualPauseScheduler`; per keystroke `modelSync.compares` 0, the private store spliced and never rebuilt, the
  mark on and no check until `fire()`.
- Diario (`DiaryTestSupport`): `editorWrote(_:)` counts no compare and leaves a save pending; a load counts none; a
  `prose` assignment outside the editor counts one.

**`UpdatePathSourceGuardTests.swift` (R-02, R-04, R-05, R-07, R-10):**

- `EditorColumn+Text.swift`, `NoteListPane+Footer.swift` and `OutlinePane.swift` name none of
  `NoteOutline.entries(in:`, `foldedOrdinals(`, `NoteFolding.foldableEntries(`;
- `OutlinePane.swift` reads neither `vault.currentOutlineEntry` nor `vault.foldedEntries` and declares no
  `let text: String`; `NoteListPane+Footer.swift` places it with `.equatable()`;
- `FindKeeping` declares no `let text: String` and no `.onChange(of: text)`;
- `BacklinksSection.swift`, `UnresolvedLinksSection.swift` and `NoteTabBar.swift`'s chip store no
  `VaultController.OpenNote` or `NoteTab`;
- `VaultBrowser.swift`'s category row does not call `NoteDocument.parse(`;
- `DiaryView.swift`'s editor binding calls `editorWrote`; `TodayView.swift`'s binds through `updateOpenNoteText`;
- `NoteTextView+Coordinator.swift` and `NoteTextView+Inputs.swift` no longer name `outlineRanges`.

### Task 5 — Coder: the outline store, the narrow inputs, the find, the inspector and Diario (R-02, R-04, R-05, R-06, R-07, R-09, R-10)
Owner: coder
Files: Sources/Core/Markdown/NoteOutline.swift, Sources/Core/Conventions/FrontmatterSource.swift, Sources/Features/Editor/OutlineMap.swift, Sources/Features/Editor/OutlineStore.swift, Sources/Features/Editor/OutlinePaneInputs.swift, Sources/Features/Editor/OutlinePane.swift, Sources/Features/Editor/NoteListPane+Footer.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView+Outline.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+DerivedState.swift, Sources/Features/Editor/NoteTextView+Update.swift, Sources/Features/Editor/ModelSync.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Editor/FindSession.swift, Sources/Features/Editor/NoteTabBar.swift, Sources/Features/Editor/BacklinksSection.swift, Sources/Features/Editor/UnresolvedLinksSection.swift, Sources/Features/Editor/VaultBrowser.swift, Sources/Vault/NoteTab.swift, Sources/App/VaultController.swift, Sources/App/VaultController+OutlineStores.swift, Sources/App/VaultController+ColumnClose.swift, Sources/Features/Diary/DiaryController.swift, Sources/Features/Diary/DiaryView.swift
Tests: OutlineMapTests.swift, OutlineMapPropertyTests.swift, OutlineStoreTests.swift, OutlinePaneInputsTests.swift, NarrowInputsTests.swift, BoundedFrontmatterTests.swift, UpdatePathCounterTests.swift, SurfaceParityUpdateTests.swift, UpdatePathSourceGuardTests.swift, OutlinePaneFoldableOffsetTests.swift, FoldBadgeClickTests.swift, EditorControllerReadTimingRemainingTests.swift, IncrementalRestyleHostedTests.swift, NoteOutlineTests.swift, StylerGoldenTests.swift
Signatures:
- NoteTextView.OutlineFeed — `struct OutlineFeed { var own: OutlineStore?; var fed: ObjectIdentifier? }`
- FrontmatterSource.closingDelimiterIndex(inLines:) — `static func closingDelimiterIndex<Lines: Sequence>(inLines lines: Lines) -> Int? where Lines.Element == String`
- (relies on every signature of Task 4)
Red: no

1. **The rule once (Core).** `NoteOutline.entry(inLine:)` is the per-line half of `entries(in:)`, which now calls
   it; `entries(in:)`'s output does not change (`NoteOutlineTests` and the golden corpus are the witnesses).
   `NoteDocument.frontmatter(in:)` splits on U+000A only until the closing delimiter, keeping a `\r` as
   `components(separatedBy: "\n")` does, and hands the lines it read to `FrontmatterParser`; the array form of
   `closingDelimiterIndex(in:)` calls the new sequence form, so all eight readers share one delimiter test
   (ADR-0065 §D1.2, PG-276; item 15). The sequence form takes a different label on purpose: an overload under
   `in:` would resolve the array form's own call to itself.
2. **`OutlineMap`** (ADR-0095 §D6): `init(text:)`/`rebuild` from `NoteOutline.entries(in:)`; `apply` through
   `OffsetRanges.apply(_:partial:)`, the partial rule chosen by the property test and the caret test (start from
   `.clip`: an entry whose line is edited keeps its start until the splice re-reads it); `splice` reads each line of
   `dirty`, skips the lines intersecting a fence, trims and calls `entry(inLine:)`, then `OffsetRanges.splice`;
   `lastEntry(atOrBefore:)` and `ordinals(ofOffsets:)` by binary search (one `partition` each); `level(ofEntry:)`
   walks back to the nearest heading; `isFoldable` reads the next entry only (§D7's local rule).
3. **`OutlineStore`**: the map and the stamp `@ObservationIgnored`; `rows` reassigned only when a value changes,
   over the replaced window, the entry before it and forward to the next heading; `generation` bumped with it;
   `tally` incremented in every configuration. `rows(describing:text:)` and `foldedOrdinals(ofOffsets:describing:text:)`
   take the fresh path (`NoteOutline.entries(in:)`, `foldedOrdinals(ofOffsets:in:)`) only when the stamp is not the
   revision asked about, and never write it back.
4. **The coordinator** (`NoteTextView+Outline.swift`, plus one stored `var outlineFeed = OutlineFeed()` in the class):
   - `outlineStore(for:)` answers `parent.outline.store` or the private one, and rebuilds it from `textView.string`
     when its identity is not `outlineFeed.fed`;
   - `shiftDerivedState(by:)` applies the edit to it; the splice runs in `applyIncrementalStyling` right after
     `restyleScope?.absorb(...)` (`NoteTextView+Coordinator.swift:825`), with the absorbed map's `fences`; the
     rebuild runs in `settleBaseline` (`:762`), which every full pass and every pass under the kill switch reaches;
   - after the styling in `runEditPasses` and in `runPasses`, `stamp(parent.outline.currentRevision?())`;
   - the selection handler (`:228`) asks `lastEntry(atOrBefore:)`; after a splice on the keystroke path the
     coordinator asks once more and lets `claimOutlineEntry` drop a repeat;
   - `runPasses` (`NoteTextView+Update.swift:70-72`) hands `applyFolding` `ordinals(ofOffsets: outline.foldedOffsets)`,
     empty without reading the map when nothing is folded.
   - `OutlineInputs.outlineRanges` and `foldedEntries` are deleted; `DerivedStateSnapshot.outline` is the map's
     `items`.
   - If SwiftUI reports a state change during a view update when a rebuild in `runPasses` reassigns `rows`, defer
     that reassignment and the stamp together to the next main-actor turn, and say so in the report.
5. **The column** (`EditorColumn+Text.swift`): `outlineInputs(for:)` passes `store: vault.outlineStore(forColumn:
   column id)`, `currentRevision: { tab?.note.revision }` and `foldedOffsets: tab?.foldedEntries ?? []`; the parse at
   `:147-149` and the translation at `:159` go. `FindKeeping` takes `revision` and `text: () -> String`;
   `.onChange(of: revision)` replaces `.onChange(of: text)`; the three other handlers read `text()`.
   `FindSession.update(in:)` counts `updates` after its `guard isOpen`.
6. **The registry.** `outlineStore(forColumn:)` makes a store on first use and keeps it; `closeColumn`
   (`VaultController+ColumnClose.swift`) drops the closed column's store.
7. **The sidebar.** `OutlinePane` holds `inputs: OutlinePaneInputs` plus `onSelect: (Int) -> Void`,
   `onToggleFold: (Int) -> Void` and `moveReplacements`, a closure answering `OutlineMove.replacements` over the note's
   text read when it runs; it is `Equatable` by `inputs`, and its body reads no observed property of
   `VaultController`. The footer builds the inputs from `store.rows(describing:text:)`,
   `vault.currentOutlineEntry` and `store.foldedOrdinals(ofOffsets:describing:text:)`, places the pane with
   `.equatable()`, and resolves a click's line range and a fold's heading offset from the store when they happen.
8. **Narrow inputs.** The chip takes `face: NoteTab.ChipFace` (`NoteTabBar.swift:46`, `:171`, the dot at `:210`
   reads `face.isUnsaved`, the identifier at `:205` reads `face.relativePath`); `BacklinksSection(title:relativePath:)`
   and `UnresolvedLinksSection(relativePath:)` (`VaultBrowser.swift:209`, `:216`); the category row reads
   `NoteDocument.frontmatter(in: note.text).foreignKeys`.
9. **`ModelSync`**: the fallback branch of `NoteTextView+Update.swift:43-44` calls `countCompare()` before
   `textView.string != text`.
10. **Diario**: the `didSet` checks `isLoaded` before it compares and counts each compare; `editorWrote(_:)` assigns
    without the compare (one flag read by the `didSet`) and runs `noteEdited()` and `scheduleSave()`; `DiaryView.swift`
    binds `Binding(get: { controller.prose }, set: { controller.editorWrote($0) })`.
11. **Run** the Task 4 suites, `IncrementalRestyleHostedTests` (the twin now compares the outline),
    `NoteOutlineTests`, `StylerGoldenTests`, then the full unit suite. SwiftLint on the touched files (CI does not run
    it): no new error.

### Task 6 — Tester: the call sites, the full suite, the "after" numbers and the Release profile (R-01, R-02, R-09, R-11)
Owner: tester
Files: build/pg406-release-sample.txt
Tests: StylerGoldenTests.swift, IncrementalRestyleHostedTests.swift, IncrementalStylerPropertyTests.swift, IncrementalRestyleSurfacesTests.swift, ModelSyncTests.swift, NoteTextViewUpdatePinsTests.swift, FoldStateOrdinalIndexStalenessTests.swift, NoteFoldingTests.swift, NoteOutlineTests.swift, OutlineMoveTests.swift, NoteFindTests.swift, DiaryControllerTests.swift, QuitCoordinatorTests.swift, VaultControllerWriteCatchUpTests.swift, EditorRestyleBudgetTests.swift, EditorUpdatePathBudgetTests.swift, UpdatePathCounterTests.swift
Signatures:
- scripts/editor-restyle-bench.sh — `--runs 9 --update`, then `--large-only --runs 3 --update`
- the large counter run — `TEST_RUNNER_RESTYLE_BUDGET_200KB=1 TEST_RUNNER_RESTYLE_BUDGET_1MB=1 xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests/UpdatePathCounterTests test`
- the Release profile run — `TEST_RUNNER_RESTYLE_BUDGET_UPDATE=1 TEST_RUNNER_RESTYLE_BUDGET_1MB=only TEST_RUNNER_RESTYLE_BUDGET_RUNS=30 xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -configuration Release -derivedDataPath build/pg401-gates-dd ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO -only-testing:PergamenumTests/EditorUpdatePathBudgetTests test`
- the sample — `sample <pid> <seconds> -file build/pg406-release-sample.txt`
Red: no

**Update tests and call-sites asserting the old behaviour.** The staleness rule: `OpenNote`'s equality, the dirty
flag's meaning, `OutlineInputs`, `OutlinePane`'s inputs and three views' inputs are observable contracts. The grep
was run on `93c17096`:

- `hasUnsavedChanges`: 84 lines in 23 test files. The note-buffer ones are in `CloseTabRequestTests`,
  `VaultWriteOrderingBatch3Tests`, `QuitSaveTests`, `VaultControllerWriteCatchUpTests`, `NoteHistoryTests`,
  `VaultControllerLandedChangeTests`, `VaultControllerExternalDeletionTests`, `QuitGapTests`,
  `QuitCoordinatorTests`, `VaultSwitchTests`, `NoteTabTests`, `TabSaveTests`, `VaultTests`, `QuitVaultSwitchTests`,
  `ColumnCloseTests`, `NoteTabGestureTests`, `VaultControllerMoveNoteTests`, `VaultControllerReconcileTests`;
  `CardFoldTests`, `NoteSaveIndicatorTests` and the three `Workspace*` files read other types' flags and are
  unaffected. Each reads clean after a save, a catch-up or an open, which link at once (ADR-0095 §D3); the one that
  reads clean after an undo back was restated in Task 2.
- `OpenNote(` constructions: 46 in 22 test files, compiling unchanged through the explicit `init`.
- `OutlineInputs` and `OutlinePane(`: item 12, restated in Task 4; `NoteTextViewUpdatePinsTests.swift:67` unchanged.
- `BacklinksSection(` and `UnresolvedLinksSection(`: `VaultBrowser.swift:209`, `:216` only. `NoteTabChip(`:
  `NoteTabBar.swift:46` only.
- `closingDelimiterIndex(in:)`: the seven callers of item 15, unchanged.
- `foldedOrdinals(ofOffsets:in:)` stays (the fresh path, `FoldStateOrdinalIndexStalenessTests`).
- **Any red is diagnosed first.** It is restated only with its reason written into ADR-0095, never disabled or
  weakened. The golden corpus, the hosted twin and the property tests are never restated.

**R-09.** Run `StylerGoldenTests` (byte-identical), then the files in `Tests:`, then the **full unit suite**
(`.claude/test-cmd`): a change of `OpenNote`'s equality can turn tests red in modules that only hold a tab. Then
`git diff --stat main -- Tuist/Package.swift Project.swift` is empty (no dependency, no manifest change).

**The "after" numbers (R-01, R-02).** On the development Mac, nothing else building, the two bench commands of
Task 1. Report both outputs verbatim, the fifth table included, and the counter values `UpdatePathCounterTests`
read at 200 KB and 1 MB through the large counter run above.

**The Release profile (R-11's evidence, not its verdict).** Run the Release command above in the background; when
the test host is up, attach `sample` to it and say which rows the window covered. Keep the samples under the
keystroke and the forced update; report TextKit's terms, then each app-owned term with its share, and say whether
any frame under SwiftUI's update (`AGGraphSetOutputValue`, a view's `==`, a body) still reads the whole note
(`_stringCompareSlow`, `NoteOutline.entries`, `NoteDocument.parse`, `components(separatedBy:)`). Name every other
app-owned term the profile shows as it appears.

### Task 7 — Coder: the ADR's numbers and pointers, the index, the ledger and the gates (R-01, R-11, R-12, R-13)
Owner: coder
Files: docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md, docs/adr/0094-an-edit-moves-a-step-not-every-offset-below-it.md, docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md, docs/adr/0073-quit-reviews-unsaved-notes.md, docs/adr/INDEX.md, CLAUDE.md, Tests/RestyleBudgetSupport+Update.swift, Tests/EditorUpdatePathBudgetTests.swift
Tests: EditorUpdatePathBudgetTests.swift, RestyleBudgetSupport+Update.swift
Signatures:
- RestyleBudget.updateCeilings — `static let updateCeilings: [Case: Double]`
- scripts/adr-index.py — `--check` exits 0
- scripts/check-adr-references.py — exits 0 after `git fetch origin`
Red: no

1. **ADR-0095 "Measured" (R-01, R-12).** A section after D11: the six update rows and the editor-only rows, before
   (Task 1) and after (Task 6), the share each adds, the counter values, the Mac, the OS, the Xcode and the
   configuration; the Release profile's table and the terms it names. Debug numbers include the counters'
   increments; the Release profile does too, at one increment per event.
2. **Pointers, one line each; history is not rewritten (R-12).**
   - ADR-0094 §D9 and its "Ledger entries" first bullet: "What SwiftUI does after the write is removed by ADR-0095;
     `ModelSync` is unchanged."
   - ADR-0073, implementation notes, departure 15: "Decided on the exact answer since ADR-0095 §D3
     (`differsFromSaved`); `hasUnsavedChanges` is a mark that clears at the pause."
   - ADR-0091 §D6, after its holder tables: "The outline is a holder since ADR-0095 §D6, shifted and spliced by
     this section's rule and rebuilt by §D8's kill switch."
3. **Indexes.** `docs/adr/INDEX.md` gets ADR-0095's summary line in its own format, after ADR-0094's. `CLAUDE.md`'s
   `## ADR index` holds the line `scripts/adr-index.py` prints, pasted with the docs PR; here it is only checked.
   `scripts/adr-index.py --check` and `scripts/check-adr-references.py` pass after `git fetch origin`.
4. **G-ceiling-406 (R-01), HITL.** Put the six update rows, their editor-only rows and the shares in front of the
   person, with ADR-0095's Gates proposal (20 ms on the share, a ceiling on the total like PG-401's). Write
   `RestyleBudget.updateCeilings` only with the values they give, and assert them in
   `aKeystrokeThroughSwiftUIsUpdateIsPrinted` for the rows that run. If the person puts the ceiling on the share,
   the test measures the editor-only row of the same case in the same run (the shape of
   `aKeystrokeInTheMiddleStaysUnderItsCeiling`) and asserts the difference. Record the answer in ADR-0095's Gates.
5. **Ledger entries (the SPEC's third open item).** Through `/project-tasks`, never by editing `TODO.md` by hand:
   each app-owned term Task 6's profile names that ADR-0095 does not remove, its ID written into ADR-0095
   "Ledger entries". If `/project-tasks` cannot be run from the building agent, say so in ADR-0095 and leave the
   filing to the person at the merge gate.
6. **G-hand-405, repeated (R-11), HITL, the person on a Release build.**
   - Build with `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -configuration Release
     -destination 'platform=macOS' -derivedDataPath build/pg406-release-dd build`.
   - Open it with `open -n` on a throwaway vault through `-recentVaults '("<path>")'`, holding the 1 MB fences note
     (`RestyleBudget.syntheticNote`).
   - Hand over R-11's checklist verbatim (type at the end and in the middle, Enter, a wrapping sentence, Cmd+Down,
     scroll to the end, click low in the pane, undo and redo, an IME composition, near the top then at the end
     three times), plus a `sample` of the process while typing.
   - The verdict goes into ADR-0095's Gates and, as a dated line, under ADR-0094's G-hand-405 bullet
     (`0094-…md:570-585`), which records the not-passed run (R-13's second half).
7. **PG-406 (R-13).** Closed by the code PR: `Closes #990` in its body and no other closing keyword; the ledger
   entry closed through `/project-tasks` at the merge.
8. **The number, again.** `git fetch origin`, then `git ls-tree origin/main docs/adr/`, and every branch about to
   merge (`docs/spec-pg-387-n4-birth-of-note` among them). If `0095` was taken, renumber (see the header).

## Risks & HITL gates

- **R-01's 20 ms cannot hold for the total at 1 MB (user decision).** The editor-only keystroke alone is 53 ms
  Debug and 55 ms Release at 1 MB, about 94% TextKit's (`PG-404`, ADR-0094 "Measured after"). The proposal: 20 ms
  on the share the update path adds, ceilings on the total like PG-401's. Decided at PLAN APPROVAL or at
  G-ceiling-406; nothing in Tasks 1 to 6 depends on the answer.
- **The pause interval (user decision).** 500 ms proposed (ADR-0095 §D4).
- **Diario's reading (user decision).** `editorWrote(_:)` makes an editor write of identical characters schedule a
  save of identical bytes (ADR-0095 §D9). The alternative is to keep Diario's compare and file a ledger entry.
- **The perimeter reading (user decision).** Items 2 to 6 of "What reading the tree added" are taken in under the
  Perimeter decision. If the person reads it more narrowly, the dropped items get ledger entries in Task 7 step 5
  and their source guards leave Task 4.
- **R-10's premise.** Oggi and Diario build `NoteTextView` directly (item 7). The plan delivers the requirement's
  behaviour and names the inaccuracy; the SPEC's wording is the person's to correct.
- **R-13's second half** is read as ADR-0094's G-hand-405 bullet (the only record of the not-passed run;
  `TODO.md`'s PG-406 entry names it as a blocker and closes with the PR).
- **ADR-0094's ledger labels collide with `TODO.md`.** Its "Ledger entries" call the transclusion scan "PG-407" and
  the far caret jump "PG-408" while saying none was filed; `TODO.md`'s `PG-407` and `PG-408` are two test flakes
  (`AttachmentChipMenuTests.swift:127`, `QuickLookFocusTests.swift:245`). Not this plan's to fix silently: if the
  person agrees at PLAN APPROVAL, Task 7 step 2 relabels the two bullets and files the open caret-jump term through
  `/project-tasks`.
- **Two ADR-0095 drafts in the tree.** Another writer produced
  `docs/adr/0095-a-keystrokes-update-compares-a-revision-not-the-note.md` at the same time, and was still changing
  it while this plan was written. The person keeps one; the other is removed by the person or the orchestrator,
  never by an agent of this plan.
- **First hosted `EditorColumnView`.** Its environment may need more than the four objects named (the column's
  subviews read `\.theme`, `VaultController`, `Navigation`, `CommandActions`, `ShortcutStore`; `ThemeEngine` and
  `PraticheController` are read only by the sidebar and the inspector). `EventKitStore()` has a test precedent.
  If forcing SwiftUI's update needs a run-loop turn, the measured interval includes it; Task 1 says which.
- **Mutating `rows` inside `updateNSView`.** A rebuild during a note switch reassigns an observed property during a
  view update; Task 5 step 4 says what to do if SwiftUI reports it.
- **The outline's fences and body start come from the restyle's map.** If the property test finds a divergence
  from `NoteOutline.entries(in:)` (a frontmatter whose lines look like a fence), the fix is the splice's input, not
  the oracle.
- **The pause costs a compare per dirty tab.** Up to the first difference, on the main thread, every pause while a
  tab is dirty: about 37 ms for a whole 1 MB note in Debug at worst (ADR-0094's measurement of the same compare).
- **Bodies that grow with the vault.** Every keystroke invalidates every view reading `vault.columns`: the note list,
  the inspector (backlinks, history dates, `vault.backlinkRows`), the menus, Diario's `noteTitles` map. Their cost
  grows with the vault, not the note; they are filed only if Task 6's profile or G-hand-405 names them.
- **SwiftLint limits.** The coordinator file is at 923 of 1000 lines and its class body is near
  `type_body_length`: one stored property in the class, everything else in `NoteTextView+Outline.swift`.
  `VaultController.swift` (455) takes stored properties only. CI does not run SwiftLint; the coder runs it on the
  touched files.
- **The Release test build.** Task 6's profile compiles the test bundle in Release; the counters compile in every
  configuration, so no `#if DEBUG` symbol is reached from a test.
- **ADR number collision.** `0095` is free today; re-check before each merge (Task 7 step 8).
- **HITL gates:**
  - PLAN APPROVAL: this plan, ADR-0095, which of the two ADR-0095 drafts survives, the R-01 reading, 500 ms, the
    Diario reading, the perimeter reading, the PG-407/PG-408 relabel;
  - commit and push of the docs branch and of the code branch;
  - G-ceiling-406 (Task 7 step 4);
  - G-hand-405 on Release (Task 7 step 6);
  - the merge of each PR, after the ADR number re-check.

  No schema, deletion or deploy step. No external resource is needed: no network, no account, no new dependency,
  no environment variable beyond the bench's own switches.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

## Build result (2026-10-13)

BUILD · DONE WITH WARNINGS
Files: 79 changed (9 new Sources, ADR-0095 new, tests new or restated); Project.swift and Tuist/Package.swift unchanged
Tests: PergamenumTests green, 6720 tests in 414 suites, 5 known issues (R-15 harness, theHarnessWindowRefusesFocusAndEveryCallThatWouldShowIt); golden corpus (119 cases) identical
Review: sonnet, safe; opus, safe (4 rounds, no BLOCKER or MAJOR in any)
Coverage:
STALE-WAIVER	R-12
STALE-WAIVER	R-13
spec-coverage: STALE-WAIVER — a (no-test: …) exemption is stale: the id is mentioned in a test file the plan names, inside a pin carrying the plan's own slug when the plan writes one, so the exemption protects nothing; delete the clause from the SPEC (not auto-repaired)
Deferred: 0
Dropped: 7 (fix-hunk 2, nit 2, unlocated 1, post-sweep 2)
Dispatch: Round 0 (red): tester — Task 2, tester — Task 4
Dispatch: Round 1: debugger — keepLocalVersion settle (VaultController+Editing.swift:169) (reviewer: sonnet); coder — 7 local MINOR fixes
Dispatch: Round 2: coder — registry test for addColumn, ADR-0095 D3/D4 rewording, footer fallback to a fresh store, gate wording (reviewer: sonnet, opus)
Dispatch: Round 3 (sweep): coder — 7 in-diff candidates and C1
INFO: review escalated, size: 79 changed files, threshold 20
INFO: Task 1 (tester, green) ran alone before the red phase, on the old code, as the plan orders (R-01 "before" numbers)
INFO: Task 7 (coder) dispatched apart from Tasks 3 and 5: it consumes Task 6's output, and its steps 4, 6 are human gates (G-ceiling-406, G-hand-405)
WARN: Task 6 closed without the "after" benches, the large counter run, the Release profile and the "before" re-take: machine saturated (load 47), person's decision on 2026-10-13; the Task 1 "before" numbers stay upper bounds from a loaded machine
WARN: coverage reports a stale waiver on R-12 and R-13 in SPEC.md, not auto-repaired
WARN: sweep dropped two findings it could not fix: CompletingTextView.swift:272 (a guard breaks CompositionCompletionPanelTests) and HostedViewSupport.swift:197 (Swift Testing limit, PG-201)

```text
TREE	93396ab0817bf6e2de93985823b14abae0be8e6c
FIX	local	**MINOR** [wrong-behaviour] Sources/App/VaultController+Editing.swift:169 — keepLocalVersion on a .deleted conflict sets savedText to "" which draws a new savedRevision; with an already empty buffer the mark reads dirty while the texts are equal and no pause is scheduled, so the dot and Save chip stay on until the next keystroke. Fix: call tab.note.settleUnsavedMark() right after the assignment. (reviewer: sonnet)	debugger
FIX	local	**MINOR** [other] Sources/App/VaultController.swift:334 — close() replaces columns with a fresh EditorColumn but leaves outlineStores keyed by the dead column ids (same leak class as VaultController+VaultSwitch.swift:85, second site). Fix: clear outlineStores in close() and in the vault switch through one helper beside dropOutlineStore. (reviewer: sonnet)	coder
FIX	local	**MINOR** [other] Tests/UnsavedMarkSourceGuardTests.swift:16 — decisionFiles omits Sources/App/VaultController+NoteBirth.swift, whose two decision sites (lines 105 and 152) this diff moved to differsFromSaved, so a regression there would pass the guard. Fix: add the file with 2 sites. (reviewer: sonnet)	coder
FIX	local	**MINOR** [other] Sources/App/VaultController+VaultSwitch.swift:85 — A vault switch replaces every column without dropping its outline store, leaking one OutlineStore per column. Fix: outlineStores.removeAll() beside the columns reset, plus a registry test for the switch. (reviewer: opus)	coder
FIX	local	**MINOR** [other] Sources/App/PauseScheduler.swift:10 — PauseScheduler.cancel() has no caller, so a pending unsaved-mark settle survives close() and switchVault(to:). Fix: cancel the pause where the vault is closed or switched, or drop the requirement. (reviewer: opus)	coder
FIX	local	**MINOR** [plan-deviation] Tests/OutlineStoreTests.swift:97-106 — The per-seed non-vacuity floor was weakened from half the steps to a quarter with its reason only in the test, while the plan requires a restated test's reason in ADR-0095, which records none. Fix: add a Restated tests entry to ADR-0095, or retune the seeds so the original floor holds. (reviewer: opus)	coder
FIX	local	**MINOR** [plan-deviation] Sources/Features/Editor/NoteTextView+Update.swift:60 — The added modelSync.wrote(text) is outside the plan's step and contradicts ADR-0095 D8's claim that ModelSync is untouched, though it is sound. Fix: record the new call in D8 or remove it. (reviewer: opus)	coder
FIX	local	**MINOR** [other] Sources/Features/Editor/NoteListPane+Footer.swift:54 — The outline-store registry is mutated from inside a view body (also EditorColumn+Text.swift:166), against the pure-body agreement. Fix: create a column's store where the column is created and read a non-mutating lookup in the body. (reviewer: opus)	coder
FIX	swept	**NIT** Sources/Features/Editor/NoteTextView+Transclusion.swift:29 — Comments still describe the deleted outlineRanges input (also FormattingTextView+Clicks.swift:161). Rewrite them to name the outline store. (reviewer: opus)
FIX	swept	**NIT** Sources/Features/Editor/OutlineMap.swift:122 — level(ofEntry:)'s doc says level 1 for an embed with no heading above, while it answers 2. Reword to match items. (reviewer: opus)
FIX	local	**MINOR** [other] Tests/OutlineStoreRegistryTests.swift:36 — No test proves a column-creation door registers the store a view body reads: the split tests create stores through outlineStore(forColumn:) which creates on demand, so removing the registration in addColumn still passes. Fix: after splitEditor() assert registeredOutlineStore(forColumn:) is non-nil for both columns and outlineStores.count == 2 before any creating call. (reviewer: sonnet, opus)	coder
FIX	local	**MINOR** [other] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:147 — D3 says keepLocalVersion's savedText assignment leaves the mark on, but it now calls settleUnsavedMark() and clears the mark for an empty buffer; the line citation :170 is also stale. Fix: reword to say it assigns "" then settles, staying dirty only for a non-empty buffer. (reviewer: sonnet)	coder
FIX	local	**MINOR** [other] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:153 — The D3 reader table and the 93c17096 baseline omit the VaultController+NoteBirth.swift decision sites (:105 sourceIsDirty, :152 settledSession) that now read differsFromSaved and are in the guard list. Fix: add a note-birth row reading exact and re-date the baseline to 32cd8ed2. (reviewer: sonnet)	coder
FIX	swept	**NIT** docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:185 — D4 does not record that close() and switchVault(to:) cancel typingPause. Fix: add one sentence. (reviewer: sonnet)
FIX	local	**MINOR** [other] Sources/Features/Editor/NoteListPane+Footer.swift:19 — The footer drops the whole INDICE section when the focused column has no registered store, so a registry regression reads as a note without headings. Fix: fall back to OutlineStore(text: note.text) instead of hiding the pane. (reviewer: opus)	coder
FIX	local	**MINOR** [other] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:526 — The plan-approval gate is still written as an open choice (500 ms, the Diario reading) though the code implements one branch of each. Fix: record the answer and its date in that bullet, as section C1 does for G-hand-405. (reviewer: opus)	coder
FIX	swept	**NIT** Sources/Features/Editor/NoteListPane+Footer.swift:59 — describing(_:) relies on a comment to stay out of view bodies. Make it a function taking the note so the constraint is structural. (reviewer: opus)
DROP	fix-hunk	**MINOR** [style] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:251 — settleBaseline is cited as :762, this build's line (32cd8ed2 has it at :760), while the neighbouring :823 is the 32cd8ed2 line; the section mixes two trees. Fix: cite :760 or say "in this build". (reviewer: sonnet, opus)
FIX	swept	**MINOR** [style] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:222 — D5 says closingDelimiterIndex(in:) gains an overload, but the code adds a differently labelled sibling closingDelimiterIndex(inLines:) and its own comment says it avoided an overload. Fix: reword the ADR to match. (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [style] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:124 — The claim of 46 OpenNote constructions in 22 test files does not reproduce: 32cd8ed2 has 15 in 10 files. Fix: recount and restate, or drop the number. (reviewer: sonnet)
FIX	swept	**NIT** docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:83 — TodayView.swift:215 is the enclosing if-let; the NoteTextView( construction is at :216. (reviewer: sonnet)
FIX	swept	**NIT** Tests/UnsavedMarkSourceGuardTests.swift:10 — The header comment still names the baseline 93c17096 while the ADR was re-dated to 32cd8ed2; update the commit reference. (reviewer: sonnet)
DROP	nit	**NIT** docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:149-150 — The sentence mixes bases: :170 is baseline-relative while :173 for settleUnsavedMark matches neither commit (175 in the working tree). Fix: cite both from one commit. (reviewer: opus)
DROP	post-sweep	**MINOR** [other] Sources/Features/Editor/CompletingTextView.swift:272 — refreshCompletion orders the completion panel front even when the parent window is not visible; any hosted test typing #, /, : or [[ puts the panel on screen, only UpdatePathFixture's check blocks it (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Tests/HostedViewSupport.swift:197 — refusals arriving after tearDown are attributed to no test (known PG-201 limit) (follow-up: coder)
DROP	unlocated	**MINOR** [other] mktemp -t template is not substituted on this macOS, the log is named editor-restyle-bench.XXXXXX.<random> (follow-up: tester)
FIX	swept	**MINOR** [other] Tests/UpdatePathSourceGuardTests.swift:10 — comment still says the guard was checked against the tree at 93c17096 (stale base) (follow-up: coder)
FIX	fix-hunk	**MINOR** [other] docs/adr/0095-what-follows-a-keystroke-compares-a-revision-not-the-note.md:69 — Stale line pointer: foldedOrdinals(ofOffsets:in:) is cited as (:159), a 93c17096 number; at 32cd8ed2 the call is EditorColumn+Text.swift:166. Fix: write (:166). (reviewer: opus)	coder
DROP	nit	**NIT** Tests/UnsavedMarkSourceGuardTests.swift:10 — The header calls the list "plan item 8's decision list" though it also holds the two VaultController+NoteBirth.swift sites item 8 never named. (reviewer: opus)
```
