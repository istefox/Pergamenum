# ADR-0094: An edit moves a step, not every offset below it

- Status: **planned**. It reaches `main` with its plan (`docs/plans/sublinear-offset-state-pg-405.md`) and
  the root `SPEC.md` in a docs PR ahead of the code (`docs/adr/README.md` rule 2), and stays `planned`
  until the code PR merges and the human gates below are answered. It then flips to `accepted`, naming
  the code PR, its merge commit and the date, in the first docs change after that merge.
- Date: 2026-10-12. Written against `377b196e` (`origin/main`, the same commit). Every line number below
  was read there.
- Number: `0094`. On 2026-10-12 the highest number on `origin/main` is `0093`, and no local or
  remote-tracking ref holds `docs/adr/0092*` or `docs/adr/0094*` (`git ls-tree` over every ref, and
  `git log --all` on both paths printed nothing). `0092` stays skipped for the reason ADR-0093's header
  records: another line of work holds an unpublished file with that number. Check again immediately
  before each merge (rule 1), including the branches about to merge.
- Source: root `SPEC.md` (Approved 2026-10-12), "Sub-linear shift and splice of offset-keyed editor
  state", R-01 to R-15, ledger entry `PG-405` (no GitHub issue). This record registers the SPEC's seven
  decisions and does not reopen them. It settles the two items the SPEC left to it: the constant that
  bounds R-05 and R-06 (D5), and the public shape of the shared type (D2).
- Relations:
  - **Extends ADR-0091 §D6.** Every holder still shifts itself where it lives. The three stores that grow
    with the note's lines and the structure map now move a step instead of every entry, and their splices
    touch the dirty range only. The holders that grow with rare constructs, fold and reveal are unchanged,
    and their bounds are recorded (D8).
  - **Keeps ADR-0091 §D2, and adds to `StorageEdit`.** The rule stays the one in `StorageEdit`. It gains two
    predicates that classify a range against the edit, and the end-anchored fence rule, moved from
    `StructureMap` with the real new text length replaced by `oldLength + delta` (D3, which records the
    invariant that makes the two equal).
  - **Extends ADR-0093 "What stays"** (`0093-…md:567-573`), whose app-owned term this record removes, and
    **replaces ADR-0093 §D8's "What stays linear"** (`:332-333`): the fence parity becomes a rank (D6). §D8's
    contract (the window's start, its parity source, the scoped form's answer) is kept.
  - **Keeps ADR-0091 §D1 and ADR-0001 §D1.** The new types import Foundation only. They sit in
    `Sources/Features/Editor` and compile into the app target only, beside `StorageEdit` and `StructureMap`,
    because nothing they serve is shared with `perg` or `pergamenum-mcp`.
  - **Keeps ADR-0091 §D8 and §D9.** With `-editorFullRestyle YES` nothing shifts and every styling is full.
    The card keeps its dictionary and the whole-text path.
  - **Keeps ADR-0082 §D7 and §D9.** The 1 MB hand check is done by the person on a Release build, and the
    ceilings are the person's.
  - **Keeps ADR-0007 §D2.** No dependency is added.
  - **Keeps ADR-0074 §D1.** Each controller keeps its own state; no store moves between holders.

## Context

**C1. What a key still pays that grows with the note.** ADR-0093's profile of the 1 MB fences row (Debug,
"Measured after") puts 22% of the key in `recordStorageEdit`: `shiftStyledRanges` (901 samples),
`EditorDecorationDelegate.shift` (397) and `RestyleScope.record` (130). A further 11% is in
`applyIncrementalStyling`, where the splices are 130 + 110 + 74 samples. About 67% of the key stays inside
TextKit, which is `PG-404` and out of scope here.

**C2. Where the linear terms are.**

- The shifts. `shiftStyledRanges` (`NoteTextView+Coordinator.swift:882-885`) clips every unspellable range
  and shifts every embed run. `EditorDecorationDelegate.shift(by:)` (`EditorDecorationDelegate.swift:948-960`)
  rebuilds eleven tables, of which `hiddenMarkers` (one key per styled paragraph) grows with the lines.
- The splices. `splice(hiddenMarkers:in:hidingMarkup:)` (`:965-970`) filters every key.
  `applyIncrementalStyling` (`NoteTextView+Coordinator.swift:772-821`) runs `MarkdownStyler.spliced` over every
  unspellable range (`:808`), filters the embed runs twice (`:811-813`), and filters the map's view-block
  runs for an ordinal (`:799`).
- A hidden copy. `applyIncrementalStyling` binds `let scope = restyleScope` (`:773`), reads it at `:781` and
  `:799`, and mutates `restyleScope` at `:814`. While the binding is alive the map's storage is shared, so the
  mutation copies it whole.
- The map. `StructureMap.applying` (`StructureMap.swift:116-127`) moves every line below the edit, shifts the
  array with `replaceSubrange`, and maps every fence, code block, table run and view-block run.
  `StructureMap.splice` (`:142-158`) finds the window with a linear `firstIndex` and filters every run list.
- The scope's reads. `RestyleScope.renumberWindow` sums the delimiters of every line above the window
  (`RestyleScope.swift:89`). `widenOverRegions` gathers every fence on each call (`:166`). `pendingOpener`
  (`:223-229`) walks back to the nearest line with a bracket token and forward to a `]]`: the whole note
  above the caret in a note without wikilinks.
- The readers. The spell checker's question (`NoteTextView+Coordinator.swift:578`) scans every unspellable
  range. `currentViewBlockFences()` (`:871-877`) filters every fence on every selection change
  (`NoteTextView+ViewBlocks.swift:106-116`, called from `NoteTextView+Coordinator.swift:214`), so on every
  keystroke. `EmbedTable.apply(runs:…within:)` (`NoteTextView+Embeds.swift:138-139`) walks every run to find
  the ones inside the dirty range.

**C3. What must not change.** The result of every edit, byte for byte (SPEC constraint, ADR-0091 §D6). The
readers: TextKit's paragraph callback asks `hiddenMarkers[range.location]`
(`EditorDecorationDelegate.swift:441`, `:457`, `:570`, `:776`, and the substitution, list, quote and checkbox
renderers), and the tests read the stores through a key subscript, `keys`, `values`, `isEmpty`, the map's
`lines` as a collection and the run lists compared with an `[NSRange]`. R-03 forbids restating them. The test
snapshots (`DerivedStateSnapshot`, `DecorationSnapshot`) keep their value types.

## Decision

### D1. One engine: entries sorted by offset, split at a step

`StepBuffer<Entry: OffsetEntry>` holds entries sorted by position and split at one index, the step. Entries
before the step are stored with their absolute offset. Entries after it are stored relative to a pending
delta, which is added on read. Prior art in the same shape: Scintilla's line partitioning.

- **Storage.** Two arrays: `front` ascending, `back` descending, so the entry next to the step is
  `back.last`. Moving the step by one entry is a `removeLast` and an `append`, gaining or shedding the delta.
- **Reads.** Entry `i` is `front[i]`, or the matching `back` entry moved by the delta: O(1). One binary search,
  `partition(_:)`, answers every positional question in O(log n). It counts its probes, which R-04 reads.
- **The one mutation.** `replace(_ window:with:movingTheRestBy:as:)` moves the step to the window's end,
  adds the delta to the pending delta (which moves every entry after the step at once), drops the window
  from the end of `front` and appends the fresh entries. Cost: entries crossed by the step, plus the window,
  plus the fresh entries.
- **What it buys.** An edit at the place of the previous one crosses nothing. A far caret jump crosses the
  entries in between, once: the SPEC's accepted one-off, with a bench row of its own. This is a bound on the
  stores, not on the keystroke: the jump row's wall clock did not move ("Measured after").
- **Equality is logical.** Two buffers are equal when their current entries are, whatever their step, delta
  or tally.

### D2. Two shapes over the engine (the SPEC's "exact public shape")

**`OffsetTable<Value>`**, the keyed table (hidden markers by paragraph start):

- `init(_ table: [Int: Value])`, one sort. `subscript(key) -> Value?`, exact, through `lookup(_:)`, which
  also returns the probes. `keys` and `values` as collections in key order, `count`, `isEmpty`.
  `entry(atOrBefore:)` and `entries(in:)` for the containing-or-preceding and enumeration questions.
- `apply(_ edit:)` is `StorageEdit.shiftedKeys`. `replace(in dirty:with:)` is the delegate's splice: the keys
  inside `dirty` (`NSLocationInRange`) are dropped and the fresh entries merged, a fresh key winning.
- `==` against another table and against an `[Int: Value]`.
- It is **not** a `Collection`. A table whose keys are `Int` would answer `table[5]` both by position and by
  key, and every reader means the key.

**`OffsetRanges<Entry: RangedEntry>`**, the list of ranges (unspellable ranges, embed runs, the map's
fences, table runs and view-block runs), a `RandomAccessCollection` in location order:

- `apply(_ edit:partial:)`: `.clip` is `StorageEdit.clipped`, `.drop` is `StorageEdit.shifted`.
  `apply(_ edit:anchoringTheEndOf:)` is the map's fence rule (D3).
- `splice(_ fragment:replacing:)` is `StructureMap.spliced`'s partition. `spliceMerging(_:replacing:)`, for
  `NSRange` entries only, is `MarkdownStyler.spliced`.
- `intersects(_:)`, `count(endingAtOrBefore:)`, `indices(intersecting:)`, `indices(touching:)` and
  `entries(startingIn:)`, each O(log n) plus what it returns.
- `==` against another list and against an `[Entry]` either way round, so `map.tableRuns == runs` still
  reads as it does in the tests. It does not conform to `ExpressibleByArrayLiteral`, so an array literal on
  the right resolves to the array operator.

**`StepTally`**, the debug counter (D5), and the two protocols: `OffsetEntry` (`position`, `moved(by:)`) and
`RangedEntry` (`range`, `with(range:)`). `NSRange`, `StructureMap.Line` and `StructureMap.Fence` conform.

The full signatures are the plan's (Task 2), which is where the tester declares them.

### D3. The rule stays `StorageEdit`'s

The type never decides where an entry goes. It finds the window, the entries the edit reaches, and hands
each one to `StorageEdit`. Everything outside the window moves in bulk by the delta, or stays.

- **The window.** Two predicates are added to `StorageEdit`: `precedes(_:)` (the range ends at or before
  the old range's start) and `follows(_:)` (it starts at or after the old range's end), `precedes` winning
  when both hold, as in `shifted(_:)` and `shiftedKeys`. A key is the empty range at its offset. In a
  sorted list whose ends do not decrease (disjoint or touching ranges, or keys), the entries that neither
  precede nor follow are contiguous, so the window is two searches.
- **Inside the window,** each entry goes through `shifted(_:)`, `clipped(_:)` or `shiftedKey(_:)` as today.
- **The collision.** A deletion that ends exactly on a key, while the key at its start stays, makes the
  moved key win (`shiftedKeys`). Both keys sit at the window's left edge, so it costs O(1).
- **The end-anchored fence rule** (`StructureMap.swift:264-271`: a fence that reached the old end still
  reaches the new one) moves into `StorageEdit` as `shifted(_:anchoringTheEndOf:)`. It differs
  from `shifted(_:)` in three cases only: an insertion at the very end of the note, an insertion at the
  last fence's own start, and a deletion of exactly that fence. In each, the last fence ends up next to the
  step, so the rule costs O(1).
  - **One substitution, and the invariant it rests on.** The old rule took the real length of the new text.
    `StorageEdit` has no text, so it computes the new end as `oldLength + delta`. The two are equal only
    while `oldLength`, the map's `length`, is the length of the text the edit was made to. That holds
    because every edit reaches the map through `RestyleScope.record`, in order, and `record` leaves on
    `.full(.wholesale)` before `applying` on a wholesale replace and on every edit after it, until a full
    restyle rebuilds the map (the doc comment on `StorageEdit.shifted(_:anchoringTheEndOf:)`). A Debug
    `assert(oldLength + edit.delta == newLength)` in `StructureMap.applying` checks it on every applied
    edit; Release is unchanged.
- **The splices** are today's three: the delegate's filter-and-merge (`EditorDecorationDelegate.swift:965-970`),
  `StructureMap.spliced` (`:274-281`) and `MarkdownStyler.spliced` (`MarkdownStyler+Incremental.swift:25-54`).
  `spliceMerging` runs `MarkdownStyler.spliced` itself on the window, extended by one entry on each side for
  as long as the seam merges. `MarkdownStyler.spliced` stays in production as the rule and as the oracle the
  incremental-styler model already uses.
- **Two preconditions make the window splices equal to the whole-list ones.** They are recorded rather than
  assumed.
  - `MarkdownStyler.spliced` merges across its whole tail (`:45-52`), not only at the seam, while the window
    stops at the first entry that does not merge. The two agree when the entries after the dirty range are
    merged among themselves. A shift only ever leaves two ranges touching at an edit point, and the dirty
    range covers every edit since the last splice, so the condition holds. The hosted twin compares the
    unspellable ranges with a fully restyled editor after every edit (`ScrolledEditorFixture.swift:443`).
  - The embed splice (`NoteTextView+Coordinator.swift:811-813`) keeps an empty run at an empty dirty range
    twice, and `StructureMap.spliced` keeps it once. An embed run is a whole `![[…]]` run and is never empty,
    so the two agree and the embed runs take `splice`.

### D4. A copy is counted, not discovered in a profile

A struct copy that is alive across a mutation copies the arrays, which is O(n). Nothing but a profile would
see it, and the coordinator holds one today (C2). In a Debug build each buffer carries an `Owner` token, a
`final class` with no state. Every mutating operation asks `isKnownUniquelyReferenced` of it first. A shared
token counts one copy and `count` touched entries, then takes a fresh token. The counter tests assert no
copy on the keystroke path. The coordinator stops holding `scope` across `absorb`.

### D5. The counter and the constant (the SPEC's "Not yet specified")

**The counter.** `StepTally { touched, copies, shifts, splices, rebuilds }`.

- `touched` counts every entry the step crosses, every entry removed, inserted or rewritten, and a whole
  store on a copy. Binary-search probes are not counted here; R-04 reads them from `lookup`.
- The counting compiles only under `#if DEBUG`. The reading API exists in every configuration and reads
  zeros in Release, because `scripts/pg-401-gates.sh` builds the test bundle in Release. The counter tests
  run only when `StepTally.isCounting` is true.

**The constant: C = 64 entries per store per keystroke**, the shift and the splice together, with zero copies.

- **R-05.** An edit at the position of the previous one touches at most C entries in each of hidden markers,
  unspellable ranges, embed runs, and each of the map's stores (R-07).
- **R-06.** The first edit after a caret jump touches at most the store's entries between the two positions,
  plus C.
- **Why 64.** On the keystroke path each entry of the paragraph's window is handled at most five times:
  crossed at the edit, rewritten, crossed at the splice, removed, inserted. Add up to four for the collision
  and the seams, and a window of m entries costs at most 5m + 4. The bench paragraph
  (`RestyleBudget.insertionPoint`, the end of an "Altro testo con …" line) holds a handful of entries in any
  store. 64 leaves room for a window of twelve, and a regression to linear touches every line: thousands at
  50 KB.
- **A sharper check sits in the pure seam.** The same local edit touches the same number of entries at
  50 KB, 200 KB and 1 MB.
- If the hosted count of the bench paragraph is above 64, the build stops and reports. It does not raise
  the constant.

### D6. The structure map

- **`lines` is a `StepBuffer<Line>`.** `applying` keeps the map's own rule: the touched lines are replaced by
  the fresh ones, and every line after them moves by the delta, in one `replace`. `lineIndex(containing:)`
  is a `partition`.
- **The run lists.** `fences` is an `OffsetRanges<Fence>` taking the end-anchored apply. `tableRuns` and
  `viewBlockRuns` are `OffsetRanges<NSRange>` taking the dropping apply. All three take `splice`.
- **`codeBlocks` stays an `[NSRange]`.** It holds the fences two other parsers see where they part from
  `fences` (`StructureMap.swift:36-40`), and those can overlap, so it is not a sorted, disjoint list. It
  costs O(k), where k is the number of such disagreements. Neither bench variant is expected to have any,
  and Task 4 asserts it.
- **Three mark sets at line starts**, each a `StepBuffer<Mark>`, kept in step with `lines` by the same
  window replacement and built in `init`:
  - `oddFenceLines`: the lines whose `listFacts.fenceDelimiters` is odd;
  - `bracketLines`: the lines whose signature holds a bracket token;
  - `closingLines`: the lines whose tokens include a `]]`.

  They are stored properties, so the map's `==` and the property test against `StructureMap(text:)` cover
  them.
- **The parity** before line `i` is the rank of `lines[i].start` in `oddFenceLines`, modulo 2. A sum modulo 2
  is the count of its odd terms modulo 2, so the answer is today's.
- **The SPEC's edge case, read.** The edge case says the map answers parity "from the fence list". The list
  read here is the map's list of fence-delimiter lines as `ListContinuation` counts them, not `CodeFence`'s
  regions. ADR-0093 §D8 takes the parity from `listFacts`, and the two readers part on `~~~` and on indented
  fences, which is why `codeBlocks` exists. Taking it from `fences` would change a renumbering, which the
  byte-for-byte constraint forbids.
- **`pendingOpener`.** The nearest line with a token before line `i` is a predecessor in `bracketLines`, and
  "a `]]` somewhere after it" is a successor in `closingLines`. Both cost O(log n).
- **`widenOverRegions`** asks `fences.indices(intersecting:)` for the current range on each pass. It still
  loops over `codeBlocks`.
- **The readers.** The view-block ordinal is `viewBlockRuns.count(endingAtOrBefore:)`.
  `currentViewBlockFences(touching:)` returns the closed view-block fences touching the selection, through
  `indices(touching:)`, which is the shape of `selectionReveals`. `fenceRanges` takes the selection.
- **`frontmatterZoneEnd` is unchanged.** It is recomputed only for an edit inside the zone, which restyles
  the note.

### D7. The three stores and their call sites

- **`hiddenMarkers` is an `OffsetTable<[HiddenMarker]>`.**
  - `apply(hiddenMarkers:hidingMarkup:)` keeps its dictionary signature, for the full path and the card, and
    builds the table in one sort. Its guard compares the table with the dictionary.
  - `splice(hiddenMarkers:in:hidingMarkup:)` calls `replace(in:with:)`, and `shift(by:)` calls `apply`.
  - Every reader keeps its line: `hiddenMarkers[x]` is the exact lookup.
- **`unspellableRanges` is an `OffsetRanges<NSRange>`.** The full path builds it from
  `MarkdownStyler.merged`. The incremental path calls `spliceMerging`, the shift calls `apply(_:partial: .clip)`,
  and the spell checker asks `intersects`.
- **`embedRuns` is an `OffsetRanges<NSRange>`.** The shift calls `apply(_:partial: .drop)`, and the
  incremental path calls `splice`. `applyEmbeds` hands `EmbedTable.apply` the runs `entries(startingIn:)`
  finds in the dirty range, or every run when there is none. `EmbedTable.apply` keeps its signature and its
  own filter.
- **`DecorationSnapshot`** moves to `NoteTextView+DerivedState.swift`, beside `DerivedStateSnapshot`, so the
  delegate's file stays under SwiftLint's `file_length` error (994 of 1000 today).

### D8. What stays as it is, and its bound

These holders keep `StorageEdit.shiftedKeys` over a dictionary or a set. Each costs O(k), where k is what the
holder counts, and an empty one costs O(1). The SPEC rejected converting them, because the R-05 twin asserts
the identity of the grids and the hosts.

| Holder | Stores | k |
| --- | --- | --- |
| `EditorDecorationDelegate` | `hiddenLineOffsets`, `foldedHeadings` | lines hidden by folds, folded headings (`PG-402`) |
| `EditorDecorationDelegate` | `tableRowOffsets`, `tableViews` | table rows, tables |
| `EditorDecorationDelegate` | `viewBlockLineOffsets`, `viewBlockHosts` | view-block lines, view blocks |
| `EditorDecorationDelegate` | `renditions`, `embedRenditions` | transclusions, embeds |
| `EditorDecorationDelegate` | `revealedParagraphs`, `revealedSpans` | paragraphs the selection reveals |
| `TableBlockController`, `TableGridStore` | `drawn`, `hiddenRows`, `grids` | tables, table rows |
| `ViewBlockController` | `drawn`, `hiddenLines` | view blocks, their lines |
| `EmbedTable` | `renditions`, `pending` (and the `renditions` filter in `apply`) | embeds |
| `TransclusionController` | `lastRenditions` | transclusions |
| `FoldController` | `lastFoldLayout` | the folded sections (`PG-402`) |
| `RevealController` | `lastRevealed`, `lastRevealedSpans` | the revealed paragraphs |
| `StructureMap` | `codeBlocks` | code blocks the parsers disagree on |

### D9. What stays linear, and where it goes

- **Bounded by a construct, not by the note.** These are:
  - the list-seed back-walk, `stack(before:)` (`RestyleScope.swift:214-219`);
  - the renumber window's walk back to a line that ends every run (`:88`);
  - `listWalkEnd` (`:145-159`);
  - `extendOverTableRuns` (`:195-211`);
  - the frontmatter recomputation.

  Each is bounded by a list, a table or the frontmatter. The SPEC leaves the list walks to R-12's profile.
- **Linear in the note, outside this SPEC.** These are:
  - the binding write that copies the note on every keystroke (`NoteTextView+EditReplay.swift:25`);
  - TextKit's own bookkeeping (`PG-404`);
  - the fold layout (`PG-402`).
- **Linear, never on the keystroke path.** The test seams `offsetKeyedSnapshot`, `hiddenMarkerCount` and
  `derivedStateSnapshot`.
- **The ledger (R-14)** gets one entry for the binding write, and one for each other app-owned term that
  R-12's profile lists among the top terms. The IDs are written under "Ledger entries".

What SwiftUI does after the write is removed by ADR-0096; `ModelSync` is unchanged.

### D10. Acceptance

Four levels, as the SPEC's test seams set them:

- **The model tests (R-01, R-02).** Both shapes are checked against today's code as the oracle, over random
  edit sequences and the SPEC's edge cases.
- **The existing twins, unchanged (R-03, R-08, R-10).** These are the shift twin, the hosted twin, the map
  and renumber-window property tests, the golden corpus and the surface tests.
- **The counter (R-05, R-06, R-07, R-09).**
  - In the pure seam, at three sizes, the counts are equal across sizes.
  - On the real editor, 50 KB runs in every per-turn suite. 200 KB and 1 MB run behind
    `RESTYLE_BUDGET_200KB` and `RESTYLE_BUDGET_1MB`, through `scripts/editor-restyle-bench.sh`.
- **The bench (R-11).** It gains a row for the first keystroke after a caret jump, printed and never
  asserted. Its "before" is measured on the old code, before anything else lands.

## Alternatives considered

From the SPEC, registered and not reopened:

- **Only the two shifts ADR-0093 named.** Rejected: the splices of the same stores and the map are linear in
  the same way, so the cost would move rather than go.
- **A tree with relative offsets.** Rejected: it is O(log n) even after a jump, but it is more code and harder
  to keep identical to the one rule in `StorageEdit`.
- **Keeping the dictionaries and iterating only the tail.** Rejected: still O(n) on average.
- **A rule of its own inside the new type.** Rejected: two rules would drift.
- **A structure that is O(log n) in every case.** Rejected for the tree's reasons. The jump is paid once
  and measured.
- **Converting the rare-construct holders.** Rejected: it risks the identity of the table grids and view
  hosts for no measurable gain.
- **Pulling the fold state (`PG-402`) in.** Rejected: two ADRs would overlap.
- **The bench alone as acceptance.** Rejected: it is noisy under load, and a term that regrows would hide
  inside it.

Raised by this design:

- **One gap vector with empty slots, Scintilla's literal layout.** Rejected: a Swift array cannot hold
  uninitialised slots, so every slot would become an `Optional`, with more memory and an unwrap on every
  read. Two arrays move the step with the same `append` and `removeLast`.
- **A keyed table that is itself a `Collection`.** Rejected: `table[5]` would be ambiguous between an index
  and a key, and the hot-path readers and the tests all mean the key.
- **The step without the copy counter.** Rejected: a copy alive across a mutation is O(n) and invisible to a
  touched-entries counter, and the coordinator holds one today.
- **Parity from `CodeFence`'s regions.** Rejected: the two readers part on `~~~` and on indented fences, so
  a renumbering would change (D6).
- **Leaving `pendingOpener`'s walk for the ledger.** Rejected under the SPEC's perimeter decision (every
  linear term, the structure map included). The walk is linear in a note with no wikilink above the caret,
  which the bench cannot show, because every bench group carries one. It is closed by the same mechanism as
  the parity.
- **Rewriting the tests' reads to a new API.** Rejected: R-03 forbids it, and the shapes answer the reads the
  tests already make.
- **The types in `Sources/Core`.** Rejected: `StorageEdit` and every consumer are app-only, so the tools would
  compile code they never call, and `StorageEdit` would have to move with it.

## Consequences

### Positive

- A keystroke at the place of the previous one moves, rebuilds and scans the three stores and the map in
  entries bounded by its paragraph, at any note size. In those stores a jump pays the entries crossed, once.
- The copy the coordinator makes today on every incremental restyle is gone, and any later one is counted.
- Six scans that grew with the note answer by search: the parity, `pendingOpener`, `widenOverRegions`, the
  view-block ordinal, the spell checker's question and the fence reveal.
- The shift and splice code of four holders becomes calls into one engine whose rule is `StorageEdit`'s.

### Negative

- Three new files and a second representation that must stay logically equal to the first. The model
  tests carry that.
- A hidden-marker read is a binary search (about 16 probes at 1 MB) instead of a hash lookup. TextKit asks
  once per laid-out paragraph, so the cost is a whole-note layout's few milliseconds, not a keystroke's.
- The full path sorts the hidden-marker keys once, O(n log n), inside a restyle that is O(n) already.
- A far caret jump costs the stores the entries in between: linear in the distance, once.
- The first keystroke after a far caret jump is not made cheaper. The jump row reads the same before and
  after (1.5 to 2.3 s at 1 MB in Debug), and the counters say the stores are not where that time goes
  ("Measured after").
- Debug numbers include the counting. Release carries none of it.
- `MarkdownStyler.spliced` stays in production. It is the rule `spliceMerging` runs on its window.

### Neutral

- Release behaviour, every on-disk format, the index schema and both connectors are unchanged.
- No GUI test is added. The card keeps the whole-text path.

## Measured before

Taken on 2026-10-12 by `scripts/editor-restyle-bench.sh` on the uncommitted tree of
`feature/sublinear-offset-state-pg-405` (on `377b196e`) with only Task 1 of the plan in it, so every number
is the old code's. Mac `Mac17,7` (MacBook Pro, Apple M5 Max, 36 GB), macOS 27.0.1 (build 26A434), Xcode 27.0
(27A266a), Debug build: milliseconds of main-thread CPU per keystroke, the minimum of K runs after one
warm-up. The 50 KB and 200 KB rows come from `--runs 9 --jump`, the 1 MB rows from `--large-only --runs 3
--jump`. **Not a quiet machine:** another session's `xcodebuild` ran in another worktree, with a load
average of 10.17 at the start of the first run and 6.23 at the second. The minimum of K absorbs some of
that, not all of it.

The six rows:

| Size | Variant | CPU ms | Wall ms | K |
| --- | --- | --- | --- | --- |
| 50 KB | prose | 4.75 | 4.75 | 9 |
| 50 KB | fences | 4.98 | 4.99 | 9 |
| 200 KB | prose | 21.61 | 21.61 | 9 |
| 200 KB | fences | 23.86 | 23.86 | 9 |
| 1 MB | prose | 85.72 | 85.76 | 3 |
| 1 MB | fences | 91.42 | 91.48 | 3 |

**The fallback rows** (printed, never asserted; ms of CPU):

| Size | Variant | `fence-open` | `table` | `list-enter` |
| --- | --- | --- | --- | --- |
| 50 KB | prose | 242.27 | 9.02 | 424.94 |
| 50 KB | fences | 282.32 | 5.78 | 360.45 |
| 200 KB | prose | 976.62 | 21.04 | 1433.45 |
| 200 KB | fences | 1385.22 | 26.78 | 1703.99 |
| 1 MB | prose | 5624.53 | 118.45 | 9453.36 |
| 1 MB | fences | 11805.24 | 119.57 | 14549.15 |

**The jump rows** (printed, never asserted): the first keystroke at the middle paragraph after one typed
near the top. `crossed` is the number of lines between the two edit points.

| Size | Variant | CPU ms | Wall ms | `crossed` | K |
| --- | --- | --- | --- | --- | --- |
| 50 KB | prose | 50.96 | 51.01 | 1060 | 9 |
| 50 KB | fences | 54.14 | 54.18 | 1125 | 9 |
| 200 KB | prose | 214.66 | 214.76 | 4240 | 9 |
| 200 KB | fences | 250.22 | 250.49 | 4500 | 9 |
| 1 MB | prose | 1557.38 | 1558.38 | 21580 | 3 |
| 1 MB | fences | 2324.09 | 2326.21 | 22921 | 3 |

**The plan's premise about the jump was wrong.** The plan expected a keystroke after a caret jump to cost,
on the old code, what a plain keystroke costs, because every old shift is linear whatever the distance. It
does not: at 1 MB the jump row reads 1.5 to 2.3 s against 86 to 91 ms for the plain keystroke, and at 50 KB
about 51 to 54 ms against about 5 ms, ten to twenty-five times as much. Wall time equals CPU time, so the
main thread is busy rather than waiting. **The cause is unprofiled.** The candidates are TextKit laying out
again after the caret moves far, which this record does not touch, and the old per-line shift of every
offset-keyed holder; neither has been measured apart from the other. "Measured after" reads the same rows on
the finished tree, and R-12's profile is where the cause would show, if it is app-owned.

## Measured after

Taken on 2026-10-12 by `scripts/editor-restyle-bench.sh` on the uncommitted tree of
`feature/sublinear-offset-state-pg-405` (on `377b196e`) with plan Tasks 1 to 7 in it. Same Mac, OS and
Xcode as "Measured before": `Mac17,7` (Apple M5 Max), macOS 27.0.1 (build 26A434), Xcode 27.0 (27A266a).
Debug build **with the counting of D5 compiled in**: milliseconds of main-thread CPU per keystroke, the
minimum of K runs after one warm-up. The 50 KB and 200 KB rows come from `--runs 9 --jump`, the 1 MB rows
from `--large-only --runs 3 --jump`. **Not a quiet machine either:** a stuck process outside this repository
(a `git ls-remote` at 98% CPU for 23 hours) ran throughout, with a load average of 7 to 11 at the first run.
The minimum of K absorbs some of that, not all of it. The ceilings in `RestyleBudget.ceilings` are not
changed here: the person fixes them at G-ceiling-4 (Gates).

The six rows, before from "Measured before":

| Size | Variant | Before CPU ms | After CPU ms | After wall ms | Ratio | K |
| --- | --- | --- | --- | --- | --- | --- |
| 50 KB | prose | 4.75 | 3.03 | 3.03 | 1.6× | 9 |
| 50 KB | fences | 4.98 | 3.00 | 3.00 | 1.7× | 9 |
| 200 KB | prose | 21.61 | 10.01 | 10.00 | 2.2× | 9 |
| 200 KB | fences | 23.86 | 10.79 | 10.80 | 2.2× | 9 |
| 1 MB | prose | 85.72 | 53.08 | 53.14 | 1.6× | 3 |
| 1 MB | fences | 91.42 | 53.27 | 53.30 | 1.7× | 3 |

The plain keystroke gets cheaper at every size, and the two variants now read within 1 ms of each other
at every size. It still grows with the note (3 ms at 50 KB, 53 ms at
1 MB), and the profile below says that growth is TextKit's.

**The fallback rows** (printed, never asserted; ms of CPU, before / after):

| Size | Variant | `fence-open` | `table` | `list-enter` |
| --- | --- | --- | --- | --- |
| 50 KB | prose | 242.27 / 246.02 | 9.02 / 3.54 | 424.94 / 347.26 |
| 50 KB | fences | 282.32 / 279.16 | 5.78 / 3.82 | 360.45 / 360.16 |
| 200 KB | prose | 976.62 / 988.93 | 21.04 / 14.05 | 1433.45 / 1443.49 |
| 200 KB | fences | 1385.22 / 1288.40 | 26.78 / 14.85 | 1703.99 / 1624.52 |
| 1 MB | prose | 5624.53 / 5669.86 | 118.45 / 75.40 | 9453.36 / 9600.92 |
| 1 MB | fences | 11805.24 / 11945.52 | 119.57 / 86.36 | 14549.15 / 14073.35 |

`fence-open` and `list-enter` still cost a full restyle, as ADR-0091 says they must. A keystroke in a table
cell is a ranged restyle and gains with the plain keystroke.

**The jump rows** (printed, never asserted; ms; ratio is before over after CPU):

| Size | Variant | Before CPU ms | After CPU ms | After wall ms | Ratio | `crossed` | K |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 50 KB | prose | 50.96 | 53.59 | 53.61 | 0.95× | 1060 | 9 |
| 50 KB | fences | 54.14 | 56.28 | 56.31 | 0.96× | 1125 | 9 |
| 200 KB | prose | 214.66 | 227.74 | 227.88 | 0.94× | 4240 | 9 |
| 200 KB | fences | 250.22 | 252.89 | 253.08 | 0.99× | 4500 | 9 |
| 1 MB | prose | 1557.38 | 1608.50 | 1609.90 | 0.97× | 21580 | 3 |
| 1 MB | fences | 2324.09 | 2315.72 | 2317.78 | 1.0× | 22921 | 3 |

**The jump row did not move.** The counters hold R-06 for the stores: the first keystroke after the jump
touches only the entries between the two positions plus at most C. So the step
makes a jump cheap for the stores, as D1 and D5 say, but not for the wall clock: 1.5 to 2.3 s at 1 MB and
about 54 ms at 50 KB, before and after, within the noise of a loaded machine. That rules out the second
candidate "Measured before" named, the old per-line shift of the offset-keyed holders. The likelier cause
is TextKit laying the text out again after the caret moves far. **It is unprofiled:** R-12's profile below
is of the plain keystroke, not of the jump, so this record does not name the cause as measured. The jump
is a candidate ledger entry ("Ledger entries").

**The hosted counters** (R-05, R-07, R-09; the `touched` count of one keystroke at the bench paragraph).
The values are the same at 50 KB, 200 KB and 1 MB, in both variants, and
`copies` is 0 in every store:

| Store | `touched` | `copies` |
| --- | --- | --- |
| `hiddenMarkers` | 2 | 0 |
| `unspellableRanges` | 4 | 0 |
| `embedRuns` | 0 | 0 |
| `StructureMap.lines` | 4 | 0 |
| `StructureMap.fences` | 0 | 0 |
| `StructureMap.tableRuns` | 0 | 0 |
| `StructureMap.viewBlockRuns` | 0 | 0 |
| `StructureMap.oddFenceLines` | 0 | 0 |
| `StructureMap.bracketLines` | 4 | 0 |
| `StructureMap.closingLines` | 4 | 0 |

The largest is 4, against C = 64 (D5), and no count changes with the note's size, which is R-05's claim.
The per-store counts of the jump keystroke were not recorded, only that R-06's assertion holds.

**The profile (R-12).** Release build (`-derivedDataPath build/pg401-gates-dd`). Unsampled first, the whole
`EditorRestyleBudgetTests` class with `RUNS=30`: 1 MB fences 55.35 ms CPU and 66.76 ms wall, 1 MB prose
54.47 and 66.53. Release reads about what Debug reads at 1 MB, which agrees with the profile: most of the
key is spent in TextKit, a system framework the build configuration does not change.

Then `sample <pid> 120 -file build/pg405-release-sample.txt` attached to a rerun of
`EditorRestyleBudgetTests/aKeystrokeInTheMiddleStaysUnderItsCeiling(_:)` with `RESTYLE_BUDGET_RUNS=100`.
**Two deviations from the plan's "one sample of a 1 MB fences keystroke":** the test function runs both
variants, so the window covers the fences row first and then the prose row; and a first attempt over the
whole class, which mixed in the fallback scenarios, sampled a `clang` process by mistake and was discarded.
`sample` slows the host (133.16 ms fences and 125.71 ms prose under it), so the shares are valid and the
milliseconds are not. 24,481 samples under `-[NSTextView insertText:replacementRange:]`:

| Where | Share | Owner |
| --- | --- | --- |
| `NSTextContentStorage` `processEditing`: the enumeration over every cached element | 62.0% | TextKit |
| `synchronizeTextLayoutManagers` from `endEditing` | 15.2% | TextKit |
| `growToFitTheText` → `_updateContentSizeIfNeeded` → `estimatedSizeForLastTextContainer` | 7.1% | TextKit |
| `synchronizeTextLayoutManagers` inside `applyIncrementalStyling` | 5.2% | TextKit |
| `LayoutDebt.settle` → `ensureLayout` | 2.1% | TextKit, asked by ADR-0093 §D4 |
| `TransclusionController.scanOccurrences` → `Transclusion.occurrences(inFragment:)`: 1,055 samples, of which `CodeFence.regions` 2.1% and `lineRanges` 1.7% | 4.3% (4.6% inclusive) | the app |
| `MarkdownStyler.spans` 0.4%, `ViewBlockController.refresh` 0.2%, `StructureMap.init(text:)` for the fragment 0.2% | under 1% | the app |
| `recordStorageEdit` (26 samples), `StructureMap.applying` (17), `RestyleScope.record` (17), `shiftDerivedState` (8), `EditorDecorationDelegate.shift` (5), `StructureMap.splice` (3), `renumberLists` (2), `OffsetRanges.apply` (1), `StepBuffer.moveStep` (1) | each 0.1% or less | the app |

About 94% of the key is TextKit's and about 6% the app's.

**R-12's answer.** The shift, the splice, `spliceMerging`, `replace`, `StructureMap.applying` and
`StructureMap.splice` are **not** among the app-owned top terms: together under 0.3% of the key, where
ADR-0093's profile put `shiftStyledRanges`, `EditorDecorationDelegate.shift` and `RestyleScope.record` at
22%. The two profiles are not directly comparable (ADR-0093's was Debug and fences only, this one Release
and both variants), but the term ADR-0093 "What stays" named is gone from the top.

**What stays.** At TextKit's floor, as in ADR-0093: the content storage's walk over its cached elements
(62%), the layout managers' synchronisation (15% + 5%) and the size estimate (7%), all proportional to the
paragraphs the note holds (`PG-404`). App-owned, the next term is the transclusion occurrence scan, 4.3%,
run on the dirty fragment; this profile cannot say whether it grows with the note. The list walks of D9 are
2 and 1 samples, so they are not filed and stay recorded as bounded by a list (D9). The binding write
(`NoteTextView+EditReplay.swift:25`) is absent from the profile because the test fixture's binding is
`.constant`, so the profile cannot measure it; its ledger entry stands on D9's reading of the code.

## Gates

- **The constant (plan approval).** C = 64 (D5) is approved with the plan, or replaced there. Measured: the
  largest hosted count is 4 ("Measured after"), so the build did not stop on it.
- **G-ceiling-4 (the person, R-11). Not answered yet.** Fix the six ceilings from "Measured after", starting
  from G-ceiling-3's values if `feature/pg-401-ceilings` has landed by then. Decide whether the jump row gets
  a ceiling. The proposal is that it does not: it stays printed, and the counter is its guard. The counter
  guards the stores only; the jump row's wall clock is TextKit's and unchanged ("Measured after").
  `RestyleBudget.ceilings` keeps its current values until the person answers.
- **G-hand-405 (the person, R-13), on a Release build with a 1 MB note.** Type at the end and in the
  middle, Enter, a wrapping sentence, Cmd+Down, scroll to the end, click low in the pane, undo and redo, and
  an IME composition. Added for D1's step: type near the top, then at the end, three times over.
  `-editorFullRestyle YES` isolates this record's change without a rebuild. **Not passed (2026-10-12,
  Release build of `main` at `2871b6bc`, fences note of 1 MB in a throwaway vault).** Typing did not
  register: the main thread was blocked for seconds per edit, in SwiftUI's layout, not in the editor.
  A `sample` of the busy process (`build/pg405-hand-sample-opennote.txt`, 3,214 main-thread samples) puts
  2,393 (75%) in `AGGraphSetOutputValue` comparing the previous and the new value of a view input, and 1,602
  (50%) of those in the derived `==` of `VaultController.OpenNote` (`NoteTab.swift:98`): `text` is compared
  as a whole through `_stringCompareSlow` (NFC normalisation), and the text the editor wrote back is a
  foreign string (`NSString` bridged from `textView.string`), which that compare walks scalar by scalar
  (`foreignIndex`, `characterAtIndex:`). The cost is linear in the note, runs on every binding write, and
  is outside everything the bench measures: it never goes through SwiftUI. The write itself is unchanged by
  this record (`parent.text = textView.string` predates it), but no build from before #982 was run to
  confirm the cost was already there. The other steps of the checklist were not reached. The gate stays
  open until a keystroke in a 1 MB note on a Release build is usable; the ledger carries the fix.

## Ledger entries

The three terms D9 and the profile left open were looked at again on 2026-10-12 (branch
`perf/editor-residual-keystroke-terms`). Two are closed by measurement or by a change, one is profiled and
stays open. None was filed as a ledger entry.

- **The binding write and what follows it (closed, PG-406).** The write itself is cheap: `textView.string`
  bridges without a copy (0.002 ms at 1 MB, Debug), so `parent.text = textView.string` is not the term. The
  term is the compare `updateNSView` makes after SwiftUI sees the write, `textView.string != text`
  (`NoteTextView+Update.swift`): linear in the note, 2.0 ms at 50 KB, 7.3 ms at 200 KB and 37 ms at 1 MB in
  Debug, on every keystroke, and invisible to the bench because its binding is `.constant` and it never calls
  `updateNSView`. `ModelSync` (`ModelSync.swift`) records the text the last binding write handed over and the
  storage's character-edit count at that moment; `pushInputs` skips the compare only when no edit has reached
  the storage since and the model's text equals the written one (two values that share storage compare in
  constant time). Anything else, an external replacement included, falls through to the compare, so the record
  can only say "equal", never "different". Pinned by `ModelSyncTests`.
  What SwiftUI does after the write is removed by ADR-0096; `ModelSync` is unchanged.
- **The transclusion occurrence scan (closed, PG-407, no code).** It is not a per-keystroke term. The ranged
  scan reads the dirty fragment only: 72 to 74 characters at 50 KB, 200 KB and 1 MB, 0.09 ms in Debug at every
  size. The 4.3% of R-12's profile is the whole-note scan the first keystroke after an open owes
  (`takeTransclusionScan` returns `.whole` until a styling has set a range): in `build/pg405-release-sample.txt`
  1,049 of the 1,109 samples under `runEditPasses` sit at `Transclusion.swift:207` (the whole scan) and 10 at
  `:213` (the ranged one), and the window of that profile included the setup of every fixture. The whole scan
  is slow because it walks a foreign string through `characterAtIndex:`, once per note, at the first edit.
- **The first keystroke after a far caret jump (profiled, open, PG-408).** Release, 1 MB: 2,173 ms (fences) and
  1,443 ms (prose), the Debug figure within noise, so it is not the build. 97% of the key is
  `growToFitTheText` -> `LayoutDebt.settle` -> `NSTextLayoutManager.ensureLayout(for:)` on the owed range
  (`NoteTextView+Layout.swift:125`, the ranged branch, not the whole-document one): TextKit lays out and
  enumerates the elements between the last laid-out place and the range (60% element enumeration, 24%
  `NSTextLayoutFragment._layout`, 15% fragment removal), about 22,000 lines in the bench. Scrolling the target
  into view first does not change it in the fixture (2.35 to 2.47 s), but the fixture's window is never shown,
  so no viewport layout runs and that does not say what a person's window does. Not changed: a cheaper
  `settle` for a range far from the viewport needs the height estimate `growToFitTheText` reads to stay right
  (ADR-0093 §D4), and that is decided with a hand check on a Release build with a 1 MB note (type after
  Cmd+Down, after a click far from the previous caret, after a wikilink jump), which G-hand-405 already covers.

Not filed: the list walks of D9, which the profile shows at 2 and 1 samples. They stay bounded by a list.

## References

- Root `SPEC.md` (Approved 2026-10-12) and the plan `docs/plans/sublinear-offset-state-pg-405.md`.
- ADR-0091 §D1, §D2, §D6, §D8, §D9 and "Measured after"; ADR-0093 §D8 ("What stays linear"), "Measured
  after" and "What stays"; ADR-0082 §D7 and §D9; ADR-0074 §D1; ADR-0007 §D2; ADR-0001 §D1;
  `docs/adr/README.md` rules 1 to 3.
- `PG-405`, follow-up of `PG-401`/#967. `PG-402`, `PG-403`, `PG-404`.
- Scintilla's `Partitioning` (a split vector with a step), the prior art the SPEC names.
