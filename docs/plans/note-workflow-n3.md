**Requirement set:** `SPEC.md`

# Note workflow N3, links: the code PR

Milestone N3 of the note-workflow chain (`PG-386`, issue #888), code half, SPEC (root, Approved
2026-10-04) R-20..R-28. The mockup PR (`docs/plans/note-workflow-n3-mockup.md`) is approved on the
Debug build first; no view code here starts before that approval.

**ADR outcome:** two new ADRs, both proposed, written by this planning pass and landed with the
mockup PR: `docs/adr/0083-links-answer-to-the-pointer-and-the-keyboard.md` (R-20..R-23) and
`docs/adr/0084-backlinks-with-context-unresolved-per-note-mentions-that-link.md` (R-24..R-28). Each
flips to `accepted` in the first docs change after this PR merges (`docs/adr/README.md` rule 2).

**Assumes merged:** N1 (ADR-0080: PG-219's pointer, the `[[` completion rule of R-03, Cmd+click on
tags and dates of R-07, the composer folder rule of R-06) and N2 (ADR-0081, ADR-0082: the styler
classifying through the shared parsers, R-18). This plan is written against `origin/main` at
`48a2d912` and depends on exactly three facts that must still hold after both merge, checked first
in Task 1:

1. The styler still writes `.editorLink` (a `URL`) on a link's target run, and
   `MarkdownAttributedText.clickTarget(for:)` still maps it to `.note`/`.embed`/`.external`
   (`WikilinkClickNavigationTests` pins this today).
2. `CompletingTextView.linkCharacterIndex(at:)` still exists in the protected
   `CompletingTextView+Pasteboard.swift`.
3. `NoteTextView+Coordinator.textView(_:clickedOnLink:at:)` still reaches `performLinkNavigation`.

N1's R-07 adds tag and date targets to the same click path: the variants of ADR-0083 §D2 apply to
note targets only, so N1's targets keep N1's behaviour whatever modifiers are held. Nothing here
edits `CompletingTextView+CursorRects.swift` (N1) or the styler (N2).

**Requirement coverage:** R-20 Tasks 1, 2, 5, 6, 8. R-21 Tasks 1, 2, 5, 6, 8. R-22 Tasks 1, 2, 4,
5, 6, 7. R-23 Tasks 1, 2, 5, 6. R-24 Tasks 1, 2, 5, 7. R-25 Tasks 1, 2, 3, 4, 5, 7. R-26 Tasks 1,
2, 3, 4, 5, 7, 8. R-27 Tasks 1, 2, 3, 4, 5, 7. R-28 Tasks 1, 2, 3, 4, 7.

**Order:** tester first, then coder, three times (pure units, session and connectors, app and
editor), then the two coder halves of the UI, then the GUI tests. Every red task declares the
signatures it tests, as stubs that compile and answer wrongly (never a trap: a stub that traps
crashes the run instead of failing a test), so the target builds and the tests are red, not absent.

## Tasks

### Task 1 — Pure link units, red (R-20, R-21, R-22, R-23, R-24, R-25, R-26, R-27, R-28)

Owner: tester
Files:
- Sources/Core/Links/LinkOpening.swift
- Sources/Core/Links/LinkDestination.swift
- Sources/Core/Links/LinkChoice.swift
- Sources/Core/Links/LinkAtCaret.swift
- Sources/Core/Links/LinkPreviewTrigger.swift
- Sources/Core/Links/LinkPreviewContent.swift
- Sources/Core/Links/BacklinkContext.swift
- Sources/Core/Links/MentionLink.swift
- Sources/Core/Links/ReverseReasonMirror.swift
- Sources/Core/Links/NoteAppearances.swift
- Sources/Core/Query/UnresolvedTargets.swift
- Sources/Core/Search/UnlinkedMentions.swift
- Sources/Core/Conventions/Wikilink.swift
- Tests/LinkOpeningTests.swift, Tests/LinkDestinationTests.swift, Tests/LinkChoiceTests.swift
- Tests/LinkAtCaretTests.swift, Tests/LinkPreviewTriggerTests.swift, Tests/LinkPreviewContentTests.swift
- Tests/BacklinkContextTests.swift, Tests/UnresolvedTargetsTests.swift, Tests/MentionLinkTests.swift
- Tests/ReverseReasonMirrorTests.swift, Tests/NoteAppearancesTests.swift
Tests: LinkOpeningTests.swift, LinkDestinationTests.swift, LinkChoiceTests.swift, LinkAtCaretTests.swift, LinkPreviewTriggerTests.swift, LinkPreviewContentTests.swift, BacklinkContextTests.swift, UnresolvedTargetsTests.swift, MentionLinkTests.swift, ReverseReasonMirrorTests.swift, NoteAppearancesTests.swift, WikilinkClickNavigationTests.swift
Signatures:
- LinkOpening — `enum LinkOpening: Equatable, Sendable { case replace, newTab, otherColumn; static func forClick(shift: Bool, option: Bool) -> LinkOpening }`
- LinkDestination — `enum LinkDestination: Equatable, Sendable { case note(path: String), board(path: String), ambiguous(title: String, paths: [String]), missing(title: String, creatable: Bool), missingBoard(name: String) }`
- LinkDestination.resolve — `static func resolve(_ target: String, notePaths: (String) -> [String], boards: () -> [String]) -> LinkDestination`
- LinkDestination.isCreatable — `static func isCreatable(_ title: String) -> Bool`
- LinkChoice — `struct LinkChoice: Equatable, Sendable, Identifiable { enum Action: Equatable, Sendable { case open(path: String), create(title: String) }; let id: String; let label: String; let detail: String; let action: Action }`
- LinkChoice.entries — `static func entries(for destination: LinkDestination) -> [LinkChoice]`
- LinkChoice.folderLabel — `static func folderLabel(of path: String) -> String`, `static let rootLabel = "radice del vault"`
- LinkAtCaret.Run — `struct Run: Equatable, Sendable { var range: NSRange; var url: URL }`
- LinkAtCaret.pick — `static func pick(caret: Int, runs: [LinkAtCaret.Run], wikilinks: [NSRange]) -> URL?`
- LinkPreviewTrigger — `struct LinkPreviewTrigger: Equatable, Sendable { static let dwell: TimeInterval = 0.25; private(set) var shownRun: NSRange?; mutating func handle(_ event: Event) -> Effect }`
- LinkPreviewTrigger.Event — `enum Event: Equatable, Sendable { case pointer(run: NSRange?, at: TimeInterval), command(isDown: Bool, at: TimeInterval), tick(TimeInterval), keyDown, escape, scroll, pointerExited, resignKey, textChanged, noteChanged }`
- LinkPreviewTrigger.Effect — `enum Effect: Equatable, Sendable { case none, show(run: NSRange), hide, hideConsumingEscape }`
- LinkPreviewContent — `struct LinkPreviewContent: Equatable, Sendable { enum Kind: Equatable, Sendable { case note(title: String, lines: [String], missingSection: String?), board(name: String), ambiguous(title: String, folders: [String]), missing(title: String, creatable: Bool) }; let kind: Kind; static let lineLimit = 12 }`
- LinkPreviewContent.make — `static func make(for destination: LinkDestination, section: String?, noteText: (String) -> String?) -> LinkPreviewContent?`
- BacklinkContext.lines — `static func lines(linking title: String, in text: String) -> [String]`
- BacklinkRow — `struct BacklinkRow: Equatable, Sendable, Identifiable { var id: String { path }; let title: String; let path: String; let firstLine: String?; let count: Int; let isStructural: Bool; static func make(path: String, title: String, text: String, linking target: String, related: [String]) -> BacklinkRow }`
- Wikilink.isNoteLink — `var isNoteLink: Bool { get }`
- UnresolvedTargets.of — `static func of(_ targets: [String], resolving: (String) -> [String]) -> [String]`
- UnresolvedTargets.firstLine — `static func firstLine(linking target: String, in text: String) -> Int?`
- UnlinkedMentions.Mention — `struct Mention: Equatable, Sendable { let range: NSRange; let matched: String; let line: String }`
- UnlinkedMentions.firstMention — `static func firstMention(of names: [String], in text: String) -> Mention?`
- MentionLink.rewrite — `static func rewrite(_ text: String, mention: UnlinkedMentions.Mention, title: String) -> String`
- ReverseReasonMirror — `struct ReverseReasonMirror: Equatable, Sendable { private(set) var reverse: String; private(set) var isEdited: Bool; mutating func forwardChanged(to forward: String); mutating func reverseEdited(to text: String) }`
- NoteAppearances — `struct NoteAppearances: Equatable, Sendable { struct Board: Equatable, Sendable { let path: String; let name: String }; struct Pratica: Equatable, Sendable { let folder: String; let title: String; let linksNote: Bool; let messages: [String] }; let boards: [Board]; let pratiche: [Pratica]; let unreadableBoards: Int }`
- NoteAppearances.build — `static func build(notePath: String, boards: [(path: String, filePaths: [String])], unreadableBoards: Int, praticaLinks: [(folder: String, references: [String])], messageLinks: [(path: String, folder: String, reference: String)], candidates: (String) -> [String]) -> NoteAppearances`
Red: yes

**Before writing a test,** confirm the three facts in the plan header on the post-N1/N2 tree
(`rg -n "editorLink" Sources/Features/Editor/MarkdownAttributedText.swift`,
`rg -n "func linkCharacterIndex" Sources/Features/Editor/CompletingTextView+Pasteboard.swift`,
`rg -n "clickedOnLink" Sources/Features/Editor/NoteTextView+Coordinator.swift`) and run
`WikilinkClickNavigationTests` green. If one fails, stop and report: the plan's seams moved.

Every file under `Sources/Core` is Foundation-only (it compiles into `perg` and `pergamenum-mcp`;
a SwiftUI or AppKit import breaks both tool builds, CLAUDE.md "AI connector"). `Sources/Core/Links/`
is a new folder under the existing `Sources/Core/**` glob, so `Project.swift` is not touched.

Stubs answer wrongly and compile: `forClick` returns `.replace`, `resolve` returns
`.missing(title:creatable: false)`, `entries` returns `[]`, `pick` returns nil, `handle` returns
`.none`, `make` returns nil, `lines` returns `[]`, `isNoteLink` returns false, `of` returns `[]`,
`firstMention` returns nil, `rewrite` returns its input, the mirror's mutators do nothing, `build`
returns empty. `UnlinkedMentions.firstMentionLine` keeps its current body in this task.

What each file pins (the rules are ADR-0083 and ADR-0084, cited per file in a header comment):

- `LinkOpeningTests`: the four Shift/Option combinations; Option wins over Shift (ADR-0083 §D2).
- `LinkDestinationTests`: one path → `.note`; two → `.ambiguous` with the paths sorted as
  `resolve(title:)` sorts them; none → `.missing`; `isCreatable` false for `TRUST.md`,
  `Cartella/Nota`, `a:b`, `X.canvas`, an empty or 61-character title, true for `Bozza`; a `.canvas`
  target → `.board` or `.missingBoard` through the board list (ADR-0083 §D5, §D6).
- `LinkChoiceTests`: one row per path, label = folder label, `rootLabel` for a root note, detail =
  the path; a creatable `.missing` → one row «Crea «X»» with `.create`; every other destination → no
  rows; ids unique.
- `LinkAtCaretTests`: caret inside a run, at its start, at its end; inside `[[`, inside the alias,
  on `]]` → the run inside that wikilink; a markdown link whose label holds a wikilink → the
  wikilink's (innermost); two runs on a line → the one at the caret; no run (an embed) → nil.
- `LinkPreviewTriggerTests`: nothing before the dwell; `show` at 250 ms with Command held; moving
  to another run restarts the dwell; a pointer event with Command already down starts it (no
  `command` event needed); Command up, `pointerExited`, `scroll`, `keyDown`, `resignKey`,
  `textChanged`, `noteChanged` → `hide`; `escape` while shown → `hideConsumingEscape`, while hidden
  → `none`; a `keyDown` during the dwell cancels it.
- `LinkPreviewContentTests`: twelve body lines at most, frontmatter never; a section through
  `Transclusion.excerpt(of:section:)`; a missing section named; a board's name; an ambiguous
  title's folder labels; a missing title with `creatable`.
- `BacklinkContextTests`: one entry per link, in order; `[[T|alias]]`, `[[T#Sez]]` and `![[T]]`
  count; `[[T.canvas]]` and links inside fences do not; matching is case-insensitive; a note that
  links only through `related` yields its `## Note correlate` bullet line; `BacklinkRow.make`'s
  count, first line and `isStructural`; and **one agreement test**: over a fixed corpus, the set
  of targets `NoteStore.linkTargets(in:)` returns equals the set of targets of the links
  `isNoteLink` keeps.
- `UnresolvedTargetsTests`: order and duplicates as given, resolved targets dropped;
  `firstLine` finds the first line holding `[[X]]`, `[[X|a]]` or `[[X#s]]`, skips code, nil when
  absent.
- `MentionLinkTests`: `firstMention`'s range is in the original text (a decomposed accent, a case
  difference, an alias); whole words only; never inside a wikilink, the frontmatter, a fence or an
  inline code span (the ADR-0084 §D3 narrowing, new behaviour); `rewrite` gives `[[T]]` for an exact
  match and `[[T|testo]]` otherwise; and **one agreement test**: for every line of a corpus,
  `firstMention(...)?.line` equals `firstMentionLine(...)` except on the code lines, which are
  listed by name as the deliberate difference.
- `ReverseReasonMirrorTests`: follows the forward reason until edited; never overwritten after; an
  edit that happens to equal the forward text still counts as an edit.
- `NoteAppearancesTests`: a board appears once when any `.file` node's path equals the note's path,
  never for a sibling path or a prefix; a pratica reference claimed only when `candidates` gives one
  path and it is this note's (`PraticaLinkResolver.note(candidates:)`'s `unique`); an ambiguous
  reference claimed by nobody; a message grouped under its pratica; `unreadableBoards` passed
  through; output sorted by path.

Swift Testing, `@Test` functions, Italian failure messages as the suite writes them.

### Task 2 — Pure link units, green; one derivation for unresolved targets and for link counting (R-20, R-21, R-22, R-23, R-24, R-25, R-26, R-27, R-28)

Owner: coder
Files:
- Sources/Core/Links/LinkOpening.swift, Sources/Core/Links/LinkDestination.swift, Sources/Core/Links/LinkChoice.swift
- Sources/Core/Links/LinkAtCaret.swift, Sources/Core/Links/LinkPreviewTrigger.swift, Sources/Core/Links/LinkPreviewContent.swift
- Sources/Core/Links/BacklinkContext.swift, Sources/Core/Links/MentionLink.swift, Sources/Core/Links/ReverseReasonMirror.swift
- Sources/Core/Links/NoteAppearances.swift, Sources/Core/Query/UnresolvedTargets.swift
- Sources/Core/Search/UnlinkedMentions.swift, Sources/Core/Conventions/Wikilink.swift
- Sources/Core/Query/ViewEvaluator.swift, Sources/Connector/VaultReads.swift, Sources/Vault/NoteStore+ReadSurface.swift
Tests: LinkOpeningTests.swift, LinkDestinationTests.swift, LinkChoiceTests.swift, LinkAtCaretTests.swift, LinkPreviewTriggerTests.swift, LinkPreviewContentTests.swift, BacklinkContextTests.swift, UnresolvedTargetsTests.swift, MentionLinkTests.swift, ReverseReasonMirrorTests.swift, NoteAppearancesTests.swift, ViewEvaluatorTests.swift, ViewEvaluatorWorkCountTests.swift, ViewEvaluatorGraphPinTests.swift, SearchTests.swift, VaultSessionTests.swift, ConnectorTests.swift
Signatures:
- (Task 1's, bodies only)
Red: no

Make Task 1 green, then route the existing copies through the new single derivations:

- `NoteStore.linkTargets(in document:)` keeps its loop and dedupe and replaces its `where` clause
  with `link.isNoteLink`, so the index and the backlink count share one predicate (ADR-0084 §D1).
- `ViewEvaluator`'s graph fills `graph.unresolved[path]` from `UnresolvedTargets.of(record.linkTargets,
  resolving: resolve)`, where `resolve` is its existing per-title memo, so the corpus is asked once
  per title as today. `ViewEvaluatorWorkCountTests` and `ViewEvaluatorGraphPinTests` stay green
  unmodified; if a work count moves, the memo was bypassed, and that is the defect to fix, not the
  pin.
- `VaultAPI.links(_:at:)` computes `unresolved` with `UnresolvedTargets.of`. Its JSON is unchanged.
- `UnlinkedMentions.firstMentionLine(of:in:)` becomes `firstMention(of:in:)?.line`. This narrows the
  existing mention scan (a name only in code is no longer a mention, ADR-0084 §D3), which no
  current test asserts against; `SearchTests` and `VaultSessionTests` run green unmodified.

`firstMention` matches on the original text with `range(of:options: [.caseInsensitive,
.diacriticInsensitive])` per name, rejecting a hit that touches a letter or a digit on either side,
that overlaps a wikilink (the line's `WikilinkParser` ranges), that sits in `CodeFence.regions(in:)`
or in an inline code span, or that is in the frontmatter. The range is an `NSRange` over the whole
text (UTF-16, the unit `rewrite` and the editor use).

`LinkPreviewContent.make` titles a note through `NoteName.title(fromFileName:)` and reads the
excerpt through `Transclusion.excerpt(of:section:)`, never a second section finder.

### Task 3 — Session and connector writes, red; update tests and call-sites asserting the old behaviour (R-22, R-25, R-26, R-27, R-28)

Owner: tester
Files:
- Sources/Index/IndexSnapshot.swift
- Sources/Vault/VaultSession+Notes.swift
- Sources/Vault/VaultSession+Appearances.swift
- Sources/App/VaultController+Notes.swift
- Sources/Features/Editor/RelatedLinkSheet.swift
- Sources/Connector/VaultLinkWrites.swift
- Sources/Core/Query/SampleViews.swift
- Tests/VaultLinkWritesTests.swift, Tests/VaultControllerLinkWritesTests.swift, Tests/ConnectorLinkWritesTests.swift
- Tests/IndexUnresolvedTargetsTests.swift, Tests/NoteAppearancesSessionTests.swift
- Tests/RelatedLinkTests.swift, Tests/VaultControllerWriteCatchUpTests.swift, Tests/VaultUnguardedWriteGuardTests.swift
- Tests/VaultControllerLandedChangeTests.swift, Tests/RelatedSectionLineRolesTests.swift, Tests/NoteByteOrderMarkTests.swift
- Tests/RelatedLinkSectionPreservationTests.swift, Tests/ViewConnectorTests.swift
Tests: VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift, ConnectorLinkWritesTests.swift, IndexUnresolvedTargetsTests.swift, NoteAppearancesSessionTests.swift, RelatedLinkTests.swift, VaultControllerWriteCatchUpTests.swift, VaultUnguardedWriteGuardTests.swift, VaultControllerLandedChangeTests.swift, RelatedSectionLineRolesTests.swift, NoteByteOrderMarkTests.swift, RelatedLinkSectionPreservationTests.swift, ViewConnectorTests.swift
Signatures:
- IndexSnapshot.unresolvedTargets — `func unresolvedTargets(of path: String) -> [String]`
- VaultSession.LinkMentionOutcome — `enum LinkMentionOutcome: Equatable, Sendable { case linked(WriteResult), noMention, movedOn, failed(String) }`
- VaultSession.planLinkMention — `func planLinkMention(in path: String, to title: String) -> (before: String, after: String, hash: String)?`
- VaultSession.linkMention — `func linkMention(in path: String, to title: String, expecting hash: String?) async -> LinkMentionOutcome`
- VaultSession.addStructuralLink — `func addStructuralLink(from sourcePath: String, toNoteAt targetPath: String, reason: String, reverseReason: String) async -> (created: Bool, written: [WriteResult])`
- VaultSession.removeStructuralLink — `func removeStructuralLink(from sourcePath: String, toNoteAt targetPath: String) async -> (removed: Bool, written: [WriteResult])`
- VaultSession.noteAppearances — `func noteAppearances(of path: String) -> NoteAppearances`
- VaultController.addStructuralLink — `func addStructuralLink(from sourcePath: String, toNoteAt targetPath: String, reason: String, reverseReason: String) async -> Bool`
- VaultController.removeStructuralLink — `func removeStructuralLink(from sourcePath: String, toNoteAt targetPath: String) async -> Bool`
- VaultController.linkMention — `func linkMention(in path: String, to title: String, expecting hash: String) async -> VaultSession.LinkMentionOutcome`
- VaultAPI.linkMention — `static func linkMention(_ session: VaultSession, in path: String, title: String) async throws -> WriteSummary`
- VaultAPI.removeStructuralLink — `static func removeStructuralLink(_ session: VaultSession, from path: String, to target: String) async throws -> [WriteSummary]`
- SampleViews — `static let all: [Sample]` gains `unresolvedLinks`, «Vista - Link non risolti»
Red: yes

**The contract change, and every call site the grep found.** `rg -n "addStructuralLink\(" Sources
Tests UITests scripts` on `48a2d912`:

- `Sources/Vault/VaultSession+Notes.swift:226` (the definition: `to targetTitle:` becomes
  `toNoteAt targetPath:`)
- `Sources/App/VaultController+Notes.swift:74`, `:81` (the wrapper and its call)
- `Sources/Features/Editor/RelatedLinkSheet.swift:87` (the sheet's `create()`)
- `Tests/RelatedLinkTests.swift:143`, `:172`, `:189`
- `Tests/VaultControllerWriteCatchUpTests.swift:353`, `:378`
- `Tests/VaultUnguardedWriteGuardTests.swift:100`
- `Tests/VaultControllerLandedChangeTests.swift:310`
- `Tests/RelatedSectionLineRolesTests.swift:236`
- `Tests/NoteByteOrderMarkTests.swift:110`
- `Tests/RelatedLinkSectionPreservationTests.swift:57`

Rerun the grep on the post-N1/N2 tree and add anything new. This task changes the label at every
site and passes the target's **path** where a title was passed (`"Destinazione"` becomes
`"03 Risorse/Destinazione.md"` or whatever path the fixture wrote). The session's body is left as it
is (it still resolves what it is given as a title), which is what makes the path-based assertions
red until Task 4. No assertion is weakened: each keeps its meaning with a path in place of a title.
`reportsATargetThatDoesNotExist` becomes "a path that does not exist", and its problem still names
it. This is a test change, so it is stated here and in the PR body as the CLAUDE.md rule asks: the
API changed shape on purpose (ADR-0084 §D4), the tests follow the API, none is disabled.

The sheet passes the selected note's path: its `List` selection is re-tagged by path (it is tagged
by `note.title` today, which two notes can share). That is the call-site half; the mirror, the
preselection and the folder labels are Task 7's.

**The second pinned value.** `Tests/ViewConnectorTests.swift:134`, `everySampleViewParses`, pins
`total == 9` blocks across `SampleViews.all`. Adding «Vista - Link non risolti» (one block) makes it
`10`; the pin is updated with a comment naming the new sample, which is the reason the pin exists
("a block dropped … is a failure here"). `installingTheSamplesWritesThemOnceAndNeverAgain` counts
through `SampleViews.all.count` and needs nothing. The sample itself goes in this task with its real
text (it is data the test reads), `where: has(unresolved)`, `sort: title`, `render: table`,
`columns: [title, unresolved]`, and one sentence of prose saying the inspector now shows the open
note's own unresolved links and this view shows the vault's.

New tests, red against stubs:

- `VaultLinkWritesTests` (session): `linkMention` writes `[[T]]` / `[[T|testo]]` once, with
  `expecting:`; a hash that no longer matches → `.movedOn` and the file untouched; no mention left →
  `.noMention`; `planLinkMention`'s `after` is exactly what lands. `addStructuralLink(toNoteAt:)`
  with two notes of one title links the one named by path; an unknown path is a named problem.
  `removeStructuralLink`: both sides lose `related` and the bullet; one side holding nothing is
  skipped and the other still written; neither → a named problem, nothing written; **the second
  write refused** through the symlink fixture `VaultUnguardedWriteGuardTests` already uses for
  `addStructuralLink` (deterministic, no timing): the first lands, the problem says «tolto a metà»
  and names both paths, `written` holds the one that landed.
- `VaultControllerLinkWritesTests` (controller, PG-233): a structural removal and a mention link on
  a note open **dirty** in a tab (focused, background, other column) raise ADR-0001 §D3.4's prompt
  and never save the buffer; a clean tab adopts the new text (ADR-0067's door, ADR-0084 §D5).
- `ConnectorLinkWritesTests`: `VaultAPI.linkMention` and `removeStructuralLink` under `arm(dryRun:
  true)` return a diff and change no byte; armed for real they write and journal; an ambiguous
  title for `linkMention` is the one this note's text mentions (the title is the target's, the path
  is the note written); a half-done removal returns the landed summary with a `note` naming the
  refused side.
- `IndexUnresolvedTargetsTests`: `unresolvedTargets(of:)` for one note; and **the three-way
  agreement test** over one vault: `IndexSnapshot.unresolvedTargets(of:)`, `VaultAPI.links(_:at:)
  .unresolved` and the query field `unresolved` (`ViewField.unresolved` through `ViewEvaluator`) give
  the same list for every note (SPEC API: "sharing the derivation").
- `NoteAppearancesSessionTests`: a temporary vault with a board holding a `.file` node on the note,
  a board that is not valid JSON (counted, not fatal), a pratica whose `pratica.md` lists the note
  in `pergamenum-dossier-links-notes`, a message whose `pergamenum-mail-note` names it, and a second
  note of the same title in another folder (claimed by neither); read from files, a cache-reused
  record included (ADR-0049 §D4).

Stub bodies: `unresolvedTargets` returns `[]`, `planLinkMention` nil, `linkMention` `.failed("")`,
`removeStructuralLink` `(false, [])`, `noteAppearances` empty, the controller wrappers false, the
two `VaultAPI` functions throw `ConnectorError("non implementato")`. `VaultSession+Appearances.swift`
is a new file outside `sharedSources`, app only; everything else lands in files the tools already
compile (`VaultSession+Notes.swift` is listed in `sharedSources`, `Sources/Connector/**` is globbed).

### Task 4 — Session and connector writes, green; perg and MCP verbs (R-22, R-25, R-26, R-27, R-28)

Owner: coder
Files:
- Sources/Index/IndexSnapshot.swift, Sources/Vault/VaultSession+Notes.swift, Sources/Vault/VaultSession+Appearances.swift
- Sources/App/VaultController+Notes.swift, Sources/Features/Editor/RelatedLinkSheet.swift
- Sources/Connector/VaultLinkWrites.swift
- Sources/CLI/main.swift, Sources/CLI/Commands/WriteCommands.swift, Sources/CLI/Help.swift
- Sources/MCPServer/ToolCatalogue+NoteLinks.swift, Sources/MCPServer/ToolCatalogue.swift
- Sources/MCPServer/VaultHost+NoteLinks.swift, Sources/MCPServer/VaultHost.swift
- scripts/mcp-smoke.py
Tests: VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift, ConnectorLinkWritesTests.swift, IndexUnresolvedTargetsTests.swift, NoteAppearancesSessionTests.swift, RelatedLinkTests.swift, VaultUnguardedWriteGuardTests.swift, ConnectorTests.swift, ViewConnectorTests.swift
Signatures:
- (Task 3's, bodies only)
- perg — `perg note link-mention <percorso> <titolo> [--allow-write] [--dry-run]`
- perg — `perg note unlink-related <percorso> <percorso-destinazione> [--allow-write] [--dry-run]`
- MCP link_mention — `{ "path": string, "title": string, "dryRun": boolean = true }`, write tool, listed only under `--allow-write`
- MCP remove_structural_link — `{ "path": string, "target": string, "dryRun": boolean = true }`, write tool, listed only under `--allow-write`
Red: no

**Session** (`VaultSession+Notes.swift`, beside `addStructuralLink`, so the file stays one place for
note-level link writes; it is about 280 lines and stays under SwiftLint's 400-line warning):

- `addStructuralLink(from:toNoteAt:...)` reads the target by path; `resolve(title:).first` goes.
  The rest of the body is unchanged (both renders before either write, `expecting:` on each, the
  half-done sentence).
- `removeStructuralLink` mirrors it over `RelatedLink.remove(target:from:)` with the titles read off
  both records; a side whose text does not change is not written; the problem strings are ADR-0084
  §D4's, word for word.
- `planLinkMention` reads the note, takes the target's `aliases` from the index record of the note
  titled `title`, calls `UnlinkedMentions.firstMention` with `[title] + aliases` and
  `MentionLink.rewrite`. `linkMention` re-reads after nothing (it is not called across an `await`
  before its own read), plans again, compares the caller's hash with the read's, and writes once
  with `expecting:` the read's hash. A `WriteRefusal` is `.movedOn`.

**Index:** `unresolvedTargets(of:)` is `UnresolvedTargets.of(notes[path]?.linkTargets ?? [],
resolving: resolve(title:))`, one line in `IndexSnapshot.swift`, which is shared, so the tools get
it free.

**Appearances** (`VaultSession+Appearances.swift`, app only): `CanvasStore.allBoards()`, `load(board:)`
per board collecting `.file(path:subpath:)` paths (a throw counts as unreadable);
`VaultAPI.praticaNotes(among:vaultRoot:)` and `messageNotes(among:folders:)` for the folders and
message records (called, ADR-0084 §D6); `PraticaLinks.parse(praticaFileAt:)` and
`MessageDocument.parse(text)?.frontmatter.linkedNote` read off the files; `candidates` resolves a
reference through `PraticaLinkReference` and `index.resolve(title:)`; then
`NoteAppearances.build`. Synchronous and main-actor, like `unlinkedMentions(for:)`; the section runs
it from a `Task` on request.

**Connectors** (`Sources/Connector/VaultLinkWrites.swift`, a new file because `VaultWrites.swift`
is at 377 lines): `linkMention` checks the note exists, plans, and writes through the session;
`.noMention` throws «nessuna menzione non collegata di «T» in «path»»; `.movedOn` throws
`VaultWriteRefusal.movedOn(path).description` as `appendToNote` does; a success is
`summarise(result, session:)`. `removeStructuralLink` takes two paths, maps the outcome as ADR-0084
§D4 says, and returns one `WriteSummary` per file written. Under `isDryRun` the session computes
both writes and performs neither, so a rehearsal returns both diffs.

**perg** (`main.swift`'s `noteGroup` gains two words; `WriteCommands` gains `noteLinkMention` and
`noteUnlinkRelated` in the shape of `noteRename`; `Help.swift` documents both under the writes).
**MCP:** the two tools in a new `ToolCatalogue+NoteLinks.swift` (`ToolCatalogue+Writing.swift` is at
399 lines), joined to the list `tools/list` returns under `--allow-write` wherever
`ToolCatalogue.writing` is read today; dispatch in a new `VaultHost+NoteLinks.swift`
(`writeNoteLinks(_:_:)`), chained from an existing write table's `default:` the way
`VaultHost+PraticheLinks.swift` is, both arming `VaultAPI.arm` with `dryRun` defaulting to `true`.

**`scripts/mcp-smoke.py`** gains a `note_links(binary, vault, check)` section in the shape of
`pratiche_links`: both tools absent without `--allow-write`; a `dryRun` call returns a diff and the
fixture file is byte-identical after it; a real `link_mention` leaves `[[T]]` in the file; a real
`remove_structural_link` leaves neither note with the `related` entry. Run it after the build:
`python3 scripts/mcp-smoke.py` against a Debug `pergamenum-mcp` (CLAUDE.md "AI connector").

Build all three schemes (`Pergamenum`, `perg`, `pergamenum-mcp`) before calling this done: a Core or
Connector file that reaches for an app type breaks the two tool builds, not the app's.

### Task 5 — App and editor link behaviour, red (R-20, R-21, R-22, R-23, R-24, R-25, R-26, R-27)

Owner: tester
Files:
- Sources/App/VaultController+LinkOpening.swift, Sources/Vault/NoteTab.swift
- Sources/App/CommandActions+LinkNavigation.swift, Sources/App/Navigation.swift
- Sources/Core/Shortcuts/ShortcutCommand.swift, Sources/App/CommandActions.swift, Sources/App/CommandActions+CanRun.swift
- Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView.swift
- Sources/Features/Editor/NoteTextView+LinkPreview.swift, Sources/Features/Editor/NoteTextView+LinkAtCaret.swift
- Sources/Features/Editor/CompletionPanel.swift, Sources/Features/Editor/QuickSwitcher.swift
- Sources/Features/Editor/BacklinksSection.swift, Sources/Features/Editor/LinkMentionSheet.swift, Sources/Features/Editor/VaultBrowser.swift
- Tests/LinkOpeningControllerTests.swift, Tests/LinkFollowCommandTests.swift, Tests/WikilinkClickVariantTests.swift
- Tests/LinkAtCaretReportTests.swift, Tests/LinkPreviewControllerTests.swift, Tests/LinkPreviewPanelTests.swift
- Tests/WikilinkCreationRowTests.swift, Tests/QuickOpenHeadingTargetsTests.swift, Tests/BacklinkCommandTests.swift
- Tests/LinkMentionReviewTests.swift, Tests/ShortcutTests.swift, Tests/InspectorSectionLabelTests.swift
Tests: LinkOpeningControllerTests.swift, LinkFollowCommandTests.swift, WikilinkClickVariantTests.swift, LinkAtCaretReportTests.swift, LinkPreviewControllerTests.swift, LinkPreviewPanelTests.swift, WikilinkCreationRowTests.swift, QuickOpenHeadingTargetsTests.swift, BacklinkCommandTests.swift, LinkMentionReviewTests.swift, ShortcutTests.swift, InspectorSectionLabelTests.swift, OpenLinkUnresolvedTests.swift, WikilinkClickNavigationTests.swift, NoteEditorTeardownTests.swift, EditorCommandTests.swift
Signatures:
- VaultController.openNote(at:how:) — `func openNote(at relativePath: String, how: LinkOpening)`
- VaultController.openNoteInOtherColumn — `func openNoteInOtherColumn(at relativePath: String)`
- VaultController.recordLinkAtCaret — `func recordLinkAtCaret(_ url: URL?, inColumn columnIndex: Int)`, `var linkAtCaret: URL? { get }`
- NoteTab.linkAtCaret — `var linkAtCaret: URL?` (transient, never persisted by `OpenTabsStore`)
- VaultController.offerNoteCreation — `func offerNoteCreation(title: String, besideNoteAt sourcePath: String?)`
- VaultController.beginStructuralLink — `func beginStructuralLink(preselecting targetPath: String?)`, `var structuralLinkPreselection: String?`
- LinkRequest — `struct LinkRequest: Equatable, Sendable { let target: String; let how: LinkOpening; let sourcePath: String?; let fromClick: Bool }`
- LinkFollowOutcome — `enum LinkFollowOutcome: Equatable, Sendable { case done, choose([LinkChoice]) }`
- LinkChoiceRequest — `struct LinkChoiceRequest: Identifiable, Equatable { let id: UUID; let title: String; let choices: [LinkChoice]; let how: LinkOpening; let sourcePath: String? }`
- Navigation.linkChoice — `var linkChoice: LinkChoiceRequest?`
- CommandActions.follow — `func follow(_ request: LinkRequest) -> LinkFollowOutcome`
- CommandActions.open(link:how:) — `func open(link target: String, how: LinkOpening = .replace, from sourcePath: String? = nil)`
- CommandActions.open(notePath:how:) — `func open(notePath: String, how: LinkOpening)`
- CommandActions.choose — `func choose(_ choice: LinkChoice, how: LinkOpening, from sourcePath: String?)`
- ShortcutCommand — `case followLink, followLinkInNewTab, followLinkInOtherColumn` (appended last, section `.view`), `static let shipsUnbound: Set<ShortcutCommand> = [.followLinkInNewTab, .followLinkInOtherColumn]`
- NoteTextView.LinkInputs — `struct LinkInputs { var follow: ((LinkRequest) -> LinkFollowOutcome)?; var choose: ((LinkChoice, LinkOpening) -> Void)?; var preview: ((String, String?) -> LinkPreviewContent?)?; var onCaretLinkChanged: ((URL?) -> Void)?; var offerCreation: ((String) -> Void)? }`, `var links = LinkInputs()` on `NoteTextView`
- LinkChoiceMenuPresenting — `@MainActor protocol LinkChoiceMenuPresenting: AnyObject { func present(_ menu: NSMenu, at point: NSPoint, in view: NSView) }`
- LinkPreviewPresenting — `@MainActor protocol LinkPreviewPresenting: AnyObject { var isShowing: Bool { get }; func show(_ content: LinkPreviewContent, below rect: NSRect, in view: NSView); func hide() }`
- LinkPreviewController — `@MainActor final class LinkPreviewController { init(parent: @escaping () -> NoteTextView?, presenter: LinkPreviewPresenting, now: @escaping () -> TimeInterval); var hasEventMonitor: Bool { get }; func pointerMoved(to point: NSPoint, in textView: CompletingTextView, commandDown: Bool); func commandChanged(isDown: Bool); func keyPressed(isEscape: Bool) -> Bool; func pointerExited(); func tearDown() }`
- CompletionItem.createNote — `case createNote(title: String)`
- QuickSwitcher.headingTargets — `static func headingTargets(for notePart: String, exact: (String) -> [String], firstMatch: (String) -> String?) -> [String]`
- BacklinkCommand — `enum BacklinkCommand: CaseIterable, Identifiable { case open, openInOtherColumn, makeStructural, unlink; var title: String; static func available(for row: BacklinkRow) -> [BacklinkCommand] }`
- VaultBrowser.InspectorSection — `static func unresolved(count: Int) -> InspectorSection` (replaces `unresolved(shown:)`), `static func whereAppears(found: Int?) -> InspectorSection`
- LinkMentionReview — `@MainActor @Observable final class LinkMentionReview { enum State: Equatable { case reviewing(diff: String, notice: String?), linked, nothingToLink, failed(String) }; init(vault: VaultController, notePath: String, title: String); private(set) var state: State; func confirm() async }`
Red: yes

All hosted tests use the in-process family's harness (`Tests/HostedViewSupport.swift`,
`EmbedEditorFixtures.editor(...)`): no window ordered front, no `sendEvent`, the `modifierFlags`
seam for Cmd state (as `WikilinkClickNavigationTests` does), and every AppKit presentation behind
a spy. A test that needs a real menu, a real panel on screen or the real menu bar is not written
here; it is one of Task 8's three.

**Two existing tests change, and why** (CLAUDE.md: say so before changing a test):

- `Tests/ShortcutTests.swift:54` `noTwoCommandsShipOnTheSameKeys` and `:67`
  `everyShippedDefaultIsUsable` assume every command ships with a key. The SPEC decided two commands
  ship with none (Decision "Link variants"). Amended, not disabled: the collision walk skips an
  empty `KeyBinding` (no key cannot collide with no key); the usability check skips exactly the
  commands in `ShortcutCommand.shipsUnbound`, and a new test pins that set to the two variants and
  asserts every command outside it still ships a valid, usable key. A third unbound command is then
  a red test.
- `Tests/InspectorSectionLabelTests.swift:22` pins `unresolved(shown:)`'s «mostrati» label, which
  described the capped vault-wide list. The section now lists the open note's own links, uncapped;
  the function becomes `unresolved(count:)` with «Link non risolti in questa nota: N», title and
  identifier unchanged, and the test follows it.

`Tests/EditorCommandTests.swift:152` (`allCases.count - 2`) is checked and **not** changed: the
three new commands stay in the slash catalogue, and at runtime `canRun` keeps them out of it (the
caret sits on the typed `/`, never inside a link). `Tests/OpenLinkUnresolvedTests.swift` must stay
green unmodified: `TRUST.md` is not creatable, so its «nota non trovata» sentence stands.

New tests, red against stubs:

- `LinkOpeningControllerTests`: `.replace` and `.newTab` keep today's behaviour; `.otherColumn` with
  one column adds the second and focuses it with the target in front and the source column
  untouched; with two columns focuses the other, deduping a tab already there; the focused column's
  index is what ADR-0015's destination reads afterwards.
- `LinkFollowCommandTests`: `open(link:how:)` on an ambiguous title sets `navigation.linkChoice` and
  opens nothing; `follow(_:)` with `fromClick: true` returns `.choose` and sets nothing; a creatable
  missing title gives the one create choice; `choose(.create)` calls `offerNoteCreation` with the
  source's folder and puts the Note pane in front; a parked draft with a title is kept and a problem
  recorded (ADR-0083 §D6, the recommended default); `canRun(.followLink)` false with no link at the
  caret and outside the Note pane, true with one; `run(.followLink)` follows the focused tab's
  `linkAtCaret`; a board link opens the board whatever the how; an external URL is opened through a
  seam, never in a test for real.
- `WikilinkClickVariantTests` (hosted): Cmd, Cmd+Shift, Cmd+Opt reach `links.follow` with
  `.replace`, `.newTab`, `.otherColumn`; with `links.follow` nil, Cmd still calls `onFollowLink`
  and the variants do nothing; a `.choose` outcome hands the spy presenter an `NSMenu` whose items
  are the folder labels and whose header is disabled; invoking an item calls `links.choose` with
  that choice and the click's how.
- `LinkAtCaretReportTests` (hosted): moving the selection into, along and out of a link reports
  the URL, the same URL, then nil, through `links.onCaretLinkChanged`; a file embed reports nil;
  `recordLinkAtCaret` writes the column's active tab only.
- `LinkPreviewControllerTests` (hosted, spy presenter, injected clock): a note link shows the
  host's content after the dwell; an external URL never asks for content or shows; Command up,
  `pointerExited`, a key, and `keyPressed(isEscape: true)` hide (Escape consumed only while
  shown); `tearDown()` hides and leaves `hasEventMonitor` false; the monitor exists only between
  the first `pointerMoved` and `pointerExited`; the text view is the window's first responder
  before, during and after (the SPEC's edge case); `links.preview` nil means the presenter is never
  called.
- `LinkPreviewPanelTests`: the production presenter's panel is a `NeverKeyPanel` with
  `ignoresMouseEvents == true`, built and never ordered front (the shape `NeverKeyPanelTests` has).
- `WikilinkCreationRowTests`: an open `[[Bozza` with no candidate and `offerCreation` set lists
  `.createNote("Bozza")` as the only row; none when a candidate matches, when the text is not
  creatable (`a:b`, `Nota.md`), or with no handler; choosing it closes the link once (R-03's rule:
  never `]]]]`) and calls the handler once.
- `QuickOpenHeadingTargetsTests`: a note part matching two titles exactly gives both paths; one
  exact match gives one; none falls back to the search's first, as today.
- `BacklinkCommandTests`: a plain row offers open, openInOtherColumn, makeStructural; a structural
  row open, openInOtherColumn, unlink; titles are the SPEC's Italian.
- `LinkMentionReviewTests` (controller, temporary vault): unchanged note → `confirm()` → `.linked`
  and the file holds the link; the note written between review and confirm → `.reviewing` with the
  recomputed diff and the notice; mention gone → `.nothingToLink`.

### Task 6 — Links in the editor: the door, the variants, the keyboard, the choice, the creation offer, the preview (R-20, R-21, R-22, R-23)

Owner: coder
Files:
- Sources/App/VaultController+LinkOpening.swift, Sources/Vault/NoteTab.swift
- Sources/App/CommandActions+LinkNavigation.swift, Sources/App/CommandActions.swift, Sources/App/CommandActions+CanRun.swift
- Sources/App/MenuCommands.swift, Sources/App/Navigation.swift, Sources/App/RootView+Sheets.swift
- Sources/Core/Shortcuts/ShortcutCommand.swift
- Sources/Features/Editor/NoteTextView.swift, Sources/Features/Editor/NoteTextView+Inputs.swift, Sources/Features/Editor/NoteTextView+Coordinator.swift
- Sources/Features/Editor/NoteTextView+LinkAtCaret.swift, Sources/Features/Editor/NoteTextView+LinkPreview.swift
- Sources/Features/Editor/LinkPreviewView.swift, Sources/Features/Editor/LinkChoiceSheet.swift
- Sources/Features/Editor/CompletingTextView.swift, Sources/Features/Editor/CompletionPanel.swift, Sources/Features/Editor/CompletionPanelView.swift
- Sources/Features/Editor/EditorColumn+Text.swift, Sources/Features/Editor/EditorColumnView.swift, Sources/Features/Editor/QuickSwitcher.swift
- Sources/Features/Today/TodayView.swift, Sources/Features/Diary/DiaryView.swift, Sources/Features/Workspace/BoardTray.swift
Tests: LinkOpeningControllerTests.swift, LinkFollowCommandTests.swift, WikilinkClickVariantTests.swift, LinkAtCaretReportTests.swift, LinkPreviewControllerTests.swift, LinkPreviewPanelTests.swift, WikilinkCreationRowTests.swift, QuickOpenHeadingTargetsTests.swift, ShortcutTests.swift, OpenLinkUnresolvedTests.swift, WikilinkClickNavigationTests.swift, NoteEditorTeardownTests.swift, NavigationHistoryTests.swift, EditorCommandTests.swift, CompletionPanelTests.swift, NeverKeyPanelTests.swift
Signatures:
- (Task 5's, bodies only)
Red: no

In this order, each step building and its tests green before the next:

1. **The door** (ADR-0083 §D1). `VaultController+LinkOpening.swift` holds `openNote(at:how:)`,
   `openNoteInOtherColumn(at:)` (`addColumn()` then `focusColumn(1)` with one column, `focusColumn`
   of the other with two, then `openNote(at:)`), `recordLinkAtCaret(_:inColumn:)` in
   `recordOutlineEntry`'s shape, and `offerNoteCreation(title:besideNoteAt:)` (sets `noteDraft` with
   the title and the source's folder and `isComposingNote = true`; a parked draft with a title is
   kept and the problem recorded). A new file because `VaultController+Tabs.swift` is at 396 lines.
   `CommandActions+LinkNavigation.swift` holds `follow`, `open(link:how:from:)` (which keeps the
   `.canvas` branch and PG-356's sentence and replaces `.first` with `LinkDestination.resolve`),
   `open(notePath:how:)` and `choose(_:how:from:)`.
2. **The keyboard** (ADR-0083 §D3). The three cases appended to `ShortcutCommand` with titles,
   section `.view`, `followLink`'s default `KeyBinding("return", [.command, .option])`, the variants
   `KeyBinding("")`. **Measure Cmd+Opt+Return against `com.apple.symbolichotkeys` before binding it**
   (`defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys`, the method the comments at
   `ShortcutCommand.swift:119` and `:297` record) and write the result in the case's comment; if it
   is taken, stop and report rather than pick another key, since the SPEC named this one.
   `CommandActions.runView` gains one arm for the three (cyclomatic complexity +1, which matters in
   that file: see its own comment about the linter); `canRun` gains them; `MenuCommands` puts three
   items in Vista after Avanti, each `.keyboardShortcut(shortcuts.shortcut(for:))` and
   `.disabled(!actions.canRun(...))`, so the variants show no key until the person binds one.
   `NoteTextView+LinkAtCaret.swift`: on every selection change the Coordinator gathers the caret
   paragraph's `.editorLink` runs and `WikilinkParser` ranges, calls `LinkAtCaret.pick`, and reports
   through `links.onCaretLinkChanged` only when the URL changed. `EditorColumn+Text` wires it to
   `vault.recordLinkAtCaret(_:inColumn: columnIndex)`.
3. **The variants and the choice at a click** (ADR-0083 §D2, §D5).
   `textView(_:clickedOnLink:at:)` keeps its Cmd guard and, for a `.note` target with `links.follow`
   set, builds a `LinkRequest(fromClick: true)` with `LinkOpening.forClick(shift:option:)` from
   `modifierFlags()`. A `.choose` outcome builds an `NSMenu` (disabled header, one item per choice)
   and hands it to `linkChoiceMenus.present(_:at:in:)` at the click point (the current event's
   location, converted), the production presenter calling `popUp(positioning:at:in:)`. `.external`
   and `.embed` keep their branches; N1's tag and date branches are untouched. With `links.follow`
   nil, the old `onFollowLink(title)` call stays.
   `LinkChoiceSheet` (title «Quale «X»?» or «Crea «X»?», the rows, Return, «Annulla») is hosted in
   `RootView+Sheets.swift` on `Bindable(navigation).linkChoice`, beside `taskPickingBoard`.
4. **Every follow site** (ADR-0083 §D5). `EditorColumn+Text` passes `links` built from
   `commandActions` (focused, as `follow(title:)` does today) and the preview closure (step 6).
   `TodayView` and `DiaryView` gain `@Environment(CommandActions.self)` and pass `links` too; Diario
   keeps `controller.flush()` before following. `BoardTray`'s title fallback calls
   `commandActions.open(link:)` when the title resolves to several notes and keeps the path open
   otherwise. `QuickSwitcher.headingQuery` reads `headingTargets` and draws one heading group per
   path under its folder label. After this step, `rg -n "resolve\(title: .*\)\.first" Sources`
   finds none of the five follow sites ADR-0083 §D5 lists (the transclusion source and
   `creationRow` are not follow sites and may remain).
5. **Creation** (ADR-0083 §D6). `CompletionItem.createNote(title:)`, drawn by `CompletionPanelView`
   with `plus.square` and «Crea «X»»; `refreshCompletion` adds it for `.wikilink(prefix)` when the
   candidates are empty, `LinkDestination.isCreatable(prefix)` holds and `offerCreation` is set;
   `apply` completes the link through the R-03 insertion N1 shipped, then calls `offerCreation`.
6. **The preview** (ADR-0083 §D7). `LinkPreviewController` in `NoteTextView+LinkPreview.swift`, owned
   by the Coordinator like `TableBlockController` (ADR-0074 §D2/§D3: the parent read through the
   provider at use time), created when `links.preview` is set. Its tracker `NSResponder` owns one
   tracking area over the visible rect, replaced on `updateTrackingAreas` of the scroll view's
   bounds (not on `CompletingTextView`'s own override, N1's file); one local monitor
   (`.flagsChanged`, `.keyDown`, `.scrollWheel`) between entry and exit; `pointerMoved` resolves
   the run through `linkCharacterIndex(at:)` and the attribute's effective range; the section comes
   from `WikilinkParser` at the index. The production presenter builds a `NeverKeyPanel`
   (`ignoresMouseEvents = true`) hosting `LinkPreviewView` (tokens only, light and dark, identifier
   `link-preview`), placed through `PanelPlacement` below the link's line rect or above it, and
   ordered out on `hide`. The Coordinator's teardown (`NoteEditorTeardownTests`' path) calls
   `tearDown()`. `EditorColumn+Text`, Oggi and Diario supply the content closure through
   `LinkDestination.resolve`, `session.read` and `LinkPreviewContent.make`.

Keep every view under the token rule (CLAUDE.md "Design system"): no colour or font outside
`theme`. Run the full unit suite at the end of this task, not only the new tests.

### Task 7 — The inspector: backlinks with context, unresolved per note, «Collega», the structural sheet, «Scollega», «Dove compare» (R-22, R-24, R-25, R-26, R-27, R-28)

Owner: coder
Files:
- Sources/Features/Editor/BacklinksSection.swift, Sources/Features/Editor/UnresolvedLinksSection.swift, Sources/Features/Editor/WhereNoteAppearsSection.swift
- Sources/Features/Editor/UnlinkedMentionsSection.swift, Sources/Features/Editor/LinkMentionSheet.swift
- Sources/Features/Editor/RelatedLinkSheet.swift, Sources/Features/Editor/VaultBrowser.swift
- Sources/App/VaultController+Notes.swift
Tests: BacklinkCommandTests.swift, LinkMentionReviewTests.swift, InspectorSectionLabelTests.swift, BacklinkContextTests.swift, ReverseReasonMirrorTests.swift, VaultLinkWritesTests.swift, VaultControllerLinkWritesTests.swift, NoteAppearancesSessionTests.swift, RelatedLinkTests.swift
Signatures:
- (Task 5's inspector signatures, bodies only)
- BacklinksSection — `struct BacklinksSection: View { let note: VaultController.OpenNote }`
- UnresolvedLinksSection — `struct UnresolvedLinksSection: View { let note: VaultController.OpenNote }`
- WhereNoteAppearsSection — `struct WhereNoteAppearsSection: View { let notePath: String }`
- LinkMentionSheet — `struct LinkMentionSheet: View { let review: LinkMentionReview }`
Red: no

`VaultBrowser.swift` is over SwiftLint's `type_body_length` warning already, so its two private
sections move out rather than grow: `backlinks(_:)` becomes `BacklinksSection`, `unresolved` becomes
`UnresolvedLinksSection`, and `inspector` reads, in order: star, category link, history,
`BacklinksSection`, `UnlinkedMentionsSection`, `WhereNoteAppearsSection`, `LinkedTasksPanel`,
`UnresolvedLinksSection`. `InspectorSection` stays in `VaultBrowser` (its tests name it there) and
gains `whereAppears(found:)`.

- **`BacklinksSection`** (ADR-0084 §D1): rows from `BacklinkRow.make`, text read through
  `vault.session?.read`, memoised in an `IndexKeyedMemo` keyed by `vault.indexGeneration` and the
  title; the row draws as the approved mockup does; `.contextMenu` and `.accessibilityActions` from
  `BacklinkCommand.available(for:)` (ADR-0023 §D1); `open` and `openInOtherColumn` through
  `commandActions.open(notePath:how:)`; `makeStructural` through
  `vault.beginStructuralLink(preselecting:)`; `unlink` through `.confirmationDialog(_:isPresented:
  presenting:)`, whose closure receives the row (CLAUDE.md working agreement), then
  `vault.removeStructuralLink(from:toNoteAt:)`.
- **`UnresolvedLinksSection`** (ADR-0084 §D2): `vault.index.unresolvedTargets(of:)`, deduplicated
  case-insensitively for display; «Crea nota» → `commandActions.choose(.create)` with this note as
  the source (only when creatable); «Vai al link» → `UnresolvedTargets.firstLine` → `NoteJump`'s
  range and ordinal → `navigation.jumpToLine(range:ordinal:)`.
- **«Collega»** (ADR-0084 §D3): each row of `UnlinkedMentionsSection` gains a «Collega» button that
  creates a `LinkMentionReview` and presents `LinkMentionSheet` (`DiffView` over the review's diff,
  the notice when present, «Collega» / «Annulla»); after `.linked` the section drops the row; after
  `.nothingToLink` it replaces the row with the sentence. `VaultController.linkMention` is the
  wrapper Task 4 wrote.
- **The structural sheet** (ADR-0084 §D4): `ReverseReasonMirror` drives the reverse field
  (`.onChange` of the forward field calls `forwardChanged`, the reverse field's binding calls
  `reverseEdited`); the selection is the path (Task 3 re-tagged it) and a row shows
  `LinkChoice.folderLabel` when its title is shared by another candidate; on appear the sheet reads
  `vault.structuralLinkPreselection`, selects it, and clears it. `beginStructuralLink(preselecting:)`
  sets that value and `isAddingRelatedLink`.
- **`WhereNoteAppearsSection`** (ADR-0084 §D6): resting button, scanning, results, empty, «Cerca di
  nuovo», in `UnlinkedMentionsSection`'s shape; the scan is `vault.session?.noteAppearances(of:)`
  from a `Task`, memoised by `(path, indexGeneration)`, re-run by «Cerca di nuovo»; a board row sets
  `vault.routeState.pendingCanvas = (path, nil)`; a pratica or message row calls
  `pratiche.select(folder, in: vault)` and `navigation.pane = .pratiche`. If the mockup approval
  chose "automatic", the scan starts in `.task(id:)` keyed on the note path instead, and nothing
  else changes.

Every row and button carries an `accessibilityIdentifier` (`backlink-row-<path>`,
`unresolved-link-<target>`, `unlinked-mention-link-<path>`, `link-mention-confirm`,
`where-appears-scan`), because Task 8's GUI test finds controls by identifier, never by their words.

### Task 8 — The three GUI tests, then the whole suite (R-20, R-21, R-26)

Owner: tester
Files:
- UITests/WikilinkNavigationUITests.swift
- UITests/LinkMentionUITests.swift
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
(`app.links["Destinazione"]`, the existing file's helper), never by on-screen prose.

1. **Follow from the keyboard, then return** (R-21): open «Origine», click into the editor, put
   the caret inside `[[Destinazione]]` with Cmd+Up then Right arrow keys, `typeKey(.return,
   modifierFlags: [.command, .option])`, wait for the editor's value to contain «Nota di arrivo»,
   `typeKey("[", modifierFlags: .command)`, wait for «Origine»'s text back.
2. **The preview appears and goes** (R-20): inside `XCUIElement.perform(withKeyModifiers:
   .command) { link.hover(); … }`, wait for the element with identifier `link-preview` to exist
   (the dwell is 250 ms, wait up to 3 s); after the block, assert it is gone within 2 s.
3. **«Collega» a mention** (R-26): a vault with «Curva» and «Prova» whose body names «Curva»
   without a link; open «Curva», press `unlinkedMentions` (the existing scan button), then
   `unlinked-mention-link-Prova.md`, wait for the sheet, press `link-mention-confirm`; assert the
   file `Prova.md` (read by the test, which made the vault) contains `[[Curva]]`, and that
   `backlink-row-Prova.md` exists.

Run them through the script only (CLAUDE.md): `scripts/uitests.sh --status` first, then
`scripts/uitests.sh WikilinkNavigationUITests` and `scripts/uitests.sh LinkMentionUITests` (an
argument replaces the selection), then `scripts/uitests.sh --affected` as the merge asks. A red is
read from the run's `.xcresult` before anything is rerun; a 60.2 s failure is the launch timeout,
not the feature.

Then the **whole unit suite**, not only the new files: this PR changes four observable contracts
(`addStructuralLink`'s signature, `InspectorSection.unresolved`, the shortcut catalogue, the mention
scan's code rule), and a contract change can break a test in a module nobody touched:
`xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS'
-only-testing:PergamenumTests test`. Then build `perg` and `pergamenum-mcp` and run
`python3 scripts/mcp-smoke.py`. Then the by-hand checks no automated test reaches: the preview and
the choice menu in light and dark, the two Vista variants after binding a key to each in
Impostazioni ▸ Scorciatoie, a follow from Oggi and from Diario, «Dove compare» on a note used by a
board and a pratica.

## Risks and HITL gates

- **HITL: the mockup approval** (`docs/plans/note-workflow-n3-mockup.md`) gates Tasks 6 and 7. Its
  open choices feed them: preview size, badge form, mirrored-text look, «Dove compare» on request or
  automatic.
- **HITL: decisions raised for the person at this plan's gate.** (a) An offer to create a note while
  a draft is parked keeps the draft and says so (recommended), or replaces it. (b) «Collega» writes
  `[[Titolo|testo]]` for any mention whose text differs from the title, case and accents included,
  not only for an alias (recommended: the prose never changes). (c) «Dove compare» on request
  (recommended) or automatic. (d) Diario and the board tray are routed through the choice too,
  beyond the SPEC's four surfaces (recommended: the SPEC's rule says "from any surface"). (e) The
  preview is a never-key panel, not the `NSPopover` the SPEC's Stack line names (ADR-0083,
  Alternatives).
- **HITL: commit, push, PR.** On a feature branch, never `main`; the commit and the push are the
  person's gates. The pre-push hook (ADR-0061/0062) must be installed on the machine.
- **Contract changes** (staleness rule): `addStructuralLink(from:to:)` → `(from:toNoteAt:)` with
  every call site listed in Task 3; `InspectorSection.unresolved(shown:)` → `unresolved(count:)`;
  `SampleViews.all` 6 → 7 (`everySampleViewParses` 9 → 10); `ShortcutCommand` +3 cases and the two
  guard tests amended; the mention scan's code narrowing. Full unit suite after the change, Task 8.
- **Protected interface.** `CompletingTextView+Pasteboard.swift` is protected as a whole file; this
  plan only calls `linkCharacterIndex(at:)`. A diff to that file is a stop, and
  `interface-check.sh` blocks it anyway.
- **Parallel files.** N1 edits `CompletingTextView+CursorRects.swift`, the click path (R-07) and the
  completion insertion (R-03); N2 edits the styler and possibly the Coordinator. N3 is built after
  both merge; rebase first, rerun Task 1's three seam checks, then start. Two worktrees editing
  `NoteTextView+Coordinator.swift` at once is the roadmap's named risk.
- **The preview's event plumbing.** A tracking area plus a local monitor is the PG-258 shape. The
  hosted tests pin the lifecycle; the GUI test pins the real thing. Whether `perform(withKeyModifiers:)`
  produces the `flagsChanged` the controller listens for is not verified (insufficient data): the
  controller also starts the dwell from a pointer event with Command already down, so the test does
  not depend on it.
- **Cmd+Opt+Return** may be taken by a system shortcut on this machine; Task 6 step 2 measures
  before binding and stops if it is.
- **SwiftLint.** `CommandActions.swift` (401 lines) and `VaultController+Tabs.swift` (396) are at
  the file-length warning; new code goes in new files (`VaultController+LinkOpening.swift`,
  `VaultLinkWrites.swift`, `ToolCatalogue+NoteLinks.swift`, `VaultHost+NoteLinks.swift`) and
  `runView` gains one arm, not three.
- **The tools' build.** Everything in `Sources/Core/Links/` and `Sources/Connector/VaultLinkWrites.swift`
  compiles into `perg` and `pergamenum-mcp`; `VaultSession+Appearances.swift` must not be added to
  `sharedSources` (it reads `CanvasStore` and the pratiche helpers, which the tools have, but no
  connector exposes it, and keeping it app-only keeps the tools' surface what the SPEC lists).
- **No schema change.** `IndexCache.schemaVersion` is not touched; if any step seems to need it, stop:
  ADR-0084 rules it out.
- **External provisioning:** none. No network, no new dependency, no new setting.

TEST-CMD CANDIDATE: xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test
TEST-CMD MODE: brownfield

CHECK-CMD CANDIDATE: NONE

No static check is declared that passes on `main`: SwiftLint fails there by design on seven types
(`.swiftlint.yml`, `.github/workflows/ci.yml`'s header), so any `swiftlint lint` form would make the
stop-gate red before the suite runs. The type check is the build inside the test command.
