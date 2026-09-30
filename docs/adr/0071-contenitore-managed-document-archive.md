# ADR-0071: Contenitore, a managed document archive fed from a drop folder

- Status: accepted. PR 1 of the two (see "Delivery") landed on `main` via PR #691 (merge
  `32b5ecd3`, 2026-09-29): the Core units, the index field, the session doors, the ingest engine,
  the extraction store and queue, and search, all dormant. PR 2 (controller, watcher, settings,
  route, pane) landed on `main` via PR #721 (merge `1535c2d9`, 2026-09-30). Flipped at PR 1 rather
  than PR 2 because `docs/adr/README.md` rule 2 keeps `proposed` for an ADR whose implementation
  is not on `main` at all, the shape ADR-0053 already took for a multi-PR plan.
- Date: 2026-09-29
- Numbering: the highest number on `origin/main` (`29307ccc`) was 0070 when this was written. Two
  unmerged `origin/docs/adr-0065-*` branches exist. Recheck `origin/main` and every branch about to
  merge immediately before this record's own merge (README rule 1).
- Source: the approved SPEC «Contenitore: a managed document archive fed from a drop folder»
  (root `SPEC.md`, Approved 2026-09-29), R-01..R-29. Plan: `docs/plans/contenitore.md`.
- Extends: ADR-0059 §D5/§D8 (a scheda's id follows the pair), ADR-0067 §D1/§D8 (the ingest door
  announces nothing), ADR-0041 §D1 (every new path resolves through `VaultBoundary`), ADR-0022
  (trash, never remove; skip an ambiguous rewrite and report it), ADR-0024 (flat rows), ADR-0023
  §D1 (one command catalogue), and ADR-0070 §D4 (Quick Look beside a `List`).
- Amends: none.
- Bumps the protected `IndexCache.schemaVersion` 6 → 7 (gate G1). Approved as 5 → 6; PG-316 took 6 on `main` first, so the same bump became 6 → 7 at merge.

## Context

The SPEC decides what Contenitore is:

- one drop folder outside the vault;
- a file moved in on arrival;
- a scheda note beside it;
- text extracted into derived state;
- a pane;
- pair operations;
- a `pergamenum://contenitore?id=` route.

Its `## Decisions` are registered here as they stand and not reopened. This record decides what the
SPEC left to design, and records the new keys, the pane and the route as R-29 requires. Reading the
code, rather than the SPEC, produced the following facts, and they shape the decisions below.

1. **The index keeps no foreign key.**
   - `StoredFrontmatter` stores `date`, `tags`, `aliases` and `related` only.
   - A `pergamenum-*` key survives a cache reuse only when it gets its own field, as `categorySlug`
     did (ADR-0047 §D5, schema 4).
   - ADR-0049 §D4 read its keys off the file instead, because a pratica has only a handful of
     links.
   - The Contenitore pane needs every scheda's file name, colour and hash on every refresh. The
     duplicate check needs every hash for each incoming file.
2. **`VaultDisk.moveFile` and `restoreFile` derive a note record for any file.**
   - They read the moved file whole (`Data(contentsOf:)`, `VaultDisk.swift:422`, `:468`) and hand
     it to `store.record(from:)`.
   - Today every existing `moveFile` caller and test moves a `.md`, so nothing moves a non-note
     file through them.
   - A PDF moved through the door would be read whole into memory. A `.txt` or `.csv` would be
     indexed as a phantom note.
3. **`VaultSession.trashFile` reads the whole file on the main actor** for the journal's
   `textBefore` (`VaultSession+Journal.swift:159`), whatever the file type.
4. **`restoreFromOutside(_:to:)` is not an ingest door.**
   - It refuses a missing parent folder on purpose (PG-168, ADR-0068 §D2).
   - It hashes the source on the main actor and treats the file as a note.
   - An import must create `<root>/YYYY/`, hash off the main actor, and never index the binary.
5. **The link-rewrite rule already handles a non-`.md` target.**
   - `NoteRename.rewritingLinks(in:from:to:)` matches `fold(link.resolvedTitle) == fold(oldTitle)`,
     and `resolvedTitle` is the target as written (`Wikilink.swift:29`).
   - Given the full file name `20260929 preventivo.pdf`, it rewrites `[[20260929 preventivo.pdf]]`
     and `![[20260929 preventivo.pdf|400]]`. It keeps the embed mark, the section and the size
     suffix, because `rendered` rebuilds all three.
   - It does not match the scheda's own title `[[20260929 preventivo]]`, and the title rewrite does
     not match the file link.
   - The rewrite covers the scheda's own `pergamenum-contenitore-file` key too, because the pass
     scans the whole text.
   - What is missing is the plan layer. `NoteFileOperations.renamePlan` knows only `.md` titles.
     Two rewrites of one note must also be composed into one `VaultFileChange`, or the second
     guarded write is refused by the hash the first one changed (ADR-0046 §D1).
6. **Attachments resolve by name anywhere.** `Attachment.resolve` looks beside the note, then from
   the vault root, then by name. A bare-name file link survives a move with no rewrite.
7. **Naming rules that bite a scheda.**
   - `NoteName.category` calls any stem that is exactly `YYYYMMDD` a daily note.
   - `NoteName.validate` flags a trailing `v2`-style token.
   - `ImportNaming.truncatedAtWordBoundary` splits on hyphens only, so it cannot cut a
     space-separated name. Two protected names' tests pin it, so it must not be edited.
8. **Vision, checked live on 2026-09-29** against Xcode 27.0 (27A266a) and macOS 27.0.1:
   - `VNRecognizeTextRequest.supportedRecognitionLanguages()`, run on this Mac, lists `it-IT` and
     `en-US` at both the accurate level (33 languages) and the fast level (6 languages).
   - The Swift `RecognizeTextRequest` lists the same two.
   - The SDK header `VNRecognizeTextRequest.h` declares `recognitionLanguages`, `recognitionLevel`,
     `usesLanguageCorrection` and `automaticallyDetectsLanguage`. Its revision 2 note lists Italian.
   - Apple's "Recognizing text in images" documentation says: "In all cases, all of Vision's
     processing happens on the user's device to enhance performance and user privacy."
9. **The shortcut, measured on this Mac.**
   - `com.apple.symbolichotkeys` has 58 entries. None uses keycode 8 (`c`).
   - The only Ctrl+Cmd entries are ids 21, 25 and 26 (Ctrl+Opt+Cmd, disabled) and 29 and 31
     (Ctrl+Shift+Cmd, disabled).
   - No `ShortcutCommand.defaultBinding` and no hard-coded `keyboardShortcut` in `Sources/` uses
     Ctrl+Cmd+C.
   - The pane digits are spent. Pratiche took Ctrl+Cmd+P for the same reason.
10. **The state directory is shared.** `VaultState`'s base is keyed by `AppInfo.bundleIdentifier`,
    so `perg` and `pergamenum-mcp` resolve the same `vaults/<id>/` directory as the app.

## Decision

### §D1 A document is a pair; the scheda's keys are final

A document is two files in one folder: `<stem>.<ext>` and its scheda `<stem>.md`. A note is a scheda
when it sits under the Contenitore root and its frontmatter carries `pergamenum-contenitore: 1`.

The keys are the SPEC's indicative names, now final:

| Key | Value | Written |
|---|---|---|
| `pergamenum-contenitore` | integer schema version, `1` | always |
| `pergamenum-contenitore-file` | `"[[<stem>.<ext>]]"`, a bare file-name wikilink | always |
| `pergamenum-contenitore-original` | `"<name as dropped>"` | always |
| `pergamenum-contenitore-sha256` | `"<64 lowercase hex>"`, the file's hash at import | always |
| `pergamenum-contenitore-color` | one of `rosso`, `arancio`, `giallo`, `verde`, `ciano`, `viola` | only when set |

- **A new scheda** has `date` (the import day), `tags: [type-note, status-inbox]`, the four keys
  that are always written, and an empty body. It passes the linter as written, because
  `status-inbox` exempts the `topic-*` requirement (`TagRules.missingRequired`).
- **Another schema value.** A value other than `1` is not a scheda for this version. The note stays
  an ordinary note, and its keys are preserved byte for byte (ADR-0065 §D2).
- **Colours.** The six colour names are the six JSON Canvas presets, in order: 1 rosso, 2 arancio,
  3 giallo, 4 verde, 5 ciano, 6 viola.
  - They are drawn through the same preset-to-token mapping as the sticky card: `stickyPink`,
    `stickyOrange`, `stickyYellow`, `stickyGreen`, `stickyBlue`, `stickyPurple`.
  - That mapping is extracted once, so the board and the pane cannot drift apart.
  - An unrecognised colour value reads as "no colour" and stays on disk untouched until the colour
    is set again.
- **One type.** Render and parse live in one pure type, `ContenitoreScheda`
  (`Sources/Core/Contenitore/`). Edits go through `NoteDocument`/`FrontmatterSource`, so a colour
  change rewrites one line.

### §D2 The index carries the scheda's facts; `IndexCache.schemaVersion` 6 → 7

- `NoteRecord` gains `contenitore: ContenitoreFacts?`: file name, original name, hash and colour.
  - `NoteStore.record(from:)` fills it through `ContenitoreScheda.facts(in: foreignKeys)`.
  - It is `nil` for any note without `pergamenum-contenitore: 1`.
- `StoredRecord` gains the matching optional field, defaulted as `categorySlug` is.
- "Under the root" is not stored. It is a setting, evaluated at read time by one helper on the
  snapshot, so changing the root needs no rescan.
- The bump follows ADR-0047 §D5. Without it, a reused record would lose the facts from the second
  scan onward.
  - It is gate **G1**, because the version is a protected interface.
  - This chain spends the bump once. Search needs no second bump (§D9).

### §D3 `VaultDisk` derives a note record only for a `.md`

- `moveFile` and `restoreFile` read the moved bytes and derive a record only when the destination is
  a `.md`. For any other file the mutation leaves the notes index unchanged, and the bytes are never
  read.
- `VaultSession.trashFile` reads `textBefore` only for a `.md` or a `.canvas`.
  - A board keeps its text because its trash was journalled with it before this ADR, and that undo
    is pinned (`VaultAsyncCascadeTests.cascadeRawFileWriteMoveAndTrashFinishInCallOrder`).
  - Any other file's journal removal carries no text, so undo declines that entry.
  - Undo of a pair trash is refused whole; the scheda and the file stay in the Finder Trash. The
    pair never ends up split by an undo.
- `VaultSession.restoreFromOutside` reads, hashes and announces the bytes only of a `.md`. The pair
  trash's rollback (§D6) restores the binary through it, with ADR-0068 §D2's refusals unchanged.
- The undo guard, `preflightUndo`, reads no binary either.
  - A move is held to the hash of the last later `textReplacement` at the same path in the same
    gesture, when there is one: a scheda's own `pergamenum-contenitore-file` rewrite after a pair
    rename is a legitimate change, not a file that moved on.
  - A move journalled with an empty `hashAfter` (a binary, whose hash is never computed) is checked
    only for existence at its path and a free `pathBefore`.
- This is a correction in its own right. Today no caller moves a non-note file through these doors,
  so the `.md` gate changes no existing behaviour.
  - The later-rewrite rule does, deliberately: an ordinary note rename whose note mentions its own
    title used to be refused on undo, and now undoes.

### §D4 Ingest: one door in, one door back, file first

The engine, `ContenitoreIngestEngine` (app target), runs one observation per call:

1. **List the drop folder.**
   - An iCloud placeholder is skipped with a notice. This is checked before the hidden-file rule,
     since the stub is itself a dot-file. A placeholder is either a `.name.icloud` stub (the
     `VaultScanner` rule) or a dataless file whose `ubiquitousItemDownloadingStatus` is not
     `.current`.
   - Other hidden entries are ignored.
   - A subfolder is reported once per name for the life of the controller.
   - A dropped `.md` or `.canvas` is refused with a notice (gate **G3**), matched
     case-insensitively. A `.md` and its scheda would have the same name; a `.canvas` would be
     listed by Workspace as a board and renamed, moved or trashed alone by the board verbs,
     splitting the pair.
2. **Wait for stability** (R-03).
   - A file is ready when its size and modification date equal those recorded at the previous
     observation. The first sighting only records them.
   - Tests call the observation twice.
   - While anything is waiting, the controller schedules the second observation about 2 seconds
     after an event.
   - No test sleeps.
3. **Hash off the main actor.** SHA-256 is streamed over the file in chunks, so a large scan never
   sits in memory.
4. **Refuse a duplicate** (R-05). If the hash equals the `sha256` of a scheda under the root (read
   from the index, §D2), the file stays where it is, and the notice names the existing document.
5. **Name the pair** (§D5) in `<root>/<YYYY>/`, using the year of the import day.
6. **Move the file in** through a new door, `VaultSession.adoptFromOutside(_:to:)`, in
   `VaultSession+Adopt.swift` (app target). The door:
   - resolves the path through `VaultBoundary`;
   - creates missing folders and refuses an existing destination;
   - moves with `FileManager.moveItem`, which copies and removes across volumes;
   - derives no record, is not journalled, and announces nothing (ADR-0067 §D8: binaries are out
     of reach).
7. **Write the scheda** through `VaultSession.write(_:to:expectingAbsent: true)`.
8. **Roll back** (R-07). On any failure after step 6, the file goes back to the drop folder through
   `VaultSession.returnToOutside(_:to:)` and a notice names it. If that move fails too, the notice
   names the in-vault path. Nothing is ever deleted.

A file answered without being imported, a duplicate (step 4) or a rolled-back import (step 8), stays
in the drop folder with a signature the listing already holds as stable. The engine remembers that
size and date in a `declined` map, so the notice is raised once and not repeated, and the file is
neither hashed nor moved again while it is unchanged. A changed size or date, or the name leaving
the folder, clears the entry.

Ingest runs only while the app is open.

- A catch-up observation runs when the vault opens (R-04).
- Nothing mints a note id at ingest. Ids are minted on demand (ADR-0059 §D2).
- The drop folder is created at first use when it is missing. An unreadable drop folder produces one
  notice and imports nothing (R-26).

### §D5 Naming: `YYYYMMDD <name>`, unique as a pair

The stem is `YYYYMMDD`, a space, and the sanitised original stem:

- the name part goes through `NoteName.sanitized`;
- a trailing version token (`v2`, `_v10`) is dropped, so the scheda passes `NoteName.validate`, and
  the token survives in `pergamenum-contenitore-original`;
- the name part is cut at the last space that lets the whole stem, plus a `-NN` suffix, fit the
  60-character title limit;
- the cut is done by `ContenitoreNaming`'s own function, not by the hyphen-only
  `ImportNaming.truncatedAtWordBoundary` (Context 7);
- a name part that sanitises to nothing becomes `documento`, since `20260929` alone would be read as
  a daily note;
- a dot inside the stem is kept, and the extension is kept as dropped.

A stem is taken in either of two cases:

- `<stem>.<ext>` or `<stem>.md` already exists in the target folder;
- a note in the index already has the title `<stem>`.

A taken stem gets `ImportNaming`'s `-2`, `-3` suffix, applied to both files (R-06).

The index check keeps `[[<stem>]]` unambiguous across the vault. It reads only the index, so it is
cheap. It deliberately widens the SPEC's "in the target folder" (gate **G4**). The naming lives in a
new pure type, `ContenitoreNaming`, and does not touch the protected `ImportNaming.
recordingNoteTitle`.

### §D6 Pair operations live at the session's note doors

`VaultSession.renameNote`, `moveNote` and `trashNote` (`VaultSession+Files.swift`, shared) act on the
pair whenever the note is a scheda whose file is present beside it. A scheda whose file is missing
is operated on alone. The three doors refuse a non-`.md` path with «<path> non è una nota», so a
connector cannot reach the binary half on its own.

Every caller gets the pair for free:

- the Contenitore pane;
- the Note pane (`VaultController+Files.swift:41,66,93`);
- the batch move (`VaultSession+Move.swift:130`);
- both connectors (`VaultWrites.swift:127,147,165`).

**Rename.**

- `NoteFileOperations.pairRenamePlan` validates the new stem and requires both new names to be
  free.
- It composes the note-title rewrite and the file-name rewrite into one `VaultFileChange` per note,
  and one per board through `repointBoardsPlan(repoints:titleChanges:)` over a list of repoints.
- One `transaction("note rename")` runs both `moveFile`s, then `VaultPlanApplication.apply` with
  `writeGuarded` and `writeFileGuarded`.
- The id follows through `moveFile`'s `relocateNoteIDs` (R-21, R-23).
- If a different file with the companion's old name exists elsewhere in the vault, the file-name
  rewrite is skipped and reported. The note-title rewrite still happens (ADR-0022's ambiguity rule).
- CommonMark `![](x.pdf)` references are not rewritten. This is a named residual; the app never
  writes that form.

**Move.**

- `pairMovePlan(scheda:companion:toFolder:renamingTo:knownPaths:)` moves both files.
- The session's `moveNote` passes no new stem and refuses a pair that would collide.
- `VaultSession.moveDocument(at:toContainer:)` computes `<container>/<YYYY>`, where YYYY is the year
  of the scheda's `date` (R-20). On a collision it passes a unique stem in the same plan and the same
  transaction.
- A bare-name link needs no rewrite for a move (Context 6). Only when a collision renames the pair
  does the rename rewrite apply.

**Trash.** Both files go to the Finder Trash in one transaction (R-22). Dangling links are reported
for both names.

**Rollback.** When the file cannot move after the scheda did, the scheda moves back; when the
scheda cannot be trashed after the file was, the file is restored from the Trash (§D3). If the
Trash gave no URL for the file, there is nothing to restore from: the pair stays split, and the
thrown error names the file left in the Trash. A rollback that fails too is named in the thrown
error, never swallowed.

**Batch move.** `moveItems` skips an item that a scheda in the same batch already carried, instead
of failing on a missing source.

### §D7 Sub-containers are folders; year folders are the app's

- A sub-container is a folder under the root whose name is not four digits.
- Create, rename, move and trash go through the existing folder doors (`FolderFileOperations`,
  `VaultSession+Folders`). Those doors already carry notes, ids and board repoints.
- The pane refuses a four-digit name before calling them. It uses
  `ContenitoreNaming.validateContainerName`, which is `FolderName.validate` (whose result is
  `[NoteName.Violation]`) plus a separate year-name refusal (R-19).
- Year folders are not tree nodes. A year folder emptied by a move stays on disk, because nothing
  here removes.
- A four-digit folder created by hand from the Note pane is treated as a year folder. This is named,
  not fixed.

### §D8 Extracted text is derived state keyed by hash

- **Store.** `ExtractedTextStore` (`Sources/Vault/`, Foundation-only, added to `sharedSources`)
  writes one JSON file per hash, under a new `VaultState.extractedText` directory. Each record holds:
  - the method: `textLayer`, `ocr`, `plainText` or `none`;
  - the status: `pending`, `done` or `failed`;
  - the text;
  - page progress.
- **Queue.** `ContenitoreExtractionQueue` (app target) is sequential: one document at a time, in the
  background.
  - The controller enqueues every scheda under the root whose hash has no `done`, `none` or `failed`
    record. It does so at vault open and after each import.
  - Page progress is published on the main actor for the list (R-09).
  - A failure records `failed` and the queue moves on (R-11). `failed` and `none` both display as
    «nessun testo».
- **Extractor.** `SystemTextExtractor` sits behind `TextExtracting`. The tests use a fake of that
  protocol.
  - A PDF's text layer is read with PDFKit.
  - A PDF with no non-whitespace character anywhere in its text layer is rendered page by page and
    OCR'd. The decision is per document, as the SPEC decides.
  - Images use Vision's `RecognizeTextRequest`, with languages `it-IT` then `en-US`, the `.accurate`
    level and language correction on (Context 8).
  - A file whose type conforms to `UTType.plainText` is read as text.
  - Anything else is `none`.
- **Clearing.** «Svuota cache» (`VaultController.clearCache`) clears the store too, and the text is
  re-extracted at the next vault open.
- **Staleness.** The key is the hash recorded in the scheda. A file edited in place after import
  keeps its old extraction. This is named, not fixed.

### §D9 Search reads extracted text through the note it belongs to

`VaultSession`'s private `hit(for:)` looks up a scheda's extracted text by
`record.contenitore?.sha256`. It appends that text to the text it matches and excerpts.

- `search` and `searchCooperatively` share `hit(for:)`. The app's global search and both
  connectors' search therefore return the scheda with no other change (R-10).
- A hit only in the extracted text shows the matching line of that text as its excerpt.
- Clearing the store removes no vault file.

### §D10 The route selects the scheda in the pane

- `PergamenumRoute` gains `.contenitore(id:)` (host `contenitore`, query `id`), and `PergamenumLink`
  gains `contenitore(id:)`.
- `VaultController.perform` resolves the id through `lookUpNote(id:)`.
  - If the id names a scheda under the root, it sets `routeState.pendingContenitore =
    .select(path)`.
  - If the id is unknown or unreadable, or names a note that is not a scheda, it sets `.none` and
    calls `recordProblem` with one sentence (R-24).
- `RootView` switches the pane when the pending value changes, and the pane consumes it. This is the
  `pendingCanvas` shape.
- «Copia link Pergamenum» on a document mints the scheda's id through `mintNoteID(for:)` and copies
  the `contenitore?id=` form (R-23).
- `note?id=` keeps opening the scheda in the editor.

### §D11 The pane

- **Sidebar.** `Navigation.Pane.contenitore` is titled «Contenitore», with SF Symbol `archivebox`.
  It sits in LAVORO as `[.tasks, .contenitore, .pratiche, .recordings]`, which keeps
  `praticheSitsInLavoroImmediatelyBeforeRecordings` true.
- **Shortcut.** `ShortcutCommand.paneContenitore` is appended at the end of the enum, in the `.view`
  section. It is titled «Vai a Contenitore» and bound to Ctrl+Cmd+C (Context 9).
- **Controller.** `ContenitoreController` (`@Observable`, injected like `PraticheController`) owns the
  settings, the watcher, the engine, the queue, the notices, the selection and the filters.
- **List model.** A pure list model derives the rows from the index: name, colour, tags, date,
  extraction state, and «file mancante» when the companion is absent (R-25). It also derives the «Da
  classificare» count (R-14) and the colour and tag filters (R-15).
- **Working agreements.**
  - The tree is flat recursive rows (ADR-0024).
  - Quick Look passes `claimsFocus: false` (ADR-0070 §D4).
  - Backspace goes through `.onDeleteCommand`, with the list's `@FocusState` set when the selection
    changes.
  - A nested menu inside a row is hosted by AppKit (ADR-0069).
  - Confirmation dialogs use `presenting:`.
- **Guarded edits.** Every inspector edit (description, date, colour, tags) goes through
  `VaultSession.write(…, expecting: <hash read>)`. If the scheda moved on since, the write is refused
  and the inspector reloads, never overwrites (R-16).
- **Visuals.** The pane's visual design is the approved mockup in `docs/design/contenitore/` (R-28,
  gate G2). Views use tokens only.
- **Decided with the mockup (G2, 2026-09-30).**
  - A document's colour is a 10 pt dot filled with its sticky token and ringed with
    `color.border.strong`; the row is not tinted.
  - A «Documento» menu sits between Inserisci and Task. Its items are enabled only while the pane
    is, gated per item as the Workspace entries are: the «Task» menu itself is not pane-gated
    (verified at `cd3d9b15`). It carries «Classifica…», «Apri», «Apri scheda», «Rinomina…», «Sposta
    in…» and «Nuovo sottocontenitore…». «Copia link Pergamenum» and «Rivela nel Finder» stay in
    File. «Sposta nel Cestino…» is added to Modifica, since no menu-bar trash item existed before.
    All of them dispatch to the selection (§D12).
  - Keys: Cmd+Opt+K «Classifica…» and Cmd+Opt+O «Apri scheda», both unused in the remappable
    catalogue at `cd3d9b15`. Enter «Apri» works on the focused list only, not as a menu key
    equivalent, which would take Return from the inspector's text fields.
  - Impostazioni gains a twelfth tab, «Contenitore», beside «Pratiche». Task 7 re-measures the
    width at which AppKit collapses the tab bar, the way `SettingsView.swift` records it, and widens
    the window as needed.
  - The sidebar order stays as above.

### §D12 One command catalogue for the pane

`ContenitoreCommand` names every action once: «Classifica», «Apri», «Rivela nel Finder», «Apri
scheda», «Copia link Pergamenum», «Rinomina…», «Sposta in…», «Sposta nel Cestino».

- «Rivela nel Finder», not the SPEC's «Mostra nel Finder» (G2, 2026-09-30): the app-wide File
  entry this command dispatches through is already titled «Rivela nel Finder», and one command
  keeps one title on every surface. Pratiche's own «Mostra nel Finder» is untouched.

- The inspector, the row context menu and the menu bar all render it (R-27, ADR-0023 §D1).
- While `navigation.pane == .contenitore`, the existing app-wide `copyLink` and `revealInFinder`
  commands, and the new Modifica «Sposta nel Cestino…», dispatch to the selected document. The menu
  bar therefore carries one «Copia link Pergamenum», not two.
- R-19's tree verbs (new sub-container, rename, move, trash) are a second, smaller catalogue,
  `ContenitoreContainerCommand`, rendered by the tree's context menu. «Nuovo sottocontenitore…» is
  also in «Documento».
- The mockup fixes where the remaining entries sit.

«Classifica» validates through `ContenitoreClassification` (R-18):

- at least one `topic-*` from the vocabulary is required;
- one optional `type-*` is allowed;
- `type-note` is kept and `status-inbox` is removed;
- more than seven tags are refused;
- the result passes the linter.

### §D13 Settings

`VaultSettings` gains `contenitore: ContenitoreSettings`, decoded key by key as `pratiche` is. It has
two fields:

- `dropFolder`, stored `~`-relative, default `~/Pergamenum Drop`;
- `root`, default `Contenitore`.

Both are validated:

- The drop folder may not be the vault, inside it, an ancestor of it, the home folder or `/`.
- The root must be a strict vault subfolder, not hidden, neither inside the Pratiche folder nor
  containing it.

Changing the root moves nothing. Schede under the old root stop being documents, and the settings
tab says so. Renaming or moving the root folder from the Note pane does not update the setting,
exactly as for Pratiche. That gap is named for Stefano (gate G5), not fixed.

A drop folder under Desktop, Documents or Downloads triggers macOS's folder-access prompt on first
read. The default avoids it, and a refusal is reported as the unreadable-folder notice.

### §D14 Connectors: nothing new, and nothing they must not do

`perg` and `pergamenum-mcp` gain no command. Through shared code they still get:

- schede as notes;
- pair rename, move and trash through the session doors (§D6);
- extracted text in search (§D9).

They never ingest and never extract. `VaultSession+Adopt.swift`, the engine, the queue and the
extractor stay out of `sharedSources`. No payload shape changes, and `VaultAPI.LintFinding` is
untouched.

### §D15 The explicit no's

Each of these is out of this version, and a future reader should not add it as a fix:

- a background agent;
- «Crea scheda» for files placed under the root by hand;
- Office extraction;
- a Finder tag or colour mirror;
- a dedicated connector command;
- a second drop folder;
- a GUI test.

### Delivery

Two PRs:

- **PR 1 is dormant.** It holds the Core units, the index field, the session doors, the ingest
  engine, the extraction store and queue, and search. Nothing starts an import, and the pair
  operations have no scheda to act on until PR 2.
- **PR 2** holds the controller, watcher, settings, route and pane. It starts only after the mockup
  is approved (G2).

## Alternatives considered

1. **Read the keys off the file on every refresh (ADR-0049 §D4), with no index field.** Rejected.
   - The pane lists every scheda, and the duplicate check compares every hash for each incoming
     file. That costs one file read per scheda per landed change.
   - ADR-0049 could afford it for a pratica's handful of links. An archive grows without bound.
2. **A separate Contenitore catalogue in the state directory.** Rejected.
   - It would be a second derived index, fed by the same watcher events, and able to disagree with
     the first.
   - `IndexCache` is already reconciled on every change.
3. **Store every foreign key in `StoredFrontmatter`.** Rejected.
   - It widens the cache for every note in the vault; a Pratiche message note carries a dozen keys.
   - It changes the meaning of the cached frontmatter for every feature. One typed field is what the
     pane needs.
4. **Pair operations only in the Contenitore pane, at the controller level.** Rejected.
   - A rename from the Note pane, a batch move or a connector call would split the pair. The SPEC
     names the Note pane explicitly.
   - The one-door rule (ADR-0041, ADR-0067) puts the behaviour where every caller passes.
5. **Reuse `restoreFromOutside` for ingest.** Rejected.
   - Its refusal of a missing parent folder is ADR-0068 §D2's deliberate guard.
   - Its main-actor hash and note bookkeeping are wrong for a binary.
   - Changing its contract would reopen a decision taken for another reason. A second small door
     costs less.
6. **Write the scheda first, then move the file.** Rejected.
   - A failure between the two would leave a scheda pointing at nothing, which the app itself would
     then list as «file mancante».
   - Moving the file first makes the rollback a single move back to where the user put it.
7. **Extracted text in `IndexCache`.** Rejected.
   - `IndexCache.load` reads every row at vault open (`IndexCache.swift:43-66`). A vault with a
     hundred scanned documents would load tens of megabytes on every launch.
   - It would also spend a schema bump on blobs. Per-hash files load only when search asks for
     them.
8. **Detect scanned pages one by one in mixed PDFs.** Considered and deferred.
   - The SPEC scopes OCR to PDFs without a text layer.
   - A per-page rule needs a threshold for "near-empty" pages, and nothing measured supports one
     yet. It is named as a residual instead.
9. **A different shortcut (Cmd+Opt+C, or Ctrl+Cmd+A for «Archivio»).** Rejected.
   - Neither was measured against the system and catalogue bindings.
   - Ctrl+Cmd plus the pane's initial is the precedent Pratiche set, and Ctrl+Cmd+C was measured
     free (Context 9).

The SPEC's own rejections are registered, not reopened:

- a registry JSON;
- Finder metadata;
- copying instead of moving;
- an in-vault drop folder;
- an approval queue;
- a `file/` subfolder;
- EXIF dates;
- text in the scheda body;
- an OCR page cap;
- category colours;
- opening the file from the link;
- scheda-only rename.

## Consequences

### Positive

- Every piece of metadata is a readable note. Search, the linter, backlinks, the id registry and the
  connectors work on schede unchanged.
- No in-app path or connector can split a pair, except a rollback that itself fails, or a scheda
  trash whose file got no Trash URL back; the thrown error names it (§D6).
- The `.md` gate in `VaultDisk` removes a latent phantom-note defect for any future non-note move.
- Scans become searchable offline, and clearing the cache costs only time.

### Negative

- One schema bump: every vault rebuilds its cache once after the update.
- A file edited in place after import keeps a stale extraction.
- Undo of a pair trash is refused whole; the scheda and the file stay in the Finder Trash.
- For an extensionless dropped file, the `-file` key `[[<stem>]]` resolves to the scheda, not the
  file.
  - The pane resolves the companion by path, so only a click on that key in the editor is
    affected.
- CommonMark references to a document are not rewritten on a pair rename.
- Renaming the root from the Note pane silently orphans the setting (gate G5).

### Neutral

- Empty year folders stay on disk after a move.
- A mixed PDF, with both text and scanned pages, is searched by its text layer only.
- The ingest door (`adoptFromOutside`) announces nothing (ADR-0067 §D8). In a pair move or trash,
  `moveFile` announces `.moved` and `trashFile` announces `.trashed` for the binary too, which is
  harmless: no tab shows a binary. The watcher already ignores non-`.md` files.

## Acceptance

- **Pure units:** scheda render and parse, naming, colour names, classification, the settings rules
  and the route parse.
- **Ingest engine:** runs on a temporary drop folder and vault with a fake extractor (R-01..R-08).
- **Pair doors:** exercised through the session (R-19..R-23).
- **Search:** exercised with a pre-seeded store (R-10).
- **Real extractors:** one PDFKit test and one Vision test, on fixtures generated inside the test.
- **Network:** a repository walk proves no network API is used (R-12).
- **UI:** one in-process hosted-view test of the pane, and zero GUI tests.
- **Manual acceptance by Stefano:** a real drop folder, a real scan, and a copied link pasted into
  another app.

## Protected-interface entry (gate G6, approved 2026-09-30)

Add `Sources/Core/Contenitore/ContenitoreScheda.swift:ContenitoreScheda.render` to
`.claude/protected-interfaces`. It emits the lines every scheda on disk is recognised by, so a
silent change would unmake existing documents. This follows the `Dossier.render` precedent
(ADR-0036).

## Open for Stefano

- **G1.** Approve the `IndexCache.schemaVersion` 6 → 7 bump. Recommended: approve (§D2).
- **G2.** Approve the pane mockup before the pane is built (R-28). **Answered 2026-09-30:** approved,
  with the decisions listed under §D11 and §D12.
- **G3.** Decide what happens to a dropped `.md`. Recommended: refuse it with a notice. The
  alternative is to import it as a plain note with no scheda. A dropped `.canvas` is refused the
  same way (§D4 step 1).
- **G4.** Check stem uniqueness against the vault's note titles as well as the target folder.
  Recommended: yes.
- **G5.** Renaming the root from the Note pane: accept it as a named gap, or file a follow-up shared
  with Pratiche. Recommended: file the follow-up. **Answered 2026-09-30:** a named gap in v1, with a
  follow-up shared with Pratiche filed in `TODO.md`.
- **G6.** Approve the protected-interface entry above. **Answered 2026-09-30:** approved; the entry is
  in `.claude/protected-interfaces`.

## References

- SPEC: root `SPEC.md`, Approved 2026-09-29. Plan: `docs/plans/contenitore.md`.
- ADR-0017, 0022, 0023, 0024, 0036, 0041, 0043, 0046, 0047, 0049, 0059, 0065, 0067, 0068, 0069,
  0070.
- Apple, "Recognizing text in images", Vision documentation (read 2026-09-29). Xcode 27.0 SDK
  header `Vision.framework/Headers/VNRecognizeTextRequest.h`.
