# SPEC — Workspace board tree single selection model

**Topic slug:** workspace-board-tree-single-selection

## Objectives

The Workspace sidebar tree (`WorkspaceBrowser.swift`) conflates two distinct selection concepts —
`selectedFolder` (the toolbar's Rinomina/Elimina target, ADR-0022 §D9) and `openBoardPath` (the
board currently shown) — and renders both with the identical `.accentPrimary` color token, with no
other visual differentiator. The result, confirmed by user report and screenshot: three rows can be
lit simultaneously with no discernible meaning, because opening a board writes both state
variables at once.

This feature replaces the two-variable model with **one derived selection**, following the
reference pattern already in the codebase (`NoteListPane.swift`): a `List(selection:)` bound to a
value derived from the controller, native system-drawn row highlighting, and folder rows that are
structurally incapable of being confused with the open board.

This work explicitly **supersedes ADR-0022 §D9** (which introduced `selectedFolder` as state
separate from the open board). The new ADR must say so.

## Scope

In scope:
- `Sources/Features/Workspace/WorkspaceBrowser.swift` — tree rendering, row model, selection state.
- `Sources/Features/Workspace/WorkspaceController.swift` — `hasOpenBoard`/`closeBoard()` folded
  into the new derived-selection model.
- `Sources/Features/Workspace/WorkspaceView.swift` — call site wiring.
- `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift` — `targetFolder` derives from the
  unified selection, no more divergent fallback.
- `Sources/Features/Workspace/BoardChrome.swift` — breadcrumb color aligned to the same convention
  (locked with the user: yes, in this same pass).
- `Tests/WorkspaceOpenStateTests.swift`, `UITests/WorkspaceOpenStateUITests.swift` — rewritten onto
  the new model (both created this session for the now-superseded `hasOpenBoard` flag).

Out of scope:
- Any change to `NoteListPane.swift` itself (it is the reference, not a target).
- Any change to what a board *is* on disk (`.canvas` files, `CanvasStore`) — this is a selection/
  rendering redesign only, no persistence schema change.
- Adding a "create board" affordance to a board-less folder's click (locked: out of scope, see
  Decisions).

## Decisions (locked with the user before/during interview)

1. **One merged row per folder+board.** The disclosure triangle expands/collapses subfolders;
   clicking the row's name opens that folder's board if it has one. The separate child "board" row
   disappears — SPEC §6.2 already treats a board as a folder, so the tree showing them as two rows
   was itself a defect against the app's own spec.
2. **Single selection across the whole tree.** Exactly one thing is selected at a time. Selecting a
   folder closes the currently open board, mirroring `NoteListPane`'s single-derived-binding model.
3. **A folder with no board of its own** (e.g. a pure grouping folder like "Progetti") only
   expands/collapses on click — no "create board" prompt. Its row can still be selected (for
   Rinomina/Elimina) without opening anything, since it has nothing to open.
4. **`hasOpenBoard`/`closeBoard()` fold into the derived-selection binding.** No separate boolean
   state survives: `hasOpenBoard` becomes `selection != nil`-equivalent, `closeBoard()` becomes the
   side effect of writing the derived binding to `nil`.
5. **`BoardChrome.swift`'s breadcrumb is aligned** to the same single color convention as the tree
   in this same pass, closing the third inconsistent color usage the diagnosis found.
6. **Native keyboard navigation is kept.** `List(selection:)` gives arrow-key row navigation for
   free (as `NoteListPane` already has); nothing suppresses it.
7. **No board-open persistence across app relaunch (correction, ADR-0024).** The interview's
   premise was wrong: no such persistence exists in the codebase — `VaultSettings` saves no board
   path, and `5041d5c` (committed this session) already shipped the opposite, "no board open until
   chosen", with a green UI test (`testLeavingAndReturningToTheWorkspacePaneForgetsTheOpenBoard`)
   asserting exactly that. Confirmed with the user at Gate 2: the app relaunches with no board open,
   same as today post-`5041d5c` — this is not a regression to fix, it is the real current state.

## Architecture

**Reference model** (`NoteListPane.swift`):
- `List(selection: selectedPath)` (`:156`) where `selectedPath` is a `Binding<String?>` derived
  from the controller (`:221-232`): `get` reads `vault.openNote?.relativePath`, `set` calls
  `vault.openNote(at:)` or `vault.leaveComposer()`.
- Folder rows carry no `.tag`, so they are structurally excluded from ever being the `List`'s
  selected value (`:290-309`) — expand/collapse only, never highlighted.
- Highlighting, click-to-select, and click-blank-space-to-deselect are all system-drawn; no
  hand-rolled `onTapGesture` substitute.

**Target model for `WorkspaceBrowser`:**
- Replace the hand-rolled `List` (`:191`, no `selection:`) with `List(selection: <derived binding>)`
  in both `folderTree` and `flatList` (the filtered/search view, shown when the filter text is
  non-empty — it must get the same treatment, not be left on the old model).
- The derived binding's `get` reads the currently open board path from `WorkspaceController`
  (replacing `openBoardPath`/`hasOpenBoard` as independently-read state); its `set`:
  - non-nil path with a board → `onOpen(path)`.
  - non-nil path with no board (a board-less folder was `.tag`ged so it can still be selected for
    the toolbar, per Decision 3) → record it as the toolbar target only, no `onOpen` call.
  - `nil` → the equivalent of today's `closeBoard()`.
- `selectedFolder` as independent `@State` is removed. `targetFolder` (`WorkspaceBrowser.swift:
  131-135`) becomes a direct read of the unified selection — no fallback branch, because the
  selection is never absent while something is open (Decision 7) and is explicitly `nil` only when
  nothing is open or selected.
- One row per folder+board (Decision 1): `WorkspaceTreeRow`'s current split between a folder row
  (`:365-373`) and a separate `boardRow` (`:419-437`) merges into a single row view. The disclosure
  chevron (if the folder has children) and the row's `.tag` (if it has a board) become independent
  affordances on the same row, not two rows.
- Icon and text color (defects 1 and 2 in the diagnosis) stop being manually conditioned on
  `selectedFolder`/`openBoardPath` — `List(selection:)`'s native row-fill highlighting is the only
  selection signal; the folder icon is no longer unconditionally `.accentPrimary`.
- AX labels (`WorkspaceBrowser.swift:379`, `:439`) gain a selected/open state, consistent with
  `List(selection:)`'s own accessibility behavior — VoiceOver must be able to tell which row is
  selected without relying on the removed manual color logic.
- `WorkspaceController.hasOpenBoard`/`closeBoard()` (added this session, `5041d5c`) fold into the
  new derived-selection model per Decision 4 — the flag is not kept as parallel state.
- `BoardChrome.swift`'s breadcrumb (per Decision 5) reads the same color token / condition the tree
  now uses for "this is the open board", replacing its own third convention.

## UI flows

1. **Open a board by clicking its row.** One row lights up (system highlight), no other row is
   affected. The toolbar's Rinomina/Elimina target updates to that folder.
2. **Select a folder (with or without a board) by clicking its row.** If a board was open, it
   closes (empty-state pane shown, per the `hasOpenBoard` behavior already shipped this session).
   The clicked folder's row lights up. The toolbar target updates.
3. **Click a board-less folder's disclosure triangle.** Expands/collapses only; does not change
   selection (matches `NoteListPane`'s folder-row behavior, `:290-309`).
4. **Click blank space below the last row.** Deselects — free from `List(selection:)`, no
   hand-rolled `onDeselect`/`onTapGesture` needed any more (the ones added this session for the
   `hasOpenBoard` feature are removed as part of this redesign, superseded by the native behavior).
5. **Arrow-key navigation.** Up/Down move the highlighted row, matching `NoteListPane`.
6. **App relaunch with a previously-open board.** The derived selection binding reflects the
   restored open board on first render — one row lit, same as flow 1, no regression from today.
7. **Filtered/search view (`flatList`, filter non-empty).** Same single-selection, same
   `List(selection:)` binding — not a second, divergent selection model for the filtered case.

## Edge cases

- Opening a board via a source outside the tree (breadcrumb, wikilink, restore-at-launch) must
  still result in the tree showing exactly that board's row as selected — the diagnosis's defect 5
  (tree and toolbar disagreeing) must not have a new equivalent under the derived-selection model.
- Renaming or deleting the currently selected/open folder: existing `WorkspaceFolderActions`
  behavior is unchanged by this feature; only what row is highlighted before/after is in scope.
- Filtering the tree text while a board is open: the open board's row, if visible in the filtered
  results, must still show as selected.

## Success criteria

- [ ] R-01 — The Workspace tree renders exactly one row per folder-that-has-a-board, never a
      separate child row for the board (Decision 1).
- [ ] R-02 — Exactly one row in the tree is ever visually highlighted as selected at a time, using
      native `List(selection:)` row-fill highlighting, not a manually-colored icon or text.
- [ ] R-03 — Opening a board highlights only that board's own row — no ancestor folder row is
      simultaneously highlighted as a second, differently-meaning selection.
- [ ] R-04 — Selecting a folder while a board is open closes the open board (Decision 2); exactly
      one thing is selected across the whole tree at any time.
- [ ] R-05 — Clicking a board-less folder's name/row only expands or collapses it — no board is
      created and no creation prompt appears (Decision 3).
- [ ] R-06 — `WorkspaceBrowserToolbar`'s Rinomina/Elimina target always matches the tree's visually
      selected row, with no fallback branch that can diverge from what is shown on screen (fixes
      diagnosis defect 5).
- [ ] R-07 — Clicking the blank area below the tree's last row deselects, using `List(selection:)`'s
      native behavior — no hand-rolled `onTapGesture`/`onDeselect` gesture remains in
      `WorkspaceBrowser.swift`.
- [ ] R-08 — Arrow-key (Up/Down) navigation moves the tree's selection natively, matching
      `NoteListPane`'s existing keyboard behavior.
- [ ] R-09 — The filtered/search list (`flatList`, shown when the filter is non-empty) uses the same
      single derived-selection `List(selection:)` binding as the unfiltered tree — not a second,
      divergent implementation.
- [ ] R-10 — Relaunching the app shows no board open (matching `5041d5c`'s existing "no board open
      until chosen" behavior — corrected at Gate 2, ADR-0024: no persisted board path exists to
      restore). A board opened from outside the tree (breadcrumb, wikilink, restore-from-state)
      still lights its own row, per R-06.
- [ ] R-11 — `WorkspaceController.hasOpenBoard` and `closeBoard()` are removed as independent state;
      their behavior is fully expressed through the new derived-selection binding (Decision 4).
- [ ] R-12 — `BoardChrome.swift`'s breadcrumb uses the same color convention as the tree's selection
      highlighting for "this is the open board", replacing its previous third, inconsistent
      convention (Decision 5).
- [ ] R-13 — VoiceOver can distinguish a selected/open row from an unselected one through its
      accessibility label or trait, not only through color (fixes diagnosis defect 6).
- [ ] R-14 — `Tests/WorkspaceOpenStateTests.swift` and `UITests/WorkspaceOpenStateUITests.swift` are
      updated to assert against the new single-selection model, with no assertions left referring to
      the removed `selectedFolder`/`hasOpenBoard` two-variable model.
- [ ] R-15 — A new ADR is written that explicitly records superseding ADR-0022 §D9
      (no-test: this is a documentation deliverable, verified by its presence in `docs/adr/` and
      its cross-reference from ADR-0022, not by an executable assertion).
- [ ] R-16 — `tuist generate` + build succeed, the full unit suite passes via `.claude/test-cmd`, and
      `scripts/uitests.sh` passes before merge, per this project's standing CLAUDE.md working
      agreement (no-test: the last clause is a process obligation confirmed by running the script,
      not something a unit test can assert on its own).
