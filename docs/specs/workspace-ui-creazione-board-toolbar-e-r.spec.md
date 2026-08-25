# SPEC — Workspace UI: creazione board, toolbar e rename

**Topic slug:** workspace-ui-creazione-board-toolbar-e-r

## Objectives

The Workspace sidebar (`WorkspaceBrowser`) currently exposes no way to create a new board, no
way to name one when creating it (the mechanism exists but is reachable only from File → "Nuova
board", not from the Workspace UI itself), and no way to rename or delete an existing one. This
feature closes all three gaps, and along the way introduces the vault's first folder-rename and
folder-delete operations (today only single notes can be renamed or trashed).

A "workspace" in this app is always the board of a real folder (`CanvasStore.boardPath(forFolder:)`
names the board after the folder). Creating, naming, renaming or deleting a workspace therefore
means creating, renaming or deleting the folder underneath it.

## Scope

In scope:
- A toolbar in the `WorkspaceBrowser` header with: "+ Nuova workspace", "Rinomina", "Elimina",
  "Espandi tutto" / "Comprimi tutto".
- Creating a new workspace/folder with an explicit parent picker and a chosen name, validated
  against `NoteName.validate` rules.
- Renaming an existing workspace/folder, with a vault-wide rewrite of every wikilink (`[[...]]`)
  and every task marker (`^[[...]].canvas`) that references a note or board whose path changed.
- Deleting a workspace/folder (moves the whole folder to the system Trash via
  `FileManager.trashItem`, consistent with the existing single-note delete), gated by a
  confirmation dialog that states how many notes/subfolders will be removed.
- The vault root's own board (named after the vault itself) is exempt from both rename and
  delete — those actions are disabled on that row.
- Name-collision handling: both create and rename block inline on a name that already exists,
  the same pattern `RenameNoteSheet` already uses for `NoteName.Violation`.
- Navigation behavior: renaming the currently open board keeps it open under its new name;
  deleting it moves the view to the nearest surviving parent folder.

Out of scope:
- Moving a workspace to a different parent without renaming it (drag-and-drop reparenting).
- Any change to the underlying `.canvas` file format or to how a board's spatial content is
  stored — only the folder/board's *name and existence* are touched.
- Undo/redo for rename or delete beyond what the filesystem Trash already provides (no
  `WriteJournal` entry — this mirrors the existing single-note delete, which is not journaled
  either).

## Stack

No new dependency. Swift 6, SwiftUI, on the macOS 26 SDK, consistent with the rest of the app.
The rewrite logic reuses `NoteRename`'s existing wikilink-rewrite machinery, extended to also
recognize the `^[[...]].canvas` task marker introduced by ADR-0021.

## Architecture

New pieces, at a level architect decides on the concrete file layout:

- `CanvasStore` or a new `FolderRenameOperations` file gains `renameFolder(from:to:)`,
  performing the on-disk `FileManager` move and reusing the vault's wikilink-rewrite pass
  (`NoteRename`-style) scoped to every note whose path starts with the renamed folder's old
  prefix, plus every task marker referencing the folder's old board file name.
- The same layer gains `deleteFolder(at:)`, trashing the folder via `FileManager.trashItem`.
- `WorkspaceBrowser` gains a header toolbar (new subview, e.g. `WorkspaceBrowserToolbar`) wired
  to: create (opens a naming sheet with a parent-folder picker), rename (opens a renaming sheet
  seeded with the selected row's current name), delete (opens a confirmation dialog stating
  the content count), expand-all/collapse-all (already exist as context-menu actions — the
  toolbar exposes the same `expanded` binding).
- The existing `checkPendingNewBoard()` / `NewCanvasItemSheet` flow in `WorkspaceView` stays for
  the File → "Nuova board" menu path; the new sidebar "+" button opens a parallel or shared sheet
  that additionally lets the user pick the parent folder (File → "Nuova board" keeps defaulting
  to the currently open board, unchanged).
- Root-board exemption: the toolbar's Rename/Elimina buttons (and the row's context menu, if one
  is added) are disabled when the selected row's `node.id` is empty/root, mirroring how
  `CanvasStore.boardPath(forFolder:)` special-cases the empty folder today.

## Data model

No new persisted state. A workspace/board continues to be identified purely by its folder's
vault-relative path; nothing new is stored in the index, in frontmatter, or in the `.canvas`
file itself (schemaVersion stays unchanged, consistent with ADR-0021 D10).

## UI flows

**Create:**
1. User clicks "+" in the Workspace toolbar (or File → "Nuova board", unchanged).
2. Sheet opens: text field for name, picker for parent folder (defaulting to the currently open
   board's folder, or root if none).
3. Live validation against `NoteName.validate` plus a same-parent name-collision check; "Crea" is
   disabled with an inline error until both pass.
4. On confirm: folder is created on disk, the sidebar tree refreshes (`scanGeneration`), the new
   board opens.

**Rename:**
1. User selects a row in the Workspace sidebar and clicks "Rinomina" in the toolbar (disabled if
   the row is the vault root).
2. Sheet opens, seeded with the current name, same validation as create.
3. On confirm: folder renamed on disk; every wikilink and every `^[[...]].canvas` task marker
   referencing a path under the old folder is rewritten; if the renamed folder is (or contains)
   the currently open board, the view stays open, now reflecting the new path/name.

**Delete:**
1. User selects a row and clicks "Elimina" in the toolbar (disabled on the vault root).
2. Confirmation dialog states the folder name and counts (e.g. "Verranno eliminate 4 note e 2
   sottocartelle").
3. On confirm: folder moved to Trash; if it was (or contained) the currently open board, the view
   moves to the nearest surviving parent.

## Edge cases

- Renaming/deleting the vault root board: blocked at the UI level (buttons disabled).
- Name collision on create or rename: blocked inline, no silent overwrite, no auto-suffix.
- Renaming a folder whose new name fails `NoteName.validate`: blocked inline with the same
  violation text `ConformanceText.lines` already renders for note rename.
- Deleting a folder that contains the currently open board, a nested board, or notes referenced
  by other boards' `NOTE REFERENZIATE` panels: those references become unresolved (shown with
  the existing "questionmark.square.dashed" treatment `BoardChrome.swift` already renders for an
  unresolved reference) — this is the existing, accepted behavior for a deleted note; nothing new
  is invented for the folder case.
- A folder deleted while it (or an ancestor) is the currently open board: the view must not be
  left pointing at a folder that no longer exists — falls back to the nearest surviving parent.
- Wikilink rewrite touches every note in the vault, not just the renamed folder's own contents —
  the same vault-wide scope `NoteRename`'s existing note-rename rewrite already has.

## Success criteria

- [ ] R-01 — The Workspace sidebar header shows a toolbar with "+ Nuova workspace", "Rinomina",
      "Elimina", "Espandi tutto"/"Comprimi tutto".
- [ ] R-02 — Clicking "+ Nuova workspace" opens a sheet with a name field and a parent-folder
      picker; confirming creates the folder on disk under the chosen parent with the chosen name.
- [ ] R-03 — Creating a workspace with a name that collides with an existing folder/file in the
      chosen parent is blocked inline, with no folder created.
- [ ] R-04 — Creating a workspace with a name that fails `NoteName.validate` is blocked inline.
- [ ] R-05 — Selecting a non-root row and clicking "Rinomina" opens a sheet seeded with the
      current name; confirming a valid new name renames the folder on disk.
- [ ] R-06 — After a rename, every wikilink (`[[...]]`) elsewhere in the vault that pointed to a
      note under the renamed folder is rewritten to the new path.
- [ ] R-07 — After a rename, every task line's `^[[...]].canvas` marker that referenced the
      renamed folder's board is rewritten to the new board file name.
- [ ] R-08 — Renaming the folder backing the currently open board keeps that board open, now
      showing the new name in the breadcrumb.
- [ ] R-09 — "Rinomina" and "Elimina" are disabled when the vault root row is selected.
- [ ] R-10 — Selecting a non-root row and clicking "Elimina" shows a confirmation dialog stating
      how many notes and subfolders will be removed.
- [ ] R-11 — Confirming delete moves the folder (and everything inside it, including its
      `.canvas` file) to the system Trash via `FileManager.trashItem`, not `removeItem`.
- [ ] R-12 — Deleting the folder backing the currently open board (or an ancestor of it) moves
      the Workspace view to the nearest surviving parent folder.
- [ ] R-13 — Unit tests cover: folder rename with wikilink rewrite, folder rename with task
      marker rewrite, name-collision rejection on create and rename, and the root-folder
      exemption from rename/delete.
- [ ] R-14 (no-test: this is a manual QA pass over the running app, not something a unit test
      asserts) — Manual UI verification: create, rename, delete and the toolbar buttons all
      exercised end-to-end in the running app before this feature is considered complete.
- [ ] R-15 (no-test: a documentation update, not an assertable behavior) — `docs/20260811_Pergamenum_SpecApp.md`
      §6.1 is updated to document that a board's folder can be renamed and deleted from the
      Workspace sidebar, and what happens to references when it is.
