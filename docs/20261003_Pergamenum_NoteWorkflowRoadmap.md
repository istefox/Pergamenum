# Pergamenum — Implementation roadmap for the note workflow report

Date: 2026-10-03 · Source: `docs/20261002_Pergamenum_NoteWorkflowReport.md` (the report) ·
Tree: `main` at `8a783716`. Subordinate to `docs/20260811_Pergamenum_SpecApp.md` (v2.2) and
`CLAUDE.md`; where a milestone needs a SPEC amendment it is named in §4 and applied before
the milestone that depends on it, never silently (the rule Roadmap v2 §6 set).

Item identifiers (`R-n`, `I-n`, `L-n`) are the report's. Every milestone is one chain
through `/spec → /workplan → /build → /ship`, with `/workplan` and `/build` in separate
sessions. Mockups are approved before any view is written (SPEC §11.1). ADR numbers below
are the next free ones at the time of writing (`0078` is the last on `main`); they are
indicative, the chain that lands first takes the number.

---

## 0. Ground rules every milestone inherits

- **The file never changes shape.** Markdown, frontmatter (four keys), flat namespaced
  tags, JSON Canvas 1.0. Every rendering change is display-only; every creation change
  writes what SPEC §4 already specifies.
- **Concealment keeps the character count** (`NSTextContentStorageDelegate` substitution,
  `docs/20260817_TextKit2_live_editing.md`). A new construct is one more branch of
  `EditorDecorationDelegate.textContentStorage(_:textParagraphWith:)` plus, where a line
  must look different from a run of glyphs, a custom `NSTextLayoutFragment`
  (`HorizontalRuleFragment.swift`, `FoldedHeadingFragment.swift` are the shapes).
- **One grammar.** After N2 lands, `MarkdownStyler` classifies through
  `MarkdownBlockParser`/`MarkdownInlineParser`; a construct added later goes into
  `Sources/Core/Markdown` first and is drawn by every surface from the same span.
- **Tokens only.** A new colour or spacing is a new key in both
  `Resources/Themes/pergamenum-light.json` and `-dark.json`, declared in
  `Sources/DesignSystem/TokenKeys.swift`, read through `Theme`. No literal in a view.
- **One write door.** Every creation or edit goes through `VaultSession.write` with
  `expecting:`/`expectingAbsent:` (ADR-0043 §D8, ADR-0057 §D3). A new capability the
  connectors should have goes into `Sources/Connector/` (ADR-0007).
- **State read before an `await` is re-read after it** (ADR-0043 §D7).
- **A `List` row's nested `.contextMenu` never opens** (ADR-0069); a tree in
  `List(selection:)` uses flat rows, never `DisclosureGroup` (ADR-0024).
- **Tests.** The merge gate is `PergamenumTests` plus the hosted-view tests; a feature
  carries at most two or three GUI tests, each justified in its ADR; every UI-test file
  passes the four isolation flags (`-disableCalendar`, `-disableUpdater`,
  `-mailStoreRoot`, `-disableContenitore`).
- **Protected interfaces** (`.claude/protected-interfaces`) are not touched by any task
  below; where a task sits next to one (`ImportNaming.recordingNoteTitle`'s truncator,
  `VaultBoundary.url(for:)`), it is named.

---

## 1. Milestones at a glance

| # | Milestone | Report items | ADRs | SPEC | Size | Order |
|---|---|---|---|---|---|---|
| N1 | Seams | I-1, I-3, I-8, L-6, L-7, R-9 (spacing), PG-219 | 0079 | §4.2, §8.1, §10 | 2 sessions | first |
| N2 | The page, part one: markers, budget, grammar | R-1, R-2, R-8 (+ PG-347) | 0080, 0081 | §5 | 3 sessions | second |
| N3 | Links | L-1, L-2, L-3, L-4, L-5, L-8, L-9, I-7 (+ PG-233) | 0082, 0083 | §5, §12 | 3 sessions | third |
| N4 | Birth of a note | I-2, I-4, I-5, I-6, I-9 | 0084, 0085 | §7.4, §8.1, §12 | 3 sessions | fourth |
| N5 | The page, part two: constructs | R-3, R-4, R-5, R-6, R-7, R-10 | 0086 | §5 | 3–4 sessions | fifth |

Why this order and not the report's A → B → C → D: N1 is prerequisite-free and fixes two
silent defects; N2 changes the styler every later editor task builds on, so it goes before
N5; N3 is independent of N2 (different files, one shared touch in
`NoteTextView+Coordinator.swift`) and carries the highest daily value after N1, so it
precedes N4 and N5; N4 depends on N1's `status-inbox` rule; N5 is the largest and the most
mockup-bound, and gains from N2's single grammar.

Parallelism: N2 and N3 can run in two worktrees at once if the Coordinator touch is
coordinated (N2 edits `textDidChange`, N3 edits `updateTrackingAreas` and the delegate's
hover handling); N4 and N5 can also overlap. Nothing else should.

---

## 2. Milestones in detail

### N1 — Seams

*Two silent defects, four one-liners, one token, one P2 already filed.*

**ADR-0079 — A note born without a topic is a capture, and capture proposes a title.**
Records I-1 and I-3 as one decision about the capture shape; amends ADR-0008 §D6 (which
promised `status-inbox` and never got it) and SPEC §4.2 on the capture surface only.

| # | Task | Files | Tests | Notes |
|---|---|---|---|---|
| 1 | `status-inbox` on every note created with no `topic-*`, every path | `Sources/Core/Conventions/Tag.swift` (`TagRules.initialTags`: the condition becomes `category == .capture \|\| topics.isEmpty`, daily excepted), `Sources/Vault/VaultSession+Notes.swift` (doc comment), `Sources/Connector/VaultWrites.swift` (doc) | `Tests/CaptureTests.swift`, `Tests/VaultSessionTests.swift`, `Tests/NoteTemplateTests.swift` (bytes pinned), one `TagRules` test per category | The event note, scheda and inbox task note are unchanged. `perg note create --topic` still yields no `status-inbox`. The MCP `dryRun` diff shows the new tag, which is the connector's acceptance |
| 2 | Capture «Nota nuova» proposes a title instead of refusing | `Sources/Connector/VaultCapture.swift` (`captureAsNote`: on `NoteName.validate` failure, derive via `NoteName.sanitized` + `ImportNaming.truncatedAtWordBoundary(_:toFit: 60)`; prose-shaped first line → whole text to body, title `YYYYMMDD HHmm Cattura`), `Sources/Features/Capture/CapturePanelView.swift` (live «Titolo: …» caption under the field), `Sources/Features/Capture/CaptureController.swift` | `Tests/CaptureTests.swift`, `Tests/CRLFCaptureTests.swift`, `Tests/CapturePanelTests.swift` | `ImportNaming.truncatedAtWordBoundary` sits behind the protected `recordingNoteTitle`; reuse it, do not fork it. Refuse only an empty capture |
| 3 | `[[` completion closes `]]`; alias rows read «Titolo · alias: X» | `Sources/Features/Editor/CompletingTextView.swift` (`apply`), `Sources/Features/Workspace/CardWikilinkCompletion.swift` (candidates from `index.search`, which already sees aliases; a candidate carries `matchedAlias`), `Sources/Features/Editor/EditorColumnView.swift:93` (feed records, not titles), `Sources/Features/Today/TodayView.swift:64` | `Tests/EditorCompletionTests.swift`, `Tests/CardWikilinkCompletionTests.swift`, `Tests/EditorCompletionCrashTests.swift` (the `#` stack-overflow guard stays green) | The inserted text is always the title (W-01). If the caret already has `]]` ahead, do not double it |
| 4 | Cmd+Shift+D switches to the Note pane; event note and Workspace «Documento» focus or announce the tab | `Sources/App/CommandActions.swift:173` (`.dailyNote` gets `navigation.pane = .notes` like `.newNote`), `Sources/App/VaultController+TimeBlocks.swift:91-105`, `Sources/Features/Workspace/WorkspaceView+Creation.swift:71-91` (open the note? no: keep the card, drop the background tab, offer «Apri» in the sheet's confirmation) | hosted `CommandActions` tests (the `Tests/HostedViewPrototypeTests.swift` family) | From the Oggi pane the daily note is already visible; the pane switch must not fire when the current pane is `.today` |
| 5 | Cmd+N lands in the sidebar's selected folder | `Sources/App/VaultController+Notes.swift` (`beginNewNote(in:)` default from the selected tree row), `Sources/Features/Editor/NoteListPane.swift` | `Tests/NoteListEditingTests.swift` | «Nuova nota qui» stays explicit |
| 6 | Clickable `#tag` and dates | `Sources/Features/Editor/MarkdownAttributedText.swift` (`clickTarget(for:)` gains `.tag`, `.date`), `Sources/App/CommandActions+LinkNavigation.swift` (`open(tag:)` → `navigation.pane = .tags` + filter; `open(day:)` → `.today` at that date), `Sources/Features/Tags/TagBrowserView.swift` (a selection entry point) | `Tests/OpenLinkUnresolvedTests.swift` sibling, `Tests/TagBrowserTests.swift` | Cmd+click, same gate as links |
| 7 | `spacing.paragraph` token; H5/H6 told apart by weight | both theme JSONs, `Sources/DesignSystem/TokenKeys.swift`, `DesignTokenDocument.swift`, `Sources/DesignSystem/ProseTypography.swift` (`paragraphStyle` applies it to prose paragraphs only; lists, quotes, code and tables excluded), `MarkdownAttributedText.swift:128-148` (H6 regular weight, `textSecondary`) | `Tests/ProseTypographyTests.swift`, `Tests/ListIndentFontInvariantTests.swift` | A value of `0.5em` reads well in Avenir Next 16; mock up both |
| 8 | PG-219: pointer feedback | as filed (#445) | as filed | `/build PG-219`, the hover preview in N3 should not land before the hand cursor does |
| 9 | Housekeeping | SPEC §8.1/§10 shortcuts (Cmd+Shift+D, Cmd+Shift+B); the three «from the template» doc comments (`DayController.swift:158`, `VaultCapture.swift:105`, `VaultSession+TimeBlocks.swift:96`); `VaultSettings.inboxFolder` (default `00 Inbox`) replacing the constant in `VaultCapture.swift:31` and `VaultSession+Tasks.swift:34`, exposed in Impostazioni › Convenzioni; errors from Quick Open create and the Workspace sheet shown inline | a `VaultSettings` decode test (the key absent → default), `Tests/PraticheSettingsTests.swift` is the shape, `Tests/CaptureTests.swift` | No ADR for these |

**Acceptance.** From Safari, Ctrl+Opt+Space, type `Idea: usare i token anche per i font?` and
press Return: a note `Idea usare i token anche per i font.md` exists in `00 Inbox` with
`type-note` and `status-inbox`, and `perg lint` reports nothing on it. In the editor,
`[[Tras` + Return yields `[[Trasmissibilità e rapporto di frequenza]]` with the caret
after `]]`. From Attività, Cmd+Shift+D shows today's note. Cmd+click on `#client-acme`
opens the Tags pane narrowed to it. The pointer is an I-beam over text and a hand over a
link.

---

### N2 — The page, part one: markers, budget, grammar

*The line never shifts under the caret; the cost of a keystroke is a number; one parser.*

**ADR-0080 — Block markers reveal in the gutter.** Amends ADR-0028 §D4's accepted
horizontal shift and ADR-0018 §D2's reveal rule for list, heading and quote paragraphs.
**ADR-0081 — The styler classifies through the shared parsers.** Extends ADR-0077 §D1 to
the editor; closes PG-347; records the keystroke budget and the two scoping changes.

| # | Task | Files | Tests | Notes |
|---|---|---|---|---|
| 1 | Mockup: revealed list item, heading and quote with the marker hanging left of a fixed content column; dim permanent `H2` badge option | `Sources/Features/DesignGallery/EditorMockup.swift` | — | Human gate before task 2 |
| 2 | Gutter reveal for lists | `Sources/Features/Editor/ListMarkerRendering.swift` (`paragraphStyle(level:font:basedOn:revealed:)`: concealed and revealed states share `headIndent`; revealed sets `firstLineHeadIndent = headIndent − width("- ")` measured in `font`), `EditorDecorationDelegate+ListRendering.swift` (revealed paragraph keeps the style instead of dropping it), `NoteTextView+Reveal.swift` | `Tests/MarkupHidingListTests.swift`, `Tests/ListIndentFontInvariantTests.swift` (new invariant: content x-origin equal in both states), `Tests/MarkupRevealTests.swift` | Ordered markers: the digits are already in the file, only the indent changes; `1. ` hangs the same way |
| 3 | Gutter reveal for headings and quotes | `EditorDecorationDelegate.swift:471-591` (heading branch sets a paragraph style with the same two indents), `EditorDecorationDelegate+QuoteRendering.swift` | `Tests/EditorDecorationSubstitutionTests.swift`, `Tests/QuoteRenderingTests.swift` | Readable-width inset already leaves a gutter; verify at the narrow width where `textContainerInset` is 24 |
| 4 | Keystroke budget, measured | new `Tests/EditorRestyleBudgetTests.swift` (synthetic notes of 50 KB, 200 KB, 1 MB, with and without fences and view blocks; asserts a generous ceiling and prints the numbers), new `scripts/editor-restyle-bench.sh` (runs that test alone and prints a table) | itself | The numbers go into ADR-0081 §Context; the ceiling is the decision |
| 5 | Scope `renumberLists` to the edited ordered run | `Sources/Features/Editor/NoteTextView+ListEditing.swift:61-69`, `Sources/Core/Editor/ListContinuation.swift` | `Tests/ListContinuationTests.swift`, `Tests/ListNestingForwardPassTests.swift` | One undo step stays one undo step |
| 6 | `growToFitTheText` ensures layout to the caret's fragment plus the viewport, not the document | `NoteTextView+Coordinator.swift:541-552` | hosted test with a long note: caret stays visible, no full-document `ensureLayout` | Folding and the outline already handle their own jumps through `RequestLedger` |
| 7 | Styler over the shared parsers | `Sources/Features/Editor/MarkdownStyler.swift` (`spans(in:)` built from `MarkdownBlockParser.blocks(in:)` + `MarkdownInlineParser.spans(in:)`; the `Span` enum and every consumer unchanged), `Sources/Core/Markdown/MarkdownInline.swift`/`MarkdownBlocks.swift` (gain whatever the editor needs they lack: list level by content column, task state, embed run, view-block run, message anchor) | `Tests/MarkdownStylerTests.swift`, `Tests/MarkdownStylerBlockTests.swift`, `Tests/MarkdownStylerFixture.swift` extended into a golden corpus (the `NoteExportGoldenCorpus` shape, each case classed A/B/C/unchanged) captured **before** the change | PG-347 closes here. `_` emphasis stays unconcealed (ADR-0030's reason holds); the parser's flanking rule decides what is emphasis |
| 8 | Surface parity | `Sources/Features/Today/TodayView.swift`, `Sources/Features/Diary/DiaryView.swift` (pass `queries` so `pergamenum-view` fences render), `Sources/Features/Workspace/CardTextView.swift:359-375` (`hiddenKind` gains quote and rule; the line-height multiple composed in) | `Tests/TransclusionLayoutTests.swift` sibling for cards | Tables and view blocks stay out of cards (ADR-0029) |

**Acceptance.** Arrow-down through a ten-item nested list: no glyph moves horizontally.
`Tests/EditorRestyleBudgetTests` prints the three sizes and passes. `file_name_here` is
plain in the editor as it is in the HTML export. A `pergamenum-view` fence in today's note
renders in the Oggi pane.

---

### N3 — Links

*A link you can peek at, follow from the keyboard, create from, and read the reasons for.*

**ADR-0082 — Links answer to the pointer and the keyboard.** Hover preview, follow command,
open-in-tab/column variants, disambiguation, create-from-dangling. Extends ADR-0012 §D4 and
ADR-0015. **ADR-0083 — Backlinks with context, unresolved per note, mentions that link.**
Amends the ADR-0012 §D9 mockup decision that refused «Collega»; decides PG-233.

| # | Task | Files | Tests | Notes |
|---|---|---|---|---|
| 1 | Mockups: preview popover, backlink rows with context and the structural badge, per-note unresolved rows, «Dove compare» | `Sources/Features/DesignGallery/UnlinkedMentionsMockup.swift` (extended), new `LinkPreviewMockup.swift` | — | Human gate |
| 2 | Hover preview | new `Sources/Features/Editor/LinkPreviewPopover.swift` (`NSPopover`, transient, 400 ms delay, content = `TranscludedNoteView` over the target's first ~20 lines or the heading section; `[[x.canvas]]` shows the board name only), `NoteTextView+Coordinator.swift` (`updateTrackingAreas` already exists; add `mouseMoved` dispatch on link ranges), `EditorDecorationDelegate+LinkRendering.swift` (tooltip stays as fallback) | hosted tests: the popover shows once per hover, closes on Esc and on leave, never steals first responder (the PG-258 orphan-window lesson: no `NeverKeyPanel`) | No preview for external URLs (nothing local to show) |
| 3 | «Segui il collegamento» and variants | `Sources/Core/Shortcuts/ShortcutCommand.swift` (`followLink`, default Cmd+Opt+Return; `followLinkInNewTab`, `followLinkInOtherColumn`), `Sources/App/ShortcutStore.swift`, `Sources/App/MenuCommands.swift` (Vista), `Sources/App/CommandActions+LinkNavigation.swift` (`open(link:how:)` with `.replace`/`.newTab`/`.otherColumn`; Cmd+Opt+click and Shift+click map to the variants in `NoteTextView+Coordinator.swift:240-243`), `Sources/App/VaultController+Tabs.swift` (`openNoteInNewTab`, the other column's `focused { }` door) | `Tests/OpenLinkUnresolvedTests.swift` family, hosted test for each variant | The link under the caret is the innermost `.wikilink`/`.link` span containing it |
| 4 | Disambiguation | `CommandActions+LinkNavigation.swift:24` (`resolve(title:)` count > 1 → `NSMenu` with folder paths at the click point, or a sheet from the keyboard), `Sources/Features/Editor/RelatedLinkSheet.swift`, `QuickSwitcher.swift` (show the path on duplicate titles) | `Tests/OpenLinkUnresolvedTests.swift` | Never `.first` silently |
| 5 | Create from a dangling name (I-7) | `CommandActions+LinkNavigation.swift:32-36` (unresolved → «Crea «X»» alert with the composer prefilled, folder = the source note's), `Sources/Features/Editor/CompletingTextView.swift` + `CompletionPanelView.swift` (a trailing «Crea «X»» row when `NoteName.validate` passes and no title matches) | `Tests/EditorCompletionTests.swift`, `Tests/CompletionPanelTests.swift` | W-07 allows the inline placeholder; this converts it |
| 6 | Backlinks with context | new `Sources/Features/Editor/BacklinksSection.swift` replacing `VaultBrowser.swift:286-302` (rows: title, the line holding the link read on demand through `VaultSession.read` + `Wikilink` scan, memoised by `indexGeneration` like `backlinksMemo`; badge «strutturale» when the source's `frontmatter.related` names this note; count in the header; row menu: Apri, Apri nell'altra colonna, Rendi strutturale); `Sources/Index/IndexSnapshot.swift:119` unchanged (paths only, principle 3) | new `Tests/BacklinkContextTests.swift` over the pure line finder; hosted test for the section | The row menu is the section's own, not nested in a `List` row (ADR-0069) |
| 7 | Unresolved links per note | `VaultBrowser.swift:304-320` → new `UnresolvedLinksSection.swift` listing the open note's own unresolved targets (derivation shared with `ViewField.unresolved`, `Sources/Core/Query/ViewField.swift:135,180`, lifted into `IndexSnapshot.unresolvedTargets(of:)`), each with «Crea nota» (task 5) and «Vai al link» (`NoteJump`); the vault-wide list becomes a sample view in `Sources/Vault/VaultSession+SampleViews.swift` | `Tests/UnresolvedLinksLimitTests.swift` adapted, new `IndexSnapshot` test | `perg note unresolved` and the MCP tool unchanged |
| 8 | Unlinked mentions → «Collega» | `Sources/Features/Editor/UnlinkedMentionsSection.swift` (per-row «Collega»), `Sources/Vault/VaultSession+Search.swift` (`linkMention(in:at:title:alias:)`: one guarded write with `expecting:` the hash the scan read; `[[Titolo]]` or `[[Titolo\|testo]]` when the mention was an alias), confirmation shows the `UnifiedDiff` line (`Sources/DesignSystem/DiffView.swift`) | `Tests/UnlinkedMentionTests` (pure rewrite), hosted test for the confirmation | Connector parity: `perg note link-mention` is optional, name it in the ADR either way |
| 9 | Lighter structural links | `RelatedLinkSheet.swift` (reverse reason prefilled as an editable mirror; a `preselected` target for «Rendi strutturale»), `Sources/Vault/VaultSession+Notes.swift` (`removeStructuralLink(from:to:)` over `RelatedLink.remove`, two guarded writes, half-done reported like `addStructuralLink`), `BacklinksSection.swift` («Scollega» on structural rows), PG-233: `addStructuralLink` saves a dirty source buffer first, the `restoreVersion` rule | `Tests/RelatedLinkTests.swift`, `Tests/RelatedSectionTests.swift`, `Tests/RelatedLinkSectionPreservationTests.swift` | PG-378 (parser over-count) is burned down first, it corrupts the «Scollega» path otherwise |
| 10 | «Dove compare» | new `Sources/Features/Editor/WhereNoteAppearsSection.swift` (boards: `CanvasStore.allBoards()` + node file paths, read on demand; pratiche: `PraticaLinkResolver` reversed over `pergamenum-dossier-links-notes` and messages' `pergamenum-mail-note`), `VaultBrowser.swift:201-217` (section order) | hosted test with a fixture vault | Read-only, no cache change, `IndexCache.schemaVersion` stays |
| 11 | GUI tests (max three) | `UITests/WikilinkNavigationUITests.swift` (follow from keyboard; preview appears), one for «Collega» on a mention | | The four isolation flags |

**Acceptance.** Hover a wikilink: the target's opening lines appear and vanish on leave.
Caret inside `[[Nota]]`, Cmd+Opt+Return opens it; Cmd+[ returns. Cmd+click `[[Nuova idea]]`
offers to create it in the same folder. The inspector shows, for each backlink, the line
that links, and marks the structural ones; «Scollega» removes one from both notes. A
mention becomes a link from the inspector after a diff confirmation. The inspector of
«Trasmissibilità» lists the boards and the pratiche that reference it.

---

### N4 — Birth of a note

*Captures get filed, templates reach every birth, one composer, extract, undo.*

**ADR-0084 — An Inbox pane for notes and one composer.** Amends SPEC §7.4 (the task Inbox
is untouched; a note Inbox is added beside it) and §12 (settings); records the composer as
the one naming surface (extends ADR-0003 §D1). **ADR-0085 — Templates where notes are
born.** Extends ADR-0011 §D5–§D7: daily template setting, `{{cursor}}`, `{{time}}`,
template choice in capture, Quick Open and Workspace, connector `--template`.

| # | Task | Files | Tests | Notes |
|---|---|---|---|---|
| 1 | Mockups: Inbox pane, generalised «Classifica» sheet, composer as a sheet | `Sources/Features/DesignGallery/` (new `InboxMockup.swift`) | — | Human gate |
| 2 | Inbox pane | new `Sources/Features/Inbox/InboxPane.swift`, `InboxListModel.swift` (every note with `status-inbox`, from the index's tag table; sort by date; folder filter), `Sources/App/SidebarItem.swift`, `RootView.swift` (`requiringVault` door), `Sources/Core/Shortcuts/ShortcutCommand.swift` (`paneInbox`, Ctrl+Cmd+I: free today, the inspector is Cmd+Opt+I), `MenuCommands.swift` (Vista) | `Tests/InboxListModelTests.swift` (the `ContenitoreListModelTests` shape) | Flat rows, `List(selection:)`, keyboard focus per ADR-0070 |
| 3 | «Classifica» for any note | `Sources/Features/Contenitore/ClassificaSheet.swift` generalised and moved to `Sources/Features/Editor/NoteClassificaSheet.swift` (topics with vocabulary completion and blocking, optional folder, preview with `status-inbox` struck through; one write with `expecting:`), the Contenitore keeps calling it; `Sources/Features/Editor/NoteRowMenu.swift` («Classifica…»), `EditorCommand.swift` (slash), `Sources/App/CommandActions.swift` | `Tests/ContenitoreListModelTests.swift` stays green; new `NoteClassificaTests` over the pure frontmatter rewrite | The topic rule here is the blocking vocabulary SPEC §4.4 promised: closed families refused, open families shaped |
| 4 | Templates everywhere | `Sources/Core/Conventions/NoteTemplate.swift` (`{{time}}`, `{{cursor}}` → returns `(text, caretOffset?)`), `Sources/Vault/VaultSettings.swift` (`dailyTemplate: String?`, a path under `Templates/`), `Sources/Vault/VaultSession+Notes.swift` (`dailyNote(for:)` passes the body), `Sources/Features/Capture/CapturePanelView.swift` (template menu under «Nota nuova»), `Sources/Connector/VaultCapture.swift` + `VaultWrites.swift` (`template:`), `Sources/CLI/Commands/WriteCommands.swift` and `Sources/MCPServer/ToolCatalogue+Writing.swift` (`--template`), `Sources/Features/Workspace/WorkspaceView+Creation.swift`, `Sources/Features/Settings/` (Convenzioni tab), `Sources/Features/Editor/TemplateSheet.swift` (caret placed at `{{cursor}}` after insertion) | `Tests/NoteTemplateTests.swift`, `Tests/CaptureTests.swift`, `scripts/mcp-smoke.py` run after the MCP change | Six shipped templates in `Templates/` are *content*, not code: a sample vault under `Tests/Fixtures` only |
| 5 | One composer, three hosts | `Sources/Features/Editor/NewNoteComposer.swift` (topic field becomes a vocabulary-completing field reused from task 3; client-/project- chips from used values; a `host` mode: in-pane or sheet), `WorkspaceView+Creation.swift` (the «Documento» sheet hosts the composer with folder = board folder), `Sources/Features/Editor/QuickSwitcher.swift:190-196` (the create row opens the composer prefilled instead of creating at the root) | `Tests/NoteListEditingTests.swift`, hosted tests for the sheet host | `NewCanvasItemSheet` keeps serving sticky/text/link cards |
| 6 | «Estrai in una nota» | `EditorCommand.swift` (slash + Modifica menu), `Sources/App/VaultController+Notes.swift` (`extractSelection`: composer prefilled with the first line, on confirm `createNote(expectingAbsent:)` then the source `write(expecting:)` replacing the selection with `[[Titolo]]`; a refusal on the second write leaves the new note and names it, the `addStructuralLink` rule) | `Tests/VaultSessionTests.swift` (two-write ordering), hosted test | Frontmatter of the source untouched |
| 7 | Creation undo toast | `Sources/App/VaultController+Notes.swift` (`lastCreation` with a 10 s window), a notice strip in the Note pane (the `ContenitoreNoticeStrip.swift` shape) with «Annulla» → `trashFile(at:forgettingNoteID: true)` | hosted test: toast appears, «Annulla» trashes, window expires | Cheaper than arming the journal in the app (ADR-0007 §D6 stays) |
| 8 | GUI tests (max two) | one for the Inbox pane filing a capture, one for the daily template | | |

**Acceptance.** Ctrl+Opt+Space, a thought, Return; Ctrl+Cmd+I shows it in the Inbox pane;
«Classifica» with `topic-vibration-isolation` and folder `03 Risorse` moves it and strips
`status-inbox`; the Inbox is empty. Today's note opens with the template resolved and the
caret at `{{cursor}}`. Select two paragraphs, `/estrai`: a new note holds them and the
source holds `[[Titolo]]`.

---

### N5 — The page, part two: constructs

*Inline code, fences, callouts, highlights, quotes, embeds, tables.*

**ADR-0086 — The editor draws the remaining constructs.** Extends ADR-0029 §D1 (the
"everything the reading view drew" scope) to constructs no surface drew: callouts and
highlights are new to `Sources/Core/Markdown` first (N2's rule), then to every surface.
Amends SPEC §5's construct list.

| # | Task | Files | Tests | Notes |
|---|---|---|---|---|
| 1 | Mockups: code pill, fence header, callout card (five types, folded and open), quote block, inline embed chip, transclusion caption, table alignment menu | `Sources/Features/DesignGallery/CodeBlockMockup.swift` (extended), new `CalloutMockup.swift` | — | Human gate; token names fixed here |
| 2 | Tokens | both theme JSONs, `TokenKeys.swift`: `color.code.inlineBackground`, `color.highlight`, `color.callout.{nota,suggerimento,importante,avviso,attenzione}`, `color.quote.bar` | `Tests/ThemeCustomizationTests.swift` (both theme files carry every new key) | Six callout names mapped from Obsidian's `note/tip/important/warning/caution`, Italian in the file, English aliases accepted |
| 3 | Inline code and highlights in the parser and the styler | `Sources/Core/Markdown/MarkdownInline.swift` (`==` span; code span already exists), `MarkdownStyler.swift` (conceal backticks and `==` on the collapse path), `EditorDecorationDelegate.swift` (background attribute on the content range), `Sources/Core/Markdown/MarkdownHTML.swift` (`<mark>`, `<code>` unchanged) | `Tests/MarkdownStylerTests.swift`, `Tests/EditorDecorationSubstitutionTests.swift`, `Tests/NoteExportGoldenCorpus` (new cases) | A `==` inside a code span is not a highlight |
| 4 | Fence chrome | `Sources/Core/Markdown/CodeFence.swift` (info string parsed), new `Sources/Features/Editor/CodeFenceHeaderFragment.swift` (the `HorizontalRuleFragment` shape: language badge, line count), `EditorDecorationDelegate.swift` (opening and closing lines drawn by the fragment, revealed on caret), `Sources/Features/Editor/EmbedContextMenu.swift` sibling for «Copia il blocco» | `Tests/CodeSyntaxTests.swift`, hosted fragment test | Lines never leave the layout: the fence body must stay editable |
| 5 | Callouts | `Sources/Core/Markdown/MarkdownBlocks.swift` (`callout(type:title:folded:)` block over a quote), `MarkdownStyler.swift`, new `EditorDecorationDelegate+CalloutRendering.swift` (title line → `CalloutTitleFragment`, body through the quote path with the type colour), `Sources/Features/Editor/HiddenBlockLines.swift` + `NoteTextView+Folding.swift` (`-` folds the body through the shared hidden-line set, ADR-0078), `EditorCommand.swift` (the slash entry the file refuses today), `MarkdownHTML.swift` (`<aside class="callout">`), `CardTextView.swift` (title colour only) | new `Tests/CalloutTests.swift`, `Tests/MarkupHidingListTests.swift` sibling | Obsidian reads the file unchanged |
| 6 | Blockquotes | `EditorDecorationDelegate+QuoteRendering.swift` (indent per level on the paragraph style, `textSecondary`, bar as a full-height fragment in `color.quote.bar`), `Sources/Features/Editor/MarkdownBlocksView.swift` (same nesting rule) | `Tests/QuoteRenderingTests.swift`, `Tests/QuoteSplitterTests.swift` | |
| 7 | Embeds: placeholder, inline chip, transclusion caption | `Sources/Features/Editor/EmbedAttachment.swift` + `NoteTextView+Embeds.swift:255-263` (reserve `|W`/`|WxH` or a default box before `ThumbnailStore` answers), `EmbedRun.swift` + `NoteTextView+Embeds.swift:265-271` (an inline or non-renderable embed becomes a chip attachment: icon, name, Quick Look on click), `NoteTextView+Transclusion.swift` + `TranscludedLineFragment.swift` (source line drawn as a caption «da «Nota» › Sezione», revealed on caret) | `Tests/EmbedDrawingTests.swift`, `Tests/EmbedResolutionTests.swift`, `Tests/TranscludedLineTests.swift`, `Tests/TranscludedLineFragmentWidthTests.swift` | ADR-0019's resize handle and `|W` writing untouched |
| 8 | Tables: alignment and sort | `Sources/Features/Editor/TableEdit.swift` (delimiter-row alignment rewrite; sort by column as one rewrite), `TableGridView.swift` (column header context menu; alignment applied to cells), `Sources/Core/Markdown/GFMTable.swift` | `Tests/TableEditTests`, `Tests/GFMTableTests` | One undo step per rewrite; no formulas (Roadmap v2 §1.1) |
| 9 | `#tag` and date chips | `MarkdownAttributedText.swift` (namespace in `textSecondary`, value in accent; dates as chips) | `Tests/MarkdownStylerTests.swift` | Builds on N1 task 6 |

**Acceptance.** A note with inline code, a `swift` fence, a `> [!avviso]-` callout, a
`==highlight==`, a nested quote, an inline `![[scheda.pdf]]`, a transclusion and a
right-aligned column: every one of them reads as such without the caret in it; with the
caret in it, the syntax reappears; Obsidian opens the file unchanged; the HTML export
agrees with the editor on every construct.

---

## 3. Dependencies and risks

| Dependency | Why |
|---|---|
| N1 task 1 before N4 task 2 | The Inbox pane lists `status-inbox` notes; without the rule it lists nothing but schede and event notes |
| N1 task 8 (PG-219) before N3 task 2 | A hover preview over a link with no hand cursor is a preview nobody expects |
| PG-378 before N3 task 9 | «Scollega» rewrites the section the parser over-counts |
| N2 task 7 before N5 tasks 3 and 5 | New constructs go into the shared parser once, not into two grammars |
| N2 task 1 and N5 task 1 before their code | SPEC §11.1 |

| Risk | Mitigation |
|---|---|
| Length-preserving substitution cannot express a callout title or a fence header | Fragments (N5 tasks 4–5) draw the line; the characters stay. A test pins the paragraph length in every branch (`EditorDecorationSubstitutionTests`) |
| `NSPopover` from a hosted `NSTextView` steals first responder or survives as an orphan | PG-258's lesson: transient behaviour, closed on `resignKey`, pinned by a hosted test that asserts `window.firstResponder` unchanged |
| The styler rewrite (N2 task 7) changes what is concealed on real notes | Golden corpus captured before the change, each difference classed A (fix), B (deliberate), C (regression); C blocks the merge |
| Keystroke budget regresses silently later | `EditorRestyleBudgetTests` in `PergamenumTests`, run by the Stop hook every turn |
| The Inbox pane and the task Inbox view get confused | Naming: «Inbox» (notes) in LAVORO beside «Attività ▸ Inbox»; the ADR records the two and SPEC §7.4 says which is which |
| Composer unification breaks `ComposerUITests` | The in-pane host keeps every `accessibilityIdentifier`; the sheet host adds a suffix |
| Two worktrees edit `NoteTextView+Coordinator.swift` | N2 owns `textDidChange`/`growToFitTheText`; N3 owns `updateTrackingAreas`/hover; the second to merge rebases through `sync_operation` |

---

## 4. SPEC amendments, in the order they are needed

| Milestone | Section | Amendment |
|---|---|---|
| N1 | §4.2 | On the capture surface a non-conformant first line yields a proposed conformant title; refusal only on empty |
| N1 | §4.3 | Any note born without a `topic-*` is a capture (`status-inbox`), on every path |
| N1 | §8.1, §10 | Daily note Cmd+Shift+D; Nuova board Cmd+Shift+B; «Vista ▸ Oggi (Cmd+T)» removed; `00 Inbox` configurable |
| N2 | §5 | Block markers reveal in the gutter; the keystroke budget stated as a number |
| N3 | §5, §12 | Hover preview, «Segui il collegamento» and variants, create from a dangling link, backlinks with context, per-note unresolved links, mention linking, «Scollega», «Dove compare» |
| N4 | §7.4, §12, §8.1 | Inbox pane for notes beside the task Inbox; «Classifica»; daily template delivered; templates in capture and Workspace; `{{cursor}}`, `{{time}}` |
| N5 | §5 | Inline code pill, fence chrome, callouts, highlights, quote styling, inline embed chip, transclusion caption, table alignment and sort |

---

## 5. Ledger entries to register

Run `/project-tasks roadmap` with this document as the source. Proposed priorities:

- **P2**: N1 task 1 (I-1, silent non-conformance), N1 task 2 (I-3), N3 tasks 2–3 (L-1), N3 task 6 (L-2)
- **P3**: every other task above, one entry per task, each citing `docs/20261003_Pergamenum_NoteWorkflowRoadmap.md` and its milestone
- Already open and absorbed, not duplicated: PG-219 (N1), PG-347 (N2), PG-233 and PG-378 (N3), PG-121 (superseded by N4 task 4; close with a note), PG-258's format-bar item (adjacent to N3 task 2, stays its own)

---

## 6. Sizing

At the pace of the last six weeks (two to three sessions per roadmap-v2 milestone, the
editor ones longer), N1 is two sessions, N2 three, N3 three, N4 three, N5 three to four:
fourteen to fifteen sessions in all, about five weeks of the current cadence, with N2/N3
and N4/N5 overlapping in separate worktrees where the dependency table allows.
