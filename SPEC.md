Status: Approved (2026-09-29)

# SPEC — Contenitore: a managed document archive fed from a drop folder

## Destination

An approved SPEC handed to `/workplan`: a new app section, «Contenitore», where any file dropped
into one watched folder outside the vault is moved into the vault, parsed for text, given a
markdown record («scheda») carrying description, colour and tags, and reachable through a stable
`pergamenum://` link. `/workplan` decides the ADR and how many PRs this takes.

## Objectives

Stefano drops documents (quotes, invoices, certificates, scans, photos, anything) into one folder
and stops thinking about where they go. Pergamenum files them in the vault, makes their content
searchable (including scans, through on-device OCR), keeps them in a queue until he classifies
them, and gives each one an address he can paste into a note, Mail or DEVONthink that keeps
working after the document is renamed or moved inside the app.

## Scope and non-goals

In: one configurable drop folder; automatic move-and-record while the app runs (and a catch-up at
launch); a scheda note per document; text extraction for PDFs, images and plain text, OCR for
scans and images; extracted text in the derived cache and reachable from global search; a
«Contenitore» pane with a nested sub-container tree, list/grid, inspector, a «Da classificare»
queue, colour and tag filters; «Classifica»; rename, move and trash of document and scheda as a
pair; duplicate refusal; a new `pergamenum://contenitore?id=` route and «Copia link Pergamenum».

Out (detail in Out of scope): dedicated connector commands, several drop folders with rules,
Office text extraction, structured field extraction, Finder tag/colour mirroring, adopting files
placed in the vault by hand, GUI tests.

## Decisions

- **Metadata lives in a scheda `.md` beside the file** — every document gets an ordinary note whose
  frontmatter carries `date`, `tags` and `pergamenum-contenitore-*` keys and whose body is the
  description. Search, tags, backlinks, the linter, the note-ID registry and both connectors work
  on it with no new store. Rejected: one registry JSON in `.pergamenum/` — metadata readable only
  by the app (weakens Principle 1), and tags/description invisible to search and linter without
  extending both. Rejected: Finder tags/colour/comment as the source of truth — xattrs are lost by
  zip, git and some copies, and the Finder has only 7 colours; also rejected as a v1 mirror,
  because Spotlight already reads PDF text and the files are managed from the app.
- **Ingest: one drop folder outside the vault, files moved in** — default `~/Pergamenum Drop`,
  configurable. Rejected: copy (two diverging originals); drop folder inside the vault (mixes
  untriaged input with the archive); several drop folders with rules (more settings than the
  need justifies now).
- **Auto-import into a «Da classificare» state** — a file is moved and recorded as soon as it is
  stable; the scheda is born `type-note` + `status-inbox`. Rejected: an approval queue before the
  move (an extra gesture per file); import with no queue (unclassified documents disappear into
  the archive).
- **Any file type is accepted; text is extracted only where possible** — PDF text layer, OCR for
  image-only PDFs and images, plain text files read directly. Other files get scheda, preview and
  metadata only. Rejected: PDF and images only; Office extraction (no system library, much more
  work).
- **Layout `<root>/[<sub-container>/…]/YYYY/`, scheda beside file** — imports land in
  `<root>/YYYY/`; moving a document into a sub-container puts the pair in `<sub-container>/YYYY/`.
  Year folders are managed by the app and are not tree nodes. Rejected: a `file/` subfolder for
  binaries (a second folder per year for no gain); a flat folder (unbounded growth); year folders
  only at the root; sub-containers without years.
- **Sub-containers are a nested tree of real folders under the root** — created, renamed, moved and
  trashed from the pane's own sidebar, flat recursive rows as in ADR-0024, drag and drop of
  documents. A document sits in exactly one sub-container; tags cover cross-cutting grouping.
  Rejected: a single level.
- **Root folder configurable** — default `Contenitore/` at the vault root, changeable like the
  Pratiche folder. Rejected: a fixed name.
- **Names: `YYYYMMDD <original name>`** — import date in front, original stem sanitised with the
  note-title rules; the file keeps its extension, the scheda has the same stem. A taken name gets
  the existing unique-name suffix, applied to the pair. Rejected: original name alone (no
  chronological order in the Finder).
- **`date` is the import date, editable** — consistent with the name prefix; corrected by hand in
  the inspector. Rejected: date from EXIF/PDF metadata (often absent or wrong).
- **Duplicates are refused** — SHA-256 of the incoming file compared with the hashes recorded in
  existing schede; a duplicate stays in the drop folder with a notice that links the existing
  document. Rejected: importing it anyway (two records of one document); trashing it (silent loss
  of a file the user just placed).
- **Extracted text lives in the derived cache, and global search reads it** — keyed by the file's
  content hash, under the vault's Application Support state (ADR-0017); a hit on extracted text
  returns the scheda. Deleting the cache loses only the time to re-extract. Rejected: text in the
  scheda body (a 100-page scan makes an enormous note in the editor); an excerpt in the body plus
  the full text in cache (two places to keep coherent).
- **OCR runs in the background on every page, Italian and English, on-device only** — only for
  PDFs without a text layer and for images; progress visible in the list. Rejected: a 50-page cap
  (the rest of a long scan would be unsearchable).
- **Colour: the six JSON Canvas presets** — Rosso, Arancio, Giallo, Verde, Ciano, Viola, drawn with
  the existing `color.sticky.*` tokens, stored as a name, never a hex. Rejected: the five task
  category colours.
- **«Classificato» means `status-inbox` removed and at least one `topic-*` present** — «Classifica»
  asks for one or more `topic-*` and offers an optional content type from the closed `type-*`
  vocabulary (e.g. `type-invoice`, `type-contract`); description and colour stay optional.
  Rejected: «a description is enough» (the scheda would then fail the linter's `topic-*` rule).
- **The link points at the scheda's note ID, and opens the pane** — `pergamenum://contenitore?id=`
  uses the scheda's ID from the ADR-0059 registry (which accepts only `.md`) and selects the
  document in the Contenitore pane; `note?id=` keeps opening the scheda in the editor. Rejected:
  opening the file directly (skips the metadata); `note?id=` only (no pane context).
- **Rename and move always act on the pair** — from the Contenitore pane and from the Note pane
  when the note is a scheda; wikilink and ID follow. Rejected: scheda only (pair drifts apart).
- **Delete trashes file and scheda together** — one command, Finder Trash, never a permanent
  removal. Rejected: asking each time.
- **Connectors get the Contenitore for free through notes** — no dedicated `perg`/MCP commands in
  v1; schede are notes, and the extended search is shared code. Rejected: a dedicated read (or
  read-write) API, deferred until a need appears.
- **Tests: the ingest engine is the main seam, zero GUI tests** — see Test seams.

## Constraints

- **File over app** — every piece of metadata is readable on disk without the app. Origin:
  CLAUDE.md Principle 1.
- **Fully offline** — no network call; OCR and text extraction are on-device. Origin: Principle 2.
- **Rebuildable index** — extracted text and thumbnails are derived state outside the vault.
  Origin: Principle 3, ADR-0017.
- **Closed frontmatter** — only `date`, `tags`, `related`, `aliases` plus `pergamenum-` prefixed
  keys; new prefixed keys need an ADR. Origin: SPEC §4.3, ADR-0032/0036 precedent.
- **Closed tag vocabulary** — `type-*` and `status-*` from `vocabolari.json`, at most 7 tags, one
  `status-*`. Origin: SPEC §4.4, Principle 5.
- **Note naming** — forbidden characters and 60-character title limit apply to the scheda. Origin:
  SPEC §4.2.
- **Every vault write goes through `VaultSession`** with the existing guards (boundary resolver,
  `expecting:` preconditions, landed-change door). Origin: ADR-0041, 0043, 0067.
- **Trash, never remove** — Origin: ADR-0022.
- **Tokens only in views** — Origin: CLAUDE.md Design system.
- **UI in Italian** — Origin: CLAUDE.md.
- **Mockup approved before the pane is built** — Origin: CLAUDE.md Design system.

## Stack

Swift 6, SwiftUI with AppKit where needed. PDFKit for text layers, Vision for OCR,
QuickLookThumbnailing through the existing thumbnail store, FSEvents for the drop-folder watcher
(the Pratiche mail-store watcher is the model). No new dependency.

## Data model

A **document** is a pair in the same folder: the file `YYYYMMDD <name>.<ext>` and its scheda
`YYYYMMDD <name>.md`. A note is a scheda when it sits under the Contenitore root and carries
`pergamenum-contenitore`.

Scheda frontmatter (key names indicative, final names in the ADR):

```yaml
date: 2026-09-29
tags:
  - type-note
  - type-invoice            # optional content type, after «Classifica»
  - topic-<something>       # required once classified
  - status-inbox            # present until classified
pergamenum-contenitore: 1                               # schema version
pergamenum-contenitore-file: "[[20260929 preventivo.pdf]]"
pergamenum-contenitore-original: "preventivo.pdf"       # name as dropped
pergamenum-contenitore-sha256: "<hex>"                  # duplicate detection
pergamenum-contenitore-color: giallo                    # optional, one of six names
```

Body: the description, free markdown.

A **sub-container** is a folder under the root that is not a year folder. Year folder names are
four digits; a sub-container may not be named with four digits.

**Extracted text** is a derived record keyed by the file's SHA-256: extraction method (text layer,
OCR, plain text, none), status (pending, done, failed), text. Renaming or moving a file does not
invalidate it.

**Import state** of a drop-folder file: waiting for stability, imported, refused as duplicate,
failed (with reason).

## API / interfaces

- New route `pergamenum://contenitore?id=<uuid>`: resolves the scheda through the note-ID registry
  and selects the document in the Contenitore pane; an unknown id reports a problem and opens the
  pane with nothing selected.
- «Copia link Pergamenum» on a document copies the `contenitore?id=` form, minting the scheda's ID
  if it has none (ADR-0059's mint-on-demand rule).
- New settings: drop folder path (stored `~`-relative), Contenitore root folder.
- Global search: results also match extracted text of schede.
- Connectors: no new command; they see schede as notes and share the extended search.

## UI flows

- **Sidebar**: «Contenitore» in the LAVORO group beside Pratiche.
- **Pane**: a left column with «Tutti», «Da classificare» (with count) and the sub-container tree;
  a centre list (thumbnail, name, colour dot, tags, date, OCR state) with a toggle to a thumbnail
  grid; filters by colour and tag; spacebar Quick Look (SPEC §6.6).
- **Inspector**: preview, name, date, description, colour (six swatches), tags (vocabulary
  autocompletion), sub-container, and actions «Classifica», «Apri», «Mostra nel Finder», «Apri
  scheda», «Copia link Pergamenum», «Sposta nel Cestino».
- **Classifica**: a sheet asking for one or more `topic-*` and an optional content type; confirm
  removes `status-inbox`.
- **Notices**: duplicates, failed imports and failed extractions appear as non-modal notices in the
  pane, each naming the file.
- Every action in the inspector also exists in the row context menu and the menu bar (ADR-0023
  parity).

## Edge cases

- File still being written or downloaded in the drop folder: imported only once its size is stable
  across two observations.
- iCloud placeholder (evicted) in the drop folder: skipped with a notice.
- Hidden files and subfolders in the drop folder: ignored; subfolders reported once.
- Drop folder missing: created at first use; unreadable: one visible notice, nothing imported.
- Files arriving while the app is closed: imported at the next launch.
- Name collision in the target year folder: the unique-name suffix is applied to file and scheda
  together, never to one only.
- Move fails half-way (file moved, scheda write refused or failed): the file is put back in the drop
  folder and the failure is reported; no orphan file is left in the vault.
- File deleted outside the app while its scheda remains: row shows «file mancante».
- Scheda edited by hand to drop `pergamenum-contenitore`: it stops being a document.
- `date` edited to another year: the pair does not move.
- Image-only PDF with no recognisable text, or an unsupported type: extraction status «nessun
  testo», document still searchable by name, description and tags.
- OCR failure on one file does not stop the queue.

## Test seams

- **Ingest engine at `VaultSession` level** (main seam, the `PraticaSyncTests` shape): temporary
  drop folder and vault, text extractor behind a protocol with a fake. Covers move, naming, pairing,
  duplicates, stability wait, half-way failure, catch-up, classify, rename/move/trash as a pair,
  sub-container operations.
- **Pure `Sources/Core` units**: scheda render/parse round-trip, name and path rules, classify
  validation, colour names, route parsing.
- **Search**: `VaultSession.search` with a pre-seeded extracted-text cache.
- **Real extractors**: one PDFKit test on a PDF fixture with a text layer, one Vision OCR test on a
  small image fixture.
- **UI**: one in-process hosted-view test of the pane. Zero GUI tests.

## Success criteria

- [ ] R-01 — A file placed in the drop folder while the app runs is moved to `<root>/YYYY/` as
  `YYYYMMDD <sanitised original name>.<ext>`, with a scheda of the same stem beside it, and is no
  longer in the drop folder.
- [ ] R-02 — The scheda carries `date` (import date), `tags` with `type-note` and `status-inbox`,
  the `pergamenum-contenitore*` keys for schema version, file wikilink, original name and SHA-256,
  and passes the linter.
- [ ] R-03 — A file still growing in size is not imported until its size is stable across two
  observations.
- [ ] R-04 — Files present in the drop folder at launch are imported.
- [ ] R-05 — A file whose SHA-256 matches an existing scheda stays in the drop folder and produces a
  notice naming the existing document.
- [ ] R-06 — A name already taken in the target folder gets the same unique suffix on file and
  scheda.
- [ ] R-07 — If the scheda cannot be written after the file moved, the file is back in the drop
  folder and the failure is reported.
- [ ] R-08 — Hidden files, subfolders and iCloud placeholders in the drop folder are not imported;
  placeholders and subfolders produce a notice.
- [ ] R-09 — Text is extracted from a PDF's text layer, from image-only PDFs and images by OCR
  (Italian and English), and from plain text files, into the derived cache keyed by content hash,
  in the background, with progress visible in the list.
- [ ] R-10 — Global search (app and connectors) returns a scheda when the query matches its file's
  extracted text; deleting the cache removes no vault file.
- [ ] R-11 — An extraction failure or a file with no text leaves the document listed with status
  «nessun testo» and does not stop other extractions.
- [ ] R-12 — No network call is made by import, extraction or the pane.
- [ ] R-13 — The Contenitore pane lists every scheda under the root, with thumbnail, name, colour,
  tags, date and extraction status, in list and grid modes.
- [ ] R-14 — «Da classificare» lists exactly the schede carrying `status-inbox`, with a count.
- [ ] R-15 — Filters by colour and by tag narrow the list.
- [ ] R-16 — Editing description, date, colour and tags in the inspector writes the scheda through
  the guarded write path; a scheda changed on disk since it was read is refused, not overwritten.
- [ ] R-17 — Colour accepts only the six preset names and is drawn with the `color.sticky.*` tokens.
- [ ] R-18 — «Classifica» requires at least one `topic-*`, offers an optional `type-*` from the
  vocabulary, removes `status-inbox`, and the result passes the linter.
- [ ] R-19 — Sub-containers can be created, renamed, moved and trashed from the pane's tree, nested
  to any depth; a four-digit name is refused.
- [ ] R-20 — Moving a document into a sub-container puts file and scheda in
  `<sub-container>/YYYY/` (year of the scheda's `date`) and updates the file wikilink.
- [ ] R-21 — Renaming a scheda (from the Contenitore pane or the Note pane) renames its file to the
  same stem; the file wikilink and the note ID follow.
- [ ] R-22 — «Sposta nel Cestino» moves file and scheda to the Finder Trash together.
- [ ] R-23 — «Copia link Pergamenum» copies `pergamenum://contenitore?id=<uuid>`, minting the ID if
  needed; opening that link selects the document in the pane, and after an in-app rename or move it
  still does.
- [ ] R-24 — An unknown `contenitore?id=` opens the pane with nothing selected and reports a
  problem.
- [ ] R-25 — A scheda whose file is gone shows «file mancante».
- [ ] R-26 — Drop folder and root folder are configurable in Impostazioni; the drop folder is
  created if missing, and an unreadable one produces one visible notice.
- [ ] R-27 — Every inspector action is available from the row context menu and the menu bar.
- [ ] R-28 — The pane's mockup is approved before it is built. (no-test: design process gate, no code)
- [ ] R-29 — The new `pergamenum-contenitore-*` keys, the pane and the route are recorded in an ADR
  and in SPEC §9. (no-test: documentation obligation)

## Assumptions

- Import and extraction run only while the app is open; there is no background agent.
- The drop folder path is stored `~`-relative in the vault settings, so it resolves on any Mac the
  vault syncs to.
- Wikilinks and embeds to the file elsewhere in the vault are rewritten on a pair rename the same
  way note renames rewrite links; if the existing rename machinery cannot do this for a non-`.md`
  target, `/workplan` states the cost.
- Vision text recognition runs entirely on-device on macOS 27 (to be confirmed against the live
  SDK documentation at `/workplan`).
- The pane's keyboard shortcut is chosen at `/workplan` (digit shortcuts are used up).

## Out of scope

- Dedicated `perg`/MCP commands — schede already reach the connectors as notes; add when a need
  appears.
- Several drop folders with rules — one folder covers the stated need.
- Office (docx/xlsx/pptx) text extraction — no system library; scheda and preview only.
- Structured field extraction (invoice number, supplier, amount) — much larger, separate feature.
- Finder tag/colour mirroring — can be added later without changing the on-disk format.
- Adopting files placed under the root by hand without a scheda — v1 records only what passes
  through the drop folder.
- GUI tests — the ingest engine and hosted-view test carry the coverage.

## Not yet specified

- Whether files put under the root by hand (Finder, board drops) should later be offered a «Crea
  scheda» action.
