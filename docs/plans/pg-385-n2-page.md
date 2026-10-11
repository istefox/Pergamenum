**Requirement set:** `docs/specs-pending/pg-385-n2-page.SPEC.md`

# PG-385 — N2 the page, part one: markers in the gutter, a measured keystroke, one grammar

- **SPEC:** root `SPEC.md`, "N2 The page, part one" (PG-385, absorbs PG-347), Status Approved
  (2026-10-06), R-13 to R-19 and R-44 to R-46. Its `## Decisions`, `## Constraints` and
  `## Test seams` are settled input. No task below reopens them. `/ship` archives it as
  `docs/archive/specs/pg-385-n2-page.SPEC.md`.
- **ADR outcome: existing ADRs, cited and corrected, no new record.**
  - `docs/adr/0081-block-markers-reveal-in-the-gutter.md` (proposed) governs R-13 and R-14.
  - `docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md` (proposed) governs R-15
    to R-19.
  - Both landed on `main` as `proposed` in `f697b363`, written against `48a2d912`. Neither
    decision changes, so no supersession is needed. The drift found on `9103768f` is corrected
    in place by Task 8 (section "ADR corrections" below). Both flip to `accepted` only after the
    code PR merges, as the first docs change after it (`docs/adr/README.md` rule 2).
- **Governing ADRs, registered and not reopened:**
  - ADR-0001 §D1 and ADR-0007: `Sources/Core` is Foundation-only and compiled into `perg` and
    `pergamenum-mcp`;
  - ADR-0018 §D1/§D2: the reveal triggers and the per-paragraph marker table;
  - ADR-0028 §D2/§D4: list and checkbox concealment, amended by ADR-0081;
  - ADR-0029 §D1/§D10/§D17: quotes, rules, `GFMTable`, the card's `default: nil` seam;
  - ADR-0030 §D5/§D6/§D10: faces through `ProseTypography`, styles composed with `basedOn:`, no
    page line height in a card;
  - ADR-0033/0035: view blocks in the editor;
  - ADR-0045: widening a `private` member, with one comment naming its reader;
  - ADR-0074 §D2: editor state lives in a controller declared in the file whose pass writes it;
  - ADR-0077 §D1/§D5/§D7: one grammar, the export golden corpus.
- **Baseline.**
  - This worktree is on `docs/spec-pg-385-n2-page-markers` at `9103768f`, with `SPEC.md` and
    this plan untracked.
  - `origin/main` is at `1586128f`, two commits ahead. PR #908 (PG-340) changes
    `scripts/check-adr-references.py` and `docs/adr/README.md` only.
  - Merge `origin/main` into every N2 branch before its first task, never rebase or force. Then
    run `tuist install` and `tuist generate --no-open`.
- **Delivery: one mockup PR plus one code PR, three `/build` sessions.**
  - **Session A, mockup PR (Task 5).** Branch `feature/n2-gutter-mockup` from `main`. It shares
    no file with Tasks 1 to 4, so it may be built first or in parallel. It must be approved (G1,
    G2) before Session C starts.
  - **Session B, code PR first half (Tasks 1 to 4).** Branch `feature/pg-385-n2-page`. This is
    the baseline, the grammar, the keystroke and the surfaces. None of it depends on a mockup
    answer.
  - **Session C, code PR second half (Tasks 6 to 8).** Same branch, after G1 and G2. This is the
    gutter, then the final measurement and the documents. One PR at the end of Session C.
  - Numbering follows the SPEC's order, not the session order. Baseline first, grammar and
    keystroke before the gutter, the mockup gate before the gutter, surfaces independent,
    measurement last.

## SPEC decisions registered (settled, not reopened)

- **Gutter reveal by indents; the characters stay.** Every `NoteTextView` paragraph starts at
  `spacing.gutter`. The container inset shrinks by the same amount, and a revealed marker hangs
  through its paragraph's own indents.
- **Mockup decides the gutter's value, the heading marker's face, the quote step and the `H2`
  badge** (ADR-0081 G1/G2). The proposal is 48 pt, the caption face, 0.75 em and no badge.
- **One token layer in the shared parsers.** The styler maps the tokens onto its unchanged
  `Span` enum and its private recognisers are deleted.
- **A golden corpus is captured from the old styler before it changes.** Each difference is
  classed A, B or C, and a C blocks the merge.
- **`>YYYY-MM-DD` at line start is a scheduling token in the shared block grammar.**
  `> 2026-10-04` stays a quote.
- **The budget is thread CPU time, minimum of K runs.** The ceiling is set from measurement at a
  gate, and wall time is printed only.
- **Renumbering rewrites only the edited ordered run, in the keystroke's undo step.** The pinned
  caret moves from 49 to 48. The card keeps the whole-text path.
- **Grow-to-fit lays out the caret's fragment plus the viewport.** The 1 MB hand check is the
  acceptance, and the fallbacks are chosen at the gate. **Withdrawn 2026-10-10** (ADR-0082 §D7
  amended): the G-grow hand check showed a click after Cmd+Down jumps and selects the whole
  note, so grow-to-fit lays out the whole document again.
- **`_` emphasis stays unconcealed.**
- **Oggi and Diario share one query-source factory.** Cards gain quote and rule concealment;
  tables and view blocks stay out of cards.
- **No GUI test.**

## What reading the current tree added (`9103768f`)

1. **ADR-0081 to ADR-0088 are already on `main` as `proposed`** (`f697b363`).
   `docs/plans/note-workflow-n2-mockup.md` still says the ADR "lands with the code PR, so `main`
   never carries a `proposed` record"; that is stale. Since PG-340, a PR is judged only on the
   ADRs it touches. The mockup PR therefore touches no ADR. The code PR edits both, and
   `adr-references.yml` reports them as "flip it to accepted". That finding is advisory, it is
   expected, and the post-merge flip clears it.
2. **A revealed list item carries no list style at all today.**
   `EditorDecorationDelegate+ListRendering.swift:26` returns `nil` before any style is built.
   ADR-0081 §D2 therefore *adds* a style to the revealed paragraph; it does not share one.
   `bodyParagraphStyle(of:)` (`:95`) is `private` to that file, and the quote and heading
   branches need it.
3. **There is no heading branch in the substitution hook.** `textContentStorage(_:textParagraphWith:)`
   at `EditorDecorationDelegate.swift:471` has these branches:
   - embed `:483`;
   - list `:494`;
   - checkbox `:503`;
   - quote `:512`;
   - table `:522`;
   - view block `:533`;
   - generic `:542-590`.

   A revealed heading falls to the generic path and returns `nil`. The file is 892 lines, so the
   new branch goes in its own file. Each branch has the shape
   `func …Paragraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph?`
   (`+ListRendering.swift:25`, `+QuoteRendering.swift:20`).
4. **The card's `hiddenKind` switch has seven arms** (`CardTextView.swift:368-383`).
   `InlineSpanRevealFenceTests.swift:323-354` counts them and expects exactly 7. Adding quote and
   rule moves it to 9, so this pinned assertion changes. The older plan said it must stay green;
   it cannot.
5. **Two more tests change meaning under ADR-0081.**
   - `MarkupHidingListTests.swift:185` (`theHookReturnsNilForARevealedListParagraph`) and
     `CardConcealmentTests.swift:187` both expect `nil` for a revealed list paragraph. Lists now
     hang in the card too (ADR-0081 §D6).
   - `ReadableWidthTests.swift:78-86` asserts `textContainerInset.width == (W − cap) / 2`. The
     inset now shrinks by G.
6. **A real keystroke runs the pipeline at least twice.**
   - `textDidChange` (`NoteTextView+Coordinator.swift:188-222`) runs `applyStyling :191`,
     embeds `:192`, transclusions `:193`, `renumberLists :198`, `applyReveal :201` and
     `growToFitTheText :209`.
   - The SwiftUI update that the binding write triggers then runs `runPasses`
     (`NoteTextView+Update.swift:55-71`): styling, embeds, transclusions, folding, matches,
     reveal and `growToFitTheText :71`, unconditionally.
   - A renumbering keystroke re-enters `textDidChange` a third time, through `replaceAtomically`'s
     `didChangeText()` (`NoteTextView+EmbedCaret.swift:101-113`).

   ADR-0082 §D5 measures only the first pass.
7. **The pinned caret test calls `renumberLists(in:)` directly** (`NoteListEditingTests.swift:275`).
   Since the SPEC keeps the whole-text form as the fallback "when no edited range is known", the
   48 is reached only through an edited range. No coordinator implements
   `textView(_:shouldChangeTextInRanges:replacementStrings:)` today, and both `insertText` and
   `replaceAtomically` pass through it.
8. **`EditorHeightTests` builds its editor without `textView.delegate`** (`:30-56`). Both tests
   that change call `ensureLayout(for: documentRange)` themselves after the keystroke (`:71`,
   `:86`). That call is the very thing R-17 removes from the app.
9. **Oggi and Diario pass no `queries`**: `TodayView.swift:216`/`:233`, `DiaryView.swift:110`/`:122`.
   Neither pane can be hosted in a test: each needs `CommandActions`, and through it
   `EventKitStore`, which is the limit recorded in `HostedViewPrototypeTests.swift:9-13` and
   ADR-0053. These doc comments state the old fact and become false:
   - `NoteTextView+Inputs.swift:83-86`;
   - `EditorColumn+Text.swift:244-247`;
   - `ViewBlockQuerySourceTests.swift:354-358`, `:382-391`;
   - `NoteTextView+Coordinator.swift:396-400`;
   - `CardTextAttributes.swift:222-232`.
10. **A card has no line-height multiple.** `CardTextAttributes.base` sets no `.paragraphStyle`
    (`:52-53`, ADR-0030 §D10). The only card paragraph style is the alignment one
    (`CardTextView+Styling.swift:130-133`). The SPEC edge case "keeps its line-height multiple"
    is read under G0 item 4.
11. **The styler and the block parser disagree beyond `>date`.**
    - Line splitting: `LineBreak.isTerminator` in the styler (`:208`), `Character.isNewline` in
      the parser (`MarkdownBlocks.swift:86`).
    - Trimming: spaces only in the styler, all whitespace in the parser.
    - Ordered digits: ASCII only in the styler, `isNumber` in the parser.
    - Frontmatter: the styler reads it (`NoteFrontmatter.range`, `:119`). The parser never does,
      since its callers pass a body.
    - Overlapping spans: the styler documents "later spans win where they overlap"
      (`MarkdownStyler.swift:113-115`). A sorted corpus cannot see a precedence change.
12. **`blocks(in:)` and `spans(in:)` have consumers beyond the exporter:**
    - `MarkdownHTML.swift:20`, `:26`;
    - `NoteOutline.swift:93`;
    - `ViewBlock.swift:267` (Core, connectors, code blocks only);
    - `MarkdownBlocksView.swift:230`;
    - `MarkdownReadingView.swift:59`;
    - `TranscludedNoteView.swift:106`;
    - `PraticaEntryRow.swift:113`;
    - `PraticaMessageRow.swift:191`;
    - `PratichePane+Inspector.swift:68`.
13. **Edge fixture.** `TagDateClickTargetTests.swift:307` holds `">2026-02-31"`, an invalid date
    at line start. It stays a quote under the shared rule, which keeps the `CalendarDate(iso:)`
    test of `MarkdownStyler.swift:630`.
14. **Ten test files call `MarkdownStyler.spans`, not nine:**
    - `ListNestingForwardPassTests`;
    - `ListNestingTests`;
    - `MarkdownAttributedTextTests`;
    - `MarkdownStylerBlockTests`;
    - `MarkdownStylerFixture`;
    - `MarkdownStylerTests`;
    - `ProseParagraphSpacingTests` (N1);
    - `SpellCheckTests`;
    - `ViewBlockSpanTests`;
    - `ViewQueryOutOfScopeTests`.
15. **Composition.** N1's `ProseParagraphSpacing.merge` (`:63-73`) and the transclusion height
    (`NoteTextView+Transclusion.swift:167-171`) both copy the existing paragraph style before
    changing it, so the gutter's indents survive them. `TranscludedRendition.gutter` (16 pt,
    `TranscludedLineFragment.swift:25`) is an unrelated band inside the transcluded picture; do
    not confuse the two names.
16. **None of N2's files exist yet:** no `StylerGolden*`, `EditorRestyleBudgetTests`,
    `scripts/editor-restyle-bench.sh`, `GutterRevealMockup` or `MockupGalleryView.Screen.gutter`.
    The PG-219 branches (`docs/spec-pg-219-cursor-feedback`, `docs/discovery-pg-219-pointer`)
    hold no `Sources/` change against the base.
17. **`growToFitTheText` has three callers:** `:209`, `:384` (the view-block height callback) and
    `NoteTextView+Update.swift:71`. The only whole-document `ensureLayout` in `Sources/` is
    `:532`.

## ADR corrections (applied by Task 8, in the code PR)

Line numbers below were read on `9103768f`.

**ADR-0081:**

1. **Head.** Add a dated line: "Re-read on `9103768f` (2026-10-06), after N1 (#897, #905); line
   numbers corrected there". Replace the plan paths with `docs/plans/pg-385-n2-page.md` and keep
   the mockup plan.
2. **Context, line cites.**
   - `NoteTextView+Coordinator.swift:627` becomes `:616`.
   - `ListMarkerRendering.swift` `:85-88` becomes `:85-89`.
   - `EmbedResize.swift:62` becomes `:64`.
   - `CardTextView.swift:138-139` becomes `:142-143` (the delegate is built at `:213`).
   - Alternatives `:509-532` and References `:541-631` become `:498-541` and `:530-631`.
3. **Context ¶1 and §D2.** A revealed list paragraph carries no style today (`+ListRendering.swift:26`
   returns `nil` first), so §D2 adds one. The style takes the page's `proseFont`, pushed at
   `NoteTextView+Coordinator.swift:344`, and composes on `bodyParagraphStyle(of:)`, which is
   shared with the quote and heading branches.
4. **§D4.** No heading branch exists today: the hook's branches are as in finding 3, and a
   revealed heading returns `nil` from the generic path. The branch lives in
   `EditorDecorationDelegate+HeadingRendering.swift` because the delegate file is 892 lines.
5. **§D1.** The base style composes with N1's `spacing.paragraph` (`ProseParagraphSpacing.merge`
   copies the style, so the indents survive) and with N1's H5/H6 faces. The initial inset is at
   `NoteTextView.swift:107`. Name `TranscludedRendition.gutter` as an unrelated constant.
6. **§D7.** The transcluded picture starts at the column's leading offset. Its own 16 pt band
   follows that offset.
7. **Consequences.** Add the restated tests: `MarkupHidingListTests:185`,
   `CardConcealmentTests:187` and `ReadableWidthTests:78-86`, each with its reason.
8. **Implementation notes.** Record the gate answers (G1, G2, G3) and the file names actually
   used.

**ADR-0082:**

1. **Head.** Add the same dated re-read line and the plan path.
2. **Context, line cites.**
   - `:303` becomes `:284`.
   - `CardTextAttributes.swift:99` becomes `:100`.
   - "nine test files" becomes ten (finding 14).
   - `:541-552` becomes `:530-541`.
   - `delimiterSpan` `:351-364` becomes `:359`.
   - The `growToFitTheText` header `:509-540` becomes `:498-529`.
   - `TodayView.swift:211` becomes `:216`.
   - `DiaryView.swift:105` becomes `:110`.
   - `EditorColumn+Text.swift:244` becomes `:248`.
   - `CardTextView.swift:359-375` becomes `:368-383`.
   - References `:188-209, 509-552` become `:188-222, 498-541`.
   - `blockquoteMarkerLength` `:630` stays: it is the date rule's line.
3. **§D1.**
   - `lineTokens` reads frontmatter only when asked (`readsFrontmatter:`), because the block
     projection is given a body and reads a leading `---` as a rule.
   - The projection keeps the parser's line split and trimming.
   - `embedRun(inLine:)` stays app-side (`EmbedRun.swift`) and the mapping calls it.
   - If the file passes 400 lines, it is split by parser; the implementation notes name the
     files.
4. **§D3.**
   - The styler corpus has its own type, because the export corpus's `Kind` gives `b` and `c`
     other meanings (`NoteExportGoldenCorpus.swift:18-28`).
   - A `captured` output is never edited.
   - The canonical form also records the emission order of overlapping spans (if G0 item 1 is
     confirmed).
5. **§D4 and Neutral.** The `>date` reading reaches every `blocks(in:)` consumer in finding 12,
   not only the exporter. `ViewBlock.blocks` reads code blocks only and is unaffected.
6. **§D5.** Name the `runPasses` re-pass and the renumber re-entry (finding 6) as outside the
   measurement. A keystroke in the app costs about two pipelines. This is proposed as a ledger
   entry, not fixed in N2.
7. **§D6.**
   - The edited range is recorded from `textView(_:shouldChangeTextInRanges:replacementStrings:)`
     and handed to `renumberLists(in:touching:)`.
   - The fallback keeps today's clamped caret (49).
   - `mapping(_:)` is exact per rewritten digit run.
8. **§D7** (withdrawn 2026-10-10, see above). The two other callers (`:384`, `NoteTextView+Update.swift:71`) take the same scoped
   path. Add the restatement wording of Task 2.
9. **§D8.**
   - `InlineSpanRevealFenceTests` moves from 7 to 9 and joins G-caret.
   - Replace "the card's line-height multiple survives" with "the card's own paragraph style
     (its alignment) survives, and a card gains no page line height (ADR-0030 §D10)". With
     gutter 0 the quote branch sets no style in a card (ADR-0081 §D6).
   - List the doc comments corrected (finding 9).
10. **§D9.** "Before" is filled by Task 1 of this plan (not Task 2); "After" and "Ceiling" are
    filled by Task 8. Name the Mac model and the macOS build.
11. **Gates, G-caret.** Add `InlineSpanRevealFenceTests` 7 to 9.

## Interpretations to confirm at GATE 1 (G0)

Each item is this plan's reading of a SPEC or ADR sentence. A correction here changes a test, not
the design.

1. **The corpus records overlap order.** Its canonical text is one line per span, as
   `start..<end span` in UTF-16 offsets, sorted. After the spans come the hidden-marker kinds,
   then one `order a < b` line per pair of overlapping spans, in emission order. Later spans win
   where they overlap, so a sorted list alone cannot see a precedence regression. This goes
   beyond ADR-0082 §D3's "sorted". I recommend it; it costs one line per overlap.
2. **Corpus inputs.** The export corpus inputs are referenced by name from
   `NoteExportGoldenCorpus.bodies` and `NoteExportGoldenPages.all`, never copied. A guard test
   fails when an export case has no styler case.
3. **The caret pin, three tests.** The restated test drives `renumberLists(in:touching:)` with
   the edited range and lands on 48. A new sibling pins the fallback, with no range, at today's
   49. A third test proves the keystroke path records the range.
4. **"Keeps its line-height multiple" (SPEC edge case) means the card keeps its own paragraph
   style**: an aligned card stays aligned, and a concealed quote adds no page line height.
5. **Oggi and Diario parity is proven by:**
   - a hosted `NoteTextView` given `ViewQuerySource.live(for:)` over a temporary vault;
   - a source guard on `TodayView.swift`/`DiaryView.swift` (the `InlineSpanRevealFenceTests`
     shape).

   It is not proven by hosting the panes (finding 9).
6. **The budget measures `textDidChange` only**, as ADR-0082 §D5 says. The `runPasses` re-pass is
   named and proposed as a follow-up, not measured. Doubling the measured scope would change the
   six-line contract.
7. **Scoped renumbering leaves another misnumbered run alone** until that run is edited. This
   follows from R-16's "only the edited ordered run", and a test pins it.
8. **Widths for R-14.**
   - Narrow is 600 pt (below 768, readable width on).
   - Readable is 1200 pt (above 816 at G = 48).
   - Readable width off at 1200 pt is checked as well.
9. **`Theme.emergency` carries the gutter at the G1 value**, as `spacing.paragraph` does
   (PG-225). Every hosted test that styles with `.emergency` therefore draws the gutter. Tests
   that read positions from layout are unaffected; the one that asserts the inset is restated.
10. **A heading with no title** (`#`, `######`) hangs its run when revealed and draws nothing
    when concealed. It is pinned by "no trap, hanging indent set", not by a content origin.

## Standing rules for every task

1. **Run TEST-CMD before Task 1 to set the baseline, and after every task.** Always run the whole
   `PergamenumTests` target. This chain changes the styler's output, the block grammar, the
   container inset and three delegate branches, and each of those reaches tests in unrelated
   suites.
2. **Run `tuist generate --no-open` after any task that adds a file** (Tasks 1, 2, 4, 5, 6, 7).
   New `Sources/Core/**` files reach `perg` and `pergamenum-mcp` through the glob
   (`Project.swift:88`). Every other new file is app-only, so `Project.swift` is not edited.
3. **A stale test changes only after its reason is said in chat** (global rule). The expected ones
   are listed under "Observable contracts changed". Any other red is a finding to report, not a
   test to edit. A styler difference is classed in the corpus first; a C is never re-captured.
4. **Label every new or rewritten test with this SPEC's pin**, for example `// (n2-page R-16)`.
5. **`Sources/Core/**` stays Foundation-only.** After Tasks 3 and 4, build `perg` and
   `pergamenum-mcp`.
6. **Tokens only.** No colour, font or spacing literal in a view. The gutter is a token, and the
   quote step and the marker face come from the G1 answers, not from literals in views.
7. **SwiftLint: no new violation in a touched file.** Read the per-file output. Watch these:
   - `EditorDecorationDelegate.swift` (892 lines): new branches go in their own files;
   - `MarkdownStyler.swift` (776 lines): it shrinks;
   - `NoteTextView+Coordinator.swift` (623 lines);
   - the new token file, under 400 lines or split.
8. **Stale DerivedData.** A launch crash in `initializeWithCopy` after a `some View` change
   (TodayView, DiaryView) is the CLAUDE.md stale-build rule, not a defect.
9. **Hosted geometry tests ensure layout for the range they measure first.** `firstRect` returns
   a zero rectangle for a range TextKit 2 has not laid out (CLAUDE.md), and a zero rectangle can
   pass an assertion by accident.

## Session B — baseline, grammar, keystroke, surfaces (code PR, first half)

### Task 1 — Tester: capture the styler corpus and the budget's "before" on untouched code (R-15, R-18)
Owner: tester
Files: Tests/StylerGoldenCorpus.swift, Tests/StylerGoldenTests.swift, Tests/ScrolledEditorFixture.swift, Tests/RestyleBudgetSupport.swift, Tests/EditorRestyleBudgetTests.swift, scripts/editor-restyle-bench.sh, docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md
Tests: StylerGoldenTests.swift, EditorRestyleBudgetTests.swift, NoteExportGoldenTests.swift
Signatures:
- StylerGoldenCase — struct StylerGoldenCase: Sendable, CustomStringConvertible { let name: String; let markdown: String; let captured: String; let change: Change }
- StylerGoldenCase.Change — enum Change: Sendable { case unchanged; case fix(reason: String, expected: String); case deliberate(reason: String, expected: String) }
- StylerGoldenCorpus.cases — static let cases: [StylerGoldenCase]
- StylerGoldenCorpus.canonical — static func canonical(_ text: String) -> String
- ScrolledEditorFixture — @MainActor struct ScrolledEditorFixture { let textView: CompletingTextView; let coordinator: NoteTextView.Coordinator; let scrollView: NSScrollView; let window: NSWindow }
- ScrolledEditorFixture.init — init(text: String, width: CGFloat = 900, height: CGFloat = 700, hidesMarkup: Bool = true, readableWidth: Bool = true, theme: Theme = .emergency)
- ScrolledEditorFixture.type — func type(_ string: String, at location: Int)
- RestyleBudget.Variant — enum Variant: String, Sendable, CaseIterable { case prose, fences }
- RestyleBudget.Case — struct Case: Hashable, Sendable, CustomStringConvertible { let bytes: Int; let variant: Variant }
- RestyleBudget.syntheticNote — static func syntheticNote(bytes: Int, variant: Variant) -> String
- RestyleBudget.threadCPUNanoseconds — static func threadCPUNanoseconds() -> UInt64
- RestyleBudget.minimum — static func minimum(runs: Int, _ body: () -> Void) -> (cpuMs: Double, wallMs: Double)
- RestyleBudget.provisionalCeiling — static func provisionalCeiling(before ms: Double, factor: Double = 3) -> Double
- RestyleBudget.ceilings — static let ceilings: [Case: Double]
- RestyleBudget.line — static func line(_ c: Case, cpuMs: Double, wallMs: Double, runs: Int) -> String
- NoteExportGoldenCorpus.bodies — static let bodies: [ExportGoldenCase] (relied on)
- NoteExportGoldenPages.all — static let all: [ExportGoldenCase] (relied on)
Red: no

This task runs before any line of `Sources/` changes. It is the "captured, never written by hand"
step of ADR-0082 §D3 and the "before" step of §D5.

**The styler corpus** (`StylerGoldenCorpus.swift`, plus `StylerGoldenTests.swift`).

- Its own type: `NoteExportGoldenCorpus`'s `Kind` gives `b`/`c` other meanings.
- `canonical(_:)` is the form G0 item 1 settles: span lines, then hidden-kind lines through
  `NoteTextView.Coordinator.hiddenKind(for:)`, then overlap-order lines.
- **Inputs:**
  - every case of `NoteExportGoldenCorpus.bodies` and `NoteExportGoldenPages.all`, referenced by
    name;
  - ADR-0082 §D3's editor constructs;
  - `file_name_here`, `2 * 3 * 4`, `nome_file_lungo`;
  - `>2026-10-04 riunione`, `> 2026-10-04`, `>2026-02-31`;
  - a CRLF note and a note with a U+2028 separator;
  - a tab-indented list, `12) `, and a fullwidth-digit ordered marker;
  - a leading `---` block in a body.
- **Capture.** A test gated on `TEST_RUNNER_STYLER_GOLDEN_CAPTURE=1` prints each case as a Swift
  literal, and the tester pastes the output into the corpus. The helper stays in the file so N5
  can reuse it.
- **`StylerGoldenTests`:**
  - every case's current output equals `captured`; once Task 3 has classed a case, it equals that
    case's `expected` instead;
  - every export case has a styler case;
  - every `fix`/`deliberate` carries a non-empty reason.
- All of it is green on untouched code by construction.

**The fixture** (`ScrolledEditorFixture.swift`). It is shared by the budget, grow-to-fit and
gutter tests:

- a `NoteTextView` coordinator, a `CompletingTextView(usingTextLayoutManager: true)` in an
  `NSScrollView`, in an off-screen `NSWindow`;
- `textView.delegate = coordinator`, `coordinator.textView = textView`, and both decoration
  delegates wired as `NoteTextView.swift` wires them;
- `applyReadableWidth` and one `applyStyling` at build time.

`type(_:at:)` sets the selection and calls `insertText(_:replacementRange:)`, so
`shouldChangeText` and `textDidChange` run as they do for a key. It mirrors `EditorHeightTests`'
window shape, adding the delegate.

**The budget** (`RestyleBudgetSupport.swift`, `EditorRestyleBudgetTests.swift`), per ADR-0082 §D5.

- `syntheticNote` is deterministic (no RNG). The variants are:
  - prose: headings, emphasis, links, tags, both dates, nested lists, tasks and quotes;
  - fences: the same plus a code fence every ~40 lines and a `pergamenum-view` fence every ~200,
    with no query source.

  Its UTF-8 size is within 1% of the target, and that is asserted.
- `threadCPUNanoseconds` reads `clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)`.
- `minimum` runs one warm-up and then takes the minimum of K runs: K is 5 at 50 KB and 200 KB,
  3 at 1 MB.
- One keystroke is `type("x", at: middle)`.
- The suite is `.serialized` and prints the six lines plus its own total wall time.
- It asserts `cpuMs <= ceilings[case]`.
- **Ceilings.** Provisional ceilings are `provisionalCeiling(before:)`: 3× rounded up to a whole
  ms, written as literals after the first measured run.
- **Pure tests (seam 1):** `provisionalCeiling` arithmetic, `line` format, and synthetic size and
  determinism.

**The bench** (`scripts/editor-restyle-bench.sh`).

- Bash 3.2: no `mapfile`, no associative arrays.
- It runs `xcodebuild … -only-testing:PergamenumTests/EditorRestyleBudgetTests test`, greps the
  `restyle-budget` lines and prints them as a table. It exits with xcodebuild's status.
- Before relying on it, verify that Swift Testing suite selection by `-only-testing:` and the
  test's stdout both reach the log.

**Report and record.**

- Fill ADR-0082 §D9's "Before" column with the measured numbers.
- Report the suite's added wall time in chat. ADR-0082 already lets G-ceiling move the 1 MB rows
  out of the per-turn suite if it is too slow.

### Task 2 — Tester: the token layer, the scoped renumber, scoped grow-to-fit and surface parity, red (R-16, R-17, R-18, R-19)
Owner: tester
Files: Sources/Core/Markdown/MarkdownTokens.swift, Sources/Core/Editor/ListContinuation.swift, Sources/Features/Editor/NoteTextView+ListEditing.swift, Sources/Features/Editor/ViewQuerySource+Live.swift, Tests/MarkdownLineTokenTests.swift, Tests/MarkdownInlineTokenTests.swift, Tests/MarkdownProjectionTests.swift, Tests/StylerSharedGrammarTests.swift, Tests/NoteExportGoldenCorpus.swift, Tests/ListRenumberScopeTests.swift, Tests/NoteListEditingTests.swift, Tests/EditorGrowToFitScopeTests.swift, Tests/EditorHeightTests.swift, Tests/DailySurfaceQueriesTests.swift, Tests/CardBlockMarkerTests.swift, Tests/InlineSpanRevealFenceTests.swift, Tests/ViewBlockQuerySourceTests.swift
Tests: MarkdownLineTokenTests.swift, MarkdownInlineTokenTests.swift, MarkdownProjectionTests.swift, StylerSharedGrammarTests.swift, NoteExportGoldenTests.swift, ListRenumberScopeTests.swift, NoteListEditingTests.swift, EditorGrowToFitScopeTests.swift, EditorHeightTests.swift, DailySurfaceQueriesTests.swift, CardBlockMarkerTests.swift, InlineSpanRevealFenceTests.swift, ListContinuationTests.swift, CardFormattingTests.swift
Signatures:
- MarkdownLineToken — struct MarkdownLineToken: Equatable, Sendable { let range: Range<String.Index>; let kind: Kind }
- MarkdownLineToken.Kind — enum Kind: Equatable, Sendable { case blank, paragraph, frontmatter, rule, messageAnchor, tableRow, fenceBody, fenceClose; case fenceOpen(language: String?); case heading(level: Int, marker: Range<String.Index>); case listItem(ordered: Bool, indentation: Range<String.Index>, marker: Range<String.Index>, level: Int); case task(state: TaskItem.State, marker: Range<String.Index>); case quote(level: Int, marker: Range<String.Index>) }
- MarkdownInlineToken — struct MarkdownInlineToken: Equatable, Sendable { let range: Range<String.Index>; let kind: Kind }
- MarkdownInlineToken.Kind — enum Kind: Equatable, Sendable { case code(delimiters: [Range<String.Index>]); case strong(delimiters: [Range<String.Index>]); case emphasis(delimiters: [Range<String.Index>]); case strikethrough(delimiters: [Range<String.Index>]); case wikilink(target: String, syntax: [Range<String.Index>]); case link(url: String, syntax: [Range<String.Index>]); case embed(target: String, syntax: [Range<String.Index>]); case tag(String); case scheduled; case due; case annotation }
- MarkdownBlockParser.lineTokens — static func lineTokens(in text: String, readsFrontmatter: Bool = false) -> [MarkdownLineToken]
- MarkdownInlineParser.tokens — static func tokens(in text: Substring) -> [MarkdownInlineToken]
- ListContinuation.Renumbering — struct Renumbering: Equatable, Sendable { let range: NSRange; let replacement: String; func mapping(_ location: Int) -> Int }
- ListContinuation.renumbered(_:touching:) — static func renumbered(_ text: String, touching edited: NSRange) -> Renumbering?
- ListContinuation.renumbered(_:) — static func renumbered(_ text: String) -> String? (relied on, unchanged)
- NoteTextView.Coordinator.renumberLists(in:touching:) — func renumberLists(in textView: NSTextView, touching edited: NSRange?)
- NoteTextView.Coordinator.renumberLists(in:) — func renumberLists(in textView: NSTextView) (relied on, the fallback)
- ViewQuerySource.live — @MainActor static func live(for vault: VaultController) -> ViewQuerySource
- CardTextView.Coordinator.hiddenKind — static func hiddenKind(for styled: MarkdownStyler.StyledRange) -> HiddenMarker.Kind? (relied on)
Red: yes

**Stubs.** The tester declares every symbol above with a body that compiles and keeps today's
behaviour, so the target builds and the new tests fail on assertions, never on a trap:

- `lineTokens` and `tokens` return `[]`;
- `renumbered(_:touching:)` returns `nil`;
- `Renumbering.mapping` returns its argument;
- `renumberLists(in:touching:)` calls `renumberLists(in:)`;
- `live(for:)` returns `ViewQuerySource(evaluate: { _ in ViewResult(groups: [], total: 0) },
  generation: 0)`.

**File placement.**

- `MarkdownTokens.swift` imports Foundation only. `tokens(in:)` takes a `Substring` so its ranges
  are valid in the whole note: a substring shares its base string's indices.
- `ViewQuerySource+Live.swift` sits in `Sources/Features/Editor/`, beside `EditorColumn+Text.swift`,
  whose body it takes over. `ViewQuerySource.swift` itself lives in `Sources/Features/Views/` and
  stays vault-free: its header says the renderer has no vault and must not grow one.

**`MarkdownLineTokenTests.swift`** (R-18):

- headings H1 to H6, with the marker range `###### ` and a heading with no title;
- `-`, `*`, `+` bullets and `1.`, `10.`, `12)` ordered items, with the indentation run (spaces
  and tabs) and the `ListNesting` level;
- every `TaskItem.State`;
- quotes `>` and `> >` with their level;
- the date rule: `>2026-10-04 x` is `.paragraph`, `> 2026-10-04` is `.quote`, and
  `>2026-02-31` is `.quote`;
- a rule;
- a fence's open, body and close, including `pergamenum-view`;
- table rows;
- a message anchor;
- frontmatter only when `readsFrontmatter: true`;
- CRLF line ranges that exclude the terminator.

**`MarkdownInlineTokenTests.swift`** (R-18):

- code before wikilink before link before emphasis;
- a link label carrying emphasis;
- strong and emphasis with their delimiter ranges;
- `file_name_here`, `2 * 3 * 4` and `nome_file_lungo` produce no emphasis, while `_a_` does;
- strikethrough;
- `#tag`, `>date`, `!date` and `@annotation` as tokens;
- every range indexes the base string of a mid-note `Substring`.

**`MarkdownProjectionTests.swift`** (R-18, green guards plus two red cases):

- **Guards, green now and after.**
  - `blocks(in:)` of a body that opens with `---\nx\n---` is unchanged.
  - The inline projection still emits `#tag`, `>date`, `!date` and `@annotation` as plain text,
    merged with their neighbours, byte-identical to today. Capture today's values in the test.
- **Red.** `blocks(in: ">2026-10-04 riunione")` is a paragraph, not a quote.

**`NoteExportGoldenCorpus.swift`**:

- E46 `>2026-10-04 riunione`, class `.a`, expected the paragraph rendering;
- E47 `> 2026-10-04 riunione`, `.unchanged`.

This is ADR-0082 §D4's one export change. E46 is red until Task 3.

**`StylerSharedGrammarTests.swift`** (R-18, red until Task 3). `file_name_here` and `2 * 3 * 4`
carry no `.italic`/`.emphasisMarker` span in `MarkdownStyler.spans`, and `MarkdownHTML.render`
holds no `<em>` for either. `nome_file_lungo` is plain. `_a_` is italic, and its `_` keeps no
`.emphasisMarker` kind that `hiddenKind` would conceal (G0: `_` stays unconcealed).

**`ListRenumberScopeTests.swift`** (R-16, pure, red):

- only the run that touches the edited range is rewritten, while a misnumbered run elsewhere is
  left alone (G0 item 7);
- a deleted separator that merges two runs is seen (the one-line widening);
- a fenced "list" is ignored;
- `nil` when nothing changes;
- applying the `Renumbering` to the text equals `renumbered(_:)` whenever the edited run is the
  only one misnumbered;
- `mapping` is exact per digit run: a location after a shrunk `10.` moves back one, a location
  between two rewritten runs moves by the first run's delta only, and a location inside a
  rewritten run stays inside it.

**`NoteListEditingTests.swift`** (R-16). State the reason in chat first. The SPEC decides the
49 to 48 move, and the test's own comment (`:249-251`) asks for that move to be deliberate.

- `renumberListsAfterARunsTrailingItemShrinksLeavesTheCaretOneCharacterAhead` (`:262-285`) is
  restated as `renumberingTheEditedRunMapsTheCaretThroughTheShrink`. It uses the same text and
  caret, calls `renumberLists(in:touching: NSRange(location: 40, length: 0))`, and expects the
  text to equal `renumbered(text)` and the caret to be 48.
- New: `withNoEditedRangeTheWholeTextFallbackKeepsTheCaretClamped`. It calls `renumberLists(in:)`
  and expects caret 49: the documented fallback for an undo or a programmatic replacement.
- New: `aRealDeleteRenumbersThroughTheRecordedRangeInOneUndoStep`. A correctly numbered
  ten-item list, then a real delete of `"9. i\n"` through `insertText("", replacementRange:)`
  with the delegate wired. Expect the renumbered text, the caret at 48, and one `undo()`
  restoring the pre-delete text.
- `deletingAMiddleItemOfAnOrderedRunRenumbersTheRestAndOneUndoRestoresBoth` (`:224`) stays
  untouched and green. So do `CardFormattingTests.swift:464` and `:507-522`, and
  `ListContinuationTests.swift:152-197`.

**`EditorGrowToFitScopeTests.swift`** (R-17, hosted through `ScrolledEditorFixture`, a note of
about 2,000 lines):

- After one keystroke at the top, the end's layout fragment has not reached `.layoutAvailable`.
  This is red today.
- Typing at the end and typing in the middle each leave the caret rect inside `visibleRect`.
- After a keystroke at the top, `moveToEndOfDocument(nil)` and
  `textViewportLayoutController.layoutViewport()` put the last line's fragment `maxY` at or
  below `textView.frame.height`.
- Never `layoutSubtreeIfNeeded` (the header's own warning).

**`EditorHeightTests.swift`** (R-17). State the reason in chat first: ADR-0082 §D7 removes the
whole-document layout these two tests rely on.

- `stylingLeavesTheTextViewTallEnoughForWhatItDraws` (`:64-76`) and
  `theLastLineOfANoteIsInsideTheScrollableArea` (`:78-97`) drop the test-side
  `ensureLayout(for: documentRange)` (`:71`, `:86`).
- After the keystroke, each brings the end into view the app's way: `moveToEndOfDocument(nil)`,
  then `layoutViewport()`.
- Each then asserts its own property:
  - the first: `frame.height >= usageBoundsForTextContainer.height + 2 × verticalInset`, as TextKit
    reports it at that moment;
  - the second: the last line's fragment `maxY <= frame.height`.
- The private fixture gains `textView.delegate = coordinator`.
- `typingAtTheEndOfANoteBringsTheCaretIntoView` (`:100`) is unchanged.

**`DailySurfaceQueriesTests.swift`** (R-19). This test is red until Task 4.

- A `TemporaryVault` holding a note `Note/N.md`, opened through
  `VaultController(recents: .volatile(), openTabs: .volatile())`.
- `ViewQuerySource.live(for:)`'s `generation` equals `EditorColumnView.viewQueryGeneration(for:)`.
  Its `evaluate` of `render: list` returns the note's row, and `move` and `undo` are non-nil.
- A hosted `NoteTextView` given it (the `ViewBlockQuerySourceTests.editor` shape) forms a host
  whose query source is non-nil.
- A source guard reads `TodayView.swift` and `DiaryView.swift` through `resolvedRepoRoot()`. Each
  passes `queries: .live(for: vault)`, and neither mentions `onEditQuery`.

**`CardBlockMarkerTests.swift`** (R-19, red until Task 4, the `CardConcealmentTests` card
fixture):

- a quote paragraph at rest is substituted (bars), and a rule's fragment is a
  `HorizontalRuleFragment`;
- an aligned card's concealed quote keeps `.alignment` and carries no `lineHeightMultiple`
  (G0 item 4);
- a table and a view block are still not concealed (`default: nil`);
- a message anchor is still not concealed in a card.

**`InlineSpanRevealFenceTests.swift`** (R-19). State the reason in chat first: R-19 adds two
mapped kinds to the card.

- `CardTextViewHiddenKindSwitchMapsExactlySevenKinds` (`:323-354`) becomes `…ExactlyNineKinds`
  and expects 9, with a message naming quote and rule.
- The opener string it searches stays byte-identical in `CardTextView.swift`.

**`ViewBlockQuerySourceTests.swift`.** Doc comments only, at `:354-358` and `:382-391`: they stop
saying that Diario and Oggi never pass `queries`. The tests themselves stay green, since
`NoteTextView`'s default is still `nil`.

### Task 3 — Coder: one grammar: the token layer, the projections, the styler mapping, the corpus classes (R-18, R-45)
Owner: coder
Files: Sources/Core/Markdown/MarkdownTokens.swift, Sources/Core/Markdown/MarkdownBlocks.swift, Sources/Core/Markdown/MarkdownInline.swift, Sources/Features/Editor/MarkdownStyler.swift, Tests/StylerGoldenCorpus.swift
Tests: MarkdownLineTokenTests.swift, MarkdownInlineTokenTests.swift, MarkdownProjectionTests.swift, StylerSharedGrammarTests.swift, StylerGoldenTests.swift, NoteExportGoldenTests.swift, MarkdownStylerTests.swift, MarkdownStylerBlockTests.swift, MarkdownParserCorrectionTests.swift, MarkdownReadingTests.swift, NoteOutlineTests.swift, TransclusionTests.swift, GFMTableTests.swift, TagDateClickTargetTests.swift
Signatures:
- MarkdownBlockParser.lineTokens — static func lineTokens(in text: String, readsFrontmatter: Bool = false) -> [MarkdownLineToken]
- MarkdownInlineParser.tokens — static func tokens(in text: Substring) -> [MarkdownInlineToken]
- MarkdownBlockParser.blocks — static func blocks(in body: String) -> [MarkdownBlock] (unchanged signature, now a projection)
- MarkdownInlineParser.spans — static func spans(in text: String) -> [MarkdownSpan] (unchanged signature, now a projection)
- MarkdownStyler.spans — static func spans(in text: String) -> [StyledRange] (unchanged signature and Span cases)
- embedRun — func embedRun(inLine line: String) -> Range<String.Index>? (relied on, stays app-side)
Red: no

**`lineTokens`** follows ADR-0082 §D1. It is built on these Core types, and adds no second
recogniser for anything they already answer:

- `ListNesting.levels(in:)`;
- `TaskParser.state(for:)`;
- `CodeFence.marks`/`language(declaredBy:)`;
- `GFMTable`;
- `PraticaEntryAnchor`;
- `ViewBlock.language`;
- `NoteFrontmatter.range`, under `readsFrontmatter`.

**The `>date` rule** is moved from the styler, not restated: one `>`, then a valid
`CalendarDate(iso:)`, makes a paragraph. The token layer keeps the parser's line split
(`Character.isNewline`), its whitespace trimming and its digit test. Where the styler differed,
the corpus classes it.

**`tokens(in:)`** is the existing inline scanner. Its rules are unchanged (match order, flanking,
`opensEmphasis`, `closingRange`); it reports ranges, and it adds the app's conventions as tokens.

**`spans(in:)` and `blocks(in:)` become projections**, the latter as the existing `Accumulator`
fed by `lineTokens(in: body, readsFrontmatter: false)`. Their suites stay green byte for byte,
bar E46.

**`MarkdownStyler.spans(in:)`** becomes the frontmatter and fence pass it has today plus a
mapping from line and inline tokens onto `Span`.

- **Deleted:**
  - `emphasis`;
  - `taskMarker`;
  - `listMarkerSpan`/`listMarkerLength`;
  - `headingSpans`;
  - `blockquoteMarkerLength`;
  - the tag, date and annotation scanners;
  - the per-line walk.
- `delimiterSpan` keeps `_` unconcealed.
- `suppressesSpellCheck`, `merged` and every `Span` case stay.
- `.embedRun` still comes from `embedRun(inLine:)`.
- Keep emission order wherever the corpus's overlap lines pin it.

**Corpus classes.** Run `StylerGoldenTests`. For every changed case, set `change` to
`.fix(reason:expected:)` or `.deliberate(reason:expected:)`, with the new output captured from the
new styler and one line of reason.

- Never edit `captured`.
- A difference that is neither a fix nor deliberate is a C. Fix it in the parser or in the
  mapping, and report it in chat.
- Expected A cases: `file_name_here`, `2 * 3 * 4`, and any flanking case.

**Finish.** Build `perg` and `pergamenum-mcp`, then run `scripts/mcp-smoke.py` (R-45). A red in
any of the ten styler test files (finding 14) is classed first, then explained in chat before
the test changes.

### Task 4 — Coder: the scoped renumber, scoped grow-to-fit, Oggi/Diario queries, card quote and rule (R-16, R-17, R-19)
Owner: coder
Files: Sources/Core/Editor/ListContinuation.swift, Sources/Features/Editor/NoteTextView+ListEditing.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/ViewQuerySource+Live.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Workspace/CardTextView.swift, Sources/Features/Workspace/CardTextView+Styling.swift, Sources/Features/Workspace/CardTextAttributes.swift
Tests: ListRenumberScopeTests.swift, NoteListEditingTests.swift, EditorGrowToFitScopeTests.swift, EditorHeightTests.swift, DailySurfaceQueriesTests.swift, CardBlockMarkerTests.swift, InlineSpanRevealFenceTests.swift, CardConcealmentTests.swift, CardFormattingTests.swift, ListContinuationTests.swift, ViewBlockQuerySourceTests.swift, IndexGenerationFollowUpTests.swift, TableCaretTests.swift
Signatures:
- ListContinuation.renumbered(_:touching:) — static func renumbered(_ text: String, touching edited: NSRange) -> Renumbering?
- NoteTextView.Coordinator.renumberLists(in:touching:) — func renumberLists(in textView: NSTextView, touching edited: NSRange?)
- NoteTextView.Coordinator.textView(_:shouldChangeTextInRanges:replacementStrings:) — func textView(_ textView: NSTextView, shouldChangeTextInRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool
- ListRenumberLedger — @MainActor final class ListRenumberLedger { var editedRange: NSRange? }
- NoteTextView.Coordinator.growToFitTheText — func growToFitTheText(_ textView: NSTextView, revealingCaret: Bool = false) (signature unchanged)
- ViewQuerySource.live — @MainActor static func live(for vault: VaultController) -> ViewQuerySource
- EditorColumnView.viewQueryGeneration — static func viewQueryGeneration(for vault: VaultController) -> Int (relied on, unchanged)
Red: no

**Scoped renumber (ADR-0082 §D6).**

- `renumbered(_:touching:)` widens the edited range by one line on each side and takes the
  ordered runs that touch it, reusing `LineScan.lines`, `codeFenceFlags`, `orderedRun` and
  `renumberEdit`.
- It returns the smallest range covering every changed digit run, its replacement, and
  `mapping`, which is exact per digit edit.
- `renumbered(_:)` is untouched, for the card and the fallback.

**Recording the edited range.**

- The coordinator implements `textView(_:shouldChangeTextInRanges:replacementStrings:)`. It
  returns `true` and records the union of the post-edit ranges (location, replacement UTF-16
  length).
- Nothing is recorded while `undoManager.isUndoing || isRedoing`, so an undo takes the fallback.
- Per ADR-0074 §D2, the state lives in `ListRenumberLedger`, declared in
  `NoteTextView+ListEditing.swift` and held by the coordinator as one stored property.
- `textDidChange :198` takes and clears the record and calls `renumberLists(in:touching:)`.
- The scoped path replaces only the covering range through `replaceAtomically`, inside the
  keystroke's undo group, then maps the caret.
- **Re-entry.** The renumber's own `didChangeText()` re-enters `textDidChange`. Its recorded range
  finds nothing to change and returns `nil`; keep that termination, and pin it by the one-undo
  test.

**Scoped grow-to-fit (ADR-0082 §D7).**

- Replace `ensureLayout(for: documentRange)` (`:532`) with `ensureLayout` over two ranges: the
  text range of the fragment holding the selection's end, and
  `textViewportLayoutController.viewportRange`. When the viewport range is `nil` (before the first
  layout), use the caret's range alone.
- Keep the height comparison, `layoutViewport()` and `scrollRangeToVisible`.
- Rewrite the header (`:498-529`) so it says what is laid out now and why. Keep the three
  "tried and failed" notes.
- The callers `:384` and `NoteTextView+Update.swift:71` are unchanged.

**Oggi and Diario (ADR-0082 §D8).**

- `ViewQuerySource.live(for:)` is the current body of `EditorColumnView.viewQuerySource`
  (`EditorColumn+Text.swift:248-261`), moved. Its generation stays
  `EditorColumnView.viewQueryGeneration(for:)`, which `IndexGenerationFollowUpTests` reads.
- `viewQuerySource` forwards to it.
- `TodayView` (`:233`) and `DiaryView` (`:122`) pass `queries: .live(for: vault)`. Neither passes
  `onEditQuery`, so the «Modifica query» control is not drawn there.
- Correct the doc comments listed in finding 9.

**Cards.**

- `CardTextView.hiddenKind` gains `case .blockquoteMarker: .blockquote` and
  `case .horizontalRule: .rule` inside the existing switch. Keep the opener line byte-identical,
  and keep `default: nil`.
- `CardTextView+Styling.applyStyling` pushes `decorations.ruleColor = NSColor(theme.color(.borderSubtle))`
  beside the badge colours.
- With the card delegate's gutter at 0, the quote branch sets no paragraph style (ADR-0081 §D6).

**Finish.** Run the full suite, then `perg` and `pergamenum-mcp`: `ListContinuation` is Core.

## Session A — the mockup PR (G1, G2)

### Task 5 — Coder: the gutter-reveal mockup page, its own PR (R-13, R-14, R-44)
Owner: coder
Files: Sources/Features/DesignGallery/GutterRevealMockup.swift, Sources/Features/DesignGallery/MockupGalleryView.swift, Tests/MockupGalleryLayoutTests.swift
Tests: MockupGalleryLayoutTests.swift
Signatures:
- GutterRevealMockup — struct GutterRevealMockup: View
- GutterRevealMockup.narrowWidth — static let narrowWidth: CGFloat
- GutterRevealMockup.readableWidth — static let readableWidth: CGFloat
- MockupGalleryView.Screen.gutter — case gutter
- MockupGalleryView.rowWidth — static let rowWidth: CGFloat (relied on)
- ProseTypography.heading — static func heading(level: Int, _ theme: Theme) -> NSFont (relied on)
Red: no

**Build exactly what `docs/plans/note-workflow-n2-mockup.md` Tasks 1 and 2 describe.** That
means the six scenes, the column guide, concealed and revealed rows under each other, the three
gutter values drawn as sums of existing spacing tokens, and two wiring and width tests. Those
tests check that `.gutter` is listed with `"N2, da approvare"`, and that both widths are positive
and at most `rowWidth` (672).

**Its stale lines, read through these corrections and not edited:**

- N1 has merged (#897, #905): cut the branch from current `main`.
- ADR-0081 and ADR-0082 are already on `main`. This PR touches no ADR, so `adr-references.yml`
  judges none of them here.
- "The code plan's Task 5" means this plan's Task 6.
- Headings draw through `ProseTypography.heading(level:_:)`, which carries N1's H5/H6 faces.
- The narrow width is read from the running app's Diario pane before it is drawn, as that plan
  says.

**Gate.** Stefano approves on the Debug build and answers G1 and G2. Then the PR merges. Session
C does not start before those answers.

## Session C — the gutter, the measurement, the documents (code PR, second half)

### Task 6 — Tester: the gutter's geometry and arithmetic, red (R-13, R-14)
Owner: tester
Files: Sources/DesignSystem/TokenKeys.swift, Sources/DesignSystem/Theme.swift, Sources/DesignSystem/ProseTypography.swift, Sources/Features/Editor/EditorGutter.swift, Sources/Features/Editor/ListMarkerRendering.swift, Sources/Features/Editor/EditorDecorationDelegate.swift, Sources/Features/Editor/MarkdownAttributedText.swift, Tests/EditorGutterTests.swift, Tests/GutterRevealGeometryTests.swift, Tests/MarkupHidingListTests.swift, Tests/QuoteRenderingTests.swift, Tests/CardConcealmentTests.swift, Tests/ReadableWidthTests.swift, Tests/DesignSystemTests.swift
Tests: EditorGutterTests.swift, GutterRevealGeometryTests.swift, MarkupHidingListTests.swift, QuoteRenderingTests.swift, CardConcealmentTests.swift, ReadableWidthTests.swift, DesignSystemTests.swift, MarkupHidingTests.swift, MarkupHidingCheckboxTests.swift, ListIndentFontInvariantTests.swift, TranscludedLineTests.swift, ProseParagraphSpacingTests.swift
Signatures:
- SpacingToken.gutter — case gutter = "spacing.gutter"
- Theme.emergency spacings — .gutter: <G1 value> (same edit as the case, PG-225)
- EditorGutter — enum EditorGutter
- EditorGutter.containerInset — static func containerInset(readableInset: CGFloat, gutter: CGFloat) -> CGFloat
- EditorGutter.columnSpan — static func columnSpan(containerWidth: CGFloat, padding: CGFloat, style: NSParagraphStyle?) -> (leading: CGFloat, width: CGFloat)
- EditorGutter.quoteColumn — static func quoteColumn(level: Int, font: NSFont, gutter: CGFloat) -> CGFloat
- EditorGutter.quoteStepInEms — static let quoteStepInEms: CGFloat
- ListMarkerRendering.paragraphStyle — static func paragraphStyle(level: Int, font: NSFont, basedOn: NSParagraphStyle? = nil, gutter: CGFloat = 0, hanging: CGFloat? = nil) -> NSParagraphStyle
- ListMarkerRendering.contentColumn — static func contentColumn(level: Int, font: NSFont, gutter: CGFloat) -> CGFloat
- ProseTypography.gutterMarker — static func gutterMarker(_ theme: Theme) -> NSFont
- EditorDecorationDelegate.gutter — nonisolated(unsafe) var gutter: CGFloat = 0
- EditorDecorationDelegate.markerFont — nonisolated(unsafe) var markerFont: NSFont?
- MarkdownAttributedText.base — static func base(theme: Theme, gutter: CGFloat = 0) -> [NSAttributedString.Key: Any]
- MarkdownAttributedText.StyleContext.init — init(theme: Theme, links: Bool, gutter: CGFloat = 0)
Red: yes

**Stubs.** Every stub compiles and keeps today's behaviour:

- `containerInset` returns `readableInset`;
- `columnSpan` returns `(padding, containerWidth − 2 × padding)`;
- `quoteColumn` returns `0`;
- `contentColumn` returns today's `headIndent`;
- `paragraphStyle` ignores `gutter` and `hanging`;
- `gutterMarker` returns `prose(theme)`;
- `base` and `StyleContext` ignore `gutter`.

**Theme values.** `quoteStepInEms` and the emergency gutter take the G1 answers. The two theme
JSON files are left to Task 7, so `DesignSystemTests` is red on them.

**`EditorGutterTests.swift`** (R-13, R-14, pure):

- ADR-0081 §D1's table through `containerInset`. At G = 48 that is `(W − 720)/2 − 48` at
  W ≥ 816, and 0 below 768 or with readable width off. The content column is `inset + G` in every
  row.
- `columnSpan` of a body style (`headIndent = G`, `tailIndent = −G`).
- `paragraphStyle` with `gutter:` and `hanging: w`: `headIndent == C(L)` and
  `firstLineHeadIndent == max(0, C(L) − w)` for L = 1 to 6.
- With both parameters defaulted, today's arithmetic is unchanged. The existing
  `MarkupHidingListTests.swift:295-319` and `ListIndentFontInvariantTests` stay as they are.
- `quoteColumn`.
- `###### ` measured in `gutterMarker` for `.emergency` and both bundled themes is less than G
  (ADR-0081 §D4's loud failure).

**`GutterRevealGeometryTests.swift`** (R-13, R-14, hosted through `ScrolledEditorFixture`). The
content origin is the `x` of the first content character, measured through the real layout after
`ensureLayout` for that range. Each case is measured concealed (caret elsewhere) and revealed
(caret in the paragraph, `applyReveal` run), and the two must be equal within 0.5 pt.

- **Lists:**
  - `-`, `*`, `+` at levels 1 to 3;
  - `1.`, `10.`, `12)`;
  - a wrapped item, whose second line sits at the first line's content in both states;
  - a task line: unchanged, never revealed, shifted by G.
- **Headings and quotes:** H1 to H6 and a heading with no title (G0 item 10), and quotes at
  levels 1 and 2. Each is measured at 600 pt and at 1200 pt with readable width on, and at
  1200 pt with it off (G0 item 8).
- **Body column.** At 1200 pt the body's content `x` equals today's `(W − 720)/2 + 5`. At 600 pt
  it equals `G + 5`.
- **Decorations (ADR-0081 §D7):**
  - a rule's drawn width equals `columnSpan`'s width;
  - a table attachment's and a view block's drawn frames stay inside the column;
  - a transcluded picture keeps no gutter: `MarkdownAttributedText.attributed` has
    `headIndent == 0`.
- **The `H2` badge** is pinned only if G2 approves it: a concealed heading's fragment draws it, and
  a folded one keeps it.

**Changed meaning.** State each reason in chat first: ADR-0081 §D2/§D6 make a revealed list
paragraph carry its hanging style instead of `nil`, and §D1 shrinks the inset by G.

- `MarkupHidingListTests.swift:185`, `theHookReturnsNilForARevealedListParagraph`, becomes
  `aRevealedListParagraphKeepsItsColumnAndShowsTheFileMarker`. The displayed paragraph is
  non-nil, its string equals the source with no substitution, and `headIndent == C(L)`.
- `CardConcealmentTests.swift:187`: the caret's list paragraph is now non-nil, and its string
  equals the source. A card hangs lists too (§D6).
- `ReadableWidthTests.swift:78-86`: `textContainerInset.width + gutter == (W − cap) / 2` before
  and after the resize. The column is unchanged; only the inset moved.

**Unchanged, at gutter 0** (the fixture delegates keep `gutter == 0`):

- `MarkupHidingTests.swift:49`, `:181`, `:275`, `:325`;
- `QuoteRenderingTests.swift:87`;
- `MessageAnchorEditorTests.swift:71`;
- `MarkupHidingCheckboxTests.swift:157`.

**New siblings:** `QuoteRenderingTests` gains one with `gutter > 0` (a revealed quote returns a
hanging style), and `MarkupHidingTests` gains one for a revealed heading at `gutter > 0`.

**`DesignSystemTests.swift`:** both themes define `spacing.gutter` at the G1 value, and
`Theme.emergency.spacing(.gutter)` equals it. The case and its emergency entry land in one edit
here.

### Task 7 — Coder: block markers hang in the gutter (R-13, R-14)
Owner: coder
Files: Resources/Themes/pergamenum-dark.json, Resources/Themes/pergamenum-light.json, Sources/Features/Editor/EditorGutter.swift, Sources/Features/Editor/MarkdownAttributedText.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/ListMarkerRendering.swift, Sources/DesignSystem/ProseTypography.swift, Sources/Features/Editor/EditorDecorationDelegate.swift, Sources/Features/Editor/EditorDecorationDelegate+ListRendering.swift, Sources/Features/Editor/EditorDecorationDelegate+QuoteRendering.swift, Sources/Features/Editor/EditorDecorationDelegate+HeadingRendering.swift, Sources/Features/Editor/HorizontalRuleFragment.swift, Sources/Features/Editor/TranscludedLineFragment.swift, Sources/Features/Editor/NoteTextView+Transclusion.swift, Sources/Features/Editor/EmbedResize.swift, Sources/Features/Editor/FoldedHeadingFragment.swift
Tests: EditorGutterTests.swift, GutterRevealGeometryTests.swift, MarkupHidingListTests.swift, QuoteRenderingTests.swift, CardConcealmentTests.swift, ReadableWidthTests.swift, DesignSystemTests.swift, TranscludedLineTests.swift, TableGridHostedAttachmentTests.swift, ViewBlockCaretTests.swift, EmbedEditorTestSupport.swift
Signatures:
- EditorGutter.containerInset — static func containerInset(readableInset: CGFloat, gutter: CGFloat) -> CGFloat
- EditorGutter.columnSpan — static func columnSpan(containerWidth: CGFloat, padding: CGFloat, style: NSParagraphStyle?) -> (leading: CGFloat, width: CGFloat)
- ListMarkerRendering.paragraphStyle — static func paragraphStyle(level: Int, font: NSFont, basedOn: NSParagraphStyle? = nil, gutter: CGFloat = 0, hanging: CGFloat? = nil) -> NSParagraphStyle
- EditorDecorationDelegate.headingParagraph — func headingParagraph(at range: NSRange, storage: NSTextStorage) -> NSTextParagraph?
- EditorDecorationDelegate.bodyParagraphStyle — static func bodyParagraphStyle(of paragraph: NSAttributedString) -> NSParagraphStyle? (widened from private, one comment naming its readers)
- NoteTextView.Coordinator.horizontalInset — nonisolated static func horizontalInset(viewWidth: CGFloat, cap: CGFloat, minimum: CGFloat, isOn: Bool) -> CGFloat (relied on, unchanged)
Red: no

**Tokens and the base style.**

- Both theme files gain `"gutter"` beside `"paragraph"` (`:128`), at the G1 value.
- `MarkdownAttributedText.base(theme:gutter:)` copies `ProseTypography.paragraphStyle(theme)` and,
  when `gutter > 0`, sets `firstLineHeadIndent = headIndent = G` and `tailIndent = −G`.
  `ProseTypography.paragraphStyle` itself is unchanged, since every other surface shares it.
- `applyStyling` (`:278`) builds `StyleContext(theme:links:true, gutter: theme.spacing(.gutter))`.
  It pushes `decorations.gutter` and `decorations.markerFont = ProseTypography.gutterMarker(theme)`
  beside `checkboxFont` (`:353`).
- The card never pushes either, so it stays at 0.

**Inset.** `applyReadableWidth` (`:586`) sets
`EditorGutter.containerInset(readableInset: horizontalInset(…), gutter:)` on both sides. The
initial inset at `NoteTextView.swift:107` is computed the same way. `horizontalInset` is
unchanged.

**Lists (§D2).**

- `listParagraph` stops returning `nil` when revealed. It applies `paragraphStyle(level:font:
  proseFont, basedOn:, gutter: delegate.gutter, hanging: w)`.
- `w` is the displayed run (`• `, or the file's `- `/`1. `/`12) `) measured in `proseFont`,
  memoised per (run, face).
- The leading indentation stays in `collapsedFont` in both states. A revealed list substitutes
  nothing.

**Quotes (§D3).** This applies only when `gutter > 0`. A quote composes on
`bodyParagraphStyle(of:)` and hangs both the concealed bars and the revealed `> ` run to
`quoteColumn`.

**Headings (§D4).**

- A new branch in `+HeadingRendering.swift`, dispatched from the hook beside the quote branch. It
  is active only when `gutter > 0` and the paragraph is revealed.
- It sets `firstLineHeadIndent = max(0, G − w)` and gives the `#` run `markerFont`. That is an
  attribute change, so the paragraph keeps its length (`NSTextContentManager.h:120`).

**Column sites (§D7).** Each reads `EditorGutter.columnSpan` from its own paragraph's style at
draw time, or from the theme in the coordinator sites:

- `HorizontalRuleFragment.swift:31-33`;
- `TranscludedLineFragment.swift:80-82`, its 16 pt band after the leading offset;
- `NoteTextView+Transclusion.swift:117-123`;
- `EmbedResize.swift:60-64`.

The table and view-block attachments adopt it only if Task 6's hosted test shows them leaving the
column.

**Badge (§D5).** Only if G2 approves it: one helper draws the `H2` label from a concealed heading's
fragment and from `FoldedHeadingFragment`. If G2 says no, nothing of §D5 is built.

**Memo safety.** The memo is lock-guarded. The delegate runs off the main actor (the ADR-0035 box
shape), never as a bare `nonisolated(unsafe)` dictionary.

**Checks.** Watch `EditorDecorationDelegate.swift`'s length; the branches live in their own files.
`bodyParagraphStyle(of:)` widens per ADR-0045, with one comment naming the quote and heading
files.

### Task 8 — Tester: measure after, fix the ceilings, correct the ADRs, amend SPEC §5, verify (R-15, R-17, R-44, R-45, R-46)
Owner: tester
Files: Tests/RestyleBudgetSupport.swift, docs/adr/0081-block-markers-reveal-in-the-gutter.md, docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md, docs/20260811_Pergamenum_SpecApp.md, CLAUDE.md
Tests: EditorRestyleBudgetTests.swift, StylerGoldenTests.swift, GutterRevealGeometryTests.swift, EditorGrowToFitScopeTests.swift
Signatures:
- RestyleBudget.ceilings — static let ceilings: [Case: Double] (final values from G-ceiling)
Red: no

1. **Measure "after".** Run `scripts/editor-restyle-bench.sh` on the finished tree, fill ADR-0082
   §D9's "After" column, and propose six ceilings (3× after, rounded up). The person fixes them at
   G-ceiling; the literals in `RestyleBudget.ceilings` and §D9's "Ceiling" column follow the
   decision. If the person moves the 1 MB rows out of the per-turn suite there, that is a SPEC
   seam 3 amendment for the person to make, not this task.
2. **Hand checks on the Debug build**, each with Stefano:
   - **G-grow:** a 1 MB note; type at the end and in the middle, Cmd+Down, scroll to the end,
     click low in the pane. If it fails, the fallback is chosen there (ADR-0082 §D7), then built
     and re-checked.
   - **G3 (ADR-0081):** Arrow-down through a ten-item nested list, every heading level and a
     two-level quote, at a narrow and a readable width; Oggi and Diario at their usual size, and a
     `pergamenum-view` fence rendering in both with no «Modifica query».
3. **G-corpus.** Show the classed corpus diff, every changed case with its class and reason.
   Merging needs zero C.
4. **ADR corrections.** Apply every item of "ADR corrections" above to ADR-0081 and ADR-0082.
   Add implementation notes: the G1/G2/G3 answers, the corpus counts per class, the `runPasses`
   follow-up, and the actual file names. Both stay `planned`.
5. **SPEC (app) §5, R-46.** Propose the wording in chat and apply it only after Stefano approves.
   The draft below sits in §5 after «Larghezza di lettura»; the date is the approval day.
   - *Emendato 2026-10-XX (ADR-0081, ADR-0082).* **I marcatori di blocco si rivelano nel
     margine**: quando il cursore entra in una voce d'elenco, in un titolo o in una citazione, il
     marcatore (`- `, `1. `, `## `, `> `) compare nel margine a sinistra della colonna e il testo
     non si sposta. Alla larghezza di lettura la colonna resta dov'era; sotto quella soglia si
     sposta una volta verso destra. Nelle card del Workspace, che non hanno margine, solo gli
     elenchi restano fermi.
   - **Il costo di un tasto è un numero misurato**: un test della suite misura in tempo CPU la
     ristilizzazione di note sintetiche da 50 KB, 200 KB e 1 MB, con e senza blocchi di codice e
     viste, e fallisce sopra il tetto registrato in ADR-0082 §D9.
   - In «Requisiti minimi», «rinumera quelle ordinate» becomes «rinumera l'elenco ordinato
     modificato».
6. **CLAUDE.md.** Add ADR-0081 and ADR-0082 lines to the Chain decision index, in the existing
   shape.
7. **Verify (R-45).**
   - Run the full `PergamenumTests` suite, then build the app, `perg` and `pergamenum-mcp`, and
     run `scripts/mcp-smoke.py`.
   - Read `scripts/uitests.sh --status`; `--affected` runs at merge and does not block it.
   - Then come the commit gate, the push, and the code PR, which closes #887 and #762 (R-44).
8. **After the merge.** The first docs change flips ADR-0081 and ADR-0082 to `accepted`, with the
   merge hash from `git log --first-parent main` and the date. Ledger proposals go to the parent
   session:
   - PG-385 and PG-347 closed;
   - follow-ups: `_` concealment, transclusions in Oggi and Diario, tasks on the list column
     (ADR-0081 Neutral), the `runPasses` double pass, and the restyle-the-edited-paragraph
     question decided by the numbers.

## Requirement coverage

| ID | Tasks | Proven by |
|---|---|---|
| R-13 | 5, 6, 7 | `GutterRevealGeometryTests` (lists, tasks, wrap), `EditorGutterTests`, mockup G1, hand check G3 |
| R-14 | 5, 6, 7 | `GutterRevealGeometryTests` (headings, quotes, 600/1200, off), mockup G1, G3 |
| R-15 | 1, 8 | `EditorRestyleBudgetTests` (six cases, ceilings), bench script, ADR-0082 §D9 |
| R-16 | 2, 4 | `ListRenumberScopeTests`, `NoteListEditingTests` (48, fallback, one undo) |
| R-17 | 2, 4, 8 | `EditorGrowToFitScopeTests`, restated `EditorHeightTests`, G-grow hand check |
| R-18 | 1, 2, 3 | `StylerGoldenTests` (no C), token/projection suites, `StylerSharedGrammarTests`, E46 |
| R-19 | 2, 4 | `DailySurfaceQueriesTests`, `CardBlockMarkerTests`, `InlineSpanRevealFenceTests` (9) |
| R-44 | 5, 8 | mockup PR approved, code PR closing #887/#762, ADR flip (no-test) |
| R-45 | 3, 8 | `perg`/`pergamenum-mcp` builds, `scripts/mcp-smoke.py` (no-test) |
| R-46 | 8 | SPEC (app) §5 wording approved and applied (no-test) |

## Order and dependencies

- **Before anything.** Merge `origin/main` on each branch, then `tuist install` and
  `tuist generate --no-open`. Run TEST-CMD for the baseline.
- **Session A.** Task 5 is independent and can run before or beside Session B. Its approval (G1,
  G2) gates Task 6.
- **Session B runs 1 → 2 → 3 → 4.**
  - Task 1 must run on untouched `Sources/`.
  - Task 2 is red before 3 and 4. Tasks 3 and 4 share no source file and can be dispatched in
    either order.
  - The commit gate ends the session, and the branch is pushed with no PR yet.
- **Session C runs 6 → 7 → 8.** It starts after G1/G2 and after merging `main` again, which by
  then holds the mockup PR. Task 8 closes the code PR.
- **After the merge.** The ADR flip is the first docs change. The two ADRs go `proposed` to
  `accepted` together.

## Observable contracts changed: call sites found

These greps ran on 2026-10-06 against `9103768f`. Re-run them after the `origin/main` merge, then
update every listed site and every test that asserts the old behaviour.

1. **`MarkdownBlockParser.blocks(in:)` for `>YYYY-MM-DD` at line start.**
   - Consumers:
     - `MarkdownHTML.swift:20`;
     - `ViewBlock.swift:267` (code blocks only, unaffected);
     - `MarkdownReadingView.swift:59`;
     - `TranscludedNoteView.swift:106`;
     - `PraticaEntryRow.swift:113`;
     - `PraticaMessageRow.swift:191`;
     - `PratichePane+Inspector.swift:68`.
   - **New expectation:** E46.
   - **Checked and green:**
     - `MarkdownReadingTests`;
     - `MarkdownParserCorrectionTests`;
     - `TransclusionTests`;
     - `GFMTableTests`;
     - `CRLFAppendTests`;
     - `EditorCommandTests`;
     - `TextFormatEdgeTests`;
     - `NoteOutlineTests`;
     - `TagDateClickTargetTests:307`.
2. **`MarkdownInlineParser.spans(in:)`, now a projection.** Consumers: `MarkdownHTML.swift:26`,
   `NoteOutline.swift:93`, `MarkdownBlocksView.swift:230`. The output stays byte-identical.
3. **`MarkdownStyler.spans(in:)` output, class A and B differences.**
   - Consumers:
     - `NoteTextView+Coordinator.swift:284`;
     - `MarkdownAttributedText.swift:55`;
     - `CardTextView+Styling.swift:44`;
     - `CardTextAttributes.swift:100`;
     - `InlineSpanReveal.swift:28`.
   - Ten test files (finding 14). A red there is classed in the corpus before the test changes.
4. **Renumbering.**
   - `renumberLists(in:)` at `NoteTextView+Coordinator.swift:198` moves to `renumberLists(in:touching:)`.
   - `ListContinuation.renumbered(_:)` keeps its callers: `NoteTextView+ListEditing.swift:62` as
     the fallback, and `CardTextView+ListEditing.swift:38-39`.
   - **Stale:** `NoteListEditingTests.swift:262-285`.
   - **Green:** `NoteListEditingTests.swift:224`, `CardFormattingTests.swift:464`, `:507-522`,
     `ListContinuationTests.swift:152-197`.
5. **`growToFitTheText`'s layout scope.**
   - Callers: `NoteTextView+Coordinator.swift:209`, `:384`, and `NoteTextView+Update.swift:71`.
   - **Stale:** `EditorHeightTests.swift:64-76`, `:78-97`.
   - **Green:** `:100`.
   - **Comment to check:** `TableCaretTests.swift:111` names `growToFitTheText`'s `ensureLayout`.
6. **The container inset.** `applyReadableWidth` (`NoteTextView+Coordinator.swift:586`, called
   from `pushInputs` and the frame observer) and the initial inset at `NoteTextView.swift:107`.
   - **Stale:** `ReadableWidthTests.swift:78-86`.
   - **Hosted fixtures that set their own inset**, reviewed under the gutter. They change only if
     one asserts an absolute `x`:
     - `CheckboxToggleTests`;
     - `FoldBadgeClickTests`;
     - `ProseParagraphSpacingTests`;
     - `TagDateClickTargetTests`;
     - `TranscludedLineTests`;
     - `EditorCompletionCrashTests`;
     - `EditorControllerReadTiming(Remaining)Tests`;
     - `EmbedEditorTestSupport`;
     - `HiddenBlockLinesTests`;
     - `HiddenFrontmatterTests`;
     - `MessageAnchorEditorTests`;
     - `NoteEditorTeardownTests`;
     - `NoteFindTests`;
     - `TableCaretTests`;
     - `TableGridCommitTests`;
     - `TableGridHostedAttachmentTests`;
     - `ViewBlockCaretTests`;
     - `ViewBlockQuerySourceTests`;
     - `ViewQueryCommitTests`;
     - `ViewQueryEntryPointTests`.
7. **The delegate's revealed list paragraph.** Producer:
   `EditorDecorationDelegate+ListRendering.swift:25-80`.
   - **Stale:** `MarkupHidingListTests.swift:185`, `CardConcealmentTests.swift:187`.
   - **Green at gutter 0:**
     - `MarkupHidingTests.swift:49`, `:181`, `:275`, `:325`;
     - `QuoteRenderingTests.swift:87`;
     - `MessageAnchorEditorTests.swift:71`;
     - `MarkupHidingCheckboxTests.swift:157`.
8. **`ListMarkerRendering.paragraphStyle` gains two defaulted parameters.** Caller:
   `EditorDecorationDelegate+ListRendering.swift:63`. `MarkupHidingListTests.swift:295-319` and
   `ListIndentFontInvariantTests` stay green through the defaults.
9. **`MarkdownAttributedText.base`/`StyleContext` gain a defaulted `gutter`.** Callers:
   - `NoteTextView+Coordinator.swift:278` (passes the token);
   - `MarkdownAttributedText.swift:52` (`attributed`, the transcluded picture, keeps 0);
   - `MarkdownAttributedText.swift:77` (`attributes(for:theme:links:)`, keeps 0; called directly by
     `TranscludedLineTests.swift:163` and `MarkdownAttributedTextTests`);
   - `MarkdownAttributedText.swift:122` (`StyleContext.init` reads `base(theme:)`, and passes the
     gutter through);
   - `CardTextAttributes`, which has its own base and is untouched.
10. **The card's `hiddenKind`** (`CardTextView.swift:368-383`).
    - **Stale:** `InlineSpanRevealFenceTests.swift:323-354` (7 to 9).
    - **Green:** `CardConcealmentTests` (except `:187`) and `MessageAnchorEditorTests`.
11. **`queries` passed by Oggi and Diario.** Sites: `TodayView.swift:233`, `DiaryView.swift:122`,
    and `EditorColumn+Text.swift:103`, `:248`.
    - **Stale docs:** finding 9's list.
    - **Green:** `IndexGenerationFollowUpTests` and `ViewBlockQuerySourceTests`.
12. **`SpacingToken.gutter`.** `Theme.swift:325-335` (the emergency dictionary). No `switch` over
    `SpacingToken` exists. `DesignGalleryView.swift:17` shows a count.

Run the **full** `PergamenumTests` suite after each change above, not only the new files.

## Risks and HITL gates

**Risks:**

- **The styler rewrite touches what every note conceals.** The corpus is only as good as its
  inputs, so Task 1 widens them beyond the export corpus (finding 11's divergences, CRLF,
  separators, tabs, frontmatter).
- **Byte-for-byte projection.** A projection that drifts reaches the exporter, the reading views,
  Pratiche and the connectors (finding 12). The parser suites and `NoteExportGoldenTests` are the
  guard, and `readsFrontmatter` defaults to `false`.
- **Grow-to-fit.** Two earlier fixes passed the suite and failed in the app. The hand check is not
  optional, and the hosted tests never use `layoutSubtreeIfNeeded`.
- **The budget's own cost.** The 1 MB rows add seconds to every Stop-hook turn on today's code.
  Task 1 reports the wall time, and G-ceiling may move those rows. CPU time on the calling thread
  excludes any work dispatched elsewhere; the printout names it.
- **Thread safety.** The marker-width memo is touched by TextKit through a non-isolated delegate,
  so it is lock-guarded.
- **PG-225.** A `SpacingToken` case without its `Theme.emergency` entry kills the test process.
  Task 6 adds both in one edit.
- **SwiftLint limits:**
  - `EditorDecorationDelegate.swift` (892 lines, error at 1000);
  - `MarkdownStyler.swift`;
  - `NoteTextView+Coordinator.swift`;
  - the token file.
- **Re-entry.** A renumbering keystroke re-enters `textDidChange`. The scoped path must still
  terminate in one nested pass and one undo step.
- **PG-219 and N3** will edit hover and tracking in the same coordinator files. N2 owns
  `textDidChange` and grow-to-fit. Whichever merges second brings `main` in through
  `sync_operation`, never a force.
- **ADR check.** `adr-references.yml` reports ADR-0081/0082 as "flip it to accepted" on the code
  PR. This is advisory and expected; the post-merge flip clears it.
- **Stale DerivedData.** The TodayView/DiaryView body changes can trigger the CLAUDE.md
  `initializeWithCopy` crash on a stale incremental build.
- **No externally provisioned resource:** no network, no new dependency, no permission, no port,
  no env var beyond the test-runner capture flag.

**HITL gates:**

- **G0/GATE 1:** plan approval, including the ten interpretations above.
- **Mockup approval (ADR-0081 G1, G2)** on the mockup PR's Debug build. It decides the gutter
  value, the marker face, the quote step, the narrow-width shift and the `H2` badge. Task 6 cannot
  start without it.
- **G-caret:** the restated tests, each reason said first:
  - `NoteListEditingTests` 49 to 48, with the fallback pinned;
  - `EditorHeightTests` `:64-76` and `:78-97`;
  - `InlineSpanRevealFenceTests` 7 to 9;
  - `MarkupHidingListTests:185`;
  - `CardConcealmentTests:187`;
  - `ReadableWidthTests:78-86`.
- **G-corpus:** the classed corpus diff, with zero C.
- **G-ceiling:** the six ceilings, and whether the 1 MB rows stay in the per-turn suite.
- **G-grow:** the 1 MB hand check; the fallback, if needed, is chosen here.
- **G3 (ADR-0081):** the arrow-down hand check at a narrow and a readable width, plus Oggi and
  Diario.
- **R-46:** the SPEC (app) §5 wording.
- **Repository steps:**
  - commit gates at the end of each session;
  - both pushes;
  - the mockup PR and the code PR;
  - their merges;
  - the ADR-0081/0082 flip commit;
  - the ledger sync.
- **What is not involved:** no schema change, no deletion of user data, no deploy. The styler's
  private recognisers are symbol deletions inside a reviewed diff, not file deletions.

## Candidates

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

This keeps `.claude/test-cmd` unchanged. It already runs the whole `PergamenumTests` target, so
the restyle budget test runs every turn as SPEC test seam 3 asks, and no GUI test is added. The
`-only-testing:PergamenumTests` restriction is load-bearing (CLAUDE.md, the Stop hook).
`scripts/editor-restyle-bench.sh` runs the budget suite alone for the table.

CHECK-CMD CANDIDATE: NONE

The project declares no static check that is green on the tree:

- there is no `.claude/check-cmd`;
- `ci.yml` does not run SwiftLint;
- a whole-repo `swiftlint lint` exits non-zero on existing, documented debt (`.swiftlint.yml`),
  so as a stop-gate it would fail every turn for reasons this chain did not introduce.

Per-file SwiftLint on touched files stays a review step (standing rule 7).

## Build result (2026-10-07)

BUILD · DONE WITH WARNINGS
Files: 35 changed or new (Session C, Tasks 6 to 8; the gutter, the column sites, the tests, ADR-0081 and ADR-0082 corrections, ADR index, the bench guard)
Tests: PergamenumTests 5700 tests in 349 suites green, 5 known issues; app, perg and pergamenum-mcp build, scripts/mcp-smoke.py green; 18 (coverage)
Review: sonnet, safe; opus, safe
Coverage: COVERED R-13, R-14, R-15, R-16, R-17, R-18, R-19, R-44, R-45, R-46 (10 declared, 10 covered, 0 uncovered; run against docs/specs-pending/pg-385-n2-page.SPEC.md)
Dropped: 7 (fix-hunk 2, post-sweep 4, nit 1)
Dispatch:
Round 0 (red): tester — Task 6
Round 0 (green): coder — Task 7
Round 1: debugger — HorizontalRuleFragment.swift:69 fragment origin, coder — hidesMarkup guards, memo cap, transclusion column width, table test, G0 item 10 note, line length, column-site tests
Round 2: coder — ADR-0081 fragment-origin note, ADR re-wrap
Round 3 (sweep): coder — C1 bench guard, C2 wide table grid (not closed), MarkupHidingListTests.swift:260, CardConcealmentTests.swift:21
Round 4 (sweep): coder — MarkupHidingListTests.swift:286, CardConcealmentTests.swift:37, editor-restyle-bench.sh:30
WARN: SPEC (app) §5 (docs/20260811_Pergamenum_SpecApp.md) is not amended: R-46 needs Stefano's approval of the drafted wording
WARN: hand checks G-grow and G3 and the decisions G-ceiling, G-corpus and G-caret are open; RestyleBudget.ceilings literals are unchanged, and the two 1 MB rows are one cold run each
WARN: a heading with no title (G0 item 10) cannot hang its run, the styler registers no marker for it; recorded in ADR-0081 notes
WARN: the branch is behind origin/main (HEAD 931a89f3); merge origin/main before the PR
WARN: scripts/uitests.sh --status has no verdict for HEAD; a full UI run is due
WARN: Stop hook test run timed out once at 600 s (attempt 1 of 3, fail-open)
INFO: review escalated, size: 34 changed files, threshold 20
INFO: ADR-0081 and ADR-0082 stay planned (the repo's word); the long-form index entries went to docs/adr/INDEX.md, not CLAUDE.md

```text
FIX	swept	**MAJOR** [wrong-behaviour] Sources/Features/Editor/HorizontalRuleFragment.swift:69 — The rule and the transcluded picture now add columnSpan's leading to the fragment's own origin while MessageAnchorFragment.swift:65 still draws at point.x with none, and layoutFragmentFrame.minX is never measured (the new ink test rasterises at a hand-chosen x: 0, Tests/GutterRevealGeometryTests.swift:475), so either the envelope paints inside the gutter or the two new sites double-count padding+indent. Fix: pin layoutFragmentFrame.minX/leadingPadding in a hosted test (or rasterise at fragment.layoutFragmentFrame.origin) and give all three fragments one convention. (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Features/Editor/EditorDecorationDelegate+HeadingRendering.swift:18 — headingParagraph has no hidesMarkup guard while quoteParagraph carries one with its reason stated (ADR-0018 §D10 must mean off wherever it is asked); only the hook reaches it today. Fix: add guard hidesMarkup, and to the list branch with it. (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Features/Editor/EditorGutter.swift:55 — MarkerRunWidths never evicts and its keys are not the few runs its header claims (one per ordered-list ordinal, one per quote level), so a long note grows the memo for the view's lifetime. Fix: clear it when the face changes, or cap it. (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Features/Editor/NoteTextView+Transclusion.swift:121 — The reserved width comes from a freshly built base(theme:gutter:) style while the fragment draws from the source line's own paragraph style, so a transclusion line inside a quote or an item is measured at a width it is not drawn at; it also rebuilds the whole attribute dictionary per pass. Fix: read the paragraph style from the storage at that line's offset, falling back to the base. (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/GutterRevealGeometryTests.swift:540 — The "table needs no change" claim rests on a 2-column table at 600 pt, and TableGridView is content-sized (TableGridView.swift:161), so the test cannot show a grid wider than the narrowed column. Fix: use a table or width whose intrinsic grid exceeds the column, or scope it out in ADR-0081 §D7. (reviewer: opus)
FIX	swept	**MINOR** [plan-deviation] Tests/GutterRevealGeometryTests.swift:429 — The plan's G0 item 10 (a titleless heading hangs its run) is unimplementable because MarkdownStyler registers no marker, and the deviation lives only in a test comment, not in ADR-0081's implementation notes. Fix: add one sentence to those notes. (reviewer: opus)
FIX	swept	**MINOR** [style] Tests/EditorGutterTests.swift:312 — 127 characters, over .swiftlint.yml's line_length warning of 120 on a code line. Fix: split the interpolated message. (reviewer: sonnet, opus)
FIX	swept	**NIT** Tests/ReadableWidthTests.swift:84 — before > 0 replaces before > minimumHorizontalInset, which still holds at the fixture's width, losing the above-the-floor check. Fix: keep the floor comparison. (reviewer: opus)
FIX	swept	**NIT** docs/plans/pg-385-n2-page.md:970 — Task 8 item 4 says the ADRs stay "proposed" while the files, the INDEX and README rule 2 use "planned"; the tree is correct, only the plan's word is stale. Fix: say planned. (reviewer: opus)
FIX	swept	**NIT** Tests/EditorGutterTests.swift:11 — Red-phase header ("RED on arrival", "declared with stubs") is stale now that Task 7 landed; same in Tests/GutterRevealGeometryTests.swift:22 and Tests/DesignSystemTests.swift. Fix: reword or delete those paragraphs. (reviewer: sonnet)
FIX	swept	**MINOR** [other] docs/adr/0081-block-markers-reveal-in-the-gutter.md:312 — The implementation notes never record the measured fragment-origin convention (point.x already is the column start, so the two fragment sites never add columnSpan.leading, which has no production reader), while §D7 reads as if the picture adds the leading offset. Fix: one sentence in "Where it landed" and a clause in columnSpan's doc comment saying leading is test-only. (reviewer: opus)
FIX	swept	**NIT** docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md:421 — Four added ADR prose lines run to 156, 137, 126 and 117 characters against the files' ~100-column wrap (also 0081:136 and :201). Fix: re-wrap them. (reviewer: opus)
DROP	post-sweep	**NIT** Sources/Features/Editor/EditorDecorationDelegate.swift:174 — The file reaches 925 lines after +29, against SwiftLint's file_length error of 1000. Fix: keep the next branch in its own extension file, as the heading one is. (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/MarkupHidingListTests.swift:260 — large_tuple SwiftLint warning in a red-phase test (follow-up: tester)
FIX	swept	**MINOR** [other] scripts/editor-restyle-bench.sh:63 — the guard pattern matches the command line of another session's polling shell, so it can refuse with nothing building (follow-up: tester)
DROP	fix-hunk	**MINOR** [other] Sources/Features/Editor/HorizontalRuleFragment.swift:56 — renderingSurfaceBounds uses max(base.width, ruleWidth) from base.minX; if base.minX < 0 the surface could stop before the end of the line, not measured, the hosted ink test passes within 1 pt (follow-up: coder)
DROP	fix-hunk	**MINOR** [other] Tests/GutterRevealGeometryTests.swift:461 — SwiftLint large_tuple violation on inkSpan (3-member tuple) (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Sources/Features/Editor/TableGridView.swift:161 — a table grid wider than the column enters the right gutter; limiting it or making it scrollable is a table decision, now recorded in ADR-0081 notes (follow-up: coder) [also Sources/Features/Editor/TableAttachment.swift:93]
FIX	swept	**MINOR** [other] Tests/CardConcealmentTests.swift:21 — a stale RED on arrival paragraph, outside this build (follow-up: coder)
FIX	swept	**MINOR** [style] Tests/MarkupHidingListTests.swift:286 — Lines 286 (121 chars) and 289 (122) exceed .swiftlint.yml's line_length warning of 120 with ignores_comments false. Fix: hoist the interpolated values into locals or split the two #expect messages. (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/CardConcealmentTests.swift:37-39 — displayed(paragraphAt:)'s doc comment still says nil covers "the paragraph revealed under the caret" and that any other answer has its markers collapsed, both contradicted by the file's own new assertions at :177-190 and :213-221. Fix: state ADR-0081 D6's split, lists hang on a card while heading and quote keep nil. (reviewer: opus)
FIX	swept	**MINOR** [other] scripts/editor-restyle-bench.sh:30-32 — The header claims parity with scripts/uitests.sh, which still carries the pgrep -fl 'xcodebuild.*Pergamenum' guard this round replaced and so still refuses to start beside another session's polling shell. Fix: qualify the parity clause and file porting the pgrep -x plus args check to uitests.sh:1205. (reviewer: opus)
DROP	post-sweep	**MINOR** [other] scripts/uitests.sh:1205 — still uses the old pgrep -fl 'xcodebuild.*Pergamenum' guard, which also matches a shell that only names the command (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Tests/MarkupHidingListTests.swift:434 — file_length warning, 434 lines against 400 (321 at HEAD), the growth comes from this build (follow-up: coder)
```
