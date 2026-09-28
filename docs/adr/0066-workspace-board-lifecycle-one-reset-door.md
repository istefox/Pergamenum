# ADR-0066: Workspace board lifecycle — one reset door, every leave path settles then flushes

## Status

**Accepted**. Merged to `main` via PR #598 (`1ec9d558`, 2026-09-27), closing `PG-255`/#569
(Audit Fable chain 2) and #506.

## Context

`WorkspaceController` holds two kinds of state: what belongs to the vault (store, thumbnails,
the vault reference) and what belongs to the board on screen (document, origin, selection,
history, folds, viewport, the editing sessions, the deferred save, the deferred refit). The
second kind was reset piecemeal. `attach`, `detach`, `load(board:)` and `select(_:)` each reset
a different subset, and none reset the editing sessions:

- `detach()` confirmed an open crop, which only schedules the ~1 s autosave, then cancelled that
  autosave. A crop confirmed with Return and followed within a second by a vault switch or a
  window close never reached disk (#569 point 1).
- `editingTextNodeID`/`Draft`, `editingTitleNodeID`/`Draft`, `editingDrawingNodeID` and
  `activeDrawing` survived every board change. Ink drawn on board A and confirmed after
  opening board B was written into B's folder, and a stale text-edit id disabled every
  single-letter tool key (points 2, 3).
- `beginTextEdit` did not close a title edit, so the rename was lost; `delete(nodeIDs:)` left
  editing ids naming deleted nodes (point 3).
- The tool-key suspension read `editingTextNodeID` only, so typing "video" in a link card's
  title switched tools (point 4).
- `detach()` cancelled `saveTask` but not `refitTask`, so a deferred refit could frame an empty
  document (point 7).
- Nothing flushed the autosave debounce on quit (#506): `WorkspaceView.onDisappear` does not run
  before the process exits, and the controller is `@State` in that view, out of the
  `AppDelegate`'s reach.

The `foldedHeadings` comment already stated the rule this ADR generalises: a table keyed by node
id would otherwise outlive the board whose ids it names.

The same audit found six smaller defects in the same subsystem (points 5, 6, 8, 9, 10, 11). They
ship here because the chain is one PR, and each is recorded below.

## Decision

### D1 · Two doors: reset and settle

`resetTransientEditing()` clears every per-board transient without writing anything: the text,
title and drawing sessions and their drafts, the crop session, the gesture transients (drag,
resize, arrow, marquee, guides) and `foldedHeadings`. A new transient added to the controller
belongs in this function. That is how the rule stays enforced.

`settleBoardEditing()` is what leaving a board owes. While `board` and `current` still name the
board being left, it confirms the crop, commits the text and title drafts and commits pending
ink (ADR-0020 §D5's "navigating away confirms" applied to every session, not only the crop).
Then it calls `resetTransientEditing()`, so a session that a guard declined to commit still
clears. Ink is committed only while a board is on screen: `commitDrawing` writes the SVG before
its `mutate` would decline, so with no board it would leave a stray file.

The sidebar's `flushBoard()` (`WorkspaceView+FolderVerbs.swift`) calls `settleBoardEditing()`,
where it used to end only the crop. A rename or move of the open board's folder ends in
`open(board: landed)`. That `load` would otherwise commit a text or title draft still open and
flush it to the old path, recreating the file the move had just taken away. The cost is that a
verb which does not touch the open board still resets its heading folds.

### D2 · Every leave path settles, then flushes, then resets

`load(board:)`, `select(_:)`'s folder/nil branch and `detach()` call `settleBoardEditing()`,
then `flushPendingSave()`, then cancel `refitTask` and drop `pendingRefit`. `attach` only resets:
the store it would write to is already gone. `detach()` skips the flush for a `.conflicted`
board, the same exception `WorkspaceView.onDisappear` makes (ADR-0054 §D5), and keeps reporting
the loss. ADR-0060's refusal to *navigate* away from a conflicted board is unchanged.

### D3 · Editing sessions stay exclusive and live

`beginTextEdit` commits an open title edit first, as `beginTitleEdit` already did for a text
edit. `delete(nodeIDs:)` drops any session whose node is being deleted, without committing it,
since there is nothing left to commit to.

### D4 · Tool keys suspend on any text field

`isEditingText` (text or title session open) replaces the text-only check in `BoardChrome`. Crop
and drawing modes have no text field and keep their shortcuts.

### D5 · Quit flushes the open board (#506)

`WorkspaceController.settleForTermination()` runs D1's settle and a flush, and skips a conflicted
board. It is synchronous because `save()` is, so unlike the diary (ADR-0060 §D2) it needs no
`.terminateLater`. `VaultController` holds a weak, observation-ignored `openBoard`. `attach`
sets it, `detach` clears it when it still points at this controller, and
`AppDelegate.applicationShouldTerminate(_:)` calls it before the diary's settle.

### D6 · The rest of the chain

- **Point 5:** `subfolder(for:)`, `editDrawing`, `commitDrawing` and the import directory
  resolve through `store.boundary.url(for:)` (ADR-0041 §D1). A drawing node whose `file`
  escapes the vault is refused and reported. Nothing is read or written outside the vault.
  `commitImport` checks the whole destination file, not only its folder, because
  `proposedName` is text the person edits. `""` still names the vault root for a folder card
  (ADR-0053 §D3), which `VaultBoundary.url(for:)` refuses by design, so the folder lookups map
  it to the root before they resolve.
- **Point 6:** the fit-on-open keys on `workspace.board` instead of `workspace.folder`, because a
  board is addressed by its own path (ADR-0025 §D1). Two boards in one folder each open
  fitted.
- **Point 8:** `ImportNaming.uniqueFileName` takes a `reserved` set, and `importFiles` threads
  the names it has already minted in the same drop, so two same-named files no longer
  collide. `reserved` is compared case-insensitively, as a default APFS volume compares names.
  `VaultController.proposeImport` (the File menu's import into the Inbox) had the same loop
  shape and the same collision. It was outside #569, and it adopts the same `reserved` thread
  here rather than leaving a known twin open.
- **Point 9:** the Workspace note creation and the sidebar move read the open board before the
  `await` and act after it only if the same board is still open (ADR-0043 §D7). Otherwise the
  created note is reported, not placed on another board, and the move leaves the person where
  they navigated. The "ask again after" half lives on the controller
  (`isStillShowing`, `placeCreatedNote`, `followMove` in `WorkspaceController+Lifecycle.swift`,
  PG-287), so `Tests/WorkspaceAfterAwaitTests.swift` pins it; the views keep only the reads made
  before the `await`.
- **Point 10:** two tokens, `color.sticky.orange` and `color.sticky.purple`, in both bundled
  themes and in the built-in fallback palette. JSON Canvas presets 1 to 6 now map one to one.
- **Point 11:** `BoardDragPayload.init?(text:)` requires its separator, so plain text dragged in
  from another app is no longer read as a note path. A custom UTType was considered and not
  adopted: it needs an exported type declaration in the manifest, and the separator check
  already closes the defect.

## Consequences

- One function to extend when a new per-board transient appears, and one test file
  (`Tests/WorkspaceLifecycleTests.swift`) pinning each leave path.
- Leaving a board with ink on it now writes an SVG. Before, the ink was either lost or, worse,
  written into the next board's folder. A person who wanted to discard the ink uses the
  eraser or undo, as for any other card.
- `VaultController` gains a board reference. It is weak and serves the quit path alone, so the
  facade's rule (ADR-0007: vault state on the session, view state on the controller) is not
  bent: the reference is to a window-level object, held only so the app delegate can reach
  it.
- No on-disk format change, no `IndexCache.schemaVersion` change, no protected interface
  touched. Zero new GUI tests.

Extends ADR-0054 §D5 and ADR-0060 §D2/§D3, and applies ADR-0020 §D5, ADR-0025 §D1, ADR-0041 §D1
and ADR-0043 §D7. Amends none.
