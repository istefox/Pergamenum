# The note as a page: closing the distance to NotePlan

**Date:** 2026-09-04
**Status:** roadmap, decides the direction and the order. The binding decisions go into an
ADR (next free number: 0030) written through the `concept-to-code` chain, which also amends
SPEC §5 and §14. Nothing here is implemented yet.

## Why this document exists

ADR-0018, ADR-0028 and ADR-0029 turned the note editor into a single, always-editable,
always-styled view: headings, emphasis, strikethrough, links and wikilinks, blockquotes,
horizontal rules, list markers, checkboxes, image/PDF embeds and GFM tables all hide their
syntax until the caret reaches their paragraph. The Modifica/Lettura toggle is gone.

What still does not feel like NotePlan is not the concealment. It is the page around it. This
document records what NotePlan actually does (with sources), what the editor already does
(read in the code on 2026-09-04), where the remaining distance is, and the order in which to
close it.

## Decisions taken on 2026-09-04

Four questions were put to Stefano and answered:

| Question | Decision |
|---|---|
| Target model | **Hybrid, NotePlan-style**: markers hidden, revealed when the caret enters the paragraph. Not a marker-free WYSIWYG in the Craft/Lettera sense. |
| Body font | **Proportional, through a token.** Monospace stays for code and fences only. |
| First phase | **A, page typography.** Then B (remaining constructs), then C (interaction polish). |
| Where the roadmap lives | **This file.** No earlier roadmap for this exists in the repo. |

The reason the marker-free model was rejected: it needs a document model separate from the
file, and every invariant this repo built since ADR-0018 assumes `textView.string` *is* the
note - `VaultSession.write`, `WriteJournal.textBefore`, `NoteHistory`, the connectors' `undo`
hash comparison. The hybrid model keeps all of that untouched.

## What NotePlan does, with sources

Researched on 2026-09-04 by a research subagent; the four sources below were re-fetched and
read directly before being cited here.

**Fact.** NotePlan is a native macOS/iOS app, not Electron
([Hacker News, 2020](https://news.ycombinator.com/item?id=25198319)). Its editor is *not*
WYSIWYG in the marker-free sense: it hides syntax and reveals it at the cursor, driven by
regular expressions declared in the theme JSON. The help page
[Extend NotePlan's Markdown](https://help.noteplan.co/article/45-extend-noteplans-markdown)
documents the two keys that define the behaviour, quoted verbatim:

> "isHiddenWithoutCursor" will hide the matched text if the cursor is not inside the word.

> "isRevealOnCursorRange" will reveal hidden text, if the cursor is inside.

and the refresh discipline:

> NotePlan doesn't re-apply the styles to the full text when just one paragraph was changed.
> To save resources, only the edited paragraph is refreshed.

Rendering can be switched off entirely
([Turn off markdown rendering](https://help.noteplan.co/article/97-turn-off-markdown-rendering)),
the same escape hatch `VaultSettings.hidesMarkup` already is here (ADR-0018 §D7, ADR-0029 §D9).

**Unverified.** Whether NotePlan's text view is TextKit 1 or TextKit 2. No official statement
was found. Nothing in this roadmap depends on the answer.

**The same model everywhere native.** Bear's successor editor Lettera
([9to5Mac, June 2026](https://9to5mac.com/2026/06/19/bear-app-developers-announce-lettera-a-beautiful-markdown-editor-for-mac/)),
iA Writer and Ulysses all keep the syntax in the text and hide or fade it around the caret.
Marker-free editing exists only in block or web editors: Craft, Obsidian on CodeMirror 6. The
subagent's claim that Typora is now native AppKit rests on a single blog post and is **not**
endorsed here.

**Conclusion.** NotePlan's mechanism is the one this repo already ships: a length-preserving
substitution in `NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)`,
reveal on the caret's paragraph (`MarkupReveal`, ADR-0018 §D2), local invalidation through
`storage.edited(.editedAttributes, …)`. There is no engine to change.

## Libraries looked at, and why none is adopted

| Library | What it is | Verdict |
|---|---|---|
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) (Apache 2.0, 971 stars) | AppKit `NSTextView` on TextKit 2, live styling, wikilinks, fenced code, LaTeX, embedded images, task checkboxes | Reference reading. Adopting it would replace ~3,700 lines of editor already wired to embeds, tables, outline drag, transclusion and the journal, for nothing this roadmap needs. |
| [Downright](https://forums.swift.org/t/downright-a-native-textkit-2-markdown-editor-and-reader-for-macos/89077) (MIT) | A TextKit 2 markdown app: "The Markdown on disk always stays authoritative", features as "decorations over known source ranges", CI budgets for large documents | Same model as ours, confirms the direction. An app, not a library. Worth reading for its large-document CI budgets (phase C). |
| [STTextView](https://github.com/krzyzanowskim/STTextView) (active, 1,182 commits) | TextKit 2 replacement for `NSTextView`, built for a source-code editor | Not a fit: it solves code-editor problems, and its author's own account of TextKit 2 (below) is the useful part. |

**TextKit 2 limits to keep in view**, from
[Krzyżanowski, "TextKit 2, the promised land" (2025-08)](https://blog.krzyzanowskim.com/2025/08/14/textkit-2-the-promised-land/):
only `NSTextContentStorage` works as content manager; text elements must inherit
`NSTextParagraph`; `usageBoundsForTextContainer` is an estimate that changes while scrolling,
so the scroller jumps; the extra line fragment at document end lays out wrongly; Apple's own
TextEdit shows the same glitches. Two of these this repo has met already (the delegate must be
`NSTextParagraph`-based, ADR-0018; the caret that does not blink after a table redirect, Apple
FB17103305). The scroller estimate is the one phase C must measure on a long note.

## Where the editor stands, read in the code

| Aspect | State on 2026-09-04 | Source |
|---|---|---|
| Concealment | heading `#`, emphasis, strikethrough, link/wikilink brackets, blockquote `>`, `---`, list markers, checkboxes, embeds, tables | `HiddenMarker.Kind` in `EditorDecorationDelegate.swift`: `heading, emphasis, embed, list, checkbox, blockquote, strikethrough, link, rule, table` |
| Reveal | caret paragraph, selection, IME composition, current find match | `NoteTextView+Reveal.swift`, `MarkupReveal.paragraphs(in:selection:markedRange:currentMatch:)` |
| Body font | **`NSFont.monospacedSystemFont(ofSize: 13)`, hardcoded**; bold is the same face in `.bold` weight | `MarkdownAttributedText.swift:18`, `:56` |
| Heading font | `systemFont(ofSize: max(15, 24 - level * 2), weight: .semibold)`, hardcoded | `MarkdownAttributedText.swift:52` |
| Font tokens | `font.title` 22/600, `font.heading` 16/600, `font.body` 13/400 line-height 1.5, `font.caption`, `font.mono` 12/400, all `fontFamily: system` or `monospace`; `Theme.nsFont(_:)` exists | `TokenKeys.swift:70-75`, `Resources/Themes/pergamenum-*.json:67-82`, `Theme.swift:51` |
| Hardcoded `NSFont.` sites in the editor | 9 across 5 files | `MarkdownAttributedText` (3), `TableGridView+Rendering` (3), `TableGridView+CellCommit` (1), `EditorDecorationDelegate` (1), `+ListRendering` (1) |
| Page geometry | `textContainerInset = 24 × 20`, text as wide as the column, no readable-width cap | `NoteTextView.swift:125` |
| Code fences | backticks and language always visible; body has `surfaceSunken` background | `MarkdownStyler.Span.codeBlock`, no `HiddenMarker.Kind` for it |
| Inline code | backticks always visible | `Span.code`, no `HiddenMarker.Kind` |
| Frontmatter | raw YAML at the top, styled as `Span.frontmatter` | `MarkdownStyler.swift:105` |
| Tags | coloured `Span.tag`, not a pill | `MarkdownAttributedText` |

Two observations fall out of the table.

1. **The editor breaks the binding token rule.** CLAUDE.md: "a view that uses a color or a font
   without going through a token does not pass review". The editor's body, bold and heading
   fonts never touch `Theme.nsFont(_:)`. Phase A is a conformance fix before it is a feature.
2. **The token file already says proportional.** `font.body` is `system` 13, not monospace.
   The "source mode" look is the editor overriding its own theme.

## The distance, named

- **Typography and page.** Monospace body, no readable width, heading scale not in the token
  file, no paragraph spacing rule. This is what makes the note read as a code buffer.
- **Three constructs still show their syntax.** Fence backticks, inline-code backticks, the
  frontmatter block.
- **Interaction.** A click on a collapsed paragraph reveals it and shifts the text under the
  pointer (NotePlan shows the same jump, so this is a polish item, not a defect). Mouse
  selection across collapsed runs and the TextKit 2 scroller estimate on long notes are
  unmeasured.

## Method

**Stack unchanged.** `NSTextView(usingTextLayoutManager: true)`, `EditorDecorationDelegate` as
the single content-storage and layout-manager delegate, length-preserving paragraph
substitution for inline markers, the enumeration hook for hidden lines, custom
`NSTextLayoutFragment` where a construct cannot length-preserve (rule, folded heading),
`NSTextAttachmentViewProvider` for live views (table). Every new construct picks one of those
four mechanisms; none is added.

**Invariant kept.** `textView.string` is the file. No mechanism here may insert, delete or
replace a character on the display path.

**One switch.** Everything stays behind `VaultSettings.hidesMarkup`, as ADR-0029 §D9
requires. Typography (phase A) is *not* behind it: a proportional body is the editor's look,
not a markup decision.

### Phase A, page typography

Scope:

- `MarkdownAttributedText` reads body, bold, italic and heading faces from `Theme.nsFont(_:)`.
  Bold becomes the body face at `.bold` weight; italic uses the real italic trait instead of
  `.obliqueness: 0.2`.
- Heading scale expressed in the token file. Today only `font.title` and `font.heading` exist;
  six levels need either a scale rule (a ratio per level from `font.title`) or per-level tokens.
  The ADR decides; the roadmap's preference is a scale rule, because five more keys in two
  theme files is what drift looks like.
- Paragraph spacing and line height from the token's `lineHeight` (already `1.5` for body),
  applied through `NSParagraphStyle`, never through blank lines in the file.
- A readable-width cap for the text column, centred, as a spacing token (`spacing.readable` or
  similar; the ADR names it). Obsidian's default is 700px; NotePlan and Bear cap similarly.
  The value is a design decision, not a measurement.
- The nine hardcoded `NSFont.` sites brought under tokens, `TableGridView` cells included, so a
  cell reads in the same face as the paragraph above it.
- Monospace remains for `Span.code`, `Span.codeBlock` and `Span.frontmatter`, from `font.mono`.

Acceptance: a note with H1-H3, body, bold, italic, a list, an inline code span and a fence
reads in the theme's faces in both light and dark; changing `font.body` in the theme JSON
changes the editor with no code change; `grep -rn "NSFont\." Sources/Features/Editor` returns
zero hits outside a deliberately named allow-list.

Risk: low. Attribute values change; no delegate, no substitution, no layout mechanism is
touched. One thing to check by hand: `EmbedAttachment` and `TableAttachment` line-fragment
heights with a larger body face, because both compute against the paragraph's font.

### Phase B, the three constructs left

- **Inline code** `` `x` ``: a new `HiddenMarker.Kind.inlineCode`, the exact twin of
  `.emphasis` and `.strikethrough` (ADR-0029 §D1's shape). Cost: one span case, one branch.
- **Fenced code block**: the opening and closing fence lines cannot length-preserve into
  nothing (a `\n` at size 0.01 still breaks the line, `docs/20260817_TextKit2_live_editing.md`).
  Two candidates, the ADR picks one: (a) a custom `NSTextLayoutFragment` drawing the language
  as a small badge in place of the fence line, the `HorizontalRuleFragment` precedent; (b) hide
  the closing fence through the enumeration hook and badge only the opening one. Reveal on
  caret applies to both fence lines as to any paragraph.
- **Frontmatter**: collapsed to a single "Proprietà" line through the enumeration hook, the
  same mechanism as a folded heading (`FoldedHeadingFragment`), with the four fields
  `date`, `tags`, `related`, `aliases` (SPEC §4.3, closed schema) drawn on the fragment.
  Clicking or moving the caret into it reveals the YAML for editing. No form UI in this phase:
  the file's YAML stays the only editor of the fields.
- **Tags as pills**: optional, a background attribute on `Span.tag`; no concealment involved.

Acceptance: `hidesMarkup` off shows every backtick and the raw YAML exactly as today
(ADR-0029 §D9). The find bar still counts matches inside a collapsed fence line.

Risk: medium for the frontmatter fold, because the enumeration hook gains a third producer
(after folding and tables, ADR-0029 §D5) and the delegate is already at SwiftLint's length
limit; the split follows `EditorDecorationDelegate+TableRendering.swift`.

### Phase C, interaction and viewport

- Measure the click-reveal jump: pointer position before and after a click into a collapsed
  paragraph, on a heading and on an emphasis run. Decide whether to re-map the caret to the
  character under the pointer *after* reveal, in `CompletingTextView.mouseDown(with:)`.
- Mouse selection dragged across collapsed runs: what lands on the pasteboard is what is
  seen (ADR-0018 §D2's third trigger already reveals paragraphs a selection touches; verify
  mid-drag).
- Long-note budget in the spirit of Downright's CI budgets: a 400-paragraph note with twenty
  fences and five tables, keystroke latency and scroller stability recorded in a unit test
  against the offscreen stack the 2026-08-17 study already built.
- The TextKit 2 scroller estimate: reproduce Krzyżanowski's jump on a long note; if present,
  decide between living with it (personal app) and a `usageBoundsForTextContainer` cache.

Acceptance: numbers in this document's successor, not adjectives.

## Non-goals

- Marker-free WYSIWYG, block editor, toolbar-only formatting (decided against, above).
- Any WebView, CodeMirror, ProseMirror (SPEC §14 "Temi" row; principle "no WKWebView").
- New markdown constructs: callouts, footnotes, math, Mermaid (ADR-0029's non-goals hold).
- A regex-driven theme grammar in NotePlan's style. Our constructs are parsed by
  `MarkdownStyler`, typed as `Span`; the theme controls colour and face, not grammar.
- A properties form for the frontmatter (phase B collapses it; editing stays in YAML).
- Workspace `.text` cards: they share `EditorDecorationDelegate` (ADR-0028 §D1) and inherit
  inline-code concealment for free, but the fence badge and the frontmatter fold must be
  kept out by `CardTextView`'s span switch (ADR-0029 §D17), since cards have neither.

## Process

1. `concept-to-code` chain on this roadmap: interview (short, the four decisions are taken),
   ADR-0030 superseding nothing and amending SPEC §5 (the editor's typography and the three
   constructs) and §14 (the "source mode con stile è sufficiente" rationale, already
   partially retired by ADR-0029), then the plan for phase A only.
2. Phases B and C get their own plans after A has been used for a few days; the ADR covers
   all three so the direction is decided once.
3. Every phase ships behind the build and the unit suite, with `scripts/uitests.sh` before
   the merge as CLAUDE.md requires. Phase A changes what `DesignAndReadingUITests` sees; those
   tests assert behaviour by `accessibilityIdentifier`, not by font, and should survive.

## Sources

- https://help.noteplan.co/article/45-extend-noteplans-markdown
- https://help.noteplan.co/article/97-turn-off-markdown-rendering
- https://news.ycombinator.com/item?id=25198319
- https://9to5mac.com/2026/06/19/bear-app-developers-announce-lettera-a-beautiful-markdown-editor-for-mac/
- https://github.com/nodes-app/swift-markdown-engine
- https://forums.swift.org/t/downright-a-native-textkit-2-markdown-editor-and-reader-for-macos/89077
- https://github.com/krzyzanowskim/STTextView
- https://blog.krzyzanowskim.com/2025/08/14/textkit-2-the-promised-land/
- `docs/20260817_TextKit2_live_editing.md`, `docs/adr/0018-…`, `docs/adr/0028-…`,
  `docs/adr/0029-editor-wysiwyg-unification.md`
