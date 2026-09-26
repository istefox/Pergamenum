# ADR-0065: Every on-disk format round-trips faithfully or is refused

- Status: **accepted**, 2026-09-26. Stefano approved all seven points of gate G1
  (`docs/plans/format-edge-hardening.md`, /workplan GATE 1/2), G1.1 to G1.7, with none refused.
  These are the points that go past the SPEC's letter, listed at the end of §Decision under «What
  G1 decides». G2 was approved the same day: `ConventionsTests.reordersTagsOnSave` is rewritten
  into two tests, not deleted. The implementation's departures are recorded under «Implementation
  notes».
- Date: 2026-09-26. Written **before** the implementation, against `43ca911` (`HEAD` =
  `origin/main`). The tree was clean apart from `SPEC.md` (`shasum` `5be9806`). Every file:line
  below was read from that tree today.
- **Numbering note.** Written as ADR-0064, when `0063` was the highest number under `docs/adr/`.
  Renumbered to 0065 before merge: PR #592 landed first and moved the duplicate external-deletion
  ADR from `0061` to `0064`.
- **Path note:** ADRs live at `docs/adr/NNNN-<slug>.md`, as ADR-0063's own path note recorded.
- **Why an ADR at all.** The SPEC mandates one (R-24). The chain also passes the significance test
  on its own terms:
  - hard to reverse: the frontmatter serializer changes from a canonical re-render to an edit in
    place, and every in-app write of an existing note goes through it;
  - surprising without context: a later reader will find a serializer that carries lines it never
    interprets, a content hash that skips three bytes, and a canvas codec that keeps array elements
    it cannot read, and will be tempted to "simplify" each of them;
  - a real trade-off: for each of those, the ROADMAP itself proposed a cheaper fix
    (§Alternatives).

  Three override conditions apply as well: an explicit no on how the codecs treat a duplicated key
  they own (§D2), the redefinition of a persisted value (§D4), and a proposed change to a protected
  constant (§D12).
- Source:
  - `SPEC.md` (Approved 2026-09-26);
  - issue **#568** (**`PG-254`**, Audit Fable chain 1);
  - `ROADMAP.md` §"Chain 1 — Format-edge hardening" (`:28-178`).
- **Extends:**
  - ADR-0054 §D4: two more reasons a reconciliation diverges (§D6);
  - ADR-0041 §D7 and the hash conventions of ADR-0043 §D5/§D8: one decode door and one definition of
    a note's content hash (§D4);
  - ADR-0036: the message file's date carries the sender's offset, which is what its own code comment
    always said (§D8);
  - ADR-0010 §D7 and ADR-0021: a board marker stops being a note link target (§D9).
- **Amends none. Reopens no SPEC §14 decision.** The SPEC's Decisions, Constraints and Test seams are
  registered as settled (§D0).
- **Protected interfaces:** no signature changes. One registry entry, `IndexCache.schemaVersion`, is
  proposed to move 4 → 5 (§D12, gate G1).
- **Principles.** Principle 1 (file over app) is what this chain protects. Principle 2 is untouched.
  Principle 5 holds: the closed frontmatter schema is not extended, because a line kept verbatim is
  never interpreted or authored by the app (SPEC Constraint 1).
- **GUI-test budget: zero** (SPEC Constraint 7). Everything is asserted in-process in
  `PergamenumTests`.

---

## Context

### The rule

The SPEC states it: what the app does not understand, it carries through untouched; where carrying
it through is impossible, it refuses visibly instead of guessing. So every byte of an on-disk file
the app writes back has one of three fates:

1. it is carried verbatim;
2. it is rewritten, because the app meant to change it;
3. the write or the open is refused, with a recorded problem.

This ADR removes the fourth fate, which today covers 16 distinct paths: dropped or altered without
a word.

### What "faithful" means for each format

- **Note (`.md`):** byte-identical outside the key or section the app changed. Line endings and a
  leading byte-order mark are bytes.
- **JSON Canvas (`.canvas`):** identical to the codec's canonical encoding of the same JSON value.
  `CanvasDocument.encoded()` re-encodes with sorted keys and pretty printing on purpose (ADR-0054's
  determinism, `JSONCanvas.swift:58-71`). So a file laid out by another tool never kept its layout
  after an in-app save, and it still will not. What must survive is every value.
- **Message document (a Pratiche message file):** render → parse → render is identical. The file is
  regenerated from Mail and compared (ADR-0036 §D21).
- **Mail input (MIME parts, headers, HTML bodies):** read only. Faithful means the decoded value is
  the one the sender meant. An input format has no serialize side, so R-23's "round-trips" applies
  to it as "decodes to the expected value".

### What was verified on `43ca911`

| # | Where | Verified |
|---|---|---|
| 1 | `Frontmatter.swift:148-157`, `:171-172` | a CRLF file's first line is `"---\r"`, and `.whitespaces` does not contain `\r`, so the file reads as `hasFrontmatterBlock: false`; `serialized()` then always emits a block (`FrontmatterSerializer.render(frontmatter) + body`), prepending `---\n---\n` to the whole file |
| 2 | `Frontmatter.swift:203-206` vs `render` | `unparsableTags` is read and never written |
| 3 | `Frontmatter.swift:183-186`, `:199-211`, `:220-224` | a colon-less line is skipped; `switch key` assigns, so the last duplicate of a schema key wins and the others vanish on write |
| 4 | `JSONCanvas.swift:52-53`, `:83-92`, `:192-193`, `:215-217` | reproduces as written |
| 5 | `CanvasReconciliation.swift:39-40`, `:63-64` | reproduces, but only through `WorkspaceController.reconcileAfterRefusal` (`WorkspaceController.swift:745`), past the `guard base != theirs` early return (`CanvasReconciliation.swift:34`) |
| 6 | `HTMLTextReducer.swift:197` | `finished()` reads `buffers[0]` alone |
| 7 | `MIMEDecoder.swift:290`, `EmailHeaders.swift:218` | both map ISO-8859-15 to `.isoLatin2` |
| 8 | `EmailHeaders.swift:148-166`, `:76`, `:182` | reproduces as written |
| 9 | `MIMEDecoder.swift:191-203` | reproduces as written |
| 10 | `MessageDocument.swift:216-223` vs `MessageDocument+Reading.swift:141-147` | reproduces; the ROADMAP's fix is wrong (§D8) |
| 11 | `MessageDocument.swift:231-236` | reproduces; the ROADMAP's reason is imprecise (§D8) |
| 12 | `TaskParser.swift:259-263` | reproduces as written |
| 13 | `MarkdownInline.swift:69`, `:78-99` | reproduces as written |
| 14 | `NoteExport.swift:19`, `Wikilink.swift:212` | reproduces, and a third copy was found: `RelatedLink.swift:73,97` («Collega») |
| 15 | `NoteRename.swift:30` | reproduces as written |
| 16 | `NoteStore+ReadSurface.swift:27-35`, `Transclusion.swift:52-61` | reproduces as written |
| 17 | resolvers | does not reproduce: Swift `String` equality and hashing already use canonical equivalence |

**Corrections to the ROADMAP**, each recorded here so that nobody re-applies the original:

- **Item 1 and the BOM.** The mechanism the ROADMAP describes holds only if the UTF-8 decode keeps
  the BOM. swift-foundation's `String(data:encoding:)` strips it (§D4). If Darwin's Foundation does
  the same, the defect is a different pair: a writer that passes `record.contentHash` refuses its
  own write, and a writer that passes a text hash writes and drops the BOM. Either way, §D4 fixes
  it.
- **Item 10.** Reversing the order of the replacements is not an inverse (§D8.1).
- **Item 11.** Daylight saving time alone does not change a stored value. A change of the machine's
  zone does (§D8.3).

**Found while verifying**, and folded in under the SPEC's own default where the SPEC covers them:

- A `nodes` array with one element that is not an object drops **every** node, because the whole
  cast `as? [[String: Any]]` fails (`JSONCanvas.swift:52`). The first save then writes an empty
  board (§D5.4).
- An edge's `fromSide`/`toSide`/`fromEnd`/`toEnd` with an unrecognised value, and a non-string
  `color` or `label`, are dropped (`JSONCanvas.swift:277-282`). See §D5.3 and G1.
- `TagRename` skips every CRLF note (`TagRename.swift:19-21`, `:168-169`). See §D3 and G1.
- `pergamenum-mail-received` depends on the machine's zone too (`MessageDocument.swift:143`). See
  §D8.4 and G1.
- The index cache would keep stale values for every note these parsers now read differently (§D12,
  G1).

### The message-file rename assumption (SPEC edge case): it holds

`PraticaSyncEngine+Messages.swift:521-535` reuses `existing.fileName` whenever a file in the pratica
already carries the message's Message-ID (`folder.messagesByID`).
`PraticaNaming.uniqueMessageFileName` runs only when no file does. The sync's other file operations
never rename a message file:

- the corrupt-attachment trash in `allegati/` (`PraticaSyncEngine+Folder.swift:84`);
- «Rigenera», which trashes and then restores or rewrites at the same path (`PraticaLiveSync.swift`,
  around `:409`).

One nuance is not a rename. A message whose file was deleted, or whose file no longer parses as a
message document, is written as a new file under a name built from today's decoding.

---

## Decision

### §D0 — The SPEC's decisions are registered, not reopened

All of them stand as the SPEC records them:

- one SPEC and one ADR;
- CRLF and BOM preserved;
- opaque-first by default;
- duplicate canvas ids open normally and diverge on reconciliation;
- the sender's offset for `pergamenum-mail-date`;
- Latin-9;
- RFC 2047 §6.2 and RFC 2231;
- rename by resolved title;
- `.canvas` is never a note link target;
- item 17 is test-only;
- the advisory lint rule;
- the in-code corpus.

This ADR decides only what the SPEC left to `/workplan`: how the preserved lines are modelled, the
duplicate-key write, and the shape of each fix.

### §D1 — Frontmatter keeps the lines it read and edits them in place (R-01, R-03, R-04, R-05)

1. **Model.** `NoteDocument` gains `source: FrontmatterSource?`. It is `nil` for a document built in
   code, and every parsed document has one. A `FrontmatterSource` holds:
   - the raw opening delimiter line;
   - the block's lines in order, each an entry. `.key(name, rawLines)` is a key line with its
     continuation lines. `.opaque(rawLine)` is any line the parser does not read as a key: a blank
     line, a column-0 YAML comment, a colon-less line, or an indented or dash line with no key
     above it;
   - the raw closing delimiter, and whether a line break followed it;
   - the text's line break (§D3);
   - the values the parse produced (`parsed: Frontmatter`), to tell a changed key from an unchanged
     one.
2. **Interpretation and emission.**
   - Each line is interpreted with one trailing `\r` removed. On the first line, one leading U+FEFF
     is removed too (§D4.4).
   - Each line is emitted exactly as it was read.
   - `Frontmatter.ForeignKey.lines` holds the interpreted lines, so no codec ever sees a `\r`.
3. **Serialize.**
   1. A schema key whose value equals `parsed` is emitted verbatim: every occurrence, in place.
   2. A changed schema key re-renders only its governing occurrence (§D2), in place, in the
      canonical form of that key. For `tags` that form is the valid tags in `TagRules.ordered` order,
      then the unparsable ones verbatim.
   3. A schema key that was absent and is now present is placed in canonical form. It goes after the
      nearest schema key that precedes it in the canonical order (`date`, `tags`, `related`,
      `aliases`) and is present. If none is present, it goes before the block's first key entry.
   4. An emptied schema key is omitted (F-08). A duplicated one follows §D2 instead.
   5. Foreign keys follow §D2's name-and-ordinal match.
   6. Opaque entries are emitted verbatim, in place.
   7. Every line the app writes ends in the document's line break (§D3).
   8. A document that had no block, and has nothing to write, gets no block. A document that had no
      block and gains a key gets exactly one, at the top. If the text starts with U+FEFF, the block
      goes after it.
   9. A closing delimiter with no line break after it gains none.
4. **`body` stays the verbatim tail** after the closing delimiter's line break, and nothing
   normalises it. `NoteOutline` and `Transclusion` compute the body's start as
   `text.index(text.endIndex, offsetBy: -document.body.count)`, which is only correct when `body` is
   an exact suffix. It is: a body starts right after a `\n`, which always ends a grapheme.
5. **A fresh render stays canonical.** `FrontmatterSerializer.render` is used for new notes, daily
   notes, time blocks, tasks and message files. It gains two things:
   - `unparsableTags`, written after the valid tags (R-03);
   - a line-break parameter that defaults to LF.
6. **Observable contract change.** An unchanged `tags` key keeps its source order and form, so an
   inline list stays inline. `ConventionsTests.reordersTagsOnSave` (`ConventionsTests.swift:199`)
   pins the opposite and is **rewritten, not deleted** (gate G2): the canonical order still applies
   whenever the app writes the tags key. The existing `inlineTagList` finding still reports the
   inline form.
7. **R-03's "after the valid tags"** applies when the app writes the tags key. An untouched tags key
   is byte-identical instead (R-05's rule), so an unparsable tag stays where the person put it.
   Neither case ever drops it.
8. **One writer bypassed `NoteDocument`.** `TranscriptNote.render` (`TranscriptNote.swift:90`)
   renders `FrontmatterSerializer.render(mergedFrontmatter(...))` for an existing note, which would
   drop a person's comment on every Plaud re-import. When the note exists with a block, it now goes
   through `NoteDocument.serialized()`.

### §D2 — A duplicated key: one occurrence governs and the others are kept (settles the SPEC's «Not yet specified»)

This stays inside the SPEC's default: every occurrence the write did not mean to change is kept.

**Schema keys (`date`, `tags`, `related`, `aliases`).**

- The reader already decides which occurrence is the value: the last one, because
  `FrontmatterParser.parse` assigns per key (`Frontmatter.swift:199-211`). That occurrence governs
  the write, so a write reads back as what the app wrote.
- A write that changes the value rewrites the governing occurrence in place. Every other occurrence
  is emitted byte-identical, where it was.
- A write that empties a duplicated key writes the governing occurrence as the bare key
  (`related:`), which `FrontmatterParser` reads as empty (`Frontmatter.swift:250-259`).
  - If the occurrence were omitted instead, an earlier one would become the value on the next read,
    and the removal would silently not happen.
  - The bare key goes against F-08's "omit an empty key", but only inside a block that R-22 already
    reports as damaged.
- A write that does not touch the key leaves every occurrence byte-identical (R-05).
- Nothing is merged and nothing is refused.

**Foreign keys.**

- The serializer does not decide. It writes exactly the entries the owning codec returns, matched to
  the file by name and ordinal. The k-th entry named N in the codec's list takes the place of the
  k-th occurrence of N in the file:
  - verbatim when its lines are unchanged;
  - replaced in place when they changed.

  An occurrence with no k-th counterpart is removed. An entry with no counterpart in the file is
  appended at the end of the block, in list order.
- So each codec's recorded rule decides its own keys, and every key no codec owns passes through
  verbatim:
  - `pergamenum-category`: one slug per note (ADR-0047).
    - `linkCategory` keeps filtering every occurrence and appending one.
    - The ordinal match puts the new value where the first occurrence was, and later duplicates go.
    - Only the category line changes.
  - `pergamenum-dossier-*` and `pergamenum-dossier-links-*`: `Dossier.merging`
    (`Dossier.swift:121-145`) and `PraticaLinks.merging` (`PraticaLinks.swift:101-120`) replace the
    first occurrence of an owned key and drop its later duplicates.
- **Explicit no:** the codecs are not changed to preserve a duplicate of a key they own.
  - Such a key already has one meaning: the occurrence its codec reads, which is the first one
    (`DossierYAML.index(of:)`, `CategoryFrontmatter.slug`).
  - A second copy is exactly the stale data R-22 now reports.
  - `pratica.md` has one editor, the inspector (ADR-0036).

The SPEC's own example is a category change on a note whose `tags:` appears twice. It writes
`pergamenum-category` only (`VaultSession+Categories.swift:138-142`), and both `tags:` blocks stay
byte-identical. That is R-05, not the open case.

### §D3 — Line endings are kept per line, and a new line takes the document's (R-01)

- **Detection.** The document's line break is the text's first line break: CRLF if it is `\r\n`,
  LF otherwise, and LF for a text that has none.
- **Existing lines keep their own ending.** A mixed file stays mixed, byte-identical.
- **A line the app writes ends in the document's line break.** This covers:
  - a re-rendered key;
  - a new key;
  - the delimiters of a new block;
  - a «Collega» bullet or heading (§D9.3).
- **`NoteDocument.parse` keeps `components(separatedBy: "\n")`** (`Frontmatter.swift:148`).
  - Foundation splits below the grapheme level, so a CRLF line arrives with its `\r` attached.
  - Swift's `Character`-level API does not. `split(separator: "\n")`, `firstIndex(of: "\n")` and
    `Character == "\n"` never see the LF of a CRLF pair, because `"\r\n"` is one `Character`.
  - No new line walk in this chain may use them (§D9.3).
- **`TagRename` (G1).** It decides "is there a block" with the same whitespace-only test
  (`TagRename.swift:19-21`, `:168-169`), so a vault-wide tag rename silently skips every CRLF note.
  The fix:
  - the delimiter test tolerates one trailing `\r`;
  - inserted lines end in the document's line break.

  The other two copies of the test are named in §D13.

### §D4 — The byte-order mark belongs to the file, and is handled at the store's byte boundary (R-02)

**What was found.**

- `NoteStore` decodes with `String(data:encoding: .utf8)` at three sites: `NoteStore.swift:100` and
  `NoteStore+ReadSurface.swift:16,44`.
- swift-foundation's implementation of that initializer strips a leading `EF BB BF` in its UTF-8
  branch (`Sources/FoundationEssentials/String/String+IO.swift`, read on 2026-09-26). Whether the
  Foundation that ships with macOS 27 does the same was not executed here.

Today is broken either way.

- **If the decode strips the BOM:**
  - `record.contentHash` hashes the raw bytes (`NoteStore.swift:130`);
  - `VaultDisk.write` compares `expecting` with a hash of the decoded text (`VaultDisk.swift:227-230`).

  So every writer that passes `record.contentHash` refuses its own write on a BOM note. There are
  twenty-one such sites (`rg -n 'contentHash' Sources`, counting only the values handed to a write
  as its expected hash), among them «Collega» (`VaultSession+Notes.swift:255,261`),
  `DossierWriter.swift:37` and `PraticaCommandActions.swift:374`.

  Every writer that passes a text hash writes, and drops the BOM. Examples are
  `VaultSession+Categories.swift:142`, `PraticaSyncEngine+Folder.swift:153` and
  `DiaryController.swift:255`.
- **If the decode keeps it:** the text starts with U+FEFF, the delimiter test fails, and the next
  serialize prepends a block. This is the ROADMAP's mechanism.

**Decision.** The BOM belongs to the file, not to the text.

1. **One decode door.** `NoteStore.decodedText(_ data: Data) -> String?` removes one leading
   `EF BB BF`, then decodes. The three `NoteStore` sites and the journal's `textBefore`
   (`VaultSession+Journal.swift:172`) use it. The text the app works on never starts with a BOM read
   from a vault note, whatever the platform does.
2. **One content hash.** `NoteStore.hash` becomes SHA-256 over the bytes after one leading
   `EF BB BF`, if there is one.
   - For every file without a BOM the value is unchanged, so every hash already persisted for such a
     file stays valid.
   - For a BOM file, the raw-bytes hash and the text hash become the same value. Every comparison
     already assumed they were equal:
     - `VaultDisk.write` and `writeFile` (`:227-230`, `:323-326`, `:356-359`);
     - `CanvasStore` (`:62`, `:86`, `:110`);
     - the journal (`VaultSession+Journal.swift:170`, `:241`, `:378`);
     - `VaultFileChange.expectedHash`;
     - the self-write hash precomputed at `VaultSession.swift:596`.
3. **The write keeps the file's BOM.** `NoteStore.write` prepends `EF BB BF` when the file it
   replaces starts with those bytes and the new bytes do not. A file that did not exist, or had no
   BOM, never gains one.
4. **A U+FEFF that arrives in text from another door is still carried.** Examples are a direct
   `String(contentsOf:)` read in `Sources/Features/Pratiche` and a connector argument.
   - `NoteDocument` interprets the first line without it and emits the line with it.
   - A new block goes after it.
   - Written back through the store, such a text does not get a second BOM, because rule 3 tests the
     new bytes.

**Result.**

- R-02 holds whatever the platform decode does.
- `VaultSession.reconcile` still recognises the app's own write to a BOM note, because under rule 2
  the precomputed hash and the file's hash agree.
- Nothing that reads line 0 of a note has to learn about U+FEFF. That covers `TaskParser`,
  `NoteOutline`, `MarkdownStyler.frontmatterRange`, `ViewCatalogue` and `TagRename`.
- A characterization test records which decode behaviour this OS has. It is kept for the record;
  §D4 does not depend on its answer.
- **Departure from the SPEC's data-model wording, not from its requirement.** The document carries
  "BOM presence" only when its text does. Otherwise the file carries it.

### §D5 — JSON Canvas carries what it cannot read (R-06, R-07, R-08)

1. **Consumption per kind (R-06).**
   - Every node consumes the common keys: `id`, `type`, `x`, `y`, `width`, `height` and `color`.
   - Each kind also consumes its own payload: `text` for text, `file` and `subpath` for file, `url`
     for link, `label` for group.
   - An `.unknown` kind consumes no payload key.
   - Everything else stays in `unknown` and is written back.

   Today one global set (`JSONCanvas.swift:192-193`) filters `url` out of an `embed` node, and
   `rawValue` writes nothing for `.unknown` (`:215-217`).
2. **Colour (R-07).**
   - `CanvasColor` gains `case unrecognised(String)`. Nodes and edges read a string value as
     `CanvasColor(raw) ?? .unrecognised(raw)`, and `rawValue` returns the string.
   - `CanvasColor.init?` stays failable, so `CardTextStyle.read` keeps "malformed reads as nil" for
     its own key.
   - `isNote` stays `color != nil`, so a card with an unrecognised colour is still a Nota, as the
     SPEC's data model requires.
   - Exhaustive switches:
     - `CardTextStyle.rgba(for:)` (`CardTextStyle.swift:73`) answers `nil`, meaning no tint;
     - `StickyTextCard.stickyColor` (`StickyTextCard.swift:128`) answers the neutral token it already
       uses for a preset outside 1-6.
3. **An optional key is consumed only when it is understood (G1).** It is left in `unknown`,
   untouched, in these cases:
   - an edge's `fromSide`, `toSide`, `fromEnd` or `toEnd` whose string is not a known value;
   - a non-string `label`;
   - a non-string `color`.

   This is rule 2 applied where the SPEC's list of examples stops. The alternative is the silent drop
   this chain exists to remove. Required keys with a wrong JSON type are named in §D13.
4. **Opaque elements (R-08).**
   - An element of `nodes` or `edges` that the codec cannot read is kept. That means:
     - an object without `id` or `type` (nodes);
     - an object without `id`, `fromNode` or `toNode` (edges);
     - anything that is not an object.
   - It goes into `CanvasDocument.opaqueNodes` / `opaqueEdges`, as a `JSONValue` with its original
     index.
   - On encode it is re-inserted at that index, in ascending order, clamped to the array's end.
   - The parse iterates `as? [Any]`, so one bad element no longer empties the board (§Context).
5. **`nodes` or `edges` present and not an array: refused at open (G1).**
   - A new `DecodingError.notAList(String)` refuses the open.
   - Such a file cannot be written back consistently, because `encoded()` always writes an array.
   - The existing load path already records the thrown error as a problem
     (`WorkspaceController.swift:311-312`).
   - An absent key still reads as empty. JSON Canvas makes both keys optional.
6. **Duplicate ids open and edit normally** (SPEC decision, registered). Nothing at decode checks
   uniqueness.

### §D6 — A reconciliation diverges on duplicate ids and on opaque elements (R-09)

1. **Duplicate ids.**
   - Before building any id-keyed dictionary, `reconcile(mine:base:theirs:)` checks `mine`, `base`
     and `theirs` for a node or edge id that appears more than once.
   - If it finds one, it answers `.diverged`, naming each duplicated id once.
   - The caller's existing path does the rest. `reconcileAfterRefusal`
     (`WorkspaceController.swift:745`) calls `enterConflicted(reason:)` (`:778`), which sets
     `.conflicted` and records exactly one problem. ADR-0054's «Mantieni le mie modifiche» and
     «Ricarica dal disco» resolve it.
2. **The early return stays first.** When `base == theirs`, a refusal caused only by a re-encoding
   difference still adopts `mine`, with or without duplicates.
3. **Opaque elements join the comparison.**
   - When `base.opaqueNodes != theirs.opaqueNodes` (or the edge lists differ), the reconciliation
     diverges, with a reason naming the element's index.
   - Without this rule, §D5.4 would create a new silent loss: `mine` carries `base`'s opaque
     elements, so an external change to one of them would be overwritten by the adopted document.
4. **Rejected:** the ROADMAP's `Dictionary(_:uniquingKeysWith:)`. It removes the trap by keeping one
   of two nodes, which is a merge decided by a guess.

This extends ADR-0054 §D4 with two more reasons it cannot speak for, and amends nothing in it.

### §D7 — Mail decoding (R-10, R-11, R-12, R-13)

1. **HTML (R-10).** `HTMLTextReducer.finished()` (`HTMLTextReducer.swift:197`) folds every pending
   buffer back into its parent, innermost first, the way the matching close would, and only then
   reads `buffers[0]`. Text after an unclosed `<a>` or `<td>` is kept, in order.
2. **Charset (R-11).**
   - One table replaces the two private ones: `MailCharset.encoding(for:)`, in the new file
     `Sources/Core/Email/MailCharset.swift`. The two it replaces are `MIMEDecoder.stringEncoding(for:)`
     (`MIMEDecoder.swift:~285-295`) and `EncodedWord.stringEncoding(for:)`
     (`EmailHeaders.swift:215-224`).
   - The new table is the union of both, so neither decoder loses an alias.
   - `ISO-8859-15`, `ISO_8859-15` and `LATIN9` decode as Latin-9, through Core Foundation:
     `String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.isoLatin9.rawValue)))`.
   - Core Foundation comes with `import Foundation` on this platform, so `Sources/Core` stays
     buildable in both tools.
3. **RFC 2047 (R-12).**
   - `EncodedWord.decode` (`EmailHeaders.swift:148`) drops the linear whitespace between two
     encoded-words only when both decode (§6.2).
   - Whitespace next to plain text stays. So does whitespace next to a word that fails and is shown
     raw.
   - A B-word's padding is normalised before decoding: every `=` is removed, the payload is
     re-padded to a multiple of four, and it is decoded with `.ignoreUnknownCharacters`.
   - The header unfold (`EmailHeaders.swift:76`, `" " + trimmed`) stays as it is. Once §6.2 is
     honoured, the space it inserts between two encoded-words is exactly the whitespace that gets
     dropped.
4. **Parameters (R-13).** A small parser, `MIMEParameter.value(_ name: String, in raw: String) ->
   String?`, lives in the new file `Sources/Core/Email/MIMEParameter.swift`. It replaces the private
   `parameter(_:of:)` (`MIMEDecoder.swift:191-203`) at all four call sites (`:42`, `:72`, `:73`,
   `:101`). It:
   - splits on `;` outside double quotes;
   - unquotes, honouring backslash escapes;
   - honours RFC 2231 `name*=charset'lang'%XX`;
   - joins the continuations `name*0`, `name*1`, `name*0*`, … in numeric order, with the charset
     taken from the first segment and resolved through §D7.2's table.

   When `filename` and `filename*` are both present, the extended form wins.

**Consequence.** New message files get names built from correctly decoded subjects. Existing ones
are never renamed (§Context).

### §D8 — The message document (R-14, R-15)

1. **Escaping (R-14).** `unquoted` (`MessageDocument+Reading.swift:141-147`) becomes a single
   left-to-right scan. It decodes `\\`, `\"` and `\n` as pairs and leaves any other backslash as it
   is. That makes it the exact inverse of `quoted()` (`MessageDocument.swift:216-223`).

   The ROADMAP's fix, reversing the order of the replacements, is not an inverse:
   - `C:\nuovo` is written as `C:\\nuovo`;
   - replacing `\\` first gives back `C:\nuovo`;
   - replacing `\n` next still produces a line break.
2. **Mail date (R-15, SPEC decision, registered).**
   - `EmailHeaders` gains `dateOffset: Int?`, in seconds east of UTC. `EmailHeaderParser.parse` sets
     it from the raw `Date` field through `RFC5322Date.offset(of:) -> Int?`, which maps:
     - `±hhmm` to its value;
     - `UT`, `GMT` and `Z` to 0;
     - `EST`, `EDT`, `CST`, `CDT`, `MST`, `MDT`, `PST` and `PDT` to their RFC 5322 §4.3 values;
     - `-0000`, military letters and any other name to `nil`.

     `EmailHeaders.==`, which is hand-written (`EmailHeaders.swift:20-25`), compares the new field.
   - `MailFrontmatter` gains `dateOffset: Int?`, defaulted to `nil` so every memberwise call keeps
     compiling.
   - The sync passes the offset only when the date came from the header
     (`PraticaSyncEngine+Messages.swift:360`, where `headers.date` is the first choice). An Envelope
     Index fallback passes `nil`. So does a zero offset, so that a regenerated document compares
     equal to its parsed copy.
   - `isoString` formats with `TimeZone(secondsFromGMT:)`, or in UTC (`Z`) for `nil`.
   - `MessageDocument.parse` reads the offset back from the stored value, with `Z` giving `nil`, so
     render → parse → render stays identical.
3. **The ROADMAP's reason is corrected; the SPEC's decision stands.** `ISO8601DateFormatter` with
   `timeZone = .current` formats an instant with the offset in force at that instant. So a DST
   change alone does not change a stored value. What does change it is the machine's zone: a second
   Mac, travel, or a CI runner in UTC. This reasoning was not executed here. The R-15 test pins the
   outcome that matters: a `+0900` header gives `+09:00` on any machine.
4. **`pergamenum-mail-received` is written in UTC (G1).** It has the same machine dependence
   (`MessageDocument.swift:143`), and no sender zone to use, because the Envelope Index stores an
   epoch.
5. **Existing message files** show a one-time diff on these values at their next regeneration: a
   «Rigenera», or a pending body arriving (SPEC edge case). No sync rewrites a message file for any
   other reason (ADR-0036).

   The file name's date and time come from `PraticaNaming.uniqueMessageFileName(date:time:…)`
   (`PraticaSyncEngine+Messages.swift:525-534`). They are fixed at creation, in the machine's zone,
   and not touched here. A future reader should not expect them to match the stored offset.

### §D9 — Task text, inline markdown, related section, rename and link targets (R-16 to R-20)

1. **R-16.** `TaskParser.displayText` (`TaskParser.swift:259-263`) removes each tag by the range the
   tag scan already found (`:235-250`), working from the end backwards. No string replacement is
   left.
2. **R-17.**
   - `MarkdownSpan.Link` gains `case embed(target: String)`.
   - `MarkdownInlineParser` recognises `![[` before the wikilink and link fallbacks
     (`MarkdownInline.swift:69`).
   - The span's text is the reference: the part before `|`, so a size suffix never shows.
   - `MarkdownBlocksView` has the only exhaustive switch (`MarkdownBlocksView.swift:245`). It renders
     the embed the way it renders `.note`, as a link with no `!`.
   - `NoteOutline.plainText` (`NoteOutline.swift:93`) joins span text and needs no change.
3. **R-18.**
   - One locator, `RelatedSection.sectionRange(in:)`, is added to `Wikilink.swift`.
   - The heading is a line that is exactly `## Note correlate` once one trailing `\r` and any
     trailing spaces or tabs are removed.
   - The section runs to the start of the next line beginning with `#`, or to the end of the body.
   - The locator walks lines below the grapheme level (§D3).
   - It is used by:
     - `RelatedSection.parse` (`Wikilink.swift:212`, the linter);
     - `NoteExport.strippingRelatedSection` (`NoteExport.swift:19`);
     - `RelatedLink.addBullet` and `removeBullet` (`RelatedLink.swift:73,97`, «Collega»), under G1.
       Without them, the linter would say there is no section while «Collega» writes its bullets
       under `### Note correlate operative`.
   - «Collega» writes its bullets and any new heading in the document's line break (§D3, R-01).
4. **R-19.**
   - `NoteRename.rewritingLinks` matches on `fold(link.resolvedTitle)` (`NoteRename.swift:30`).
   - It rewrites the title inside the marker pair that `resolvedTitle` stripped, through a `Wikilink`
     helper: `[[**Forno tunnel**]]` becomes `[[**Nuovo nome**]]`.
   - The section and the alias are untouched.
   - The count `NoteFileOperations.renamePlan` reports (`rewrittenPaths`) then includes the file.
5. **R-20.**
   - `NoteStore.linkTargets(in:)` (`NoteStore+ReadSurface.swift:27-35`) excludes every target whose
     extension is `canvas`, embed or not. As a result:
     - a board stops being a backlink target, an unresolved link, a graph neighbour, and a `links`
       value in a `pergamenum-view` query;
     - a note whose only link is a board marker becomes an orphan, which is what it is in the note
       graph.
   - `Transclusion.isNoteReference` (`Transclusion.swift:52-61`) decides by two named sets:
     - `noteExtensions` (`md`) answers true;
     - `fileExtensions` answers false. It holds the attachment types the app renders or previews,
       plus `canvas`.
   - An extension in neither set falls back to today's shape rule, so an attachment with an unlisted
     short extension does not become a phantom note. The `else { return true }` for any extension
     longer than five characters is what made `Q4.canvas` a note. Every extension the app knows is
     now decided by name. The fallback is kept, deliberately, only for the long tail.

### §D10 — Unicode normalisation is pinned, not changed (R-21)

Swift `String` equality and hashing use canonical equivalence (SPEC, verified 2026-09-26). A
regression test pins NFD equal to NFC in:

- `WorkspaceBoardResolver` (`:36-38`, `:46-48`);
- `NoteRename.fold` (`:72-74`);
- `Transclusion.normalised` (`:177-179`).

No code changes. The test exists so that a later change to a byte or `NSString` comparison is
caught.

### §D11 — Frontmatter damage becomes an advisory lint finding (R-22)

- `FrontmatterViolation` gains three cases. `FrontmatterRules.validate` produces them from the
  document's source, and only when the note has a block:
  - `secondFrontmatterBlock`. All three conditions hold:
    - the body's first line is `---` once one leading U+FEFF and one trailing `\r` are removed;
    - a later body line is `---`;
    - at least one line between them reads as a key.

    This is the prepend defect's trace: an empty block, then the original one.
  - `duplicateKey(name)`: one finding per key name, schema or foreign, that appears more than once.
  - `lineWithoutColon(line)`: one finding per non-blank opaque line that has no colon. Blank lines
    are not reported.
- `ConformanceText.frontmatterLines` (`ConformanceText.swift:36`) gains three Italian lines.
- **The `VaultAPI.LintFinding` shape does not change.** Its `frontmatter` field is
  `violations.frontmatter.map { "\($0)" }` (`VaultPayloads.swift:145`). The new values are the
  strings `secondFrontmatterBlock`, `duplicateKey("tags")` and `lineWithoutColon("…")`, inside the
  existing array.
- **Advisory.** Blocking reads only `.tags` violations (`VaultSession+TaskDrop.swift:66-72`,
  `VaultSession+BoardDrop.swift:58-59`). Tag entry reads `TagRules`. Nothing reads the new cases.

### §D12 — The index cache schema moves 4 → 5 (G1)

- The scanner reuses a cached record when a file's size and modification date are unchanged
  (`VaultScanner.swift:96-102`). `StoredFrontmatter` persists date, tags, aliases and related.
- After this chain, a reused record would keep:
  - an empty frontmatter for every CRLF note, and for every BOM note on a platform that keeps U+FEFF,
    so their tags, date and category would be missing from every view until the file changed;
  - `.canvas` link targets (§D9.5).
- The persisted `contentHash` of a BOM note would keep the old definition too. No writer reads it
  from the index: writers read fresh through `VaultSession.read` (`VaultSession.swift:246-247`). So
  this alone would not justify a bump.
- **Decision (G1):** `IndexCache.schemaVersion` goes from 4 to 5. The first launch then rebuilds the
  cache from a full scan. Principle 3 holds: the cache is rebuildable and nothing is lost. The
  precedent is ADR-0047 §D5 (3 → 4).
- The registry protects this constant (`.claude/protected-interfaces`), and the SPEC's constraint
  list does not name it. So it is Stefano's call, not the plan's.
- **Alternative if refused:** no bump. Stale records stay until each file changes or «Svuota cache»
  is used, and the release notes say so.

### §D13 — Named here and not fixed

Each item is out of the SPEC's scope and is filed as a follow-up:

1. **CRLF line walks at the `Character` level.** The editor styler's line ranges
   (`MarkdownStyler`), `NoteOutline`'s line ranges and `NoteExport`'s other line walks search for a
   `"\n"` `Character`, so they treat a CRLF note as one line. Headings, the outline and the export
   come out wrong. The file is never damaged by it.
2. `DossierYAML` writes keywords without escaping `"` or a line break.
3. `MessageFrontmatterPatch.swift:24-26` (app-written files) and `ViewCatalogue.swift:78,83` keep the
   whitespace-only delimiter test.
4. A canvas's required keys with a wrong JSON type (`"x": "12"`, `"text": 42`) are replaced by their
   defaults (`JSONCanvas.swift:171-189`).
5. A `## Note correlate` line inside a fenced code block is still taken as the heading.
6. `JSONValue` holds numbers as `Double`, so an integer beyond 2^53 loses precision. This is
   pre-existing.
7. A `.canvas` file that starts with a BOM was not examined.

### What G1 decides

| # | Point | Recommendation |
|---|---|---|
| G1.1 | §D12, `IndexCache.schemaVersion` 4 → 5 (protected constant) | approve |
| G1.2 | §D4.2, the content-hash definition skips one leading BOM (a persisted value is redefined; R-02 needs it) | approve |
| G1.3 | §D3, `TagRename` tolerates CRLF | approve |
| G1.4 | §D9.3, «Collega» uses the anchored locator | approve |
| G1.5 | §D8.4, `pergamenum-mail-received` is written in UTC | approve |
| G1.6 | §D5.5, a non-array `nodes`/`edges` is refused at open | approve |
| G1.7 | §D5.3, an optional canvas key is consumed only when understood | approve |

A refusal of any point leaves the rest standing. The plan records a refused point as a named gap,
rather than claiming it holds.

---

## Alternatives considered

### §D1: canonical re-render with carry-through lists

The ROADMAP's items 2 and 3 fix two symptoms: re-emit `unparsableTags`, and re-emit a list of
unknown lines. **Rejected.**

- The fix cannot meet R-01's "every other byte untouched", because a canonical render:
  - re-sorts tags;
  - rewrites `related` quoting;
  - turns an inline tag list into a block;
  - moves foreign keys after the schema keys;
  - writes LF.

  Each of those is an unasked diff on every write of a note that another tool wrote.
- The chosen model costs two things:
  - a second representation of the block that must agree with the parsed values;
  - the tags-order contract change (§D1.6).

### §D1: where the source lives

On `Frontmatter` rather than on `NoteDocument`. **Rejected.**

- It would travel into every `NoteRecord` the index holds.
- It would make `Frontmatter ==` sensitive to formatting.
- Its only saving is the one-line `TranscriptNote` change (§D1.8).

### §D4: the text carries the BOM as U+FEFF

**Rejected.**

- Every reader of line 0 would have to learn it: `TaskParser`, `NoteOutline`,
  `MarkdownStyler.frontmatterRange`, `ViewCatalogue` and `TagRename`.
- The editor would hold an invisible character at offset 0, which a person can delete or type in
  front of.
- The outcome would still depend on whether the platform decode keeps the BOM.

Normalising the BOM away was rejected by the SPEC.

### §D2: a duplicated key that a write empties

- **Omit only the governing occurrence:** rejected. The earlier occurrence becomes the value, and
  the removal silently does not happen.
- **Omit every occurrence:** rejected. It deletes lines the person wrote and the app never displayed.
- **Refuse the write:** rejected. `serialized()` would have to throw, and that cascades through
  `RelatedLink` and every writer, all for the rarest case. The bare key reaches the same consistency
  with no loss.

### §D5: how opaque elements are held

- **`nodes` as an enum of card-or-opaque:** rejected. The whole Workspace reads
  `nodes: [CanvasNode]`, while a side list costs one interleave in `encoded()`.
- **Refuse to save any document whose parse dropped something** (the ROADMAP's other option for
  item 4): rejected by the SPEC's default.

### §D6: `Dictionary(_:uniquingKeysWith:)`

The ROADMAP's fix. **Rejected**: it decides a merge by keeping one of two nodes. Refusing the board
at open was rejected by the SPEC.

### §D8.1: reversing the replacement order

**Rejected**, because it is not an inverse (§D8.1).

### §D9.5: the extension test

- **Note extensions only** (everything that is not `md` is a file): rejected. A title with a dot,
  such as `Riunione del 12.03` or `Analisi 3.5 mm` (pinned by `TransclusionTests:33-35`), would stop
  being a note.
- **Two closed lists and no fallback:** rejected. An attachment with an extension nobody listed would
  become a note transclusion.

### §D12: no bump

This is the named alternative in §D12.

---

## Consequences

### Positive

- A note written by another tool or on another platform survives an in-app write, outside the part
  the app changed.
- A BOM note is written without refusing itself.
- A CRLF note's frontmatter is finally read: its tags, date and category reach every view.
- A foreign `.canvas` keeps every value, and a malformed element no longer empties a board.
- A duplicate-id board can no longer kill the app on the path that exists to protect data.
- An Exchange or Latin-9 mail imports with the right text, subject and attachment names.
- Damage already done is findable through `perg lint`, the MCP `lint` tool and the rule engine.

### Negative

- The frontmatter serializer is harder to read, with two representations to keep in agreement. The
  round-trip corpus is what keeps them honest.
- Unrelated writes no longer normalise tags. An unsorted or inline tag list stays until the tags key
  itself is written, and lint still reports the inline form.
- A BOM note's index hash is no longer the file's plain SHA-256, so `shasum` and the index disagree
  on those files by design.
- If G1.1 passes, the first launch runs a one-time full rescan.
- Message files show a one-time date diff at their next regeneration.
- A note whose only link is a board marker is now counted among `orphan:` results.

### Neutral

- No format the app writes changes shape, apart from the two mail date values.
- `perg` and `pergamenum-mcp` pick up every `Sources/Core` change through `sharedSources`, with no
  manifest edit. Two new files land under `Sources/Core/Email`, and one may land under
  `Sources/Core/Conventions` (`FrontmatterSource.swift`, to keep `Frontmatter.swift` under
  SwiftLint's 400-line warning).
- The `VaultAPI.LintFinding` and `VaultAPI.PraticaSummary` shapes are unchanged.

---

## Acceptance

| R-id | Proven by |
|---|---|
| R-01 | the corpus round-trip in `Tests/FrontmatterRoundTripTests.swift`; a vault-level CRLF case in `Tests/NoteByteOrderMarkTests.swift`; «Collega» on CRLF in `Tests/RelatedSectionTests.swift` |
| R-02 | `Tests/NoteByteOrderMarkTests.swift`, through the session's write door |
| R-03, R-04, R-05 | `Tests/FrontmatterRoundTripTests.swift` |
| R-06, R-07, R-08 | `Tests/CanvasRoundTripTests.swift` |
| R-09 | `Tests/CanvasReconciliationTests.swift` and `Tests/WorkspaceAutosaveRaceTests.swift` (written with the fix, because they trap today) |
| R-10 to R-13 | `Tests/MailFormatEdgeTests.swift` |
| R-14, R-15 | `Tests/MessageDocumentTests.swift` and `Tests/MailFormatEdgeTests.swift` |
| R-16 to R-21 | `Tests/TextFormatEdgeTests.swift`, `Tests/RelatedSectionTests.swift`, `Tests/NoteRenameCharacterizationTests.swift` |
| R-22 | `Tests/FrontmatterDamageLintTests.swift` and `Tests/ConformanceTextTests.swift` |
| R-23 | `Tests/FormatEdgeCorpusTests.swift`, over `Tests/FormatEdgeCorpus.swift` |
| R-24 | this ADR, and `ROADMAP.md` §Chain 1 marked shipped with the PR number |

The whole `PergamenumTests` bundle stays green, including `ConventionsTests`, `TranscriptNoteTests`,
`TranscriptMergeTests`, `DossierWriterTests`, `PraticaLinksWriterTests`, `CategoryLintTests`,
`TransclusionTests` and `CanvasTests`.

## Proposed `CLAUDE.md` chain-index entry

- **ADR-0065** — Closes `PG-254`/#568 (Audit Fable chain 1): every on-disk format round-trips
  faithfully or is refused.
  - `NoteDocument` keeps a `FrontmatterSource` of the lines it read and edits the block in place:
    - an unchanged key, a comment, a colon-less line, an unparsable tag or a duplicate is emitted
      byte-identical;
    - a changed key is rewritten at its governing occurrence, the last one, the one the reader
      already uses;
    - an emptied duplicated key is written bare;
    - a foreign key follows its codec, matched by name and ordinal;
    - CRLF is kept per line, and new lines take the document's line break.
  - The BOM is a property of the file: one decode door strips it, `NoteStore.hash` skips it, and
    `NoteStore.write` keeps it.
  - JSON Canvas consumes keys per kind, keeps unrecognised colours as `.unrecognised`, and keeps
    unreadable elements at their index.
  - `reconcile` diverges on duplicate ids and on opaque differences instead of trapping.
  - Mail: one Latin-9-aware charset table, RFC 2047 §6.2 and B-padding, RFC 2231 parameters, an HTML
    reducer that drains its pending buffers, an exact escape inverse, and `pergamenum-mail-date` with
    the sender's offset (UTC otherwise).
  - Task tags are removed by range, and `![[x]]` is an inline embed.
  - One anchored `RelatedSection.sectionRange(in:)` serves export, the linter and «Collega».
  - Rename matches on `resolvedTitle`.
  - `.canvas` is never a note link target.
  - Three advisory `frontmatter` lint strings are added.
  - `IndexCache.schemaVersion` 4 → 5 (G1).
  - Extends ADR-0054 §D4, ADR-0041 §D7 and ADR-0043's hash convention; amends none →
    `docs/adr/0065-format-round-trip-faithful-or-refused.md`

## Implementation notes

Written after the implementation on `fix/chain-1-format-edge-hardening`, 2026-09-26.

### Gates

- **G1.1.** `IndexCache.schemaVersion` went from 4 to 5 (`Sources/Index/IndexCache.swift`). The
  protected-interface hook did not block the edit. `IndexCacheTests.aCacheStampedFourIsNotReused`
  proves the bump. The existing pin in
  `theThreeNewTaskFieldsSurviveASaveAndLoadRoundTripWithNoSchemaBump` moves from `== 4` to `== 5`,
  as ADR-0047's bump did (`af667c36`). The assertion is unchanged; only its constant follows the
  approved bump.
- **G1.2 to G1.7** are implemented as decided.
- **G2.** `ConventionsTests.reordersTagsOnSave` became `reordersTagsWhenTheTagsKeyIsWritten`, with
  `FrontmatterRoundTripTests.anUnchangedTagsKeyKeepsItsSourceOrder` as its counterpart. No other
  existing test pinned a canonical re-render of an untouched key.

### Departures from the plan

1. **The header unfold changed too.** `EmailHeaderParser.parse` now normalises CRLF to LF before it
   splits fields. The `.eml` import doors hand it CRLF text, and on that text it kept only the
   first field, so R-14's offset could never reach a header that was not first.
2. **ISO-8859-2 is in the charset table.** `MailCharset` maps ISO-8859-2 as well as Latin-9: the
   plan's own test decodes a Latin-2 word, and without the entry it would fall back to UTF-8.
3. **RFC 2047 token end.** `EncodedWord` searches for a token's closing `?=` only after its
   `charset?encoding?` prefix. A `?=` inside the prefix otherwise ended the token early.
4. **HTML drain order.** `HTMLTextReducer.drained()` closes open owners innermost first. It places
   a run of unclosed `td`/`th` cells in the open table outer first, then renders any table still
   open at the end.
5. **Zero offset reads as no offset.** `MessageDocument`'s reader takes `+00:00` as `nil`, the same
   as `Z`. That makes render, parse and render stable for a UTC sender. The sync writes a zero
   header offset as `nil` for the same reason.
6. **The anchored related-section door has two entry points.** `RelatedSection.sectionRange(in:)`
   is joined by `bulletsStart(in:section:)`, the index just after the heading line's break.
   «Collega» needs it to keep the heading line verbatim, CRLF included.
7. **Where tests live.** The R-21 NFD/NFC tests and the extension-set tests are in
   `Tests/TextFormatEdgeTests.swift`; `TransclusionTests` is unchanged. The `MessageDocument`
   exactness tests are a new suite, `MessageDocumentExactnessTests`, inside
   `Tests/MessageDocumentTests.swift`. The sync-path offset test is in
   `Tests/PraticaSyncWritePathTests.swift`.
8. **Bold-link rename count.** `renameCountsTheBoldLink` asserts on `RenamePlan.noteChanges`,
   because `RenamePlan` has no `rewrittenPaths`.
9. **The colon-less finding.** `lineWithoutColon` reports the line trimmed of surrounding
   whitespace.
10. **Where the lint body and the byte cases live.** `FrontmatterRules.damageFindings(of:)` is in
    `FrontmatterSource.swift`, which keeps `Frontmatter.swift` under the 400-line warning. The BOM
    corpus cases (`FormatEdgeCorpus.bomNotes`) arrived in Task 8's sweep, not Task 2.
11. **Lint refactor.** `CanvasDocument.reconcile`'s two early answers (`base == theirs` and
    duplicate ids) moved into a private `settledEarly`, to stay under SwiftLint's complexity
    warning. The behaviour is unchanged.

### Platform decode characterization

On macOS 27.0, `String(data:encoding: .utf8)` **strips** a leading UTF-8 BOM. So, as §D4
anticipated, the decode door cannot tell from the `String` whether a BOM was there. The file keeps
it: `NoteStore.write` reads it back from disk, and `NoteStore.hash` skips it.

### Corpus state

In the final `PergamenumTests` run, every case of `FormatEdgeCorpus.allCases` is green (notes, BOM
byte cases, canvases, mail, message documents). Each one either round-trips byte-identical or is
refused with a named error. None is dropped. The per-case red state before each fix was not
measured case by case; the plan's «Today» column is the prediction, and it was not re-checked
individually.

## References

- `SPEC.md` (Approved 2026-09-26), R-01 to R-24.
- `ROADMAP.md` §"Chain 1 — Format-edge hardening".
- ADR-0010 §D7, ADR-0021, ADR-0036 (§D12, §D21), ADR-0041 §D7, ADR-0043 §D5/§D8, ADR-0047 §D5,
  ADR-0054 §D4/§D5.
- swift-foundation, `Sources/FoundationEssentials/String/String+IO.swift`: the UTF-8 BOM strip, read
  2026-09-26.
- RFC 2047 §6.2, RFC 2231 §3–§4, RFC 5322 §3.3/§4.3, JSON Canvas 1.0.
- Plan: `docs/plans/format-edge-hardening.md`.
