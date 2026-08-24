# SPEC — Workspace file browser, Task↔Workspace/Note relations, project sub-tasks

**Topic slug:** workspace-tasks-notes-integration

## Objectives

Give Stefano a way to work Pergamenum's three existing tools — vault notes, Workspace canvases,
and the task system — as one connected project surface for client work:

1. Browse and open Workspaces (`.canvas` files) through a dedicated folder tree in the sidebar,
   alongside the existing Note and Task trees.
2. Assign exactly one Workspace to a Task, and see, from the Workspace side, which tasks are
   assigned to it, plus which notes it references — in a dedicated side panel on the canvas.
3. Manage a Task as a project: sub-tasks with their own independent due dates, grouped and
   expandable in the Attività view, with a derived (non-authoritative) progress indicator.
4. Assign multiple Notes to a Task (already possible today via wikilinks in the task line, per
   SPEC §7.2) and exactly one Workspace (new field, see below).

## Non-objectives

- No new top-level "client project" grouping above individual Workspace files — Workspace-as-file
  keeps mapping 1:1 to a `.canvas`, browsed through the vault's existing folder structure.
- No change to `.pergamenum/vocabolari.json`, the tag schema (SPEC §4.4), or the note frontmatter
  schema (SPEC §4.3). Both stay closed, per CLAUDE.md.
- No automatic completion cascade from sub-tasks to their parent task.
- No cross-file cascading delete/update for orphaned `^parent` references — the conformance
  linter flags them; nothing blocks or auto-repairs.
- No change to Obsidian round-trip compatibility beyond what this feature explicitly introduces
  (see Decisions below) — already deprioritized as a product direction (ADR-0020, 2026-08-24).

## Decisions carried from the interview

- **Workspace browser reuses the existing folder tree over `.canvas` files.** No new file format,
  no new persisted grouping concept. It is a third top-level sidebar section (Note / Workspace /
  Task), mirroring the existing note folder tree's UI pattern.
- **Task↔Workspace and Task↔Note relations are new explicit caret markers in the task line text**,
  not the existing generic wikilink mechanism (SPEC §7.2 stays as-is for incidental links; these
  markers are the *authoritative* single-Workspace assignment):
  - `^[[Workspace.canvas]]` — the one Workspace assigned to this task. A second `^[[...]].canvas`
    marker in the same task line is invalid; the conformance linter (§4.7) flags it, the first
    occurrence wins at read time.
  - Plain wikilinks `[[Note title]]` in the task text continue to mean "note(s) linked to this
    task" exactly as SPEC §7.2 already defines — no change; this is how "multiple Notes per Task"
    is satisfied, unchanged from today.
  - This deliberately breaks Obsidian readability for the `^[[Workspace.canvas]]` marker specifically
    (it renders as literal text with a caret prefix in Obsidian) — accepted tradeoff, confirmed
    2026-08-24, consistent with ADR-0020's same-day Obsidian-compatibility deprioritization. The
    file remains valid Markdown; nothing else about the note breaks.
- **Sub-task hierarchy uses new explicit id/parent caret markers**, not GFM indentation and not the
  `#project-*` tag:
  - `^id(N)` — assigned automatically by the app when a sub-task is created via "Aggiungi
    sotto-task", auto-incrementing, unique **within the containing note only** (not vault-wide).
    No registry to maintain — consistent with the rebuildable-index principle (CLAUDE.md
    principle 3): ids are read directly from the note text at scan time.
  - `^parent(N)` — on a sub-task line, references its parent task's `^id(N)` within the same note.
  - **Deliberately not a tag**: `#task-NNN` was considered and rejected — `task` is not one of the
    closed tag-schema prefixes (`client|competitor|project|type|topic|status|area|source`, SPEC
    §4.4), and CLAUDE.md forbids extending that schema locally (harness-system is the source of
    truth). The `^id`/`^parent` markers are a separate, task-line-local namespace; they do not
    touch the tag system.
  - A parent task with sub-tasks shows a **derived, non-authoritative progress indicator**
    ("3/5 completati") in the Attività view. Completing all sub-tasks does **not** write `@done`
    to the parent line automatically — the parent's own completion stays a manual action, same as
    every other task (no hidden automatic file writes).
  - Deleting/editing lines such that a `^parent(N)` points at an id no longer present in the note
    produces no cascade and no block: the conformance linter (§4.7) flags the orphaned reference.
    Note rename/move is already covered by the existing wikilink-rewrite mechanism (wikilink.md
    W-08); ids are note-local so they need no rewriting on move.
- **Workspace dashboard**: a new collapsible right-side panel on the canvas (same UI pattern as
  the existing "Task collegati" / "Backlink" panels on notes, SPEC §7.2), with two sections:
  - **Task assegnati** — every task in the vault whose line carries `^[[this-canvas]]`, with
    status/dates, completable in place (writes to the task's source note, same as the existing
    "Task collegati" panel).
  - **Note referenziate** — the Document cards and wikilinks present on this canvas.
  This panel is new UI; it does not replace or change the existing tag-based project view
  (SPEC line 152), which continues to aggregate by `#project-*` unchanged.
- **Attività view** gets a new "Progetti" grouping mode: a parent task with `^id` is
  expandable/collapsible, showing its `^parent`-linked sub-tasks indented beneath it with the
  progress indicator described above. The existing Inbox/Oggi/Progetto/Tutti groupings stay flat
  and unchanged — every sub-task still appears there individually if it has its own `>date`/`!due`.
- **EventKit / Calendario integration is unchanged**: a sub-task with its own `!scadenza` or
  `>date` participates in the timeline/calendar exactly like any other task (SPEC §7.5/§7.6) — no
  special-casing for parent/child relationship on the calendar side.

## Architecture

- **Parser extension** (`Sources/Core` task-line parser): recognize three new caret markers —
  `^[[<canvas-file>]]` (Workspace assignment), `^id(<N>)`, `^parent(<N>)` — alongside the existing
  `>date`, `!due`, `@remind(...)`, `@repeat(...)` markers. Grammar addition only; no change to the
  frontmatter or tag parsers.
- **Index (`.pergamenum/cache.db` via GRDB, per CLAUDE.md principle 3)**: extend the task table
  with `workspace_path` (nullable, from `^[[...]]`), `local_id` (nullable, from `^id`),
  `parent_local_id` (nullable, from `^parent`). Entirely derived from a vault rescan — deleting
  the cache loses nothing, consistent with the existing rebuildable-index guarantee.
- **Workspace browser**: new sidebar section reusing the existing folder-tree view component used
  for notes, filtered to `.canvas` files, with the existing card/thumbnail conventions.
- **Workspace dashboard panel**: new `NSViewRepresentable`/SwiftUI panel on the canvas view,
  querying the index for tasks where `workspace_path` matches the open canvas's path, and for
  Document cards / note wikilinks already present on the canvas (no new query — existing canvas
  card enumeration).
- **Task detail / Attività view**: existing task list view extended with an optional "Progetti"
  grouping mode, driven by `local_id`/`parent_local_id` joined within the same source note.
- **Conformance linter (§4.7)**: two new advisory rules — duplicate `^[[...]].canvas` marker in
  one task line (second ignored, first wins), and `^parent(N)` referencing an id not present in
  the same note (orphaned reference). Both advisory, neither blocks a save or a scan.

## Data model

No frontmatter changes. No tag schema changes. All new state lives in task-line text (source of
truth, per CLAUDE.md principle 1 "file over app") and is mirrored into the rebuildable SQLite
index, per principle 3.

Task line grammar addition (informal):

```
- [ ] <text> [[Note A]] [[Note B]] ^[[Workspace.canvas]] ^id(3) ^parent(1) >2026-09-01 !2026-09-10
```

- `[[Note A]] [[Note B]]` — existing wikilink mechanism, unchanged (SPEC §7.2): "Notes linked to
  this task", zero or more.
- `^[[Workspace.canvas]]` — new, zero or one per task line: the single assigned Workspace.
- `^id(N)` — new, zero or one per task line: this task's local identifier (assigned by the app on
  sub-task creation, not manually typed under normal use).
- `^parent(N)` — new, zero or one per task line: the local id of this task's parent within the
  same note.
- All markers are order-independent relative to each other and to the existing `>date`/`!due`
  markers, consistent with the existing task grammar's tolerance.

## UI flows

1. **Browse and open a Workspace**: sidebar → Workspace section → folder tree of `.canvas` files
   → click opens the canvas, same interaction model as the existing note tree.
2. **Assign a Workspace to a Task**: Task detail panel → "Workspace" field → picker (same
   component class as the existing note-linking picker) → writes `^[[chosen.canvas]]` into the
   task's source line.
3. **View a Workspace's assigned tasks and notes**: open a Workspace canvas → toggle the new right
   side panel → "Task assegnati" (completable in place) and "Note referenziate" sections.
4. **Create a project with sub-tasks**: on any task, "Aggiungi sotto-task" command → new task line
   created with `^id` auto-assigned and `^parent` pointing at the current task's `^id` (created if
   the current task didn't have one yet) → each sub-task gets its own `>date`/`!due` independently.
5. **View projects in Attività**: Attività sidebar → new "Progetti" grouping → parent tasks appear
   expandable, showing progress ("3/5 completati") and their sub-tasks indented; other groupings
   (Inbox/Oggi/Progetto/Tutti) remain flat and show every task, including sub-tasks, individually.

## Edge cases

- Two `^[[...]].canvas` markers on one task line → first wins at read time; linter flags it as
  advisory, no block, no auto-fix.
- `^parent(N)` with no matching `^id(N)` in the same note (deleted line, typo, or copy-pasted from
  elsewhere) → orphaned reference, linter flags it as advisory; the sub-task still appears
  ungrouped in the flat Attività views.
- Note/canvas rename or move → existing wikilink-rewrite mechanism (W-08) updates any
  `^[[Workspace.canvas]]` reference exactly as it updates plain wikilinks today; `^id`/`^parent`
  need no rewrite since they are note-local.
- Task copied to another note (e.g. via daily-note reference or manual copy-paste) carrying an
  `^id`/`^parent` → those become meaningless in the new note (ids are note-local); not actively
  stripped, but not resolved either — advisory linter territory if it ever matters in practice.
- Deleting the parent task line while sub-tasks remain → no cascade; sub-tasks keep their
  `^parent(N)` pointing at a now-orphaned id, flagged by the linter as above.
- Workspace assigned to a task that is later deleted from the canvas (canvas file deleted) →
  `^[[Workspace.canvas]]` becomes an unresolved wikilink, same handling as any other unresolved
  wikilink in the app today (§Link non risolti view).

## Success criteria

- [ ] R-01 — A new "Workspace" section exists in the sidebar, showing a folder tree of `.canvas` files, and clicking an entry opens that canvas.
- [ ] R-02 — The task-line parser recognizes `^[[<canvas-file>]]`, `^id(<N>)`, and `^parent(<N>)` markers without breaking existing `>date`/`!due`/`@remind`/`@repeat`/wikilink parsing.
- [ ] R-03 — Assigning a Workspace to a task via the Task detail panel's "Workspace" field writes exactly one `^[[...]].canvas` marker into the task's source line.
- [ ] R-04 — A task can carry multiple plain wikilinks to notes (`[[Note A]] [[Note B]]`) alongside its single `^[[Workspace.canvas]]` marker, and both are indexed correctly.
- [ ] R-05 — Opening a Workspace canvas and toggling the new side panel shows a "Task assegnati" section listing every task in the vault whose line carries `^[[this-canvas]]`, with status and dates, completable in place.
- [ ] R-06 — The same side panel's "Note referenziate" section lists the Document cards and note wikilinks present on the open canvas.
- [ ] R-07 — "Aggiungi sotto-task" on a task creates a new task line with an auto-assigned `^id`, sets `^parent` to the current task's id (assigning one to the parent first if absent), and the new sub-task's own `>date`/`!due` are independent of the parent's.
- [ ] R-08 — The Attività view offers a "Progetti" grouping mode where a parent task with an `^id` is expandable/collapsible, shows its `^parent`-linked sub-tasks indented beneath it, and displays a derived "N/M completati" progress indicator that does not write to any file.
- [ ] R-09 — Completing every sub-task of a project does not automatically mark the parent task complete (no `@done` auto-write).
- [ ] R-10 — Existing flat Attività groupings (Inbox/Oggi/Progetto/Tutti) continue to show every task, including sub-tasks, individually and unchanged.
- [ ] R-11 — A second `^[[...]].canvas` marker on the same task line is flagged as an advisory finding by the conformance linter (§4.7); the first occurrence is used at read/index time; nothing blocks the save.
- [ ] R-12 — A `^parent(N)` referencing an id not present in the same note is flagged as an advisory finding by the conformance linter; no cascade, no auto-repair.
- [ ] R-13 — Renaming or moving a `.canvas` file updates every `^[[...]].canvas` marker referencing it, via the existing wikilink-rewrite mechanism (W-08).
- [ ] R-14 — The SQLite index (`workspace_path`, `local_id`, `parent_local_id` on the task table) is fully derivable from a vault rescan; deleting `cache.db` and rescanning reproduces identical Workspace/sub-task relationships.
- [ ] R-15 — No frontmatter key or tag prefix outside the closed schemas (SPEC §4.3, §4.4) is introduced by this feature.
- [ ] R-16 — End-to-end, offline: open the Workspace browser, select a client `.canvas`, see its assigned tasks and referenced notes in the side panel; create a project task with 2 sub-tasks on different due dates; assign the same Workspace and two different notes to the project task; see it expandable with a progress bar in Attività; all state survives an app restart and a full index rebuild.

## Stack

Unchanged from the project baseline (see CLAUDE.md): Swift 6, SwiftUI on macOS 26 SDK, GRDB for
the SQLite cache, TextKit 2 editor, no new dependencies.
