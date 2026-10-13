# ADR-0096: What follows a keystroke compares a revision, not the note

- Status: **planned**. It reaches `main` with its plan (`docs/plans/no-whole-note-term-on-the-update-path-pg-406.md`)
  and the root `SPEC.md` in a docs PR ahead of the code (`docs/adr/README.md` rule 2). It stays `planned` until
  the code PR merges and the two human gates below are answered: the ceilings of the update-path row
  (G-ceiling-406, the SPEC's R-01) and the repeat of G-hand-405 (R-11). It then flips to `accepted`, naming the
  code PR, its merge commit and the date, in the first docs change after that merge.
- Date: 2026-10-12. Written against `93c17096`; re-dated on 2026-10-13 to `32cd8ed2`, the commit this build sits
  on (`git log -1 --format=%h HEAD`), which brought PG-387's note birth (`b429afb7`) in. Every line number below
  names that commit's tree, re-read there, unless the sentence says it names this build's code.
- Number: `0096`. Drafted as `0095` on 2026-10-12, when the highest number on `origin/main` was `0094` and no
  ref held `docs/adr/0095*`. On 2026-10-13 `origin/main` took `0095` for PG-392
  (`0095-the-board-controller-lives-with-the-vault.md`, merged by PR #1000, `5ead20db`), so this record was
  renumbered to `0096` before the code PR, with every reference in the sources, tests, plan and indexes.
  `0092` stays skipped for the reason ADR-0093's header records. Check again immediately before each merge
  (rule 1), including the branches about to merge.
- Source: root `SPEC.md` (Approved 2026-10-12), "No term proportional to the note on the SwiftUI path of a
  keystroke (PG-406)", R-01 to R-13; ledger entry `PG-406` (#990). This record registers the SPEC's six
  decisions and does not reopen them. It settles the two design items the SPEC left to the plan: how a revision
  is unique across buffers (D1) and how the pause check is scheduled and injected (D4).
- Relations:
  - **Extends ADR-0094 §D9.** §D9 left "the binding write that copies the note on every keystroke"
    (`NoteTextView+EditReplay.swift:25`) linear and outside its SPEC, and its "Ledger entries" closed the
    write itself and the compare in `updateNSView` with `ModelSync`. This record removes what SwiftUI does
    after that write: the diff of view inputs that carry the note, the change detection on the note, the
    per-body outline parses and the dirty flag. `ModelSync` is unchanged (D8).
  - **Narrows ADR-0073's departure 15 to the exact answer, without changing it.** `OpenNote.catchUp(to:)`
    decides "dirty and different" on the exact compare, as today; the cheap mark this record adds is never
    read there (D3). The quit review, Cmd+W, the chip's close and every save also decide on the exact compare.
  - **Adds a holder under ADR-0091 §D6, decided by §D3's rule and rebuilt by §D8's kill switch.** The outline
    is an offset-keyed store: it shifts where it lives, splices over the dirty range of a `.lines` decision,
    and rebuilds whole on every `.full` decision and on every pass with `-editorFullRestyle YES` (D6).
    ADR-0091's invalidation rule gains no case.
  - **Keeps ADR-0094 §D1 to §D3.** The outline store is an `OffsetRanges`, and its shift rule is
    `StorageEdit`'s.
  - **Keeps ADR-0082 §D7 and §D9.** The 1 MB hand check is the person's, on a Release build, and the ceilings
    are the person's.
  - **Keeps ADR-0001 §D1 and the `sharedSources` boundary of ADR-0007.** The two additions to `Sources/Core`
    (a per-line outline rule and a bounded frontmatter read) import Foundation only. `TextRevision`,
    `OpenNote` and everything else new are app-only.
  - **Keeps ADR-0065 §D1.2** (one delimiter test for every frontmatter reader, PG-276): the bounded read shares
    it. **Keeps ADR-0012 §D3** (closing a dirty tab asks), **ADR-0047 §D10** (the category is read from the live
    buffer), **ADR-0074 §D1** (the outline is a controller of its own, not a field of the coordinator).
  - **Not ADR-0011's version history.** "Revision" here is a change marker on one in-memory buffer.

## Context

**C1. The measurement.** G-hand-405 did not pass (ADR-0094, Gates, 2026-10-12, Release build of `main` at
`2871b6bc`, the 1 MB fences note). 2,393 of 3,214 main-thread samples (75%) sat in `AGGraphSetOutputValue`
comparing the previous and the new value of a view input, and 1,602 (50%) of those in the derived `==` of
`VaultController.OpenNote` (`Sources/Vault/NoteTab.swift:105`), which compares `text` through
`_stringCompareSlow` over a foreign `NSString`. The bench never saw it: its binding is `.constant` and it never
goes through SwiftUI.

**C2. What the same path holds, read from the tree.** The SPEC lists the family; reading the code adds four
members it does not name (marked *new*).

- `OpenNote`'s derived `==` (`NoteTab.swift:105`), compared wherever SwiftUI holds a value that contains one:
  `NoteTab` (derived `Equatable`, `:13`) inside the tab chip (`NoteTabBar.swift:46`, `:171`), and the open
  note itself inside `BacklinksSection` (`BacklinksSection.swift:15`, which reads `title` and `relativePath`)
  and `UnresolvedLinksSection` (`UnresolvedLinksSection.swift:11`, which reads `relativePath`), built by the
  inspector (`VaultBrowser.swift:202`, `:209`).
- `hasUnsavedChanges` (`NoteTab.swift:119`, `text != savedText`), read on every render by the tab chip's dot
  (`NoteTabBar.swift:210`), the save chip (`:77`), the breadcrumb and the save indicator
  (`VaultTopBar.swift:30`, `:42`), and *new*: by `canRun(.save)` (`CommandActions+CanRun.swift:35`), which the
  File menu's «Salva» evaluates (`VaultCommands.swift:102`) and which the column's body evaluates for every app
  entry of the slash menu (`EditorColumn+Text.swift:192`, through `EditorCommand.all(canRun:)`).
- The find modifier's `.onChange(of: text)` (`EditorColumn+Text.swift:327`): a whole compare per update, and a
  `NoteFind.run` per keystroke only while the bar is open (`FindSession.swift:98`).
- The outline: `NoteOutline.entries(in:)` plus the `NSRange` conversion (`EditorColumn+Text.swift:154-156`) and
  `foldedOrdinals(ofOffsets:in:)` (`:166`) in the column's body; the sidebar's own parse
  (`NoteListPane+Footer.swift:22`) plus `NoteFolding.foldableEntries(in:)` (`OutlinePane.swift:187-189`), which
  calls `line(of:)` once per heading, each a walk over every line (`NoteFolding.swift:211-218`), so it is
  quadratic; and *new*: the pane takes `text: String` as an input (`OutlinePane.swift:21`), so SwiftUI compares
  the whole note once more for it, the pane reads `vault.currentOutlineEntry` and `vault.foldedEntries` in its
  own body (`OutlinePane.swift:69`, `:155-162`, `:203`), so it is invalidated by every keystroke whatever its
  inputs, and the coordinator finds the caret's entry by a linear scan over every entry on every selection
  change (`NoteTextView+SelectionReport.swift:23`).
- *New*: the inspector's category row parses the whole note on every evaluation of the inspector's body
  (`VaultBrowser.swift:247`; `NoteDocument.parse` splits the whole text, `FrontmatterSource.swift:109-110`).
- *New*: Diario's model compares the whole prose on every binding write (`DiaryController.swift:28`,
  `guard prose != oldValue`), both sides foreign strings the editor wrote.

Oggi and Diario do not host the editor column, as the SPEC's R-10 words it: each builds `NoteTextView` directly
(`TodayView.swift:216`, `DiaryView.swift:109`). Oggi binds the open note (`vault.openNote?.text`,
`vault.updateOpenNoteText`), so it inherits D1 to D4; Diario binds its own `prose` and gets D9.

**C3. What must not change.** Typing, caret, undo, IME and marked text, list renumbering and the reveal under the
caret; the golden corpus (119 cases), byte for byte; `ModelSync`'s meaning; every decision that asks "is this
tab dirty" before closing, quitting, saving, following a rename or catching up (ADR-0073 departure 15); the
outline the editor, the sidebar and the fold read, equal to `NoteOutline.entries(in:)` over the same text.

## Decision

### D1. The revision, unique by a process-wide counter

`TextRevision` (`Sources/Vault/TextRevision.swift`, app-only, Foundation and `Synchronization`) is an opaque
`Hashable, Sendable` value wrapping a `UInt64`. `TextRevision.next()` takes the next value of one process-wide
`static let` `Atomic<UInt64>`, with `wrappingAdd(1, ordering: .relaxed)`. Checked in the installed SDK:
`Synchronization.Atomic` is available from macOS 15, and the deployment target is 27.0.

`OpenNote.text` gets a `didSet` that assigns `revision = .next()`, so every assignment, from any call site, makes
a revision no other assignment in the process ever made. That is R-03 by construction: two buffers that differ
in text got their texts from different assignments, so their revisions differ. Copies of one buffer share a
revision only while they share the assignment that made it, and so the text. Two buffers built separately
never share one, because each `init` draws its own.

The counter does not need to be ordered or dense; `.relaxed` is enough because the only property used is
uniqueness. 2^64 assignments do not wrap in the life of a process.

### D2. Equality by revision, and an explicit initializer

`OpenNote`'s `==` is written by hand over `relativePath`, `title`, `revision`, `savedRevision` and
`externalChangePending`. It never reads `text` or `savedText`. `externalChangePending` can hold a
`.text(String)`; it is compared only while a conflict banner is pending, and the value compared is the same
copy on both sides.

`NoteTab` and `EditorColumn` keep their derived `Equatable`, which is now constant in the note's size wherever
it is asked.

A consequence worth naming: two buffers holding the same text compare unequal. Nothing in the app compares buffers
for content (the plan's grep found no `==` between two `OpenNote`, `NoteTab` or `EditorColumn` values in the
sources or the tests), and for SwiftUI an unequal value means one more body evaluation, never a wrong one.

`OpenNote` gains an explicit `init(relativePath:title:text:savedText:externalChangePending: = nil)` with the
memberwise labels, so the one production site (`VaultController+Tabs.swift:407`) and the 46 constructions in 22
test files compile unchanged. The initializer draws a revision for `text`, and links `savedRevision` to it when
`text == savedText`: one compare, when a buffer is built, never on a keystroke.

### D3. The unsaved mark, and the exact answer

Two readings, as the SPEC's decision on the dirty flag sets them:

- **`hasUnsavedChanges` is the mark**: `revision != savedRevision`, constant time. It is true from the first
  keystroke, and it may read dirty late. It never reads clean while `text != savedText`, by the invariant below.
- **`differsFromSaved` is the exact answer**: `false` when the two revisions are equal, otherwise
  `text != savedText`. It is linear only for a buffer the mark already calls dirty, and only where it is asked.

**The invariant: `savedRevision == revision` implies `text == savedText`.** It holds because `savedRevision` is
set equal to `revision` in exactly four places, each of which knows the two texts are equal or has just compared
them:

1. `init`, after its one compare (D2);
2. `adopt(_:)`, which assigns the same string to `text` and to `savedText` (used by `catchUp(to:)`'s `.text`
   branch, `NoteTab.swift:156-157`, and by `acceptExternalChange`, `VaultController+Editing.swift:151-152`);
3. `recordWrite(_:)`, which assigns the text a write of this buffer landed and links only when the buffer still
   holds that text (D4);
4. `settleUnsavedMark()`, which runs the compare and links only when the texts are equal (D4).

Every other assignment to `savedText` gives `savedRevision` a fresh value. The only one is `keepLocalVersion`'s
`savedText = ""` over a note deleted on disk (`VaultController+Editing.swift:170` in this build), and it calls
`settleUnsavedMark()` straight after (`:173`). The mark stays on only for a non-empty buffer, which does differ
from the empty saved text; an empty buffer is linked there and reads clean at once, since no typing pause is
scheduled to clear it.

**Who reads which.** The name stays with the mark because the SPEC's decision names the flag `hasUnsavedChanges`.
The readers split as follows; a source guard in the plan keeps the decision sites off the mark.

| Reader | Site | Reads |
| --- | --- | --- |
| tab chip dot, save chip | `NoteTabBar.swift:210`, `:77` | the mark |
| breadcrumb, save indicator | `VaultTopBar.swift:30`, `:42` | the mark |
| «Salva» enabled, slash menu offer | `CommandActions+CanRun.swift:35` | the mark |
| catch-up (departure 15) | `NoteTab.swift:150` | exact |
| save | `VaultController+Editing.swift:59` | exact |
| save and close | `VaultController+Editing.swift:93` | exact |
| Cmd+W | `VaultController+Tabs.swift:106`, `CommandActions.swift:153` | exact |
| chip close button | `EditorColumn+Closing.swift:26` | exact |
| quit review | `QuitReview.swift:97`, `VaultController+Quit.swift:31` | exact |
| file and folder operations | `VaultController+Files.swift:34`, `VaultController+Folders.swift:31` | exact |
| rename follow-up | `VaultController+TabFollowUps.swift:76` | exact |
| note birth (extract, settled session) | `VaultController+NoteBirth.swift:105` (`sourceIsDirty`), `:152` (`settledSession`) | exact |

So the SPEC's edge case holds without a separate step: quit and close ask on the exact state, and a buffer whose
pause check has not run is verified at that moment, because the exact answer is the check. A «Salva» enabled by a
late mark finds nothing to write (`saveTab` answers `.clean` on the exact answer), which is the SPEC's "may read
dirty late".

**ADR-0073's departure 15 is unchanged.** `catchUp(to:)` still adopts an incoming `.text` equal to a dirty
buffer's text. It reads `differsFromSaved` where it read `hasUnsavedChanges`, so a buffer undone back to its saved
text before the pause catches up as clean, exactly as today.

### D4. The pause, and the save

`PauseScheduler` (`Sources/App/PauseScheduler.swift`) is a `@MainActor` protocol with `restart(_:)` and
`cancel()`. Production uses `TaskPauseScheduler`: `restart` cancels the pending `Task` and starts one that
sleeps for the interval (`Task.sleep(for:)`) and then runs the action on the main actor. The interval is
**500 ms**, proposed: at the five keys a second the SPEC names, keys arrive every 200 ms, so a pause of 500 ms is
"typing stopped" and the mark clears half a second after an undo back to the saved text. It is approved with the
plan or replaced there.

`VaultController.init` gains `typingPause: any PauseScheduler = TaskPauseScheduler()`, so every existing
construction compiles unchanged. `updateOpenNoteText(_:)` (`VaultController.swift:365`), the one door the editor's
binding writes through, restarts it. The action, `settleUnsavedMarks()`, walks every tab of every column whose
mark is on, runs `settleUnsavedMark()` on it, and writes the tab back only when the mark changed, so a pause over
a buffer that is still dirty mutates nothing and invalidates no view. Every tab, not only the one typed in: a tab
undone back to its saved text and left for the other column would otherwise keep its dot. Tests inject
`ManualPauseScheduler` (`Tests/ManualPauseScheduler.swift`), which records the pending action and runs it when the
test calls `fire()`: no test waits on a timer. `close()` and `switchVault(to:)` cancel the pending pause, so a check
scheduled over one vault never runs over the tabs of the next.

**A save links without waiting for the pause.** The writer's own catch-up (`caughtUp(with:savedBy:)`,
`VaultController+TabFollowUps.swift:51`), which `VaultSession.write` reaches before it returns
(`VaultSession.swift:702-706`), calls `recordWrite(result.text)` where it assigned `savedText`. When nothing was
typed during the write, the buffer still holds the very string it handed to the write (`saveTab` reads `note.text`
before the `await`, and `WriteResult` carries that value), so the compare is between two values sharing one
storage and costs nothing, the argument `ModelSync` already rests on (D8). The mark goes off at once, as today.
When something was typed, the compare reads up to the first difference, once per save, and the mark stays on,
which is the truth. The same door serves every writer that names its tab as `origin`, not only `saveTab`.

### D5. Narrow inputs

- **The tab chip** takes `NoteTab.ChipFace`: the tab's `id`, `title`, `relativePath`, `isPreview` and the mark.
  `NoteTab.chipFace` builds it, and it is declared on `NoteTab` because the chip itself is `private` to
  `NoteTabBar.swift`. A keystroke after the first changes none of its fields.
- **`BacklinksSection`** takes `title` and `relativePath`; **`UnresolvedLinksSection`** takes `relativePath`.
- **The find modifier** takes `revision` and a getter for the text. `.onChange(of: revision)` replaces
  `.onChange(of: text)`, and the query and option handlers read the text through the getter when they fire.
  `FindSession.update(in:)` keeps its `guard isOpen`, so with the bar closed a keystroke does no find work and no
  compare; with it open, the matches are recomputed on each revision, over the same text as today. Each run
  counts in `FindSession.updates`.
- **The inspector's category row** reads `NoteDocument.frontmatter(in:)` (`Sources/Core/Conventions`), a new read
  that splits lines only up to the closing delimiter, the way `components(separatedBy: "\n")` splits them (a CRLF
  line keeps its `\r`), and returns the same `Frontmatter` that `NoteDocument.parse(text).frontmatter` returns.
  The delimiter test stays one: `closingDelimiterIndex(in:)` gains a sibling over lines read in order,
  `closingDelimiterIndex(inLines:)`, and the array form calls it. It stays live, as ADR-0047 §D10 wants.
- **`canRun(.save)`, the save chip and the top bar** read the mark (D3).

### D6. The outline map and its store

**The rule, once.** `NoteOutline` gains `entry(inLine:)`, the per-line half of `entries(in:)` (a trimmed line is
an ATX heading by `headingLevel(of:)`, or an embed on a line of its own that is not remote, or nothing).
`entries(in:)` calls it, so the rule exists once. The embed's level is not part of that half: it depends on the
heading above (`min(enclosing + 1, 6)`, the enclosing level 1 when no heading precedes it), so it is derived on
read.

**`OutlineMap`** (`Sources/Features/Editor/OutlineMap.swift`, Foundation only, app-only) holds the entries as
`OffsetRanges<OutlineMap.Entry>`: each entry is the line's `NSRange` (the same range `NoteOutline` gives,
terminator excluded), its kind, its title and its line's terminator length in UTF-16 units. It does four things:

- `init(text:)` and `rebuild(text:)`: every entry of `NoteOutline.entries(in:)`, converted;
- `apply(_:)`: the shift, with `StorageEdit`'s rule through `OffsetRanges.apply(_:partial:)`;
- `splice(_:in:fences:)`: the entries of the dirty range's lines, through `entry(inLine:)`, skipping every line
  that intersects one of the fence regions, spliced over the range;
- the reads below (D7).

**When.** The coordinator drives it from the three places ADR-0091 §D6 already uses:

- `shiftDerivedState(by:)` (`NoteTextView+DerivedState.swift:43`) shifts it with every other holder;
- `applyIncrementalStyling` splices it over the `.lines` decision's range, after
  `restyleScope?.absorb(...)` (`NoteTextView+Coordinator.swift:823`), reading the fences from the absorbed map:
  `StructureMap.fences` are built from `CodeFence.regions(in:)` over the whole text (`StructureMap.swift:72-82`),
  the regions `NoteOutline` skips by;
- `settleBaseline` (`:762`), the full path's bookkeeping, rebuilds it whole. Every `.full` decision reaches it,
  and so does every pass with `-editorFullRestyle YES`, where nothing is recorded or shifted.

That is ADR-0091's rule with nothing added. A `.lines` decision never starts inside the frontmatter zone
(`RestyleScope.swift:139`, `.full(.frontmatter)` otherwise), which bounds `NoteOutline`'s body start from above;
`.full(.fenceLine)` covers a change of which lines are code; and a fence body is widened to the whole region,
where no entry can sit. A setext heading is not an outline entry (`NoteOutline` reads ATX only), and an edit
under one is line-local like any other; the property test carries it as one of the SPEC's structural cases.

**The store.** `OutlineStore` (`Sources/Features/Editor/OutlineStore.swift`) is a `@MainActor @Observable final
class` around one `OutlineMap`. Its map and its stamp are `@ObservationIgnored`; what views observe is `rows`, an
array of `OutlineRow` (kind, title, level, foldable), which holds no offset and is assigned only when one of its
values changes, with a `generation` bumped on each assignment. `rows` is recomputed over the replaced window, the
entry before it, and forward to the next heading (an embed's level follows the heading above it); a rebuild
recomputes all of it. The store counts its shifts, splices and rebuilds in `tally`, in every configuration.

**One store per editor column.** `VaultController` keeps them in an `@ObservationIgnored` registry keyed by
`EditorColumn.id`, made where the column is made (the controller's first column, `addColumn`, and the fresh
column `close()` and `switchVault(to:)` leave, which replace the whole registry) and dropped when the column
closes. A view body reads it without inserting (`registeredOutlineStore(forColumn:)`), so no update writes to
the controller. The column hands its store to the editor through `OutlineInputs.store`. A store follows the column's storage, not a tab: the coordinator feeds
whatever note its text view holds, and a tab switch is a full restyle that rebuilds it. A `NoteTextView` given
no store (Oggi, Diario, the tests that build one directly) keeps a private one, so the coordinator has one code
path. A store the coordinator has not fed is rebuilt from the storage before it is first read or spliced.

**The stamp.** The store records the `TextRevision` it describes. After each styling pass, in
`runEditPasses` and in `runPasses`, the coordinator stamps it with `OutlineInputs.currentRevision`, a getter that
reads the column's active tab live. On a keystroke the binding write comes first and the splice second
(`NoteTextView+EditReplay.swift:25-27`), so the stamp is the revision the write just made, before SwiftUI's
update runs. A reader that finds a stamp other than its note's revision has a store that has not caught up (a
note just opened, a text replaced from outside before the next `updateNSView`); it reads rows parsed from the
note's own text instead, without writing them into the store, and the coordinator's rebuild replaces them a pass
later. On a keystroke that never happens.

### D7. Who reads the store

- **The caret's entry.** The selection handler (`NoteTextView+SelectionReport.swift:23`) asks
  `OutlineMap.lastEntry(atOrBefore:)`, a binary search, for the same answer `outlineRanges.lastIndex { … }` gave.
  After a splice on the keystroke path it asks once more, so an edit that makes or unmakes an entry above the
  caret is reported without waiting for the next caret move; `claimOutlineEntry` still drops a repeat.
- **The fold.** `OutlineInputs.foldedOffsets` carries the tab's offsets (`NoteTab.foldedEntries`) unchanged, and
  `runPasses` translates them with `OutlineMap.ordinals(ofOffsets:)` before `applyFolding`
  (`NoteTextView+Update.swift:70-72`). Same rule as `foldedOrdinals(ofOffsets:in:)`: an offset names the entry,
  heading or embed, that starts exactly there, and an offset with no entry is dropped. With nothing folded it
  answers empty without reading the map. `NoteFolding.layout` itself is unchanged (`PG-402`).
- **The sidebar pane.** `OutlinePane` takes the rows, a source tag saying which rows they are (the store's
  identity and generation, or the revision they were parsed from), the note's path, the caret's entry, the folded
  ordinals and its closures, and is `Equatable` over everything but the closures. Its body reads no observed
  property of `VaultController`: the caret's entry and the folds arrive as inputs, so a keystroke that changes
  neither the rows nor the caret's entry leaves the pane equal, and the footer's `.equatable()` skips its body.
  `hiddenByFold` and the chevrons read the rows and the ordinals. A click hands the closure the entry's ordinal,
  and the footer resolves the line range and the heading's offset from the store at that moment. The drag
  validity and the drop still run `OutlineMove.replacements(in:…)` over the note's text, through a closure that
  reads the text when it runs, as today.
- **Foldable, from two neighbours.** `NoteFolding.foldableEntries(in:)` reduces to a local rule, which the rows
  use: a heading followed by another entry is foldable unless that entry is a heading of the same or a higher
  level starting on the very next line; the last entry is foldable when its line ends with a terminator. The
  property test holds it equal to `foldableEntries(in:)` after every edit.

### D8. `ModelSync` stays as it is

The revision is not used by `ModelSync`. `ModelSync` answers "the view holds what the model holds" from the
string the view last wrote and the storage's edit count, in constant time when the two strings share storage
(ADR-0094, "Ledger entries"). A revision would need the coordinator to learn the revision its own write
produced, and would answer the same question a second way. A model replaced from outside still gets a new string
and still falls through to the compare, so the SPEC's constraint holds by not touching it. One addition to the
record, not to its rule: after `updateNSView` assigns a model replaced from outside to the text view, it records
that string with `modelSync.wrote(_:)`, so the whole-text compare runs once per replacement, not once per update
until the next keystroke. The compare fallback counts in `ModelSync.compares`, so a test can say it did not run.

### D9. Oggi and Diario

Oggi binds the open note through `updateOpenNoteText`, so D1 to D4 reach it as they reach the Note pane. It passes
no outline inputs, so its coordinator keeps a private store nobody reads, at the cost of a splice per keystroke.

Diario's model gets `editorWrote(_:)`, which the editor's binding calls instead of the `prose` setter: it assigns
without the compare and records the edit and the save as the `didSet` does. The `didSet` itself checks `isLoaded`
before it compares, so a load never compares either. One behaviour moves, and the plan asks the person about it:
an editor write of the same characters (a selection replaced by itself) used to schedule no save and now
schedules one, which writes the bytes the file already holds. `proseCompares` counts the compares that remain.

### D10. Acceptance

- **The update-path row (R-01).** A hosted `EditorColumnView` in a window that is never shown, over a temporary
  vault holding the synthetic note, with the real `VaultController`, `Navigation`, `CommandActions` and
  `ShortcutStore`. One keystroke at the insertion point, then SwiftUI's update forced and checked: the
  coordinator's `restyleLog.skipped` advancing by one is the proof `updateNSView` ran. CPU milliseconds of the
  main thread for the six cases, printed as `restyle-budget-update` lines; the editor-only row of the same case is
  printed beside it, so the share the update path adds is read off directly. The column holds the tab bar and
  the editor; the sidebar and the inspector are not in it, and their terms are held by the counters, the pane's
  equality and the source guards below.
- **The counters (R-02, R-05).** On that path, per plain keystroke: `ModelSync.compares` 0, the store's
  rebuilds 0, `FindSession.updates` 0 with the bar closed, `VaultController.unsavedMarkChecks` 0 until the pause is
  fired. A fence keystroke rebuilds the store once (the structural fallback). Source guards pin that the column,
  the footer and the pane no longer call `NoteOutline.entries(in:`, `foldedOrdinals(` or
  `NoteFolding.foldableEntries(`, and that `OpenNote`'s `==` does not read `text` or `savedText`.
- **The property tests (R-06, R-07).** After every edit of `EditGenerator`'s random sequences, structural atoms
  included, the map equals `NoteOutline.entries(in:)` of the same text, its ordinals equal `foldedOrdinals`, its
  foldable set equals `foldableEntries`. The hosted twin compares the outline through `DerivedStateSnapshot`.
- **The hand check (R-11).** G-hand-405, repeated on a Release build by the person.

### D11. What stays, and its bound

- **Bounded by a construct.** `NoteFrontmatter.exists(in:)` (`NoteTabBar.swift:74`, `canRun(.toggleFrontmatter)`)
  and the bounded category read walk the frontmatter only; a note that opens with `---` and never closes it is
  read whole by both, on every update, as today.
- **Paid on a shape change, not a keystroke.** Typing inside a heading's title changes a row: the store copies
  `rows` and the pane redraws its rows, in proportion to the headings. No parse.
- **Paid once per pause, and once per save.** The pause's exact compare, on a buffer the mark calls dirty: one
  compare per dirty tab per pause, up to the first difference, the compare ADR-0094 measured at 37 ms for a
  whole 1 MB note in Debug. The save's `recordWrite`, when something was typed during the write.
- **Linear, outside this record.** TextKit's own bookkeeping (`PG-404`, about 53 ms of the 1 MB key in Debug and
  55 ms in Release, ADR-0094 "Measured after"); the fold layout with something folded (`PG-402`); the find bar's
  recompute while open (the SPEC's decision); the card's whole-text path.
- **Not measured by the row.** Every view that reads `vault.columns` is invalidated by every keystroke, because
  `columns` is one observed property: the note list, the inspector, the menus. Their cost grows with the vault,
  not the note. The repeat of G-hand-405 profiles the whole app; a term it names that is not this record's goes to
  the ledger (the SPEC's "Not yet specified", third item).

## Measured

**Where and how.** `Mac17,7` (Apple M5 Max), macOS 27.0.1 (build 26A434), Xcode 27.0 (27A266a). Debug
configuration, through `scripts/editor-restyle-bench.sh`: milliseconds of main-thread CPU per keystroke, the
minimum of K runs after one warm-up. The 50 KB and 200 KB rows come from `--runs 9 --update`, the 1 MB rows from
`--large-only --runs 3 --update`. The editor-only rows are the first table of the same run, so each share is read
inside one run. Debug numbers include the counters' increments (`ModelSync.compares`, the store's `tally`,
`FindSession.updates`, `unsavedMarkChecks`, `proseCompares`); a Release profile includes them too, at one
increment per event.

### Before (plan Task 1, on the old code)

Taken on 2026-10-13 on this branch over `32cd8ed2`, with only Task 1's test code and bench switch in the tree.
**Not a quiet machine:** the load average peaked at 17 during the first run and reached 58 during the second. The
minimum of K absorbs some of that, not all of it, so these rows are upper bounds.

| Size | Variant | Editor-only CPU ms | Through SwiftUI's update CPU ms | Share the update adds | K |
| --- | --- | --- | --- | --- | --- |
| 50 KB | fences | 3.45 | 49.19 | 45.74 | 9 |
| 50 KB | prose | 3.19 | 42.86 | 39.67 | 9 |
| 200 KB | fences | 10.71 | 229.27 | 218.56 | 9 |
| 200 KB | prose | 11.01 | 169.39 | 158.38 | 9 |
| 1 MB | fences | 56.54 | 2614.13 | 2557.59 | 3 |
| 1 MB | prose | 54.23 | 798.69 | 744.46 | 3 |

The editor-only rows agree with ADR-0094 "Measured after" within the load (3.00 to 53.27 ms there). What the
update path adds is from 12 to 45 times the editor's own key. Under the load noted above, it grows faster than the
note in the fences variant (about 4.8 times from 50 KB to 200 KB, 11.7 times from 200 KB to 1 MB, for notes 4 and
5.1 times larger) and about as fast as the note in the prose variant (4.0 and 4.7 times).

Observed while taking them:

- **The first keystroke after the open is a full restyle** (`restyleLog.full` 1 -> 2). Both runs kept the
  warm-up, which is untimed and comes first (`RestyleBudget.minimum`), so no row above times that keystroke.
- **The forcing mechanism.** `layoutSubtreeIfNeeded()` on the hosting view was enough to run SwiftUI's update
  after each key (4 of 4 keys); the plan's fallback, one turn of the main run loop, never fired, so no row includes a run-loop turn.

### After, the counters and the Release profile

**Not measured in this build; to be taken by the person on a quiet Mac before G-ceiling-406 and G-hand-405.** The
machine was saturated (load average 47) when plan Task 6 closed, and the person decided on 2026-10-13 to close it
without them. Not taken:

- the six update rows and their editor-only rows on the new code (the same two bench commands);
- the counter values `UpdatePathCounterTests` reads at 200 KB and 1 MB;
- the Release profile of a keystroke and its forced update (`sample` of the test host), with TextKit's terms, each
  app-owned term and its share, and whether any frame under SwiftUI's update still reads the whole note;
- a re-take of the "before" rows on a quiet machine.

No number in this record stands for any of them. D10's acceptance therefore rests, in this build, on the tests
alone: the counters (`UpdatePathCounterTests`, on the default 50 KB cases), the source guards, the property tests
and the unit suite.

## Restated tests

Each keeps its scenario and its expected outcome unless the line says otherwise; the reason is also written beside
the change in the test file.

- `Tests/VaultControllerExternalDeletionTests.swift`, `aBufferUndoneToCleanCanStillBeKeptAndSaved` (plan Task 2):
  calls `settleUnsavedMarks()` after the undo back, before requiring a clean buffer. The mark no longer compares the
  whole text on a keystroke, so it stays on until the pause settles it (D3); the test's point, `keepLocalVersion` on
  a deleted note turning a clean buffer dirty, is unchanged.
- `Tests/FoldBadgeClickTests.swift` and `Tests/EditorControllerReadTimingRemainingTests.swift`,
  `aBadgeClickAfterAParentSwapCallsTheNewOnToggleFold` (plan Task 4): pass `foldedOffsets:` instead of the entries'
  ranges and the folded ordinals, which left `OutlineInputs` (D7). `# Uno` is at offset 0, the ordinal's old value,
  so the number does not change.
- `Tests/EditorControllerReadTimingRemainingTests.swift`, the `OutlineEntryCallbackFiresOnChangeOnly` fixture (plan
  Task 4): no ranges are handed in; the coordinator's own store, built on first read from the text view's string,
  answers (D6, D7), because the fixture sets the string and moves the caret with no styling pass in between.
- `Tests/OutlinePaneFoldableOffsetTests.swift` (plan Task 4): the three cases ask
  `OutlineStore(text:).foldableOffset(ofEntry:)` instead of a pane built with the note's text, because the pane no
  longer holds the text (D7). Same texts, same entries, same expected answers; only the object asked changed.
- `Tests/ScrolledEditorFixture.swift` (plan Task 4): `fold(heading:)` writes the heading's UTF-16 offset into
  `outline.foldedOffsets` instead of its ordinal into `foldedEntries`, which the input no longer carries (D7); which
  heading is folded, and when, is as it was. `RestyleTwin` compares `outline` and names it when empty, because the
  store's outline is derived state the full-restyle twin rebuilds after every edit (D6).
- `Tests/OffsetShiftTests.swift` (plan Task 4): the expected snapshot below the edited paragraph keeps the outline
  entries below the boundary only, like every other offset-keyed field; the edited line's own entry is re-read by
  the splice, which this test does not run (D6).
- `Tests/SelectionReportHostedTests.swift` (plan Task 5): no ranges are handed in; the coordinator's own store,
  built from the same text, answers the caret's entry (D6, D7).
- `Tests/UnsavedMarkSourceGuardTests.swift`, `aDecisionSiteReadsTheExactAnswer` (merge with `origin/main`, 2026-10-13):
  a line naming `openBoard.hasUnsavedChanges` is no longer counted as a note decision site. `VaultController+Folders.swift`
  gained it from PG-392 (ADR-0095): it is the Workspace board's own mark, not an `OpenNote`'s. The note site beside it
  (`folderRefusal`) now reads `differsFromSaved`, and the guard still requires it.
- `Tests/UnsavedMarkTests.swift`, `everyAssignmentToTheTextMakesANewRevision` (plan Task 6): the red-phase step
  required a new revision after `catchUp(to: .text("c"))` on a dirty buffer. Departure 15 (ADR-0073, kept by D3)
  answers `.asked` there and assigns nothing, so the revision stays; the step now asserts that, and the catch-ups
  that do assign (a clean buffer, and `.adopted`) are the ones that must draw.
- `Tests/OutlineStoreTests.swift`, `theRowsFollowEveryEditOfARandomSequence` (plan Task 6): the per-seed
  non-vacuity floor goes from half the steps holding a row to a quarter, and a pooled floor of half is added. The
  seeds are fixed, so the counts are exact: rows in 36, 59, 60, 30 and 28 of 60 steps for seeds 1, 2, 3, 5 and 8
  (213 of 300 pooled). A seed that opens a fence early parks the rest of its run inside it, the structural case the
  generator exists to produce. The equality assertions are untouched.

## Alternatives considered

From the SPEC, registered and not reopened:

- **Fixing `OpenNote ==` alone.** Rejected: the next hand check would name the next term.
- **Outline and fold in a separate entry.** Rejected: per-body parses of the same shape, and the typing has to be
  usable now.
- **Narrow inputs only, or the revision only.** Rejected: the first leaves every future compare of `text`, the
  second leaves views diffing fields they do not read.
- **An outline reparse deferred to idle, or a lazy parse on caret change.** Rejected: the highlight and the pane
  lag, and the caret moves on every keystroke.
- **Dirty by revision alone.** Rejected: an undo back to the saved text would stay dirty until saved, which changes
  departure 15 and the quit review. **Exact on every keystroke.** Rejected: not shown constant-time.
- **Counters and the hand check without a bench row, or the hand check alone.** Rejected: no number would guard
  the path.

Raised by this design:

- **A UUID per assignment.** Unique as well. Rejected: a random draw and 16 bytes on every keystroke, for the
  guarantee the counter already gives.
- **A per-buffer identity plus a counter.** Rejected: R-03 breaks. `splitEditor` copies a dirty buffer into the
  other column; the two copies then diverge, and each reaches `(id, n + 1)` with a different text.
- **A hash of the text.** Rejected: linear in the note, the thing being removed.
- **Keeping `hasUnsavedChanges` exact and giving the mark a new name.** Every existing reader would keep
  compiling against the linear flag, so the compiler would point at none of the display sites. Rejected because
  the SPEC's decision gives the name to the cheap flag; the source guard over the decision sites does the
  compiler's job.
- **Linking a save by the revision `saveTab` read before its `await`.** Exact too. Rejected: only `saveTab` knows
  that revision, and every other writer that names its tab as `origin` would leave the dot on until the pause.
- **A run-loop idle observer for the pause.** Rejected: the run loop goes idle between two keys, so it would run the
  compare per keystroke, the opposite of the decision.
- **An outline store per tab.** Rejected: the coordinator feeds the note its storage holds; per tab, a tab switch
  hands it a store that describes another text, and the shift at the switch's own storage edit corrupts it before
  the rebuild.
- **The outline owned by the coordinator alone.** Rejected: the sidebar cannot reach a coordinator.
- **An invalidation rule of the outline's own.** Rejected: ADR-0091 §D6 makes the restyle's decision the one rule,
  and a second would need its own proof.
- **A cached category read keyed by the revision.** Rejected: the revision changes on every keystroke, so the cache
  would never hit on the path that matters. Reading the index instead was rejected by ADR-0047 §D10: an unsaved
  key shows at once.
- **Diario keeping its compare, with a ledger entry.** It keeps one behaviour exactly and leaves the one
  whole-note term this record would leave on a surface R-10 covers. Not rejected outright: it is the alternative
  put to the person at plan approval (Gates).

## Consequences

### Positive

- A keystroke after the first makes no SwiftUI input compare the note, no change detection read it, and no body
  parse it, on the Note pane and on Oggi.
- The sidebar outline stops being quadratic in a note's headings; the caret's entry is a binary search.
- Every whole-note compare left on the path is behind a counter a test reads.

### Negative

- Two names for "unsaved", with different costs. A new decision site that reads the mark is a defect the
  source guard catches only in the files it lists.
- Two buffers with the same text are unequal values. Harmless today (D2) and easy to forget.
- The unsaved mark can stay on for half a second after an undo back to the saved text.
- A second representation of the outline that must stay equal to `NoteOutline.entries(in:)`; the property test and
  the hosted twin carry it.
- A pause over a dirty 1 MB buffer can cost one whole compare, on the main thread.

### Neutral

- No on-disk format, frontmatter key, index schema or connector changes. No dependency is added.
- No GUI test is added. The card keeps the whole-text path.

## Gates

- **The interval and the Diario reading (plan approval). Not recorded yet.** This build implements the plan as
  proposed: a 500 ms default pause (D4) and Diario reading `editorWrote` instead of its compare (D9). The person's
  confirmation of both at PLAN APPROVAL is not recorded here; a different interval, or Diario keeping its compare
  with a ledger entry for it, would change that code.
- **G-ceiling-406 (the person, R-01). Not answered yet; a human gate, not performed in this build (plan Task 7
  step 4).** `RestyleBudget.updateCeilings` is not written and `aKeystrokeThroughSwiftUIsUpdateIsPrinted` asserts
  nothing on time: the ceilings are the person's values, and the "after" rows they would be read from were not
  taken ("Measured"). Fix the ceilings of the six `restyle-budget-update` rows. R-01's "under 20 ms at every size" cannot hold for the total at 1 MB: the editor-only row alone is 53 ms
  in Debug and 55 ms in Release, about 94% of it TextKit's (ADR-0094 "Measured after", `PG-404`). The proposal is
  that the 20 ms applies to the share the update path adds (the row minus the editor-only row), and that the
  total gets ceilings like PG-401's rows. The person decides.
- **G-hand-405, repeated (the person, R-11), on a Release build with the 1 MB fences note. Not answered yet; a
  human gate, not performed in this build (plan Task 7 step 6).** The checklist of
  ADR-0094's Gates, plus a `sample` of the typing: no frame in a whole-note compare or parse under SwiftUI's update.
  Its verdict is written here and in ADR-0094's G-hand-405 entry.

## Ledger entries

None yet. A term the repeat of G-hand-405 names that is not this record's is filed through `/project-tasks` and
its ID written here.

## References

- Root `SPEC.md` (Approved 2026-10-12) and the plan `docs/plans/no-whole-note-term-on-the-update-path-pg-406.md`.
- ADR-0094 §D1 to §D3, §D9, "Measured after", "Ledger entries" and Gates; ADR-0091 §D3, §D6, §D8, §D9;
  ADR-0073 §D4 and implementation notes, departure 15; ADR-0082 §D7 and §D9; ADR-0065 §D1.2; ADR-0047 §D10;
  ADR-0012 §D3; ADR-0074 §D1; ADR-0007; ADR-0001 §D1; `docs/adr/README.md` rules 1 to 3.
- `PG-406` (#990), follow-up of `PG-405` and `PG-401` (#967). `PG-402`, `PG-404`.
