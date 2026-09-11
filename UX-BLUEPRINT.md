# UX Blueprint — Pratiche

Scope: the «Pratiche» feature only (SPEC.md, topic slug `pratiche`). The app shell — one
`WindowGroup`, `NavigationSplitView` with a three-group sidebar, the `Settings` scene with
`TabView`, `MenuCommands`, the rebindable `ShortcutCommand` catalogue, ADR-0023's
"declare once, render on every surface" — is existing and is not redesigned here. Everything
below plugs into it the way `Registrazioni` (ADR-0032) did.

## Window inventory

| Window | Type | SwiftUI Scene / Style | Notes |
|--------|------|-----------------------|-------|
| Main window, «Pratiche» pane | existing `WindowGroup` | `NavigationSplitView` sidebar → pane content composed as `VaultBrowser` is: top bar + `HSplitView` (list column · timeline column · inspector column) | New `Navigation.Pane.pratiche`. The pane owns its own list column (pratiche tree), like Note owns `NoteListPane`. |
| «Nuova pratica…» | `.sheet` on the main window | Three-step sheet, fixed width 560, height adapts per step, `Form` root | Steps 1 Nome e cliente · 2 Seme · 3 Proposte. Modal on purpose: the seed reads Mail's selection and the user must not change it mid-flow. |
| «Aggiungi a pratica da Mail…» | `.sheet` | Single-step picker: list of pratiche (recent first, filter field) + «Nuova pratica…» row that hands off to the wizard with the seed pre-filled | Reached from Inserisci menu, sidebar toolbar, row context menu, and Cmd+Shift+P. |
| «Cerca nella posta…» (picker) | `.sheet` on top of the wizard (step 2) or standalone from the tray | `Table`/`List` of conversations with search field and period picker, multi-select | Same component both places. |
| Elimina pratica | `.alert` | Destructive «Elimina» (`.destructive`), «Annulla» default (`.cancel`), Esc cancels | Only alert in the feature. |
| Rigenera messaggio | `.sheet` | Unified diff preview (reuses `UnifiedDiff` rendering) with «Rigenera» / «Annulla» | Shown only when the `.md` differs from what would be regenerated. |
| Settings › Pratiche | existing `Settings` scene | Eleventh `tabItem`, `Form` root, no `ScrollView` | Window frame is 700×560 today; the tab must fit in that height (seven rows + one status row: fits). The toolbar collapse threshold noted in `SettingsView.swift` must be re-verified with eleven tabs. |
| Quick Look | system panel | existing `QuickLook` feature | Attachment chips call the same panel Workspace cards use. |

No new `Window` scene, no floating panel, no `MenuBarExtra`.

## Navigation structure

- **Sidebar (column 1, existing):** new row «Pratiche» in the LAVORO group, immediately before
  «Registrazioni». It is a `Navigation.Pane`, selectable like the other panes. No nested rows in
  the app sidebar — the pratiche tree lives in the pane's own list column, as notes do.
- **Pane list column (column 2, pane-owned, 190–320 pt):** flat recursive rows per ADR-0024
  (no `DisclosureGroup`): client folder rows (chevron drawn by hand, not selectable) → pratica rows
  (`.tag` = folder path). Ordered by latest activity. Badge = new messages since last open; dot =
  tray non-empty. Collapsed group «Chiuse» at the bottom (`status-archived`/`status-final`).
  Filter field at the top. Toolbar row as a sibling of the header (ADR-0022 §D8 trap): «Nuova
  pratica…», «Aggiorna ora».
- **Content column (column 3, min 360 pt):** the timeline of the selected pratica. Empty
  selection → placeholder «Scegli una pratica o creane una nuova» with the two buttons.
- **Inspector column (column 4, optional, 190–320 pt):** `pratica.md` opened in the note editor
  (same editor engine and toolbar-less chrome as the notes inspector's shape), toggled by a
  toolbar button «Nota della pratica» (`sidebar.trailing`), state in `Navigation` like
  `isShowingInspector`. Manual entries edited inline in the timeline and in this editor are the
  same file: edits in one appear in the other on save (the editor buffer is the single source).
- Focus mode (`isNotesFocused` equivalent): Cmd+Shift+F already toggles concentrazione elsewhere;
  in this pane it hides list and inspector columns and leaves the timeline.

### Timeline column anatomy (top to bottom)

1. **Top bar** (pane-level, like `VaultTopBar`): breadcrumb `Pratiche › <Cliente> › <Pratica>`,
   status pill (Attiva / In attesa / Chiusa, click = menu to change), «Aggiorna ora», filter field,
   sender menu, «Solo con allegati» toggle, «Nota della pratica» inspector toggle.
2. **Full Disk Access banner** (conditional): one line + «Apri Impostazioni di Sistema» + «Come
   fare» disclosure. Token colour `warning` background. Never modal.
3. **Sync progress** (conditional): 2 pt bar + «12 di 80» + «Annulla».
4. **«Da smistare» tray** (conditional, collapsible, remembers collapsed state per window):
   rows = proposed conversations with subject, counterpart, date range, count, «Aggiungi»
   (default button) / «Ignora».
5. **Timeline list**: `List` with sticky day separators (`Section` headers). Rows:
   - Message row, collapsed: `[chevron] 14:06  Mario Rossi   Richiesta offerta staffe…  📎2  «Buongiorno Stefano, …»`.
     Received rows aligned leading at 70 % width, sent rows aligned trailing at 70 % width, lane
     background from tokens (`surface.received`, `surface.sent` — new tokens), direction glyph
     `arrow.down.left` / `arrow.up.right` beside the time for colour-blind users.
   - Message row, expanded: body as `MarkdownBlocksView`, «Testo citato» native disclosure,
     footer buttons «Apri in Mail» · «Escludi» · «Sposta in ▸» · «Aggiungi anche a ▸».
   - Pending row: dimmed, «Corpo non ancora scaricato», «Apri in Mail» button.
   - Not-in-Mail row: subject as plain text + caption «non più in Mail».
   - Manual entry row (full width, token `surface.entry`): glyph `phone` / `pencil`, time,
     title, body editable inline (text view bound to the heading's range in `pratica.md`).
   - Gap affordance: hovering the space between two rows shows a hairline with «Inserisci qui»;
     click inserts an entry at the midpoint timestamp.
6. **Bottom bar**: «Nota» and «Telefonata» buttons (primary actions of the timeline), count
   «80 messaggi · 3 voci · 14 allegati».

Attachment chips: click = Quick Look, double-click = open with default app, context menu =
«Mostra nel Finder», «Copia», «Apri con ▸». Over-threshold chip shows `icloud.slash` and a
tooltip with the size.

## Settings layout

Tab «Pratiche» (`folder.badge.person.crop`, or `tray.full` if unavailable), `Form` root:

| Row | Control |
|-----|---------|
| Cartella radice | path label + «Scegli…» (NSOpenPanel, folders only, inside the vault) |
| I miei indirizzi | editable list (add/remove), pre-filled from the index |
| Conserva l'originale `.eml` | toggle, default on |
| Soglia allegati | stepper + unit «MB», default 100 |
| Finestra proposte | stepper + unit «giorni», default 90 |
| Scrivi nel diario | toggle, default on |
| Accesso completo al disco | status `Label` («concesso» / «negato») in the style of the calendar tab + «Apri Impostazioni di Sistema» |
| Sincronizzazione | «Aggiorna tutte le pratiche ora» + last sync timestamp |

Fits 560 pt without scrolling. Shortcuts stay in Impostazioni › Scorciatoie (existing tab).

## Menu bar map

| Menu | Item | Shortcut | Action |
|------|------|----------|--------|
| File | Nuova pratica… | Cmd+Opt+P | Opens the wizard (any pane; switches to Pratiche on create) |
| Inserisci | Aggiungi a pratica da Mail… | Cmd+Shift+P | Reads Mail's selection, opens the pratica picker sheet |
| Vista | Pratiche | (existing pane switching shortcut scheme) | Shows the pane |
| Vista | Mostra/Nascondi nota della pratica | Cmd+Opt+I (verify free; else none) | Toggles the inspector column in this pane |
| Vista | Espandi tutto / Comprimi tutto | Opt+Space (timeline focused, not a menu shortcut) | Row expansion |
| Pratica (context menu of a row, also under Vista › Pratica submenu) | Apri, Rinomina…, Chiudi/Riapri, Aggiorna ora, Mostra nel Finder, Elimina… | — | ADR-0023: same catalogue, three surfaces |
| Messaggio (row footer + context menu) | Apri in Mail, Anteprima allegato, Escludi dalla pratica, Sposta in ▸, Aggiungi anche a ▸, Rigenera… | Return, Cmd+Return, Backspace, —, —, — | keys apply when the timeline has focus |

All shortcuts are `ShortcutCommand` cases (rebindable in Impostazioni › Scorciatoie). System-level
freedom of Cmd+Opt+P and Cmd+Shift+P is checked at wiring time against
`com.apple.symbolichotkeys`, as ADR-0032 did for Cmd+R.

## Toolbar items

| Item | Symbol | Placement | Shortcut | Notes |
|------|--------|-----------|----------|-------|
| Nuova pratica… | plus | pane list column toolbar row | Cmd+Opt+P | File menu twin |
| Aggiorna ora | arrow.clockwise | list column toolbar row + timeline top bar | — (toolbar/menu only, deliberate) | Spins during sync |
| Nota della pratica | sidebar.trailing | timeline top bar, trailing | Cmd+Opt+I if free | Vista menu twin |
| Filtro | magnifyingglass field | timeline top bar | Cmd+F when the pane has focus | Esc clears |
| Mittente | person menu | timeline top bar | — | Filter |
| Solo con allegati | paperclip toggle | timeline top bar | — | Filter |
| Nota / Telefonata | pencil / phone | timeline bottom bar | — (buttons + context menu on gap) | Primary create actions of the timeline |

Filters and «Aggiorna ora» are toolbar/menu-only by decision: they are not verbs a person
performs blind from the keyboard.

## Keyboard shortcuts

| Action | Shortcut | Source |
|--------|----------|--------|
| Nuova pratica… | Cmd+Opt+P | File menu + list toolbar |
| Aggiungi a pratica da Mail… | Cmd+Shift+P | Inserisci menu + toolbar + context menu |
| Move focus between rows | Up / Down | timeline |
| Expand / collapse focused row | Space | timeline |
| Expand / collapse all | Opt+Space, Opt+click on any chevron | timeline |
| Open focused message in Mail | Return | timeline (= subject click) |
| Quick Look first attachment | Cmd+Return | timeline |
| Exclude focused message (undoable) | Backspace | timeline |
| Undo exclude / move | Cmd+Z | window undo manager (ADR-0026 precedent) |
| Focus filter field | Cmd+F | pane |
| Clear filter / leave field | Esc | pane |
| Toggle inspector | Cmd+Opt+I (if free) | Vista menu + toolbar |
| Settings | Cmd+, | existing |
| Close window | Cmd+W | existing |

## Accessibility checklist

- [ ] Every message row is one accessibility element with a composed label:
      «Ricevuta, 10 giugno 14:06, Mario Rossi, Richiesta offerta staffe antivibranti, 2 allegati,
      compressa» (direction, date, sender, subject, attachment count, state); value = first line;
      actions: Espandi/Comprimi, Apri in Mail, Escludi.
- [ ] Chevron, chips, footer buttons and tray buttons carry `accessibilityLabel`s.
- [ ] Stable `accessibilityIdentifier`s, never label text (UI-test rule of this repo):
      `pratiche-pane`, `pratiche-list`, `pratiche-row-<slug>`, `pratiche-new`, `pratiche-refresh`,
      `pratiche-filter`, `pratiche-sender-menu`, `pratiche-attachments-only`,
      `pratiche-inspector-toggle`, `pratiche-fda-banner`, `pratiche-fda-open-settings`,
      `pratiche-sync-progress`, `pratiche-sync-cancel`, `pratiche-tray`,
      `pratiche-tray-row-<conversationID>`, `pratiche-tray-add-<id>`, `pratiche-tray-ignore-<id>`,
      `pratiche-timeline`, `pratiche-message-<messageIDHash>`, `pratiche-message-chevron-<hash>`,
      `pratiche-message-subject-<hash>`, `pratiche-attachment-<hash>-<n>`,
      `pratiche-entry-<timestamp>`, `pratiche-add-note`, `pratiche-add-call`,
      `pratiche-insert-here-<index>`, `pratiche-wizard`, `pratiche-wizard-title`,
      `pratiche-wizard-client`, `pratiche-wizard-seed-mail`, `pratiche-wizard-seed-search`,
      `pratiche-wizard-seed-later`, `pratiche-wizard-proposal-<id>`, `pratiche-wizard-keywords`,
      `pratiche-wizard-create`, `pratiche-picker`, `pratiche-picker-row-<slug>`,
      `pratiche-delete-alert`, `settings-pratiche-*` per row.
- [ ] Semantic fonts through tokens only (`font.body`, `font.caption`, prose faces for bodies);
      no fixed point sizes; Dynamic Type respected.
- [ ] Lane colour is never the only direction cue: glyph + alignment + label word.
- [ ] Full keyboard path for every action listed above; focus ring visible on rows and chips.
- [ ] Increase Contrast and both themes verified on lanes, entry colour, banner, dimmed pending row.
- [ ] Reduce Motion: no slide animation on expand; opacity only.

## Notes for the architect

- **Pane composition mirrors `VaultBrowser`** (top bar above an `HSplitView` of list · content ·
  inspector), not `RecordingsPane` (single column). The pane-owned list column is what keeps the
  app sidebar flat.
- **Two new surface tokens** (`surface.received`, `surface.sent`, `surface.entry`) join the theme
  JSON for light and dark; the binding rule (no hardcoded colours) applies to lanes.
- **Sheets, not windows**: wizard, picker, add-to-pratica picker and regenerate diff are `.sheet`.
  The wizard is modal by design because the Mail selection it reads must stay stable.
- **Exclude is undoable, not confirmed**: registers on the window's `@Environment(\.undoManager)`
  (ADR-0026 precedent); the only alert is «Elimina pratica» with a destructive role and cancel
  default. Backspace maps to Escludi only when the timeline has key focus, never in the inspector
  editor.
- **Inline entry editing and the inspector share one buffer**: an entry edited in the timeline
  is a range of `pratica.md`; the architect must decide the single owner (recommendation: the
  same `VaultController` editor buffer, with the timeline view binding to heading ranges) so the
  two never diverge.
- **The Settings tab count crosses eleven**: the toolbar-collapse threshold measured at 620 pt for
  eight tabs must be re-measured at 700 pt with eleven; if it collapses, widen the window rather
  than nesting the tab.
- **UI tests**: launch with `-mailStoreRoot <fixture>` plus the existing `-disableCalendar YES
  -disableUpdater YES`; find every control by the identifiers above.
