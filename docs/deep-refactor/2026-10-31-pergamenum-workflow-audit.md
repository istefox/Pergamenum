# Pergamenum — workflow audit (step 2 of 4)

Date: 2026-10-31 · Tree: branch `feat/pg-427-pg-428-underscore-concealment-daily-transclusions`
(`023c8d87`, on `main` `54cf47e7`) · Scope: how the app is *operated*: steps per task, where
each verb sits, what it is called, which key reaches it. Nothing was built or run. **[fact]** rows
were read at the cited file and line; **[assumption]** rows are inferences about a person at the
keyboard, including every KLM time. Input: `2026-10-30-pergamenum-surface-inventory.md` (step 1)
plus targeted reads.

Subordinate to `docs/20260811_Pergamenum_SpecApp.md` and to `CLAUDE.md`. No recommendation adds a
network call, a storage schema or a frontmatter key.

## 0. Relation to the October note-workflow audit

`docs/20261002_Pergamenum_NoteWorkflowReport.md` covered the life of a *note* (rendering, links,
birth). Its milestones shipped: N1/N2 (PG-384, PG-385), N3 links (PG-386: ADR-0083, ADR-0084),
N4 birth (PG-387: ADR-0080, ADR-0085, ADR-0086, ADR-0088), N5 constructs (ADR-0087). None of
those items is repeated here. This audit covers what the October one did not: tasks, Oggi /
Settimana / Mese, Diario, Pratiche, Contenitore, Workspace, Settings, and above all the
**consistency across surfaces**: the same verb, name, position and key everywhere.

## 1. Method

Three rules from Taylor's scientific management, translated to a single-user desktop app:

1. **One best way, standardised.** Each operation has one name, one position, one key. Two names
   for one action (§3 W-03) or two orders for one pair of buttons (§3 W-02) force a person to
   re-read instead of acting. Standardisation is the cheapest speed-up there is.
2. **Separate planning from execution.** Pergamenum already does this well for notes: capture
   now (Ctrl+Opt+Space, no decisions), classify later («Da classificare», «Classifica»). The
   proposals extend the same split to documents and tasks rather than invent a new one.
3. **Measure, then cut.** Each core task below is counted in actions (a click, a chord, a typed
   field, a pointing move) with a Keystroke-Level Model estimate (K 0.28 s, P 1.1 s, B 0.1 s,
   M 1.35 s mental preparation, H 0.4 s hand move). Hick's law argues for fewer, grouped choices in
   menus; Fitts's law for keeping frequent targets large and at fixed edges.

## 2. Core workflows, counted

| # | Task | Today: steps (actions) | KLM today [assumption] | Proposed | KLM proposed [assumption] | Finding |
|---|---|---|---|---|---|---|
| 1 | Capture a thought from another app | Ctrl+Opt+Space, type, Return (3) | ≈ 3.5 s + typing | unchanged | — | sound |
| 2 | New note inside the app | Cmd+N, title, (folder, template, topic), Return (3–6) | 4–9 s | unchanged; folder pre-filled from the selected tree folder | −1 P | W-12 |
| 3 | Schedule the selected task for today | row «Porta a oggi» (2) or Cmd+Opt+0 (1) | 2.6 s / 1.6 s | unchanged; one name | — | W-03 |
| 4 | Block time on Diario | drag on the timeline, sheet, Salva (4) or «Nuovo blocco», 3 pickers, Salva (6) | 6 s / 10 s | drag stays primary; the toolbar button pre-fills the next free slot | −2 P | sound / W-14 |
| 5 | Go to yesterday on Diario | click «Giorno precedente» (2) | 2.6 s | Cmd+Left, as on Oggi (1) | 1.6 s | W-01 |
| 6 | File a document dropped in the Contenitore | select, «Classifica…» (Cmd+Opt+K), topic, type, Return (5) | 8 s | unchanged keys; one «Classifica» shortcut for notes and documents | — | W-07 |
| 7 | Add a Mail thread to a pratica | Cmd+Shift+P, filter, pick, Aggiungi (4) | 7 s | unchanged | — | sound |
| 8 | Resolve a conflict after an external edit | read banner, pick button (2) | 3 s, + M when the order differs by surface | one wording, one order | −1 M | W-02 |
| 9 | Refresh the external source of the current pane | Pratiche «Aggiorna ora» click; Oggi «Aggiorna da EventKit» click; Registrazioni Cmd+R; Contenitore only from Settings (2–5) | 2–8 s | Cmd+R everywhere, same toolbar slot | 0.6 s | W-08 |
| 10 | Open the inspector of the current object | Note Cmd+Opt+I; Pratiche top-bar «Nota della pratica»; Contenitore always on; Workspace tray «Nuovi elementi» (1–2) | 1–3 s | Cmd+Opt+I and one trailing toolbar slot everywhere | 0.6 s | W-06 |
| 11 | Create the pane's primary object | Note toolbar «+» or Cmd+N; Workspace tree-footer «Nuova board…»; Pratiche list-header «+»; Contenitore sidebar-header «+»; Oggi toolbar «Nuovo task»; Diario toolbar «Nuovo blocco» | 2–3 s, + M to find the button | one leading toolbar slot, Cmd+N bound per pane context | −1 M | W-05 |
| 12 | Switch to a pane by keyboard | Ctrl+Cmd+digit or letter, order unrelated to the sidebar (1, + M to recall) | 1.9 s | digits follow sidebar order | 0.6 s with practice | W-09 |

Takeaway: the long flows are already short. Most of the time a person loses goes to the mental M
operator: recalling which name, which corner and which key *this* pane uses. That is where the
findings below are.

## 3. Findings (P1 → P4)

### W-01 — Cmd+Left/Cmd+Right and «Vai a oggi» move Oggi's date from any pane, and may take line navigation from the editor
- Where: `Sources/Core/Shortcuts/ShortcutCommand.swift:383`, `Sources/App/CommandActions.swift:337-340`, `Sources/App/CommandActions+CanRun.swift:69`, `Sources/Features/Diary/DiaryToolbar.swift:25-48`
- Category: workflow / correctness · Severity: P2 · Confidence: confirmed for the scope, suspected for the editor
- What: «Giorno precedente/successivo» are menu key equivalents always enabled, and they call `day.moveSpan`, the Oggi controller. On Diario, whose own toolbar has the same three buttons, the keys move a pane that is not shown and Diario stays put. Cmd+Left and Cmd+Right are also the system text-view bindings for line start and line end; a main-menu key equivalent is matched before `keyDown` reaches an `NSTextView`, so in a note the keys probably change Oggi's day instead of moving the caret. Nothing in `Sources/Features/Editor` intercepts them.
- Trigger: open a note, put the caret mid-line, press Cmd+Left → expected caret at line start; suspected: caret unmoved and Oggi one day back. On Diario, press Cmd+Left → Diario unchanged.
- Fix: enable the two commands only while Oggi or Diario is the pane and route them to that pane's controller; never while a text view is first responder. Hand check first: the editor half is unverified.
- Tracked: none

### W-02 — Three conflict banners, three wordings, two button orders
- Where: `Sources/Features/Editor/ConflictBannerCopy.swift:19-25`, `Sources/Features/Diary/DiaryView+Conflict.swift:16-18`, `Sources/Features/Workspace/BoardChrome.swift:57-61`
- Category: workflow consistency · Severity: P2 · Confidence: confirmed
- What: note and Diario say «Ricarica da disco» then «Tieni la mia versione». The board says «Mantieni le mie modifiche» then «Ricarica dal disco»: a different verb, a different preposition and the reverse order. The banner exists for the most dangerous moment the app has, and the button a person reaches for by position does the opposite thing on the board.
- Fix: one `ConflictBannerCopy`-style value shared by the three banners, one order (accept the disk version first, keep mine second), one component.
- Tracked: none

### W-03 — One action, two names: «Porta a oggi» and «Pianifica oggi»
- Where: `Sources/Features/Tasks/TasksView+Row.swift:50` and `:170` (same row: button vs context menu), `Sources/Features/Today/DayReferences.swift:126`, `Sources/Features/Tasks/LinkedTasksPanel.swift:96`, `Sources/Features/Tasks/TasksView.swift:114`, `Sources/Core/Shortcuts/ShortcutCommand.swift:265`, `Sources/Features/Settings/TaskSettings.swift:42`
- Category: workflow consistency · Severity: P3 · Confidence: confirmed
- What: all six call `apply(.schedule(.today))`. The Task menu and the context menus say «Pianifica oggi», the inline buttons and the Settings help say «Porta a oggi». A person learning from one place cannot find it by name in the other.
- Fix: one title, from `ShortcutCommand.taskToday.title`, used by every site (the ADR-0023 "named once, rendered twice" rule already says this). Keep «Pianifica oggi»: it matches «Domani», «+2 giorni», «Settimana prossima» in the same menu.
- Tracked: none

### W-04 — Delete verbs and confirmations differ by object
- Where: note, folder, board, Contenitore, recording: «Sposta nel Cestino» with a confirmation (`NoteListPane.swift:215-236`, `WorkspaceBrowser.swift:183-203`, `RecordingsPane.swift:81`); pratica: «Elimina» with a message saying it goes to the Cestino (`PratichePane.swift:93-109`); category: «Elimina», no confirmation, no undo (`CategorySidebarSection.swift:176`, `VaultSession+Categories.swift:68-70`); Diario card: «Elimina», no confirmation (`DiaryEntryCard.swift:103`)
- Category: workflow consistency · Severity: P3 · Confidence: confirmed
- What: the same reversible trash operation is called two names, and two irreversible in-app removals ask nothing. A category delete drops the registry entry (colour, parent, home note) with one click; the tasks keep the tag, so it degrades to an implicit category rather than losing data, but the registry fields are gone.
- Fix: a three-rule contract (§4 C-05): to the Finder Trash → «Sposta nel Cestino…» with confirmation; removed for good → «Elimina…» with confirmation; reversible inside the app → no dialog, an undo toast.
- Tracked: none

### W-05 — The primary «create» verb lives in a different corner of every pane
- Where: Note: window toolbar «Nuova nota» and the list footer toolbar (`VaultBrowser.swift:96-127`, `NoteListToolbar.swift:32-62`); Workspace: tree footer only (`WorkspaceBrowserToolbar.swift:35-68`); Pratiche: list header «+» (`PraticheListColumn.swift:36-50`); Contenitore: sidebar header «+» (`ContenitoreSidebar.swift:25-39`); Oggi: toolbar primary «Nuovo task» (`DayToolbar.swift:69`); Diario: toolbar primary «Nuovo blocco» (`DiaryToolbar.swift:53`)
- Category: workflow placement · Severity: P3 · Confidence: confirmed
- What: four different positions (window toolbar, list footer, list header, sidebar header) for the same idea. Fitts favours a fixed edge target; Hick favours one learned location.
- Fix: the pane's primary create verb is the first item of the window toolbar's primary group in every pane; the list-local «+» may stay as a duplicate at the list foot (macOS source-list convention), never as the only entry point. Cmd+N creates the pane's primary object (§4 C-08).
- Tracked: none

### W-06 — The inspector has four shapes and three toggles
- Where: Note: toolbar toggle «Ispettore», Cmd+Opt+I (`VaultBrowser.swift:129-171`); Pratiche: top-bar toggle «Nota della pratica», no key (`PraticaTopBar.swift:188-196`); Contenitore: always on, 310 pt (`ContenitoreView.swift:13-41`); Workspace: the tray «Nuovi elementi» plays the role (`BoardTray.swift:65-89`)
- Category: workflow placement · Severity: P3 · Confidence: confirmed
- What: one concept (details of the selected object, trailing column) under three names and three switches.
- Fix: «Ispettore» everywhere, trailing column, toggled by Cmd+Opt+I and by the last item of the toolbar's primary group; the Workspace tray keeps its creation role and gains the board inspector sections it already shows (TASK ASSEGNATI, NOTE REFERENZIATE) under that toggle.
- Tracked: none

### W-07 — «Da classificare» names two different inboxes, and «Classifica» has two keys
- Where: sidebar LAVORO «Da classificare» for notes (`SidebarItem.swift:59-96`, ADR-0085) and the Contenitore sidebar's «Da classificare» for documents (`ContenitoreSidebar.swift:40-57`, ADR-0071); note «Classifica…» has no default key (`RootView+Sheets.swift:43-45`), document «Classifica…» is Cmd+Opt+K (`ContenitoreMenuItems.swift:60-105`); the status item says «Inbox» (`MenuBarItem.swift:58-70`)
- Category: workflow naming · Severity: P3 · Confidence: confirmed
- What: one label for two queues in two panes, and the same verb reachable by a key in one pane only. Taylor's planning/execution split is right here; it just has two doors with one name.
- Fix: either one triage pane listing notes and documents with a kind filter, or distinct names («Note da classificare», «Documenti da classificare»); bind Cmd+Opt+K to «Classifica…» for whatever is selected; rename the status item's «Inbox» to the pane's name.
- Tracked: none

### W-08 — «Refresh from the outside» has four names and one key
- Where: Pratiche top bar «Aggiorna ora» and list column «Aggiorna tutte le pratiche» (`PraticaTopBar.swift`, `PraticheListColumn.swift:52-66`); Oggi «Aggiorna da EventKit» (`DayToolbar.swift:69`); Registrazioni «Aggiorna», Cmd+R (`MenuCommands.swift:13-136`); Contenitore «Importa ora» only in Settings (`ContenitoreSettingsTab.swift:127`)
- Category: workflow consistency · Severity: P3 · Confidence: confirmed
- What: the same idea (re-read Mail, EventKit, Plaud, the drop folder) with four names, four positions and a key only for recordings.
- Fix: «Aggiorna» with Cmd+R in every pane fed from outside the vault, in the same toolbar slot; «Aggiorna tutte» stays as Option-modified variant (Cmd+Opt+R).
- Tracked: none

### W-09 — Pane shortcuts do not follow the sidebar order
- Where: `Sources/Core/Shortcuts/ShortcutCommand.swift:347-421`, sidebar order `SidebarItem.swift:59-96`
- Category: workflow keyboard · Severity: P3 · Confidence: confirmed
- What: the sidebar reads Note, Workspace, Tag, Preferite, Viste · Oggi, Settimana, Mese, Nota di oggi, Diario · Attività, Da classificare, Contenitore, Pratiche, Registrazioni. The keys are 1, 2, 7, 9, 8 · 3, —, —, Cmd+Shift+D, 6 · 4, I, C, P, 0, with 5 left unbound on purpose (`:351-353`: renumbering would move a user's overrides because raw values key the overrides file). The rationale is sound for the storage; it is not a reason for the *defaults* to stay scattered.
- Fix: first check how `ShortcutStore` resolves an override against a changed default (the comment at `:351-353` says a renumber would move a user override; read the store before deciding), then renumber the defaults to follow the sidebar, and reorder the Vista ▸ «Vai a …» items to match.
- Tracked: none

### W-10 — Default shortcuts that shadow macOS conventions
- Where: `ShortcutCommand.swift:334` Cmd+Shift+S «Aggiungi alle preferite» (Duplica/Salva come… in document apps); `:341` Cmd+Shift+[ «Wikilink» (previous tab in every tabbed macOS app, and Pergamenum has tabs with Cmd+T, Cmd+W, Cmd+1…9); `:385` Cmd+E «Nuovo evento» (Use Selection for Find in every text view; here it also switches the pane to Oggi)
- Category: workflow keyboard · Severity: P3 · Confidence: confirmed for the bindings, suspected for the editor interference of Cmd+E (same mechanism as W-01)
- Fix: Cmd+Shift+[ / ] go to previous/next tab; «Wikilink» keeps `[[` typing (the completion panel already exists) and moves to Cmd+K, the de-facto "insert link" key; Cmd+E returns to the text system; «Nuovo evento» moves to Cmd+Opt+E (Cmd+Shift+E is already «Nuovo promemoria»); «Aggiungi alle preferite» moves to Cmd+Opt+S or stays menu-only.
- Tracked: none

### W-11 — Theme toggle on ten pane toolbars
- Where: `Sources/App/HistoryToolbar.swift:60-81`, ten call sites; absent from Pratiche and Ricerca globale
- Category: workflow placement · Severity: P3 · Confidence: confirmed
- What: a setting changed a few times a year occupies a toolbar slot on almost every pane, and its absence on two panes makes it look like a pane feature. It also pushes the frequent toggles (inspector, focus, tree) to a variable position.
- Fix: Vista ▸ Tema and Impostazioni ▸ Generali only (both exist); free the toolbar slot.
- Tracked: PG-262 touches the toolbar component layer, not this decision

### W-12 — Save state shown twice on the Note pane, and three save models
- Where: `Sources/Features/Editor/VaultTopBar.swift:37-39` and `NoteTabBar.swift:97-106`; notes save explicitly (Cmd+S, «Non salvato»), boards autosave («Salvataggio…», `BoardChrome.swift:43-66`), Diario autosaves (`DiaryController.swift:36,210`)
- Category: workflow consistency · Severity: P3 · Confidence: confirmed
- What: the same note's state in two places one centimetre apart, and a person moving from a board to a note goes from "it saves itself" to "it does not" with no cue but a small label.
- Fix: one indicator per pane, in the top bar; record in an ADR whether notes keep explicit save (a defensible choice given ADR-0073's quit review) and say it in the indicator's help text.
- Tracked: none

### W-13 — Undo after a change is offered by four different strips
- Where: `CreationUndoStrip.swift:20-38` («Nota creata · Annulla»), `VaultBrowser+NoteBirth.swift:14-41`, tag rename banner «Annulla la rinomina · Chiudi» (`TagBrowserView.swift:416-419`), view-board drop banner «Annulla · Chiudi» (`ViewBoardRenderer.swift:170-179`)
- Category: workflow consistency · Severity: P4 · Confidence: confirmed
- Fix: one toast component, one position (bottom of the content column), «Annulla» first, auto-dismiss, and Cmd+Z reaching the same undo.
- Tracked: PG-262 (component layer) is the natural home

### W-14 — Context menus list the same verbs in different orders
- Where: note row `NoteRowMenu.swift:28-76` (Apri · Apri in una nuova tab · Preferite · Rinomina… · Sposta in ▸ · commands · Mostra nel Finder · Elimina…); board row `WorkspaceRow.swift:289-300` (Rinomina… · Elimina… · Sposta in ▸: no Apri, no Finder, delete in the middle); note folder row `NoteTreeRow.swift:151-182` (Nuova nota qui · Comprimi/Espandi · Mostra nel Finder · Sposta in ▸: no Rinomina, no Elimina); Contenitore row `ContenitoreMenuItems.swift:11-29` (Classifica… · Apri · … · Sposta nel Cestino); pratica row `PraticaMenuItems.swift:13-27` (Apri · Rinomina… · Chiudi/Riapri · Aggiorna ora · Mostra nel Finder · Collega… ×3 · Elimina…)
- Category: workflow placement · Severity: P3 · Confidence: confirmed
- What: Hick's cost is paid every time, because no position is learnable. The board row puts «Elimina…» above «Sposta in», the folder row cannot rename or delete from the menu.
- Fix: the canonical order of §4 C-04, applied by a shared menu builder fed from each object's command catalogue (`PraticaCommand`, `ContenitoreCommand`, `TaskCommand` already exist as catalogues).
- Tracked: none

### W-15 — Two filter fields in the Pratiche pane
- Where: `PraticaTopBar.swift` «Filtra» (timeline) and `PraticheListColumn.swift:103-109` «Filtra pratiche» (list)
- Category: workflow placement · Severity: P4 · Confidence: confirmed
- What: both are needed, but they look alike and sit in two rows; a typed filter lands in whichever was focused. Every other pane has one filter at the top of its list.
- Fix: keep the list filter at the top of the list column (as Note, Workspace, Contenitore); give the timeline filter a distinct placeholder («Filtra messaggi») and the Cmd+F binding while the timeline has focus.
- Tracked: none

### W-16 — Day navigation is labelled two ways and placed two ways
- Where: Oggi toolbar `.principal` «Precedente · Oggi · Successivo · Vai a data» (`DayToolbar.swift:28`); Diario toolbar `.navigation` «Giorno precedente · Torna a oggi · Giorno successivo · Vai a una data» (`DiaryToolbar.swift:24-48`); sidebar Settimana and Mese duplicate the Oggi «Scala» picker
- Category: workflow consistency · Severity: P4 · Confidence: confirmed
- Fix: one day-navigation group, same placement and labels on both panes (the Oggi wording, since it also covers week and month); keep the sidebar Settimana/Mese rows only if the picker goes, not both.
- Tracked: none

## 4. Placement and naming contract

What "buttons always in the same place" becomes in practice. Each row is a rule the roadmap
(step 4) can implement once in `Sources/DesignSystem` and check in review.

| id | Surface | Canonical order / rule |
|---|---|---|
| C-01 | Window toolbar, leading (`.navigation`) | Indietro · Avanti · (date navigation on Oggi/Diario) |
| C-02 | Window toolbar, primary (trailing) | **Create** (pane's primary object) · pane actions (Aggiorna Cmd+R, filters as toggles) · view toggles (Albero, Concentrazione) · **Ispettore** last. No theme toggle. |
| C-03 | List column | header: title + count · filter field at top · rows · optional footer «+» duplicating C-02's create |
| C-04 | Context menu | Open group (Apri, Apri in una nuova tab, Apri nell'altra colonna) · object's own verbs (Classifica…, Collega…, Chiudi/Riapri) · Organise (Rinomina…, Sposta in ▸, Preferite) · Locate/share (Mostra nel Finder, Copia link Pergamenum) · divider · destructive last |
| C-05 | Destructive verbs | Finder Trash → «Sposta nel Cestino…» + confirmation; permanent → «Elimina…» + confirmation; reversible in app → no dialog + undo toast (C-07) |
| C-06 | Sheet footer | «Annulla» (Esc) left of the confirming verb (Return); the confirming verb names the action («Crea», «Rinomina», «Collega»), never «OK»/«Fatto» when an action happens |
| C-07 | Feedback after a change | one toast, bottom of the content column, «Annulla» first, Cmd+Z equivalent |
| C-08 | Keys | Cmd+N primary create of the current pane; Cmd+R refresh from outside; Cmd+Opt+I inspector; Cmd+Opt+K classify selection; Ctrl+Cmd+digit in sidebar order; no binding on a system text-editing key (Cmd+Left/Right, Cmd+E, Cmd+Shift+[ ]) |
| C-09 | Conflict banner | message · «Ricarica da disco» · «Tieni la mia versione» (deletion: «Scarta ed elimina» first), same component on note, board, Diario |
| C-10 | One verb, one name | the title comes from the command catalogue (`ShortcutCommand.title`, ADR-0023), never a literal at the call site |

## 5. Confirmed sound

- «Sposta in ▸» is the same submenu shape on notes, note folders, boards, Contenitore and messages.
- Sheets consistently put «Annulla» with `.cancelAction` before a named confirming verb with `.defaultAction` (Esc/Return), except the HelpSheet Esc gap already in PG-258.
- Capture then classify (ADR-0080, ADR-0085) is a clean planning/execution split; the capture panel never activates the app.
- The Task menu's scheduling ladder (Cmd+Opt+0…3) is a well-built, learnable sequence.
- Diario creates a block by dragging on the timeline (`DiaryTimeline.swift:146`), the fastest path, and the toolbar button is the fallback.
- Pratiche's tray «Da smistare» puts the default «Aggiungi» on Return and the secondary «Ignora» beside it: a model for C-06.
- CLI and MCP give the same verbs the same names (`perg`/`pergamenum-mcp` parity through `VaultAPI`).

## 6. Numbers

| Severity | Count | Ids |
|---|---|---|
| P2 | 2 | W-01, W-02 |
| P3 | 11 | W-03 to W-12, W-14 |
| P4 | 3 | W-13, W-15, W-16 |

Wait-for-hand-check: W-01 editor half and W-10 Cmd+E interference (one Debug build, a note with
focus, press the key).
