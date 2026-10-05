Status: Approved (2026-10-04)

# SPEC — The note workflow, N1 to N5: seams, the page, links, birth of a note, constructs

## Destination

One SPEC, handed to `/workplan`, that settles every decision for the five milestones of
`docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` (ledger `PG-384`..`PG-388`, issues
#886..#890). `/workplan` cuts it into five plans, N1 → N2 → N3 → N4 → N5, each built and
shipped as its own PR, each opening with a mockup PR approved on the Debug build before any
view is written. Facts re-read on `origin/main` @ `63831c64` on 2026-10-04.

## Objectives

- A note born without a topic is findable and conformant: it is a capture, it carries
  `status-inbox`, and a pane lists it until it is filed (I-1, I-2).
- Capture never refuses a title it can propose (I-3); a note is born from a template
  wherever notes are born (I-4); one composer names every note (I-5); a selection becomes a
  note (I-6); a creation can be undone (I-9).
- The line never shifts under the caret, the cost of a keystroke is a number, and the editor
  has one grammar shared with the reading surfaces and the export (R-1, R-2, R-8).
- A link can be peeked at, followed from the keyboard, opened in a tab or the other column,
  disambiguated, created from when dangling; the inspector shows why a note is linked, what it
  fails to link, where it appears (L-1..L-9, I-7).
- The editor draws inline code, fences, callouts, highlights, quotes, embeds and table
  alignment as what they are, and the export agrees with it (R-3..R-7, R-10).

## Scope and non-goals

In: every task of the roadmap's N1..N5 as amended by the Decisions below; the absorbed ledger
entries `PG-219` (N1), `PG-347` (N2), `PG-121` (N4, closed as superseded); the SPEC (app)
amendments the roadmap §4 names; connector parity for four new note operations.

Out (detail in Out of scope): a graph view; block references; untitled notes renamed from
their first heading; «Rendi strutturale» from the `[[` popup; table formulas; any on-disk
format change; any change to `IndexCache.schemaVersion`.

## Decisions

- **One SPEC for all five milestones** — the person's call («All five, one chain», 2026-10-03,
  confirmed 2026-10-04). Rejected: a discovery map plus a SPEC for N1 only — splits the chain
  the person asked to keep whole; five SPEC files — five archives for one decision set.
- **One PR per milestone, in order N1, N2, N3, N4, N5** — a regression in N2's styler cannot
  hold N1 hostage, and each PR closes one issue. Rejected: one PR for everything (weeks of
  drift, an unreviewable diff); one PR per ADR (splits N2, N3 and N4 into coupled halves).
- **Mockups ship first, as their own PR per milestone** — SPEC §11.1; the person approves the
  DesignGallery mockup on the Debug build, then the milestone's code is built. N1's mockup
  covers only paragraph spacing and the H5/H6 distinction. Rejected: HTML mockups drawn during
  this interview (not the real tokens and fonts); mockups for N4/N5 only (N2's gutter and N3's
  popover are visible changes too).
- **`status-inbox` on every path that creates a note with no `topic-*`, daily note excepted**
  — composer, Quick Open, Workspace «Documento», capture «Nota nuova», `perg` and MCP note
  creation; a topic given yields no `status-inbox`. This is ADR-0008 §D6's promise, never
  delivered. Rejected: capture and connectors only (hand-made topic-less notes would stay
  unfindable); app paths only (an assistant's topic-less note is just as unfiled).
- **Capture proposes `sanitize + 60`** — the title is the first line passed through the note-
  name sanitizer and cut at a word boundary to 60 characters; when sanitizing or cutting lost
  anything, the original first line stays as the body's first line; a timestamp title
  `YYYYMMDD HHmm Cattura` only when nothing usable remains; refusal only for an empty capture.
  Rejected: the report's "prose-shaped" rule (needs a fuzzy threshold for no gain over keeping
  the line in the body); always a timestamp title (throws away a usable title).
- **Workspace «Documento» places the card and opens no tab** — its confirmation offers
  «Apri», which opens the note in the Note pane. Rejected: switching to the Note pane (leaves
  the board the person was working on); keeping the background tab with an announcement (the
  tab is the clutter being removed).
- **Hover preview fires on Cmd + hover only** — reading or resting the pointer over text never
  pops anything, and the gesture matches Cmd+click to follow. Rejected: plain hover after
  400 ms (the roadmap's choice: popovers while reading); a setting (one more switch for a
  behaviour nobody asked to vary).
- **Link variants**: Cmd+click follows; Cmd+Shift+click opens in a new tab; Cmd+Opt+click opens
  in the other column; Cmd+Opt+Return follows the link under the caret (remappable); «apri in
  una nuova tab» and «apri nell'altra colonna» are in Vista with no default key. Rejected:
  Shift+click for a variant (it extends the selection in a text view); default keys for all
  three (two more chords nobody will remember).
- **The note pane listing `status-inbox` is called «Da classificare»** — never confused with
  the task view «Attività ▸ Inbox», and it says what to do. Rejected: «Inbox» (two in the
  sidebar); «Note in arrivo».
- **Callouts write the English type keywords** `note`, `tip`, `important`, `warning`, `caution`
  (the set GitHub and Obsidian style); the Italian names `nota`, `suggerimento`, `importante`,
  `avviso`, `attenzione` are read as aliases; the interface labels them in Italian; any other
  type is read as a callout and drawn neutral. Rejected: Italian keywords in the file (the
  roadmap's wording, which contradicts its own "Obsidian reads the file unchanged").
- **Connector parity for four new operations**: «Classifica» a note, link a mention, remove a
  structural link, extract a line range into a note — each in the shared connector layer,
  exposed by `perg` and MCP, writes behind `--allow-write` and `dryRun` default true (ADR-0007
  §D6). Templates gain `--template` as the roadmap already says.
- **PG-233 stays as decided on 2026-10-03**: «Collega» on a dirty source note raises the
  conflict prompt; the report's "save the buffer first" (L-5) is not adopted.
- **Creation undo is a 10-second toast, not the journal** — «Nota creata · Annulla» moves the
  file to the Trash and forgets its id; the app keeps no write journal (ADR-0007 §D6 stays).
  Rejected: arming the journal in the app.
- **The keystroke budget's ceiling is set from measurement** — N2 measures first, ADR-0082
  records the numbers and the ceiling; this SPEC fixes the method, not the number.
- **Clickable dates are the `>YYYY-MM-DD` scheduling tokens** (with or without an hour); a bare
  ISO date in prose is not a link. Rejected: every ISO date (false positives in prose).

## Constraints

- **The file never changes shape**: markdown, the closed four-key frontmatter (SPEC §4.3), flat
  namespaced tags (SPEC §4.4), JSON Canvas 1.0; every rendering change is display-only —
  origin: CLAUDE.md principles 1 and 4, SPEC §4.
- **Concealment keeps the character count**; a line that must look different is drawn by a
  layout fragment, its characters stay — origin: ADR-0028, the TextKit 2 design note.
- **One grammar**: after N2 every new construct enters the shared markdown parsers first and is
  drawn by every surface from the same span — origin: ADR-0077 §D1, roadmap §0.
- **Tokens only**: a new colour or spacing is a key in both theme files — origin: CLAUDE.md
  design system rule.
- **One write door, guarded**: every write through the session with `expecting:` or
  `expectingAbsent:`; state read before an `await` is re-read after it — origin: ADR-0043
  §D7/§D8, ADR-0057 §D3.
- **List rows**: flat rows in `List(selection:)`, no nested `.contextMenu`, keyboard focus per
  ADR-0070 — origin: ADR-0024, ADR-0069, ADR-0070.
- **Fully offline**; no index schema change; protected interfaces untouched (the word-boundary
  truncator behind `ImportNaming.recordingNoteTitle` is reused, never forked) — origin:
  CLAUDE.md principles 2 and 3, `.claude/protected-interfaces`.
- **GUI tests bounded**: at most three in N3 and two in N4, none elsewhere, each justified in
  its ADR, every file on `PergamenumUITestCase` — origin: CLAUDE.md merge-gate rule, user
  mandate in this interview.
- **PG-233's prompt stays** — origin: user decision 2026-10-03.

## Stack

Swift 6, SwiftUI with AppKit where the editor needs it (TextKit 2 `NSTextView`, layout
fragments, `NSPopover`), Swift Testing, the shared connector layer compiled into `perg` and
`pergamenum-mcp`. No new dependency.

## Data model

No new storage. `status-inbox` is an ordinary tag. The «Da classificare» list is a query over
the index's tag table. Backlink context lines, per-note unresolved targets and «Dove compare»
are read on demand and memoised by the index generation. Two new settings on the vault's
settings file: the inbox folder (default `00 Inbox`, an absent key reads as the default) and the
daily template (a note under `Templates/`, absent means none). Template placeholders gain
`{{time}}` and `{{cursor}}`; `{{cursor}}` is never written, it yields a caret offset.

## API / interfaces

- Creation: every note-creating door applies one initial-tags rule (topic-less → `status-inbox`,
  daily excepted).
- Capture: a pure title-proposal function (first line → proposed title plus "keep the line in
  the body" flag), used by the panel's live caption and by the write.
- Link navigation: one open-link entry taking a how (`replace`, `newTab`, `otherColumn`), used by
  clicks, the follow command and the backlink menu.
- Session writes: link a mention, remove a structural link (two guarded writes, half-done
  reported like adding one), classify a note (topics, optional folder, `status-inbox` removed,
  one guarded write plus an optional move), extract a range into a new note (create with
  `expectingAbsent:`, then replace the range with `[[Titolo]]` with `expecting:`).
- Connectors: the four operations above plus `--template` on note creation; read tools for
  unresolved links unchanged.
- Index snapshot: `unresolvedTargets(of:)` for one note, sharing the derivation the query
  layer's `unresolved` field already uses.

## UI flows

- **Capture**: Ctrl+Opt+Space, text, a live «Titolo: …» caption under the field, Return
  creates in the inbox folder; a template menu under «Nota nuova».
- **Da classificare**: in LAVORO, Ctrl+Cmd+I; rows sorted by date with a folder filter;
  «Classifica…» opens the sheet: topics with vocabulary completion and blocking, optional
  folder, frontmatter preview with `status-inbox` struck through. The same verb is on the note
  row's menu, in the slash menu and in the command catalogue.
- **Composer**: the one "name a note" surface, hosted in the pane, in the Workspace «Documento»
  sheet (folder = the board's folder) and from Quick Open's create row (prefilled); topic field
  with vocabulary completion; `client-`/`project-` chips from used values.
- **Links**: Cmd+hover shows the preview popover (the target's opening lines or its heading
  section; a `.canvas` link shows the board name); Cmd+click / Cmd+Shift+click / Cmd+Opt+click;
  Cmd+Opt+Return; a dangling link offers «Crea «X»»; several matches show a menu of folder
  paths.
- **Inspector**: backlinks with the linking line, a count, a «strutturale» badge and a row menu
  (Apri, Apri nell'altra colonna, Rendi strutturale; «Scollega» on structural rows); the open
  note's own unresolved links with «Crea nota» and «Vai al link»; unlinked mentions with
  «Collega» behind a diff confirmation; «Dove compare» (boards and pratiche).
- **Editor**: block markers revealed in the gutter; inline code pills, `==highlight==`, fence
  header with language badge and line count, callout cards (foldable), quote bars, embed chips,
  transclusion captions, `#tag` and date chips; table column menu for alignment and sort;
  «Estrai in una nota» in the slash menu and Modifica.

## Edge cases

- A capture whose proposed title is already taken: the caption shows it, Return is refused with
  the composer's existing "already exists" sentence, and the person edits the first line.
- A capture that is only whitespace or punctuation after sanitizing: timestamp title, text in
  the body.
- `[[` completion when `]]` already follows the caret: not doubled.
- Cmd+Shift+D from the Oggi pane: no pane switch (the note is already visible there).
- Cmd+N with a parked composer draft: the draft's folder wins; otherwise the sidebar's selected
  folder row, or the selected note's folder, or the vault root.
- Event note created from a time block: opens and switches to the Note pane, focused.
- A link whose title resolves to several notes: never the first one silently, from any surface
  (editor, Oggi, structural sheet, Quick Open).
- The preview popover: never takes first responder, closes on Cmd release, pointer leave and
  Esc, never survives as an orphan window (PG-258's lesson); no preview for an external URL.
- «Collega» on a mention whose note changed since the scan: refused, the diff is recomputed.
- «Scollega» or «Estrai» whose second write is refused: the first write stays, and the result
  names what landed and what did not (the `addStructuralLink` rule).
- `==` inside a code span is not a highlight; a fence body stays editable when its header is
  drawn.
- An unknown callout type renders neutral; a folded callout's body hides through the shared
  hidden-line set (ADR-0078).
- A template naming `{{cursor}}` twice: the first wins, the others are removed.
- The undo toast after its window: gone, the note stays.

## Test seams

Chosen in the interview (2026-10-04), existing seams first, highest level possible:

1. Pure unit tests in `PergamenumTests` for everything in Core and the connector layer: the
   initial-tags rule, the capture title proposal, parser spans, callouts, highlights, table
   rewrites, templates, the backlink line finder, per-note unresolved targets, the mention
   rewrite, extract's two writes, classify's frontmatter rewrite.
2. The styler golden corpus, captured before N2's rewrite (the export corpus's shape), each
   difference classed A (fix) / B (deliberate) / C (regression); reused for N5's constructs and
   the export.
3. A restyle budget test with a fixed ceiling, in the suite the Stop hook runs.
4. Hosted-view tests (the in-process family) for the gutter reveal, the popover, the link
   commands, the inspector sections, the «Da classificare» pane, the composer sheet and the
   undo toast.
5. Connectors: `perg` tests, and `scripts/mcp-smoke.py` after each MCP change.
6. GUI tests only in N3 (at most three: follow from the keyboard, the preview appears, «Collega»
   a mention) and N4 (at most two: filing a capture, the daily template).

## Success criteria

### N1 — Seams (issue #886, ADR-0080)

- [ ] R-01 — A note created with no `topic-*` carries `status-inbox` from the composer, Quick
  Open, Workspace «Documento», capture «Nota nuova», `perg` and MCP; a note created with a topic
  does not; the daily note never does; the event note, the Contenitore scheda and the inbox task
  note are unchanged; the MCP `dryRun` diff shows the tag.
- [ ] R-02 — Capture «Nota nuova» with an invalid first line creates a note titled by the
  sanitize-and-60 rule, keeps the original first line in the body when anything was lost, falls
  back to `YYYYMMDD HHmm Cattura` when nothing usable remains, refuses only an empty capture,
  and the panel shows the proposed title live; `Idea: usare i token anche per i font?` yields
  `Idea usare i token anche per i font`.
- [ ] R-03 — Applying a `[[` completion inserts the title and the closing `]]` (not doubled when
  already present), in the editor and in Workspace cards; a candidate matched by an alias reads
  «Titolo · alias: X» and inserts the title.
- [ ] R-04 — Cmd+Shift+D shows today's note in the Note pane from any pane but Oggi; an event
  note opens focused in the Note pane.
- [ ] R-05 — Workspace «Documento» places the card, opens no tab, and its confirmation's «Apri»
  opens the note in the Note pane.
- [ ] R-06 — Cmd+N creates in the sidebar's selected folder (or the selected note's folder),
  the vault root when nothing is selected, the parked draft's folder when one exists; «Nuova nota
  qui» is unchanged.
- [ ] R-07 — Cmd+click on `#client-acme` opens the Tags pane narrowed to it; Cmd+click on
  `>2026-10-14` opens the Oggi pane at that date.
- [ ] R-08 — A `spacing.paragraph` token exists in both themes and applies to prose paragraphs
  only (lists, quotes, code and tables excluded); H5 and H6 are visibly different (H6 regular
  weight in the secondary text colour).
- [ ] R-09 — The pointer is an I-beam over editor text and a pointing hand over a link
  (`PG-219`, #445).
- [ ] R-10 — The inbox folder is a vault setting (default `00 Inbox`, an absent key reads as
  the default) in Impostazioni › Convenzioni, used by note capture and task capture.
- [ ] R-11 — Errors from Quick Open's create row and the Workspace creation sheet are shown
  where the gesture was made and recorded in the problems list.
- [ ] R-12 — SPEC (app) §4.2, §4.3, §8.1 and §10 state the capture title rule, the topic-less
  rule, Cmd+Shift+D, Cmd+Shift+B and Oggi on Ctrl+Cmd+3; the three "from the template" doc
  comments are corrected (no-test: documentation text only, checked by reading the diff).

### N2 — The page, part one (issue #887, ADR-0081, ADR-0082)

- [ ] R-13 — For bullet, ordered and task items at every nesting level, the content's
  horizontal origin is identical whether the marker is concealed or revealed.
- [ ] R-14 — The same holds for headings and quotes at the narrow width and at the readable
  width.
- [ ] R-15 — A restyle budget test measures synthetic notes of 50 KB, 200 KB and 1 MB, with and
  without fences and view blocks, prints the numbers and fails above the ceiling ADR-0082
  records.
- [ ] R-16 — Renumbering after an edit rewrites only the edited ordered run, and one edit is
  one undo step.
- [ ] R-17 — Growing the view to fit lays out up to the caret's fragment plus the viewport, not
  the whole document, and the caret stays visible in a long note.
- [ ] R-18 — The styler classifies through the shared block and inline parsers; the golden
  corpus captured before the change classes every difference, none is C; `file_name_here` is
  plain in the editor as in the export (`PG-347`, #762).
- [ ] R-19 — A `pergamenum-view` fence renders in the Oggi and Diario panes; Workspace cards
  conceal quote and rule markers; tables and view blocks stay out of cards.

### N3 — Links (issue #888, ADR-0083, ADR-0084)

- [ ] R-20 — Holding Cmd over a wikilink shows a preview popover with the target's opening lines
  (or its heading section; a board link shows the board name); it closes on Cmd release,
  pointer leave and Esc, never takes first responder, and is never shown for an external URL.
- [ ] R-21 — Cmd+Opt+Return follows the innermost link at the caret and Cmd+[ returns;
  Cmd+Shift+click opens it in a new tab, Cmd+Opt+click in the other column; both variants are
  in Vista and bindable.
- [ ] R-22 — A title resolving to several notes shows a choice of folder paths (a menu at the
  click, a sheet from the keyboard), in the editor, Oggi, the structural-link sheet and Quick
  Open; nothing opens the first match silently.
- [ ] R-23 — Cmd+click on an unresolved `[[X]]` offers «Crea «X»» with the composer prefilled
  in the source note's folder; the `[[` popup shows a «Crea «X»» row when nothing matches and the
  typed text is a valid title.
- [ ] R-24 — The inspector's backlinks show, per note, the linking line, a count, a «strutturale»
  badge when the source's `related` names this note, and a row menu: Apri, Apri nell'altra
  colonna, Rendi strutturale; the index still stores paths only.
- [ ] R-25 — The inspector lists the open note's own unresolved links, each with «Crea nota» and
  «Vai al link»; the vault-wide list is a sample view; `perg note unresolved` and its MCP tool
  are unchanged.
- [ ] R-26 — «Collega» on an unlinked mention writes `[[Titolo]]` (or `[[Titolo|testo]]` for an
  alias) in the other note after a diff confirmation, in one guarded write refused when the note
  moved on; the connectors expose the same operation.
- [ ] R-27 — The structural-link sheet pre-fills the reverse reason as an editable mirror;
  «Scollega» removes the link from both notes in two guarded writes, a half-done result named;
  «Rendi strutturale» from a backlink row opens the sheet with the target preselected; a dirty
  source still raises the conflict prompt; the connectors expose the removal.
- [ ] R-28 — «Dove compare» lists the boards whose nodes point at the note and the pratiche that
  link it, read-only, a click opens each; no cache or schema change.

### N4 — Birth of a note (issue #889, ADR-0085, ADR-0086)

- [ ] R-29 — The «Da classificare» pane in LAVORO (Ctrl+Cmd+I) lists every note carrying
  `status-inbox`, sorted by date, filterable by folder, with flat keyboard-navigable rows.
- [ ] R-30 — «Classifica…» on any note sets one or more vocabulary-checked topics, optionally
  moves the note to a folder, removes `status-inbox`, previews the frontmatter, and writes once
  with `expecting:`; it is reachable from the pane, the note row menu, the slash menu and the
  command catalogue; the Contenitore's classification still works; the connectors expose it.
- [ ] R-31 — A daily-template setting makes Cmd+Shift+D, `pergamenum://today` and the capture
  «Oggi» destination create today's note from that template; `{{time}}` resolves and
  `{{cursor}}` places the caret without being written; capture «Nota nuova», Workspace
  «Documento» and Quick Open offer a template choice; `perg` and MCP accept `--template`;
  `PG-121` is closed as superseded.
- [ ] R-32 — The composer is the one naming surface, hosted in the pane, in the Workspace sheet
  (folder = the board's folder) and from Quick Open's create row; its topic field completes from
  the vocabulary and blocks a closed-family violation; existing accessibility identifiers stay.
- [ ] R-33 — «Estrai in una nota» (slash and Modifica) creates a note from the selection through
  the composer, prefilled with its first line, and replaces the selection with `[[Titolo]]`; a
  refused second write keeps the new note and names it; the source frontmatter is untouched; the
  connectors extract a line range the same way.
- [ ] R-34 — After an app-side creation a «Nota creata · Annulla» toast lets the person move the
  note to the Trash within 10 seconds, forgetting its id; after the window the note stays.

### N5 — The page, part two (issue #890, ADR-0087)

- [ ] R-35 — Both themes define tokens for inline code background, highlight, the five callout
  types and the quote bar.
- [ ] R-36 — Inline code reads as a pill and `==testo==` as highlighted text with their
  delimiters concealed off-caret and revealed on it; `==` inside code is not a highlight.
- [ ] R-37 — A fence's opening line reads as a header with a language badge and a line count, its
  closing line drawn quietly, both revealed on caret; the body stays editable; «Copia il blocco»
  copies the body.
- [ ] R-38 — `> [!type] Titolo` and the foldable `-`/`+` forms render as callout cards in the
  type's colour; the app writes the English keywords, reads the Italian aliases, labels them in
  Italian, draws an unknown type neutral, folds the body through the shared hidden-line set, and
  inserts one from the slash menu; Workspace cards colour the title only.
- [ ] R-39 — Quoted paragraphs indent per nesting level in the secondary text colour beside a
  full-height bar in the quote-bar colour, in the editor and in the reading view.
- [ ] R-40 — An embed reserves its written or default size before its thumbnail loads; an inline
  or non-renderable embed reads as a chip (icon, name, Quick Look on click); a transclusion's
  source line reads as the caption «da «Nota» › Sezione», revealed on caret; the resize handle
  and `|W` writing are unchanged.
- [ ] R-41 — A table column's menu changes its alignment by rewriting the delimiter row and sorts
  the rows by that column, each as one undo step.
- [ ] R-42 — `#tag` reads as a chip (namespace in the secondary colour, value in the accent) and a
  `>date` as a date chip.
- [ ] R-43 — The HTML export agrees with the editor on every construct of R-36..R-42 (highlight as
  `<mark>`, callout as an aside), pinned by golden corpus cases.

### Across the chain

- [ ] R-44 — Each milestone ships as its own PR after its mockup PR, closes its issue (#886..#890)
  and its ledger entry, and records its ADRs (0080..0087, numbers taken at merge) (no-test:
  release process, checked at each /ship gate).
- [ ] R-45 — `perg`, `pergamenum-mcp` and the app build after every milestone, and
  `scripts/mcp-smoke.py` passes after each MCP change (no-test: build and smoke script, not a
  unit test).

## Not yet specified

_none_

## Out of scope

- **A graph view** — the report advises against it: tags plus `related` are already browsable,
  and backlinks with context cover the need.
- **Block references `^id`** — ADR-0010 scoped them out; headings cover the real need.
- **Untitled notes renamed from their first heading** — the title is the file name by
  convention, and W-08 forbids renames outside the app; capture's proposal and «Estrai» give the
  speed.
- **«Rendi strutturale» from the `[[` popup (L-5's Cmd+Shift+K)** — the roadmap left it out; the
  backlink row covers the gesture. A later ledger entry if wanted.
- **Table formulas** — Roadmap v2 §1.1.
- **On-disk format, frontmatter schema, index schema** — unchanged by every milestone.

## Domain terms

- **Capture** — a note born without a topic: it carries `status-inbox` until classified,
  whatever path created it.
- **«Da classificare»** — the pane listing captures (notes). Not «Attività ▸ Inbox», which lists
  tasks (SPEC §7.4).
- **Structural link** — a link recorded in both notes' `related` with a reason (W-04), as
  opposed to an inline wikilink.
