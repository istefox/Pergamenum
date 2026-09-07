# SPEC — Fix rename/move/trash silent-failure bug + Workspace board wikilink rewrite gap

**Topic slug:** rename-move-trash-silent-failure-fix

## Objectives

Two related defects in Pergamenum's sidebar note/folder operations and Workspace board rename
propagation, both found during investigation of a user-reported bug (renaming a note through the
sidebar context menu silently did nothing):

1. Five call sites discard the `Bool`/`String?` result of a vault operation
   (rename/move/trash note, rename/trash folder) and unconditionally close their sheet or dialog,
   so a refused operation (most commonly: the note is open in the editor with unsaved changes)
   looks like it succeeded. The refusal reason is already recorded into `vault.problems` but never
   surfaced in that flow — only visible later in Settings diagnostics.
2. A separate structural gap: when a note is renamed, `NoteFileOperations`'s board-repointing pass
   rewrites `.file`-kind canvas nodes (embeds) but never inspects `.text`-kind canvas node bodies.
   A Workspace board's own freehand text/To-Do card containing `[[OldTitle]]` is left with a stale,
   unresolved wikilink after the rename, while the identical wikilink inside any ordinary `.md`
   note is correctly rewritten.

## Scope

In scope:
- `NoteListPane.swift` — rename sheet confirm handler, trash confirmationDialog destructive button.
- `NoteRowMenu.swift` — "Sposta in" submenu buttons (move note).
- `NoteListPane+FolderVerbs.swift` — folder rename sheet confirm handler, folder trash
  confirmationDialog destructive button.
- `NoteFileOperations.swift` (`repointBoardsPlan`/`repointBoards`) — extend to rewrite
  `[[OldTitle]]` wikilink occurrences inside `.text`-kind canvas node bodies, reusing
  `NoteRename`'s existing wikilink-rewriting logic (`NoteRename.rewritingLinks` or the pure
  string-rewrite it wraps).
- `VaultController+Files.swift` / `VaultController+Folders.swift` — read-only: consult the
  existing `@discardableResult` signatures and `vault.problems`/`recordProblem` mechanism; no
  change to `canOperate`'s refusal policy itself.

Out of scope (explicit non-goals):
- Note-rename-to-task-line propagation for ordinary `.md` files (wikilinks on task lines, frontmatter
  `related`/quoted-related rewriting) — already verified correct in this codebase, untouched.
- `canOperate(on:)` / `canOperateOnFolder(_:)` unsaved-changes refusal policy — this fix is about
  surfacing an existing refusal to the user, never about removing or loosening it.
- `WorkspaceView+FolderVerbs.swift` (board folder rename/delete) — already checks its return value
  correctly (`guard let result = mutate() else { return }`); only lacks a proactive alert, and is
  not part of this chain's delegated scope.
- Any new `WriteJournal`/undo entry kind for folder operations (unrelated to this defect).

## Current behavior (confirmed by investigation, no further discovery needed)

1. `NoteListPane.swift:161-162` — the rename sheet's `onConfirm` closure calls
   `vault.renameNote(at:to:)` (which returns `@discardableResult -> Bool`,
   `VaultController+Files.swift:32-48`) and discards the result, then unconditionally sets
   `renaming = nil`. `canOperate(on:)` (`VaultController+Files.swift:18-23`) returns `false`
   — before any file I/O — when the note being renamed is open in the editor with
   `hasUnsavedChanges == true`, recording `Self.unsavedNoteRefusal` ("salva la nota prima di
   rinominarla, spostarla o eliminarla") via `recordProblem`. That string is never read by this
   call site.
2. `NoteRowMenu.swift:31,33` — the "(radice)" button and the per-folder buttons inside the "Sposta
   in" submenu call `vault.moveNote(at:toFolder:)` and discard the `Bool` return entirely — no
   `if`/`guard`, no alert, no `problems` read.
3. `NoteListPane.swift:173-174` — the delete `confirmationDialog`'s destructive button calls
   `vault.trashNote(at:)` and discards the `Bool`, then unconditionally sets `deleting = nil`.
4. `NoteListPane+FolderVerbs.swift:147-148` — the folder-delete `confirmationDialog`'s destructive
   button calls `vault.trashFolder(at:)` and discards the `Bool`, then unconditionally sets
   `deletingFolder = nil`.
5. `NoteListPane+FolderVerbs.swift:188-189` — `renamingFolder = nil` is set **before**
   `vault.renameFolder(at:to:)` is even called, so the `String?` result cannot be meaningfully
   checked at that point regardless.
6. `NoteFileOperations.swift`'s `repointBoardsPlan`/`repointBoards` (~lines 156-195) iterate a
   board's `CanvasNode`s and rewrite only `.file(path:, subpath:)` entries whose `path` matches the
   renamed note's old relative path. `.text`-kind nodes (the card body string) are never passed to
   any wikilink rewriter, so `[[OldTitle]]` inside a board's own text/To-Do card content survives a
   rename unchanged and becomes an unresolved link.

## Existing patterns to reuse (already correct in this codebase)

- `NoteListPane.swift`'s drag&drop `performMove` (~lines 528-556): checks
  `VaultSession.MoveBatchOutcome.didMove`; on failure builds a `moveRefused` message from
  `outcome.refusals + outcome.failures` and triggers `.alert("Spostamento rifiutato", ...)`
  (~lines 101-114). This is the reference shape for "close + alert" on refusal.
- `RecordingsController.swift:402-413`: checks `vault.trashNote`'s `Bool`, surfaces failure via
  `rowErrors[recordingID] = "Nota non eliminata: \(path)"`, and — critically — does not proceed
  with the dependent ledger-entry state change when the note operation failed.
- `NoteRename.rewritingLinks` (`Sources/Core/Conventions/NoteRename.swift:23`): calls
  `WikilinkParser.links(in: text)` on arbitrary text and returns the rewritten string plus any
  failures — already text-shape-agnostic (works identically on prose, task lines, and frontmatter
  text), so it is directly reusable on a `.text` canvas node's body string.

## UI/UX decisions (from interview)

- **R-01/R-02/R-03/R-04/R-05 (all five call sites): "close + alert" pattern.** On refusal, the
  sheet/dialog still dismisses (unchanged from today), and a `.alert(...)` is then shown with the
  operation-specific title (e.g. "Rinomina rifiutata", "Spostamento rifiutato" — reusing the
  existing wording where a title already exists — "Eliminazione rifiutata" for trash) and
  `vault.problems.last` as the message. This matches the existing `moveRefused` pattern exactly and
  needs no new interaction shape (no inline-error UI, no keep-dialog-open state machine).
- **Testing:** Definition of Done requires unit tests only, covering the refusal-detection/alert-
  message-building logic (pure, testable) and the `.text`-node wikilink rewrite. Visual confirmation
  that the alert actually renders on screen is a manual check, consistent with this project's
  convention that the UI XCUITest suite runs by hand before a merge to `main`, not through
  `.claude/test-cmd`.

## Architecture

- Each of the five call sites gains an `if`/`guard` on the existing `@discardableResult` return
  value (no signature changes to `VaultController+Files.swift`/`VaultController+Folders.swift`).
- On failure, read `vault.problems.last` (already populated by `recordProblem` inside
  `canOperate`/`canOperateOnFolder` or the session's `catch` blocks) into a new or existing
  `@State` alert-message property, and present it via `.alert(...)`, following the exact shape of
  the existing `moveRefused` alert in `NoteListPane.swift`.
- For folder rename (`renameFolder(at:to:) -> String?`), "failure" is a `nil` return; call the
  operation, branch on `nil` vs a concrete new path, and only then clear `renamingFolder`.
- The board `.text`-node wikilink rewrite is added inside `NoteFileOperations`'s existing
  board-repointing pass: for every `.text`-kind `CanvasNode` on every board scanned during a note
  rename, run the same `NoteRename` wikilink-rewrite logic already applied to `.md` file content,
  and write the rewritten body back into the node if it changed. This reuses `WikilinkParser`
  identically to how it is already reused for prose and task lines — no new parser.

## Edge cases

- A note reference appearing more than once inside the same `.text` card body — all occurrences
  rewritten in one pass, matching `NoteRename.rewritingLinks`'s existing whole-text behavior.
- A `.text` card containing no wikilink at all — no-op, node left byte-identical (avoid spurious
  diffs / journal noise).
- Folder rename refusal: `renameFolder` returning `nil` for reasons other than the unsaved-changes
  guard (e.g. name collision) must surface the corresponding `vault.problems.last` message, not a
  generic one.
- A rename that succeeds for the note itself but partially fails to rewrite some links (existing
  `outcome.failures` from `session.renameNote`) is already handled today via
  `recordProblem("link non aggiornato in \(failure)")` in `VaultController+Files.swift:36-38` —
  unaffected by this change, not to be conflated with the "operation refused outright" case this
  SPEC addresses.

## Success criteria

- [ ] R-01 — Renaming a note that is open in the editor with unsaved changes, via the sidebar
      context menu, shows an alert naming the refusal reason instead of silently closing the
      rename sheet with no file change.
- [ ] R-02 — Moving a note via the "Sposta in" submenu, when refused, shows an alert naming the
      refusal reason instead of silently doing nothing.
- [ ] R-03 — Trashing a note via the delete confirmation dialog, when refused, shows an alert
      naming the refusal reason instead of silently doing nothing.
- [ ] R-04 — Renaming a folder via the sidebar, when refused, shows an alert naming the refusal
      reason instead of silently closing the rename sheet with no folder change.
- [ ] R-05 — Trashing a folder via the delete confirmation dialog, when refused, shows an alert
      naming the refusal reason instead of silently doing nothing.
- [ ] R-06 — Renaming a note that is referenced by `[[OldTitle]]` inside a Workspace board's own
      `.text`-kind card (freehand text or To-Do card body) rewrites that occurrence to
      `[[NewTitle]]`, matching the existing rewrite already applied to `.md` files.
- [ ] R-07 — A `.text` canvas node with no matching wikilink is left byte-identical after a note
      rename (no spurious writes).
- [ ] R-08 — `canOperate(on:)`/`canOperateOnFolder(_:)`'s unsaved-changes refusal policy is
      unchanged in behavior — this fix only makes an existing refusal visible, it does not remove,
      loosen, or bypass it. (no-test: policy-preservation is verified by code review of the diff
      against `VaultController+Files.swift`/`VaultController+Folders.swift`, not by a new
      automated test, since the requirement is the absence of a change)
- [ ] R-09 — Unit tests cover: each of the five refusal-detection/alert-message-building paths, and
      the `.text`-node wikilink rewrite (including the no-match no-op case from R-07).
- [ ] R-10 — Note-rename-to-task-line propagation for ordinary `.md` files is unmodified by this
      change. (no-test: this is a non-regression guarantee over existing, already-verified-correct
      behavior; confirmed by the unit suite continuing to pass with no changes needed to existing
      `NoteRename`/`TaskParser` tests, not by a new test asserting the absence of a change)
