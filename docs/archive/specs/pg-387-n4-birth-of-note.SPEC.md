Status: Approved (2026-10-06)

# SPEC — N4 Birth of a note: «Da classificare», «Classifica», templates, one composer, «Estrai», creation undo (PG-387)

## Destination

A SPEC handed to `/workplan`, built in about three `/build` sessions and shipped as one PR after its
mockup PR. Closes ledger `PG-387` / issue #889 and records ADR-0085 and ADR-0086 (both written,
`proposed`). It is the N4 slice of the approved chain SPEC (saved in `f697b363`, R-29..R-34), re-read
against `origin/main` @ `36017e1b` on 2026-10-06, with the three gates ADR-0085 left to the person
now settled. `PG-121` closes as superseded by this SPEC.

## Objectives

- A capture (a note born with no topic, ADR-0080) is findable: one pane lists every note carrying
  `status-inbox`, and one verb files it, from four surfaces and both connectors.
- A note is born from a template wherever notes are born: the day's note, capture «Nota nuova»,
  Quick Open, Workspace «Documento», `perg` and MCP.
- One composer names every note, instead of three disagreeing surfaces.
- A selection becomes a note, and a creation can be undone.

## Scope and non-goals

In: roadmap §N4 tasks 1-8 as ADR-0085 and ADR-0086 decide them; connector parity for «Classifica» and
«Estrai» and `--template`; the SPEC (app) amendments in ADR-0085 §D12 and ADR-0086.
Out: the template engine of `PG-121`, any journal in the app, a toast beyond the pane-host composer,
a delete verb in the pane. Detail under Out of scope.

## Decisions

- **The pane is «Da classificare», not «Inbox»** — a note pane in LAVORO after «Attività», opened by
  Ctrl+Cmd+I (free today; the inspector is Cmd+Opt+I), so it is never confused with «Attività ▸
  Inbox», which lists tasks (SPEC (app) §7.4). Settled by the approved chain SPEC; the request text
  and the roadmap say «Inbox». Rejected: «Inbox» (two in the sidebar); a sixth task view (ADR-0013
  §D6 keeps the five closed).
- **The pane is a query, not a store** — rows are the index's notes carrying `status-inbox`, read per
  index generation and never cached. Rejected: a registry file or cache column (a second truth to
  keep in step; principle 3).
- **Schede carrying `status-inbox` are listed, and classified through their own form (gate G1,
  2026-10-06)** — R-29 says «every note» and a scheda is a note in the index. Rejected: excluding
  them behind a footer linking to the Contenitore (answers a flood nobody measured).
- **One classification rule, the scheda rule as its special case** — removes `status-inbox`, keeps or
  adds `type-note`, adds the topics, caps at seven tags. Rejected: two rules (they drift, ADR-0041 §D4).
- **«Classifica» writes first, moves second** — one guarded write with `expecting:`, then an optional
  move. A failed move leaves a classified note in place and is reported, never thrown. Rejected:
  move first (a refused write would strand an unfiled note outside the inbox folder).
- **A dirty note is saved first, as part of the confirmation (gate G2, 2026-10-06)** — the button
  reads «Salva e classifica» / «Salva ed estrai». Rejected: refusing (hostile from the slash menu,
  where the note is almost always dirty); «Estrai» as an undoable buffer edit (the app would stop
  using the guarded session write and the connectors would diverge).
- **The composer composes, the host creates** — two hosts: the Note pane (ADR-0003 §D1 unchanged,
  identifiers and `ComposerUITests` kept) and a sheet for the Workspace «Documento» (folder = the
  board's folder) and «Estrai». Quick Open's create row opens the pane host prefilled. Rejected: a
  sheet everywhere (ADR-0003 §D1 was a fix the person asked for); the editor column for «Estrai»
  (the source and its selection must stay visible).
- **The topic field becomes a tag field** — one pure door, `TagEntry`: bare text reads as a topic, a
  closed-family value outside the vocabulary is refused, `type-*` and `status-*` are refused (the
  initial-tags rule owns them), completions come from the vocabulary or the values most used.
- **«Estrai» is a two-write session door** — create the note with `expectingAbsent:`, then replace
  the range with `[[Titolo]]` with `expecting:`. A refusal on the second write keeps the new note and
  names it (the `addStructuralLink` rule). A range touching the frontmatter is refused, so the
  source frontmatter is untouched by construction.
- **The creation toast covers the pane-host composer only (gate G3, 2026-10-06)** — «Nota creata ·
  Annulla», 10 seconds, trashes through the door that forgets the id; refused when a tab holds unsaved
  changes or the file moved on. Excluded, each for a recorded reason: Workspace «Documento» (a card
  would point at a missing file), «Estrai» and Pratiche create-and-link (two writes), daily and event
  notes, capture, connectors (own journal). Rejected: arming the journal in the app (ADR-0007 §D6);
  including the Workspace (two surfaces in one undo).
- **Placeholders: `{{time}}` and `{{cursor}}`** — `{{cursor}}` is located before any other
  substitution and never written; the first wins, the others are removed; a connector, having no
  caret, removes it. Rejected: a template engine (`PG-121`).
- **The daily template is a vault setting applied at the one door every day's note is born through**
  — Cmd+Shift+D, `pergamenum://today`, capture «Oggi», the event note's day and the Pratiche diary
  mirror all inherit it. A missing or unreadable template never blocks the day.
- **The caret is a one-shot property of the tab** — consumed on the column's first update, passed
  only when the call created the note. Rejected: persisting it.
- **N4 is built after N3 (2026-10-06)** — N3 (`PG-386`) is not on `main`: `shipsUnbound`,
  `offerNoteCreation(title:besideNoteAt:)` and `recordLinkAtCaret` do not exist, and N4 needs all three
  (unbound catalogue commands, the composer's prefill entry, the selection report). They are hard
  prerequisites; `/workplan` stops if one is missing. Rejected: N4 carrying minimal copies (conflicts
  on `ShortcutCommand` and the controller); cutting the features that depend on them.
- **Two GUI tests at most** — filing a capture and the daily template, each justified in its ADR; the
  rest hosted, pure and session tests. Rejected: more GUI tests (merge-gate rule).
- **Existing artefacts are kept** — ADR-0085/0086 and `docs/plans/note-workflow-n4*.md` cite the chain
  SPEC's numbering (R-29..R-34, R-44). This SPEC renumbers locally (R-01..) and maps each to its chain
  id; `/workplan` repoints the plan, the ADRs' «Source» lines follow at ship.

## Constraints

- **The file never changes shape**: markdown, the closed four-key frontmatter, flat namespaced tags,
  JSON Canvas 1.0; no `IndexCache.schemaVersion` change; one setting key added to the vault's
  settings file (app configuration, not note content) — origin: CLAUDE.md principles 1, 3, 4.
- **One guarded write door**: every write through the session with `expecting:` or `expectingAbsent:`;
  state read before an `await` is re-read after it — origin: ADR-0043 §D7/§D8, ADR-0057 §D3.
- **List rows**: flat rows in `List(selection:)`, no nested `.contextMenu`, focus set on selection
  change per ADR-0070; a sidebar `.badge` goes before `.tag` — origin: ADR-0024, ADR-0069, ADR-0070.
- **A banner above an `HSplitView` must not change height**: the toast is a constant-height overlay —
  origin: ADR-0075.
- **A command catalogue is the one source of every surface** — origin: ADR-0023 §D1.
- **Connectors**: new behaviour in `Sources/Connector`, writes behind `--allow-write`, `dryRun`
  default true, `undo` never deletes — origin: ADR-0007 §D2/§D4/§D6, ADR-0063.
- **Mockups first**: the pane, the generalised sheet and the composer sheet are approved on the Debug
  build in their own PR before any view is written — origin: SPEC §11.1, chain decision.
- **Tokens only; fully offline; protected interfaces untouched** (`ContenitoreScheda.render`,
  `ImportNaming.recordingNoteTitle`) — origin: CLAUDE.md.
- **`CompletingTextView+Pasteboard.swift` is not touched**; the slash selection stash lives in a new file —
  origin: protected file.

## Stack

Swift 6, SwiftUI with AppKit for the editor, Swift Testing, the shared connector layer compiled into
`perg` and `pergamenum-mcp`. No new dependency.

## Data model

No new storage. `status-inbox` is an ordinary tag. New settings key: the daily template, a vault-
relative path under `Templates/` (absent or empty means none; any other value is ignored with a
recorded problem). `Resolved` template = body plus an optional caret offset in UTF-16 units. A tab
carries a transient pending caret. The creation offer is `{path, createdHash, expiresAt}`, at most one,
a new creation replacing it.

## API / interfaces

- Rule: `NoteClassification.classify(tags:topics:vocabulary:)`; the scheda rule keeps its signature.
- Session: classify a note (guarded write, then optional move, outcome naming both); extract a range
  (create, then replace, outcome naming both); the daily note's birth returns path, created flag and
  caret, and `dailyNote(for:)` keeps its signature.
- Templates: resolve (`{{title}}`, `{{date}}`, `{{time}}`, `{{cursor}}`); compose a capture into a
  template; resolve a template reference by path or title, refusing unknown and ambiguous ones and
  listing the available templates.
- Catalogue: `paneUnfiled` (Ctrl+Cmd+I), `classifyNote` and `extractToNote` (shipped unbound).
- Connectors: `perg note classify`, `perg note extract`, MCP `classify_note`, `extract_to_note`;
  `--template` on `perg note new` and `perg capture` (note destination only) and on MCP `create_note`
  and `capture`. Topics are one comma-separated string; lines are 1-based and inclusive.

## UI flows

- **Capture to filing**: Ctrl+Opt+Space, a thought, Return; Ctrl+Cmd+I shows it in «Da classificare»
  (date, newest first, folder filter with counts); Return on a row opens «Classifica…»: topics with
  vocabulary completion and blocking, optional folder, frontmatter preview with `status-inbox` struck
  through and «N di 7 tag»; confirm moves it and the selection advances to the next row.
- **Daily note**: Cmd+Shift+D opens a day created from the template, `{{time}}` resolved, caret at
  `{{cursor}}`; reopening an existing day moves no caret.
- **Capture «Nota nuova»**: a template menu under the destination; the captured text goes at the
  cursor marker or after the body.
- **Composer**: Cmd+N and Quick Open's create row (pane host, prefilled), Workspace «Documento»
  (sheet, folder fixed); template menu in every host but the extract mode.
- **«Estrai»**: select two paragraphs, `/estrai` (or Modifica): a sheet prefilled with the derived first-
  line title and a selection preview; confirm leaves the source in front holding `[[Titolo]]`.
- **Toast**: «Nota creata · Annulla» at the bottom of the Note pane for 10 seconds.

## Edge cases

- A scheda row carries a document glyph; its «Classifica…» opens the scheda form (no folder field).
- Templates and event notes carrying `status-inbox` are listed like any note.
- A `status-*` among the given topics suppresses `status-inbox` (PG-390); the classification rule
  removes `status-inbox` regardless.
- `/` typed over a selection replaces it: a one-shot stash restores it before running a command that
  takes the selection; without a stash those entries are not offered; any other outcome drops it.
- «Estrai» on a dirty source: save, re-read the tab after the `await`, confirm the text is still at the
  range, then call the door. The replacement is not on the editor's undo stack.
- «Estrai» whose second write is refused: the new note stays, both outcomes named in the sheet.
- «Annulla» refused with a sentence when a tab shows unsaved changes or the hash moved since creation;
  a write landing between the check and the trash is trashed with the note (accepted residual, the
  file goes to the Finder Trash).
- A template naming `{{cursor}}` twice, or a title containing the marker: first real marker wins,
  typed text is written as typed.
- The Oggi pane's embedded daily editor is not a tab and does not consume the caret.
- A connector `undo` reverses a classification in two steps (move, then write); a creation is declined.
- The toast is absent after its window; the note stays.

## Test seams

Existing seams, highest level possible, fewest: (1) pure and session unit tests in `PergamenumTests` for
the classification rule, `TagEntry`, template resolution and composition, the extraction plan, the
creation offer, `classifyNote`/`extractToNote`/`dailyNoteBirth` ordering and refusal; (2) hosted-view
tests for the pane rows and empty state, the sheets, the composer hosts and the toast; (3) connector
tests plus `scripts/mcp-smoke.py` after the MCP change; (4) two GUI tests on `PergamenumUITestCase`
(filing a capture; the daily template), the only place a menu shortcut reaching a pane, list keyboard
focus and a sheet over a key window can be seen. The Contenitore's classification suite stays green
unmodified. **To confirm at the gate.**

## Success criteria

- [ ] R-01 — (chain R-29) «Da classificare» sits in LAVORO after «Attività», opens with Ctrl+Cmd+I and
  lists every note carrying `status-inbox`, schede included, sorted by date newest first, with a folder
  filter that hides when empty and flat keyboard-navigable rows (Return runs «Classifica…»).
- [ ] R-02 — (chain R-30) One rule classifies any note: topics added, `status-inbox` removed, `type-note`
  kept, at most seven tags, a closed-family value outside the vocabulary or a malformed or date-shaped
  topic refused; the Contenitore classification suite passes unmodified.
- [ ] R-03 — (chain R-30) «Classifica…» writes the frontmatter once with `expecting:` and then optionally
  moves the note; a refused write moves nothing; a failed move is reported with the note already
  classified; open tabs follow.
- [ ] R-04 — (chain R-30) «Classifica…» is reachable from the pane, the note row menu, the slash menu and
  the command catalogue (unbound by default), and its sheet previews the frontmatter with `status-inbox`
  struck through.
- [ ] R-05 — (chain R-30) `perg note classify` and MCP `classify_note` classify and optionally move,
  behind `--allow-write` with `dryRun` true by default, returning the diff.
- [ ] R-06 — (chain R-31) A daily-template setting (a note under `Templates/`, absent means none) makes
  Cmd+Shift+D, `pergamenum://today`, capture «Oggi», the event note's day and the diary mirror create
  the day from it; a missing or unreadable template creates the day empty and records a problem.
- [ ] R-07 — (chain R-31) `{{time}}` resolves to `HH:mm`; `{{cursor}}` is never written, the first
  occurrence gives the caret and the others are removed; `{{title}}`/`{{date}}` and unknown
  placeholders behave as before.
- [ ] R-08 — (chain R-31) A day opened by the call that created it places the caret at `{{cursor}}`;
  reopening an existing day moves no caret; «Applica un template…» places it too.
- [ ] R-09 — (chain R-31) Capture «Nota nuova» offers a template menu whose result composes the title,
  the captured text and the template in one write; «Task», «Oggi» and «In una nota» offer none.
- [ ] R-10 — (chain R-31) `perg` and MCP accept `--template` by path or title on note creation and
  capture, refuse an unknown or ambiguous reference listing the templates, and remove `{{cursor}}`.
- [ ] R-11 — (chain R-32) The composer is the one naming surface: hosted in the Note pane (existing
  identifiers and `ComposerUITests` unmodified), in a sheet for Workspace «Documento» (folder fixed to
  the board's folder) and for «Estrai», and by Quick Open's create row, prefilled, instead of writing at
  the vault root.
- [ ] R-12 — (chain R-32) The composer's topic field completes from the vocabulary, blocks a
  closed-family violation, refuses `type-*`/`status-*`, offers `client-`/`project-` chips from used
  values, and enables «Crea» only when the resulting tags validate.
- [ ] R-13 — (chain R-33) «Estrai in una nota» (slash and Modifica, enabled by a non-empty selection)
  creates a note holding the selection and replaces it with `[[Titolo]]`, the title prefilled from the
  selection's first line, the source frontmatter untouched, a range touching it refused.
- [ ] R-14 — (chain R-33) A refused second write keeps the new note and names it; a dirty source is
  saved first through «Salva ed estrai» and the range is re-verified after the save.
- [ ] R-15 — (chain R-33) `perg note extract` and MCP `extract_to_note` extract a 1-based inclusive line
  range the same way, behind `--allow-write` with `dryRun` true by default.
- [ ] R-16 — (chain R-34) After a pane-host creation a «Nota creata · Annulla» strip of constant height
  shows for 10 seconds; «Annulla» moves the note to the Trash and forgets its id, refusing with a
  sentence when a tab has unsaved changes or the file changed; after the window the note stays; no
  other creation path offers it.
- [ ] R-17 — Exactly two GUI tests, one filing a capture from Ctrl+Cmd+I to a classified, moved note and
  an empty pane, one the daily template, each on `PergamenumUITestCase` (no-test: counted by review, a
  structural limit rather than a behaviour).
- [ ] R-18 — (chain R-44, R-45) The milestone ships as its own PR after its mockup PR, closes #889 and
  `PG-387`, closes `PG-121` with a note, records ADR-0085 and ADR-0086 with numbers re-checked at merge;
  `perg`, `pergamenum-mcp` and the app build and `scripts/mcp-smoke.py` passes (no-test: release
  process and build, checked at the /ship gate).

## Not yet specified

_none_

## Out of scope

- **A template engine (`PG-121`)** — the delivered-template need is covered by `{{time}}`/`{{cursor}}`,
  the setting and the menus; the engine is not recommended now (ledger, 2026-10-03).
- **An app-side write journal** — ADR-0007 §D6 stays; the toast is cheaper and enough.
- **The toast for Workspace, «Estrai», daily/event notes, capture, Pratiche and connectors** — each
  excluded for the reason recorded in Decisions.
- **A delete verb in the pane** — nothing is deleted from «Da classificare».
- **On-disk format, frontmatter schema, index schema** — unchanged.
- **N3's three prerequisites** — built by N3, not here.

## Domain terms

- **Capture** — a note born without a topic: it carries `status-inbox` until classified, whatever path
  created it.
- **«Da classificare»** — the pane listing captures (notes). Not «Attività ▸ Inbox», which lists tasks.
