# ADR-0093: A keystroke lays out what it changed, and renumbers from a line the map vouches for

- Status: **planned**. The root `SPEC.md`, the plan (`docs/plans/scoped-layout-followup.md`) and this
  record land on `main` with the code PR, from `feature/scoped-layout-followup`, where they are untracked
  until that PR's commit (`docs/adr/README.md` rule 2). It stays `planned` until the human gates below
  are answered, and flips to `accepted`, naming the code PR, its merge commit and the date, in the first
  docs change after that merge.
- Date: 2026-10-11. Written against `3070555b` (`origin/main` after `git fetch origin`, the same commit).
  Every line number below was read there.
- Number: `0093`, not `0092`, on purpose. On 2026-10-11 the highest number on `origin/main` is `0091`,
  no local or remote-tracking ref holds `docs/adr/0092*` or higher (`git ls-tree` over every ref, and
  `git log --all -- 'docs/adr/0092*'` printed nothing), and the one worktree inside this repository
  (`.claude/worktrees/agent-a86607d92ffe59aa9`) holds none. Rule 1 alone would give `0092`. The SPEC
  records that another line of work holds an unpublished file with that number, in a worktree this
  session could not read; taking `0092` would be the collision the renumbering register in
  `docs/adr/README.md` records five times. The gap costs nothing (no script checks for one). Check again
  immediately before the merge (rule 1), including the branches about to merge.
- Source: root `SPEC.md` (Approved 2026-10-11), "What is left of the per-keystroke cost after the
  per-paragraph restyle", R-01 to R-17, part of `PG-401`/#967. This record registers the SPEC's twelve
  decisions and does not reopen them.
- Relations:
  - **Extends ADR-0091.** §D2's storage delegate gains its second callback; §D8's kill switch gets a
    sibling; §D9's surfaces (note, Oggi, Diario) take the new path and the card does not.
  - **Amends ADR-0091 §D10**, its layout half: `growToFitTheText` no longer lays out the document range
    on every call. §D10's fence-crossing half stands.
  - **Amends ADR-0082 §D7: reopened, and scoped.** §D7 was withdrawn at G-grow on 2026-10-10 because
    every update invalidated the whole note, so heights above the viewport became estimates. ADR-0091
    removed that cause. The invariant is §D7's withdrawal's own: after a keystroke no height in the
    note is an estimate. What is laid out is what the record owes (D4), not the caret's fragment and the
    viewport, which is the design §D7 tried and which stays rejected.
  - **Keeps ADR-0082 §D6.** The scoped renumbering keeps its contract (one undo step, `mapping`, the
    run widened by a line each side); the windowed form (D8) is its sibling and returns the same value.
    The card keeps the whole-text form.
  - **Keeps ADR-0001 §D1.** The windowed renumbering and its line facts live in `Sources/Core`,
    Foundation only, and compile into `perg` and `pergamenum-mcp`.
  - **Keeps ADR-0074 §D1 and §D2.** The pass order does not change; the record is one
    `@MainActor final class`, declared in the file of the pass that writes it, handed to the three
    controllers that invalidate the layout the way `decorations` is handed to them.
  - **Keeps ADR-0081 §D4.** The record changes no attribute; the stored paragraph keeps its length.
  - **Does not touch ADR-0077 §D1.** No shared parser gains a projection; `ListContinuation` is the
    editor's list rule, read by no exporter.

## Context

**C1. What a keystroke still costs.** ADR-0091's "Measured after" (2026-10-11, Debug, CPU ms per key,
K = 9): 50 KB 5.81 / 7.35 (prose / fences), 200 KB 22.55 / 37.59, 1 MB 121.96 / 522.68. Four of six rows
miss 20 ms. Its profile of the 1 MB fences row puts 39% in TextKit's own range update inside
`insertText`, 25% in `growToFitTheText` laying out the document range, 15% in the linear shift of
ADR-0091 §D6, and 19% in `renumberLists(in:touching:)` (10.6%) plus the incremental restyle itself (8.8%).
The two app-owned terms this record takes on are the 25% and the 10.6%.

**C2. Where the whole-document layout comes from.**

- `growToFitTheText` (`NoteTextView+Coordinator.swift:627-638`) calls
  `ensureLayout(for: layout.documentRange)` at `:629` on every call. Its callers: `textDidChange`
  (`:275`), `runPasses` (`NoteTextView+Update.swift:79`), the view-block refresh hand-off (`:751`) and
  the deferred view-block relayout (`NoteTextView+ViewBlocks.swift:332`).
- Three note-editor passes invalidate the layout of the whole document directly, and they are the only
  `invalidateLayout` calls under `Sources/Features/Editor` (`git grep`, 2026-10-11):
  - folding, `NoteTextView+Folding.swift:68-70`, after a whole-range `.editedAttributes` at `:65-67`;
  - transclusion, `NoteTextView+Transclusion.swift:195-197`, when the renditions changed;
  - the view-block height callback, `NoteTextView+ViewBlocks.swift:331`, deferred one turn.
- The card has its own fold invalidation (`CardTextView+Fold.swift:42-44`) on its own coordinator, with
  no grow-to-fit and no layout call.

Everything else that makes a fragment lose its layout already reaches the text storage as a processed
edit: a typed character, the incremental restyle's `setAttributes` over the dirty range, the reveal and
the embed passes (`storage.edited(.editedAttributes, range: paragraph, …)` at
`NoteTextView+Reveal.swift:225` and `NoteTextView+Embeds.swift:265`), the renumbering's
`replaceAtomically`, a note switch's `textView.string = text` (`NoteTextView+Update.swift:51`), and a
full restyle's whole-range `setAttributes`. The fourth way is a new container width or a new inset:
`applyReadableWidth` assigns `textContainerInset` (`:702`), which invalidates the layout of the whole
note without a storage edit, and a window resize changes the container's size the same way. With
readable width on and the pane wider than the cap, the inset absorbs the resize and the container stays
`cap + 2 * gutter` wide, so the container width alone would not show it: the record compares the inset
too (measured in `aReadableWidthInsetChangeOwesTheWholeNote`: without it, the settle after a 900 to 1200
pt resize laid out nothing and heights above the viewport stayed estimates).

**C3. The storage's delegate.** ADR-0091 §D2 installs the coordinator in `settleBaseline`
(`:759`), after the first full restyle's `endEditing()`. Two facts from reading the tree:

- `dismantleNSView` (`NoteTextView.swift:290-297`) purges undo actions and the link preview, and
  leaves the storage's delegate pointing at the coordinator.
- With the delegate replaced by another object, the coordinator records nothing, so
  `applyStylingIfNeeded` (`:234-250`) finds no pending decision and an unchanged edit count, and takes
  the **skip** path: the keystroke is not restyled at all. The SPEC names the layout half of this
  ("the record vouches for nothing"); the restyle half is the same defect one call earlier, found while
  reading, and is closed by D5.

The parallel line of work observed a full-suite flake, 3 runs in 10, in which the delegate that heard
the storage was not the coordinator; it was not reproducible once observed and has no explained cause.

**C4. Undo, redo and composed text, as tested so far.** The hosted twin calls the update pass by hand
after every operation (`Tests/ScrolledEditorFixture.swift:348-356` for an edit, `:365-379` for undo and
redo), and the composition test drives `setMarkedText` through that same helper
(`Tests/IncrementalRestyleHostedTests.swift:273-306`). A missing `NSText.didChangeNotification` would
therefore be hidden: the hand call styles what the notification would have. During an undo or a redo the
coordinator records no edited range for the renumber (`NoteTextView+ListEditing.swift:109-112`), so the
renumber falls back to the whole-text form there. Whether the real undo, redo and marked-text paths post
the change notification is not known at the time of writing; plan Task 1 finds out and "The real edit
path" below records the answer.

**C5. Renumbering reads the whole text on every keystroke.** `ListContinuation.renumbered(_:touching:)`
(`ListContinuation.swift:358-398`) builds `LineScan.lines(in:)` and `codeFenceFlags(in:haystack:)`
over the whole note (`:360-361`) before it looks at the few lines around the edit. `LineScan` splits at
every terminator `NSString.getLineStart` knows: `\n`, `\r\n`, a lone `\r`, NEL, LINE SEPARATOR and
PARAGRAPH SEPARATOR (`LineScan.swift:22-46`). The styler's grammar line ends at `\n` or `\r\n` only
(ADR-0091 C3), so every grammar line is a union of whole `LineScan` lines. The renumberer's fence flag
toggles on any line that starts, after spaces and tabs, with three backticks or three tildes
(`:231-249`), with no matching of the two. In `role(of:level:…)` (`:209-222`) a line is a boundary of
every ordered run when it is fenced, blank, or at a smaller indent than the run's level and not an
ordered item at it, so a column-0 line that is not an ordered item ends every run.

**C6. Registered from the SPEC, not argued again:** the layout debt is its own record fed by the
storage's processed edits; it hears them in the delegate's second callback; every whole-document
invalidation goes through one door; the card is untouched; a foreign delegate means whole-note layout,
and the coordinator clears the delegate when dismantled; a launch argument restores the whole-note
layout; the windowed renumbering starts at a line the structure map vouches for; undo, redo and
composed text are verified on the real path first and fixed only if the result differs; acceptance is
asserted up to 200 KB and measured at 1 MB; one build and one Release hand-check pass; the structural
bench rows are printed, not asserted.

## Decision

### D1. The record

`LayoutDebt`, a `@MainActor final class` in `Sources/Features/Editor/NoteTextView+Layout.swift`, owned
by `NoteTextView.Coordinator` as `layoutDebt` (ADR-0074 §D2: the file of the pass that writes it). It
holds:

- `owed`: `.everything`, or `.ranges([NSRange])`, sorted and disjoint, in the text as it now is. It
  starts at `.everything`.
- the container width and the horizontal inset the last layout was made at, nil until the first;
- the storage length as of the last edit it heard;
- `log`, a `LayoutLog` (whole, ranged and empty settles counted, the settles that left a range
  unconverted counted as `unconverted` (D4), the reason of the last whole layout, the ranges of the last
  ranged one): a test seam and a diagnostic, as `RestyleLog` is; nothing
  branches on it.

It is a reference type because several parties write it: the coordinator's storage callback, the
coordinator's grow-to-fit, and the three controllers' door calls. It is not persisted and holds no
text.

### D2. Hearing

`NoteTextView.Coordinator` implements `textStorage(_:didProcessEditing:range:changeInLength:)`,
`nonisolated`, entering the main actor with `MainActor.assumeIsolated` exactly as its
`willProcessEditing` twin does (`NoteTextView+StorageEdits.swift:55-65`). The restyle record keeps the
first callback and its pre-fixing range (ADR-0091 C4); the layout record takes the second, for **any**
mask, characters or attributes, because attribute fixing has by then widened the range to what TextKit
re-creates (`{10, 1}` becomes `{10, 27}` in ADR-0091 C4's measurement).

`hear(_:in:)` does, in order:

1. moves every owed range past the edit with `StorageEdit`'s rule (before stays, after moves by delta,
   overlapping is cut to its outside part). The widened range is a superset of the edit with the same
   delta, so shifting by it is exact for everything outside it, and everything inside it is owed again
   in step 2;
2. adds the edited range; an empty one, which a deletion reports, is replaced by
   `paragraphRange(for:)` of its location, the paragraph the deletion joined;
3. merges, and turns a range that covers the whole text into `.everything`;
4. records the storage length.

So a whole-text pass (a note switch, an external change, a theme or setting change, Enter in a list, the
whole-text renumber) reaches the record as a range covering the note, with no call of its own.

**Installing the delegate owes everything.** `settleBaseline` (`:758-765`) installs the coordinator after
the full restyle's `endEditing()`, so that pass's own edit was heard by whoever held the slot before.
Every installation therefore sets `owed = .everything` (`oweEverything()`). That covers the first use of
a coordinator and the reinstallation after a foreign delegate (D5).

### D3. One door

`LayoutDebt.invalidateWholeDocument(of:)` sets `owed = .everything` and calls
`invalidateLayout(for: documentRange)` on the text view's layout manager. It is the only place in the
note surfaces' sources that invalidates layout:

- `FoldController`, `TransclusionController` and `ViewBlockController` receive the record at `init`
  (`layout:`), beside `decorations`, and call the door where they call `invalidateLayout` today
  (C2). The coordinator is their only constructor (`:78`, `:91`, `:96`).
- Folding's whole-range `.editedAttributes` stays: it is a processed edit, heard by D2 as a range
  covering the note.
- A guard test reads every Swift file under `Sources/Features/Editor`, `Sources/Features/Today` and
  `Sources/Features/Diary`, skips comment lines (`NoteTextView+ViewBlocks.swift:320` names the call in a
  doc comment), and fails on any `invalidateLayout(` outside `NoteTextView+Layout.swift`. It reads at
  least the number of files there today, so a listing that read nothing cannot pass, the shape
  `UITestLaunchHarnessGuardTests` uses.
- The card is outside the guard and keeps its own call (SPEC: nothing consumes a record there).

### D4. Grow-to-fit lays out what is owed

`growToFitTheText(_:revealingCaret:)` keeps its signature and its three steps (ensure layout, compare
the needed height, ask the viewport controller). Only the first step changes: it calls
`layoutDebt.settle(textView, delegateIsCoordinator:forcesWhole:)`, which lays out

- **the document range** when `owed` is `.everything`, when the container width or the horizontal inset
  differs from the last layout's, when the coordinator is not the storage's delegate, when the storage length differs from the
  last heard one, or when the kill switch is on (D6); the log names which;
- **otherwise each owed range, widened by one character on each side** and clamped to the text,
  because TextKit invalidates the paragraph after an attribute edit together with it (SPEC edge case);
- **nothing** when nothing is owed and the width and the inset are unchanged.

It then clears `owed` and records the width and the inset, unless a widened range could not be converted to an
`NSTextRange` (or the layout manager has no `textContentManager` while ranges are owed): that range was
not laid out, so everything stays owed, `log.unconverted` counts it, and the next settle lays out the
document range with `.everythingOwed` as its reason. A second grow-to-fit in the same keystroke (`runPasses`
after `textDidChange`) finds nothing owed and lays out nothing.

This is ADR-0082 §D7 reopened in a different shape, and the difference is the point. §D7 laid out the
caret's fragment and the viewport, whatever had been invalidated, and failed G-grow because every update
invalidated the whole note. Here the layout follows exactly what was invalidated: every invalidation is
heard (D2) or goes through the door (D3), so a fragment outside what is owed has a layout that is still
valid, and its height is not an estimate. The two tests that pin §D7's withdrawal
(`EditorGrowToFitScopeTests.afterTheKeystrokePassesNoHeightInTheNoteIsAnEstimate` and
`thePassesAClickRunsLeaveTheViewOnTheSameText`) stay unchanged and green: both run a full restyle,
which owes the note.

**If TextKit leaves an estimate outside the owed ranges anyway** (the profile names a soft invalidation
inside the whole-document call, `__NSTextLayoutManagerFillSoftInvalidationToLocation`, whose reach after
a ranged layout is not measured), the hosted no-estimate tests turn red and the build stops there. The
remedy that is always correct, laying out from the first owed location to the end of the document, puts
the cost of a keystroke at the top of a long note back to the whole note; it is a different trade-off
and the person's to choose, not a silent fallback.

### D5. What the record vouches for, and the delegate

The coordinator passes `delegateIsCoordinator: storage.delegate === self` to every settle. With any other
delegate, or none, the layout is the whole note: the answer before this work.

**The restyle takes the same guard.** `applyStylingIfNeeded` treats a storage whose delegate is not the
coordinator as having no baseline, so it runs the full restyle, whose `settleBaseline` reinstalls the
coordinator and owes the layout everything (D2). Without this the keystroke is skipped (C3), the layout
record is guarded and the text is left unstyled. This goes one call beyond the SPEC's sentence, which
names the layout, because the same foreign delegate breaks the restyle first; the cost is a pointer
comparison per styling.

**Dismantle clears the delegate.** `dismantleNSView` sets `textStorage.delegate = nil` when it is this
coordinator, and only then, beside the undo purge it already does.

### D6. The layout kill switch

`EditorRestyleSwitch` gains `layoutKey = "editorFullLayout"` and
`forcesFullLayout(arguments:defaults:)`, read the way ADR-0091 §D8's switch is: the argument pair
`-editorFullLayout YES` in the launch arguments, or the key in the defaults, read once when the
coordinator is made; a test sets `forcesFullLayout` directly; Impostazioni does not show it. With it on
every settle lays out the document range, today's `growToFitTheText` byte for byte, while the record
keeps hearing so the log stays a report. It is independent of `editorFullRestyle`: `-editorFullRestyle
YES` already owes the whole note on every keystroke (a full restyle is a whole-range edit) and turns the
windowed renumbering off (D8), so the two switches between them isolate #971 from this work on a Release
build.

### D7. Undo, redo and composed text are verified on the real path, then fixed if they differ

Plan Task 1 drives each through the real operation (the window's undo manager's `undo()` and `redo()`;
`setMarkedText`, a second `setMarkedText` over the marked range, and the committing `insertText`) and
compares the text, the binding value, the attributes run by run and the derived state with a twin
restyled in full. The twin is the oracle: it receives the same operation and then the update pass by
hand. The incremental editor gets no pass by hand: only the one SwiftUI itself would run, which happens
when `textDidChange` wrote the binding, so a missing notification leaves it unstyled and the test red.

- **If they are equal, no code changes.** The finding and the method go into "The real edit path"
  below.
- **If one differs**, the fix is the SPEC's: the coordinator observes `didUndoChangeNotification` and
  `didRedoChangeNotification` of the undo manager it already tracks (`pushInputs`,
  `NoteTextView+Update.swift:14`), and `CompletingTextView` overrides the marked-text entry point to call
  the coordinator back. Each hook replays the edit path (`textDidChange`'s body after its guard, moved
  into one function both call), and only while `hasUnstyledEdits` is true, so a path that does post the
  notification and also reaches a hook is styled once. **The replay leaves out the renumbering.** The
  undo notification arrives after the undo manager has finished undoing, so a renumber written there
  would register as a new edit and empty the redo stack; the text an undo restores was renumbered when
  it was first written. **A composition step's replay never opens the completion panel, but refreshes one already open:**
  the marked text is not yet a word the person wrote and the commit posts `textDidChange`, which opens the panel on the
  normal path, yet the refresh is the only thing that closes an open panel whose context the marked text ends. The observation is removed in `dismantleNSView` and moved when the tracked undo
  manager changes. With `-editorFullRestyle YES` nothing counts as unstyled (ADR-0091 §D8 records no
  edit count with the switch on), so no hook replays and the switch keeps today's behaviour.

Either way a keystroke that renumbered a list stays one undo step on undo and on redo, and a restyle
during composition leaves the marked range and the selection as they were (SPEC edge cases).

### D8. The windowed renumbering

`ListContinuation.renumbered(_:touching:window:)`, a sibling of the scoped form in `Sources/Core/Editor`,
Foundation only. It takes the note as an `NSString` (the storage's own string, so no bridge of the note
is made for it), the edited range, and a `Window` (`start`, the UTF-16 offset of a grammar line start;
`fenceOpen`, the renumberer's fence parity there). It returns a `Windowed`: the same `Renumbering?` the
scoped form returns for that text and edit, plus `linesRead` and `readRange`, so a test can assert the
read does not grow with the note.

**The line facts.** `ListContinuation.facts(ofLine:in:)` reads one grammar line with the renumberer's own
rules and returns `LineFacts`:

- `fenceDelimiters`: how many of the line's `LineScan` lines are fence delimiters in the renumberer's
  sense (C5), so a delimiter after a lone `\r`, NEL, LINE SEPARATOR or PARAGRAPH SEPARATOR counts;
- `endsEveryRun`: whether the line's last `LineScan` line ends every ordered run whatever the fence
  state: it is blank (spaces and tabs only, as `role(of:level:…)` reads it), it is a fence delimiter, or
  it is a column-0 line that is not an ordered item (C5). The SPEC's wording, "a column-0 line that is
  not a list item", is the narrower case of the same rule; either is correct, since a column-0 bullet
  also ends every ordered run. A line inside a fence is a boundary too, but whether it is inside depends
  on the parity, so it is not a fact of the line and is not counted here.

`StructureMap.Line` carries them as `listFacts`, computed wherever the map computes a line's signature,
so ADR-0091 §D2's invariant (the kept map equals `StructureMap(text:)`) now covers them too. They are on
the map's line and not on `MarkdownLineSignature`, which restates the styler's grammar (ADR-0091 §D3):
these are the renumberer's facts, and a fence after a LINE SEPARATOR is not a structural change to the
styler.

**The window.** `RestyleScope.renumberWindow(before:)` takes the grammar line before the one holding
the edit's start, walks the map back to the nearest line whose previous line `endsEveryRun` (or the
first line), and returns its start with the parity of the `fenceDelimiters` of every line above it. No
ordered run crosses that start, by construction. It returns nil while the map is stale (a wholesale
replace waiting on its full restyle). The map is the current text's at the moment the renumber runs:
`RestyleScope.record` applies every edit to it as the storage reports it (ADR-0091 §D2).

**The read.** From the start, `LineScan` lines are read forward, the fence flags seeded with the parity,
up to and including the first line at or after the one that follows the edit's last line whose facts end
every run, or the end of the text. Every run the scoped form would renumber has ended by then. The run
walk is the scoped form's own, not a copy: both forms call one walk over the lines they were given, so
the equality below is a property of the code and not a coincidence of two implementations.

**What it must equal.** The scoped form's value for the same text and edit, `Renumbering` for
`Renumbering`: range, replacement and `mapping`. The SPEC's word for the oracle is "the whole-text
renumbering"; read literally as `renumbered(_:)`, that form also rewrites misnumbered runs the edit never
touched, which ADR-0082 §D6 deliberately leaves alone. The property test therefore asserts equality with
the scoped form on every generated case, and equality of the rewritten text with `renumbered(_:)` on the
cases where nothing outside the touched runs is misnumbered.

**Who calls it.** `renumberLists(in:touching:)` uses the windowed form when it has a recorded range and
`renumberWindow(before:)` answers; otherwise the scoped form as today (kill switch on, no scope, stale
map). A `textDidChange` with no recorded range stays the whole-text form. The card keeps
`renumbered(_:)` (`CardTextView+ListEditing.swift:38-39`) and its tests do not change.

**What stays linear.** The parity is a sum over the map's lines above the start: an array walk over
integers, the same order as ADR-0091's list-seed fold and its shift, and no text is read for it.

Replaced by ADR-0094 §D6: the parity is a rank in the map's odd-delimiter lines.

### D9. The structural bench rows

`scripts/editor-restyle-bench.sh --structural` sets `RESTYLE_BUDGET_STRUCTURAL=1` and prints a third
table from lines of the form

`restyle-budget-structural size=<bytes> variant=<prose|fences> path=<fence-open-last|fence-open-above|wikilink-open|wikilink-close-far> cpu_ms=<min> wall_ms=<min> dirty=<utf16 length> runs=<K>`

for the four edits the SPEC names: a fence opened with no fence below, a fence opened above later
fences, `[[` completed with no `]]` below, and `]]` completed with the last `]]` far above. `dirty` is
the length the restyle covered, the note's length for a full restyle. None is asserted on time; each
scenario asserts only that it prepared the note it describes, as the fallback rows do (ADR-0091 §D11).
The per-turn suite runs none of them.

### D10. Acceptance

- The four rows up to 200 KB must read under 20 ms CPU per key in Debug on the development Mac. The two
  1 MB rows are measured. The six asserted ceilings are fixed by the person at G-ceiling-3; until then
  `RestyleBudget.ceilings` keeps ADR-0082 §D9's.
- The share of the 1 MB keystroke that stays inside TextKit's insertion is stated in "Measured after",
  from a `sample` profile of the 1 MB fences row, as ADR-0091 did.
- The golden corpus stays byte-identical, ADR-0091's property test stays green, and the unit suite
  passes.
- One Release hand-check pass covers this work and ADR-0091's open gates (Gates below).

## Alternatives considered

- **Lay out the caret's fragment and the viewport (ADR-0082 §D7 as first written).** Rejected by the
  SPEC: it failed G-grow, and it lays out by position rather than by what was invalidated, so it is wrong
  whenever an invalidation lands outside the viewport.
- **A second delegate object on the storage**, replacing the coordinator. Rejected by the SPEC: two
  owners of one slot is how the flake can arise.
- **Leave the three invalidation calls where they are, and teach the record by comment.** Rejected by
  the SPEC: the next call added leaves estimates silently. The guard test is what makes the door the only
  one.
- **Lay out from the first owed location to the end of the document.** Always correct whatever TextKit's
  soft invalidation does, and simpler. Rejected: a keystroke at the top of a long note would again cost
  the whole note, which is the 25% this record exists to remove. Kept as the named remedy of D4 if the
  no-estimate tests say the ranged layout is not enough, chosen by the person.
- **A fixed window of lines around the edit for the renumbering.** Rejected by the SPEC: a run can be
  arbitrarily long, and the answer would differ from the scoped form's.
- **The parity read from the text, walking back from the window's start.** Rejected: a walk back to the
  previous fence line is bounded only by the note, which is the read this work removes.
- **The renumberer's facts on `MarkdownLineSignature`.** Rejected: the signature is the styler's
  grammar, which `RestyleScope` reads to decide a restyle; mixing the renumberer's line splitting into it
  would make one type answer two grammars (D8).
- **The replay hooks renumbering like `textDidChange` does.** Rejected: outside the undo manager's own
  undo, the renumber's write is a new edit and empties the redo stack (D7).
- **The parallel line's design** (its own recorder, offset table and incremental styler). Not shipped,
  by the person's decision; only its findings are taken here.

## Consequences

### Positive

- A line-local keystroke lays out the paragraphs it invalidated, plus a character on each side, instead
  of the note.
- Renumbering on a keystroke reads the lines from the nearest run boundary above the edit to the end of
  the runs it touches, whatever the note's size.
- A foreign storage delegate can no longer leave a keystroke unstyled or a height estimated, and a
  dismantled editor no longer leaves its coordinator as a storage's delegate.
- Undo, redo and composed text are pinned on the path the app takes.

### Negative

- Every invalidation of a note editor's layout now has to reach the record. A way TextKit can lose a
  fragment's layout that is not in C2 would leave an estimate. The one candidate named while reading is
  TextKit's own tracking of an attachment view's bounds (`tracksTextAttachmentViewBounds`, set by the
  table grid and view-block providers): whether a measured size change invalidates the attachment's
  fragment inside TextKit, without a storage edit, is not known. The no-estimate hosted tests on the
  rich note, which carries a table and a view block, are the net, and only for the cases they drive.
- The structure map's lines carry two more facts, computed on every full build and every touched line.
- Three controller initialisers gain a parameter.
- A composition step now runs the edit path (D7), and that path writes the binding: the uncommitted
  marked text reaches `parent.text`, so `VaultController.updateOpenNoteText` marks the tab dirty and
  promotes a preview tab while the person is still composing, before anything is committed. Kept on
  purpose: the binding then always equals the text view's string (`RealEditPathTests` pins
  `bound.value == textView.string` after each marked-text step). An abandoned composition is not measured
  here.
- Still proportional to the note on every key: TextKit's own range update inside `insertText`, the
  linear shift of ADR-0091 §D6, the `parent.text` copy, the parity's array walk, and `NoteFolding.layout`
  while something is folded.

### Neutral

- No on-disk format, schema, protected interface or connector changes; no GUI test is added.
- The card's coordinator, renumbering and fold invalidation are unchanged.

## The real edit path (R-04)

**Method.** `Tests/RealEditPathTests.swift` on `RestyleTwin.rich(bindsIncremental: true)`: the rich note
in two editors, the incremental one built over a recording binding (`BoundText`) and with the window's
undo manager handed to the coordinator, the one line `pushInputs` runs in the app. Each operation is
given to both: the full twin (the oracle) gets the update pass by hand; the incremental editor gets
`fold(heading:)` and `runPasses()` only when the binding was written, the `updateNSView` that
`textDidChange`'s `parent.text = …` schedules, and nothing otherwise. Before that pass the test asserts
the binding holds the view's text and the coordinator has no unstyled edit; after it, text, attributes
run by run (`StorageComparison.firstDifference`), derived state (`twin.differences()`), selection and,
while composing, the marked range. The probe adds four observers for the length of the operation, none
of which touches the storage's delegate slot: `NSText.didChangeNotification` on the incremental text
view, the undo manager's did-undo and did-redo notifications, `NSTextStorage.didProcessEditingNotification`
with `.editedCharacters`, and the `restyleLog` delta. The undo sequence is a character typed in the prose,
then a `"3"` over the list's first digit (a renumbering keystroke), two undos and two redos; the
composition is `setMarkedText("ñ")`, `setMarkedText("ñé")` over the marked range, and the committing
`insertText("ñé", replacementRange: markedRange())`.

**Finding, before any hook** (plan Task 1's run, 2026-10-11):

```
real-edit-path op=undo did_change=0 undo_notice=1 storage_edits=1 styled=none
real-edit-path op=undo did_change=0 undo_notice=1 storage_edits=2 styled=none
real-edit-path op=redo did_change=0 undo_notice=1 storage_edits=1 styled=none
real-edit-path op=redo did_change=0 undo_notice=1 storage_edits=2 styled=none
real-edit-path op=mark-set did_change=0 undo_notice=0 storage_edits=1 styled=none
real-edit-path op=mark-replace did_change=0 undo_notice=0 storage_edits=1 styled=none
real-edit-path op=mark-commit did_change=1 undo_notice=0 storage_edits=1 styled=incremental
```

| Operation | `textDidChange` | undo manager notice | character edits | styling |
| --- | --- | --- | --- | --- |
| undo (each of two) | no | yes | 1 or 2 | none |
| redo (each of two) | no | yes | 1 or 2 | none |
| first `setMarkedText` | no | no | 1 | none |
| second `setMarkedText` | no | no | 1 | none |
| committing `insertText` | yes | no | 1 | incremental |

So undo, redo and both marked-text steps change the storage and never reach `textDidChange`: the binding
kept the old text and the lines they rewrote stayed unstyled, the C4 gap the hand-called pass in the old
twin helpers had hidden. Only the commit takes the ordinary path. `storage_edits` counts the character
edits the storage reported during one operation; the order of the 1 and the 2 across the two undos is not
the same in this run and in the one after the hooks below, and the finding does not rest on it.

**Hooks installed (D7), all three:**

- `textDidChange`'s body after its guard moved into `runEditPasses(in:renumbering:)`
  (`NoteTextView+EditReplay.swift`); `textDidChange` calls it with `renumbering: true`, unchanged.
  `replayEditIfUnstyled(in:)` runs it with `renumbering: false`, only while `hasUnstyledEdits` is true;
  the replay takes the renumber ledger's recorded range and drops it, so the next change cannot inherit
  it.
- The coordinator's `undoManager` gained a `didSet` that moves two block observers
  (`.NSUndoManagerDidUndoChange`, `.NSUndoManagerDidRedoChange`, queue `.main`) to the new manager;
  they call the replay, and are removed in `dismantleNSView` and in `deinit`.
- `CompletingTextView` overrides `setMarkedText(_:selectedRange:replacementRange:)`
  (`CompletingTextView+Composition.swift`, a file of its own because `CompletingTextView.swift` is at
  SwiftLint's length): `super`, then `onComposedTextChanged`, which `NoteTextView.wire(_:to:)` sets to the
  replay. Neither the marked range nor the selection is touched.

**After the hooks** (the same tests, green, 2026-10-11):

```
real-edit-path op=undo did_change=0 undo_notice=1 storage_edits=2 styled=incremental
real-edit-path op=undo did_change=0 undo_notice=1 storage_edits=1 styled=incremental
real-edit-path op=redo did_change=0 undo_notice=1 storage_edits=1 styled=incremental
real-edit-path op=redo did_change=0 undo_notice=1 storage_edits=2 styled=incremental
real-edit-path op=mark-set did_change=0 undo_notice=0 storage_edits=1 styled=incremental
real-edit-path op=mark-replace did_change=0 undo_notice=0 storage_edits=1 styled=incremental
real-edit-path op=mark-commit did_change=1 undo_notice=0 storage_edits=1 styled=incremental
```

Every operation is now styled on the incremental path before any pass SwiftUI runs, the binding holds the
text, the one-undo-step and one-redo-step assertions hold, and the commit, which posts the notification,
is styled once: by the time it could reach a hook nothing is unstyled. `dismantleNSView` clears the
storage's delegate when it is the coordinator and leaves a foreign one in place (`NoteEditorTeardownTests`).

## Measured after

Taken on 2026-10-11 by `scripts/editor-restyle-bench.sh` on the uncommitted tree of
`feature/scoped-layout-followup` (on `3070555b`), Mac `Mac17,7` (Apple M5 Max), macOS 27.0.1 (build 26A434),
Xcode 27.0 (27A266a), Debug build: milliseconds of main-thread CPU per keystroke, the minimum of K runs
after one warm-up. The 50 KB and 200 KB rows come from `--runs 9 --structural`; the two 1 MB rows from a
separate `--large-only` run. The ceilings in `RestyleBudget.ceilings` are ADR-0082 §D9's and are **not**
changed here: the person fixes the new ones at G-ceiling-3 (Gates).

The six rows, against ADR-0091's "Measured after" (K = 9):

| Size | Variant | Before (ADR-0091) | After | Ratio | Under 20 ms |
| --- | --- | --- | --- | --- | --- |
| 50 KB | prose | 5.81 | 4.93 | 1.2× | yes |
| 50 KB | fences | 7.35 | 5.10 | 1.4× | yes |
| 200 KB | prose | 22.55 | 17.15 | 1.3× | yes |
| 200 KB | fences | 37.59 | 17.90 | 2.1× | yes |
| 1 MB | prose | 121.96 | 90.20 | 1.4× | measured, not asserted (D10) |
| 1 MB | fences | 522.68 | 81.14 | 6.4× | measured, not asserted (D10) |

D10's acceptance holds in Debug: the four rows up to 200 KB read under 20 ms, the closest by 2.1 ms. The
1 MB rows are 81 and 90 ms in Debug; whether a person feels them is read on Release at G-grow-2. The gain
grows with the fenced variant and with size, because that is where ADR-0091's two app-owned terms, the
document-range layout and the whole-text renumbering, were largest.

**The fallback rows** (printed, never asserted; ms of CPU, before from ADR-0091's K = 9 table):

| Size | Variant | `fence-open` before / after | `table` before / after | `list-enter` before / after |
| --- | --- | --- | --- | --- |
| 50 KB | prose | 227.64 / 238 | 7.06 / 5.3 | 322.11 / 334 |
| 50 KB | fences | 255.09 / 272 | 8.28 / 5.4 | 334.01 / 353 |
| 200 KB | prose | 934.07 / 965 | 27.88 / 19.9 | 1376.05 / 1399 |
| 200 KB | fences | 1215.37 / 1254 | 43.70 / 21.4 | 1549.27 / 1588 |
| 1 MB | prose | 5268.33 / 5341 | 147.68 / 102.0 | 9033.04 / 9034 |
| 1 MB | fences | 11688.01 / 11610 | 504.31 / 117.9 | 13605.01 / 13554 |

`fence-open` and `list-enter` still cost a full restyle, as ADR-0091 says they must, and move within 7% of
ADR-0091's numbers either way. A keystroke in a table cell now costs about the plain keystroke at every
size, 1 MB fences included (504 to 118 ms): the table run was restyled locally already, and what it paid
was the document-range layout.

**The structural rows** (D9; printed, never asserted; ms of CPU; `dirty` was the note's length in every
row, so each took the full restyle, as D9 expects). Not measured at 1 MB.

| Size | Variant | `fence-open-last` | `fence-open-above` | `wikilink-open` | `wikilink-close-far` |
| --- | --- | --- | --- | --- | --- |
| 50 KB | prose | 334 | 146 | 330 | 323 |
| 50 KB | fences | 347 | 187 | 343 | 341 |
| 200 KB | prose | 1390 | 570 | 1383 | 1345 |
| 200 KB | fences | 1572 | 913 | 1560 | 1522 |

They sit where `fence-open` and `list-enter` sit: a structural edit costs a full restyle, and the gap to the
plain keystroke (30 to 90 times) is the price D9 records rather than the one this record removes.

**Where the 1 MB keystroke goes now.** One `sample` profile of the 1 MB fences row, Debug, 6,724 samples
under `NSTextView.insertText`:

| Where | Share | Owner |
| --- | --- | --- |
| `NSTextContentStorage` `processEditing`: the enumeration over every cached element | 43% | TextKit |
| `synchronizeTextLayoutManagers` (two call sites) | 11% + 4% | TextKit |
| `scrollRangeToVisible` → `estimatedSize` | 5% | TextKit |
| `LayoutDebt.settle` → `ensureLayout` over the owed ranges | 1.5% | TextKit, asked by D4 |
| `willProcessEditing` → `recordStorageEdit`: `shiftStyledRanges` (901 samples), `EditorDecorationDelegate.shift` (397), `RestyleScope.record` (130) | 22% | the app |
| the rest of `textDidChange`: `applyIncrementalStyling` (338 samples: the splice 130, `splice(hiddenMarkers:)` 110, `absorb` 74) and the other passes | 11% | the app |

About 67% stays inside TextKit and about 33% is the app's. The ranged layout (D4) is 1.5%: it is not
what a key pays for any more, against 25% for the document-range layout in ADR-0091's profile.

**What stays.** At TextKit's floor: the content storage's walk over its cached elements on every
`processEditing` (43%), the layout managers' synchronisation (15%) and the scroll's size estimate (5%), all
proportional to the paragraphs the note holds; whether a lazily laid-out note keeps fewer cached elements
is the third ledger entry's open question. App-owned, the largest term is ADR-0091 §D6's linear shift of
the derived state: `shiftStyledRanges` (`NoteTextView+Coordinator.swift:875`) and
`EditorDecorationDelegate.shift` (`EditorDecorationDelegate.swift:948`), about 20% of the key together,
walking every styled range and every decoration on every edit. Neither is changed here.

The app-owned term named here is removed by ADR-0094; see its Measured after.

## Gates

- **G-ceiling-3** (the person): fix the six ceilings from "Measured after". If ADR-0091's G-ceiling-2 is
  still open then, one answer settles both. Proposed, not written: three times the "after" column rounded
  up to a whole millisecond, the rule ADR-0082 §D9's ceilings and `RestyleBudget.provisionalCeiling`
  follow: 15 ms (50 KB prose), 16 (50 KB fences), 52 (200 KB prose), 54 (200 KB fences), 271 (1 MB
  prose), 244 (1 MB fences). At 50 KB a factor of three leaves about 10 ms of room, which a loaded Mac can
  take; a floor of R-14's 20 ms for the two 50 KB rows is the alternative if a red under load is not
  wanted. `RestyleBudget.ceilings` keeps ADR-0082 §D9's values until the person answers.
- **G-grow-2** (the person, R-17): on a Release build with a 1 MB note, type at the end and in the
  middle, Enter, a wrapping sentence, Cmd+Down, scroll to the end, click about 60 pt above the bottom
  edge and type; repeat after a keystroke at the top.
- **G-type-2** (the person, R-17): on a Release build with a 50 KB note, undo and redo after typing, and
  an IME composition.
- ADR-0091's G-grow and G-type run in the same Release session. `-editorFullLayout YES` and
  `-editorFullRestyle YES` isolate which change a failure belongs to, without a rebuild.

## Ledger entries

**Not filed yet, a deviation from plan Task 8 step 4**, which asks for the IDs here: `/project-tasks`
cannot be run from the agent that built this. The deferral is acknowledged by the person at the merge
gate (`/ship` GATE 3/3); the four entries below then go into the ledger through `/project-tasks` after
the code PR merges, and their IDs are written here in the first docs change after that merge, the one
that flips this record to `accepted`:

- a ranged fold layout (with a section folded, `NoteFolding.layout` reads the whole note on every update;
  414 ms at 1 MB by the parallel line's measurement);
- a bench row that carries embeds and view blocks, then each update pass made proportional or named with
  its number;
- TextKit's own bookkeeping of an insertion, and whether a note laid out lazily with a scroll anchor keeps
  fewer cached elements;
- the linear shift of ADR-0091 §D6, `shiftStyledRanges` (`NoteTextView+Coordinator.swift:875`) and
  `EditorDecorationDelegate.shift` (`EditorDecorationDelegate.swift:948`): about 19% of the 1 MB key
  ("Measured after", "What stays"), the largest term the app still owns.

## References

- Root `SPEC.md` (Approved 2026-10-11) and the plan `docs/plans/scoped-layout-followup.md`.
- ADR-0091 C4, §D2, §D6, §D8 to §D11 and "Measured after"; ADR-0082 §D5 to §D7 and §D9; ADR-0074 §D1
  and §D2; ADR-0081 §D4; ADR-0077 §D1; ADR-0045 (widening a `private`); ADR-0001 §D1;
  `docs/adr/README.md` rules 1 and 2.
- `PG-401`/#967; PR #971 (`18fb38e4`).
