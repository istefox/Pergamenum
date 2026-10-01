# ADR-0076: A manual entry anchors to one message by its Message-ID, through one shared parser, one ordering rule and guarded body writes

- Status: **accepted**. PR 1 of the two (Tasks 2-5: the Core parser and ordering, the app model
  switch-over, connector parity, the carry on «Sposta in…») landed on `main` via PR #724 (merge
  `73f17450`, 2026-09-30). PR 2 (Tasks 6-7: the verbs, the picker, the rows, the editor
  concealment) is not on `main` yet; its merge is added here when it lands (ADR-0071's two-PR
  precedent, `docs/adr/README.md` rule 2).
- Date: 2026-09-30. Written before the implementation, against `160d3e76` (the branch
  `kepler/docs/spec-pg-338`). `origin/main` is at `c99103c8`. Its diff against `160d3e76` touches
  `NoteFolding`, `OutlinePane`, `TagRenameSheet`, three Tasks views, `BoardCardMenu` and
  `NoteFoldingTests`, and none of the files this record cites. Every line number below was read at
  `160d3e76`.
- **Renumbering note (2026-09-30).** This record was first written as `0074`, then as `0075`, and
  neither number was ever committed for it. `0074` was taken on `origin/main` by
  `docs/adr/0074-editor-coordinator-feature-controllers.md` (PR #717) while this chain was in
  progress. `0075` is held by `docs/adr/0075-day-boundary-and-calendar-math.md` on the branch
  `fix/pg-259-day-boundary-calendar-math` (`PG-259`, commit `768ecd09`), which is not on `main`
  yet; rule 1 counts branches about to merge, so this record moved to `0076`. `0076` was checked
  free on every ref on 2026-09-30, after `git fetch origin`: `git log --all -- 'docs/adr/0076*'`
  printed nothing and `git ls-tree origin/main docs/adr/` lists nothing above `0074`. Check again
  immediately before the merge (`docs/adr/README.md` rule 1).
- Source: `docs/specs/pratiche-message-anchored-entries.spec.md` (Approved 2026-09-30, `PG-338`),
  which declares R-01 to R-24. Plan: `docs/plans/pratiche-message-anchored-entries.md`.
- **Extends ADR-0036 and amends its §D5** (the timeline's writes widen, §D4 below). **Extends**
  ADR-0023 §D1 (two catalogues drive menu, footer and accessibility actions), ADR-0029 §D1 (one
  more whole-line concealed construct), ADR-0043 §D7/§D8, ADR-0057 §D3 and ADR-0052's origin
  marker (every body write is guarded and checked against what the timeline read), ADR-0067 (the
  landed-change door catches editor tabs up after each write) and ADR-0068 §D1 (the «Sposta in…»
  path this record adds a tail to). **Relation to ADR-0049** stated in §D11: it does not reopen
  «manual entries stay unlinkable» for notes, tasks and boards; it adds one relation, entry to
  message, carried in the entry's own text.
- No frontmatter key, no message-file change, no `Dossier`/`Dossier.render` change, no
  `IndexCache.schemaVersion` bump. One protected-interface entry is proposed (gate G2, §D12).

## Context

### What the SPEC already settled (registered here, not reopened)

The anchor is a comment line, `<!-- pergamenum-message: <Message-ID> -->`, directly under the
entry's heading, holding the Message-ID with its angle brackets and compared byte for byte. The
heading keeps the time of writing, and the daily-note mirror goes to the day of writing. An
anchored entry is drawn in its message's lane at the lane's width, indented, in the manual-entry
colour. «Aggiungi nota» and «Aggiungi telefonata» appear on every message row. Escludi leaves the
entries in place, orphaned. «Sposta in…» carries them (append, then remove) and «Aggiungi anche a…»
does not. The anchor line is concealed in the editor. An anchored entry follows its message
through the filters. The connectors expose the anchor and share the ordering. Existing entries can
be anchored, re-anchored and unanchored through a list picker. At an equal instant the message
sorts first. The SPEC's Constraints (frontmatter and message files untouched, every body write
guarded and refused while dirty, re-read after `await`, no schema bump, tokens and a mockup first,
connectors read-only, nothing under `Sources/Core` or `Sources/Connector` importing AppKit or
SwiftUI) are inputs to every decision below.

### Evidence (facts, read at `160d3e76`)

- **F1. Two parsers of one grammar.** The app parses manual entries in
  `Sources/Features/Pratiche/PraticheController+TimelineRead.swift`: `readManualEntries` (`:187-228`)
  and `parseEntryHeading` (`:231-259`), with its own copy of the heading formatter,
  `entryHeadingFormatter` (`:291`). The connector restates the same grammar in
  `Sources/Connector/VaultPratiche.swift`: `manualEntryRows` (`:247-288`) and `entryHeading`
  (`:292-300`), through `PraticaEntry.headingFormatter`. Neither connector function has a caller
  outside that file, tests included.
- **F2. The equal-instant tie-break differs.** The app's `PraticaTimelineModel.ordered`
  (`PraticaTimelineModel.swift:94-98`) breaks a date tie by `id`. A manual entry's id is
  `"<pratica>#entry-<yyyyMMddHHmm>"` and a message's is `"<pratica>/email/<file>"`; `#` (0x23)
  sorts before `/` (0x2F), so the app puts the manual entry first. The connector
  (`VaultPratiche.swift:196`) compares a message's file name (`YYYYMMDD_…`, a digit) with
  `"pratica.md#N"`, so it puts the message first.
- **F3. Both tie-breaks lose file order past nine.** The app suffixes a repeated minute with
  `-<occurrence>` (`PraticheController+TimelineRead.swift:207-209`) and the connector numbers
  entries `#<count>` (`VaultPratiche.swift:258`). Both compare as strings, so `-10` sorts before
  `-2` and `#10` before `#2`.
- **F4. Nothing pins either detail.** No test asserts the timeline's equal-instant tie-break (the
  one "tie-break" test in `Tests/PraticaTimelineTests.swift:288` is about the sidebar grouping).
  No test feeds either parser a CRLF `pratica.md`; `Tests/CRLFAppendTests.swift` covers
  `PraticaEntry.insert` only.
- **F5. ADR-0036 §D5 allows the timeline two writes**: one heading appended to `pratica.md`, and
  the daily-note line (`docs/adr/0036-pratiche.md:226-227`). `PraticaEntryComposer.insert(_:at:)`
  (`PraticaEntryComposer.swift:50-76`) is that path: `vault.canOperate(on:)`, `session.read`,
  `PraticaEntry.insert`, `session.write(…, expecting: record.contentHash)`, the mirror,
  `reloadTimeline`, the hand-off to the editor.
- **F6. The dirty-tab refusal records a sentence about other verbs.**
  `VaultController.canOperate(on:)` (`Sources/App/VaultController+Files.swift:18-29`) records
  `unsavedNoteRefusal`, «salva la nota prima di rinominarla, spostarla o eliminarla» (`:34`), as a
  vault problem.
- **F7. The message verbs write the dossier, never a body.** `PraticaCommandActions.move`
  (`PraticaCommandActions.swift:247-278`) moves the files, then adds the id to the source's
  `excluded` and to the destination's `included` through `DossierWriter.update`, and its undo
  reverses all three. `exclude` (`:199-242`) records the exclusion, then trashes the files; its undo
  restores them and removes the id. `alsoAdd` (`:286-295`) copies and includes, with no undo.
  `confirmRegeneration` (`:318-342`) trashes and recommits the message file and never opens
  `pratica.md`. `DossierWriter.update` does not ask whether a tab is dirty.
- **F8. Message verbs come from one catalogue; entries have none.** `MessageCommand`
  (`MessageCommand.swift`) has eight cases. The expanded footer (`PraticaMessageRow`) and the
  context menu (`MessageMenuItems.menu`, `PraticaMenuItems.swift:29-35`) both iterate
  `PraticaCommandActions.commands(for:)`. The message row carries no `.accessibilityActions`. The
  timeline gives every message row its menu whatever its position (`PraticaTimelineView.swift:177-185`);
  only «Inserisci qui» depends on a following row. `PraticaEntryRow` offers no verb.
- **F9. Layout and day sections key on `date`.** `PraticaTimelineView.row` (`:120-170`) sizes a
  message at 70% of `width - gutter - noteSlotWidth` and an entry at full width, through
  `containerRelativeFrame`. `sections(of:)` (`:297-310`) starts a new day section whenever
  `entry.date` crosses midnight.
- **F10. The inspector renders `pratica.md` whole.** `loadInspector`
  (`PratichePane+Inspector.swift:97-104`) hands `NoteDocument.parse(text).body` to
  `MarkdownBlocksView`, and `MarkdownBlockParser` has no rule for an HTML comment, so an anchor
  line would read raw there.
- **F11. The editor already conceals one whole line.** `MarkdownStyler.spans(inLine:)` emits
  `.horizontalRule` for the whole line and returns (`MarkdownStyler.swift:248-256`).
  `NoteTextView+Coordinator.hiddenKind(for:)` maps it to `HiddenMarker.Kind.rule` (`:610`).
  `EditorDecorationDelegate` collapses the characters on its generic path and vends a
  `HorizontalRuleFragment` while `hidesMarkup` is on and the paragraph is not revealed (`:415-425`).
  The exhaustive switches a new span or marker kind must join are `MarkdownStyler.swift:160-176`,
  `MarkdownAttributedText.swift:251`, `CardTextAttributes.swift:220` (a colour table for Workspace
  cards, where `.horizontalRule` sits on the `.textTertiary` shelf), `EditorDecorationDelegate.swift:107-111`
  (`isInline`) and `:756-801` (`stillSpells`). `CardTextView.swift:374-388` maps spans to marker
  kinds with a `default: nil`, and `Tests/InlineSpanRevealFenceTests.swift:327` counts its seven
  `case` lines, so a new span must not gain a line there (ADR-0029 §D17 keeps cards out).
- **F12. The timeline payload is not protected.** `VaultAPI.PraticaTimelinePayload.Entry`
  (`Sources/Connector/VaultPayloads.swift:287-306`) is absent from `.claude/protected-interfaces`,
  which protects `VaultAPI.PraticaSummary` only among the Pratiche payloads. Its `Encodable` is
  synthesized, so an optional field that is `nil` is omitted from the JSON.
- **F13. ADR-0049 kept manual entries unlinkable for a stated reason**: "a manual entry has no file
  of its own to carry a key, which is the real reason it is out of scope rather than an oversight"
  (`docs/adr/0049-pratiche-links-to-notes-tasks-and-boards.md:444-446`).
- **F14. The timeline does not reload after an in-app save of `pratica.md`.** The inspector reloads
  on `PraticheController.InspectorKey` (selection plus ADR-0067's landed generation,
  `PraticheController.swift:68-82`, `PratichePane.swift:85`). `reloadTimeline(from:)`
  (`PraticheController+Ledger.swift:209-230`) runs on selection, sync and after each command, not
  on that key.

## Decisions

### §D1 — One parser of manual entries, in `Sources/Core`

A new Foundation-only file, `Sources/Core/Pratiche/PraticaManualEntries.swift`, is the only
reader of the manual-entry grammar. It compiles into the app, `perg` and `pergamenum-mcp` through
the `Sources/Core/**` glob, so `sharedSources` needs no edit.

- `struct PraticaManualEntry` carries the kind, the heading date, the heading tail (`subject`), the
  counterpart, the anchor (`String?`), the body, the entry's `ordinal` (its index among the
  entries, in file order), its `occurrence` (how many earlier entries share its heading minute, the
  app's id suffix), its `blockRange` and its `anchorLineRange` (both `NSRange`, UTF-16, in the
  **full** source, frontmatter included).
- `PraticaManualEntries.parse(_ source: String) -> [PraticaManualEntry]` keeps today's grammar:
  a line starting `## ` ends the open entry; it opens a new one when `yyyy-MM-dd HH:mm <tail>`
  parses through `PraticaEntry.headingFormatter`; the kind is `.call` when the tail starts with
  `PraticaEntry.Kind.call.label`; the counterpart is everything after the first ` · `. The body is
  the entry's lines, anchor line excluded, joined by LF and trimmed, as both parsers produce today.
  Lines split on LF and CRLF alike, and a terminator is never part of a parsed value.
- The body offset is the source's UTF-16 length minus that of `NoteDocument.parse(source).body`,
  which is a verbatim suffix of the source (`Frontmatter.swift`).
- `PraticaEntryAnchor` is the codec. `line(for messageID:) -> String?` spells
  `<!-- pergamenum-message: <id> -->`, and answers `nil` for an empty id or one containing `-->`,
  CR or LF, which cannot survive the round trip. `messageID(inLine:) -> String?` trims the line's
  surrounding whitespace, then requires the exact prefix `<!-- pergamenum-message: ` and suffix
  ` -->`, and returns the text between them verbatim when it is non-empty. The line anchors an
  entry only at position one, directly under the heading; anywhere else it is body text.
- `Sources/Core/Pratiche/PraticaEntryEdit.swift` holds the pure text transforms every write below
  uses, each in the target's own line break (`LineBreak.detected(in:)`, R-19):
  `anchoring(entryAt:to:in:) -> String?` (writes or replaces the anchor line; `nil` when the
  ordinal is out of range, the id cannot be spelled, or the entry already carries that anchor),
  `unanchoring(entryAt:in:) -> String?` (removes the line and its terminator; `nil` when there is
  none), `blocks(anchoredTo:in:) -> [String]` (each anchored block, LF-normalised, trailing blank
  lines dropped), `appending(_:to:) -> String` (one blank line before each block, never two, the
  separator rule `PraticaEntry.insert` already applies), `removing(_:anchoredTo:from:) -> Removal`
  (removes each block anchored to that id whose normalised text equals a carried one, each carried
  block consumed once; `Removal.missing` names the carried blocks it did not find) and
  `removingAnchorLines(in:) -> String` (for the inspector, §D7).
- `PraticaEntry.insert(kind:at:counterpart:anchor:in:)` gains `anchor: String? = nil`. With an
  anchor, the heading is followed by the anchor line and then the empty body line, and
  `cursorRange` points at the body line. Every existing caller compiles unchanged.
- `PraticaEntry.counterpart(ofMessage:ownAddresses:) -> String?` names the message's counterpart
  for the heading through `MessageDocument.counterpart(direction:from:to:cc:ownAddresses:)` and
  `EmailAddress.displayText`: the sender of a received message, else the first recipient that is
  not the user's own, else the first Cc.
- The app's `readManualEntries`, `parseEntryHeading` and `entryHeadingFormatter`, and the
  connector's `manualEntryRows` and `entryHeading`, are deleted. `entryIDFormatter` stays: the app
  builds its entry ids with it and `PraticaEntryRow` reads it.

### §D2 — One ordering and placement rule, in `Sources/Core`

`Sources/Core/Pratiche/PraticaTimelineOrder.swift` decides where every row goes, for the app and
both connectors.

- Input: one `Item` per row, either `.message(messageID:fileName:)` or `.entry(anchor:ordinal:)`,
  with its date (a message's `PraticaTimelineModel.sortDate`, an entry's heading time).
- Output: `arrange(_:) -> [Placed]`, each carrying the input index, a `Placement`
  (`.message`, `.free`, `.anchored(messageID:)`, `.orphaned(messageID:)`) and the `placementDate`.
- The spine holds messages, free entries and orphaned entries, sorted by date. At an equal date a
  message sorts before an entry (R-08); two messages sort by file name, which is today's order in
  both readers; two entries sort by `ordinal`, which fixes F3.
- An entry is anchored when a message in the input carries its anchor; it is placed directly
  after that message, after any earlier-placed entries of the same message, ordered by heading
  date, then ordinal (R-04). Its `placementDate` is the message's date. An entry whose anchor
  names no message in the input is orphaned and sits on the spine by its heading date (R-05).
- A Message-ID carried by two message files of one pratica is owned by the first in spine order;
  an empty Message-ID owns nothing (`PraticaEntryAnchor.messageID(inLine:)` never returns one).
- Message-IDs compare as Swift strings, which means canonical equivalence rather than bytes;
  RFC 5322 Message-IDs are ASCII, so in practice this is byte comparison.
- Placement is recomputed on every read. Nothing is cached, and nothing is written when a message
  leaves or returns: undoing Escludi re-anchors by reading (R-05, R-13).

### §D3 — The app's timeline model reads the rule and follows the message

- `PraticaTimelineEntry` gains fields appended after `isInMail`, each defaulted so every existing
  memberwise call compiles: `anchor: String? = nil`, `fileOrdinal: Int = 0`,
  `placement: PraticaTimelineOrder.Placement = .free`, `placementDate: Date? = nil` and
  `hostDirection: MessageDocument.Direction? = nil`. A computed `placedAt` is
  `placementDate ?? date`.
- `PraticaTimelineModel.ordered` maps entries to `Item`s, calls `arrange`, and returns the rows in
  that order with `placement`, `placementDate` and `hostDirection` filled. The app's tie-break
  flips to message-first (F2). No existing test asserts the old one (F4).
- `lane(for:)` is unchanged: an anchored entry still answers `.entry`, which keeps its colour and
  glyph. A new `hostLane(for:)` answers the lane an anchored entry aligns to: its message's
  `.received` or `.sent` (R-09).
- **Filters.** An anchored entry is visible exactly when its message is. A message is visible when
  it passes the sender and attachments filters and the text filter matches it or any entry
  anchored to it. Free and orphaned entries keep today's rule: only the text filter hides them
  (R-06).
- **Day sections** move from the view into the model as `daySections(of:calendar:)` and group by
  `placedAt`, so a day header never separates a message from its entries.
- **«Inserisci qui».** `insertionDate(between:and:)` takes the midpoint of the two neighbours'
  `placedAt` (R-07). `nextRows(in:)` offers no gap inside an anchored group: a row whose next row
  is anchored to the same message gets none, and the group's last row gets the next spine row.
  A free entry cannot land between a message and its anchored entries, so the gap is not offered
  there.
- **The origin.** `TimelineRead` gains `praticaNoteHash: String?`, `NoteStore.hash` over the same
  bytes the parser read. `reloadTimeline(from:)` stores it on the controller as `timelineOrigin`.
  It is written there, and cleared by the controller's vault reset beside the selection, so an
  origin read in a vault that has been left never survives into the next (ADR-0052's cross-vault
  lesson).
- **Freshness.** The timeline also reloads on the `InspectorKey` beat the inspector already uses
  (F14), so an in-app save of `pratica.md`, a hand-edited anchor included, redraws the timeline
  and refreshes the origin. It reloads there only when stale (`reloadTimelineIfStale(from:)`):
  when `pratica.md`'s current hash, one read through the session, differs from `timelineOrigin`,
  or the selected pratica is not the one the origin was read for. A selection change was already
  read by `select(_:in:)`, and parsing the pratica folder twice on the main actor buys nothing.
  External edits stay as ADR-0068 §D20 left them.

### §D4 — ADR-0036 §D5 is amended: the timeline's writes widen

The timeline's writes become:

1. one heading appended to `pratica.md`, free or anchored (anchored adds the anchor line in the
   same write);
2. the daily-note line;
3. writing, replacing or removing one anchor line (§D5);
4. appending entry blocks to one `pratica.md` and removing the same blocks from another, on
   «Sposta in…» and its undo (§D6).

Every one is a whole-file `VaultSession.write` with `expecting:`, and every one is computed from a
fresh read by a pure transform of §D1. **§D5's single-editor rule stands unchanged**: the timeline
still never binds a live text view to a range, and editing an entry still means the editor.
ADR-0036 gains a dated note under §D5, worded in the plan's Task 1.

### §D5 — Anchor, re-anchor, unanchor: refused while dirty or stale, then one guarded write

One door, `PraticaCommandActions.rewriteEntry(_:_:)` in the new
`PraticaCommandActions+Entries.swift`, serves «Collega a un messaggio…» and «Scollega dal
messaggio»:

1. **Dirty check.** `VaultController.hasUnsavedTab(showing:)`, extracted from `canOperate(on:)`
   without recording anything; `canOperate` becomes that call plus its own record, unchanged in
   behaviour. On a dirty `pratica.md` Pratiche reports its own sentence (F6's wording names other
   verbs): «Salva «pratica.md» prima di collegare o scollegare una voce.»
2. **Fresh read** through `session.read`.
3. **Origin check.** The read's `contentHash` must equal `timelineOrigin`. Otherwise the file
   changed since the timeline was drawn, the entry's ordinal may name another entry, and the
   command refuses, reloads the timeline and says ««pratica.md» è cambiato: la cronologia è stata
   ricaricata, riprova.» (R-18).
4. **Transform** by the entry's `fileOrdinal` (`anchoring` or `unanchoring`). `nil` means nothing
   to write.
5. **Write** with `expecting: record.contentHash`. A `WriteRefusal` is reported like the
   composer's. Then `reload()`. ADR-0067's door catches any clean editor tab up.

No undo is registered. The inverse is the other named verb, as for ADR-0049's link verbs, which
register none either.

### §D6 — «Sposta in…» carries anchored entries; Escludi, «Aggiungi anche a…» and «Rigenera» write no body

`move(_:detail:to:)` gains a pre-flight and a tail, in a new `PraticaEntryCarry.swift`.

- **Pre-flight, before anything moves.** Read the source `pratica.md` fresh and collect
  `blocks(anchoredTo:)`. With none, the rest is today's path exactly (R-18). With some: refuse,
  with a sentence and nothing moved, when either `pratica.md` is dirty in a tab
  («Salva «…» prima di spostare un messaggio con voci collegate: non è stato spostato nulla.»),
  or when the source's hash differs from `timelineOrigin` (the stale sentence of §D5).
- **Order.** `moveFiles`, then the two dossier writes exactly as today (F7), then the carry:
  append the blocks to the destination (fresh read, `appending`, `expecting:`), and only when that
  write landed, remove them from the source (fresh read, `removing`, `expecting:`).
- **Every step asks for a dirty tab again.** The pre-flight's dirty check runs before the moves,
  the dossier writes and the test hook, and `expecting:` cannot see a tab that turned dirty since,
  because the disk did not change. So each step asks `hasUnsavedTab(showing:)` again after its
  fresh read and the hook, with no `await` between that answer and its write (CLAUDE.md: a
  precondition before an `await` is a filter, not a guard). A dirty tab fails the step as a
  refusal does, with the same outcome and sentence: an append that did not land leaves the
  entries in the source, a removal that did not land leaves them in both.
- **Outcomes.** `.carried`; `.appendedOnly` (the source removal was refused, or some blocks were
  no longer there to remove), reported as «Le voci collegate sono ora sia in «…» sia in «…»: non è
  stato possibile toglierle dall'origine.»; `.notCarried` (the destination write was refused, so
  the message moved and the entries stay in the source, orphaned), reported as «Il messaggio è
  stato spostato, ma le voci collegate sono rimaste in «…».». Text is never lost; the worst case is
  a declared duplicate (R-15).
- **Undo.** Today's undo runs first, unchanged. Then the carry runs back according to the
  recorded outcome: `.carried` appends to the source and removes from the destination;
  `.appendedOnly` first appends to the source, from a fresh read, every carried block the source
  no longer holds (`removing(…).missing` over the source), and then removes the blocks from the
  destination; `.notCarried` touches no body. Removing from the destination only would lose text
  when the move's removal was partial: a block the source did give up would then be in neither
  file. The accepted cost: when a block was edited in the source after the append, the edited text
  no longer matches the carried one, so its old version comes back beside the edit, both under
  the message, a visible duplicate rather than a silent loss. After a full refusal the source
  still holds every block and nothing is appended. A dirty tab on either file at undo time skips
  the carry-back and says where the entries are, and each step re-checks it as in the move.
  Carried-back blocks land at the end of the source file (§D12). Redo re-runs `move`, which
  recomputes the carry.
- **What starts the carry, and the session it runs in.** The carry starts when the message
  note itself moved, not when any message file did: `moveFiles` moves the `.md` and the `.eml`
  independently, and with only the sidecar moved the message is still in the source, so its
  entries stay there, anchored to it, with no sentence of their own beyond `moveFiles`'. The
  session is read at the top of the verb, before its first suspension, and handed to the carry
  steps and to the undo; every step refuses when it is no longer the current one, asked again
  after the test hook and before the write, beside the dirty-tab re-check. A precondition read
  before an `await` is a filter, not a guard.
- **The undo's own guards.** The undo closure captures the session the move was made in, and
  the carry-back writes nothing when another session is current: the undo manager outlives a
  vault switch, and a same-named `pratica.md` in the other vault is not the file the blocks came
  from, so the sentence says where the entries are instead (ADR-0067 §D4's guard shape). The
  carry-back also runs only when `moveBack` actually restored the message note to the source:
  otherwise the entries stay with the message, in the destination, rather than orphaned in a
  source the message did not return to.
- **Round trip.** A move and its undo return both files byte-exact, with one exception in
  whitespace only, never text: a source file that already ended in a blank line, or had no final
  newline, returns differing by one blank line, because `appending` writes exactly one blank line
  before each block.
- **Test seam.** `PraticheController.testOnlyCarryHook: (@MainActor (PraticaEntryCarry.Phase) async
  -> Void)?`, `@ObservationIgnored`, awaited between each carry step's read and its write
  (`.willAppend`, `.willRemove`). A test writes the file there, and the real `expecting:` refuses.
  This is ADR-0057 §D9's `DiaryController.testOnlyWriteHook` shape, an instrument inside the
  existing commands-over-a-temporary-vault seam, not a new seam.
- **Escludi, «Aggiungi anche a…», «Rigenera»** gain no code. Escludi keeps writing the source
  dossier's `excluded` key and its undo removes it (F7); the entries' text is byte-identical
  throughout, they read as orphaned, then anchored again, with no body write (R-13). «Aggiungi
  anche a…» writes the destination's `included` key only (R-16). «Rigenera» never opens
  `pratica.md` (R-17). Tests pin all three.

### §D7 — The commands, the composer and the inspector

- **`MessageCommand`** gains `.addNote` («Aggiungi nota») and `.addCall` («Aggiungi telefonata»),
  always available and carrying no argument. `allCases.count` goes from 8 to 10. Their place in
  the declaration order and their symbols are fixed at the mockup gate (G1). A new
  `accessibilityCommands(hasAttachments:hasLinkedNote:)` returns the available commands that carry
  no argument. The message row draws them as `.accessibilityActions`, which reaches every
  argument-free verb, not only the two new ones (R-02).
- **`PraticaEntryCommand`**, a new catalogue in `PraticaEntryCommand.swift`, holds `.linkMessage`
  («Collega a un messaggio…») and `.unlinkMessage` («Scollega dal messaggio»),
  `available(hasAnchor:)` (unlink only with an anchor, R-12) and the identifier
  `pratiche-entry-command-<raw>`. It drives the entry row's context menu and its
  `.accessibilityActions`.
- **The composer** gains an anchored insert: the pratica from the row, a heading at `Date()`, the
  counterpart from a fresh read of the message file through `PraticaEntry.counterpart(ofMessage:
  ownAddresses:)`, falling back to today's `counterpart(of:fallback:)`, the anchor line, one
  guarded write, the mirror on today, the reload and the existing hand-off (R-03). Its dirty-tab
  refusal stays `canOperate(on:)`, as for every insert today.
- **The inspector** renders `PraticaEntryEdit.removingAnchorLines(in:)` of the body (F10), so the
  anchor line appears in no rendered body (R-01).

### §D8 — The message picker is a pane sheet

`PraticaMessagePicker` is shaped like `PraticaLinkPicker` (ADR-0049 §D10): filter field, list,
footer, keyboard reachable. A pure `PraticaMessagePickerModel.rows(from:filter:currentAnchor:)`
lists the pratica's messages with a non-empty Message-ID (date, sender, subject), filters on sender
and subject, and marks the current anchor (R-11). It is hosted by `PratichePane+Sheets.swift`
through `pratiche.anchorRequest`, the `renameRequest` shape, because the verb is offered from one
surface only, the timeline inside the pane.

### §D9 — The anchor line is concealed on ADR-0029's whole-line path

- `MarkdownStyler.Span.messageAnchor`, emitted for the whole line when
  `PraticaEntryAnchor.messageID(inLine:)` answers, with an early return, the rule's shape (F11). It
  joins the not-spell-checked shelf.
- `HiddenMarker.Kind.messageAnchor`, a block kind (`isInline == false`), so the reveal is
  paragraph-grained: the caret entering the line reveals it raw. `stillSpellsAMessageAnchor`
  re-validates it.
- `MessageAnchorFragment`, a new `NSTextLayoutFragment` beside `HorizontalRuleFragment`, draws the
  small marker the mockup fixes, in a colour pushed in from a token (`ruleColor`'s shape). It is
  vended only while `hidesMarkup` is on and the paragraph is not revealed; with the setting off
  the line is raw (R-20).
- `MarkdownAttributedText` and `CardTextAttributes` give the span `.textTertiary`, a colour only.
  `CardTextView`'s kind mapping is not touched, so Workspace cards never conceal it (ADR-0029 §D17).
- The rule is path-agnostic. The styler knows no note path, and only this feature writes the
  line, so concealing it in any note costs nothing.

### §D10 — The connectors expose the anchor and share the rule

`PraticaTimelinePayload.Entry` gains `anchorMessageID: String?` and `anchorState: String?`
(`"anchored"` or `"orphaned"`), both `nil` and therefore omitted for messages and free entries
(F12). `VaultPratiche.timeline(ofPraticaFolder:session:)` builds its rows through
`PraticaManualEntries.parse` and `PraticaTimelineOrder.arrange`, so its order is the app's
(R-08, R-21). An entry's `date` stays its heading time and its `body` excludes the anchor line.
`perg pratica` prints one line under an anchored or orphaned entry. The MCP `pratica` tool
description names the two fields. The connectors gain no write (ADR-0036 §D20, `PG-115`).
`scripts/mcp-smoke.py` gains a stage over a fixture with one anchored and one orphaned entry.

### §D11 — Relation to ADR-0049: one new relation, carried by the entry's own text

ADR-0049 kept manual entries unlinkable because an entry has no file of its own to carry a key
(F13). The anchor answers exactly that reason: the relation lives in the entry's text, in the one
file that owns the entry, as a line of the body and not as a frontmatter key. This record adds one
relation, entry to message. It does not make entries linkable to notes, tasks or boards,
`PraticaLinks` and the `pergamenum-dossier-links-*` keys are untouched, and `pergamenum-mail-note`
on message files is untouched.

### §D12 — Named and not fixed

- **Other reading surfaces show the line raw.** The export, a transclusion or a hover preview of
  `pratica.md` renders the anchor line as text. Only the editor and the inspector hide it.
- **A Message-ID containing `-->`, CR or LF** cannot be anchored. `line(for:)` refuses it, and the
  verb reports it.
- **Carry-back lands at the end of the file.** The original offsets go stale as soon as anything
  writes the source. Placement is by anchor, so the timeline looks the same; only file order, and
  so an equal-minute tie within one message, can change.
- **A non-anchoring anchor line is concealed too.** A copy of the line written further down an
  entry anchors nothing (§D1) but is still hidden in the editor, since the styler reads lines, not
  entries.
- **VoiceOver in the editor reads the raw line.** The concealment is visual.
- **Protected-interface proposal (G2).** `PraticaEntryAnchor.line(for:)` spells an on-disk format
  every anchored entry depends on, the argument that protects `PraticaNaming.messageFileName`.
  Proposed entry: `Sources/Core/Pratiche/PraticaManualEntries.swift:PraticaEntryAnchor.line(for:)`.
  Adding it is Stefano's decision.

## Alternatives considered

- **Moving `PraticaTimelineModel` into `Sources/Core` as the shared rule.** Rejected. It reads
  `ColorToken` (DesignSystem) and `MailURL`, which lives in `MailLink.swift`, the one Core file
  excluded from `sharedSources`. Making it compile in the tools means splitting it anyway; the
  split in §D2 keeps the placement rule pure and leaves lanes, colours and links in the app.
- **Two parsers kept in step by a parity test.** Rejected. R-21 asks for one parser, and F2 and F3
  show two copies of one grammar already drifted once without a test noticing.
- **Anchoring on a fresh read alone, with no origin check.** Rejected. The command names an entry
  by its ordinal in the text the timeline read. If a writer changed `pratica.md` in between,
  ordinal N can be a different entry, and the anchor would land on it silently. `expecting:`
  guards only the gap between the fresh read and the write.
- **Naming the entry by a fingerprint of its heading and body.** Rejected. It is a second identity
  concept for a rare case. Two same-minute entries with the same text are ambiguous under it, and
  the origin check turns the rare case into one retry.
- **One combined write per `pratica.md` on «Sposta in…» (dossier key and body together).**
  Rejected. It would route the dossier update, which today never refuses on a dirty tab, through
  the body carry's refusals, and change the path R-18 requires unchanged when nothing is anchored.
  `DossierWriter` would also have to learn about bodies.
- **Carrying back to the original position on undo.** Rejected. The offsets recorded at carry time
  go stale with any write to the source. Placement does not depend on position (§D12).
- **Concealing by length-preserving substitution, or by an attachment.** Rejected for ADR-0029
  §D1's reason: a forty-character line cannot be drawn as a glyph by substitution, and an
  attachment changes the text storage the editor saves. The rule's collapse-plus-fragment path is
  the working precedent.
- **Hiding the line in `MarkdownBlockParser` for every reading surface.** Rejected for this chain.
  That parser serves every reading surface and Workspace, for a line only `pratica.md` carries.
  The inspector strip covers R-01, and the other surfaces are named in §D12.
- **Hosting the picker on `RootView` through `Navigation`, as `PraticaLinkPicker` is.** Rejected.
  ADR-0049 §D10 hosted that picker there because its command is offered from more than one surface.
  The entry verbs are offered from the timeline only, and the pane's own sheet reaches it.

## Consequences

**Positive.** A note written today about last week's email sits under that email, the last row
included. One grammar and one order serve the app, `perg` and the MCP server, which also fixes the
lexicographic `-10`/`-2` tie (F3) and the CRLF gap (F4) as side effects. Every new body write goes
through the existing door, precondition and landed-change catch-up; no new write mechanism exists.
A move keeps a note with its email, and no command ever deletes handwritten text.

**Negative.** The timeline now writes entry bodies, which is exactly what ADR-0036 §D5 kept it
from; the amendment is bounded to whole-file writes from fresh reads. A stale timeline refuses an
anchor once and reloads. A carry can leave a declared duplicate. `MessageCommand` grows to ten
cases, and the message row's accessibility actions now list every argument-free verb. The app's
equal-instant order flips, visibly, for any pratica with a same-minute message and note.

**Neutral.** No schema, frontmatter or message-file change, and no migration: existing entries
stay free until anchored by hand. `perg` and `pergamenum-mcp` output gains two optional keys.

## Gates

- **G0: the plan and this record**, with the interpretations the plan lists (R-13/R-14 wording
  against the dossier writes, the inspector strip, the message's counterpart in the heading, the
  filter rule, the path-agnostic concealment, no gap inside an anchored group, the timeline reload
  on `InspectorKey`, the carry hook).
- **G1: the mockup**, under `docs/design/pratiche/`, before any view is built (R-10). It also fixes
  the catalogue order and symbols, the orphan caption, the marker glyph and any new token.
  **Approved by Stefano on 2026-09-30, with no mockup file under `docs/design/pratiche/`.** Tasks 6
  and 7 are open. The choices G1 was to fix (catalogue order, symbols, orphan caption, marker glyph,
  new tokens) are made by the implementation, following this record and the existing Pratiche
  views, and are reviewed on the Debug build in Task 8's hand check. R-10 is met by this approval
  record, not by a mockup.
- **G2: the protected-interface entry** of §D12.

## Implementation notes

**Task 8 hand check, 2026-10-01: the footer on every row, and double-click/Return toggle a row.**
Two changes Stefano asked for on the Debug build, shipped in PR #761.

- *The footer closes every message row, collapsed or expanded* (`PraticaMessageRow.body`). This
  amends DESIGN.md's message row anatomy and UX-BLUEPRINT §5, which drew it only on the expanded
  row. No new read is needed, since `PraticheController+TimelineRead` already builds every row's
  `PraticaRowDetail` when the timeline loads. The cost is one caption line per collapsed card, and
  at the 428 pt minimum the verbs stack (`ViewThatFits`).
- *A double-click on a row, or Return on the selected row, toggles its expansion*, through the
  `List`'s own `contextMenu(forSelectionType:menu:primaryAction:)` with an empty menu
  (`PraticaTimelineView.list`, `ContenitoreList`'s shape). No custom gesture competes with
  `List(selection:)` (ADR-0025 §D9). This amends UX-BLUEPRINT's shortcut table: Return toggled
  nothing and was never wired to «Apri in Mail», and it now opens or closes the row. Every row
  takes the same toggle, manual entries included.
- *Measured by hand on the Debug build (gate M), all five checks passed*:
  1. a double-click on a collapsed card expands it, and a second one collapses it;
  2. Return toggles the selected row;
  3. the per-row context menus survive the list-level primary action, «Inserisci qui» included;
  4. a double-click on an attachment chip opens the file and leaves the row as it was;
  5. a double-click on a word of an expanded body selects the word and keeps the row open.

  The ordered fallbacks, row menus moved into the list-level closure and a header-only
  `simultaneousGesture`, were not needed.
- *GUI tests*: one, `PraticheUITests.testDoubleClickTogglesMessageRow`. The toggle runs in
  AppKit's table double-action, which no hosted-view test can drive. The existing M6 step
  (a double-click on body text, then Backspace) is the regression check for check 5. The footer is
  pinned by a hosted-view test.
- *Hand check, «Sposta in…» on a `/private` vault*: on the hand-check vault, opened as
  `/private/tmp/…`, «Sposta in…» put the message at the vault root and the undo moved nothing.
  The anchored call was carried and carried back correctly. The cause predates this ADR (ADR-0068's
  `PraticaFileOperations`): `VaultScanner.relativePath(of:under:)` compared `standardizedFileURL`
  paths, and `standardizedFileURL` drops a leading `/private` only from a path that exists. So a
  move target, which does not exist yet, failed the prefix test against its root and fell back to its
  bare name. The function now drops the prefix from both sides, which fixes move, copy, undo and the
  watcher's paths for a deleted file in one place. A vault under the home folder was never affected.
  Pinned by `VaultScannerRelativePathTests` and
  `PraticaFileOperationsSessionTests.moveFilesAndMoveBackLandRightUnderAPrivateSpelledRoot`.

## References

- `docs/specs/pratiche-message-anchored-entries.spec.md`, `docs/plans/pratiche-message-anchored-entries.md`
- ADR-0036 §D5, §D6, §D20, §D21; ADR-0049 §D1, §D2, §D4, §D10; ADR-0023 §D1; ADR-0029 §D1, §D17;
  ADR-0043 §D7, §D8; ADR-0052; ADR-0057 §D3, §D9; ADR-0067; ADR-0068 §D1, §D20; ADR-0069;
  ADR-0070
- Code, at `160d3e76`: `Sources/Features/Pratiche/PraticheController+TimelineRead.swift`,
  `Sources/Connector/VaultPratiche.swift`, `Sources/Features/Pratiche/PraticaTimelineModel.swift`,
  `Sources/Features/Pratiche/PraticaEntryComposer.swift`, `Sources/Features/Pratiche/MessageCommand.swift`,
  `Sources/Features/Pratiche/PraticaCommandActions.swift`, `Sources/Features/Pratiche/PraticaTimelineView.swift`,
  `Sources/Core/Pratiche/PraticaEntry.swift`, `Sources/Features/Editor/MarkdownStyler.swift`,
  `Sources/Features/Editor/EditorDecorationDelegate.swift`, `Sources/App/VaultController+Files.swift`
