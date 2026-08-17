<!-- project-tasks: prefix=PG lastId=16 -->
# PROJECT TASKS

Updated: 2026-08-17 · Open: 13 (P1: 0) · In progress: 1

## Open Issues

- [ ] `PG-004` **P2** `.pergamenum/cache.db` syncs in iCloud and will produce conflict copies; moving it out of the vault needs an ADR — `Sources/Index/IndexCache.swift` <!-- src:manual opened:2026-08-16 -->
  - Harmless by principle 3, the cache is rebuildable, but the conflict files accumulate in the vault the user reads.
- [ ] `PG-005` **P2** `NoteFileOperations` does not go through `VaultSession.write`, so the journal covers only part of a link rewrite and neither connector can offer `note rename|move|trash` — `Sources/Vault/NoteFileOperations.swift` <!-- src:manual opened:2026-08-16 -->
- [ ] `PG-006` **P2** Build 89: block deletion and images in notes never confirmed by hand — `docs/20260811_Pergamenum_SpecApp.md` <!-- src:manual opened:2026-08-16 -->
  - Pasting an image from the clipboard has no automated test on purpose: driving it would clobber the real system pasteboard.

## In Progress

- [-] `PG-008` **P2** M7 Cattura globale — branch `feature/capture-in-connector` <!-- src:session opened:2026-08-16 -->
  - ADR-0008 accepted and the panel's mockup approved on 2026-08-17 (PRs #38, #39).
  - Order is deliberate: the capture write in `Sources/Connector/` first, with its tests, then the
    AppKit the tests cannot reach.

## Backlog / To Add

- [ ] `PG-009` **P2** M8 Menu comandi ed editor: slash menu, find and replace, outline, code highlighting, transclusion <!-- src:session opened:2026-08-16 -->
  - Starts by putting `completionContext()` under hostile-input test: a lone `#` on a line already took the app down once.
- [ ] `PG-010` **P3** M9 Template e cronologia: templates as real notes, local version snapshots <!-- src:session opened:2026-08-16 -->
- [ ] `PG-011` **P3** M10 Navigazione e organizzazione: tabs, split view, tag browser, starred, the missing search operators <!-- src:session opened:2026-08-16 -->
- [ ] `PG-012` **P2** M11 Viste: saved queries over the index, rendered as table, board, gallery or calendar <!-- src:session opened:2026-08-16 -->
  - Bumps `IndexCache.schemaVersion` to 2 for `embedTargets`, once, and that is the only schema change the milestone may make (ADR-0009 §D2).
  - Blocked by `PG-001` until ADR-0009 is accepted.
- [ ] `PG-013` **P3** M12 La settimana: week and month views, event notes, task grouping and sorting <!-- src:session opened:2026-08-16 -->
- [ ] `PG-014` **P3** M13 Vault completo: `note rename|move|trash` under the journal, prompts in the vault, static export, import, AppIntents <!-- src:session opened:2026-08-16 -->
- [ ] `PG-015` **P3** SPEC amendments §5, §7.4, §8 and §12, plus new §16 Cattura and §17 Viste — `docs/20260811_Pergamenum_SpecApp.md` <!-- src:session opened:2026-08-16 -->
  - Each is applied before the milestone that depends on it, never after.

## Blocked / Decisions Needed

- [ ] `PG-001` **P2** ADR-0009 is `proposed`, not accepted: M11 does not start until it is — `docs/adr/0009-views-are-queries-over-the-index.md` <!-- src:session opened:2026-08-16 -->
- [ ] `PG-002` **P2** SPEC §7.3 rollover as an off-by-default option: the reopening needs Stefano's approval, ADR-0012 would record it <!-- src:session opened:2026-08-16 -->
- [ ] `PG-003` **P2** M9's version snapshots add a second write-time store beside `WriteJournal`: disposable, but state the vault did not have before <!-- src:session opened:2026-08-16 -->

## Project Map

- **Entry point**: `Sources/App/PergamenumApp.swift` · CLI `Sources/CLI/main.swift` · MCP `Sources/MCPServer/main.swift`
- **Modules**: `Core` (pure, no SwiftUI, compiled by all three binaries) · `Vault` `Index` (files and the rebuildable cache) · `Connector` (the one vault API behind `perg` and `pergamenum-mcp`) · `Features` `DesignSystem` `App` `Calendar` (app only)
- **Build & test**: `tuist generate --no-open` after editing `Project.swift` or after any git op that adds or removes a file · test-cmd: `xcodebuild -workspace Pergamenum.xcworkspace -scheme Pergamenum -destination 'platform=macOS' test`
- **Key ADRs**: 0001 architecture · 0002 naming and shortcuts · 0003 composers · 0004 hours on task dates · 0005 the diary pane · 0006 timeline hours as a setting · 0007 the AI connector · 0009 views are queries (proposed)
- **Invariants**: no network call in any feature · every piece of content is a readable file · the index is rebuildable and never the source of truth · frontmatter is exactly `date`, `tags`, `related`, `aliases` · tags are flat and namespaced, no `/` · no colour or font in a view without a token · never commit to `main`, never force-push · a new connector capability goes in `Sources/Connector/`, never in one front end · the repo has no CI, so "green" always means a local `xcodebuild test`

## Done

- [x] `PG-016` ADR-0008 accepted and the capture panel's mockup approved (2026-08-17)
- [x] `PG-007` ADR-0008, the global capture panel, written and proposed (2026-08-16)
