**Requirement set:** `docs/archive/specs/scoped-layout-followup.SPEC.md` (root `SPEC.md` while this was built)

# What is left of the per-keystroke cost after the per-paragraph restyle (PG-401, after #971)

- **SPEC:** root `SPEC.md`, "What is left of the per-keystroke cost after the per-paragraph restyle",
  Status Approved (2026-10-11), R-01 to R-17. Its `## Decisions`, `## Constraints` and `## Test seams`
  are settled input, and no task below reopens them. `/ship` archives it under `docs/archive/specs/`.
- **ADR outcome: new ADR**, `docs/adr/0093-a-keystroke-lays-out-what-it-changed.md`, written `planned`.
  - It extends ADR-0091 (§D2, §D8, §D9), amends ADR-0091 §D10's layout half, and records the amendment
    to ADR-0082 §D7: reopened and scoped, same invariant (R-16).
  - It keeps ADR-0082 §D6, ADR-0001 §D1, ADR-0074 §D1 and §D2, ADR-0081 §D4, and does not touch
    ADR-0077 §D1.
  - **Number.** `0093`, because `0092` is held by the unpublished file the SPEC's last constraint names.
    On 2026-10-11 `git fetch origin` left `origin/main` at `3070555b`, whose highest ADR is `0091`, and no
    ref nor the one worktree inside this repository holds `0092` or higher. **Re-check the number right
    before the docs PR merges and again before the code PR merges** (`docs/adr/README.md` rule 1): if
    `0093` is taken by then, renumber the file, its heading, every reference to it in this plan and in
    the code comments, and the index lines.
  - It flips to `accepted` in the first docs change after the code PR merges (rule 2).
- **Governing ADRs, registered and not reopened:** ADR-0091 (the incremental restyle, its storage
  delegate, its kill switch, its surfaces, its bench); ADR-0082 §D6 (the scoped renumber in the
  keystroke's undo step), §D7 (withdrawn 2026-10-10, reopened here), §D9 (the bench); ADR-0074 (pass
  order, each controller owns its state); ADR-0081 §D4 (the stored paragraph keeps its length); ADR-0001
  §D1 (`Sources/Core` is Foundation only); ADR-0045 (a widened `private` carries one comment naming its
  reader).
- **Baseline.** Branch `docs/spec-scoped-layout-followup` at `3070555b`, which is `origin/main`.
  `SPEC.md`, this plan and ADR-0093 are untracked.
- **Delivery: one code PR** on `feature/scoped-layout-followup`, cut from `main` after the docs branch
  lands, in one `/build` session.
  - If the context runs short, split after Task 4: Tasks 1 to 4 are a green, self-contained change (the
    real edit path, the delegate and the layout record). Tasks 5 and 6 (the renumbering) depend on none
    of it but the map.
  - Run `tuist install` and `tuist generate --no-open` before the first task, and again after every
    task that adds a file.
  - PR bodies say `refs PG-401` and `refs #967`, never a closing keyword, negated or not.

## SPEC decisions registered (settled, not reopened)

- **The layout debt is its own record**, fed by the storage's processed edits, owing everything or a
  set of ranges. The three ways a fragment loses its layout (a processed edit, a whole-document
  invalidation, a new container width) each reach it; a fourth must go through it. Laying out only the
  caret's fragment and the viewport stays rejected.
- **It hears in the second callback of the delegate #971 installs.** A second delegate object was
  rejected.
- **One door for every whole-document invalidation** of a note editor (fold, transclusion, view-block
  height). Teaching the record by comment was rejected.
- **The card is untouched.**
- **A foreign delegate means whole-note layout**, and dismantle clears the delegate. Waiting for a root
  cause was rejected.
- **A launch argument restores the whole-note layout**, shaped like ADR-0091 §D8's switch.
- **The windowed renumbering starts at a line the map vouches for**, with its fence parity, and reads
  forward until the touched runs have ended. A fixed number of lines was rejected.
- **Undo, redo and composed text are verified through the real operation first**, then fixed through
  undo-manager notifications and a composed-text override only if the result differs.
- **Acceptance: asserted up to 200 KB, measured at 1 MB**; the ceilings are the person's at a gate.
- **One build, one Release hand-check pass** covering #971 too.
- **The structural bench rows are printed, not asserted.**

## What reading the tree added (`3070555b`)

1. **The only whole-document invalidations** under `Sources/Features/Editor` are the three the SPEC
   names: `NoteTextView+Folding.swift:68-70`, `NoteTextView+Transclusion.swift:195-197`,
   `NoteTextView+ViewBlocks.swift:331` (`git grep invalidateLayout`). The card's is
   `CardTextView+Fold.swift:42-44`. `Sources/Features/Today` and `Sources/Features/Diary` have none.
   The comment at `NoteTextView+ViewBlocks.swift:320` names the call, so the guard skips comment lines.
2. **`growToFitTheText`'s callers:** `NoteTextView+Coordinator.swift:275` (`textDidChange`), `:751`
   (the view-block refresh hand-off), `NoteTextView+Update.swift:79` (`runPasses`), and the deferred
   relayout at `NoteTextView+ViewBlocks.swift:332`. Its doc comment (`:617-626`) states the old fact.
3. **A foreign delegate also breaks the restyle, not only the layout.** With the delegate replaced, the
   coordinator records nothing, `applyStylingIfNeeded` (`:234-250`) sees no pending decision and an
   unchanged edit count, and skips. ADR-0093 §D5 closes it with the same guard; it is filed under R-02.
4. **`dismantleNSView` (`NoteTextView.swift:290-297`) leaves the storage's delegate set.** It runs on
   every pane switch.
5. **The fixture never runs `pushInputs`,** so `coordinator.undoManager` is nil in every hosted test
   but `NoteEditorTeardownTests`, which sets it by hand (`:84`). The fixture gains that one line.
6. **The fixture's binding is `.constant(text)`** (`ScrolledEditorFixture.swift:28`), so a binding write
   cannot be seen. A recording binding is needed for R-03's "the binding value".
7. **`textDidChange` styles before SwiftUI runs `updateNSView`** (`:255`); `runPasses` then skips. A
   real-path test therefore sees the restyle on the incremental editor without any pass, as long as
   `textDidChange` ran.
8. **During an undo the renumber gets no recorded range** (`NoteTextView+ListEditing.swift:109-112`) and
   uses the whole-text form, inside the undo. A replay hook runs after the undo has finished, so it must
   not renumber (ADR-0093 §D7).
9. **`ListContinuation.swift` is 399 lines** (SwiftLint `file_length` warns at 400). The scoped form
   (`:321-399`) moves into the new `ListContinuation+Window.swift` with its windowed sibling, and the
   helpers it reads in the main file widen from `private` to internal, one ADR-0045 comment each.
10. **`NoteTextView+Coordinator.swift` is 886 lines** (error at 1000) and the class body sits near
    `type_body_length`. The two new stored properties go in the class body with one-line doc comments;
    every new method goes in an extension file.
11. **`StructureMap.Line` is built in three places only**, all in `StructureMap.swift` (`:144`, `:192`,
    `:199`); no test constructs one.
12. **The map is the current text's when the renumber runs**: `RestyleScope.record` applies every edit
    to it as the storage reports it (`RestyleScope.swift:39-56`); only a wholesale replace leaves it
    stale.

## Requirement coverage

| Requirement | Tasks |
| --- | --- |
| R-01 | 1, 2 |
| R-02 | 3, 4 |
| R-03 | 1, 2 |
| R-04 | 1, 2 |
| R-05 | 3, 4 |
| R-06 | 3, 4 |
| R-07 | 3, 4 |
| R-08 | 3, 4 |
| R-09 | 3, 4 |
| R-10 | 5, 6 |
| R-11 | 5, 6 |
| R-12 | 5, 6 |
| R-13 | 7 |
| R-14 | 7, 8 |
| R-15 | 7 |
| R-16 | 7, 8 |
| R-17 | 8 |

## Order

1. The real edit path, verified first and red (Task 1), then the dismantle fix and only the hooks the
   verification asks for (Task 2).
2. The layout record, its door, its switch and the delegate guard: red (Task 3), green (Task 4).
3. The windowed renumbering: red (Task 5), green (Task 6).
4. The restated tests, the structural rows and the benches (Task 7).
5. The ADR's numbers, the pointers, the indexes, the ledger, the gates, the ADR number re-check
   (Task 8).

### Task 1 — Tester: undo, redo, composed text and dismantle on the real path, red first (R-01, R-03, R-04)
Owner: tester
Files: Tests/RealEditPathTests.swift, Tests/ScrolledEditorFixture.swift, Tests/NoteEditorTeardownTests.swift
Tests: RealEditPathTests.swift, NoteEditorTeardownTests.swift, IncrementalRestyleHostedTests.swift
Signatures:
- BoundText — `@MainActor final class BoundText { private(set) var value: String; private(set) var writes: Int; init(_ value: String); var binding: Binding<String> { get } }`
- ScrolledEditorFixture.init — init(text: String, width: CGFloat = 900, height: CGFloat = 700, hidesMarkup: Bool = true, readableWidth: Bool = true, theme: Theme = .emergency, queries: ViewQuerySource? = nil, vault: NoteTextView.VaultInputs? = nil, revealsInlineSpans: Bool = false, forcesFullRestyle: Bool? = false, bound: BoundText? = nil)
- ScrolledEditorFixture.bound — let bound: BoundText?
- RestyleTwin.rich — static func rich(text: String = RichNote.text, bindsIncremental: Bool = false) async throws -> RestyleTwin
- RestyleTwin.realUndo — func realUndo()
- RestyleTwin.realRedo — func realRedo()
- RestyleTwin.realEdit — func realEdit(_ body: (ScrolledEditorFixture) -> Void)
- RealEditProbe.line — static func line(op: String, didChange: Bool, undoNotice: Bool, storageEdits: Int, styled: String) -> String
- NoteTextView.dismantleNSView — static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator)
- NoteTextView.Coordinator.hasUnstyledEdits — var hasUnstyledEdits: Bool { get }
- NoteTextView.Coordinator.undoManager — weak var undoManager: UndoManager?
Red: yes

Everything here is test code; no source file changes in this task.

**The fixture.**

- `BoundText` holds the value and counts writes. `binding` is `Binding(get:set:)` over it.
- `ScrolledEditorFixture.init` gains `bound:`. Given one, the `NoteTextView` is built with
  `bound.binding` instead of `.constant(text)`. Every existing caller passes nothing and is unchanged.
- After `window.contentView = scrollView`, the fixture sets `coordinator.undoManager =
  textView.undoManager`, the one line `pushInputs` runs in the app (`NoteTextView+Update.swift:14`).
  The window's undo manager is what `textView.undoManager` resolves to.
- `RestyleTwin.rich(bindsIncremental: true)` gives the incremental editor a `BoundText`; the default
  keeps every existing caller as it is.
- `realEdit`, `realUndo` and `realRedo`:
  - give the **full** twin the operation, then `fold(heading:)` and `runPasses()` by hand. It is the
    oracle, exactly as `edit`, `undo` and `redo` do today;
  - give the **incremental** editor the operation and then only what SwiftUI would run. If
    `bound.writes` moved (the app's binding write in `textDidChange`), it gets `fold(heading:)` and
    `runPasses()`, the `updateNSView` that write schedules. If it did not move, it gets nothing. A
    missing notification therefore leaves it unstyled, and the test red;
  - keep today's undo grouping (`groupsByEvent = false`, one group per `realEdit`).

**`RealEditPathTests.swift` (R-03), on `RestyleTwin.rich(bindsIncremental: true)`.**

- **Undo**: type a character in the prose, then a renumbering keystroke in the list (the existing
  `"3"` over the first digit), then `realUndo()` twice; then **redo** with `realRedo()` twice.
- **Composed text**: `setMarkedText("ñ", …)` at a caret in "prosa", then `setMarkedText("ñé", …)` over
  `markedRange()`, then commit with `insertText("ñé", replacementRange: markedRange())`.
- After each operation, before any pass:
  - `bound.value == textView.string`;
  - `!coordinator.hasUnstyledEdits`.
- After the pass SwiftUI would run (none if the binding was not written):
  - text equal to the twin's;
  - `StorageComparison.firstDifference` is nil;
  - `twin.differences().isEmpty`;
  - the selection and, during composition, `markedRange()` and `hasMarkedText()` equal to the twin's.
- **One undo step**: after the renumbering keystroke, one `realUndo()` takes back the keystroke and
  its renumbering together, and one `realRedo()` puts both back.
- If the full comparison already holds before the pass, assert it there too; stronger is better.

**The probe (R-04's method).** Each real-path test prints one line per operation:

`real-edit-path op=<undo|redo|mark-set|mark-replace|mark-commit> did_change=<0|1> undo_notice=<0|1> storage_edits=<n> styled=<incremental|full|skipped|none>`

- `did_change`: an `NSText.didChangeNotification` observer on the incremental text view, added and
  removed by the test.
- `undo_notice`: observers on the undo manager's did-undo and did-redo notifications.
- `storage_edits`: an `NSTextStorage.didProcessEditingNotification` observer. It is a notification, so
  it leaves the storage's delegate slot alone.
- `styled`: the `restyleLog` delta.

**`NoteEditorTeardownTests.swift` (R-01).** Two tests beside the existing two, on a
`ScrolledEditorFixture`, whose first styling installs the delegate:

- `storage.delegate === coordinator` first; after `NoteTextView.dismantleNSView(fixture.scrollView,
  coordinator:)`, `storage.delegate == nil`.
- With a foreign `NSTextStorageDelegate` object installed before the dismantle, the dismantle leaves it
  in place.

**Expected red:** the dismantle test is red. The R-03 tests are red exactly when the real path misses a
notification. Report which ones were red and paste the probe lines: they are R-04's evidence.

### Task 2 — Coder: dismantle clears the delegate, and only the replay hooks Task 1 asks for (R-01, R-03, R-04)
Owner: coder
Files: Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+EditReplay.swift, Sources/Features/Editor/CompletingTextView.swift, docs/adr/0093-a-keystroke-lays-out-what-it-changed.md
Tests: RealEditPathTests.swift, NoteEditorTeardownTests.swift, IncrementalRestyleHostedTests.swift
Signatures:
- NoteTextView.dismantleNSView — static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator)
- NoteTextView.Coordinator.runEditPasses — func runEditPasses(in textView: NSTextView, renumbering: Bool)
- NoteTextView.Coordinator.replayEditIfUnstyled — func replayEditIfUnstyled(in textView: NSTextView)
- NoteTextView.Coordinator.undoManager — weak var undoManager: UndoManager? { didSet }
- CompletingTextView.onComposedTextChanged — var onComposedTextChanged: (() -> Void)?
- CompletingTextView.setMarkedText — override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange)
Red: no

**Always: the dismantle (R-01).** In `dismantleNSView`, after the undo purge: `if
textView.textStorage?.delegate === coordinator { textView.textStorage?.delegate = nil }`. Also remove
the undo observations below, if they exist.

**Only for an operation Task 1 found red (R-03), ADR-0093 §D7.**

- Move `textDidChange`'s body after its guard into `runEditPasses(in:renumbering:)`, in the new
  `NoteTextView+EditReplay.swift`. `textDidChange` calls it with `renumbering: true` and behaves
  byte for byte as before. The coordinator file must not grow past what the class body allows.
- `replayEditIfUnstyled(in:)` calls `runEditPasses(in:renumbering: false)` only while
  `hasUnstyledEdits` is true.
- **Undo and redo, if red:** `undoManager` gets a `didSet` that moves two block observers
  (`.NSUndoManagerDidUndoChange` and `.NSUndoManagerDidRedoChange`, object = the new manager, queue
  `.main`) from the old manager to the new one. They are stored `nonisolated(unsafe)` and removed in
  `deinit`, as `frameObserver` is (`NoteTextView+Coordinator.swift:128`). Each calls
  `replayEditIfUnstyled(in:)`.
  - The window's manager is shared with the sidebar's move-undo (ADR-0026 §D8). An undo there posts
    the same notification and finds nothing unstyled.
- **Composed text, if red:** `CompletingTextView` overrides `setMarkedText(_:selectedRange:replacementRange:)`.
  It calls `super`, then `onComposedTextChanged?()`. `NoteTextView.wire(_:to:)` sets the closure, weakly,
  to `replayEditIfUnstyled(in:)`, like the other closures there.
  - Do not touch the marked range or the selection. A restyle during composition must leave both as
    they are (SPEC edge case, pinned by Task 1).
- **If Task 1 was green for an operation**, write no hook for it. If all three were green, this task is
  the dismantle line alone, and `NoteTextView+EditReplay.swift` is not created.

**The ADR (R-04).** Fill "The real edit path (R-04)" in ADR-0093:

- per operation, the probe's fields;
- which hooks were installed, if any;
- the method: the fixture, the observers and the printed lines, quoted.

Green bar: Task 1's tests, `IncrementalRestyleHostedTests` and `NoteEditorTeardownTests`.

### Task 3 — Tester: the layout record, its door, its switch and the delegate guard, declared and red (R-02, R-05, R-06, R-07, R-08, R-09)
Owner: tester
Files: Sources/Features/Editor/NoteTextView+Layout.swift, Sources/Features/Editor/NoteTextView+StorageEdits.swift, Sources/Features/Editor/EditorRestyleSwitch.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Tests/LayoutDebtTests.swift, Tests/LayoutDebtHostedTests.swift, Tests/LayoutDoorGuardTests.swift, Tests/EditorRestyleSwitchTests.swift, Tests/IncrementalRestyleSurfacesTests.swift, Tests/IncrementalRestyleHostedTests.swift, Tests/ScrolledEditorFixture.swift
Tests: LayoutDebtTests.swift, LayoutDebtHostedTests.swift, LayoutDoorGuardTests.swift, EditorRestyleSwitchTests.swift, IncrementalRestyleSurfacesTests.swift, IncrementalRestyleHostedTests.swift, EditorGrowToFitScopeTests.swift
Signatures:
- LayoutDebt — @MainActor final class LayoutDebt { enum Owed: Equatable { case everything; case ranges([NSRange]) }; private(set) var owed: Owed; private(set) var log: LayoutLog; init() }
- LayoutDebt.hear — func hear(_ edit: StorageEdit, in storage: NSTextStorage)
- LayoutDebt.oweEverything — func oweEverything()
- LayoutDebt.invalidateWholeDocument — func invalidateWholeDocument(of textView: NSTextView)
- LayoutDebt.settle — func settle(_ textView: NSTextView, delegateIsCoordinator: Bool, forcesWhole: Bool)
- LayoutLog — struct LayoutLog: Equatable, Sendable { var whole: Int = 0; var ranged: Int = 0; var empty: Int = 0; var lastWholeReason: WholeReason?; var lastRanges: [NSRange] = [] }
- LayoutLog.WholeReason — enum WholeReason: Equatable, Sendable { case everythingOwed, widthChanged, foreignDelegate, lengthMismatch, killSwitch }
- EditorRestyleSwitch.layoutKey — static let layoutKey = "editorFullLayout"
- EditorRestyleSwitch.forcesFullLayout — static func forcesFullLayout(arguments: [String], defaults: UserDefaults) -> Bool
- NoteTextView.Coordinator.layoutDebt — let layoutDebt: LayoutDebt
- NoteTextView.Coordinator.forcesFullLayout — var forcesFullLayout: Bool
- NoteTextView.Coordinator.textStorage(_:didProcessEditing:range:changeInLength:) — nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int)
- NoteTextView.Coordinator.growToFitTheText — func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false)
- ScrolledEditorFixture.init — the parameter forcesFullLayout: Bool? = false, between forcesFullRestyle and bound
Red: yes

**Declarations with neutral bodies, never `fatalError`.**

- `LayoutDebt`, `LayoutLog` and `WholeReason` go in the new `NoteTextView+Layout.swift`. Their bodies:
  - `hear`, `oweEverything` and `settle` do nothing;
  - `invalidateWholeDocument(of:)` calls `invalidateLayout(for: documentRange)` and nothing else;
  - `owed` stays `.everything` and `log` stays empty.
- `EditorRestyleSwitch.forcesFullLayout` returns false.
- The coordinator gains `layoutDebt` and `forcesFullLayout`, the latter set from
  `forcesFullLayout(arguments:defaults:)` in `init`. One-line doc comments; the class body is near its
  SwiftLint limit.
- The `didProcessEditing` callback goes beside its twin in `NoteTextView+StorageEdits.swift`, with an
  empty body.
- `growToFitTheText` is **not** changed in this task: the record is not wired, so the existing suite
  stays green and the new tests are red.

**`LayoutDebtTests.swift`, the record alone, over a plain `NSTextStorage`.**

- Starts `.everything`. After `settle`, nothing is owed.
- `hear` a typed character: owes the edited range. A second edit after it shifts the first range by
  its delta.
- A deletion reports an empty range: it owes the joined paragraph (`paragraphRange(for:)`), never an
  empty range.
- Overlapping and adjacent ranges merge. A range covering the whole text becomes `.everything`.
- An attribute-only edit (delta 0) adds its range and shifts nothing.
- `oweEverything()` gives `.everything`.

**`LayoutDebtHostedTests.swift`, on `ScrolledEditorFixture` and `RestyleTwin.rich()`, driven through
`type`, `insertText`, `setSelectedRange`, `moveToEndOfDocument(_:)` and mouse events, as
`EditorGrowToFitScopeTests` does.**

- **R-05:** a long plain note and the rich note (it carries a table, a view block, an embed and a
  transclusion), `openLikeTheApp()`, then three keystrokes at the top:
  - a character;
  - a new paragraph;
  - an insertion that wraps the line.

  Repeat after `moveToEndOfDocument(_:)` and a keystroke there. After each keystroke's passes:
  - `layoutDebt.log.ranged` grew, which is what makes the test red until Task 4;
  - **no estimate**, by the witness `EditorGrowToFitScopeTests` already uses: the usage height and the
    last fragment's `y` do not change when the document range is then laid out. A fragment-counting
    probe cannot see reuse; this one can.
- **R-06:** a keystroke, `moveToEndOfDocument(_:)`, then a click about 60 pt above the bottom edge, as in
  `thePassesAClickRunsLeaveTheViewOnTheSameText`. The top of the view stays on the same text, and the
  caret lands at the character under the click. Also assert `log.ranged` grew.
- **R-07, owes the whole note exactly at:**
  - the first use of a coordinator;
  - a whole-text pass: a note switch through `textView.string =`, a theme change, an external change;
  - a fold change: `fold(heading:)` plus `runPasses()`;
  - a transclusion change: the resolver's generation moved, so the renditions change;
  - a view-block height change: `ViewBlockAttachment`'s measured height changed, then one main-actor
    turn;
  - a container width change: the scroll view's frame resized.

  Each is read off `log.lastWholeReason == .everythingOwed`, or `.widthChanged` for the width.
- **R-07, only the edited ranges after:**
  - a keystroke;
  - a reveal: the caret moved into a paragraph with markup;
  - an embed: the thumbnail rendition arrived;
  - a view-block per-paragraph edit: a keystroke in a fence body, which the restyle covers as the
    fence's lines.

  Each is read off `log.lastRanges`: inside the paragraphs that changed, widened by one character
  each side, never the note.
- **R-02:**
  - with the storage's delegate replaced by a foreign object, the next grow-to-fit lays out the whole
    note, with `lastWholeReason == .foreignDelegate`, and no height is an estimate;
  - with the delegate correct, it lays out only what is owed.
  - **The restyle half (ADR-0093 §D5):** with a foreign delegate, the next keystroke is restyled
    (`restyleLog.full` grew), and afterwards `storage.delegate === coordinator` again.
- **R-09:** with `forcesFullLayout` on, every settle is whole (`lastWholeReason == .killSwitch`), and
  the R-05 and R-06 assertions still hold, minus `log.ranged`.

**`LayoutDoorGuardTests.swift` (R-08).** The guard reads every `.swift` file under
`Sources/Features/Editor`, `Sources/Features/Today` and `Sources/Features/Diary`, through
`resolvedRepoRoot` as `UITestLaunchHarnessGuardTests` does.

- It skips lines whose first non-blank characters are `//`.
- It fails on any `invalidateLayout(` outside `NoteTextView+Layout.swift`, naming the file and line.
- It asserts it read at least as many files as there are today, so an empty listing cannot pass.
- Red now: three sites call it directly.

**`EditorRestyleSwitchTests.swift` (R-09):**

- `-editorFullLayout YES` and the key in a scratch defaults suite both read true; absent reads false.
- The two switches are independent.

**`IncrementalRestyleSurfacesTests.swift` (R-05, the surfaces):** a keystroke in the Oggi and the Diario
editors takes the ranged layout and leaves no estimate.

**`IncrementalRestyleHostedTests.swift`, platform pin:** a typed character reaches `didProcessEditing`
as its paragraph-widened range (ADR-0091 C4's `{10, 27}` shape), and a deletion as an empty range. Pins
the fact ADR-0093 §D2 rests on.

**`ScrolledEditorFixture`:** `forcesFullLayout:` set on the coordinator before the first styling, as
`forcesFullRestyle:` is.

### Task 4 — Coder: the record, the door and the scoped grow-to-fit (R-02, R-05, R-06, R-07, R-08, R-09)
Owner: coder
Files: Sources/Features/Editor/NoteTextView+Layout.swift, Sources/Features/Editor/NoteTextView+StorageEdits.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/EditorRestyleSwitch.swift, Sources/Features/Editor/NoteTextView+Folding.swift, Sources/Features/Editor/NoteTextView+Transclusion.swift, Sources/Features/Editor/NoteTextView+ViewBlocks.swift
Tests: LayoutDebtTests.swift, LayoutDebtHostedTests.swift, LayoutDoorGuardTests.swift, EditorRestyleSwitchTests.swift, IncrementalRestyleSurfacesTests.swift, IncrementalRestyleHostedTests.swift, EditorGrowToFitScopeTests.swift, EditorHeightTests.swift, NoteFoldingTests.swift, TransclusionLayoutTests.swift, ViewBlockRenderingTests.swift, ViewBlockHostStoreTests.swift
Signatures:
- LayoutDebt.hear — func hear(_ edit: StorageEdit, in storage: NSTextStorage)
- LayoutDebt.oweEverything — func oweEverything()
- LayoutDebt.invalidateWholeDocument — func invalidateWholeDocument(of textView: NSTextView)
- LayoutDebt.settle — func settle(_ textView: NSTextView, delegateIsCoordinator: Bool, forcesWhole: Bool)
- FoldController.init — init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate, layout: LayoutDebt)
- TransclusionController.init — init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate, layout: LayoutDebt)
- ViewBlockController.init — init(parent: @escaping () -> NoteTextView?, decorations: EditorDecorationDelegate, layout: LayoutDebt)
- NoteTextView.Coordinator.growToFitTheText — func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false)
Red: no

ADR-0093 §D1 to §D6, in this order:

1. **The bodies** of `LayoutDebt`, as §D1, §D2 and §D4 state them.
   - `hear` shifts the owed ranges with `StorageEdit`'s rule, then adds the range. An empty range
     becomes its paragraph; a whole-text range becomes `.everything`.
   - `settle` lays out:
     - the document range for any `WholeReason`: everything owed, a width change, a foreign
       delegate, a length mismatch, or the kill switch;
     - otherwise each owed range widened by one character each side, converted to an
       `NSTextRange` through the content storage;
     - otherwise nothing.

     Then it clears `owed`, records the width and logs.
   - The width is `textView.textContainer?.size.width`, the value `StylingInputs` already reads.
2. **Hearing.** The `didProcessEditing` callback builds a `StorageEdit(range:delta:)` from its
   arguments and calls `layoutDebt.hear` inside `MainActor.assumeIsolated`, for any mask.
   `settleBaseline` calls `layoutDebt.oweEverything()` in the same branch that installs the delegate.
3. **The door.** The three controllers take `layout:` at `init` (the coordinator, `:78`, `:91`, `:96`,
   is the only caller) and call `layout.invalidateWholeDocument(of: textView)` where they called
   `invalidateLayout` (C2 of the ADR). Folding's whole-range `.editedAttributes` stays.
4. **Grow-to-fit.** `growToFitTheText`'s `ensureLayout(for: layout.documentRange)` becomes
   `layoutDebt.settle(textView, delegateIsCoordinator: textView.textStorage?.delegate === self,
   forcesWhole: forcesFullLayout)`. The other two steps are unchanged.
5. **The restyle guard (§D5).** `applyStylingIfNeeded` adds `storage.delegate === self` to the
   conditions of its incremental branch, so a foreign delegate runs `applyStyling`.
6. **The switch (§D6).** `forcesFullLayout(arguments:defaults:)` reads `-editorFullLayout <bool>`, then
   the defaults, with `EditorRestyleSwitch`'s own `isOn`.
7. **The stale comments in sources.** Update both to the new fact and cite ADR-0093:
   - `growToFitTheText`'s doc comment, `NoteTextView+Coordinator.swift:617-626`;
   - the relayout comment, `NoteTextView+ViewBlocks.swift:317-323`.

**If R-05 stays red with the record wired** (TextKit leaves an estimate outside the owed ranges, or a
table or view-block bounds change invalidates a fragment inside TextKit), **stop and report.** Do not
switch to laying out from the owed start to the end of the document, and do not route around the
witness. ADR-0093 §D4 and its Consequences name that choice as the person's.

Green bar: Task 3's tests, `EditorGrowToFitScopeTests` (its two §D7 pins unchanged), `EditorHeightTests`,
`NoteFoldingTests`, `TransclusionLayoutTests`, `ViewBlockRenderingTests`, `ViewBlockHostStoreTests`,
`IncrementalRestyleHostedTests`, then the full unit suite.

### Task 5 — Tester: the windowed renumbering and the map's line facts, declared and red (R-10, R-11, R-12)
Owner: tester
Files: Sources/Core/Editor/ListContinuation+Window.swift, Sources/Features/Editor/StructureMap.swift, Sources/Features/Editor/RestyleScope.swift, Tests/ListRenumberWindowTests.swift, Tests/ListRenumberWindowPropertyTests.swift, Tests/StructureMapTests.swift, Tests/RestyleScopeTests.swift
Tests: ListRenumberWindowTests.swift, ListRenumberWindowPropertyTests.swift, StructureMapTests.swift, RestyleScopeTests.swift, ListRenumberScopeTests.swift, ListContinuationTests.swift, CardFormattingTests.swift
Signatures:
- ListContinuation.Window — struct Window: Equatable, Sendable { var start: Int; var fenceOpen: Bool }
- ListContinuation.Windowed — struct Windowed: Equatable, Sendable { var renumbering: Renumbering?; var linesRead: Int; var readRange: NSRange }
- ListContinuation.LineFacts — struct LineFacts: Equatable, Sendable { var fenceDelimiters: Int; var endsEveryRun: Bool }
- ListContinuation.facts(ofLine:in:) — static func facts(ofLine line: NSRange, in text: NSString) -> LineFacts
- ListContinuation.renumbered(_:touching:window:) — static func renumbered(_ text: NSString, touching edited: NSRange, window: Window) -> Windowed
- ListContinuation.renumbered(_:touching:) — static func renumbered(_ text: String, touching edited: NSRange) -> Renumbering?
- ListContinuation.renumbered(_:) — static func renumbered(_ text: String) -> String?
- StructureMap.Line — struct Line: Equatable, Sendable { var start: Int; var signature: MarkdownLineSignature; var listFacts: ListContinuation.LineFacts = .init(fenceDelimiters: 0, endsEveryRun: false) }
- RestyleScope.renumberWindow — func renumberWindow(before offset: Int) -> ListContinuation.Window?
Red: yes

**Declarations with neutral bodies.**

- In the new `Sources/Core/Editor/ListContinuation+Window.swift` (Foundation only):
  - `facts` returns zero delimiters and `endsEveryRun: false`;
  - the windowed form returns `Windowed(renumbering: nil, linesRead: 0, readRange: NSRange(location: 0, length: 0))`.
- `StructureMap.Line.listFacts` gets a default, so the three construction sites compile unchanged.
- `renumberWindow(before:)` returns nil.
- Run `tuist generate --no-open`, then build `perg` and `pergamenum-mcp` once: the new Core file
  compiles into both.

**`ListRenumberWindowTests.swift`:**

- **`facts`**, case by case:
  - a fence line with ``` and with ~~~, indented by spaces and by tabs;
  - a grammar line holding two delimiters split by a lone `\r`, NEL, U+2028 or U+2029: count 2;
  - a blank line, and spaces only: `endsEveryRun`;
  - a column-0 bullet and a column-0 prose line: `endsEveryRun`;
  - a column-0 ordered item and an indented item: not;
  - a grammar line whose last `LineScan` line is blank after a U+2028: `endsEveryRun`.
- **`renumberWindow(before:)`** on a `RestyleScope`:
  - the start is the nearest line whose previous line ends every run;
  - the parity is right after one fence, two fences, and a fence opened behind a lone CR;
  - nil after a wholesale replace.
- **R-11:** the same local structure (a 12-item ordered list with a nested run, a fence above it,
  blank-line boundaries) placed at the end of a 50 KB and of a 1 MB note made of
  `RestyleBudget.syntheticNote`-style prose. The same edit in both gives:
  - equal `linesRead`, greater than 0;
  - equal `readRange.length`;
  - equal renumberings, offsets aside.
- **R-12:**
  - a source guard reads `Sources/Features/Workspace/CardTextView+ListEditing.swift` and asserts it
    calls `ListContinuation.renumbered(` with the one-argument form and never `window:`;
  - `CardFormattingTests` stays untouched, checked by `git diff` at review.

**`ListRenumberWindowPropertyTests.swift` (R-10).**

- **Generator.** A fixed SplitMix64 generator, seeds `1, 2, 3, 5, 8, 13, 21, 34, 55, 89`, 300 cases
  each. Notes are built from lines:
  - ordered items with `.` and `)`, gapped ordinals, multi-digit ordinals;
  - bullets and checkboxes;
  - nesting at indents 0, 2, 3 and 4, and with tabs;
  - blank and spaces-only lines, column-0 prose;
  - fences with ``` and ~~~, indented and not, closed and left open;
  - the terminators `\n`, `\r\n`, lone `\r`, NEL, U+2028 and U+2029.
- **Edits:** insert, delete or replace a token at a random offset, including at 0 and at the end.
- **Per case**, on the text after the edit with the edit's range: the window from
  `RestyleScope(text:)` then `renumberWindow(before: edited.location)`.
  - `renumbered(text, touching:window:).renumbering == renumbered(text, touching:)`: range,
    replacement, and `mapping` at every offset of the rewritten range plus its two ends.
  - Where the text after the windowed rewrite has nothing left to renumber (`renumbered(_:)` of it is
    nil), `renumbered(_:)` of the edited text must give the same text.

    This is how "equals the whole-text renumbering" is read (ADR-0093 §D8). Literal equality with
    `renumbered(_:)` would force it to touch misnumbered runs the edit never reached, which ADR-0082 §D6
    forbids.
- **Non-vacuity.** Counters asserted at the end, each above a floor:
  - a non-nil renumbering;
  - a window start above 0;
  - `fenceOpen` true at the start;
  - a nested run renumbered;
  - an extra separator inside the read range;
  - a gapped run fixed.

**`StructureMapTests.swift`:** `StructureMap(text:)`'s lines carry `facts(ofLine:)` for their own range,
and a map kept through edits equals a fresh one, facts included.

Expected red: everything but the oracle forms, which are unchanged.

### Task 6 — Coder: the windowed renumbering, the map's facts and the coordinator call (R-10, R-11, R-12)
Owner: coder
Files: Sources/Core/Editor/ListContinuation+Window.swift, Sources/Core/Editor/ListContinuation.swift, Sources/Core/Editor/LineScan.swift, Sources/Features/Editor/StructureMap.swift, Sources/Features/Editor/RestyleScope.swift, Sources/Features/Editor/NoteTextView+ListEditing.swift
Tests: ListRenumberWindowTests.swift, ListRenumberWindowPropertyTests.swift, StructureMapTests.swift, RestyleScopeTests.swift, ListRenumberScopeTests.swift, ListContinuationTests.swift, NoteListEditingTests.swift, ListRenumberRecordingTests.swift, IncrementalStylerPropertyTests.swift, CardFormattingTests.swift
Signatures:
- ListContinuation.facts(ofLine:in:) — static func facts(ofLine line: NSRange, in text: NSString) -> LineFacts
- ListContinuation.renumbered(_:touching:window:) — static func renumbered(_ text: NSString, touching edited: NSRange, window: Window) -> Windowed
- RestyleScope.renumberWindow — func renumberWindow(before offset: Int) -> ListContinuation.Window?
- NoteTextView.Coordinator.renumberLists(in:touching:) — func renumberLists(in textView: NSTextView, touching edited: NSRange?)
Red: no

ADR-0093 §D8.

1. **One walk, two callers.**
   - Move the scoped form (`ListContinuation.swift:321-399`, with `Renumbering` and `DigitEdit`) into
     `ListContinuation+Window.swift`, unchanged in behaviour.
   - Extract its loop and its covering-range builder into one function over a `[LineScan.Line]` and its
     fence flags. `LineScan.Line` carries absolute offsets, so no base shift is needed.
   - The scoped form passes every line; the windowed form passes the lines it read.
   - The helpers the new file reads in `ListContinuation.swift` (`Edit`, `apply`, `renumberEdit`,
     `orderedRun`, `role`, `codeFenceFlags`, `isFenceDelimiter`, `marker`, `ordered`) widen from
     `private` to internal, each with one comment naming the reader (ADR-0045).
   - `ListContinuation.swift` must end under 400 lines.
2. **The read.**
   - From `window.start`, read `LineScan` lines forward with `getLineStart`, through a ranged reader
     added to `LineScan` if the coder prefers. The fence flag is seeded with `window.fenceOpen`.
   - Stop after the first line, at or after the line following the edit's last line, whose facts end
     every run, or at the end of the text. The edit's last line is the scoped form's `last`.
   - `linesRead` and `readRange` report what was read.
3. **The facts.** `facts(ofLine:in:)` splits the grammar line with `LineScan` and applies
   `isFenceDelimiter` and the blank, indent and ordered tests `role` uses. `StructureMap` fills
   `listFacts` at its three construction sites (`:144` copies it with the offset; `:192` and `:199`
   compute it).
4. **The window.** `renumberWindow(before:)`, per ADR-0093 §D8:
   - nil while `isStale`;
   - otherwise from the grammar line before the one holding `offset`, walk back over
     `listFacts.endsEveryRun`;
   - sum `fenceDelimiters` above the start, mod 2.
5. **The call.** `renumberLists(in:touching:)`:
   - with a recorded range and `restyleScope?.renumberWindow(before: edited.location)` answering, it
     calls the windowed form on the storage's string as `NSString` and applies `.renumbering` exactly
     as it applies the scoped result today;
   - otherwise the scoped form;
   - with no range, the whole-text form. The undo-step and caret behaviour are unchanged.

`NoteListEditingTests:270` calls `renumberLists(in:touching:)` directly and must stay green unchanged.
`IncrementalStylerPropertyTests` (ADR-0091's map invariant) must stay green with the facts in the map.

### Task 7 — Tester: the restated tests, the structural rows, the benches and the full suite (R-13, R-14, R-15, R-16)
Owner: tester
Files: Tests/RestyleBudgetSupport.swift, Tests/EditorRestyleBudgetTests.swift, scripts/editor-restyle-bench.sh, Tests/EditorGrowToFitScopeTests.swift, Tests/EditorHeightTests.swift
Tests: EditorRestyleBudgetTests.swift, RestyleBudgetSupport.swift, EditorGrowToFitScopeTests.swift, EditorHeightTests.swift, StylerGoldenTests.swift, IncrementalStylerPropertyTests.swift
Signatures:
- RestyleBudget.StructuralPath — enum StructuralPath: String, Sendable, CaseIterable { case fenceOpenLast = "fence-open-last", fenceOpenAbove = "fence-open-above", wikilinkOpen = "wikilink-open", wikilinkCloseFar = "wikilink-close-far" }
- RestyleBudget.includesStructuralRows — static var includesStructuralRows: Bool { get }
- RestyleBudget.structuralLine — static func structuralLine(_ c: Case, path: StructuralPath, cpuMs: Double, wallMs: Double, dirty: Int, runs: Int) -> String
- StructuralScenario — struct StructuralScenario { func keystroke(); func restore(); func outcome() -> Outcome }
- scripts/editor-restyle-bench.sh — flag --structural, exporting TEST_RUNNER_RESTYLE_BUDGET_STRUCTURAL=1; third table from lines matching ^restyle-budget-structural size=
Red: no

**Update tests and call-sites asserting the old behaviour** (the staleness rule; the grep below was run
on `3070555b`):

- **The layout contract changes; `growToFitTheText`'s signature does not.**
  - Its callers: `NoteTextView+Coordinator.swift:275`, `:751`; `NoteTextView+Update.swift:79`;
    `NoteTextView+ViewBlocks.swift:332`; `Tests/EditorGrowToFitScopeTests.swift:60`, `:96`;
    `Tests/ScrolledEditorFixture.swift:92`.
  - No assertion depends on a whole-document layout per call. The comments that say it does are
    restated:
    - `Tests/EditorGrowToFitScopeTests.swift`, header `:5-16`;
    - `Tests/EditorHeightTests.swift:15-17`.
  - The two §D7 pins themselves are not touched (R-05).
- **`dismantleNSView`** callers: `NoteTextView.swift:290`, `Tests/NoteEditorTeardownTests.swift:105`,
  `:142`. Unaffected: neither test styles, so neither storage has the coordinator as delegate. The
  card's own `dismantleNSView` is unrelated.
- **The controller initialisers** have one caller each, the coordinator (`:78`, `:91`, `:96`), done in
  Task 4.
- **`renumberLists(in:touching:)`:** `NoteTextView+Coordinator.swift:264`,
  `Tests/NoteListEditingTests.swift:270`. Same result, so no restatement.
- **`StructureMap.Line`** is built only in `StructureMap.swift` (`:144`, `:192`, `:199`).
- Any other red in the full suite is diagnosed first and restated only with its reason written into
  ADR-0093, never disabled.

**The structural rows (R-13), ADR-0093 §D9, the shape of `FallbackScenario`.**

- Four scenarios on each active case:
  - a fence opened with no fence below;
  - a fence opened above later fences;
  - `[[` completed with no `]]` below;
  - `]]` completed with the last `]]` far above.
- An always-on test asserts each scenario prepares the note it describes and takes the path it names:
  - a full restyle, with `RestyleScope.Reason` `.fenceLine` for both fence paths;
  - `.wikilinkPending` or `.wikilinkTokens` for the two link paths;
  - `dirty` equal to what the restyle covered.
- The timed test runs only with `RESTYLE_BUDGET_STRUCTURAL=1` and prints `structuralLine`. Nothing is
  asserted on time.
- A unit test pins the line's fields, as `theFallbackLineHasTheSevenFieldsTheBenchScriptGreps` does:
  `restyle-budget-structural size=51200 variant=fences path=fence-open-last cpu_ms=12.35 wall_ms=15.50 dirty=123 runs=5`.
- `scripts/editor-restyle-bench.sh` takes `--structural`. It updates the header comment's list of
  switches and prints a third table (`size`, `variant`, `path`, `cpu_ms`, `wall_ms`, `dirty`, `runs`)
  under "structural paths (printed, never asserted):".

**The measurements (R-14, R-16).** On the development Mac, nothing else building:

- `scripts/editor-restyle-bench.sh --runs 9 --structural`, then
  `scripts/editor-restyle-bench.sh --large-only --runs 9`.
- One `sample` profile of the 1 MB fences row, naming the share inside TextKit's insertion
  (`insertText` down to the content storage's element ranges and the layout manager's invalidation)
  and the app's remaining terms.
- Report all three outputs verbatim for Task 8.
- The four rows up to 200 KB must read under 20 ms. If one does not, report it with the profile; do
  not raise a ceiling.

**R-15:** `StylerGoldenTests` byte-identical, `IncrementalStylerPropertyTests` green, then the **full
unit suite** (`.claude/test-cmd`): a contract change in the layout path can turn tests red in modules
that only share the fixture.

### Task 8 — Coder: the ADR's numbers, the pointers, the indexes, the ledger and the gates (R-14, R-16, R-17)
Owner: coder
Files: docs/adr/0093-a-keystroke-lays-out-what-it-changed.md, docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md, docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md, docs/adr/INDEX.md, CLAUDE.md, Tests/RestyleBudgetSupport.swift
Tests: EditorRestyleBudgetTests.swift, RestyleBudgetSupport.swift
Signatures:
- RestyleBudget.ceilings — static let ceilings: [Case: Double]
- scripts/adr-index.py — --check exits 0
- scripts/check-adr-references.py — exits 0 after git fetch
Red: no

1. **ADR-0093 "Measured after" (R-16):**
   - the six rows before (ADR-0091's, K = 9) and after, from Task 7's output;
   - the structural rows;
   - the Mac, the OS, the Xcode and the build configuration;
   - the profile's split, naming what stays at TextKit's floor.
2. **Pointers, one line each, history not rewritten:**
   - under ADR-0082 §D7 (`0082-…md:289`): "Reopened and scoped by ADR-0093 §D4";
   - under ADR-0091 §D10 (`0091-…md:506`): "Its layout half is amended by ADR-0093 §D4".
   - **ADR-0091's status flip** to `accepted` is not this task's to decide. See Risks.
3. **Indexes:**
   - `docs/adr/INDEX.md` gets ADR-0093's summary line in its own format;
   - `CLAUDE.md`'s `## ADR index` gets the line `scripts/adr-index.py` prints;
   - `scripts/adr-index.py --check` and `scripts/check-adr-references.py` pass.
4. **Ledger entries (R-16).** The three entries ADR-0093 names, filed through `/project-tasks`, never by
   editing `TODO.md` by hand:
   - a ranged fold layout;
   - a bench row with embeds and view blocks, then each update pass made proportional or named with its
     number;
   - TextKit's own bookkeeping of an insertion, with the lazily laid-out note as the open question.

   Write the IDs into ADR-0093's "Ledger entries".
5. **G-ceiling-3 (R-14), HITL.** Put the six measured numbers in front of the person. Write
   `RestyleBudget.ceilings` (`Tests/RestyleBudgetSupport.swift:189-196`) only with the values they give,
   then rerun `EditorRestyleBudgetTests` with `RESTYLE_BUDGET_200KB=1`.
6. **G-grow-2 and G-type-2 (R-17), HITL, the person on a Release build.** Hand over the checklist from
   ADR-0093's Gates verbatim:
   - G-grow-2: 1 MB note; type at the end and in the middle, Enter, a wrapping sentence, Cmd+Down,
     scroll to the end, click about 60 pt above the bottom edge then type; repeat after a keystroke at
     the top.
   - G-type-2: 50 KB note; undo and redo after typing, and an IME composition.

   Run them together with ADR-0091's G-grow and G-type, with `-editorFullLayout YES` and
   `-editorFullRestyle YES` as the isolators. The person's verdict goes into ADR-0093's Gates.
7. **The number, again.** `git fetch origin`, then `git ls-tree origin/main docs/adr/` and every branch
   about to merge. If `0093` was taken meanwhile, renumber (see the header).

## Risks & HITL gates

- **TextKit's soft invalidation (high impact, unmeasured).** A ranged `ensureLayout` might leave an
  estimate below the owed ranges. Task 3's witness catches it, and Task 4 stops and reports. The remedy
  (lay out from the owed start to the end) is the person's choice, because it gives back most of the
  gain at the top of a long note.
- **A fifth way of losing layout.** Attachment view bounds tracking (`tracksTextAttachmentViewBounds`
  on the table grid and view-block providers) may invalidate a fragment inside TextKit with no storage
  edit. The R-05 tests on the rich note are the net. If they show it, the fix is a ranged door call from
  the measured-size crossing (`TableGridView+Rendering.swift:155`), which needs a line in ADR-0093
  before it is written.
- **Undo replay.** A hook that renumbered after an undo would empty the redo stack. The replay leaves
  the renumber out (ADR-0093 §D7), and Task 1's one-undo-step test with redo is the guard. The window's
  undo manager is shared with the sidebar (ADR-0026 §D8). Its notifications reach the hook, which finds
  nothing unstyled.
- **SwiftLint size limits.** `ListContinuation.swift` (399 of 400) and the coordinator class body.
  Task 6 moves the scoped form out; Task 4 keeps new methods out of the class body. CI does not run
  SwiftLint, so the coder runs it on the touched files.
- **The windowed renumbering has no switch of its own.** `-editorFullRestyle YES` turns it off as a side
  effect (no scope), which is enough to isolate it on Release. Say so if a separate switch is wanted.
- **The flake behind the delegate guard is still unexplained.** The guard makes it harmless; it does not
  explain it.
- **ADR number collision.** `0093` is free on `origin/main` today, and `0092` is skipped on the SPEC's
  word: the worktree holding it was not inspected (outside this session's scope). Re-check before each
  merge (Task 8, step 7).
- **ADR-0091's status (user decision).** It still reads `planned` on `main` although #971 merged
  (`18fb38e4`). `docs/adr/README.md` rule 2 flips it in the first docs change after the merge, so this
  docs PR qualifies; the project context file says to flip it after the human gates. Decide before the
  docs PR: flip it here (rule 2), or after G-grow and G-type.
- **HITL gates:**
  - PLAN APPROVAL (this plan and ADR-0093);
  - commit and push of the docs branch and of the code branch;
  - G-ceiling-3 (Task 8 step 5);
  - G-grow-2 and G-type-2 on Release, with #971's G-grow and G-type (Task 8 step 6);
  - the merge of each PR, after the ADR number re-check.

  No schema, deletion or deploy step. No external resource is needed: no network, no account, no new
  dependency.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

## Build result (2026-10-11)

BUILD · DONE WITH WARNINGS
Files: 45 paths (4 new sources, 9 new test files, ADR-0093, SPEC.md, this plan; edits in Sources/Core/Editor, Sources/Features/Editor, Tests, docs/adr, scripts/editor-restyle-bench.sh, CLAUDE.md)
Tests: 6271 passed in 378 suites, 5 known issues, 6 (coverage)
Review: sonnet, safe; opus, safe
Coverage: no UNCOVERED line for R-01 to R-17; STALE-WAIVER R-16, R-17
Dropped: 15 (nit 10, fix-hunk 2, post-sweep 3)
Dispatch: Round 0 (red): tester — Task 1, tester — Task 3, tester — Task 5
Dispatch: Round 1: debugger — settle drops an unconverted range, coder — ledger IDs unfiled, coder — composition binding write, coder — multi-keystroke witness
Dispatch: Round 2: debugger — container inset not compared in wholeReason
Dispatch: Round 1 (sweep): coder — C1, C2, C3, C4, C5, LayoutDoorGuardTests header
Dispatch: Round 2 (sweep): coder — body length, headers, ADR §D8, debugger — composition panel close
Routing: round 2 triage fell back, the MAJOR [wrong-behaviour] went to debugger by its category
INFO: review escalated, size: 44 changed files, threshold 20
WARN: finding triage not evaluated in round 2, malformed record 7 (a sonnet NIT carried confidence "-")
WARN: STALE-WAIVER R-16 (SPEC no-test clause is stale: a test file the plan names mentions it)
WARN: STALE-WAIVER R-17 (same)
INFO: the full suite was red on EditorRestyleBudgetTests.aKeystrokeInTheMiddleStaysUnderItsCeiling (50 KB prose, 696 to 779 ms against the 596 ms ceiling) and passed alone at about 6 ms. Cause found after the report: a coordinator whose text view was gone still received the change notification of a new view allocated at the same address, styled it with its own baseline and took the storage's delegate slot, so every keystroke was a full restyle. Fixed in `NoteTextView.Coordinator.textDidChange` (it answers only a view it is the delegate of), pinned by `ReplayAndWindowCoverage.aCoordinatorIgnoresTheChangeNotificationOfAnotherView`; the full suite then passed (6272 tests, prose 4.60 ms, fences 4.95 ms). The ceilings stay the person's at G-ceiling-3
WARN: branch still at 3070555b while main has moved (#973, #974): merge origin/main per file before the PR, then redo the ADR 0093 number check and the TODO.md sync
WARN: Task 8 left to the person: ledger entries unfiled, G-ceiling-3 (RestyleBudget.ceilings), G-grow-2 and G-type-2 on a Release build, ADR-0091 and ADR-0093 flips

```text
FIX	swept	**MINOR** [other] Sources/Features/Editor/NoteTextView+EditReplay.swift:56 — composition replay refreshes the completion panel, not named in the ADR (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/LayoutDebtHostedTests.swift:103-117 — no hosted test asserts unconverted stayed put (reviewer: opus)
FIX	swept	**MINOR** [plan-deviation] docs/adr/0093-a-keystroke-lays-out-what-it-changed.md:587 — ledger entries not filed (reviewer: opus)
FIX	swept	**MINOR** [other] docs/adr/0093-a-keystroke-lays-out-what-it-changed.md:3 — Status planned vs proposed (reviewer: opus)
FIX	swept	**MINOR** [style] Tests/ListRenumberWindowTests.swift:129 — two large_tuple lint errors (reviewer: sonnet)
FIX	swept	**MINOR** [style] Tests/LayoutDoorGuardTests.swift:12 — header says the controllers still call invalidateLayout directly (AUTO)
FIX	swept	**MINOR** [style] Tests/LayoutDebtHostedTests.swift:101 — suite body still over type_body_length 250 (reviewer: opus)
FIX	swept	**MINOR** [style] Tests/ListRenumberWindowTests.swift:13 — stale 'Red until Task 6' headers (reviewer: sonnet, opus)
FIX	swept	**MINOR** [other] docs/adr/0093-a-keystroke-lays-out-what-it-changed.md:329 — §D8 says an undo or redo takes the whole-text form (reviewer: opus)
FIX	swept	**MINOR** [wrong-behaviour] Sources/Features/Editor/NoteTextView+EditReplay.swift:67 — composition step never closes an open completion panel (reviewer: sonnet, opus)
FIX	swept	**NIT** Tests/LayoutDebtHostedTests.swift:199 — #expect message over 200 characters (reviewer: sonnet)
FIX	swept	**NIT** Tests/EditorRestyleBudgetTests.swift:84 — test name says eight fields, the line has seven (reviewer: opus)
FIX	swept	**NIT** Sources/Core/Editor/LineScan.swift:46 — line(at:in:) precondition not in the doc comment (reviewer: opus)
DROP	fix-hunk	**MINOR** [wrong-behaviour] Sources/Features/Editor/NoteTextView+Layout.swift:145 — width or inset changed and restored before a settle goes unseen, layout invalid with nothing owed (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [wrong-behaviour] Sources/Features/Editor/NoteTextView+EditReplay.swift:70 — undo/redo replay runs with completing: true, so Cmd+Z can open the completion panel (reviewer: opus)
DROP	post-sweep	**MINOR** [other] Sources/Features/Editor/NoteTextView+ListEditing.swift:81 — comments at :81 and :117 still say an undo or redo takes the whole-text renumber (reviewer: sonnet, opus)
DROP	post-sweep	**MINOR** [other] docs/plans/scoped-layout-followup.md:26 — branch still at 3070555b while main moved by #973 and #974, git diff main shows #973 reverted (reviewer: opus)
DROP	post-sweep	**NIT** docs/adr/0093-a-keystroke-lays-out-what-it-changed.md:468 — Hooks-installed list has the old signatures (reviewer: sonnet)
```
