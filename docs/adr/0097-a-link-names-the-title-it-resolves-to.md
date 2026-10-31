# ADR-0097: A link names the title it resolves to, for the rename, the index and every row

- Status: **proposed**. The implementation is not on `main`. Plan:
  `docs/plans/pg-399-rename-backlink-rule.md`. Flips to `accepted`, naming the code PR, its merge
  commit and the date, in the first docs change after that merge (`docs/adr/README.md` rule 2).
- Date: 2026-10-16. Written against `57edd30b` (`HEAD` = `origin/main`). Every line number below was
  read there.
- Number: `0097`. `git ls-tree` over every local and remote-tracking ref, rerun on 2026-10-31 after
  `git fetch origin`, finds no `docs/adr/0092*` and no `docs/adr/0097*` on any ref. ADR-0098 is on
  `origin/main` (PR #1036), and its own header records `0097` as held by this draft; nothing exists
  at `0099` or above. `0092` stays skipped
  for the reason ADR-0093's header records. Check again immediately before the merge (rule 1),
  including the branches about to merge.
- Source: ledger entry `PG-399` (`TODO.md`), and the burn-down of 2026-10-16
  (`docs/plans/burn-down-2026-10-16-pg-424-pg-399.md`), which chose this rule and left the entry open
  because applying it needs this record first. No SPEC applies.
- Relations:
  - **Amends ADR-0084 §D1**, its comparison sentence ("the link's `target`, lowercased ... not
    `resolvedTitle`, so `[[**T**]]` is no backlink of `T`"). A row and the index both match a link by
    its `resolvedTitle`. §D1's principle, one predicate for "a link the index counts" and "a link a
    row counts", stands, and is extended to "a link the rename rewrites".
  - **Extends ADR-0065 §D9.4 (R-19).** The rename's match becomes the shared predicate. Its
    behaviour does not change.
  - **Extends ADR-0065 §D9.5 (R-20).** A `.canvas` target is judged after the emphasis is stripped,
    so `[[**Q4.canvas**]]` stays out of the index.
  - **Moves `IndexCache.schemaVersion` 7 → 8** (protected interface, gate G-schema), meaning only, as
    ADR-0065 §D12 did for the same column (4 → 5). The bump is this record's, not ADR-0021's, so
    ADR-0021 §D4 stands.
  - Keeps ADR-0029 §D3 (a link run's decoration label shows what the file says).
- Why an ADR. It is hard to reverse: a cache bump, and connector output values. It is surprising
  without context: an accepted ADR says the opposite in so many words. It is a real trade-off: four
  ways were on the table (§Alternatives). Two overrides apply as well: it reverses an explicit "no"
  in ADR-0084 §D1, and it moves a protected constant.

## Context

Measured on `57edd30b`:

- **The rename.** `NoteRename.rewritingLinks` keeps the links with
  `fold($0.resolvedTitle) == needle` (`NoteRename.swift:33`), where `fold` is trim plus lowercase
  (`:78-80`). `[[**Forno tunnel**]]` follows a rename of `Forno tunnel` (ADR-0065 R-19, pinned by
  `NoteRenameCharacterizationTests.swift:86-110`).
- **The index.** `NoteStore.linkTargets(in:)` stores `link.target`, the literal bracket interior
  (`NoteStore+ReadSurface.swift:33-34`). `IndexSnapshot.rebuildDerivedIndexes` files body links under
  it (`IndexSnapshot.swift:88-89`) and `related` links under `link.target` (`:94-95`), lowercased by
  `addBacklink` (`:80-84`). The ledger cited `:79`; the code has moved, the claim has not.
- **The row.** `BacklinkContext.lines` and `BacklinkRow.isStructural` compare `target` on purpose
  (`BacklinkContext.swift:7-10`, `:18`, `:58`), as ADR-0084 §D1 says, pinned by
  `aRowComparesTheLinkTargetAsTheIndexKeysItNotTheResolvedTitle` (`BacklinkContextTests.swift:209-227`).
- **The editor.** Navigation and hover already take `resolvedTitle` (`MarkdownStyler.swift:555`,
  `NoteTextView+LinkPreview.swift:299`). `Wikilink.resolvedTitle`'s own comment says anything that
  resolves a link to a note wants it (`Wikilink.swift:20-28`).
- **Titles.** `*` is forbidden in a note title (`NoteName.swift:13`). Under the literal rule,
  `[[**T**]]` can name no note at all.
- **What a person sees.** Take a note `Curva` and a link `[[**Curva**]]` in `Fonte`. A click opens
  Curva, and a rename of Curva rewrites the link. But Curva's backlinks do not list Fonte, and
  Fonte's unresolved list shows `**Curva**`. After a rename to Nuovo it shows `**Nuovo**`. The rename
  changed the unresolved panel, which the app SPEC says it must not
  (`docs/20260811_Pergamenum_SpecApp.md:114`: "al termine l'app verifica che il pannello link non
  risolti sia invariato").
- **The same literal comparison elsewhere.** It is repeated by:
  - the row's highlight (`BacklinksSection.swift:124`);
  - «Vai al link» (`UnresolvedTargets.swift:24`);
  - the trash warning (`NoteFileOperations.swift:158`);
  - the structural verbs (`RelatedLink.swift:46`, `:52`, `:65`, `:144`, `:188`, `:215`);
  - a board's references (`WorkspaceReferences.swift:38-39`);
  - a task's links (`TaskParser.swift:78`).
- **The cache.** `StoredRecord.linkTargets` persists the list (`IndexCache.swift:269`). The scanner
  reuses a row whose size and modification date match (`VaultScanner.swift:94-101`). The version is
  bumped "whenever `StoredRecord` changes shape - or its meaning" (`IndexCache.swift:200`), and this
  column's meaning has moved twice before, each time with a bump: 2 (ADR-0010 §D7, transclusions
  counted) and 5 (ADR-0065 §D12, `.canvas` excluded). Tasks differ: `StoredTask` re-parses `rawLine`
  (`IndexCache.swift:351-355`, ADR-0021 §D4), so `TaskItem.links` follows the parser with no bump.

## Decision

**D1. One rule, one predicate.**

A wikilink names the note whose title equals its `resolvedTitle`, compared case-insensitively, with
surrounding horizontal whitespace ignored (`.whitespaces`: spaces, tabs and the other Unicode space
separators, the set `NoteRename`'s `fold` trims).

- `Wikilink.names(_ title: String) -> Bool` is that predicate.
- `Wikilink.target(_ target: String, names title: String) -> Bool` is the same predicate over a bare
  interior string, for the callers that hold one (a `StructuralLink.target`). The instance method is
  this one applied to `target`.
- The rename, the index and every matcher in D3 call it, or store exactly what it compares. No
  matcher compares the literal `target`.
- `resolvedTitle` trims surrounding horizontal whitespace (`.whitespaces`) after stripping its one
  marker pair. When that leaves nothing (`[[** **]]`) it is `target` unchanged. So the index's key,
  `resolvedTitle` lowercased, equals the rename's `fold`.
- One pair only, longest first, as R-19 has it: `[[***T***]]` names `*T*`, as it does today.

**D2. The index stores the resolved title.**

- `NoteStore.linkTargets(in:)` appends `link.resolvedTitle`, deduplicated on it, in source order:
  `[[**Curva**]] e [[Curva]]` gives `["Curva"]`.
- `Wikilink.isNoteLink` judges `resolvedTitle` in both halves. `[[**Q4.canvas**]]` stays a board
  (R-20), and `![[**foto.png**]]` stays a file.
- `IndexSnapshot`'s two `related` reads, the backlinks (`:95`) and the neighbourhood (`:164`), take
  `link.resolvedTitle`.
- Every reader of `linkTargets` inherits the rule with no change of its own: nine read sites in five
  files. They feed the backlinks, the per-note and vault-wide unresolved lists, `linked:` and
  `orphan:`, the view fields `links` and `unresolved` and the view graph, and the connectors' `links`,
  `resolved`, `unresolved`, `unresolved_links` and `backlinks`.

**D3. Every other matcher calls the predicate.**

- `BacklinkContext.lines` and `BacklinkRow.isStructural`, and the row's accent highlight
  (`BacklinksSection.context`).
- «Vai al link»: `UnresolvedTargets.firstLine(linking:in:)` compares `resolvedTitle` with the target
  it is given, exactly, since that target is now a resolved title.
- The trash warning: `NoteFileOperations.danglingLinks(for:knownPaths:)`.
- The structural verbs: `RelatedLink.add`'s two duplicate checks and `remove`'s two removals.
  «Scollega» then removes the `[[**Curva**]]` the badge counted, instead of skipping that side and
  reporting success. `RelatedLink` thereby matches case-insensitively, as `isStructural` already did.
- A board's «Note referenziate»: `WorkspaceReferences.notes(in:)` lists a text card's `[[**Curva**]]`
  as `Curva`.
- A task's links: `TaskParser` fills `task.links` with resolved titles. «Task collegati»
  (`IndexSnapshot.tasks(linkingTo:)`), which its own comment calls the reverse of the backlink
  relation, then finds the task, and «Collega nota» (`TaskParser+Writes.swift:108`) does not add a
  second link to a note the task already names, in any case. It folds both sides (trim, lowercase)
  rather than calling `Wikilink.target(_:names:)`, because `task.links` already holds resolved
  titles and resolving one again would turn a title `*T*` into `T`.

**D4. `IndexCache.schemaVersion` moves 7 → 8 (gate G-schema).**

- Meaning only: `StoredRecord` keeps its shape. A version 7 row holds literal targets, and the scanner
  would reuse it until each file changed.
- Precedent: ADR-0065 §D12, for this same column. The first launch rebuilds the cache from a full
  scan, and principle 3 holds.
- `StoredTask` needs nothing (ADR-0021 §D4).
- The literal pin in `IndexCacheTests.swift:229` moves to 8, its comment naming this record, and a
  test shows a cache stamped 7 is not reused.
- **If G-schema is refused:** no bump. Version 7 rows keep literal targets until each file changes or
  «Svuota cache» is used. For those notes the disagreement this record removes persists until then.

**D5. Explicit no's.**

These do not match a link to a note, so they stay outside the rule:

- `RelatedSection.parse` and `discrepancies` (the linter's W-06 and W-09). They compare the two
  writings of one structural link with each other, not with a note. `[[**Curva**]]` in `related`
  against `[[Curva]]` in the section stays a reported discrepancy.
- `EditorDecorationDelegate+LinkRendering.swift:82`, which labels a run with what the file says
  (ADR-0029 §D3).
- `NoteTextView+EmbedChip.swift:50`, `Transclusion.embeddedFiles` and the transclusion renderer.
  They read embeds through their own line parser. A wrapped transclusion `![[**Curva**]]` becomes a
  backlink of Curva here, but the editor still does not draw it, which is unchanged.
- `TaskParser.annotatedLinks`' Workspace assignment (`^[[X.canvas]]`), and the Contenitore and
  Pratiche link fields.
- A bare quoted `related:` entry (`- "Curva"`). The rename rewrites it
  (`NoteRename.rewritingQuotedRelated`) and the index does not count it. Whether F-06 admits it is for
  the harness-system convention to say (principle 5). It is not a question about emphasis, so it is
  left to the person as a separate ledger entry.

**D6. Tests.**

Pure and in-process, Swift Testing. Two agreement tests carry the rule:

- Over one corpus of spellings, a link the rename rewrites is one the index files as a backlink, and
  the reverse. A rename leaves the source note's unresolved targets unchanged.
- A row counts what the index counts, emphasis included. This is ADR-0084 §D1's pin, inverted.

Zero GUI tests: nothing here is a gesture.

## Alternatives considered

**Literal `target` everywhere, the rename included (undo R-19).** Rejected. `*` cannot appear in a
title, so `[[**T**]]` would name no note: always unresolved, while a click on it opens `T`, because
the styler resolves it. A rename would leave it pointing at nothing, which is the defect R-19 fixed.

**Resolve at derivation, keep `linkTargets` literal, no bump.** This is the no-schema-change answer
the ledger asked about, and it exists: `resolvedTitle` depends on the target alone, so `addBacklink`
could key by it from the cached strings. Rejected for three reasons:

- Nine read sites take `linkTargets`, and each would have to resolve on its own. The next one that
  forgets reopens this entry. That drift is what PG-399 is, and it is the shape
  `.claude/rules/vault-writes.md` warns about: a step a caller can forget gets skipped (ADR-0041).
- ADR-0021 §D4's no-bump argument holds where the cache stores the line and re-derives on decode
  (`StoredTask.rawLine`). `linkTargets` stores the derived list instead.
- Both earlier changes of this column's meaning changed the extraction and bumped.

**Resolve at extraction and again on decode, so version 7 rows are fixed on load.** Rejected. It
leaves rows of two meanings under one stamp, against the cache's policy of dropping rather than
migrating. And the resolution is not idempotent. `[[***T***]]` (bold italic) resolves to `*T*` when
the file is read, and to `T` if a cached `*T*` is resolved again, so a fresh scan and a reload
would disagree.

**Fix only the backlink path** (key `addBacklink` by the resolved title, the ledger's literal scope).
Rejected. The unresolved lists, the view fields, `linked:` and the connectors would still show
`**Curva**` as unresolved beside a backlink list that counts it. That is the same disagreement, one
panel over.

## Consequences

Positive:

- These all read `[[**Curva**]]` as a link to Curva: a rename, a click, the backlinks and their
  badge, the unresolved lists, «Scollega», the trash warning, a board's references and a note's
  linked tasks.
- A rename leaves the unresolved panel unchanged for emphasised links (app SPEC line 114).
- One predicate replaces the inline comparisons D2 and D3 list, so a new matcher has one thing to
  call.

Negative:

- The first launch after the update drops the index cache and scans the whole vault once.
- For emphasised links, values change but shapes do not. That covers `perg` and MCP output (`links`,
  `resolved`, `unresolved`, `unresolved_links`, `backlinks`, a task's `links`) and the view fields:
  `**Curva**` becomes `Curva`, and resolves. `VaultAPI.LintFinding`, the protected JSON shape, is not
  touched.
- `RelatedLink` matches case-insensitively: «Scollega» on `Curva` removes a `[[curva]]` entry.
- A note whose title is itself wrapped in `~~` is not reached by `[[~~T~~]]`, which names `T`. `~`
  is allowed in a title; `*` is not. Navigation and the rename already treat it this way, and now
  the index does too.
- `![[**foto.png**]]` is in neither `linkTargets` nor `embedTargets`.
- `BacklinkContextTests`' pin is inverted, not deleted. `IndexCacheTests`' literal pin moves to 8.

Neutral:

- No on-disk format, `StoredRecord` field, frontmatter key or `Project.swift` change.
- The rename's behaviour is unchanged, and `NoteRenameCharacterizationTests` stays green as written.
- No GUI test.

## Implementation notes

The landing evidence for the status line is written at the merge.

**Gate outcome (2026-10-31).** G-schema approved: `IndexCache.schemaVersion` is 8, as §D4 says, and
`aCacheStampedSevenIsNotReused` pins that a version 7 cache is dropped. The "if refused" branch of
§D4 did not apply.

**Departures from the plan (2026-10-31).** The review sweep of `/build` added three changes the plan's
tasks did not name. Each stays inside §D1's rule:

- **`RelatedLink.add`'s self-link guard calls the predicate.** §D3 named only `add`'s two duplicate
  checks. The guard now goes through `Wikilink.target(target, names: selfTitle)`, so `nota`,
  `**Nota**` and ` Nota ` are refused on the note `Nota` as the literal title is. Leaving the guard
  literal would have let a verb write a link the index then counts as a backlink of the note to
  itself. Test: `refusesToLinkANoteToItselfInAnotherCaseOrThroughEmphasis` (`RelatedLinkTests`).
- **`IndexSnapshot.tasks(linkingTo:)` trims as well as lowercases**, on both sides, so its key equals
  the rename's `fold` and the index's key (§D1). It used to lowercase only. Test:
  `tasksLinkingToATitleFoldSpacesAndCase` (`RenameBacklinkAgreementTests`).
- **«Collega nota»'s duplicate check folds both sides** (`TaskParser.line(for:addingLinkTo:)`), as the
  last sentence of §D3 now records, instead of comparing exactly. Tests:
  `linkingANoteTheTaskAlreadyNamesThroughEmphasisChangesNothing` and
  `linkingANoteTheTaskAlreadyNamesInAnotherCaseChangesNothing` (`TaskTests`).

**One fold (2026-10-31, after the build).** The trim-then-lowercase fold §D1 names is written once,
`Wikilink.fold`, internal. `NoteRename`, «Collega nota» and `IndexSnapshot.tasks(linkingTo:)` call it,
and `IndexSnapshot.backlinks(toTitle:)` folds its query through it too, so both reverse queries agree.
`addBacklink` keys `backlinkIndex` and `orphans` reads it through the same fold; the parser already
trims a plain target, so no key moves and `schemaVersion` stays 8. No other behaviour changes.

**Outside this record.** The same diff moves ADR-0098's status to `accepted` (PR #1036, `9bc493b4`),
a `docs/adr/README.md` rule 2 follow-up that was waiting for a docs change. It changes nothing
decided here.

## References

- `TODO.md` PG-399; `docs/plans/burn-down-2026-10-16-pg-424-pg-399.md`;
  `docs/plans/pg-399-rename-backlink-rule.md`.
- ADR-0084 §D1, §D2; ADR-0065 §D9.4, §D9.5, §D12; ADR-0021 §D4; ADR-0010 §D7; ADR-0029 §D3;
  ADR-0041.
- App SPEC `docs/20260811_Pergamenum_SpecApp.md` §4 (line 114, rename; F-06; W-01).
