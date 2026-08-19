<!-- project-tasks: prefix=PG lastId=29 -->
# PROJECT TASKS

Updated: 2026-08-19 · Open: 14 (P1: 0) · In progress: 0

## Open Issues

- [ ] `PG-004` **P2** `.pergamenum/cache.db` syncs in iCloud and will produce conflict copies; moving it out of the vault needs an ADR — `Sources/Index/IndexCache.swift` <!-- src:manual opened:2026-08-16 -->
  - Harmless by principle 3, the cache is rebuildable, but the conflict files accumulate in the vault the user reads.
- [ ] `PG-005` **P2** `NoteFileOperations` does not go through `VaultSession.write`, so the journal covers only part of a link rewrite and neither connector can offer `note rename|move|trash` — `Sources/Vault/NoteFileOperations.swift` <!-- src:manual opened:2026-08-16 -->
  - `PG-019` (dragging a section in the outline to move it) is the same class of work — a real text rewrite outside `VaultSession.write` — and belongs here rather than under the editor's own milestone.
- [ ] `PG-006` **P2** Build 89: block deletion and images in notes never confirmed by hand — `docs/20260811_Pergamenum_SpecApp.md` <!-- src:manual opened:2026-08-16 -->
  - Pasting an image from the clipboard has no automated test on purpose: driving it would clobber the real system pasteboard.

## In Progress

_Nothing in progress._

## Backlog / To Add

- [ ] `PG-011` **P3** M10 Navigazione e organizzazione: tabs, split view, tag browser, starred, the missing search operators <!-- src:session opened:2026-08-16 -->
- [ ] `PG-012` **P2** M11 Viste: saved queries over the index, rendered as table, board, gallery or calendar <!-- src:session opened:2026-08-16 -->
  - Bumps `IndexCache.schemaVersion` to **3** for `embedTargets`, once, and that is the only schema change the milestone may make (ADR-0009 §D2). It was 2 until ADR-0010 §D7 spent that number in M8.
  - Unblocked: ADR-0009 accepted 2026-08-17.
- [ ] `PG-013` **P3** M12 La settimana: week and month views, event notes, task grouping and sorting <!-- src:session opened:2026-08-16 -->
- [ ] `PG-014` **P3** M13 Vault completo: `note rename|move|trash` under the journal, prompts in the vault, static export, import, AppIntents <!-- src:session opened:2026-08-16 -->
- [ ] `PG-019` **P2** The index's second half: drag a section to move it, which is a real text rewrite through `VaultSession.write` with the journal behind it — `Sources/Features/Editor/OutlinePane.swift` <!-- src:session opened:2026-08-17 -->
  - Deferred on purpose when the index shipped: listing and jumping touch nothing, moving a section writes. Belongs with `PG-005`, not with the editor's own milestone.
- [ ] `PG-029` **P3** Nothing on screen says a note draft is parked — `Sources/Features/Editor/NewNoteComposer.swift` <!-- src:session opened:2026-08-19 -->
  - Stepping out of the composer keeps the title, the folder, the topic and the template for the next `Cmd+N` (PG-028), and `Cmd+N` is the only way back to them. Left out of that slice on purpose: a «riprendi» row in the list or a badge on the toolbar button is a design decision, and whether one is needed at all is a question for use rather than for review.
- [ ] `PG-026` **P3** `CLAUDE.md` is missing three things measured on 2026-08-18 — `CLAUDE.md` <!-- src:session opened:2026-08-18 -->
  - A full UI run started with stale instances alive gives **18 failures that are not real**, every one at exactly 60.2 s: the launch timeout. The note at "A UI-test instance outlives its run" says the instances survive; it does not say what they then cost. Kill every instance before a full run, and read the timings before believing a failure.
  - `firstRect(forCharacterRange:)` returns a **zero rectangle** for a range TextKit 2 has not laid out - the end of every long note - and a zero rectangle sent to a popup's placement clamps it to the screen's bottom-left corner.
  - The runner's temporary directory is inside its container and is unreadable from outside, sandbox off or not. `XCTAttachment` plus `-resultBundlePath`, then `xcrun xcresulttool export attachments`, is how a screenshot actually gets looked at.

- [ ] `PG-015` **P3** SPEC amendments §5, §7.4, §8 and §12, plus new §16 Cattura and §17 Viste — `docs/20260811_Pergamenum_SpecApp.md` <!-- src:session opened:2026-08-16 -->
  - Each is applied before the milestone that depends on it, never after.

## Blocked / Decisions Needed

- [ ] `PG-002` **P2** SPEC §7.3 rollover as an off-by-default option: the reopening needs Stefano's approval, ADR-0012 would record it <!-- src:session opened:2026-08-16 -->
- [ ] `PG-003` **P2** M9's version snapshots add a second write-time store beside `WriteJournal`: disposable, but state the vault did not have before <!-- src:session opened:2026-08-16 -->
- [ ] `PG-018` **P3** Direct editing in the NotePlan sense, hiding the syntax while typing: SPEC §14 excludes it from v1, reopening needs an ADR — `docs/20260817_TextKit2_live_editing.md` <!-- src:session opened:2026-08-17 -->
  - The study measured what it would cost. The mechanism exists and preserves the file; the expensive part is caret navigation over hidden characters, which folding did *not* need.

## Project Map

- **Entry point**: `Sources/App/PergamenumApp.swift` · CLI `Sources/CLI/main.swift` · MCP `Sources/MCPServer/main.swift`
- **Modules**: `Core` (pure, no SwiftUI, compiled by all three binaries) · `Vault` `Index` (files and the rebuildable cache) · `Connector` (the one vault API behind `perg` and `pergamenum-mcp`) · `Features` `DesignSystem` `App` `Calendar` (app only)
- **Build & test**: `tuist generate --no-open` after editing `Project.swift` or after any git op that adds or removes a file · test-cmd: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' -only-testing:PergamenumTests test` — the Stop hook runs it every turn, so the UI suite is deliberately not in it (see CLAUDE.md)
- **Design notes**: `docs/20260817_TextKit2_live_editing.md` — what TextKit 2 allows, measured against the installed SDK, and the two mechanisms for making the display differ from the file
- **Key ADRs**: 0001 architecture · 0002 naming and shortcuts · 0003 composers · 0004 hours on task dates · 0005 the diary pane · 0006 timeline hours as a setting · 0007 the AI connector · 0008 the global capture panel · 0009 views are queries
- **Invariants**: no network call in any feature · every piece of content is a readable file · the index is rebuildable and never the source of truth · frontmatter is exactly `date`, `tags`, `related`, `aliases` · tags are flat and namespaced, no `/` · no colour or font in a view without a token · never commit to `main`, never force-push · a new connector capability goes in `Sources/Connector/`, never in one front end · the repo has no CI, so "green" always means a local `xcodebuild test`

## Done

- [x] `PG-027` The index and the inspector stop describing a note the composer is covering (`5abbae4`): `newNote` meant both "a draft exists" and "the composer is on screen", so opening a note left it underneath. Split into `noteDraft` and `isComposingNote`, with `isOpenNoteVisible` the one rule both panes read. The on-screen check then found the half no unit test could reach — the list's selection is derived from `openNote`, and SwiftUI runs a selection binding's setter only on a change, so clicking the covered note was no change at all (`d8a67b6`) (2026-08-19)
- [x] `PG-028` A typed title survives stepping out of the composer (`5abbae4`): navigating away parks the title, the folder, the topic and the template for the next `Cmd+N`, while «Annulla», Escape, the × and «Crea» all discard through `endNewNote()`. The guard in `parkNewNote` is what makes the order of SwiftUI's `onDisappear` against the button's own action stop mattering. Only a draft with a title is parked, which is the same threshold the parking uses and is what kept `aNewNoteStartsInTheFolderItWasAskedFor` true (2026-08-19)
- [x] `PG-009` M8 Menu comandi ed editor complete, thirteen slices (PR #62, `7d19baa`): slash menu, code fence highlighting, the note's index, heading folding, transclusion in both surfaces, one `CompletionPanel` for every trigger (PG-023), spell check, emoji completion, find/replace with regex, and the floating format bar last — bold/italic/strikethrough/code plus wikilink/link over a selection, its `PanelPlacement` shared with `CompletionPanel` rather than duplicated. Two AppKit defects only found on screen: `NSPanel.hasShadow` ringed the capsule because its native shadow is computed from the window's own rectangular backing store, and a `.clear`-background `Button` was clickable only on its own glyph without an explicit `contentShape`. Left over: `PG-019`, filed under `PG-005` (2026-08-18)
- [x] `PG-023` One panel draws every completion (PR #57, `6625362`): titles, sections, tags and commands all on `CompletionPanel`, which sits under the caret, flips above the line when there is no room, and never crosses the line being typed into — a clamp that held it inside the screen was the first attempt and put it on top of the text (2026-08-18)
- [x] `PG-025` Typing at the end of a note brings the caret into view: the note grows taller on that very keystroke, so the scroll has to come after the growth and not before (`b1b2dfa`, 2026-08-18)
- [x] `PG-024` The editor's text view now grows to what styling makes it draw — 1431 points needed against the 1244 given, so the last 187 were outside the scroll view's reach and the note looked like it stopped at its final heading. Three mechanisms lie: `sizeToFit()` does nothing, `layoutSubtreeIfNeeded()` works in a hand-built test and not in the app, `setFrameSize` works and empties the diary by re-entering SwiftUI's update pass. `layoutViewport()` leaves the resizing to AppKit (`b1b2dfa`, pre-existing on main, 2026-08-18)
- [x] `PG-021` The fold badge opens its own section: the click hit test the transclusion slice built (`onClickInMargin` plus a rectangle the fragment reports) turned out to be exactly what the badge was waiting for (2026-08-17)
- [x] `PG-017` ADR-0010 written and accepted the same day: transclusion is a view of another note, both surfaces draw it, depth one, and a transcluded note counts as a link — the editor half of §D3 is what is left, and it lives in PG-009 (2026-08-17)
- [x] `PG-010` M9 complete: ADR-0011 implemented end to end in three slices — the `NoteHistory` store and its write hook, the restore sheet with its inspector section and `⌘⇧H`, and templates as notes under `Templates/` with `{{date}}`/`{{title}}` (2026-08-18)
- [x] `PG-020` `![[nota]]` no longer claims a file is missing: a note embed is a note, drawn where it stands, and the message names whichever of the two was actually looked for — closed by the transclusion slice rather than patched (2026-08-17)
- [x] `PG-022` M8's first five slices merged: the slash menu and its panel, code fence highlighting, the note's index, and heading folding — every one mockup-first and verified by hand (2026-08-17)
- [x] `PG-001` ADR-0009 accepted after five corrections from Stefano: `has()` defined, `render: board` without `group` is a parse error, the zero and multi `status-*` cases on the board decided, and the borrowed 150 ms replaced by a real measurement — M11 is unblocked (2026-08-17)
- [x] `PG-008` M7 Cattura globale complete: the connector's `capture` (PR #40) and the global panel (PRs #41), verified by hand over another app and over a full-screen one (2026-08-17)
- [x] `PG-016` ADR-0008 accepted and the capture panel's mockup approved (2026-08-17)
- [x] `PG-007` ADR-0008, the global capture panel, written and proposed (2026-08-16)
