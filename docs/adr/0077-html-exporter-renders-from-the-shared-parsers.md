# ADR-0077: The HTML exporter renders from the shared markdown parsers, and escapes once, at emission

- Status: **accepted**. Merged to `main` via PR #737 (`a6063a9a`, 2026-09-30), for `PG-147`/#247,
  sub-item `structure-NoteExport.swift-c0f`. Implementation plan:
  `docs/plans/pg-147-core-app-shell-structure.md` (Tasks 1 to 3).
- Date: 2026-09-30. Written against `096d36a5` on `refactor/pg-147-core-app-shell-structure`, which is
  `origin/main` (clean tree). Every line number, count and output quoted below was read or measured on
  that commit. The old/new comparison in §Context came from a throwaway harness that compiled
  `NoteExport.swift`'s `MarkdownHTML` beside `MarkdownBlocks.swift`, `MarkdownInline.swift` and their
  Foundation-only dependencies, outside the repository.
- **Numbering note.** Drafted as 0075, then 0076, and took 0077 before its first commit, so there is
  nothing to `git mv`. On 2026-09-30 `origin/main` (`73f17450`) carries
  `docs/adr/0075-day-boundary-and-calendar-math.md` (PR #722, `5343eb58`) and
  `docs/adr/0076-pratiche-message-anchored-entries.md` (PR #724, `73f17450`, merged the same day while
  this chain was in flight). Main's two keep their numbers; the move is recorded in the register of
  `docs/adr/README.md`. No remote branch and not `origin/main` carries a `docs/adr/007[7-9]-*` file
  (checked 2026-09-30). Check again immediately before the merge.
- Source: the `PG-147` entry in `TODO.md` (P2, chain "core and app shell"), GitHub #247, from the
  audit of 2026-09-12. There is no SPEC. The repo-root `SPEC.md` belongs to the Contenitore chain and
  is not this record's input.
- **Reopens nothing.** No SPEC §14 decision, no on-disk format, no frontmatter key, no
  `IndexCache.schemaVersion` change (it stays 7: the index caches nothing either parser derives), no
  entry of `.claude/protected-interfaces`, no connector JSON, no exception to CLAUDE.md principle 2.
- **Extends, and changes nothing of:** ADR-0018 §D1 and ADR-0029 §D10 ("one grammar, read by every
  surface"), now applied to the exporter, which neither of them reached. ADR-0065 §D9.2 (an embed
  span carries its reference, never the size suffix) and §D13.1 (a CRLF line carries no `\r` into the
  page) keep holding through the parser, which already implements both.
- **Records, in their new place, the exporter's PG-124 properties** (PR #486, `0d239d48`), which
  landed without an ADR: `LinkPolicy.isOpenable` gates every anchor, and a quote in a URL cannot
  leave its `href`. The mechanism that guarantees the second one changes here (§D2), so the property
  needs a written home.

## Context

### Two grammars for one dialect

`NoteExport.html(from:title:)` (`Sources/Core/Conventions/NoteExport.swift:35`) is the only
production path from a note to HTML. It is also the only path to PDF: `NoteExporter.writePDF`
(`Sources/App/NoteExporter.swift:60`) hands the same HTML to `NSAttributedString(html:)`. The body
comes from `MarkdownHTML.render` (`NoteExport.swift:136-218`), a line scanner with its own rules for
headings, lists, quotes, tables and fences. Its inline pass (`:241-302`) escapes the whole text
first, then substitutes `[[…]]`, `` `…` ``, `[…](…)`, `**…**` and `*…*` in that order, over the
escaped string.

Every other surface that shows a note's markdown, rather than editing it, reads it through
`MarkdownBlockParser.blocks(in:)` (`Sources/Core/Markdown/MarkdownBlocks.swift:80`) and
`MarkdownInlineParser.spans(in:)` (`Sources/Core/Markdown/MarkdownInline.swift:39`). That covers the
transclusion rendition, the Pratiche rows and inspector, the outline's heading titles and, through
`NoteOutline`, section matching for `![[nota#sezione]]`. The parsers are Foundation-only, in
`Sources/Core`, and return values, so the exporter can use them without anything new.

### What the two disagree on, measured

The harness ran 45 inputs through both. On 24 of them the exporter is wrong and the parser is right.
The table lists the defects, not the inputs: one table input and one code-span input carry two each,
and the `__forte__`/`_lieve_` row comes from the mixed input discussed below.

| Input | Exporter today | Parser |
|---|---|---|
| `#project-av45 in corso` (a tag at the start of a line), `#Titolo` | `<h1>project-av45 in corso</h1>`, `<h1>Titolo</h1>` | paragraphs (a heading needs the space) |
| `####### troppo` | `<h6># troppo</h6>` | paragraph |
| `\| solo \| riga \|` with no delimiter row | a headless, bodiless `<table>` | paragraph |
| table rows of 2 and 4 cells under a 3-cell header | rows emitted ragged | padded and truncated to 3 (GFM) |
| `\|:--\|:-:\|--:\|` | alignment dropped | `.leading`, `.center`, `.trailing` |
| `>citato` | `<p>&gt;citato</p>` | quote |
| `1) primo` | paragraph | numbered list |
| `- [-] annullato`, `- [>] rinviato` | `<li>[-] annullato</li>`, `<li>[&gt;] rinviato</li>` | task lines with their marker |
| `- [ ]attaccato` (the task index counts it) | `<li>[ ]attaccato</li>` | task line |
| `---` between paragraphs | `<p>---</p>` | rule |
| `* * *` | `<ul><li><em> </em></li></ul>` | rule |
| `![[foto.png]]` | `<p>!foto.png</p>` | `.embed(target: "foto.png")` |
| `![[foto.png\|300]]` | `<p>!300</p>`: the size suffix is shown as the label | `.embed(target: "foto.png")` |
| `![didascalia](foto.png)` | `<p>!didascalia</p>` | `.embed(alt: "didascalia")` |
| `![[Altra nota#Sezione]]` | `<p>!Altra nota</p>` | `.transclusion` |
| `Vedi ![[foto.png\|300]] qui.` | `Vedi !300 qui.` | an embed span, text `foto.png` |
| `![[https://x.it/a.png]]` (remote, so not an embed block) | `<p>!https://x.it/a.png</p>` | an embed span, no `!` |
| `![alt](https://x.it/a.png)` | `<p>!<a href="https://x.it/a.png">alt</a></p>` | a link span, no `!` |
| ```` ``` ```` alone (an unclosed, empty fence) | nothing at all | an empty code block, as a closed empty fence already exports |
| `` `[[x]]` `` | `<code>x</code>`: the wikilink pass ran inside code | code, verbatim |
| `` `a*b*c` `` | `<code>a<em>b</em>c</code>` | code, verbatim |
| `2 * 3 * 4` | `2 <em> 3 </em> 4` | plain text (whitespace-flanked markers open nothing) |
| `__forte__`, `_lieve_`, `~~via~~` | literal | strong, emphasis, strikethrough |
| `**forte con *corsivo***` | `<strong>forte con <em>corsivo</strong></em>`: mis-nested, invalid HTML | two correctly nested spans |
| `[[Nota\|a#b]]` | `a`: the alias is cut at `#` | `a#b` |

On four inputs the exporter happens to be right and the parser is wrong, and a fifth
(`file_name_here e __forte__ e _lieve_`) is right on one side of it and wrong on the other. The five
come down to three parser defects. Adopting the parser as it stands would make them export
regressions, and each is already a defect on the surfaces that use the parser today:

1. **An intraword underscore opens emphasis.** `file_name_here` parses to `file`, *`name`*, `here`,
   so the reading view drops both underscores and the outline title reads `filenamehere`.
   `![[Nota#a_b_c]]` then fails to find `## a_b_c`, because `Transclusion.excerpt` compares against
   that outline title (`Transclusion.swift:108-111`). The editor's own recogniser has the same gap:
   `MarkdownStyler.swift:25` and `:358` record it, under ADR-0018 §D1, as the reason the editor
   never hides `_`.
2. **A link's label is not parsed.** `[**forte**](https://x.it)` and `[a **b**](https://x.it)` each
   parse to one span whose text keeps its asterisks. The exporter's substitution order happened to
   produce `<a href="https://x.it"><strong>forte</strong></a>` and
   `<a href="https://x.it">a <strong>b</strong></a>`.
3. **Any single bracketed character is a task marker.** `- [1] Rossi, 2020` and `- [a] voce` parse to
   tasks with markers `1` and `a`. The reading view draws an empty checkbox and the text `Rossi, 2020`, so `[1]` is lost.
   The task index accepts exactly ` `, `x`, `X`, `>` and `-` (`TaskParser.state(for:)`,
   `Sources/Core/Tasks/TaskParser.swift:100`), and the parser's own doc comment names the same four
   (`MarkdownBlocks.swift:41-42`).

On the other 16 inputs the output is already the same: prose, links, the PG-124 cases, CRLF, bold
list items, an indented task, headings with inline markup, bare URLs, raw HTML (escaped) and a `~~~`
fence, which neither side recognises. Three of the 16 match only through a presentation rule of §D3 or
§D6: `[[Nota#Sezione]]` and `[[Nota|]]`, whose parsed label differs from what the export shows, and a
multi-line paragraph, whose line breaks the export joins with a space.

### How the security properties hold today

PG-124 left two properties on the exporter. Both are pinned by `Tests/NoteExportTests.swift:80-100`:

- an anchor is written only when `LinkPolicy.isOpenable(url)` accepts the scheme, and a refused link
  exports as its label;
- a `"` in a URL cannot leave the `href`, because `NoteExport.escape` (`NoteExport.swift:71-78`) runs
  over the whole text before any substitution. The URL the anchor receives is already escaped.

The second property is a consequence of order: escape first, then insert markup. It also explains two
details that only make sense in that order. `LinkPolicy.isOpenable(_: String)` exists because an
escaped URL can fail `URL(string:)` (`LinkPolicy.swift:34-39`). `'` becomes `&apos;` rather than
`&#39;` because the wikilink pass splits at `#` after escaping (`NoteExport.swift:68-70`).

Parsing the note first means escaping cannot come first any more, so the property needs a new
mechanism.

### The PDF path reads the HTML

`NoteExporter.writePDF` gives the exported HTML to `NSAttributedString(html:)`. The exporter has
never emitted an element that names a resource (`img`, `link`, `script`, `iframe`, `object`, a
`style` or `src` attribute taken from the note), so this question never came up. An exporter that
starts drawing embeds could emit one by accident, and a resource named there is a load the HTML
importer may attempt. That would be a network call from note content: CLAUDE.md principle 2
allows exactly one, and this is not it. Nothing in the code today says so.

### Why this is an ADR

Most of this change is the obvious refactor, and the obvious refactor alone would not need a record.
Two things push it past the bar (the significance override for a security boundary, and for a
constraint the code does not show):

- the escaping mechanism behind a PG-124 property moves, and that property never had an ADR;
- the "no element that names a resource" rule and the "embeds export as text" choice are invisible
  constraints. The next reader who wants pictures in the PDF would otherwise add an `<img>`.

It also sets a rule for future work: a defect the exporter inherits from the parser is fixed in the
parser.

## Decision

### D1. `MarkdownHTML` renders parsed values and recognises nothing itself

`MarkdownHTML.render(_:)` becomes `MarkdownBlockParser.blocks(in:)`, one emitter per
`MarkdownBlock` case, joined by `"\n"`. `MarkdownHTML.inline(_:)` becomes
`MarkdownInlineParser.spans(in:)` with one emitter per span. The type keeps its name and both
signatures, `render(_ markdown: String) -> String` and `inline(_ text: String) -> String`, so the
tests that call them do not change. Its private line scanner, `Blocks` accumulator, `listItem`,
`replacePairs`, `replaceCode` and `replaceMarkdownLinks` are deleted.

`MarkdownHTML` moves out of `NoteExport.swift` into `Sources/Core/Markdown/MarkdownHTML.swift`,
beside the parsers it reads. It stays Foundation-only: `Sources/Core/**` is a `sharedSources` glob
(`Project.swift:88`), so the file compiles into `perg` and `pergamenum-mcp`, and an `import SwiftUI`
there breaks both tool builds (ADR-0001 §D1). `NoteExport` keeps `markdown(from:)`,
`html(from:title:)` and `escape(_:)` where they are.

### D2. Escaping happens once, at emission, on every string that came from the note

Parsing happens on the raw text. Every string the emitters take from a parsed value goes through
`NoteExport.escape` exactly once, as it is written out. That covers:

- span text, a code block's lines and a table cell (through its spans);
- a heading, a list item and a quote (through their spans);
- an embed's name or alt text and a transclusion's reference;
- a URL placed in `href`.

Nothing from the note is written unescaped, and nothing is escaped twice. The emitters' own markup
(tag names, the fixed `style` values of §D4) is the only unescaped output. This replaces
"escape, then substitute" as the mechanism behind PG-124's `href` property. The property itself, and
the byte output of `Tests/NoteExportTests.swift:80-86`, do not change.

`escape` keeps its five replacements and `&apos;`. The old reason for `&apos;` (the `#` split after
escaping) is gone. `&apos;` is still defined in HTML5, and keeping it keeps every existing expected
string byte-identical. Its doc comment is rewritten to say that.

### D3. Links: an anchor only for an openable URL; note links and embeds are text

- A `.url(target)` span becomes `<a href="\(escape(target))">…</a>` when
  `LinkPolicy.isOpenable(target)` accepts the **raw** target, and its content alone otherwise. The
  string overload stays: its rule is the scheme before the first `:`, and escaping can only change
  `&<>"'`, none of which is in an openable scheme. So asking before or after escaping gives the same
  answer, and the raw target is the honest input. Its doc comment, which says it is called after the
  escaping pass (`LinkPolicy.swift:34-39`), is corrected.
- Consecutive spans that carry the same `.url` link share one anchor, so `[a **b**](x)` is one link.
- A `.note(title:)` span exports as the alias when there is one. Otherwise it exports as the title
  up to its first `#`, so `[[Nota#Sezione]]` reads `Nota`. The span carries no separate alias field:
  the parser puts the alias in the span's text, the title itself when there is no alias, and `""`
  for `[[Nota|]]`. "There is one" therefore means a text that is non-empty and differs from
  `title`. A written alias identical to its own title reads the same either way, except for
  `[[A#B|A#B]]`, which exports `A`; that is accepted. This keeps the rule
  `Tests/NoteExportTests.swift:67-73` pins: the reader has no vault to resolve a link in. It is a
  rule about presenting a parsed value, not a second recogniser. The reading view keeps showing
  the full `Nota#Sezione`, because in the app a click resolves the section.
- An `.embed(target:)` span exports as its target's text. It is never an anchor and never an image.

### D4. A closed element set, and no element that names a resource

The body emitters write exactly these elements: `p`, `h1`–`h6`, `ul`, `ol`, `li`, `blockquote`,
`pre`, `code`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `hr`, `strong`, `em`, `del` and `a`.
They write exactly two attributes: `href` on `a` (§D3), and `style` on `th`/`td` with one of two
fixed values, `text-align: center` or `text-align: right`, for a column the delimiter row aligns
that way. A leading-aligned column gets no attribute, so a default table's bytes do not change.

**No `img`, `link`, `script`, `iframe`, `object`, `source`, `video`, `audio`, and no `src`, ever.**
`MarkdownBlock.embed` exports as `<p>` plus the alt text when there is one and the target otherwise.
`MarkdownBlock.transclusion` exports as `<p>` plus the reference. A test scans the whole golden
corpus for any other element or attribute (plan Task 3).

This is the explicit "no" of this record. Pictures in the PDF, whether as an `<img>` pointing at the
vault or as a `data:` URI, would be a feature with its own design: file size, which embeds, and what
a missing file prints as. They are not a side effect of a refactor.

### D5. A defect the exporter inherits from the parser is fixed in the parser

The three defects of §Context are fixed in the parsers, for every surface at once:

1. `_` and `__` open emphasis only when the character before them is not a letter or digit, and
   close only when the character after them is not one (CommonMark's intraword rule for `_`). `*`,
   `**` and `~~` keep today's whitespace rule.
2. A link's label is parsed with `spans(in:)`, and every span it yields carries the link. This
   covers `[…](…)` and the remote `![…](…)` form.
3. A task line's marker must be one `TaskParser.state(for:)` accepts. That function widens from
   `private` to `internal`, with a comment naming `MarkdownBlockParser` as its reader (ADR-0045's
   rule). The markdown parser then asks the task index's own grammar instead of keeping a copy.

An exporter-side workaround for any of the three, for example a pre-pass that protects underscores,
would be a second grammar again. That is what this record removes. The editor's `MarkdownStyler` is
**not** changed. It is the editor's own recogniser, with ranges, and it has never had either flanking
rule (`2 * 3 * 4` italicises there today). That disagreement predates this chain and is not widened
by it.

The user-visible effect outside the export: underscores stop vanishing in the reading surfaces and
the outline, a styled link label is styled there too, and `- [1] …` stops drawing a checkbox. A
transclusion of a section whose heading has two underscores now finds it.

**A persisted consequence.** An outline title is not only displayed. The `[[Nota#` completion
(`NoteTextView.swift`, `noteSections`) writes `entry.title` into the note text, and
`Transclusion.excerpt` later matches that string against the current titles. A section written
before this change under a heading whose title changed therefore stops resolving, and
`![[Nota#…]]` shows «sezione non trovata». Two shapes change title, measured by running the old and
the new `MarkdownInlineParser` side by side:

| Heading | Old title (what the link holds) | New title |
|---|---|---|
| `## file_name_here` | `filenamehere` | `file_name_here` |
| `## Vedi [**x**](u)` | `Vedi **x**` | `Vedi x` |

The first shape is any heading with an intraword `_` pair (`snake_case_name`, `2024_05_01`); the
second is a markdown link label that carries its own markup (`**`, `*`, `_`, `` ` ``, `~~`). Every
other heading keeps its title: a single intraword `_`, a leading `__init__`, a plain link label,
a wikilink. `Transclusion.excerpt` is the only reader that matches a title against persisted text;
`QuickSwitcher`, the outline, the fold submenu and the `[[Nota#` completion read titles live, and
fold state, jumps and `OutlineMove` go by ordinal or range.

This is accepted and not bridged. The old titles were the parser's mistakes (dropped underscores,
literal asterisks), and a fallback that also matched them would be a second grammar for heading
titles, the thing this record removes. The fix for a person is to complete the link again; the
completion now offers the correct title. `Tests/TransclusionTests.swift`
(`aSectionNamedByAnOldOutlineTitleNoLongerMatches`) pins the behaviour so it is a decision and not a
surprise. A compatibility fallback, if ever wanted, is Stefano's call.

### D6. What the exporter keeps as its own presentation

These rules act on parsed values and keep today's bytes wherever the parsers agree with today's
output:

- a paragraph's or a quote's lines are trimmed and joined by one space before the inline pass;
- a fence is `<pre><code>…</code></pre>` with no language class, `pergamenum-view` included. The
  expected string in `Tests/ViewBlockOutOfScopeTests.swift:145-172` stays byte-identical;
- the document skeleton and `<style>` block of `NoteExport.html` do not change, including for the new
  `<hr>` and `<del>`. The same R-11 test pins them byte for byte;
- task glyphs: `[ ]` is `☐` and `[x]`/`[X]` is `☑`, as today, and done text is not struck. `[-]`
  and `[>]` need glyphs of their own, and which ones is Stefano's call (plan gate G1). The
  recommendation is `⊟` (U+229F) for cancelled and `▷` (U+25B7) for rescheduled: both have a
  fallback in the system fonts, and neither reads as "done";
- a list keeps the parser's grouping. A run that mixes task lines and plain bullets becomes two
  adjacent `<ul>`s, as the reading view draws it;
- `<ol>` starts at 1. The parser does not keep the first number (`MarkdownBlock.numberedList([String])`),
  and neither did the exporter.

### D7. The golden corpus is the acceptance contract

Before the renderer changes, the current output for a fixed corpus is captured and committed
green (plan Task 1). The renderer then changes against expectations rewritten case by case, each
tagged with its class: A (the exporter was wrong), B (the parser was wrong, fixed by §D5) or C (a
presentation rule, §D6). An old/new difference without a class is a finding, not an expectation to
update.

## Alternatives considered

**Keep the exporter's grammar and patch the 24 differences one by one.** Rejected. It is the second
recogniser that ADR-0018 §D1 and ADR-0029 §D10 refused, and the measurement shows why: the two
drifted on 24 of 45 inputs, because what the parser gained over time never reached the exporter:
strikethrough, `_`/`__`, the embed span of ADR-0065 §D9.2 and the delimiter-row table rule. The next
dialect change would open the gap again. A patched
second grammar also keeps the escape-first mechanism and its two workarounds (§Context).

**Adopt a CommonMark library (swift-markdown or cmark-gfm) for the export.** Rejected. Wikilinks,
`![[…]]` embeds and transclusions, the four task markers and the `|W` size suffix are not
CommonMark. Each would need an extension, and the export would follow a grammar the app itself
does not use: two grammars by construction, now with a dependency. It is also a Tuist/SPM
dependency on the path to `Sources/Core`, compiled into both connectors, for one menu item. Full
CommonMark would also change far more output than the 24 differences above, with no reader asking
for it.

**Render `MarkdownBlocksView`'s attributed strings and ask AppKit for HTML.** Rejected.
`MarkdownBlocksView` is SwiftUI, and `Sources/Core` cannot import it. `NSAttributedString`'s HTML
writer emits presentational markup (fonts and colours from the active theme), not the semantic
document the exporter writes today. The exported page would then depend on the theme in use at
export time.

**Leave the item where the ledger put it, inside `PG-124`.** Moot. PG-124 closed on 2026-09-24
(PR #486) with this sub-item left open on purpose, so the escaping fix has since landed on the old
grammar, and this record moves it (§D2).

## Consequences

**Positive**

- One grammar for every rendering of a note that is not the editor. A dialect change reaches the
  export automatically.
- 24 export defects close, including three that change meaning: a tag line exported as a title, an
  embed's size suffix exported as its label, and `2 * 3 * 4` exported as italics.
- The exported body is always well-formed. The mis-nested `strong`/`em` case disappears.
- The PG-124 property rests on one rule (escape once, at emission) rather than on the order of five
  substitutions. The "no element that names a resource" constraint is now written and tested.
- Three parser defects close for the reading surfaces, the outline and section transclusion too.
- `NoteExport.swift` loses its two SwiftLint warnings on `render` (`cyclomatic_complexity` 11,
  `function_body_length` 68) and the 121-column line.

**Negative**

- The reading surfaces change behaviour in three small, visible ways (§D5). They are corrections,
  but a note that relied on `_x_` intraword italics (none is known) would lose them.
- A section link completed before the change against a heading with an intraword `_` pair or a
  styled link label stops resolving (`filenamehere` and `Vedi **x**` are no longer titles). The
  person completes it again. No fallback, by design (§D5, «A persisted consequence»).
- A mixed task/bullet run exports as two lists, not one. The spacing between them is the browser's.
- The exporter now depends on the parsers' shape. A future change to a `MarkdownBlock` case is a
  compile error in `MarkdownHTML`. That is the point, but it is a coupling that did not exist.
- The editor's `MarkdownStyler` still reads `_` and `*` differently from the reading surfaces. This
  was true before, and it is recorded here rather than fixed.

**Neutral**

- The PDF path, `NoteExport.markdown(from:)`, the Markdown export, the exported file names and the
  `<style>` block do not change.
- No connector change. `perg` and `pergamenum-mcp` compile `MarkdownHTML.swift` as they compiled
  `NoteExport.swift`, and neither calls it.

## References

- `TODO.md` `PG-147` (and `PG-124`, closed), GitHub #247 and #224.
- ADR-0001 §D1, ADR-0018 §D1, ADR-0029 §D10, ADR-0045 (the widening rule), ADR-0065 §D9.2 and §D13.1.
- `Sources/Core/Conventions/NoteExport.swift`, `Sources/Core/Markdown/MarkdownBlocks.swift`,
  `Sources/Core/Markdown/MarkdownInline.swift`, `Sources/Core/Email/LinkPolicy.swift`,
  `Sources/Core/Tasks/TaskParser.swift`, `Sources/App/NoteExporter.swift`.
- `Tests/NoteExportTests.swift`, `Tests/ViewBlockOutOfScopeTests.swift:119-179` (R-11, byte-identical
  export of a note with a fence).
- Plan: `docs/plans/pg-147-core-app-shell-structure.md`.
