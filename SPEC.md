Status: Approved (2026-09-26)

# SPEC — Format-edge hardening: every on-disk format round-trips faithfully or is refused

## Destination

A SPEC handed to `/workplan`. Closes issue #568 (Audit Fable chain 1, promoted from `PG-254`) in
one chain with one ADR: "the round-trip of every on-disk format is faithful or refused". The
parsers for notes, frontmatter, JSON Canvas, mail and task text stop losing or corrupting data on
inputs that are legitimate in this vault's own life, and a new advisory lint rule points at the
notes an earlier version of the app already damaged.

## Objectives

- A file written by another tool or another platform (a note synced from Windows, a `.canvas`
  written by another editor, an Exchange mail) survives an in-app write unchanged outside the part
  the app meant to change. Today 16 distinct paths drop or corrupt data silently: no error, no
  report.
- Principle 1 (file over app) holds for real on the formats the app writes: what the app does not
  understand, it carries through untouched; where carrying it through is impossible, it refuses
  visibly instead of guessing.
- Notes already damaged by the frontmatter defects are findable: `perg lint`, the MCP `lint` tool
  and the rule engine report them.

## Scope and non-goals

In: the 17 items of `ROADMAP.md` §Chain 1, as verified against HEAD `43ca911` on 2026-09-26
(15 reproduce as written, item 5 reproduces under a narrower condition, item 17 does not
reproduce and is pinned by a test only); one advisory lint rule over frontmatter damage.

Out (detail in *Out of scope*): repairing already-damaged files; renaming existing Pratiche
message files; a fixture directory of real files; GUI tests; the other chains of the audit.

## Decisions

- **One SPEC and one ADR for all 17 items** — the principle is one and the test harness is shared
  (a corpus plus table-driven round-trip tests). Rejected: three SPECs (notes and text, Canvas,
  mail) — three ADRs or one ADR amended twice for a single rule.
- **CRLF line endings and a UTF-8 BOM are preserved on write** — the file keeps its bytes outside
  the part the app changed, consistent with file over app and with a vault synced from Windows.
  Rejected: normalising to LF without a BOM — the first write would rewrite every line, an
  enormous diff that iCloud and other tools see as a full modification.
- **Default for what a parser does not understand: keep it opaque and re-emit it verbatim; refuse
  only where keeping it cannot be made consistent** — covers frontmatter lines without a colon
  (including YAML comments), duplicate keys, tags outside the vocabulary, Canvas nodes of an
  unknown type with every payload key, unknown colours kept as raw strings, nodes or edges
  missing `id`/`type`. Rejected: refusing every save on anything unknown — no loss, but the app
  stops working on legitimate files from other tools.
- **A Canvas with duplicate node or edge ids opens normally; a reconciliation that meets
  duplicate ids diverges into the existing `conflicted` board state and records a problem, never a
  crash** — reuses ADR-0054's non-modal «Mantieni le mie modifiche» / «Ricarica dal disco».
  Rejected: refusing the board at open — makes a legitimate foreign file unusable.
- **`pergamenum-mail-date` is written with the sender's own UTC offset, taken from the raw `Date`
  header; UTC when only the Envelope Index date is available** — matches the documented intent
  ("the zone the message was sent in") and removes the dependency on the machine's zone, which is
  what broke ADR-0036 §D21's diff stability across a DST change. Rejected: always UTC — uniform,
  but a 10:00 Italian mail reads 08:00Z in the file.
- **ISO-8859-15 (Latin-9) decodes as Latin-9** — today it is mapped to Latin-2, which decodes
  cleanly and wrongly (`€` becomes `¤`). No alternative was on the table.
- **RFC 2047: linear whitespace between two adjacent encoded-words is dropped (§6.2); a B-word
  with non-canonical padding still decodes; RFC 2231 extended and continued parameters are
  honoured and a `;` inside quotes does not split a parameter.** No alternative discussed.
- **Rename matches a wikilink on its resolved title (emphasis stripped), the same rule navigation
  and backlinks already use, and rewrites the title inside the emphasis markers** —
  `[[**Forno tunnel**]]` becomes `[[**Nuovo nome**]]`. No alternative discussed.
- **A `.canvas` target is never a note link target; the transclusion "is this a note" test names
  its extensions explicitly** — a board stops appearing as a backlink target. No alternative
  discussed.
- **Item 17 (Unicode normalisation in resolvers) gets a regression test and no code change** —
  verified 2026-09-26: Swift `String` equality and hashing already use canonical equivalence, so
  NFD and NFC compare equal in every cited fold. Rejected: dropping it with no test — the
  guarantee would rest on nobody changing a comparison to a byte or `NSString` one.
- **A new advisory lint rule reports frontmatter damage: a note carrying two frontmatter blocks
  (the prepend defect's trace), duplicate frontmatter keys, and frontmatter lines without a
  colon** — surfaced through the existing `frontmatter` findings, so the protected
  `VaultAPI.LintFinding` JSON shape does not change. Rejected: leaving existing damage out of
  scope with no detection (the recommended option, overruled by Stefano); reporting only the
  double block (less noise, overruled for completeness).
- **The corpus lives in a Swift source file of byte-exact strings, following
  `EmailFixtureCorpus`'s convention; no fixture directory** — no manifest change, `\r\n` and the
  BOM are explicit in the source. Rejected: a `Tests/Fixtures` directory of real files — more
  faithful to "a file from another tool" but needs a `Project.swift` resource change.

## Constraints

- **Note frontmatter schema is closed (`date`, `tags`, `related`, `aliases`) and tags match the
  namespaced regex** — origin: SPEC §4.3/§4.4, CLAUDE.md. Preserving an unknown line verbatim is
  not extending the schema: the app never interprets or writes it.
- **A Pratiche regeneration's diff shows exactly the bytes written** — origin: ADR-0036 §D21.
- **Protected interfaces unchanged**: `VaultAPI.LintFinding`, `PraticaNaming.messageFileName`,
  `Dossier.render`, `ImportNaming.recordingNoteTitle`, `MessageDocument.isPendingAttachmentEntry`
  — origin: `.claude/protected-interfaces`.
- **`Sources/Core` stays Foundation-only** — origin: ADR-0001 §D1; `perg` and `pergamenum-mcp`
  compile it.
- **A board conflict uses ADR-0054's existing `conflicted` state and its two actions** — origin:
  ADR-0054 §D5/§D7.
- **The new lint findings are advisory and never block a write or tag entry** — origin: user
  mandate in this interview ("segnala"), and ADR-0038 keeps the rule engine behind tag-entry
  blocking, which these findings must not reach.
- **No GUI test** — origin: CLAUDE.md merge-gate rule; nothing here is reachable only through the
  interface.

## Stack

Swift 6, Swift Testing, Foundation string encodings (Latin-9 through the Core Foundation encoding
table). No new dependency.

## Data model

- **Frontmatter document**: besides the four schema keys and the foreign `pergamenum-*` keys it
  already keeps, it carries the raw lines it did not interpret, in their original position, the
  tags that failed validation, and the file's line-ending style and BOM presence, so rendering
  can reproduce them.
- **Canvas node / edge**: an unknown-type node keeps its whole raw object; an unrecognised colour
  is kept as its raw string; a node or edge without `id`/`type` is kept as an opaque raw object and
  written back in place. Whether a card is a "Nota" depends on a colour being present, not on the
  colour being valid, so an unknown colour does not turn a note into plain text.
- **Message document**: the date carries the sender's offset; escaping and unescaping are exact
  inverses.

## API / interfaces

- No connector JSON shape changes. `lint` gains new strings inside the existing `frontmatter`
  findings array.
- No change to any protected interface signature.

## Edge cases

- A note with CRLF and a BOM whose frontmatter is edited in-app: only the edited key changes; every
  line still ends in CRLF; the BOM is still there.
- A duplicated `tags:` block: both blocks survive a write that does not touch tags (see *Not yet
  specified* for a write that does).
- A Canvas whose nodes share an id: opens and edits normally; if an external writer changes the
  file during a pending save, the board goes `conflicted` with a recorded problem instead of
  trapping.
- An existing Pratiche message file written before this change: a later «Rigenera» shows a
  one-time diff on `pergamenum-mail-date` (machine zone → sender offset). Its file name does not
  change, because a sync never renames a message file.
- An HTML body with an unclosed `<a>` or `<td>` at end of input: the text after the open tag is
  kept.
- A task line with `#topic-forni e #topic-forni-tunnel`: the display text removes both tags whole,
  leaving "e" and no `-tunnel` residue.
- `## ![[schema.png]]` in a heading: renders as an embed, never as `!schema.png`.
- `### Note correlate operative` or a mid-sentence "## Note correlate": not taken as the related
  section by export or by the linter.

## Test seams

1. **The pure parsers in Core** (frontmatter, JSON Canvas and reconciliation, MIME decoder, header
   decoder, HTML reducer, message document, task parser, inline markdown, rename, export, related
   section, transclusion, board resolver): table-driven Swift Testing over one in-code corpus, each
   case asserting parse → serialise equals the original bytes, or a named refusal. This seam
   carries almost every criterion.
2. **One vault-level test through the session's write door** for CRLF and BOM, because the BOM's
   fate is decided by the text decoding on read and the write hash, not by the parser alone.
3. **The existing lint engine tests** for the new advisory rule.

No GUI test, no new test target.

## Success criteria

- [ ] R-01 — A note with CRLF line endings, with and without frontmatter, round-trips byte-identical
  through parse and serialise, and an in-app frontmatter change leaves every other byte (CRLF
  included) untouched; no second frontmatter block is ever prepended.
- [ ] R-02 — A note starting with a UTF-8 BOM keeps its BOM and its frontmatter through an in-app
  write via the session's write door, and the write is not refused by its own hash precondition.
- [ ] R-03 — A tag that fails vocabulary validation is written back verbatim, after the valid tags,
  on every serialise.
- [ ] R-04 — A frontmatter line without a colon (including a column-0 YAML comment) is written back
  verbatim in its original position.
- [ ] R-05 — A duplicated frontmatter key (schema or foreign) round-trips with both occurrences,
  byte-identical, when the write does not touch that key.
- [ ] R-06 — A Canvas node of an unknown type round-trips with every payload key it had.
- [ ] R-07 — An unrecognised colour on a node or an edge round-trips as its original string, and a
  node carrying one is still read as a "Nota".
- [ ] R-08 — A Canvas node or edge missing `id` or `type` is written back, not dropped.
- [ ] R-09 — Reconciling a Canvas document with duplicate node or edge ids never traps: the board
  enters the `conflicted` state and one problem is recorded.
- [ ] R-10 — An HTML body with an unclosed `<a>` or `<td>` keeps all the text that follows it.
- [ ] R-11 — An ISO-8859-15 part or header decodes byte `0xA4` as `€`.
- [ ] R-12 — Whitespace between two adjacent RFC 2047 encoded-words (including one produced by
  unfolding) does not reach the decoded subject; a B-word with non-canonical padding decodes.
- [ ] R-13 — An RFC 2231 `filename*=` (with charset, and with continuations) yields the right
  attachment name and extension, and `filename="Report; finale.pdf"` is not cut at the semicolon.
- [ ] R-14 — A message subject containing a backslash followed by `n` (`C:\nuovo`) round-trips
  through the message document unchanged.
- [ ] R-15 — `pergamenum-mail-date` carries the sender's offset from the raw `Date` header, or UTC
  when there is none, and the value does not depend on the machine's time zone.
- [ ] R-16 — A task's display text removes each tag as a whole token, so a tag that is a prefix of
  another leaves no residue.
- [ ] R-17 — `![[file]]` inline is parsed as an embed, with no orphan `!`, in body text and in
  headings.
- [ ] R-18 — The related section is recognised only as a line that is exactly its heading, by
  export and by the linter.
- [ ] R-19 — Renaming a note rewrites `[[**Title**]]` (and the other emphasis forms `resolvedTitle`
  strips) to the new title inside the same markers, and the reported count includes it.
- [ ] R-20 — A `^[[Board.canvas]]` marker never adds a `.canvas` target to a note's link targets,
  and the transclusion note test decides by an explicit extension list.
- [ ] R-21 — A regression test asserts that NFD and NFC spellings of the same name resolve to the
  same board and the same note in the cited resolvers.
- [ ] R-22 — The lint engine reports, as advisory `frontmatter` findings, a note carrying two
  frontmatter blocks, a duplicated frontmatter key, and a frontmatter line without a colon; the
  `VaultAPI.LintFinding` JSON shape is unchanged and none of these findings blocks a write or tag
  entry.
- [ ] R-23 — Every case of the chain's corpus either round-trips byte-identical or is refused with
  a recorded problem; no case is dropped silently.
- [ ] R-24 — One ADR records the "faithful or refused" rule and the decisions above, and
  `ROADMAP.md` §Chain 1 is marked shipped with the PR number. (no-test: documentation obligation)

## Not yet specified

- **An in-app write to a key that appears more than once** (for example a category change on a
  note whose `tags:` is duplicated): which occurrence the app rewrites, and whether the others
  stay, merge or trigger a refusal. Real and in scope, but it depends on how the preserved raw
  lines are modelled, which `/workplan` settles; the default under the opaque-first rule is to keep
  every occurrence it did not mean to change.

## Out of scope

- **Repairing damaged files**: data already lost (a dropped tag, a dropped canvas key) cannot be
  reconstructed; a double frontmatter block is fixed by hand once lint points at it.
- **Renaming existing Pratiche message files** whose names were built from a subject decoded with
  the whitespace defect: a sync never renames a message file (ADR-0036), and changing that is a
  separate decision.
- **A fixture directory of real files**: rejected above for the manifest change it needs.
- **GUI tests**: nothing here needs the interface to be observed.
- **The other chains of the audit**, including chain 2 (board lifecycle), which touches
  neighbouring Workspace code but not the parsers.
