# UX Blueprint — Workspace browser, Task↔Workspace/Note relations, project sub-tasks

## Window inventory

| Window | Type | SwiftUI Scene / Style | Notes |
|--------|------|-----------------------|-------|
| Main window | WindowGroup | NavigationSplitView (existing, 2–3 column) | No new window type introduced. This feature extends the existing sidebar and canvas content area. |
| Settings | Settings (existing) | TabView | Unchanged — no new preferences introduced by this feature. |

No new window, no new scene. Everything lives inside the existing single main window.

## Navigation structure

The existing sidebar (`NavigationSplitView`, `.listStyle(.sidebar)`) already carries Note and Task
top-level sections. This feature adds a third top-level section, **Workspace**, using the same
folder-tree component already used for the Note section — filtered to `.canvas` files, same
disclosure-group/expand-collapse behavior, same card/thumbnail conventions. No new navigation
pattern; this is an additional entry in an existing list, not a structural change.

The canvas content area (right side, when a Workspace is open) gains a **trailing inspector
column** for the new dashboard panel — the same structural slot the existing "Backlink" / "Task
collegati" panels already occupy on the note editor. Toggled via the existing **Vista** menu, not
a new window or sheet.

The Attività section (existing sidebar list) gains a new grouping mode, **Progetti**, alongside
the existing Inbox / Oggi / Progetto / Tutti groupings — selected the same way the existing
groupings are selected (no new UI chrome, just a new list entry).

## Settings layout

No settings change. This feature introduces no new preference.

## Menu bar map

| Menu | Item | Shortcut | Action |
|------|------|----------|--------|
| Task (existing) | Aggiungi sotto-task | Cmd+Shift+Return | Creates a sub-task line under the selected task: auto-assigns `^id` to the parent if absent, assigns the new sub-task's `^parent`, and its own auto-`^id`. |
| Vista (existing) | Pannello Workspace | — (no dedicated shortcut, consistent with Backlink/Task collegati) | Toggles the new trailing inspector panel on the open canvas. |

No other menu bar changes. The Workspace field assignment on a task and the Progetti grouping in
Attività are reached through existing UI (Task detail panel, Attività section), not new menu
items.

## Toolbar items

No new toolbar items. The canvas toolbar and the sidebar toolbar are unchanged by this feature —
the dashboard panel is reached via the Vista menu (see above), consistent with how Backlink/Task
collegati are already reached on notes (no toolbar icon for those either).

## Keyboard shortcuts

| Action | Shortcut | Source |
|--------|----------|--------|
| Aggiungi sotto-task | Cmd+Shift+Return | New — Task menu + task context menu |
| Completa/riapri task | Cmd+Invio | Existing, unchanged |
| Pianifica oggi/domani/+2/settimana | Cmd+0/1/2/3 | Existing, unchanged |
| Pannello Workspace (toggle) | none | New menu item, no shortcut — matches existing Backlink/Task collegati panels |

## Accessibility checklist

- [ ] VoiceOver labels on the new Workspace sidebar section header and its folder-tree rows (reuse the existing note-tree row's accessibility label pattern, substituting "Nota" → "Workspace")
- [ ] VoiceOver labels on the new dashboard panel's two section headers ("Task assegnati", "Note referenziate") and each listed row, consistent with the existing Backlink/Task collegati panel labels
- [ ] VoiceOver label on the "Progetti" grouping's expand/collapse disclosure control and its progress indicator ("3 di 5 completati" spoken form, not a bare fraction)
- [ ] Semantic fonts used throughout (no fixed point sizes) — matches existing app-wide token usage (`font.body`, `font.title`)
- [ ] Cmd+Shift+Return reachable via Task menu even with no toolbar/mouse action, satisfying full keyboard access for "Aggiungi sotto-task"
- [ ] Progress indicator and dashboard panel content are read-only-derived — no interactive control introduced that would need a new focus stop beyond the existing completable checkbox rows (which already carry their own accessibility label)

## Notes for the architect

- No new SwiftUI Scene, no new Window type — every surface here extends an existing container
  (sidebar list, trailing inspector slot, Attività list). Treat this as additive UI, not a new
  navigation structure.
- The trailing dashboard panel should reuse whatever view/container abstraction already backs the
  Backlink/Task collegati panels on the note editor, rather than introducing a second inspector
  mechanism for the canvas — same HIG slot, same interaction pattern, different data source.
- The Workspace sidebar section should reuse the existing folder-tree view component (used today
  for notes) with a file-type filter, not a parallel tree implementation — this keeps the "reuse
  the existing folder browser" decision from the SPEC binding at the architecture level too.
- `Cmd+Shift+Return` is currently unused in the app's shortcut map (confirmed against SPEC §menu
  bar mapping and ShortcutStore-configurable set, line 296) — safe to bind without conflict, but
  the architect/coder should still register it through the existing `ShortcutStore` mechanism
  (user-configurable, per Impostazioni) rather than hardcoding it, consistent with how the existing
  Opt+Cmd+0…3 rescheduling shortcuts are handled.
