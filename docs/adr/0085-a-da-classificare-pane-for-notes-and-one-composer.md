# ADR-0085: A «Da classificare» pane for notes, one «Classifica» verb, and one composer

- Status: **proposed**. Written before the implementation, for `PG-387`/#889 (N4 of the
  note-workflow chain).
- Date: 2026-10-04. Written against `48a2d912`. Every line number below was read there.
- Number: `0085` was reserved for this record by the chain's dispatch. It was checked free on every
  ref on 2026-10-04 (`git log --all -- 'docs/adr/0085*'` printed nothing). Check again immediately
  before the merge (`docs/adr/README.md` rule 1).
- Source: root `SPEC.md` (Approved 2026-10-04), milestone N4, R-29, R-30, R-32, R-33 and R-34.
  Plans: `docs/plans/note-workflow-n4-mockup.md` (mockup PR) and `docs/plans/note-workflow-n4.md`.
  Companion record: ADR-0086 (templates), the other half of N4.
- Depends on ADR-0080 (N1): `TagRules.initialTags(for:topics:)` gives `status-inbox` to every note
  born with no `topic-*` tag (§D1 there), `VaultSettings.inboxFolder` (§D6 there), and
  `CaptureTitle.derive(fromTypedLine:now:calendar:)` (§D3 there). Depends on ADR-0083 (N3): a
  `ShortcutCommand` may ship unbound (`KeyBinding("")`, allow-listed in
  `ShortcutCommand.shipsUnbound`, §D3 there), and `VaultController.offerNoteCreation(title:besideNoteAt:)`
  opens the composer prefilled (§D6 there). N4 ships after N1 and N3 (SPEC: one PR per milestone,
  in order). If either name differs when N4 starts, this record follows what was merged.
- **Amends SPEC (app)** §7.4 (a note pane beside the task Inbox), §10 (three menu entries) and §12
  (the quick switcher's «crea nota chiamata X» opens the composer). **Extends** ADR-0003 §D1 (the
  composer gains a sheet host for two named cases), ADR-0071 §D12 (the scheda's «Classifica» rule
  becomes a special case of the note rule), ADR-0023 §D1 (two catalogue commands) and ADR-0059 §D6
  (the creation toast trashes through the door that forgets the id). Amends none of them.
- No on-disk format, frontmatter key, `IndexCache.schemaVersion` or protected-interface change.
  `ContenitoreScheda.render` and `ImportNaming.recordingNoteTitle` are untouched.

## Context

### What the SPEC already settled (registered here, not reopened)

- The pane is called «Da classificare», never «Inbox». It sits in LAVORO and opens with Ctrl+Cmd+I.
  «Attività ▸ Inbox» keeps listing tasks (SPEC (app) §7.4).
- «Classifica» exists for notes as well as for Contenitore schede. It sets one or more
  vocabulary-checked topics, optionally moves the note, removes `status-inbox`, previews the
  frontmatter and writes once with `expecting:`. It is reachable from the pane, the note row menu,
  the slash menu and the command catalogue, and the connectors expose it.
- The composer is the one "name a note" surface. It is hosted in the pane, in the Workspace
  «Documento» sheet (folder = the board's folder) and from Quick Open's create row (prefilled).
  Its topic field completes from the vocabulary and blocks a closed-family violation.
- «Estrai in una nota» (slash and Modifica) creates a note from the selection through the composer,
  prefilled with its first line, and replaces the selection with `[[Titolo]]`. A refused second
  write keeps the new note and names it. The source frontmatter is untouched. The connectors
  extract a line range the same way.
- Creation undo is a 10-second «Nota creata · Annulla» toast that moves the note to the Trash and
  forgets its id. The app keeps no write journal (ADR-0007 §D6 stays).
- At most two GUI tests in N4, each justified in its ADR: filing a capture (this record) and the
  daily template (ADR-0086).

### What the code does today

- `IndexSnapshot.notes(carryingAll:)` (`Sources/Index/IndexSnapshot+Search.swift:25`) already
  answers "every note carrying `status-inbox`" from the index's tag table. Nothing lists it.
- `ContenitoreClassification.classify(tags:topics:type:vocabulary:)`
  (`Sources/Core/Contenitore/ContenitoreClassification.swift`) is a correct, pure «Classifica» rule,
  but only for schede. `ClassificaSheet` (`Sources/Features/Contenitore/ClassificaSheet.swift`)
  is its only surface. Its `actions` property is declared and never read.
- `NewNoteComposer` (`Sources/Features/Editor/NewNoteComposer.swift`) has one host, the Note pane's
  editor column (`VaultBrowser.swift:182-194`), and one topic field taking a single raw string
  (`:98`, `:205`).
- Quick Open's create row writes a note directly at the vault root (`VaultBrowser.swift:81-86`),
  with no folder, template or topic choice.
- Workspace «Documento» names a note in `NewCanvasItemSheet(kind: .note)`
  (`WorkspaceView+Creation.swift:50`), a second naming surface with its own rules.
- There is no extract verb and no undo for a creation.

## Decision

**D1. The pane is a query, not a store.** `Navigation.Pane.unfiled` («Da classificare», row id
`pane-unfiled`) sits in LAVORO immediately after «Attività»:
`[.pane(.tasks), .pane(.unfiled), .pane(.contenitore), .pane(.pratiche), .pane(.recordings)]`. The
mockup may move it within LAVORO. `ShortcutCommand.paneUnfiled` («Vai a Da classificare»,
Ctrl+Cmd+I, section `.view`) is appended to the catalogue, so the Vista menu lists it with no new
menu code (`MenuCommands.swift:24` iterates `Navigation.Pane.allCases`).

The rows are `index.notes(carryingAll: [status-inbox])`, read on every index generation and never
cached. **Contenitore schede carrying `status-inbox` are listed too** (gate G1). R-29 says "every
note", a scheda is a `.md` note in the index, and the Note pane already lists schede as notes. A
scheda row carries a document glyph and its «Classifica…» opens the scheda form (D5). Templates and
event notes carrying `status-inbox` are listed like any other note, because nothing exempts them.

**D2. Rows follow the list rules this repository already paid for.**

- Flat rows in `List(selection:)` (ADR-0024). The row's context menu is attached to the row, with
  no nested `.contextMenu` (ADR-0069). The menu holds «Classifica…», «Apri», «Apri in una nuova
  tab» and «Mostra nel Finder», plus «Mostra nel Contenitore» for a scheda.
- Keyboard focus follows ADR-0070: a `@FocusState` is set on selection change and used as a setter,
  never as a guard. Return runs «Classifica…» on the selected row and a double click opens it. The
  pane binds no delete key: nothing is deleted from here.
- Order: frontmatter `date`, newest first, then `modifiedAt`, then title. The mockup confirms the
  direction.
- A folder filter: «Tutte le cartelle», then each folder holding a capture with its count. An
  empty folder list hides the control.
- After a row is filed, the selection moves to the row that followed it, so a run of captures is
  filed from the keyboard alone.
- If the mockup adopts a count on the sidebar row, the `.badge` goes before `.tag`, or the tag is
  dropped (the `RootView.swift` trap).
- The rows and the filter are one pure model, `UnfiledListModel`, which the view only draws.

**D3. One classification rule, with the scheda rule as its special case.**
`NoteClassification.classify(tags:topics:vocabulary:) -> Result<[Tag], ClassificationRefusal>` in
`Sources/Core/Conventions/NoteClassification.swift` removes `status-inbox`, keeps or adds
`type-note`, adds the topics and orders the result. It refuses no topic, a non-`topic-*` topic, a
date-shaped or malformed tag, and more than seven tags. `ContenitoreClassification.classify` keeps
its signature and becomes the note rule plus the optional content type. Its tests in
`ContenitoreCoreTests` stay green unmodified, which is the acceptance for "the Contenitore's
classification still works". `ClassificationRefusal` keeps its cases. Topics are an open family, so
"vocabulary-checked" means `TagEntry` (D7) refuses a malformed or date-shaped topic and completes
from the topics already in use. The closed families are checked against the vocabulary wherever
they are typed.

**D4. One session door, one guarded write, then an optional move.**
`VaultSession.classifyNote(at:topics:toFolder:) async throws -> NoteClassifyOutcome`, in a new
shared file `Sources/Vault/VaultSession+NoteBirth.swift` (named in `sharedSources`):

1. Read the note and its hash.
2. Apply D3.
3. Write the frontmatter change once, with `expecting:` set to that hash. A refusal throws before
   anything moved.
4. When a folder is given and differs, move through `moveNote(at:toFolder:)`. A scheda moves as a
   pair (ADR-0071 §D6).

The write comes before the move on purpose. A failed move then leaves a classified note where it
was, which is harmless. A move first and a refused write would leave an unfiled note out of the
inbox folder. A move that fails after the write is reported in the outcome (`movedTo == nil`,
`moveProblem` set), never thrown: the `addStructuralLink` rule for half-done results. Tabs follow
through ADR-0067's landed door (`.written`, then `.moved`).

The write runs in its own gesture, `transaction("note classify")`, and the move in `moveNote`'s own
`transaction("note move")`. One gesture cannot hold both, because a nested transaction asserts
(ADR-0050). A connector `undo` therefore reverses a classification in two steps, the move first.

**D5. One sheet, two subjects.** `ClassificaSheet` moves to
`Sources/Features/Editor/ClassificaSheet.swift` and takes `Subject`:

- `.note(path)`: topics plus an optional folder, through D4. Identifiers `note-classifica-topic`,
  `note-classifica-folder` and `note-classifica-confirm`.
- `.scheda(path)`: topics plus the content type, through the unchanged
  `ContenitoreInspectorModel.classify`. The `contenitore-classifica-*` identifiers are kept. No
  folder field, because a scheda's place is the Contenitore's (ADR-0071 §D7).

The unused `actions` property is dropped. The sheet previews the resulting frontmatter, with
`status-inbox` struck through and «N di 7 tag», as the scheda form does today.

The note subject is presented by `RootView+Sheets.swift` from `Navigation.classifying`, so every
surface reaches it. The Contenitore keeps presenting its own `.scheda` sheet from
`contenitore.classifying`, so `ContenitoreController`'s vault-switch reset is untouched.

**D6. The verb is reachable from four places.**

- The pane (Return and the row menu).
- The note row menu: `.classifyNote` joins `CommandActions.rowCommands`, which opens the note and
  then runs, the ADR-0023 cluster-2 pattern.
- The command catalogue: `ShortcutCommand.classifyNote`, «Classifica…», section `.file`, shipped
  unbound. It sits in the File menu beside «Applica un template…».
- The slash menu, which needs no code: `EditorCommand.appEntries` maps every catalogue command but
  two.

`canRun(.classifyNote)` holds when a note is open.

**D7. One composer, two hosts, and the host performs the creation.**
`NewNoteComposer(draft:host:perform:onCreated:onCancel:)`.

- **Composing and creating are split.** The composer composes a `NoteComposition` (title, folder,
  tags, template body, body caret). `perform` is the host's creation, so each host decides what
  follows. The pane opens a tab with the caret and offers the toast (D9). The Workspace places a
  card and opens no tab (ADR-0080, R-05). «Estrai» writes two files (D8).
- **`.pane` is ADR-0003 §D1 unchanged.** It runs in the editor column, parks drafts, and keeps the
  identifiers `new-note-title`, `new-note-folder` and `new-note-template`. `ComposerUITests`, which
  asserts no sheet floats over the window for Cmd+N, stays green unmodified.
- **Quick Open's create row reaches the pane host.** It opens the composer prefilled with the typed
  title (ADR-0083 §D6's entry, and a parked draft wins as it does there) instead of writing at the
  vault root. Folder, template and topics are then chosen like any other note.
- **`.sheet(folder:)` is the extension of ADR-0003 §D1.** It serves two named cases where the
  context must stay on screen: the Workspace «Documento» sheet, whose folder is fixed to the board's
  folder, and «Estrai», whose source and selection must stay visible.
  - ADR-0003's objection was to naming a note "in a floating window" instead of where it will be
    edited. Neither case edits the new note next: the Workspace places a card, and «Estrai» leaves
    the source in front.
  - The sheet host parks no draft.
  - `NewCanvasItemSheet` keeps its folder, link and sticky kinds and loses `.note`.
- **The topic field becomes a tag field.**
  - One pure door, `TagEntry` in `Sources/Core/Conventions/TagEntry.swift`:
    - `check` turns typed text into a `Tag` or a refusal. Bare text reads as `topic-…`. A
      closed-family value outside the vocabulary is refused (`notInVocabulary`,
      `vocabularyUnavailable`). Date-shaped and malformed values are refused. `type-*` and
      `status-*` are refused here, because the initial-tags rule owns both.
    - `completions` offers vocabulary values for the closed families and used values, most used
      first, for the open ones.
  - `client-` and `project-` chips come from the most used values.
  - Before «Crea» is enabled, the tags the rule would write pass `TagRules.validate`.
  - `NoteDraft` gains `tags: [Tag] = []`. `topic` stays as the text being typed, so
    `NewNoteDraftTests` keeps compiling and passing.

**D8. «Estrai in una nota» is the composer in extract mode over a two-write session door.**

- **Reach.** `ShortcutCommand.extractToNote` («Estrai in una nota», section `.edit`, shipped
  unbound) appears in Modifica and, automatically, in the slash menu.
- **Enablement.** `canRun` needs a non-empty selection in the focused Note-pane tab. The editor
  reports it as `NoteTab.selection: NSRange?`, nil for an empty selection, written only when it
  changes. This is ADR-0083 §D3's report shape, so typing with a bare caret writes nothing.
- **The slash case.** Typing `/` over a selection replaces it. `CompletingTextView` therefore keeps
  a one-shot stash (location and text) when `/` replaces a non-empty selection, in a new file
  `CompletingTextView+SlashSelection.swift`. `CompletingTextView+Pasteboard.swift` is a protected
  file and is not touched.
  - Accepting a command whose `ShortcutCommand.takesSelection` is true restores the stashed text
    over `/prefix`, reselects it, then runs.
  - Without a stash, such entries are not offered.
  - Any other outcome drops the stash, and the replaced text stays replaced, as today. Cmd+Z
    restores it.
- **The composer.** It opens as the sheet host in extract mode:
  - the folder defaults to the source note's folder;
  - the title is prefilled with `CaptureTitle.derive` of the selection's first line (ADR-0080 §D3);
  - the selection is previewed;
  - the template menu is hidden, because the body is the selection.
- **The session door.** `VaultSession.extractToNote(from:range:expectedText:title:in:topics:date:)
  -> ExtractOutcome` runs in this order:
  1. Read the source and its hash. Refuse a range out of bounds, a range whose text differs from
     `expectedText`, and a range intersecting the frontmatter block, so the source frontmatter is
     untouched by construction.
  2. Create the note with the selection as its body, `expectingAbsent:` through `createNote`.
  3. Replace the range with `[[Titolo]]` in one write, `expecting:` the hash read in step 1.
  4. A refusal or failure of step 3 keeps the new note. The outcome names both (`created`, plus
     `source: .refused(sentence)`), and the composer shows that sentence in place before it closes.

  The pure planning (line range to `NSRange`, frontmatter check, replaced text) is
  `NoteExtraction` in `Sources/Core/Conventions/NoteExtraction.swift`, shared with the connectors.
- **A dirty source tab (gate G2).** The confirm button reads «Salva ed estrai» and the sheet says
  the note will be saved first. «Salva ed estrai» saves through `saveTab(_:)` (ADR-0073 §D4), then
  re-reads the tab after the `await` (ADR-0043 §D7) and confirms the selected text is still at the
  range, before calling the door.
  - Without the save, the source write would be refused against the disk, or would land under a
    dirty buffer and raise ADR-0058 §D1's conflict prompt on the person's own gesture.
  - «Classifica…» on a dirty note gets the same treatment: «Salva e classifica».
- **Afterwards.** The source stays in front, its tab adopts the landed text through ADR-0067's
  door, and the new note is not opened. The replacement is not on the editor's undo stack. Undoing
  an extract is opening the new note and pasting back.

**D9. The creation toast covers creations whose whole effect is one new file (gate G3).**

- **The offer.** `CreationUndo` (pure, `Sources/App/CreationUndo.swift`) holds `{path, createdHash,
  expiresAt}`, with a 10-second window and `now` injected. `VaultController.creationUndo` holds at
  most one offer, and a new creation replaces it.
- **The strip.** «Nota creata · Annulla» is an overlay at the bottom of the Note pane's editor area
  (`VaultBrowser.editor`), of constant height. It is never a layout row above the `HSplitView`:
  ADR-0075 recorded that a banner changing height above an `HSplitView` crashes AppKit.
- **«Annulla».** It is refused, with a sentence, when a tab showing the note has unsaved changes or
  when the file's hash moved since creation (the person already wrote into it). Otherwise it calls
  `VaultController.trashNote(at:)`. That reaches `VaultSession.trashNote`, `trashFile(at:)` with
  `forgettingNoteID: true` (ADR-0059 §D6), and the landed door, which closes the clean tab.
- **Expiry.** After 10 seconds the strip is gone and the note stays.
- **Scope.** The offer follows the pane-host composer only: Cmd+N, «Nuova nota qui», Quick Open's
  create row and ADR-0083's «Crea «X»». These are excluded, each for a reason:

  | Excluded creation | Reason |
  | --- | --- |
  | Workspace «Documento» | It also placed a card. Trashing the note would leave a card on a missing file, and the board's own Cmd+Z removes the card. |
  | «Estrai» | Two writes. Trashing the note would leave a dangling `[[Titolo]]` in the source. |
  | The daily note and event notes | They are navigation targets created as a side effect of opening a day. |
  | The capture panel | A non-activating panel over another app, where nobody sees the main window's strip. |
  | Pratiche create-and-link | Two writes, the same reason as «Estrai». |
  | The connectors | They have their own `undo` through the journal (ADR-0007 §D6). |

- **Residual.** A write landing between the hash check and the trash is trashed with the note.
  `trashFile` carries no `expecting:`. The window is one main-actor turn, and the file goes to the
  Finder Trash, not away.

**D10. The connectors.** One new file, `Sources/Connector/VaultNoteBirth.swift`, holds both writes,
and the front ends only translate (ADR-0007 §D2/§D4). Both writes stay behind `--allow-write`, with
`dryRun` defaulting to true (§D6). `undo` reverses an extract's source rewrite and declines its
creation, because the journal never deletes (ADR-0063). It reverses a classification in the two
steps D4 names.

| Operation | `VaultAPI` | `perg` | MCP tool | Returns |
| --- | --- | --- | --- | --- |
| Classify | `classifyNote` | `perg note classify <percorso> --topic a,b [--folder F]` | `classify_note {path, topics, folder?, dryRun}` | `ClassifySummary`: path, applied, diff, `movedTo`, note |
| Extract | `extractToNote` | `perg note extract <percorso> --lines A-B --title T [--folder F] [--topic t]` | `extract_to_note {path, fromLine, toLine, title, folder?, topics?, dryRun}` | `ExtractSummary`: created path, two diffs, `sourceRefused` |

- Topics are a comma-separated string, because `ToolArguments` reads no arrays.
- Lines are 1-based and inclusive, counted over the whole file. A range touching the frontmatter is
  refused.
- `scripts/mcp-smoke.py` gains both tools: absent without `--allow-write`, and a rehearsal by
  default.

**D11. One GUI test: filing a capture.** `UITests/NoteBirthUITests.swift`, on
`PergamenumUITestCase`.

- **Steps.** Seed `00 Inbox/Idea.md` carrying `status-inbox`. Press Ctrl+Cmd+I, arrow onto the row
  and press Return. In the sheet, type a topic, choose the folder `03 Risorse` and confirm.
- **Assertions.** The file is now `03 Risorse/Idea.md`, its frontmatter has the topic and no
  `status-inbox`, and the pane shows its empty state.
- **Why it has to be GUI.** The hosted harness (`Tests/HostedViewSupport.swift`) refuses to make a
  window key or send it events (R-15 there). Three links of this chain exist only in a real key
  window:
  - the menu shortcut reaching a sidebar pane;
  - a `List`'s keyboard focus, which ADR-0070 measured a row click does not even give;
  - a sheet presented from `RootView` over that window.
- **What other tests cover.** Pure and session tests cover the rule, the write and the move. Hosted
  tests cover the rows and the empty state.

**D12. SPEC (app) amendments, as dated notes, bodies untouched.**

- §7.4: beside the five task views, the LAVORO pane «Da classificare» lists notes carrying
  `status-inbox`. It is not a sixth task view, and «Inbox» there still means tasks.
- §10: File gains «Classifica…», Modifica gains «Estrai in una nota», and Vista gains «Vai a Da
  classificare» (Ctrl+Cmd+I).
- §12: the quick switcher's «crea nota chiamata X» opens the composer prefilled instead of writing
  at the vault root.

## Gates for the person

- **G1. Schede in «Da classificare».** Recommended: listed, and classified through the scheda form
  (D1, D5). This is the literal reading of R-29 and of the SPEC's "Capture … whatever path created
  it". Alternative: excluded, with a footer «N documenti da classificare nel Contenitore» linking
  to the Contenitore's own scope. That alternative answers a fear of the drop folder flooding the
  notes pane, which nobody has measured.
- **G2. A dirty note under «Classifica» or «Estrai».** Recommended: an explicit «Salva e
  classifica» or «Salva ed estrai», which saves first as part of the confirmation (D8).
  Alternatives:
  - refuse, the `canOperate(on:)` precedent ("salva la nota prima di …"). This is hostile from the
    slash menu, where the note is almost always dirty;
  - for «Estrai» only, replace the selection in the buffer as one undoable edit and then save, the
    outline section-move precedent (`pendingReplacementsIsMove`). That gives Cmd+Z, but the app's
    second write would no longer be the guarded session write the SPEC's API names, and the app and
    the connectors would part ways.
- **G3. The toast's scope.** Recommended: the pane-host composer only, with the six exclusions in
  D9. Alternative: the Workspace too, with «Annulla» also deleting the placed card through the
  board's own delete. That is two surfaces in one undo, and N1 has just made the Workspace creation
  open no tab.

## Alternatives considered

- **A sixth task view or an `Attività` subsection for notes.** Rejected: ADR-0013 §D6 and ADR-0047
  keep the task views closed, and a capture is a note, not a task. The SPEC named the pane apart
  from the task Inbox for exactly this reason.
- **A stored list of captures (a registry file or a cache column).** Rejected: the tag is already
  in the index's tag table, a store would be a second truth to keep in step, and principle 3 holds
  only while the list is derivable.
- **Keeping two «Classifica» rules, one for notes and one for schede.** Rejected: the scheda rule is
  the note rule plus a type. Two copies drift. The Contenitore once paid for drifted copies of the
  vault walk and the apply-plan loop (ADR-0041 §D4).
- **Moving before writing in `classifyNote`.** Rejected in D4: a refused write after a move leaves
  an unfiled note out of the inbox folder.
- **The composer in a sheet everywhere (one host).** Rejected: ADR-0003 §D1's in-pane naming for
  Cmd+N was the person's complaint fixed, and `ComposerUITests` pins it.
- **The composer in the editor column for «Estrai».** Rejected: the column is where the source and
  its selection are, and the pane host would park the extract as an ordinary new-note draft.
- **The journal for the creation undo.** Rejected by the SPEC (ADR-0007 §D6 stays).

## Consequences

Positive:

- A capture is findable: one pane lists it, and one verb files it from four surfaces and two
  connectors.
- One classification rule and one naming surface instead of two and three.
- «Estrai» and «Classifica» reuse the guarded write doors. Neither adds a new way to write a file.

Negative:

- Two catalogue commands ship unbound. `ShortcutCommand.shipsUnbound` and its pinned test grow
  from two to four entries (ADR-0083 §D3).
- «Estrai» is not on the editor's undo stack (G2).
- `TagEntry` adds a fourth caller-facing tag parser beside `Tag.init?`, `TagRules` and the Tags
  pane's rename. It is a door over `Tag.init?` and `TagRules`, not a grammar of its own.
- The toast's residual race (D9).

Neutral:

- A scheda can be filed from either pane, through the same rule.
- Templates and event notes carrying `status-inbox` appear in the pane until filed.
- Opening the note from a note row's «Classifica…» before the sheet is the existing row-command
  pattern. The pane's own «Classifica…» does not open the note.

## References

- SPEC.md (root), N4: R-29, R-30, R-32, R-33, R-34. Decisions, Constraints, Edge cases, Test seams 4
  and 6.
- `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §N4. `docs/20261002_Pergamenum_NoteWorkflowReport.md`
  I-2, I-5, I-6, I-9.
- ADR-0003 §D1, ADR-0007 §D2/§D4/§D6, ADR-0023 §D1, ADR-0024, ADR-0043 §D7/§D8, ADR-0058 §D1,
  ADR-0059 §D6, ADR-0067, ADR-0069, ADR-0070, ADR-0071 §D6/§D7/§D12, ADR-0073 §D4, ADR-0075, ADR-0080,
  ADR-0083 §D3/§D6, ADR-0086.
