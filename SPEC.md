# SPEC — Drag-and-drop board and note files into folders

**Topic slug:** drag-and-drop-board-files-into-workspace

## Objective

Let the user reorganize the vault by dragging rows in the Workspace sidebar tree (boards and
folders) and in the Note sidebar tree (notes and folders) — moving a file or folder into another
folder, or out to the vault root, without leaving the sidebar. Today neither tree has any
drag-and-drop: reorganization requires Finder or manual rename/recreate.

This also extends the sidebar selection model: since the user wants multi-row drag ("move
everything currently selected together"), both trees gain Cmd/Shift-click multi-selection,
additive to (not replacing) the existing single-selection "click opens" behavior.

## Scope

In scope:
- Drag-and-drop of board rows (`.canvas`) and folder rows within the Workspace sidebar tree.
- Drag-and-drop of note rows (`.md`) and folder rows within the Note sidebar tree
  (`NoteListPane.swift` / `NoteTree.swift`).
- Drop targets: an existing folder row (move inside it), or the root area of the tree (move to
  vault root).
- Cmd-click / Shift-click multi-selection in both trees, additive to the existing single-selection
  click-to-open behavior.
- Undo/redo of a move via the standard AppKit `NSUndoManager` (Cmd+Z / Cmd+Shift+Z).
- Name-collision rejection at the destination (no auto-rename, no overwrite).
- Cycle prevention when dragging a folder into its own descendant (or itself).

Out of scope (explicitly deferred, no code touches these):
- Dragging a file/folder in from Finder, or dragging a row out to Finder.
- Copy-on-drag (Option-drag or similar) — every drop is a move.
- Drag-and-drop of anything other than notes, boards and folders (no card-level drag inside a
  canvas; that already exists and is unrelated).
- Reordering rows within the same folder (this feature only changes which folder a row belongs
  to, never its position among siblings — neither tree has manual row ordering today).

## Stack

Swift 6 / SwiftUI on macOS 26, `List(selection:)` inside `WorkspaceBrowser.swift` and
`NoteListPane.swift`. Drag-and-drop uses SwiftUI's `.draggable(_:)` / `.dropDestination(...)`
(or the `NSItemProvider`-based `onDrag`/`onDrop` pair if `.draggable`/`.dropDestination` prove
unable to distinguish "internal reorder" from "external file drop" cleanly inside a `List` — the
architect decides based on a concrete spike, this SPEC does not mandate the API). No new external
dependency.

## Architecture

### Selection model change (supersedes ADR-0024 §D2 in part)

ADR-0024 made `WorkspaceSelection` a single derived value (`.board(folder:)` / `.folder(_)`),
replacing two competing booleans, specifically to remove ambiguity between "what's lit" and
"what's open". That invariant is preserved: there is still exactly one *open* board and one *lit*
row at a time, and a plain click still both selects and opens, unchanged.

What this feature adds is a second, additive concept: a **multi-selection set** (row IDs) used
only to decide what a drag carries. Cmd-click / Shift-click extend this set without changing the
single "open" selection. The two are independent: `WorkspaceSelection` (or its Note-sidebar
equivalent) continues to answer "what's open"; the new multi-selection set answers "what moves
together on a drag". A row that is drag-started while inside a non-empty multi-selection set that
contains it drags the whole set; a row dragged while it is not part of the current multi-selection
drags only itself (the multi-selection set is replaced by the single dragged row for that drag).

This is a deliberate, disclosed reopening of ADR-0024 §D2/§D3's scope — not a reversal of its core
claim (open vs. lit stays one value), an *addition* alongside it.

### Move operation (new, both trees)

Neither `BoardFileOperations.swift` nor `FolderFileOperations.swift` has a move-to-different-
folder operation today (`renamePlan`/`renameBoard`/`trashBoard` and `renamePlan`/
`repointBoardsPlan`/`renameFolder`/`trashFolder` respectively — all same-folder rename or trash,
none change a file's parent folder). This feature adds:
- `BoardFileOperations.movePlan(from:to:)` / `.move(...)` — moves a `.canvas` file to a new
  folder, keeping its file name unchanged. Rejects (reports, does not silently rename) if the
  destination already contains a file of that name.
- `FolderFileOperations.movePlan(from:to:)` / `.move(...)` — moves a folder (and everything
  inside it) to a new parent folder. Rejects on name collision at the destination, and rejects
  (the UI layer refuses to even offer the drop, per the interview decision) when the destination
  is the folder itself or one of its own descendants.
- The Note sidebar needs the equivalent for notes: either a new `NoteFileOperations.movePlan`
  mirroring `BoardFileOperations`'s shape, or reuse if an equivalent already exists for notes —
  the architect confirms which by reading `Sources/Vault/` before designing this.

### Marker and link consequences of a move (no new rewriting)

- **Note wikilinks are unaffected.** `[[Nota]]` addresses a note by title, not path (ADR-0022
  §D4 / ADR-0025 key decision 1) — moving a note to a different folder rewrites nothing.
- **`^[[board.canvas]]` markers are unaffected by a move that keeps the file name.**
  `WorkspaceBoardResolver` resolves a marker by bare file name against every board on disk
  (`resolve(_:in:)`), not by path — the marker text itself never encodes a folder. A move can
  change whether that bare name is `.unique`/`.ambiguous`/`.notFound` afterward (e.g. moving a
  board into a folder that happens to contain a same-named board — already rejected as a
  collision by this feature, so that specific case cannot arise from a move), but the marker is
  never rewritten, matching ADR-0025's explicit choice to report ambiguity rather than guess it.
- **`IndexSnapshot.tasks(assignedToWorkspace:)`'s file-name-only comparison stays unchanged**
  (ADR-0025 key decision 5) — a move does not require touching it; any resulting ambiguity
  surfaces the same way any other ambiguous marker does today.
- **A folder move that carries boards inside it works the same way**, board by board: each
  moved board's bare file name is unaffected (only its containing folder changes), so no marker
  anywhere needs rewriting as a result of a folder move either.

### Undo (new integration — no prior `NSUndoManager` usage in this codebase)

No file in `Sources/` uses `NSUndoManager` today; this is the first. On a successful move, the
handling view registers an inverse move (`newPath → oldPath`) on `NSUndoManager` via
`registerUndo(withTarget:handler:)` (or the SwiftUI `UndoManager` environment value, whichever the
architect determines composes correctly with the existing `NSViewRepresentable` editor/canvas,
which already owns its own undo stack for text/canvas edits — the two undo domains must not
collide or double-register). Redo is the standard `NSUndoManager` inverse-of-inverse; no custom
redo logic.

### Drag/drop UI mechanics

- A row (board, note, or folder) is a drag source. A folder row and the tree's own root/background
  area are valid drop targets; a board or note row is never a drop target.
- During a drag, a folder that is the dragged folder itself or one of its descendants gives no
  drop-target visual affordance and does not accept the drop (interview decision: invalid up
  front, not rejected after the fact).
- A destination already containing a same-named entry gives a drop-target-not-accepted affordance
  the same way, OR (architect's call, whichever the chosen drag API makes straightforward) accepts
  the visual drop and then shows an error dialog naming the collision — either satisfies "reject,
  no silent rename/overwrite" from the interview; the architect states which and why.
- Selecting a board row with a plain click continues to open it, unchanged. Cmd-click / Shift-click
  extend the multi-selection set and never change which board is open.

## Data model

No new persisted schema. `IndexCache.schemaVersion` (currently 3, ADR-0021) is unaffected — a move
is a filesystem rename the existing vault-scan/index-rebuild already tolerates (ADR-0025's
"rebuildable index" principle: nothing here needs a new field, since the index is rebuilt from the
files on disk regardless of which folder they are found in).

## API

No connector surface (`VaultAPI`) change is required by this SPEC — this is a UI-only feature
scoped to the app target's sidebar views and the two new `movePlan`/`move` operations in
`Sources/Vault/`. If the architect finds a reason connectors need this capability too (e.g. a
future `perg move` CLI command), that is out of scope here and tracked separately, consistent with
"a new capability goes into `Sources/Connector/`, not into a front end" (CLAUDE.md) not applying
retroactively to a feature this SPEC does not request there.

## UI flows

1. **Move a board into a folder (Workspace).** User drags a board row onto a folder row. Folder
   highlights as a valid target. On drop: `BoardFileOperations.move` runs, the tree re-renders
   with the board under its new folder, the moved board (if it was the open board) stays open and
   selected at its new location, an inverse-move undo action is registered.
2. **Move a folder into another folder (Workspace or Note).** Same as above; the whole subtree
   moves. Its own descendants (and any folder that is the dragged folder) never highlight as valid
   targets during this drag.
3. **Move to root.** User drags a row onto the tree's empty/root area. Item moves to the vault
   root (folder `""`).
4. **Multi-row move.** User Cmd-clicks or Shift-clicks to build a selection of several rows across
   folders, then drags one of the selected rows. All selected rows move to the drop target
   together, each independently validated (a collision or cycle on one selected row does not
   silently skip it — see edge cases).
5. **Rejected drop (collision).** Destination already has an entry with that name. No files move;
   an error is shown naming the conflicting item(s).
6. **Undo.** Cmd+Z after a move (single or multi-row) reverses it — every moved item returns to
   its prior folder in one undo step for a multi-row move (one `NSUndoManager` group, not N
   separate undo steps a user has to repeat N times).

## Edge cases

- Multi-row drag where the selection includes a folder and one of its own descendants (also
  selected): moving the ancestor folder already carries the descendant with it — the architect
  decides whether the descendant is silently excluded as redundant or produces no separate error
  (it is not a cycle, since the descendant moves as part of its ancestor, not into it).
- Multi-row drag where the selection includes rows that already live directly inside the drop
  target folder: no-op for those rows (already there), not an error, and not skipped from the
  undo group's bookkeeping in a way that would try to "restore" a no-op move.
- Multi-row drag where one selected row's move would collide and another's would not: the
  interview's "reject, no auto-rename" applies per item — the whole multi-row move either commits
  entirely or is refused entirely with the conflicting item(s) named (an all-or-nothing group is
  simpler to reason about and to undo atomically than a partial commit; the architect may choose
  a different atomicity policy only if it states the reason).
- Dragging the row that represents the currently-open board: the open board must not flicker
  closed/reopened; its `WorkspaceSelection` tracks the new folder path after the move completes.
- Dragging while the destination folder is itself mid-rename or mid-delete in another part of the
  UI (unlikely but possible race): the move operation re-validates the destination exists
  immediately before writing, the same defensive pattern `BoardFileOperations`/
  `FolderFileOperations` already use elsewhere in this codebase.
- Undo after further unrelated edits (renames, other moves) between the move and the Cmd+Z: the
  inverse-move undo action targets the *current* path recorded at registration time; if that path
  no longer exists (e.g. a subsequent operation renamed it), the undo action reports it cannot be
  applied rather than silently doing nothing or corrupting state (R-11 (no-test: requires a
  scripted multi-step undo race exercised by hand, not practically assertable in an XCUITest
  without excessive flakiness) covers this by manual verification, not an automated test).

## Success criteria

- [ ] R-01 — Dragging a board row onto a folder row moves the `.canvas` file into that folder on
      disk, and the sidebar tree reflects the new location without a manual rescan.
- [ ] R-02 — Dragging a folder row onto another folder row moves the folder (and everything
      inside it) into that folder on disk.
- [ ] R-03 — Dragging a note row onto a folder row in the Note sidebar moves the `.md` file into
      that folder on disk.
- [ ] R-04 — Dragging a folder row onto another folder row in the Note sidebar moves the folder
      (and its contents) into that folder on disk.
- [ ] R-05 — Dragging any row (board, note, or folder) onto the root area of its tree moves it to
      the vault root.
- [ ] R-06 — Dragging a folder onto itself, or onto one of its own descendant folders, is refused:
      no drop-target affordance appears and no filesystem change occurs.
- [ ] R-07 — Dropping onto a destination that already contains an entry with the same name is
      refused: no files move, no silent rename, no overwrite, and the conflicting name is shown to
      the user.
- [ ] R-08 — Moving a board whose bare file name is referenced by one or more `^[[board.canvas]]`
      task markers elsewhere in the vault does not rewrite those markers; resolution behavior
      (unique/ambiguous/not-found) is computed the same way after the move as before, with no
      marker text changed.
- [ ] R-09 — Moving a note does not modify any `[[Nota]]` wikilink anywhere in the vault.
- [ ] R-10 — Cmd-click and Shift-click extend a multi-row selection in both the Workspace and Note
      sidebar trees without changing which board is currently open.
- [ ] R-11 — Dragging a row that is part of an active multi-row selection moves every selected row
      to the drop target in one operation; dragging a row that is not part of the current
      selection moves only that row.
- [ ] R-12 — A completed move (single-row or multi-row) can be undone with Cmd+Z, restoring every
      moved item to its prior folder in one undo step, and redone with Cmd+Shift+Z.
- [ ] R-13 — A board that is open in the canvas at the moment it (or an ancestor folder of it) is
      moved remains open and correctly selected at its new location after the move completes.
- [ ] R-14 — `xcodebuild ... -only-testing:PergamenumTests test` passes with tests covering the
      new `movePlan`/`move` operations in `BoardFileOperations`, `FolderFileOperations`, and the
      Note-sidebar equivalent, including the collision-rejection and cycle-rejection cases.
- [ ] R-15 — `scripts/uitests.sh` passes, including new UI coverage for at least: a single-row
      board drag-move, a folder drag-move, a multi-row drag-move, and an undo of a move.
