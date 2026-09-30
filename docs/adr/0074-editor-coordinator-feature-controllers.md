# ADR-0074: The editor's Coordinator keeps the order of the passes; each feature's state moves into a controller that owns it

- Status: proposed. The implementation is not on `main`. Plan:
  `docs/plans/pg-144-editor-coordinator-feature-controllers.md`, which declares R-01 to R-10.
- Date: 2026-09-29. Written against `3cdc97fb` (`kepler/fix-fable-chain-debt`, clean tree).
  `origin/main` is at `06812344`. Of the files this record cites by line, only
  `Tests/MarkdownStylerTests.swift` differs between the two (695 lines on the branch, 741 on
  `main`), and the plan merges `main` in before its first task. Every line number, count and access
  modifier below was read from `3cdc97fb`. Lint findings come from `swiftlint 0.65.1` run against
  `.swiftlint.yml` on that tree. None is recalled from the ledger entry, which dates from 2026-09-12.
- **Renumbering note (2026-09-30).** Written and committed as ADR-0071 on
  `refactor/pg-144-editor-coordinator`, before PR #691 landed a different ADR-0071 (Contenitore,
  a managed document archive) on `main` and PR #684 and the PG-326 chain took 0072 and 0073.
  Main's 0071 keeps its number; this record moved to the next free one at the merge with `main`
  (`docs/adr/README.md` rule 1). The numbering note below is kept as written.
- **Numbering note.** `0070` is the highest ADR on `origin/main` (`06812344`), and
  `git log --all -- 'docs/adr/0071*'` is empty (checked 2026-09-29). Another chain is being
  specified in parallel, so check again immediately before the merge (`docs/adr/README.md` §1).
- Source: the `PG-144` entry in `TODO.md` (P2, chain "editor"), GitHub #244, from the audit of
  2026-09-12. There is no SPEC. The repo-root `SPEC.md` belongs to another chain and is not this
  one's input.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key, no
  `IndexCache.schemaVersion` change (it stays 5), no entry of `.claude/protected-interfaces`, no
  user-visible behaviour. Adds no GUI test and no exception to CLAUDE.md principle 2.
- **Amends one clause in each of three ADRs, the clause that names the owner, and nothing any of
  them decides about behaviour:** ADR-0019 §D6 ("the state lives on the Coordinator", the embed
  resize drag), ADR-0029 §D6 (the table grid store is "a `@MainActor` type on the Coordinator"),
  ADR-0033 §D2 (the view-block host is "built and owned by the Coordinator"). Each gains a dated
  amendment note at its head (plan Task 8). Its body is left as written.
- **Extends, and changes nothing of:** ADR-0018 §D2 and §D5 (reveal is a paragraph rule; the caret
  is taught the embed run), ADR-0019 §D7 (`replaceAtomically(_:with:in:)` is the one write
  mechanism), ADR-0029 §D5 (the table pass has its own hidden-line input, change check and caret
  rescue), ADR-0033 §D3 (hosts keyed by fence ordinal), §D4 and §D5 (the fence reveal and the
  crossing guard), §D15 (the third caret-rescue twin), ADR-0035 §D5 (the deferred, coalesced
  relayout), ADR-0037 §D6 and §D7 (the inline-span reveal, pushed from `applyStyling`), ADR-0053 §D2
  seam #4 (`modifierFlags` on the Coordinator, read at the moment the delegate method runs).
- **Takes early the extraction ADR-0028 A9 deferred**, without reopening A9's own decision (§D9).
  This is the one clause Stefano may veto on its own, at plan approval.

---

## Context

### What the audit found, and what holds today

`PG-144` names ten findings about the note editor. The ledger's own order is: remove the
duplicates first, since that shrinks the god object without touching TextKit dispatch; group the
inputs next; decide the sub-controller design last, in its own ADR. This record is that ADR. The
duplicate removals and the input grouping do not need an ADR (plan, "ADR outcome"). They appear
here only where they shape the design: §D8 and §D9.

Each finding was re-measured on `3cdc97fb`. All ten still hold. Two have grown, and one covers
more code than the audit named. The plan's disposition table is the per-finding record. What
matters for this decision:

| Measured | On 2026-09-12 | On `3cdc97fb` |
|---|---|---|
| Stored fields on `NoteTextView.Coordinator` (`NoteTextView+Coordinator.swift:12`) | 31 | **33**: 26 internal, 5 `private`, 2 `private(set)` |
| Lines in the Coordinator's extension files | ~2,270 | **2,284** across 12 files |
| Coordinator class body (lint) | not stated | 294 lines, `type_body_length` warning (limit 250) |
| Stored inputs on `NoteTextView` (`NoteTextView.swift:9`) | 37 | **38** |
| `updateNSView` (`NoteTextView.swift:321`) | 123 lines | 123 lines, lint body 71 (limit 50), complexity 12 (limit 10) |
| Caret-rescue copies | 3 | 3: `rescueCaret` (`+Coordinator:353`), `tableCaretRescue` (`+Tables:129`), `viewBlockCaretRescue` (`+ViewBlocks:264`) |

### The shape of the problem

The whole class is one declaration, `NoteTextView+Coordinator.swift:12-799`. Twelve extension files
add the features, one per file. The 33 stored fields can only be declared in the class body, so
all of them are declared in one file. Most of them are read and written only from one of the other
twelve.

Swift's `private` is scoped to the file, and so is a `private(set)` setter (ADR-0052 §D2 records
the same constraint for the Pratiche ledger). A field that one extension file writes therefore
cannot be `private`. Five of the Coordinator's own doc comments say so outright: "Not private
because the pass lives in `NoteTextView+Tables.swift`" and four siblings. The result is that 23 of
the 33 fields are module-wide mutable state belonging to one feature, and nothing stops the next
feature from writing another feature's field. The fields grouped by the feature that actually owns
them:

| Owner (the file whose pass writes it) | Fields |
|---|---|
| Tables (`+Tables.swift`) | `tableGrids`, `lastTableRows`, `drawnTables`, `pendingTableCaret` |
| View blocks (`+ViewBlocks.swift`, `+ViewBlockEditing.swift`) | `viewBlockHosts`, `lastViewBlockLines`, `drawnViewBlocks`, `pendingViewBlockCaret`, `pendingViewBlockRelayout`, `lastRevealedViewBlock` |
| Embed resize (`+EmbedResize.swift`) | `embedDrag` |
| Transclusion (`+Transclusion.swift`) | `lastRenditions`, `renditionCache` |
| Reveal (`+Reveal.swift`) | `lastRevealed`, `lastRevealedSpans` |
| Folding (`+Coordinator.swift:328-365`) | `lastFoldLayout` |
| Request bookkeeping (`NoteTextView.swift`'s `updateNSView`, `+Matches.swift`, `textViewDidChangeSelection`) | `lastFocusRequest`, `lastScrollRequest`, `lastMatchLocation`, `lastAppliedReplacements`, `lastAppliedReplacementTexts`, `lastNotePath`, `lastOutlineEntry` |
| The text view as a whole | `parent`, `textView`, `modifierFlags`, `undoManager`, `isStyling`, `decorations`, `unspellableRanges`, `embedRuns`, `embeds`, `frameObserver` |

Three ADRs put state there on purpose, by clause, and each was right for its feature at the time:
ADR-0019 §D6, ADR-0029 §D6 and ADR-0033 §D2. None of them decided that every feature's state
shares one access scope. That followed from where the class had to be declared.

### What must not move: the order of the passes

The order in which the passes run is load-bearing. Several ADRs rest on it, and it is written out
in four places:

- `applyStyling` (`+Coordinator.swift:446-571`): attributes, then the span walk, then the theme
  hand-over to `decorations`, then `applyTables`, `applyViewBlocks`,
  `decorations.apply(hiddenMarkers:)` and `apply(revealsInlineSpans:)`, then the storage's
  `endEditing`, then `refreshTableGrids`, `refreshViewBlockHosts` and the tracking areas. It runs
  under the re-entrancy flag `isStyling`.
- `textDidChange` (`+Coordinator.swift:366`): styling, embeds, transclusions, list renumbering,
  reveal, then the height with the caret revealed.
- `updateNSView` (`NoteTextView.swift:321`): styling, embeds, transclusions, folding, matches,
  reveal, height. Then come the one-shot requests in a fixed order: insertion (and the query builder
  it may open), focus, find, replacements, match jump, scroll.
- `makeNSView` (`NoteTextView.swift:157`): styling, embeds, transclusions, matches. It runs no
  folding, reveal or height pass.

These four sequences are different subsets of the passes, in different orders. That rules out any
design that turns the order into data (Alternative 2).

### Constraints read from the tree

- **`CompletingTextView+Pasteboard.swift` is a protected file** (`.claude/protected-interfaces`,
  `shasum` `6a6648fa242b1ba9b870bf01934379449c94c03f` on `3cdc97fb`), and its comments cite the
  editor by name: `NoteTextView+EmbedCaret.swift`'s `PendingEmbedDeletion`,
  `selectEmbed(at:in:)`, `NoteTextView+Reveal`, `applyReveal` and `NoteTextView+Coordinator.swift`.
  A change that makes one of those citations false cannot be repaired in that file.
- **The Workspace card borrows from the note editor.** `CardTextView.swift:396` and `:405` call
  `NoteTextView.Coordinator.linkDelimiters(in:of:)` and `NoteTextView.Coordinator.hiddenMarker(_:at:paragraphStart:)`.
  `CardTextView+Reveal.swift` calls `MarkupReveal`. `EditorDecorationDelegate` is shared too. The
  card has its own Coordinator with its own `lastRevealed`, `lastRevealedSpans` and fold state,
  which this ADR does not touch.
- **Tests build the Coordinator through `makeCoordinator()`** (for example
  `Tests/EmbedEditorTestSupport.swift:74`) and usually never set `coordinator.textView`. Every
  pass today takes the text view as a parameter.
- **Some entry points read the view's inputs when AppKit calls them, not when a pass runs.**
  `commitTable` reads `parent.hidesMarkup` and `parent.text` when a grid cell commits
  (`+Tables.swift:171-173`). `openTransclusion` and `unfold` read `parent.onFollowLink` and
  `parent.onToggleFold` on a click (`+Transclusion.swift:162`, `:178`). `applyReveal` reads
  `parent.matches`, `parent.currentMatch` and `parent.revealsInlineSpans` on a selection change
  (`+Reveal.swift:157-168`). Other values are captured once: a view-block host is vended with
  `parent.onFollowLink` and `parent.onEditQuery` captured at vend time (`+ViewBlocks.swift:191-200`).
  A move that changes *when* a value is read changes behaviour even if every line of logic is
  identical.

### Why this is an ADR

It passes all three parts of the test. It is expensive to undo, since the move touches around
twenty files and re-points 54 test reads. A future reader will want to know why feature state
sits in small classes the Coordinator forwards to rather than in the Coordinator, and why those
classes read their inputs through a closure. And real alternatives exist, each rejected below for
a stated reason. The ledger entry also asks for it in its own words: "the sub-controller design as
its own ADR".

## Decision

### D1. The Coordinator keeps the delegate conformances, the order of every pass and the text-view-wide state

`NoteTextView.Coordinator` stays the object AppKit and SwiftUI talk to. It stays the
`NSTextViewDelegate` and the `LinkNavigatingDelegate`, and `wire(_:to:)` keeps every claimant
chain as it is. The four sequences in the Context stay written out, call by call, in the functions
that run them today (`applyStyling`, `textDidChange`, `updateNSView`, `makeNSView`). No array, no
protocol and no controller decides the order.

It keeps the state that belongs to the text view rather than to one feature: `parent`, `textView`,
`modifierFlags` (ADR-0053 §D2 seam #4), `undoManager`, `isStyling`, `decorations`,
`unspellableRanges`, `embedRuns` and `frameObserver`. `embedRuns` stays beside
`unspellableRanges` because both are outputs of `applyStyling`, which stays here. The embed pass
reads it, but the styling pass writes it.

It also keeps the static helpers other types call: `hiddenKind(for:)`, `linkDelimiters(in:of:)`,
`hiddenMarker(_:at:paragraphStart:)`, `inContainer(_:of:)`, `verticalInset`,
`minimumHorizontalInset` and `horizontalInset`. Their names and signatures do not change.
`viewBlockBody(in:range:)` stays a Coordinator static in `+ViewBlockEditing.swift` too. It goes
from `private` to internal, so that `updateNSView`'s insertion step can call it instead of the
copy it inlines today (`NoteTextView.swift:397-402`). Its two callers, `commitViewBlock` and that
step, are not controllers.

### D2. Each feature that has state gets one `@MainActor final class`, declared in the file whose pass writes that state

| Controller | Declared in | Owns | Coordinator property |
|---|---|---|---|
| `TableBlockController` | `NoteTextView+Tables.swift` | the grid store, the drawn tables, the hidden rows, the pending caret; the table pass and the grid refresh | `tables` |
| `ViewBlockController` | `NoteTextView+ViewBlocks.swift` | the host store, the drawn blocks, the hidden lines, the pending caret, the relayout flag, the last revealed fence; the view-block pass, the host refresh, the height callback, the crossing test; the statics `revealedViewBlock`, `viewBlockRanges`, `selectionReveals` | `viewBlocks` |
| `EmbedTable` (exists, `+Embeds.swift`) | unchanged | as today | `embeds` |
| `EmbedResizeController` | `NoteTextView+EmbedResize.swift` | the drag in flight, the three phases, `handleRect(forEmbedAt:in:)` | `embedResize` |
| `TransclusionController` | `NoteTextView+Transclusion.swift` | the renditions drawn and the cache; the transclusion pass; opening one on a click | `transclusion` |
| `FoldController` | `NoteTextView+Folding.swift` (new) | the last fold layout; the folding pass | `folding` |
| `RevealController` | `NoteTextView+Reveal.swift` | the revealed paragraphs and spans; the reveal pass | `reveal` |
| `RequestLedger` | `NoteTextView+Requests.swift` (new) | the last focus, scroll and match-jump requests, the last replacement batch, the last note path, the last outline entry; one claim method per request | `requests` |

Each controller's state is `private` or `private(set)`. Its writers live in its own file, so the
compiler now enforces what five doc comments could only ask for. The Coordinator goes from 33
stored fields to 17: the ten text-view-wide fields of D1 plus seven controller references
(`embeds` is already one of the ten).

**The replacement ledger keeps its order.** `apply(_:to:)` records a batch *before* it validates
it, and `alreadyApplied(_:)` refuses to replay a batch it has seen (PG-093). `RequestLedger` keeps
exactly that order. No test pins it today (`Tests/OutlineMoveTests.swift` mentions it only in a
comment), so the plan adds one before the move.

**Structs that belong to a controller** (`DrawnTable`, `DrawnViewBlock`, `EmbedDrag`) stay where
they are declared, and keep their names.

### D3. A controller reads the view's inputs through one provider, at the moment it uses them

A controller holds no reference to the Coordinator and none to another controller. It receives at
`init`:

- a provider `() -> NoteTextView?` that the Coordinator builds as `{ [weak self] in self?.parent }`.
  It is a read of the inputs and nothing else: a controller cannot call the Coordinator through it;
- the text-view-wide collaborators it needs: `decorations` for most of them, and `embeds` for
  `EmbedResizeController`, the one controller that reads another's state (the renditions a handle
  is drawn on).

**Rule: a value is read when it is read today.** Where the current code reads `parent.X` inside a
callback, the controller calls the provider inside that callback. Where it captures `parent.X`
when it vends a host, the controller captures it at that same moment. The provider changes who
holds the reference, not when the value is read. Every site listed under "Constraints read from the
tree" is a case of this rule, and the plan names each one at the task that moves it.

A controller's methods take the text view as a parameter, as the passes do today. None reads the
Coordinator's `textView`, because the test harnesses do not set it. `EmbedTable` keeps its own
weak text view, as today.

### D4. Stateless text operations become statics on the Coordinator, keeping their names and their files

A controller that writes to the note still uses the one write door, so it has to reach it
without an instance of the Coordinator.

- `replaceAtomically(_:with:in:)` becomes a `static func` in `NoteTextView+EmbedCaret.swift`.
  ADR-0019 §D7, ADR-0023, ADR-0033 and ADR-0034 cite it by that selector as the one edit mechanism, and
  `CheckboxClick`'s and `TableEditTests`' comments cite its file. Instance call sites become
  `Self.replaceAtomically(…)`.
- `decoration(in:claimedBy:)` becomes a `static func` in `NoteTextView+Transclusion.swift`.
- `inContainer(_:of:)` is already static. `toggleCheckbox`'s inline copy of the same arithmetic
  (`+CheckboxClick.swift:26-27`) calls it instead.
- `growToFitTheText(_:revealingCaret:)` stays an instance method. No controller needs it.

The alternative was an `NSTextView` extension (`textView.replaceAtomically(_:with:)`). It is
rejected because it renames a selector that four ADRs and several comments cite as the one write
door, and a rename there is exactly the kind of drift the next reader cannot follow.

### D5. The Coordinator's entry points stay where production calls them: as one-line forwards when the state moved, with their bodies when there is no state

These keep their names and signatures and forward to the controller that now owns the work:

- `applyTables` and `applyViewBlocks`, which `applyStyling` calls in its sequence;
- `applyFolding`, `applyReveal` and `applyTransclusions`, which `updateNSView`, `textDidChange` and
  `textViewDidChangeSelection` call;
- `openTransclusion` and `resizeEmbed`, which the closures in `wire(_:to:)` call.

These stay Coordinator extensions with their bodies, because they own no state. Where they need a
controller's state, they read it through the controller's read-only accessors:

- the claimants `claimsEmbedCommand`, `claimsTableCommand` and `claimsListCommand`;
- `selectEmbed`, `embedMenu`, `toggleCheckbox`, `unfold`, `commitTable` and `applyMatches`;
- `commitViewBlock`, which reads the drawn source through `viewBlocks`;
- `apply(_:to:)` for replacements, which consults `requests`;
- `textViewDidChangeSelection`, which asks `viewBlocks` whether the selection crossed a fence and
  `requests` whether the outline entry changed.

`applyStyling` calls `tables` and `viewBlocks` directly for the grid and host refreshes. No
production code outside the Coordinator calls those, and no test does.

**No forward exists only for a test.** A test that reads moved state reads it on the controller
(`coordinator.viewBlocks.drawn`, not a `coordinator.drawnViewBlocks` kept alive for it). On
`3cdc97fb` that is 54 reads in five files, all of them reads and none a write:

| File | Reads |
|---|---|
| `Tests/ViewBlockCaretTests.swift` | 18: `drawnViewBlocks` 6, `lastViewBlockLines` 4, `Coordinator.revealedViewBlock` 8 |
| `Tests/EmbedResizeGestureTests.swift` | 12: `embedDrag` 8, `handleRect(forEmbedAt:in:)` 4 |
| `Tests/ViewBlockQuerySourceTests.swift` | 10: `drawnViewBlocks` 6, `viewBlockHosts` 4 |
| `Tests/MarkupHidingTests.swift` | 7: `lastRevealedSpans` |
| `Tests/ViewQueryEntryPointTests.swift` | 7: `viewBlockHosts` |

The receiver changes and the assertion does not. `Tests/CardConcealmentTests.swift` reads and
writes `lastRevealedSpans` too, but on the Workspace card's own Coordinator, which does not move.

### D6. Features without state stay Coordinator extensions

`+EmbedCaret`, `+TableCaret`, `+CheckboxClick`, `+ListEditing`, `+Matches` and the `unfold` half of
`+Transclusion` keep their current shape. A controller with no state would only add a hop, and the
compiler has nothing to enforce there.

### D7. No file is renamed

A controller lives in the `NoteTextView+X.swift` file its feature already has. Two new files are
added (`NoteTextView+Folding.swift`, `NoteTextView+Requests.swift`), and no existing file is
renamed or removed. The protected file cites `NoteTextView+EmbedCaret.swift`, `NoteTextView+Reveal`
and `NoteTextView+Coordinator.swift` by name, and it cannot be edited to follow a rename. The
other extension files keep their names too, for the same reason in a weaker form: a rename breaks
`git blame` and every doc comment in the tree that cites the file.

### D8. The block constructs share one line walk and one caret-rescue rule; their tails stay their own

`applyTables` (`+Tables.swift:41-106`) and `applyViewBlocks` (`+ViewBlocks.swift:54-142`) run the
same skeleton:

- the paragraph start at the anchor, and a `contentsEnd > start` guard;
- a `HiddenMarker` over `0 ..< contentsEnd - start`;
- a line walk from `end` to `NSMaxRange(recognised.range)` that fills a set of hidden line starts
  and an owner map;
- a change check, a caret rescue, and a pending caret applied after `endEditing` through
  `setSelectedRange` and `scrollRangeToVisible`.

That skeleton becomes one value type, `HiddenBlockLines` (in `Sources/Features/Editor/`, since
`HiddenMarker` lives there), and one rescue rule with one `placeCaret` step. The rule is "a caret
inside a line that has just left the layout goes to the target its owner names". Folding reuses the
rescue test through a target closure: the heading for a fold, the header for a table, the opening
fence for a view block (ADR-0029 §D5, ADR-0033 §D15).

What differs stays per construct: the grid store keys by header offset (ADR-0029 §D6), the host
store keys by ordinal (ADR-0033 §D3), and each has its own attachment and refresh.

The same move applies to `EditorDecorationDelegate`, whose six substitution branches (list, quote,
checkbox, table, view block, embed) repeat the same marker lookup, and three of them the same
attachment tail. One marker lookup and one attachment substitution are shared. Each branch keeps
its own guards: the `length > 0` guard of table and view block, and the collapse of the surviving
markers, which the checkbox applies only when the paragraph is not revealed. That half is a
duplicate removal with no design content, and it is in this record only because it changes the
same delegate the Workspace card uses.

### D9. ADR-0028 A9's accepted duplication is closed now, without waiting for a third caller

ADR-0028 A9 rejected merging `ListContinuation` into `LineFormat`. They answer different
questions, and that rejection stands: the two types stay separate. A9 also accepted "~40 lines of
digit-and-delimiter scanning" duplicated between them, noting that "a later extraction is cheap if a
third caller ever appears". No third caller exists. The audit nevertheless names the duplication
(`structure-ListContinuation.swift-f19`), and the tree shows it is wider than A9 counted: the
`Line` struct, `lines(in:)` (byte-identical once comments are stripped), `indentLength`,
`isChecklistMarker`, `matches` and `isDigit`.

They move into one Foundation-only type in `Sources/Core/Editor/`, which both enums call. The
trigger A9 named was about cost, not correctness. The cost is now paid inside a chain that already
touches these files, and after this chain a change to how a checklist marker is recognised is made
once, not twice.

**Stefano may veto this clause alone at plan approval.** On a veto, the finding is deferred with
A9 as the reason, and nothing else in this ADR changes.

## Alternatives considered

**1. Value-type state structs held by the Coordinator, with the logic left in the extensions.**
A `TableState` struct stored on the Coordinator is the mechanical move the audit warned against
("not a mechanical move"). Every extension could still write `tableState.pendingCaret` because the
stored property is internal, so it closes nothing, and it puts one more name between the reader and
the field. Rejected: access control is the whole point, and a struct stored on the Coordinator
inherits the Coordinator's scope.

**2. A pipeline: an ordered array of pass objects conforming to one protocol.** It would make
"add a feature" into "append a pass". It is rejected on two measured facts. The passes have no
common signature: styling takes a theme, folding a set of folded entries and a theme, matches a
match list and a current index, reveal nothing. And the four sequences in the Context are different
subsets in different orders, so one array is wrong, while four arrays are the four call lists again
behind one more indirection. The order is the most load-bearing fact in this code. It should stay
readable at the call site.

**3. Drop the forwards, and let `NoteTextView`, `wire(_:to:)` and the tests call the controllers
directly.** This saves a line per entry point. It is rejected for two reasons. The protected file
cites `applyReveal` and `selectEmbed(at:in:)` by name, and ADR-0019 and ADR-0033 cite `resizeEmbed`
and `applyViewBlocks` as Coordinator methods. And about sixty test calls would change receiver
for no gain in enforcement: `resizeEmbed` 43, `applyTransclusions` 6,
`applyReveal` 4, `applyViewBlocks` 3, `openTransclusion` 2, `applyFolding` 1. D2 already makes
the state unreachable, whichever object the call goes through.

**4. Stop after the duplicate removals.** This is the cheapest option, and it is the fallback if
gate G1 (plan) finds the first application too costly. As a decision it is rejected because the
root cause stays: 23 feature fields mutable from any file in the module, and the next editor
feature lands its state on the Coordinator because there is nowhere else for it to go.

**5. Controllers holding a weak or unowned reference to the Coordinator.** This is the easiest way
to move code without re-plumbing the inputs. It is rejected because every controller could then
reach every other controller's state through `coordinator.x.y`, and the ownership D2 buys would
only be nominal. The input provider of D3 gives the same reach to the inputs and none to state.

**6. Rename the extension files after their controllers** (`TableBlockController.swift`). This
makes names match types. It is rejected under D7: three of the files are cited by name from a file
nobody may edit.

## Consequences

**Positive**

- Feature state is `private` and has one owner, and the compiler enforces it. The Coordinator goes
  from 33 stored fields to 17, and its class body from 294 lint lines to an expected 180 or so
  (measured at plan Task 7).
- A new editor feature has a place to put its state that is not the Coordinator.
- The block passes, the caret rescue and the delegate's substitution preamble each exist once. A
  fix to one is a fix to all.
- Every controller's inputs are visible at its `init`, and every AppKit-time read is visible as a
  provider call.

**Negative**

- Reading a feature now takes one more hop: forward, then controller. The forwards are one line
  each and named after what they did before.
- 54 test reads are re-pointed and about ten test files change their `NoteTextView(…)` labels (plan
  Task 5). The diff is wide, even though no assertion changes.
- `git blame` on moved code stops at the move commits. `git log -C --follow` recovers it. The PR
  body says so.
- Seven small objects are allocated per editor instance. That is negligible next to one TextKit
  layout pass, and stated so it is not rediscovered as a finding.

**Neutral**

- `EditorDecorationDelegate`, `MarkupReveal`, the static span helpers and the Workspace card's own
  Coordinator are untouched in behaviour. The card depends on the first three and the plan's hand
  check covers it.
- Nothing about TextKit dispatch changes. The delegate is still not `@MainActor`, the
  content-storage and layout delegates are still `decorations`, and every substitution still keeps
  the paragraph's length.

## References

- `TODO.md` `PG-144`, GitHub #244; the audit findings it lists.
- `docs/plans/pg-144-editor-coordinator-feature-controllers.md`.
- ADR-0018 §D2, §D5; ADR-0019 §D6, §D7; ADR-0023; ADR-0028 A9; ADR-0029 §D5, §D6; ADR-0033 §D2,
  §D3, §D4, §D5, §D15; ADR-0034; ADR-0035 §D5; ADR-0037 §D6, §D7; ADR-0045 (the precedent for a
  structure refactor recorded as an ADR); ADR-0052 §D2 (a `private(set)` setter is file-scoped);
  ADR-0053 §D2 seam #4.
- `Sources/Features/Editor/NoteTextView+Coordinator.swift`, `NoteTextView.swift` and the twelve
  `NoteTextView+*.swift` files; `EditorDecorationDelegate*.swift`;
  `Sources/Features/Workspace/CardTextView.swift`;
  `Sources/Features/Editor/CompletingTextView+Pasteboard.swift` (protected).
