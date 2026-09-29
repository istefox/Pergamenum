# Fix: two frontmatter readers find a CRLF `---\r` delimiter the way the note parser does (PG-276)

No `SPEC.md` governs this task. The repo-root `SPEC.md` belongs to `PG-260`'s chain, merged in
PR #662, and `BRAINSTORM.md`/`UX-BLUEPRINT.md` belong to other features; none of the three is this
chain's input. The brief is the `PG-276` entry in `TODO.md` (#615, P2, kind:fix), which ADR-0065
§D13.3 names and leaves open. The acceptance criteria are declared here as eight requirement ids.

The plan was read at `549d6dbe` (`HEAD`). `origin/main` is at `3a0d49b2`, and the two differ only in
`TODO.md` (`git diff --stat HEAD origin/main`). Every line number below was read from that tree.

## What is already settled, and not reopened

ADR-0065 (accepted) governs. Registered as it stands:

- **§D1.2: how a frontmatter line is interpreted.** Each line of a text split on `"\n"` is read
  with one trailing `\r` removed; on the text's first line, one leading U+FEFF is removed too. The
  line is still emitted exactly as it was read.
- **§D3: line endings.** Existing lines keep their own ending, so a mixed file stays mixed. A line
  the app writes ends in the document's line break, which is the text's first line break (CRLF if
  it is `\r\n`, LF otherwise). §D3 already applied this to `TagRename` (G1.3): "the delimiter test
  tolerates one trailing `\r`; inserted lines end in the document's line break."
- **§D1.3.1: an unchanged key is emitted verbatim.** The note serializer rewrites only what
  changed.
- **§D11: the second-block lint.** "The body's first line is `---` once one leading U+FEFF and one
  trailing `\r` are removed."
- **§D13.1 is not this chain.** `Character`-level line walks (`MarkdownStyler`, `NoteOutline`,
  `NoteExport`) are `PG-274` (#613).

§D13.3 names the defect: "`MessageFrontmatterPatch.swift:24-26` (app-written files) and
`ViewCatalogue.swift:78,83` keep the whitespace-only delimiter test." This plan applies §D1.2 and
§D3 to those two readers. It changes no rule.

## The rule, as the note parser has it

`NoteDocument.parse` → `FrontmatterSource.document(from:)` (`FrontmatterSource.swift:82-117`):

1. Split with Foundation's `components(separatedBy: "\n")`, so a CRLF line arrives with its `\r`.
2. Interpret each line with `FrontmatterSource.interpreted(_:isFirst:)` (`:66-73`): one trailing
   `\r` removed; on line 0 only, one leading U+FEFF removed.
3. A delimiter is `FrontmatterSource.isDelimiter(_:)` (`:75-77`): the interpreted line, trimmed of
   `CharacterSet.whitespaces`, equals exactly `---`. `.whitespaces` is Unicode General Category Zs
   plus U+0009 (Apple's documentation for `CharacterSet.whitespaces`, read 2026-09-28), so it
   removes spaces, tabs and U+00A0, and never `\r` (Cc) or U+FEFF (Cf).
4. The opening is line 0; the closing is the **first later** delimiter line. An opening with no
   closing is no block: the whole text is body (`:93-99`).

`TagRename.frontmatterEnd(of:)` (`TagRename.swift:165-172`) composes the same two helpers the same
way. What that means per line, each line written as a Swift literal of the `"\n"` split:

| Line | As the opening (line 0) | As the closing (a later line) |
|---|---|---|
| `"---"` | delimiter | delimiter |
| `"--- "`, `"\t---"`, `"  ---  "`, `"\u{00A0}---"` | delimiter | delimiter |
| `"---\r"`, `"--- \r"`, `"\t---\r"` | delimiter | delimiter |
| `"\u{FEFF}---"`, `"\u{FEFF}---\r"` | delimiter | **not** a delimiter |
| `"---\r\r"` (two `\r`) | not a delimiter | not a delimiter |
| `"----"`, `"--- x"`, `"-- -"` | not a delimiter | not a delimiter |
| an opening with no closing line | no block, the whole text is body | — |

This table is R-03's definition of "no looser, no stricter".

## The defect, as the code has it

**`MessageFrontmatterPatch.applying(line:forKey:before:to:)`** (`MessageFrontmatterPatch.swift:22-44`)
tests `lines.first?.trimmingCharacters(in: .whitespaces) == "---"` and the same for the closing
(`:24-27`), with no `\r` or U+FEFF removal. On a CRLF message file it returns `nil`. Meanwhile
`MessageDocument.parse` reads the same file correctly, since it goes through `NoteDocument.parse`
(`MessageDocument+Reading.swift:11`). The six production callers then behave as follows on a CRLF
message:

- the sync's pending-attachment retry and inline-image resolution return early, silently
  (`PraticaSyncEngine+Messages.swift:797-808`, through `MessageInlineImagePatch.swift:57,91` and
  `MessageAttachmentPatch.swift:22`);
- the corrupt-attachment repair skips the file, silently (`PraticaSyncEngine+Folder.swift:152`);
- «Collega nota» on a message reports «frontmatter non valido» in the app
  (`PraticaCommandActions+Links.swift:83-89`) and throws the same `ConnectorError` in `perg` and
  `pergamenum-mcp` (`VaultPraticheLinks.swift:234-238`);
- «Rigenera»'s `carryingOverLinkedNote` (`PraticaSyncEngine+Messages.swift:613`) patches a fresh LF
  render, so it is unaffected.

Once the delimiter is found, a second defect appears. The replacement or inserted line
(`:35`, `:40`) carries no `\r`, so a patch would make a CRLF file mixed. §D3 says a written line
takes the document's line break.

**`ViewCatalogue.locations(in:)`** (`ViewCatalogue.swift:67-114`) splits on `"\n"` (`:73`) and trims
`.whitespaces` (`:74`), then tests `trimmed == "---"` for the opening (`:78`) and the closing (`:83`).
Its output is paired by ordinal with `ViewBlock.blocks(in: NoteDocument.parse(text).body)` in
`scan` (`:148-149`), which goes through `MarkdownBlockParser`. That parser splits on `.newlines`
(`MarkdownBlocks.swift:82`), so it never sees a `\r`. Three divergences follow:

1. A CRLF frontmatter is not skipped. A YAML comment line such as `# commento` inside it becomes the
   heading in force, and so the name of the first view below it. This is the §D13.3 defect.
2. An opening `---` with no closing makes the walk skip the **whole file**, while `NoteDocument.parse`
   treats that text as body and the parser finds its views. The rows then get `lineIndex` 0 and no
   heading. This is a pre-existing divergence from the same rule.
3. In a CRLF body every fence line keeps its `\r`, so `CodeFence.language(declaredBy:)` (`:99`)
   reads `pergamenum-view\r` and **no view in a CRLF note is ever located**. Every row falls back to
   `lineIndex` 0 and the note's title. A heading keeps its `\r` too (`:109`). This one is not a
   delimiter test, but it hides divergence 1 on any all-CRLF note: with it unfixed, `locations` is
   `[]` both before and after a delimiter-only fix, so R-02 could be observed only on a mixed file.
   It is R-06, behind G1.

## Acceptance criteria

- **R-01** `MessageFrontmatterPatch.applying` recognises a `---\r` opening and closing delimiter
  in a CRLF message file. Its output keeps every byte outside the patched line identical, CRLF
  endings included. Precisely:
  - an inserted line, and a replaced line whose value changes, end in the document's line break
    (§D3), so a CRLF file stays all-CRLF;
  - a replaced line whose value is unchanged is left verbatim (§D1.3.1's rule): the existing line,
    read with one trailing `\r` removed, equals `line`. So a no-op patch equals the input on a
    mixed file too, and ADR-0040 §D6's "a patch identical to the file on disk is never written"
    stays true;
  - a removal removes the whole raw line, its `\r` included;
  - `MessageDocument.parse` of the output reads the patched value;
  - it holds through the sync's door (`MessageAttachmentPatch.applying`) and through the connector's
    door on disk (`VaultAPI.linkMessageNote`/`unlinkMessageNote`).
- **R-02** `ViewCatalogue.locations(in:)` recognises `---\r` delimiters the same way (both former
  sites, `:78` and `:83`). A line inside a CRLF frontmatter is never a view's heading.
- **R-03** Both readers use the note parser's rule exactly, as the table above states, through one
  shared helper. So:
  - `MessageFrontmatterPatch` answers non-`nil` exactly when `NoteDocument.parse(text).hasFrontmatterBlock`
    (for a block carrying the `pergamenum-mail` key);
  - `ViewCatalogue.locations(in:).count == ViewBlock.blocks(in: NoteDocument.parse(text).body).count`,
    for every row of the table, including an opening with no closing (divergence 2).
- **R-04** Each fix is pinned by a Swift Testing test that fails on current `main` with a CRLF
  fixture. A regression test shows an LF file behaves unchanged. Every existing test stays green,
  **unmodified**.
- **R-05** The sweep. `rg` over `Sources` for every `---` literal and every whitespace-trim
  delimiter test:
  - **fixed here:**
    - `MessageFrontmatterPatch.swift:24-26` (R-01);
    - `ViewCatalogue.swift:78,83` (R-02);
    - `FrontmatterRules.opensWithSecondBlock` (`FrontmatterSource.swift:297-305`): the body's first
      line is interpreted twice (the `.map` at `:298`, then `interpreted(first, isFirst: true)` at
      `:300`), so a body opening with `"---\r\r"` counts as a second block. §D11 removes one `\r`.
      The adoption of the helper aligns it with §D11's letter;
  - **out of scope, with the reason:**
    - `MarkdownStyler.frontmatterRange(in:)` (`MarkdownStyler.swift:199-204`,
      `hasPrefix("---")` plus a `"\n---"` search). It parses the block's extent, looser than the
      rule, but only to decide where styling starts; it never writes. Its function's line walks
      are `PG-274`'s (§D13.1): fixing the range alone while `lineRanges` (`:206-216`) still sees a
      CRLF note as one line would change nothing observable. It goes to `PG-274`;
    - `DiffView.swift:28` and `UnifiedDiff.swift:31` (diff headers), `GFMTable.swift:231` and
      `HTMLTextReducer.swift:333` (table delimiter rows), `EditorCommand.swift:84,184` (inserted
      text), `SampleViews.swift:28,33,136,141` (sample note content) and
      `Frontmatter.swift:275,282` (`FrontmatterSerializer.render`, a writer with its own
      line-break parameter, §D1.5): none is a frontmatter delimiter test.
- **R-06** (G1) `ViewCatalogue` reads every body line through the same `FrontmatterSource.interpreted`,
  one trailing `\r` removed, before it trims. So in a CRLF note:
  - each `pergamenum-view` fence is located, on its whole-file line index;
  - headings carry no `\r`;
  - the count equals `ViewBlock.blocks(in:)`'s.
- **R-07** Nothing changes in the on-disk format, in `IndexCache.schemaVersion` or in any entry of
  `.claude/protected-interfaces`. `perg` and `pergamenum-mcp` build unchanged: both compile
  `FrontmatterSource.swift`, `TagRename.swift` and `MessageFrontmatterPatch.swift` through
  `Sources/Core/**`, and `VaultPraticheLinks.swift` through `Sources/Connector/**`. (no-test:
  checked by `git diff --stat`, the protected-interface hook and the three builds in Task 5)
- **R-08** The record follows the code:
  - ADR-0065 gains a dated cross-reference under §D13.3 and a `### Follow-up: PG-276` subsection
    under «Implementation notes», in the PG-277 shape;
  - this plan gains a closing «Implementation notes» section;
  - the two `Character`-level walks found while planning (see Risks) are reported for `/ship` to
    record against `PG-274`;
  - `TODO.md` and issue #615 are left to `/ship`.
  (no-test: documentation obligation)

## ADR outcome: existing ADR, ADR-0065, with a dated follow-up note

**ADR-0065 governs, unchanged in its decisions.** §D1.2 defines how a line is interpreted, §D3
defines the delimiter tolerance and the written line's ending and applied both to `TagRename`, §D11
defines the second-block test's first line, and §D13.3 names this exact defect as out of that
chain's scope. This fix applies those rules to two more readers.

**No new ADR.** The significance test fails on "hard to reverse": a few lines in five files, with
no on-disk format, schema or interface change. It fails on "real trade-off" too. The one design
choice, a shared helper rather than a third and fourth inline copy of the composition, is internal
code organisation. It follows `CLAUDE.md`'s working agreement that an invariant is exposed as the
only way to obtain the value, since the copies drifting is how this defect happened. R-06's
widening is the same rule applied to more lines of the same walk. No override applies:

- no security boundary is involved;
- no constraint is invisible in the code, because the doc comments and the ADR-0065 note carry it;
- nothing deviates from the governing ADR, since this is its approach.

**The note (Task 6, behind G2)** mirrors «Follow-up: PG-277»:

- a dated blockquote under §D13.3: "Closed by PG-276 (#615), PR #N, `<merge hash>`: see
  Implementation notes, Follow-up PG-276";
- a `### Follow-up: PG-276` subsection with the rule table, the helper and its five adopters, the
  written-line rule for the patch, the §D11 alignment, R-06 (or, if G1 refuses it, R-06 as a named
  gap), and what stays out with its ticket.

It is not a supersession. No decision of ADR-0065 is reversed.

## Tasks

Order: the tester writes Task 1, the coder writes Tasks 2 to 4, and Tasks 5 and 6 close the
chain. **No new declaration is needed by any test.** Every test drives existing internal API:

- `MessageFrontmatterPatch.applying(line:forKey:before:to:)`, `MessageAttachmentPatch.applying(entries:to:)`;
- `MessageDocument.parse`, `noteLine(for:)`, `attachmentsLine(for:)`, `attachmentEntry(linking:)`;
- `ViewCatalogue.locations(in:)`, `ViewBlock.blocks(in:)`, `NoteDocument.parse`;
- `VaultAPI.arm`, `linkMessageNote`, `unlinkMessageNote`, `praticaMessageLink`;
- the damage-lint door `FrontmatterDamageLintTests` already uses.

The new helper of Task 2 is coder-owned and referenced by no test, so the target builds at the end
of Task 1 and red is an assertion failure, never a build break. Zero GUI tests: everything is
in-process in `PergamenumTests`.

**Fixture trap.** Swift normalises the line endings of a multi-line string literal to LF
(`FormatEdgeCorpus.swift:7-9`). Every CRLF fixture is a single-line literal with `\r\n` spelled
out, or an LF literal passed through `.replacingOccurrences(of: "\n", with: "\r\n")`.
`TemporaryVault.write` writes `Data(contents.utf8)`, so a CRLF fixture reaches the disk as is.

### Task 1 — Red tests (tester) (R-01, R-02, R-03, R-04, R-05, R-06)

Files:

- **new** `Tests/FrontmatterDelimiterParityTests.swift`, with a header comment citing ADR-0065
  §D1.2, §D3, §D13.3 and this plan. Then run `tuist generate --no-open`, because a new file under
  `Tests/**` must reach the generated project;
- **extend** `Tests/PraticheLinksConnectorTests.swift`, in `VaultAPIPraticheLinksTests`, under a
  new `// MARK: - PG-276: a CRLF message file`. It reuses the file's private `messageWithNoLink`,
  `messagePath`, `praticaFolder` and `openVaultWithOnePratica` (`:25-52`);
- **extend** `Tests/FrontmatterDamageLintTests.swift`, beside `aSecondBlockAfterATextBorneBOMIsReported`
  (`:42-49`), in its shape.

Tests. Each names its R-id in a comment, and "Today" is the predicted state before Task 2:

| Test | Asserts | Today |
|---|---|---|
| `insertsIntoACRLFMessageAndKeepsEveryOtherByte` | CRLF message (the `messageWithNoLink` shape), insert `MessageDocument.noteLine(for: "[[X]]")` before `pergamenum-mail-body`: the result equals the input with exactly `pergamenum-mail-note: "[[X]]"\r\n` inserted before that line; every line but the last ends in `\r`; `MessageDocument.parse(result)?.frontmatter.linkedNote == "[[X]]"` | red (`nil`) |
| `replacesAndRemovesAKeyInACRLFMessage` | replacing a changed value gives the exact expected CRLF text; removing the key (`line: nil`) gives the input without that raw line | red (`nil`) |
| `anUnchangedValueLeavesTheLineVerbatim` (two cases) | (a) CRLF message, patch with the value already present: result `==` input. (b) Mixed file with LF delimiters and first line break, and a CRLF `pergamenum-mail-note` line, patched with the same value: result `==` input | (a) red (`nil`); (b) red (the `\r` is dropped) |
| `theSyncsAttachmentDoorReachesACRLFMessage` | `MessageAttachmentPatch.applying(entries: [attachmentEntry(linking: "a.pdf")], to: crlf)` is non-`nil`, the attachments line ends in `\r`, every line but the last ends in `\r` | red (`nil`) |
| `anLFMessageIsPatchedExactlyAsBefore` | the insert, replace and remove cases above on the LF message give the exact expected LF texts, with no `\r` anywhere | green, pin |
| `aCommentInACRLFFrontmatterIsNotAViewHeading` | mixed note, CRLF frontmatter holding `# commento`, LF body with one un-headed view: `locations` has one entry and its `heading == nil` | red (heading `"commento\r"`) |
| `aCRLFNotesViewsAreLocatedWithTheirHeadings` (R-06) | all-CRLF note with `# commento` in the frontmatter, then `## Vista valida` plus a view and `## Vista rotta` plus a view: two locations, headings exactly `"Vista valida"`/`"Vista rotta"`, `lines[lineIndex] == "```pergamenum-view\r"` over a `"\n"` split, and `count == ViewBlock.blocks(in: NoteDocument.parse(text).body).count` | red (zero locations) |
| `anLFNoteIsLocatedExactlyAsBefore` | the LF twin of the fixture above: same headings, same line indices, same count | green, pin |
| `everyReaderAgreesWithTheNoteParser` (`@Test(arguments:)`, one case per line of the rule table, plus the unterminated row) | for each (opening, closing, expected): `NoteDocument.parse(msg).hasFrontmatterBlock == expected` (pins the rule itself); `(MessageFrontmatterPatch.applying(…, to: msg) != nil) == expected`; for `view = opening + "\n# commento\n" + closing + "\n```pergamenum-view\nrender: list\n```\n"`, `locations.count == ViewBlock.blocks(in: NoteDocument.parse(view).body).count` and `(locations.first?.heading == nil) == expected`. The body stays LF on purpose, so this test does not depend on R-06 | red on the openings `"---\r"`, `"--- \r"`, `"\t---\r"` and `"\u{FEFF}---"` (both readers), and on the `"\u{FEFF}---"` closing and the unterminated row (`ViewCatalogue` only); green on the rest |
| `aBodyOpeningWithTwoCarriageReturnsIsNotASecondBlock` (R-05, in `FrontmatterDamageLintTests.swift`) | `"---\ndate: 2026-01-01\n---\n---\r\r\ndate: 2026-01-02\n---\nCorpo.\n"` yields no `.secondFrontmatterBlock` | red (reported today) |
| `linkingANoteToACRLFMessageWritesItAndKeepsCRLF` (in `PraticheLinksConnectorTests.swift`) | write `messageWithNoLink` converted to CRLF, `rescan`, `arm(…, command: "message_link_note", dryRun: false)`, `linkMessageNote(…, title: "Offerta 2026")`: on disk the file holds `pergamenum-mail-note: "[[Offerta 2026]]"\r\n`, every line but the last ends in `\r`, and `praticaMessageLink(…)?.reference == "[[Offerta 2026]]"`. Then `unlinkMessageNote`: the key is gone and every line still ends in `\r` | red (throws «frontmatter non valido») |

If G1 refuses R-06, `aCRLFNotesViewsAreLocatedWithTheirHeadings` is not written. R-02 is still
observable through the mixed fixture and the parity table.

The tester runs the three touched test files and reports the red and green counts against the
"Today" column. No existing test is edited (R-04).

### Task 2 — One block-extent helper, adopted by the note parser's own readers (coder) (R-03, R-05)

Files: `Sources/Core/Conventions/FrontmatterSource.swift` and `Sources/Core/Conventions/TagRename.swift`.

- Add `static func closingDelimiterIndex(in lines: [String]) -> Int?` to `FrontmatterSource`, beside
  `interpreted` and `isDelimiter`. It takes the raw lines of a `"\n"` split and returns the index of
  the closing delimiter when line 0 is an opening. Line 0 is interpreted with `isFirst: true`,
  later lines with `isFirst: false`, and the first later delimiter wins. It returns `nil` when
  there is no opening or no closing. The doc comment calls it the one block-extent test every
  frontmatter reader uses (ADR-0065 §D1.2, §D3; PG-276). Foundation only: the file is compiled by
  `perg` and `pergamenum-mcp`.
- Adopt it, with semantics identical, in:
  - `FrontmatterSource.document(from:)`, replacing the guard's composition at `:93-94`
    (`interpretedLines` stays, for the block and its entries);
  - `TagRename`: delete the private `frontmatterEnd(of:)` (`:165-172`) and call the helper at its
    three call sites (`:19`, `:117`, `:152`);
  - `FrontmatterRules.opensWithSecondBlock(_:)` (`:297-305`): find the closing through the helper
    on the raw body lines, then test the lines between for a key through `interpreted`. This drops
    the double interpretation of the first line (R-05).
- `interpreted` and `isDelimiter` stay visible to the module. They have other callers:
  `NoteRename.swift:63`, `FrontmatterSource.swift:255,288` and `TagRename.listItemValue`.
- Done when `FrontmatterRoundTripTests`, `FormatEdgeCorpusTests`, `NoteByteOrderMarkTests`,
  `TagRenameTests` and `FrontmatterDamageLintTests` pass, the new damage-lint test included.

### Task 3 — `MessageFrontmatterPatch` (coder) (R-01, R-03)

File: `Sources/Core/Pratiche/MessageFrontmatterPatch.swift`, and nothing else.

- Replace `:24-27` with `FrontmatterSource.closingDelimiterIndex(in: lines)`. `block` is still
  `1..<closing`.
- Detect the document's line break once, with `LineBreak.detected(in: text)`.
- Replacement (`:35`): if `FrontmatterSource.interpreted(lines[existing]) == line`, leave the line
  as it is; otherwise write `line + lineBreak.lineSuffix`.
- Insertion (`:40`): write `line + lineBreak.lineSuffix`.
- Removal (`:37`) is unchanged: it removes the raw line with its `\r`.
- `isTopLevelKey` (`:59-63`) is unchanged. It reads only the text before the first colon, which a
  trailing `\r` never reaches. Say so in one comment line.
- Update the doc comments (`:7-13`) to state that the delimiters are the note parser's (the helper)
  and that a written line takes the document's line break (ADR-0065 §D3, PG-276).
  `MessageAttachmentPatch`'s doc comment (`:17-19`) stays true.
- The signature is unchanged. Callers pass lines without a terminator (`MessageDocument.swift:195-209`).
- Done when the R-01 rows and the patch half of the parity table are green.

### Task 4 — `ViewCatalogue.locations(in:)` (coder) (R-02, R-03, R-06)

File: `Sources/Features/Views/ViewCatalogue.swift`. It is app-only, and `FrontmatterSource` is in
the same module.

- Split once: `let lines = text.components(separatedBy: "\n")`. The body starts at
  `FrontmatterSource.closingDelimiterIndex(in: lines).map { $0 + 1 } ?? 0`. Skip every index below
  it and keep the whole-file `lineIndex`. Delete `isInFrontmatter` (`:71`) and the two delimiter
  branches (`:76-85`). An unterminated opening now reads as body, as the parser reads it.
- (R-06, G1) Compute `trimmed` from `FrontmatterSource.interpreted(line, isFirst: index == 0)`,
  then trim `.whitespaces` (`:74`). This lets fences and headings drop a CRLF line's `\r`. If G1
  refuses it, body lines keep `line.trimmingCharacters(in: .whitespaces)`.
- Replace the frontmatter comment with the reason: the walk must skip exactly the block
  `NoteDocument.parse` recognises, because `scan` pairs these locations by ordinal with
  `ViewBlock.blocks(in: NoteDocument.parse(text).body)`, whose parser never sees a `\r`. That is the
  same pairing argument as the fence comment at `:87-93`.
- Done when the `ViewCatalogue` rows and the parity table are green, and `SidebarTests`,
  `ViewBlockOutOfScopeTests` and `ViewBlockSpanTests` pass unmodified.

### Task 5 — Staleness sweep, full suite, three builds (coder, then orchestrator) (R-04, R-05, R-07)

**Observable contracts that change**, with the call sites grepped for this plan:

- `MessageFrontmatterPatch.applying(line:forKey:before:to:)` answers non-`nil` for a CRLF or
  BOM-opened block, and a written line takes the document's line break. The signature is unchanged.
  - Production callers (`rg -n "MessageFrontmatterPatch|MessageAttachmentPatch.applying|MessageInlineImagePatch.applying" Sources`):
    - `MessageAttachmentPatch.swift:22` and `MessageInlineImagePatch.swift:57,91` (wrappers);
    - `PraticaSyncEngine+Messages.swift:613,797,806` and `PraticaSyncEngine+Folder.swift:152` (sync);
    - `PraticaCommandActions+Links.swift:83` (app);
    - `VaultPraticheLinks.swift:234` (connectors).
  - Tests: `MessageInlineImagePatchTests.swift` (`MessageFrontmatterPatchTests`, 7 tests, plus the
    inline-image suite), `MessageAttachmentPatchTests.swift`, `PraticaSyncPendingTests.swift:261`,
    `PraticaSyncAttachmentTests.swift:281` and `PraticaRegenerationTests.swift:198`. All use LF
    fixtures, and every `== nil` pin (`MessageInlineImagePatchTests.swift:82-104,220`,
    `MessageAttachmentPatchTests.swift:128-148`) feeds a text with no block, an unterminated block
    or no `pergamenum-mail` key, whose answer does not change. None needs updating.
- `ViewCatalogue.locations(in:)` locates views in a CRLF note, skips a CRLF frontmatter, reads an
  unterminated opening as body and strips `\r` from headings.
  - Production caller: `ViewCatalogue.scan` (`:148`).
  - Tests: `SidebarTests.swift:99,128` and `ViewBlockOutOfScopeTests.swift:249,262`, with a comment
    at `ViewBlockSpanTests.swift:108`. All use LF notes with closed blocks. None needs updating.
- `FrontmatterRules`' `secondFrontmatterBlock` changes for a body opening with `"---\r\r"` only. It
  reaches `VaultAPI.LintFinding.frontmatter` as the same string, and the shape is unchanged.
  `FrontmatterDamageLintTests.swift:39,48` stay green: the `"\u{FEFF}---\r"` case interprets to
  `---` either way.
- `NoteDocument.parse` and `TagRename.apply` show no observable change. Their suites are the guard.

After Tasks 2 to 4, the coder re-runs the sweeps below. Any new hit is handled here with its
reason, never deleted:

- `rg -n -F -- '---' Sources` (R-05's list);
- `rg -n 'isDelimiter\(|frontmatterEnd' Sources`, where `isDelimiter` should appear only inside
  `FrontmatterSource.swift` and `frontmatterEnd` nowhere;
- the staleness greps above.

Verification:

- the **full** unit suite, not only the touched files:
  `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS'
  -only-testing:PergamenumTests test`. `NoteDocument.parse` sits under the scanner, every writer,
  the linter, Pratiche and the connectors;
- `xcodebuild ... -scheme perg ... build` and `-scheme pergamenum-mcp ... build`;
- SwiftLint on the touched files. `FrontmatterSource.swift` is at 306 lines, with the warning at
  400;
- `git diff --stat origin/main` touches no `IndexCache.swift`, no file named in
  `.claude/protected-interfaces` and no fixture on disk (R-07);
- `scripts/uitests.sh --status`, then `--affected` at merge per `CLAUDE.md`. The merge gate is the
  unit suite.

### Task 6 — Records (coder; the ADR-0065 wording behind G2) (R-08)

Files:

- `docs/adr/0065-format-round-trip-faithful-or-refused.md`:
  - under §D13.3, a dated blockquote in the form of the one under §D13.4;
  - under «Implementation notes», after «Follow-up: PG-277», a `### Follow-up: PG-276` subsection
    with the content listed under «ADR outcome».

  Neither the decision text nor the Acceptance table is edited. The PR number and merge hash are
  filled in after the merge (`docs/adr/README.md` rule 2); until then the note reads "PR #N".
- This plan: a closing «Implementation notes» section, with the measured red and green counts and
  any departures.
- Not edited:
  - `CLAUDE.md`, whose ADR-0065 index entry stays true;
  - `TODO.md` and issue #615, which `/ship` closes;
  - `PG-274`'s entry. The finding is handed to `/ship` in the report, not written here.

Run `scripts/check-adr-references.py` after the ADR edit, following `git fetch origin`.

## Risks and HITL gates

- **The note parser is touched.** Task 2 routes `NoteDocument.parse` through the new helper. The
  change is meant to be semantics-identical, and the round-trip corpus, the BOM tests and the
  `TagRename` suite guard it. The reviewer reads that hunk against `:93-99` line by line.
- **CRLF message files start receiving writes.** After the fix, the first sync lands the pending
  attachment retries and corrupt-link repairs that were silently skipped on CRLF message files. That
  is the purpose of the fix. Each write keeps its `expecting:` hash precondition.
- **Mixed files.** A changed line takes the document's line break (§D3), while unchanged lines,
  and an unchanged patched line, stay verbatim. A mixed message file therefore stays mixed.
- **A located CRLF view still does not jump.** `ViewsPane.open` (`ViewsPane.swift:152`) resolves
  the line through `NoteJump.lineRange` (`NoteJump.swift:20-32`), which searches for a `"\n"`
  `Character`. On a CRLF note it finds none, so any `lineIndex` above 0 answers `nil`, and the
  note opens without moving the caret. `CodeFence.lineRanges` (`CodeFence.swift:91-101`) has the
  same shape. Both are `PG-274`'s class (§D13.1), and `PG-274` does not name them yet. They are
  reported for `/ship`, not fixed here. After this chain a CRLF view row gets its right name and
  heading, and the jump waits for `PG-274`.
- **Residual pairing edges, pre-existing:** `MarkdownBlockParser` also splits on a lone `\r`,
  U+2028, U+2029 and U+0085 (`.newlines`), and `ViewCatalogue` does not. They are not addressed.
- **Gates:**
  - G1 before Task 4 (R-06);
  - G2 at Task 6 (the ADR-0065 note's wording);
  - commit, push, PR and merge are Stefano's.

  There is no schema change, no file deletion and no release.
- No externally provisioned resource is needed: no network, no service, no credential, no port.

## Open for Stefano

- **G1: widen the `ViewCatalogue` fix to body lines (R-06).** It is the same `interpreted` rule,
  applied once more in the same walk. Without it, no view in an all-CRLF note is ever located, and
  R-02's fix is observable only on mixed files. **Recommended: include.** If refused, R-06 becomes
  a named gap in the ADR-0065 note and a separate ticket.
- **G2:** the wording of the ADR-0065 follow-up note (Task 6).
- **For `/ship`:** add `NoteJump.lineRange` and `CodeFence.lineRanges` to `PG-274` (#613), or file
  them as a sibling ticket.

## Test command

`xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test`

This is the unit suite only, and it is the current `.claude/test-cmd` unchanged. `CLAUDE.md`
records why the `Stop` hook must stay restricted to `PergamenumTests`. The GUI suite runs only
through `scripts/uitests.sh`.

## Implementation notes

Written 2026-09-29, after Tasks 2 to 6. G1 was approved, so R-06 is implemented. The ADR-0065 note
is a draft for G2, with "PR #N" and `<merge hash>` placeholders for `/ship`.

**Red, before Tasks 2 to 4 (the tester's run of Task 1).** Every row the "Today" column predicts
red was red. `ViewCatalogue` was also red in the parity table for the closings `"----"`,
`"--- x"`, `"-- -"` and `"---\r\r"`, which the column had not predicted: each is an opening with no
closing, divergence 2, where the old walk skipped the whole file. These counts come from the
tester's report; the coder did not re-measure the red state.

**Green, after Tasks 2 to 4.** Measured with `-derivedDataPath build/coder-dd`:

- the narrow run (`MessageFrontmatterPatchCRLFTests`, `DelimiterParityTests`,
  `VaultAPIPraticheLinksTests`): 22 tests in 3 suites passed, the parity test with all 21 cases;
- the full unit suite (`-only-testing:PergamenumTests`): 4037 tests in 215 suites passed, exit 0.
  The 5 known issues are `HostedViewPrototypeTests`' own `withKnownIssue`, pre-existing.
  `ViewCatalogueCRLFTests` and `aBodyOpeningWithTwoCarriageReturnsIsNotASecondBlock` pass there;
- `perg` and `pergamenum-mcp` build, exit 0 each;
- SwiftLint on the four touched sources: one warning, `function_parameter_count` at
  `ViewCatalogue.swift:162` (`entry(...)`), pre-existing and not in a touched hunk.
  `FrontmatterSource.swift` is at 311 lines;
- `scripts/check-adr-references.py` after `git fetch origin`: 0 findings, exit 0, with two
  pre-existing rule-2 warnings on ADR-0048 and ADR-0064;
- `git diff --stat origin/main`: no `IndexCache.swift`, no entry of `.claude/protected-interfaces`,
  no fixture on disk. `TODO.md` differs only because `origin/main` moved ahead (R-07).

**Sweeps (Task 5).**

- `rg -n 'isDelimiter\(|frontmatterEnd' Sources`: `isDelimiter` appears only inside
  `FrontmatterSource.swift` (its declaration and the helper), `frontmatterEnd` nowhere.
- `rg -n -F -- '---' Sources`: every hit R-05 lists, plus hits it does not list. None of the
  unlisted ones is a delimiter test:
  - doc comments or prose that name `---` (`VaultSession+Notes.swift:58`,
    `HarnessImporter.swift:60`, `Frontmatter.swift:139`, `MessageAttachmentPatch.swift:19`,
    `MessageFrontmatterPatch.swift:16`, `NoteTemplate.swift:37`, `Transclusion.swift:160`,
    `NoteOutline.swift:84`, `MarkdownStyler.swift:15,80,706`, `HorizontalRuleFragment.swift:3,26,47`,
    `EditorDecorationDelegate.swift:66`, `NoteTextView+TableCaret.swift:15`, `GFMTable.swift:94`,
    `QuoteSplitter.swift:23,24,78`, `MIMEDecoder.swift:125`). `NoteTemplate`, `Transclusion` and
    `NoteOutline` already go through `NoteDocument.parse`;
  - `TaskControlsMockup.swift:174,179`: mockup content in the design gallery.
- The staleness greps find the production callers the plan lists and no other.

**Departures.**

- Task 4, R-06: body lines are read with `FrontmatterSource.interpreted(line)`, not
  `interpreted(line, isFirst: index == 0)`. When a note has no block, its body starts on line 0
  and `NoteDocument.parse` hands the whole text, a leading U+FEFF included, to
  `MarkdownBlockParser`, which trims only `.whitespaces` and so keeps it. Removing the U+FEFF in
  the walk would locate a fence on line 0 the parser does not count, breaking R-03's count
  equality. When a note has a block, line 0 is the opening and is skipped, so `isFirst` would never
  apply anyway.
- The helper is written `lines.indices.dropFirst().first { … }`; `TagRename`'s deleted
  `lines.dropFirst().firstIndex { … }` answered the same base index.

**For `/ship` (R-08).** `NoteJump.lineRange` (`NoteJump.swift:20-32`) and `CodeFence.lineRanges`
(`CodeFence.swift:91-101`) search for a `"\n"` `Character`, so a view located in a CRLF note still
opens without moving the caret. Add them to `PG-274` (#613), or file a sibling ticket.
