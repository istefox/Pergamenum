# Pergamenum — Note workflow, markdown rendering and interconnection: usage audit

Date: 2026-10-02 · Tree: `main` at `8a783716` · Scope: how the app is *used*, not how the
code is written. Nothing was built or run: every **[fact]** below was read at the cited
file and line, every **[assumption]** is an inference about what a person at the keyboard
would experience. Three parallel read-only audits (editor rendering, note creation,
interconnection) feed this document; their file-level evidence is kept in the tables.

Subordinate to `docs/20260811_Pergamenum_SpecApp.md` (v2.2) and to the binding principles
in `CLAUDE.md`. No recommendation here adds a network call, a second storage schema, a
frontmatter key outside the closed four, or a `/`-nested tag. Where a recommendation
touches a SPEC decision, it says so and names the amendment.

---

## 0. Executive summary

Pergamenum already has the hard parts: one always-editable editor that conceals syntax,
tables and view blocks hosted as attachments, a journalled vault with guarded writes,
wikilinks with heading completion, transclusion, backlinks, unlinked mentions, structural
links with reason and symmetry, a tag browser, Quick Open, tabs and split view, global
capture, templates, version history. The gaps are not missing pillars. They are seams
between pillars, and most of them are cheap relative to what is already built.

The ten changes that would most improve daily use, in order:

| # | Change | Area | Why first |
|---|---|---|---|
| 1 | Reveal block markers (`- `, `## `, `> `) in the left gutter instead of in the text column, so a line never shifts under the caret | Rendering | The single most visible "this is not a live preview" moment, hit on every arrow key through a list **[fact]** |
| 2 | Hover preview of a wikilink's target (local popover reusing the transclusion renderer) plus a keyboard «Segui il collegamento» command | Links | Links are inert today: no pointer feedback (PG-219), Cmd+click only, tooltip shows the raw target **[fact]** |
| 3 | Backlinks with the linking line as context, grouped by note, structural links badged | Links | Every backlink costs an open-and-scan; the mention scanner already extracts a line **[fact]** |
| 4 | Every note born without a `topic-*` gets `status-inbox`, and an Inbox triage pane lists those notes with a «Classifica» sheet | Creation | Cmd+N with an empty topic, Quick Open create, Workspace «Documento», the capture panel and `perg capture` all write non-conformant notes silently; SPEC §4.3 promises the capture shape **[fact]** |
| 5 | Capture «Nota nuova» proposes a sanitised title instead of refusing the first line | Creation | A `:` or a 61st character leaves the panel open over another app with a refusal **[fact]** |
| 6 | Create a note from a dangling link: Cmd+click on `[[Nuova idea]]` and a «Crea «X»» row in the `[[` popup; the popup also closes `]]` | Links + Creation | Today the only creation path from a name is Quick Open with the exact title **[fact]** |
| 7 | Inline code pill, fence chrome (language badge, backticks concealed, copy), callouts and `==highlight==` rendered | Rendering | Four constructs a Craft/Obsidian writer uses daily are raw or half-styled **[fact]** |
| 8 | One markdown grammar for every surface: `MarkdownStyler` consumes `MarkdownInlineParser`/`MarkdownBlockParser` spans; Oggi/Diario pass `queries`; cards get the missing kinds | Rendering | Editor and reading surfaces disagree today (PG-347 is one symptom) **[fact]** |
| 9 | Per-note unresolved links in the inspector, clickable, with «Crea nota»; the vault-wide list becomes a `pergamenum-view` | Links | The inspector of note X shows the vault's broken links, capped at 10, not clickable **[fact]** |
| 10 | Daily-note template and `{{cursor}}`; templates reachable from capture, Quick Open and Workspace | Creation | SPEC §8.1 and Roadmap M9 promise it, three doc comments claim it, nothing implements it **[fact]** |

Items 1, 4, 5 and the `]]` half of 6 are one-session changes. Items 2, 3, 7 and 8 are each
an ADR-sized chain. Section 6 proposes the sequencing.

---

## 1. How notes work today: the workflow map

### 1.1 Getting a note or a line into the vault

Fourteen entry points, one write door (`VaultSession.createNote`, `VaultSession+Notes.swift:37-70`).
Tags come from `TagRules.initialTags` (`Tag.swift:164-168`): `type-note` + supplied topics,
plus `status-inbox` **only for `category: .capture`**, which only the event note, the inbox
task note and the Contenitore scheda pass.

| Entry point | Trigger | Decisions asked | Lands in | Frontmatter | Opens? |
|---|---|---|---|---|---|
| Nuova nota | Cmd+N, File menu, toolbar «+», folder menu «Nuova nota qui» | title, folder, template, one `topic-` (free text, no completion) | chosen folder, default root | `type-note` (+ topic) | new tab, pane switch |
| Quick Open «Crea la nota «X»» | Cmd+O, exact unmatched title | none | vault root | `type-note` | new tab |
| Global capture «Nota nuova» | Ctrl+Opt+Space | first line = title | `00 Inbox` | `type-note` | no |
| Global capture «Task» | same | text, Programma, Scadenza, note | `00 Inbox/Capture.md` or chosen note | task line | no |
| Global capture «Oggi» / «In una nota» | same | text (+ note) | daily note / chosen note | append | no |
| Task composer | Cmd+Shift+N | destination, text, dates, category, time block | chosen note, default inbox note | task line | optional («Crea e apri») |
| Daily note | Cmd+Shift+D, Quick Open, Oggi pane, routes | none | `Calendar/YYYYMMDD.md` | `type-note`, **empty body** | tab, **no pane switch** |
| Event note | right-click an event ▸ «Nota per questo evento» | none | `Calendar/YYYYMMDD-slug.md` | `type-note + status-inbox`, body with time and attendees, link from the daily note | tab, no pane switch |
| Workspace «Documento» | tool D | name (modal sheet) | board folder | `type-note` | card + background tab |
| `pergamenum://capture`, `task?add` | URL | none | as capture | as capture | no |
| `perg capture` / `perg note create` / MCP | CLI, stdio | flags | as capture | `type-note` (+ topic) | n/a |
| Plaud import | Registrazioni pane | review sheet | `Registrazioni/` | `type-note + topic-trascrizione` + `pergamenum-plaud-*` | n/a |
| Contenitore scheda | file in the drop folder | none, then «Classifica» | Contenitore root | `type-note + status-inbox` + `pergamenum-contenitore-*` | n/a |
| Templates | composer, «Applica un template…» Cmd+Ctrl+T | template | — | `{{date}}`, `{{title}}` only | — |

Rules at birth **[fact]**: title refused (never sanitised) on forbidden characters, 60+
characters, version suffix, leading dot (`NoteName.swift:13-81`); `date` always today in
the app; tag shape checked, closed vocabulary **not** checked anywhere in the app
(`TagRules.validate` is called by the linter, the board drop and the task drop only);
`#` completion suggests but never blocks, contrary to SPEC §4.4; `00 Inbox` and
`Capture.md` are constants, not settings; no conformance feedback remains in the app
since ADR-0038, so a non-conformant note is invisible until `perg lint`.

### 1.2 Writing and reading: one editor, concealed syntax

Governed by `VaultSettings.hidesMarkup` (default on). The whole note is re-classified,
re-attributed, re-laid-out and, when an ordered list changed, re-numbered on **every
keystroke** (`NoteTextView+Coordinator.swift:188-222`, `growToFitTheText` calls
`ensureLayout(for: documentRange)`); the header comment justifies it with "notes are small
enough" (`:264-267`). Concealment keeps the character count (TextKit 2 constraint) by
drawing delimiters at 0.01 pt; whole lines (folds, hidden frontmatter, table rows, fence
bodies) leave the layout through a separate mechanism. Reveal is paragraph-grained by
default, span-grained for emphasis/strikethrough/link behind an off-by-default setting
(ADR-0037).

| Construct | Today | Concealed | Reveal |
|---|---|---|---|
| Headings | title face, six sizes (H5 = H6) | `#` | paragraph, **text shifts right when revealed** |
| `**` `*` `~~` | styled | yes | paragraph / span |
| `_` `__` emphasis | styled, **never concealed** (deliberate) | no | — |
| Inline code | mono + secondary colour, **backticks visible, no pill** | no | — |
| Fences | mono on sunken surface, 7 grammars, **backticks and info string visible, no badge, no copy** | no | — |
| Wikilink, markdown link | accent, brackets concealed, tooltip = raw target | yes | paragraph / span |
| Image/PDF embed alone on a line | picture drawn, resize handle | whole run | never |
| Embed inline or other file type | **raw** | no | — |
| Transclusion `![[nota]]` | rendition drawn **under the still-visible source line** | no | — |
| GFM table | real grid attachment, Tab/Enter/blur commit; no alignment, sort or resize | rows hidden | never |
| Task checkbox | glyph, clickable | `[ ]` | never (deliberate) |
| Bullet list | `•`, indent by level | marker + indent | paragraph, **text shifts left when revealed** |
| Ordered list | digits kept, renumbered | indent | paragraph |
| Blockquote | one `▏` per level, **no indent, no colour** | `>` | paragraph |
| Rule `---` | drawn line | yes | paragraph |
| Frontmatter | mono; hideable per tab (Cmd+Opt+Y) | lines leave layout | — |
| `#tag`, `>date`, `!date`, `@done` | colour only | no | — |
| `pergamenum-view` fence | live attachment in Nota; **source text in Oggi and Diario** | opening line | whole fence |
| Callout `> [!nota]` | **raw** (plain quote bar) | — | — |
| `==highlight==`, footnotes, math, HTML, comments | **raw** | — | — |

Editing affordances present **[fact]**: slash menu (12 editor entries + every
`ShortcutCommand`), floating format bar on selection, completion on `[[`, `[[Nota#`, `#`,
`:`, list continuation and renumbering, spell check that skips syntax, find and replace,
outline with drag-to-move, heading folding, explicit save.

Pointer feedback: **none** app-wide, no I-beam and no pointing hand (PG-219).

### 1.3 Interconnection and navigation

| Feature | State | Where | Steps from the editor |
|---|---|---|---|
| `[[` completion | fuzzy over titles and board paths, 12 rows; **aliases never offered**; inserts the title and **leaves `[[Nota` open** (`CompletingTextView.swift:317-320`) | popup | 3 + type `]]` |
| `[[Nota#` | that note's headings | popup | 4 |
| Insert wikilink | Cmd+Shift+[ writes `[[]]` | Inserisci | 1 |
| Follow a link | **Cmd+click only**, or right-click ▸ Apri collegamento; ambiguous title opens `.first` silently; missing note → «nota non trovata» problem, **nothing created** (`CommandActions+LinkNavigation.swift:11-37`) | editor | mouse only |
| Open link in new tab / other column | **absent** from the link itself | — | — |
| Hover preview | **absent**; tooltip with the raw target | — | — |
| Backlinks | inspector (Cmd+Opt+I): title buttons, **no context line, no count, structural and inline merged** (`VaultBrowser.swift:286-302`) | inspector | 1 + mouse |
| Unlinked mentions | inspector, on request («Cerca nel vault»), shows the mention line, **no «Collega» action** (mockup refused it, roadmap promised it) | inspector | 2 + mouse |
| Unresolved links | inspector: **vault-wide**, max 10, not clickable, sources in a tooltip (`VaultBrowser.swift:304-320`) | inspector | read-only |
| Nota correlata (W-04/05/06/09) | sheet: search (aliases work), pick, **two mandatory reasons**, Collega; writes `related` + `## Note correlate` on both notes, max 5; **no «Scollega» in the UI** | Cmd+Shift+K | 6 |
| Transclusion | `![[nota]]`, `![[nota#sez]]`, depth 1, click opens | editor | 1 |
| Tag browser | own pane (Ctrl+Cmd+6), AND narrowing, journalled rename | pane | 1 + click |
| Inline `#tag` | coloured, **not clickable** | editor | — |
| Quick Open | Cmd+O: recents, starred, daily, fuzzy titles+aliases, create row, `#heading` jump; **no content, tag or folder filter** | sheet | 1 + type |
| Global search | Cmd+Shift+F: operators incl. `linked:`, `orphan:`; excerpt of the first matching line | sheet | 1 + type |
| Back/forward | Cmd+[ / Cmd+], 50 entries | toolbar | 1 |
| Tabs, split | Cmd+T, Cmd+1…9, Vista ▸ Dividi (keyless) | — | 1 |
| Note → task | inspector TASK COLLEGATI, toggle in place | inspector | 1 |
| Note → board | Inserisci ▸ Apri nel Workspace (keyless); board tray lists notes; **no inspector section «boards that show this note»** | menu | 1 |
| Note ↔ pratica | pratica → note only; **the note's inspector shows no pratica** | pratiche | — |
| Copia link Pergamenum | Cmd+Shift+L, `note?id=` | everywhere | 1 |
| Rename propagation | row menu «Rinomina…», rewrites every `[[…]]` and `related:` | row menu | 2 |
| Graph view, block refs | absent, deliberately | — | — |

---

## 2. Rendering markdown better and more fluidly

### 2.1 Findings, ranked

| # | Finding | Status |
|---|---|---|
| R-F1 | Revealing a list item or heading restores `- `/`## ` **inside the text column** and drops the paragraph indent, so the line jumps horizontally on every caret entry (`ListMarkerRendering.swift:68-71`, ADR-0028 accepted consequence) | fact |
| R-F2 | Full-document restyle, attribute rewrite, renumber scan and `ensureLayout(documentRange)` on every keystroke; last measurement 2026-08-17 (5.8 ms on 17 KB); no ceiling stated, no incremental path (`NoteTextView+Coordinator.swift:264-267, 541-552`) | fact for the mechanism, assumption for the felt latency |
| R-F3 | Inline code: backticks visible, no background; fences: delimiters and info string visible, no badge, no copy; named in ADR-0030's Phase B, whose cited roadmap file does not exist in the tree | fact |
| R-F4 | Callouts render as a plain quote bar; the slash menu refuses an entry for that reason (`EditorCommand.swift:41-45`); Roadmap M8 promised callout folding | fact |
| R-F5 | `==highlight==`, footnotes, HTML, generic comments raw; math deferred by roadmap | fact |
| R-F6 | Editor grammar (`MarkdownStyler`, no flanking rules) ≠ reading grammar (`MarkdownInlineParser`) used by transclusion renditions, Pratiche rows, view renderers, HTML export (PG-347) | fact |
| R-F7 | Blockquote: a `▏` glyph per level, no indent, no colour; nested quotes disagree with `MarkdownBlocksView` | fact |
| R-F8 | Embeds draw only when alone on a line and only for image/PDF; transclusion keeps the source line above the rendition; first render shows raw syntax until the thumbnail answers | fact |
| R-F9 | No pointer feedback (PG-219); Cmd+click only; no hover preview | fact |
| R-F10 | Tables: no alignment, sort, column resize; roadmap promised sorting and alignment | fact |
| R-F11 | `#tag`, dates, annotations are colour only, no chip | fact |
| R-F12 | `paragraphSpacing` is zero everywhere; H5 = H6 size | fact |
| R-F13 | Surfaces diverge: Workspace cards lack quote/rule/table/view-block rendering and the line-height multiple; Oggi and Diario show `pergamenum-view` fences as source and have no outline, fold or slash commands | fact |
| R-F14 | No typewriter/focus mode | fact |
| R-F15 | Find counts matches inside hidden rows and fence bodies but cannot show them | fact |

### 2.2 Recommendations

All of these stay inside the mechanism the tree already has (length-preserving paragraph
substitution, custom `NSTextLayoutFragment`s, attachments on one character, DTCG tokens).
None needs a new storage, a webview or a change to what is written on disk.

**R-1. Markers in the gutter, never in the column.** Keep the content column fixed and let
the revealed marker hang to its left: for a revealed list item or heading, set
`firstLineHeadIndent = headIndent − width(marker)` instead of showing the marker in the
column. The concealed and revealed states then share the same content x-origin, which
removes R-F1 without touching the file or the substitution rule. Same treatment for `> `
(quote bar stays, the `>` appears in the gutter). Headings may keep a dim `H2` badge in the
gutter permanently, the way Bear and iA Writer do; that is a design choice to mock up first.
Candidate for the first chain: paragraph-style only, one ADR amending ADR-0028's accepted
consequence.

**R-2. Measure, then scope the restyle.** Before any optimisation, add a measured ceiling:
the time of one `textDidChange` on a 50 KB, a 200 KB and a 1 MB note, with and without
fences and view blocks, recorded in the ADR. Then two cheap moves that need no incremental
parser: (a) `renumberLists` replaces the whole document atomically; limit it to the ordered
run containing the edited paragraph; (b) `growToFitTheText` ensures layout of the whole
document; ensure only up to the caret's fragment plus the viewport. Only if the
measurements say so, scope `spans(in:)` and `setAttributes` to the edited paragraph
range ± one paragraph, with a full pass on open and on fence-boundary changes (fences are
the only non-local construct). Keep the "notes are small enough" assumption explicit in the
ADR with the number that bounds it.

**R-3. Inline code and fences.** Inline code: conceal the backticks on the collapse path
(same shape as `~~`) and draw a background on the content with a new token
`color.code.inlineBackground`, radius from the existing `radius.control` (the theme has only `card`, `control`, `sticky`). Fences: conceal the two delimiter
lines to a thin header fragment (the `HorizontalRuleFragment` shape) that carries the
language badge, a line count and a «Copia» affordance in the context menu; the info string
is edited by revealing the line. This is the Phase B ADR-0030 named and never filed.

**R-4. Callouts.** `> [!tipo] Titolo` and `> [!tipo]- Titolo` (foldable): render through the
quote path with a per-type colour token (`color.callout.nota/avviso/importante/…`), a title
row from the type and the optional text, body indented, folding through the existing
hidden-line set (the frontmatter and heading folds share it, ADR-0078). Add the slash entry
`EditorCommand` refuses today. Obsidian reads the same text unchanged.

**R-5. Highlights.** `==testo==` as one more delimiter pair on the collapse path, background
from a new `color.highlight` token. One afternoon, the mechanism is identical to strikethrough.

**R-6. Blockquotes.** Indent the quoted paragraphs (`headIndent` per level), colour the text
`textSecondary`, draw the bar as a fragment the full line height, and make the nesting
rule the same as `MarkdownBlocksView`'s.

**R-7. Embeds and transclusions.** Reserve the written size (`|W`/`|WxH`, else a default
box) as a placeholder on the first pass, so the picture replaces a box and not raw text.
Draw an inline embed as a small chip (icon + name, click opens Quick Look) rather than raw
syntax, for every file type. For a transclusion, conceal the source line to a caption
(«da «Nota» › Sezione») above the rendition, revealed on caret like any paragraph.

**R-8. One grammar.** Make `MarkdownStyler` a consumer of `MarkdownInlineParser` and
`MarkdownBlockParser` spans (ADR-0077 already did this for the HTML exporter and measured
the old scanner wrong on 24 of 45 inputs). PG-347 closes as a consequence instead of as a
patch. Then parity: Oggi and Diario pass `queries` so views render there too; cards gain
quote, rule and the line-height multiple (tables and view blocks stay out of cards, ADR-0029).

**R-9. Typography.** A `spacing.paragraph` token (prose paragraphs only, lists and code
excluded), H5/H6 differentiated by weight or colour rather than size, `#tag` drawn as a
chip with the namespace in a lighter weight (`client-` dim, `acme` full), dates as chips
that open the day on click (ties into L-7).

**R-10. Tables.** Alignment via the delimiter row (`:---:`) editable from a cell context
menu; sort by column as a one-shot rewrite (journalled, one undo); column resize is not
worth building, the readable width already bounds the grid.

**Not recommended**: math (no local typesetter without a webview; keep "defer"), Mermaid
(rejected), a reading mode (ADR-0029 closed it), focus/typewriter mode (nice, not a
workflow gap; revisit after R-1 and R-2 land).

---

## 3. Improving the note insertion flow

### 3.1 Findings, ranked

| # | Finding | Status |
|---|---|---|
| I-F1 | Cmd+N with an empty topic, Quick Open create, Workspace «Documento», capture «Nota nuova», `pergamenum://capture?dest=note`, `perg capture` all write `type-note` alone: non-conformant (`TagRules.missingRequired`, `Tag.swift:151-152`) and not in the inbox. SPEC §4.3 and ADR-0008 §D6 promise `type-note + status-inbox` for a capture without topic; `VaultWrites.swift:59-80` passes the default category | fact |
| I-F2 | No triage surface for notes: the Contenitore has «Da classificare» + «Classifica»; `00 Inbox` notes have no list, no verb, and leave `status-inbox` only by editing YAML | fact |
| I-F3 | Capture «Nota nuova» validates the first line as a title and **refuses** on `:` `?` `/` or 61+ characters (`VaultCapture.swift:152-164`); the panel stays open over another app | fact; that this is the most common refusal is an assumption |
| I-F4 | Title before text everywhere (ADR-0003 §D1); no «extract selection to a new note» | fact |
| I-F5 | Daily note is created with an empty body; no template setting; three doc comments say "from the template" (`DayController.swift:158`, `VaultCapture.swift:105`, `VaultSession+TimeBlocks.swift:96`) | fact |
| I-F6 | Templates reach only the composer and «Applica un template…»; placeholders are `{{date}}` and `{{title}}` only; no `{{cursor}}`, `{{time}}` | fact |
| I-F7 | Cmd+Shift+D opens the daily note **without switching to the Note pane** (`CommandActions.swift:173-182`), unlike `.newNote`; event note and Workspace «Documento» also open background tabs | fact; perceived as "nothing happened" from Attività/Workspace is an assumption |
| I-F8 | Tag vocabulary is advisory: the composer's topic field accepts `status-final`; `#` completion never blocks; SPEC §4.4 says blocking | fact |
| I-F9 | Three UIs for "name a new note": in-pane composer, Workspace modal sheet, Quick Open row, with three different sets of decisions | fact |
| I-F10 | Cmd+click on a missing note creates nothing; the `[[` popup has no create row | fact |
| I-F11 | SPEC drift: daily note Cmd+T → actual Cmd+Shift+D; Nuova board Cmd+Shift+C → actual Cmd+Shift+B; «Vista ▸ Oggi (Cmd+T)» gone | fact |
| I-F12 | Errors surface differently per path: inline caption (composer), problems list (Quick Open, Workspace, routes), a line that dies with the panel (capture) | fact |
| I-F13 | App-side creation is not journalled (ADR-0007 §D6): no undo, only «Elimina…» to the Trash | fact |
| I-F14 | Three landing rules for imported files (Importa → `00 Inbox`, drop on editor → beside the note, drop on board → card), none chosen at import time | fact |
| I-F15 | Composer: one topic, no completion, no `client-`/`project-` chips, folder defaults to root rather than the sidebar's selected folder | fact |
| I-F16 | `00 Inbox` and `Capture.md` hard-coded, not in Impostazioni | fact |

### 3.2 Recommendations

**I-1. One rule for a note born without a topic: it is a capture.** `createNote` (or
`TagRules.initialTags`) gives `status-inbox` to any note created with no `topic-*`, on
every path, app and connector alike. This is what SPEC §4.3 already says for captures and
what makes the note conformant (`status-inbox` exempts the topic requirement) and
findable. One-line change plus tests; the connector's `--dry-run` diff shows it.

**I-2. An Inbox pane for notes.** A list of every note carrying `status-inbox` (an index
query, no new storage: `tag(status-inbox)` is already a view term), with the Contenitore's
«Classifica» sheet generalised: pick one or more `topic-*` from the vocabulary with
completion, optionally a folder to move to, preview of the frontmatter with `status-inbox`
struck through, one guarded write. The same verb goes on the note row's context menu and on
the slash menu. This closes the loop that capture opens; without it the roadmap's capture
bet produces debris. SPEC §7.4's task Inbox stays what it is.

**I-3. Capture never refuses a title it can propose.** When the first line fails
`NoteName.validate`, derive a title with `NoteName.sanitized` (already used for import
proposals), truncate at a word boundary to 60, show the proposal inline («Titolo: …») and
create on Return; the whole text goes to the body when the first line is clearly prose
(longer than 60 or ends with punctuation). Refuse only an empty capture. SPEC §4.2's rule
is kept because the proposal is conformant; the amendment is "propose, don't refuse" on
the capture surface only, which ADR-0008 can record.

**I-4. Templates where notes are born.** A daily-note template setting (a note in
`Templates/`, resolved on creation; also used by `pergamenum://today` and the capture
«Oggi» destination when it creates the note); `{{cursor}}` and `{{time}}`; the template
menu in the capture panel's «Nota nuova» and in the Workspace «Documento» sheet; the three
doc comments corrected in the same change. Roadmap M9's acceptance («today's daily note
is created from a template») becomes true.

**I-5. One composer, three hosts.** The in-pane `NewNoteComposer` becomes the only "name a
note" surface: the Workspace «Documento» sheet and Quick Open's create row prefill it
(title, folder = board folder or the sidebar's selected folder) instead of owning their
own decisions. Topic field with vocabulary completion and blocking (closes I-F8 and SPEC
§4.4's promise), chips for `client-`/`project-` from used values.

**I-6. «Estrai in una nota»** on a selection (slash and Modifica menu): creates the note
through the composer with the first line as proposed title, replaces the selection with
`[[Titolo]]`, keeps the source note's frontmatter unchanged. Two guarded writes, same shape
as the structural link.

**I-7. Create from a dangling name.** Cmd+click on an unresolved `[[X]]` offers «Crea
«X»» (composer prefilled, folder = the source note's folder); the `[[` popup shows a
«Crea «X»» row when nothing matches and the typed text is a valid title; the popup closes
`]]` on apply, as Inserisci ▸ Wikilink already does. ADR-0010/0012 do not forbid it; W-07
allows an inline unresolved link as a placeholder, which is exactly what this converts.

**I-8. Small fixes, one session.** Cmd+Shift+D switches to the Note pane like Cmd+N; event
note and Workspace «Documento» focus the created tab or say where it went; Cmd+N defaults
to the sidebar's selected folder; SPEC §8.1/§10 shortcuts updated (I-F11); errors from
Quick Open/Workspace/routes shown inline where the gesture was made, with the problems
list as the record; `00 Inbox` path in Impostazioni › Convenzioni.

**I-9. Undo for creation.** A toast after an app-side creation («Nota creata · Annulla»)
that trashes the file within a few seconds; cheaper than arming the journal in the app and
sufficient for the mistake it addresses.

**Not recommended**: untitled notes renamed from the first heading (title = file name is
the harness convention and W-08 forbids renames outside the app; I-3 and I-6 give the
speed without the drift); a block-based capture ("markdown in → blocks out", rejected by
ADR-0008 for good reasons).

---

## 4. Improving interconnection

### 4.1 Findings, ranked

| # | Finding | Status |
|---|---|---|
| L-F1 | No hover preview; no keyboard "follow link"; no pointer feedback (PG-219); Cmd+click only | fact |
| L-F2 | Backlinks are a title list: no context line, no count, no structural/inline distinction, no «apri nell'altra colonna» | fact |
| L-F3 | Dangling links are a dead end (see I-F10) | fact |
| L-F4 | Unresolved-links section is vault-wide, capped, not clickable; per-note data exists in `ViewField.unresolved` | fact |
| L-F5 | Structural link: six inputs, two mandatory reasons; no «Scollega» in the UI (`RelatedLink.remove` has no app caller); inspector cannot tell structural from inline | fact |
| L-F6 | `[[` completion leaves `[[Nota` open; aliases never offered and no hint that an alias maps to a title | fact |
| L-F7 | Unlinked mentions cannot be linked (mockup refused, roadmap M10 promised one-click linking) | fact |
| L-F8 | Ambiguous title resolves to `.first` silently | fact; stability of the order across rescans unverified |
| L-F9 | Inline `#tag` and dates not clickable | fact |
| L-F10 | No "open in new tab / other column" from a link | fact |
| L-F11 | Note's inspector shows no boards and no pratiche that reference it; pratica → note is one-way | fact |
| L-F12 | No graph, no block references, deliberately | fact |

### 4.2 Recommendations

**L-1. Links that answer to the pointer and the keyboard.** (a) Fix PG-219 first, it is a
P2 already filed. (b) Hover preview: an `NSPopover` after ~400 ms over a wikilink, showing
the target's first ~20 lines through the renderer the transclusion already uses
(`TranscludedNoteView`), with the heading section when the link has one; Esc or moving
away closes it; no network, no cache. (c) A remappable «Segui il collegamento» command
(suggested Cmd+Opt+Return; Cmd+Return is the task toggle) on the caret's link, with
Cmd+Opt+click and Shift+Return variants for «apri in una nuova tab» and «apri nell'altra
colonna». (d) Plain click stays a caret placement; this is the right choice for an editor.

**L-2. Backlinks with context.** For each backlinking note show the line that holds the
link (the `UnlinkedMentions` scanner already extracts a mention line; the same read gives
the link line), grouped by note with a count in the header, a badge for structural links
(present in `related:`) versus inline citations, and a row context menu: apri, apri
nell'altra colonna, rendi strutturale (opens the related sheet prefilled). The index keeps
storing paths only; the lines are read on demand, memoised by `indexGeneration` like the
list already is.

**L-3. Unresolved links per note.** The inspector of note X lists X's own broken targets
(from `ViewField.unresolved`'s derivation), each with «Crea nota» (I-7) and «Vai al link»
(caret jump through the existing `NoteJump`). The vault-wide list moves to a stock
`pergamenum-view` fence shipped in `Templates/` and to the Tags-style pane if wanted; it
stops occupying the inspector.

**L-4. Unlinked mentions → «Collega».** Add the action the roadmap promised: replace the
mention in the other note with `[[Titolo]]` (or `[[Titolo|testo]]` when the mention is an
alias), one guarded write with `expecting:`, a confirmation showing the diff line (the
`UnifiedDiff` type exists). The mockup's objection, "writes into another note", is already
how rename works; the diff confirmation answers it.

**L-5. Lighter structural links.** Keep W-04's mandatory reason, it is the convention, but:
pre-fill the reverse reason from the forward one as an editable mirror; «Scollega» in the
inspector's structural-link rows (two guarded writes, the inverse of `addStructuralLink`);
«Rendi strutturale» from a backlink row and from the `[[` popup (Cmd+Shift+K while the
popup is open opens the sheet prefilled with the selected note). Resolve PG-233 with "save
the buffer first, then link", the same rule `restoreVersion` uses.

**L-6. Completion details.** Close `]]` on apply (match Inserisci ▸ Wikilink); when the
query matches an alias, show the row as «Titolo · alias: X» and insert the title (W-01
kept); a «Crea «X»» row (I-7); fuzzy match stays.

**L-7. Clickable tags and dates.** Cmd+click on `#client-acme` opens the Tags pane
narrowed to it; Cmd+click on `>2026-10-14` opens that day; both reuse `clickTarget(for:)`.

**L-8. Disambiguation.** When `resolve(title:)` returns more than one path, show a small
menu with the folder paths instead of opening `.first`; the same menu serves the
structural link sheet and Quick Open.

**L-9. Where this note appears.** One inspector section «DOVE COMPARE» listing boards whose
nodes point at the note (`CanvasStore.allBoards()` + node paths, read on demand) and
pratiche whose `pergamenum-dossier-links-notes` or messages' `pergamenum-mail-note` name
it (`PraticaLinkResolver` in reverse). Read-only, click opens; no cache change.

**Not recommended**: a graph view (the vault's structure is tags plus `related`, both
already browsable; a force graph adds nothing a `linked:`/`orphan:` search and L-2 do not);
block references `^id` (ADR-0010 scoped them out; headings cover the real need).

---

## 5. What is already tracked, and what is new

Already open in `TODO.md` or the roadmap, not re-proposed here:

| ID | Covers |
|---|---|
| PG-219 (#445, P2) | pointer feedback, prerequisite of L-1 |
| PG-347 (#762, P3) | emphasis grammar, closed by R-8 |
| PG-258 (#572, P2) | format-bar orphan window, `onChange` without `initial` swallowing reveal requests |
| PG-262 (#576, P2) | missing tokens, last hardcoded colour in `EditorDecorationDelegate` |
| PG-233 (#517, P3) | «Collega» on a dirty note, decided in L-5 |
| PG-378 (P3) | `RelatedSection.parse` over-count |
| PG-135 (#235, P3) | board completion popup clamp |
| PG-121 (P3) | template engine, superseded in scope by I-4 |
| PG-132 (#232), PG-125 | capture route raising the app, route logging |
| PG-014 (#218), PG-269 (#583) | AppIntents, static export, prompts in the vault |
| PG-263 (#577) | menu/label drift |
| Roadmap §1.1, M8, M9, M10 | callouts, code languages, table sort/alignment, `{{cursor}}`, daily template, unlinked-mention linking |

Not tracked anywhere open, proposed as ledger entries (`/project-tasks`):

- R-1 marker-in-gutter reveal · R-2 restyle ceiling and scoping · R-3 inline code and fence chrome · R-4 callouts · R-5 highlights · R-6 blockquote styling · R-7 embed placeholder, inline embed chip, transclusion caption · R-9 paragraph spacing, H5/H6, tag chips · R-10 table alignment and sort
- I-1 `status-inbox` for every topic-less note · I-2 Inbox pane for notes · I-3 capture title proposal · I-5 one composer · I-6 extract to note · I-7 create from a dangling name · I-8 pane switch, folder default, SPEC shortcut drift, error surfacing, inbox path setting · I-9 creation undo toast
- L-1 hover preview and follow-link command · L-2 backlink context · L-3 per-note unresolved · L-4 mention linking · L-5 «Scollega», mirrored reason, «Rendi strutturale» · L-6 `]]` and alias hint · L-7 clickable tags/dates · L-8 disambiguation · L-9 «Dove compare»

SPEC amendments these imply (none silent): §4.2 "propose, don't refuse" on the capture
surface (I-3); §4.4 blocking vocabulary actually enforced (I-5); §5 callouts, highlights,
hover preview, follow-link command, extract-to-note; §8.1 daily template delivered and
Cmd+Shift+D recorded; §10 menu table refreshed; §12 Inbox pane for notes.

---

## 6. Suggested sequencing

Four chains, each through `/spec → /workplan → /build → /ship` with its own ADR, ordered by
value per session. Chain A has no design risk and no SPEC conflict; it ships first.

| Chain | Content | Size |
|---|---|---|
| **A — Seams** | I-1, I-8, L-6 (`]]`), L-7, PG-219, R-9 (spacing token only), I-3 | one or two sessions |
| **B — The page** | R-1, R-2 (measure first), R-3, R-4, R-5, R-6, R-7, R-8, R-10 | the largest; split B1 (R-1, R-2, R-8) from B2 (constructs) |
| **C — Links** | L-1, L-2, L-3, L-4, L-5, L-8, L-9, I-7 | two or three sessions |
| **D — Birth of a note** | I-2, I-4, I-5, I-6, I-9 | two sessions |

Mockups first for R-1 (gutter markers), R-4 (callout card), L-1 (preview popover), L-2
(backlink rows) and I-2 (Inbox pane), per CLAUDE.md's design rule; the DesignGallery
already hosts the mockup pages and has retained the shipped ones.

---

## 7. Method and confidence

- Sources: SPEC v2.2, Roadmap v2, ADR-0001…0078 as relevant, `Sources/Features/Editor`,
  `Sources/Features/Capture`, `Sources/Features/Search`, `Sources/Features/Tags`,
  `Sources/Core/Markdown`, `Sources/Core/Conventions`, `Sources/Vault`, `Sources/Connector`,
  `Sources/App`, `TODO.md`, `PROJECT_BRIEF.md`.
- Confidence **high** on every presence/absence claim marked fact (tied to a read line and
  spot-checked on the eight load-bearing ones: per-keystroke restyle, Cmd+click gate,
  `[[Nota` left open, capture frontmatter, daily-note body, backlink and unresolved panels,
  link navigation). **Medium** on step counts and keyboard reachability of list rows,
  inferred from view code. **Low** on felt latency (R-F2): nothing has been measured
  since 2026-08-17, which is why R-2 starts with a measurement.
- The real vault was not read (the session is scoped to the repository); where a finding
  depends on vault size or on how often a path is used, it is marked as an assumption.
