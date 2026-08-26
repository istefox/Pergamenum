# Workspace folder/board separation (Finder/Obsidian model)

**Topic slug:** workspace-folder-board-separation

## Objective

Separate the folder-container concept from the board-file concept in the Workspace, replacing
the current "one board per folder, named after it" rule with a Finder/Obsidian model: a folder
is always a pure container, never directly openable as a board, and a `.canvas` file is a free
document — any name, any folder, any count.

## Context / current state

`CanvasStore.boardPath(forFolder:)` derives a board's file path from its containing folder's
name (`prova/prova.canvas`), so every folder that owns a board is indistinguishable from a
"file": it can be both entered as a container and opened/written to as a board. This is codified
by SPEC §6.1 (docs/20260811_Pergamenum_SpecApp.md, lines 189-190: "il Workspace è organizzato in
board, una per cartella"), ADR-0022, and ADR-0024 §D2/§D3.

## Scope

In scope: `Sources/Vault/CanvasStore.swift`, `Sources/Features/Workspace/WorkspaceTree.swift`,
`Sources/Features/Workspace/WorkspaceSelection.swift`, `Sources/Features/Workspace/WorkspaceBrowser.swift`,
`Sources/Features/Workspace/WorkspaceBrowserToolbar.swift`,
`Sources/Features/Workspace/WorkspaceView+FolderVerbs.swift`, `WorkspaceController`, `BoardTopBar`
breadcrumb, unit tests for `WorkspaceTree`/`CanvasStore`/selection, UI test identifiers touching
`workspace-board-*`/`workspace-foreign-board-*`.

Out of scope: `perg`/`pergamenum-mcp` CLI connectors (boards are not exposed there — unaffected),
`pergamenum://` URL scheme semantics (already addressed by file path), vault data migration
(none needed — see Data model below).

## Stack

Swift 6, SwiftUI, macOS 26. No new dependency. Same layering as the rest of the Workspace
feature (Vault → Controller → View).

## Architecture

### Data model

- A folder is a pure container. It never has an implicit board.
- A `.canvas` file is addressed by its own file path, not derived from any folder name.
- A folder and a `.canvas` file may share a name in the same parent directory (Finder
  semantics — folders and files live in separate namespaces). This is required for backward
  compatibility: `prova/prova.canvas` remains valid, now read simply as "the board named
  `prova`, inside the folder `prova`" — no conversion, no migration script, no data rewrite.
- `CanvasStore.boardPath`/`url`/`load`/`save` become addressed by the board's own file path
  instead of by its containing folder. `contents(ofFolder:board:)` keeps deriving the containing
  folder from the board's path (`deletingLastPathComponent`), used for file-drop placement
  (unchanged: a dropped file lands beside the open board, in its containing folder).
- New: `CanvasStore.createBoard(named:in:)` writes an empty `.canvas` with a user-chosen name in
  a chosen folder, rejecting a name already taken by another `.canvas` in that same folder.
  `createFolder(named:in:)` is unchanged and no longer implicitly calls `save(.empty, folder:)`
  after it — creating a folder never creates a board.

### Tree model

- `WorkspaceTree.Node.Kind` becomes `.folder` and `.board(path:)`, replacing
  `.workspace(board:)` and `.foreignBoard(path:)`. The `.foreignBoard` case and its
  non-selectability rule (ADR-0024 §D3) are removed entirely — every `.canvas` is a legitimate,
  openable board now.
- The tree is built from folders **plus** `.canvas` files, not from `allBoards()` alone: a
  folder with no board must still appear in the tree (this is what unblocks the deferred "new
  folder" toolbar button).
- The root's special-cased synthesis in `build(boards:boardPath:)` is removed — the vault root
  is an ordinary folder like any other, and any `.canvas` at its top level (e.g.
  `Pergamena.canvas`) is an ordinary board file inside it, not a synthesized root board.

### Selection

- `WorkspaceSelection.board(folder:)` becomes `.board(path:)`. This deliberately reverses
  ADR-0024 §D2 ("the selection tag is always the folder path, never the board path"), which is
  why this feature's ADR must explicitly supersede that decision rather than silently diverge
  from it.

### Controller / views

- `WorkspaceController.open(folder:)` becomes `open(board:)`; its `folder` property is derived
  from the open board's path (`deletingLastPathComponent`) rather than being the identity itself.
- `BoardTopBar` breadcrumb shows the containing folder's path plus the board's own file name.
- `WorkspaceBrowser.identifier(for:)` drops the `workspace-foreign-board-*` form.
  `selection(for:)` drops the branch that returns `nil` for a foreign board (nothing is
  unselectable anymore). `WorkspaceRow.icon` switches from "does this folder own a board" to a
  direct `Kind` switch: `folder`/`folder.fill` for `.folder`, `rectangle.3.group` for `.board`.
- `WorkspaceBrowserToolbar`: the existing `+` becomes "Nuova board" and prompts for a name; a
  new "Nuova cartella" button (`folder.badge.plus`, identifier `workspace-new-folder`) sits
  beside it and calls `createFolder(named:in:)` alone, with no board side effect.
- `WorkspaceView+FolderVerbs.swift`: `createWorkspace(named:in:)` splits into `createBoard`
  (writes a `.canvas`, does not touch folders) and `createFolder` (writes a directory only).
  Folder rename/delete simplify: the "ambiguous board file name" case in ADR-0022 (two folders
  sharing a name → board-marker rewrite skipped) is removed, since there is no more one board
  per folder to disambiguate.
- A board row gets its own Rinomina/Elimina (toolbar + context menu, same pattern as ADR-0023's
  other command clusters), operating on the `.canvas` file directly rather than through a
  folder-rename side effect. This did not exist before because a board's name was always its
  folder's name.

## UI flows

- **Create board**: click "Nuova board" → name prompt → file created. If a tree row is
  selected, the board is created in that folder; if nothing is selected, it is created at the
  vault root (same fallback `targetFolder` already uses today for nothing-selected, per
  ADR-0024 §D5).
- **Create folder**: click "Nuova cartella" (next to "Nuova board") → name prompt → empty
  directory created, no board, appears immediately in the tree.
- **Open a board**: single click on a board row (unchanged mechanism, now driven by
  `.board(path:)` instead of `.board(folder:)`).
- **Double-click on a folder row**, including one holding exactly one board: expands/collapses
  the row. It never opens a board implicitly — opening a board always requires an explicit
  click on the board's own row. This keeps the model consistent (a folder is always just a
  container) rather than adding a single-board shortcut exception.
- **"Nuovi elementi" tray**: continues to exclude only the file of the currently-open board.
  Sibling `.canvas` files in the same folder are NOT surfaced as tray cards — the tray shows
  unplaced items, not a board switcher.
- **Rename/Delete a board row**: new Rinomina + Elimina, acting on the `.canvas` file alone.
- **Rename/Delete a folder row**: acts on the directory alone; no longer touches any board
  marker rewrite tied to a same-named board file.

## Edge cases

- Root-level `.canvas` (`Pergamena.canvas`): ordinary board row at the top level of the tree,
  no special synthesis.
- Folder and `.canvas` sharing a name in the same parent (`prova/` + `prova.canvas` inside
  its parent, or `prova/prova.canvas` where `prova.canvas` sits *inside* folder `prova`):
  both are valid, addressed independently by path — this is the existing vault shape and must
  keep working with zero data migration.
- Empty folder (no boards, no children): appears in the tree as a plain expandable/collapsible
  row with no board icon underneath.
- `^[[name.canvas]]` markers (ADR-0021): continue to resolve by file path; become less ambiguous
  since a `.canvas` is no longer implicitly tied to one specific folder name.
- Deleting a folder still moves the whole folder (and any boards inside it) to the Trash via
  `FileManager.trashItem`, unchanged mechanism (ADR-0022 §D... delete-via-Trash convention).

## Non-goals

- No automatic migration or rewrite of existing vault files. `prova/prova.canvas` needs no
  change on disk — only how the tree interprets and displays it changes.
- No change to `perg`/`pergamenum-mcp` connectors.
- No change to `pergamenum://` URL scheme handling.

## Success criteria

- [ ] R-01 — Creating a folder via "Nuova cartella" produces no `.canvas` file and the folder appears in the Workspace tree as an expandable container with no board underneath.
- [ ] R-02 — Creating a board via "Nuova board" writes a `.canvas` file with the chosen name in the chosen folder (or vault root when nothing is selected) and does not create or require a same-named folder.
- [ ] R-03 — Two `.canvas` files can coexist in the same folder with different names, and both appear as separate, independently openable board rows in the tree.
- [ ] R-04 — A folder and a `.canvas` file sharing the same name in the same parent directory (e.g. `prova/` and a sibling `prova.canvas`, or the pre-existing `prova/prova.canvas` shape) both resolve correctly with no data loss and no crash.
- [ ] R-05 — Double-clicking a folder row, including one containing exactly one board, expands or collapses that row and never opens a board.
- [ ] R-06 — Single-clicking a board row opens that board, addressed by its own file path rather than by any folder identity.
- [ ] R-07 — The "Nuovi elementi" tray excludes only the file of the currently-open board; sibling `.canvas` files in the same folder do not appear as tray cards.
- [ ] R-08 — A board row exposes its own Rinomina and Elimina commands (toolbar + context menu), acting on the `.canvas` file independently of any folder.
- [ ] R-09 — Renaming or deleting a folder never rewrites or otherwise touches an unrelated same-named `.canvas` file, and never hits the "ambiguous board file name" skip case from ADR-0022 (that case no longer applies).
- [ ] R-10 — An empty folder (no boards, no children) is visible in the tree as a plain container row.
- [ ] R-11 — A root-level `.canvas` file (e.g. `Pergamena.canvas`) appears as an ordinary board row at the top of the tree, with no special-cased root synthesis.
- [ ] R-12 — `^[[name.canvas]]` markers (ADR-0021) continue to resolve correctly to the target board by file path after this change.
- [ ] R-13 — The existing vault at `~/Library/Mobile Documents/com~apple~CloudDocs/Vaults/Pergamena` (verified on a disposable COPY, never the original) opens with all existing boards and folders intact and correctly distinguished, requiring no conversion step. (no-test: manual verification against a copied vault is required because it depends on real iCloud-synced user data that cannot be part of the automated test suite)
- [ ] R-14 — The full unit test suite passes with `WorkspaceTree`, `CanvasStore`, and selection tests rewritten (not disabled) for the new model.
- [ ] R-15 — `perg` and `pergamenum-mcp` command-line targets continue to build (ADR-0001 §D1 conformance).
- [ ] R-16 — `scripts/uitests.sh` passes in full before merge, with `workspace-board-*`/`workspace-foreign-board-*` identifiers updated to match the new tree model. (no-test: full confirmation of this requires the human-run UI suite per CLAUDE.md's binding merge rule, run deliberately by hand rather than by an automated agent)
- [ ] R-17 — SPEC §6.1 (lines 189-190) and §6.4 tool 4 (Cartella) in docs/20260811_Pergamenum_SpecApp.md are amended to describe the new folder/board model. (no-test: a documentation amendment has no executable assertion; it is verified by human review of the diff)
- [ ] R-18 — A new ADR is written that explicitly supersedes ADR-0024 §D2/§D3 and the relevant part of ADR-0022, and CLAUDE.md's chain decision index is updated to reference it. (no-test: an ADR and a documentation index entry are process artifacts verified by human review, not by an automated assertion)
