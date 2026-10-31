**Requirement set:** none, ledger entries PG-427 and PG-428 (no SPEC applies; the root SPEC.md belongs to PG-406)

# PG-427 and PG-428: `_` emphasis concealed like `*`, transclusions drawn in Oggi and Diario

## Requirements, verbatim

- **PG-427** (P3, kind:roadmap): `_` emphasis markers stay unconcealed in the editor (decided in
  the N2 plan, not an oversight): conceal them the way `*` is.
  `Sources/Features/Editor/MarkdownStyler.swift` · `docs/plans/pg-385-n2-page.md`.
- **PG-428** (P3, kind:roadmap): Oggi and Diario pass no `queries`, so transclusions and view fences
  stay raw there; make them render as in a note. Follow-up of PG-385 (#887).
- **Acceptance**, as Stefano stated it on 2026-10-30 ("sono delle p3, fixale subito"):
  - `_a_` and `__a__` delimiters are concealed exactly like `*a*` and `**a**` on every surface that
    conceals `*`: the note editor, Oggi, Diario and Workspace text cards.
  - They reveal under the same caret and span rules.
  - `nome_file_lungo` stays plain text and is never concealed.
  - In Oggi and Diario, transclusions (`![[...]]`) and view fences render as they do in an ordinary
    note's editor.

## Frame

- **ADR outcome: a new record, ADR-0098**, at
  `docs/adr/0098-underscore-emphasis-is-concealed-and-the-daily-panes-draw-transclusions.md`
  (drafted under `docs/architecture/` and moved there by the orchestrator before GATE 1).
  - It amends ADR-0082 §D2's "`_` emphasis stays unconcealed". ADR-0082's own implementation notes
    say that reversal is "a decision for its own record".
  - It closes ADR-0082 §D8's named transclusion gap.
  - It restores ADR-0018 §D1 as written, and SPEC (app) §5, which already says «il `*`/`_`
    dell'enfasi».
- **Number.** `0098`. `origin/main` stops at `0096`. `0097` is held by the uncommitted PG-399
  draft in another worktree. No ref holds `0097*` or `0098*` (`git log --all`, 2026-10-30).
  Check again before the merge (`docs/adr/README.md` rule 1).
- **Governing records, registered and not reopened:**
  - ADR-0018 §D1/§D2: concealment by paragraph substitution, the stale-entry re-check, and reveal
    by paragraph;
  - ADR-0037 §D2/§D4/§D5: span reveal; `.emphasis` is an inline kind;
  - ADR-0077 §D5: the intraword `_` rule lives in the parser;
  - ADR-0082 §D2 (one grammar, no second recogniser), §D3 (the golden corpus, captured strings
    never edited), §D8 (one factory per vault source, no «Modifica query» in the daily panes) and
    §D9 (the six ceilings);
  - ADR-0010 §D2/§D3/§D6: the transclusion lookup and depth one;
  - ADR-0053: the panes cannot be hosted;
  - ADR-0091 §D7: a ranged transclusion scan;
  - ADR-0096: no term proportional to the note on the SwiftUI path of a keystroke.
- **N2 plan decisions registered.** "`_` emphasis stays unconcealed" is the one decision PG-427
  reverses, through ADR-0098. "Oggi and Diario share one query-source factory" is applied
  unchanged to the transclusion source. "No GUI test" holds.
- **Baseline.** `main` at `54cf47e7`, clean. Cut `feature/pg-427-pg-428-underscore-and-daily-transclusions`
  from `origin/main`. Before the first task run `tuist install`, `tuist generate --no-open`, then
  TEST-CMD for the baseline.
- **Delivery.** One branch, one `/build` session, one PR.

## What reading the tree added (`54cf47e7`)

1. **Half of PG-428 already shipped.**
   - `TodayView.swift:240` and `DiaryView.swift:129` pass `queries: .live(for: vault)`, since
     #956 (`806277d3` on the branch, merged as `558db01c`).
   - `DailySurfaceQueriesTests.swift:76-83` pins it.
   - The ledger line repeats the N2 plan's pre-build wording.
   - What is still missing is `transclusions`. Neither pane passes it (`TodayView.swift:234-243`,
     `DiaryView.swift:123-132`), and ADR-0082 §D8 named that gap and left it open.
   - The view-fence half is checked by hand only (G-hand). If a fence is still raw there, the cause
     is new, it is reported, and it is not guessed at here.
2. **The styler is not the only gate.** `EditorDecorationDelegate.stillSpellsAnEmphasisMarker`
   (`EditorDecorationDelegate.swift:869-875`) accepts one or two `*` only.
   - A `_` `.emphasisMarker` reaching the delegate is refused as stale, and nothing is concealed.
   - The golden corpus cannot see this: its `hidden` lines come from the pure
     `NoteTextView.Coordinator.hiddenKind(for:)`.
   - The note editor and the card build this same delegate (`NoteTextView+Coordinator.swift:68`,
     `CardTextView.swift:213`).
   - Fixing the styler alone would be green in the corpus and invisible on screen.
3. **The card needs no code of its own.** `CardTextView.Coordinator.hiddenKind(for:)` already maps
   `.emphasisMarker` to `.emphasis` (`CardTextView.swift:371`). `InlineSpanRevealFenceTests`' card
   arm count stays 9.
4. **Reveal needs no change.**
   - `InlineSpanReveal.constructs` reads `.italic`/`.bold` run spans, which a `_` run already
     carries.
   - `HiddenMarker.Kind.emphasis` is inline (`EditorDecorationDelegate.swift:117`).
   - ADR-0081's gutter is for block markers only, so it does not apply to an inline delimiter.
5. **The interface copy names `*` only.** The caption under «Nascondi i marcatori mentre scrivi»
   reads «I `#` di un titolo e i `*` di un'enfasi non vengono disegnati» (`EditorSettings.swift:96`).
   No test pins it (`git grep "di un'enfasi"`: the source line only).
6. **Two pinned tests assert the old behaviour:**
   - `MarkdownStylerTests.swift:101-107` (`underscoreEmphasisHasNoMarkerSpan`);
   - `StylerSharedGrammarTests.swift:37-50` (`anUnderscorePairIsItalicAndItsDelimitersStayVisible`),
     with its header at `:8-10`.

   The corpus inputs holding a `_` run are `E25` (`file_name_here e __forte__ e _lieve_`) and `S35`.
   Both are already classed `.fix` (`StylerGoldenChanges.swift:56`, `:152`).
7. **The transclusion pass already scans in both panes.** `TransclusionController.apply`
   (`NoteTextView+Transclusion.swift:149-199`) scans whether or not a source is set; a nil source
   only makes `rendition(for:)` return nil (`:308`). The only vault-backed `TransclusionSource` is
   `EditorColumnView.transclusionSource` (`EditorColumn+Text.swift:281-299`).
8. **One test claims to build the editor "the way Oggi and Diario build it"**, with "no transclusion
   source": `IncrementalRestyleSurfacesTests.swift:84-100`. After PG-428 that sentence is false.
9. **Stale comments:**
   - `NoteTextView+ViewBlocks.swift:241` ("`DiaryView`/`TodayView` pass no `queries`"), false
     since #956;
   - `NoteTextView+Inputs.swift:114-116`, the `transclusions` input's doc;
   - `DailySurfaceQueriesTests.swift:6-11`, a red-phase header that says neither pane passes
     `queries`.
10. **File limits** (SwiftLint `file_length` warns at 400 and errors at 1000):
    - `EditorDecorationDelegate.swift` is 966 lines;
    - `MarkdownStyler.swift` is 586;
    - `MarkupHidingTests.swift` is 455 and `CardConcealmentTests.swift` 423, so new tests go in new
      files (the per-file-fixture convention `CardBlockMarkerTests.swift:8-9` names).
11. **Shared sources.** Neither `MarkdownStyler` nor the delegate is in `sharedSources`
    (`Project.swift:87`), so `perg` and `pergamenum-mcp` are untouched.

## How the keystroke budget stays intact (ADR-0082 §D9, ADR-0091, ADR-0093, ADR-0096)

- **PG-427** changes a per-token constant only: the two `.emphasisMarker` appends a `*` run already
  pays, and a per-marker character test.
  - It adds no pass, no scan and no allocation per line.
  - `RestyleBudgetSupport.swift:117-136`'s synthetic note holds no `_` run, so the measured
    workload's output is byte-identical.
  - The six ceilings are not re-measured and not edited.
  - `EditorRestyleBudgetTests` and `IncrementalStylerPropertyTests` (whose alphabets hold `_`) run
    in every full-suite run below.
  - A red budget test is reported as a finding, never answered by raising a ceiling.
- **PG-428.** The scan already runs. A source adds resolution only for occurrences in the dirty
  range, or on an index generation change, which a write makes and a keystroke never does.
  - The factory reads `vault.indexGeneration`, which both pane bodies already observe through
    `ViewQuerySource.live(for:)`.
  - The SwiftUI path of a keystroke therefore gains no observation and no term proportional to the
    note.
  - `EditorUpdatePathBudgetTests`, `UpdatePathSourceGuardTests` and `SurfaceParityUpdateTests` stay
    in the run.

## Standing rules for every task

1. Run TEST-CMD after every task, the whole `PergamenumTests` target, never a filtered subset.
2. Run `tuist generate --no-open` after any task that adds a file (Tasks 1, 3).
3. A test that asserts the old behaviour is changed only after its reason is said in chat
   (CLAUDE.md). The three are named under G-tests.
4. No GUI test. `scripts/uitests.sh --affected` runs at merge and does not block it.

### Task 1 — Tester: `_` delimiters are concealed and revealed like `*`, red (PG-427)
Owner: tester
Files: Tests/UnderscoreEmphasisConcealmentTests.swift, Tests/MarkdownStylerTests.swift, Tests/StylerSharedGrammarTests.swift
Tests: UnderscoreEmphasisConcealmentTests.swift, MarkdownStylerTests.swift, StylerSharedGrammarTests.swift
Signatures:
- MarkdownStyler.spans — static func spans(in text: String) -> [MarkdownStyler.StyledRange] (relied on, unchanged)
- NoteTextView.Coordinator.hiddenKind — static func hiddenKind(for span: MarkdownStyler.Span) -> HiddenMarker.Kind? (relied on, unchanged)
- CardTextView.Coordinator.hiddenKind — static func hiddenKind(for styled: MarkdownStyler.StyledRange) -> HiddenMarker.Kind? (relied on, unchanged)
- MarkupHidingFixture.displayedParagraph — static func displayedParagraph(_ note: String, markers: [HiddenMarker], at location: Int = 0, hidesMarkup: Bool = true, revealed: Set<Int> = [], spans: [Int: [NSRange]] = [:], revealsInlineSpans: Bool = false) -> NSTextParagraph? (relied on)
- EditorDecorationDelegate.textContentStorage(_:textParagraphWith:) — func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? (relied on)
- ScrolledEditorFixture.init — init(text: String, width: CGFloat = 900, height: CGFloat = 700, hidesMarkup: Bool = true, readableWidth: Bool = true, theme: Theme = .emergency, queries: ViewQuerySource? = nil, vault: NoteTextView.VaultInputs? = nil, revealsInlineSpans: Bool = false, forcesFullRestyle: Bool? = false, forcesFullLayout: Bool? = false, bound: BoundText? = nil) (relied on)
Red: yes
Depends: none

No production signature is new. Every test compiles against today's API and is red only where the
behaviour is missing.

**`UnderscoreEmphasisConcealmentTests.swift`** (new; header cites ADR-0098 §D1/§D2 and PG-427):

- **The styler, pure. Red:**
  - `"testo _corsivo_ qui"` carries exactly two `.emphasisMarker` spans, spelling `"_"` and `"_"`;
  - `"testo __forte__ qui"` carries exactly two, spelling `"__"` and `"__"`;
  - each marker is emitted after its run span (the `theEmphasisMarkerSpansComeAfterTheRunSpan`
    shape);
  - each maps to `.emphasis` through both `hiddenKind` tables.
- **The styler, pure. Green guards that must stay green:** none of the following carries an
  `.emphasisMarker`:
  - the intraword cases `nome_file_lungo`, `file_name_here`, `snake_case_name`, `_lieve_mente` and
    `a__b__ c`;
  - the wikilinks `[[nome_file_lungo]]` and `[[20260811_Pergamenum_SpecApp]]`;
  - inline code `` `a_b_` `` and a fenced `_x_`;
  - the unclosed `_solo` and the opener followed by a space, `_ a_`;
  - the empty run `____` (the `****` guard).
- **The delegate, driven directly** through `MarkupHidingFixture.displayedParagraph`:
  - `"testo __forte__ e _lieve_\n"` with four `.emphasis` markers (`__` at 6 and 13, `_` at 18 and
    24; derive the offsets from the string, never hand-count them):
    - at rest, a non-nil paragraph of identical length. **Red**: today the re-check refuses `_`.
    - Revealed paragraph: nil. Green.
    - `hidesMarkup: false`: nil. Green.
  - With `revealsInlineSpans: true` and the `__forte__` span revealed, a non-nil paragraph in
    which only `_lieve_`'s markers collapse. **Red.**
  - Stale-entry guards, green: an `.emphasis` entry over `*_` (mixed), over `___` (three) and over
    two prose letters each yields nil.
- **The hosted note editor.** `ScrolledEditorFixture(text: "testo _corsivo_ e __forte__\naltro\n")`:
  - the coordinator's delegate table at paragraph 0 holds four `.emphasis` entries at the four
    delimiter ranges. **Red.**
  - With the caret on the second line, the delegate's substituted paragraph for paragraph 0 is
    non-nil. **Red.**
  - With the caret inside `_corsivo_`, it is nil (ADR-0018 §D2 paragraph reveal). Green.
  - A paragraph `nome_file_lungo` gets no entry. Green.
- **The hosted card**, a private copy of `CardConcealmentTests`' card fixture (the convention
  `CardBlockMarkerTests.swift:8-9` names). For `"_corsivo_ e __forte__"`:
  - the card coordinator's `hiddenMarkers[0]` holds four `.emphasis` entries;
  - an uneditable card's `displayed(paragraphAt: 0)` is non-nil.
  - **Red.**

**Restated (G-tests: say each reason in chat first, which is ADR-0098 §D1 reversing ADR-0082 §D2):**

- `MarkdownStylerTests.underscoreEmphasisHasNoMarkerSpan` (`:101-107`) becomes
  `underscoreEmphasisHasTwoMarkerSpans`:
  - `emphasisMarkers("testo _corsivo_ qui") == ["_", "_"]`;
  - `emphasisMarkers("testo __forte__ qui") == ["__", "__"]`;
  - `.italic` still present.

  Its comment cites ADR-0098 in place of "Deliberate narrowing of ADR-0018 §D1". Red.
- `StylerSharedGrammarTests.anUnderscorePairIsItalicAndItsDelimitersStayVisible` (`:37-50`) becomes
  `anUnderscorePairIsItalicAndItsDelimitersAreConcealable`:
  - the italic range is still `"_a_"`;
  - there are two `.emphasisMarker` spans over the `_`;
  - each maps to `.emphasis`.

  The header (`:8-10`) loses "`_` emphasis stays unconcealed (G0)". Red.
  `intrawordUnderscoresCarryNoEmphasisSpan` and `aStarPairKeepsItsConcealableMarkers` are untouched.

Report the red count, and confirm every green guard above is green on untouched `Sources/`.

Sub-tasks:
- [x] Create `Tests/UnderscoreEmphasisConcealmentTests.swift` with its ADR-0098 §D1/§D2 header and the pure styler cases: two `.emphasisMarker` spans spelling `"_"`/`"_"` and `"__"`/`"__"`, emitted after the run span, each mapping to `.emphasis` through `NoteTextView.Coordinator.hiddenKind(for:)` and `CardTextView.Coordinator.hiddenKind(for:)`; red
- [x] Add the styler green guards to the same file: `nome_file_lungo`, `file_name_here`, `snake_case_name`, `_lieve_mente`, `a__b__ c`, the two wikilinks, inline code `` `a_b_` ``, a fenced `_x_`, `_solo`, `_ a_` and `____` each carry no `.emphasisMarker`; green on untouched `Sources/`
- [x] Add the delegate cases through `MarkupHidingFixture.displayedParagraph` over `"testo __forte__ e _lieve_\n"` with offsets derived from the string: at rest non-nil of equal length (red), revealed nil, `hidesMarkup: false` nil, the `revealsInlineSpans` case collapsing only `_lieve_`'s markers (red), and nil for stale entries over `*_`, `___` and two prose letters
- [x] Add the hosted note editor cases on `ScrolledEditorFixture(text: "testo _corsivo_ e __forte__\naltro\n")`: four `.emphasis` entries at paragraph 0 (red), a non-nil substituted paragraph with the caret on line 2 (red), nil with the caret inside `_corsivo_`, and no entry for a `nome_file_lungo` paragraph
- [x] Add a private copy of `CardConcealmentTests`' card fixture and the card cases for `"_corsivo_ e __forte__"`: `hiddenMarkers[0]` holds four `.emphasis` entries and an uneditable card's `displayed(paragraphAt: 0)` is non-nil; red
- [x] State the G-tests reason in chat, then rename `MarkdownStylerTests.underscoreEmphasisHasNoMarkerSpan` to `underscoreEmphasisHasTwoMarkerSpans` asserting `["_", "_"]`, `["__", "__"]` and `.italic`, with its comment citing ADR-0098; red
- [x] Rename `StylerSharedGrammarTests.anUnderscorePairIsItalicAndItsDelimitersStayVisible` to `anUnderscorePairIsItalicAndItsDelimitersAreConcealable` (italic `"_a_"`, two `.emphasisMarker` spans, each `.emphasis`) and drop "`_` emphasis stays unconcealed (G0)" from the header at `:8-10`; `git grep "StayVisible" Tests/` prints nothing
- [x] Run `tuist generate --no-open`, then TEST-CMD; report the red count and confirm every green guard, `intrawordUnderscoresCarryNoEmphasisSpan` and `aStarPairKeepsItsConcealableMarkers` pass

### Task 2 — Coder: the styler mapping, the delegate re-check, the caption, the corpus classes (PG-427)
Owner: coder
Files: Sources/Features/Editor/MarkdownStyler.swift, Sources/Features/Editor/EditorDecorationDelegate.swift, Sources/Features/Settings/EditorSettings.swift, Tests/StylerGoldenChanges.swift
Tests: UnderscoreEmphasisConcealmentTests.swift, MarkdownStylerTests.swift, StylerSharedGrammarTests.swift, StylerGoldenTests.swift, MarkupHidingTests.swift, MarkupHidingInlineSpanTests.swift, CardConcealmentTests.swift, InlineSpanRevealFenceTests.swift, InlineSpanRevealTests.swift, IncrementalStylerPropertyTests.swift, SpellCheckTests.swift, MarkdownAttributedTextTests.swift, EditorRestyleBudgetTests.swift
Signatures:
- MarkdownStyler.spans — static func spans(in text: String) -> [MarkdownStyler.StyledRange] (signature unchanged; output gains `.emphasisMarker` over `_`/`__` delimiters)
- MarkdownStyler.spans(in:readsFrontmatter:listSeed:) — static func spans(in text: String, readsFrontmatter: Bool, listSeed: [Int]) -> [MarkdownStyler.StyledRange] (unchanged; same body, so the fragment path follows)
- EditorDecorationDelegate.stillSpellsAnEmphasisMarker — private static func stillSpellsAnEmphasisMarker(_ text: NSString, at range: NSRange) -> Bool (body widened)
- StylerGoldenCase.Change — enum Change { case unchanged; case fix(reason: String, expected: String); case deliberate(reason: String, expected: String) } (relied on)
Red: no
Wave: 1
Depends: Task 1

**Styler (ADR-0098 §D1).**

- In `spans(of:in:)` (`MarkdownStyler.swift:390-418`), drop `starMarker`. `.strong` and
  `.emphasis` pass `.emphasisMarker` to `run(...)` whatever the delimiter.
- `run`'s empty-run guard stays as it is.
- Rewrite the comments that state the old rule: the file header (`:5-12`), `Span.emphasisMarker`
  (`:23-27`), `:392` and `run`'s doc (`:420-423`). Each cites ADR-0098 §D1 and names the parser's
  flanking rule as what keeps `nome_file_lungo` plain.
- Net line count: zero or fewer.

**Delegate (ADR-0098 §D2).**

- `stillSpellsAnEmphasisMarker` (`:869-875`) answers true when the candidate is one or two
  characters, all the same, and that character is `*` or `_`.
- Update its doc line.
- Net change of three lines or fewer: the file is at 966 and errors at 1000.

**Caption (ADR-0098 §D1).** `EditorSettings.swift:96` becomes «I `#` di un titolo e i `*` o `_` di
un'enfasi non vengono disegnati, e ricompaiono …». The rest of the sentence is unchanged.

**Corpus (ADR-0098 §D3).**

- Run `StylerGoldenTests`. `E25` and `S35` are expected to move. For each:
  - keep `.fix`;
  - reprint `expected` from the new styler through `StylerGoldenCorpus.canonical`;
  - append one sentence to the reason citing ADR-0098 §D1.
- A moved case that was `.unchanged` becomes `.deliberate` with that reason.
- Never edit a captured string.
- Any moved line that is not an `_`/`__` `emphasisMarker`, `hidden … emphasis` or `order` line
  is a C. Stop and report it in chat; do not class it.

**Finish.** Run the full suite. Expect green with the ceilings untouched. A red budget row is
reported, not raised.

Sub-tasks:
- [x] In `MarkdownStyler.spans(of:in:)` delete `starMarker` and pass `.emphasisMarker` to `run(...)` in the `.strong` and `.emphasis` arms; `grep -n starMarker Sources/Features/Editor/MarkdownStyler.swift` prints nothing and `UnderscoreEmphasisConcealmentTests`' styler cases pass
- [x] Rewrite the header (`:5-12`), `Span.emphasisMarker` (`:23-27`), the `:392` comment and `run`'s doc (`:420-423`) to cite ADR-0098 §D1 and the parser's flanking rule; `git diff --numstat` on the file shows added lines not above removed ones
- [x] Widen `EditorDecorationDelegate.stillSpellsAnEmphasisMarker` to one or two copies of the same character, `*` or `_`, and update its doc line; the delegate and hosted cases of `UnderscoreEmphasisConcealmentTests` pass, `MarkupHidingTests.aStaleEmphasisEntryDoesNotCollapseProse` stays green, and `wc -l` on the file reads 969 or fewer
- [x] Change the caption at `EditorSettings.swift:96` to «I `#` di un titolo e i `*` o `_` di un'enfasi non vengono disegnati, e ricompaiono …»; `git grep "i \`\*\` o \`_\` di un'enfasi" Sources/` finds the one line
- [x] Run `StylerGoldenTests`; for `E25` and `S35` keep `.fix`, reprint `expected` through `StylerGoldenCorpus.canonical` and append one sentence citing ADR-0098 §D1 in `Tests/StylerGoldenChanges.swift`; any other moved case that was `.unchanged` becomes `.deliberate`, and any moved line that is not a `_`/`__` marker, `hidden … emphasis` or `order` line is stopped and reported in chat as a C
- [x] Run TEST-CMD over the whole `PergamenumTests` target; Task 1's cases and `StylerGoldenTests` pass, `EditorRestyleBudgetTests` passes with its ceilings unedited (a red row is reported, not raised)

### Task 3 — Tester: Oggi and Diario draw transclusions, red, with the factory's signature (PG-428)
Owner: tester
Files: Sources/Features/Editor/TransclusionSource+Live.swift, Tests/DailySurfaceTransclusionsTests.swift, Tests/IncrementalRestyleSurfacesTests.swift, Tests/DailySurfaceQueriesTests.swift
Tests: DailySurfaceTransclusionsTests.swift, IncrementalRestyleSurfacesTests.swift, DailySurfaceQueriesTests.swift, IndexGenerationFollowUpTests.swift
Signatures:
- TransclusionSource.live — @MainActor static func live(for vault: VaultController) -> TransclusionSource (declared here; stub body `TransclusionSource(resolve: { _ in nil }, generation: 0)`)
- EditorColumnView.transclusionGeneration — static func transclusionGeneration(for vault: VaultController) -> Int (relied on, unchanged)
- ViewQuerySource.live — @MainActor static func live(for vault: VaultController) -> ViewQuerySource (relied on, unchanged)
- NoteTextView.VaultInputs.transclusions — var transclusions: TransclusionSource? (relied on, unchanged)
- TransclusionController.lastRenditions — private(set) var lastRenditions: [Int: TranscludedRendition] (relied on)
- RestyleTwin — struct RestyleTwin; init(incremental: ScrolledEditorFixture, full: ScrolledEditorFixture, foldedHeading: String? = nil, root: URL? = nil) (relied on)
- resolvedRepoRoot — func resolvedRepoRoot() throws -> URL (relied on)
Red: yes
Depends: none

**`Sources/Features/Editor/TransclusionSource+Live.swift`** is new. It holds an
`extension TransclusionSource` with `live(for:)`, `@MainActor`, and the stub body above, so the
target builds and the tests below are red rather than unbuildable.

- Its header follows `ViewQuerySource+Live.swift`'s shape: it cites ADR-0098 §D4 and ADR-0082 §D8,
  and says the stub is replaced by Task 4.
- Run `tuist generate --no-open` after adding it.

**`DailySurfaceTransclusionsTests.swift`** (new): a `TemporaryVault` holding `Note/N.md` with a
body line and a `## Sezione`, opened through
`VaultController(recents: .volatile(), openTabs: .volatile())`. The `DailySurfaceQueriesTests`
shape, `.serialized`.

- **The generation.** The factory's generation equals
  `EditorColumnView.transclusionGeneration(for:)`, and it moves after a write plus `reconcile`.
  Red on the move.
- **The lookup.** `resolve("N")` and `resolve("Note/N.md")` both return `relativePath == "Note/N.md"`
  and the file's text, and `resolve("Assente")` is nil. Red.
- **A hosted editor draws it.** Build `ScrolledEditorFixture(text: "prima\n![[N]]\ndopo\n", vault:)`
  with the inputs the panes pass: `vaultRoot`, `notePath`, `thumbnails`, `transclusions: .live(for:)`
  and `queries: .live(for:)`. Then:
  - after `runPasses()`, `coordinator.transclusion.lastRenditions` holds one rendition at the
    line's offset, titled `N`. Red.
  - A `![[N#Sezione]]` line gets a rendition titled `N › Sezione`. Red.
- **The incremental path.** A `RestyleTwin` of two such editors (incremental, and
  `forcesFullRestyle: true`) over a prose line and the `![[N]]` line. One prose keystroke:
  - is one incremental restyle;
  - leaves the rendition drawn;
  - gives `twin.differences().isEmpty`.

  Red, because no rendition is drawn with the stub.
- **Source guards**, read through `resolvedRepoRoot()`. Red:
  - `TodayView.swift` and `DiaryView.swift` each contain `transclusions: .live(for: vault)`;
  - `EditorColumn+Text.swift` no longer contains `vault.index.resolve(title:`, so the lookup lives
    in the factory only. This is the call-site check, not a symbol check: a factory nothing calls
    must fail here.

**Restated (G-tests, reason first).**

- `IncrementalRestyleSurfacesTests.aDailyPaneEditorWithNoFlagSetTakesTheIncrementalPath`
  (`:84-100`) claims to build the editor as the panes do. Its `VaultInputs` gain
  `transclusions: .live(for: controller)`, and its comment drops "no transclusion source".
  It stays green: its text holds no `![[`.

**Doc only.** `DailySurfaceQueriesTests.swift:6-11` loses the red-phase sentence saying neither
pane passes `queries`.

Sub-tasks:
- [x] Create `Sources/Features/Editor/TransclusionSource+Live.swift` with a `ViewQuerySource+Live.swift`-shaped header (ADR-0098 §D4, ADR-0082 §D8, "replaced by Task 4") and `@MainActor static func live(for vault: VaultController) -> TransclusionSource` returning `TransclusionSource(resolve: { _ in nil }, generation: 0)`; run `tuist generate --no-open` and the app target builds
- [x] Create `Tests/DailySurfaceTransclusionsTests.swift`, `.serialized`, over a `TemporaryVault` holding `Note/N.md` with a body line and `## Sezione`: the generation equals `EditorColumnView.transclusionGeneration(for:)` and moves after a write plus `reconcile` (red), and `resolve("N")`/`resolve("Note/N.md")` return `Note/N.md` and its text while `resolve("Assente")` is nil (red)
- [x] Add the hosted editor cases on `ScrolledEditorFixture(text: "prima\n![[N]]\ndopo\n", vault:)` with the panes' inputs (`transclusions: .live(for:)`, `queries: .live(for:)`): after `runPasses()` `coordinator.transclusion.lastRenditions` holds one rendition titled `N`, and a `![[N#Sezione]]` line one titled `N › Sezione`; red
- [x] Add the `RestyleTwin` case (incremental and `forcesFullRestyle: true`): one prose keystroke is one incremental restyle, leaves the rendition drawn, and gives `twin.differences().isEmpty`; red
- [x] Add the source guards through `resolvedRepoRoot()`: `TodayView.swift` and `DiaryView.swift` each contain `transclusions: .live(for: vault)`, and `EditorColumn+Text.swift` does not contain `vault.index.resolve(title:`; red
- [x] State the G-tests reason in chat, then give `IncrementalRestyleSurfacesTests.aDailyPaneEditorWithNoFlagSetTakesTheIncrementalPath`'s `VaultInputs` `transclusions: .live(for: controller)` and drop "no transclusion source" from its (R-11) comment; it stays green
- [x] Remove the red-phase sentence from `DailySurfaceQueriesTests.swift:6-11`, then run TEST-CMD and report the red count (every red one in `DailySurfaceTransclusionsTests`, `DailySurfaceQueriesTests` and `IndexGenerationFollowUpTests` green)

### Task 4 — Coder: the factory body, the column's forward, the two panes, the doc comments (PG-428)
Owner: coder
Files: Sources/Features/Editor/TransclusionSource+Live.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView+ViewBlocks.swift, Sources/Features/Editor/TranscludedNoteView.swift
Tests: DailySurfaceTransclusionsTests.swift, DailySurfaceQueriesTests.swift, IncrementalRestyleSurfacesTests.swift, IndexGenerationFollowUpTests.swift, TransclusionScopeTests.swift, TranscludedLineTests.swift, TransclusionTests.swift, ViewBlockQuerySourceTests.swift, SurfaceParityUpdateTests.swift, UpdatePathSourceGuardTests.swift, EditorUpdatePathBudgetTests.swift, EditorRestyleBudgetTests.swift
Signatures:
- TransclusionSource.live — @MainActor static func live(for vault: VaultController) -> TransclusionSource (body moved from `EditorColumnView.transclusionSource`)
- EditorColumnView.transclusionSource — var transclusionSource: TransclusionSource (now `.live(for: vault)`)
- EditorColumnView.transclusionGeneration — static func transclusionGeneration(for vault: VaultController) -> Int (unchanged)
- NoteTextView.VaultInputs.transclusions — var transclusions: TransclusionSource? (unchanged; doc rewritten)
Red: no
Wave: 1
Depends: Task 3

**Factory (ADR-0098 §D4).**

- Move the body of `EditorColumnView.transclusionSource` (`EditorColumn+Text.swift:281-299`),
  unchanged, into `TransclusionSource.live(for:)`. That is the `.md`-path-then-title lookup through
  `vault.session` and `vault.index`, with `generation: EditorColumnView.transclusionGeneration(for: vault)`.
- Move its doc comment with it.
- `transclusionSource` forwards to `.live(for: vault)`, the way `viewQuerySource` does at `:257`,
  with a doc that names the three hosts.
- `transclusionGeneration(for:)` stays where it is: `IndexGenerationFollowUpTests` reads it.

**Panes.**

- `TodayView` (`:234-243`) and `DiaryView` (`:123-132`) pass `transclusions: .live(for: vault)`
  between `thumbnails:` and `queries:`, the memberwise order.
- Extend each pane's existing one-line comment to say it is the Note pane's source (ADR-0010 §D3)
  and that a click follows through the pane's own `onFollowLink`.
- Nothing else in either body changes.

**Doc comments.**

- `NoteTextView+Inputs.swift:114-116`: `transclusions` is handed in by the three hosts as
  `TransclusionSource.live(for:)`, the `queries` doc's own shape.
- `NoteTextView+ViewBlocks.swift:238-242`: the daily panes pass the live query source, without
  `onEditQuery`.

**Finish.**

- Run the full suite.
- Build the app target once, then open the Debug build per CLAUDE.md's DerivedData recipe. If it
  crashes at launch in `initializeWithCopy`, that is a stale incremental build after a pane body
  change: move this worktree's own DerivedData folder aside and rebuild clean.

Sub-tasks:
- [x] Move the body and doc comment of `EditorColumnView.transclusionSource` (`EditorColumn+Text.swift:281-299`) unchanged into `TransclusionSource.live(for:)` in `TransclusionSource+Live.swift`, with `generation: EditorColumnView.transclusionGeneration(for: vault)`; `DailySurfaceTransclusionsTests`' generation and lookup cases pass
- [x] Make `EditorColumnView.transclusionSource` return `.live(for: vault)` as `viewQuerySource` does, with a doc naming the three hosts, and leave `transclusionGeneration(for:)` in place; `git grep "vault.index.resolve(title:" Sources/Features/Editor/EditorColumn+Text.swift` prints nothing and `IndexGenerationFollowUpTests` passes
- [x] Pass `transclusions: .live(for: vault)` between `thumbnails:` and `queries:` in `TodayView` (`:234-243`) and `DiaryView` (`:123-132`), extending each pane's one-line comment (Note pane's source, ADR-0010 §D3, a click follows the pane's own `onFollowLink`); the source-guard cases pass
- [x] Rewrite the `transclusions` doc at `NoteTextView+Inputs.swift:114-116` (handed in by the three hosts as `TransclusionSource.live(for:)`) and the daily-pane sentence at `NoteTextView+ViewBlocks.swift:238-242` (live query source, no `onEditQuery`); `git grep "pass no \`queries\`" Sources/` prints nothing
- [x] Run TEST-CMD over the whole `PergamenumTests` target; `DailySurfaceTransclusionsTests` (hosted editor and `RestyleTwin` included), `UpdatePathSourceGuardTests`, `EditorUpdatePathBudgetTests`, `SurfaceParityUpdateTests` and `EditorRestyleBudgetTests` pass
- [x] Build the `Pergamenum` scheme, locate this checkout's Debug build with CLAUDE.md's `WorkspacePath` recipe and `open -n "$APP"`; the app launches without an `initializeWithCopy` crash (otherwise move this worktree's own DerivedData aside and rebuild clean)
  Done 2026-10-30: `BUILD SUCCEEDED`, the `Pergamenum-affgbig…` Debug build (dylib 21:12) launched with `open -n`, ran 40 s (PID 94323), and left no Pergamenum crash report in `~/Library/Logs/DiagnosticReports`.

### Task 5 — Coder: the records, and the verification before the commit gate (PG-427, PG-428)
Owner: coder
Files: docs/adr/0098-underscore-emphasis-is-concealed-and-the-daily-panes-draw-transclusions.md, docs/adr/0082-the-styler-classifies-through-the-shared-parsers.md, CLAUDE.md
Tests: StylerGoldenTests.swift, EditorRestyleBudgetTests.swift, UnderscoreEmphasisConcealmentTests.swift, DailySurfaceTransclusionsTests.swift
Signatures:
- ADR-0098 heading — ``# ADR-0098: `_` emphasis is concealed as `*` is, and Oggi and Diario draw transclusions`` (frozen: `scripts/adr-index.py` reads it)
- ADR-0082 §D2 amendment line — ``*Amended 2026-10-30 by ADR-0098 §D1: `_` and `__` delimiters are concealed as `*` and `**` are.*``
- ADR-0082 §D8 closing line — ``*Closed by ADR-0098 §D4: Oggi and Diario pass `transclusions: .live(for: vault)`.*``
Red: no
Wave: 2
Depends: Task 1, Task 2, Task 3, Task 4

**Precondition.** ADR-0098 must already be at `docs/adr/` under its staged name, moved there by the
orchestrator before `/build`. If it is still under `docs/architecture/`, stop and report; do not
move it yourself.

1. **ADR-0098.** Fill the implementation notes:
   - the files touched;
   - the moved corpus cases with their classes (expected: `E25` and `S35`, still `.fix`, reasons
     extended; zero B unless a case surfaced; zero C);
   - the red-then-green counts of Tasks 1 and 3;
   - that the budget's ceilings were not touched.

   Leave the status `proposed` (or `planned`, if it reached `main` with this plan). The flip comes
   after the merge.
2. **ADR-0082.** Add the two dated lines above:
   - the §D2 line directly under the paragraph "`_` emphasis stays unconcealed";
   - the §D8 line under "Named and not fixed".

   In the implementation notes' follow-up list, mark the two matching items "closed by ADR-0098".
   Nothing else in ADR-0082 changes.
3. **CLAUDE.md.** Paste the `ADR-0098` line `scripts/adr-index.py` prints into `## ADR index`, then
   run `scripts/adr-index.py --check`. If `0097` has landed on `main` by then, its line comes from
   the same command.
4. **Checks.**
   - Run `git fetch origin`, then `scripts/check-adr-references.py`. Its findings are advisory.
   - Run TEST-CMD once more on the finished tree.
   - Run `scripts/uitests.sh --status`. It reports only.
5. **Hand-check list.** Write the G-hand-427/428 steps from ADR-0098's Gates into the chat for
   Stefano, with plain-text key names. Then stop at the commit gate.

Sub-tasks:
- [x] Confirm `docs/adr/0098-underscore-emphasis-is-concealed-and-the-daily-panes-draw-transclusions.md` exists and nothing remains under `docs/architecture/`; otherwise stop and report
- [x] Fill ADR-0098's `## Implementation notes` with the files touched, `E25`/`S35` and their classes (zero C), the red-then-green counts of Tasks 1 and 3 and the untouched ceilings, leaving the status line `proposed` (or `planned`)
- [x] Add the §D2 amendment line under ADR-0082's "`_` emphasis stays unconcealed" paragraph (`:145`) and the §D8 closing line under "Named and not fixed" (`:380`), and mark the two matching items in its "Follow-ups" list (`:610`) "closed by ADR-0098"; `git diff --stat` on ADR-0082 shows only those lines
- [x] Paste the `ADR-0098` line `scripts/adr-index.py` prints into `CLAUDE.md`'s `## ADR index`; `scripts/adr-index.py --check` exits 0
- [x] Run `git fetch origin`, then `scripts/check-adr-references.py` (findings advisory), TEST-CMD on the finished tree (green) and `scripts/uitests.sh --status` (report only)
- [x] Write the G-hand-427/428 steps from ADR-0098's Gates into chat with plain-text key names, then stop at the commit gate

## Requirement coverage

| ID | Tasks | Proven by |
|---|---|---|
| PG-427 | 1, 2, 5 | `UnderscoreEmphasisConcealmentTests` (styler, delegate, hosted editor, hosted card), restated `MarkdownStylerTests`/`StylerSharedGrammarTests`, `StylerGoldenTests` (no C), G-hand-427 (Oggi, Diario, card) |
| PG-428 | 3, 4, 5 | `DailySurfaceTransclusionsTests` (factory, hosted editor, incremental twin, source guards), `DailySurfaceQueriesTests` (the fence half, green since #956), G-hand-428 (both panes, transclusion and fence) |

## Observable contracts changed: call sites found

These greps ran on `54cf47e7`. Re-run them after merging `origin/main` into the branch.

1. **`MarkdownStyler.spans(in:)` output for `_`/`__` runs.**
   - Sources:
     - `NoteTextView+Coordinator.swift:433` and `:844` (full and fragment walks into
       `hiddenKind`, `:532-535`);
     - `CardTextView+Styling.swift:44` (the card's table);
     - `CardTextAttributes.swift:100` (card colour);
     - `MarkdownAttributedText.swift:68` (transcluded picture colour);
     - `InlineSpanReveal.swift:28` (reads run spans only, unaffected);
     - `ProseParagraphSpacing.swift:93` (`.emphasisMarker` does not shape its line, unaffected).
   - Tests calling it: `EditorChipDrawingTests`, `IncrementalStylerModel`,
     `IncrementalStylerPropertyTests`, `ListNestingForwardPassTests`, `ListNestingTests`,
     `MarkdownAttributedTextTests`, `MarkdownStylerBlockTests`, `MarkdownStylerFixture`,
     `MarkdownStylerTests`, `MessageAnchorEditorTests`, `ProseParagraphSpacingTests`,
     `SpellCheckTests`, `StructureMapTests`, `StylerGoldenCorpus`, `StylerSharedGrammarTests`,
     `ViewBlockSpanTests`, `ViewQueryOutOfScopeTests`.
   - **Stale:**
     - `MarkdownStylerTests.swift:101-107`;
     - `StylerSharedGrammarTests.swift:8-10` and `:37-50`;
     - corpus `E25` and `S35`.

     No other test fixture holds an accepted `_` run (grep over `Tests/*.swift`, golden
     captures excluded).
2. **`stillSpellsAnEmphasisMarker`'s acceptance.** It is called from `stillSpells` (`:789`), which
   the generic substitution path calls (`:655`).
   - New: `UnderscoreEmphasisConcealmentTests`.
   - **Green:**
     - `MarkupHidingTests` `MarkupHidingEmphasis` (`:170-243`), including
       `aStaleEmphasisEntryDoesNotCollapseProse`;
     - `MarkupHidingInlineSpanTests`;
     - `MarkupHidingCheckboxTests:189`;
     - `MarkupHidingListTests:361`;
     - `CardConcealmentTests`.
3. **`NoteTextView.VaultInputs.transclusions`, now set by the daily panes.** Sites:
   - `TodayView.swift:234-243`;
   - `DiaryView.swift:123-132`;
   - `EditorColumn+Text.swift:110` and `:281-299`.

   - **Stale:** `IncrementalRestyleSurfacesTests.swift:84-100` (its inputs).
   - **Green:**
     - `IndexGenerationFollowUpTests:114-132`;
     - `DailySurfaceQueriesTests`;
     - `UpdatePathSourceGuardTests:116-124` (the bindings are unchanged);
     - `TransclusionScopeTests`;
     - `TranscludedLineTests`.

     `SurfaceParityUpdateTests.swift:9`/`:17` cite `TodayView.swift`/`DiaryView.swift` line
     numbers in comments, which shift by one; comment-only.
4. **The settings caption.** `EditorSettings.swift:96`. No test pins it.

Run the full `PergamenumTests` suite after each change above.

## Order and dependencies

- **Before anything:** merge `origin/main` into the branch (never rebase, never force), then
  `tuist install` and `tuist generate --no-open`, then TEST-CMD for the baseline.
- **Order:** 1 → 2 and 3 → 4. The two pairs share no file and can run in either order. `/build`
  runs the two red tester tasks first. Task 5 runs last, after both coders.
- **The commit gate** ends the session. The ADR flip to `accepted` is the first docs change after
  the merge.

## Risks and HITL gates

**Risks:**

- **The delegate re-check is the load-bearing change, and the corpus cannot see it** (finding 2).
  Task 1's delegate, hosted-editor and hosted-card tests are what catch a styler-only fix.
- **A visible change wherever the grammar accepts a `_` run outside code.**
  - `__init__` in prose draws as a bold «init», with its underscores hidden at rest.
  - `[[_bozza_]]` shows «bozza», because wikilink interiors are scanned for emphasis (#188).
  - A URL path segment `/_x_/` is italic.

  `*` already behaves this way and the export already renders it so. The person's acceptance
  ("exactly like `*`") covers it. Confirm at G-hand anyway.
- **File limits.** `EditorDecorationDelegate.swift` is at 966 of 1000. Task 2 caps its growth at
  three lines.
- **The panes cannot be hosted** (ADR-0053). Their parity rests on source guards, a hosted
  `NoteTextView` built with the panes' inputs, and the hand check.
- **The ledger's premise for fences is stale** (finding 1). A raw fence at G-hand is a new defect.
  It is recorded in the ledger, not patched in this PR.
- **Diario re-resolves its transclusions on every save of the day**, since the index generation
  moves on each one. This is the Note pane's existing bargain (PG-328), and it is bounded by the
  number of `![[` lines.
- **Stale DerivedData** after the pane body edits (CLAUDE.md's `initializeWithCopy` rule).
- **Parallel chains.**
  - ADR number `0097` (PG-399) may land first or later. Rule 1 is re-checked before the merge.
  - Another branch touching `TodayView`, `DiaryView` or `MarkdownStyler` is brought in by merging
    `main`, with the pre-push merge-integrity hook (ADR-0061/0062) installed.
- **PG-423**, the N2 gutter hand checks on Oggi and Diario, overlaps G-hand in place but not in
  content. This plan does not close it.
- **No externally provisioned resource:** no network, no dependency, no permission, no port, no
  environment variable.

**HITL gates:**

- **GATE 1:** plan approval, including ADR-0098's decisions (already relocated to `docs/adr/`).
- **G-tests:** the three restated tests (Tasks 1 and 3), each reason said in chat before the edit.
- **G-corpus-427:** the person reads the moved corpus cases and their classes. A C blocks the
  merge.
- **G-hand-427/428** on the Debug build:
  - `_a_`, `__a__`, `*a*` and `nome_file_lungo` at rest and under the caret, in a note, in Oggi, in
    Diario and in a Workspace text card, with «Rivela solo la parola sotto il cursore» off and
    then on;
  - `![[Nota]]` and a `pergamenum-view` fence in Oggi and in Diario, each drawn, the fence with no
    «Modifica query».
- **Repository steps:** the commit gate, the push, the PR, its merge, the ADR-0098 flip commit, and
  the ledger sync closing PG-427 and PG-428. PR bodies say "refs PG-427"/"refs PG-428", never a
  closing keyword.
- **Not involved:** no schema change, no deletion of user data, no deploy, no file format change.

## Candidates

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test

CHECK-CMD CANDIDATE: NONE

`.claude/test-cmd` already holds this command, so it stays unchanged. `.claude/check-cmd` holds
`NONE`. `.swiftlint.yml` exists, but it is not declared as the project's check, and by its own
comment it fails on seven types today, so it cannot be a stop-gate.

## Build result (2026-10-30)

BUILD · DONE
Files: 22 (20 modified or added in the diff, plus the untracked ADR-0098 and this plan)
Tests: 7107 passed, 12 (coverage)
Review: sonnet, safe; opus, safe
Coverage: not run, the plan's requirement set is not SPEC.md
Deferred: 0
Dropped: 5 (post-sweep 1, unlocated 2, nit 2)
Dispatch: Round 0 (red): tester — Task 1, tester — Task 3
Dispatch: Round 0 (wave 1): coder — Task 2, coder — Task 4; debugger — DailySurfaceTransclusionsTests stale offset
Dispatch: Round 1: coder — red-phase comments; coder — Debug launch check
Dispatch: Round 2: coder — stale stub comments
Dispatch: Round 3 (sweep): coder — MarkdownStyler.swift:423, ADR-0098:252, TransclusionSource+Live.swift:37, StylerSharedGrammarTests.swift:8, DailySurfaceQueriesTests.swift:68, C1, C2, C3
Dispatch: Round 4 (sweep): coder — NoteTextView+Inputs.swift:117, plan:352
INFO: review escalated, size: 21 changed files, threshold 20

```text
FIX	swept	**NIT** Sources/Features/Editor/MarkdownStyler.swift:423 — run(...markedBy:) made non-optional, the if let dropped. (reviewer: opus)
FIX	swept	**NIT** docs/adr/0098-underscore-emphasis-is-concealed-and-the-daily-panes-draw-transclusions.md:252-255 — Files touched lists UnderscoreAndTransclusionCoverageTests and reclassifies DailySurfaceQueriesTests. (reviewer: sonnet, opus)
FIX	swept	**NIT** Sources/Features/Editor/TransclusionSource+Live.swift:37 — a doc line explains why the generation stays on EditorColumnView. (reviewer: sonnet)
FIX	swept	**MINOR** [other] Tests/StylerSharedGrammarTests.swift:8 — stale "Red until Task 3" sentence removed. (follow-up: coder)
FIX	swept	**MINOR** [other] Tests/DailySurfaceQueriesTests.swift:68 — stale stub sentence reworded. (follow-up: coder)
FIX	swept	**MINOR** [other] Sources/Features/Editor/NoteTextView.swift:201-202 — [[Nota# completion in Oggi and Diario named in ADR-0098 Consequences and covered by a hosted test. (reviewer: opus)
FIX	swept	**NIT** Sources/Features/Editor/TranscludedNoteView.swift:6-8 — the doc names only the callers that pass nil, the three Pratiche bodies. (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/HostedViewSupport.swift:46 — R-15 sendEvent issues verified pre-existing on a clean main run (4 there, 2 here), ledger PG-434, no change. (follow-up: coder, tester)
FIX	swept	**NIT** Sources/Features/Editor/NoteTextView+Inputs.swift:117 — the doc names vaultInputs(for:). (reviewer: sonnet)
FIX	swept	**NIT** docs/plans/pg-427-pg-428-underscore-concealment-daily-transclusions.md:352 — Task 4's Files line lists TranscludedNoteView.swift. (reviewer: opus)
DROP	post-sweep	**MINOR** [other] Sources/Features/Editor/NoteTextView+Inputs.swift:126 — the queries doc comment names editing(_:) as the host, but VaultInputs are built in vaultInputs(for:); predates this branch. (follow-up: coder)
DROP	unlocated	**MINOR** [other] scripts/uitests.sh: --status exits 1 with "nessun verdetto", although CLAUDE.md says it "fails nothing". (follow-up: coder)
DROP	unlocated	**MINOR** [other] ~/Library/Logs/DiagnosticReports/ExcUserFault_nsattributedstringagent-2026-10-30-*.ips: four nsattributedstringagent fault reports from a system process, not investigated. (follow-up: coder)
```
