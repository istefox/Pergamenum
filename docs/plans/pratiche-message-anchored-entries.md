# Plan: Pratiche, manual entries anchored to a message (PG-338)

- **SPEC:** `docs/specs/pratiche-message-anchored-entries.spec.md` (Approved 2026-09-30). It is the
  authority for scope, decisions and R-01..R-24.
  - The repo-root `SPEC.md` (Contenitore, ADR-0071) and `BRAINSTORM.md` (PG-018) are other features
    and not inputs. The repo-root `UX-BLUEPRINT.md` was read as context for the timeline's current
    shape only; it adds no requirement here.
- **ADR:** `docs/adr/0076-pratiche-message-anchored-entries.md` (new, `proposed`). It extends
  ADR-0036 and amends its §D5. Recheck the number against `origin/main` right before each merge
  (`docs/adr/README.md` rule 1).
- **Base:** `160d3e76`. Every line number below was read there. `origin/main` is at `c99103c8`,
  whose changes touch none of the files this plan names. Merge `origin/main` into the branch before
  Task 2 starts, then `tuist install` and `tuist generate --no-open`.
- **Delivery: two PRs.**
  - **PR 1** covers Tasks 2-5: the Core parser, transforms and ordering, the app model switch-over,
    connector parity, and the carry on «Sposta in…». No new control is drawn. Hand-written anchor
    lines start placing entries under their message, full width, as today's entry rows.
  - **PR 2** covers Tasks 6-7: the new verbs, the picker, the rows and the editor concealment. It
    starts after gate G1 (the mockup).
  - Task 1 opens both PRs, and Task 8 closes each.

## SPEC decisions registered, not reopened

ADR-0076 carries these as the SPEC states them:

- **The anchor.** A comment line `<!-- pergamenum-message: <Message-ID> -->`, first line after the
  heading, surrounding whitespace allowed, the id with its angle brackets, compared byte for byte.
  Rejected by the SPEC: a wikilink to the message file; both carriers.
- **Time.** The heading keeps the time of writing; the mirror goes to the day of writing.
- **Look.** Drawn in the message's lane, at the lane's width, indented, in the manual-entry colour.
- **Creation.** «Aggiungi nota» and «Aggiungi telefonata» on every message row, the last included,
  through the message command catalogue.
- **Verbs on other commands.** Escludi leaves the entries in place, orphaned, and its undo
  re-anchors with no write. «Sposta in…» carries them, append then remove, and its undo carries
  them back. «Aggiungi anche a…» does not copy them.
- **Editor.** The anchor line is concealed with «Nascondi markup» on, revealed on caret entry, raw
  with the setting off.
- **Filters.** An anchored entry follows its message; a matching entry brings its message.
- **Connectors.** They expose the anchor, share the ordering and one tie-break, and stay read-only.
- **Existing entries.** «Collega a un messaggio…» (write or replace) and «Scollega dal messaggio»,
  through a list picker shaped like ADR-0049 §D10's.
- **Tie-break.** At an equal instant the message sorts first.
- **Out of scope, not planned:** connector writes (`PG-115`), drag-to-anchor, copying on «Aggiungi
  anche a…», migration. Two pre-existing defects go to `TODO.md` in Task 8: the same-minute
  midpoint collision of «Inserisci qui», and a click on an entry row not jumping to its heading.

## Interpretations resolved here (confirm at G0)

Each is a reading of the SPEC this plan builds on. A different answer re-plans the named task.

1. **R-13 and R-14 against the dossier writes.** Escludi, its undo and «Sposta in…» already write
   the `pergamenum-dossier-excluded`/`-included` keys of `pratica.md` (ADR-0076 F7). R-13's
   "without writing `pratica.md`" is read as "without writing its body", and R-14's "the rest of
   both files is byte-identical" as "the rest of both bodies, and every frontmatter line other than
   the dossier keys the verb already writes". R-16 already says "bodies". **Recommended.** The
   literal reading would forbid today's dossier writes, which the SPEC's Constraints keep. Task 5.
2. **The inspector hides the anchor line** (ADR-0076 §D7). It renders `pratica.md`'s body whole, and
   R-01 says the line never appears in a rendered body. Task 7.
3. **The heading's counterpart** for an anchored entry is the message's counterpart (the sender of a
   received message, else the first recipient not the user's own, else the first Cc), not the
   dossier's first counterpart the free «Nota» uses. R-03 says "the message's counterpart". Task 6.
4. **Filters treat a message and its anchored entries as one unit**: the group shows when the
   message passes the sender and attachment filters and the text matches the message or any of its
   entries; a non-matching entry of a shown message still shows. Task 3.
5. **Concealment is path-agnostic** (ADR-0076 §D9): the styler has no note path, and only this
   feature writes the line. Task 7.
6. **No «Inserisci qui» inside an anchored group.** A free entry cannot land between a message and
   its anchored entries, so the gap is not offered there; the group's last row offers the gap after
   the group. Task 3.
7. **The timeline reloads on the inspector's `InspectorKey` beat** (ADR-0076 §D3, F14), so an in-app
   save of `pratica.md` refreshes placement and the origin hash. Without it, anchoring after an
   editor save refuses once as stale. Task 3.
8. **R-15's refusals are forced through a test-only hook**, `PraticheController.testOnlyCarryHook`,
   an instrument inside the SPEC's second seam (ADR-0057 §D9's shape), not a new seam. Task 5.
9. **Message rows gain `.accessibilityActions` for every argument-free verb**, not only the two new
   ones, because the actions come from the catalogue (ADR-0023 §D1). Task 6/7.
10. **Anchor and unanchor register no undo**; the inverse is the other verb, as with ADR-0049's link
    verbs. Carried-back entries land at the end of the source file. Tasks 5-6.

## What reading the code added (the coder must know these)

1. **Two parsers, one grammar, two tie-breaks** (ADR-0076 F1-F3):
   - the app's `readManualEntries`/`parseEntryHeading`/`entryHeadingFormatter`
     (`Sources/Features/Pratiche/PraticheController+TimelineRead.swift:187-259`, `:291`);
   - the connector's `manualEntryRows`/`entryHeading` (`Sources/Connector/VaultPratiche.swift:247-300`),
     with no caller outside that file;
   - `VaultPratiche.swift:177`'s doc comment says the connector breaks a tie "the same way
     `PraticaTimelineModel.ordered(_:)` does". It does not (app: entry first; connector: message
     first). The comment goes with the rewrite.
2. **Ids stay as they are.** App entry ids are `"<pratica>#entry-<yyyyMMddHHmm>"` plus `-<n>` for a
   repeated minute (`:207-209`); `PraticaEntryRow` builds its AX identifier from `entryIDFormatter`.
   Selection, expansion and `details` are keyed on these ids, so the new parser must reproduce them
   exactly. Connector entry ids (`"pratica.md#<n>"`) are internal to the sort and can go.
3. **`PraticaTimelineEntry`'s memberwise init** is used by `readMessages`, by the parser and by many
   tests. New fields go at the end, each with a default.
4. **`NoteStore.read` hashes the bytes it decodes** (`Sources/Vault/NoteStore.swift`, `read(_:)` and
   `static func hash(_:)` at `:225`). `readTimeline` must read `Data` once, hash it with
   `NoteStore.hash` and decode it with `NoteStore.decodedText`, so the origin equals
   `session.read(notePath).record.contentHash` for an unchanged file.
5. **`PraticaCommandActions` is rebuilt inside every undo closure** (`register(undoName:_:)`,
   `PraticaCommandActions.swift:482-503`). Anything the carry-back needs (the outcome, the blocks,
   both paths) is captured by value in `move`'s closure. The test hook lives on
   `PraticheController`, which survives.
6. **`DossierWriter.update` never asks about dirty tabs** (F7). The carry's dirty check is a new
   pre-flight that runs only when there is something to carry, so the no-anchor path stays
   literally today's.
7. **`canOperate(on:)` records a sentence about renaming, moving and deleting**
   (`Sources/App/VaultController+Files.swift:18-34`) and is shared by batch move and every file
   verb. Extract `hasUnsavedTab(showing:)` without changing `canOperate`'s behaviour; Pratiche
   reports its own sentences.
8. **Exhaustive switches the editor change must join:** `MarkdownStyler.swift:160-176`,
   `MarkdownAttributedText.swift:251`, `CardTextAttributes.swift:220`,
   `NoteTextView+Coordinator.swift:597-615`, `EditorDecorationDelegate.swift:107-111` and
   `:756-801`, plus the test list `Tests/MarkdownAttributedTextTests.swift:348-374`
   (`everySpanKind`). `CardTextAttributes.swift:220` is a colour table: the new span joins
   `.horizontalRule` on the `.textTertiary` shelf. **Do not touch `CardTextView.swift:374-388`**:
   its span-to-kind switch ends in `default: nil`, and `Tests/InlineSpanRevealFenceTests.swift:327`
   fails if it gains an eighth `case` line.
9. **The timeline does not reload after an in-app save** of `pratica.md`; only the inspector does,
   on `InspectorKey` (`PratichePane.swift:85`).

## Standing rules for every task

- **Tooling.**
  - Run `tuist install` once per fresh worktree.
  - Run `tuist generate --no-open` after adding any file. Every new file here falls under an
    existing glob: `Sources/Core/**` reaches `perg` and `pergamenum-mcp` with no `sharedSources`
    edit, and `Sources/Features/**` and `Sources/App/**` stay app-only.
  - Never edit `.xcodeproj` or `.xcworkspace`.
- **Tester owns the signatures, coder owns the bodies.**
  - Every "Declarations" list below belongs to the tester half of its task.
  - Each declaration gets a body that keeps today's behaviour (a no-op, `nil`, `[]`, the input
    unchanged, today's rule), so the target builds and the new tests fail on their assertions.
  - If a batch leaves the target unbuildable, it produces no reds at all.
- **Keep the build green.**
  - Every task ends with the app, `perg` and `pergamenum-mcp` building, and `PergamenumTests` green
    apart from the declared reds.
  - Run the **full** `PergamenumTests` suite after every coder half. The timeline order, the
    message catalogue, `canOperate` and the editor's span and marker enums are shared contracts.
- **Tests.**
  - Swift Testing only, on `TemporaryVault` (`Tests/TemporaryVaultSupport.swift`) with a temporary
    state base. Fixtures follow `PraticaExcludeOrderingTests` (`Tests/PraticheControllerTests.swift:1190-1222`):
    `VaultController(recents: .volatile(), openTabs: .volatile())`,
    `PraticheController(probe: { .granted }, performSync: { _, _ in })`,
    `PraticaCommandActions(pratiche:vault:navigation:)`; undo follows `:647-661`
    (`UndoManager()`, `manager.undo()`, `waitUntil {}`).
  - Never disable or delete a test. An assertion that must change is explained in chat first; the
    known ones are listed per task.
  - Zero GUI tests (SPEC Test seams).
- **UI.** Strings in Italian. Colours and fonts through tokens only. SwiftLint clean.
- **Protected interfaces.** Every entry in `.claude/protected-interfaces` stays untouched,
  `Dossier.render`, `PraticaNaming.messageFileName` and `VaultAPI.PraticaSummary` included.
  `IndexCache.schemaVersion` does not change.

---

## Task 1 — Record, mockup, and the ADR-0036 note (R-10, R-24)

Owners are the parent session and Stefano. No production code.

- **ADR.** `docs/adr/0076-pratiche-message-anchored-entries.md` is written as `proposed`. Stefano
  answers G0 (this plan, the ADR and the ten interpretations above) before Task 2.
- **ADR-0036 note (R-24).** Add under §D5 of `docs/adr/0036-pratiche.md`, after its "Reason"
  paragraph, in PR 1:

  > **§D5 amended 2026-09-30 by ADR-0076 §D4** — the timeline's writes widen: an appended heading
  > may carry an anchor line in the same write, and the timeline may write, replace or remove one
  > anchor line, and carry anchored entry blocks between two `pratica.md` files on «Sposta in…»
  > and its undo. Each is one whole-file `VaultSession.write` with `expecting:`, computed from a
  > fresh read. The single-editor rule stands: the timeline never binds a text view to a range.

- **Mockup (R-10).** Under `docs/design/pratiche/`, beside `Pergamenum Pratiche.dc.html`. It must
  show:
  - an anchored entry under a received and under a sent message, collapsed and expanded, light
    and dark, with the indent and the manual-entry colour and symbol;
  - two entries on one message, and an anchored entry under the last row;
  - an orphaned entry with its caption;
  - the message footer and context menu with «Aggiungi nota» and «Aggiungi telefonata», and their
    place in the order (they sit near ADR-0049's «Collega nota…»: settle the three labels);
  - the entry context menu with «Collega a un messaggio…» and «Scollega dal messaggio»;
  - the message picker, with the current anchor marked;
  - the editor marker, collapsed and revealed.

  Stefano's approval is gate G1. It opens Task 6 and Task 7, and fixes the catalogue order, the
  symbols, the orphan caption, the marker glyph and any new token. PR 1 does not wait for it.
- **Done when:** the ADR and the ADR-0036 note are on the branch, and the mockup is approved.

## Task 2 — Core parser, anchor codec and text transforms (R-01, R-03, R-11, R-12, R-14, R-19, R-23)

### Declarations (tester)

New Foundation-only files under `Sources/Core/Pratiche/`:

- **`PraticaManualEntries.swift`**
  - `struct PraticaManualEntry: Equatable, Sendable` with `kind: PraticaEntry.Kind`, `date: Date`,
    `subject: String` (the heading tail), `counterpart: String`, `anchor: String?`, `body: String`,
    `ordinal: Int`, `occurrence: Int`, `blockRange: NSRange`, `anchorLineRange: NSRange?`.
  - `enum PraticaManualEntries { static func parse(_ source: String) -> [PraticaManualEntry] }`.
    Stub: `[]`.
  - `enum PraticaEntryAnchor { static func line(for messageID: String) -> String?;
    static func messageID(inLine line: some StringProtocol) -> String? }`. Stubs: `nil`.
- **`PraticaEntryEdit.swift`**
  - `enum PraticaEntryEdit` with `anchoring(entryAt ordinal: Int, to messageID: String, in source:
    String) -> String?`, `unanchoring(entryAt:in:) -> String?`, `blocks(anchoredTo:in:) -> [String]`,
    `appending(_ blocks: [String], to target: String) -> String`,
    `removing(_ blocks: [String], anchoredTo messageID: String, from source: String) -> Removal`,
    `removingAnchorLines(in source: String) -> String`.
  - `struct Removal: Equatable, Sendable { var text: String; var missing: [String] }`.
  - Stubs: `nil`, `nil`, `[]`, `target`, `Removal(text: source, missing: blocks)`, `source`.

Edits to `Sources/Core/Pratiche/PraticaEntry.swift`:

- `insert(kind:at:counterpart:anchor: String? = nil, in:)`. The stub ignores `anchor`. Existing
  callers compile unchanged: `Sources/Features/Pratiche/PraticaEntryComposer.swift:64`,
  `Tests/PraticaEntryTests.swift:21,30,41,73-80`, `Tests/CRLFAppendTests.swift:136,137,264`,
  `Tests/VaultWriteOrderingBatch3Tests.swift:172,200,227`.
- `static func counterpart(ofMessage frontmatter: MessageDocument.MailFrontmatter, ownAddresses:
  Set<String>) -> String?`. Stub: `nil`.

### Red suite (tester)

`Tests/PraticaManualEntriesTests.swift`:

- **Grammar.** A note and a call; a counterpart containing ` · `; a `## ` heading that is not an
  entry ends the open one and opens nothing; frontmatter before the body shifts every range; a file
  without frontmatter; `ordinal` in file order; `occurrence` counts a repeated minute.
- **Ranges.** `blockRange` spans the heading through the line before the next `## ` (or the end of
  the file); the substring at `anchorLineRange` is the anchor line.
- **Anchor (R-01).** Recognised directly under the heading, with leading and trailing whitespace;
  ignored after a blank line and anywhere lower in the entry (it stays body text there); never in
  `body`.
- **CRLF (R-19).** The same file with CRLF parses to the same values, no `\r` in any string, and
  ranges that address the CRLF source.
- **Codec.** `line(for:)` round-trips through `messageID(inLine:)`; `nil` for an empty id and for
  one containing `-->`, CR or LF; `messageID(inLine:)` refuses a missing space and an empty id.

`Tests/PraticaEntryEditTests.swift`, each on LF and CRLF:

- **Anchor and re-anchor (R-11).** Inserts the line after the heading; replaces an existing anchor
  keeping its terminator; `nil` for the same id and for an out-of-range ordinal; the frontmatter
  bytes and every other line are identical.
- **Unanchor (R-12).** Removes the line and its terminator only; `nil` on a free entry.
- **Carry (R-14, R-19).** `blocks` returns only blocks anchored to that id, LF-normalised,
  trailing blank lines dropped. `appending` gives exact bytes: one blank line before each block,
  never two, in the target's line break. `removing` drops exactly the matching block ranges and
  leaves every other byte; an edited block lands in `missing` and stays; two identical blocks are
  consumed once each.
- **Inspector (R-01).** `removingAnchorLines` drops position-one anchor lines only.

Additions to `Tests/PraticaEntryTests.swift`:

- **Anchored insert (R-03).** Heading, anchor line, empty body line, in the source's line break;
  `cursorRange` at the body line; the no-anchor output is byte-identical to today's.
- **Counterpart (R-03).** Received gives the sender's display text; sent gives the first To that
  is not own, then the first Cc; `nil` with none.

`SharedSourcesPurityTests` already covers the new files (R-23).

### Coder

Fill every body. `parse` reuses `PraticaEntry.headingFormatter` (*2026-10-01, PG-356:* plus an
optional `±hh:mm` offset token read through `UTCOffset`); the body offset is the source's
UTF-16 length minus that of `NoteDocument.parse(source).body`.

## Task 3 — One ordering rule, and the app's model switches to it (R-01, R-04, R-05, R-06, R-07, R-08, R-21)

### Declarations (tester)

- **`Sources/Core/Pratiche/PraticaTimelineOrder.swift`** (new, Foundation-only):
  - `enum Placement: Equatable, Sendable { case message, free, anchored(messageID: String),
    orphaned(messageID: String) }`;
  - `struct Item: Sendable` with `enum Kind { case message(messageID: String, tieKey: String),
    entry(anchor: String?, ordinal: Int) }` and `date: Date`. `tieKey` sorts two messages at one
    instant: the file name, or anything that sorts like it (the app passes its id);
  - `struct Placed: Equatable, Sendable { var index: Int; var placement: Placement;
    var placementDate: Date }`;
  - `static func arrange(_ items: [Item]) -> [Placed]`. Stub: input order, `.message` or `.free`,
    `placementDate` = the item's date.
- **`Sources/Features/Pratiche/PraticaTimelineModel.swift`:**
  - `PraticaTimelineEntry` gains, after `isInMail`: `anchor: String? = nil`, `fileOrdinal: Int = 0`,
    `placement: PraticaTimelineOrder.Placement = .free`, `placementDate: Date? = nil`,
    `hostDirection: MessageDocument.Direction? = nil`, and computed `placedAt` (stub: `date`);
  - `hostLane(for:) -> PraticaLane` (stub: `lane(for:)`);
  - `struct PraticaTimelineDay: Equatable { var day: Date; var entries: [PraticaTimelineEntry] }`
    and `daySections(of:calendar:) -> [PraticaTimelineDay]` (stub: today's grouping by `date`,
    moved from `PraticaTimelineView.swift:297-310`);
  - `insertionDate(between:and:) -> Date` (stub: `PraticaEntry.midpoint` of the two `date`s);
  - `orphanCaption(for:) -> String?` (stub: `nil`).
- **`Sources/Features/Pratiche/PraticheController+TimelineRead.swift`:** `TimelineRead` gains
  `praticaNoteHash: String? = nil`.
- **`Sources/Features/Pratiche/PraticheController.swift`:** `var timelineOrigin: String?`, written
  only by `reloadTimeline(from:)`.

### Red suite (tester)

`Tests/PraticaTimelineOrderTests.swift` (pure):

- **R-04.** Two entries on one message follow it by heading date, then ordinal; a free entry dated
  between them sits after the group, never inside it; the last message's entries close the list.
- **R-05.** An anchor naming no message is `.orphaned` at its heading date; the same input with the
  message present is `.anchored`.
- **R-08.** At one instant: message, then free entry, then orphaned entry by ordinal; two messages
  by `tieKey`; entries by ordinal, including a tenth same-minute entry after the second (ADR-0076
  F3).
- A Message-ID carried twice is owned by the first message; `placementDate` of an anchored entry
  is its message's date.

`Tests/PraticaAnchoredTimelineTests.swift` (pure, over `PraticaTimelineModel`):

- `ordered` fills `placement`, `placementDate` and `hostDirection`; `hostLane` of an anchored entry
  is its message's lane; `lane` stays `.entry`.
- **R-06.** The matrix of sender, attachments-only and text filters over a message with two
  entries, one matching; an orphaned and a free entry keep today's rule.
- `daySections` keeps a group under a message dated the day before its entries' headings.
- **R-07.** `insertionDate` next to an anchored entry uses its message's time.
- `nextRows` gives no successor inside a group and the next spine row after the group's last row;
  with no anchored entry it equals today's map.
- **R-05.** `orphanCaption` is non-nil for `.orphaned` only.

Additions to the `readTimeline` suites (`Tests/PraticheControllerTests.swift`, beside
`PraticaReadTimelinePendingAttachmentsTests` at `:1049`), over `TemporaryVault`:

- An anchored entry reads with its anchor, its `fileOrdinal`, and a preview and body without the
  anchor line (R-01); ids equal today's for the same file, repeated minute included.
- A CRLF `pratica.md` reads the same entries.
- `praticaNoteHash` equals `session.read(notePath).record.contentHash`; `reloadTimeline(from:)`
  stores it in `timelineOrigin` (R-21's app half).

### Coder

- `readManualEntries` becomes a map over `PraticaManualEntries.parse`, keeping today's ids and
  `details`; `parseEntryHeading` and `entryHeadingFormatter` are deleted. `readTimeline` reads the
  file's `Data` once (What reading the code added, item 4).
- `ordered` maps to `Item`s, calls `arrange` and fills the fields; `filtered` applies the unit
  rule; `nextRows` skips inside a group; `placedAt`, `hostLane`, `daySections`, `insertionDate`,
  `orphanCaption` get their bodies (the caption wording is G1's; use the ADR's until then).
- `PraticaTimelineView` calls `daySections` instead of its private `sections(of:)`, which is
  deleted. `PraticaEntryComposer.insertBetween` dates through `insertionDate`. No visual change.
- `reloadTimeline(from:)` (`PraticheController+Ledger.swift:209-230`) stores `timelineOrigin`, and
  clears it with no selection.
- `PratichePane.swift:85`: the `.task(id: pratiche.inspectorKey(for:))` also calls
  `pratiche.reloadTimeline(from: vault)` (interpretation 7).

### Update tests and call-sites asserting the old behaviour

- **Tie-break flip (observable).** `PraticaTimelineModel.ordered` has one production caller,
  `PraticheController+Ledger.swift:223`, and one test, `Tests/PraticaTimelineTests.swift:34`, whose
  dates are distinct and stays green. No test asserts today's entry-first tie (grep for the
  pattern found none).
- `filtered`: `Tests/PraticaTimelineTests.swift:141-178` and
  `Tests/PraticaTimelineNextRowsTests.swift:71-77` use free entries only and stay green.
- `nextRows`: `Tests/PraticaTimelineNextRowsTests.swift:47-77` compares against a reference
  successor map over inputs with no anchor, and stays green.
- `readTimeline`'s signature is unchanged: `Tests/VaultBoundaryCallSiteTests.swift:265`,
  `Tests/PraticaLedgerTests.swift:81`, `Tests/PraticheControllerTests.swift:1073`.

## Task 4 — Connector parity (R-01, R-08, R-21, R-22, R-23)

### Declarations (tester)

- `Sources/Connector/VaultPayloads.swift:296-305`: `PraticaTimelinePayload.Entry` gains
  `var anchorMessageID: String? = nil` and `var anchorState: String? = nil`. The two construction
  sites (`VaultPratiche.swift:220`, `:259`) compile unchanged.

### Red suite (tester)

`Tests/PraticheConnectorAnchorTests.swift`, over `TemporaryVault` and `VaultSession`, on the
fixture shape of `Tests/PraticheConnectorTests.swift`:

- An anchored entry follows its message with `anchorMessageID` and `anchorState == "anchored"`; an
  orphaned entry sits at its heading time with `"orphaned"`; a free entry's encoded JSON has
  neither key (R-22).
- An entry's `body` excludes the anchor line (R-01).
- At one instant, the message comes first (R-08).
- **Parity (R-21).** The same pratica through `PraticheController.readTimeline` plus
  `PraticaTimelineModel.ordered` and through `VaultPratiche.timeline` yields the same sequence of
  kind, date and subject.

### Coder

- `VaultPratiche.timeline` builds message rows (with `mail.messageID`, file name as `tieKey`) and
  entry rows from `PraticaManualEntries.parse`, orders them through `PraticaTimelineOrder.arrange`,
  and fills the two fields. `manualEntryRows` and `entryHeading` are deleted, and the doc comment at
  `:177` is rewritten.
- `Sources/CLI/Commands/PraticheCommands.swift:90-115`: under an anchored entry print
  `collegata al messaggio <Message-ID>`, under an orphaned one
  `il suo messaggio non è più in questa pratica (<Message-ID>)`.
- `Sources/MCPServer/ToolCatalogue.swift:213-231`: the `pratica` description adds one sentence
  naming `anchorMessageID` and `anchorState`.
- `scripts/mcp-smoke.py`: a new stage, `pratiche_anchors`, registered beside `pratiche` and
  `pratiche_links`. It writes its own folder with `PRATICA_NOTE`, `MESSAGE_NOTE`
  (`<abc@rossi-spa.it>`), one entry anchored to that id and one anchored to a missing id, and
  checks the order and both `anchorState` values over a read-only server (R-22). The shared
  fixtures and the existing stages' counts stay as they are.

## Task 5 — The carry on «Sposta in…»; Escludi, «Aggiungi anche a…» and «Rigenera» pinned (R-13, R-14, R-15, R-16, R-17, R-18, R-19)

### Declarations (tester)

- **`Sources/App/VaultController+Files.swift`:** `func hasUnsavedTab(showing relativePath: String)
  -> Bool`. Stub: `false`. `canOperate(on:)` is not rewired by the tester.
- **`Sources/Features/Pratiche/PraticaEntryCarry.swift`** (new, `@MainActor struct
  PraticaEntryCarry { let pratiche: PraticheController; let vault: VaultController }`):
  - `enum Phase: Equatable, Sendable { case willAppend(notePath: String), willRemove(notePath:
    String) }`;
  - `enum Preflight: Equatable { case nothingToCarry, carry(blocks: [String]), refused(String) }`;
  - `enum Outcome: Equatable, Sendable { case carried(count: Int), appendedOnly(count: Int,
    missing: Int), notCarried }`;
  - `func preflight(messageID: String, from source: String, to destination: String) -> Preflight`
    (stub: `.nothingToCarry`);
  - `func carry(_ blocks: [String], anchoredTo messageID: String, from source: String, to
    destination: String) async -> Outcome` (stub: `.notCarried`);
  - `func carryBack(_ outcome: Outcome, blocks: [String], anchoredTo messageID: String, source:
    String, destination: String) async` (stub: no-op);
  - `static func sentence(for outcome: Outcome, source: String, destination: String) -> String?`
    (stub: `nil`).
- **`Sources/Features/Pratiche/PraticheController.swift`:** `@ObservationIgnored var
  testOnlyCarryHook: (@MainActor (PraticaEntryCarry.Phase) async -> Void)?`.

### Red suite (tester)

`Tests/PraticaEntryCarryTests.swift`, two pratiche in one `TemporaryVault`, the source holding a
message with two anchored entries, an entry anchored to another message and a free entry:

- **R-14.** «Sposta in…» appends both blocks to the destination and removes them from the source.
  Every other body byte of both files is identical; frontmatter differs only in the dossier keys
  the verb already writes (interpretation 1). The destination's timeline shows them anchored.
  Undo puts them back in the source (at its end) and out of the destination; the message returns.
- **R-15.** With the hook writing the destination at `.willAppend`: the message moved, the source
  body is unchanged, the entries read as orphaned there, and the reported sentence names both
  files. With the hook writing the source at `.willRemove`: both files hold the blocks, and the
  sentence says so. No block is lost in either case.
- **R-18.** A dirty tab on the source, then on the destination: refused, nothing moved (the
  message file still in the source, both `pratica.md` byte-identical), the sentence reported. The
  source changed on disk after `reloadTimeline`: refused, and the timeline reloaded. A message with
  no anchored entry moves while `pratica.md` is dirty, exactly as today.
- **R-19.** A CRLF destination stays CRLF after the append; a CRLF source keeps CRLF after the
  removal.
- **R-13.** Escludi on the message: both entries' bytes unchanged, both read `.orphaned`; undo:
  `.anchored` again, the body unchanged.
- **R-16.** «Aggiungi anche a…»: both bodies unchanged; the destination shows the message with no
  entry under it.
- **R-17.** «Rigenera» (the `Tests/PraticaRegenerationTests.swift` harness): `pratica.md` bytes
  unchanged, entries still anchored.
- **`hasUnsavedTab`** answers per path and records no problem.

### Coder

- `canOperate(on:)` becomes `hasUnsavedTab(showing:)` plus its existing record; behaviour
  unchanged.
- The carry bodies (ADR-0076 §D6): the pre-flight reads the source through `session.read`,
  collects `PraticaEntryEdit.blocks`, and with any, checks `hasUnsavedTab` on both
  `PraticaNaming.praticaNotePath`s and the source hash against `timelineOrigin`. Each carry step is
  fresh read, `await testOnlyCarryHook?(phase)`, transform, `session.write(…, expecting:)`.
  Refusals and failures become outcomes, never thrown past the verb.
- `PraticaCommandActions.move` (`:247-278`): the pre-flight runs before `files.moveFiles`; a
  `.refused` reports and returns. After the two dossier writes, `carry` runs, and its sentence is
  reported. The undo closure captures the outcome, the blocks and both paths, runs today's undo
  body, then `carryBack`. The redo re-runs `move`.
- Escludi, `alsoAdd` and `confirmRegeneration` are not edited.

### Update tests and call-sites asserting the old behaviour

- `canOperate(on:)` callers keep their behaviour (`VaultController+Move.swift:172`,
  `PraticaEntryComposer.swift:60`, and the file verbs); their existing tests stay green unchanged.
- No existing test drives `PraticaCommandActions.move`; `Tests/PraticaFileOperationsSessionTests.swift`
  covers `moveFiles` alone and is not affected.

## Task 6 — The verbs: catalogues, anchored insert, anchor and unanchor, picker model (R-02, R-03, R-11, R-12, R-18)

Starts after G1, which fixes the catalogue order, titles and symbols.

### Declarations (tester)

- **`Sources/Features/Pratiche/MessageCommand.swift`:** cases `.addNote` («Aggiungi nota») and
  `.addCall` («Aggiungi telefonata») at the position G1 fixes, with their symbols;
  `carriesArgument` false; `available` offers them always.
  `static func accessibilityCommands(hasAttachments:hasLinkedNote:) -> [MessageCommand]`
  (stub: `[]`). `PraticaCommandActions.run(_:on:detail:)` gains `case .addNote, .addCall: break`.
- **`Sources/Features/Pratiche/PraticaEntryCommand.swift`** (new): `enum PraticaEntryCommand:
  String, CaseIterable, Sendable { case linkMessage, unlinkMessage }` with `title` («Collega a un
  messaggio…», «Scollega dal messaggio»), `symbol` (G1), `identifier`
  (`"pratiche-entry-command-\(rawValue)"`), `static func available(hasAnchor: Bool) -> [Self]`
  (stub: `allCases`).
- **`Sources/Features/Pratiche/PraticaCommandActions+Entries.swift`** (new):
  `commands(forEntry:) -> [PraticaEntryCommand]` (stub: `[]`),
  `run(_ command: PraticaEntryCommand, on entry: PraticaTimelineEntry)` (stub: no-op),
  `anchor(_ entry: PraticaTimelineEntry, to messageID: String) async` and
  `unanchor(_ entry: PraticaTimelineEntry) async` (stubs: no-op).
- **`Sources/Features/Pratiche/PraticaEntryComposer.swift`:**
  `insertAnchored(_ kind: PraticaEntry.Kind, on message: PraticaTimelineEntry, detail:
  PraticaRowDetail?) async` (stub: no-op).
- **`Sources/Features/Pratiche/PraticaMessagePickerModel.swift`** (new): `struct Row: Equatable,
  Identifiable { messageID, date, sender, subject, isCurrent }`,
  `static func rows(from timeline: [PraticaTimelineEntry], filter: String, currentAnchor: String?)
  -> [Row]` (stub: `[]`).
- **`Sources/Features/Pratiche/PraticheController.swift`:** `struct PraticaAnchorRequest:
  Identifiable { let entry: PraticaTimelineEntry }` and `var anchorRequest: PraticaAnchorRequest?`.

### Red suite (tester)

`Tests/PraticaEntryCommandTests.swift`:

- **R-02.** `.addNote` and `.addCall` are offered for every `hasAttachments`/`hasLinkedNote`
  combination, carry no argument, and appear in `accessibilityCommands`, which excludes `.moveTo`
  and `.alsoAddTo`. Availability does not depend on the row's position, so the last row gets them.
- **R-12.** `available(hasAnchor: false) == [.linkMessage]`; with an anchor, both.
- **R-03**, over `TemporaryVault` (the composer fixtures of
  `Tests/VaultWriteOrderingBatch3Tests.swift:172-240`): `insertAnchored` on a received message
  appends the heading at "now" with the message's counterpart, the anchor line and an empty body
  line, in one landed write; the daily note of today gains its line with the mirror on and none
  with it off; `jumpToLine` receives the body line; the entry reads back anchored.
- **R-11, R-12.** `anchor` writes the line on a free entry and replaces it on an anchored one;
  `unanchor` removes only the line. Frontmatter bytes and every other entry are unchanged.
- **R-18.** With `pratica.md` dirty in a tab, `anchor` and `unanchor` refuse with the sentence and
  leave the file byte-identical. With the file written on disk after `reloadTimeline`, they refuse,
  reload the timeline, and write nothing.
- **R-11.** `PraticaMessagePickerModel.rows` lists messages only, skips an empty Message-ID, filters
  on sender and subject case-insensitively, marks the current anchor, and keeps timeline order
  unless G1 fixed another.

### Coder

- `accessibilityCommands`, `available(hasAnchor:)`, `commands(forEntry:)` (from `entry.anchor`).
- `run(.addNote/.addCall)` builds `PraticaEntryComposer(pratiche:vault:navigation:)` and calls
  `insertAnchored`. `insertAnchored` and today's `insert(_:at:)` share one private write path taking
  the pratica, the timestamp, the counterpart and an optional anchor; the anchored one reads the
  message file (`detail.notePath`) for `PraticaEntry.counterpart(ofMessage:ownAddresses:)` with
  `Set(vault.settings.pratiche.ownAddresses)`, falling back to `counterpart(of:fallback:)`. An id
  `PraticaEntryAnchor.line(for:)` refuses is reported, nothing written.
- `anchor`/`unanchor` through one door (ADR-0076 §D5): `hasUnsavedTab`, `session.read`, the
  `timelineOrigin` check, the transform by `fileOrdinal`, `write(…, expecting:)`, `reload()`.
  `run(.linkMessage)` sets `pratiche.anchorRequest`.

### Update tests and call-sites asserting the old behaviour

- **`MessageCommand` grows from 8 to 10 (observable).** `Tests/PraticaCommandTests.swift:86`
  (`allCases.count == 8`) becomes 10: explain it in chat first. `:108-115` checks membership and
  stays green; extend `:117-125`'s "no other command carries an argument" list with the two new
  cases. Callers of `available(hasAttachments:hasLinkedNote:)`: `PraticaCommandActions.swift:52-57`
  and the test file only.
- Every `switch` over `MessageCommand` gains the two cases: `PraticaCommandActions.run`
  (`:165-181`), `title`, `symbol`, `carriesArgument`, `available`.

## Task 7 — The rows, the picker, the inspector and the editor concealment (R-01, R-02, R-05, R-09, R-10, R-11, R-20)

Starts after G1. Everything drawn matches the approved mockup (R-10); every colour and font is a
token, in light and dark (R-09). A token the mockup adds goes into the theme JSON for both themes
and into `ColorToken`.

### Declarations (tester)

- **`Sources/Features/Editor/MarkdownStyler.swift`:** `Span.messageAnchor`, joining every
  exhaustive switch (What reading the code added, item 8) with today-shaped arms: not emitted yet,
  spell-check suppressed, `.textTertiary` in `MarkdownAttributedText` and in `CardTextAttributes`.
  `CardTextView.swift` is not edited.
- **`Sources/Features/Editor/EditorDecorationDelegate.swift`:** `HiddenMarker.Kind.messageAnchor`,
  `isInline == false`, `stillSpells` arm answering `false`; `hiddenKind(for:)` maps the span to it.
- **`Sources/Features/Editor/MessageAnchorFragment.swift`** (new): `final class
  MessageAnchorFragment: NSTextLayoutFragment` with `nonisolated(unsafe) var markerColor: NSColor`,
  drawing nothing yet.

### Red suite (tester)

- `Tests/MarkdownStylerTests.swift`: the exact line yields one `.messageAnchor` span over the whole
  line, with surrounding whitespace too; a near miss yields none; `suppressesSpellCheck`.
- `Tests/MarkupHidingTests.swift`, a new suite beside `MarkupHidingRule` (`:928`), reusing its
  file-private `displayedParagraph` and `fragments` helpers: the line collapses into
  `collapsedFont` keeping its length; it lays out as a `MessageAnchorFragment`; a revealed paragraph
  is not substituted; the hook is inert with the setting off; a stale marker does not collapse
  prose (R-20).
- `Tests/MarkdownAttributedTextTests.swift:348-374`: `everySpanKind` gains `.messageAnchor`.

### Coder

- **Editor (R-20).** The styler emits the span through `PraticaEntryAnchor.messageID(inLine:)` with
  an early return, before the blockquote check; `stillSpellsAMessageAnchor` re-validates; the
  delegate vends `MessageAnchorFragment` beside the rule branch (`:415-425`) with its colour pushed
  in from a token; the fragment draws the marker G1 fixed.
- **Rows (R-02, R-05, R-09).** `PraticaTimelineView.row` aligns an anchored entry through
  `hostLane`, at the lane's width with the mockup's indent; `PraticaEntryRow` draws the anchored
  and orphaned states and the caption from `orphanCaption`, and gains `.accessibilityActions` from
  `commands(forEntry:)`; `PraticaMessageRow` gains `.accessibilityActions` from
  `accessibilityCommands`.
- **Menus.** `PraticaMenuItems.swift` gains `EntryMenuItems`; `PraticaTimelineView.menu(for:next:)`
  (`:177-185`) draws it for entry rows, above «Inserisci qui».
- **Picker (R-11).** `PraticaMessagePicker.swift` (new), shaped like `PraticaLinkPicker`, hosted by
  `PratichePane+Sheets.swift` on `pratiche.anchorRequest`; choosing calls `anchor(_:to:)`.
- **Inspector (R-01).** `PratichePane+Inspector.swift:104` renders
  `PraticaEntryEdit.removingAnchorLines(in:)` of the body.

### Update tests and call-sites asserting the old behaviour

- `Tests/MarkdownAttributedTextTests.swift:348-374` as above. No other test enumerates `Span` or
  `HiddenMarker.Kind`. `Tests/InlineSpanRevealFenceTests.swift:327` reads `CardTextView.swift`'s
  source and stays green only while that file is untouched.

## Task 8 — Verification and closing the record (R-22, R-23, R-24)

**Per PR, before merge:**

- **Full suite.** `PergamenumTests` with the pinned test command.
- **Connectors.** Build `perg` and `pergamenum-mcp`; run `scripts/mcp-smoke.py`, which must pass,
  the new stage included (R-22). Confirm no pratiche write tool appears in `tools/list`.
- **R-23.** `git diff origin/main -- .claude/protected-interfaces Sources/Core/Pratiche/Dossier.swift
  Sources/Index/IndexCache.swift` shows no change to a protected signature, `Dossier.render` or
  `schemaVersion`; `SharedSourcesPurityTests` green; no diff under a message-file writer.
- **Lint and GUI.** SwiftLint; `scripts/uitests.sh --status`, then `--affected` (advisory at merge
  per CLAUDE.md).
- **ADR checks.** `git fetch origin`, `scripts/check-adr-references.py`, and 0076 still free on
  every ref, branches about to merge included (`git log --all -- 'docs/adr/0076*'`, rule 1).

**PR 2 only, by hand (Stefano), on a Debug build over a throwaway vault:** «Aggiungi nota» on the
last message; anchor and unanchor an old entry through the picker; Escludi and undo; «Sposta in…»
and undo; the editor marker with «Nascondi markup» on and off; `perg pratica` on the same pratica.

**After each merge (a docs change):**

- After PR 1: flip ADR-0076 to `accepted`, naming PR 1's merge (ADR-0071's precedent: rule 2
  reports a `proposed` ADR on `main`).
- After PR 2: add PR 2's merge hash to the status line; add the ADR-0076 line to CLAUDE.md's chain
  decision index (R-24); file in `TODO.md` the two SPEC out-of-scope defects (the same-minute
  «Inserisci qui» collision and the entry-row click that does not jump); add the protected-interface
  entry if G2 was approved.

## Requirement coverage

| R | Tasks | R | Tasks | R | Tasks |
|---|---|---|---|---|---|
| R-01 | 2, 3, 4, 7 | R-09 | 7 | R-17 | 5 |
| R-02 | 6, 7 | R-10 | 1, 7 | R-18 | 5, 6 |
| R-03 | 2, 6 | R-11 | 2, 6, 7 | R-19 | 2, 5 |
| R-04 | 3 | R-12 | 2, 6 | R-20 | 7 |
| R-05 | 3, 7 | R-13 | 5 | R-21 | 3, 4 |
| R-06 | 3 | R-14 | 2, 5 | R-22 | 4, 8 |
| R-07 | 3 | R-15 | 5 | R-23 | 2, 4, 8 |
| R-08 | 3, 4 | R-16 | 5 | R-24 | 1, 8 |

R-10 and R-24 are `(no-test:)` criteria: Task 1 and Task 7 meet R-10 through the approved mockup,
Task 1 and Task 8 meet R-24 through the ADR, the ADR-0036 note and the CLAUDE.md line.

## Order and dependencies

**Order:** Task 1 (G0) → 2 → 3 → 4 → 5, which is PR 1. Then G1 → 6 → 7, which is PR 2. Task 8
closes each PR.

- Task 3 needs Task 2's parser; Task 4 needs Tasks 2-3; Task 5 needs Task 2's transforms and
  Task 3's `timelineOrigin`.
- Task 6 needs Task 5's `hasUnsavedTab` and G1; Task 7 needs Task 6's catalogues and G1.
- The mockup can be produced while PR 1 is built.

## Risks, dependencies and HITL gates

- **G0: this plan, ADR-0076 and the ten interpretations.** Blocks Task 2.
- **G1: mockup approval** (R-10). Blocks Tasks 6 and 7 only. It also settles the three near labels
  in one menu: «Collega nota…» (ADR-0049, a note linked to the message), «Aggiungi nota» (new) and,
  on entries, «Collega a un messaggio…».
  **Approved by Stefano on 2026-09-30, with no mockup file** (recorded in ADR-0076's Gates). Tasks
  6 and 7 are open. Where a task below says "G1 fixes", the implementation decides, following
  ADR-0076 and the existing Pratiche views, and Task 8's hand check on a Debug build reviews it.
- **G2: protected-interface entry** for `PraticaEntryAnchor.line(for:)` (ADR-0076 §D12).
  Recommended: approve, the argument that protects `PraticaNaming.messageFileName`. Not blocking.
- **Stefano's usual gates.** Commit, push and merge of each PR, and the edit to the accepted
  ADR-0036. No schema change and no file deletion: the duplicate parsers are removed as code inside
  existing files.
- **The equal-instant order flips in the app**, visibly, for a pratica holding a message and a
  manual entry in the same minute. It is the SPEC's decision; no test pinned the old order.
- **The carry writes two files one after the other.** A refusal between them leaves a declared
  duplicate or orphaned entries, never lost text (R-15). The undo is best-effort in the same way.
- **`canOperate(on:)` is shared** by batch move and every file verb. The extraction must keep its
  behaviour; the full suite covers its callers.
- **Stale-timeline refusals.** Anchoring after an external edit of `pratica.md` refuses once and
  reloads (ADR-0068 §D20 leaves external edits unobserved).
- **Two PRs and the ADR status.** 0076 reads `proposed` on `main` after PR 1 until the flip
  (Task 8).
- **Nothing to provision.** No API, account, port or environment variable.

## TEST-CMD

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield
