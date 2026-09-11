# Design — Pratiche

Source: Claude Design (claude.ai/design)
Shared URL: https://claude.ai/design/p/feb088be-b3b7-4363-81e0-f9453868ce07?file=Pergamenum+Pratiche.dc.html
URL shape check: valid
Captured: 2026-09-09T00:00:00+02:00
Prompt: DESIGN-PROMPT.md
Local export: docs/design/pratiche/Pergamenum Pratiche.dc.html (plus its runtime `support.js`; fetched through the DesignSync tool, project "UI mockups for instruction prompt", type PROJECT_TYPE_PROJECT)
Handoff bundle: none

## Screens

| Screen | Purpose | SPEC ids | Notes |
|--------|---------|----------|-------|
| 1a Pratiche · stato principale · chiaro | The pane: app sidebar (Pratiche selected in LAVORO before Registrazioni), pane list column (Rossi S.p.A. › Offerta staffe antivibranti [badge 3], Reclamo lotto 2026-07; Bianchi Srl › Trattativa quadro 2026; «Chiuse 7»), timeline with breadcrumb, status pill «Attiva», filters, progress «12 di 80 · Annulla», tray «Da smistare · 2 conversazioni proposte» with Aggiungi/Ignora, sticky day separator, collapsed/expanded/pending rows in two lanes, Telefonata entry, «Inserisci qui» gap, bottom bar Nota/Telefonata + counts | R-18, R-23, R-24, R-25, R-26, R-27, R-28, R-30, R-32, R-33 | 1440×900, columns sidebar 220 · list 260 · timeline flexible (min 360) · inspector 280 |
| 1b Pratiche · stato principale · scuro | Same as 1a in dark | R-39 | Both lane surfaces and entry surface re-tinted for dark |
| 1c Banner Accesso completo al disco + inspector aperto | Non-modal banner «Pergamenum non può leggere Mail» with «Come fare» and «Apri Impostazioni di Sistema»; trailing inspector showing `pratica.md` | R-18, R-29 | Light only; dark variant listed by the design as a next step |
| 1d Sheet «Nuova pratica…» | Three steps side by side, 560 pt: Nome e cliente (Titolo, Cliente menu, Cartella radice + link Impostazioni) · Seme (three choice buttons, conversation summary, counterpart chips incl. «tutto @rossi-spa.it») · Proposte (checkbox list of same-counterpart conversations, «Parole chiave») with Annulla/Indietro/Continua/Crea footers | R-20 | «PASSO n DI 3» eyebrow label per step |
| 1e Sheet «Aggiungi a pratica da Mail…» | Header with the selected Mail message, «Filtra pratiche», pratiche grouped by client with «Ultima attività … · N messaggi», final row «Nuova pratica…», footer Annulla/Aggiungi | R-21 | Shown over the empty-state pane |
| 1f Impostazioni › Pratiche | Eleventh tab: Cartella radice, I miei indirizzi (list), Conserva l'originale .eml, Soglia allegati 100 MB, Finestra proposte 90 giorni, Scrivi nel diario, Accesso completo al disco «negato» + button, Sincronizzazione «Aggiorna tutte le pratiche ora · ultima: oggi 09:14» | R-35 | Fits 700×560 without scrolling |
| 1g Stato vuoto del pannello | «Scegli una pratica o creane una nuova» + «Nuova pratica…» / «Aggiungi da Mail…» | R-33 | No illustration |

## Binding decisions

- Column widths for the pane: app sidebar 220 pt, pane list 260 pt, timeline flexible with minimum 360 pt, inspector 280 pt (within UX-BLUEPRINT's 190–320 ranges).
- Three surface tokens, light/dark each: `surface.received` neutral grey (left lane), `surface.sent` cool tint (right lane), `surface.entry` warm tint (manual entries). Direction is always redundant: glyph + alignment + lane.
- Lane rows at ~70% width aligned leading (received) / trailing (sent); manual entries full width.
- Message row anatomy as in 1a: chevron · time · sender · subject (link) · attachment chips · first line; expanded row adds the markdown body, a «Testo citato» disclosure and the footer «Apri in Mail · Escludi · Sposta in ▸ · Aggiungi anche a ▸».
- Tray «Da smistare» sits above the timeline as a collapsible strip with a count subtitle; each proposal shows subject, address, date range, count, and Aggiungi (default) / Ignora.
- Sync progress is a thin bar with «n di N · Annulla» under the top bar.
- Full Disk Access banner is inline, above the tray, never modal; carries «Come fare» disclosure and the System Settings button.
- Wizard uses an eyebrow «PASSO n DI 3», a Form layout and footers Annulla/Continua, Indietro/Continua, Indietro/Crea.
- Status pill in the breadcrumb bar shows the pratica's `status-*` and is the affordance for changing it.
- Settings tab row set and order exactly as 1f, including the «Sincronizzazione» row.
- Empty state is text plus two buttons, no illustration.

## Not decided here

- Dark variant of 1c (banner + inspector), the «Cerca nella posta…» picker sheet, and the «Elimina pratica» alert were not drawn (the design lists them as next steps); UX-BLUEPRINT.md governs them.
- Hover/pressed states of buttons and the selected-row accent were not drawn.
- The drawn glyphs are placeholders for SF Symbols; exact symbol names come from UX-BLUEPRINT.md and the implementation.
- Exact hex values in the export are mockup colours, not the token values: tokens are defined in the theme JSON files during implementation and must satisfy contrast in both themes.
