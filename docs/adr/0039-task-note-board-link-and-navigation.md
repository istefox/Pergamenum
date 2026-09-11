# ADR-0039: Task ↔ note/board link and navigation

## Status

Accepted

## Context

In the Attività pane, a task's relation to its note and to a board was confusing and
partly broken. Three defects, verified against the code before this chain started:

1. **The breadcrumb button on a task row never brought its destination forward.**
   `TasksView+Row.swift`'s breadcrumb called `vault.openNote(at: task.sourcePath)` but
   never set `navigation.pane = .notes`. The note loaded into a background tab that was
   never brought on screen, so from the Attività pane the click produced nothing
   visible. The same omission was independently present in three other places: the Task
   menu (`PergamenumApp.swift`), the "Task collegati" panel row (`LinkedTasksPanel.swift`),
   and, differently, was correctly paired only in the row's own context menu and the
   Attività toolbar.
2. **"Collega nota o board…" could not actually link a board.** It opened
   `QuickSwitcher(mode: .pick)`, whose `Choice` enum had no board/canvas case at all —
   `.note`, `.heading`, `.createNote`, `.dailyNote` only — and the handler discarded
   anything but `.note`. The label promised a capability the code never implemented.
3. **The note half of that same command was redundant regardless.** A task's note is
   already the file it was captured into, decided once at creation by `TaskComposer`'s
   `DestinationPicker`. There is no second note to "link" later — the breadcrumb already
   shows the one and only note a task belongs to.

A fourth, smaller defect sat beside these: `TasksView+Row.swift`'s `open(link:)`, the
handler for a task's own wikilink chips, carried a comment stating a `.canvas`-suffixed
link "points at a board" but then did `return` — doing nothing — instead of navigating
to it.

Underlying all four: the three commands involved (link a board, go to the note, go to
the board) were duplicated by hand across four surfaces — the row's context menu, the
Attività toolbar, the Task menu, and the "Task collegati" panel row — with no shared
catalogue, which is exactly how the surfaces had already drifted out of step with each
other.

SPEC §7.2 required an assisted-linking command to a **note** from the task views. This
ADR removes it (point 3 above) — this is a deliberate, recorded reopening of that
requirement, not an omission. The model itself is unchanged: a task may still contain
any hand-written wikilink to a note or a `.canvas`, and both remain clickable (the
fourth defect above is fixed as part of this same change).

## Decision

**One task-command catalogue, `TaskCommand`** (`Sources/Features/Tasks/TaskCommand.swift`),
mirroring `CardCommand` and `CalendarDayCommand`: an `import Foundation`-only,
`CaseIterable` enum with `title`, `symbol`, `identifier`, and a
`static func available(for: TaskItem) -> [TaskCommand]`. Three cases:

- `.linkBoard` — "Collega una board…", always offered.
- `.goToNote` — "Vai alla nota di origine", always offered.
- `.goToBoard` — "Vai alla board collegata", offered only when `task.workspacePath != nil`.

The note-linking capability of the old "Collega nota o board…" is gone — not renamed,
not narrowed, removed — because there is nothing left for it to do that the composer
does not already do at creation time.

**One place performs the three actions**: `CommandActions+TaskCommands.swift` adds
`run(_ command: TaskCommand, on task: TaskItem)` and the matching `canRun`, the same
shape `CommandActions.run(_:on:)`/`canRun(_:on:)` already use for the note-row context
menu. `.goToNote` performs `vault.openNote(at:)` and `navigation.pane = .notes`
together, closing the breadcrumb's defect at its one real cause. `.goToBoard` reuses
`WorkspaceBoardResolver` and `vault.routeState.pendingCanvas` — the exact mechanism the
row's board chip already used successfully — falling back to the picker on an
ambiguous file name and to `vault.recordProblem` on an orphaned marker. `.linkBoard`
sets a new `navigation.taskPickingBoard: TaskItem?`.

**The board picker moves to `RootView`.** It used to live inside `TasksView`, reachable
from the Task menu only through a flag-plus-`onChange` round trip
(`vault.isLinkingSelectedTask`, now removed). Hosting the `.sheet(item:)` at `RootView`
instead means the command works from every surface that offers it, including the "Task
collegati" panel, which lives inside the Workspace pane where `TasksView` does not
exist.

**All four surfaces now read the one catalogue and call the one action set**: the task
row's context menu and breadcrumb, the Attività toolbar, the Task menu, and the "Task
collegati" panel row (`TaskPanelRow`).

**`open(link:)` is fixed to actually navigate** on a `.canvas` wikilink, resolving it
through `WorkspaceBoardResolver` instead of returning without effect.

**Nothing at the vault-write layer changes.** `VaultSession.TaskChange.link` and
`TaskParser+Writes.line(for:addingLinkTo:)` stay — pure, tested capability for writing
a wikilink into a task line — simply uncalled by any UI after this change. A wikilink
typed by hand into a task line, to a note or to a `.canvas`, remains valid and
navigable; only the assisted UI for adding a *new* note link is gone.

## Alternatives considered

- **Keep both "Collega nota o board…" and "Assegna a un Workspace…" as two separate
  commands, and just fix the first to actually support boards.** Rejected: fixing the
  note half would still leave it linking to a second, additional note the task views
  give no reason to want, since the one note that matters is already fixed at capture
  time. Two commands for one useful action (assigning a board) is worse than one.
- **A single "Vai a…" command that opens whichever destination is more specific**
  (board if assigned, else note). Rejected in favor of two distinct, always-present
  commands: collapsing them would hide the source note whenever a board is also
  assigned, discarding information a person may specifically want (which note the task
  is written in, independent of which board it is also filed under).

## Consequences

**Positive:**
- The breadcrumb, the Task menu, and the "Task collegati" panel now actually navigate
  to the note, not just to a background tab.
- A board can be reached from every surface that mentions one, including a new "Vai
  alla board collegata" that did not exist anywhere before (SPEC §7.2 asked for it,
  under a different, never-implemented name).
- A `.canvas` wikilink chip on a task row is no longer inert.
- The three commands cannot drift out of step across surfaces again without a change to
  the one catalogue and the one action set both live in.

**Negative:**
- SPEC §7.2's original "collegamento assistito" to a note is gone; a person who wants a
  task to reference a *second*, unrelated note now has to type the wikilink by hand
  (still fully supported and navigable — just with no picker UI).
- `QuickSwitcher.Mode.pick` is now unreferenced by any caller (the only one was the
  removed handler). Left in place rather than removed in this chain — its removal
  touches a file (`QuickSwitcher.swift`) outside this change's scope and is a candidate
  for a small, separate follow-up.

**Neutral:**
- `vault.isLinkingSelectedTask` and `TasksView`'s `linking`/`assigningWorkspaceFor`
  `@State` are removed; `WorkspacePicker` itself is unchanged, only re-hosted.

## References

- ADR-0021 (Workspace/Task/Note integration) — original `^[[<board>.canvas]]` marker
  and `TaskItem.workspacePath`/`links` split this ADR builds on without changing.
- ADR-0023 (universal command surface parity) — the shared-catalogue pattern
  (`CardCommand`, `CalendarDayCommand`, `CommandActions.run(_:on:)`) this ADR mirrors
  for tasks.
- ADR-0025 (folder/board separation) — `WorkspaceBoardResolver`, reused unchanged by
  `.goToBoard` and by the fixed `open(link:)`.
- `docs/20260811_Pergamenum_SpecApp.md` §7.2 — amended 2026-09-08 alongside this ADR.
