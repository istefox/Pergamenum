# ADR-0087: The editor draws the remaining constructs

- Status: **planned**. Written before the implementation (milestone N5 of the note-workflow
  chain, issue #890). Flip to `accepted` with the merge commit of N5's code PR, per
  `docs/adr/README.md` rule 2.
- Date: 2026-10-04. Written against `48a2d912` (`origin/main` at the same commit). Every line
  number below was read there. N5 is built last: by the time its code lands, N1 (ADR-0080) and N2
  (ADR-0081, ADR-0082) are on `main`, and N2 will have rewritten `MarkdownStyler.spans(in:)` over
  the shared parsers. Line numbers in `Sources/Features/Editor/MarkdownStyler.swift` and
  `EditorDecorationDelegate.swift` will have moved; the decisions below name types and functions,
  not lines, wherever N2 can move them.
- Number: `0087` was reserved for this record by the chain's dispatch and checked free on every
  ref on 2026-10-04 (`git log --all -- 'docs/adr/0087*'` printed nothing). Check again
  immediately before the merge (`docs/adr/README.md` rule 1).
- Source: the root `SPEC.md` (Approved 2026-10-04), milestone N5, R-35 to R-43; background in
  `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 "N5" and
  `docs/20261002_Pergamenum_NoteWorkflowReport.md` R-3 to R-7 and R-10. Plans:
  `docs/plans/note-workflow-n5-mockup.md` (the mockup PR, first) and
  `docs/plans/note-workflow-n5.md` (the code PR).
- **Extends** ADR-0029 §D1 (the constructs the editor draws in place of their syntax) to
  constructs no surface drew before: highlights, callouts, nested quotes in the reading view, and
  the chrome of inline code, fences, embeds, transclusions, tables, tags and dates. **Extends**
  ADR-0078 (a second producer of folded lines on the shared hidden-line set), ADR-0037 (two more
  inline kinds on the span-grained reveal) and ADR-0023 §D1 (one catalogue for the table column
  menu). **Amends** ADR-0029 §D1's blockquote bullet (the `▏` substitution gives way to a
  full-height bar, §D7) and ADR-0077 §D4 (the export's closed element set gains `mark` and
  `aside`, and `aside` one fixed-vocabulary `class`, §D12). **Amends** SPEC (app) §5's list of
  constructs that hide their syntax (§D1).
- Depends on: ADR-0082 (the styler classifies through `MarkdownBlockParser` and
  `MarkdownInlineParser`, so a construct added there reaches the editor), ADR-0081 (the quote
  content column a revealed `>` hangs left of) and N1's R-07 (Cmd+click on a `#tag` or a `>date`).
- No on-disk format change, no frontmatter key, no `IndexCache.schemaVersion` bump, no
  protected-interface change. `CompletingTextView+Pasteboard.swift` (protected as a whole) is not
  edited: every new click and menu hook goes through a closure or a delegate method it already
  calls (§D6, §D8, §D9).

## Context

### What the SPEC already settled (registered here, not reopened)

- **Callout keywords.** The app writes the English type keywords `note`, `tip`, `important`,
  `warning`, `caution`; it reads the Italian names `nota`, `suggerimento`, `importante`, `avviso`,
  `attenzione` as aliases; the interface labels the five in Italian; any other type is read as a
  callout and drawn neutral. The roadmap's "Italian keywords in the file" was rejected by the
  SPEC because it contradicts the roadmap's own "the file stays readable elsewhere". §D3 records
  this decision; it is not re-decided here.
- **Clickable dates are the `>YYYY-MM-DD` scheduling tokens**, with or without an hour. A bare ISO
  date in prose is not a date chip and not a link.
- **No GUI tests in N5.** Hosted-view tests (the in-process family) and pure unit tests carry the
  acceptance; the SPEC's GUI cap (three in N3, two in N4) leaves N5 at zero.
- **Mockups first, as their own PR**, approved on the Debug build before any view code (SPEC
  §11.1). The token names are fixed in that PR.
- Constraints: the file never changes shape; concealment keeps the character count and a line
  that must look different is drawn by a layout fragment; one grammar, with new constructs entering
  the shared parsers first; tokens only, each new key in both theme files; no index schema change
  and no protected-interface change.
- Edge cases: `==` inside a code span is not a highlight; a fence body stays editable while its
  header is drawn; an unknown callout type renders neutral; a folded callout's body hides through
  the shared hidden-line set (ADR-0078).

### What the code draws today (measured at `48a2d912`)

- **Inline code** is a `.code` span coloured `color.text.secondary` in `font.mono`, with no
  background and its backticks visible (`MarkdownAttributedText.swift`). No `==highlight==`
  exists anywhere: `MarkdownSpan.Style` is `strong`, `emphasis`, `code`, `strikethrough`
  (`MarkdownInline.swift:9-14`).
- **Fences** are coloured by `CodeSyntax` and their fence lines stay as written. `CodeFence`
  (`Sources/Core/Markdown/CodeFence.swift`) knows the regions, the body and the language, but
  nothing draws a header.
- **Quotes**: the editor substitutes each `>` with `▏` (U+258F), character for character
  (`EditorDecorationDelegate+QuoteRendering.swift`, ADR-0029 §D1). The bar is a glyph, so it is
  drawn on the first visual line of a wrapped paragraph only. The shared parser loses nesting:
  `MarkdownBlock.quote([String])` drops one `>` and keeps `> x` as text for `>> x`
  (`MarkdownBlocks.swift:198-199`), so the reading view (`MarkdownBlocksView.quoteView`, one 3 pt
  bar in `color.border.strong`) and the export (`<blockquote><p>…</p></blockquote>`) both flatten
  a nested quote.
- **Callouts** are parsed by nothing. `EditorCommand.editorEntries` excludes them on purpose
  (`EditorCommand.swift:41-45`), because a slash entry producing something the app draws as a plain
  quote would be a promise the app did not keep.
- **Embeds**: a whole-line `![[file]]` of an image or a PDF is drawn by an `EmbedAttachment` once
  `ThumbnailStore` answers; until then `EmbedRendition` is nil and the raw text shows, so the line
  jumps when the picture arrives. A non-renderable type (`isRenderableType`, image or PDF only)
  stays raw text forever, and an inline `![[x]]` is an `.embedTarget` span styled as a link.
- **Transclusions**: the source line `![[Nota#Sezione]]` stays raw, and `TranscludedLineFragment`
  draws a header caption («Nota › Sezione») under it, then the body, in height bought through
  `paragraphSpacing`.
- **Tables**: `GFMTable` parses and applies column alignment, but nothing changes it, and nothing
  sorts. Every structural edit goes through `TableEdit.applied(to:)` and `commitTable`, which
  rewrites the whole table in its canonical serialisation in one undoable replacement.
- **Tags and dates** are coloured spans (`color.accent.primary`, `color.task.scheduled`) with no
  shape.

### Forces

- The substitution may not change a paragraph's length (`NSTextContentManager.h`'s constraint,
  ADR-0028). A header, a caption, a card edge or a full-height bar is therefore drawn by a
  fragment, never by characters.
- `NoteTextView+Coordinator.swift`, `EditorDecorationDelegate.swift` and `MarkdownStyler.swift`
  are already past SwiftLint's `file_length` warning; new logic goes in `Type+Aspect.swift` files.
- `CompletingTextView+Pasteboard.swift` owns `mouseDown(with:)` and `menu(for:)` and is protected
  as a whole. Its existing claimants (`onEmbedResize`, `onClickInMargin`, `onToggleCheckbox`,
  `onEmbedMenu`, then `super`) are the only doors.
- ADR-0047 §D11 retired the Obsidian round-trip as an obligation. What still holds is principle 4's
  "the formats underneath are ordinary ones", which is why the callout syntax is GitHub's and
  Obsidian's spelling rather than an invented one.

## Decision

**D1. Scope: the editor draws seven more constructs, every change display-only, and SPEC (app) §5
says so.**

The constructs are inline code, highlights, fences, callouts, quotes, embeds and transclusions,
plus the table column menu and tag and date chips. Nothing new is written to a file by drawing.
Two gestures write, and both through paths that already write: the table column menu (alignment
and sort) commits a `TableEdit` through `commitTable`, and the slash entry «Callout» inserts text
at the caret. ADR-0029 §D1 retired the "three named constructs" boundary; this decision adds to
the list it left open and does not restore a boundary.

SPEC (app) §5's bullet «Costrutti che nascondono la loro sintassi» gains, in Italian, the code pill
(backticks hidden), the highlight (`==` hidden), the fence header with language and line count
and the quiet closing line, the callout card (keywords in English, aliases in Italian, labels in
Italian, foldable with `-`/`+`), the quote bar at full height with an indent per level, the embed
chip and the reserved placeholder, the transclusion caption, and the tag and date chips. Its
«Una tabella GFM è una griglia vera» bullet gains the column menu.

**D2. One grammar: highlights, nested quotes, callouts, fence chrome and the transclusion caption
enter `Sources/Core/Markdown` first.**

- `MarkdownSpan.Style` gains `highlight`. `==` opens like `~~` does (`emphasisMarker`): never
  followed by whitespace, closed by the next `==` that is not preceded by whitespace. Code spans are
  matched first, as today, so `` `a==b==` `` is code and stays code (the SPEC's edge case).
  `a == b` opens nothing.
- `MarkdownBlock.quote` changes from `[String]` to `[QuoteLine]`, where `QuoteLine` is
  `level` plus `text`. The level is the number of `>` in the line's opening run, each optionally
  followed by spaces (CommonMark's rule, so `>> x` and `> > x` are both level 2). A level-1 quote's
  texts are exactly today's strings, so the export of a single-level quote keeps its bytes (E06).
- `MarkdownBlock` gains `callout(Callout)`. A callout is a quote run whose first line, at level 1,
  reads `> [!type]`, optionally followed by `-` or `+`, then optionally a space and a title. Its body
  is the rest of the run, with each line's level reduced by one (level 0 is the callout's own
  text). A `[!type]` on a deeper line is quote text, not a nested callout. One parser function,
  `Callout.header(inLine:)`, recognises the title line and reports the marker's UTF-16 length, so
  the editor conceals exactly what the parser recognised.
- `FenceChrome` describes each **closed** fence (opening line, closing line, body, declared
  language, body line count). `pergamenum-view` fences are excluded: they are view blocks
  (ADR-0033) and draw their own way. An unclosed fence gets no chrome, for the reason ADR-0033 §D6
  gave view blocks: typing the opening backticks must not restyle the rest of the note mid-keystroke.
- `TransclusionCaption.text(note:section:)` spells «da «Nota» › Sezione» («da «Nota»» with no
  section), read by the editor's caption and by the export.

Contract changes and their call sites (grepped at `48a2d912`): `.quote(` is matched at
`MarkdownBlocks.swift:227`, `MarkdownHTML.swift:59`, `MarkdownBlocksView.swift:61` and
`Tests/MarkdownReadingTests.swift:77`. The two exhaustive switches over `MarkdownBlock` are
`MarkdownHTML.html(for:)` and `MarkdownBlocksView`'s block switch;
`Tests/NoteOutlineTests.swift:145` and `ViewBlock.blocks(in:)` use `default`/`guard case` and are
unaffected. `MarkdownSpan.Style` has no exhaustive switch.

**D3. Callouts write English keywords and read Italian aliases (the SPEC's decision, recorded).**

`CalloutKind` is `note`, `tip`, `important`, `warning`, `caution` or `other(String)`.
`CalloutKind(keyword:)` is case-insensitive, so GitHub's `[!WARNING]` reads as `warning`. It maps
`nota`, `suggerimento`, `importante`, `avviso` and `attenzione` to the same five cases, and
anything else to `other` with the type as written. `keyword` is what the app writes, `label` is
what the interface shows («Nota», «Suggerimento», «Importante», «Avviso», «Attenzione»; for
`other`, the written type with its first letter capitalised). The app never rewrites a keyword
that is already in a file: a `[!avviso]` stays `[!avviso]` on disk and is drawn as `warning`. The
only writer is the slash entry, and it writes `> [!note] `.

**D4. Eight colour tokens, both themes, fixed in the mockup PR; everything else reuses a token
that exists.**

The new keys are `color.code.inlineBackground`, `color.highlight`, `color.quote.bar` and
`color.callout.note`, `.tip`, `.important`, `.warning`, `.caution`. They are added to both bundled
theme files, to `ColorToken` and to `Theme.emergency` (the PG-225 contract: a token missing from
the emergency palette crashes `rawColor`). They land in the mockup PR, so the mockup draws through
the real tokens. The gallery has no colour literals, so a mockup drawn before the tokens exist
would not be the design being approved.

- A callout card's background is its type colour at one fixed opacity, named once
  (`CalloutStyle.backgroundOpacity`, 0.08), the precedent of the transclusion rule's
  `withAlphaComponent(0.35)` on a token. The type colour itself draws the bar, the icon and the
  title.
- An unknown type draws neutral from existing tokens: `color.quote.bar` for bar, icon and title,
  `color.surface.sunken` for the card.
- The tag chip's background is `color.accent.muted`; its namespace is `color.text.secondary` and
  its value `color.accent.primary`, as R-42 says. The date chip's background is
  `color.surface.sunken`, with the `>` in `color.text.secondary` and the date in
  `color.task.scheduled`. Neither chip adds a key.
- Binding thresholds, asserted by the token test rather than by eye:
  - each callout colour is at least 4.5:1 against `color.background.primary` and against its own
    card (the title is text);
  - `color.quote.bar` is at least 3:1 against `color.background.primary` (non-text, WCAG 2
    §1.4.11, the rail tokens' rule from ADR-0079);
  - `color.text.secondary` on `color.code.inlineBackground` and `color.text.primary` on
    `color.highlight` are each at least 4.5:1.

**D5. A pill or a chip is drawn behind the text by one painter. The text stays text, and the room
for padding is made with `.kern`, never with characters.**

- Inline code, highlights, tags, dates and inline embeds are chips: a rounded background
  (`radius.control`) behind a character range. A custom attribute on the substituted paragraph
  marks the range and its colours. `InlineChipPainter` turns it into one rect per line fragment
  the range crosses and paints it before the glyphs.
- Every fragment class the delegate returns calls the painter: a new `ChipLineFragment`, which
  replaces the standard fragment when a paragraph carries chips, and `FoldedHeadingFragment`,
  `QuoteBarFragment` and `CalloutTitleFragment`. A heading or a quote with inline code in it is
  therefore not left without its pill.
- Padding comes from `.kern` on the concealed delimiters, or on the characters on each side when
  nothing is concealed (a tag). The character count never changes, and the find bar, the
  selection and VoiceOver still read the file's own text.
- Inline code's backticks and a highlight's `==` are concealed off the caret by two new inline
  `HiddenMarker` kinds, `.inlineCode` and `.highlight`. ADR-0037's span-grained reveal applies to
  them when its setting is on, paragraph-grained otherwise.
- A tag's split is `#` plus the namespace and its `-` (secondary), then the rest (accent). A tag
  outside SPEC §4.4's namespaced pattern draws whole in the accent. A date chip keeps its `>`
  visible: it is the scheduling sigil of SPEC §7.1, and concealing it would buy nothing a colour
  does not already say. N1's Cmd+click targets ride on the same ranges and are unchanged.

**D6. A fence's opening and closing lines are drawn by one fragment class, revealed on the caret.
The body never leaves the layout, and «Copia il blocco» goes through the text view's delegate.**

- The opening and closing lines of each `FenceChrome` get two new block `HiddenMarker` kinds,
  `.fenceOpening` and `.fenceClosing`. Their characters are collapsed on the generic path and the
  line is drawn by `CodeFenceFragment`. In its header role it draws a language badge (the declared
  language as written, none when undeclared) and «N righe» / «1 riga». In its closing role it
  draws a quiet rule.
- Both re-validate against the element's own characters (`CodeFence.marks`), the rule's shape
  (`HorizontalRuleFragment`). The caret on either line reveals that line, paragraph-grained.
  Body lines carry no marker and stay editable (the SPEC's edge case).
- «Copia il blocco» is added to the editor's ordinary context menu by
  `NSTextViewDelegate.textView(_:menu:for:at:)` on the coordinator. `CompletingTextView.menu(for:)`
  is protected and reaches `super.menu(for:)` whenever `onEmbedMenu` answers nil, which is where
  AppKit asks the delegate. The item copies `FenceChrome.body`, fences excluded, to the general
  pasteboard as plain text. Workspace cards draw no fence chrome: `CardTextView.hiddenKind`'s
  `default: nil` (ADR-0029 §D17) already says so.

**D7. A quote is indented per level and drawn in the secondary text colour beside a full-height
bar per level. The `▏` substitution gives way to a fragment.**

- The `>` run is collapsed instead of substituted. The paragraph style indents the content by one
  step per level. The step is the quote content column ADR-0081 fixes; if ADR-0081 fixes none,
  it is `spacing.m`. Both states (concealed and revealed) keep the content's origin, R-14's rule,
  which N2 owns.
- `QuoteBarFragment` draws one bar per level in `color.quote.bar`, over the fragment's full height
  paragraph spacing included, so consecutive quoted lines draw one unbroken bar. The text is
  `color.text.secondary`.
- `QuoteGeometry` is the one place the indent and the bar positions are computed, read by the
  editor and by `MarkdownBlocksView`. The reading view draws the same nesting from `QuoteLine.level`.
- This amends ADR-0029 §D1's blockquote bullet. A glyph per `>` cannot span a wrapped paragraph,
  which is what "full-height" asks for.
- Pratiche message and entry rows render through `MarkdownBlocksView`, so a quoted reply chain in
  an email body gains its nesting there too.

**D8. A callout is a card drawn by fragments. Its fold is transient per tab, on the shared
hidden-line set, and never written.**

- **Title line.** `> [!type]` with its sign and one space is collapsed by a new block kind,
  `.calloutMarker`. `CalloutTitleFragment` draws the card's top: the icon (an SF Symbol per kind),
  the title (or the Italian label when the line names none) in the type colour, and a chevron when
  the callout is foldable.
- **Body lines.** They are quote lines whose bar and card band take the type colour.
  `QuoteBarFragment` paints the card band per line, one piece each (`first`, `middle`, `last`,
  `only`), so the card's rounded corners sit on its first and last lines. This is ADR-0079's
  rail-piece shape.
- **Fold state.** A callout without a sign is not foldable. `-` starts folded and `+` starts open.
  `NoteTab.toggledCallouts` holds the title-line offsets whose state the person flipped in this tab,
  keyed and carried exactly as `NoteTab.foldedEntries` is. It is not written to the file, because
  rewriting `-` to `+` would dirty the note for a look.
- **Hiding.** `CalloutFold.hiddenLines(in:toggled:)` returns the body lines of every folded
  callout. `FoldController.apply` unions them into `hiddenLineOffsets`, the set ADR-0078 already
  shares between folded headings and the frontmatter. `CaretRescue` moves a caret out of hidden
  lines as it does for a heading.
- **Click.** A click on the chevron toggles the fold through the `onClickInMargin` chain
  (`toggleCallout`, after `unfold`), then `VaultController.toggleCallout(_:)`. The Diario and Oggi
  editors pass no toggle and draw each callout in its file's default state.
- **Reading view.** `MarkdownBlocksView` draws a callout as the same card, always open: it is
  read-only and has no tab to remember a fold.
- **Workspace cards.** The title line is coloured in its type colour and nothing else changes
  (R-38). `[!type]` stays as written in a card.
- **Slash menu.** One entry, «Callout», inserts `> [!note] `, and the exclusion comment in
  `EditorCommand.swift` goes. The app now draws what the entry writes.

**D9. An embed reserves its size before its picture arrives. An inline or non-renderable embed is
a chip that opens Quick Look on a click.**

- `EmbedRendition` gains `pending`. While `ThumbnailStore` has not answered, an `EmbedAttachment`
  is drawn at `EmbedPlaceholder.size(written:column:)`: the written `|WxH`, or `|W` at a default
  ratio, or a default box, each clamped to the column through `EmbedResize`'s existing clamp. The
  picture then replaces a box of the same width.
- A pending or chip embed gets no resize handle (ADR-0019 §D8's `guard case .drawn` already
  refuses). ADR-0019's handle and its `|W` writing are untouched.
- `EmbedPresentation` decides how a file target draws. A whole-line image or PDF is `drawn`, as
  today. Any other file type on its own line, and every inline file embed, is a `chip`: an icon
  for its uniform type plus its name, the `![[`, `|W` and `]]` concealed by a new inline kind,
  `.embedChip`. A note target stays a transclusion.
- A plain click on a chip, off the caret, previews the file through the same Quick Look route the
  embed's «Anteprima» already uses (`previewURLs` in `EditorColumn+Text.swift`), claimed in the
  `onClickInMargin` chain. When the caret is in the paragraph the chip is raw text, and a click
  places the caret, as a drawn embed's line does.

**D10. A transclusion's source line becomes its caption.**

- When a transclusion has a rendition and its line is not revealed, the source line's characters
  are collapsed, and `TranscludedLineFragment` draws «da «Nota» › Sezione»
  (`TransclusionCaption`) in that line's own row.
- The rendition's separate header caption is removed, and `reservedHeight` drops by its height.
- A click on the caption opens the note, as the header did. The caret on the line reveals
  `![[Nota#Sezione]]`. An unresolved transclusion keeps today's drawing.

**D11. A table column's menu sets its alignment and sorts its rows, each as one `TableEdit`
through `commitTable`.**

- `TableEdit` gains two cases:
  - `align(column:_:)` replaces one entry of `alignments`. Setting the alignment a column already
    has is not an edit.
  - `sort(column:ascending:)` reorders the body rows by that column. The order is
    `localizedStandardCompare`, which sorts numbers by value. Empty cells go last in both
    directions, the sort is stable, and the header is untouched.
- Both commit through `commitTable` like every structural edit. That makes each one a single
  replacement and a single undo step, guarded by ADR-0029 §D8's re-read.
- They write the table's canonical serialisation, ADR-0029's existing rule for every structural
  edit. For a table already in that form, an alignment change differs only in its delimiter row.
- The menu is one catalogue, `TableColumnMenu.entries(current:)` (ADR-0023 §D1's shape). It is
  shown from a new column control beside the add/remove column buttons and from a right-click on a
  header cell.

**D12. The export agrees with the editor on what each construct is, not on its editing chrome.**

- `==x==` exports as `<mark>x</mark>`. The wrap order becomes `code`, `mark`, `del`, `em`,
  `strong`.
- A callout exports as `<aside class="callout-<kind>">`, where `<kind>` is one of six fixed values
  chosen by the app (`note`, `tip`, `important`, `warning`, `caution`, `other`), never text from
  the note. It holds a `<p><strong>` title (the written title, else the Italian label) and then its
  body. A folded callout exports open.
- A nested quote exports as nested `<blockquote>`, and a level-1 quote keeps today's bytes.
- A transclusion exports its caption text (E15 changes from `<p>Altra nota</p>` to
  `<p>da «Altra nota» › Sezione</p>`, re-captured and reasoned in the corpus).
- Fences, inline code, embeds, tags, dates and tables export as today. The language badge, the line
  count, «Copia il blocco», the chips and the fold are interaction, and ADR-0077 §D4's closed set
  has no element for a chip.
- This amends ADR-0077 §D4 by two elements and one attribute: still no resource, no `src`, no
  script. The export stylesheet in `NoteExport.html` gains rules for `mark` and the six `aside`
  classes in literal hex, copied from the light theme the way the existing `blockquote` rule's
  colours are.
- Golden cases N01 onward pin every construct of R-36 to R-42, each with a reason. Cases whose
  bytes equal today's are marked unchanged.

**D13. Acceptance is pure tests, hosted tests and the corpora. No GUI test.**

- Parser, callout, highlight, fence-chrome, caption and table-rewrite rules are pure unit tests.
- N2's styler golden corpus gains N5's constructs, the export corpus gains its cases, and the
  token test asserts §D4's thresholds.
- Drawing is pinned in process: the fragment class at each construct's offset, the paragraph-length
  invariant in every new substitution branch (`EditorDecorationSubstitutionTests`'s rule), reveal
  on the caret, the fold through `shouldEnumerate`, the menu item and its pasteboard text, a
  table edit undone in one step, and the placeholder's reserved size.
- The roadmap's acceptance note is checked by hand on the Debug build in light and dark:
  inline code, a `swift` fence, `> [!avviso]-`, `==highlight==`, a nested quote, an inline
  `![[scheda.pdf]]`, a transclusion and a right-aligned column.

## Alternatives considered

- **Italian keywords in the file** (the roadmap's wording, `> [!avviso]` written by the app).
  Rejected by the SPEC: the type keywords are a shared spelling (GitHub, Obsidian), and principle 4
  keeps the formats ordinary. Reading the Italian names as aliases costs one table and keeps every
  hand-written `[!avviso]` working.
- **Reading only the five English keywords.** Rejected: a note written by hand in Italian, the
  vault's own language, would draw neutral for no reason the person could see, and the aliases are
  one dictionary.
- **A surface token per callout type** (`color.callout.noteSurface` and four more, the
  `surface.entryNote`/`entryCall` precedent). Rejected: ten keys whose pairs must be retuned
  together in every theme, including a person's own under `.pergamenum/themes/`. One opacity
  derived from the type colour keeps the pair in step by construction. The cost is a card tint the
  theme cannot set independently. A theme that needs it later adds the keys then, and that is an
  addition, not a migration.
- **Keeping the `▏` substitution for quotes** (ADR-0029 §D1 as written). Rejected: a glyph sits on
  the first visual line of a wrapped paragraph only, and R-39 asks for a full-height bar. The
  substitution's one advantage, unbounded depth from the characters, is kept: the fragment reads
  the level from the live characters the same way.
- **Writing the callout fold to the file** (toggling `-`/`+` on a chevron click). Rejected: a look
  would dirty the note, raise the quit review and the conflict prompt, and contradict the
  "display-only" constraint. ADR-0078 and `NoteTab.foldedEntries` already chose transient state for
  the same kind of choice.
- **«Copia il blocco» through `onEmbedMenu`** (answering a fence's own menu from the existing
  closure). Rejected: a non-nil answer replaces the editor's ordinary menu, which loses copy, paste
  and spelling, the regression ADR-0023 §D9 warns about. Editing `menu(for:)` itself is excluded
  because the file is protected. The delegate method adds one item to the ordinary menu.
- **Chips as `NSTextAttachment`s** (an image of the tag or the embed name on the first character,
  the rest collapsed). Rejected: the name would become a picture, so find, selection, VoiceOver and
  spell-check would stop reading it, and a find match inside a tag would highlight nothing visible.
- **Aligning by patching the delimiter line alone** (a byte-minimal write, closer to the SPEC's
  "rewriting the delimiter row"). Rejected: it would be a second write path into a table beside
  `commitTable`, with its own guard to keep in step with ADR-0029 §D8. The canonical serialisation
  is already what every table edit writes, and for a canonical table the two produce the same
  bytes.
- **Exporting tags and dates as styled `<span>` chips.** Rejected: ADR-0077 §D4's set has no
  `span`, and the reader of an exported page has no tags pane or calendar for a chip to point at.

## Consequences

**Positive**

- The SPEC's constructs read as what they are without the caret in them, and as their syntax with
  it, on every surface that draws a note. The editor, the reading view, the Pratiche rows and the
  export share one parse.
- The slash menu can offer a callout, and the comment that refused one is gone because its reason
  is.
- A picture no longer makes its line jump when it arrives with a written size, and a non-renderable
  embed is no longer raw text forever.
- Table alignment and sort no longer need the person to edit pipes by hand. Both are undoable in
  one step.

**Negative**

- The fragment surface grows by four classes (`CodeFenceFragment`, `QuoteBarFragment`,
  `CalloutTitleFragment`, `ChipLineFragment`) and the painter. Each must keep calling the painter
  and re-validating its characters, and a fifth fragment written later must remember to call the
  painter too.
- `MarkdownBlock.quote`'s payload changes, so every consumer of the shared parser recompiles
  against `QuoteLine`. The four call sites are listed in §D2.
- A table edited for the first time through the column menu is normalised to the canonical
  serialisation if it was hand-padded. That already happens on any cell edit, so it is not new.
- The export stylesheet's callout and highlight colours are literal copies of the light theme. They
  do not follow a theme change, as the `blockquote` rule's colours never did.
- Workspace cards stay simpler than the editor: no pills, no fence chrome, and a callout title
  coloured but not carded. A person moving a note to a card sees less.

**Neutral**

- A callout's fold is lost when its tab closes, as a heading's fold is.
- An email body in Pratiche that happens to contain `> [!...]` now draws a callout card. It is a
  read-only surface, and the file is unchanged.
- No index, schema, connector or protected interface changes. `perg` and `pergamenum-mcp` compile
  the new Core types (`Callout`, `FenceChrome`, `TransclusionCaption`) and expose nothing new.

## References

- Root `SPEC.md` (Approved 2026-10-04), milestone N5, R-35 to R-43; R-44 and R-45 chain-wide.
- `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 N5 and §3; `docs/20261002_Pergamenum_NoteWorkflowReport.md`
  R-3 to R-7, R-10.
- ADR-0018 (substitution at identical length), ADR-0019 (embed resize, §D8 handle guard),
  ADR-0023 §D1/§D9 (catalogues, the editor's ordinary menu), ADR-0028, ADR-0029 §D1/§D4/§D8/§D17,
  ADR-0033 §D6, ADR-0037, ADR-0047 §D11, ADR-0077 §D4/§D6/§D7, ADR-0078, ADR-0079 (rail pieces,
  contrast rule), ADR-0080, ADR-0081, ADR-0082.
- SPEC (app) `docs/20260811_Pergamenum_SpecApp.md` §5, §7.1, §4.4, §11.1.
- `.claude/protected-interfaces` (`CompletingTextView+Pasteboard.swift`).
