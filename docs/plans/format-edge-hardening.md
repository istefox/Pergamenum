# Plan: PG-254 / #568 (Audit Fable chain 1), format-edge hardening

- **SPEC:** `SPEC.md` (Approved 2026-09-26), success criteria R-01…R-24.
  - Its Decisions, Constraints and Test seams are settled and are not reopened here.
  - Seven points go past the SPEC's letter. Each one waits on gate G1 below, and none is decided on
    Stefano's behalf.
  - One test rewrite waits on gate G2.
- **ADR:** new, ADR-0065, at `docs/adr/0065-format-round-trip-faithful-or-refused.md` (status:
  proposed). The SPEC mandates it (R-24), and the chain passes the significance test on its own
  (see the ADR's header).
- **The SPEC's «Not yet specified» item is settled in ADR-0065 §D2.**
  - Schema keys: one occurrence governs, the last one, which is the one the reader already uses.
    - A write that changes the value rewrites that occurrence in place.
    - A write that empties a duplicated key writes it as the bare key (`related:`), which reads back
      as empty.
    - Every other occurrence stays byte-identical, where it was.
  - Foreign keys follow their owning codec, matched to the file by name and ordinal.
  - Nothing is merged and nothing is refused.
- **Baseline:** written against `43ca911`, which is both `HEAD` and `origin/main`. The tree is clean
  apart from `SPEC.md` and the two new documents. Every file:line below was read from that tree on
  2026-09-26.
- **UI budget:** zero GUI tests (SPEC Constraint 7). Everything is asserted in-process in
  `PergamenumTests`.

## Before `/build` (orchestrator; each item is a HITL point)

**Approved by Stefano at `/workplan` GATE 1/2, 2026-09-26:** the plan, ADR-0065, G1.1–G1.7 and G2
as recommended below. Item 6 (filing the §D13 follow-ups) still needs its own OK at Task 8.

1. Run `tuist install` (once per fresh worktree), then `tuist generate --no-open`.
   - Run `tuist generate --no-open` again after every tester half that adds a file.
   - New test files are added in Tasks 1, 2, 3, 4, 6 and 7.
   - New `Sources/Core` files are added in Tasks 1, 3 (optional) and 4.
   - `Sources/Core/**` and `Tests/**` are globbed, so no manifest edit is needed.
2. **Gate G1: approve ADR-0065.** Each point needs its own answer. Refusing one leaves the rest
   standing; the plan then records that point as a named gap and never claims it holds.

   | # | Point (ADR-0065) | If refused | Recommendation |
   |---|---|---|---|
   | G1.1 | §D12, `IndexCache.schemaVersion` 4 → 5 (a protected constant the SPEC's list omits) | stale cached frontmatter for every CRLF note until the file changes or «Svuota cache»; say so in the release notes | approve |
   | G1.2 | §D4.2, `NoteStore.hash` skips one leading BOM (redefines a persisted value; values for every BOM-less file are unchanged) | R-02 cannot hold on a platform whose decode strips the BOM, and the plan has no other design that meets it | approve |
   | G1.3 | §D3, `TagRename` tolerates CRLF delimiters | a vault-wide tag rename keeps silently skipping every CRLF note | approve |
   | G1.4 | §D9.3, «Collega» (`RelatedLink`) uses the anchored locator | the linter and «Collega» disagree about where the section is | approve |
   | G1.5 | §D8.4, `pergamenum-mail-received` is written in UTC | that key keeps the machine's zone, so R-15's stability holds for the date only | approve |
   | G1.6 | §D5.5, a `nodes`/`edges` value that is not an array refuses the open | such a board opens empty, and the first save writes `[]` over the value | approve |
   | G1.7 | §D5.3, an optional canvas key is consumed only when understood (edge side/end, non-string `label`/`color`) | those values keep being dropped on save | approve |

3. **Gate G2: a test that pins the old contract is rewritten, never deleted.**
   - `ConventionsTests.reordersTagsOnSave` (`ConventionsTests.swift:199-212`) asserts that saving an
     unchanged note re-sorts its tags.
   - That is exactly the "every other byte untouched" that R-01 forbids and that the SPEC's
     Decision 2 rules out.
   - It becomes two tests:
     - `reordersTagsWhenTheTagsKeyIsWritten`: a tag is added, and the canonical order is asserted;
     - `anUnchangedTagsKeyKeepsItsSourceOrder`.
   - The global rule asks for this reason to be stated in chat before the test changes. It is stated
     here, and the orchestrator repeats it at the gate.
   - If Task 1's full-suite run turns up another test that pins a canonical re-render of an
     **untouched** key, that test comes back to G2 with the same explanation before anyone edits it.
4. **G1.1 meets the protected-interface hook.**
   - `interface-check.sh` guards `Sources/Index/IndexCache.swift:schemaVersion`.
   - It is handled the way ADR-0047's 3 → 4 bump was: Stefano approves it in the session, and the
     orchestrator either lets the one-line edit through or hands it to him verbatim.
5. Commit, push and merge stay HITL at the end of `/build`.
   - The pre-push guard (ADR-0061/0062) runs on push, if it is installed on this machine.
   - The merge gate is the unit suite, plus `scripts/uitests.sh --affected` (CLAUDE.md).
6. Filing the ADR-0065 §D13 follow-ups as GitHub issues (Task 8) is an outward action. It happens
   with Stefano's OK.

## Ownership and order

This is a compiled target. In each task the **tester** owns every signature the tests name, and the
**coder** owns the bodies.

**Within a task**, the tester's half lands first and must leave `Pergamenum`, `perg` and
`pergamenum-mcp` building.

- The new tests are then red on their assertions, except the ones marked «green» (pins) or «platform»
  (Task 2).
- When the tester adds an enum case, the tester also adds a compiling arm to every exhaustive switch
  on it. The coder may refine that arm.

**Across tasks**, the order below is binding where one task depends on another:

- Task 1 comes first: it builds the frontmatter model that Tasks 2, 6 and 7 read.
- Task 2 comes after Task 1.
- Task 5 comes after Task 4, because both edit `Sources/Core/Email/EmailHeaders.swift`.
- Task 6 comes after Task 1, because «Collega» needs the document's line break.
- Task 7 comes after Task 1, because it reads `FrontmatterSource`.
- Task 3 is independent of the rest.
- Task 8 comes last.

The tester may do several tasks' halves in one batch before the coder starts, as long as all four
rules below hold.

**Rule 1: no test may trap the test host on today's code.**

- The `Stop` hook runs the whole `PergamenumTests` bundle every turn. A trap kills the bundle and
  hides every other result, which is worse than a red test.
- One path traps in-process today: duplicate ids reaching `Dictionary(uniqueKeysWithValues:)`
  (`CanvasReconciliation.swift:39-40`, `:63-64`).
- The R-09 tests, both the pure ones and the controller one, are therefore written in **Task 3's
  coder half, in the same commit as the fix**. Task 3's tester half still has a non-trapping red for
  the reconciliation: the opaque-element divergence.

**Rule 2: placeholder bodies never trap.** No `fatalError`, no `preconditionFailure`, no force
unwrap. A placeholder keeps today's behaviour, or returns an inert value.

**Rule 3: no test changes the process's time zone or locale.**

- Swift Testing runs tests in parallel, and `NSTimeZone.default` is process-wide.
- R-15's independence from the machine's zone is proven with a sender offset no test machine has
  (`+0900`): Stefano's Mac is `+01:00`/`+02:00`, and CI is UTC.

**Rule 4: corpus bytes are explicit.**

- Swift normalises the line endings of a multi-line string literal to LF. So every CRLF case is a
  single-line literal with `\r\n` spelled out, and U+FEFF is spelled `\u{FEFF}`.
- A byte-level BOM is `Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)`.
- The corpus follows `Tests/EmailFixtureCorpus.swift`'s convention: one `enum` of static values, with
  no fixture directory (SPEC Decision 10).

---

### Task 1 — The corpus and the lossless frontmatter (R-01, R-03, R-04, R-05, R-23)

**Files:**

- `Sources/Core/Conventions/Frontmatter.swift`
- new `Sources/Core/Conventions/FrontmatterSource.swift`, which keeps `Frontmatter.swift` under
  SwiftLint's 400-line warning (it is 368 lines today)
- `Sources/Core/Conventions/TagRename.swift` (G1.3)
- `Sources/Features/Recordings/TranscriptNote.swift`
- new `Tests/FormatEdgeCorpus.swift`
- new `Tests/FrontmatterRoundTripTests.swift`
- new `Tests/FormatEdgeCorpusTests.swift`
- `Tests/ConventionsTests.swift` (G2)
- `Tests/TagRenameTests.swift`
- `Tests/TranscriptNoteTests.swift`

#### Tester

1. Declare in `FrontmatterSource.swift`, under ADR-0065 §D1.1:
   - `enum LineBreak: Equatable, Sendable { case lf, crlf }`, with `var characters: String`;
   - `struct FrontmatterSource: Equatable, Sendable`, containing:
     - a nested `enum Entry: Equatable, Sendable { case key(name: String, lines: [String]); case opaque(String) }`;
     - `opening: String`;
     - `entries: [Entry]`;
     - `closing: String?`;
     - `closingHasLineBreak: Bool`;
     - `lineBreak: LineBreak`;
     - `parsed: Frontmatter`.
2. Add `var source: FrontmatterSource? = nil` to `NoteDocument` (`Frontmatter.swift:137`). The
   memberwise init stays source-compatible, including
   `NuovaPraticaWizard+Actions.swift:172-176` and `Frontmatter.swift:150,157`.
3. Add `lineBreak: LineBreak = .lf` to `FrontmatterSerializer.render`.
4. The placeholders keep today's behaviour: `parse` leaves `source` nil, and `serialized()`/`render`
   are unchanged.
5. Run `tuist generate --no-open`.
6. Write `Tests/FormatEdgeCorpus.swift`: `enum FormatEdgeCorpus`, with
   `struct NoteCase { let name: String; let text: String }` and `static let notes: [NoteCase]`. The
   cases are listed here by name, with their shape. The exact bytes are the tester's, within Rule 4.

   | Case | Shape |
   |---|---|
   | `lfConformant` | today's conformant note: `date`, block `tags`, a body |
   | `crlfWithFrontmatter` | `"---\r\ndate: 2026-09-26\r\ntags:\r\n  - type-note\r\n---\r\n# Titolo\r\n\r\nCorpo.\r\n"` |
   | `crlfWithoutFrontmatter` | `"# Titolo\r\n\r\nCorpo.\r\n"` |
   | `lfWithoutFrontmatter` | `"# Titolo\n\ntesto"` |
   | `mixedLineEndings` | some block lines CRLF, others LF, a CRLF body |
   | `textBorneBOM` | `"\u{FEFF}---\ndate: …\ntags: [type-note]\n---\nCorpo.\n"` |
   | `yamlComment` | `# importato da Plaud` as the first block line |
   | `colonlessAndBlankLines` | a blank line and `solo testo` between two keys |
   | `orphanContinuation` | `  - vagante` straight after the opening delimiter |
   | `duplicateTags` | `tags:` twice, with different items |
   | `duplicateRelated` | `related:` twice |
   | `duplicateForeign` | `cssclass:` twice, with a schema key between them |
   | `duplicateCategory` | `pergamenum-category:` twice |
   | `unparsableTag` | `cliente-acme` before `type-note` in a block list |
   | `unsortedInlineTags` | `tags: [topic-zeta, type-note]` |
   | `closingWithoutLineBreak` | the file ends at the closing `---` |
   | `unterminatedBlock` | `"---\ndate: 2026-09-26\ntesto che continua"` |
   | `damagedDoubleBlock` | `"---\n---\n---\r\ndate: 2026-01-01\r\ntags: [type-note]\r\n---\r\nCorpo.\r\n"` (read by Task 7) |

7. Write `Tests/FrontmatterRoundTripTests.swift`. "Category change" means appending
   `Frontmatter.ForeignKey(name: "pergamenum-category", lines: ["pergamenum-category: presse"])`,
   the way `linkCategory` does (filter, then append).

| Test | Asserts | Today |
|---|---|---|
| `everyNoteCaseRoundTripsByteIdentical` (arguments: `FormatEdgeCorpus.notes`) | `NoteDocument.parse(text).serialized() == text` (R-01, R-04, R-05, R-23) | red, except `lfConformant` and `unterminatedBlock`… see note below |
| `aCRLFNoteGainsOneLineOnACategoryChange` | on `crlfWithFrontmatter`, the result is the original with exactly one added line, `pergamenum-category: presse\r\n`, before the closing delimiter; every line ends in `\r\n`; one block (R-01) | red |
| `aNoteWithoutFrontmatterSerializesToItself` | `crlfWithoutFrontmatter` and `lfWithoutFrontmatter` give back their own text; no `---` is added (R-01) | red |
| `aNoteWithoutFrontmatterThatGainsAKeyGetsOneBlock` | `crlfWithoutFrontmatter` plus `related = ["[[Alfa]]"]` gives one CRLF block at the top, then the original bytes (R-01) | red |
| `aCRLFBodyIsTheVerbatimTail` | on `crlfWithFrontmatter`, `body == "# Titolo\r\n\r\nCorpo.\r\n"` and `text.hasSuffix(body)` (R-01) | red |
| `aClosingDelimiterWithoutLineBreakGainsNone` | `closingWithoutLineBreak` plus a `related` change still ends in `---` (R-01) | red |
| `aTextBorneBOMStaysFirst` | `textBorneBOM` round-trips; after a category change it still starts with `"\u{FEFF}---\n"` (R-01, ADR §D4.4) | red |
| `anUnparsableTagSurvivesATagWrite` | `unparsableTag` plus an appended `topic-gomma`: the valid tags come in `TagRules.ordered` order, then `  - cliente-acme` (R-03) | red |
| `aFreshRenderWritesUnparsableTagsLast` | `FrontmatterSerializer.render` of a `Frontmatter` with `tags [type-note]` and `unparsableTags [cliente-acme]` contains `"  - type-note\n  - cliente-acme\n"` (R-03) | red |
| `anUnchangedTagsKeyKeepsItsSourceOrder` | `unsortedInlineTags` plus a `related` change keeps the `tags:` line byte-identical (R-05; G2's counterpart) | red |
| `aColumnZeroCommentStaysOnItsLine` | `yamlComment` plus a `related` change: block line 1 is still `# importato da Plaud` (R-04) | red |
| `aColonlessLineAndABlankLineStayInPlace` | `colonlessAndBlankLines` plus a category change keeps both lines where they were (R-04) | red |
| `anOrphanContinuationLineIsKept` | `orphanContinuation` plus a category change keeps `  - vagante` on its line (R-04) | red |
| `aDuplicatedTagsKeySurvivesACategoryWrite` | `duplicateTags` plus a category change: both `tags:` blocks byte-identical; re-parse gives the last one's tags (R-05) | red |
| `aDuplicatedForeignKeySurvivesAnUnrelatedWrite` | `duplicateForeign` plus a `related` change: both `cssclass` lines byte-identical, in place (R-05) | red |
| `aChangedDuplicatedKeyRewritesTheLastOccurrence` | `duplicateRelated` plus `[[Gamma]]` appended: the first `related:` block is byte-identical, the second is rewritten, and re-parse gives the written list (ADR §D2) | red |
| `anEmptiedDuplicatedKeyIsWrittenBare` | `duplicateRelated` plus `related = []`: the first block is byte-identical, the second becomes `related:`, and re-parse gives `[]` (ADR §D2) | red |
| `aCodecOwnedDuplicateFollowsTheCodec` | `duplicateCategory` after filter-then-append leaves one category line, at the first occurrence's position (ADR §D2, ADR-0047) | red |
| `aTranscriptReimportKeepsAComment` (in `TranscriptNoteTests`) | `TranscriptNote.render(…, existingNoteText:)` over a note with a YAML comment keeps the comment on its line (R-04) | red |
| `tagRenameReachesACRLFNote` (in `TagRenameTests`) | renaming `type-note` over `crlfWithFrontmatter` rewrites the tag, and every line still ends in `\r\n` (G1.3) | red |

The note on the first row: the green cases are the ones whose text is today's canonical form
(`lfConformant`) or has no block (`unterminatedBlock` is green only if today's serialize adds
nothing, which it does not). The tester records each case's red or green state in the commit message
rather than guessing it here.

8. Write `Tests/FormatEdgeCorpusTests.swift` with one parameterized test,
   `everyCorpusCaseRoundTripsOrIsRefused`, over the note cases for now (R-23). Tasks 2 to 5 add
   their formats to it.

#### Coder

1. `NoteDocument.parse` builds the `FrontmatterSource` (ADR-0065 §D1.1-§D1.2):
   - it keeps `components(separatedBy: "\n")`;
   - it interprets each line with one trailing `\r` removed, and removes one leading U+FEFF on the
     first line;
   - it tests delimiters on the interpreted line;
   - it detects the line break from the text's first line break (§D3);
   - `body` stays the verbatim tail.
2. `FrontmatterParser.parse` takes interpreted lines. Its value semantics do not change: the last
   occurrence of a schema key still wins, and foreign keys are appended in order. `ForeignKey.lines`
   holds interpreted lines.
3. `serialized()` implements §D1.3 and §D2:
   - verbatim entries;
   - an in-place rewrite of the governing occurrence;
   - canonical placement of a new schema key;
   - the bare key for an emptied duplicate;
   - the name-and-ordinal match for foreign keys;
   - opaque entries emitted verbatim;
   - the document's line break on every new line;
   - no block for a document that had none and has nothing to write;
   - no line break added after a closing delimiter that had none.
4. `FrontmatterSerializer.render` writes `unparsableTags` after the valid tags, and honours
   `lineBreak` (§D1.5).
5. `TranscriptNote.render` (`TranscriptNote.swift:76-90`): when `existing` has a block, it sets the
   merged frontmatter and the rebuilt body on the parsed document and returns `serialized()`. It
   stays unchanged for a new note (§D1.8).
6. `TagRename` (`:19-21`, `:168-169`): the delimiter test tolerates one trailing `\r`, and inserted
   lines end in the document's line break (G1.3).
7. G2: rewrite `reordersTagsOnSave` as `reordersTagsWhenTheTagsKeyIsWritten`. Its assertion stays
   the canonical order, now after a tag is added.

**Contract-change call sites.** `serialized()` stops re-rendering untouched keys. The reviewer reads
each of these against the new rule:

- in `Sources`:
  - `RelatedLink.swift:57,65`
  - `VaultSession+Categories.swift:140`
  - `VaultPraticheLinks.swift:360`
  - `PraticaCommandActions.swift:374`
  - `PraticaLiveSync+Run.swift:201`
  - `DossierWriter.swift:37`
  - `PraticaLinksWriter.swift:31`
  - `NuovaPraticaWizard+Actions.swift:176`
  - `TranscriptNote.swift:90`
- `FrontmatterSerializer.render`'s fresh renders produce the same output as today whenever there is
  no unparsable tag:
  - `MessageDocument.swift:111`
  - `VaultSession+Tasks.swift:316`
  - `VaultSession+Diary.swift:58`
  - `VaultSession+TimeBlocks.swift:107`
  - `VaultSession+Notes.swift:63`
- tests that call `serialized()`/`render`: `ConventionsTests` (5 calls), `TranscriptNoteTests` (3,
  including `:74` and `:108`), `FrontmatterPrefixTests:78`.
- tests that assert text a writer produced: `DossierWriterTests`, `PraticaLinksWriterTests`,
  `PraticaLinkCommandTests`, `RelatedLinkTests`, `CategoryLintTests`, `TranscriptMergeTests`,
  `TaskMarkerTests:310`.

Any of these that goes red on an **untouched** key goes through G2.

**Done when:** every test above passes, `reordersTagsWhenTheTagsKeyIsWritten` passes, all three
schemes build, and the whole unit bundle is green.

### Task 2 — The byte-order mark belongs to the file (R-02, R-01, R-23)

**Files:**

- `Sources/Vault/NoteStore.swift`
- `Sources/Vault/NoteStore+ReadSurface.swift`
- `Sources/Vault/VaultSession+Journal.swift`
- `Sources/Vault/VaultFileChange+ExpectedHash.swift` (doc comment only)
- new `Tests/NoteByteOrderMarkTests.swift`
- `Tests/FormatEdgeCorpus.swift` (byte-level BOM cases)
- `Tests/FormatEdgeCorpusTests.swift`

#### Tester

1. Declare `static func decodedText(_ data: Data) -> String?` on `NoteStore`, with the placeholder
   `String(data: data, encoding: .utf8)`.
2. Add `static let bomNotes: [(name: String, bytes: Data)]` to the corpus: a BOM plus
   `crlfWithFrontmatter`, and a BOM plus `lfConformant`.
3. Vault-level tests use a temporary root and a temporary `stateBase`, in the shape of
   `CategoryLintTests.swift:15-27` (`session(root:stateBase:)`, `openSession`).

| Test | Asserts | Today |
|---|---|---|
| `theDecodeDoorStripsOneLeadingBOM` | `decodedText(BOM + "---\n") == "---\n"`; a BOM-less input is unchanged; a U+FEFF that is not at byte 0 is kept (R-02) | platform |
| `theContentHashSkipsOneLeadingBOM` | `hash(BOM + x) == hash(x)`, and `hash(x)` equals the plain SHA-256 hex of `x`, which pins every persisted hash of a BOM-less file (R-02, G1.2) | red on the first assertion, green on the second |
| `aCRLFNoteKeepsCRLFThroughTheSessionDoor` | `linkCategory` on a CRLF note answers `.written`; every line on disk still ends in `\r\n`; one block (R-01) | red |
| `aBOMNoteKeepsItsBOMThroughACategoryLink` | a file with the bytes BOM plus `crlfWithFrontmatter`, then `linkCategory("presse")`: the answer is `.written`, the bytes still start with `EF BB BF`, every line ends in `\r\n`, and the decoded text is the original plus one category line (R-02, R-01) | red |
| `aBOMNoteIsNotRefusedByTheLinkWriter` | two BOM notes and `addStructuralLink` (`VaultSession+Notes.swift:221`, which passes `record.contentHash`): both are written and neither is refused; both keep their BOM; the source's `related` contains the target (R-02) | red or platform |
| `theAppsOwnWriteToABOMNoteIsNotAnExternalChange` | after the write, `await session.reconcile(["Nota.md"])` is empty (R-02) | platform |
| `theReadTextOfABOMNoteHasNoBOM` | `session.read(path).text` does not start with U+FEFF (R-02) | platform |
| `aNewNoteNeverGetsABOM` | a note made through the session's note-creation door does not start with `EF BB BF` (R-02 boundary) | green, pins |
| `platformUTF8DecodeOfABOMIsRecorded` | characterization: whether `String(data:encoding: .utf8)` keeps U+FEFF on this OS. The expected value is taken from the first run, and a comment says that ADR-0065 §D4 does not depend on it | green, characterization |

"platform" means the test's state today depends on the decode behaviour the characterization test
records. The tester writes that result in the commit message.

#### Coder

1. `NoteStore.decodedText` removes one leading `EF BB BF`, then decodes. It is used at
   `NoteStore.swift:100`, `NoteStore+ReadSurface.swift:16,44` and
   `VaultSession+Journal.swift:172` (ADR-0065 §D4.1).
2. `NoteStore.hash` hashes the bytes after one leading `EF BB BF` (§D4.2, G1.2). Update the
   `hexString` comment, whose words "persisted in the index cache, so the spelling is not free to
   change" now describe a deliberate, bounded redefinition.
3. `NoteStore.write` reads the first three bytes of the file it replaces. If they are a BOM and the
   new bytes do not start with one, it prepends it (§D4.3). `writeGuarded` inherits the rule, because
   it delegates to `write`.
4. The doc comment of `VaultFileChange+ExpectedHash.swift` names the new definition.

**Contract-change call sites** (`NoteStore.hash`). Every one of them compares values made by the
same function, so none changes. The reviewer confirms that none hashes a note's bytes by any other
route:

- `VaultScanner.swift:156`
- `NoteStore.swift:161,184`
- `VaultDisk.swift:228,325,357`
- `VaultSession+Journal.swift:170,241,378`
- `VaultSession.swift:596`
- `VaultSession+Categories.swift:142`
- `VaultSession+Tasks.swift:150`
- `VaultSession+TimeBlocks.swift:109`
- `VaultFileChange+ExpectedHash.swift:11`
- `CanvasStore.swift:62,86,95,110`
- `PraticaSyncEngine+Folder.swift:153`
- `PraticaSyncEngine+Messages.swift:852`
- `DiaryController.swift:255`

`ThumbnailStore.swift:137`, `VaultSession+Identity.swift:96` and
`PraticaSyncEngine+Attachments.swift:49` hash other data and are unaffected.

**Done when:** every test above passes and the whole unit bundle is green.

### Task 3 — JSON Canvas carries what it cannot read, and reconciliation never traps (R-06, R-07, R-08, R-09, R-23)

**Files:**

- `Sources/Core/Canvas/JSONCanvas.swift`
- new `Sources/Core/Canvas/CanvasOpaqueElement.swift`, if `JSONCanvas.swift` would pass 400 lines
- `Sources/Core/Canvas/CanvasReconciliation.swift`
- `Sources/Features/Workspace/CardTextStyle.swift`
- `Sources/Features/Workspace/StickyTextCard.swift`
- new `Tests/CanvasRoundTripTests.swift`
- `Tests/CanvasReconciliationTests.swift`
- `Tests/WorkspaceAutosaveRaceTests.swift`
- `Tests/FormatEdgeCorpus.swift` (canvas cases)
- `Tests/FormatEdgeCorpusTests.swift`

#### Tester

1. Add `case unrecognised(String)` to `CanvasColor`, with arms in every exhaustive switch:
   - `rawValue` (`JSONCanvas.swift:96-97`) returns the string;
   - `CardTextStyle.rgba(for:)` (`CardTextStyle.swift:73`) returns `nil`;
   - `StickyTextCard.stickyColor` (`StickyTextCard.swift:128`) returns `theme.color(.stickyGrey)`.
2. Add `struct CanvasOpaqueElement: Equatable, Sendable { var index: Int; var value: JSONValue }`.
   Add `opaqueNodes` and `opaqueEdges: [CanvasOpaqueElement]` to `CanvasDocument`, with defaulted
   parameters on `init(nodes:edges:unknown:)` so every call compiles.
3. Add `case notAList(String)` to `CanvasDocument.DecodingError`, with its `description` line.
4. The decode produces none of these yet.
5. Run `tuist generate --no-open`.
6. The fixtures are JSON text in the corpus. A test canonicalises a fixture once, through
   `JSONSerialization` with the codec's options (`JSONCanvas.swift:66-69`), and compares
   `encoded()` to those bytes: that is what "round-trips" means for `.canvas` (ADR-0065 §Context).

| Test | Asserts | Today |
|---|---|---|
| `anUnknownTypeNodeKeepsEveryPayloadKey` | an `embed` node with `url`, `label` and `text` re-encodes to the canonical original (R-06) | red |
| `aKnownKindKeepsAnotherKindsKey` | a `text` node carrying `url` keeps it (R-06) | red |
| `anUnrecognisedNodeColourRoundTrips` | `"7"`, `"#GGG"` and `"red"` come back as the same strings, and `isNote` is true for each (R-07) | red |
| `anUnrecognisedEdgeColourRoundTrips` | the same, on an edge (R-07) | red |
| `anUnderstoodColourStillParses` | `"3"` gives `.preset(3)` and `"#FF0000"` gives `.hex` (R-07) | green, pins |
| `aNonStringColourOrLabelIsKept` | a node's `"color": 3` and an edge's `"label": 7` survive (G1.7) | red |
| `anUnrecognisedEdgeSideOrEndIsKept` | `"toEnd": "diamond"` and `"fromSide": "centre"` survive (G1.7) | red |
| `aNodeWithoutIdOrTypeIsWrittenBackInPlace` | `nodes: [A, {type,text}, {id}, B]` encodes to the same array, in the same order (R-08) | red |
| `anEdgeWithoutEndpointsIsWrittenBackInPlace` | the same for `edges` (R-08) | red |
| `aNonObjectElementDoesNotEmptyTheBoard` | for `nodes: [A, 42, B]`, `document.nodes` ids are `[A, B]` and the encoded nodes are `[A, 42, B]` (R-08) | red |
| `opaqueElementsSurviveAnEdit` | deleting A and appending C keeps every opaque element, in its original relative order (R-08) | red |
| `aNodesValueThatIsNotAListIsRefused` | `{"nodes": {}}` throws `.notAList("nodes")`, `{"edges": "x"}` throws `.notAList("edges")`, and `{}` decodes empty (R-23, G1.6) | red |
| `aBoardWhoseNodesAreNotAListRecordsAProblem` | through `WorkspaceAutosaveRaceTests`' `openedWorkspaceController`/`CanvasTemporaryRoot`, opening that board records one problem that names it (`WorkspaceController.swift:311-312`) (R-23) | red |
| `aDuplicateIdBoardOpensAndReencodes` | two nodes with id `a` both decode and both encode (SPEC decision) | green, pins |
| `anOpaqueChangeByTheirsDiverges` | `base` and `theirs` differ only in an opaque element, so the result is `.diverged` (ADR §D6.3) | red, no trap |
| `aReencodingOnlyRefusalStillAdopts` | `base == theirs`, both with duplicate ids, gives `.adopted(mine)` (ADR §D6.2) | green, pins (the early return precedes the trapping dictionaries) |

7. Add the canvas cases to `everyCorpusCaseRoundTripsOrIsRefused` (R-23).

#### Coder

1. `CanvasNode.init?` consumes per kind; `CanvasEdge.init?` consumes an optional key only when it is
   understood; colours go through `CanvasColor(raw) ?? .unrecognised(raw)` for string values
   (ADR-0065 §D5.1-§D5.3).
2. `CanvasDocument.init(data:)`:
   - iterates `as? [Any]`, keeping every element it cannot read as a `CanvasOpaqueElement`;
   - throws `.notAList` for a present non-array value (G1.6).

   `encoded()` re-inserts the opaque elements in ascending index, clamped (§D5.4-§D5.5).
3. `reconcile(mine:base:theirs:)`, after the early return:
   - checks all three documents for duplicate node and edge ids, and diverges naming each duplicated
     id once;
   - diverges on any opaque-element difference between `base` and `theirs` (§D6).
4. **Rule 1:** in this same commit, write the tests that trap today:

| Test | Asserts |
|---|---|
| `reconcilingDuplicateNodeIdsDiverges` | with `base != theirs` and two nodes `a` in `base`, the result is `.diverged` naming `a` once (R-09) |
| `reconcilingDuplicateEdgeIdsDiverges` | the same, for edges (R-09) |
| `aDuplicateIdInTheirsAloneDiverges` | only `theirs` carries the duplicate (R-09) |
| `aDuplicateIdBoardGoesConflictedWithOneProblem` (in `WorkspaceAutosaveRaceTests`) | a board with duplicate node ids is opened, there is a pending edit, and an external write changes the bytes: `saveState == .conflicted`, the problem count grows by exactly one, and the test host is still alive (R-09) |

**Contract-change call sites.**

- New `CanvasColor` case: the three switches above. `CanvasColor ==` comparisons in the colour
  pickers simply match no swatch for an unrecognised value.
- New `CanvasDocument` fields: the synthesized `Equatable` now compares them, which is the reason
  `aReencodingOnlyRefusalStillAdopts` exists.
- The existing suites that must stay green: `CanvasTests` (including
  `roundTripsAnObsidianCanvas`), `CanvasStoreTests`, `CanvasReconciliationTests`,
  `WorkspaceAutosaveRaceTests`, `CanvasDuplicateTests` and `CanvasCropTests`.

**Done when:** every test above passes and the whole unit bundle is green.

### Task 4 — Mail decoding (R-10, R-11, R-12, R-13, R-23)

**Files:**

- `Sources/Core/Email/HTMLTextReducer.swift`
- new `Sources/Core/Email/MailCharset.swift`
- new `Sources/Core/Email/MIMEParameter.swift`
- `Sources/Core/Email/MIMEDecoder.swift`
- `Sources/Core/Email/EmailHeaders.swift`
- new `Tests/MailFormatEdgeTests.swift`
- `Tests/FormatEdgeCorpus.swift` (mail cases)
- `Tests/FormatEdgeCorpusTests.swift`

#### Tester

1. Declare `enum MailCharset { static func encoding(for charset: String) -> String.Encoding }`. Its
   placeholder is the **union** of today's two tables (`MIMEDecoder.swift:~285-295`,
   `EmailHeaders.swift:215-224`), with ISO-8859-15 still mapped to `.isoLatin2`.
2. Declare `enum MIMEParameter { static func value(_ name: String, in raw: String) -> String? }`.
   Its placeholder is today's `parameter(_:of:)` body (`MIMEDecoder.swift:191-203`).
3. Nothing calls either declaration yet.
4. Run `tuist generate --no-open`.

| Test | Asserts | Today |
|---|---|---|
| `anUnclosedAnchorKeepsTheTextAfterIt` | `<p>Vedi <a href="https://x">Preventivo 2026 allegato` reduces to text that contains `Preventivo 2026 allegato` (R-10) | red |
| `anUnclosedCellKeepsTheTextAfterIt` | `<table><tr><td>Totale<td>1.250,00` keeps both `Totale` and `1.250,00` (R-10) | red |
| `nestedUnclosedTagsKeepTheirOrder` | `<td>A <a href="x">B` puts `A` before `B` (R-10) | red |
| `latin9PartDecodesTheEuroSign` | `MIMEDecoder.decodeText(Data([0x31, 0x20, 0xA4]), transferEncoding: nil, charset: "ISO-8859-15") == "1 €"` (R-11) | red |
| `latin9HeaderDecodesTheEuroSign` | `EncodedWord.decode("=?ISO-8859-15?Q?1.250,00_=A4?=") == "1.250,00 €"` (R-11) | red |
| `latin9AliasesAgree` | `ISO-8859-15`, `iso-8859-15`, `ISO_8859-15` and `LATIN9` give the same encoding, and `ISO-8859-2` is still Latin-2 (R-11) | red |
| `everyOldAliasStillMaps` | every alias of both old tables maps as before (R-11 regression) | green, pins |
| `adjacentEncodedWordsJoin` | `=?UTF-8?Q?artic?= =?UTF-8?Q?oli?=` decodes to `articoli` (R-12) | red |
| `aFoldedSubjectHasNoSpaceMidWord` | `EmailHeaderParser.parse` of a `Subject:` folded with `\r\n ` between two encoded-words gives `Preventivo fornitura articoli tecnici` (R-12) | red |
| `anEncodedWordBesidePlainTextKeepsItsSpace` | `=?UTF-8?Q?Ciao?= mondo` decodes to `Ciao mondo` | green, pins |
| `aFailingWordKeepsItsSpace` | an undecodable word stays raw, and so does the space next to it | green, pins |
| `aBWordWithoutPaddingDecodes` | `=?UTF-8?B?Y2lhbw?=` decodes to `ciao` (R-12) | red |
| `anRFC2231FilenameWithCharsetDecodes` | `MIMEParameter.value("filename", in: "attachment; filename*=UTF-8''Preventivo%20%E2%82%AC.pdf") == "Preventivo €.pdf"` (R-13) | red |
| `continuedRFC2231SegmentsJoin` | `filename*0*=UTF-8''Relazione%20; filename*1*=finale.pdf` gives `Relazione finale.pdf`, and so does the quoted, unencoded `filename*0`/`filename*1` form (R-13) | red |
| `aQuotedSemicolonDoesNotSplit` | `attachment; filename="Report; finale.pdf"` gives `Report; finale.pdf` (R-13) | red |
| `theExtendedFormWins` | when both `filename` and `filename*` are present, the result is the extended value (R-13) | red |
| `boundaryAndCharsetStillParse` | a quoted boundary containing `;` parses whole, and `charset=utf-8` still parses (R-13 regression) | red for the first, green for the second |
| `anRFC2231NameReachesTheAttachment` | `MIMEDecoder.decode` of a message carrying such a part gives `filename == "Preventivo €.pdf"`, extension `pdf` (R-13) | red |

5. Add the mail cases to `everyCorpusCaseRoundTripsOrIsRefused`: an input format passes when it
   decodes to the expected value (ADR-0065 §Context) (R-23).

#### Coder

1. `HTMLTextReducer.finished()` folds pending buffers innermost-first, as the matching close would
   (ADR-0065 §D7.1).
2. `MailCharset` maps Latin-9 through Core Foundation. Both private tables are deleted and their
   callers use `MailCharset` (§D7.2).
3. `EncodedWord.decode` applies §6.2, and `decodeToken` normalises B padding (§D7.3). The unfold at
   `EmailHeaders.swift:76` is not touched.
4. `MIMEParameter` implements quoting, RFC 2231 and continuations. `parameter(_:of:)` is deleted, and
   its four call sites (`MIMEDecoder.swift:42,72,73,101`) use `MIMEParameter` (§D7.4).

**Done when:** every test above passes, the existing `HTMLTextReducerTests`, `MIMEDecoderTests`,
`EmailTests` and every Pratiche sync test that reads `EmailFixtureCorpus` stay green, and the whole
unit bundle is green.

### Task 5 — The message document: exact escaping and the sender's offset (R-14, R-15)

**Files:**

- `Sources/Core/Pratiche/MessageDocument.swift`
- `Sources/Core/Pratiche/MessageDocument+Reading.swift`
- `Sources/Core/Email/EmailHeaders.swift`
- `Sources/Features/Pratiche/PraticaSyncEngine+Messages.swift` (one argument at `:542-562`)
- `Tests/MessageDocumentTests.swift`
- `Tests/MailFormatEdgeTests.swift`
- the Pratiche sync test file that already drives `PraticaSyncEngine` over `EmailFixtureCorpus`; the
  tester picks it from `Tests/PraticaSync*Tests.swift`
- `Tests/FormatEdgeCorpusTests.swift`

#### Tester

1. Declare `static func offset(of raw: String) -> Int?` on `RFC5322Date`, with placeholder `nil`.
2. Add `var dateOffset: Int? = nil` to `EmailHeaders`, and compare it in the hand-written `==`
   (`EmailHeaders.swift:20-25`).
3. Add `var dateOffset: Int? = nil` to `MessageDocument.MailFrontmatter`. The memberwise calls keep
   compiling: `MessageDocument+Reading.swift:19`, `PraticaSyncEngine+Messages.swift:542`, and the
   test fixtures in `MessageAttachmentPatchTests`, `PraticaSyncRepairTests`,
   `PraticheConnectorTests` and `VaultBoundaryCallSiteTests`.

| Test | Asserts | Today |
|---|---|---|
| `aBackslashNSubjectRoundTrips` | a subject `C:\nuovo` (backslash, `n`): render → parse gives the same subject, and rendering again is byte-identical (R-14) | red |
| `escapeAndUnescapeAreInverses` | table of subjects: `a"b`, `x\\y`, a real line break, a literal `\\n`, a trailing `\`, and `\t` each round-trip (R-14) | red for the backslash cases |
| `numericZoneOffsets` | `+0900` gives 32400, `-0500` gives -18000, `+0000` gives 0, and `-0000` gives `nil` (R-15) | red |
| `obsoleteZoneNames` | `GMT` and `UT` give 0; `EST` -18000; `EDT` -14400; `PST` -28800; `PDT` -25200; `CEST` and `A` give `nil` (R-15) | red |
| `aTrailingCommentDoesNotHideTheOffset` | `… +0200 (CEST)` gives 7200 (R-15) | red |
| `theHeaderParserRecordsTheOffset` | `EmailHeaderParser.parse` of a `Date: … +0900` header gives `dateOffset == 32400` (R-15) | red |
| `theMailDateCarriesTheSendersOffset` | the instant 2026-09-26T01:00:00Z with `dateOffset` 32400 renders `pergamenum-mail-date: 2026-09-26T10:00:00+09:00` (R-15) | red on this machine and on CI |
| `theMailDateWithoutAnOffsetIsUTC` | `dateOffset == nil` renders `…T01:00:00Z` (R-15) | red |
| `theMailDateSurvivesParseAndRender` | render → parse → render is identical, the parsed `dateOffset` is 32400, and `Z` reads back as `nil` (R-15, R-14) | red |
| `receivedIsWrittenInUTC` | the `pergamenum-mail-received` line ends in `Z` (G1.5) | red |
| `aSyncedMessageCarriesTheHeaderOffset` | in the sync harness, a fixture whose `Date` carries `+0900` writes a message file whose date line ends in `+09:00`, and a fixture with no `Date` header writes `Z` (R-15) | red |

Add the message-document cases to `everyCorpusCaseRoundTripsOrIsRefused` (R-23).

#### Coder

1. `unquoted` becomes a single left-to-right scan (ADR-0065 §D8.1).
2. `RFC5322Date.offset(of:)` follows §D8.2's table. `EmailHeaderParser.parse` sets `dateOffset` from
   the raw `Date` field.
3. The sync passes `dateOffset` only when `headers.date` is the source
   (`PraticaSyncEngine+Messages.swift:360`), and passes `nil` for a zero offset.
4. `isoString` takes the offset: `TimeZone(secondsFromGMT:)`, or UTC. Reading sets `dateOffset` from
   the stored string, with `Z` giving `nil`.
5. G1.5: `received` is written in UTC.

**Contract-change call sites.** `rg` finds no test that asserts a rendered `pergamenum-mail-date`
string. The fixtures that feed one in as input (`PraticaLinksWriterTests:127`,
`PraticaLinkAggregationTests:115`, `PraticaLinkCommandTests:33`, `PraticheLinksConnectorTests:34`)
parse `+02:00` and stay green.

**Done when:** every test above passes and the whole unit bundle is green.

### Task 6 — Task text, inline embeds, the related section, rename and link targets (R-01, R-16, R-17, R-18, R-19, R-20, R-21)

**Files:**

- `Sources/Core/Tasks/TaskParser.swift`
- `Sources/Core/Markdown/MarkdownInline.swift`
- `Sources/Features/Editor/MarkdownBlocksView.swift`
- `Sources/Core/Conventions/Wikilink.swift`
- `Sources/Core/Conventions/NoteExport.swift`
- `Sources/Core/Conventions/RelatedLink.swift` (G1.4 and R-01)
- `Sources/Core/Conventions/NoteRename.swift`
- `Sources/Vault/NoteStore+ReadSurface.swift`
- `Sources/Core/Markdown/Transclusion.swift`
- new `Tests/TextFormatEdgeTests.swift`
- new `Tests/RelatedSectionTests.swift`
- `Tests/NoteRenameCharacterizationTests.swift`
- `Tests/TransclusionTests.swift` (additions only; `:33-35` stay as they are)

#### Tester

1. Add `case embed(target: String)` to `MarkdownSpan.Link`. Add an arm in `MarkdownBlocksView.swift:245`
   that renders it like `.note`.
2. Declare `static func sectionRange(in body: String) -> Range<String.Index>?` on `RelatedSection`,
   with a placeholder that keeps today's `body.range(of: heading)` behaviour.
3. Declare `func retitled(_ newTitle: String) -> Wikilink` on `Wikilink`, with a placeholder that sets
   `target`.
4. Declare `static let noteExtensions: Set<String> = ["md"]` and `static let fileExtensions:
   Set<String>` on `Transclusion`. Tests iterate these sets, so they are part of the contract. The
   proposed `fileExtensions`, which the reviewer may prune:
   - images: `png jpg jpeg gif webp heic heif tif tiff bmp svg avif`
   - documents: `pdf`
   - audio: `mp3 m4a wav aac flac ogg`
   - video: `mp4 mov m4v webm mkv avi`
   - office and data: `doc docx xls xlsx ppt pptx key pages numbers odt ods odp rtf txt csv tsv json
     xml html htm`
   - archives: `zip gz tar 7z rar dmg`
   - mail and calendar: `eml emlx msg ics vcf`
   - `canvas`
   - other apps' formats: `drawio excalidraw sketch webarchive`

   `isNoteReference` does not read them yet.

| Test | Asserts | Today |
|---|---|---|
| `aPrefixTagLeavesNoResidue` | `TaskParser.displayText(from: "Rivedere offerta #topic-forni e #topic-forni-tunnel")` has no `-tunnel`, and equals today's whitespace rule applied to "Rivedere offerta e" (R-16) | red |
| `aLongerTagFirstLeavesNoResidue` | the same tags, in the opposite order (R-16) | green, pins |
| `anInlineEmbedHasNoOrphanBang` | the spans of `Vedi ![[foto.png]] qui` contain no `!`, and one span is `.embed(target: "foto.png")` (R-17) | red |
| `aSizedEmbedShowsItsReference` | `![[foto.png\|300]]` has the text `foto.png` (R-17) | red |
| `anEmbedInAHeadingOutlinesAsItsReference` | the `NoteOutline` of `## ![[schema.png]]` gives the heading title `schema.png` (R-17) | red |
| `aMarkdownImageIsStillALink` | `![alt](x.png)` gives `.url("x.png")` | green, pins |
| `aWikilinkIsStillANoteLink` | `[[Nota]]` gives `.note(title: "Nota")` | green, pins |
| `aBoardMarkerIsNotALinkTarget` | `NoteStore.linkTargets(in:)` of `- [ ] x ^[[Q4.canvas]]`, and of a plain `[[Q4.canvas]]`, excludes `Q4.canvas` (R-20) | red |
| `aTranscludedNoteIsStillALinkTarget` | `![[Nota]]` and `![[Nota.md]]` are included (R-20 regression; ADR-0010 §D7) | green, pins |
| `aCanvasIsNotANoteReference` | `Transclusion.isNoteReference("Q4.canvas")` is false (R-20) | red |
| `everyListedExtensionDecides` | `isNoteReference("x.<ext>")` is false for every `fileExtensions` member and true for every `noteExtensions` member (R-20) | red for the long ones |
| `nfdAndNfcNamesResolveToTheSameBoard` | `WorkspaceBoardResolver` resolves an NFD `Città.canvas` from an NFC marker (R-21) | green, pins |
| `nfdAndNfcTitlesMatchInRename` | `NoteRename.rewritingLinks` rewrites an NFD link given the NFC old title (R-21) | green, pins |
| `nfdAndNfcMatchInTransclusion` | `Transclusion`'s section and note matching treats NFD and NFC as the same (R-21) | green, pins |

`RelatedSectionTests.swift`:

| Test | Asserts | Today |
|---|---|---|
| `theExactHeadingIsFound` | `## Note correlate` followed by one bullet: `parse` gives that bullet (R-18) | green, pins |
| `aSubHeadingIsNotTheSection` | `### Note correlate operative` with a bullet: `parse` is empty and export keeps it (R-18) | red |
| `aMidSentenceMentionIsNotTheSection` | `Vedi ## Note correlate sotto` (R-18) | red |
| `trailingSpacesAndCRAreTolerated` | `"## Note correlate  \r\n\r\n- [[A]] — r\r\n"` gives `[A]` (R-18) | red |
| `theLinterInventsNoDiscrepancyFromASubHeading` | `session.violations(path:title:text:)` on a note with `related [A]` and bullets under `### Note correlate operative` reports only the real discrepancy (R-18) | red |
| `exportOfACRLFNoteStopsAtTheNextHeading` | `NoteExport.markdown` of a CRLF note keeps the `## Altro` that follows the section (R-18) | red |
| `collegaWritesUnderTheExactHeadingOnly` | `RelatedLink.add` on a note that has only `### Note correlate operative` creates a `## Note correlate` section and leaves the sub-heading's bytes untouched (G1.4) | red |
| `collegaOnACRLFNoteKeepsCRLF` | `RelatedLink.add` on `crlfWithFrontmatter`: every line ends in `\r\n`, one block (R-01) | red |
| `unlinkOnACRLFNoteKeepsCRLF` | the same, for `RelatedLink.remove` (R-01) | red |

`NoteRenameCharacterizationTests.swift` additions:

| Test | Asserts | Today |
|---|---|---|
| `renameRewritesABoldWikilinkInsideItsMarkers` | `[[**Forno tunnel**]]` becomes `[[**Nuovo nome**]]`, the `~~` and `*` forms likewise, and `[[**Forno tunnel**#Sez\|alias]]` keeps `#Sez\|alias` (R-19) | red |
| `renameCountsTheBoldLink` | when a vault's note links only through the bold form, `NoteFileOperations.renamePlan`'s `rewrittenPaths` contains that note (R-19) | red |
| `aTitleThatOnlyContainsEmphasisIsUntouched` | `[[**Forno tunnel** vecchio]]` is not matched | green, pins |

#### Coder

1. `displayText` removes each tag by its range, from the end backwards (ADR-0065 §D9.1).
2. `MarkdownInlineParser` recognises `![[` first, and the span's text is the reference (§D9.2).
3. `RelatedSection.sectionRange(in:)` implements the anchored, `\r`-tolerant locator, walking lines
   below the grapheme level. `RelatedSection.parse`, `NoteExport.strippingRelatedSection` and
   `RelatedLink.addBullet`/`removeBullet` use it (G1.4). «Collega» ends its bullets and any new
   heading in the document's line break, using `NoteDocument`'s `LineBreak` from Task 1 (R-01, §D9.3).
4. `NoteRename.rewritingLinks` matches on `fold(resolvedTitle)` and writes through
   `Wikilink.retitled` (§D9.4).
5. `NoteStore.linkTargets(in:)` excludes `canvas` targets. `isNoteReference` decides by the two sets
   first, then by today's shape rule (§D9.5).

**Contract-change call sites.**

- `linkTargets` narrowing:
  - `IndexSnapshot.swift:79` (backlinks), `:137` (neighbourhood), `:157` (orphans);
  - `VaultReads.swift:32-33` (the connector's resolved and unresolved lists);
  - `VaultPayloads.swift:30`;
  - `ViewField.swift:172` (`links`);
  - `ViewEvaluator.swift:179,242,249`.

  `rg` finds no test that pins a `.canvas` link target. The suites that exercise these sites stay
  green: `SearchTests`, `ViewEvaluatorTests`, `VaultTests`, `NoteStoreReadTests`,
  `TaskArrangementTests` and `TaskMarkerLintTests`.
- `isNoteReference`: `Transclusion.swift:33`, `NoteStore+ReadSurface.swift:31`,
  `MarkdownAttributedText.swift:191`, `CardTextAttributes.swift:173`, and
  `TransclusionTests.swift:33-35`, which stays unchanged.
- `MarkdownSpan.Link`: `MarkdownBlocksView.swift:245` is the only exhaustive switch.
  `NoteOutline.swift:93` joins text.

**Done when:** every test above passes and the whole unit bundle is green.

### Task 7 — Frontmatter damage becomes an advisory lint finding (R-22)

**Files:**

- `Sources/Core/Conventions/Frontmatter.swift` (`FrontmatterViolation`, `FrontmatterRules.validate`)
- `Sources/Core/Conventions/ConformanceText.swift`
- new `Tests/FrontmatterDamageLintTests.swift`
- `Tests/ConformanceTextTests.swift`

#### Tester

1. Add `case secondFrontmatterBlock`, `case duplicateKey(String)` and `case lineWithoutColon(String)`
   to `FrontmatterViolation`.
2. Add their arms to `ConformanceText.frontmatterLines` (`ConformanceText.swift:36`), in Italian:
   - «Secondo blocco frontmatter all'inizio del corpo»
   - «Chiave ripetuta nel frontmatter: \(name)»
   - «Riga del frontmatter senza due punti: \(line)»
3. `validate` does not produce the new cases yet.
4. Tests go through `VaultSession.violations(path:title:text:)` (`VaultSession+Search.swift:106`), in
   `CategoryLintTests.swift`'s shape.

| Test | Asserts | Today |
|---|---|---|
| `aSecondBlockIsReported` | `damagedDoubleBlock` gives `.secondFrontmatterBlock` (R-22) | red |
| `aSecondBlockAfterATextBorneBOMIsReported` | `"---\n---\n\u{FEFF}---\r\ndate: …"` (R-22) | red |
| `aHorizontalRuleIsNotASecondBlock` | a body that opens with `---`, text, `---` and no key line: not reported | green, pins |
| `aDuplicatedKeyIsReportedOnce` | `duplicateTags` gives exactly `[.duplicateKey("tags")]`; `duplicateForeign` gives `.duplicateKey("cssclass")` once (R-22) | red |
| `aColonlessLineIsReportedAndABlankLineIsNot` | `colonlessAndBlankLines` gives only `.lineWithoutColon("solo testo")`; `yamlComment` gives `.lineWithoutColon("# importato da Plaud")` (R-22) | red |
| `aConformantNoteHasNoDamageFindings` | `lfConformant` gives none of the three (R-22) | green, pins |
| `theLintFindingShapeIsUnchanged` | the encoded `VaultAPI.LintFinding` of a damaged note has the same top-level JSON keys as a clean note's, and its `frontmatter` array holds `duplicateKey("tags")` (R-22) | red on the string |
| `aDamagedNoteDoesNotBlockADrop` | a board drop and a task drop onto a note carrying all three damages, in the `BoardDropTests`/`TaskDropTests` shape, are not refused (R-22) | green, pins |
| `conformanceTextNamesTheNewFindings` (in `ConformanceTextTests`) | the three Italian lines (R-22) | green once the tester's arms land; pins the wording |

#### Coder

`FrontmatterRules.validate` produces the three cases from `document.source`, only when the note has
a block, under the exact conditions of ADR-0065 §D11. Blocking is untouched: it reads `.tags` only
(`VaultSession+TaskDrop.swift:66-72`, `VaultSession+BoardDrop.swift:58-59`).

**Done when:** every test above passes and the whole unit bundle is green.

### Task 8 — The index cache, the corpus sweep, and the records (R-23, R-24)

**Files:**

- `Sources/Index/IndexCache.swift` (G1.1)
- `Tests/IndexCacheTests.swift`
- `Tests/FormatEdgeCorpusTests.swift`
- `ROADMAP.md`
- `CLAUDE.md` (the chain-index line)
- `docs/adr/0065-format-round-trip-faithful-or-refused.md` (status and implementation notes)

#### Tester

| Test | Asserts | Today |
|---|---|---|
| `aCacheStampedFourIsNotReused` (in `IndexCacheTests`) | a cache whose `user_version` is 4 loads as empty (`IndexCache.swift:43-46`) (G1.1) | red until the bump |
| `everyCorpusCaseRoundTripsOrIsRefused`, final form | every case of every format either round-trips byte-identical or is refused with a named error or a recorded problem; none is dropped (R-23). The byte-level BOM cases go through `NoteStore.write`/`read` in a temporary directory | green at the end of this task |

If `IndexCacheTests` has no helper to stamp a version, the first test is dropped. The reviewer then
reads the one-line diff, which is how ADR-0047's bump was verified.

#### Coder

1. If G1.1 passes, set `IndexCache.schemaVersion` to 5, through the protected-interface hook (see
   «Before `/build`», item 4).
2. `ROADMAP.md` §Chain 1: mark it shipped, with the PR number (R-24).
3. ADR-0065:
   - set its status to accepted, with the G1 answers;
   - add «Implementation notes» covering the departures from this plan, the result of the
     platform-decode characterization, and the red or green state recorded for each corpus case.
4. `CLAUDE.md`: add the chain-index entry proposed at the end of ADR-0065.
5. With Stefano's OK, file ADR-0065 §D13's items as issues. `TODO.md` `PG-254` is closed by the
   repo's usual after-merge `chore(tasks)` sync, not on this branch.

**Done when:**

- the whole unit bundle is green;
- `scripts/uitests.sh --status` has been read;
- `--affected` has been run for the merge;
- the ADR and the ROADMAP match what shipped.

---

## Requirement coverage

| R-id | Task(s) |
|---|---|
| R-01 | 1, 2, 6 |
| R-02 | 2 |
| R-03 | 1 |
| R-04 | 1 |
| R-05 | 1 |
| R-06 | 3 |
| R-07 | 3 |
| R-08 | 3 |
| R-09 | 3 |
| R-10 | 4 |
| R-11 | 4 |
| R-12 | 4 |
| R-13 | 4 |
| R-14 | 5 |
| R-15 | 5 |
| R-16 | 6 |
| R-17 | 6 |
| R-18 | 6 |
| R-19 | 6 |
| R-20 | 6 |
| R-21 | 6 |
| R-22 | 7 |
| R-23 | 1, 2, 3, 4, 8 |
| R-24 | 8 (documentation obligation; no test) |

## Departures / open points

1. **R-03's "after the valid tags"** holds whenever the app writes the tags key. An untouched tags key
   stays byte-identical instead, under R-05's rule (ADR-0065 §D1.7). The tag is never dropped either
   way.
2. **The SPEC's data model says the frontmatter document carries "BOM presence".** Here the document
   carries it only when its text does, and otherwise the file carries it (ADR-0065 §D4). R-02's
   requirement is met, and so is the SPEC's own Test seam 2, which is what points at the write door.
3. **R-23's "round-trips" is read per format.**
   - Notes and message documents: byte-identical.
   - `.canvas`: identical to the codec's canonical encoding, which already holds for every foreign
     layout today (ADR-0054).
   - Mail input: decodes to the expected value.
4. **Folded in under R-08 without a gate:** a `nodes`/`edges` element that is not an object at all.
   The SPEC's default covers it, and today it empties the whole board.
5. **Gated extensions (G1.3-G1.7)** are listed in «Before `/build`».
6. **Named and not fixed** (ADR-0065 §D13), to be filed in Task 8:
   - CRLF line walks at the `Character` level in the editor styler, `NoteOutline` and `NoteExport`;
   - `DossierYAML` keyword escaping;
   - the delimiter tests in `MessageFrontmatterPatch` and `ViewCatalogue`;
   - canvas required keys with a wrong JSON type;
   - `## Note correlate` inside a code fence;
   - `JSONValue`'s `Double` precision;
   - a `.canvas` with a BOM.
7. **The SPEC's assumption that a sync never renames a message file was verified and holds**
   (`PraticaSyncEngine+Messages.swift:521-535`; ADR-0065 §Context). One nuance: a message whose file
   was deleted, or no longer parses, is written as a new file under today's decoding.

## Risks and HITL gates

- **The lossless serializer is the riskiest change.** Every in-app write of an existing note goes
  through it.
  - The mitigations are the corpus, the full unit bundle after Task 1, and a reviewer who reads the
    output of every writer test listed in Task 1's call sites.
  - `pratica.md` keys now keep the file's order rather than the codec's list order (ADR-0065 §D2).
    `DossierWriterTests` may pin the codec order. If a test pins the order of an **untouched** key,
    that goes to G2.
- **The platform decode of a BOM was not executed.** ADR-0065 §D4 holds either way, and Task 2's
  characterization test records the answer.
- **`components(separatedBy: "\n")` versus `Character`.** A new line walk written with the
  `Character` API would silently merge CRLF lines. The CRLF corpus cases in Tasks 1 and 6 catch it.
- **G1.1 means a full rescan at first launch.** Its duration on the Labs vault was not measured.
- **One extra three-byte read per note write** (`NoteStore.write`, §D4.3). For session writes it
  happens inside the `VaultDisk` actor, and it is negligible next to the atomic write.
- **Dependencies:** none external. No third-party library is involved, so no Context7 lookup was
  needed. The one platform behaviour that matters was read from swift-foundation's source on
  2026-09-26 and is pinned by a test. No externally provisioned resource, env var or port is
  needed.
- **HITL:**
  - G1, G2, and the protected-interface hook for G1.1;
  - commit, push and merge;
  - filing the follow-up issues.

  No DB schema change beyond the cache version (principle 3: rebuildable). No deletion of user
  data.
- **Full suite:** the `Stop` hook runs the whole `PergamenumTests` bundle every turn, which is the
  full-suite run this chain's contract changes call for. At merge, run
  `scripts/uitests.sh --affected` (CLAUDE.md). The chain adds no GUI test.

TEST-CMD CANDIDATE: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`
TEST-CMD MODE: brownfield
