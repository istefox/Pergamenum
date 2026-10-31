# ADR-0098: `_` emphasis is concealed as `*` is, and Oggi and Diario draw transclusions

- Status: **accepted**. Merged to `main` via PR #1036 (`9bc493b4`, 2026-10-31), built from
  `docs/plans/pg-427-pg-428-underscore-concealment-daily-transclusions.md`.
- Date: 2026-10-30. Written against `54cf47e7` (`origin/main` at the same commit). Every line number
  below was read there.
- Number: `0098`. The highest number on `origin/main` is `0096`. `0097` is held by a draft for
  `PG-399` that is not yet committed in another worktree, which rule 1 counts. No ref held
  `docs/adr/0097*` or `docs/adr/0098*` on 2026-10-30 (`git log --all` printed nothing for either).
  Check again immediately before the merge (rule 1), including the branches about to merge.
- Source: ledger entries `PG-427` and `PG-428` (P3, kind:roadmap, opened 2026-10-15 from the N2
  close-out). Stefano asked on 2026-10-30 for both to be fixed now ("sono delle p3, fixale
  subito"). No root SPEC applies: the root `SPEC.md` belongs to `PG-406`.
- **Amends** ADR-0082 §D2, its paragraph "`_` emphasis stays unconcealed", which that record said
  should be reversed only by a record of its own. **Closes** ADR-0082 §D8's "Named and not fixed"
  transclusion gap by applying §D8's one-factory rule unchanged. **Restores** ADR-0018 §D1 as
  written ("the `*` or `_` of emphasis") and brings the editor into line with SPEC (app) §5, which
  already lists «il `*`/`_` dell'enfasi» among the constructs that hide their syntax. Supersedes
  nothing.

## Context

- **What the styler does today.** `MarkdownStyler.spans(of:in:)` maps a `.strong` or `.emphasis`
  inline token onto `.bold`/`.italic`. It adds the two `.emphasisMarker` delimiter spans only when
  the run opens with `*`. The test is `starMarker` at `MarkdownStyler.swift:393`, and the comments at
  `:23-27`, `:392` and `:420-423` give the reason. A `_a_` or `__a__` run is styled and its
  delimiters stay on screen. `Tests/MarkdownStylerTests.swift:101` (`underscoreEmphasisHasNoMarkerSpan`)
  and `Tests/StylerSharedGrammarTests.swift:37-50` pin that. The editor settings caption says the
  same thing in the interface: «I `#` di un titolo e i `*` di un'enfasi non vengono disegnati»
  (`EditorSettings.swift:96`).
- **Why it was so, and why that reason is gone.** ADR-0018 §D1 decided to hide "the `*` or `_` of
  emphasis". The implementation narrowed it to `*`, because the styler's own scanner had no
  word-boundary rule and `nome_file_lungo` parsed as italic. Hiding its `_` would have shown
  `nomefilelungo`. ADR-0082 moved the styler onto the shared grammar, whose flanking rule
  (ADR-0077 §D5, `MarkdownInline+Emphasis.swift:31-37` for opening and `:71-74` for closing) reads
  an intraword `_` as nothing. `nome_file_lungo`, `file_name_here` and `_lieve_mente` therefore
  carry no emphasis token at all. ADR-0082 §D2 still kept `_` visible, as "a visible change no N2
  criterion asks for". Its implementation notes call the reversal "a decision for its own record".
- **The second gate is not in the styler.** `EditorDecorationDelegate` collapses a hidden marker
  only after `stillSpells` re-reads the live characters, so a stale table entry can never collapse
  prose. For `.emphasis` that check is `stillSpellsAnEmphasisMarker`
  (`EditorDecorationDelegate.swift:869-875`), which accepts exactly one or two `*`. A `_`
  `.emphasisMarker` that reached the delegate would therefore be refused, and nothing would be
  concealed. The styler golden corpus would not notice: its `hidden` lines come from
  `NoteTextView.Coordinator.hiddenKind(for:)`, a pure mapping, not from the delegate. The note
  editor and the Workspace `.text` card share this delegate (`NoteTextView+Coordinator.swift:68`,
  `CardTextView.swift:213`). Both map `.emphasisMarker` to `.emphasis`
  (`NoteTextView+Coordinator.swift:535`, `CardTextView.swift:371`).
- **Reveal is already span-shaped for both spellings.** ADR-0037's `InlineSpanReveal.constructs`
  reads the `.italic`/`.bold` run spans, which a `_` run already has. `HiddenMarker.Kind.emphasis`
  is inline (`EditorDecorationDelegate.swift:117`). ADR-0081's gutter governs block markers (list,
  heading, quote) and has nothing to say about an inline delimiter.
- **The daily panes.** ADR-0082 §D8 moved the view-query source into `ViewQuerySource.live(for:)`.
  `TodayView` and `DiaryView` pass it (`TodayView.swift:240`, `DiaryView.swift:129`, since #956),
  and `DailySurfaceQueriesTests` pins it. So the "view fences stay raw" half of `PG-428` describes
  the tree before #956, and the ledger line repeats the N2 plan's pre-build wording. Neither pane
  passes `transclusions` (`TodayView.swift:234-243`, `DiaryView.swift:123-132`). A `![[Nota]]`
  there stays the plain link it was, as §D8 named and left open. The only `TransclusionSource` over
  a vault is `EditorColumnView.transclusionSource` (`EditorColumn+Text.swift:281-299`), a computed
  property on a view the daily panes cannot reach.
- **What the transclusion pass costs without a source.** `TransclusionController.apply`
  (`NoteTextView+Transclusion.swift:149-199`) scans the dirty range on every pass whether or not a
  source is set. A nil source only makes `rendition(for:)` return nil (`:308`). Neither pane can be
  hosted in a test, because each needs `CommandActions` and through it `EventKitStore`
  (`HostedViewPrototypeTests.swift:9-13`, ADR-0053).

## Decision

### D1. The styler marks `_` and `__` delimiters as it marks `*` and `**`

`spans(of:in:)` gives a `.strong` or `.emphasis` token's two delimiters the `.emphasisMarker` span
whatever character spells them. `starMarker` goes, and `run(_:_:delimiters:markedBy:)` keeps its
empty-run guard: `____` keeps its characters as `****` does. The styler adds no rule of its own
about where a `_` may open or close. That stays the parser's, and only the parser's (ADR-0082 §D2:
no second recogniser). Everything downstream already has an arm for `.emphasisMarker`:

- concealment at rest (`hiddenKind` in the note editor and in the card);
- reveal by paragraph (ADR-0018 §D2) or by span under `revealsInlineSpans` (ADR-0037);
- the marker grey (`MarkdownAttributedText.colorToken`, `CardTextAttributes`);
- exclusion from spell check (`suppressesSpellCheck`);
- the line-shape table (`ProseParagraphSpacing.shapesItsLine`).

No `Span` case, `HiddenMarker.Kind` or arm is added. `InlineSpanRevealFenceTests`' count of the
card's arms stays 9. The settings caption under «Nascondi i marcatori mentre scrivi» names `_`
beside `*`: «I `#` di un titolo e i `*` o `_` di un'enfasi non vengono disegnati, …».

### D2. The delegate's re-check accepts either delimiter character, never a mix

`stillSpellsAnEmphasisMarker` answers true for one or two of the same character, when that character
is `*` or `_`. A mixed `*_`, three characters, or anything else stays refused, so a stale entry over
prose still collapses nothing (`MarkupHidingTests.aStaleEmphasisEntryDoesNotCollapseProse`). This is
the change that makes D1 visible. Without it, the D1 change alone is green in the corpus and
conceals nothing on screen. The card inherits D1 and D2 with no change of its own.

### D3. The corpus classes the move as deliberate

`StylerGoldenTests` moves for every corpus input holding a `_` run the parser accepts: on
`54cf47e7`, `E25` and `S35`. It gains `.emphasisMarker` and `hidden … emphasis` lines and their
`order` lines. A captured string is never edited (ADR-0082 §D3).

- A case still `.unchanged` that moves becomes `.deliberate` (class B), citing this record.
- A case already classed keeps its class. `E25` and `S35` are `.fix`, class A, for the intraword
  rule. Each has its `expected` reprinted from the new styler and its reason extended by one
  sentence citing this record.
- Any difference other than `_` delimiter lines is a C and blocks the merge.

### D4. Oggi and Diario pass a transclusion source, from one factory

The body of `EditorColumnView.transclusionSource` moves, unchanged, into
`TransclusionSource.live(for:)` in `Sources/Features/Editor/TransclusionSource+Live.swift`. That
file mirrors `ViewQuerySource+Live.swift`. Its generation stays
`EditorColumnView.transclusionGeneration(for:)`, which `IndexGenerationFollowUpTests` reads. The
column's property forwards to the factory. `TodayView` and `DiaryView` pass
`transclusions: .live(for: vault)` beside the `queries:` they already pass. A transcluded note in
those panes therefore resolves by the lookup the Note pane uses (ADR-0010 §D2/§D3: a `.md` path,
otherwise a title through the index). Its source line becomes the caption (ADR-0087 §D10), and a
click follows it through the pane's own `onFollowLink`:

- in Oggi, `commandActions.open(link:from:)`;
- in Diario, `follow(_:)`, which flushes the day first (ADR-0083 §D5).

Depth stays one (ADR-0010 §D6), so a daily note that transcludes itself draws one row. The doc
comment that still says the daily panes pass no `queries` (`NoteTextView+ViewBlocks.swift:241`) is
corrected, along with the `transclusions` input's own comment (`NoteTextView+Inputs.swift:114-116`).

### D5. The keystroke budget does not move, and the plan says why

- **D1 and D2** change a per-token constant: the same two appends a `*` run already pays, and a
  per-marker character test instead of a fixed one. No pass, scan or allocation is added. The
  budget's synthetic note (`RestyleBudgetSupport.swift:117-136`) holds no `_` run, so its styled
  output is byte-identical, and the six ceilings (ADR-0082 §D9) are neither re-measured nor edited.
  A red `EditorRestyleBudgetTests` after this change is a finding to report, never a ceiling to
  raise.
- **D4.** The transclusion scan already runs on every pass in both panes. A source adds resolution
  only for occurrences in the dirty range (ADR-0091 §D7), or for all of them when the index
  generation moves, which happens on a write and never on a keystroke (ADR-0072 §D11). The factory
  reads `vault.indexGeneration` at construction, which both pane bodies already observe through
  `ViewQuerySource.live(for:)`. So the SwiftUI path of a keystroke gains no observation and no term
  proportional to the note (ADR-0096).

### D6. Tests are unit and in-process tests; there is no GUI test

- D1 to D3 are proven by pure styler tests, by the shared delegate's substitution hook driven
  directly (`MarkupHidingFixture`), and by a hosted note editor and a hosted card. The two pinned
  tests that assert the old behaviour are restated, with the reason said first (CLAUDE.md).
- D4 is proven by the factory over a `TemporaryVault`, by a hosted `NoteTextView` given it, by an
  incremental-versus-full twin built as the panes build their editor, and by source guards on
  `TodayView.swift`, `DiaryView.swift` and `EditorColumn+Text.swift`.
- The panes themselves are checked by hand on the Debug build, because they cannot be hosted
  (ADR-0053). No GUI test is added, so none needs justifying here.

## Alternatives considered

- **Keep `_` visible (ADR-0082 §D2 as it stands).** The reason ADR-0018 gave for the narrowing no
  longer holds, SPEC §5 already names `_`, and the person asked for the change. Rejected.
- **A stricter styler-side boundary check before concealing a `_`** (say, whitespace or punctuation
  on both outer sides). This is a second recogniser, which ADR-0082 §D2 rules out: the parser
  already applies the intraword rule at both ends. A styler that disagreed with it would bring back
  the editor-versus-export drift `PG-347` was. Rejected.
- **A separate `HiddenMarker.Kind` for `_`.** It would need an answer in every exhaustive switch
  (`isInline`, `stillSpells`, both `hiddenKind` tables, `InlineSpanRevealFenceTests`' arm count) and
  would behave the same as `.emphasis`. Rejected for D2's one-line widening of the existing check.
- **Drop the character test from the emphasis re-check.** It would accept any one or two characters
  and collapse prose on a stale entry, the defect the check exists to prevent. Rejected.
- **A setting for `_` concealment.** No requirement asks for one, and `hidesMarkup` is already the
  switch for all concealment. Rejected.
- **Oggi and Diario build their own `TransclusionSource` inline.** That is two copies of a
  resolver that ADR-0010 §D3 requires to agree with the wikilink lookup, and they could drift.
  ADR-0082 §D8 rejected the same shape for `queries`. Rejected.
- **`NoteTextView` builds a default source when none is given.** The editor holds no vault, by
  design (ADR-0007; `VaultInputs` defaults to nil). A default would also reach the Workspace card
  and the design gallery, which pass nothing on purpose. Rejected.

`BRAINSTORM.md` and `UX-BLUEPRINT.md` do not exist for this work.

## Consequences

**Positive.**

- `_a_` and `*a*` look the same at rest and reveal the same way in the note editor, Oggi, Diario and
  a Workspace text card, as SPEC §5 says.
- Oggi and Diario draw `![[Nota]]` as the Note pane does, so the three editor hosts take both vault
  sources from the same two factories.
- Because `[[Nota#` completion resolves through the same transclusion source, Oggi and Diario now
  also offer a note's sections after `#`, as the Note pane does.
- ADR-0082's two named follow-ups are closed.

**Negative.**

- A `_` run that the shared grammar accepts is now concealed wherever it is written outside code.
  Some examples:
  - `__init__` in prose draws as a bold «init», when today it is bold with visible underscores;
  - a wikilink whose title is wrapped in underscores, `[[_bozza_]]`, shows «bozza», since a
    wikilink's interior is scanned for emphasis (issue #188);
  - a bare URL with a `/_x_/` path segment shows the segment italic.

  Each matches what `*` already does and what the HTML export already renders. Intraword names
  (`nome_file_lungo`, `20260811_Pergamenum_SpecApp`) are untouched. The way out is the same as for
  `*`: backticks.
- In Diario, every save of the day moves the index generation, so every transclusion in the day is
  resolved again on the next pass (a file read each, cached per generation). This is the bargain
  the Note pane already makes for its own note (PG-328).
- The panes' parity rests on source guards and a hand check, not on a hosted pane.

**Neutral.**

- No file format, `Span` case, `HiddenMarker.Kind`, schema, protected interface or consumer
  signature changes.
- The HTML export, the reading views and the connectors are untouched. `MarkdownStyler` and the
  delegate are app-only, outside `sharedSources`.
- A transcluded picture, which draws its source styled but unconcealed, shows `_` delimiters in the
  marker grey as it already shows `*`.
- SPEC (app) §5 is not amended: it already says `_`.
- The «Modifica query» control stays absent from the daily panes (ADR-0082 §D8).

## Gates

- **G-tests:** the restatement of `MarkdownStylerTests.underscoreEmphasisHasNoMarkerSpan` and
  `StylerSharedGrammarTests.anUnderscorePairIsItalicAndItsDelimitersStayVisible`, and the inputs of
  `IncrementalRestyleSurfacesTests.aDailyPaneEditorWithNoFlagSetTakesTheIncrementalPath`, each with
  its reason stated in chat before the edit.
- **G-corpus-427:** the person reads the moved corpus cases (D3) before the merge. A C blocks it.
- **G-hand-427/428** on the Debug build, with Stefano:
  - `_a_`, `__a__`, `*a*` and `nome_file_lungo` at rest and under the caret, in a note, in Oggi, in
    Diario and in a Workspace text card, with «Rivela solo la parola sotto il cursore» off and
    then on;
  - a `![[Nota]]` and a `pergamenum-view` fence in Oggi and in Diario, each drawn, the fence with no
    «Modifica query».

## Implementation notes

Written at the code PR, from the build of 2026-10-30. The G-hand answers and the merge evidence for
the status line are still to come: the status stays `proposed` until the merge.

**Files touched.**

- §D1/§D2 (PG-427):
  - `Sources/Features/Editor/MarkdownStyler.swift`: `starMarker` is gone, and the `.strong` and
    `.emphasis` arms pass `.emphasisMarker` for either delimiter, so `run(…markedBy:)` takes a
    non-optional marker;
  - `Sources/Features/Editor/EditorDecorationDelegate.swift`: `stillSpellsAnEmphasisMarker`
    accepts one or two copies of the same character, `*` or `_`;
  - `Sources/Features/Settings/EditorSettings.swift`: the caption names `*` or `_`;
  - `Tests/StylerGoldenChanges.swift`: `E25` and `S35` (§D3, below).
- §D4 (PG-428):
  - `Sources/Features/Editor/TransclusionSource+Live.swift` (new): `TransclusionSource.live(for:)`
    holds the body that was `EditorColumnView.transclusionSource`;
  - `Sources/Features/Editor/EditorColumn+Text.swift`: forwards to `.live(for: vault)`;
  - `Sources/Features/Today/TodayView.swift`, `Sources/Features/Diary/DiaryView.swift`: pass
    `transclusions: .live(for: vault)`;
  - `Sources/Features/Editor/NoteTextView+Inputs.swift`,
    `Sources/Features/Editor/NoteTextView+ViewBlocks.swift`,
    `Sources/Features/Editor/TranscludedNoteView.swift`: doc comments only.
- Tests: `Tests/UnderscoreEmphasisConcealmentTests.swift`,
  `Tests/DailySurfaceTransclusionsTests.swift` and `Tests/UnderscoreAndTransclusionCoverageTests.swift`
  (new); `Tests/MarkdownStylerTests.swift`, `Tests/StylerSharedGrammarTests.swift` and
  `Tests/IncrementalRestyleSurfacesTests.swift` (restated, G-tests);
  `Tests/DailySurfaceQueriesTests.swift` (comment only).

**The corpus (§D3).** Two cases moved, `E25` and `S35`. Both were already `.fix` (class A, the
intraword rule) and stay so: each `expected` is reprinted from the new styler and each reason gains
one sentence citing §D1. Every moved line is a `_`/`__` `emphasisMarker`, a `hidden … emphasis` or an
`order` line. No other case moved: zero B, zero C.

**Red, then green.**

- Task 1 (PG-427): 12 red tests, all green after Task 2; the narrow run passed 220 tests in 19
  suites.
- Task 3 (PG-428): 7 red tests, all green after Task 4; the narrow run passed 23 tests in 4 suites.
- G-tests, the two renames that reverse ADR-0082 §D2's rule:
  `MarkdownStylerTests.underscoreEmphasisHasNoMarkerSpan` is now `underscoreEmphasisHasTwoMarkerSpans`,
  and `StylerSharedGrammarTests.anUnderscorePairIsItalicAndItsDelimitersStayVisible` is now
  `anUnderscorePairIsItalicAndItsDelimitersAreConcealable`.
- One red-phase test, `DailySurfaceTransclusions.aProseKeystrokeKeepsTheRenditionAndTheIncrementalPath`,
  read a caret offset taken before the keystroke. It now recomputes the offset after the keystroke
  and asserts it equals `lineStart + 1`, which is stricter than before.

**The budget (§D5).** The ceilings in `Tests/RestyleBudgetSupport.swift` were not touched, and
`EditorRestyleBudgetTests` was not edited.

## References

- ADR-0018 §D1/§D2, ADR-0010 §D2/§D3/§D6, ADR-0037 §D2/§D4/§D5, ADR-0053, ADR-0072 §D11,
  ADR-0077 §D5, ADR-0081, ADR-0082 §D2/§D3/§D8/§D9 and its implementation notes, ADR-0083 §D5,
  ADR-0087 §D10, ADR-0091 §D7, ADR-0096.
- `docs/plans/pg-385-n2-page.md` (SPEC decisions registered: "`_` emphasis stays unconcealed",
  "Oggi and Diario share one query-source factory"; follow-ups at Task 8 item 8).
- `Sources/Features/Editor/MarkdownStyler.swift:23-27, 390-436`,
  `Sources/Features/Editor/EditorDecorationDelegate.swift:786-790, 869-875`,
  `Sources/Core/Markdown/MarkdownInline+Emphasis.swift:24-75`,
  `Sources/Features/Editor/EditorColumn+Text.swift:281-310`,
  `Sources/Features/Editor/ViewQuerySource+Live.swift`,
  `Sources/Features/Editor/NoteTextView+Transclusion.swift:149-221, 303-336`,
  `Sources/Features/Settings/EditorSettings.swift:90-101`,
  `Sources/Features/Today/TodayView.swift:213-249`, `Sources/Features/Diary/DiaryView.swift:107-140`.
- `docs/20260811_Pergamenum_SpecApp.md` §5.
