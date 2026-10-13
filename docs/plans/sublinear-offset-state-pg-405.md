**Requirement set:** `docs/archive/specs/sublinear-offset-state-pg-405.SPEC.md` (root `SPEC.md` while this was built)

# Sub-linear shift and splice of offset-keyed editor state (PG-405)

- **SPEC:** root `SPEC.md`, "Sub-linear shift and splice of offset-keyed editor state (PG-405)", Status
  Approved (2026-10-12), R-01 to R-15. Its `## Decisions`, `## Constraints` and `## Test seams` are settled
  input, and no task below reopens them. `/ship` archives it under `docs/archive/specs/`.
- **ADR outcome: new ADR**, `docs/adr/0094-an-edit-moves-a-step-not-every-offset-below-it.md`, written
  `planned`.
  - It extends ADR-0091 §D6 and ADR-0093 "What stays", and replaces ADR-0093 §D8's "What stays linear"
    paragraph (R-14). It keeps ADR-0091 §D1, §D2, §D8 and §D9, ADR-0001 §D1, ADR-0082 §D7 and §D9,
    ADR-0007 §D2 and ADR-0074 §D1.
  - It settles the SPEC's two open items: the public shape of the shared type (§D2) and the constant,
    C = 64 entries per store per keystroke with zero copies (§D5).
  - **Number.** `0094`. On 2026-10-12 `origin/main` is `377b196e`, whose highest ADR is `0093`, and no ref
    holds `0092` or `0094`. `0092` stays skipped for the reason ADR-0093's header records. **Re-check the
    number right before the docs PR merges and again before the code PR merges** (`docs/adr/README.md`
    rule 1). If `0094` is taken by then, renumber the file, its heading, every reference to it in this plan
    and in code comments, and the index lines.
  - It flips to `accepted` in the first docs change after the code PR merges (rule 2).
  - **`CLAUDE.md`'s `## ADR index` needs one line**, pasted from `scripts/adr-index.py`. Until it is there,
    `scripts/adr-index.py --check` reports it missing. The line is
    `- ADR-0094 — An edit moves a step, not every offset below it`. It travels with the docs PR, not with
    this plan's tasks.
- **Governing ADRs, registered and not reopened:**
  - ADR-0091: §D1 Foundation only, §D2 the one shift rule in `StorageEdit`, §D6 every holder shifts itself,
    §D8 the kill switch, §D9 the surfaces and the card.
  - ADR-0093: §D8, the windowed renumbering and its parity source, `listFacts`; "What stays".
  - ADR-0082: §D7, the Release hand check by the person; §D9, the bench and the person's ceilings.
  - ADR-0074 §D1: each controller owns its state. ADR-0045: a widened `private` carries a comment naming
    its reader.
- **Baseline.** `main` at `377b196e`, which is `origin/main`. `SPEC.md`, this plan and ADR-0094 are
  untracked.
- **Delivery.**
  - A docs PR carries `SPEC.md`, this plan, ADR-0094 and the index line.
  - One code PR on `feature/sublinear-offset-state-pg-405`, cut from `main` after the docs branch lands,
    and preferably after `feature/pg-401-ceilings` lands (see Risks). It is built in one `/build` session.
  - If the context runs short, split after Task 3. Tasks 1 to 3 are a green, self-contained change: the
    bench row, the type and its pure tests, with nothing in the editor using the type yet.
  - Run `tuist install` and `tuist generate --no-open` before the first task, and again after every task
    that adds a file (Tasks 1, 2 and 4).
  - PR bodies say `refs PG-405`, never a closing keyword, negated or not.

## SPEC decisions registered (settled, not reopened)

- **The perimeter is every linear term, the structure map included.** This covers the shift and splice of
  the three stores, plus the map's shift, its fence parity and its splice scans. This plan reads it as also
  covering the two map scans the SPEC does not list: `pendingOpener`'s walk and the fence reveal (see
  "What reading the tree added", items 3 and 4).
- **The mechanism is sorted storage with a pending delta (a step), in one shared type.** A tree with relative
  offsets was rejected, and so was iterating only the tail of the dictionaries.
- **The shift rule stays `StorageEdit`'s.** A rule of its own inside the new type was rejected.
- **A far caret jump is paid once and measured,** with its own bench row. A structure that is O(log n) in
  every case was rejected.
- **The rare-construct holders stay dictionaries with a declared bound,** given in ADR-0094 §D8.
  Converting them was rejected.
- **Fold and reveal state stay out.** Pulling `PG-402` in was rejected.
- **Acceptance is a touched-entries counter plus the bench.** The ceilings are the person's. The bench
  alone was rejected.
- **Constraints carried into every task.**
  - The result of an edit is byte for byte today's.
  - The pure types import Foundation only, and no dependency is added.
  - The golden corpus stays byte identical.
  - The 1 MB hand check is on Release, by the person.
  - Surface parity is kept.
  - The ledger entry stays `PG-405`, and PR bodies say "refs".

## What reading the tree added (`377b196e`)

1. **A hidden copy on every incremental restyle.** `applyIncrementalStyling` binds `let scope =
   restyleScope` (`NoteTextView+Coordinator.swift:773`), reads it at `:781` and `:799`, and mutates
   `restyleScope` at `:814`. A binding alive across the mutation makes the map's arrays copy whole. Task 5
   removes the binding, and D4's counter makes any later one visible.
2. **The spell checker scans every unspellable range** on each question (`:578`). It becomes `intersects`.
3. **The fence reveal scans every fence on every keystroke.** `currentViewBlockFences()` (`:871-877`) is read
   by `selectionCrossedFence` (`NoteTextView+ViewBlocks.swift:106-116`), which the coordinator calls on every
   selection change (`NoteTextView+Coordinator.swift:214`), so on every keystroke. No test reads either name
   (`git grep`), so the closure can take the selection. That is ADR-0094 §D6, in Task 6.
4. **`pendingOpener` walks the note above the caret** when no line above holds a bracket token
   (`RestyleScope.swift:223-229`). The bench cannot show it, because every bench group carries
   `[[Nota n]]` (`Tests/RestyleBudgetSupport.swift:116`). It is closed with two mark sets (ADR-0094 §D6, Task 6).
5. **`EmbedTable.apply(runs:…within:)` walks every run** to find the ones inside the dirty range
   (`NoteTextView+Embeds.swift:138-139`). The call site pre-filters them (Task 5), and the signature and its
   own filter stay.
6. **`MarkdownStyler.spliced` merges across its whole tail** (`MarkdownStyler+Incremental.swift:45-52`), not
   only at the seam. The window version is equal under the precondition ADR-0094 §D3 records, and the hosted
   twin guards that precondition (`Tests/ScrolledEditorFixture.swift:443`).
7. **Two drop rules part on one degenerate case.** The embed splice (`NoteTextView+Coordinator.swift:811-813`)
   and `StructureMap.spliced` (`StructureMap.swift:274-281`) disagree only for an empty run at an empty dirty
   range. Embed runs are never empty, so both take `splice`.
8. **The map's fence rule is not `StorageEdit.shifted`** (`StructureMap.swift:264-271`). It differs in three
   cases, each of which leaves the last fence next to the step (ADR-0094 §D3). It moves into `StorageEdit`
   (Task 3), and the map calls it (Task 6).
9. **`codeBlocks` can overlap** (`StructureMap.swift:36-40`, `:65-69`), so it stays an array.
10. **The parity source.** The SPEC's edge case says the map answers parity "from the fence list". The list
    it can answer from without changing a renumbering is the map's list of odd-delimiter lines, built from
    `listFacts`, not `CodeFence`'s regions (ADR-0094 §D6).
11. **What the delegate's readers need.**
    - Every source reader of the delegate's markers is a key subscript: `EditorDecorationDelegate.swift:441`,
      `:457`, `:570`, `:776`, `+Substitution.swift:19`, `+ListRendering.swift:61`, `+QuoteRendering.swift:74`
      and `+CheckboxRendering.swift:66`.
    - Only two test lines read the delegate's store directly: `MessageAnchorEditorTests.swift:113-119` (a
      subscript compared with an array literal, then `.values.joined()`) and `:142` (`.values.joined()`).
      Every other test hands it a dictionary through `apply(hiddenMarkers:hidingMarkup:)`, which keeps its
      signature (Task 7 lists them all).
    - `coordinator.hiddenMarkers` in a test is always the card coordinator's own dictionary
      (`CardTextView.swift:226`), which does not change. The note coordinator has no such property.
12. **What the map's readers need.** `StructureMapTests.swift` uses `count`, subscript, `map`, `zip`,
    `indices`, `first`, `isEmpty`, `lines == expected.lines`, and `tableRuns == [NSRange]` (`:211`, `:212`,
    `:295`). `RestyleScopeTests.swift:471` compares `expected.tableRuns` with an array literal, and
    `IncrementalStylerPropertyTests.swift:126` asks `map.lines.isEmpty`. All of these are served by a
    `RandomAccessCollection` with a logical `==` and an `==` against an array.
13. **Copies in tests.** `DerivedStateSnapshot.map` (`NoteTextView+DerivedState.swift:56`) and
    `StructureMapTests.swift:291` hold a copy across an edit. That is harmless, but a counter test must not do
    it, or it counts the copy.
14. **The Release test build.** `scripts/pg-401-gates.sh` builds the test bundle in Release with
    `ENABLE_TESTABILITY=YES`, and `Sources/Features/Editor` has no `#if DEBUG` today (`restyleLog` is always
    compiled). The counting therefore compiles under `#if DEBUG`, while its reading API compiles everywhere
    (ADR-0094 §D5).
15. **Size limits.**

    | File | Lines (warn 400 / error 1000) | Plan |
    | --- | --- | --- |
    | `EditorDecorationDelegate.swift` | 994 | `DecorationSnapshot` (15 lines) moves out |
    | `NoteTextView+Coordinator.swift` | 886, class body near `type_body_length` | new methods go in its trailing extension |
    | `NoteTextView+ViewBlocks.swift` | 395 | a one-line closure-type change |
    | `EditorRestyleBudgetTests.swift` | 389 | new suites go in new files |
    | `RestyleBudgetSupport.swift` | 371 | new helpers go in new files |
    | `StructureMap.swift` | 282 | |
    | `RestyleScope.swift` | 287 | |

16. **Where the type compiles.** `StorageEdit` and `StructureMap` are app-only (`Sources/Features/Editor`, not
    in `sharedSources`, `Project.swift:87`). The app target globs `Sources/**` (`Project.swift:262`), so the
    three new files need no manifest change, only `tuist generate`.

## Requirement coverage

| Requirement | Tasks |
| --- | --- |
| R-01 | 2, 3 |
| R-02 | 2, 3 |
| R-03 | 7 |
| R-04 | 2, 3, 5 |
| R-05 | 2, 3, 4, 5 |
| R-06 | 1, 2, 3, 4, 5, 6 |
| R-07 | 4, 6 |
| R-08 | 2, 3, 5 |
| R-09 | 4, 5 |
| R-10 | 5, 7 |
| R-11 | 1, 7, 8 |
| R-12 | 7, 8 |
| R-13 | 8 |
| R-14 | 8 |
| R-15 | 2, 3 |

## Order

1. The jump row lands first, and every "before" is measured on the old code (Task 1).
2. The shared type: red (Task 2), then green (Task 3). Nothing in the editor uses it yet.
3. The counters on the real editor, red (Task 4). Then the three stores (Task 5) and the structure map
   (Task 6), green.
4. The call sites, the full suite, the "after" numbers and the Release profile (Task 7).
5. The ADR's numbers, the pointers, the indexes, the ledger, the gates and the number re-check (Task 8).

### Task 1 — Tester: the caret-jump bench row, and every "before" measured on the old code (R-06, R-11)
Owner: tester
Files: Tests/RestyleBudgetSupport+Jump.swift, Tests/EditorRestyleJumpTests.swift, scripts/editor-restyle-bench.sh
Tests: EditorRestyleJumpTests.swift, EditorRestyleBudgetTests.swift
Signatures:
- RestyleBudget.includesJumpRows — static var includesJumpRows: Bool { get }
- RestyleBudget.jumpLine — static func jumpLine(_ c: Case, cpuMs: Double, wallMs: Double, crossed: Int, runs: Int) -> String
- RestyleBudget.jumpPoint — static func jumpPoint(in note: String) -> Int
- JumpScenario — @MainActor final class JumpScenario { init(_ c: RestyleBudget.Case); let fixture: ScrolledEditorFixture; var crossed: Int { get }; func jumpAway(); func keystroke() }
- scripts/editor-restyle-bench.sh — flag --jump, exporting TEST_RUNNER_RESTYLE_BUDGET_JUMP=1 and adding -only-testing:PergamenumTests/EditorRestyleJumpTests; a fourth table from lines matching ^restyle-budget-jump size=
Red: no

Everything here is test code and the bench script. No source file changes in this task, and it runs before
any other task, so its numbers are the old code's (R-11).

**What the row measures (R-06's bench row).** The first keystroke after a caret jump.

- `jumpPoint(in:)` is the end of the first `Altro testo con` line, near the top of the note.
- `JumpScenario.jumpAway()` types `x` at the jump point and lets the coordinator restyle. It is untimed.
- `JumpScenario.keystroke()` types `x` at the end of the middle paragraph, the one
  `RestyleBudget.insertionPoint(in:)` finds. Track its offset as the note grows: one character above it per
  `jumpAway`, one at it per `keystroke`. Every run then types at the end of the same paragraph.
- `crossed` is the number of lines between the two edit points, counted from the text, and is printed for
  reading.
- On the old code a jump cost far more than a plain keystroke: Task 1 measured 1.5 to 2.3 s against about
  90 ms at 1 MB, cause unprofiled. After ADR-0094 §D1 the step crosses those lines once.

**The line.** `restyle-budget-jump size=<bytes> variant=<prose|fences> cpu_ms=<min> wall_ms=<min>
crossed=<lines> runs=<K>`. It starts `restyle-budget-jump`, so neither existing table's pattern matches it.

**`EditorRestyleJumpTests.swift`, `@Suite(.serialized)`:**

- `theJumpLineHasTheSevenFieldsTheBenchScriptGreps` pins
  `restyle-budget-jump size=51200 variant=fences cpu_ms=4.10 wall_ms=5.20 crossed=640 runs=5`, as
  `theFallbackLineHasTheSevenFieldsTheBenchScriptGreps` does.
- `theJumpPointIsNearTheTopAndAboveTheInsertionPoint`, for both variants at 50 KB. The jump point is in the
  first tenth of the note, above the insertion point, and both are ends of `Altro testo con` lines.
- `theJumpScenarioTypesIncrementallyAtBothPlaces`, always on, at 50 KB fences. Over three rounds of
  `jumpAway` and `keystroke`, each call is one ranged restyle: `restyleLog.incremental` advances by one and
  `full` does not. The middle paragraph's text ends with the `x`s typed into it so far. This keeps the
  printed row from ever measuring a fallback.
- `aKeystrokeAfterACaretJumpIsPrinted(_ c: RestyleBudget.Case)`, `.enabled(if:
  RestyleBudget.includesJumpRows)`, arguments `RestyleBudget.activeCases`. It runs `openLikeTheApp()` and
  `RestyleBudget.minimum(runs:warmUp:prepare: { scenario.jumpAway() }) { scenario.keystroke() }`, then prints
  `jumpLine`. Nothing is asserted on time.

**`scripts/editor-restyle-bench.sh`:**

- `--jump` exports `TEST_RUNNER_RESTYLE_BUDGET_JUMP=1` and adds `-only-testing:PergamenumTests/EditorRestyleJumpTests`
  beside the existing one.
- bash 3.2 with `set -u` fails on an empty `"${extra[@]}"`, so use `${extra[@]+"${extra[@]}"}`.
- It prints a fourth table, "after a caret jump (printed, never asserted):", with the columns `size`,
  `variant`, `cpu_ms`, `wall_ms`, `crossed` and `runs`.
- The header comment's list of switches gains `RESTYLE_BUDGET_JUMP=1`.

**The "before" measurements (R-11).** On the development Mac, on this task's tree, with nothing else
building:

- `scripts/editor-restyle-bench.sh --runs 9 --jump`
- `scripts/editor-restyle-bench.sh --large-only --runs 3 --jump`

Report both outputs verbatim, with `sw_vers`, `xcodebuild -version` and the Mac model. Task 3 writes them into
ADR-0094 "Measured before".

### Task 2 — Tester: the shared type declared, and its pure tests red (R-01, R-02, R-04, R-05, R-06, R-08, R-15)
Owner: tester
Files: Sources/Features/Editor/StepBuffer.swift, Sources/Features/Editor/OffsetTable.swift, Sources/Features/Editor/OffsetRanges.swift, Sources/Features/Editor/StorageEdit.swift, Tests/OffsetStoreModel.swift, Tests/OffsetStoreModelTests.swift, Tests/OffsetStoreBoundsTests.swift, Tests/OffsetStoreImportGuardTests.swift
Tests: OffsetStoreModelTests.swift, OffsetStoreBoundsTests.swift, OffsetStoreImportGuardTests.swift, OffsetStoreModel.swift, IncrementalStylerModel.swift
Signatures:
- OffsetEntry — protocol OffsetEntry: Equatable { var position: Int { get }; func moved(by delta: Int) -> Self }
- RangedEntry — protocol RangedEntry: OffsetEntry { var range: NSRange { get }; func with(range: NSRange) -> Self }
- NSRange — extension NSRange: RangedEntry (position is location)
- StepTally — struct StepTally: Equatable, Sendable { var touched: Int; var copies: Int; var shifts: Int; var splices: Int; var rebuilds: Int; enum Operation: Sendable { case shift, splice }; static var isCounting: Bool { get } }
- StepBuffer — `struct StepBuffer<Entry: OffsetEntry>: RandomAccessCollection, Equatable { init(); init(sorted entries: [Entry]); var startIndex: Int { get }; var endIndex: Int { get }; subscript(index: Int) -> Entry { get } }`
- StepBuffer.partition — func partition(_ isPast: (Entry) -> Bool) -> (index: Int, probes: Int)
- StepBuffer.lowerBound — func lowerBound(_ position: Int) -> Int
- StepBuffer.replace — `mutating func replace(_ window: Range<Int>, with fresh: [Entry], movingTheRestBy delta: Int, as operation: StepTally.Operation)`
- StepBuffer.rebuild — mutating func rebuild(sorted entries: [Entry])
- StepBuffer.tally — var tally: StepTally { get }; mutating func resetTally()
- StepBuffer: Sendable — extension StepBuffer: Sendable where Entry: Sendable
- Keyed — `struct Keyed<Value: Equatable>: OffsetEntry { var position: Int; var value: Value }`
- OffsetTable — `struct OffsetTable<Value: Equatable>: Equatable { init(); init(_ table: [Int: Value]); var count: Int { get }; var isEmpty: Bool { get }; var keys: some RandomAccessCollection<Int> { get }; var values: some RandomAccessCollection<Value> { get }; subscript(key: Int) -> Value? { get } }`
- OffsetTable.lookup — func lookup(_ key: Int) -> (value: Value?, probes: Int)
- OffsetTable.entry — func entry(atOrBefore offset: Int) -> (key: Int, value: Value)?
- OffsetTable.entries — func entries(in range: NSRange) -> [(key: Int, value: Value)]
- OffsetTable.apply — mutating func apply(_ edit: StorageEdit)
- OffsetTable.replace — mutating func replace(in dirty: NSRange, with fresh: [Int: Value])
- OffsetTable.== — static func == (lhs: OffsetTable, rhs: [Int: Value]) -> Bool
- OffsetTable.tally — var tally: StepTally { get }; mutating func resetTally()
- OffsetTable: Sendable — extension OffsetTable: Sendable where Value: Sendable
- OffsetRanges — `struct OffsetRanges<Entry: RangedEntry>: RandomAccessCollection, Equatable { enum Partial: Sendable { case clip, drop }; init(); init(sorted entries: [Entry]); var startIndex: Int { get }; var endIndex: Int { get }; subscript(index: Int) -> Entry { get } }`
- OffsetRanges.apply — mutating func apply(_ edit: StorageEdit, partial: Partial)
- OffsetRanges.apply(anchoringTheEndOf:) — mutating func apply(_ edit: StorageEdit, anchoringTheEndOf oldLength: Int)
- OffsetRanges.splice — mutating func splice(_ fragment: [Entry], replacing dirty: NSRange)
- OffsetRanges.spliceMerging — mutating func spliceMerging(_ fragment: [NSRange], replacing dirty: NSRange), in extension OffsetRanges where Entry == NSRange
- OffsetRanges.intersects — func intersects(_ range: NSRange) -> Bool
- OffsetRanges.count — func count(endingAtOrBefore offset: Int) -> Int
- OffsetRanges.indices(intersecting:) — `func indices(intersecting range: NSRange) -> Range<Int>`
- OffsetRanges.indices(touching:) — `func indices(touching range: NSRange) -> Range<Int>`
- OffsetRanges.entries — func entries(startingIn range: NSRange) -> [Entry]
- OffsetRanges.== — static func == (lhs: OffsetRanges, rhs: [Entry]) -> Bool; static func == (lhs: [Entry], rhs: OffsetRanges) -> Bool
- OffsetRanges.tally — var tally: StepTally { get }; mutating func resetTally()
- OffsetRanges: Sendable — extension OffsetRanges: Sendable where Entry: Sendable
- StorageEdit.precedes — func precedes(_ range: NSRange) -> Bool
- StorageEdit.follows — func follows(_ range: NSRange) -> Bool
- StorageEdit.shifted(_:anchoringTheEndOf:) — func shifted(_ range: NSRange, anchoringTheEndOf oldLength: Int) -> NSRange?
Red: yes

**Declarations with neutral bodies, never `fatalError`.**

- Each of the three new files imports Foundation only and carries a header naming ADR-0094 and the
  section it implements.
- The tester's placeholder storage is one `entries: [Entry]` array that `init(sorted:)` fills. The coder
  replaces it with the step layout.
- Every mutating operation is a no-op. `partition` answers `(0, 0)`, `lookup` answers `(nil, 0)`, and the
  queries answer empty, `false` or `0`. Tallies read zero, and `StepTally.isCounting` is `true` under
  `#if DEBUG` and `false` otherwise.
- The three `StorageEdit` additions answer `false`, `false` and `nil`. Nothing in the app calls them yet, and
  the existing members are untouched.

**`OffsetStoreModel.swift`, the oracle and the generators.** The naive implementations are today's code,
written out in the test so they survive Task 6:

| Shape and rule | The oracle |
| --- | --- |
| keyed, apply | `edit.shiftedKeys(dict)` |
| keyed, replace | `dict.filter { !NSLocationInRange($0.key, dirty) }`, merged with the fresh entries, a fresh key winning |
| ranges, `.clip` | `flatMap { edit.clipped($0) }` |
| ranges, `.drop` | `compactMap { edit.shifted($0) }` |
| ranges, anchored | a copy of `StructureMap.shifted(_:by:oldLength:newLength:)` (`StructureMap.swift:266-271`), which takes `newLength`; the moved rule replaces it with `oldLength + delta` (ADR-0094 §D3) |
| ranges, `splice` | a verbatim copy of `StructureMap.spliced` (`:274-281`), plus the embed filter of `NoteTextView+Coordinator.swift:811-813` |
| ranges, `spliceMerging` | `MarkdownStyler.spliced` itself |

The generators run on `SplitMix64` (`IncrementalStylerModel.swift:165`):

- a text of a random length, split into random lines;
- edits that insert, delete, replace, delete the whole text, and act at 0 and at the end;
- keys at line starts;
- range lists that are sorted, disjoint and non-empty, some touching;
- dirty ranges that cover every edit since the previous splice, which is ADR-0094 §D3's precondition;
- fresh fragments inside the dirty range: merged for `spliceMerging`, non-empty and disjoint for `splice`,
  keyed inside the range for `replace`;
- a `keystroke(at:)` helper: a one-character insertion, then a splice of its line.

**`OffsetStoreModelTests.swift` (R-01, R-02).**

- **The random run.** Seeds 1 to 20, 200 operations each, interleaving `apply` and the splice of each shape.
  After every operation the store equals its oracle: `table == dict`, and `Array(ranges) == naive` for
  `.clip`, `.drop` and the anchored rule (each its own list). The anchored list's `oldLength` is the model
  text's length before the edit.
- **The SPEC's edge cases, one argument each:**
  - an empty store;
  - an edit at 0, and an edit at the end;
  - a deletion of the whole note;
  - one line split into two, and two lines joined into one;
  - the first edit after a jump, and an alternation of two far positions;
  - a deletion that lands a moved key on a stayed key, where the moved key wins;
  - a range clipped into two parts, a range stretched by an edit it contains, and a range dropped wholly
    inside an edit;
  - the three anchored cases of ADR-0094 §D3: an insertion at the note's end, an insertion at the last
    fence's start, and a deletion of exactly that fence.
- **R-02 at the boundaries.**
  - A deletion leaves two unspellable ranges touching at the edit point. A `spliceMerging` whose dirty range
    covers that point equals `MarkdownStyler.spliced`, and leaves no two entries touching or overlapping at
    either seam.
  - The same holds for a head entry that crosses `dirty.location` and for a tail entry that crosses the
    dirty range's end.
- **Logical equality.** A buffer brought to some entries through many edits, with its step in the middle,
  is `==` to `init(sorted:)` of the same entries, and the tally takes no part.
  `OffsetRanges(sorted: runs) == runs` and `runs == OffsetRanges(sorted: runs)` both compile and hold.

**`OffsetStoreBoundsTests.swift` (R-04, R-05, R-06, R-08).**

- **The sizes.** n is the number of lines of `RestyleBudget.syntheticNote(bytes:variant: .fences)` at 50 KB,
  200 KB and 1 MB. The stores are uniform, so that only the size differs between them:
  - a key per line start;
  - three unspellable ranges per line;
  - one embed run every 20 lines.
- **R-04.**
  - `lookup` on a table of n keys, for every key and for absent keys between them, takes at most
    `Int(ceil(log2(Double(n + 1)))) + 1` probes, and its value is the dictionary's.
  - `partition` on a list of n ranges keeps the same bound.
- **R-05,** `.enabled(if: StepTally.isCounting)`.
  - The same keystroke is made twice at the middle line, with `resetTally()` in between.
  - On the second keystroke, each store's tally reads `touched <= 64`, `copies == 0`, `shifts == 1` and
    `splices == 1`.
  - `touched` is identical at the three sizes.
- **R-06.**
  - A keystroke near the top, then one at the middle: `touched <= crossed + 64`, where `crossed` is the
    store's entries between the two positions, counted on the oracle.
  - For an alternation of the two positions, each edit holds to the same bound.
- **The copy (ADR-0094 §D4).** Hold a copy of a store across a mutation, and the tally reads `copies == 1`
  and `touched >= count`. Drop it, and the next mutation reads `copies == 0`.
- **R-08.**
  - The table holds `final class Box: Equatable`, whose `==` is identity.
  - After random shifts and replacements, every surviving value is `===` the object it was inserted as.
- **Rebuilds.** `init(_:)` and `init(sorted:)` each count one rebuild.

**`OffsetStoreImportGuardTests.swift` (R-15).** It reads the files through `resolvedRepoRoot()`:

- The four source files of this task import exactly `Foundation`.
- `OffsetStoreModel.swift`, `OffsetStoreModelTests.swift` and `OffsetStoreBoundsTests.swift` import only
  `Foundation`, `Testing` and `@testable import Pergamenum`. None names `AppKit` or `SwiftUI`.

**Expected red.** The model tests are red, because mutations are no-ops. The bounds tests are red, because
the probes and the values are wrong and `shifts` reads zero. The import guard is green from the start, and
stays red only if a file imports more.

### Task 3 — Coder: the step buffer, the two shapes and StorageEdit's predicates (R-01, R-02, R-04, R-05, R-06, R-08, R-15)
Owner: coder
Files: Sources/Features/Editor/StepBuffer.swift, Sources/Features/Editor/OffsetTable.swift, Sources/Features/Editor/OffsetRanges.swift, Sources/Features/Editor/StorageEdit.swift, docs/adr/0094-an-edit-moves-a-step-not-every-offset-below-it.md
Tests: OffsetStoreModelTests.swift, OffsetStoreBoundsTests.swift, OffsetStoreImportGuardTests.swift, IncrementalStylerPropertyTests.swift, StructureMapTests.swift, RestyleScopeTests.swift
Signatures:
- StepBuffer.replace — `mutating func replace(_ window: Range<Int>, with fresh: [Entry], movingTheRestBy delta: Int, as operation: StepTally.Operation)`
- StepBuffer.partition — func partition(_ isPast: (Entry) -> Bool) -> (index: Int, probes: Int)
- OffsetTable.lookup — func lookup(_ key: Int) -> (value: Value?, probes: Int)
- OffsetRanges.spliceMerging — mutating func spliceMerging(_ fragment: [NSRange], replacing dirty: NSRange)
- StorageEdit.precedes — func precedes(_ range: NSRange) -> Bool
- StorageEdit.follows — func follows(_ range: NSRange) -> Bool
- StorageEdit.shifted(_:anchoringTheEndOf:) — func shifted(_ range: NSRange, anchoringTheEndOf oldLength: Int) -> NSRange?
Red: no

**First, the "before" (R-11).** Write Task 1's outputs into ADR-0094 "Measured before", as tables in the shape
of ADR-0093's "Measured after", so the old numbers are on disk before the code changes.

**`StepBuffer` (ADR-0094 §D1, §D4, §D5).**

- **Storage.** `front` ascending and absolute; `back` descending and relative to `pendingDelta`.
- **The step.** Moving the step moves entries one by one between the two arrays, adding or subtracting the
  delta. `replace` moves the step to `window.upperBound`, adds `delta` to `pendingDelta`, removes the window
  from the end of `front` and appends `fresh`.
- **`partition` is the only binary search.** It reads positions through the subscript. `lowerBound` and
  every query of the two shapes call it. Reads never mutate, so the delegate's `nonisolated(unsafe)` store
  stays safe to read from TextKit's layout callback.
- **The `Owner` token and the counting,** both under `#if DEBUG`. The token is `final class Owner: Sendable {}`,
  with no stored state, so `StepBuffer` stays conditionally `Sendable` and `StructureMap` stays `Sendable`.
  Every mutating entry point checks `isKnownUniquelyReferenced(&owner)` first. On a shared token it counts
  `copies += 1` and `touched += count`, then takes a fresh token.
- **`init(sorted:)`** asserts the order under `#if DEBUG`: positions ascending, and for the range shape ends
  non-decreasing. That is O(n), and only the full path pays it.
- **`==` compares the current entries.**

**`OffsetTable`.**

- **The window.** A keyed edit's window lies between the first key that does not `precede` the old range and
  the first key that `follows` it. `precedes` wins when both hold, as in `shiftedKeys`.
- **The collision** is checked at the window's left edge.
- **`replace(in:with:)`** widens its window to the fresh keys' span, if any falls outside `dirty`. Inside the
  window it keeps the old entries outside `dirty` and merges the fresh ones, a fresh key winning. In
  production the fresh keys lie inside `dirty`, and the widening costs nothing.
- **The surface.** `keys` and `values` are lazy maps. The subscript is `lookup(key).value`.

**`OffsetRanges`.**

- **The window** is the run of entries that neither `precede` nor `follow` the old range. It is contiguous
  because ends do not decrease. Each entry in it goes through `edit.clipped` or `edit.shifted`, and is
  rebuilt with `with(range:)`.
- **`apply(_:anchoringTheEndOf:)`** applies `edit.shifted(_:anchoringTheEndOf:)` to the last entry and the
  dropping rule to the rest. That entry sits next to the step afterwards (ADR-0094 §D3), so it costs O(1).
- **`splice`** reproduces `StructureMap.spliced`'s partition. Before: `end <= dirty.location`. After:
  `location >= NSMaxRange(dirty) && end > dirty.location`. Anything else is dropped, and the fragment goes in
  between.
- **`spliceMerging`** runs `MarkdownStyler.spliced` on the window, extended by one entry on each side for as
  long as the seam merges, and writes the result back with one `replace`.
- **`indices(intersecting:)`** is `location < NSMaxRange(r) && end > r.location`, and `indices(touching:)` is
  `location <= NSMaxRange(r) && end >= r.location`. Both are two `partition`s.

**`StorageEdit`.**

- `precedes(r)` is `NSMaxRange(r) <= oldRange.location`, and `follows(r)` is
  `r.location >= NSMaxRange(oldRange)`.
- `shifted(_:anchoringTheEndOf:)` is `StructureMap.shifted(_:by:oldLength:newLength:)` moved, with
  `newLength` replaced by `oldLength + delta` (ADR-0094 §D3). `StructureMap` keeps its private copy until
  Task 6 removes it.
- The existing members keep their behaviour. If they are rewritten over the predicates, the model tests
  are the proof that nothing changed.

**Not touched.** `Project.swift` (the `Sources/**` glob takes the files), `sharedSources`,
`Tuist/Package.swift`, every caller in the editor.

**Done when** Task 2's tests are green, and so are `IncrementalStylerPropertyTests`, `StructureMapTests` and
`RestyleScopeTests` (untouched). SwiftLint is clean on the touched files.

### Task 4 — Tester: the counters on the real editor, declared and red (R-05, R-06, R-07, R-09)
Owner: tester
Files: Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/StructureMap.swift, Sources/Features/Editor/RestyleScope.swift, Tests/OffsetStoreHostedCounterTests.swift, scripts/editor-restyle-bench.sh
Tests: OffsetStoreHostedCounterTests.swift, OffsetShiftTests.swift, IncrementalRestyleHostedTests.swift, EditorRestyleJumpTests.swift
Signatures:
- NoteTextView.Coordinator.offsetStoreTallies — func offsetStoreTallies() -> [String: StepTally]
- NoteTextView.Coordinator.resetOffsetStoreTallies — func resetOffsetStoreTallies()
- StructureMap.tallies — var tallies: [String: StepTally] { get }
- StructureMap.resetTallies — mutating func resetTallies()
- RestyleScope.resetTallies — mutating func resetTallies()
- tally keys — the frozen strings "hiddenMarkers", "unspellable", "embedRuns", "map.lines", "map.fences", "map.tableRuns", "map.viewBlockRuns", "map.oddFenceLines", "map.bracketLines", "map.closingLines"
- scripts/editor-restyle-bench.sh — adds -only-testing:PergamenumTests/OffsetStoreHostedCounterTests to every run, and prints the lines matching ^offset-store-counter as a table
Red: yes

**Declarations with neutral bodies.**

- `offsetStoreTallies()` answers `[:]`, and the three resets do nothing.
- The coordinator's two methods go in the trailing extension of `NoteTextView+Coordinator.swift`, never the
  class body. That file is the one where the `private(set)` stores can be reset.
- `StructureMap.tallies` answers `[:]` until Task 6.

**`OffsetStoreHostedCounterTests.swift`, `@Suite(.serialized)`, every test `.enabled(if:
StepTally.isCounting)`.**

- **The cases.** 50 KB in both variants always. 200 KB when `RestyleBudget.includesMediumNotes`, and 1 MB when
  `RestyleBudget.includesLargeNotes`. Each case is a `ScrolledEditorFixture(text:)` of
  `RestyleBudget.syntheticNote`, then `openLikeTheApp()`.
- **One rule for every test.** No `derivedStateSnapshot()`, map or store binding stays alive across a
  measured keystroke, because it shares storage and `copies` would count it. Take what is needed into plain
  `Int`s inside a `do { }` block first.
- **`theThreeStoresStayLocal` (R-05).**
  - Type `x` at `RestyleBudget.insertionPoint(in:)`, so the step moves there. Then
    `resetOffsetStoreTallies()`, and type `x` one character later.
  - For `hiddenMarkers`, `unspellable` and `embedRuns`, the key is present (`#require`), and the tally reads
    `shifts >= 1`, `splices >= 1`, `touched <= 64` and `copies == 0`.
  - `restyleLog.incremental` advanced by one, and `full` did not.
  - Print one line per store: `offset-store-counter size=<bytes> variant=<v> store=<key> touched=<n>
    copies=<n>`. Task 7 reads them.
- **`theMapStaysLocal` (R-07).**
  - The same keystrokes, and the same assertions for the seven `map.*` keys.
  - Before the reset, `codeBlocks` is empty on both bench variants. It is read from
    `derivedStateSnapshot().map?.codeBlocks` inside the `do` block, which is ADR-0094 §D6's assumption.
- **`aJumpCrossesOnce` (R-06).**
  - Type `x` at `RestyleBudget.jumpPoint(in:)`. Then count each store's `crossed` from
    `derivedStateSnapshot()` with collection operations only (`filter`, `count`), so the test compiles against
    today's arrays and tomorrow's buffers:
    - for the hidden-marker keys, the keys between the two positions;
    - for the range lists, the ranges that intersect the span;
    - for the map's lines and for each mark set, the lines that start in the span.
  - Then reset, and type at the middle. Every key reads `touched <= crossed + 64` and `copies == 0`.
- **`theKillSwitchShiftsNothing` (R-09).**
  - The fixture is built with `forcesFullRestyle: true`, and two keystrokes are typed.
  - The three store keys are present, with `shifts == 0` and `splices == 0`.
  - No key starts with `map.`, because there is no scope. `restyleLog.full` advanced by two.

**`scripts/editor-restyle-bench.sh`.**

- It gains `-only-testing:PergamenumTests/OffsetStoreHostedCounterTests` on every run, so the 200 KB rows
  (every run but `--large-only`) and the 1 MB rows (`--large`, `--large-only`) of R-05 are asserted where they
  can be afforded. One header line says so.
- The script deletes its log on exit, so it also prints the `offset-store-counter` lines as a last table,
  "offset-store counters (asserted in the test):", with the columns `size`, `variant`, `store`, `touched`
  and `copies`. Task 7 reports that table.

**Expected red.** Every test is red: the tallies are empty, so the `#require`s fail. After Task 5 the store
assertions and the kill switch turn green. `theMapStaysLocal` and the map rows of `aJumpCrossesOnce` wait for
Task 6.

### Task 5 — Coder: the three stores move to the step (R-04, R-05, R-06, R-08, R-09, R-10)
Owner: coder
Files: Sources/Features/Editor/EditorDecorationDelegate.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+DerivedState.swift, Sources/Features/Editor/NoteTextView+Embeds.swift
Tests: OffsetStoreHostedCounterTests.swift, OffsetShiftTests.swift, IncrementalRestyleHostedTests.swift, IncrementalRestyleSurfacesTests.swift, MessageAnchorEditorTests.swift, MarkupHidingTests.swift, EmbedDrawingTests.swift, StylerGoldenTests.swift, CardConcealmentTests.swift
Signatures:
- EditorDecorationDelegate.hiddenMarkers — `nonisolated(unsafe) var hiddenMarkers: OffsetTable<[HiddenMarker]>`
- EditorDecorationDelegate.apply(hiddenMarkers:hidingMarkup:) — func apply(hiddenMarkers markers: [Int: [HiddenMarker]], hidingMarkup hides: Bool)
- EditorDecorationDelegate.splice(hiddenMarkers:in:hidingMarkup:) — func splice(hiddenMarkers markers: [Int: [HiddenMarker]], in dirty: NSRange, hidingMarkup hides: Bool)
- NoteTextView.Coordinator.unspellableRanges — `private(set) var unspellableRanges: OffsetRanges<NSRange>`
- NoteTextView.Coordinator.embedRuns — `private(set) var embedRuns: OffsetRanges<NSRange>`
- NoteTextView.Coordinator.offsetStoreTallies — func offsetStoreTallies() -> [String: StepTally]
- DecorationSnapshot — struct DecorationSnapshot: Equatable, moved to NoteTextView+DerivedState.swift with its fields unchanged
Red: no

**`EditorDecorationDelegate.swift` (ADR-0094 §D7).**

| Where | Change |
| --- | --- |
| `:211` | the type becomes `OffsetTable<[HiddenMarker]>`, initialised empty; the doc comment says so and names ADR-0094 |
| `:339-347` | the dictionary signature stays; the guard becomes `!(hiddenMarkers == markers) \|\| hides != hidesMarkup`; `hiddenMarkers = OffsetTable(markers)` |
| `:263` | `hiddenMarkerCount` compiles over `values` as written |
| `:930` | `hiddenMarkers.keys.sorted()` compiles as written; the keys are already in order |
| `:955` | `hiddenMarkers.apply(edit)` |
| `:965-970` | `hiddenMarkers.replace(in: dirty, with: markers)`, then `hidesMarkup = hides` |
| `:980-994` | `DecorationSnapshot` moves to `NoteTextView+DerivedState.swift`, so the file stays under 1000 lines |

The readers listed in "What reading the tree added" item 11 keep their lines.

**`NoteTextView+Coordinator.swift`.**

| Where | Change |
| --- | --- |
| `:67`, `:72` | the two types become `OffsetRanges<NSRange>` |
| `:423-424` | `OffsetRanges(sorted: MarkdownStyler.merged(collected.unspellable))` and `OffsetRanges(sorted: collected.embedRuns)` |
| `:578` | `let isSyntax = unspellableRanges.intersects(affectedCharRange)` |
| `:773` | `guard let storage = textView.textStorage, restyleScope != nil else { return }`; the list seed and the view-block ordinal are read from `restyleScope` into locals before any mutation, so no binding of the scope outlives `:814` |
| `:799` | the ordinal keeps its `filter` until Task 6 |
| `:808-810` | `unspellableRanges.spliceMerging(MarkdownStyler.merged(collected.unspellable), replacing: dirty)` |
| `:811-813` | `embedRuns.splice(collected.embedRuns, replacing: dirty)` |
| `:882-885` | `unspellableRanges.apply(edit, partial: .clip)` and `embedRuns.apply(edit, partial: .drop)` |

In the trailing extension, `offsetStoreTallies()` gathers the three keys, plus
`restyleScope?.map.tallies` (empty until Task 6). `resetOffsetStoreTallies()` resets all four sources.

**`NoteTextView+DerivedState.swift`.** `unspellable: Array(unspellableRanges)` and `embedRuns: Array(embedRuns)`.
It receives `DecorationSnapshot`.

**`NoteTextView+Embeds.swift:295-302`.** `applyEmbeds` passes
`dirty.map { embedRuns.entries(startingIn: $0) } ?? Array(embedRuns)`. `EmbedTable.apply`'s signature and its
own filter (`:138-139`) stay.

**Not touched.** The card: `CardTextView+Styling.swift:66-106` keeps its dictionary and calls the dictionary
entry. The rare-construct holders (ADR-0094 §D8) are not touched either. No new method goes in the
coordinator's class body.

**Done when:**

- Task 4's `theThreeStoresStayLocal`, `theKillSwitchShiftsNothing` and the store rows of `aJumpCrossesOnce`
  are green;
- `OffsetShiftTests` (R-08), `IncrementalRestyleHostedTests` (the twin) and `IncrementalRestyleSurfacesTests`
  (R-10) are green and unchanged;
- every test Task 7 lists compiles unchanged.

If one does not compile, report it before touching it (R-03). If the count of the bench paragraph is above 64,
stop and report: ADR-0094 §D5 says the constant is not raised.

### Task 6 — Coder: the structure map and its readers move to the step (R-06, R-07)
Owner: coder
Files: Sources/Features/Editor/StructureMap.swift, Sources/Features/Editor/RestyleScope.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+ViewBlocks.swift
Tests: OffsetStoreHostedCounterTests.swift, StructureMapTests.swift, RestyleScopeTests.swift, IncrementalStylerPropertyTests.swift, ListRenumberWindowTests.swift, ListRenumberWindowPropertyTests.swift, IncrementalRestyleHostedTests.swift, ViewBlockRenderingTests.swift, ReplayAndWindowCoverageTests.swift
Signatures:
- StructureMap.lines — `private(set) var lines: StepBuffer<Line>`
- StructureMap.fences — `private(set) var fences: OffsetRanges<Fence>`
- StructureMap.tableRuns — `private(set) var tableRuns: OffsetRanges<NSRange>`
- StructureMap.viewBlockRuns — `private(set) var viewBlockRuns: OffsetRanges<NSRange>`
- StructureMap.codeBlocks — private(set) var codeBlocks: [NSRange]
- StructureMap.Mark — struct Mark: OffsetEntry, Sendable { var position: Int }
- StructureMap.oddFenceLines — `private(set) var oddFenceLines: StepBuffer<Mark>`
- StructureMap.bracketLines — `private(set) var bracketLines: StepBuffer<Mark>`
- StructureMap.closingLines — `private(set) var closingLines: StepBuffer<Mark>`
- StructureMap.fenceParity — func fenceParity(before index: Int) -> Bool
- StructureMap.nearestBracketLine — func nearestBracketLine(before index: Int) -> Int?
- StructureMap.hasClosingBracket — func hasClosingBracket(after index: Int) -> Bool
- StructureMap.Line — extension StructureMap.Line: OffsetEntry (position is start)
- StructureMap.Fence — extension StructureMap.Fence: RangedEntry (range is range)
- NoteTextView.Coordinator.currentViewBlockFences — func currentViewBlockFences(touching selection: NSRange) -> [NSRange]?
- ViewBlockController.fenceRanges — var fenceRanges: ((NSRange) -> [NSRange]?)?
Red: no

**`StructureMap.swift` (ADR-0094 §D6).**

- **`init(text:)`** builds the arrays as today, wraps them with `init(sorted:)`, and builds the three mark
  sets from the lines:
  - `listFacts.fenceDelimiters` odd;
  - `signature.brackets` non-empty;
  - `signature.brackets` contains `.close`.
- **`applying`.**
  - `lineIndex(containing:)` is a `partition`.
  - Before mutating, read the old window's bounds: `windowStart = lines[first].start`, and `windowEnd` is
    `lines[last + 1].start`, or `Int.max` at the end.
  - Then `lines.replace(first..<last + 1, with: fresh, movingTheRestBy: edit.delta, as: .shift)`.
  - Each mark set replaces `lowerBound(windowStart)..<lowerBound(windowEnd)` with the marks of `fresh`, under
    the same delta.
  - `fences.apply(edit, anchoringTheEndOf: oldLength)`. `codeBlocks` maps through
    `edit.shifted(_:anchoringTheEndOf:)`. `tableRuns` and `viewBlockRuns` take `apply(edit, partial: .drop)`.
  - The frontmatter recomputation is as today. Its private static takes the buffer.
- **`splice`.**
  - `low` and `high` are `lowerBound`s. `lines.replace(low..<high, with: fresh, movingTheRestBy: 0, as:
    .splice)`, and the mark sets replace the same span.
  - The three run lists take `splice`, and `codeBlocks` keeps the private `spliced` static.
- **Remove** `StructureMap.shifted(_:by:oldLength:newLength:)`. `StorageEdit` holds the rule now.
- **The readers.**
  - `fenceParity(before:)` is `oddFenceLines.lowerBound(lines[i].start) % 2 == 1`.
  - `nearestBracketLine(before:)` takes the predecessor of line `i`'s start in `bracketLines` and returns its
    line index through `lines.lowerBound`. `i` may be `lines.count`, which reads as a position past every
    line.
  - `hasClosingBracket(after:)` asks whether `closingLines` holds a position after `lines[i].start`.
- **`tallies`** reads the seven buffers under the frozen keys, and `resetTallies()` resets them.

**`RestyleScope.swift`.**

- `renumberWindow` (`:89`) becomes `fenceOpen: map.fenceParity(before: start)`.
- `pendingOpener` (`:223-229`): `guard let line = map.nearestBracketLine(before: index), case .open(_, inCode:
  false)? = map.lines[line].signature.brackets.last else { return false }`, then
  `return map.hasClosingBracket(after: line)`.
- `widenOverRegions` (`:166-177`) iterates `map.fences.indices(intersecting:)` of the current range on each
  pass, then `map.codeBlocks` as today. A pass's range is fixed when the pass starts, so the order in which it
  visits the regions does not matter.
- `resetTallies()` calls `map.resetTallies()`.

**`NoteTextView+Coordinator.swift`.**

- `:799` becomes `restyleScope?.map.viewBlockRuns.count(endingAtOrBefore: dirty.location) ?? 0`, read before
  `:814`.
- `currentViewBlockFences(touching:)` (`:871-877`) keeps the closed `pergamenum-view` fences among
  `indices(touching: selection)`, in order.
- The closure at `:93` passes the selection.

**`NoteTextView+ViewBlocks.swift`.** `:95` declares the new closure type, and `:108` calls
`fenceRanges?(selection)`. The fallback parse at `:111` is unchanged, and the file stays under 400 lines.

**The constraints.** `StructureMap` stays `Equatable, Sendable`, and its synthesized `==` now includes the mark
sets, which `StructureMap(text:)` builds. Every read in "What reading the tree added" item 12 compiles
unchanged; if one does not, report it before touching it (R-03).

**Done when** all of Task 4 is green, and so are `StructureMapTests`, `RestyleScopeTests`,
`IncrementalStylerPropertyTests`, `ListRenumberWindowTests`, `ListRenumberWindowPropertyTests` and
`IncrementalRestyleHostedTests` (its `map == StructureMap(text:)` check), all unchanged.

### Task 7 — Tester: the call sites, the full suite, the "after" numbers and the Release profile (R-03, R-10, R-11, R-12)
Owner: tester
Files: build/pg405-release-sample.txt
Tests: StylerGoldenTests.swift, OffsetShiftTests.swift, IncrementalRestyleHostedTests.swift, StructureMapTests.swift, ListRenumberWindowPropertyTests.swift, IncrementalStylerPropertyTests.swift, IncrementalRestyleSurfacesTests.swift, OffsetStoreHostedCounterTests.swift, EditorRestyleBudgetTests.swift, EditorRestyleJumpTests.swift
Signatures:
- scripts/editor-restyle-bench.sh — --runs 9 --jump, then --large-only --runs 3 --jump
- the Release profile run — `TEST_RUNNER_RESTYLE_BUDGET_1MB=only TEST_RUNNER_RESTYLE_BUDGET_RUNS=30 xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -configuration Release -derivedDataPath build/pg401-gates-dd ENABLE_TESTABILITY=YES ENABLE_HARDENED_RUNTIME=NO -only-testing:PergamenumTests/EditorRestyleBudgetTests test`
- the sample — `sample <pid> <seconds> -file build/pg405-release-sample.txt`
Red: no

**Update tests and call-sites asserting the old behaviour.** This is the staleness rule. The store types are an
observable contract of the coordinator, the delegate and the map, although no function signature changes. The
grep was run on `377b196e` (`git grep -n 'apply(hiddenMarkers'`, `'hiddenMarkers'`, `'unspellableRanges'`,
`'embedRuns'`, `'currentViewBlockFences'`, `'fenceRanges'`):

- **Source callers of the delegate's entries:**
  - `apply(hiddenMarkers:hidingMarkup:)`: `NoteTextView+Coordinator.swift:416` (the full path), and the card at
    `CardTextView+Styling.swift:81` and `:106`;
  - `splice(hiddenMarkers:in:hidingMarkup:)`: `NoteTextView+Coordinator.swift:804`;
  - `shift(by:)`: `NoteTextView+DerivedState.swift:27`.
- **Tests that call `apply(hiddenMarkers:hidingMarkup:)` with a dictionary,** expected to compile and pass
  unchanged:
  - `CardConcealmentTests.swift:268`, `CardRoundTripTests.swift:254`;
  - `EditorDecorationSubstitutionTests.swift:11`;
  - `EmbedDrawingTests.swift:52`, `:69`, `:100`, `:111`, `:121`, `:133`, `:141`, `:289`;
  - `GutterBlockRevealCoverageTests.swift:115`, `ListIndentFontInvariantTests.swift:115`;
  - `InlineSpanRevealFenceTests.swift:168`, `:291`, `:299`;
  - `MarkupHidingFixture.swift:27`, `:80`, `:108`;
  - `MarkupHidingListTests.swift:234`, `:278`, `:299`;
  - `MarkupHidingTests.swift:51`, `:67`, `:154`, `:161`, `:214`, `:229`, `:236`, `:275`, `:286`, `:293`;
  - `MessageAnchorEditorTests.swift:164`, `QuoteRenderingTests.swift:34`;
  - `TableRenderingTests.swift:99`, `:120`, `:132`;
  - `ViewBlockRenderingTests.swift:184`, `:202`, `:238`, `:330`.
- **Tests that read the delegate's table directly:** `MessageAnchorEditorTests.swift:113-119` and `:142`.
- **Tests that read the card coordinator's own dictionary,** unaffected: `CardBlockMarkerTests.swift:51`,
  `CardConcealmentTests.swift:108`, `:136`, `:373`, `:384`, `:400`, `CardRoundTripTests.swift:192`, `:230`,
  `MessageAnchorEditorTests.swift:141`, `:143`, `ViewQueryOutOfScopeTests.swift:75`, `:78`.
- **`unspellableRanges` and `embedRuns`** are read through the snapshot only (`ScrolledEditorFixture.swift:443`,
  `:444`, `:471`; `OffsetShiftTests.swift:66`), which keeps `[NSRange]`.
- **The map's stores:** see "What reading the tree added" item 12.
- **`currentViewBlockFences` and `fenceRanges`** have no test caller.
- **Any red is diagnosed first.** It is restated only with its reason written into ADR-0094, never disabled
  or weakened. The R-03 set (golden corpus, shift twin, hosted twin, map and renumber-window property tests)
  is never restated.

**R-03 and R-10.**

- Run `StylerGoldenTests`, byte-identical; then `OffsetShiftTests`, `IncrementalRestyleHostedTests`,
  `StructureMapTests`, `ListRenumberWindowPropertyTests`, `IncrementalStylerPropertyTests` and
  `IncrementalRestyleSurfacesTests`.
- Then run the **full unit suite** (`.claude/test-cmd`). A change of store type can turn tests red in modules
  that only share the fixture.
- Then `git diff --stat main -- Tuist/Package.swift Project.swift` is empty (R-15, no dependency).

**The "after" numbers (R-11).** On the development Mac, nothing else building, run the two commands of Task 1,
which now also assert the 200 KB and 1 MB hosted counters. Report both outputs verbatim, the counter table
included.

**The Release profile (R-12).**

- Run the Release profile command above with `run_in_background`. It measures only the two 1 MB rows, on a
  Release build, and reuses the gate script's DerivedData and build settings.
- When the test host is up (the `Pergamenum` process under `build/pg401-gates-dd`), attach `sample` to it.
  `activeCases` sorts fences before prose, so a sample started then covers the fences row first. Say which
  rows the window covered.
- Keep the samples under `NSTextView.insertText`. Report the shares in the shape of ADR-0093's table: TextKit's
  terms, then each app-owned term with its share, and say whether `shift`, `splice`, `spliceMerging`,
  `replace`, `StructureMap.applying` or `StructureMap.splice` is among the top app-owned terms.
- Name the next app-owned terms as they appear: the list walks (ADR-0094 §D9), the binding write.

### Task 8 — Coder: the ADR's numbers, the pointers, the indexes, the ledger and the gates (R-11, R-12, R-13, R-14)
Owner: coder
Files: docs/adr/0094-an-edit-moves-a-step-not-every-offset-below-it.md, docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md, docs/adr/0093-a-keystroke-lays-out-what-it-changed.md, docs/adr/INDEX.md, CLAUDE.md, Tests/RestyleBudgetSupport.swift
Tests: EditorRestyleBudgetTests.swift, RestyleBudgetSupport.swift
Signatures:
- RestyleBudget.ceilings — static let ceilings: [Case: Double]
- scripts/adr-index.py — --check exits 0
- scripts/check-adr-references.py — exits 0 after git fetch
Red: no

1. **ADR-0094 "Measured after" and the profile (R-11, R-12).**
   - The six rows and the jump rows, before (Task 1) and after (Task 7), with the ratio.
   - The hosted counter values per store and size.
   - The Mac, the OS, the Xcode and the configuration.
   - The Release profile's table and the terms it names.
2. **Pointers, one line each; history is not rewritten.**
   - Under ADR-0091 §D6 (`0091-…md`, after `:432`): "`hiddenMarkers`, the coordinator's two range lists and
     `StructureMap` move a step since ADR-0094 §D1; the other holders keep this section's tables, with ADR-0094
     §D8's bounds."
   - Under ADR-0093 §D8's "What stays linear" (`0093-…md:332-333`): "Replaced by ADR-0094 §D6: the parity is a
     rank in the map's odd-delimiter lines."
   - Under ADR-0093 "What stays" (`:567-573`): "The app-owned term named here is removed by ADR-0094; see its
     Measured after."
3. **Indexes.**
   - `docs/adr/INDEX.md` gets ADR-0094's summary line in its own format, after ADR-0093's.
   - `CLAUDE.md`'s `## ADR index` holds the line `scripts/adr-index.py` prints, pasted with the docs PR. Here
     it is only checked.
   - `scripts/adr-index.py --check` and `scripts/check-adr-references.py` pass, after `git fetch origin`.
4. **Ledger entries (R-14).** Filed through `/project-tasks`, never by editing `TODO.md` by hand, and the IDs
   are written into ADR-0094 "Ledger entries":
   - the binding write (`NoteTextView+EditReplay.swift:25`);
   - each other app-owned term Task 7's profile lists among the top terms. The list walks of ADR-0094 §D9
     are filed only if the profile names them; otherwise ADR-0094 records them as bounded by a list.

   If `/project-tasks` cannot be run from the building agent (ADR-0093's precedent), say so in ADR-0094 and
   leave the filing to the person at the merge gate.
5. **G-ceiling-4 (R-11), HITL.** Put the six rows and the jump rows in front of the person. Write
   `RestyleBudget.ceilings` only with the values they give, then rerun `EditorRestyleBudgetTests` with
   `RESTYLE_BUDGET_200KB=1`. The jump row gets a ceiling only if the person asks for one. The proposal is
   that it does not.
6. **G-hand-405 (R-13), HITL, the person on a Release build.**
   - Build with `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -configuration Release
     -destination 'platform=macOS' -derivedDataPath build/pg405-release-dd build`.
   - Open it with `open -n` on a throwaway vault through `-recentVaults '("<path>")'`, holding a 1 MB note.
     The fences variant of `RestyleBudget.syntheticNote` is a ready text.
   - Hand over ADR-0094's Gates checklist verbatim. `-editorFullRestyle YES` isolates this change. The
     person's verdict goes into ADR-0094's Gates.
7. **The number, again.** Run `git fetch origin`, then `git ls-tree origin/main docs/adr/`, and check every
   branch about to merge. If `0094` was taken meanwhile, renumber (see the header).

## Risks & HITL gates

- **A copy alive across a mutation (high impact, now visible).** One exists today (item 1). Others can appear
  wherever a store or the map is bound with `let` and the owner is mutated before the binding dies. D4's
  counter turns each into a red counter test rather than a slow key. The test seams that hold a snapshot copy
  on purpose (item 13) are outside the measured keystrokes.
- **Exactness rests on three recorded preconditions** (ADR-0094 §D3): sorted input to `init(sorted:)`, a
  merged tail for `spliceMerging`, and non-empty embed runs. The first is asserted in Debug. The second is
  guarded by the hosted twin after every edit. The third is a styler fact. If the twin goes red on
  `unspellable`, that precondition broke, and the fix is the dirty range, not the splice.
- **`pendingOpener` and the fence reveal were not named by the SPEC.** This plan takes them in under the
  perimeter decision ("every linear term, the structure map included"). If the person reads that decision
  more narrowly, Task 6 drops the two mark sets for brackets and the `currentViewBlockFences(touching:)`
  change, and ADR-0094 §D9 lists both as remaining linear terms with ledger entries. Decide at PLAN
  APPROVAL.
- **The parity reading.** ADR-0094 §D6 reads the SPEC's "from the fence list" as the map's odd-delimiter lines,
  because `CodeFence`'s regions would change a renumbering. The byte-for-byte constraint decides it, but it is
  an interpretation of the SPEC's words, so it is named here.
- **C = 64 is proposed, not measured.** Task 4 prints the real counts. If the bench paragraph's count is above
  64, the build stops and reports (ADR-0094 §D5).
- **The Release test build.** `scripts/pg-401-gates.sh` and Task 7's profile compile the test bundle in
  Release. Any reference to a `#if DEBUG`-only symbol from a test breaks it. The counter API compiles in every
  configuration; only the counting is conditional.
- **SwiftLint limits.** `EditorDecorationDelegate.swift` is at 994 of 1000 lines, and the coordinator's class
  body is near `type_body_length`. Task 5 moves `DecorationSnapshot` out and keeps new methods out of the class
  body. CI does not run SwiftLint, so the coder runs it on the touched files.
- **Merge with `feature/pg-401-ceilings`** (not merged at `377b196e`). It edits:
  - `Tests/RestyleBudgetSupport.swift` (the ceilings);
  - `Tests/EditorRestyleBudgetTests.swift`;
  - `Tests/PG401GateTests.swift`;
  - ADR-0091, which it flips to `accepted`;
  - `docs/adr/INDEX.md`;
  - `scripts/pg-401-gates.sh`.

  This plan's Task 8 edits ADR-0091 (one line) and `INDEX.md`, and G-ceiling-4 starts from G-ceiling-3's
  values. Cut the code branch after that PR lands. Otherwise merge `main` in per file before the PR, and redo
  the number check.
- **Debug numbers include the counting.** The "before" (Task 1) has none, and the "after" has a few
  increments per touched entry. The Release profile (R-12) has none. ADR-0094's "Measured after" says so.
- **A jump costs the entries between.** On a 1 MB note, typing at the top and then at the bottom pays roughly
  one old keystroke's shift, once. The jump row measures it, and G-ceiling-4 decides whether it gets a ceiling.
- **ADR number collision.** `0094` is free today. `0092` is skipped on ADR-0093's word. Re-check before each
  merge (Task 8, step 7).
- **HITL gates:**
  - PLAN APPROVAL: this plan, ADR-0094, C = 64, and the two perimeter readings above;
  - commit and push of the docs branch and of the code branch;
  - G-ceiling-4 (Task 8, step 5);
  - G-hand-405 on Release (Task 8, step 6);
  - the merge of each PR, after the ADR number re-check.

  No schema, deletion or deploy step. No external resource is needed: no network, no account, no new
  dependency, no environment variable beyond the bench's own switches.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

## Build result (2026-10-12)

BUILD · DONE WITH WARNINGS
Files: 29 (13 modified, 16 new): Sources/Features/Editor (StepBuffer, OffsetTable, OffsetRanges, StorageEdit, StructureMap, RestyleScope, EditorDecorationDelegate, NoteTextView+Coordinator/+DerivedState/+Embeds/+ViewBlocks), Tests (10 new files), scripts/editor-restyle-bench.sh, ADR-0091/0093/0094, INDEX.md, CLAUDE.md, SPEC.md, this plan
Tests: PergamenumTests 6326 passed in 389 suites, 5 known issues (HostedViewSupport.swift:46, pre-existing), 3 (coverage)
Review: sonnet, safe; opus, safe
Coverage: not run to completion, spec-coverage.sh reported MALFORMED R-13; by the tester's report R-01..R-10 and R-15 have tests, R-11 and R-12 are measured in ADR-0094 "Measured after", R-13 (Release hand check) and R-14 (ledger entries) are open for the person
Deferred: none
Dropped: 9 (fix-hunk 4, post-sweep 4, unlocated 1)
Dispatch: Round 0 (red): tester — Task 1, tester — Task 2, tester — Task 4
Dispatch: Round 1: coder — Tests/OffsetStoreModelTests.swift:151-173, coder — Sources/Features/Editor/StorageEdit.swift:117-122 (reviewer: opus; sonnet)
Dispatch: Round 2: coder — docs/adr/0094-an-edit-moves-a-step-not-every-offset-below-it.md:24, coder — Tests/OffsetStoreModelTests.swift:162-171 (reviewer: sonnet; opus)
Dispatch: Round 3 (sweep): coder — C1 NoteTextView+Transclusion.swift:214, coder — 7 in-diff candidates
Dispatch: Round 4 (sweep): coder — NoteTextView+Transclusion.swift:214-219, coder — OffsetTable.swift:67-78, coder — StructureMap.swift:222-225
WARN: spec-coverage not evaluated, MALFORMED R-13
INFO: review escalated, size: 29 changed files, threshold 20
INFO: verdict not-safe, no BLOCKER or MAJOR record, round 3
INFO: HITL gates still open for the person: G-ceiling-4 (RestyleBudget.ceilings), G-hand-405 (Release hand check), ledger filing via /project-tasks, ADR number re-check; ADR-0094 stays planned
INFO: the working tree bundles the docs (SPEC.md, plan, ADR-0094) with the code, while the plan's Delivery asks for a docs PR first; settle at /ship
INFO: the caret-jump row did not move (1 MB: 1.5-2.3 s before and after); the stores no longer cross more than the entries between, the cost is probably TextKit relayout, unprofiled (ADR-0094 Measured after)
INFO: ADR-0091.md:434 (DROP post-sweep) was wrapped by hand after the sweep

```text
FIX	swept	**NIT** Tests/OffsetStoreModelTests.swift:57 — Lines over 120 characters in the new tests trip the line_length warning (OffsetStoreModelTests.swift:57, OffsetStoreBoundsTests.swift:191, OffsetStoreModel.swift:353, StructureMapReadersTests.swift:131). Fix: wrap them. (reviewer: sonnet)
FIX	swept	**NIT** Sources/Features/Editor/NoteTextView+Coordinator.swift:780 — The ?? 0 on firstOrdinal is unreachable because the guard above already proved restyleScope != nil. Fix: comment it or remove it. (reviewer: opus)
FIX	swept	**NIT** Sources/Features/Editor/StepBuffer.swift:157 — The assert message names init(sorted:) but sits in rebuild(sorted:), which can be called directly. Fix: correct the message. (reviewer: opus)
FIX	swept	**NIT** Tests/StructureMapReadersTests.swift:68 — Walk.disagreement(map) is evaluated twice per #expect (the message is not an autoclosure) on a quadratic walk. Fix: bind it to a let before the assert. (reviewer: opus)
FIX	swept	**MINOR** [other] docs/adr/INDEX.md:122 — The ADR-0094 summary still says the end-anchored fence rule was "moved verbatim", contradicting ADR-0094 line 24-26 and §D3 which now record the oldLength + delta substitution. Fix: reword the index line to name the substitution and its invariant. (reviewer: sonnet, opus)
DROP	fix-hunk	**MINOR** [other] Tests/OffsetStoreModel.swift:39-42 — The comment claims the oracle's newLength makes the substitution "checked rather than copied", but edited.length equals text.length + delta by construction, so no drawn input can falsify it; same claim at OffsetStoreModelTests.swift:160-162. Fix: reword both to say the two coincide by construction and the invariant is carried by the Debug assert in StructureMap.applying. (reviewer: opus)
DROP	fix-hunk	**MINOR** [other] Sources/Features/Editor/NoteTextView+Transclusion.swift:214 — `Sources/Features/Editor/NoteTextView+Transclusion.swift:214`: `occurrences = occurrences.filter { ... }` is a dictionary-wide filter on every ranged scan. It is O(occurrences), a rare construct, and not visible in the profile (follow-up: tester)
FIX	swept	**MINOR** [other] docs/plans/sublinear-offset-state-pg-405.md:189 — `docs/plans/sublinear-offset-state-pg-405.md:189`: the plan says "On the old code a jump costs what a plain keystroke costs". "Measured before" showed that is wrong (follow-up: coder)
DROP	unlocated	**MINOR** [other] `build/pg405-release-sample-fullclass.txt`: a sample of the wrong process, left over from Task 7 (follow-up: coder)
FIX	swept	**MINOR** [other] docs/plans/sublinear-offset-state-pg-405.md:294 — `docs/plans/sublinear-offset-state-pg-405.md:294` and `:436-437` still call the anchored rule "verbatim" (follow-up: coder)
DROP	fix-hunk	**MINOR** [other] Tests/OffsetStoreModelTests.swift:162-167 — `Tests/OffsetStoreModelTests.swift:162-167`: the `precedes`/`follows` comparisons restate the production bodies and cannot fail; no independent oracle (follow-up: coder)
DROP	post-sweep	**NIT** docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md:434 — The inserted line is 177 characters where the file's prose wraps near 100. Fix: split it over two lines. (reviewer: opus)
DROP	post-sweep	**MINOR** [other] Sources/Features/Editor/NoteTextView+Transclusion.swift:166 — `Sources/Features/Editor/NoteTextView+Transclusion.swift:166`, `:187`, `:400`: the `lastRenditions` filters and the `shift` stay O(transclusions) per keystroke, the bound ADR-0094 §D8 accepts (follow-up: coder)
DROP	fix-hunk	**MINOR** [other] Tests/EditorRestyleJumpTests.swift:94 — `Tests/EditorRestyleJumpTests.swift:94`: SwiftLint reports `multiple_closures_with_trailing_closure` (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Tests/OffsetStoreModel.swift:322 — `Tests/OffsetStoreModel.swift:322` and `Tests/OffsetStoreModelTests.swift:52`: `cyclomatic_complexity` 11, over the limit of 10 (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Tests/OffsetStoreModel.swift:305 — `Tests/OffsetStoreModel.swift:305`: `large_tuple`, a 3-member tuple (follow-up: coder)
```
