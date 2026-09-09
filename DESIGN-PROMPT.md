# Claude Design Prompt — Pratiche

Go to claude.ai/design (Pro/Max/Team/Enterprise plan required — no free-tier access, no
public API). Paste the fenced block below whole. Ask for 7 screens (screen 1 in light and
dark) and share the result with link access; bring the shared URL back to this chain.

```
Pergamenum «Pratiche» — a new pane of Pergamenum, a native, fully offline personal macOS 26 app (SwiftUI) that merges a markdown note vault, a spatial canvas and tasks/calendar. A «pratica» is one matter with one client (an offer, a claim, a negotiation): a vault folder that fills itself from Apple Mail's local store and shows every received and sent message, attachments, and the user's own notes and phone calls as one chronological timeline. Platform: macOS 26 Tahoe, Apple Silicon, one main window with a NavigationSplitView sidebar. UI language: Italian. No network, no account.

Design language (binding): aesthetic reference is Craft — minimal, generous whitespace, hierarchy from weight and space rather than lines and boxes, SF Symbols only, no emoji anywhere in the interface, short animations. Light and dark themes are both first class: design both. Colours and fonts come from W3C DTCG design tokens; use a neutral system palette (system font, SF Symbols) and mark the three new surface tokens explicitly: `surface.received` (left lane), `surface.sent` (right lane), `surface.entry` (manual entries). Direction must never be conveyed by colour alone: also glyph (arrow.down.left / arrow.up.right) and alignment.

Screens / flows:
1. Pratiche pane, main state, LIGHT and DARK (R-23, R-24, R-25, R-26, R-27, R-28, R-30, R-32, R-33). App sidebar on the far left with the LAVORO group showing the new row «Pratiche» (symbol folder.badge.person.crop) selected, placed just before «Registrazioni». Then the pane's own list column (190–320 pt): client folder rows (Rossi S.p.A., Bianchi Srl) with hand-drawn chevrons, pratica rows under them ordered by latest activity («Offerta staffe antivibranti» with a numeric badge 3 and a dot; «Reclamo lotto 2026-07»), a collapsed group «Chiuse» at the bottom, a filter field at the top, and a toolbar row with «Nuova pratica…» (plus) and «Aggiorna ora» (arrow.clockwise). Then the timeline column (min 360 pt), top to bottom: a top bar with breadcrumb «Pratiche › Rossi S.p.A. › Offerta staffe antivibranti», a status pill «Attiva», «Aggiorna ora», a filter field, a «Mittente» menu, a «Solo con allegati» toggle (paperclip), and a trailing «Nota della pratica» inspector toggle (sidebar.trailing); a thin sync progress bar «12 di 80 · Annulla»; a collapsible tray «Da smistare» listing 2 proposed conversations (subject, counterpart, date range, message count, buttons «Aggiungi» default and «Ignora»); the timeline list with sticky day separators («Martedì 10 giugno 2026»). Rows: received messages aligned leading at 70% width on `surface.received`; sent messages aligned trailing at 70% width on `surface.sent`. A collapsed row shows: chevron · time «14:06» · direction glyph · sender «Mario Rossi» · subject in medium weight «Richiesta offerta staffe antivibranti» (the subject is a link that opens the message in Apple Mail) · attachment chips (paperclip + file name, e.g. «offerta-2024-118.pdf», «disegno-staffa.dwg») · first body line truncated in secondary colour. Show exactly one expanded row: body rendered as light markdown (a short paragraph, a 3-row GFM table), a native disclosure «Testo citato» collapsed, a footer with text buttons «Apri in Mail» · «Escludi» · «Sposta in ▸» · «Aggiungi anche a ▸». Show one pending row, dimmed: «Corpo non ancora scaricato da Mail» with an «Apri in Mail» button. Show one manual entry spanning the full width on `surface.entry` with a phone glyph: «15:30 Telefonata · Rossi» and a two-line body containing one task checkbox line. Show a hover affordance between two rows: a hairline with «Inserisci qui». Bottom bar: buttons «Nota» (pencil) and «Telefonata» (phone) and the count «80 messaggi · 3 voci · 14 allegati».
2. Same pane with the Full Disk Access banner and the inspector open (R-18, R-29). Above the tray, a non-modal banner on a warning surface: «Pergamenum non può leggere Mail» with the button «Apri Impostazioni di Sistema» and a «Come fare» disclosure. The trailing inspector column (190–320 pt) shows `pratica.md` in the note editor: frontmatter hidden, the same «## 2026-06-11 15:30 Telefonata · Rossi» heading visible as a page heading with its body and task line.
3. «Nuova pratica…» sheet, all three steps side by side (R-20). Width 560 pt, Form layout. Step 1 «Nome e cliente»: title field, client menu («Rossi S.p.A.», «Nuovo cliente…»), root folder shown read-only «01 Progetti» with a link «Impostazioni». Step 2 «Seme»: three large choice buttons «Dal messaggio selezionato in Mail», «Cerca nella posta…», «Più tardi»; below, after a seed is chosen, the conversation summary («Richiesta offerta staffe antivibranti · 12 messaggi · 4 allegati · 10 giu – 3 set») and removable counterpart chips (m.rossi@rossi-spa.it, ufficio.acquisti@rossi-spa.it, «+ tutto @rossi-spa.it»). Step 3 «Proposte»: a list of same-counterpart conversations with checkboxes, each with subject, date range and count, plus a «Parole chiave» field; footer «Indietro» · «Crea» (default).
4. «Aggiungi a pratica da Mail…» picker sheet (R-21). Header line with the selected Mail message («Re: Richiesta offerta staffe antivibranti — Mario Rossi, oggi 09:12»), a filter field, a list of pratiche grouped by client with the most recent first, and a final row «Nuova pratica…». Footer «Annulla» · «Aggiungi» (default).
5. Settings › Pratiche tab (R-35). The existing Settings window (700×560, tabs across the top; add «Pratiche» as the eleventh tab). Form rows: Cartella radice (path + «Scegli…»), I miei indirizzi (editable list with + / −), Conserva l'originale .eml (toggle on), Soglia allegati (stepper «100 MB»), Finestra proposte (stepper «90 giorni»), Scrivi nel diario (toggle on), Accesso completo al disco (status label «negato» with xmark.circle + button «Apri Impostazioni di Sistema»), Sincronizzazione («Aggiorna tutte le pratiche ora» + «ultima: oggi 09:14»). Must fit without scrolling.
6. Empty state of the pane (R-33). No pratica selected: placeholder text «Scegli una pratica o creane una nuova» with the two buttons «Nuova pratica…» and «Aggiungi da Mail…», no illustration.

Platform constraints (verbatim from UX-BLUEPRINT.md):

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

## Navigation structure

- **Sidebar (column 1, existing):** new row «Pratiche» in the LAVORO group, immediately before «Registrazioni». It is a `Navigation.Pane`, selectable like the other panes. No nested rows in the app sidebar — the pratiche tree lives in the pane's own list column, as notes do.
- **Pane list column (column 2, pane-owned, 190–320 pt):** flat recursive rows per ADR-0024 (no `DisclosureGroup`): client folder rows (chevron drawn by hand, not selectable) → pratica rows (`.tag` = folder path). Ordered by latest activity. Badge = new messages since last open; dot = tray non-empty. Collapsed group «Chiuse» at the bottom (`status-archived`/`status-final`). Filter field at the top. Toolbar row as a sibling of the header (ADR-0022 §D8 trap): «Nuova pratica…», «Aggiorna ora».
- **Content column (column 3, min 360 pt):** the timeline of the selected pratica. Empty selection → placeholder «Scegli una pratica o creane una nuova» with the two buttons.
- **Inspector column (column 4, optional, 190–320 pt):** `pratica.md` opened in the note editor (same editor engine and toolbar-less chrome as the notes inspector's shape), toggled by a toolbar button «Nota della pratica» (`sidebar.trailing`), state in `Navigation` like `isShowingInspector`. Manual entries edited inline in the timeline and in this editor are the same file: edits in one appear in the other on save (the editor buffer is the single source).

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

Non-goals:
- No HTML rendering of email bodies (light markdown text only), no WebView.
- No «Esporta per ChatGPT» or in-app assistant, no «Apri come board» canvas, no URL-scheme entry point — deferred.
- No composing or replying to mail, no contacts, no calendar integration in this feature.
- No new window scenes, no floating panels, no menu bar extra; no tab bar as primary navigation.
- No emoji, no illustrations in empty states, no hard-coded brand colours: neutral system palette plus the three named surface tokens.

Produce 7 screens (screen 1 in light and dark, screens 2–6 in light) at 1440×900 window size and share with link access.
```
