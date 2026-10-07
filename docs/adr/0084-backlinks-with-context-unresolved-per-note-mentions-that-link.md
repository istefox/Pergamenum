# ADR-0084: Backlinks with context, unresolved per note, mentions that link

- Status: planned. Milestone N3 of the note-workflow chain (`PG-386`, #888), SPEC R-24..R-28.
  The implementation is not on `main`; the flip to `accepted` names the merge commit of the N3
  code PR.
- Date: 2026-10-04. Written against `48a2d912` (`origin/main` at the time). Every line number
  below was read there; N3 is built after N1 (ADR-0080) and N2 (ADR-0081, ADR-0082) merge, so the
  symbols named are the contract, not the lines.
- Number: `0084` reserved for this record by the chain's dispatch on 2026-10-04 and checked free
  on every ref (`git log --all -- 'docs/adr/0084*'` printed nothing). Check again immediately
  before the merge (`docs/adr/README.md` rule 1).
- Amends: the third decision of the unlinked-mentions mockup approved under ADR-0012 §D9
  (`Sources/Features/DesignGallery/UnlinkedMentionsMockup.swift`, "A row opens the note and
  nothing else"), by adding «Collega» (§D3). ADR-0012 §D9 itself (mentions computed on request,
  never cached) is kept and extended by one narrowing (§D3).
- Extends: ADR-0012 §D9, ADR-0023 §D1, ADR-0043 §D7/§D8 (the `expecting:` precondition),
  ADR-0049 §D4/§D5 (links read off the file, one resolver), ADR-0057 §D8 and ADR-0058 §D5
  (`addStructuralLink`'s half-done rule), ADR-0067 (the landed-change door that catches tabs up).
- Records: PG-233's decision of 2026-10-03, kept (§D5).
- Companion: ADR-0083 (the pointer and keyboard half of N3).

## Context

The note inspector (`VaultBrowser.inspector`, a `ScrollView` of `TraySection`s since PG-376)
answers "who points here" with a list of titles and nothing else, measured on `48a2d912`:

- **Backlinks without a reason.** `backlinks(_:)` draws one `Button(record.title)` per note from
  `IndexSnapshot.backlinks(toTitle:)`. Why that note links here, how often, and whether the link is
  a structural one (`related` in its frontmatter plus a bullet under `## Note correlate`, app SPEC
  §4.5 and wikilink.md W-04/W-05) needs opening it.
  There is no row menu.
- **Unresolved links of the whole vault, under one note.** `unresolved` draws
  `vault.index.unresolvedLinks(limit: 10)`, which is vault-wide: the inspector of note A lists
  dangling links of notes B, C and D, ten at most, and none of them can be acted on.
- **Mentions that can only be opened.** `UnlinkedMentionsSection` (ADR-0012 §D9) finds notes that
  name this one without linking it, on request, and a row opens the note. The mockup decision under
  §D9 refused «Collega» explicitly: "a write into a note you are not looking at, and the one write
  guardrail this app has is that you see what changes. It can be added later on its own reasoning".
- **Structural links are one-way to make and never unmade.** `RelatedLinkSheet` asks for both
  reasons blank, selects a target by title (ambiguous with two notes of one title, and
  `addStructuralLink` then takes `resolve(title:).first`), and nothing in the app removes a
  structural link: `RelatedLink.remove(target:from:)` exists, tested, with no caller.
- **Nothing says where a note is used outside notes.** A board's `.file` node and a pratica's
  `pergamenum-dossier-links-notes` (ADR-0049) both point at notes; the note cannot see either.

SPEC (root, Approved 2026-10-04) settled, and this record registers: the row menu (Apri, Apri
nell'altra colonna, Rendi strutturale; «Scollega» on structural rows); per-note unresolved links
with «Crea nota» and «Vai al link», the vault-wide list moving to a sample view, `perg note
unresolved` and its MCP tool unchanged; «Collega» behind a diff confirmation in one guarded write
refused when the note moved on; «Scollega» in two guarded writes with a half-done result named;
connector parity for "link a mention" and "remove a structural link"; PG-233's prompt kept;
«Dove compare» for boards and pratiche, read-only, no cache or schema change; context lines,
per-note unresolved targets and «Dove compare» read on demand and memoised by the index
generation; the index still stores paths only.

## Decision

**D1. A backlink row says why: the line, a count, a badge, a menu.**

One pure function, `BacklinkContext.lines(linking title: String, in text: String) -> [String]`
(`Sources/Core/Links/`), returns the trimmed body lines that hold a link to `title`, in order, one
entry per link. It walks `WikilinkParser.links(in:)` (code skipped by the parser) and keeps a link
by one predicate, `Wikilink.isNoteLink`, extracted from `NoteStore.linkTargets(in document:)`'s own
`where` clause and called by both, so "a link the index counts" and "a link a row counts" cannot
drift. The comparison is the index's: the link's `resolvedTitle`, lowercased, against the title,
lowercased. A note that links here only through `related` has no body line naming it outside the
`## Note correlate` bullet, and that bullet's line, reason included, is its context.

A row is a pure value, `BacklinkRow` (title, path, first line, count, `isStructural`), built from
the record and its text. The count shows when it is above one. `isStructural` is true when the
source's `frontmatter.related` names this note, read through `WikilinkParser` the way
`IndexSnapshot.neighbourhood` already reads `related`. The text comes from disk through
`VaultSession.read`, on demand, memoised by `(indexGeneration, title)` in the existing
`IndexKeyedMemo`; nothing is added to the index, which keeps storing paths (SPEC R-24).

The menu is one catalogue, `BacklinkCommand` (`open`, `openInOtherColumn`, `makeStructural`,
`unlink`), rendered as the row's `.contextMenu` and as its `.accessibilityActions` (ADR-0023 §D1).
`makeStructural` is offered on a row that is not structural, `unlink` («Scollega») only on one that
is. `open` and `openInOtherColumn` go through ADR-0083 §D1's door with a path. The inspector is a
`ScrollView`, not a `List`, so CLAUDE.md's nested-menu trap (ADR-0069) does not apply and a SwiftUI
menu is enough.

**D2. The inspector's unresolved links are the open note's own.**

`IndexSnapshot.unresolvedTargets(of path: String) -> [String]` answers for one note. Its body is one
pure derivation, `UnresolvedTargets.of(_ targets:resolving:)` (`Sources/Core/Query/`), now called
by the three places that each wrote it out: `ViewEvaluator`'s `graph.unresolved` (the query field
`unresolved`), `VaultAPI.links(_:at:)` and the new snapshot method. Same order (`linkTargets`'),
same duplicates rule, pinned by one test that runs all three over one corpus.

`UnresolvedLinksSection` lists them, deduplicated case-insensitively for display. Each row has
«Crea nota», ADR-0083 §D6's offer (the folder is this note's), and «Vai al link», which puts the
caret on the first source line holding `[[X]]` through `Navigation.jumpToLine(range:ordinal:)`,
the outline's own jump. A target that is not creatable (`[[X.md]]`) keeps «Vai al link» only.

The vault-wide list leaves the inspector and becomes a seventh sample view, «Vista - Link non
risolti» in `SampleViews` (`where: has(unresolved)`, `columns: [title, unresolved]`), installed
like the other six when the person asks (ADR-0011 §D5). `IndexSnapshot.unresolvedLinks(limit:)`
stays, because `perg note unresolved` and the MCP `unresolved_links` tool read it and the SPEC
keeps them unchanged.

**D3. «Collega» writes the link the person was shown.**

The mockup refused «Collega» because a write into a note you are not looking at breaks the one
guardrail "you see what changes". «Collega» meets that condition instead of waiving it: nothing is
written before the person has seen the diff of the exact bytes that will land. The refusal said it
could be added on its own reasoning; this is that reasoning.

*Which words.* `UnlinkedMentions.firstMention(of names: [String], in text: String) -> Mention?`
returns the first mention's range in the original text and the text it matched. `firstMentionLine`
becomes a derivation of it, so the scan and the link cannot disagree about which mention is the
first. The match is the scan's rule, run on the original text (case and diacritic insensitive
`range(of:options:)`, whole words, outside wikilinks, body only), with one narrowing added to
ADR-0012 §D9's list: **a name inside fenced or inline code is not a mention.** Writing `[[…]]` into
code would change code, and a name in code is not prose about the note. `CodeFence.regions(in:)`
and the inline code spans already decide what code is.

*What it writes* (`MentionLink.rewrite(_:mention:title:)`, pure): `[[Titolo]]` when the matched
text is the title byte for byte, otherwise `[[Titolo|testo]]`, where `testo` is the matched text.
That covers the SPEC's alias case and also a mention that differs only by case or accents, so the
prose reads exactly as it did. `[[alias]]` alone would not do: `resolve(title:)` indexes titles,
not aliases, so it would be a dangling link.

*How it lands.* The confirmation sheet (`LinkMentionSheet`) reads the note, computes the rewrite
and shows `UnifiedDiff` through `DiffView`; «Collega» calls
`VaultSession.linkMention(in path: String, to title: String, expecting hash: String) async
-> LinkMentionOutcome` (`linked`, `noMention`, `movedOn`, `failed`), one `write(_:to:expecting:)`
with the hash of the bytes the diff was computed from. A `movedOn` refusal recomputes the diff in
place and says «La nota è cambiata: il confronto è stato aggiornato» (SPEC edge case). A `noMention`
(the name went, or a link to it arrived) says so and drops the row. The session re-reads after its
`await`, never acting on state read before it (ADR-0043 §D7). The note is in the backlinks after the
write, because the index takes the write immediately (ADR-0001), and leaves the mention list on the
next scan.

*Connectors* (SPEC: connector parity): `VaultAPI.linkMention(_:in:title:)` in
`Sources/Connector/VaultLinkWrites.swift`, armed by `VaultAPI.arm` like every write, answering a
`WriteSummary` with its diff. `perg note link-mention <percorso> <titolo>` and the MCP tool
`link_mention` (`path`, `title`, `dryRun` default true, present only under `--allow-write`).

**D4. Structural links: a mirrored reason, a path, and a way back.**

`RelatedLinkSheet` changes in three ways:

- **The reverse reason is an editable mirror.** It follows the forward reason as it is typed until
  the person edits it, and is never overwritten after that. The rule is a pure value,
  `ReverseReasonMirror`, so it is tested without a view.
- **A target is a path.** The candidate list is selected by path and a row shows its folder label
  when its title is shared (ADR-0083 §D5). `VaultSession.addStructuralLink(from:to:reason:
  reverseReason:)` becomes `addStructuralLink(from:toNoteAt:reason:reverseReason:)`, and its
  `resolve(title:).first` goes. An unknown path is reported by name, as an unknown title was.
- **«Rendi strutturale» preselects.** Opened from a backlink row, the sheet arrives with that row's
  path selected (`VaultController.beginStructuralLink(preselecting:)`).

«Scollega» is `VaultSession.removeStructuralLink(from sourcePath: String, toNoteAt targetPath:
String) async -> (removed: Bool, written: [WriteResult])`, over the existing
`RelatedLink.remove(target:from:)`. It is `addStructuralLink`'s shape inverted (ADR-0057 §D8,
ADR-0058 §D5): both removals are rendered before either write; each write carries `expecting:` its
own read hash; a side that holds no link to the other is skipped, not an error; neither side holding
one is a problem «nessun legame strutturale fra «A» e «B»»; a refusal on the second write leaves
the first and is named «legame strutturale tolto a metà: «A» non punta più a «B», ma il ritorno
resta», and `written` holds what landed so ADR-0067's door catches the tabs up. The row asks first
through `.confirmationDialog(_:isPresented:presenting:)` (CLAUDE.md: the value is the closure's
parameter, never re-read from `@State` inside the `Task`).

*Connectors*: `VaultAPI.removeStructuralLink(_:from:to:)`, `perg note unlink-related <percorso>
<percorso-destinazione>`, and the MCP tool `remove_structural_link` (`path`, `target`, `dryRun`
default true). The target is a path on both, so a connector never resolves a title to the first
match either. A half-done removal is a failure in the summary, worded as above.

**D5. A dirty source still raises the conflict prompt (PG-233, kept).**

«Collega» and «Scollega» write to disk through the session, whatever a tab holds. When a tab shows
a written note with unsaved edits, ADR-0067's landed-change door reaches it and ADR-0058 §D1 asks
(ADR-0001 §D3.4's «Ricarica da disco» / «Tieni la mia versione»); a clean tab adopts the new text.
This is PG-233's decision of 2026-10-03, and the SPEC keeps it. The roadmap's task 9 and the
report's L-5 proposed saving the buffer first; that is ADR-0058's Alternative 5, rejected again for
the reason PG-233 gave: an implicit save breaks the explicit-save model (ADR-0012 §D3), and a link
has no history to protect, unlike `restoreVersion`. «Collega» on a mention never writes into the
open note's buffer either; the mention is in another note, and that note's bytes on disk are what
the diff showed.

**D6. «Dove compare» is asked for, read-only, and read off the files.**

A section under the backlinks, `WhereNoteAppearsSection`, in ADR-0012 §D9's shape: a resting
button («Cerca dove compare»), a scanning state, the results, «Cerca di nuovo». Asked for and not
automatic, because the pratiche half reads every message file's frontmatter, a vault-wide read of
the same order as the mention scan that §D9 put behind a button. The mockup shows both states, and
the person can choose automatic there.

What it reads, through `VaultSession.noteAppearances(of path: String) -> NoteAppearances`
(`Sources/Vault/VaultSession+Appearances.swift`, app only, not in `sharedSources`, since no
connector exposes it), with the pure join in `NoteAppearances.build(...)` (`Sources/Core/Links/`):

- **Boards**: `CanvasStore.allBoards()`, each loaded with `load(board:)`; a board appears once when
  any `.file(path:subpath:)` node's path equals the note's path. An unreadable board is skipped and
  counted in a footnote, never a failure.
- **Pratiche**: each `pratica.md`'s `pergamenum-dossier-links-notes` through `PraticaLinks.parse`,
  and each message file's `pergamenum-mail-note` through `MessageDocument.parse`, read off the files
  and never off `NoteRecord.frontmatter.foreignKeys`, which is empty on a cache-reused record
  (ADR-0049 §D4). Each reference counts only when `PraticaLinkResolver.note(candidates:)` answers
  `unique` for this note's path; an ambiguous reference is not claimed by either note. The folder
  enumeration is `VaultAPI.praticaNotes(among:vaultRoot:)` and `messageNotes(among:folders:)`,
  called, not copied.

A result is memoised by `(path, indexGeneration)`; «Cerca di nuovo» always rescans, because a board
save does not move the index generation. A board row sets `routeState.pendingCanvas`, the door a
board wikilink uses; a pratica row calls `PraticheController.select(_:in:)` and shows the Pratiche
pane; a message row opens its pratica. Nothing is written, no cache or schema changes
(`IndexCache.schemaVersion` stays where N1 and N2 leave it).

**D7. One GUI test, «Collega» a mention end to end.**

In a new file, `UITests/LinkMentionUITests.swift`, subclassing `PergamenumUITestCase`: open the
mentioned note, scan the mentions, «Collega» on the row, the sheet's diff exists, confirm, then the
other note's file on disk holds `[[Titolo]]` and the backlinks section lists it. In-process cannot
prove it: the inspector's buttons are SwiftUI rows, the in-process accessibility tree is one
childless group (PG-380), and a hosted view receives no mouse event (the harness refuses
`sendEvent`), so neither the row button nor the sheet's confirm can be pressed there. The locator,
the rewrite, the session write and its refusal, the connector and the section values are all
covered in-process; this test adds the gesture and the inspector refresh. With ADR-0083 §D8's two,
N3 has three GUI tests, the SPEC's ceiling.

## Alternatives considered

**Keep the mockup's refusal: mentions open, never link.** Rejected: the refusal's own condition,
seeing what changes, is met by the diff, and leaving the link to be typed by hand means opening the
other note, finding the word and wrapping it, the three steps «Collega» is for (report L-5, SPEC
R-26).

**Link every mention in the note at once.** Rejected: one mention, one diff, one write is reviewable
and refusable; a bulk rewrite is ADR-0012 §D7's tag-rename shape, with a vault-wide diff, and nobody
asked for it.

**Write `[[testo]]` for an alias mention.** Rejected: aliases are not resolved (`resolve(title:)`
reads `titleIndex`, titles only), so the link would dangle.

**Save the dirty buffer before linking (roadmap task 9, report L-5).** Rejected, D5: PG-233.

**Keep the vault-wide unresolved list in the inspector beside the per-note one.** Rejected: under a
note it answers a question about other notes, which is the defect; as a view it is one query the
person can sort, filter and keep.

**Backlink context in the index** (a stored line per link). Rejected: it would change the record
shape and `IndexCache.schemaVersion` for something read only when an inspector is open, and the
SPEC fixes "the index still stores paths only".

**«Dove compare» computed on every note open.** Not rejected outright, deferred to the mockup: it is
cheap for boards and expensive for message files, and the on-request shape is the one ADR-0012 §D9
already proved for a vault-wide read. Raised at the plan gate.

**Structural target by title, disambiguated in the sheet only.** Rejected: the session would still
resolve the title again, a second time, and could still pick the first match; the path is the only
reference that cannot be misread.

## Consequences

Positive:

- The inspector answers why a note links here and lets the person act on it from the row.
- Unresolved links are a to-do list for the open note instead of a vault-wide sample.
- A mention becomes a link in two clicks with the diff in front of the person, from the app and
  from either connector.
- A structural link can be made from a backlink, mirrored, and unmade.
- A note sees the boards and the pratiche that use it.

Negative:

- `addStructuralLink`'s signature changes (title → path): two app call sites (the controller's
  wrapper and the sheet) and ten test call sites in seven files are updated in the same PR, listed
  in the plan; their assertions keep their meaning with a path in place of a title.
- `VaultBrowser.InspectorSection.unresolved(shown:)` described a capped vault-wide list («mostrati»);
  it becomes `unresolved(count:)` for the open note («Link non risolti in questa nota: N»), and
  `InspectorSectionLabelTests` follows it.
- `SampleViews.all` grows to seven, so `everySampleViewParses`'s pinned block total goes from 9 to
  10; the test is updated, not loosened.
- The mention scan drops names that appear only in code, a narrowing of ADR-0012 §D9 that changes
  what the existing list shows.
- One more inspector section, and a button the person has to press for «Dove compare».
- One GUI test joins the bounded suite (D7).

Neutral:

- No on-disk format, frontmatter key, index field or schema change; no protected interface touched.
- `perg note unresolved`, the MCP `unresolved_links` tool and `IndexSnapshot.unresolvedLinks(limit:)`
  are unchanged.
- Adding a structural link from a connector is not in the SPEC and stays app-only.

## References

- SPEC (root, Approved 2026-10-04): N3 R-24..R-28; Decisions "Connector parity", "PG-233 stays";
  Data model; API; Edge cases on «Collega» and «Scollega»; Test seams 1, 4, 5, 6.
- `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` §2 N3 tasks 6..11;
  `docs/20261002_Pergamenum_NoteWorkflowReport.md` L-5, L-8, L-9.
- App SPEC §4.5 (structural links); ADR-0001 §D3.4, ADR-0011 §D5, ADR-0012 §D3/§D7/§D9, ADR-0023 §D1, ADR-0043 §D7/§D8, ADR-0049 §D4/§D5,
  ADR-0057 §D8, ADR-0058 §D1/§D5, ADR-0067, ADR-0069, PG-233, PG-376, PG-380.
- Plans: `docs/plans/note-workflow-n3-mockup.md`, `docs/plans/note-workflow-n3.md`.
