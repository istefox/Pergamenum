**Requirement set:** `SPEC.md`

# Note workflow N3, links: the code PRs

Milestone N3 of the note-workflow chain (`PG-386`, issue #888), code half, SPEC (root, Approved
2026-10-07) R-20..R-31. The mockup PR (`docs/plans/note-workflow-n3-mockup.md`, unchanged by this
revision) goes first; then three sessions, three PRs, as the SPEC's Decision "Three sessions" and
its Success criteria lay them out. This file replaces the 2026-10-04 revision written against
`48a2d912`, which assumed N1 and N2 unmerged, drew the preview in a `NeverKeyPanel` and had one
code PR.

**ADR outcome:** no new ADR. The governing records are the two already on `main` as `planned`,
edited in place by this planning pass and kept `planned`:

- `docs/adr/0083-links-answer-to-the-pointer-and-the-keyboard.md` (R-20..R-23). §D7 is rewritten
  for an `NSPopover` whose lifecycle the controller owns, its first Alternatives paragraph now
  rejects the `NeverKeyPanel`, and its stale facts are corrected (line numbers,
  `NoteTextView+LinkNavigation.swift`, «Apri collegamento» as a second follow path, ADR-0090 owning
  the pointer overrides, the parked draft settled by the SPEC).
- `docs/adr/0084-backlinks-with-context-unresolved-per-note-mentions-that-link.md` (R-24..R-28).
  Re-checked: it still stands after ADR-0090, which governs only the text views' pointer. Edited
  for what the SPEC settled («Dove compare» on request, connector parity mandatory), the session
  placement, the new shared session file and the scan button's identifier.

Both flip to `accepted` in Task 8 (R-31).

**Written against:** `origin/main` at `a2ada538` (2026-10-07). Every symbol and line below was read
on `5711ee0c`; the two commits since touch only `TODO.md` and `Tests/ConformanceTextTests.swift`.

**What is on `main`, re-checked:** N1 shipped (PG-384, PR #924; ADR-0080 and ADR-0088 accepted).
PG-219's pointer shipped as ADR-0090 (PR #920). ADR-0082's styler code is on `main` (PR #921,
`feature/pg-385-n2-page`) although its record still reads `planned` and PG-385 is open. ADR-0081 is
not on `main` (its mockup only). N3 needs neither ADR-0081 nor ADR-0082's status: it needs the
`.editorLink` attribute, which is present.

**The three seam facts,** verified on `a2ada538`, and re-run at the start of each session
(`git grep -n` on the three files); if one fails, stop and report, the seams moved:

1. The styler writes `.editorLink` (a `URL`): `MarkdownAttributedText.swift:27` declares it, `:232`
   sets it in `clickable(_:url:)`; `clickTarget(for:)` (`:329`) maps it to `LinkClickTarget`
   (`:314`: `.note(title:)`, `.embed(name:)`, `.external(URL)`, `.tag(Tag)`, `.day(CalendarDate)`).
   `WikilinkClickNavigationTests` pins it.
2. `CompletingTextView.linkCharacterIndex(at:)` is at `CompletingTextView+Pasteboard.swift:80`, a
   protected file.
3. `NoteTextView+Coordinator.textView(_:clickedOnLink:at:)` (`:244`) guards `.command` and calls
   `performLinkNavigation(_:)`, which now lives in `NoteTextView+LinkNavigation.swift`. The
   protected file's «Apri collegamento» (`openLinkFromMenu`, `:283`) calls the same method directly
   with no Command held: a second follow path, routed in Task 4.

**Sessions and PRs.**

| PR | Tasks | Criteria | Gate before it starts |
|---|---|---|---|
| Mockup | `docs/plans/note-workflow-n3-mockup.md` | R-29 | none |
| A | 1, 2 | R-22 (choice rule), R-24..R-28 (logic, writes, connectors), R-29, R-30 | none: no new view code |
| B | 3, 4 | R-20..R-23, R-29, R-30 | PR A merged; mockup approved before Task 4's view code |
| C | 5, 6, 7 | R-24..R-28 (UI), R-20, R-21, R-26, R-30 | PR B merged; mockup approved |
| Docs | 8 | R-31 | PR C merged |

**Requirement coverage:** R-20 Tasks 3, 4, 7. R-21 Tasks 3, 4, 7. R-22 Tasks 1, 2, 3, 4, 6. R-23
Tasks 3, 4. R-24 Tasks 1, 2, 5, 6. R-25 Tasks 1, 2, 5, 6. R-26 Tasks 1, 2, 5, 6, 7. R-27 Tasks 1, 2,
5, 6. R-28 Tasks 1, 2, 5, 6. R-29 Tasks 1, 4, 6. R-30 Tasks 2, 4, 7. R-31 Task 8.

**Order inside a session:** tester first, then coder. Every red task declares the signatures it
tests as stubs that compile and answer wrongly, never a trap (a stub that traps crashes the run
instead of failing a test), so the target builds and the tests are red, not absent. On Swift the
tester owns the declaration and the coder owns the body; a red batch that leaves a target unable to
build has produced no red at all.

## Tasks

### Task 1 — Session A, red: the choice rule, the inspector's pure units, the link writes and every `addStructuralLink` call site (R-22, R-24, R-25, R-26, R-27, R-28, R-29)
Owner: tester
Files: Sources/Core/Links/LinkDestination.swift, Sources/Core/Links/LinkChoice.swift, Sources/Core/Links/BacklinkContext.swift, Sources/Core/Links/MentionLink.swift, Sources/Core/Links/ReverseReasonMirror.swift, Sources/Core/Links/NoteAppearances.swift, Sources/Core/Query/UnresolvedTargets.swift, Sources/Core/Search/UnlinkedMentions.swift, Sources/Core/Conventions/Wikilink.swift, Sources/Core/Query/SampleViews.swift, Sources/Index/IndexSnapshot.swift, Sources/Vault/VaultSession+Notes.swift, Sources/Vault/VaultSession+LinkWrites.swift, Sources/Vault/VaultSession+Appearances.swift, Sources/App/VaultController+Notes.swift, Sources/Features/Editor/RelatedLinkSheet.swift, Sources/Connector/VaultLinkWrites.swift, Project.swift, Tests/LinkDestinationTests.swift, Tests/LinkChoiceTests.swift, Tests/BacklinkContextTests.swift, Tests/UnresolvedTargetsTests.swift, Tests/MentionLinkTests.swift, Tests/ReverseReasonMirrorTests.swift, Tests/NoteAppearancesTests.swift, Tests/VaultLinkWritesTests.swift, Tests/VaultControllerLinkWritesTests.swift, Tests/ConnectorLinkWritesTests.swift, Tests/IndexUnresolvedTargetsTests.swift, Tests/NoteAppearancesSessionTests.swift, Tests/RelatedLinkTests.swift, Tests/VaultControllerWriteCatchUpTests.swift, Tests/VaultUnguardedWriteGuardTests.swift, Tests/VaultControllerLandedChangeTests.swift, Tests/RelatedSectionLineRolesTests.swift, Tests/NoteByteOrderMarkTests.swift, Tests/RelatedLinkSectionPreservationTests.swift, Tests/ViewConnectorTests.swift
Tests: LinkDestinationTests.swift, LinkChoiceTests.swift, BacklinkContextTests.swift, UnresolvedTargetsTests.swift, MentionLinkTests.swift, ReverseReasonMirrorTests.swift, NoteAppearancesTests.swift, VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift, ConnectorLinkWritesTests.swift, IndexUnresolvedTargetsTests.swift, NoteAppearancesSessionTests.swift, RelatedLinkTests.swift, VaultControllerWriteCatchUpTests.swift, VaultUnguardedWriteGuardTests.swift, VaultControllerLandedChangeTests.swift, RelatedSectionLineRolesTests.swift, NoteByteOrderMarkTests.swift, RelatedLinkSectionPreservationTests.swift, ViewConnectorTests.swift
Signatures:
- LinkDestination — `enum LinkDestination: Equatable, Sendable { case note(path: String), board(path: String), ambiguous(title: String, paths: [String]), missing(title: String, creatable: Bool), missingBoard(name: String) }`
- LinkDestination.resolve — `static func resolve(_ target: String, notePaths: (String) -> [String], board: (String) -> String?) -> LinkDestination`
- LinkDestination.isCreatable — `static func isCreatable(_ title: String) -> Bool`
- LinkChoice — `struct LinkChoice: Equatable, Sendable, Identifiable { enum Action: Equatable, Sendable { case open(path: String), create(title: String) }; let id: String; let label: String; let detail: String; let action: Action }`
- LinkChoice.entries — `static func entries(for destination: LinkDestination) -> [LinkChoice]`
- LinkChoice.folderLabel — `static func folderLabel(of path: String) -> String`, `static let rootLabel = "radice del vault"`
- BacklinkContext.lines — `static func lines(linking title: String, in text: String) -> [String]`
- BacklinkRow — `struct BacklinkRow: Equatable, Sendable, Identifiable { var id: String { path }; let title: String; let path: String; let firstLine: String?; let count: Int; let isStructural: Bool; static func make(path: String, title: String, text: String, linking target: String, related: [String]) -> BacklinkRow }`
- Wikilink.isNoteLink — `var isNoteLink: Bool { get }`
- UnresolvedTargets.of — `static func of(_ targets: [String], resolving: (String) -> [String]) -> [String]`
- UnresolvedTargets.firstLine — `static func firstLine(linking target: String, in text: String) -> Int?`
- UnlinkedMentions.Mention — `struct Mention: Equatable, Sendable { let range: NSRange; let matched: String; let line: String }`
- UnlinkedMentions.firstMention — `static func firstMention(of names: [String], in text: String) -> Mention?`
- MentionLink.rewrite — `static func rewrite(_ text: String, mention: UnlinkedMentions.Mention, title: String) -> String`
- ReverseReasonMirror — `struct ReverseReasonMirror: Equatable, Sendable { private(set) var reverse: String; private(set) var isEdited: Bool; mutating func forwardChanged(to forward: String); mutating func reverseEdited(to text: String) }`
- NoteAppearances — `struct NoteAppearances: Equatable, Sendable { struct Board: Equatable, Sendable { let path: String; let name: String }; struct Pratica: Equatable, Sendable { let folder: String; let title: String; let linksNote: Bool; let messages: [String] }; let boards: [Board]; let pratiche: [Pratica]; let unreadableBoards: Int; static let empty: NoteAppearances }`
- NoteAppearances.build — `static func build(notePath: String, boards: [(path: String, filePaths: [String])], unreadableBoards: Int, praticaLinks: [(folder: String, references: [String])], messageLinks: [(path: String, folder: String, reference: String)], candidates: (String) -> [String]) -> NoteAppearances`
- IndexSnapshot.unresolvedTargets — `func unresolvedTargets(of path: String) -> [String]`
- VaultSession.LinkMentionOutcome — `enum LinkMentionOutcome: Equatable, Sendable { case linked(WriteResult), noMention, movedOn, failed(String) }`
- VaultSession.planLinkMention — `func planLinkMention(in path: String, to title: String) -> (before: String, after: String, hash: String)?`
- VaultSession.linkMention — `func linkMention(in path: String, to title: String, expecting hash: String) async -> LinkMentionOutcome`
- VaultSession.addStructuralLink — `func addStructuralLink(from sourcePath: String, toNoteAt targetPath: String, reason: String, reverseReason: String) async -> (created: Bool, written: [WriteResult])`
- VaultSession.removeStructuralLink — `func removeStructuralLink(from sourcePath: String, toNoteAt targetPath: String) async -> (removed: Bool, written: [WriteResult])`
- VaultSession.noteAppearances — `func noteAppearances(of path: String) -> NoteAppearances`
- VaultController.addStructuralLink — `func addStructuralLink(from sourcePath: String, toNoteAt targetPath: String, reason: String, reverseReason: String) async -> Bool`
- VaultController.removeStructuralLink — `func removeStructuralLink(from sourcePath: String, toNoteAt targetPath: String) async -> Bool`
- VaultController.linkMention — `func linkMention(in path: String, to title: String, expecting hash: String) async -> VaultSession.LinkMentionOutcome`
- VaultAPI.linkMention — `static func linkMention(_ session: VaultSession, in path: String, title: String) async throws -> WriteSummary`
- VaultAPI.removeStructuralLink — `static func removeStructuralLink(_ session: VaultSession, from path: String, to target: String) async throws -> [WriteSummary]`
- SampleViews.all — `static let all: [Sample] = [clients, projects, readings, orphans, deadlines, weeklyReview, unresolvedLinks]`, the seventh named «Vista - Link non risolti»
Red: yes

**R-29, the gate.** Session A opens with the mockup PR, which the person reviews on the Debug build,
light and dark, while A is built. Tasks 1 and 2 write no new view code: the one view file they
touch, `RelatedLinkSheet.swift`, passes a path where it passed a title and re-tags its `List`
selection by path, and draws nothing new. PR A may therefore merge before the approval; Tasks 4 and
6 may not start their view code before it.

**Placement.** Every file under `Sources/Core` is Foundation-only and compiles into `perg` and
`pergamenum-mcp` (a SwiftUI or AppKit import breaks both tool builds, CLAUDE.md "AI connector").
`Sources/Core/Links/` is a new folder under the existing `Sources/Core/**` glob. The session's new
doors go in a **new** `Sources/Vault/VaultSession+LinkWrites.swift`, because `VaultSession+Notes.swift`
is at 289 lines and would cross the 400-line warning; the connectors call them, so this task adds
that one file by name to `sharedSources` in `Project.swift` and runs `tuist generate --no-open`.
`VaultSession+Appearances.swift` is new and stays out of `sharedSources` (no connector exposes it,
SPEC Constraint "the appearances reader stays app-only"). `addStructuralLink` stays where it is and
changes its label only. `Sources/Connector/VaultLinkWrites.swift` is new, under the globbed
`Sources/Connector/**`; `VaultWrites.swift` is at 381 lines.

**The contract change, and every call site the grep found.** `git grep -n "addStructuralLink(" --
Sources Tests UITests scripts` on `a2ada538`:

- `Sources/Vault/VaultSession+Notes.swift:235` (the definition: `to targetTitle:` becomes
  `toNoteAt targetPath:`; its `resolve(title:).first` is `:241`)
- `Sources/App/VaultController+Notes.swift:97` (the wrapper) and `:104` (its call)
- `Sources/Features/Editor/RelatedLinkSheet.swift:87` (the sheet's `create()`)
- `Tests/RelatedLinkTests.swift:143`, `:172`, `:189`
- `Tests/VaultControllerWriteCatchUpTests.swift:353`, `:378`
- `Tests/VaultUnguardedWriteGuardTests.swift:100`
- `Tests/VaultControllerLandedChangeTests.swift:310`
- `Tests/RelatedSectionLineRolesTests.swift:236`
- `Tests/NoteByteOrderMarkTests.swift:110`
- `Tests/RelatedLinkSectionPreservationTests.swift:57`

Rerun the grep before editing and add anything new. This task changes the label at every site and
passes the target's **path** where a title was passed. The session's body is left as it is (it still
resolves what it is given as a title), which is what makes the path-based assertions red until
Task 2. No assertion is weakened: each keeps its meaning with a path in place of a title;
`reportsATargetThatDoesNotExist` becomes "a path that does not exist", and its problem still names
it. This is a test change, stated here and in the PR body as the CLAUDE.md rule asks: the API
changed shape on purpose (ADR-0084 §D4), the tests follow the API, none is disabled.

**The second pinned value.** `Tests/ViewConnectorTests.swift:134`, `everySampleViewParses`, pins
`total == 9` blocks across `SampleViews.all`. The seventh sample (one block) makes it `10`; the pin
is updated with a comment naming the new sample, which is why the pin exists. The two install tests
(`:161`, `:171`) count through `SampleViews.all.count` and need nothing;
`ViewDateBoundTests.swift:102` looks a sample up by name and needs nothing. The sample goes in this
task with its real text, since it is data a test reads: `where: has(unresolved)`, `sort: title`,
`render: table`, `columns: [title, unresolved]`, and one sentence of prose saying the inspector shows
the open note's own unresolved links and this view shows the vault's.

**Stubs** (wrong, never trapping): `resolve` returns `.missing(title:creatable: false)`, `entries`
`[]`, `lines` `[]`, `isNoteLink` false, `of` `[]`, `firstLine` nil, `firstMention` nil, `rewrite`
its input, the mirror's mutators nothing, `build` `.empty`, `unresolvedTargets` `[]`,
`planLinkMention` nil, `linkMention` `.failed("")`, `removeStructuralLink` `(false, [])`,
`noteAppearances` `.empty`, the controller wrappers false, the two `VaultAPI` functions throw a
`ConnectorError` saying «non implementato». `UnlinkedMentions.firstMentionLine` keeps its body.

**What each new test pins** (Swift Testing, `@Test` functions, Italian failure messages as the suite
writes them; each file cites its ADR section in a header comment):

- `LinkDestinationTests`: one path → `.note`; two → `.ambiguous` with the paths in the order
  `resolve(title:)` gives; none → `.missing`; `isCreatable` false for `TRUST.md`, `Cartella/Nota`,
  `a:b`, `X.canvas`, an empty and a 61-character title, true for `Bozza`; a `.canvas` target →
  `.board` when the board closure answers a path, `.missingBoard` when it answers nil (ADR-0083
  §D5, §D6).
- `LinkChoiceTests`: one row per path, label = folder label, `rootLabel` for a root note, detail =
  the path; a creatable `.missing` → one row «Crea «X»» with `.create`; every other destination → no
  rows; ids unique.
- `BacklinkContextTests`: one entry per link, in order; `[[T|alias]]`, `[[T#Sez]]` and `![[T]]`
  count; `[[T.canvas]]` and links inside fences do not; matching is case-insensitive; a note that
  links only through `related` yields its `## Note correlate` bullet line; `BacklinkRow.make`'s
  count, first line and `isStructural`; and **one agreement test**: over a fixed corpus, the set of
  targets `NoteStore.linkTargets(in:)` returns equals the set of targets of the links `isNoteLink`
  keeps (ADR-0084 §D1).
- `UnresolvedTargetsTests`: order and duplicates as given, resolved targets dropped; `firstLine`
  finds the first line holding `[[X]]`, `[[X|a]]` or `[[X#s]]`, skips code, nil when absent.
- `MentionLinkTests`: `firstMention`'s range is in the original text (a decomposed accent, a case
  difference, an alias); whole words only; never inside a wikilink, the frontmatter, a fence or an
  inline code span (ADR-0084 §D3's narrowing, new behaviour); `rewrite` gives `[[T]]` for an exact
  match and `[[T|testo]]` otherwise; and **one agreement test**: for every line of a corpus,
  `firstMention(...)?.line` equals `firstMentionLine(...)` except on the code lines, listed by name
  as the deliberate difference.
- `ReverseReasonMirrorTests`: follows the forward reason until edited; never overwritten after; an
  edit that happens to equal the forward text still counts as an edit.
- `NoteAppearancesTests`: a board appears once when any `.file` node's path equals the note's path,
  never for a sibling path or a prefix; a pratica reference claimed only when `candidates` gives one
  path and it is this note's (`PraticaLinkResolver.note(candidates:)`'s `unique`); an ambiguous
  reference claimed by nobody; a message grouped under its pratica; `unreadableBoards` passed
  through; output sorted by path.
- `VaultLinkWritesTests` (session): `linkMention` writes `[[T]]` / `[[T|testo]]` once, with
  `expecting:`; a hash that no longer matches → `.movedOn` and the file untouched; no mention left →
  `.noMention`; `planLinkMention`'s `after` is exactly what lands. `addStructuralLink(toNoteAt:)`
  with two notes of one title links the one named by path; an unknown path is a named problem.
  `removeStructuralLink`: both sides lose `related` and the bullet; one side holding nothing is
  skipped and the other still written; neither → «nessun legame strutturale fra «A» e «B»», nothing
  written; **the second write refused** through the symlink fixture `VaultUnguardedWriteGuardTests`
  already uses for `addStructuralLink` (deterministic, no timing): the first lands, the problem reads
  «legame strutturale tolto a metà: …» and names both, `written` holds the one that landed.
- `VaultControllerLinkWritesTests` (controller, PG-233, ADR-0084 §D5): a structural removal and a
  mention link on a note open **dirty** in a tab (focused, background, other column) raise ADR-0001
  §D3.4's prompt and never save the buffer; a clean tab adopts the new text (ADR-0067's door).
- `ConnectorLinkWritesTests`: `VaultAPI.linkMention` and `removeStructuralLink` under `arm(dryRun:
  true)` return a diff and change no byte; armed for real they write and journal; the title for
  `linkMention` is the target's and the path is the note written; a half-done removal returns the
  landed summary with a note naming the refused side.
- `IndexUnresolvedTargetsTests`: `unresolvedTargets(of:)` for one note; and **the three-way
  agreement test** over one vault: `IndexSnapshot.unresolvedTargets(of:)`, `VaultAPI.links(_:at:)
  .unresolved` and the query field `unresolved` (`ViewField.unresolved` through `ViewEvaluator`)
  give the same list for every note (SPEC API: one derivation, three callers).
- `NoteAppearancesSessionTests`: a temporary vault with a board holding a `.file` node on the note,
  a board that is not valid JSON (counted, not fatal), a pratica whose `pratica.md` lists the note in
  `pergamenum-dossier-links-notes`, a message whose `pergamenum-mail-note` names it, and a second note
  of the same title in another folder (claimed by neither); read from files, a cache-reused record
  included (ADR-0049 §D4).

Run the whole unit suite at the end: everything new is red, everything that was green stays green
except the ten relabelled structural-link sites and the pinned total, which are red by design.

### Task 2 — Session A, green: one derivation each for unresolved targets and link counting, the session doors, the connectors, `perg` and MCP (R-22, R-24, R-25, R-26, R-27, R-28, R-30)
Owner: coder
Files: Sources/Core/Links/LinkDestination.swift, Sources/Core/Links/LinkChoice.swift, Sources/Core/Links/BacklinkContext.swift, Sources/Core/Links/MentionLink.swift, Sources/Core/Links/ReverseReasonMirror.swift, Sources/Core/Links/NoteAppearances.swift, Sources/Core/Query/UnresolvedTargets.swift, Sources/Core/Search/UnlinkedMentions.swift, Sources/Core/Conventions/Wikilink.swift, Sources/Core/Query/ViewEvaluator.swift, Sources/Connector/VaultReads.swift, Sources/Vault/NoteStore+ReadSurface.swift, Sources/Index/IndexSnapshot.swift, Sources/Vault/VaultSession+Notes.swift, Sources/Vault/VaultSession+LinkWrites.swift, Sources/Vault/VaultSession+Appearances.swift, Sources/App/VaultController+Notes.swift, Sources/Connector/VaultLinkWrites.swift, Sources/CLI/main.swift, Sources/CLI/Commands/WriteCommands.swift, Sources/CLI/Help.swift, Sources/MCPServer/ToolCatalogue+NoteLinks.swift, Sources/MCPServer/VaultHost.swift, Sources/MCPServer/VaultHost+PraticheLinks.swift, Sources/MCPServer/VaultHost+NoteLinks.swift, scripts/mcp-smoke.py
Tests: LinkDestinationTests.swift, LinkChoiceTests.swift, BacklinkContextTests.swift, UnresolvedTargetsTests.swift, MentionLinkTests.swift, ReverseReasonMirrorTests.swift, NoteAppearancesTests.swift, VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift, ConnectorLinkWritesTests.swift, IndexUnresolvedTargetsTests.swift, NoteAppearancesSessionTests.swift, RelatedLinkTests.swift, VaultUnguardedWriteGuardTests.swift, ViewEvaluatorTests.swift, ViewEvaluatorWorkCountTests.swift, ViewEvaluatorGraphPinTests.swift, SearchTests.swift, VaultSessionTests.swift, ConnectorTests.swift, ViewConnectorTests.swift
Signatures:
- (Task 1's, bodies only)
- perg link-mention — `perg note link-mention <percorso> <titolo>`, with the write flags `noteRename` already takes
- perg unlink-related — `perg note unlink-related <percorso> <percorso-destinazione>`, with the same flags
- MCP link_mention — `{ "path": string, "title": string, "dryRun": boolean = true }`, a write tool, listed only under `--allow-write`
- MCP remove_structural_link — `{ "path": string, "target": string, "dryRun": boolean = true }`, a write tool, listed only under `--allow-write`
- ToolCatalogue.noteLinks — `static let noteLinks: [Tool]`
- VaultHost.writeNoteLinks — `func writeNoteLinks(_ name: String, _ arguments: ToolArguments) async throws -> CallTool.Result?`
Red: no

Make Task 1 green, then route the existing copies through the new single derivations:

- `NoteStore.linkTargets(in document:)` (`NoteStore+ReadSurface.swift:31`) keeps its loop and dedupe
  and replaces its `where` clause with `link.isNoteLink`, so the index and the backlink count share
  one predicate (ADR-0084 §D1).
- `ViewEvaluator`'s `Context.init` fills `graph.unresolved[path]` (`:220`) from
  `UnresolvedTargets.of(record.linkTargets, resolving: resolve)`, where `resolve` is its existing
  per-title memo, so the corpus is asked once per title as today. `ViewEvaluatorWorkCountTests` and
  `ViewEvaluatorGraphPinTests` stay green unmodified; if a work count moves, the memo was bypassed,
  and that is the defect to fix, not the pin.
- `VaultAPI.links(_:at:)` (`VaultReads.swift:33`) computes `unresolved` with `UnresolvedTargets.of`.
  Its JSON is unchanged.
- `UnlinkedMentions.firstMentionLine(of:in:)` becomes `firstMention(of:in:)?.line`. This narrows the
  mention scan (a name only in code is no longer a mention, ADR-0084 §D3); `SearchTests` (`:351`,
  `:359`, `:365`) and `VaultSessionTests` run green unmodified, and `VaultSession+Search.swift:150`
  keeps its call.

`firstMention` matches on the original text with `range(of:options: [.caseInsensitive,
.diacriticInsensitive])` per name, rejecting a hit that touches a letter or a digit on either side,
that overlaps a wikilink (the line's `WikilinkParser` ranges), that sits in `CodeFence.regions(in:)`
or in an inline code span, or that is in the frontmatter. The range is an `NSRange` over the whole
text (UTF-16, the unit `rewrite` and the editor use).

**Index:** `unresolvedTargets(of:)` is `UnresolvedTargets.of(notes[path]?.linkTargets ?? [],
resolving: resolve(title:))`, one line in `IndexSnapshot.swift`, which is shared, so the tools get it
free. `IndexCache.schemaVersion` stays 7.

**Session** (`VaultSession+LinkWrites.swift`, plus the one changed door in `VaultSession+Notes.swift`):

- `addStructuralLink(from:toNoteAt:...)` reads the target by path; `resolve(title:).first` goes.
  The rest of the body is unchanged (both renders before either write, `expecting:` on each, the
  half-done sentence).
- `removeStructuralLink` mirrors it over `RelatedLink.remove(target:from:)` with the titles read off
  both records; a side whose text does not change is not written; the problem strings are ADR-0084
  §D4's, word for word.
- `planLinkMention` reads the note, takes the target's `aliases` from the index record of the note
  titled `title`, calls `UnlinkedMentions.firstMention` with `[title] + aliases` and
  `MentionLink.rewrite`; the hash is computed the way `addStructuralLink` computes its `expecting:`.
  `linkMention` reads, plans again, compares the caller's hash with the read's (a mismatch is
  `.movedOn` with nothing written), and writes once with `expecting:` the read's hash; a
  `VaultWriteRefusal` from the write is `.movedOn`. Nothing read before an `await` is acted on after
  it (ADR-0043 §D7).
- `planLinkMention` remembers the hash of the `after` it returned, per path and lowercased title,
  in `shownMentionPlans` on the session (one entry per key, replaced by the next plan for it,
  consumed by the next `linkMention`, dropped by `forgetLinkMentionPlan(in:to:)` when the diff is
  cancelled): a replan whose `after` differs from the one shown is `.movedOn`, because the caller's
  hash covers the note's bytes but not the target's aliases; a caller that never planned is checked
  by the hash alone (ADR-0084 §D3).

**Appearances** (`VaultSession+Appearances.swift`, app only): `CanvasStore.allBoards()`,
`load(board:)` per board collecting `.file(path:subpath:)` paths (a throw counts as unreadable);
`VaultAPI.praticaNotes(among:vaultRoot:)` and `messageNotes(among:folders:)` for the folders and
message records, called, not copied; `PraticaLinks.parse(praticaFileAt:)` and
`MessageDocument.parse(text)?.frontmatter.linkedNote` read off the files; `candidates` resolves a
reference through `PraticaLinkReference(parsing:)` and `index.resolve(title:)`; then
`NoteAppearances.build`. Synchronous and main-actor, like `unlinkedMentions(for:)`; the section runs
it from a `Task` on request (Task 6).

**Connectors** (`Sources/Connector/VaultLinkWrites.swift`): `linkMention` checks the note exists,
plans, and writes through the session; `.noMention` throws «nessuna menzione non collegata di «T» in
«path»»; `.movedOn` throws `VaultWriteRefusal.movedOn(path).description` as `appendToNote` does; a
success is `summarise(result, session:)`. `removeStructuralLink` takes two paths, maps the outcome as
ADR-0084 §D4 says, and returns one `WriteSummary` per file written. Under `isDryRun` the session
computes both writes and performs neither, so a rehearsal returns both diffs.

**`perg`:** `main.swift`'s `noteGroup` (`:43`) gains the two words beside `rename`/`move`/`trash`
(`:47`..`:49`); `WriteCommands` gains `noteLinkMention` and `noteUnlinkRelated` in the shape of
`noteRename`; `Help.swift` documents both under the writes. `perg note unresolved`
(`NoteCommands.swift:14`) is not touched (SPEC R-25).

**MCP:** the two tools in a new `ToolCatalogue+NoteLinks.swift` (`ToolCatalogue+Writing.swift` is at
399 lines), as `ToolCatalogue.noteLinks`. `VaultHost.swift` reads `ToolCatalogue.writing` at `:36`
(`tools/list`) and `:173` (the write guard); both read `writing + noteLinks`, so the tools are listed
and dispatched only under `--allow-write`. Dispatch in a new `VaultHost+NoteLinks.swift`
(`writeNoteLinks(_:_:)`), chained from `writeMessageLinks`' `default:` in
`VaultHost+PraticheLinks.swift` the way that file chains from `writePraticaLinks`, arming
`VaultAPI.arm` with `dryRun` defaulting to `true`.

**`scripts/mcp-smoke.py`** gains a `note_links(binary, vault, check)` section in the shape of
`pratiche_links`, called from `main`: both tools absent without `--allow-write`; a `dryRun` call
returns a diff and the fixture file is byte-identical after it; a real `link_mention` leaves `[[T]]`
in the file; a real `remove_structural_link` leaves neither note with the `related` entry.

**Done means** (R-30): the whole unit suite green, `Pergamenum`, `perg` and `pergamenum-mcp` built
(a Core or Connector file that reaches for an app type breaks the two tool builds, not the app's),
and `python3 scripts/mcp-smoke.py` passing against the Debug `pergamenum-mcp`.

### Task 3 — Session B, red: the editor's pure units, the open-link door, the commands, the click variants, the creation row and the preview controller (R-20, R-21, R-22, R-23)
Owner: tester
Files: Sources/Core/Links/LinkOpening.swift, Sources/Core/Links/LinkAtCaret.swift, Sources/Core/Links/LinkPreviewTrigger.swift, Sources/Core/Links/LinkPreviewContent.swift, Sources/App/VaultController+LinkOpening.swift, Sources/App/VaultController+Notes.swift, Sources/Vault/NoteTab.swift, Sources/App/CommandActions+LinkNavigation.swift, Sources/App/CommandActions.swift, Sources/App/CommandActions+CanRun.swift, Sources/App/Navigation.swift, Sources/Core/Shortcuts/ShortcutCommand.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+LinkNavigation.swift, Sources/Features/Editor/NoteTextView+LinkAtCaret.swift, Sources/Features/Editor/NoteTextView+LinkPreview.swift, Sources/Features/Editor/LinkPreviewPopover.swift, Sources/Features/Editor/LinkChoiceMenu.swift, Sources/Features/Editor/CompletionPanel.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/QuickSwitcher.swift, Tests/LinkOpeningTests.swift, Tests/LinkAtCaretTests.swift, Tests/LinkPreviewTriggerTests.swift, Tests/LinkPreviewContentTests.swift, Tests/LinkOpeningControllerTests.swift, Tests/LinkFollowCommandTests.swift, Tests/WikilinkClickVariantTests.swift, Tests/LinkAtCaretReportTests.swift, Tests/LinkPreviewControllerTests.swift, Tests/LinkPreviewPopoverTests.swift, Tests/WikilinkCreationRowTests.swift, Tests/QuickOpenHeadingTargetsTests.swift, Tests/ShortcutTests.swift, Tests/CapturePanelTests.swift
Tests: LinkOpeningTests.swift, LinkAtCaretTests.swift, LinkPreviewTriggerTests.swift, LinkPreviewContentTests.swift, LinkOpeningControllerTests.swift, LinkFollowCommandTests.swift, WikilinkClickVariantTests.swift, LinkAtCaretReportTests.swift, LinkPreviewControllerTests.swift, LinkPreviewPopoverTests.swift, WikilinkCreationRowTests.swift, QuickOpenHeadingTargetsTests.swift, ShortcutTests.swift, CapturePanelTests.swift, OpenLinkUnresolvedTests.swift, WikilinkClickNavigationTests.swift, NoteEditorTeardownTests.swift, EditorCommandTests.swift, CommandActionTests.swift, NavigationHistoryTests.swift, CompletionPanelTests.swift
Signatures:
- LinkOpening — `enum LinkOpening: Equatable, Sendable { case replace, newTab, otherColumn; static func forClick(shift: Bool, option: Bool) -> LinkOpening }`
- LinkAtCaret.Run — `struct Run: Equatable, Sendable { var range: NSRange; var url: URL }`
- LinkAtCaret.pick — `static func pick(caret: Int, runs: [LinkAtCaret.Run], wikilinks: [NSRange]) -> URL?`
- LinkPreviewTrigger — `struct LinkPreviewTrigger: Equatable, Sendable { static let dwell: TimeInterval = 0.25; private(set) var shownRun: NSRange?; mutating func handle(_ event: Event) -> Effect }`
- LinkPreviewTrigger.Event — `enum Event: Equatable, Sendable { case pointer(run: NSRange?, commandDown: Bool, at: TimeInterval), command(isDown: Bool, at: TimeInterval), tick(TimeInterval), keyDown, escape, scroll, pointerExited, resignKey, textChanged, noteChanged, showFailed }`
- LinkPreviewTrigger.Effect — `enum Effect: Equatable, Sendable { case none, schedule(after: TimeInterval), show(run: NSRange), hide, hideConsumingEscape }`
- LinkPreviewContent — `struct LinkPreviewContent: Equatable, Sendable { enum Kind: Equatable, Sendable { case note(title: String, lines: [String], missingSection: String?), board(name: String), ambiguous(title: String, folders: [String]), missing(title: String, creatable: Bool) }; let kind: Kind; static let lineLimit = 12 }`
- LinkPreviewContent.make — `static func make(for destination: LinkDestination, section: String?, noteText: (String) -> String?) -> LinkPreviewContent?`
- VaultController.openNote(at:how:) — `func openNote(at relativePath: String, how: LinkOpening)`
- VaultController.openNoteInOtherColumn — `func openNoteInOtherColumn(at relativePath: String)`
- VaultController.recordLinkAtCaret — `func recordLinkAtCaret(_ url: URL?, inColumn columnIndex: Int)`, `var linkAtCaret: URL? { get }`
- VaultController.linkDestination — `func linkDestination(for target: String) -> LinkDestination`
- VaultController.linkPreviewContent — `func linkPreviewContent(for target: String, section: String?) -> LinkPreviewContent?`
- VaultController.offerNoteCreation — `func offerNoteCreation(title: String, besideNoteAt sourcePath: String?)` (in `VaultController+Notes.swift`, beside the private parked draft)
- NoteTab.linkAtCaret — `var linkAtCaret: URL?` (transient, never persisted by `OpenTabsStore`, reset by `showing(_:)`)
- LinkRequest — `struct LinkRequest: Equatable, Sendable { let target: String; let how: LinkOpening; let sourcePath: String?; let fromClick: Bool }`
- LinkFollowOutcome — `enum LinkFollowOutcome: Equatable, Sendable { case done, choose([LinkChoice]) }`
- LinkChoiceRequest — `struct LinkChoiceRequest: Identifiable, Equatable { let id: UUID; let title: String; let choices: [LinkChoice]; let how: LinkOpening; let sourcePath: String? }`
- Navigation.linkChoice — `var linkChoice: LinkChoiceRequest?`
- CommandActions.follow — `func follow(_ request: LinkRequest) -> LinkFollowOutcome`
- CommandActions.open(link:how:from:) — `func open(link target: String, how: LinkOpening = .replace, from sourcePath: String? = nil)`
- CommandActions.open(notePath:how:) — `func open(notePath: String, how: LinkOpening)`
- CommandActions.choose — `func choose(_ choice: LinkChoice, how: LinkOpening, from sourcePath: String?)`
- CommandActions.linkInputs — `func linkInputs(from sourcePath: String?, column: Int?, beforeFollow: (() -> Void)? = nil) -> NoteTextView.LinkInputs`
- CommandActions.runLinkOrHistory — `func runLinkOrHistory(_ command: ShortcutCommand)`
- ShortcutCommand — `case followLink, followLinkInNewTab, followLinkInOtherColumn` (appended last, section `.view`, titles «Segui il link», «Apri il link in una nuova tab», «Apri il link nell'altra colonna»), `static let shipsUnbound: Set<ShortcutCommand> = [.followLinkInNewTab, .followLinkInOtherColumn]`
- NoteTextView.LinkInputs — `struct LinkInputs { var follow: ((LinkRequest) -> LinkFollowOutcome)?; var choose: ((LinkChoice, LinkOpening) -> Void)?; var preview: ((String, String?) -> LinkPreviewContent?)?; var onCaretLinkChanged: ((URL?) -> Void)?; var offerCreation: ((String) -> Void)? }`, `var links = LinkInputs()` on `NoteTextView`
- NoteTextView.Coordinator.performLinkNavigation(_:how:fromClick:) — `@discardableResult func performLinkNavigation(_ link: Any, how: LinkOpening, fromClick: Bool) -> Bool`
- NoteTextView.Coordinator.linkChoiceMenus — `var linkChoiceMenus: LinkChoiceMenuPresenting`
- NoteTextView.Coordinator.linkPreview — `private(set) lazy var linkPreview: LinkPreviewController`
- LinkChoiceMenuPresenting — `@MainActor protocol LinkChoiceMenuPresenting: AnyObject { func present(_ menu: NSMenu, at point: NSPoint, in view: NSView) }`, production `final class LinkChoiceMenu: LinkChoiceMenuPresenting`
- LinkPreviewPresenting — `@MainActor protocol LinkPreviewPresenting: AnyObject { var isShowing: Bool { get }; @discardableResult func show(_ content: LinkPreviewContent, anchoredTo rect: NSRect, in view: NSTextView) -> Bool; func hide() }`
- LinkPreviewFocus — `struct LinkPreviewFocus: Equatable, Sendable { var windowIsKey: Bool; var textViewIsFirstResponder: Bool; static func lostKeyboard(before: LinkPreviewFocus, after: LinkPreviewFocus) -> Bool }`
- LinkPreviewPopover — `@MainActor final class LinkPreviewPopover: LinkPreviewPresenting { let popover: NSPopover; init() }`
- LinkPreviewController — `@MainActor final class LinkPreviewController { init(parent: @escaping () -> NoteTextView?, presenter: LinkPreviewPresenting, now: @escaping () -> TimeInterval, schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void); var hasEventMonitor: Bool { get }; var hasTrackingArea: Bool { get }; var isObservingWindowKey: Bool { get }; func attach(to textView: CompletingTextView); func pointerEntered(); func pointerMoved(to point: NSPoint, commandDown: Bool); func pointerExited(); func commandChanged(isDown: Bool); func keyPressed(isEscape: Bool) -> Bool; func scrolled(); func windowResignedKey(); func textChanged(); func noteChanged(); func tearDown() }`
- CompletionItem.createNote — `case createNote(title: String)`
- QuickSwitcher.headingTargets — `static func headingTargets(for notePart: String, exact: (String) -> [String], firstMatch: (String) -> String?) -> [String]`
Red: yes

**Before writing a test,** run the three seam checks of the plan header and
`WikilinkClickNavigationTests` green on the session's base (PR A merged).

**Placement.** `LinkOpening`, `LinkAtCaret`, `LinkPreviewTrigger` and `LinkPreviewContent` are
Foundation-only units in `Sources/Core/Links/`. They land here, in B, rather than in A: the SPEC's
Success criteria put R-20, R-21 and R-23 in B, and units nothing calls until B would ship dead in PR
A (raised at the plan gate, below). The new controller code goes in new files because
`VaultController+Tabs.swift` is at 412 lines and `CommandActions.swift` at 399. `CommandActions.swift`
changes by one line: `runView`'s `case .goBack, .goForward:` arm lists the three new commands and
calls `runLinkOrHistory(_:)` (in `CommandActions+LinkNavigation.swift`, which calls the existing
`walkHistory(_:)` in `CommandActions+CanRun.swift` for the two history commands), so the file gains
no line and `runView` no arm, the complexity its own header records. `NoteTextView.Coordinator`'s
class body is at the length the linter allows (`NoteTextView+LinkNavigation.swift` says so): it
gains the two stored properties above and nothing else; every body lives in an extension file.

**Stubs** (wrong, never trapping): `forClick` returns `.replace`; `pick` nil; `handle` `.none`;
`make` nil; `openNote(at:how:)` and `openNoteInOtherColumn` call today's `openNote(at:)`;
`recordLinkAtCaret` nothing; `linkDestination` `.missing(title:creatable: false)`;
`linkPreviewContent` nil; `offerNoteCreation` nothing; `follow` `.done` having called the old
`open(link:)` body unchanged; `choose` nothing; `linkInputs` `LinkInputs()`; `runLinkOrHistory`
calls `walkHistory` for `.goBack`/`.goForward` and does nothing for the rest, so
`NavigationHistoryTests` stays green; `canRun` answers false for the three (its switch has a
`default: false` already); the three default bindings are all `KeyBinding("")` for now (Task 4
measures, then binds `followLink`); `performLinkNavigation(_:how:fromClick:)` does what
`performLinkNavigation(_:)` does today and ignores the rest; `LinkChoiceMenu.present` nothing;
`LinkPreviewPopover.show` returns false; `LinkPreviewFocus.lostKeyboard` false; the controller's
methods nothing and its three flags false; `headingTargets` `[firstMatch(notePart)]` compacted. The
new `CompletionItem` case needs an arm in each exhaustive switch over it: the three in
`CompletionPanel.swift` (`id` at `:26`, the label at `:35`, the symbol at `:44`) answer
placeholders, and `apply` in `CompletingTextView.swift` (`:312`) does nothing; `refreshCompletion`
never produces the case. `CompletionPanelView` reads items through those properties and `if case`
tests, so it needs no change.

All hosted tests use the in-process family's harness (`Tests/HostedViewSupport.swift`,
`EmbedEditorFixtures.editor(...)` in `Tests/EmbedEditorTestSupport.swift`): no window ordered front,
no `sendEvent`, the `modifierFlags` seam for Command state (as `WikilinkClickNavigationTests` does),
an injected clock and scheduler, and every AppKit presentation behind a spy. A test that needs a
real menu, a real popover on screen or the real menu bar is not written here; it is Task 7's.

**Three existing tests change, and why** (CLAUDE.md: say so before changing a test). Each assumes
every command ships with a key; the SPEC decided two commands ship with none (Decision "One
open-link door with a how"). Amended, not disabled:

- `Tests/ShortcutTests.swift:54` `noTwoCommandsShipOnTheSameKeys`: the collision walk skips an empty
  `KeyBinding` (no key cannot collide with no key).
- `Tests/ShortcutTests.swift:67` `everyShippedDefaultIsUsable`: skips exactly the commands in
  `ShortcutCommand.shipsUnbound`. A new test pins that set to the two variants and asserts every
  command outside it ships a valid, usable key, so a third unbound command is a red test, and
  `followLink` is pinned to `KeyBinding("return", [.command, .option])` (red until Task 4).
- `Tests/CapturePanelTests.swift:32` `theDefaultBindingOfEveryCommandCanBeTranslated`: skips the
  commands in `shipsUnbound`, since an empty binding has no Carbon key by construction; every other
  command, `followLink` included, must still translate (`"return"` already does, for `taskToggle`).

Checked and **not** changed: `Tests/EditorCommandTests.swift:152` (`allCases.count - 2`) holds,
since the three commands stay in the slash catalogue and `canRun` keeps them out of it at runtime
(the caret sits on the typed `/`, never inside a link); `Tests/CommandActionTests.swift:107` only
asks `canRun` for every command; `Tests/OpenLinkUnresolvedTests.swift` stays green unmodified, since
`TRUST.md` is not creatable and its «nota non trovata» sentence stands, and `open(link: "TRUST")`
still switches to the Note pane. `ShortcutStore.conflicts` already ignores an invalid binding.

**New tests, red against the stubs:**

- `LinkOpeningTests`: the four Shift/Option combinations; Option wins over Shift (ADR-0083 §D2).
- `LinkAtCaretTests`: caret inside a run, at its start, at its end; inside `[[`, inside the alias,
  on `]]` → the run inside that wikilink; a markdown link whose label holds a wikilink → the
  wikilink's (innermost); two runs on a line → the one at the caret; no run (an embed) → nil.
- `LinkPreviewTriggerTests`: a pointer event with Command down schedules the dwell and shows nothing
  yet; `tick` at 250 ms shows; moving to another run restarts the dwell; Command up,
  `pointerExited`, `scroll`, `keyDown`, `resignKey`, `textChanged`, `noteChanged` → `hide`;
  `escape` while shown → `hideConsumingEscape`, while hidden → `none`; a `keyDown` during the dwell
  cancels it; `showFailed` returns to hidden and a new dwell is needed.
- `LinkPreviewContentTests`: twelve body lines at most, frontmatter never; a section through
  `Transclusion.excerpt(of:section:)`; a missing section named; a board's name; an ambiguous
  title's folder labels; a missing title with `creatable`; an external target never gets content.
- `LinkOpeningControllerTests`: `.replace` and `.newTab` keep today's behaviour; `.otherColumn` with
  one column adds the second (not `splitEditor`) and focuses it with the target in front and the
  source column untouched; with two columns focuses the other, deduping a tab already there; the
  focused column's index is what ADR-0015's destination reads afterwards; `linkAtCaret` is reset
  when the tab shows another note.
- `LinkFollowCommandTests`: `open(link:how:)` on an ambiguous title sets `navigation.linkChoice` and
  opens nothing; `follow(_:)` with `fromClick: true` returns `.choose` and sets nothing; a creatable
  missing title gives the one create choice; `choose(.create)` calls `offerNoteCreation` with the
  source's folder and puts the Note pane in front; a parked draft with a title is kept and the
  sentence recorded (SPEC edge case); `canRun(.followLink)` false with no link at the caret and
  outside the Note pane, true with one; `run(.followLink)` follows the focused tab's
  `linkAtCaret`, the two variants with their how; a board link opens the board whatever the how;
  `linkInputs(from:column:beforeFollow:)` focuses `column` and calls `beforeFollow` before following
  (the editor's `focused { }`, Diario's flush).
- `WikilinkClickVariantTests` (hosted): Cmd, Cmd+Shift, Cmd+Opt reach `links.follow` with
  `.replace`, `.newTab`, `.otherColumn` and `fromClick: true`; `performLinkNavigation(_:)` (the
  «Apri collegamento» path) reaches it with `.replace` and `fromClick: false`; with `links.follow`
  nil, Cmd still calls `onFollowLink` and the variants do nothing; a `.choose` outcome hands the spy
  presenter an `NSMenu` whose header is disabled and whose items are the folder labels; invoking an
  item calls `links.choose` with that choice and the click's how; tag and day targets keep N1's
  routing whatever modifiers are held.
- `LinkAtCaretReportTests` (hosted): moving the selection into, along and out of a link reports the
  URL once, then nil, through `links.onCaretLinkChanged`; a file embed reports nil;
  `recordLinkAtCaret` writes the column's active tab only.
- `LinkPreviewControllerTests` (hosted, spy presenter, injected clock and scheduler): `attach`
  installs one tracking area owned by the tracker with `.mouseMoved`, `.mouseEnteredAndExited`,
  `.activeInKeyWindow`, `.inVisibleRect`, and a second `attach` adds none; `pointerEntered` installs
  exactly one monitor and `pointerExited` removes it (`hasEventMonitor`); a note link shows the
  host's content after the dwell, anchored to the run's rect; an external URL or a file embed never
  asks for content or shows; Command up, `pointerExited`, a key, a scroll, `windowResignedKey`,
  `textChanged`, `noteChanged` and `keyPressed(isEscape: true)` hide, Escape consumed only while
  shown; the window-key observation exists only while shown (`isObservingWindowKey`); a presenter
  whose `show` returns false leaves the controller hidden until a fresh dwell; `tearDown()` hides and
  leaves all three flags false, also when the text view has no window (the `dismantleNSView` case);
  the text view is the window's first responder before, during and after; `links.preview` nil means
  the presenter is never called (ADR-0083 §D7, PG-258).
- `LinkPreviewPopoverTests`: the popover's `behavior` is `.applicationDefined` and `animates` is
  false; its content controller is an `NSHostingController` of `LinkPreviewView` (a placeholder view
  the stub may declare); `show` returns false without calling `NSPopover.show` for a text view with
  no window and for an empty rect (the documented exception never reached); `hide` on a never-shown
  presenter is a no-op; `LinkPreviewFocus.lostKeyboard` is true when the window stopped being key or
  the text view stopped being first responder, false when nothing changed or nothing was held
  before. No popover is ever shown on screen here.
- `WikilinkCreationRowTests`: an open `[[Bozza` with no candidate and `offerCreation` set lists
  `.createNote("Bozza")` as the only row; none when a candidate matches, when the text is not
  creatable (`a:b`, `Nota.md`), or with no handler; choosing it closes the link once through
  `insertWikilink(_:replacing:)`'s rule (never `]]]]`, n1-seams R-07) and calls the handler once.
- `QuickOpenHeadingTargetsTests`: a note part matching two titles exactly gives both paths; one
  exact match gives one; none falls back to the search's first, as today.

### Task 4 — Session B, green: the door, the keyboard, the variants and the choice, every follow site, the creation offer, the popover preview (R-20, R-21, R-22, R-23, R-29, R-30)
Owner: coder
Files: Sources/Core/Links/LinkOpening.swift, Sources/Core/Links/LinkAtCaret.swift, Sources/Core/Links/LinkPreviewTrigger.swift, Sources/Core/Links/LinkPreviewContent.swift, Sources/App/VaultController+LinkOpening.swift, Sources/App/VaultController+Notes.swift, Sources/Vault/NoteTab.swift, Sources/App/CommandActions+LinkNavigation.swift, Sources/App/CommandActions+CanRun.swift, Sources/App/MenuCommands.swift, Sources/App/Navigation.swift, Sources/App/RootView+Sheets.swift, Sources/Core/Shortcuts/ShortcutCommand.swift, Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift, Sources/Features/Editor/NoteTextView+LinkNavigation.swift, Sources/Features/Editor/NoteTextView+LinkAtCaret.swift, Sources/Features/Editor/NoteTextView+LinkPreview.swift, Sources/Features/Editor/NoteTextView+Requests.swift, Sources/Features/Editor/LinkPreviewPopover.swift, Sources/Features/Editor/LinkPreviewView.swift, Sources/Features/Editor/LinkChoiceMenu.swift, Sources/Features/Editor/LinkChoiceSheet.swift, Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/CompletingTextView+CreateNote.swift, Sources/Features/Editor/CompletionPanel.swift, Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Editor/QuickSwitcher.swift, Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Workspace/BoardTray.swift, Sources/Features/DesignGallery/LinkPreviewMockup.swift
Tests: LinkOpeningTests.swift, LinkAtCaretTests.swift, LinkPreviewTriggerTests.swift, LinkPreviewContentTests.swift, LinkOpeningControllerTests.swift, LinkFollowCommandTests.swift, WikilinkClickVariantTests.swift, LinkAtCaretReportTests.swift, LinkPreviewControllerTests.swift, LinkPreviewPopoverTests.swift, WikilinkCreationRowTests.swift, QuickOpenHeadingTargetsTests.swift, ShortcutTests.swift, CapturePanelTests.swift, OpenLinkUnresolvedTests.swift, WikilinkClickNavigationTests.swift, NoteEditorTeardownTests.swift, NavigationHistoryTests.swift, EditorCommandTests.swift, CommandActionTests.swift, CompletionPanelTests.swift, NeverKeyPanelTests.swift, EditorPointerTests.swift, MockupGalleryLayoutTests.swift
Signatures:
- (Task 3's, bodies only)
- LinkPreviewView — `struct LinkPreviewView: View { let content: LinkPreviewContent }`, identifier `link-preview`
- LinkChoiceSheet — `struct LinkChoiceSheet: View { let request: LinkChoiceRequest }`
Red: no

**R-29 first.** No step below that draws (`LinkPreviewView`, `LinkChoiceSheet`, the completion row,
the menu) starts before the person has approved the N3 mockup on the Debug build. When it is
approved, `LinkPreviewMockup`'s page label goes from «N3, da approvare» to «N3, approvato» in this
PR, the record the mockup plan names.

In this order, each step building and its tests green before the next:

1. **The door** (ADR-0083 §D1). `VaultController+LinkOpening.swift`: `openNote(at:how:)`,
   `openNoteInOtherColumn(at:)` (`addColumn()` then `focusColumn` of the new column with one column,
   `focusColumn` of the other with two, then `openNote(at:)`), `recordLinkAtCaret(_:inColumn:)` in
   `recordOutlineEntry`'s shape, `linkDestination(for:)` (the index's `resolve(title:)` and
   `WorkspaceBoardResolver.resolve(_:in:)` over `CanvasStore.allBoards()`, its `unique` answer the
   only board path) and `linkPreviewContent(for:section:)` (`linkDestination`, `session.read`,
   `LinkPreviewContent.make`). `offerNoteCreation` in `VaultController+Notes.swift` sets `noteDraft`
   with the title and the source's folder and `isComposingNote = true`, the way `beginNewNote` does;
   a parked draft with a title is kept and «Una nota è già in preparazione: completala o annullala,
   poi riprova» recorded. `NoteTab.showing(_:)` resets `linkAtCaret`.
   `CommandActions+LinkNavigation.swift`: `follow`, `open(link:how:from:)` (keeps the `.canvas`
   branch and PG-356's sentence, replaces `.first` with `linkDestination`), `open(notePath:how:)`,
   `choose`, `linkInputs` (which focuses `column` first, as `EditorColumnView.focused(_:)` does today
   for `follow(title:)`, `EditorColumnView.swift:189`/`:201`) and `runLinkOrHistory`.
2. **The keyboard** (ADR-0083 §D3). **Measure Cmd+Opt+Return against `com.apple.symbolichotkeys`
   before binding it** (`defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys`, the method
   the comments at `ShortcutCommand.swift:119`/`:297` record) and write the result in the case's
   comment; if it is taken, stop and report rather than pick another key (SPEC edge case). Then
   `followLink`'s default is `KeyBinding("return", [.command, .option])`. `canRun` gains one arm for
   the three. `MenuCommands` puts three items in Vista after Avanti (`:16`..`:21`, inside
   `CommandGroup(after: .sidebar)`), each `.keyboardShortcut(shortcuts.shortcut(for:))` and
   `.disabled(!actions.canRun(...))`, so the variants show no key until the person binds one.
   `NoteTextView+LinkAtCaret.swift`: on every selection change (one call from
   `textViewDidChangeSelection`, Coordinator `:137`) gather the caret paragraph's `.editorLink`
   runs and `WikilinkParser` ranges, call `LinkAtCaret.pick`, and report only when the URL changed.
   `EditorColumn+Text` wires it to `vault.recordLinkAtCaret(_:inColumn: columnIndex)` through
   `commandActions.linkInputs`.
3. **The variants and the choice at a click** (ADR-0083 §D2, §D5). `textView(_:clickedOnLink:at:)`
   keeps its Cmd guard and calls `performLinkNavigation(link, how: LinkOpening.forClick(...),
   fromClick: true)` with the flags from `modifierFlags()`. In `NoteTextView+LinkNavigation.swift`,
   `performLinkNavigation(_:)` (the protocol method the protected file calls for «Apri
   collegamento») forwards with `.replace` and `fromClick: false`; the routing body sends a `.note`
   target to `links.follow` when set and to `onFollowLink(title)` otherwise; a `.choose` outcome
   builds an `NSMenu` (disabled header, one item per choice) for `linkChoiceMenus.present(_:at:in:)`
   at the click point (the current event's location, converted), the production presenter calling
   `popUp(positioning:at:in:)`. `.external`, `.embed`, `.tag` and `.day` keep their arms.
   `LinkChoiceSheet` (title «Quale «X»?» or «Crea «X»?», the rows, Return, «Annulla») is hosted in
   `RootView+Sheets.swift` on `Bindable(navigation).linkChoice`, beside `taskPickingBoard`.
4. **Every follow site** (ADR-0083 §D5). `EditorColumn+Text` (`onFollowLink: follow(title:)` at
   `:73`) passes `links` from `commandActions.linkInputs(from:column: columnIndex)`, and
   `EditorColumnView.follow(title:)` stays the `onFollowLink` fallback. `TodayView` (`onFollowLink`
   at `:231`) and `DiaryView` (`follow(_:)` at `:141`) already read `CommandActions` from the
   environment and pass `links` too; Diario passes `beforeFollow: { controller.flush() }`, and Oggi
   now switches to the Note pane on a follow (ADR-0083 Consequences). `BoardTray.resolvedPath(for:)`
   (`:196`) calls `commandActions.open(link:)` when its title fallback resolves to several notes and
   keeps the path open otherwise. `QuickSwitcher.headingQuery` (`:221`) reads `headingTargets` and
   draws one heading group per path under its folder label. After this step,
   `git grep -n "resolve(title:" -- Sources` shows `.first` at none of the five follow sites of
   ADR-0083 §D5 (the transclusion source in `EditorColumn+Text.swift:274` and
   `QuickSwitcher.creationRow` are not follow sites and remain).
5. **Creation** (ADR-0083 §D6). `CompletionItem.createNote(title:)` gets its id, its label «Crea
   «X»» and its `plus.square` symbol in `CompletionPanel.swift`'s three switches, which
   `CompletionPanelView` already draws from; `refreshCompletion` (`CompletingTextView.swift:217`)
   adds it for `.wikilink(prefix)` when the candidates are empty, `LinkDestination.isCreatable(prefix)`
   holds and `offerCreation` is set; `apply` (`:301`, its switch at `:312`) completes the link through
   `insertWikilink(_:replacing:)`, then calls `offerCreation`. The logic lives in a new
   `CompletingTextView+CreateNote.swift`; each arm in `CompletingTextView.swift` stays one line (the
   file is at 387).
6. **The preview** (ADR-0083 §D7). `LinkPreviewController` in `NoteTextView+LinkPreview.swift`,
   created lazily by the Coordinator like `tables` and attached when `links.preview` is set: its
   tracker `NSResponder` owns the one tracking area (`.inVisibleRect`, no re-add on
   `updateTrackingAreas`, nothing on `CompletingTextView`'s own overrides, which are ADR-0090's);
   one local monitor (`.flagsChanged`, `.keyDown`, `.scrollWheel`) from `mouseEntered` to
   `mouseExited`, returning nil for Escape only while shown; the window-key observation only while
   shown; `pointerMoved` resolves the run through `linkCharacterIndex(at:)` and the attribute's
   effective range, and the section through `WikilinkParser` at that index; the dwell through the
   injected scheduler (production: a main-actor `Task.sleep` or `DispatchQueue.main.asyncAfter`,
   cancelled on hide). `LinkPreviewPopover` builds one `NSPopover` (`.applicationDefined`,
   `animates = false`, no detaching delegate), hosts `LinkPreviewView` (tokens only, light and dark,
   `appearance` from the text view's `effectiveAppearance`, identifier `link-preview`, nothing
   focusable), anchors it with `show(relativeTo:of:preferredEdge:)` to the run's rect after the
   layout is confirmed, guards the window, its visibility and an empty rect, and runs the
   `LinkPreviewFocus` check around `show`, closing and giving first responder back on a loss. Confirm
   on the Debug build that the preferred edge puts it **below** the line in the flipped text view,
   and that it never covers the link. `NoteTextView.dismantleNSView` (`NoteTextView.swift:280`) calls
   `coordinator.linkPreview.tearDown()`; the Coordinator's `textDidChange` calls `textChanged()`;
   the note-path change in `NoteTextView+Requests.swift` calls `noteChanged()`. `EditorColumn+Text`,
   Oggi and Diario supply `links.preview` through `linkInputs`, which calls
   `vault.linkPreviewContent(for:section:)`.

Keep every view under the token rule (CLAUDE.md "Design system"): no colour or font outside
`theme`. **Done means** (R-30): the whole unit suite green, not only the new tests (this PR changes
the shortcut catalogue, a contract three unrelated tests read); `Pergamenum`, `perg` and
`pergamenum-mcp` built (the Core units compile into the tools); a by-hand look at the popover and
the choice menu in light and dark on the Debug build.

### Task 5 — Session C, red: the inspector's models, labels and doors (R-24, R-25, R-26, R-27, R-28)
Owner: tester
Files: Sources/Features/Editor/BacklinkCommand.swift, Sources/App/VaultController+Inspector.swift, Sources/App/CommandActions+LinkNavigation.swift, Sources/Features/Editor/LinkMentionReview.swift, Sources/Features/Editor/WhereNoteAppearsScan.swift, Sources/Features/Editor/VaultBrowser.swift, Tests/BacklinkCommandTests.swift, Tests/InspectorLinkRowsTests.swift, Tests/LinkMentionReviewTests.swift, Tests/WhereNoteAppearsScanTests.swift, Tests/InspectorSectionLabelTests.swift
Tests: BacklinkCommandTests.swift, InspectorLinkRowsTests.swift, LinkMentionReviewTests.swift, WhereNoteAppearsScanTests.swift, InspectorSectionLabelTests.swift, VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift
Signatures:
- BacklinkCommand — `enum BacklinkCommand: CaseIterable, Identifiable, Sendable { case open, openInOtherColumn, makeStructural, unlink; var id: Self { self }; var title: String { get }; static func available(for row: BacklinkRow) -> [BacklinkCommand] }`
- VaultController.backlinkRows — `func backlinkRows(toTitle title: String) -> [BacklinkRow]`, memoised by `(indexGeneration, title)` in an `IndexKeyedMemo`
- UnresolvedLinkRow — `struct UnresolvedLinkRow: Equatable, Sendable, Identifiable { var id: String { target.lowercased() }; let target: String; let isCreatable: Bool }`
- VaultController.unresolvedLinkRows — `func unresolvedLinkRows(ofNoteAt path: String) -> [UnresolvedLinkRow]`
- VaultController.beginStructuralLink — `func beginStructuralLink(preselecting targetPath: String?)`, `var structuralLinkPreselection: String?`, `func takeStructuralLinkPreselection() -> String?`
- VaultController.noteAppearances — `func noteAppearances(ofNoteAt path: String, rescan: Bool) -> NoteAppearances`
- CommandActions.goToLink — `func goToLink(target: String)`
- VaultBrowser.InspectorSection — `static func unresolved(count: Int) -> InspectorSection` (replaces `unresolved(shown:)`), `static func whereAppears(found: Int?) -> InspectorSection`
- LinkMentionReview — `@MainActor @Observable final class LinkMentionReview { enum State: Equatable { case reviewing(diff: String, notice: String?), linked, nothingToLink, failed(String) }; init(vault: VaultController, notePath: String, title: String); private(set) var state: State; func confirm() async }`
- WhereNoteAppearsScan — `@MainActor @Observable final class WhereNoteAppearsScan { enum State: Equatable { case resting, scanning, found(NoteAppearances) }; init(vault: VaultController, notePath: String); private(set) var state: State; func scan(again: Bool) async }`
Red: yes

**Before writing a test,** confirm PR B is merged and the session's base builds. The inspector's
SwiftUI rows cannot be pressed in-process (the in-process accessibility tree is one childless group,
PG-380, and the harness refuses `sendEvent`), so what is tested here is everything the rows call:
the models, the labels and the controller doors. The views are Task 6's and the gesture is Task 7's.

**The contract change, and its call sites.** `git grep -n "unresolved(shown" -- Sources Tests
UITests` on `a2ada538`: `Sources/Features/Editor/VaultBrowser.swift:359` (the definition),
`VaultBrowser.swift:318` (its one caller, the current section) and
`Tests/InspectorSectionLabelTests.swift:24`. The function becomes `unresolved(count:)` with «Link
non risolti in questa nota: N», title and identifier (`inspector-unresolved-links`) unchanged; the
caller at `:318` passes the count it has until Task 6 replaces the section, and the test follows the
new label. This is a test change, stated here and in the PR body: the label described a capped
vault-wide list that ADR-0084 §D2 removes from the inspector.

**Stubs:** `available(for:)` `[]`, `title` `""`, `backlinkRows` `[]`, `unresolvedLinkRows` `[]`,
`beginStructuralLink` nothing, `takeStructuralLinkPreselection` nil, `noteAppearances` `.empty`,
`goToLink` nothing, `whereAppears` a section with an empty label, `LinkMentionReview` starting and
staying `.failed("")`, `WhereNoteAppearsScan` staying `.resting`.

**New tests, red against the stubs:**

- `BacklinkCommandTests`: a plain row offers open, openInOtherColumn, makeStructural; a structural
  row open, openInOtherColumn, unlink; the titles are the SPEC's Italian (Apri, Apri nell'altra
  colonna, Rendi strutturale, Scollega).
- `InspectorLinkRowsTests` (controller, temporary vault): `backlinkRows` gives the line, the count
  and the badge from the files, and a write that moves the index generation refreshes the line; the
  index record is unchanged (paths only, SPEC R-24); `unresolvedLinkRows` lists the open note's own
  dangling targets, deduplicated case-insensitively, `[[Piano.md]]` not creatable; `goToLink` sets
  the jump `navigation.jumpToLine(range:ordinal:)` reads for the first line holding `[[X]]`;
  `beginStructuralLink(preselecting:)` sets the preselection and raises `isAddingRelatedLink`, and
  `takeStructuralLinkPreselection` hands it over once; `noteAppearances(ofNoteAt:rescan: false)`
  answers from the memo for an unchanged generation, `rescan: true` sees a board saved since (a board
  save does not move the generation).
- `LinkMentionReviewTests` (controller, temporary vault): an unchanged note → `.reviewing` with the
  diff, `confirm()` → `.linked` and the file holds the link; the note written between review and
  confirm → `.reviewing` with the recomputed diff and «La nota è cambiata: il confronto è stato
  aggiornato»; the mention gone → `.nothingToLink`; an alias mention → the diff shows
  `[[Titolo|testo]]`.
- `WhereNoteAppearsScanTests`: `.resting` until asked; `scan(again: false)` → `.found` with the
  boards and pratiche of the fixture vault; `scan(again: true)` rescans.
- `InspectorSectionLabelTests`: `unresolved(count:)`'s label and `whereAppears(found:)`'s resting
  (nil) and counted labels.

### Task 6 — Session C, green: the inspector sections, «Collega», the structural sheet, «Scollega», «Dove compare» (R-22, R-24, R-25, R-26, R-27, R-28, R-29)
Owner: coder
Files: Sources/Features/Editor/BacklinkCommand.swift, Sources/App/VaultController+Inspector.swift, Sources/App/CommandActions+LinkNavigation.swift, Sources/Features/Editor/LinkMentionReview.swift, Sources/Features/Editor/WhereNoteAppearsScan.swift, Sources/Features/Editor/BacklinksSection.swift, Sources/Features/Editor/UnresolvedLinksSection.swift, Sources/Features/Editor/WhereNoteAppearsSection.swift, Sources/Features/Editor/UnlinkedMentionsSection.swift, Sources/Features/Editor/LinkMentionSheet.swift, Sources/Features/Editor/RelatedLinkSheet.swift, Sources/Features/Editor/VaultBrowser.swift, Sources/Features/DesignGallery/InspectorLinksMockup.swift, Sources/Features/DesignGallery/UnlinkedMentionsMockup.swift
Tests: BacklinkCommandTests.swift, InspectorLinkRowsTests.swift, LinkMentionReviewTests.swift, WhereNoteAppearsScanTests.swift, InspectorSectionLabelTests.swift, BacklinkContextTests.swift, ReverseReasonMirrorTests.swift, VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift, NoteAppearancesSessionTests.swift, RelatedLinkTests.swift, MockupGalleryLayoutTests.swift
Signatures:
- (Task 5's, bodies only)
- BacklinksSection — `struct BacklinksSection: View { let note: VaultController.OpenNote }`
- UnresolvedLinksSection — `struct UnresolvedLinksSection: View { let note: VaultController.OpenNote }`
- WhereNoteAppearsSection — `struct WhereNoteAppearsSection: View { let notePath: String }`
- LinkMentionSheet — `struct LinkMentionSheet: View { let review: LinkMentionReview }`
- accessibility identifiers — `backlink-row-<path>`, `unresolved-link-<target>`, `unlinked-mentions-scan`, `unlinked-mention-link-<path>`, `link-mention-confirm`, `where-appears-scan`
Red: no

**R-29 first**, as in Task 4: no view here before the approval; when approved, the
`InspectorLinksMockup` and `UnlinkedMentionsMockup` page labels record it («N3, approvato» and
«M10, N3 approvato»), the mockup plan's record.

`VaultBrowser.swift` (369 lines) is over SwiftLint's `type_body_length` warning already, so its two
private sections move out rather than grow: `backlinks(_:)` (`:293`) becomes `BacklinksSection`,
`unresolved` (`:314`) becomes `UnresolvedLinksSection`, and `inspector` (`:204`) reads, in order:
star, category link, history, `BacklinksSection`, `UnlinkedMentionsSection`,
`WhereNoteAppearsSection`, `LinkedTasksPanel`, `UnresolvedLinksSection`. `InspectorSection` stays in
`VaultBrowser` (its tests name it there) with `whereAppears(found:)` added. The sections are
`TraySection`s in a `ScrollView`, so a SwiftUI `.contextMenu` is enough (ADR-0069 applies to `List`
rows only, SPEC Constraint).

- **`BacklinksSection`** (ADR-0084 §D1): rows from `vault.backlinkRows(toTitle:)`, drawn as the
  approved mockup draws them (badge form as approved); `.contextMenu` and `.accessibilityActions`
  from `BacklinkCommand.available(for:)` (ADR-0023 §D1); `open` and `openInOtherColumn` through
  `commandActions.open(notePath:how:)`; `makeStructural` through
  `vault.beginStructuralLink(preselecting:)`; `unlink` through `.confirmationDialog(_:isPresented:
  presenting:)` («Scollegare «A» e «B»?», «Scollega» destructive), whose closure receives the row,
  never re-read from `@State` inside the `Task` (`.claude/rules/swiftui-views.md`), then
  `vault.removeStructuralLink(from:toNoteAt:)`.
- **`UnresolvedLinksSection`** (ADR-0084 §D2): `vault.unresolvedLinkRows(ofNoteAt:)`; «Crea nota»
  (only when creatable) → `commandActions.choose(.create)` with this note as the source; «Vai al
  link» → `commandActions.goToLink(target:)`; the empty state «nessun link non risolto in questa
  nota».
- **«Collega»** (ADR-0084 §D3): each row of `UnlinkedMentionsSection` gains a «Collega» button that
  creates a `LinkMentionReview` and presents `LinkMentionSheet` (`DiffView` over the review's diff,
  the notice when present, «Collega» default, «Annulla»); after `.linked` the section drops the row;
  after `.nothingToLink` it replaces the row with the sentence. The scan button gets the identifier
  `unlinked-mentions-scan` (the existing `unlinkedMentions` identifier stays on the section).
  For a title several notes share, the section filters out rows that match only an alias: the
  session's `planLinkMention` drops a shared title's aliases, so «Collega» would answer
  `.noMention` there (ADR-0084 §D3).
- **The structural sheet** (ADR-0084 §D4): `ReverseReasonMirror` drives the reverse field
  (`.onChange` of the forward field calls `forwardChanged`, the reverse field's binding calls
  `reverseEdited`); the selection is the path (Task 1 re-tagged it) and a row shows
  `LinkChoice.folderLabel` when its title is shared by another candidate (R-22); on appear the sheet
  takes `vault.takeStructuralLinkPreselection()` and selects it.
- **`WhereNoteAppearsSection`** (ADR-0084 §D6, on request, SPEC Decision): resting button «Cerca dove
  compare» with its one sentence, scanning, results (BOARD, PRATICHE, messages under their pratica),
  empty «non compare in nessuna board né pratica», the unreadable-board footnote, «Cerca di nuovo»,
  driven by a `WhereNoteAppearsScan`; a board row sets `vault.routeState.pendingCanvas = (path,
  nil)`, the door a board wikilink uses; a pratica or message row calls
  `pratiche.select(_:in:)` (`PraticheController+Ledger.swift:198`, from the environment) and shows
  the Pratiche pane.

Every row and button the GUI test or a person's assistive technology needs carries the identifiers
listed in the signatures, because Task 7 finds controls by identifier, never by their words. Tokens
only, light and dark. **Done means:** the whole unit suite green, then a by-hand pass on the Debug
build over every section in light and dark, including «Dove compare» on a note used by a board and a
pratica (the row opens are composed from tested doors, and this pass is what checks the composition).

### Task 7 — Session C: the three GUI tests, then the whole suite, both tools and the MCP smoke (R-20, R-21, R-26, R-30)
Owner: tester
Files: UITests/WikilinkNavigationUITests.swift, UITests/LinkMentionUITests.swift
Tests: WikilinkNavigationUITests.swift, LinkMentionUITests.swift
Signatures:
- WikilinkNavigationUITests.testFollowingTheLinkAtTheCaretAndComingBack — `func testFollowingTheLinkAtTheCaretAndComingBack() throws`
- WikilinkNavigationUITests.testCommandHoverShowsThePreviewAndReleaseHidesIt — `func testCommandHoverShowsThePreviewAndReleaseHidesIt() throws`
- LinkMentionUITests.testCollegaLinksTheMentionAfterTheDiff — `final class LinkMentionUITests: PergamenumUITestCase`, `func testCollegaLinksTheMentionAfterTheDiff() throws`
Red: no

Three GUI tests, the SPEC's ceiling for N3, each justified in its ADR (ADR-0083 §D8 for the first
two, ADR-0084 §D7 for the third). Both files subclass `PergamenumUITestCase`, create their vault
with `makeTemporaryVault(prefix:)` and launch with `launchApp(extraArguments:)`; none builds its own
`XCUIApplication` or sets launch arguments (`UITestLaunchHarnessGuardTests` fails otherwise). They
find controls by `accessibilityIdentifier` and the wikilink by its `AXLink` element
(`app.links["Destinazione"]`, the existing file's helper), never by on-screen prose. The existing
`testCommandClickOnAWikilinkNavigatesToTheLinkedNote` and its fixture (`Origine.md` holding
`[[Destinazione]]` with no trailing newline) are reused, not changed.

1. **Follow from the keyboard, then return** (R-21): open «Origine», click into the editor, put the
   caret inside `[[Destinazione]]` (Cmd+Down to the end of the text, then three Left arrows, which
   lands inside the name whatever the line wraps to), `typeKey(.return, modifierFlags: [.command,
   .option])`, wait for the editor's value to contain «Nota di arrivo», `typeKey("[",
   modifierFlags: .command)`, wait for «Origine»'s text back.
2. **The preview appears and goes** (R-20): inside `XCUIElement.perform(withKeyModifiers: .command)
   { link.hover(); … }`, wait for the element with identifier `link-preview` to exist (the dwell is
   250 ms, wait up to 3 s); after the block, assert it is gone within 2 s, then type one character
   and assert the editor's value contains it, which proves the popover left the keyboard with the
   editor.
3. **«Collega» a mention** (R-26): a vault with «Curva» and «Prova» whose body names «Curva» without
   a link; open «Curva», press `unlinked-mentions-scan`, then `unlinked-mention-link-Prova.md`, wait
   for the sheet, press `link-mention-confirm`; assert the file `Prova.md` (read by the test, which
   made the vault) contains `[[Curva]]`, and that `backlink-row-Prova.md` exists.

Run them through the script only (`.claude/rules/ui-tests.md`): `scripts/uitests.sh --status` first,
then `scripts/uitests.sh WikilinkNavigationUITests` and `scripts/uitests.sh LinkMentionUITests` (an
argument replaces the selection), then `scripts/uitests.sh --affected` as the merge asks. A red is
read from the run's `.xcresult` before anything is rerun; a failure at about 60 s is the launch
timeout, not the feature; `contaminated` is rerun, not acted on.

Then **R-30, in full**: the whole unit suite, not only the new files, because N3 changes five
observable contracts (`addStructuralLink`'s signature, `InspectorSection.unresolved`, the shortcut
catalogue, `SampleViews.all`, the mention scan's code rule) and a contract change can break a test
in a module nobody touched: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum
-destination 'platform=macOS' -only-testing:PergamenumTests test`. Then build `perg` and
`pergamenum-mcp`, run `python3 scripts/mcp-smoke.py`, and confirm `IndexCache.schemaVersion` is
still 7 (`git diff origin/main -- Sources/Index/IndexCache.swift` empty). Then the by-hand checks no
automated test reaches: the two Vista variants after binding a key to each in Impostazioni ▸
Scorciatoie, a follow from Oggi and from Diario, an ambiguous title from Quick Open's heading query.

### Task 8 — Docs, after PR C merges: flip ADR-0083 and ADR-0084 to accepted (R-31)
Owner: coder
Files: docs/adr/0083-links-answer-to-the-pointer-and-the-keyboard.md, docs/adr/0084-backlinks-with-context-unresolved-per-note-mentions-that-link.md, docs/adr/INDEX.md
Signatures:
- ADR-0083 status line — `Status: accepted. Implemented by PR #<B> (merge <hash>) and PR #<C> (merge <hash>).`
- ADR-0084 status line — `Status: accepted. Implemented by PR #<A> (merge <hash>) and PR #<C> (merge <hash>).`
Red: no

The first docs change after the session C PR merges (SPEC R-31, `docs/adr/README.md` rule 2). Read
the merge hashes off `git log --first-parent main`, never from a PR page. Before flipping, re-read
ADR-0083 §D7 against what PR B built: the popover's behaviour, the guards, the focus check and the
lifecycle must read as built; a difference is corrected in the record, in the same change, before
the flip. Add both records to `docs/adr/INDEX.md` in its existing shape. Run
`scripts/check-adr-references.py` after `git fetch origin` (and `--self-test` if the script
changed). No code changes in this task.

## Risks and HITL gates

- **HITL: the mockup approval** (R-29, `docs/plans/note-workflow-n3-mockup.md`) gates the view code
  of Tasks 4 and 6. Its open choices feed them: the preview's size and cut, the badge form, the
  mirrored text's look. Two items in that plan are stale against this SPEC and are not edited here,
  as instructed: it draws "the preview panel below the line" (now an `NSPopover` beside the link,
  ADR-0083 §D7) and offers «Dove compare» automatic as an open question (now settled on request,
  ADR-0084 §D6). The mockup implementer should draw the popover and only the on-request shape; the
  person may want that plan amended before it is built.
- **HITL: decisions raised for the person at this plan's gate.** (a) The editor's pure units
  (`LinkOpening`, `LinkAtCaret`, `LinkPreviewTrigger`, `LinkPreviewContent`) are placed in session B,
  not A: the SPEC's Decision says "A = pure units", its Success criteria put R-20, R-21 and R-23 in
  B, and units nothing calls until B would ship dead in PR A (recommended: B). (b) Diario and the
  board tray are routed through the choice too, beyond the four surfaces the SPEC names, because
  R-22 says nothing opens the first match silently (recommended: yes). (c) «Apri collegamento» on an
  ambiguous title opens the sheet, not a second menu (recommended: the sheet). Settled by the SPEC
  and no longer asked: the parked draft is kept, the `[[Titolo|testo]]` form, «Dove compare» on
  request, the popover.
- **HITL: commit, push, PR,** for each of the four PRs (A, B, C, docs). On a feature branch, never
  `main`; the commit and the push are the person's gates. The pre-push hook (ADR-0061/0062) must be
  installed on the machine.
- **Contract changes** (staleness rule), each with its call sites listed in its task:
  `addStructuralLink(from:to:)` → `(from:toNoteAt:)` (Task 1, 3 source and 10 test sites);
  `InspectorSection.unresolved(shown:)` → `unresolved(count:)` (Task 5); `SampleViews.all` 6 → 7 and
  `everySampleViewParses` 9 → 10 (Task 1); `ShortcutCommand` + 3 cases and the three guard tests
  amended (Task 3); the mention scan's code narrowing (Task 2). The full unit suite runs at the end
  of every session, not only the new tests.
- **The popover's key status is undocumented** (insufficient data: `NSPopover.h` declares nothing
  that keeps its window from becoming key). Mitigated by content with nothing focusable, the
  fail-closed `LinkPreviewFocus` check, and GUI test 2's typed character. If the check fires on
  every show, the preview never stays up and GUI test 2 is red: that is a stop and a report, not a
  reason to drop the check.
- **The preview's event plumbing.** A tracking area plus a local monitor is the PG-258 shape. The
  hosted tests pin the lifecycle; the GUI test pins the real thing. Whether
  `perform(withKeyModifiers:)` produces the `flagsChanged` the controller listens for is not verified
  (insufficient data): the controller also starts the dwell from a pointer event with Command
  already down, so the test does not depend on it. The preferred edge in a flipped view is confirmed
  by eye, not assumed.
- **Protected interface.** `CompletingTextView+Pasteboard.swift` is protected as a whole file; this
  plan only calls `linkCharacterIndex(at:)` and keeps `performLinkNavigation(_:)`'s signature, which
  that file calls. A diff to it is a stop.
- **Cmd+Opt+Return** may be taken by a system shortcut on this machine; Task 4 step 2 measures
  before binding and stops if it is.
- **SwiftLint budgets.** `CommandActions.swift` (399) and `VaultController+Tabs.swift` (412) are at
  or past the file-length warning, `VaultBrowser` and the Coordinator at their type-body limits:
  new code goes in new files, `runView` gains no arm, the Coordinator's class body gains two stored
  properties. SwiftLint is not a gate (it fails on `main` by design), but a new warning on these
  files is read in review.
- **The tools' build.** `Sources/Core/Links/`, `VaultSession+LinkWrites.swift` (added to
  `sharedSources` in Task 1) and `Sources/Connector/VaultLinkWrites.swift` compile into `perg` and
  `pergamenum-mcp`; `VaultSession+Appearances.swift` must not be added to `sharedSources`. After
  touching `Project.swift`, `tuist generate --no-open` (and `tuist install` once in a fresh worktree).
- **No schema change.** `IndexCache.schemaVersion` stays 7; if any step seems to need it, stop:
  ADR-0084 rules it out.
- **ADR-0082's status.** Its code is on `main` (PR #921) and its record reads `planned`; that is
  N2's flip to make, not N3's, and it is reported, not changed here.
- **External provisioning:** none. No network, no new dependency, no new setting.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

No static check is declared that passes on `main`: SwiftLint fails there by design on seven types
(`.swiftlint.yml`'s own comment, `.github/workflows/ci.yml`), so any `swiftlint lint` form would make
the stop-gate red before the suite runs. The type check is the build inside the test command.
`scripts/check-adr-references.py` is a documentation checker, run by hand in Task 8, not a code check.

## Build result (2026-10-07)

BUILD · DONE WITH WARNINGS
Scope: Session A, Tasks 1 and 2 (Tasks 3 to 8 are gated on PR A, the mockup approval and PR C by the plan)
Files: 58 changed files, Session A: new Sources/Core/Links/, UnresolvedTargets.swift, Connector/VaultLinkWrites.swift, Vault/VaultSession+LinkWrites.swift and +Appearances.swift, MCPServer NoteLinks files, 13 new test files; ADR-0083/0084, this plan, SPEC.md are planning artifacts
Tests: PergamenumTests 5778 passed (5 known issues, pre-existing); perg and pergamenum-mcp build exit 0; scripts/mcp-smoke.py exit 0
Review: sonnet, safe; opus, safe
Coverage: 11 of 12 R-ids covered; R-30 UNCOVERED on tests (a gate requirement, verified by the runs above)
Dropped: 17 (post-sweep 8, fix-hunk 4, unlocated 1, nit 4)
Dispatch: Round 0 (red): tester — Task 1
Dispatch: Round 1: debugger — BacklinkContext.swift:16 (reviewer: sonnet, opus), VaultSession+LinkWrites.swift:28 (reviewer: sonnet), VaultLinkWrites.swift:23 (reviewer: sonnet); coder — VaultLinkWrites.swift:21 (reviewer: sonnet)
Dispatch: Round 2: debugger — VaultSession+Notes.swift:244 (reviewer: opus), VaultSession+LinkWrites.swift:69-72 (reviewer: opus); coder — VaultSession.swift:155 (reviewer: opus), VaultSession.swift:151 (reviewer: sonnet), VaultSession+LinkWrites.swift:25 (reviewer: opus), UnlinkedMentions.swift:105 (reviewer: opus), VaultLinkWrites.swift:23 (reviewer: sonnet, opus)
Dispatch: Round 1 (sweep): debugger — VaultSession+LinkWrites.swift:60 (reviewer: opus), VaultSession+LinkWrites.swift:135-136 (reviewer: opus); coder — NoteRename.swift:33 (follow-up: debugger), UnlinkedMentions.swift:5-15, UnlinkedMentions.swift:39 (reviewer: opus), UnlinkedMentions.swift:302 (reviewer: sonnet), VaultSession+LinkWrites.swift:36 (reviewer: opus), VaultReads.swift:32-33 (reviewer: opus), VaultSession+LinkWrites.swift:163 (reviewer: opus), IndexSnapshot.swift:79, WriteCommands.swift:61, Wikilink.swift:357, main.swift:12 (follow-ups)
Dispatch: Round 2 (sweep): debugger — UnlinkedMentions.swift:42-44 (reviewer: opus); coder — UnlinkedMentions.swift:104 (reviewer: sonnet), VaultSession+LinkWrites.swift:91-95 (reviewer: opus), VaultLinkWrites.swift:23-30 (reviewer: opus), Project.swift:229 and VaultControllerLandedChangeTests.swift:354 (follow-ups: coder)
Dispatch: Round 3 (closing, beyond the review cap, not re-reviewed): coder — UnlinkedMentions.swift:45 (tag/annotation), UnlinkedMentions.swift:45 (early return), ADR-0084 §D3, VaultSession+LinkWrites.swift:103, MentionLinkTests.swift:228
WARN: UNCOVERED R-30 tests: R-30 is a gate requirement (unit suite, builds, smoke, schemaVersion 7, no new GUI test); the runs verify it, no test names it
WARN: the closing round (inline tag and annotation exclusion, early return in firstMention, ADR-0084 §D3, two NITs) ran beyond the four-review-round cap under Stefano's standing authorization and was not re-reviewed; the suite is green after it
WARN: decision-bound, for Stefano: the agents amended ADR-0084 §D1, §D3, §D4 and the plan's Task 2 and Task 6 text; the connector refuses a title shared by several notes (link_mention, remove_structural_link) and any path that is not an indexed note, a behaviour beyond the SPEC wording
WARN: git status carries a staged SPEC.md rename to docs/archive/specs/pg-219-pointer-feedback.SPEC.md and docs/plans/pg-219-pointer-feedback.md that pre-date this build; /ship weighs them
INFO: review escalated, size: 58 changed files, threshold 20

```text
DROP	unlocated	**MINOR** [other] Tests/VaultLinkWritesTests.swift (new file): -only-testing:PergamenumTests/VaultLinkWritesTests runs 0 tests because the tests are free functions, use the full PergamenumTests selection (follow-up: debugger)
DROP	fix-hunk	**MINOR** [wrong-behaviour] Sources/Vault/VaultSession+LinkWrites.swift:22 — planLinkMention and linkMention skip linkEndRefusal, so a direct session caller can scan and rewrite the raw text of a .canvas or settings JSON; only VaultAPI.requireNote guards it. Fix: call linkEndRefusal(path) at the top of both doors and extend the non-note test to the session door. (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [other] Sources/Connector/VaultLinkWrites.swift:75 — requireNote duplica VaultSession.linkEndRefusal con frasi diverse per la stessa condizione, così app e connettore non rifiutano allo stesso modo. Fix: lanciare ConnectorError con la frase di session.linkEndRefusal(path). (reviewer: opus)
DROP	fix-hunk	**MINOR** [wrong-behaviour] Sources/Vault/VaultSession+LinkWrites.swift:87 — mentionPlan drops the target's aliases when two notes share the title, but unlinkedMentions(for:) (VaultSession+Search.swift:140) still lists alias-only mentions, so the inspector shows rows «Collega» answers noMention for; ADR-0084 §D3 and the plan do not record the unique-carrier rule. Fix: one shared name-list helper used by both, then correct the comments and ADR §D3. (reviewer: sonnet)
DROP	fix-hunk	**MINOR** [other] Sources/Vault/VaultSession+LinkWrites.swift:87-91 — Il commento afferma che gli alias sono letti come in unlinkedMentions(for:), che invece usa gli alias del soggetto senza condizioni: con un titolo condiviso l'inspector mostra una riga via alias che «Collega» rifiuta come .noMention. Fix: correggere il commento nominando la divergenza e filtrare le righe-alias omonime in sessione C. (reviewer: opus)
DROP	post-sweep	**NIT** Sources/Core/Search/UnlinkedMentions.swift:302 — mentions(_:in:) and containsWholeWord are kept in the shared production sources with no production caller, only as a test oracle; move them into the test target if the oracle can live there. (reviewer: sonnet)
DROP	post-sweep	**MINOR** [other] Sources/Index/IndexSnapshot.swift:79 — backlinks use link.target while ADR-0084 §D1 says resolvedTitle, they differ for [[**T**]] (follow-up: tester)
DROP	post-sweep	**MINOR** [other] Sources/CLI/Commands/WriteCommands.swift:61 — the perg wiring (noteLinkMention, noteUnlinkRelated) has no automated test, only VaultAPI and the MCP smoke are covered (follow-up: tester)
DROP	post-sweep	**MINOR** [other] Sources/CLI/main.swift:12 — SwiftLint cyclomatic_complexity 17 on the dispatcher, already there (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Sources/Core/Conventions/NoteRename.swift:33 — matches links by resolvedTitle, so a rename follows [[**T**]] while the index files it under **T**, different subsystem, not checked (follow-up: debugger)
DROP	post-sweep	**MINOR** [other] Sources/Connector/VaultPraticheLinks.swift:67 — still check only session.exists before writing (also :235, :320 and Sources/Connector/VaultWrites.swift:93), old «non esiste» wording, may share the non-note hole (follow-up: debugger)
DROP	post-sweep	**MINOR** [other] Project.swift:229 — line_length warning, the NSAppleEventsUsageDescription string, already there before this build (follow-up: coder)
DROP	post-sweep	**MINOR** [other] Tests/VaultControllerLandedChangeTests.swift:354 — line_length warning, 122 characters, already there before this build (follow-up: coder)
FIX	swept	**NIT** Sources/Core/Search/UnlinkedMentions.swift:105 — mentions(_:in:) and containsWholeWord only used as a test oracle (reviewer: sonnet)
FIX	swept	**NIT** Sources/Core/Search/UnlinkedMentions.swift:3 — header omits the code narrowing (reviewer: sonnet)
FIX	swept	**NIT** Sources/Core/Search/UnlinkedMentions.swift:5-15 — type doc omits the code narrowing (reviewer: opus)
FIX	swept	**NIT** Sources/Core/Search/UnlinkedMentions.swift:37-39 — CodeFence.regions union unexplained (reviewer: opus)
FIX	swept	**NIT** Sources/Vault/VaultSession+LinkWrites.swift:36 — refusal type spelled two ways (reviewer: opus)
FIX	swept	**NIT** Sources/Connector/VaultReads.swift:32-33 — resolved resta il filtro scritto a mano mentre unresolved passa per UnresolvedTargets.of. Far passare anche resolved dalla derivazione condivisa. (reviewer: opus)
FIX	swept	**MAJOR** [wrong-behaviour] Sources/Vault/VaultSession+LinkWrites.swift:60 — linkMention e planLinkMention non applicano linkEndRefusal, quindi un percorso che esiste ma non è una nota indicizzata (.canvas, .pergamenum/*.json) può essere riscritto da VaultController.linkMention: il controllo vive solo nel connettore. Fix: chiamare linkEndRefusal(path) in testa a entrambe e tornare nil / .failed(refusal). (reviewer: opus)
FIX	swept	**MAJOR** [wrong-behaviour] Sources/Vault/VaultSession+LinkWrites.swift:135-136 — removeStructuralLink prende due percorsi ma rimuove per titolo, così con due note omonime cancella la voce related e il bullet che puntavano all'altra omonima e riporta removed == true (raggiungibile da perg note unlink-related e dal tool MCP). Fix: rifiutare con una frase nominata quando index.resolve(title:) dà più di un percorso per uno dei due titoli. (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Core/Search/UnlinkedMentions.swift:39 — CodeFence.regions(in: body) è ridondante accanto a WikilinkParser.codeRanges(in: body): due autorità su cos'è codice e una scansione in più. Fix: togliere il termine CodeFence.regions o motivare entrambi. (reviewer: opus)
FIX	swept	**MINOR** [style] Sources/Vault/VaultSession+LinkWrites.swift:163 — Riga di 122 caratteri, oltre il line_length warning 120 di .swiftlint.yml, su un file nuovo. Fix: spezzare la stringa della frase «legame strutturale tolto a metà». (reviewer: opus)
FIX	swept	**MINOR** [other] Sources/Core/Conventions/Wikilink.swift:357 — SwiftLint vertical_whitespace, double blank line already there (follow-up: coder)
FIX	swept	**MAJOR** [wrong-behaviour] Sources/Core/Search/UnlinkedMentions.swift:45 — A name inside an inline #tag (e.g. #client-rossi) counts as a mention because the excluded set has no tag/annotation ranges, so link-mention writes #client-[[Rossi|rossi]] and breaks the tag, with no diff on the perg and MCP dryRun:false doors. Fix: add the parser's .tag and .annotation token ranges to the excluded set and add a test. (reviewer: sonnet)
FIX	swept	**MINOR** [other] Sources/Core/Search/UnlinkedMentions.swift:45 — firstMention builds the whole excluded set before checking that any name occurs in the body, which adds a full parse to every note in the vault-wide mention scan. Fix: return nil early when no name occurs in the body, or compute excluded lazily on the first hit. (reviewer: sonnet)
FIX	swept	**MINOR** [plan-deviation] docs/adr/0084-backlinks-with-context-unresolved-per-note-mentions-that-link.md:135 — ADR-0084 section D3 records only the code narrowing, but UnlinkedMentions.urlRanges also excludes markdown links and bare URLs while citing D3; neither the SPEC decision nor the plan Task 2 mention it. Fix: record the URL/markdown-link narrowing in D3 and the connector refusals (shared title, non-note path), and the tag narrowing. (reviewer: sonnet, opus)
FIX	swept	**NIT** Tests/MentionLinkTests.swift:228 — The oracle comment claims the two code entries are the only ones where old and new scan may disagree; the URL narrowing adds a second class of divergence. Fix: reword. (reviewer: opus)
```
