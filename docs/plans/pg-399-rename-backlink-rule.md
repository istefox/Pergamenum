**Requirement set:** none, no SPEC applies (brief: PG-399)

# Plan — PG-399: one rule for what a wikilink names (the rename, the index, every row)

Written 2026-10-16 against `57edd30b` (`HEAD` = `origin/main`, branch
`fix/burn-down-2026-10-16-pg-424-pg-399`). The root `SPEC.md` is PG-406's and does not apply: no R-id
below comes from it. Inputs: ledger entry `PG-399` (`TODO.md:39`), the burn-down result in
`docs/plans/burn-down-2026-10-16-pg-424-pg-399.md`, ADR-0065, ADR-0084, ADR-0082, ADR-0021 §D4,
`docs/adr/README.md`, and the sources named below, each re-read on `57edd30b`.

## ADR outcome

**A new ADR, `docs/adr/0097-a-link-names-the-title-it-resolves-to.md` (proposed), written with this
plan.** It amends ADR-0084 §D1 and records the bump of a protected constant.

- **Why an ADR.** It is hard to reverse: a cache bump, and connector output values. It is surprising
  without context, because ADR-0084 §D1 says the opposite ("not `resolvedTitle`, so `[[**T**]]` is no
  backlink of `T`"). It is a real trade-off: four alternatives are in the record. Two overrides apply
  as well: it reverses an explicit "no" in an accepted ADR, and it moves
  `IndexCache.schemaVersion` (`.claude/protected-interfaces`).
- **Why a new number and not an edit of ADR-0084.** `docs/adr/README.md` has no amendment rule. The
  repository's practice for a later decision that changes an accepted section is a new record whose
  Relations say "Amends ADR-NNNN §Dn", plus a one-line pointer under the amended section of the old
  record:
  - ADR-0091 §D10: "Its layout half is amended by ADR-0093 §D4.";
  - ADR-0082 §D7: "Reopened and scoped by ADR-0093 §D4.".

  ADR-0084's own in-place "*Amended 2026-10-12 ...*" paragraphs (§D3, §D4) were written at its flip
  by its own chain, as built. That is not the case here. Task 7 writes the pointer line.
- **Number.** `0097`. The highest number on `origin/main` is `0096`. `git ls-tree` over every local
  and remote-tracking ref finds no `0092` and nothing at `0097` or above. `0092` stays skipped (see
  ADR-0093's header). Re-check before the merge (README rule 1).

## Requirements

Local to this plan. `(no-test: …)` exempts a requirement from the test axis only, never from the plan.

- [ ] R-01 One predicate decides whether a link names a title: `Wikilink.names(_:)` and
  `Wikilink.target(_:names:)`. Both compare `resolvedTitle` with the title, case-insensitively, with
  surrounding spaces and tabs ignored. `NoteRename.rewritingLinks` matches through it, and its
  behaviour is unchanged (`NoteRenameCharacterizationTests` green as written).
- [ ] R-02 `Wikilink.resolvedTitle` trims spaces and tabs after stripping its one marker pair, and is
  `target` when that leaves nothing.
- [ ] R-03 The index stores and keys the resolved title:
  - `NoteStore.linkTargets(in:)` returns resolved titles, deduplicated on them, in source order;
  - `Wikilink.isNoteLink` judges `resolvedTitle`;
  - `IndexSnapshot`'s two `related` reads (backlinks, neighbourhood) use `resolvedTitle`.
- [ ] R-04 The rename and the index agree. Over one corpus of spellings, the rename rewrites a link
  exactly when the index lists the linking note as a backlink. A rename leaves the source note's
  unresolved targets unchanged (app SPEC `docs/20260811_Pergamenum_SpecApp.md:114`).
- [ ] R-05 A backlink row counts what the index counts. `BacklinkContext.lines`,
  `BacklinkRow.isStructural` and the row's highlight use the predicate. ADR-0084 §D1's pin is
  inverted, and its agreement test reads `resolvedTitle`.
- [ ] R-06 «Vai al link» finds the line of an emphasised unresolved link
  (`UnresolvedTargets.firstLine`).
- [ ] R-07 «Scollega» and «Rendi strutturale»'s structural edit find the link the badge found
  (`RelatedLink.add` and `remove`).
- [ ] R-08 These read an emphasised link as its title: the trash warning (`danglingLinks`), a board's
  «Note referenziate» (`WorkspaceReferences.notes(in:)`) and a task's links (`task.links`, and
  `TaskParser.line(for:addingLinkTo:)`'s duplicate check).
- [ ] R-09 `IndexCache.schemaVersion` is 8, and a cache stamped 7 is not reused (gate G-schema).
- [ ] R-10 ADR-0097 is recorded. ADR-0084 §D1 carries the amendment pointer, and `CLAUDE.md`'s ADR
  index and `docs/adr/INDEX.md` list ADR-0097. (no-test: documentation, checked by
  `scripts/adr-index.py --check` and `scripts/check-adr-references.py`)

## Re-verification of the brief on `57edd30b`

Every claim the brief carried was re-checked against today's sources. **The conclusion holds.** The
rule is `resolvedTitle` everywhere, and applying it needs:

- the ADR-0084 §D1 amendment;
- the pin-test inversion;
- the bump from 7 to 8.

Those three are necessary, **but not sufficient**: the last bullet of the list below is what was
missing.

- **`NoteRename.swift:33` matches by `resolvedTitle`.** Still true:
  `filter { fold($0.resolvedTitle) == needle }`, where `fold` trims and lowercases (`:78-80`).
- **`IndexSnapshot.swift:79` files backlinks under `link.target`.** The line moved; the claim holds:
  - `:79` is now `backlinkDisplayForm.removeAll`;
  - body links are filed at `:88-89` from `record.linkTargets`, which `NoteStore+ReadSurface.swift:33-34`
    fills with `link.target`;
  - `related` links are filed at `:94-95` with `link.target`;
  - the key is lowercased by `addBacklink` at `:80-84`.
- **The pin test at `BacklinkContextTests.swift:211`.** True: `:211` is the last line of its doc
  comment, the test is `aRowComparesTheLinkTargetAsTheIndexKeysItNotTheResolvedTitle` (`:212-227`),
  and the agreement test it leans on is at `:192-207`.
- **`schemaVersion` is 7.** True: `IndexCache.swift:218`, with its doc comment at `:200-217`. The
  literal pin is `IndexCacheTests.swift:229`.
- **ADR-0084 §D1 says `target`.** True: ADR-0084 lines 80-82.
- **"Check that the index side needs no schema change."** There is no change of *shape*:
  `StoredRecord` keeps its fields. There is a change of *meaning*, and that needs a bump:
  - `IndexCache`'s own rule asks for one on a meaning change (`:200`);
  - the scanner reuses an unchanged file's row (`VaultScanner.swift:94-101`);
  - both earlier meaning changes of this column bumped (2, ADR-0010 §D7; 5, ADR-0065 §D12).

  The no-bump route (resolve at derivation time) exists, and ADR-0097 rejects it with its reason.
  Task links need no bump, because `StoredTask` re-parses `rawLine` (`IndexCache.swift:351-355`).
- **Not in the burn-down.** Applying the rule only to `IndexSnapshot` and `BacklinkContext` would
  open new disagreements:
  - `isNoteLink` judges the literal target (`Wikilink.swift:59-62`), so `[[**Q4.canvas**]]` would put
    `Q4.canvas` into `linkTargets` and break ADR-0065 R-20;
  - `UnresolvedTargets.firstLine` compares `target ==` (`UnresolvedTargets.swift:24`), so «Vai al
    link» would lose emphasised targets;
  - `RelatedLink` removes by literal target (`RelatedLink.swift:52`, `:65`, `:144`, `:188`, `:215`),
    so «Scollega» on a row the badge now calls structural would skip that side and report success;
  - the same literal comparison sits in `BacklinksSection.swift:124`, `NoteFileOperations.swift:158`,
    `WorkspaceReferences.swift:38-39` and `TaskParser.swift:78`;
  - `resolvedTitle` does not trim, while the rename's `fold` does: `[[** Curva **]]` is rewritten by
    a rename of Curva but would be keyed `" curva "`.

  Tasks 3 and 4 cover them.

## Call-sites of the changed contract (staleness rule)

The observable change is the *value* of a note's link titles: `NoteRecord.linkTargets`,
`TaskItem.links`, and every output derived from them. Shapes do not change. Found by grep on `57edd30b`.

- **Readers of `linkTargets`.** Nine sites, unchanged by this plan, inheriting the rule:
  - `IndexSnapshot.swift:88`, `:122`, `:159` (and `:179`, emptiness only);
  - `ViewEvaluator.swift:219`, `:223`;
  - `ViewField.swift:172`;
  - `VaultReads.swift:32`, `:35`;
  - `VaultPayloads.swift:30` (`NoteSummary.links`, JSON);
  - the cache's own copy, `IndexCache.swift:269`, `:290`, `:305`.
- **Readers of `task.links`:** `IndexSnapshot.swift:214`, `TaskParser+Writes.swift:108`,
  `TasksView+Row.swift:100`, `VaultPayloads.swift:100` (JSON).
- **Tests asserting the old behaviour:**
  - `BacklinkContextTests.swift:209-227` (the pin, inverted by Task 3);
  - `BacklinkContextTests.swift:192-207` (maps `\.target`, moved to `\.resolvedTitle` by Task 3);
  - `IndexCacheTests.swift:229` (the literal `== 7`, moved to 8 by Task 5).
- **Nothing else asserts it.** No other test, UI test or `scripts/mcp-smoke.py` assertion contains an
  emphasised wikilink (`grep -rn '\[\[[^]]*[*~]' Tests/ UITests/`). The exceptions keep their
  assertions:
  - `ConventionsLinkTests.swift:52-62` (`resolvedTitle` of `[[**Prova**]]` stays `Prova`);
  - `MarkdownStylerTests.swift:207-220`;
  - `StylerGoldenCorpus.swift:167`;
  - `NoteRenameCharacterizationTests.swift:86-115`.
- **The full unit suite runs after the change, not just the new files.** `linkTargets` feeds views,
  connectors, the inspector and the mention scan (`VaultSession+Search.swift:143`).

## Tasks

### Task 1 — Red: the predicate, the resolved title and the index key (R-01, R-02, R-03, R-04)
Owner: tester
Files: Tests/WikilinkNamesTests.swift, Tests/RenameBacklinkAgreementTests.swift, Sources/Core/Conventions/Wikilink.swift
Tests: WikilinkNamesTests.swift, RenameBacklinkAgreementTests.swift, NoteRenameCharacterizationTests.swift
Signatures:
- Wikilink.names(_:) — func names(_ title: String) -> Bool
- Wikilink.target(_:names:) — static func target(_ target: String, names title: String) -> Bool
- Wikilink.resolvedTitle — var resolvedTitle: String
- Wikilink.isNoteLink — var isNoteLink: Bool
- NoteStore.linkTargets(in:) — static func linkTargets(in document: NoteDocument) -> [String]
- NoteRename.rewritingLinks(in:from:to:includeQuotedRelated:) — static func rewritingLinks(in text: String, from oldTitle: String, to newTitle: String, includeQuotedRelated: Bool = true) -> String?
- IndexSnapshot.replaceAll(with:duration:) — mutating func replaceAll(with outcome: VaultScanner.Outcome, duration: Duration)
- IndexSnapshot.backlinks(toTitle:) — func backlinks(toTitle title: String) -> [NoteRecord]
- IndexSnapshot.unresolvedTargets(of:) — func unresolvedTargets(of path: String) -> [String]
- IndexSnapshot.neighbourhood(ofTitle:) — func neighbourhood(ofTitle title: String) -> Set<String>
Red: yes

**Stubs (the tester owns the signatures).** In `Sources/Core/Conventions/Wikilink.swift`, declare the
two new members. Each body is today's literal rule, so the target builds and the tests are red, not
crashing:

- `names(_:)`: `target.lowercased() == title.lowercased()`;
- `target(_:names:)`: the same comparison over its arguments.

Never `fatalError`: a trap takes the whole test run down. Mark both `// ADR-0097: body owned by
Task 2`.

**`WikilinkNamesTests.swift` (new).** Each case parses a body with `WikilinkParser.links(in:)`.

- `names("Curva")` is true for `[[Curva]]`, `[[curva]]`, `[[**Curva**]]`, `[[~~Curva~~]]`,
  `[[*Curva*]]`, `[[**Curva**#Sez|alias]]`, `![[**Curva**]]` and `[[** Curva **]]`.
- It is false for `[[**Curva** vecchio]]`, `[[Curvatura]]` and `[[***Curva***]]` (one pair only:
  that link names `*Curva*`).
- `Wikilink.target("**Curva**", names: "Curva")` is true, and `Wikilink.target("Curva", names: " curva ")`
  is true.
- `resolvedTitle`: `[[** Curva **]]` gives `Curva`, and `[[** **]]` gives `** **`.
- `isNoteLink`: false for `[[**Q4.canvas**]]` and `![[**foto.png**]]`, true for `[[**Nota**]]` and
  `![[**Nota**]]`.
- `NoteStore.linkTargets(in:)`:
  - `"Con enfasi [[**Curva**]] e senza [[Curva]]."` gives `["Curva"]`;
  - `"[[~~Forno~~]] e [[Altra]]"` gives `["Forno", "Altra"]`;
  - `"[[**Q4.canvas**]]"` gives `[]`.

**`RenameBacklinkAgreementTests.swift` (new), R-04.** The index is built the way the app builds it.
Use a `TemporaryVault` holding `Curva.md` and `Fonte.md`, scan it with `VaultScanner(root:).scan()`,
then call `IndexSnapshot.replaceAll(with:duration:)`. Never hand-write a `NoteRecord`: the test must
go through the extraction.

1. **Agreement over one corpus.** For each body in the corpus, the two sides must agree:
   - `NoteRename.rewritingLinks(in: body, from: "Curva", to: "Nuovo", includeQuotedRelated: false) != nil`;
   - `backlinks(toTitle: "Curva")` lists `Fonte.md`.

   The corpus is every spelling above, plus `` `[[**Curva**]]` `` in an inline code span (neither).
   Not vacuous: assert at least one `true` (`[[**Curva**]]` by name) and one `false`.
2. **Through `related`.** `Fonte.md` carries `related:` with `"[[**Curva**]]"` and no body link. Then
   `backlinks(toTitle: "Curva")` lists `Fonte.md`, `neighbourhood(ofTitle: "Curva")` contains
   `Fonte.md`, and `neighbourhood(ofTitle: "Fonte")` contains `Curva.md`.
3. **The SPEC's rename invariant (line 114).** `Fonte.md` reads `Vedi [[**Curva**]] e [[Assente]].`
   - Before: `unresolvedTargets(of: "Fonte.md") == ["Assente"]`.
   - Perform the rename: either apply `NoteFileOperations.renamePlan`'s `noteChanges` and move the
     file (as `renameCountsTheBoldLink` builds its plan), or write `Nuovo.md` and Fonte's rewritten
     text by hand.
   - Rescan: still `["Assente"]`.

Red before Task 2: `names` is literal, `resolvedTitle` does not trim, and `isNoteLink`, `linkTargets`
and the `related` reads use the literal target.

### Task 2 — The rule and the index key (R-01, R-02, R-03, R-04)
Owner: coder
Files: Sources/Core/Conventions/Wikilink.swift, Sources/Core/Conventions/NoteRename.swift, Sources/Vault/NoteStore+ReadSurface.swift, Sources/Vault/NoteStore.swift, Sources/Index/IndexSnapshot.swift
Tests: WikilinkNamesTests.swift, RenameBacklinkAgreementTests.swift, NoteRenameCharacterizationTests.swift, ConventionsLinkTests.swift, WikilinkIsNoteLinkTests.swift
Signatures:
- Wikilink.names(_:) — func names(_ title: String) -> Bool
- Wikilink.target(_:names:) — static func target(_ target: String, names title: String) -> Bool
- Wikilink.resolvedTitle — var resolvedTitle: String
Red: no

Make Task 1 green. Nothing outside the files listed.

- **`Wikilink.swift`.**
  - `resolvedTitle` (`:29-32`) strips the one marker pair as today, then trims spaces and tabs. When
    that leaves an empty string it returns `target`. Update the doc comment at `:20-28`, citing
    ADR-0097 §D1.
  - Give the stubs their bodies: fold both sides (trim spaces and tabs, then lowercase) and compare
    the resolved title of the target with the title. `names(_:)` calls `target(target, names:)`.
    The string form resolves a bare interior exactly as the property does: share one private helper,
    so there is no second marker list.
  - `isNoteLink` (`:59-62`): `Transclusion.isNoteReference(resolvedTitle)`, and the `.canvas` test
    on `resolvedTitle`. Update the doc comment at `:51-58` (ADR-0097 §D2).
  - `retitled(_:)` and `rendered` stay on `target`: the rename must keep the emphasis (`:20-28`'s
    own warning).
- **`NoteRename.swift:33`.** Becomes `filter { $0.names(oldTitle) }`. The early `guard`
  (`:25-26`) and `rewritingQuotedRelated` keep `fold`. Rewrite the comment at `:30-32`, which says
  "as the index does" (true from now on), to cite ADR-0097 §D1 next to R-19.
- **`NoteStore+ReadSurface.swift:33-34`.** Insert and append `link.resolvedTitle`. Doc comment at
  `:28-29`: the stored value is the title the link names (ADR-0097 §D2).
- **`NoteStore.swift:13`.** `NoteRecord.linkTargets` doc: "the note titles the body links to (each
  link's `resolvedTitle`), in source order, duplicates removed". Comment only.
- **`IndexSnapshot.swift`.** `link.target` becomes `link.resolvedTitle` at `:95` and `:164`. The
  `backlinkIndex` doc at `:31` reads "lowercased resolved title". `addBacklink` (`:80-84`) is
  unchanged: its input is now a resolved title, already trimmed.
- **What stays as is.** `ConventionsLinkTests`, `WikilinkIsNoteLinkTests` and
  `NoteRenameCharacterizationTests` stay green as written. If one goes red, stop and report: it is
  not a pin to move.

### Task 3 — Red: rows, «Vai al link», structural verbs, trash, boards, tasks (R-05, R-06, R-07, R-08)
Owner: tester
Files: Tests/BacklinkContextTests.swift, Tests/UnresolvedTargetsTests.swift, Tests/RelatedLinkTests.swift, Tests/NoteFileOperationTests.swift, Tests/WorkspaceReferenceTests.swift, Tests/TaskTests.swift
Tests: BacklinkContextTests.swift, UnresolvedTargetsTests.swift, RelatedLinkTests.swift, NoteFileOperationTests.swift, WorkspaceReferenceTests.swift, TaskTests.swift
Signatures:
- BacklinkContext.lines(linking:in:) — static func lines(linking title: String, in text: String) -> [String]
- BacklinkRow.make(path:title:text:linking:related:) — static func make(path: String, title: String, text: String, linking target: String, related: [String]) -> BacklinkRow
- BacklinkRow.isStructural(related:linking:) — static func isStructural(related: [String], linking target: String) -> Bool
- UnresolvedTargets.firstLine(linking:in:) — static func firstLine(linking target: String, in text: String) -> Int?
- RelatedLink.add(target:reason:to:selfTitle:) — static func add(target: String, reason: String, to text: String, selfTitle: String) throws -> String
- RelatedLink.remove(target:from:) — static func remove(target: String, from text: String) -> String
- NoteFileOperations.danglingLinks(for:knownPaths:) — func danglingLinks(for relativePath: String, knownPaths: [String]) -> [String]
- WorkspaceReferences.notes(in:) — static func notes(in document: CanvasDocument) -> [String]
- TaskParser.parse(line:sourcePath:lineIndex:) — static func parse(line: String, sourcePath: String, lineIndex: Int) -> TaskItem?
- TaskParser.line(for:addingLinkTo:) — static func line(for task: TaskItem, addingLinkTo target: String) -> String
- NoteStore.linkTargets(in:) — static func linkTargets(in document: NoteDocument) -> [String]
Red: yes

All pure or `TemporaryVault`-backed, in-process. No new symbol: every test is written against an
existing signature.

**`BacklinkContextTests.swift`.**

- **Invert the pin (`:209-227`), ADR-0084 §D1 amended by ADR-0097 §D1.** Do not delete it. Rename
  the test (for example `aRowReadsTheTitleAnEmphasisedLinkNamesAsTheIndexDoes`) and rewrite its doc
  comment. For `text = "Con enfasi [[**Curva**]] e senza [[Curva]]."`:
  - `linkTargets(in:) == ["Curva"]`;
  - `lines(linking: "Curva", in: text) == [text, text]` (one entry per link);
  - `lines(linking: "**Curva**", in: text).isEmpty`.

  For `onlyEmphasised`: `lines(linking: "Curva")` is `[onlyEmphasised]`; the row built with
  `related: ["[[**Curva**]]"]` has `count == 1` and `isStructural`.
- **The agreement test (`:192-207`).** `counted` maps `\.resolvedTitle`. `agreementCorpus` gains one
  emphasised entry (for example `"Vedi [[**Nota**]] e [[~~Altra~~]]."`), with a non-vacuous
  `#expect` that a resolved title from it is in `all`.
- **New: a row agrees with the index.** Over a corpus of the Task 1 spellings (written out again
  here: Task 1's is private to its file), assert
  `!BacklinkContext.lines(linking: "Curva", in: body).isEmpty == NoteStore.linkTargets(in: NoteDocument.parse(body)).contains { $0.lowercased() == "curva" }`.

**The other files.**

- **`UnresolvedTargetsTests.swift` (R-06).** `firstLine(linking: "Nuova", in:)` over a note whose
  frontmatter is followed by `prima\nVedi [[**Nuova**]].` returns the zero-based line of the second
  body line, counted over the whole text.
- **`RelatedLinkTests.swift` (R-07).** Use the file's existing fixture shape: frontmatter `related:`
  plus a `## Note correlate` bullet.
  - `RelatedLink.remove(target: "Curva", from:)` on a note whose `related` holds `"[[**Curva**]]"`
    and whose section holds `- [[**Curva**]] — motivo` removes both writings.
  - The same with `[[curva]]` (case).
  - `RelatedLink.add(target: "Curva", ...)` on the emphasised note returns the text unchanged: no
    second link.
- **`NoteFileOperationTests.swift` (R-08).**
  `danglingLinks(for: "Curva.md", knownPaths: ["Curva.md", "Fonte.md"])` with `Fonte.md` reading
  `Vedi [[**Curva**]].` gives `["Fonte.md"]`.
- **`WorkspaceReferenceTests.swift` (R-08).** A `CanvasDocument` with one `.text` node
  `vedi [[**Curva**]]` gives `notes(in:) == ["Curva"]`.
- **`TaskTests.swift` (R-08).**
  - `TaskParser.parse(line: "- [ ] chiamare [[**Curva**]]", sourcePath: "A.md", lineIndex: 0)?.links == ["Curva"]`.
  - `TaskParser.line(for: thatTask, addingLinkTo: "Curva")` returns the task's `rawLine` unchanged.

Red before Task 4. The parts that also need Task 2 (`linkTargets` in the pin and the agreement) are
red before Task 2 as well.

### Task 4 — Every other matcher calls the predicate (R-05, R-06, R-07, R-08)
Owner: coder
Files: Sources/Core/Links/BacklinkContext.swift, Sources/Features/Editor/BacklinksSection.swift, Sources/Core/Query/UnresolvedTargets.swift, Sources/Core/Conventions/RelatedLink.swift, Sources/Vault/NoteFileOperations.swift, Sources/Core/Canvas/WorkspaceReferences.swift, Sources/Core/Tasks/TaskParser.swift
Tests: BacklinkContextTests.swift, UnresolvedTargetsTests.swift, RelatedLinkTests.swift, NoteFileOperationTests.swift, WorkspaceReferenceTests.swift, TaskTests.swift, RelatedLinkSectionPreservationTests.swift, InspectorLinkRowsTests.swift, VaultLinkWritesTests.swift, ConnectorLinkWritesTests.swift
Signatures:
- Wikilink.names(_:) — func names(_ title: String) -> Bool
- Wikilink.target(_:names:) — static func target(_ target: String, names title: String) -> Bool
Red: no

Make Task 3 green.

**The changes, one per site:**

- **`BacklinkContext.swift`.**
  - `:18` becomes `$0.isNoteLink && $0.names(title)`.
  - `:58` becomes `$0.names(target)`.
  - Rewrite the doc comment at `:7-12`: a row matches the title a link names, as the index keys it
    (ADR-0097 §D1, amending ADR-0084 §D1). The `wanted` locals go.
- **`BacklinksSection.swift:124`.** `where link.names(title)`. The `wanted` local goes.
- **`UnresolvedTargets.swift:24`.** `$0.isNoteLink && $0.resolvedTitle == target`, exact, since the
  target it receives is now a resolved title. Update the doc at `:18-21`.
- **`NoteFileOperations.swift:158`.** `contains { $0.names(title) }`. The `needle` local goes.
- **`RelatedLink.swift`:**
  - `:46` becomes `existing.contains { Wikilink.target($0.target, names: target) }`;
  - `normalised` (`:210-216`) and its two callers (`:52`, `:65`) compare through the predicate, for
    example a `names(_ entry: String, _ target: String) -> Bool` private helper that unwraps the
    quotes and the brackets as `normalised` does today;
  - `removedLines` (`:188`) compares `linkTarget(of:)`'s result through
    `Wikilink.target(_:names:)`;
  - `linkTarget(of:)` (`:141-145`) still returns the literal interior: the sort-anchor test at `:115`
    only asks `!= nil`, so the insertion order does not change.
  - `RelatedSection.parse` and `discrepancies` (`Wikilink.swift:317-365`) are not touched (ADR-0097
    §D5: the linter compares two writings with each other).
- **`WorkspaceReferences.swift:39`.** `append(link.resolvedTitle)`. `BoardTray.resolvedPath(for:)`
  needs nothing more.
- **`TaskParser.swift:78`.** `.map(\.link.resolvedTitle)`. `:76` (`workspacePath`) and
  `annotatedLinks` (`:186-195`) stay literal (ADR-0097 §D5).

**Not unit-covered.** The highlight in `BacklinksSection.context(_:)` is a private view function,
covered by review. The predicate it calls is pinned in Task 1. A hand check is optional: H-1 under
Gates.

### Task 5 — Red: the cache drops version 7 rows (R-09)
Owner: tester
Files: Tests/IndexCacheTests.swift
Tests: IndexCacheTests.swift
Signatures:
- IndexCache.schemaVersion — static let schemaVersion: Int32
- IndexCache.load() — func load() -> [String: IndexCache.Entry]
- IndexCache.save(_:boardTasks:) — func save(_ records: [NoteRecord], boardTasks: [BoardTaskRecord] = []) -> Bool
Red: yes

**Only after G-schema is approved** (see Gates). If it is refused, this task and Task 6 are dropped.

- **New test, `aCacheStampedSevenIsNotReused`.** Same shape as `aCacheStampedFourIsNotReused`
  (`:168-181`): save, stamp `PRAGMA user_version = 7`, and expect `cache.load().isEmpty`. Its doc
  comment says a version 7 row holds an emphasised link's literal interior where `linkTargets` now
  holds the title it names (ADR-0097 §D4).
- **The literal pin at `:229`.** It moves to `== 8`. Its comment (`:222-228`) gains "and to 8 for a
  fifth (ADR-0097 §D4, `linkTargets` holds resolved titles)". The assertion's meaning is unchanged
  (ADR-0021 spends no bump of its own), exactly as ADR-0065's G1.1 moved it.

### Task 6 — Bump `IndexCache.schemaVersion` to 8 (R-09)
Owner: coder
Files: Sources/Index/IndexCache.swift
Tests: IndexCacheTests.swift
Signatures:
- IndexCache.schemaVersion — static let schemaVersion: Int32
Red: no

**Only after G-schema is approved.**

- `:218`: `= 8`.
- The doc comment (`:200-217`) gains "8 (ADR-0097 §D4): meaning only - version 7 rows hold the
  literal bracket interior of an emphasised link (`**Curva**`) where `linkTargets` now holds the
  title it names, and the scanner would reuse them until each file changed."
- No `StoredRecord` or `StoredTask` change.
- The protected-interfaces registry entry stays as it is. The value changes and the signature does
  not, and ADR-0065 records that the hook did not block its own bump.

### Task 7 — Record the amendment and the indexes, then run the whole suite (R-10)
Owner: coder
Files: docs/adr/0084-backlinks-with-context-unresolved-per-note-mentions-that-link.md, docs/adr/0097-a-link-names-the-title-it-resolves-to.md, docs/adr/INDEX.md, CLAUDE.md
Signatures:
- scripts/adr-index.py — prints the `## ADR index` lines; `--check` exits 1 on a stale or missing line
- scripts/check-adr-references.py — exits 0 clean, 1 on a finding, against origin/main
Red: no

1. **The pointer in ADR-0084.** Directly under ADR-0084's `**D1. A backlink row says why: the line,
   a count, a badge, a menu.**` heading (line 72), add one line:

   > Its comparison is amended by ADR-0097 §D1: a row and the index match a link by its
   > `resolvedTitle`, not its literal `target`. The one-predicate principle below stands.

   Change nothing else in ADR-0084. Its own text stays as the history of what was decided on
   2026-10-04.
2. **The `CLAUDE.md` index.** Run `scripts/adr-index.py`, paste the ADR-0097 line it prints into
   `CLAUDE.md`'s `## ADR index`, then run `scripts/adr-index.py --check`, which must exit 0.
3. **`docs/adr/INDEX.md`.** Append a long-form `- **ADR-0097** — ...` summary at the end of its
   "Chain decision index" section, in the shape of the ADR-0094 to ADR-0096 entries: `PG-399`, status
   `proposed`, D1 to D6 in a few sentences, "Amends ADR-0084 §D1, extends ADR-0065 §D9.4/§D9.5,
   `IndexCache.schemaVersion` 7 → 8", and the path.
4. **ADR-0097.** If G-schema was refused, rewrite §D4 to say so and name what persists. Record any
   departure of the build under an `## Implementation notes` heading. The status stays `proposed`
   until the merge.
5. **Checks.** `git fetch origin`, then `scripts/check-adr-references.py`. Run the full unit suite
   (TEST-CMD below), not only the touched test files.

## Gates (HITL)

- **GATE 1/2, plan approval.** The rule itself is decided at this gate: `resolvedTitle` everywhere a
  link is matched to a note, with ADR-0097's scope and explicit no's.
- **G-schema, asked together with GATE 1/2 so `/build` never runs Task 5 on an unapproved bump.**
  - What: approve `IndexCache.schemaVersion` 7 → 8. It is a protected interface, whose registry line
    reads "a silent bump invalidates ADR-0021 §D4". This bump is recorded, not silent.
  - Recommendation: **approve**. Without it, every unchanged emphasised-link note keeps the
    disagreement until the file changes or «Svuota cache» is used.
  - If refused: drop Tasks 5 and 6, and Task 7 rewrites ADR-0097 §D4.
- **Commit, push, PR, merge.** Human. The branch is `fix/burn-down-2026-10-16-pg-424-pg-399`. The
  untracked `docs/plans/burn-down-2026-10-15-pg-306.md` and the burn-down plan in `git status` are not
  this plan's files.
- **H-1, an optional hand check, not a merge condition.** On a Debug build, open `Curva` while
  another note holds `[[**Curva**]]`:
  - the backlinks section lists that note, with the link in the accent colour and the structural
    badge when `related` names it;
  - its unresolved section does not list `**Curva**`.

  No GUI test is added (ADR-0097 §D6). The GUI suite is a bounded backstop (`CLAUDE.md`, merge gate).
- **No deletions, migrations or file moves.** The cache is a derived store (principle 3). Dropping
  it is the bump's whole effect.

## Risks

- **Connector and view values change for emphasised links** (`links`, `resolved`, `unresolved`,
  `unresolved_links`, `backlinks`, a task's `links`, the view fields `links` and `unresolved`). The
  shapes do not change. `VaultAPI.LintFinding`, the protected JSON, is untouched. An external caller
  matching on the literal `**T**` would see `T`. None in this repository does (grep).
- **First launch rebuilds the cache.** `IndexCache.swift:201` says "a fraction of a second". That
  was not measured on the Labs vault for this plan: insufficient data on the real cost, expected to
  be the same order as bumps 5, 6 and 7.
- **`RelatedLink` becomes case-insensitive.** «Scollega» on `Curva` removes a `[[curva]]` entry,
  which `isStructural` already counted. This is a behaviour change beyond emphasis, made so the
  badge and the verb cannot disagree. ADR-0097 records it.
- **Stubs in `Sources` between Tasks 1 and 2.** They carry today's literal behaviour, so a build
  stopped there behaves as `main` does.
- **ADR number.** `0097` must be re-checked on every ref right before the merge (README rule 1). The
  only unmerged branch touching these files, `origin/fix/burn-down-2026-10-02-pg-378`, is stale:
  PG-378 shipped in PR #844.
- **Known flakes in a full run.** `Tests/QuickLookFocusTests.swift:245` (PG-408),
  `AttachmentChipMenuTests` (PG-407) and the wikilink double-click test can go red in a full run
  with no relation to this change. Rerun alone before treating one as a regression. Do not count one
  as green either.
- **`perg`/MCP smoke.** `Sources/Connector` and `Sources/MCPServer` are not edited, but the values
  they emit change. `scripts/mcp-smoke.py` is advisable after the build. It asserts no emphasised
  link, so it is a sanity check, not a test of this rule.
- **TODO.md.** PG-399 is closed at ship by the ledger sync, naming ADR-0097 and the PR. PG-424 stays
  open and is not part of this plan.

## For the person (decisions not taken here)

- **Bare quoted `related:` entries (`- "Curva"`, no brackets).** `NoteRename.rewritingQuotedRelated`
  rewrites them on a rename, and the index does not count them as backlinks: the same disagreement
  as PG-399, in a different shape. Whether F-06 admits that spelling is a harness-system convention
  question (principle 5), not an emphasis question, so ADR-0097 §D5 leaves it out.
  - Proposal: a new ledger entry.
  - Your call: is `- "Titolo"` a structural link the index should count, or a non-conformity the
    linter should report?
- **A wrapped transclusion `![[**Curva**]]`** becomes a backlink of Curva with this plan, but the
  editor's transclusion renderer, which uses its own embed parser, still does not draw it. This is
  pre-existing. Proposal: a P4 follow-up, if you want it drawn.

## Commands

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

The test command is the repository's own `.claude/test-cmd`, which is the merge gate (the unit suite
plus the in-process tests). For check: `.claude/check-cmd` is `NONE`. A `.swiftlint.yml` exists and
`swiftlint` is installed, but ADR-0044 item 10 records that SwiftLint fails on this codebase by
design, so a lint step would block on findings that predate this change. Run `tuist install` once in
a fresh worktree before the first generate (`CLAUDE.md`), and `tuist generate --no-open` after Task 1
adds two test files.

## Build result (2026-10-31)

BUILD · DONE WITH WARNINGS
Files: Sources/Core/Conventions/Wikilink.swift, NoteRename.swift, RelatedLink.swift; Sources/Core/Links/BacklinkContext.swift; Sources/Core/Query/UnresolvedTargets.swift; Sources/Core/Canvas/WorkspaceReferences.swift; Sources/Core/Tasks/TaskParser.swift, TaskParser+Writes.swift; Sources/Features/Editor/BacklinksSection.swift; Sources/Index/IndexCache.swift, IndexSnapshot.swift; Sources/Vault/NoteFileOperations.swift, NoteStore.swift, NoteStore+ReadSurface.swift; Tests/WikilinkNamesTests.swift (new), RenameBacklinkAgreementTests.swift (new), BacklinkContextTests, IndexCacheTests, NoteFileOperationTests, RelatedLinkTests, TaskTests, UnresolvedTargetsTests, WorkspaceReferenceTests; docs/adr/0097 (new), 0084, 0098, INDEX.md; CLAUDE.md
Tests: PergamenumTests 7142 run, exit 0, TEST SUCCEEDED (2 pre-existing Test «unknown» issues at HostedViewSupport.swift:46 are PG-434), 6 (coverage); perg and pergamenum-mcp build; adr-index.py --check and check-adr-references.py exit 0
Review: sonnet, safe; opus, safe
Coverage: not run, the plan's requirement set is not SPEC.md (plan R-01..R-09 tested, R-10 no-test, checked by the ADR scripts)
Dropped: 4 (unlocated 1, fix-hunk 2, post-sweep 1)
Dispatch: Round 0 (red): tester — Task 1, tester — Task 3, tester — Task 5
  Round 1 (sweep): coder — C1 TaskParser+Writes:108, coder — C2 ADR-0098:3, coder — NIT ADR-0097:8, coder — NIT ADR-0097:77, coder — WorkspaceReferenceTests:10, coder — RelatedLink:42
  Round 2 (sweep): coder — NIT IndexSnapshot:33, coder — IndexSnapshot:212
INFO: G-schema approved by the human on 2026-10-31 (IndexCache.schemaVersion 7 → 8)
INFO: tiered coder high opus/xhigh, Task 4 size: 7 files, high size 6
INFO: tiered tester high opus/high, Task 4 size: 7 files, high size 6
INFO: review escalated, size: 29 changed files, threshold 20
INFO: findings sweep answered Fix all
WARN: precondition DIRTY docs/adr/0097-a-link-names-the-title-it-resolves-to.md tolerated, it is this plan's ADR (docs/adr is this repo's ADR directory)

```text
FIX	swept	**MINOR** [other] Sources/Core/Tasks/TaskParser+Writes.swift:108 — The «Collega nota» duplicate check task.links.contains(target) is case-sensitive while ADR-0097 §D3 says it does not add a second link to a note the task already names and IndexSnapshot.swift:214 matches in lowercase, so a task holding [[curva]] gets a second [[Curva]] (pre-existing, R-08 met). (reviewer: opus)
FIX	swept	**MINOR** [other] docs/adr/0098-underscore-emphasis-is-concealed-and-the-daily-panes-draw-transclusions.md:3 — status `proposed` but already on origin/main, so check-adr-references.py rule 2 exits 1 on every branch until it becomes accepted. (follow-up: coder)
FIX	swept	**NIT** docs/adr/0097-a-link-names-the-title-it-resolves-to.md:8 — The Number bullet says the highest ADR on origin/main is 0096 and nothing exists at 0097 or above, but ADR-0098 is now on main; 0097 is still free. (reviewer: sonnet, opus)
FIX	swept	**NIT** docs/adr/0097-a-link-names-the-title-it-resolves-to.md:77 — §D1 says spaces and tabs, but the code trims .whitespaces (Unicode Zs plus tab, the same set NoteRename.fold uses). (reviewer: opus)
FIX	swept	**MINOR** [other] Tests/WorkspaceReferenceTests.swift:10 — the header comment still says `notes(in:)` is a signature-only stub returning `[]`. That is stale. (follow-up: tester)
FIX	swept	**MINOR** [other] Sources/Core/Conventions/RelatedLink.swift:42 — `guard target != selfTitle` still compares literal strings, so add(target: "curva", selfTitle: "Curva") is not refused as a self-link while the duplicate checks below now ignore case and emphasis. (follow-up: tester)
FIX	swept	**NIT** Sources/Index/IndexSnapshot.swift:33 — backlinkDisplayForm doc still says it keeps the spelling the user typed, but addBacklink now receives resolvedTitle so emphasis is dropped. (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Index/IndexSnapshot.swift:212 — tasks(linkingTo:) lowercases without trimming, the only comparison left outside the rule. (follow-up: coder)
DROP	unlocated	**MINOR** [other] `docs/adr/INDEX.md`: the long-form ADR-0098 entry is missing. (follow-up: coder)
DROP	fix-hunk	**MINOR** [plan-deviation] Sources/Core/Conventions/RelatedLink.swift:44 — The self-link check in RelatedLink.add now goes through Wikilink.target(_:names:), but neither plan Task 4 nor ADR-0097 §D3 asks for it, and ADR-0097 has no Implementation notes section as plan Task 7 step 4 requires. Fix: add an Implementation notes entry (or a §D3 bullet) to ADR-0097 recording the change and its test. (reviewer: opus)
DROP	fix-hunk	**MINOR** [other] Sources/Index/IndexSnapshot.swift:217 — The trim-then-lowercase fold that ADR-0097 §D1 calls the rule is written out four times (Wikilink.fold, NoteRename.fold, and closures in TaskParser+Writes.swift:110 and IndexSnapshot.swift:217), the drift ADR-0041 warns about. Fix: make Wikilink.fold internal and call it from the two task sites. (reviewer: sonnet, opus)
DROP	post-sweep	**NIT** Sources/Index/IndexSnapshot.swift:127 — tasks(linkingTo:) now trims its query but backlinks(toTitle:) only lowercases, so the reverse queries fold differently. Fix: fold the query in backlinks(toTitle:) too, or drop the trim and tasksLinkingToATitleFoldSpacesAndCase. (reviewer: opus)
```

### Post-build fixes (2026-10-31)

Stefano approved closing the dropped findings before `/ship` ("Sì, prima i MINOR"). Nothing committed.

- `DROP fix-hunk RelatedLink.swift:44` closed: ADR-0097 gains `## Implementation notes` (G-schema
  outcome, the sweep's three departures with their tests, the ADR-0098 status flip).
- `DROP fix-hunk IndexSnapshot.swift:217` closed: `Wikilink.fold` is internal and the one
  implementation; `NoteRename.fold` delegates to it, `TaskParser.line(for:addingLinkTo:)` and
  `IndexSnapshot.tasks(linkingTo:)` call it. Behaviour identical.
- `DROP post-sweep IndexSnapshot.swift:127` closed: `backlinks(toTitle:)` folds its query through
  `Wikilink.fold`, so both reverse queries agree. The query now also ignores surrounding whitespace.
- `DROP unlocated docs/adr/INDEX.md` closed: long-form ADR-0098 entry added after ADR-0097's.

- `IndexSnapshot.addBacklink` keys `backlinkIndex` by `Wikilink.fold(target)` and `orphans` reads it
  by `Wikilink.fold(record.title)`, so every write and read of that dictionary folds one way
  (Stefano: "Sì, allinea la 82"). The parser already trims a plain target (`Wikilink.swift:261`),
  so `[[ T ]]` was filed under `t` before too: a consistency change, no key moves, no cache bump
  (`schemaVersion` stays 8). Pinned by `aSpacedPlainLinkIsFoundByTheTitleAndByASpacedQuery`.

Tests: PergamenumTests 7143 run, exit 0, TEST SUCCEEDED (the 2 Test «unknown» issues at
HostedViewSupport.swift:46 are PG-434); perg and pergamenum-mcp build; adr-index.py --check and
check-adr-references.py exit 0. An earlier stop-gate run reported reds in NoteTextViewUpdatePinsTests
and ClassifySheetVaultSwitchHostedTests on a docs-only change; NoteTextViewUpdatePinsTests passed
13/13 alone and the full run above is green, so it is read as load, not a defect.

