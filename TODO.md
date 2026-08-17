<!-- project-tasks: prefix=PG lastId=22 -->
# PROJECT TASKS

Updated: 2026-08-17 · Open: 17 (P1: 0) · In progress: 0

## Open Issues

- [ ] `PG-004` **P2** `.pergamenum/cache.db` syncs in iCloud and will produce conflict copies; moving it out of the vault needs an ADR — `Sources/Index/IndexCache.swift` <!-- src:manual opened:2026-08-16 -->
  - Harmless by principle 3, the cache is rebuildable, but the conflict files accumulate in the vault the user reads.
- [ ] `PG-005` **P2** `NoteFileOperations` does not go through `VaultSession.write`, so the journal covers only part of a link rewrite and neither connector can offer `note rename|move|trash` — `Sources/Vault/NoteFileOperations.swift` <!-- src:manual opened:2026-08-16 -->
- [ ] `PG-006` **P2** Build 89: block deletion and images in notes never confirmed by hand — `docs/20260811_Pergamenum_SpecApp.md` <!-- src:manual opened:2026-08-16 -->
  - Pasting an image from the clipboard has no automated test on purpose: driving it would clobber the real system pasteboard.
- [ ] `PG-020` **P2** Reading mode renders `![[nota]]` as "file non trovato nel vault": embedding a *note* is not supported yet and the error box says the wrong thing about it — `Sources/Features/Editor/MarkdownReadingView.swift` <!-- src:session opened:2026-08-17 -->
  - Seen on screen on 2026-08-17 while checking the outline. Pre-existing, not introduced by M8. The fix is transclusion (PG-017); until then the message should say the target is a note rather than claim the file is missing.

## In Progress

_Nothing in progress._

## Backlog / To Add

- [ ] `PG-009` **P2** M8 Menu comandi ed editor: five slices merged 2026-08-17, the rest still open <!-- src:session opened:2026-08-16 -->
  - Done: slash menu and its own panel (#44, #45), code fence highlighting with seven local grammars (#47), the note's index with click-to-scroll (#48), heading folding with a count badge (#49).
  - Left: transclusion (blocked on PG-017), block links `[[note#heading]]`, floating format bar, emoji on `:`, spell check, regex in find, and the index's drag-to-move (PG-019).
  - Find and replace was already there: only regex is missing, and `NSTextFinder` does not offer it.
- [ ] `PG-010` **P3** M9 Template e cronologia: templates as real notes, local version snapshots <!-- src:session opened:2026-08-16 -->
- [ ] `PG-011` **P3** M10 Navigazione e organizzazione: tabs, split view, tag browser, starred, the missing search operators <!-- src:session opened:2026-08-16 -->
- [ ] `PG-012` **P2** M11 Viste: saved queries over the index, rendered as table, board, gallery or calendar <!-- src:session opened:2026-08-16 -->
  - Bumps `IndexCache.schemaVersion` to 2 for `embedTargets`, once, and that is the only schema change the milestone may make (ADR-0009 §D2).
  - Unblocked: ADR-0009 accepted 2026-08-17.
- [ ] `PG-013` **P3** M12 La settimana: week and month views, event notes, task grouping and sorting <!-- src:session opened:2026-08-16 -->
- [ ] `PG-014` **P3** M13 Vault completo: `note rename|move|trash` under the journal, prompts in the vault, static export, import, AppIntents <!-- src:session opened:2026-08-16 -->
- [ ] `PG-019` **P2** The index's second half: drag a section to move it, which is a real text rewrite through `VaultSession.write` with the journal behind it — `Sources/Features/Editor/OutlinePane.swift` <!-- src:session opened:2026-08-17 -->
  - Deferred on purpose when the index shipped: listing and jumping touch nothing, moving a section writes.
- [ ] `PG-021` **P3** The fold badge is not clickable: a section is folded from the index or from Vista, never from the editor itself — `Sources/Features/Editor/FoldedHeadingFragment.swift` <!-- src:session opened:2026-08-17 -->
  - Needs hit-testing a rect the fragment draws, which nothing in the text view tracks today.
- [ ] `PG-015` **P3** SPEC amendments §5, §7.4, §8 and §12, plus new §16 Cattura and §17 Viste — `docs/20260811_Pergamenum_SpecApp.md` <!-- src:session opened:2026-08-16 -->
  - Each is applied before the milestone that depends on it, never after.

## Blocked / Decisions Needed

- [ ] `PG-002` **P2** SPEC §7.3 rollover as an off-by-default option: the reopening needs Stefano's approval, ADR-0012 would record it <!-- src:session opened:2026-08-16 -->
- [ ] `PG-003` **P2** M9's version snapshots add a second write-time store beside `WriteJournal`: disposable, but state the vault did not have before <!-- src:session opened:2026-08-16 -->
- [ ] `PG-017` **P2** Transclusion needs an ADR before any code — `docs/20260816_Pergamenum_Roadmap.md` <!-- src:session opened:2026-08-17 -->
  - Rendering `![[nota]]` in reading mode only widens the distance between the two surfaces, and every such addition turns "add direct editing" into "choose between two editors". The ADR has to decide whether the editor draws it too.
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

- [x] `PG-022` M8's first five slices merged: the slash menu and its panel, code fence highlighting, the note's index, and heading folding — every one mockup-first and verified by hand (2026-08-17)
- [x] `PG-001` ADR-0009 accepted after five corrections from Stefano: `has()` defined, `render: board` without `group` is a parse error, the zero and multi `status-*` cases on the board decided, and the borrowed 150 ms replaced by a real measurement — M11 is unblocked (2026-08-17)
- [x] `PG-008` M7 Cattura globale complete: the connector's `capture` (PR #40) and the global panel (PRs #41), verified by hand over another app and over a full-screen one (2026-08-17)
- [x] `PG-016` ADR-0008 accepted and the capture panel's mockup approved (2026-08-17)
- [x] `PG-007` ADR-0008, the global capture panel, written and proposed (2026-08-16)
