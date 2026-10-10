**Requirement set:** `docs/archive/specs/per-paragraph-restyle.SPEC.md` (root `SPEC.md` while this was built)

# Per-keystroke restyle cost proportional to the edited paragraph (follow-up of PG-385 N2)

- **SPEC:** root `SPEC.md`, "Per-keystroke restyle cost proportional to the edited paragraph
  (follow-up of PG-385 N2)", Status Approved (2026-10-10), R-01 to R-16. Its `## Decisions`,
  `## Constraints` and `## Test seams` are settled input, and no task below reopens them. `/ship`
  archives it under `docs/archive/specs/`.
- **ADR outcome: new ADR**, `docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md`,
  written `proposed`.
  - It extends ADR-0082 §D2, §D5, §D8 and §D9, closes §D9's "restyle only the edited paragraph"
    follow-up, keeps §D6, and leaves §D7 withdrawn.
  - It touches ADR-0077 §D1.
  - It answers the SPEC's two "Not yet specified" questions: §D3 for the signature and the
    widening rule, §D5 for unspellable ranges and paragraph spacing.
  - It becomes `planned` if it lands on `main` with this plan ahead of the code, and `accepted`
    when the code PR merges (`docs/adr/README.md` rule 2).
  - The number was checked free on 2026-10-10. Check it again right before the merge (rule 1).
- **Governing ADRs, registered and not reopened:**
  - ADR-0001 §D1: `Sources/Core` is Foundation-only and compiled into `perg` and `pergamenum-mcp`.
  - ADR-0074: pass order, and each controller owns its state.
  - ADR-0081 §D4: a displayed paragraph keeps the stored length.
  - ADR-0082 §D2, §D5, §D6, §D8 and §D9: one grammar; the CPU-minimum budget; the scoped renumber
    in the keystroke's undo step; surface parity; the measured costs.
  - ADR-0033 §D3: view-block hosts keyed by ordinal.
  - ADR-0037 §D7: the reveal toggle restyles on `updateNSView`.
  - ADR-0045: widening a `private` member, with one comment naming its reader.
  - ADR-0077 §D7: the golden corpus.
- **Baseline.**
  - The worktree is on `docs/spec-per-paragraph-restyle` at `da38099d`, which is also
    `origin/main`.
  - `SPEC.md` is untracked. The previous root SPEC is staged as a rename to
    `docs/specs/note-workflow-n3.spec.md`.
  - This plan and ADR-0091 are uncommitted.
  - `TODO.md.lock` exists in the working tree: see Risks.
- **Delivery: one code PR** on `feature/per-paragraph-restyle`, cut from `main` after the docs
  branch lands, in one `/build` session.
  - If the context runs short, the session splits after Task 2, because Tasks 1 and 2 form a
    green, self-contained pure layer.
  - Run `tuist install` and `tuist generate --no-open` before the first task, and again after
    every task that adds a file.

## SPEC decisions registered (settled, not reopened)

- **Dirty-range restyle.** Attributes are rewritten only inside the dirty range, and
  `NSTextStorage` shifts the rest itself. Offset-keyed state is shifted by the delta in a linear
  pass, with no parsing. A per-line span cache was rejected.
- **Structural signature, otherwise a full restyle.** A local block (a table run, a list run)
  widens to the block. Always widening and never falling back was rejected.
- **The edited range comes from the text storage**, not from `shouldChangeTextInRanges`. A
  wholesale replace is a full restyle.
- **Layout stays whole-document in `growToFitTheText`.** Re-scoping it is a new decision with its
  own G-grow.
- **The card stays on the whole-text path.** Parity is proven by the property test.
- **A hidden kill switch**: a `UserDefaults` key plus a launch argument. An idle reconciliation was
  rejected.
- **The bench**: the six rows are asserted at the ceilings set at the gate (proposal 20 ms CPU).
  The fallback rows are printed and never asserted.

## What reading the tree added (`da38099d`)

1. **The styler is not in the shared sources.**
   - `MarkdownStyler` lives in the app target and calls the app-side `embedRun(inLine:)`
     (`Sources/Features/Editor/EmbedRun.swift`).
   - The SPEC's API sentence ("kept in the shared sources") is therefore met in part.
   - The grammar facts go into `Sources/Core`: the line signature, list roles and seeds, the
     `lineTokens` seed, and fragment transclusions.
   - The fragment entry, the map and the scope go beside the styler, Foundation-only.
   - ADR-0091 §D1 records the deviation and its reason. No SwiftUI enters a shared file, so the
     constraint the SPEC actually binds holds.
2. **A keystroke styles twice.** `textDidChange` calls `applyStyling`
   (`NoteTextView+Coordinator.swift:191-226`). The binding write then schedules `updateNSView`,
   whose `runPasses` (`NoteTextView+Update.swift:54-72`, called at `NoteTextView.swift:265`)
   calls `applyStyling` and the whole-text transclusion scan again.
3. **`selectionCrossedFence(in:)` runs a whole-text `CodeFence.regions`** inside every
   `insertText` once the note spells `pergamenum-view`
   (`NoteTextView+ViewBlocks.swift:95-100` → `NoteTextView+ViewBlockEditing.swift:119-129`).
4. **The text storage's delegate slot is free.** No file under `Sources/` assigns it, and
   `NSTextContentStorage` takes part as the `textStorageObserver`.
   - `NSTextStorageDelegate` carries no main-actor annotation in the MacOSX27.0 SDK
     (`NSTextStorage.h:129-142`).
   - So the `@MainActor` coordinator implements the callback `nonisolated` and enters the main
     actor with `MainActor.assumeIsolated`, the pattern already at
     `NoteTextView+Coordinator.swift:582`.
5. **The `NSTextContentManager.h:120` constraint** sits at `NSTextContentManager.h:282-283` in the
   MacOSX27.0 SDK. Only the line number moved.
6. **Enter in a list replaces `0..<length`** (`claimsListCommand`,
   `NoteTextView+ListEditing.swift:37-45`), and so does the whole-text `renumberLists(in:)`
   (`:61-69`). Both stay full restyles under this design (ADR-0091 §D2). Narrowing them is a user
   decision, see Risks.
7. **Grammar facts the widening rests on** (ADR-0091 C3):
   - a styler line ends at `"\n"` or `"\r\n"` (`MarkdownStyler.swift:145` passes
     `LineBreak.isTerminator`; `CodeFence.lineRanges` and `ListNesting.levels` use the same
     predicate);
   - the six cross-line constructs are frontmatter (two parsers), code fences
     (`CodeFence` ``` ``` ```; `WikilinkParser.codeRanges` also `~~~`), view blocks, tables
     (including a pipe-less delimiter row), list levels (a forward fold over every line) and
     wikilinks (global pairing);
   - the blockquote is line-local.
8. **PG-219 coordination has nothing in flight.** `git log origin/main..docs/spec-pg-219-cursor-feedback`
   is empty, PG-219 closed on 2026-10-06, and ADR-0090 merged through PR #920.
9. **Test survey (R-13), in four groups:**
   - 32 test files call the coordinator's `applyStyling(to:theme:)` directly, and it stays a full
     restyle;
   - 5 card test files call `CardTextView`'s own `applyStyling(to:)`, which is untouched;
   - 7 files type through `insertText` or `textDidChange`;
   - 63 files edit an editor's text programmatically.

   No assertion read so far depends on a keystroke restyling outside the touched paragraph. The
   full suite with the incremental path on (Task 5) is what settles it. Any red is restated only
   after its reason is in ADR-0091 §D12.

## Requirement coverage

| Requirement | Tasks |
| --- | --- |
| R-01 | 6 |
| R-02 | 1, 2, 3 |
| R-03 | 1, 2 |
| R-04 | 1, 2 |
| R-05 | 3, 4 |
| R-06 | 3, 5 |
| R-07 | 3, 5 |
| R-08 | 3, 5 |
| R-09 | 3, 5 |
| R-10 | 3, 5 |
| R-11 | 3, 5 |
| R-12 | 6 |
| R-13 | 6, 7 |
| R-14 | 7 |
| R-15 | 7 |
| R-16 | 7 |

## Order

1. The pure layer: the grammar facts, the structure map, the scope decision and the fragment
   entry, red (Task 1) then green (Task 2).
2. The coordinator's seams, red (Task 3).
3. Offset-keyed shifting in every holder (Task 4).
4. The coordinator wiring: recording, the incremental branch, the second-pass skip, transclusion
   and embed scoping, the kill switch (Task 5).
5. The bench and the restated tests (Task 6).
6. The documents, the ledger and the hand checks (Task 7).

The ledger entry of Task 7 may be filed first, at plan approval.

### Task 1 — Tester: the grammar facts, the structure map, the scope decision and the fragment entry, declared and red (R-02, R-03, R-04)
Owner: tester
Files: Sources/Core/Markdown/MarkdownLineSignature.swift, Sources/Core/Editor/ListNesting.swift, Sources/Core/Markdown/MarkdownTokens.swift, Sources/Core/Markdown/Transclusion.swift, Sources/Features/Editor/StorageEdit.swift, Sources/Features/Editor/StructureMap.swift, Sources/Features/Editor/RestyleScope.swift, Sources/Features/Editor/MarkdownStyler+Incremental.swift, Sources/Features/Editor/ProseParagraphSpacing.swift, Tests/IncrementalStylerPropertyTests.swift, Tests/IncrementalStylerModel.swift, Tests/MarkdownLineSignatureTests.swift, Tests/ListNestingSeedTests.swift, Tests/StructureMapTests.swift, Tests/RestyleScopeTests.swift
Tests: IncrementalStylerPropertyTests.swift, IncrementalStylerModel.swift, MarkdownLineSignatureTests.swift, ListNestingSeedTests.swift, StructureMapTests.swift, RestyleScopeTests.swift, StylerGoldenTests.swift, MarkdownLineTokenTests.swift, ListNestingTests.swift, ListNestingForwardPassTests.swift, TransclusionTests.swift, CRLFLineWalkTests.swift
Signatures:
- MarkdownLineSignature — struct MarkdownLineSignature: Equatable, Sendable { var fenceMark: Bool; var tableCapable: Bool; var listRole: ListNesting.Role; var brackets: [Bracket] }
- MarkdownLineSignature.Bracket — enum Bracket: Equatable, Sendable { case open(embed: Bool, inCode: Bool); case close }
- MarkdownLineSignature.of — static func of(_ line: Substring) -> MarkdownLineSignature
- ListNesting.Role — enum Role: Equatable, Sendable { case blank; case item(indent: Int, contentColumn: Int); case continuation; case reset }
- ListNesting.role — static func role(of line: Substring) -> Role
- ListNesting.folding — static func folding(_ stack: [Int], _ role: Role) -> [Int]
- ListNesting.levels(in:seed:) — static func levels(in text: String, seed: [Int]) -> [String.Index: Int]
- ListNesting.level(in:lineStart:indent:seed:) — static func level(in text: String, lineStart: String.Index, indent: Int, seed: [Int]) -> Int
- MarkdownBlockParser.lineTokens — static func lineTokens(in text: String, readsFrontmatter: Bool = false, endsLine: (Character) -> Bool = \.isNewline, listSeed: [Int] = []) -> [MarkdownLineToken]
- Transclusion.occurrences(inFragment:offset:) — static func occurrences(inFragment fragment: String, offset: Int) -> [Occurrence]
- StorageEdit — struct StorageEdit: Equatable, Sendable { var range: NSRange; var delta: Int; var oldRange: NSRange { get } }
- StorageEdit.shifted(offset) — func shifted(_ offset: Int) -> Int
- StorageEdit.shifted(range) — func shifted(_ range: NSRange) -> NSRange?
- StorageEdit.clipped — func clipped(_ range: NSRange) -> [NSRange]
- StructureMap — struct StructureMap: Equatable, Sendable { private(set) var lines: [Line]; private(set) var fences: [Fence]; private(set) var tableRuns: [NSRange]; private(set) var viewBlockRuns: [NSRange]; private(set) var frontmatterZoneEnd: Int?; init(text: String) }
- StructureMap.Line — struct Line: Equatable, Sendable { var start: Int; var signature: MarkdownLineSignature }
- StructureMap.Fence — struct Fence: Equatable, Sendable { var range: NSRange; var language: String?; var isClosed: Bool }
- StructureMap.apply — mutating func apply(_ edit: StorageEdit, in text: NSString)
- StructureMap.splice — mutating func splice(_ fragment: StructureMap, at offset: Int, replacing dirty: NSRange)
- RestyleScope — struct RestyleScope: Sendable { private(set) var map: StructureMap; init(text: String) }
- RestyleScope.Decision — enum Decision: Equatable, Sendable { case full(Reason); case lines(NSRange) }
- RestyleScope.Reason — enum Reason: Equatable, Sendable { case noBaseline, wholesale, frontmatter, fenceLine, wikilinkTokens, wikilinkPending }
- RestyleScope.record — mutating func record(_ edit: StorageEdit, in text: NSString)
- RestyleScope.take — mutating func take() -> Decision?
- RestyleScope.listSeed — func listSeed(at offset: Int) -> [Int]
- RestyleScope.absorb — mutating func absorb(_ fragment: StructureMap, at offset: Int, replacing dirty: NSRange)
- MarkdownStyler.FragmentContext — struct FragmentContext: Equatable, Sendable { var listSeed: [Int]; var readsFrontmatter: Bool }
- MarkdownStyler.spans(inFragment:context:) — static func spans(inFragment fragment: String, context: FragmentContext) -> [StyledRange]
- MarkdownStyler.spliced — static func spliced(_ current: [NSRange], replacing dirty: NSRange, with fragment: [NSRange]) -> [NSRange]
- ProseParagraphSpacing.paragraphRanges(inFragment:offset:spans:) — static func paragraphRanges(inFragment fragment: String, offset: Int, spans: [MarkdownStyler.StyledRange]) -> [NSRange]
Red: yes

Declare every symbol above with a placeholder body that returns a neutral value: an empty array,
`nil`, `.blank`, an unchanged stack, a map with no lines, and `take()` returning `.full(.noBaseline)`.
A body is never `fatalError`, because a trap kills the whole test host instead of turning one test
red.

Placement:

- `MarkdownLineSignature.swift` and the `ListNesting`, `lineTokens` and `Transclusion` additions sit
  in the shared sources. They import Foundation only, and `Sources/Core/**` is already in
  `sharedSources`.
- `StorageEdit`, `StructureMap`, `RestyleScope` and `MarkdownStyler+Incremental.swift` sit beside
  the styler, also Foundation-only (ADR-0091 §D1).

Run `tuist generate --no-open`, then build `perg` and `pergamenum-mcp` once to prove that the shared
additions compile there.

The tests, all Swift Testing with `#expect`:

- **`IncrementalStylerModel`** is the pure model of the editor's styling state:
  - the text;
  - a `RestyleScope`;
  - the spans as `(NSRange, Span)` in emission order;
  - the merged unspellable ranges;
  - the paragraph-spacing ranges.

  `apply(_:)` turns a string edit into a `StorageEdit`, records it, and shifts the spans and ranges
  with `StorageEdit`.

  `restyle()` takes the decision:
  - `.full`: everything is recomputed with `spans(in:)`;
  - `.lines(r)`: the fragment `r` is styled with `FragmentContext(listSeed: scope.listSeed(at: r.location), readsFrontmatter: r.location == 0)`.
    Its spans, unspellable ranges and spacing are spliced, and the fragment's map is absorbed.

  `coverage(_:)` renders a span list canonically as runs, each holding the ordered stack of spans
  that covers it. Equal coverage means equal attributes, because the styler applies spans in
  emission order and "later wins" is the only overlap rule.
- **`IncrementalStylerPropertyTests` (R-02, Seam 1).**
  - Seeds: a fixed SplitMix64 generator with the seeds `1, 2, 3, 5, 8, 13, 21, 34, 55, 89`, at 200
    edits each.
  - The SPEC's alphabet plus these tokens: ` ``` `, `~~~`, ` ```pergamenum-view\n`, `---`, `[[`,
    `]]`, `![[`, `| --- |`, `- `, `1. `, `> `, `\t`, `\r\n`, U+2028, a lone `\r`, `*`, `_`, `~`,
    `!`.
  - Edit kinds: insert, delete, multi-line replace (paste), the inverse of the previous edit
    (undo), and edits at offset 0, at the end and into an empty text.
  - Offsets are drawn from grapheme boundaries.
  - Also seeded: each of the 119 golden inputs as a starting text with 20 edits (R-03 as an
    oracle).
  - After every `restyle()`, three assertions:
    1. coverage, unspellable ranges and spacing ranges equal a full recomputation;
    2. `scope.map == StructureMap(text:)`;
    3. the decision was not `.full` for at least the share of edits that touched only line-local
       constructs. This is a non-vacuity floor, so that a scope that always answers `.full`
       cannot pass.
  - Keep the texts under 4 KB, and report the suite's added time in the task's notes.
- **`RestyleScopeTests` (R-04)**, one named case per SPEC edge case, each asserting the decision:
  - a fence opened and closed, with ` ``` ` and with `~~~`;
  - a `pergamenum-view` fence line;
  - an edit inside a fence body, which widens to the region, to the end when unclosed;
  - frontmatter: an edit inside it, `---` typed at offset 0, a leading U+FEFF, and a deleted
    closing line;
  - a table header, a delimiter row, a pipe-less delimiter, and a run split or joined;
  - a list indent change that widens until the stacks converge, and a `.reset` line that stops
    the widening;
  - a blockquote that stays `.lines`, which asserts ADR-0091 §D3's decision;
  - `[[` or `]]` typed or deleted, which is `.full(.wikilinkTokens)`;
  - a pending opener with a later `]]`, which is `.full(.wikilinkPending)`;
  - plain prose, which is `.lines` of the edited line;
  - a CRLF line, and U+2028 and a lone `\r` inside a line.
- **`MarkdownLineSignatureTests`, `ListNestingSeedTests`, `StructureMapTests`:**
  - `MarkdownLineSignature.of` against each recogniser it restates;
  - `levels(in:seed:)` with an empty seed equal to `levels(in:)`;
  - `lineTokens(listSeed: [])` equal to today's tokens;
  - `occurrences(inFragment:offset:)` equal to the slice of `occurrences(in:)`;
  - `StorageEdit`'s three rules: before stays, after moves by delta, containing stretches;
    partial is `nil` for `shifted`, and is cut down to the outside parts for `clipped`;
  - the map's apply and splice.

`StylerGoldenTests` is relied on unchanged: the full path does not change.

### Task 2 — Coder: the bodies of the pure layer (R-02, R-03, R-04)
Owner: coder
Files: Sources/Core/Markdown/MarkdownLineSignature.swift, Sources/Core/Editor/ListNesting.swift, Sources/Core/Markdown/MarkdownTokens.swift, Sources/Core/Markdown/Transclusion.swift, Sources/Features/Editor/StorageEdit.swift, Sources/Features/Editor/StructureMap.swift, Sources/Features/Editor/RestyleScope.swift, Sources/Features/Editor/MarkdownStyler+Incremental.swift, Sources/Features/Editor/MarkdownStyler.swift, Sources/Features/Editor/ProseParagraphSpacing.swift
Tests: IncrementalStylerPropertyTests.swift, MarkdownLineSignatureTests.swift, ListNestingSeedTests.swift, StructureMapTests.swift, RestyleScopeTests.swift, StylerGoldenTests.swift, MarkdownLineTokenTests.swift, ListNestingTests.swift, ListNestingForwardPassTests.swift, TransclusionTests.swift, CRLFLineWalkTests.swift, MarkdownStylerTests.swift, MarkdownStylerBlockTests.swift, ProseParagraphSpacingTests.swift
Signatures:
- MarkdownStyler.spans(in:) — static func spans(in text: String) -> [StyledRange] (unchanged signature and meaning)
- ListNesting.levels(in:) — static func levels(in text: String) -> [String.Index: Int] (unchanged; becomes levels(in: text, seed: []))
- ListNesting.level(in:lineStart:indent:) — static func level(in text: String, lineStart: String.Index, indent: Int) -> Int (unchanged)
- Transclusion.occurrences(in:) — static func occurrences(in text: String) -> [Occurrence] (unchanged)
Red: no

Fill the bodies so that Task 1's tests turn green, following ADR-0091 §D3, §D4 and §D5.

**Line signatures and list roles.**

- `MarkdownLineSignature.of` reads each member with the predicate it restates. It never writes a
  second copy of a predicate:
  - `CodeFence.marks` for the fence mark, plus the `~~~` test;
  - `GFMTable.alignments` for a delimiter row;
  - `ListNesting.role(of:)` for the list role;
  - the bracket scan of `WikilinkParser.links`.

  If a predicate is `private`, widen it per ADR-0045 with a comment naming
  `MarkdownLineSignature` as its reader.
- `ListNesting.role(of:)` and `folding(_:_:)` are the body of the existing forward loop
  (`ListNesting.swift:47-77`), and `levels(in:)` becomes the fold over them. A tab counts as 4,
  and the level is still `min(1 + stack.count, 6)`.
- The `seed` overloads start the forward fold, or bottom out the backward read, at the given stack.

**The fragment entry.**

- `lineTokens` passes `listSeed` to both reads (`MarkdownTokens.swift:90` and `:196`).
- `spans(inFragment:context:)` runs the same steps as `spans(in:)`, in the same order. With
  `readsFrontmatter == false` it skips both `NoteFrontmatter.range` and `lineTokens`' frontmatter
  read, so a fragment line that starts with `---` is never a frontmatter block.
- Factor the shared steps into one private function. Do not duplicate them: the golden corpus
  (R-03) and the property test pin both paths.

**Scope and map.**

- `RestyleScope.record` does three things:
  1. reads the old lines' signatures from the map;
  2. applies the edit to the map, with the shift plus a recomputation of the touched lines;
  3. decides, per §D3's table, and folds the decision into the pending one through the edits that
     follow.
- `take()` returns the union, aligned outward to styler lines by a UTF-16 scan for U+000A, then
  widened, and clears the pending state.

**The splice helpers.** `MarkdownStyler.spliced` cuts the dirty range out of the list, inserts the
fragment's ranges, and re-merges at the two seams only. `ProseParagraphSpacing.paragraphRanges(inFragment:offset:spans:)`
is the existing per-line predicate over the fragment's lines.

Run `tuist generate --no-open`, then:

- the unit suite;
- `xcodebuild … -scheme perg … build`;
- `xcodebuild … -scheme pergamenum-mcp … build`;
- `scripts/mcp-smoke.py`, because `Sources/Core` changed.

### Task 3 — Tester: the coordinator's seams, hosted, red (R-02, R-05, R-06, R-07, R-08, R-09, R-10, R-11)
Owner: tester
Files: Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+StorageEdits.swift, Sources/Features/Editor/NoteTextView+DerivedState.swift, Sources/Features/Editor/EditorRestyleSwitch.swift, Sources/Features/Editor/EditorDecorationDelegate.swift, Sources/Features/Editor/NoteTextView+Tables.swift, Sources/Features/Editor/TableGridStore.swift, Sources/Features/Editor/NoteTextView+ViewBlocks.swift, Sources/Features/Editor/NoteTextView+Embeds.swift, Sources/Features/Editor/NoteTextView+Transclusion.swift, Sources/Features/Editor/NoteTextView+Folding.swift, Sources/Features/Editor/NoteTextView+Reveal.swift, Tests/IncrementalRestyleHostedTests.swift, Tests/OffsetShiftTests.swift, Tests/TransclusionScopeTests.swift, Tests/EditorRestyleSwitchTests.swift, Tests/IncrementalRestyleSurfacesTests.swift, Tests/NoteTextViewUpdatePinsTests.swift, Tests/ScrolledEditorFixture.swift
Tests: IncrementalRestyleHostedTests.swift, OffsetShiftTests.swift, TransclusionScopeTests.swift, EditorRestyleSwitchTests.swift, IncrementalRestyleSurfacesTests.swift, NoteTextViewUpdatePinsTests.swift, ScrolledEditorFixture.swift, DailySurfaceQueriesTests.swift, ListRenumberScopeTests.swift, ListRenumberRecordingTests.swift, NoteListEditingTests.swift, CardTextViewTests.swift, CardFormattingTests.swift, CardConcealmentTests.swift, CardBlockMarkerTests.swift, CardFoldTests.swift, CardFoldBadgeTests.swift
Signatures:
- RestyleLog — struct RestyleLog: Equatable, Sendable { var full: Int; var incremental: Int; var skipped: Int; var lastDirtyRange: NSRange? }
- NoteTextView.Coordinator.restyleLog — private(set) var restyleLog: RestyleLog
- NoteTextView.Coordinator.forcesFullRestyle — var forcesFullRestyle: Bool
- NoteTextView.Coordinator.lastRecordedEdit — private(set) var lastRecordedEdit: StorageEdit?
- NoteTextView.Coordinator.applyStylingIfNeeded — func applyStylingIfNeeded(to textView: NSTextView, theme: Theme)
- NoteTextView.Coordinator.textStorage(_:didProcessEditing:range:changeInLength:) — nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) (conformance `extension NoteTextView.Coordinator: NSTextStorageDelegate`)
- NoteTextView.Coordinator.shiftDerivedState — func shiftDerivedState(by edit: StorageEdit)
- NoteTextView.Coordinator.derivedStateSnapshot — func derivedStateSnapshot() -> DerivedStateSnapshot
- DerivedStateSnapshot — `struct DerivedStateSnapshot: Equatable { var decorations: DecorationSnapshot; var unspellable: [NSRange]; var embedRuns: [NSRange]; var tablesDrawn: [Int]; var tableHiddenRows: Set<Int>; var viewBlocksDrawn: [Int]; var viewBlockHiddenLines: Set<Int>; var embedRenditions: [Int]; var transclusionRenditions: [Int]; var foldLayout: NoteFolding.Layout; var revealed: Set<Int>; var revealedSpans: [Int: [NSRange]]; var map: StructureMap? }`
- EditorDecorationDelegate.offsetKeyedSnapshot — func offsetKeyedSnapshot() -> DecorationSnapshot
- DecorationSnapshot — `struct DecorationSnapshot: Equatable { var hiddenMarkerKeys: [Int]; var hiddenLineOffsets: Set<Int>; var foldedHeadings: [Int: Int]; var tableRowOffsets: Set<Int>; var viewBlockLineOffsets: Set<Int>; var renditionKeys: [Int]; var embedRenditionKeys: [Int]; var revealedParagraphs: Set<Int>; var revealedSpanKeys: [Int]; var tableViewKeys: [Int]; var viewBlockHostKeys: [Int] }`
- EditorDecorationDelegate.shift — func shift(by edit: StorageEdit)
- TableBlockController.shift — func shift(by edit: StorageEdit)
- TableGridStore.shift — func shift(by edit: StorageEdit)
- TableGridStore.identities — func identities() -> [Int: ObjectIdentifier]
- ViewBlockController.shift — func shift(by edit: StorageEdit)
- EmbedTable.shift — func shift(by edit: StorageEdit)
- TransclusionController.shift — func shift(by edit: StorageEdit)
- TransclusionController.lastScannedRange — private(set) var lastScannedRange: NSRange?
- FoldController.shift — func shift(by edit: StorageEdit)
- RevealController.shift — func shift(by edit: StorageEdit)
- EditorRestyleSwitch — enum EditorRestyleSwitch { static let key: String }
- EditorRestyleSwitch.forcesFullRestyle — static func forcesFullRestyle(arguments: [String], defaults: UserDefaults) -> Bool
Red: yes

**Placeholders**, each one keeping today's behaviour so that the existing suite stays green:

- `applyStylingIfNeeded` calls `applyStyling(to:theme:)`;
- every `shift(by:)` does nothing, and the delegate callback is empty;
- `restyleLog` stays zero;
- `EditorRestyleSwitch.key` is `"editorFullRestyle"` and the read returns `false`;
- `derivedStateSnapshot()` and `offsetKeyedSnapshot()` return real values, read from the existing
  stores. They are test seams, not behaviour.

**Where things go.**

- Stored properties go in `NoteTextView+Coordinator.swift`, where `isStyling` is `private` and the
  incremental branch will live (Task 5).
- The delegate conformance goes in the new `NoteTextView+StorageEdits.swift`.
- Snapshots and shifts go in each holder's own file, because the stores are `private` there
  (`EditorDecorationDelegate.swift:125-252`, `TableGridStore.swift:25`). No store is widened.
- A member that must be read from outside its file is widened per ADR-0045, with one comment
  naming its reader.

**The tests.** A hosted twin is a second `ScrolledEditorFixture` with `forcesFullRestyle = true`,
fed the same edits through the same entry points. `ScrolledEditorFixture` gains an initialiser
parameter that sets the flag before `openLikeTheApp()`. Its default is `false`, so no existing
caller changes.

- **`IncrementalRestyleHostedTests`:**
  - (R-02) 10 fixed seeds × 25 edits, through `type(_:at:)`, `replaceCharacters` plus
    `didChangeText`, `undoManager.undo()` and `redo()`. After each edit:
    - the storages' attributes are equal run by run (`enumerateAttributes`, compared with
      `isEqual`; attachments compared by the presence of a view and its key, never by object);
    - `derivedStateSnapshot()` is equal for both.
  - (R-06) one undo step per keystroke, including a keystroke that renumbers (`1.` to `3.`, as
    `ListRenumberScopeTests` does): the selection after the undo, and the reveal set under the
    caret.
  - (R-07) `setMarkedText` mid-word: `hasMarkedText()`, `markedRange()` and the selection are
    unchanged by the restyle, and are equal to the twin's.
  - (R-06, platform pin) `lastRecordedEdit` after typing `x` at 10 is `(range: {10, 1}, delta: 1)`;
    after deleting 3 characters at 10 it is `(range: {10, 0}, delta: -3)`. ADR-0091 C4 rests on
    this.
  - (R-06, platform pin) `textStorage.delegate` is `nil` on a fresh fixture before the first full
    restyle, so installing the coordinator displaces nothing.
  - (R-06) `restyleLog.incremental` grows on a prose keystroke and `restyleLog.full` grows on a
    fence-line keystroke.

  Non-vacuity: every twin comparison runs on a fixture that holds a table, a view block, a
  transclusion, a fold, hidden markers and unspellable ranges below the edit, and asserts that each
  matching snapshot field is non-empty. An empty snapshot fails instead of passing.
- **`OffsetShiftTests` (R-05).** Set the kill switch on the fixture so that nothing shifts by
  itself. Edit above a table, a view block, an embed, a transclusion, a fold and a hidden marker,
  call `shiftDerivedState(by:)` with the recorded edit, and compare `derivedStateSnapshot()`
  outside the edited lines with a twin fully restyled on the new text. Assert the same
  `ObjectIdentifier` for the grid of the table below the edit (`TableGridStore.identities()`),
  and for the view-block host.
- **`NoteTextViewUpdatePinsTests` (R-08).** Drive the hosted SwiftUI harness through one keystroke
  and the `updateNSView` that follows it. The `runPasses` styling counts as `skipped`. A theme
  change, a `hidesMarkup` flip and a `revealsInlineSpans` flip each count as a styling.
- **`TransclusionScopeTests` (R-09):**
  - after a prose keystroke, `lastScannedRange` is the dirty range, and the rendition table equals
    the twin's full scan;
  - after a keystroke on a transclusion line, the new occurrence appears;
  - after a fence-line keystroke, the scan is whole.
- **`EditorRestyleSwitchTests` (R-10):**
  - `forcesFullRestyle(arguments: ["-editorFullRestyle", "YES"], defaults: …)` is true, the key in
    a scratch `UserDefaults(suiteName:)` is true, and absent is false;
  - with the switch on, `restyleLog.incremental` stays 0 over a typed sentence, and attributes and
    snapshot equal the twin's.
- **`IncrementalRestyleSurfacesTests` (R-11):**
  - `TodayView.swift` and `DiaryView.swift` build `NoteTextView`, and neither sets
    `forcesFullRestyle`. This reads the source, the pattern of `DailySurfaceQueriesTests:76-77`.
  - A fixture built with `ViewQuerySource.live(for:)` takes the incremental path and equals its
    twin.
  - The card tests are relied on unchanged.

### Task 4 — Coder: offset-keyed state is shifted where it lives (R-05)
Owner: coder
Files: Sources/Features/Editor/EditorDecorationDelegate.swift, Sources/Features/Editor/NoteTextView+Tables.swift, Sources/Features/Editor/TableGridStore.swift, Sources/Features/Editor/NoteTextView+ViewBlocks.swift, Sources/Features/Editor/NoteTextView+Embeds.swift, Sources/Features/Editor/NoteTextView+Transclusion.swift, Sources/Features/Editor/NoteTextView+Folding.swift, Sources/Features/Editor/NoteTextView+Reveal.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+DerivedState.swift
Tests: OffsetShiftTests.swift, TableGridHostedAttachmentTests.swift, TableGridCommitTests.swift, TableCaretTests.swift, ViewBlockCaretTests.swift, ViewBlockQuerySourceTests.swift, ViewBlockRenderingTests.swift, EmbedCaretTests.swift, EmbedDrawingTests.swift, TranscludedLineTests.swift, TransclusionLayoutTests.swift, NoteFoldingTests.swift, HiddenBlockLinesTests.swift, SpellCheckTests.swift
Signatures:
- EditorDecorationDelegate.splice — func splice(hiddenMarkers markers: [Int: [HiddenMarker]], in dirty: NSRange, hidingMarkup hides: Bool)
- EditorDecorationDelegate.apply(hiddenMarkers:hidingMarkup:) — func apply(hiddenMarkers markers: [Int: [HiddenMarker]], hidingMarkup hides: Bool) (unchanged, full path)
Red: no

Implement every `shift(by:)` with ADR-0091 §D6's rule, through `StorageEdit`:

- an offset before the old range stays;
- an offset at or after its end moves by `delta`;
- a range that contains the edit stretches;
- a range partly inside is dropped.

The splice rewrites whatever lies in the dirty range in any case. `shiftDerivedState(by:)` calls the
holders in one place, and also shifts `unspellableRanges` (with `StorageEdit.clipped`) and
`embedRuns`.

**`EditorDecorationDelegate` gets the shift and the splice entries.** They cover markers, table
rows, view-block lines, table views and view-block hosts, and replace only the keys inside the dirty
range. They live in `EditorDecorationDelegate.swift`, because its stores are `private`. The splice
invalidates layout only for the paragraphs it changed. The whole-dictionary comparison at `:339`
stays for the full path only.

**What must keep its identity.** A table outside the dirty range keeps its `TableGridView` (a key
shift in `TableGridStore.grids`, no rebuild). View-block hosts stay keyed by ordinal (ADR-0033 §D3),
and their line offsets shift.

Make `OffsetShiftTests` green and keep every listed suite green. Do not wire the delegate callback
yet: that is Task 5.

### Task 5 — Coder: the coordinator records, styles the dirty range, skips the second pass, scopes transclusions and embeds, honours the kill switch (R-06, R-07, R-08, R-09, R-10, R-11)
Owner: coder
Files: Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+StorageEdits.swift, Sources/Features/Editor/NoteTextView+Update.swift, Sources/Features/Editor/NoteTextView+Transclusion.swift, Sources/Features/Editor/NoteTextView+Embeds.swift, Sources/Features/Editor/NoteTextView+Tables.swift, Sources/Features/Editor/NoteTextView+ViewBlocks.swift, Sources/Features/Editor/NoteTextView+ViewBlockEditing.swift, Sources/Features/Editor/ProseParagraphSpacing.swift, Sources/Features/Editor/EditorRestyleSwitch.swift, Sources/Features/Editor/NoteTextView.swift
Tests: IncrementalRestyleHostedTests.swift, OffsetShiftTests.swift, TransclusionScopeTests.swift, EditorRestyleSwitchTests.swift, IncrementalRestyleSurfacesTests.swift, NoteTextViewUpdatePinsTests.swift, IncrementalStylerPropertyTests.swift, StylerGoldenTests.swift, EditorHeightTests.swift, EditorGrowToFitScopeTests.swift, ListRenumberScopeTests.swift, ListRenumberRecordingTests.swift, NoteListEditingTests.swift, DailySurfaceQueriesTests.swift, InlineSpanRevealFenceTests.swift
Signatures:
- NoteTextView.Coordinator.applyStyling(to:theme:) — func applyStyling(to textView: NSTextView, theme: Theme) (unchanged signature; stays the full restyle, now also installs the storage delegate, rebuilds the scope and clears the record)
- NoteTextView.runPasses — func runPasses(on textView: CompletingTextView, coordinator: Coordinator) (unchanged signature; calls applyStylingIfNeeded)
- ViewBlockController.selectionCrossedFence — func selectionCrossedFence(in textView: NSTextView) -> Bool (unchanged signature; reads the map's view-block runs)
Red: no

**1. Recording** (`NoteTextView+StorageEdits.swift`). The `nonisolated` callback keeps only
`.editedCharacters` and enters the main actor through `MainActor.assumeIsolated`, the
`NoteTextView+Coordinator.swift:582` pattern. Then:

- it sets `lastRecordedEdit`, calls `scope.record`, and calls `shiftDerivedState(by:)`;
- it does nothing at all while `forcesFullRestyle` is on;
- it reads only `scope.map` and the holders. No AppKit call, no layout, no parse beyond the
  touched lines' signatures.

The full `applyStyling` sets `textStorage.delegate = self` the first time it styles that storage. A
changed storage identity counts as no baseline.

**2. The incremental branch** (`NoteTextView+Coordinator.swift`, beside `applyStyling`, because
`isStyling` is `private`).

- `textDidChange` calls `applyStylingIfNeeded`, which asks `scope.take()`:
  - `nil` with a baseline whose inputs are unchanged: skipped;
  - `nil` with no baseline, as for a direct `textDidChange` from a test: full;
  - `.full`: full;
  - `.lines(r)`: incremental.
- The incremental path follows ADR-0091 §D4:
  1. one `String` copy of `r`;
  2. `spans(inFragment:context:)`;
  3. the span loop of `applyStyling` (`:293-321`), factored into one function with a text and an
     offset, so the full and incremental paths share it;
  4. `setAttributes(base)` over `r`;
  5. the spans' attributes, then `ProseParagraphSpacing` over `r`;
  6. the table and view-block passes for the runs inside `r`;
  7. the decoration splice;
  8. the unspellable splice (`MarkdownStyler.spliced`);
  9. `scope.absorb`;
  10. `endEditing`.
- `restyleLog` counts each path and sets `lastDirtyRange`.

**3. The second pass** (`NoteTextView+Update.swift`). `runPasses` calls `applyStylingIfNeeded`.
The fingerprint is:

- the storage's `ObjectIdentifier`;
- the recorded character-edit count;
- `Theme`;
- `hidesMarkup`;
- `revealsInlineSpans`.

When nothing differs and nothing is recorded, both the styling and the transclusion scan are
skipped (R-08). A toggle flip changes the fingerprint, so ADR-0037 §D7's restyle on `updateNSView`
still happens.

**4. Transclusions and embeds.** The styling pass hands `applyTransclusions` a one-shot scope token.

- With a token: scan `r` with `Transclusion.occurrences(inFragment:offset:)`, merge into the
  shifted table, resolve those occurrences, reserve space inside `r` only, and set
  `lastScannedRange`.
- Without a token (a direct call, a full pass, a changed rendition generation): the whole note as
  today. A changed rendition generation resolves again from the shifted table, without rescanning
  the text.
- Embeds are scoped the same way from the spliced `embedRuns`.

**5. Fence crossing.** `selectionCrossedFence` reads the map's view-block runs. When it answers
yes, it still triggers the full `applyStyling` (`:161`).

**6. The kill switch.** The coordinator's `init` reads
`EditorRestyleSwitch.forcesFullRestyle(arguments: ProcessInfo.processInfo.arguments, defaults: .standard)`.
The arguments domain makes `-editorFullRestyle YES` set the same key, and Impostazioni does not
show it. With the switch on, every pass is today's full path, the second pass included.

**7. PG-219 check.** Run `git log origin/main..docs/spec-pg-219-cursor-feedback`.

- Empty, as on 2026-10-10: there is nothing to coordinate.
- Not empty: stop and hand `sync_operation` the overlap in `textDidChange` and `growToFitTheText`
  before going further.

**Verify:**

- `StylerGoldenTests` stays byte-identical (R-03);
- the property test stays green;
- the `perg` and `pergamenum-mcp` builds pass;
- then the **full unit suite**, with the incremental path on (the default).

A red outside the listed files is a contract surprise: stop, and record its reason in ADR-0091 §D12
before any test changes (R-13).

### Task 6 — Tester: the bench prints the fallback rows, the ceilings are fixed at the gate, the restated tests carry their reason (R-01, R-12, R-13)
Owner: tester
Files: Tests/RestyleBudgetSupport.swift, Tests/EditorRestyleBudgetTests.swift, scripts/editor-restyle-bench.sh, docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md, docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md
Tests: EditorRestyleBudgetTests.swift, RestyleBudgetSupport.swift, StylerGoldenTests.swift, IncrementalStylerPropertyTests.swift
Signatures:
- RestyleBudget.FallbackPath — enum FallbackPath: String, Sendable, CaseIterable { case fenceOpen = "fence-open"; case table; case listEnter = "list-enter" }
- RestyleBudget.includesFallbackRows — static var includesFallbackRows: Bool
- RestyleBudget.fallbackLine — static func fallbackLine(_ c: Case, path: FallbackPath, cpuMs: Double, wallMs: Double, runs: Int) -> String
- RestyleBudget.ceilings — static let ceilings: [Case: Double] (values from G-ceiling-2)
Red: no

**1. The fallback rows (R-12).** One parametrised test over `activeCases × FallbackPath.allCases`.
It runs only when `RESTYLE_BUDGET_FALLBACK=1`, and prints
`restyle-budget-fallback size=<bytes> variant=<prose|fences> path=<fence-open|table|list-enter> cpu_ms=<min> wall_ms=<min> runs=<K>`
with the existing CPU-minimum method. It asserts nothing about the times, by decision. It does
assert that the keystroke took the path it names, through `restyleLog`:

- `fence-open` types the third backtick at the start of a line that already holds two, and is
  `full`;
- `table` types in a cell of a table inserted before the measurement, and is `incremental` with a
  `lastDirtyRange` equal to the table run;
- `list-enter` presses Enter at the end of a list item, and is `full`.

The synthetic notes of the six rows do not change. A test pins the new line's format, the way
`theLineHasTheSixFieldsTheBenchScriptGreps` pins the existing one.

**2. The script.** `scripts/editor-restyle-bench.sh` exports `TEST_RUNNER_RESTYLE_BUDGET_FALLBACK=1`
and prints a second table from the lines that start with `restyle-budget-fallback` (columns size,
variant, path, cpu_ms, wall_ms, runs). The exit status stays `xcodebuild`'s own, and the header
comment documents the new variable.

**3. G-ceiling-2 (R-01).** Measure "after" with the six rows plus the fallback rows:

- `scripts/editor-restyle-bench.sh --large` (the 1 MB rows take minutes before this change and
  should not after it);
- and once with `--runs 9`.

Record the numbers in ADR-0091 under a new "Measured after" note, and ask the person to fix the
six ceilings (the proposal is 20 ms CPU per row). Write them into `RestyleBudget.ceilings`. Until
the gate answers, ADR-0082 §D9's ceilings stay, and ADR-0082 §D9 gains one line pointing to
ADR-0091 for the new ones.

- **A 1 MB row that cannot reach 20 ms**, with the overshoot traced to `ensureLayout(for: documentRange)`
  or to the `parent.text` copy, is reported at the gate with its profile. It is never hidden by a
  looser ceiling chosen here: re-scoping the layout is a new decision (SPEC, Out of scope).

**4. Restated tests (R-13).** For every test that Task 5's full run turned red because it pinned
whole-note styling after a keystroke, write the reason into ADR-0091 §D12 first, in its own
commit. Then restate the test. A test is never disabled, deleted or loosened without that line. If
none was red, §D12 keeps "none" and says which run proved it.

**5. Full unit suite** with the default settings, then `scripts/editor-restyle-bench.sh` once more
to confirm that the six rows pass at the fixed ceilings.

### Task 7 — Coder: the documents, the ledger entry and the hand checks (R-13, R-14, R-15, R-16)
Owner: coder
Files: docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md, docs/adr/INDEX.md, CLAUDE.md, TODO.md
Tests: EditorRestyleBudgetTests.swift, IncrementalRestyleHostedTests.swift
Signatures:
- ADR index line — `- ADR-0091 — A keystroke restyles the paragraph it touched, and a structural change restyles the note`
- Ledger entry — kind:roadmap, adr:0091, links `PG-385` (#887) and PR #956
Red: no

**1. ADR-0091.** Finalise it:

- the status line (`planned` or `accepted` per `docs/adr/README.md` rule 2);
- §D12 as Task 6 left it (R-13);
- the "Measured after" numbers;
- the G-ceiling-2 answer.

**2. The ADR index line in `CLAUDE.md`** (`## ADR index`). Paste what `scripts/adr-index.py` prints,
which is the line in Signatures, and confirm with `scripts/adr-index.py --check`. Then run
`scripts/check-adr-references.py` against `origin/main` after a `git fetch`.

**3. The long-form summary in `docs/adr/INDEX.md`**, as one bullet after the ADR-0090 bullet of
the "Chain decision index", in the file's one-paragraph-per-ADR shape. The text below is the
bullet's content, to be pasted after `- ` on a single line:

> **ADR-0091** — Follow-up of `PG-385`/#887 and PR #956 (`proposed`, flips to `accepted` at the code PR's merge): a keystroke restyles the paragraph it touched, and a structural change restyles the note. The coordinator becomes the text storage's delegate and records each character edit (`StorageEdit`), so undo, redo, paste, IME and the renumber come by one route; `StructureMap` holds one `MarkdownLineSignature` per line (fence mark, table capability, list role, bracket tokens) plus fences, table runs, view-block runs and the frontmatter zone, shifted at the edit and spliced at the restyle (§D2). `RestyleScope` decides by §D3's table: the frontmatter zone, a fence line, changed bracket tokens or a pending `[[` restyle the whole note; a fence body widens to its region, a table to its run of table-capable lines, a list until the folded stacks converge; the blockquote is line-local. `MarkdownStyler.spans(inFragment:context:)` styles the dirty range through the same steps as `spans(in:)`, and only the dirty range's attributes are written (§D4); unspellable ranges are shifted and spliced, paragraph spacing is recomputed on the dirty lines (§D5); every offset-keyed holder shifts itself (§D6); transclusions and embeds are scanned only in the dirty range (§D7). `runPasses` skips a styling whose inputs did not change, and `editorFullRestyle` (`-editorFullRestyle YES`) forces today's path (§D8). Oggi and Diario inherit the path and the card does not (§D9); `growToFitTheText` still lays out the whole note (§D10); the bench prints three fallback rows, never asserted, and the six ceilings are fixed at G-ceiling-2 (§D11). The grammar facts live in the shared sources and the fragment entry beside the app-side styler (§D1, a recorded deviation from the SPEC's API sentence). No on-disk format, schema, protected interface or connector change; zero GUI tests. Extends ADR-0082 §D2/§D5/§D8/§D9, touches ADR-0077 §D1 → `docs/adr/0091-a-keystroke-restyles-the-paragraph-it-touched.md`

**4. The ledger entry (R-16)**, through `/project-tasks`, never by hand-editing around
`TODO.md.lock`. It may be filed at plan approval, before Task 1:

- kind `roadmap`, P2, the next free id (`PG-401` on 2026-10-10);
- the summary "Per-keystroke restyle cost proportional to the edited paragraph, follow-up of
  `PG-385` (#887) and PR #956 (`558db01c`)";
- paths `Sources/Features/Editor/NoteTextView+Coordinator.swift`,
  `Sources/Features/Editor/MarkdownStyler.swift` and `docs/plans/per-paragraph-restyle.md`;
- `adr:0091`.

**5. Acceptance, by the person, on a Release build** (`scripts/release.sh` is not needed; a local
Release configuration build is enough):

- **G-grow (R-14)**, with a 1 MB note: type at the end and in the middle, press Cmd+Down, scroll to
  the end, and click low in the pane. The caret lands where clicked, and nothing selects the whole
  note.
- **G-type (R-15)**, with a 50 KB note: a typed sentence shows no perceptible lag.

Both results go into ADR-0091's Gates section with the date. A failure reopens Task 5 or Task 6,
not the ADR's decision. Afterwards, update `PROJECT_BRIEF.md` "Status" only if this closes a
milestone item.

## Observable contracts and call sites

Each change below was grepped across `Sources/` and `Tests/` on 2026-10-10.

- **`MarkdownBlockParser.lineTokens(in:readsFrontmatter:endsLine:)` gains `listSeed: [Int] = []`.**
  Every caller passes nothing and keeps today's tokens:
  - `Sources/Core/Markdown/MarkdownBlocks.swift:87`;
  - `Sources/Features/Editor/MarkdownStyler.swift:145`;
  - `Tests/MarkdownLineTokenTests.swift`.

  The doc comments that name the old signature, at `Sources/Core/Editor/ListNesting.swift:133` and
  `Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift:118`, are updated in
  Task 2.
- **`ListNesting.levels(in:)` and `level(in:lineStart:indent:)` are kept**, and the `seed`
  overloads are new. Callers:
  - `Sources/Core/Markdown/MarkdownTokens.swift:90` and `:196`;
  - `Sources/Features/Editor/EditorDecorationDelegate+ListRendering.swift:186`;
  - `Tests/ListNestingTests.swift` and `Tests/ListNestingForwardPassTests.swift`;
  - `Tests/MarkdownStylerBlockTests.swift:178` (a comment).
- **`Transclusion.occurrences(in:)` is kept**, and the fragment entry is new. Callers:
  `Sources/Features/Editor/NoteTextView+Transclusion.swift`, `Tests/TransclusionTests.swift` and
  `Tests/CRLFLineWalkTests.swift`.
- **`NoteTextView.Coordinator.applyStyling(to:theme:)` keeps its signature and its full meaning.**
  Callers:
  - `NoteTextView+Coordinator.swift` (`:161` and `textDidChange`, which becomes
    `applyStylingIfNeeded`);
  - `NoteTextView+Update.swift:56` (`runPasses`, which becomes `applyStylingIfNeeded`);
  - `NoteTextView.swift`;
  - 32 test files, which keep the full restyle.

  `CardTextView.applyStyling(to:)` is a different method and is untouched, as are its 5 card test
  files.
- **`runPasses(on:coordinator:)` changes behaviour:** the styling and the transclusion scan are
  skipped when nothing changed. Caller: `NoteTextView.swift:265`. The pins are in
  `Tests/NoteTextViewUpdatePinsTests.swift`.
- **`ViewBlockController.selectionCrossedFence(in:)` keeps its signature** and reads the map.
  Caller: `NoteTextView+Coordinator.swift:161`.
- **The text storage's delegate is newly assigned.** No other assignment exists in `Sources/`.
- **No on-disk format, protected interface (`.claude/protected-interfaces`), connector, token or
  GUI test changes.**

Run the **full unit suite** after Tasks 2, 5 and 6, not only the new files: the styling contract
is shared by every surface that hosts `NoteTextView`.

## Risks and HITL gates

- **G-ceiling-2 (the person, Task 6).** Fixes the six ceilings from the "after" measurements (the
  proposal is 20 ms CPU). The 1 MB rows may stay above 20 ms because of the work this design keeps
  proportional to the note:
  - the `parent.text` copy;
  - `ensureLayout(for: documentRange)` walking every fragment;
  - `NoteFolding.layout` while something is folded.

  The gate decides. Re-scoping the layout would be a new ADR with its own G-grow.
- **G-grow (R-14) and G-type (R-15)**, by the person on a Release build (Task 7).
- **A user decision, not taken here:** narrowing `claimsListCommand`'s write (Enter in a list) and
  the whole-text renumber from `0..<length` to the span that changes. Today both are full restyles,
  about 200 ms per Enter at 50 KB and seconds at 1 MB, measured in Debug by ADR-0082 §D9. The
  architect's view: worth doing as a follow-up ledger entry, because Enter in a list is common
  typing. It changes the undo payload and the renumber's caret mapping, so it needs its own SPEC
  line.
- **A deviation from the SPEC to confirm:** the incremental entry point is beside the styler, not
  in the shared sources (ADR-0091 §D1). The grammar facts are shared, and no SwiftUI enters a
  shared file.
- **Correctness risk: divergence from the full result.** The guards are the property test (Seam 1),
  the hosted twins, and the kill switch for the person. A holder of offset-keyed state added later
  without a `shift(by:)` diverges until the next full restyle. ADR-0091 §D6 names the rule, and
  the R-05 test lists the holders.
- **Platform risk.** `NSTextStorageDelegate` is not main-actor annotated in the SDK, so the
  callback is `nonisolated` with `MainActor.assumeIsolated`. That traps if AppKit ever edits the
  storage off the main thread, which the editor never does today. The `editedRange` semantics and
  the free delegate slot are pinned by tests (Task 3), not assumed.
- **IME (R-07).** A restyle over the marked range must not end composition. Task 3 pins it against
  the twin. If the twin itself shows today's behaviour disturbing the marked text, report it rather
  than "fix" it silently.
- **Parallel work.**
  - A locked Kepler worktree is checked out on `kepler/fix/incremental-note-restyling`, at
    `/Users/stefer/kepler/worktrees/Pergamenum-fix-incremental-note-restyling-c08eafa6`.
  - Its branch has no commit beyond `main`: it sits at `bcbb3999`, behind `da38099d`.
  - Its uncommitted files are outside this session's scope and were not read.
  - Check it before `/build`, so that two implementations of the same idea do not collide.
- **`TODO.md.lock` exists** in this working tree. A `/project-tasks` write may be in progress or
  have died. Check it before filing the R-16 entry.
- **The staged SPEC rename** (`SPEC.md` → `docs/specs/note-workflow-n3.spec.md`), with the new
  `SPEC.md` untracked: the docs commit must carry both together.
- **HITL:** commit, push and PR creation on both branches; the merge; the G-ceiling-2, G-grow and
  G-type answers. No DB schema change, no deletion, no deploy. There are no externally provisioned
  resources.

## Candidates

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

- The test command is the existing `.claude/test-cmd`, unchanged.
- There is no check command for one reason: SwiftLint is the project's declared linter, but it
  fails by design on seven types today, `MarkdownStyler` among them, and the repository declares
  no `.claude/check-cmd`. A read-only check that is red before any change cannot gate anything.
- Adopting `swiftlint lint --strict --baseline <file>` is a separate decision.
