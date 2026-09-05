# UX Blueprint — Plaud recording import into Pergamenum

## Window inventory

| Window | Type | SwiftUI Scene / Style | Notes |
|--------|------|-----------------------|-------|
| Main window | WindowGroup (existing) | NavigationSplitView, sidebar + content | Unchanged pattern; gains one sidebar row |
| Recordings review | .sheet (new, on main window) | Form-based, scrollable content | Modal, focused start-to-end flow (review → import or cancel) |
| Settings | Settings (existing) | Existing tabs, unchanged structure | Gains one numeric field in an existing tab |

## Navigation structure

No new navigation pattern. The existing sidebar (`Note`, `Workspace`, `Attività`, `Calendario`)
gains a fifth row, **"Registrazioni"**, placed last — after `Calendario`. Selecting it shows the
recording list in the content area, exactly like the other four sections today. No new column is
introduced; the review flow is a `.sheet` presented over this content area, not a third column,
because it is a bounded, terminal flow (ends in import or cancel) rather than a persistent
browsing surface.

## Settings layout

No new tab. The existing Impostazioni tab that already holds comparable single-purpose numeric/
text fields (the one nearest in spirit to "giorni catalogo") gains one field: **"Giorni
registrazioni Plaud"**, a numeric stepper/text field, default 14. Exact tab placement is an
architect-level detail (whichever existing tab already groups vault/sync-adjacent settings);
no new Settings tab is justified for a single field.

## Menu bar map

| Menu | Item | Shortcut | Action |
|------|------|----------|--------|
| View (or equivalent existing menu) | Aggiorna registrazioni | Cmd+R | Re-fetches `/recordings` for the current vault, only enabled while "Registrazioni" is the active sidebar section |

No new top-level menu. Per-row actions (Elabora/Rivedi/Riprova/Elimina/Rielabora/Apri nota) stay
row-level (button + context menu), not promoted to the menu bar — they act on a specific list item,
not a global mode, matching this app's existing convention for row-scoped actions (e.g. Workspace
folder rename/delete).

## Toolbar items

| Item | Symbol | Placement | Shortcut | Notes |
|------|--------|-----------|----------|-------|
| Aggiorna | `arrow.clockwise` | .primaryAction | Cmd+R | Only toolbar item this feature adds; mirrors the menu entry above |

## Keyboard shortcuts

| Action | Shortcut | Source |
|--------|----------|--------|
| Aggiorna registrazioni | Cmd+R | Toolbar + menu, both wired to the same action |
| Close sheet / Annulla revisione | Esc | Standard sheet dismissal, no custom binding needed |
| Close window | Cmd+W | Auto-provided, unchanged |

Row-level actions (Elabora, Rivedi, Riprova, Elimina, Rielabora, Apri nota) get no dedicated
shortcut — they are contextual to a selected row, consistent with how comparable row actions work
elsewhere in the app (e.g. Workspace board rows).

## Accessibility checklist

- [ ] VoiceOver labels on every row action button (Elabora/Rivedi/Riprova/Elimina/Rielabora/Apri
  nota) — icon-only buttons must not rely on symbol alone.
- [ ] VoiceOver labels on every task checkbox in the review sheet, including the task title so a
  checkbox reads meaningfully out of visual context.
- [ ] Status badges (nuova/in corso/pronta/fallita/importata) exposed as accessible text, not
  color alone.
- [ ] Semantic fonts throughout (no fixed sizes), matching the rest of the app.
- [ ] The review sheet's per-theme sections and task lists reachable via keyboard navigation
  (Tab/arrow keys) without the mouse.

## Notes for the architect

- The review flow's `.sheet` needs its own local `@State`/observable draft (accept/reject per
  task, per-speaker rename text) that survives independently of the sheet being dismissed
  accidentally — this is the same state SPEC.md's R-10 requires to be persisted locally and
  restored on relaunch, not just kept in-memory for the sheet's lifetime.
- The "Registrazioni" section's list view should follow the same row/detail visual language as
  the existing four sidebar sections (list styling, section headers, badge conventions) rather
  than inventing a new visual idiom — no new design tokens needed for this feature.
- Cmd+R must be free in the current key-binding map before wiring it — verify against
  `ShortcutCommand` (the app's existing rebindable-shortcut catalogue) at Step 2, since a
  collision would silently shadow an existing binding.
- The "Elimina" row action reuses the existing Trash-confirmation dialog pattern (role: destructive,
  confirm/cancel), not a new custom alert type.
