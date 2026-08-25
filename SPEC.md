# SPEC — Universal command surface parity (PG-042)

**Topic slug:** universal-command-surface-parity

## Objectives

Pergamenum's commands are scattered unevenly across three surfaces: the menu bar (with a
keyboard shortcut), toolbars, and per-row context menus. A prior read-only survey of every command
surface in the app found six gap clusters where a command exists on one surface but not on the
others it should reasonably appear on, plus one command family (the drawn-embed delete) with no
discoverable UI at all beyond its shortcut. This feature closes those gaps so that, per row/card/
cell type, every applicable command is reachable both from a toolbar/menu-bar entry point and from
the corresponding right-click context menu — "universal" here means complete for the six identified
clusters, not a claim that every future command will automatically appear everywhere.

## Scope

In scope — six gap clusters plus one net-new command:

1. **Workspace folder row context menu** — add Rinomina and Elimina to the folder row's own
   context menu (today: `WorkspaceBrowserToolbar.swift` toolbar-only, `WorkspaceBrowser.swift`
   right-click shows only Espandi tutto/Comprimi tutto). This revisits ADR-0022 §D8's deliberate
   toolbar-only decision, with the user's informed consent.
2. **Note-row context menu** — add three actions that today exist only as menu-bar items acting on
   "the open note": Copia link, Cronologia, Applica un template.
3. **Task-row context menu** — add "Aggiungi sotto-task" (today: menu-bar/shortcut only, acting on
   the selected task).
4. **Canvas card toolbar** — add board-toolbar equivalents, shown only when a card is selected, for
   actions that today exist only in the card's own context menu: Copia link, Colore, Ridimensiona
   preset, Ritaglia (with Adatta al ritaglio / Rimuovi ritaglio), Elimina.
5. **Editor embed context menu** — add a right-click context menu on a drawn image/PDF embed with
   Elimina, the one command in the app with zero discoverable UI beyond its keyboard shortcut.
6. **Calendar day-cell context menus** — add "Nuovo evento" and "Nuovo promemoria" to the day-cell
   context menus in MonthView, WeekView and MiniCalendar (today: Calendario menu-bar only).
7. **Duplica card (net-new)** — a new command on the canvas card toolbar/context menu that
   duplicates the canvas node only, pointing at the same referenced file, offset from the original
   position. Not a surface-parity fix (the command does not exist anywhere today) — explicitly
   scoped in by the user despite the initial recommendation to defer it.

Out of scope (deliberate exceptions, confirmed during interview):
- Global capture hotkey (Ctrl+Opt+Space) — fires system-wide; a menu entry inside Pergamenum
  would only help while the app is frontmost, so it stays shortcut-only (ADR-0008 §D1 unchanged).
- Cmd+1…Cmd+9 tab switching — not a command in the `ShortcutCommand` catalogue, stays that way.
- Embed resize (drag gesture, ADR-0019) — a continuous gesture, not a discrete command; no menu
  treatment.
- No new context menus are added where a row/cell has none of the six clusters' commands to offer
  (e.g. no blanket "add a context menu to everything").
- No per-namespace tag colours, no unrelated visual redesign of any existing menu.

## Stack

Swift 6, SwiftUI, macOS 26 SDK — same as the rest of the app. AppKit only where already bridged
(canvas, editor `NSTextView`). No new dependency.

## Architecture

- **Note-row actions invoked from a non-open row (cluster 2):** "Apri la nota, poi esegui
  l'azione" — the context menu action opens the note first (same as the existing "Apri" row
  action), then performs Copia link / Cronologia / Applica template against the now-open note.
  These three actions stay conceptually "acts on the open note"; the context menu just adds an
  implicit open step rather than being reimplemented as acting on an arbitrary path.
- **Card toolbar visibility (cluster 4):** the new card-toolbar buttons (Copia link, Colore,
  Ridimensiona, Ritaglia, Duplica) are shown only when exactly a card is selected on the board and
  hidden entirely — not shown-disabled — when no card is selected, matching how Anteprima rapida
  already behaves in that toolbar.
- **Embed context menu (cluster 5):** the new context menu attaches to the embed itself (right
  click on the image/PDF inside the editor), not to a toolbar or menu-bar location — there is no
  natural "selected embed" concept in the editor today, so a toolbar surface is not introduced.
- **Calendar day-cells (cluster 6):** all three calendar surfaces (MonthView, WeekView,
  MiniCalendar) get both new context-menu items identically — no surface-specific variation.
- **Workspace folder row (cluster 1):** the new Rinomina/Elimina context-menu entries call the
  same `VaultController.renameFolder`/`trashFolder` facade the toolbar buttons already call
  (ADR-0022) — no new business logic, only a second UI entry point.
- **Root-folder guard (cluster 1, edge case):** the vault root row does not gain Rinomina/Elimina
  in its context menu at all — consistent with the toolbar, which already disables both on the
  root selection. `FolderFileOperations`'s independent reject-on-root guard is unchanged and
  remains the actual defense; the context menu simply never offers the entries there, so no user
  ever reaches the guard through this new surface.
- **Duplica card (cluster 7) — data model:** duplicating a card means appending a new JSON Canvas
  node to the board's `.canvas` file, same `type: "file"` and same `file` path as the original,
  a new generated `id`, and `x`/`y` offset from the original (small fixed pixel offset, same
  pattern as a manual duplicate-and-drag in Obsidian). `width`/`height` copy the original.
  **No new file is created and no file on disk is touched** — this is "file over app" and
  "rebuildable index" (CLAUDE.md principles 1/3) applied to the canvas: the underlying note/PDF/
  image stays a single file; only the canvas's own node list gains an entry.

## UI flows per cluster

1. **Workspace folder row:** right-click a folder row (not the vault root) → context menu gains
   Rinomina and Elimina below the existing Espandi tutto/Comprimi tutto, same icons/behavior as
   the toolbar buttons.
2. **Note row:** right-click any note row → context menu gains Copia link, Cronologia, Applica
   template. Selecting one from a row that is not the currently open note first opens that note
   (replicating the existing "Apri" behavior), then performs the action.
3. **Task row:** right-click a task row → context menu gains "Aggiungi sotto-task", acting on that
   row's task exactly as the existing menu-bar/shortcut version acts on the selected task.
4. **Canvas card:** select a card on the board → the board's own toolbar (not the sidebar
   toolbar) shows new buttons for Copia link, Colore, Ridimensiona, Ritaglia (context-sensitive:
   shows Adatta al ritaglio/Rimuovi ritaglio depending on crop state), Duplica. Deselecting the
   card hides all of them.
5. **Editor embed:** right-click a drawn image/PDF embed in the editor → new context menu with
   Elimina, performing the same atomic delete the Backspace shortcut already does.
6. **Calendar day-cell:** right-click an empty day cell in MonthView, WeekView, or MiniCalendar →
   context menu gains "Nuovo evento" and "Nuovo promemoria", pre-filling that day, matching the
   Calendario menu-bar versions.
7. **Duplica card:** invoke Duplica (card toolbar button or card context menu) on a selected
   canvas card → a new card appears on the same board, offset from the original, referencing the
   same underlying file.

## Edge cases

- **Duplica card on a card whose referenced file no longer exists on disk:** the duplicate is
  still created (same missing-file reference as the original) — the canvas node is a pointer, and
  Pergamenum's existing missing-file card rendering (broken-file placeholder) already handles this
  case for the original card; the duplicate renders identically. No special-cased error path.
- **Root-folder row (cluster 1):** Rinomina/Elimina are absent from its context menu entirely (see
  Architecture above) — never shown, never disabled-and-shown.
- **Card toolbar with no selection (cluster 4):** the new buttons are hidden, not disabled (see
  Architecture above).
- **Note-row actions on an already-open note (cluster 2):** no implicit re-open — the action runs
  directly against the currently open note, same as invoking it from the menu bar today.
- Every new context-menu entry follows the existing per-surface convention for disabled vs.
  hidden that surface already uses elsewhere (e.g. the folder row already hides rather than
  disables inapplicable entries) — no new convention is introduced by this feature.

## UI/UX conventions

- SF Symbols coherent with the icons already used for the same command elsewhere in the app (the
  toolbar icon for a given command is reused verbatim in its new context-menu appearance, and vice
  versa) — no new icon choices.
- No emoji, Craft-aesthetic spacing, W3C DTCG tokens only for any new color use (CLAUDE.md Design
  system section) — applies to the card-toolbar buttons and any new menu styling.
- Italian UI strings, English code/comments/commits (project convention, unchanged).

## Success criteria

- [ ] R-01 — Il context menu della riga cartella Workspace (non radice) offre Rinomina ed
      Elimina, con lo stesso comportamento dei pulsanti toolbar esistenti (ADR-0022).
- [ ] R-02 — Il context menu della riga cartella Workspace sulla radice del vault NON mostra
      Rinomina/Elimina.
- [ ] R-03 — Il context menu della riga nota offre Copia link, Cronologia e Applica template.
- [ ] R-04 — Invocare una delle tre azioni della riga nota (R-03) da una nota non aperta apre
      prima la nota, poi esegue l'azione.
- [ ] R-05 — Il context menu della riga task offre "Aggiungi sotto-task", con lo stesso
      comportamento dello shortcut/menu esistente.
- [ ] R-06 — La toolbar del board mostra Copia link, Colore, Ridimensiona, Ritaglia (con
      Adatta al ritaglio/Rimuovi ritaglio) e Duplica quando una card è selezionata.
- [ ] R-07 — I pulsanti di R-06 sono nascosti (non disabilitati) quando nessuna card è
      selezionata.
- [ ] R-08 — L'embed immagine/PDF nell'editor ha un context menu proprio con Elimina, che esegue
      lo stesso delete atomico dello shortcut Backspace esistente.
- [ ] R-09 — MonthView, WeekView e MiniCalendar offrono "Nuovo evento" e "Nuovo promemoria" nel
      context menu della cella giorno, identici tra loro.
- [ ] R-10 — Duplica card crea un nuovo nodo canvas che referenzia lo stesso file dell'originale,
      senza creare né duplicare alcun file su disco.
- [ ] R-11 — Duplica card su una card con file mancante crea comunque il duplicato, che mostra lo
      stesso placeholder "file mancante" dell'originale.
- [ ] R-12 — Nessuna regressione nei context menu e nelle toolbar esistenti (manual QA pass su
      tutte le sei superfici toccate).
- [ ] R-13 — Ogni nuova voce di menu/toolbar usa lo stesso SF Symbol già in uso per lo stesso
      comando altrove nell'app.
- [ ] R-14 — La suite unit passa (`-only-testing:PergamenumTests`) e il build `perg`
      (`Sources/Core`/`Sources/Connector`) non regredisce (no import SwiftUI introdotto in quei
      target).
