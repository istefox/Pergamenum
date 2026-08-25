# SPEC — Task row richer info display

**Topic slug:** task-list-row-richer-info-display-worksp

## Objectives

The Attività task row shows too little of what a task actually carries. Today a task assigned to
a Workspace board via `^[[board.canvas]]` (ADR-0021) is invisible on the row — it has no marker at
all, and it lands under "Senza" in the "Per progetto" grouping, which groups by an unrelated
`^id`/`^parent` sub-task relation, not by Workspace. A task with both a scheduled date and a
deadline silently loses one of the two on the row. Tags never appear on the row at all.

This feature makes the row (and, for Workspace assignment specifically, a new grouping) surface
the metadata that already exists on `TaskItem` but is not drawn: which note the task lives in
(already shown), which Workspace board it is assigned to (not shown today), scheduled date and
deadline together when both exist (only one shown today), and its tags (not shown today).

## Scope

In scope:
- Workspace-assignment indicator on the task row, both densities (`compact`: minimal icon;
  `expanded`: full board name, path when unambiguous, clickable to open the board).
- A sixth `TaskGrouping` case, "Per Workspace", grouping tasks by assigned board.
- Showing both scheduled date and deadline on the row when a task has both.
- Tag chips on the expanded row, one neutral design-system color (no per-namespace colors — see
  Trade-offs).
- A shared helper resolving a task's stored `workspacePath` (a bare board file name) to the
  board's full vault-relative path, replacing the two existing independent implementations of
  that same comparison (`IndexSnapshot.tasks(assignedToWorkspace:)`, `WorkspacePicker.row`) —
  closes `PG-038`.

Out of scope (explicitly deferred, decided in interview):
- Per-namespace tag colors (8 new design tokens, light+dark) — needs its own mockup and its own
  chain, per CLAUDE.md's "no hardcoded colors, every token needs an approved mockup" rule.
- Any change to note-reference or wikilink display on the row (already correct).
- Any change to `TaskGrouping.project` ("Per progetto") — it stays exactly what it is today, the
  `^id`/`^parent` sub-task grouping (ADR-0021 §D6); this feature does not touch it.

## Stack

Swift 6, SwiftUI, macOS 26 SDK. No new dependency. No index schema change (`workspacePath`
resolution is computed at read time from `CanvasStore.allBoards()`, exactly as `WorkspacePicker`
already does — nothing new is persisted).

## Architecture

- `Sources/Core/Tasks/TaskItem.swift` — no change; `workspacePath: String?` and `tags: [Tag]`
  already exist and already carry what this feature needs.
- New shared resolver (exact file TBD by the architect, likely `Sources/Core/Tasks/` or
  `Sources/Vault/`, pure — no SwiftUI import, so it stays reachable by `perg`/`pergamenum-mcp`
  per the `sharedSources` rule in CLAUDE.md): given a vault root and a bare board file name,
  returns one of `.unique(path)`, `.ambiguous`, `.notFound` (or an equivalent enum — architect's
  call). Consumed by:
  - `IndexSnapshot.tasks(assignedToWorkspace:)` (existing call site, replaces its own inline
    comparison).
  - `WorkspacePicker.row` (existing call site, replaces its own inline comparison).
  - The new row-display code in `TasksView.swift` (new call site).
  - The new `.workspace` case in `TaskArrangement.groups(...)` (new call site).
- `Sources/Core/Tasks/TaskListOptions.swift` — `TaskGrouping` gains a `case workspace` (title "Per
  Workspace", icon `rectangle.3.group` — same icon the toolbar's "Assegna a un Workspace" button
  and `WorkspacePicker` already use for this concept). `TaskArrangement.groups(...)` gains a
  `.workspace` branch grouping by the resolved board's full path when unambiguous, by the bare
  board name when ambiguous, and unassigned tasks under a group titled "Nessun Workspace" (not
  the shared `TaskArrangement.noneTitle` constant — deliberately, per interview: this grouping's
  empty bucket is more specific than the other five).
- `Sources/Features/Tasks/TasksView.swift`:
  - `row(_:)` gains a compact-density Workspace indicator (icon only, shown only when
    `task.workspacePath != nil`).
  - `details(_:)` (the expanded second/third line) gains: the Workspace name (resolved via the
    shared helper; full path when unambiguous, bare name when ambiguous or when the reference is
    orphaned — no board on disk matches the stored name at all), clickable when resolved to
    exactly one path, plain text when ambiguous or orphaned; both `!due` and `>scheduled` shown
    together when both exist (today only one renders); tag chips.
  - Opening a Workspace board from the row reuses the existing route mechanism
    (`vault.routeState.pendingCanvas` / `Navigation.pane = .workspace`), the same one
    `PergamenumURL`'s `pergamenum://canvas` route and in-board node navigation already use — no
    new navigation primitive.
- `Sources/Features/Tasks/WorkspacePicker.swift` — its own `isAssigned` comparison (line 84)
  switches to the shared helper; no behavior change, only de-duplication.
- `Sources/Index/IndexSnapshot.swift` — `tasks(assignedToWorkspace:)` switches to the shared
  helper; no behavior change, only de-duplication.

## Data model

No new fields, no index schema bump. Everything drawn already exists on `TaskItem`
(`workspacePath`, `scheduled`, `due`, `tags`, `links`, `sourcePath`). The only new piece of
*derived* data is the resolved-path lookup, computed on demand from `CanvasStore.allBoards()` and
never persisted — the same non-persistence choice `WorkspacePicker` already makes for its own
board list.

## API

No connector-facing change. `Sources/Connector/VaultAPI` is untouched — this is a pure
presentation-layer feature (row rendering, grouping) with one shared internal resolver that is
not part of the CLI/MCP surface.

## UI flows

1. **Compact row, task assigned to a Workspace.** The row shows the task text and, beside it (or
   inline with the checkbox/marker cluster — architect/coder's call on exact placement, but not
   in the second line, since compact density has none), a small `rectangle.3.group` icon. No
   other row gains this icon.
2. **Expanded row, task assigned to a Workspace, unambiguous.** Second line gains a clickable
   segment showing the board's full vault-relative path (e.g. "Prova/Prova 2 rinominata"),
   styled like the existing note-reference button. Clicking it switches to the Workspace pane and
   opens that board.
3. **Expanded row, task assigned to a Workspace, ambiguous (two+ boards share the file name).**
   Second line shows the bare board name only (no path), not clickable as a board-open action;
   clicking it opens `WorkspacePicker` for that task instead, so the user can clarify/reassign.
4. **Expanded row, task assigned to a Workspace, orphaned (no board on disk has that name any
   more).** Second line shows the bare name written in the marker, as plain text, not clickable.
5. **Expanded row, task with both `>scheduled` and `!due`.** Trailing area shows both markers
   (today shows only `!due` when both are present).
6. **Expanded row, task with tags.** Second/third line gains one chip per tag, single neutral
   design-system color, `#namespace-value` text.
7. **Attività, grouping menu.** A sixth entry "Per Workspace" (icon `rectangle.3.group`) appears
   alongside the existing five. Selecting it groups the current view's tasks by resolved board
   path (unambiguous) or bare board name (ambiguous), with unassigned tasks under "Nessun
   Workspace".

## Edge cases

- Ambiguous board name (two folders, same board file name): row shows name-only, not clickable as
  open-board; grouping heading shows name-only too, and two differently-located same-named boards
  collapse into one grouping bucket (documented limitation, consistent with the ambiguity itself
  being unresolvable without more context — same limitation ADR-0022 §D8 already accepts for the
  marker-rewrite case).
- Orphaned board reference (marker points to a file that no longer exists): row shows the raw
  name from the marker, not clickable, no error state — mirrors how an ordinary wikilink to a
  missing note already renders in this app.
- Task with no Workspace assignment: no icon in compact, no Workspace segment in expanded, lands
  in "Nessun Workspace" when grouped by Workspace.
- Task with neither `>scheduled` nor `!due`: trailing area unchanged (nothing shown there today,
  nothing shown there after this feature).
- Task with no tags: no chip row, no layout gap.
- Empty vault / no boards at all: "Per Workspace" grouping shows a single "Nessun Workspace"
  bucket with every task in it — no crash, no special-cased empty state beyond that.

## Success criteria

- [x] R-01 — The task row's expanded density shows the assigned Workspace board's full
      vault-relative path when the board name resolves to exactly one board on disk.
- [x] R-02 — The Workspace name shown on the row is clickable and switches to the Workspace pane,
      opening the resolved board, when resolution is unambiguous.
- [x] R-03 — When board-name resolution is ambiguous (multiple boards share the file name), the
      row shows the bare board name only (no path), and clicking it opens `WorkspacePicker` for
      that task instead of attempting to open a board.
- [x] R-04 — When the stored board name matches no board on disk (orphaned reference), the row
      shows the raw name as plain, non-clickable text.
- [x] R-05 — The task row's compact density shows a minimal Workspace-assignment icon
      (`rectangle.3.group`) when the task is assigned to a Workspace, and shows nothing extra
      when it is not.
- [x] R-06 — When a task has both a scheduled date (`>date`) and a deadline (`!date`), the
      expanded row shows both, not only the deadline as today.
- [x] R-07 — The task row's expanded density shows one chip per tag the task carries, using a
      single neutral design-system color token (no per-namespace differentiation in this cycle).
- [x] R-08 — `TaskGrouping` gains a sixth case "Per Workspace" (icon `rectangle.3.group`) that
      groups the current view's tasks by resolved assigned-board path (or bare name when
      ambiguous), with unassigned tasks grouped under "Nessun Workspace".
- [x] R-09 — A single shared helper resolves a task's `workspacePath` to a board's full path (or
      reports ambiguous/not-found), and replaces the two pre-existing independent
      implementations of that same comparison in `IndexSnapshot.tasks(assignedToWorkspace:)` and
      `WorkspacePicker.row` — no third duplicate copy exists after this feature (closes `PG-038`).
- [x] R-10 — No view touched by this feature introduces a hardcoded color; every color used goes
      through an existing design-system token (SPEC binding rule, CLAUDE.md).
- [x] R-11 — Unit tests cover: the new `.workspace` case of `TaskArrangement.groups(...)`
      (unambiguous, ambiguous, and unassigned-to-"Nessun Workspace" cases), the shared resolver
      helper (unique match, ambiguous match, no match), and the row logic that shows both
      scheduled date and deadline when both are present.
- [x] R-12 (no-test: this is a manual QA pass over the running app, not something a unit test
      asserts) — Manual verification on the running app: compact row shows the Workspace icon
      only when assigned, expanded row shows note/Workspace/tags/both-dates together correctly,
      clicking the Workspace name opens the correct board, and the new "Per Workspace" grouping
      populates "Nessun Workspace" correctly for unassigned tasks.

## Trade-offs (recorded from interview)

- **Full path over bare name for the Workspace display**, chosen despite the extra row width,
  because the user explicitly wants precision over compactness for this specific piece of
  information — reconsider if it proves visually cramped during manual QA.
- **Single neutral tag-chip color, not per-namespace**, because no color token for any of the 8
  tag namespaces (SPEC §4.4) exists in `Resources/Themes/*.json` today, and CLAUDE.md requires an
  approved mockup before a new design token is introduced. Per-namespace color is explicitly
  deferred to its own future chain, not dropped.
- **"Nessun Workspace" rather than the shared `TaskArrangement.noneTitle` ("Senza")** for this
  grouping's empty bucket — a deliberate one-grouping exception, chosen in interview over
  consistency with the other five groupings' shared empty-label constant.
