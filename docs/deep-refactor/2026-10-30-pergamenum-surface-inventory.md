# Pergamenum surface inventory — 2026-10-30

Collected by the step-1 code audit as input for the workflow (step 2) and GUI (step 3) audits. One section per slice, verbatim.

# S01-app

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Main window «Pergamenum» (`Window`, id `main`) | launch, any `pergamenum://` link, status item | sidebar + detail, title removed from the toolbar, min 1180×700 | — | `PergamenumApp.swift:346,367`, `RootView.swift:219` |
| Sidebar (`List(selection:)`, three sections) | main window | VAULT: Note, Workspace, Tag, Preferite, Viste · GIORNATA: Oggi, Settimana, Mese, Nota di oggi, Diario · LAVORO: Attività, Da classificare, Contenitore, Pratiche, Registrazioni | pane rows through `ShortcutStore` (defaults Ctrl+Cmd+1 Note, 2 Workspace, 3 Oggi, 6 Diario, 4 Attività, 7 Tag, 9 Preferite, 8 Viste, 0 Registrazioni, P Pratiche, C Contenitore, I Da classificare); Nota di oggi Cmd+Shift+D | `RootView.swift:229-264`, `SidebarItem.swift:59-96`, `Navigation.swift:13-72` |
| Empty state «Nessuna cartella note aperta» | any pane while `vault.root == nil` | «Apri cartella note…» | the pane's own shortcut when passed | `RootView.swift:325-347` |
| Toolbar, navigation placement (`HistoryToolbar`) | every pane through `.windowHistory` | «Indietro» (`history-back`), «Avanti» (`history-forward`) | Cmd+[ , Cmd+] (Vista menu) | `HistoryToolbar.swift:14-45,89-97` |
| Toolbar «Tema» picker (`themeToggleToolbarItem`) | panes that add it (ten call sites, Pratiche and Search excluded) | Sistema, Chiaro, Scuro, then each vault theme | — | `HistoryToolbar.swift:60-81` |
| Menu Pergamenum (`CommandGroup(after: .appInfo)`) | menu bar | «Cerca aggiornamenti…» (disabled unless `canCheckForUpdates`) | — | `MenuCommands.swift:292-296` |
| Menu File (`CommandGroup(after: .newItem)`) | menu bar | «Nuova nota», «Nuova board…», «Nuova pratica…», «Nota di oggi», «Nuovo task rapido…», «Cattura rapida» · «Apri cartella note…», «Cartelle recenti» ▸ (one row per recent, «Svuota elenco»), «Rigenera indice» · «Importa file…», «Importa convenzioni…», «Esporta nota» ▸ «Markdown (.md)», «HTML (.html)», «PDF (.pdf)» · «Salva», «Mostra nel Finder» · «Nuova tab», «Chiudi tab», «Riapri l'ultima tab chiusa», «Vai alla tab 1…9» | Cmd+N, Cmd+Shift+B, Cmd+Opt+P, Cmd+Shift+D, Cmd+Shift+N, none in the menu (Ctrl+Opt+Space is the global hot key) · Cmd+Shift+O, —, — · —, —, — · Cmd+S, Cmd+Shift+R · Cmd+T, Cmd+W, Cmd+Shift+T, Cmd+1…9 (hand-written `KeyEquivalent`) | `VaultCommands.swift:27-121`, defaults `ShortcutCommand.swift:297-422` |
| Menu Modifica additions (`CommandGroup(after: .pasteboard)`) | menu bar | «Incolla come testo puro», «Copia link Pergamenum», «Ricerca globale…» · «Sposta nel Cestino» (Contenitore selection) | Cmd+Shift+Opt+V, Cmd+Shift+L, Cmd+Shift+F · — | `MenuCommands.swift:306-322` |
| Menu Modifica, find group (`CommandGroup(replacing: .textEditing)`) | menu bar | «Trova nella nota», «Sostituisci», «Trova successivo», «Trova precedente» · «Estrai in una nota» | Cmd+F, Cmd+Opt+F, Cmd+G, Cmd+Shift+G · none | `MenuCommands.swift:327-340` |
| Menu Vista (`CommandGroup(after: .sidebar)`) | menu bar | «Indietro», «Avanti» · «Segui il link», «Apri il link in una nuova tab», «Apri il link nell'altra colonna» · «Vai a Note», «Vai a Workspace», «Vai a Oggi», «Vai a Diario», «Vai ad Attività», «Vai a Tag», «Vai a Preferite», «Vai a Viste», «Vai a Registrazioni», «Vai a Pratiche», «Vai a Contenitore», «Vai a Da classificare» · «Vai alla nota…», «Cronologia…» · «Dividi l'editor», «Chiudi la colonna» · «Ispettore», «Pannello Workspace», «Concentrazione Workspace», «Nascondi albero Workspace», «Concentrazione Note», «Nascondi albero Note» (toggles) · «Ripiega la sezione», «Espandi tutto», «Mostra il frontmatter»/«Nascondi il frontmatter» · «Aggiorna registrazioni» · «Aggiungi alle preferite»/«Togli dalle preferite», «Applica un template…», «Classifica…» · «Anteprima rapida» | Cmd+[, Cmd+] · Cmd+Opt+Return, none, none · Ctrl+Cmd+1, 2, 3, 6, 4, 7, 9, 8, 0, P, C, I · Cmd+O, Cmd+Shift+H · —, — · Cmd+Opt+I, —, —, —, —, — · Cmd+Opt+Left, Cmd+Opt+Right, Cmd+Opt+Y · Cmd+R · Cmd+Shift+S, Cmd+Ctrl+T, none · Space | `MenuCommands.swift:13-136` |
| Menu Vista ▸ «Tema» (`CommandGroup(after: .toolbar)`) | menu bar | Picker: Sistema, Chiaro, Scuro, then each vault theme | — | `MenuCommands.swift:351-361` |
| Menu Calendario (`CommandMenu`) | menu bar | «Vai a oggi», «Giorno precedente», «Giorno successivo», «Vai a data…» · «Nuovo evento…», «Nuovo promemoria…» · «Pubblica i time block sul Calendario», «Aggiorna da EventKit» | —, Cmd+Left, Cmd+Right, — · Cmd+E, Cmd+Shift+E · —, — | `MenuCommands.swift:151-184` |
| Menu Inserisci (`CommandMenu`) | menu bar | «Wikilink», «Tag», «Task» · «Data pianificata», «Scadenza», «Promemoria» · «Nota correlata…», «Tabella», «Vista…», «Immagine o file…», «Link email da Mail», «Aggiungi a pratica da Mail…» · «Apri nel Workspace» | Cmd+Shift+[, —, — · —, —, — · Cmd+Shift+K, —, —, —, —, Cmd+Shift+P · — | `MenuCommands.swift:197-224` |
| Menu Task (`CommandMenu`) | menu bar | «Nuovo task in questa nota» · «Completa o riapri», «Aggiungi sotto-task» · «Pianifica oggi», «Domani», «+2 giorni», «Settimana prossima», «Togli la data» · the selected task's `TaskCommand.available(for:)` entries, or disabled «linkBoard»/«goToNote» with none selected | — · Cmd+Return, Cmd+Shift+Return · Cmd+Opt+0, Cmd+Opt+1, Cmd+Opt+2, Cmd+Opt+3, — · — | `PergamenumApp.swift:485-536` |
| Menu Aiuto (`CommandGroup(replacing: .help)`) | menu bar | «Guida sintassi task», «Convenzioni harness», «Come funziona il Diario» | — | `MenuCommands.swift:269-273` |
| Status item menu (`NSStatusItem`, `NSMenu`) | menu bar extra | «Cattura rapida» · «Oggi», «Inbox» · «Esci da Pergamenum» | —, —, —, q (hand-written key equivalent) | `MenuBarItem.swift:58-70` |
| Global hot key (`GlobalHotkey`, `RegisterEventHotKey`) | anywhere, app in background included | opens the capture panel | Ctrl+Opt+Space (ShortcutStore `globalCapture`) | `PergamenumApp.swift:299-307` |
| Sheet «Ricerca globale» (`GlobalSearchView`) | Modifica ▸ Ricerca globale…, `vault.isShowingGlobalSearch` | view outside this slice | Cmd+Shift+F | `RootView.swift:167-172` |
| Sheet «Importa file» (`FileImportSheet`) | File ▸ Importa file…, after the open panel | per file: original name, «Nome file» field · «Annulla», «Importa» | Esc, Return | `RootView.swift:175-190`, `FileImportSheet.swift:28-51` |
| Sheet task composer (`TaskComposer`) | File ▸ Nuovo task rapido…, `vault.taskDraft` | view outside this slice | Cmd+Shift+N | `RootView.swift:195-201` |
| Sheet «Nuova pratica» (`NuovaPraticaWizard`) | File ▸ Nuova pratica…, «Aggiungi a pratica» ▸ new | view outside this slice | Cmd+Opt+P | `RootView.swift:205-207` |
| Sheet «Aggiungi a pratica» (`AddToPraticaSheet`) | Inserisci ▸ Aggiungi a pratica da Mail… | close, new pratica (switches to Pratiche and opens the wizard) | Cmd+Shift+P | `RootView.swift:208-216` |
| Help sheets (`HelpSheet` ×3) | Aiuto menu | view outside this slice | — | `RootView+Sheets.swift:16-24` |
| Sheet `WorkspacePicker` (task → board) | `navigation.taskPickingBoard` (Task menu, task rows) | view outside this slice | — | `RootView+Sheets.swift:25-27` |
| Sheet `CategoryPicker` (task → category) | `navigation.taskPickingCategory` | view outside this slice | — | `RootView+Sheets.swift:28-30` |
| Sheet `CategoryEditor` | `navigation.categoryEditorTarget` | view outside this slice | — | `RootView+Sheets.swift:31-33` |
| Sheet `CategoryNotePicker` | `navigation.categoryLinkingNote` | view outside this slice | — | `RootView+Sheets.swift:34-37` |
| Sheet `LinkChoiceSheet` | `navigation.linkChoice` (ambiguous link) | view outside this slice | — | `RootView+Sheets.swift:38-42` |
| Sheet `ClassificaSheet` | Vista ▸ Classifica…, `navigation.classifying` | view outside this slice | none by default | `RootView+Sheets.swift:43-45` |
| Sheet `PraticaLinkPicker` | `navigation.praticaLinkRequest` | view outside this slice | — | `RootView+Sheets.swift:46-52` |
| Quit review alert (`NSAlert`, app-modal) | Cmd+Q, red button on the last window, logout; vault switch; column close | «Salva» or «Salva tutto» · «Annulla» · «Non salvare» (ids `quit-prompt-*`, `vault-switch-prompt-*`, `column-close-prompt-*`) | Return, Esc, Cmd+D | `QuitReviewAlert.swift:21-45`, `QuitReview.swift:228-253` |
| Open panel «Scegli la cartella delle note» (`NSOpenPanel`, directories) | File ▸ Apri cartella note…, empty state | system panel | Cmd+Shift+O | `VaultOpenPanel.swift:10-19,40-49` |
| Open panel «Importa convenzioni» (`NSOpenPanel`, directories) | File ▸ Importa convenzioni… | system panel | — | `VaultOpenPanel.swift:21-27` |
| Open panel «Importa file» (`NSOpenPanel`, multiple files) | File ▸ Importa file… | system panel, message names the inbox folder | — | `VaultOpenPanel.swift:30-38`, `VaultCommands.swift:80-89` |
| Save panel «Esporta nota» (`NSSavePanel`) | File ▸ Esporta nota ▸ format | system panel, extension from the format | — | `NoteExporter.swift:33` |

Values in the slice that do not come from a token:

| value | where | note |
|---|---|---|
| `.frame(minWidth: 1180, minHeight: 700)` | `RootView.swift:219` | window minimum |
| `navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)` | `RootView.swift:241` | sidebar width |
| `.frame(maxWidth: 420)` | `RootView.swift:339` | empty-state text width |
| `spacing: 2` | `FileImportSheet.swift:32` | chain 9 names `spacing.xxs` (2) as a missing token |
| `.frame(maxHeight: 240)` | `FileImportSheet.swift:41` | list height |
| `.frame(width: 560)` | `FileImportSheet.swift:51` | sheet width (chain 9: "three named sheet widths") |
| `NSSize(width: 595, height: 842)`, `margin` 56 | `NoteExporter.swift:69-73` | A4 print geometry, not UI theming |

No colour and no font literal in the slice (`Color.`, `NSColor.`, `.font(`, `NSFont.`, `.caption2`: zero matches outside `theme.`).

# S04-core-markdown-query

## Surface inventory

Not applicable: no SwiftUI or AppKit view in this slice.

# S06-connector-cli-mcp-index-calendar

## Surface inventory

No views in this slice. In its place, as the task asked: the connector surface (read vs write), the Periphery verdicts and the slice-specific claims verified.

**MCP tools** (`pergamenum-mcp`; every write tool carries `dryRun` with default `true`, is listed only under `--allow-write` and re-checked in `VaultHost.write`):

| Kind | Tools |
|---|---|
| read (19, `readOnlyHint: true`) | `search_vault`, `read_note`, `list_notes`, `note_links`, `note_backlinks`, `unresolved_links`, `list_tasks`, `day_agenda`, `list_categories`, `category_tasks`, `lint_note`, `lint_vault`, `list_views`, `run_view`, `vault_stats`, `pratiche`, `pratica`, `pratica_links`, `journal_log` |
| read (resources) | `resources/list` (paged, cursor parsed), `resources/read` (`pergamenum://note?file=`) |
| write (28) | `create_note`, `append_to_note`, `rename_note`, `move_note`, `trash_note`, `add_task`, `capture`, `complete_task`, `reopen_task`, `reschedule_task`, `add_time_block`, `pratica_link_note`, `pratica_unlink_note`, `pratica_link_board`, `pratica_unlink_board`, `pratica_link_task`, `pratica_unlink_task`, `pratica_create_note`, `pratica_create_task`, `pratica_create_board`, `message_link_note`, `message_unlink_note`, `message_create_note`, `undo_write`, `link_mention`, `remove_structural_link`, `classify_note`, `extract_to_note` |

**CLI commands** (`perg`; writes take `--dry-run` and are journalled; exit 0 done, 1 usage, 2 refused):

| Kind | Commands |
|---|---|
| read | `note list\|read\|links\|backlinks\|unresolved`, `search`, `task list [--completed]`, `categories`, `category-tasks <slug>`, `day show`, `lint [percorso]`, `view list\|run`, `pratiche`, `pratica <rif>`, `pratica links <rif>`, `index stats`, `journal log`, `help` |
| read, CLI-only by design | `app open today\|note\|day\|search` (ADR-0007 §D5, launches the app through `/usr/bin/open`) |
| write | `note new\|append\|rename\|move\|trash\|link-mention\|unlink-related\|classify\|extract`, `capture`, `task add\|done\|reopen\|reschedule`, `day block add`, `pratica link-note\|unlink-note\|link-board\|unlink-board\|link-task\|unlink-task\|create-note\|create-task\|create-board`, `message link-note\|unlink-note\|create-note`, `journal undo <id>` |

Parity (focus a): every read and write maps one-to-one between the two front ends through `VaultAPI`, with two exceptions: `app open` (CLI-only by design) and `VaultAPI.praticaMessageLink`, exposed by neither (S06-08). No read or write is implemented inside `Sources/CLI` or `Sources/MCPServer`; both only translate.

**Periphery verdicts** (focus f, g):

- Connector, 26 `assignOnlyProperty`: all are `let` fields of `Encodable` payload structs (`VaultCategories.swift:26-33,69`, `VaultPayloads.swift:18-349`, `VaultPratiche.swift:213`) serialized by the synthesized `encode(to:)` through `ConnectorJSON.encode`. False positives, none real.
- MCPServer, 16 "unused": every type and global of the `pergamenum-mcp` executable (`Diagnostics`, `ToolArguments`, `ToolCatalogue*`, `VaultHost*`, `main.swift`'s `help`/`version`/`instructions`/`register`/`boot`). Periphery ran on the `Pergamenum` scheme (PG-266), which does not compile `Sources/MCPServer`. False positives, none real.
- `CalendarEvent.isEditable` assign-only: real. Set in `fetch` (`CalendarService.swift:197`) and `createEvent`, read nowhere in `Sources/` or `Tests/`. ROADMAP Chain 13 item 3 left it "worth a decision" and PG-266 closed without recording one. Keep (and read it where a read-only calendar's event is shown) or delete.
- `TimeBlock.sourceTaskID` assign-only: real as a fact (set at `DayController.swift:221`, read nowhere; `TimeBlockSection.parse` always writes `nil` at `TimeBlock.swift:172` and `render` never emits it) and deliberate per ROADMAP Chain 13 item 3, whose pointer `DayController.swift:197-203` is stale: the rationale now sits at `DayController.swift:228-235`.
- `CalendarStore.eventAccess`, `.reminderAccess`, `.requestAccess()`, `.writableCalendarTitles` unused: true of the protocol requirements, not of the members. Every caller holds the concrete `EventKitStore` (`SettingsView.swift:183-257`, `DayTimeline.swift:255-262`, `MenuCommands.swift:179`, `CommandActions+CanRun.swift:58-60`, `CalendarDayMenuItems.swift:43-44`, `DayToolbar.swift:100-103`, `TimelineBlockBox.swift:58`), and `DayController` (the one `any CalendarStore` holder) calls only the event and reminder members. Dropping the four requirements also drops their stubs in `Tests/DayTestSupport.swift`. The 2026-09-11 audit's `writableReminderListTitles` is already gone.

**Verified claims** (focus b, c, d, e, f):

- (c) `VaultHost.call` rescans before every tool call, read-only tools included (`VaultHost.swift:53`). The item (`perf-VaultHost.swift-bbb`) was grouped under PG-137 and closed by ADR-0041 as an isolation change: the rescan went `async`, and the per-call rescan is kept by the documented design at `:11-14`. No regression. The resource endpoints do not rescan (S06-07).
- (b) Write tools are absent from `tools/list` without `--allow-write` (`VaultHost.swift:35-43`) and re-locked in `write` (`:179-187`); `dryRun` is read once for all 28 with default `true` (`:188`; `ToolArguments.swift:90-103` coerces `true/false/yes/no/1/0` and ints by design, anything else falls to the safe default). `undo` refuses a moved-on file (`VaultWrites.swift:334-341`, `expecting:` at `:356`) and an operation whose members fail preflight (`VaultSession+Journal.swift:299-300`). Negative or unreadable `limit`/`cursor` are refused (`VaultReads.swift:59-79`, `VaultHost.swift:296-301`), `--folder --dry-run` is refused (`Arguments.swift:79-83`), invalid dates (`VaultLookup.day`) and out-of-range minutes (`VaultWrites.swift:250`) are refused. Per-call, these hold; across concurrent calls, S06-01.
- (d) `isDryRun` is assigned only in `VaultAPI.arm` (`VaultWrites.swift:31`). `journal` and `journalCommand` have one app-side arming site outside this slice, `Sources/Vault/VaultSession+BoardDrop.swift:66-74`, which arms and restores them around a Workspace drop (ADR-0016's gesture journal): CLAUDE.md's "the app arms none of them" is true of `isDryRun`, not of the journal. Not a finding here (S02's file); one sentence in CLAUDE.md would settle it.
- (e) Every SQL value is bound (`sqlite3_bind_text/blob` with `SQLITE_TRANSIENT`); the only interpolation is the static `schemaVersion` (`IndexCache.swift:244`). `user_version` 7, a mismatch drops and rebuilds; the cache is wholly derived (`StoredRecord` carries size, mtime and payload, no id column: ADR-0059 holds, ids live in the registry file). `IndexSnapshot.generation` bumps in `replaceAll`/`update` (`IndexSnapshot.swift:67`) and the derived maps are rebuilt there (ADR-0072), `allNotes` excepted (S06-09).
- (f) `nonisolated(unsafe) var observations` (`CalendarService.swift:59`): written once in `init` (`:63-71`), read in `deinit` (`:74-76`, which may run off the main actor for a `@MainActor` class), and the two `Task`s capture `[weak self]`: the documented reason holds. EventKit writes (`createEvent`, `createReminder`, `setCompleted`) are guarded on access and go through `EKEventStore.save`/`commit`; this slice writes vault → calendar only (per-block publish), nothing flows from EventKit into the vault.

# S07-designsystem-small-features

## Surface inventory

| Surface | Opens from | Verbs / buttons in order | Shortcut | file:line |
|---|---|---|---|---|
| Impostazioni window | app menu (`Settings` scene, opener outside the slice) | tabs Generali, Scorciatoie, Design system, Editor, Canvas, Attività, Giornata, Convenzioni, Calendario, Pratiche, Contenitore, Avanzate; 840×560 | Cmd+, (standard scene) | `SettingsView.swift:18-36`, `:57` |
| Generali | tab | Cartella note (label), Percorso (label), «Apri un'altra cartella…», Viste di esempio «Scrivi in Templates/», Tema picker (Sistema/Chiaro/Scuro + user themes, bundled ids filtered), Problemi nei token list | none | `SettingsView.swift:73-126`, `:86`, `:95`, `:109`, `:113`, `:118` |
| Scorciatoie | tab | «Ripristina tutte le scorciatoie», one recorder button per command (`KeyRecorder`) | none | `ShortcutSettings.swift:28`, `:80`, `:112-242` |
| Design system | tab | Tema attivo (label), Personalizzazione «Riparti dal tema attuale», «Ripristina» (destructive), «Mostra tutti i token…», «Mostra i mockup…», per-token reset («Torna al valore del tema di base») and `ColorPicker` for the 35 editable colour tokens; two sheets with «Chiudi» (720×620, 780×640) | none | `DesignSystemSettings.swift:21-33`, `:38`, `:53`, `:56`, `:76`, `:77`, `:97`, `:103`, `:111`, `:117`, `:127-138` |
| Editor | tab | Carattere della nota: Famiglia picker, Corpo stepper, «Ripristina carattere»; toggles «Nascondi i marcatori mentre scrivi», «Rivela solo la parola sotto il cursore», «Larghezza di lettura», «Correttore ortografico» with Lingua picker | none | `EditorSettings.swift:50`, `:61-69`, `:75`, `:90`, `:103`, `:115`, `:126`, `:135` |
| Canvas | tab | «Mostra la griglia», «Aggancia alla griglia», Import «File trascinati» radio (S07-01); form disabled without a vault | none | `CanvasSettings.swift:14`, `:18`, `:26-33`, `:39` |
| Attività | tab | «Durata predefinita del blocco tempo» picker, «Mostra i task rimandati», «Quanti giorni indietro» picker | none | `TaskSettings.swift:18`, `:33`, `:46` |
| Giornata | tab | Oggi and Diario «Dalle»/«alle» hour pickers; Santo patrono: Nome, «il» day picker, month picker | none | `TimelineSettings.swift:19`, `:29`, `:60-78`, `:130`, `:141` |
| Convenzioni | tab | Cartella daily (S07-03), «Modello della nota del giorno» picker, Cartella inbox, Cartella diario (S07-03), Vocabolari chiusi counts (type/status/area/source), «Importa convenzioni…» | none | `SettingsView.swift:132`, `DailyTemplateField.swift:15`, `SettingsView.swift:343`, `:143`, `:157-161`, `:167` |
| Calendario | tab | Accesso Calendario / Promemoria / Notifiche labels, «Richiedi accesso alle notifiche», «Invia una notifica di prova», «Richiedi accesso», «Apri Impostazioni di Sistema: Calendario», «Apri Impostazioni di Sistema: Promemoria», «Calendario di scrittura» picker | none | `SettingsView.swift:183-185`, `:190`, `:209`, `:230`, `:235`, `:240`, `:252` |
| Pratiche | tab | «Conserva l'originale .eml», two steppers, «Scrivi nel diario», Cartella radice «Scegli…», I miei indirizzi «Rimuovi» / new-address field / «Aggiungi» (S07-04), Accesso completo al disco «Apri Impostazioni di Sistema», Sincronizzazione «Aggiorna tutte le pratiche ora»; form not disabled without a vault | none | `PraticheSettingsTab.swift:36-79`, `:40`, `:46`, `:56`, `:68`, `:90`, `:144-152`, `:233`, `:281` |
| Contenitore | tab | Testo estratto (label), Cartella di raccolta «Scegli…» / «Mostra nel Finder», Cartella radice «Scegli…», Stato «Importa ora» | none | `ContenitoreSettingsTab.swift:23`, `:42`, `:44`, `:83`, `:127` |
| Avanzate | tab | Note indicizzate (label), Plaud days field, «Svuota cache e ricostruisci», Problemi list with «Svuota» | none | `SettingsView.swift:284-318`, `:286`, `:91`/`:360-382`, `:296`, `:313` |
| Capture panel | global hotkey, non-activating `NSPanel` (`orderFrontRegardless`, never activates the app) | title caption, template menu (note only), destination chips Nota/Task/Oggi/Esistente, folder popover, text field (`ComposerTextField`), schedule and deadline popovers (task only), note picker «Cerca una nota» (existing only), «Cattura»; Esc closes via `EscapableCapturePanel.cancelOperation` | Ctrl+Opt+Space (`.globalCapture`), Cmd+1…4 destinations, Return captures | `CapturePanelView.swift:34`, `:67`, `:94-96`, `:125-127`, `:142`, `:184-185`, `:213-215`, `:263-273`, `:333`; `CapturePanel.swift:164-172`; `GlobalHotkey.swift:85-119`; `ShortcutCommand.swift:319` |
| Tag browser | Tag pane | «Azzera», namespace toggle buttons, tag row context menu «Rinomina in tutto il vault…», note rows open on click, rename-outcome banner «Annulla la rinomina» / «Chiudi»; pin toggle (PG-258) | Ctrl+Cmd+7 (`.paneTags`) | `TagBrowserView.swift:148`, `:159`, `:204-209`, `:245`, `:416`, `:419`; `ShortcutCommand.swift:357` |
| Tag rename sheet | «Rinomina in tutto il vault…» | «nuovo tag» field, «Annulla», «Rinomina»; 560 wide | Esc cancels, Return renames | `TagRenameSheet.swift:41`, `:53-58`, `:63` |
| Ricerca globale | menu / shortcut | «Cerca in tutte le note…» field, result rows open on tap (no keyboard selection path), no toolbar or theme toggle (PG-262); 720×520 | Cmd+Shift+F (`.globalSearch`), Esc dismisses | `GlobalSearchView.swift:36`, `:38`, `:51`, `:82`; `ShortcutCommand.swift:321` |
| Quick Look | selection in a list hosting `QuickLookTarget` | Space toggles the system panel from `keyDown`; menu path via `togglePreviewPanel`; first-responder claim and hand-back per ADR-0070 §D4; `isShowingQuickLook` latch (PG-258) | Space (`.quickLook`) | `QuickLookPresenter.swift:28-33`, `:39`, `:94`, `:107`, `:145`, `:148`; `ShortcutCommand.swift:320` |
| Help sheets | Aiuto menu (`RootView+Sheets.swift:17-23`) | three topics (Guida sintassi task, Convenzioni harness, Come funziona il Diario), sections, «Chiudi»; 620×520, first column 190 | Return closes (Esc tracked in PG-258) | `HelpSheets.swift:15-24`, `:42`, `:57`, `:61`, `:82-151` |
| Da classificare | pane | «Cartella» picker; row menu «Classifica» (`ShortcutCommand.classifyNote.title`), «Apri», «Apri in una nuova tab», «Mostra nel Finder», «Mostra nel Contenitore»; Return / double-click = `primaryAction` | Ctrl+Cmd+I (`.paneUnfiled`) | `UnfiledPane.swift:59`, `:116-127`, `:138-151`; `ShortcutCommand.swift:421` |
| Viste pane | pane | rows open the note (`.help("Apri …")`); rescans on `scanGeneration` or a new day (S07-08) | Ctrl+Cmd+8 (`.paneViews`) | `ViewsPane.swift:56`, `:59`, `:95`, `:124`; `ShortcutCommand.swift:362` |
| Rendered view block | a `pergamenum-view` fence in the editor | «Modifica la sorgente», «Modifica query», «Aggiorna la vista»; board drop banner «Annulla» (S07-05) / «Chiudi»; 320pt cap per ADR-0035 | none | `RenderedViewBlock.swift:121-125`, `:132-136`, `:139-143`; `ViewBoardRenderer.swift:170`, `:179` |
| Query builder sheet | «Modifica query» | folders «Aggiungi», terms «Aggiungi» with per-row kind/comparison/text/glob/note/field/status/form/day controls, sort «decrescente», Rendering picker, columns, limit field, remove buttons («Rimuovi»); «Annulla», «Fatto»; 560 wide, list capped at 420 | Esc cancels, Return commits | `ViewQueryBuilderSheet.swift:92`, `:111-115`, `:121`; `ViewQuerySections.swift:36`, `:97`, `:129`, `:182`, `:210`, `:228`, `:240-245`; `ViewQueryTermRow.swift:102`, `:130`, `:141`, `:189`, `:224`, `:248`, `:272`, `:290`, `:324`, `:334` |

### Non-token literals (colours and fonts: none; sizes and spacings below)

| file:line | Literal | Kind |
|---|---|---|
| `GlobalSearchView.swift:36` | 720×520 | sheet size |
| `GlobalSearchView.swift:72`, `:101` | `spacing: 2` | spacing |
| `HelpSheets.swift:42` | `width: 190` | column width |
| `HelpSheets.swift:61` | 620×520 | sheet size |
| `SettingsView.swift:57` | 840×560 | window size |
| `SettingsView.swift:372` | `width: 80` | field width |
| `DesignSystemSettings.swift:103`, `:117` | 720×620, 780×640 | sheet sizes |
| `DesignSystemSettings.swift:132`, `ShortcutSettings.swift:85` | `.buttonStyle(.borderless)` | style outlier (PG-262) |
| `ShortcutSettings.swift:123` | `minWidth: 92` | width |
| `TimelineSettings.swift:66`, `:75`, `:86`, `:138`, `:149` | 220, 90, 140, 150, 150 | widths |
| `ContenitoreSettingsTab.swift:26`, `:52`, `:89` | `maxWidth: 420` | width |
| `PraticheSettingsTab.swift:280` | `spacing: 2` | spacing |
| `CapturePanelView.swift:43` | `width: 460` | panel width |
| `TagBrowserView.swift:59`, `:61` | 240/300/420, `minWidth: 320` | column widths |
| `TagBrowserView.swift:184`, `:192`, `:246` | `width: 11`, `padding 3`, `spacing: 1` | sizes |
| `TagBrowserView.swift:112`, `:225`, `:426` | `Divider()` | divider (PG-262) |
| `TagRenameSheet.swift:63` | `width: 560` | sheet width |
| `UnfiledPane.swift:51`, `:84` | `spacing: 2`, `maxWidth: 420` | spacing, width |
| `UnfiledRow.swift:15`, `:16` | `width: 18`, `spacing: 2` | sizes |
| `RenderedViewBlock.swift:77`, `:192` | `lineWidth: 1`, `spacing: 1` | stroke, spacing |
| `ViewBoardRenderer.swift:45`, `:91`, `:95`, `:237` | `spacing: 8`, `spacing: 4`, `spacing: 4`, `lineWidth: 1` | spacing, stroke |
| `ViewGridRenderers.swift:21`, `:22`, `:76`, `:85`, `:92` | 145, `spacing: 16`, 320, `height: 98`, `lineWidth: 1` | sizes |
| `ViewGridRenderers.swift:159`, `:213`, `:216`, `:230`, `:236-237`, `:240`, `:248` | `spacing: 4/2/4/2`, padding 4/1, `cornerRadius: 4`, `minHeight: 76` | spacing, radius, size |
| `ViewRowRenderers.swift:28`, `:101`, `:210-211` | `spacing: 2`, `spacing: 4`, padding 6/1 | spacing |
| `ViewsPane.swift:50`, `:97` | `maxWidth: 820`, `spacing: 2` | width, spacing |
| `ViewQueryBuilderSheet.swift:92`, `:121` | `maxHeight: 420`, `width: 560` | sheet sizes |
| `ViewQuerySections.swift:230` | `width: 120` | width |
| `ViewQueryTermRow.swift:108`, `:138`, `:247`, `:256`, `:323` | `width: 140`, `spacing: 4` ×3, `height: 100` | sizes |

# S08-editor-a

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Assegna una categoria menu | note inspector, uncategorised note | «Assegna una categoria…» ▸ one row per category | none | AssignCategoryMenu.swift:19-41 |
| Backlinks section | note inspector | rows (title, line, count, «strutturale») | none | BacklinksSection.swift:29-116 |
| Backlink row context menu / accessibility actions | right-click / VoiceOver on a backlink row | «Rendi strutturale» or «Scollega» (BacklinkCommand) | none | BacklinksSection.swift:103-116, BacklinkCommand.swift:21-25 |
| Scollega confirmation | «Scollega» | «Scollega», «Annulla» | Esc | BacklinksSection.swift:43-56 |
| Scollega refused alert | failed unlink | «OK» | Return | BacklinksSection.swift:57-66 |
| Classifica sheet (scheda) | Contenitore «Classifica…» | topic chips (×), topic field, suggestions, «Crea «X»», «Tipo» picker, preview, «Annulla», «Classifica» | Esc, Return | ClassificaSheet.swift:59-162 |
| Classifica sheet (note) | «Classifica…» on a note | topic chips, topic field, completions, «Cartella» picker, preview, «Annulla», «Classifica»/«Salva e classifica» («Chiudi» after) | Esc, Return | NoteClassificaForm.swift:31-127 |
| Completion panel | `[[`, `[[X#`, `#`, `/`, `:` in the editor | rows; «Crea «X»» when no match; footer hints | Up, Down, Return, Tab, Esc | CompletionPanel.swift:125-153, CompletionPanelView.swift:30-50,177,196-214, CompletingTextView.swift:286-306, CompletingTextView+Context.swift:110-145 |
| Slash menu catalogue | `/` at line start | Titolo 1, Titolo 2, Titolo 3, Elenco puntato, Elenco numerato, Task, Citazione, Callout, Blocco di codice, Tabella, Separatore, Incorpora nota o file, Tag, Vista …, Pianifica per un giorno, Scadenza, Promemoria, Ripeti | per-command caption | EditorCommand.swift:40-153 |
| Link context menu item | right-click on a link | «Apri collegamento» (added to the text menu) | Cmd+click navigates | CompletingTextView+Pasteboard.swift:253-284 |
| Embed context menu | right-click on a drawn embed | «Elimina» | Backspace/Delete at the run edge | EmbedContextMenu.swift:21-23, EmbedNavigation.swift:84-97 |
| Link choice menu | Cmd+click an ambiguous or dangling link | header «Più note si chiamano «X»», one row per note; or «Crea «X»» | none | LinkChoiceMenu.swift:23-46 |
| Link choice sheet | keyboard follow, «Apri collegamento», card, chip, tray | rows, «Annulla», «Apri»/«Crea» | Esc, Return | LinkChoiceSheet.swift:20-37,87-97 |
| Link mention sheet | «Collega» on a mention | diff, «Annulla», «Collega» | Esc, Return | LinkMentionSheet.swift:16-44 |
| Link preview popover | hover on a link | note preview / «Nessuna sezione «X»» / «N note si chiamano «X»» / «Nessuna nota si chiama «X»» | none | LinkPreviewPopover.swift:72-84, LinkPreviewView.swift:30-59 |
| Find bar | Cmd+F, Cmd+Alt+F (replace) | query field, `.*`, `Aa`, scope chip, tally, previous, next, «Fine»; replace row: field, «Sostituisci», «Tutti» | Cmd+F, Cmd+Alt+F, Cmd+G, Cmd+Shift+G, Return, Shift+Return, Esc | FindBar.swift:23-151, EditorColumn+Text.swift:227-239,320-330 |
| Format bar panel | non-empty selection outside fences/embeds | Grassetto, Corsivo, Barrato, Codice, Collega a una nota del vault, Collega a un indirizzo | none | FormatBar.swift:38-52,55-99, FormatBarPanel.swift:46-85 |
| Conflict banner | external change or deletion of an open note | message, «Ricarica da disco»/«Scarta ed elimina», keep-local verb | none | EditorColumn+Conflict.swift:16-33, ConflictBannerCopy.swift:16-27 |
| Unsaved tab dialog | closing a dirty tab | «Salva», «Non salvare», «Annulla» | Esc | EditorColumn+Closing.swift:60-80 |
| Editor empty state | no open note | icon + text | none | EditorColumn+Closing.swift:12-22 |
| Editor column | Note pane | tab strip, editor, Quick Look on embeds, view-query sheet | Space (Quick Look) | EditorColumnView.swift:86-140 |
| Column divider | «Dividi l'editor» | drag to resize | none | EditorColumns.swift:64-93 |
| Creation undo strip | after a pane-host note creation | «Nota creata», «Annulla» | none | CreationUndoStrip.swift:20-38 |
| New note composer | «Nuova nota», sheet hosts, «Estrai in una nota» | title, tags field, folder menu («(radice)», folders), template menu («(nessuno)», templates), preview, «Annulla», «Crea» | Esc, Return | NewNoteComposer.swift:83-247, NewNoteComposer+Hosts.swift:8-28, NewNoteComposer+Tags.swift:30-55 |
| Note history sheet | note history command | version list, preview, «Chiudi», «Ripristina» | Return | NoteHistorySheet.swift:109-157 |
| Note list header | Note pane | «Filtra» field, folders/list toggle | none | NoteListPane.swift:241-267 |
| Note list toolbar | Note pane | «Nuova nota», «Nuova cartella», «Rinomina nota/cartella», «Elimina nota/cartella», «Espandi tutto», «Comprimi tutto» | none | NoteListToolbar.swift:32-62 |
| Note row context menu | right-click a note row (tree and flat) | NoteRowMenu (file in S09) | none | NoteListPane.swift:324-325,381-382 |
| Tree background context menu | right-click the tree | «Espandi tutto», «Comprimi tutto» | none | NoteListPane.swift:350-353 |
| Rename note sheet | «Rinomina» | rename sheet | Esc, Return | NoteListPane.swift:203-214 |
| Delete note dialog | «Elimina» | «Sposta nel Cestino», «Annulla» | Esc | NoteListPane.swift:215-236 |
| Move/rename/trash refused alerts | failed verb | «OK» | Return | NoteListPane.swift:113-154 |
| Folder sheets and dialog | «Nuova cartella», «Rinomina cartella», «Elimina cartella» | new-folder sheet, rename sheet, «Sposta nel Cestino», «Annulla», refused alerts «OK» | Esc, Return | NoteListPane+FolderVerbs.swift:120-184,189-225 |
| Note list footer | Note pane | counts, index failures badge | none | NoteListPane+Footer.swift:18-53,99-122 |
| Reading view (retained, unreferenced) | none (ADR-0029 §D14) | scroll only | PageDown, Space, PageUp, Down, Up, Home, End | MarkdownReadingView.swift:118-124 |

Non-token values:

| value | use | reachable at runtime | file:line |
|---|---|---|---|
| `NSColor.secondaryLabelColor` | missing-embed glyph | yes, every missing embed (PG-262) | EditorDecorationDelegate+EmbedRendering.swift:46 |
| `.systemFont(ofSize: NSFont.systemFontSize)` | delegate `proseFont` default | only before first `applyStyling` | EditorDecorationDelegate.swift:168 |
| `.systemFont(ofSize: 10)` | fold badge default | no, overwritten each layout | EditorDecorationDelegate.swift:173, FoldedHeadingFragment.swift:24 |
| `.systemFont(ofSize: 11)`, `(15, .semibold)`, radius 10 | `EditorConstructStyle` defaults | only before first styling; app uses `init(_ theme:)` | EditorConstructStyle.swift:14,28,30 |
| `.systemFont(ofSize: NSFont.systemFontSize)`, `?? .secondaryLabelColor` | chip fallbacks | no (embed chips always carry `leading`) | InlineChipPainter.swift:33,68 |
| `markerPointSize = 11` | anchor fallback | no, set at layout | MessageAnchorFragment.swift:21 |
| `.black` gradient | preview fade mask (mask, not colour) | yes | LinkPreviewView.swift:82 |
| `Theme.emergency` | popover/preview default theme | only if a host omits it | LinkPreviewPopover.swift:56, LinkPreviewView.swift:14 |
| 26×22, 16, 2, 4 | format bar buttons/divider/padding (PG-262) | yes | FormatBar.swift:60,66,86 |
| 240×32, 24 | format bar panel rect, shadow margin | yes | FormatBarPanel.swift:30,61 |
| 3, 96×1 | find bar toggle padding, spacer | yes | FindBar.swift:89,112,135 |
| 22×22 | note toolbar buttons | yes | NoteListToolbar.swift:76 |
| 6, 1, 2, spacing 1 | backlink rows | yes | BacklinksSection.swift:75,81,82,97 |
| 32, lineWidth 1 | undo strip | yes | CreationUndoStrip.swift:14,35 |
| 280, 1, 10 | column min width, divider, grab | yes | EditorColumns.swift:37,38,40 |
| 0.08 | callout background opacity | yes | CalloutStyle.swift:7 |
| 340×200, 120, 320, 16 | completion panel | yes | CompletionPanel.swift:139,207, CompletionPanelView.swift:41,114,117,237 |
| sheet widths 520 / 340 / 560 / 360 / 820×560, 240 (PG-262) | sheets and popover | yes | ClassificaSheet.swift:86, NoteClassificaForm.swift:46, NewNoteComposer.swift:51, LinkChoiceSheet.swift:29, LinkMentionSheet.swift:39, LinkPreviewView.swift:17, NoteHistorySheet.swift:118,126 |
| 2, 14 | link choice rows | yes | LinkChoiceSheet.swift:48,68 |
| 18, 1 | reading-view list number, rule | retained view only | MarkdownBlocksView.swift:87,166 |
| 48 | reading-view line step | retained view only | MarkdownReadingView.swift:153 |
| 80, 14, 3, 22 | embed resize min side and handles | yes | EmbedResize.swift:47,203-205 |
| 1.5, 6×2 | resize overlay | yes | EmbedResizeOverlay.swift:47-48 |
| 8, 6×1 | fold badge gap/padding | yes | FoldedHeadingFragment.swift:32-33 |
| 8, 1 | fence chrome | yes | CodeFenceFragment.swift:16-17 |
| 1 | rule thickness | yes | HorizontalRuleFragment.swift:20 |
| -4 | chevron hit slop | yes | CalloutTitleFragment.swift:53 |
| 16 | placeholder text inset | yes | EmbedPlaceholder.swift:42 |
| 720, 120 | embedded file render width, loading height | yes | EmbeddedFileView.swift:26,65 |

# S09-editor-b

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Note pane (VaultBrowser) | sidebar «Note» | VaultTopBar · NoteListPane · editor columns · inspector | — | `VaultBrowser.swift:16-57` |
| Note pane toolbar, navigation group | Note pane | Nuova nota (parked-draft dot) · Vai alla nota · Ricerca globale | — (menu items carry them) | `VaultBrowser.swift:96-127` |
| Note pane toolbar, primary group | Note pane | Ispettore (toggle) · Concentrazione (toggle) · Albero (toggle) · theme toggle | — | `VaultBrowser.swift:129-171` |
| VaultTopBar | top of Note pane | breadcrumb crumbs (reveal folder) · save state label (Salvato/Non salvato) | — | `VaultTopBar.swift:28-46` |
| Inspector | toolbar Ispettore | star · CATEGORIA / Assegna · CRONOLOGIA · BACKLINK · MENZIONI NON LINKATE · DOVE COMPARE · task linkati · LINK NON RISOLTI | — | `VaultBrowser.swift:193-218` |
| Inspector star | inspector | Aggiungi alle preferite / Togli dalle preferite | — | `VaultBrowser.swift:223-238` |
| Inspector CATEGORIA | inspector, note with `pergamenum-category` | category name (go to Tasks category) · Scollega la categoria; else AssignCategoryMenu | — | `VaultBrowser.swift:247-281` |
| Inspector CRONOLOGIA | inspector | summary «N versioni, l'ultima alle…» · Sfoglia… / «nessuna» | — | `VaultBrowser+History.swift:17-31` |
| NoteHistorySheet presentation | Sfoglia… / menu | restore · close | — | `VaultBrowser+History.swift:47-73` |
| MENZIONI NON LINKATE | inspector | Cerca nel vault → rows (open) · Collega (LinkMentionSheet) · Cerca di nuovo | — | `UnlinkedMentionsSection.swift:34-217` |
| DOVE COMPARE | inspector | Cerca dove compare → BOARD rows · PRATICHE rows · message rows · Cerca di nuovo | — | `WhereNoteAppearsSection.swift:23-162` |
| LINK NON RISOLTI | inspector | per row: Crea nota (if creatable) · Vai al link | — | `UnresolvedLinksSection.swift:14-51` |
| QuickSwitcher sheet | toolbar Vai alla nota / menu | field «Vai alla nota, o a una sezione con #…» · Nota di oggi · RECENTI · PREFERITE · TUTTE LE NOTE · Crea la nota «X» · heading groups · legend | Invio (onSubmit) · Esc (onExitCommand) | `QuickSwitcher.swift:36-122,160-194` |
| RelatedLinkSheet | menu «Nota correlata» | search field · list · motivo · motivo del ritorno · Annulla · Collega | Annulla `.cancelAction`, Collega `.defaultAction` | `RelatedLinkSheet.swift:33-92` |
| TemplateSheet | menu «Applica un template» | template rows (insert at caret) · Annulla | Annulla `.cancelAction` | `TemplateSheet.swift:23-61` |
| NoteBirthPresentation strip | after a note is created | creation toast · Annulla (refusal sentence) | — | `VaultBrowser+NoteBirth.swift:14-41` |
| ExtractNoteSheet | «Estrai in una nota» | composer (extract host); half-done: Chiudi | Chiudi `.defaultAction` | `VaultBrowser+NoteBirth.swift:47-83` |
| NoteTabBar | top of editor column | tab chip (click select, double-click make stable) · close xmark «Chiudi la tab» · unsaved dot · Salva chip / Salvato · frontmatter toggle | — | `NoteTabBar.swift:73-147,190-258` |
| NoteRowMenu context menu | right-click note row in tree | Apri · Apri in una nuova tab · Aggiungi/Togli preferite · Rinomina… · Sposta in ▸ (radice), folders · row commands · Mostra nel Finder · Elimina… | — | `NoteRowMenu.swift:28-76` |
| RenameNoteSheet | Rinomina… | title field · Annulla · Rinomina | Annulla `.cancelAction` | `NoteRowMenu.swift:100-123` |
| Folder row context menu | right-click folder row | Nuova nota qui · Comprimi/Espandi · Sposta in ▸ · Mostra nel Finder | — | `NoteTreeRow.swift:129,150-189` |
| Folder/note rows | tree | chevron tap / double-tap · drag · drop target | — | `NoteTreeRow.swift:80-147,214-247` |
| StarredPane | sidebar Preferite | rows (open) · context menu Togli dalle preferite · theme toggle | — | `StarredPane.swift:34-89` |
| OutlinePane | Note sidebar | INDICE · rows (jump) · chevron Espandi/Ripiega la sezione · double-click fold · drag heading · nest drop · gap drop | — | `OutlinePane.swift:53-290` |
| Table grid | closed GFM table in editor | cells · Riga [+][-] · Colonna [+][-][…] | Tab/Shift-Tab between cells, Tab past last / Shift-Tab before first / Enter / Esc leave | `TableGridView.swift:113-135`, `TableGridView+CellCommit.swift:36-59` |
| Table column menu | `…` button or right-click header cell | Allinea a sinistra · al centro · a destra · Ordina A→Z · Ordina Z→A | — | `TableGridView+ColumnMenu.swift:10-51`, `TableColumnMenu.swift` |
| Fence context menu | right-click inside closed fence | AppKit menu + Copia il blocco | — | `NoteTextView+FenceMenu.swift:8-30` |
| Embed context menu | secondary click on drawn embed | EmbedContextMenu items | — | `NoteTextView+EmbedChip.swift`, `+Embeds.swift` |
| Link choice menu | click on ambiguous/missing link | LinkChoiceMenu choices | — | `NoteTextView+LinkNavigation.swift:59` |
| Link preview | Cmd+hover link | preview popover | Cmd (hover) | `NoteTextView+LinkPreview.swift` |
| View block «Modifica query» | header of drawn `pergamenum-view` | Modifica query → ViewQueryEditRequest sheet | — | `NoteTextView+ViewBlocks.swift:288-297`, `ViewQueryEditRequest.swift` |
| Transclusion (editor) | `![[nota]]` line | rendition under line · caption in collapsed row · «… apri la nota» · click opens | — | `TranscludedLineFragment.swift:124-191` |
| TranscludedNoteView (reading surfaces) | `![[nota]]` in block views | loading placeholder · header (open) · body · apri la nota · link (depth one) · missing note/section | — | `TranscludedNoteView.swift:72-173` |
| Find bar inputs | Modifica › Trova | matches/replace/jump | — | `NoteTextView+Inputs.swift:11-32` |

### Colours, fonts, spacings not from a token

| value | file:line | note |
|---|---|---|
| caption font `.systemFont(ofSize: 10)` | `TranscludedLineFragment.swift:34` | finding 06 |
| gutter 16, rule 3, padding 8, max body 320 | `TranscludedLineFragment.swift:28-38` | geometry |
| `ruleColor .separatorColor`, `captionColor .secondaryLabelColor` defaults | `TranscludedLineFragment.swift:21-22` | overridden from tokens at `+Transclusion.swift:330-331` |
| alpha 0.35 on accent | `NoteTextView+Transclusion.swift:330`, `TranscludedNoteView.swift:101` | duplicated literal |
| radius 1.5, width 3, height 24, max 320 | `TranscludedNoteView.swift:60,82,100-102` | radius in PG-262 |
| Metrics (row 24, inset 6, column 72–220, control 18/3/24, gaps 4/14, pill 6/2/6, slop 3) | `TableGridView.swift:28-56` | grid geometry |
| default colours `.separatorColor/.labelColor/.secondaryLabelColor/.tertiaryLabelColor`, fonts `.systemFont(13)` | `TableGridView.swift:86-106` | overwritten by `update(with:theme:)` (`+Rendering.swift:22-37`) |
| `lineWidth = 1` pill stroke | `TableGridView.swift:223` | |
| max 320, min 24, unmeasured 120 | `ViewBlockAttachment.swift:51-59` | |
| pane widths 190/230/320, editor min 360, dot 6, category dot 8 | `VaultBrowser.swift:25,29,32,106,255` | |
| sheet width 460, list height 220, spacing 2 | `TemplateSheet.swift:25,48,59` | PG-262 |
| sheet width 460 | `NoteRowMenu.swift:123` | PG-262 |
| 560×380, icon width 14 | `QuickSwitcher.swift:44,102` | PG-262 |
| width 560, list height 150 | `RelatedLinkSheet.swift:56,92` | PG-262 |
| maxWidth 780 | `StarredPane.swift:34` | |
| tab paddings 2/3, minWidth 64, dot 8, maxWidth 160 | `NoteTabBar.swift:57,86,101,135,195,218,240` | PG-262 literals |
| indent 14, stroke 1 | `NoteTreeRow.swift:68,115` | |
| chevron width 12, padding 3, stroke 2, gap 2/2/min 6 | `OutlinePane.swift:165,172,194,250,281,283,285` | |
| paddings 6/2/1 | `UnlinkedMentionsSection.swift:95,122,147,153-154,199`, `UnresolvedLinksSection.swift:42,57-58`, `WhereNoteAppearsSection.swift:120,129,154` | PG-262 literals |
| gap 6, margin 8 | `PanelPlacement.swift:21-22` | pure placement helper |
| bar width 2 | `QuoteGeometry.swift:20` | |

No hardcoded colour found in a view in this slice: every colour drawn goes through `theme.color(...)` or is pushed in from one.

# S10-workspace

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Workspace pane | app sidebar «Workspace» | top bar, tree, divider, tool column, board, tray | none | `Sources/Features/Workspace/WorkspaceView.swift:141` |
| Window toolbar (Workspace) | Workspace pane | Annulla, Ripeti, Anteprima, «Nuovi elementi» (`workspace-tray-toggle`), «Concentrazione» (`workspace-focus-toggle`), «Albero» (`workspace-tree-toggle`), theme toggle | Cmd+Z, Cmd+Shift+Z | `Sources/Features/Workspace/WorkspaceView+Toolbar.swift:11-78` |
| Empty state | pane with no board selected | creation prompts | none | `Sources/Features/Workspace/WorkspaceView.swift:226-237` |
| BoardTopBar (breadcrumb + save indicator) | always above the pane | ancestor crumbs (links), last crumb (plain), «Salvato» / «Salvataggio…» / «Conflitto» + «Mantieni le mie modifiche» (`board-conflict-keep-local`) + «Ricarica dal disco» (`board-conflict-reload`) | none | `Sources/Features/Workspace/BoardChrome.swift:15`, `:43-66` |
| BoardToolbar (tool column) | board open | tool buttons 30x30 (select, sticky, text, to-do, note, link, folder, image, pen, …) | bare-key tool shortcuts, suspended while `isEditingText` | `Sources/Features/Workspace/BoardChrome.swift:89`, `:100`, `:135-140` |
| BoardZoomControls | floating on the board | «Riduci» (`board-zoom-out`), zoom level, «Ingrandisci», «Adatta alla finestra» (`board-zoom-fit`) | none | `Sources/Features/Workspace/BoardChrome.swift:150-174` |
| BoardPenControls | pen tool active | 4 colours, 3 widths, «Gomma», «Fatto» | none | `Sources/Features/Workspace/BoardChrome.swift:189-246`, `:270` |
| Floating controls container | board open | zoom controls, pen controls, card bar | none | `Sources/Features/Workspace/WorkspaceView+Board.swift:117-136` |
| BoardCardControls (card bar, `board-card-bar`) | card selected | card command buttons | none | `Sources/Features/Workspace/BoardCardControls.swift:18`, `:52` |
| Card context menu | right-click on a card | card commands (`BoardCardMenu.swift:255`), «Colore» (Nessuno + 6 presets), «Colore testo», «Allineamento» (Naturale, Sinistra, Centro, Destra, Giustificato), «Ripiega titoli» toggles, «Ridimensiona» presets, «Adatta al ritaglio», «Ritaglia», «Rimuovi ritaglio» | none | `Sources/Features/Workspace/BoardContentLayer.swift:112` → `Sources/Features/Workspace/BoardCardMenu.swift:222-395` |
| «Ridimensiona» size presets | card context menu | preset sizes | none | `Sources/Features/Workspace/BoardContentLayer.swift:288-291` |
| BoardCropEditor | «Ritaglia» on an image card | drag rectangle, corner grips (`CropHandleView`), hidden confirm/cancel buttons | Return confirms, Esc cancels | `Sources/Features/Workspace/BoardCropEditor.swift:14`, `:141`; `Sources/Features/Workspace/WorkspaceView+Board.swift:105-114` |
| Marquee / alignment guides | drag on empty canvas / drag a card | none | none | `Sources/Features/Workspace/BoardOverlays.swift:8`, `:34` |
| Format bar (card) | text editing in a sticky/text card | Grassetto, Corsivo, Barrato, Elenco puntato, Elenco numerato, Titolo (`card-format-<id>`) | Cmd+B, Cmd+I (in the text view) | `Sources/Features/Workspace/BoardOverlays.swift:76` → `Sources/Features/Workspace/BoardFormatBar.swift:217` → `Sources/Features/Workspace/CardFormatBar.swift:88-121`; `Sources/Features/Workspace/FormattingTextView.swift:341-350` |
| Card text editor | double-click a sticky/text card, «Modifica testo» | free text, list editing, fold | Esc ends editing | `Sources/Features/Workspace/CardTextView.swift:1`; `Sources/Features/Workspace/FormattingTextView.swift:40-50` |
| Link card title field | «Rinomina» on a link card | TextField | Return commits, Esc discards | `Sources/Features/Workspace/NodeCard.swift:176-194` |
| Wikilink completion popup | typing `[[` in a card | candidate rows (notes, boards) | arrows, Return, Esc | `Sources/Features/Workspace/BoardWikilinkCompletionLayer.swift:139-208` |
| Edge layer | canvas edges | none (labels drawn) | none | `Sources/Features/Workspace/BoardEdgeLayer.swift:8` |
| Drawing layer | pen tool | strokes | none | `Sources/Features/Workspace/WorkspaceView+Drawing.swift:6-25` |
| BoardTray (`board-tray`) | toolbar «Nuovi elementi» | NUOVI ELEMENTI items, linked tasks panel, TASK ASSEGNATI, NOTE REFERENZIATE (note rows) | none | `Sources/Features/Workspace/BoardTray.swift:65-89`, `:76-79`, `:99-147`, `:162-199`, `:238-265` |
| NewCanvasItemSheet | creating a folder/link/note card | name field, Annulla, Crea | Esc (cancelAction), Return (defaultAction) | `Sources/Features/Workspace/BoardSheets.swift:6`, `:68-93` |
| ImportSheet | drop or «Importa immagini» | proposal rows (name fields), Annulla, Importa | Esc, Return | `Sources/Features/Workspace/BoardSheets.swift:106-143` |
| «Importa immagini» open panel | tool column image tool | system open panel | none | `Sources/Features/Workspace/WorkspaceView+Creation.swift:41-46` |
| DocumentComposerSheet | new note card from the board | composer, «Apri», «Fine» | Return («Fine», defaultAction), Esc | `Sources/Features/Workspace/WorkspaceView+Creation.swift:121-175` |
| Workspace tree header | tree visible | filter field (`workspace-filter`) | none | `Sources/Features/Workspace/WorkspaceBrowser.swift:245-261` |
| Workspace tree toolbar | below the tree | «Nuova board…» (`workspace-new`), «Nuova cartella…» (`workspace-new-folder`), «Rinomina board/cartella…» (`workspace-rename`), «Elimina …» (`workspace-delete`), «Espandi tutto», «Comprimi tutto» | none | `Sources/Features/Workspace/WorkspaceBrowser.swift:226-241` → `Sources/Features/Workspace/WorkspaceBrowserToolbar.swift:35-68` |
| Tree list context menu | right-click on blank list area | «Espandi tutto», «Comprimi tutto» | none | `Sources/Features/Workspace/WorkspaceBrowser+Rows.swift:66-69` |
| Tree row | tree | chevron (tap expands, double-tap), row click opens | none | `Sources/Features/Workspace/WorkspaceRow.swift:25`, `:262-272` |
| Tree row context menu | right-click on a row | «Rinomina…», «Elimina…», «Sposta in ▸» | none | `Sources/Features/Workspace/WorkspaceRow.swift:289-300` |
| «Sposta in ▸» submenu (`workspace-move-menu`) | row context menu | destination folders | none | `Sources/Features/Workspace/WorkspaceRow+Move.swift:123-133` |
| Row/root drag-and-drop | drag rows | drop on folder row, drop on list root | none | `Sources/Features/Workspace/WorkspaceRow+Move.swift:76-93`; `Sources/Features/Workspace/WorkspaceBrowser+Rows.swift:59-61` |
| NewWorkspaceSheet (`workspace-new-sheet`) | «Nuova board…» / «Nuova cartella…» | Nome (`workspace-new-name`), Picker «Dentro» (`workspace-new-parent`), Annulla, Crea | Esc, Return | `Sources/Features/Workspace/WorkspaceBrowser.swift:141-158` → `Sources/Features/Workspace/WorkspaceFolderSheets.swift:175-216` |
| RenameWorkspaceSheet (`workspace-rename-sheet`) | «Rinomina…» | Nome (`workspace-rename-name`), Annulla, Rinomina | Esc, Return | `Sources/Features/Workspace/WorkspaceBrowser.swift:162-178` → `Sources/Features/Workspace/WorkspaceFolderSheets.swift:268-296` |
| Delete confirmation dialog | «Elimina…» | «Sposta nel Cestino» (`workspace-delete-confirm`), Annulla | Esc | `Sources/Features/Workspace/WorkspaceBrowser.swift:183-203` |
| Move-conflict alert | a refused move | «Spostamento rifiutato», OK | Return | `Sources/Features/Workspace/WorkspaceBrowser.swift:208-221` |
| WorkspacePaneDivider | between tree and board | drag to resize (160...420) | none | `Sources/Features/Workspace/WorkspacePaneDivider.swift:36-55` |

### Colours, fonts and sizes not from a token

| value | where | note |
|---|---|---|
| `RGBA(hex: "#E8E5DF")!` | `StickyTextCard.swift:138` | S10-workspace-05 |
| `Color(.sRGB, …)` from the file's hex | `StickyTextCard.swift:139` | user colour from `.canvas`, by design |
| six preset hexes | `CardTextStyle.swift:62` | JSON Canvas presets, deliberate per ADR-0027 §D4 |
| `Color(hex: stroke.color)` | `WorkspaceView+Drawing.swift:16` | ink colour stored in the SVG, by design |
| highlighter opacity `0.4`, eraser radius `max(8, penWidth * 3)` | `WorkspaceView+Drawing.swift:43`, `:33` | |
| `.opacity(0.7)` over `canvasBackground` | `BoardCropEditor.swift:88` | |
| `.opacity(0.12)`, `dash: [4, 3]` | `BoardOverlays.swift:21`, `:54` | marquee fill / guides |
| `.opacity(0.4)` | `WorkspaceBrowserToolbar.swift:94` | disabled tint |
| `lineWidth: 1.5` | `BoardCropEditor.swift:111`; `BoardEdgeLayer.swift:41,77,121` | |
| `lineWidth: 1` / `2` | `BoardContentLayer.swift:96,232`; `BoardWikilinkCompletionLayer.swift:177`; `BoardOverlays.swift:22`; `NodeCard.swift:130,163,209`; `WorkspaceRow+Move.swift:82`; `WorkspaceView+Board.swift:191` | |
| `dash: [5, 4]`, arrow `length = 10`, `.padding(.horizontal, 4)` | `BoardEdgeLayer.swift:77`, `:106`, `:51` | |
| `cornerRadius: 3`, `spacing: 3`, `spacing: 2` | `NodeCard.swift:80,261`, `:99`, `:147` | PG-262 |
| `spacing: 8`, `30x30`, `.padding(2)`, `width: 44`, divider heights 12/14 | `BoardChrome.swift:53`, `:100`, `:117`, `:145`, `:170,226,238,245` | partly PG-262 |
| sheet widths 460 / 560, `spacing: 2`, `maxHeight: 240` | `BoardSheets.swift:60`, `:141`, `:122`, `:131`; `WorkspaceFolderSheets.swift:209,292` | PG-262 |
| tray width 200 | `BoardTray.swift:86` | |
| row height 28, width 240, gap 4 | `BoardWikilinkCompletionLayer.swift:24-26` | |
| `.padding(.vertical, 4)`, button 26x22 | `CardFormatBar.swift:95`, `:107` | PG-262 (`:95`) |
| pill 208x30, gap 8 | `BoardFormatBar.swift:41`, `:45` | |
| `textContainerInset` 2x2 | `CardTextView.swift:123` | |
| `.padding(2)` | `StickyTextCard.swift:123` | |
| button 22x22 | `WorkspaceBrowserToolbar.swift:86` | PG-262 |
| min/max 160/420, hit 10, line 1 | `WorkspacePaneDivider.swift:18,20,28,30` | |
| row indent 14 | `WorkspaceRow.swift:63` | |
| grid step 24, fit margin 80 | `WorkspaceController.swift:552`; `WorkspaceController+Viewport.swift:52` | geometry constants |
| min card 40x30, handle 10/24, group band 16, placeholder zoom 0.25 | `BoardGeometry.swift:31,43,46,49,262` | geometry constants |
| card size presets | `BoardContentLayer.swift:288-291` | |
| `Color.clear` (hit areas) | `BoardContentLayer.swift:95`; `BoardChrome.swift:104`; `CardFormatBar.swift:109`; `BoardWikilinkCompletionLayer.swift:205`; `WorkspaceRow+Move.swift:82`; `WorkspacePaneDivider.swift:42`; `BoardCropEditor.swift:120` | neutral, acceptable |

# S11-pratiche-features

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Pratiche pane (`PratichePane`) | app sidebar «Pratiche» (LAVORO) | top bar · Full Disk Access banner (when `.notGranted`) · problem line · `HSplitView` list column (hidden when `isNotesFocused`) · content · inspector (when `isShowingPraticaInspector`) | — | `PratichePane.swift:44-73` |
| Top bar / breadcrumb (`PraticaTopBar`) | pane | crumbs «Pratiche › Cliente › Pratica» (ancestor click → no selection) · status pill · «Aggiorna ora» · progress «n di N» + «Annulla» (while a sync reports) · «Filtra» field · sender menu · «Solo con allegati» toggle · «Nota della pratica» inspector toggle | filter focus through `filterFocus` (bound by the app, Task 7) | `PraticaTopBar.swift:23-43,103-116,126-133,146,161-174,178-184,188-196` |
| Status pill menu | top bar | `PraticaCommand.available(isActive:)` reduced to the status verbs: «Chiudi» or «Riapri» | — | `PraticaTopBar.swift:65-83`, `PraticaCommand.swift:20-21,83-88` |
| Full Disk Access banner (`FullDiskAccessBanner`) | pane, probe `.notGranted` | «Come fare» disclosure · «Apri Impostazioni di Sistema» · numbered steps when open | — | `FullDiskAccessBanner.swift:30-50` |
| List column (`PraticheListColumn`) | pane | header «Pratiche» + «n pratiche» · toolbar «Nuova pratica…» (plus) · «Aggiorna tutte le pratiche» · `ChronologicalOrderMenu` · «Filtra pratiche» field · client rows (chevron toggles the group) · pratica rows (tray dot, title, day, badge) · «Chiuse n» row (toggle) | Cmd+Opt+P for «Nuova pratica…» (declared in the app's `ShortcutCommand`, cited at `:23`) | `PraticheListColumn.swift:36-50,52-66,68-101,103-109,111-135,139-161,166-190` |
| Pratica row context menu | right-click on a pratica row | `PraticaMenuItems.menu`: «Apri» · «Rinomina…» · «Chiudi» or «Riapri» · «Aggiorna ora» · «Mostra nel Finder» · «Collega una nota…» · «Collega un task…» · «Collega una board…» · «Elimina…» | — | `PraticheListColumn.swift:186`, `PraticaMenuItems.swift:13-27`, `PraticaCommand.swift:14-53,83-88` |
| Empty state | pane with no selection | «Scegli una pratica o creane una nuova» · «Nuova pratica…» · «Aggiungi da Mail…» | — | `PratichePane+Inspector.swift:19-34` |
| Tray «Da smistare» (`PraticaTrayStrip`) | above the timeline when proposals exist | header toggle «Da smistare» + count (collapsible, per window) · per proposal: subject, address, date range, count · «Aggiungi» (`.borderedProminent`, default) · «Ignora» | Return → «Aggiungi» when the strip has focus | `PraticaTrayStrip.swift:80-93,103-122` |
| Timeline (`PraticaTimelineView`) | pane content with a selection | `List(selection:)` of message and entry rows, day sections, rail · «I filtri attivi nascondono tutte le righe.» when filtered empty · counts bar «n messaggi · n voci · n allegati» · «Nota» · «Telefonata» | Backspace → «Escludi» on the selected message (ADR-0070, `takeDeleteKeyTarget`) · Opt+click expands/collapses every row (`ExpansionState`) · double-click or Return toggles a row (DESIGN.md:28) | `PraticaTimelineView.swift:49-61,92-96,108-114,189,262,273-283,296-309` |
| Message row (`PraticaMessageRow`) | timeline | chevron · time · sender · subject (link → «Apri in Mail») · attachment chips · first line; expanded: body (or «Corpo non ancora scaricato») · «Testo citato» disclosure · footer «Apri in Mail» · «Aggiungi nota» · «Altro» ▸ (Anteprima allegato · Escludi dalla pratica · Sposta in ▸ · Aggiungi anche a ▸ · Rigenera… · Aggiungi telefonata · Collega una nota… or Scollega nota) · fallback «Apri in Mail» alone for a message not in Mail | — | `PraticaMessageRow.swift:86-94,131-146,187,212-219,252-289`, `MessageCommand.swift:10-49,122-127` |
| Message row context menu | right-click on a message row | the full `MessageCommand.available` catalogue in declaration order (Apri in Mail · Anteprima allegato · Escludi dalla pratica · Sposta in ▸ · Aggiungi anche a ▸ · Rigenera… · Aggiungi nota · Aggiungi telefonata · Collega una nota… or Scollega nota) · «Inserisci qui» ▸ (Nota · Telefonata) when a next row exists | — | `PraticaTimelineView.swift:189,219,237-243`, `PraticaMenuItems.swift:31-90` |
| Entry row (`PraticaEntryRow`) | timeline (manual note or call) | chevron · orphan marker · body or «Nessun testo in questa voce.» · «Apri la nota della pratica» · context menu «Collega a un messaggio…» · «Scollega dal messaggio» (when anchored) · «Inserisci qui» ▸ | — | `PraticaEntryRow.swift:43,70,77-85,119-126`, `PraticaEntryCommand.swift:12-19,39-46`, `PraticaMenuItems.swift:95-102` |
| Linked-note slot (`PraticaMessageNoteSlot`) | message row with `linkedNote` | note title button (opens the note) · «nota non trovata nel vault» | — | `PraticaMessageNoteSlot.swift:50-86` |
| Attachment chip (`AttachmentChip`) | message row | click → Quick Look preview · AppKit context menu (right-click or Ctrl-click): «Anteprima allegato» · «Apri» · «Mostra nel Finder» · «Copia» · refusal alert «Mostra nel Finder» / «OK» | — | `AttachmentChip.swift:53,72,90-91`, `AttachmentChipMenuHost.swift:32,55-56`, `AttachmentChipModel.swift:136-151` |
| Inspector («Nota della pratica») | top-bar toggle, `navigation.isShowingPraticaInspector` | «Apri nell'editor» · links summary «n note · n task · n board» (click scrolls) or «nessun collegamento» · body (`MarkdownBlocksView`) or «Nessuna pratica scelta.» · sections NOTE COLLEGATE · TASK COLLEGATI · BOARD COLLEGATE with one open button per row | — | `PratichePane+Inspector.swift:40-90`, `PratichePane+LinksSummary.swift:29-49`, `PratichePane+Links.swift:22-30,100-211` |
| Rename sheet | «Rinomina…» | «Rinomina la pratica» · «Nome» field · «Annulla» · «Rinomina» | Esc · Return | `PratichePane+Sheets.swift:40-62` |
| Deletion alert «Eliminare «…»?» | «Elimina…» | «Elimina» (destructive) · «Annulla» · message «La cartella, i messaggi e gli allegati vanno nel Cestino.» | — | `PratichePane.swift:92-111` |
| Regeneration sheet, preparing | «Rigenera…» | «Rigenerare «subject»?» · spinner «Sto leggendo il messaggio da Mail…» · «Annulla» | Esc | `PratichePane+Sheets.swift:82-99` |
| Regeneration sheet, ready | after the preview | «Rigenerare «file»?» · «Le modifiche fatte a mano … vanno perse.» · consequences (Allegati riscritti · Riscrive anche il file .eml originale) · `DiffView` · «Annulla» · «Rigenera», or «Il file è già identico…» · «Chiudi» | Esc · Return | `PratichePane+Sheets.swift:105-155` |
| Message picker («Collega a un messaggio») | entry row «Collega a un messaggio…» | «Filtra» field · rows «data · mittente» (click anchors) · «Chiudi» | Esc | `PraticaMessagePicker.swift:33-113` |
| «Aggiungi a pratica da Mail» sheet (`AddToPraticaSheet`) | File menu · Cmd+Shift+P · empty state «Aggiungi da Mail…» | «Filtra pratiche» field · pratica list · «Nuova pratica…» · «Annulla» · «Aggiungi» | Cmd+Shift+P (declared in the app, cited at `PratichePane.swift:169`) · Esc · Return | `AddToPraticaSheet.swift:38-45,66,105,170-174` |
| «Nuova pratica…» wizard (`NuovaPraticaWizard`) | File menu · Cmd+Opt+P · list «plus» · empty state · AddToPratica «Nuova pratica…» | eyebrow «PASSO n DI 3» or «DI 4» · title · step 1 «Titolo» · «Cliente» + «Clienti esistenti» menu · «Cartella radice» + «Impostazioni» link · step 2 «Dalla selezione di Mail» · «Cerca nella posta…» · «Più tardi» · counterpart chips · «Aggiungi un indirizzo» + «Aggiungi» · step 3 proposals checklist · «Parole chiave» · step 4 (when offered) new-counterpart checkboxes · «e altri n indirizzi ignorati» · footer «Annulla» · «Indietro» · «Continua» or «Crea» | Esc · Return | `NuovaPraticaWizard.swift:44-69`, `NuovaPraticaWizard+Steps.swift:15-37,56-87,130-149,179,225-247` |
| Mail seed picker («Cerca nella posta») | wizard step 2 «Cerca nella posta…» | «Indirizzo della controparte» field · «Cerca» · results or «Nessuna conversazione con questo indirizzo negli ultimi n giorni.» · «Annulla» · «Usa questa conversazione» | Esc · Return | `MailSeedPicker.swift:167-232` |
| Link picker (`PraticaLinkPicker`) | «Collega una nota…» · «Collega un task…» · «Collega una board…» | «Filtra» field · candidate list · «Crea nuova…» → sub-sheet «Annulla» · «Crea» · «Chiudi» | Esc · Return (sub-sheet) | `PraticaLinkPicker.swift:66-73,109,145,250-251,342-349` |
| Mail drop report line | a drag from Mail dropped on the timeline (R-22 tracer bullet) | «summary Per ora usa «Aggiungi a pratica da Mail…» (Cmd+Shift+P).» | — | `PratichePane.swift:168-174,186`, `MailDropReceiver.swift:20-33` |

Not in this slice: the Settings tab «Pratiche» (`Sources/Features/Settings/PraticheSettingsTab.swift`) and the menu-bar declarations of Cmd+Opt+P / Cmd+Shift+P (`ShortcutCommand`, App slice).

Colours, fonts and spacings not from a token (no palette colour and no font outside the tokens was found; the rows are literal sizes):

| file:line | value | what | note |
|---|---|---|---|
| `PratichePane.swift:64,67,70` | `minWidth 190 / idealWidth 260 / maxWidth 320`, `minWidth 360`, `190 / 280 / 320` | column widths | DESIGN.md's own binding numbers, literal in the view |
| `PratichePane+Sheets.swift:58,96,152` | `.frame(width: 420)`, `.frame(width: 440)` ×2 | rename and regeneration sheet widths | PG-262 (open) |
| `PraticaMessagePicker.swift:40`, `PraticaLinkPicker.swift:73,349`, `AddToPraticaSheet.swift:45`, `MailSeedPicker.swift:178`, `NuovaPraticaWizard.swift:69` | `380×380`, `380×380`, `360`, `520×460`, `520×420`, `560×520` | picker, sheet and wizard frames | PG-262 (open) |
| `PratichePane+Inspector.swift:59` | `.easeOut(duration: 0.2)` | links-summary scroll | PG-264 (open) |
| `PraticaTopBar.swift:76,153` | `.padding(.vertical, 2)` | status pill, sync status | — |
| `PraticaTopBar.swift:149` | `.frame(width: 140)` | «Filtra» field width | — |
| `PraticaTrayStrip.swift:65,120` | `.padding(.vertical, 2)` | tray header, proposal row | — |
| `PraticaTrayStrip.swift:103`, `PraticheListColumn.swift:174`, `AddToPraticaSheet.swift:120`, `MailSeedPicker.swift:207`, `NuovaPraticaWizard+Steps.swift:136,190` | `spacing: 1` | two-line row stacks | — |
| `PraticaMessageNoteSlot.swift:60,75`, `FullDiskAccessBanner.swift:47`, `AddToPraticaSheet.swift:65` | `spacing: 2` | slot, how-to steps, sheet header | — |
| `AttachmentChip.swift:60` | `.padding(.vertical, 2)` | chip | — |
| `PraticheListColumn.swift:172` | `.frame(width: 6, height: 6)` | tray dot | colour is `accentPrimary` through the token |
| `PraticaMessageRow.swift:60` | `.opacity(isPending ? 0.6 : 1)` | pending row dimming | — |
| `PraticaTimelineModel+Rail.swift:87,96` | `railLineWidth 2`, `railRowInset 4` | rail geometry constants (model, ADR-0079) | colours through `railReceived`/`railSent` |
| `PraticaTimelineView.swift:206-207`, `PraticaMessageNoteSlot.swift:58` | `Color.clear` + `.frame(height: 0)` | layout placeholders | not a palette colour |

# S12-today-diary-tasks-recordings

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Diario pane | sidebar «Diario» | timeline, entry cards, live preview | — | `Sources/Features/Diary/DiaryView.swift:63` |
| Diario toolbar (navigation) | Diario pane | Giorno precedente · Oggi · Giorno successivo · Vai a data | — | `Sources/Features/Diary/DiaryToolbar.swift:24` |
| Diario toolbar (primary) | Diario pane | Nuovo blocco · theme toggle | — | `Sources/Features/Diary/DiaryToolbar.swift:53` |
| Diario go-to-date sheet | toolbar «Vai a data» | date picker · Annulla · Vai | Esc / Enter | `Sources/Features/Diary/DiaryView.swift:63`, `Sources/Features/Today/GoToDateSheet.swift:46` |
| Diario entry sheet | «Nuovo blocco», card «Modifica…» | Ora · Minuti · Durata pickers · colour buttons · note · Elimina · Annulla · Salva | Esc / Enter | `Sources/Features/Diary/DiaryEntrySheet.swift:49`, `:98`, `:142` |
| Diario entry card context menu | right-click on card | Modifica… · Elimina | — | `Sources/Features/Diary/DiaryEntryCard.swift:101` |
| Diario entry card hover remove | hover card | remove (x) | — | `Sources/Features/Diary/DiaryEntryCard.swift:144` |
| Diario conflict banner | file changed on disk under unsaved diary | Ricarica da disco · Tieni la mia versione | — | `Sources/Features/Diary/DiaryView+Conflict.swift:16` |
| Oggi pane | sidebar «Oggi» | day/week/month timeline, references, mini calendar | — | `Sources/Features/Today/TodayView.swift:83` |
| Oggi toolbar (principal) | Oggi pane | Precedente · Oggi · Successivo · Vai a data · Scala picker (Giorno/Settimana/Mese) | — | `Sources/Features/Today/DayToolbar.swift:28` |
| Oggi toolbar (primary) | Oggi pane | Nuovo task · Solo in scadenza toggle · Completati toggle · Nuovo evento · Aggiorna da EventKit · theme toggle | — | `Sources/Features/Today/DayToolbar.swift:69` |
| Oggi go-to-date sheet | toolbar «Vai a data» | date picker · Annulla · Vai | Esc / Enter | `Sources/Features/Today/GoToDateSheet.swift:32` |
| New event/reminder draft sheet | «Nuovo evento», click on hour row | title · Ora picker · Durata picker · Annulla · Crea | Esc / Enter | `Sources/Features/Today/TodayView.swift:277` |
| Daily note link | Oggi header | Apri la nota di… | — | `Sources/Features/Today/TodayView.swift:253` |
| Event context menu (day timeline) | right-click on event | Apri la nota dell'evento / Nota per questo evento · calendar day items | — | `Sources/Features/Today/DayTimeline.swift:81`, `:111`, `:223` |
| Calendar access prompt | timeline without access | request access · open Privacy settings | — | `Sources/Features/Today/DayTimeline.swift:256`, `:264` |
| Time block context menu | right-click on block | block verbs · Rimuovi | — | `Sources/Features/Today/TimelineBlockBox.swift:54`, `:72` |
| References task row | Oggi references list | open task · context menu · Porta a oggi · Inserisci blocco tempo · due-day button · remove block | — | `Sources/Features/Today/DayReferences.swift:85`, `:96`, `:126`, `:144`, `:169`, `:214` |
| Day column menu | week view column header | day verbs | — | `Sources/Features/Today/DayColumnMenu.swift:15` |
| Calendar day menu items | event/day menus | entries from `CalendarDayCommand` (title, enabled) | — | `Sources/Features/Today/CalendarDayMenuItems.swift:36` |
| Week view | Scala «Settimana» | day columns, entry rows, column menu | — | `Sources/Features/Today/WeekView.swift:67`, `:95`, `:137` |
| Month view | Scala «Mese» | day cells, context menu | — | `Sources/Features/Today/MonthView.swift:79`, `:94`, `:126` |
| Day month section | Oggi sidebar | month day buttons | — | `Sources/Features/Today/DayMonthSection.swift:54` |
| Mini calendar | Oggi sidebar | previous month · next month · day cells | — | `Sources/Features/Today/MiniCalendar.swift:57`, `:63`, `:134` |
| Task drop banner | dragging a task over the timeline | drop target text / cancel | — | `Sources/Features/Today/TaskDropBanner.swift:34` |
| Attività pane | sidebar «Attività» | view sidebar, list, toolbar | — | `Sources/Features/Tasks/TasksView.swift:54` |
| Attività toolbar | Attività pane | new task, task commands on selection (six enabled by selection), list options | — | `Sources/Features/Tasks/TasksView.swift:82` |
| Task view sidebar | Attività pane | views with counts | — | `Sources/Features/Tasks/TaskViewSidebar.swift:17` |
| Category sidebar section | Attività sidebar | category rows · disclosure · implicit rows · archived group | — | `Sources/Features/Tasks/CategorySidebarSection.swift:26`, `:190`, `:206`, `:234` |
| Category row context menu | right-click on category | category verbs · Elimina (no confirmation) | — | `Sources/Features/Tasks/CategorySidebarSection.swift:164` |
| List controls menus | Attività list header | grouping / sorting / filter menus | — | `Sources/Features/Tasks/TaskListControls.swift:25` |
| Task row | Attività list | checkbox · title · Porta a oggi · context menu | — | `Sources/Features/Tasks/TasksView+Row.swift:20`, `:50` |
| Task row context menu | right-click on task | TaskCommand entries (Collega una board… · Vai alla nota di origine · Vai alla board collegata · Assegna una categoria… · Togli la categoria) and row verbs | — | `Sources/Features/Tasks/TasksView+Row.swift:152`, `Sources/Features/Tasks/TaskCommand.swift:31` |
| Due date sheet | row «aggiungi scadenza» | date picker · Chiudi | Esc | `Sources/Features/Tasks/TasksView+Row.swift:187`, `:209` |
| Category view header | selecting a category | category actions | — | `Sources/Features/Tasks/CategoryView.swift:88` |
| Category editor sheet | new/edit category | name · colour · parent · Annulla · Salva | Esc / Enter | `Sources/Features/Tasks/CategoryEditor.swift:71`, `:85`, `:87` |
| Category note picker | category editor | search · list · Annulla | Esc | `Sources/Features/Tasks/CategoryNotePicker.swift:34`, `:126` |
| Category picker | «Assegna una categoria…» | grouped list · Annulla | Esc | `Sources/Features/Tasks/CategoryPicker.swift:23`, `:101` |
| Workspace picker | «Collega una board…» | search · board list · Annulla | Esc | `Sources/Features/Tasks/WorkspacePicker.swift:26`, `:120` |
| Linked tasks panel | note/board inspector | checkbox · title · context menu | — | `Sources/Features/Tasks/LinkedTasksPanel.swift:27`, `:63`, `:94` |
| Task composer | Nuovo task (toolbar, capture) | title · destination picker · chips (schedule, due, reminder, category) · Crea · menu (Crea e apri / Crea e continua) | Enter | `Sources/Features/Tasks/TaskComposer.swift:34`, `Sources/Features/Tasks/TaskComposer+Footer.swift:43`, `:52`, `:56` |
| Destination picker | composer destination chip | search · note list | — | `Sources/Features/Tasks/TaskComposer.swift:194` |
| Schedule panel | composer schedule chip | month calendar · quick dates · time row | — | `Sources/Features/Tasks/TaskDatePanels.swift:9`, `Sources/Features/Tasks/MonthCalendar.swift:22`, `Sources/Features/Tasks/TaskTimeRow.swift:17` |
| Due panel | composer due chip | month calendar · clear | — | `Sources/Features/Tasks/TaskDatePanels.swift:221` |
| Reminder page | composer reminder chip | date/time · Fatto | Enter | `Sources/Features/Tasks/TaskDatePanels.swift:289`, `:331` |
| Registrazioni pane | sidebar «Registrazioni» | recordings list, health banner | — | `Sources/Features/Recordings/RecordingsPane.swift:45` |
| Registrazioni toolbar | Registrazioni pane | order menu · Aggiorna | — | `Sources/Features/Recordings/RecordingsPane.swift:58`, `:103`, `:113` |
| Plaud health banner | service unreachable/unhealthy | message · retry | — | `Sources/Features/Recordings/RecordingsPane.swift:159` |
| Delete confirmation dialog | row delete | Elimina · Annulla | — | `Sources/Features/Recordings/RecordingsPane.swift:76` |
| Recording row | Registrazioni list | Elabora / Rivedi / Rielabora / Apri nota buttons · context menu | — | `Sources/Features/Recordings/RecordingRow.swift:224`, `:246`, `:282` |
| Retry confirmation | row «Rielabora» | Rielabora · Annulla | — | `Sources/Features/Recordings/RecordingRow.swift:300` |
| Review sheet | row «Rivedi» | themes with task toggles · speaker renames · transcript preview · Annulla · Importa | Esc / Enter | `Sources/Features/Recordings/ReviewSheet.swift:178`, `:226`, `:253`, `:268`, `:277`, `:304`, `:309`, `:311` |

### Non-token values (colours: all through tokens, `.clear` only; fonts: all through `theme.font`/`themedText`)

| value | file:line |
|---|---|
| widths/heights 60/52, misc frames and paddings | `Sources/Features/Diary/DiaryTimeline.swift:15`, `:16`, `:124`, `:129`, `:159`, `:179`, `:184` |
| card frames, paddings, line widths | `Sources/Features/Diary/DiaryEntryCard.swift:34`, `:40`, `:84`, `:96`, `:113`, `:119`, `:128`, `:133`, `:149`, `:160` |
| sheet widths, picker widths, swatch sizes | `Sources/Features/Diary/DiaryEntrySheet.swift:64`, `:104`, `:113`, `:125`, `:132`, `:145`, `:172` |
| pane widths | `Sources/Features/Diary/DiaryView.swift:41`, `:43` |
| hour heights, gutters | `Sources/Features/Today/DayTimeline.swift:19`, `:127`, `:186`, `:206`, `:217` |
| entry box paddings/radii | `Sources/Features/Today/TimelineEntryBox.swift:51`, `:57`, `:66`, `:79`, `:84`, `:102` |
| block box sizes | `Sources/Features/Today/TimelineBlockBox.swift:79`, `:95` |
| row spacings | `Sources/Features/Today/WeekEntryRows.swift:31`, `:43`, `:87` |
| column spacings/widths | `Sources/Features/Today/WeekView.swift:27`, `:90`, `:108`, `:122`, `:163` |
| cell spacings/heights | `Sources/Features/Today/MonthView.swift:20`, `:23`, `:46`, `:61`, `:69`, `:107` |
| mini calendar spacings/sizes | `Sources/Features/Today/MiniCalendar.swift:27`, `:84`, `:110`, `:113`, `:118`, `:123` |
| section spacings | `Sources/Features/Today/DayMonthSection.swift:90` |
| pane widths/paddings | `Sources/Features/Today/TodayView.swift:141`, `:143`, `:176`, `:250`, `:303` |
| sheet width | `Sources/Features/Today/GoToDateSheet.swift:54` |
| glyph `"↗ "` as text | `Sources/Features/Today/DayReferences.swift:88` |
| width 380; swatch 16×16; lineWidth 2/0 | `Sources/Features/Tasks/CategoryEditor.swift:93`, `:144`, `:147` |
| picker frames 380×380 | `Sources/Features/Tasks/CategoryNotePicker.swift:42`, `Sources/Features/Tasks/CategoryPicker.swift:31`, `Sources/Features/Tasks/WorkspacePicker.swift:34` |
| dot 8×8; offset -4; lineWidth 1/2; ring 14×14 | `Sources/Features/Tasks/CategorySidebarSection.swift:109`, `:143`, `:282`, `:312`, `:315`, `:318` |
| dot 6×6 | `Sources/Features/Tasks/CategoryView.swift:175` |
| spacing 1 | `Sources/Features/Tasks/LinkedTasksPanel.swift:70` |
| grid min 34 / spacing 4; minHeight 32 | `Sources/Features/Tasks/MonthCalendar.swift:20`, `:68`, `:80`, `:97` |
| spacing 3; padding 6/2 | `Sources/Features/Tasks/TaskListControls.swift:71`, `:77` |
| spacing 4; padding 2 | `Sources/Features/Tasks/TaskComposer+Footer.swift:90`, `:112`, `:154` |
| width 520; height 260; width 360 | `Sources/Features/Tasks/TaskComposer.swift:52`, `:226`, `:228` |
| panel width 340 | `Sources/Features/Tasks/TaskDatePanels.swift:48`, `:284` |
| sidebar width 200 | `Sources/Features/Tasks/TaskViewSidebar.swift:58` |
| spacing 2; lineWidth 2; sheet width 320; glyphs `"↗ "`/`"▦ "` | `Sources/Features/Tasks/TasksView+Row.swift:32`, `:69`, `:94`, `:134`, `:141`, `:147`, `:213` |
| maxWidth 780 | `Sources/Features/Recordings/RecordingsPane.swift:52` |
| sheet 620×560; spacing 2 | `Sources/Features/Recordings/ReviewSheet.swift:186`, `:279` |

# S13-contenitore-designgallery

## Surface inventory

### Contenitore
| surface | opens from | verbs/buttons in order | keyboard shortcut | file:line |
|---|---|---|---|---|
| Pane (sidebar 230 · list · inspector 310) | sidebar «Vai a Contenitore» | n/a | Ctrl+Cmd+C per ADR-0071 `:369` (outside slice, not verified) | `ContenitoreView.swift:13-41` |
| Sidebar header | pane | «+» new container | none | `ContenitoreSidebar.swift:25-39` |
| Sidebar list | pane | «Da classificare» (count), container tree | none | `ContenitoreSidebar.swift:40-57` |
| Sidebar row menu | right-click container | Nuovo sottocontenitore…, Rinomina…, Sposta in ▸, Sposta nel Cestino… | none | `ContenitoreSidebar.swift:142-157` |
| Sidebar rename sheet / trash dialog | row menu | Annulla, Rinomina / Annulla, Sposta nel Cestino | Esc, Enter | `ContenitoreSidebar.swift:64-83` |
| Sidebar footer | pane | drop folder status, last import time | none | `ContenitoreSidebar.swift:168-177` |
| Documents header + filter bar | pane | scope title, list/grid, «＋ tag…», sort | none | `ContenitoreList.swift:47-72`, `ContenitoreFilterBar.swift:35,53-57` |
| Notice strip | ingest notices | per-notice trailing action | none | `ContenitoreNoticeStrip.swift:8-26,74-95` |
| Empty state | empty scope | text only | none | `ContenitoreList.swift:91-118` |
| List row | pane | thumbnail, name, subtitle | Backspace via `.onDeleteCommand` | `ContenitoreList.swift:169-175,195-244` |
| Grid cell | grid mode | tap select, double-tap open, badge | none | `ContenitoreGrid.swift:20,59-60,88-107` |
| Row context menu | right-click row | Classifica…, Apri, Apri scheda, Mostra nel Finder, Copia link Pergamenum, Rinomina…, Sposta in ▸, Divider, Sposta nel Cestino | none | `ContenitoreMenuItems.swift:11-29`, titles `ContenitoreCommand.swift:32-39` |
| «Documento» menu | menu bar | same catalogue | Cmd+Opt+K Classifica…, Cmd+Opt+O Apri scheda | `ContenitoreMenuItems.swift:60-105` |
| Inspector | selection | preview 280×180, Classifica… (inbox), NOME, DATA, description, SOTTOCONTENITORE menu, colour swatches, action list | none | `ContenitoreInspector.swift:73-74,86,92,147-161,171,218-220` |
| Sheets | commands | Classifica, Rinomina documento, Sposta in, Nuovo sottocontenitore, trash confirm | Esc, Enter | `ContenitoreView.swift:44-103`, `ContenitoreNameSheet` `:106-165` (320), `ContenitoreMoveSheet` `:168-213` (320×260) |
| Scheda (the note) | «Apri scheda» | editor | Cmd+Opt+O | `ContenitoreCommand.swift:114` |
| Route / copy link | `pergamenum://` | Copia link Pergamenum | none | `ContenitoreController+RouteAndSettings.swift:14-41` |
| Settings | Impostazioni | drop folder, root | none | `ContenitoreController+RouteAndSettings.swift:47-64` (tab outside slice) |

### Design gallery entries (`MockupGalleryView.swift:79-106`)
| name | mockup file | shipped view it stands for |
|---|---|---|
| Cattura | CaptureMockup.swift | Features/Capture (`CapturePanelView`) |
| Menu / | SlashMenuMockup.swift | Features/Editor slash menu |
| Codice | CodeBlockMockup.swift | Editor code fences |
| Indice | OutlineMockup.swift | Editor outline (`NoteOutline`) |
| Ripiegamento | FoldingMockup.swift | Editor folding (`NoteFolding`) |
| Transclusione | TransclusionMockup.swift | Editor transclusion (ADR-0010) |
| Immagini e PDF | EmbedMockup.swift | Editor embeds (ADR-0018/0019) |
| Trova | FindBarMockup.swift | Editor find bar |
| Formato | FormatBarMockup.swift | Editor format bar |
| Cronologia | HistoryMockup.swift | note history (ADR-0011) |
| Template | TemplateMockup.swift | templates (ADR-0011/0086) |
| Tab | TabBarMockup.swift | editor tabs (ADR-0012) |
| Tag e preferiti | TagBrowserMockup.swift | Features/Tags |
| Menzioni | UnlinkedMentionsMockup.swift | backlinks/mentions (ADR-0084) |
| Viste | ViewMockup.swift | Features/Views (ADR-0009/0033) |
| Settimana | WeekMockup.swift | week view (ADR-0013) |
| Attività e rollover | TaskControlsMockup.swift | Features/Tasks |
| Margine dei marcatori | GutterRevealMockup.swift | editor gutter (ADR-0081) |
| Editor | EditorMockup.swift | Features/Editor (M1) |
| Workspace | WorkspaceMockup.swift | Features/Workspace |
| Oggi | TodayMockup.swift | Features/Today |
| Attività | TasksMockup.swift | Features/Tasks |
| Link | LinkPreviewMockup.swift | `Editor/LinkPreviewView.swift` (ADR-0083) |
| Ispettore: link | InspectorLinksMockup.swift | inspector links (ADR-0084) |
| Nascita di una nota | NoteBirthMockup.swift | Unfiled pane, composer (ADR-0085/0086) |
| Callout | CalloutMockup.swift | editor callouts (ADR-0087) |
| Codice, citazioni e chip | PageConstructsMockup.swift | editor constructs (ADR-0087) |
| Embed, transclusioni e tabelle | PageEmbedsMockup.swift | editor embeds/tables (ADR-0087) |
Token gallery: `DesignGalleryView.swift` → theme tokens (no shipped view). Contenitore has no gallery entry; its mockup is `docs/design/contenitore/Pergamenum Contenitore.html`.

### Non-token colours / fonts / notable literals
| file:line | literal | status |
|---|---|---|
| `TransclusionMockup.swift:114,201` | `.font(.system(size: 20/size, weight: .semibold))` | ADR-0051 §D10 exempt; PG-262 |
| `TransclusionMockup.swift:190` | `[.black, .black.opacity(0)]` mask | §D10 exempt |
| `EmbedMockup.swift:105` | `.font(.system(size: 22))` | §D10; PG-262 |
| `ViewMockupRenderers.swift:186` | `.font(.system(size: 26))` | §D10; PG-262 |
| `WeekMockupPieces.swift:23` | `.font(.system(size: 7))` | §D10; PG-262 |
| `LinkPreviewMockup.swift:131` | `[.black, .black.opacity(0)]` mask | not in §D10 (S13-21) |
| `ViewMockupRenderers.swift:152` | `.shadow(radius:y:)` | not `themedShadow` (S13-21) |
| `TagBrowserMockupPieces.swift:233-234` | token `.opacity(0.10)` | token-derived |
| `TransclusionMockup.swift:75,143`, `PageEmbedsMockup.swift:115` | `.accentPrimary.opacity(0.35)` | token-derived |
| `CalloutMockup.swift:168` | `cardOpacity 0.08` | token-derived, ADR-0087 §D4 |
| `HistoryMockup.swift:137,178,181`, `TemplateMockup.swift:160` | `.textInverted` for button text (others `.onAccent`) | token, inconsistent role |
| `SystemTextExtractor.swift:98` | `CGColor(gray: 1, alpha: 1)` | OCR canvas fill, not UI |
| `ContenitoreSidebar.swift:124` | `Color.clear.frame(width: 12)` | spacer, grep flag refuted |
| `ContenitoreView.swift:28,34,137,187` | widths 230/310/320/320×260 | literal sheet/pane widths (PG-262 item 3) |
| `ContenitoreInspector.swift:73` | 280×180 preview | literal |
Refuted grep flags: `FoldingMockup`, `FindBarMockup`, `GutterRevealMockupPieces`, `TagBrowserMockupPieces` draw every colour through tokens.

# SEC-security

## Surface inventory

| surface | opens from | verbs/buttons in the order shown | keyboard shortcut | file:line |
|---|---|---|---|---|
| Menu «Cerca aggiornamenti…» | app menu | Cerca aggiornamenti… | none | `Sources/App/MenuCommands.swift:293` (excerpt) |
| Attachment chip | pratica timeline row | click (preview popover), double-click (Apri, or Mostra nel Finder when refused) | none | `Sources/Features/Pratiche/AttachmentChip.swift:53` |
| Attachment chip refusal alert | double-click on a refused type | Mostra nel Finder · OK | Esc | `Sources/Features/Pratiche/AttachmentChip.swift:90` |
| Attachment chip context menu (AppKit) | right-click on chip | Anteprima allegato · Apri · Mostra nel Finder · Copia | none | `Sources/Features/Pratiche/AttachmentChipModel.swift:143` |
| Pratica message row subject | timeline row | subject button «Apri in Mail» (or caption «non più in Mail») | none | `Sources/Features/Pratiche/PraticaMessageRow.swift:129` |
| Pratica message row footer | expanded row | Apri in Mail · Aggiungi nota · Altro ▸ | none | `Sources/Features/Pratiche/PraticaMessageRow.swift:239` |
| Board card double-click / «Apri» | Workspace card | enter folder / open note / open file in vault / open link (LinkPolicy) | none | `Sources/Features/Workspace/BoardCardMenu.swift:182` (excerpt) |
| Note editor / card link | Cmd+click or «Apri collegamento» | external http(s) opens in browser; note, embed, tag, day routed in-app | Cmd+click | `Sources/Features/Editor/NoteTextView+LinkNavigation.swift:20`, `Sources/Features/Workspace/CardTextView.swift:332` |
| Esporta nota save panel | File › Esporta nota | Markdown · HTML · PDF, then the save panel | none | `Sources/App/NoteExporter.swift:28` |

No colour, font or spacing outside a token was found in the view code read for this slice; the export stylesheet's literal colours (`Sources/Core/Conventions/NoteExport.swift:43-60`) are document CSS for a file leaving the app, not app UI.

# X01-tooling

## Surface inventory

What the GUI suite drives (36 tests in 20 classes, plus the base class and `DragSupport`). Every class inherits `PergamenumUITestCase`, so all five isolation flags (`-disableCalendar`, `-disableUpdater`, `-mailStoreRoot`, `-disableContenitore`, `-disablePlaud`) plus `-stateBase` and a temp `-recentVaults` are always set. No test touches real Application Support, the Labs vault or Mail.

| test | surface · opens from | verbs / buttons in order | keyboard | file:line |
|---|---|---|---|---|
| testANewNoteIsNamedInTheEditorAndNotInAFloatingWindow | editor title field · toolbar `note-new` | type title, no sheet, Return → tab `note-tab-…` | Return | UITests/ComposerUITests.swift:27 |
| testTypingAfterChoosingADateContinuesTheText… | task composer · `pane-tasks` → toolbar `tasks-capture` | type, `task-composer-scheduled` → `date-option-today`, type, `task-composer-create` → `00 Inbox/Capture.md` | — | UITests/ComposerUITests.swift:60 |
| testVaiADataMovesTheDay | Oggi go-to-date popover · `pane-today` → `day-go-to-date` | `go-to-date-field`, pick `day-<date>`, `go-to-date-confirm` → `today-header-date` | — | UITests/DayViewUITests.swift:62 |
| testABlockIsComposedAndWrittenToTheFile | Diario new-entry sheet · `pane-diary` → `diary-new-entry` | `diary-sheet-title`, `diary-sheet-save` → `diary-entry`, `Diario/<yyyyMMdd>.md` | — | UITests/DiaryUITests.swift:38 |
| testTypingInTheFindFieldNeverMovesTheKeyboardIntoTheNote | find bar · note editor | `find-query`, `find-tally`, Return steps | Cmd+F, Return | UITests/EditorHandCheckUITests.swift:35 |
| testTheDiaryEditorContinuesAList | `diary-editor` · Diario | list continuation after `- uno` | Return | UITests/EditorHandCheckUITests.swift:65 |
| testTheTodayEditorContinuesAList | `today-editor` (+`today-open-daily-note`) · Oggi | list continuation | Return | UITests/EditorHandCheckUITests.swift:73 |
| testTheSpinnerDrawsAndTypingIsAcceptedWhileASearchRuns | global search sheet · 4,001-note vault | `search-field`, `search-progress`, `search-results`, `search-result-Bersaglio.md` | Cmd+Shift+F | UITests/GlobalSearchUITests.swift:94 |
| testTheArrowsWalkThePanesInOrder | toolbar history · Tag/Viste panes | `pane-tags`, `pane-views`, `history-back`, `history-forward` | — | UITests/HistoryNavigationUITests.swift:24 |
| testCollegaLinksTheMentionAfterTheDiff | inspector unlinked mentions · note `Curva.md` | `unlinked-mentions-scan`, `unlinked-mention-link-Prova.md`, `link-mention-confirm` → `backlink-row-Prova.md` | — | UITests/LinkMentionUITests.swift:35 |
| testFilingACaptureFromDaClassificare | «Da classificare» pane | `unfiled-row`, `note-classifica-topic` (chip), `note-classifica-folder` → «03 Risorse», `note-classifica-confirm` | Ctrl+Cmd+I, Down, Return | UITests/NoteBirthUITests.swift:17 |
| testTheDailyTemplatePlacesTheCaret | daily note from template | new daily note, caret at `{{cursor}}`, save | Cmd+Shift+D, Cmd+S | UITests/NoteBirthUITests.swift:95 |
| testAShortcutChangedInSettingsIsTheOneTheMenuAnswersTo | quick switcher · `-shortcutOverrides` | `quick-switcher-field` opens on Cmd+J, not on Cmd+O | Cmd+J, Esc, Cmd+O | UITests/NoteTreeAndShortcutsUITests.swift:33 |
| testTheTimelineAndInspectorToggleAreAddressable | Pratiche · `pane-pratiche` | `pratiche-timeline`, `pratiche-inspector-toggle`, `pratiche-filter` | — | UITests/PraticheUITests.swift:61 |
| testBackspaceExcludesTheSelectedMessageCollapsedAndExpanded | Pratiche timeline row | select, chevron `pratiche-message-chevron-<h>` (Espandi/Comprimi), exclude, undo, forward delete, Edit menu `delete:` | Backspace, Cmd+Z, Fn+Delete | UITests/PraticheUITests.swift:73 |
| testBackspaceStillExcludesAfterAQuickLookPreview | Quick Look · attachment chip | open preview, Esc, reopen, exclude | Space, Esc, Backspace | UITests/PraticheUITests.swift:115 |
| testDoubleClickTogglesMessageRow | timeline row header | double-click trailing area toggles `pratiche-message-body-<h>` | — | UITests/PraticheUITests.swift:160 |
| testAttachmentChipContextMenuShowsBothCatalogueEntries | chip context menu · `pratiche-attachment-<h>-0` | right-click → «Mostra nel Finder», «Copia», «Anteprima allegato», «Apri»; no «Escludi dalla pratica» | — | UITests/AttachmentChipContextMenuUITests.swift:50 |
| testRightClickBesideTheChipStillOpensTheMessageMenu | message context menu · `pratiche-message-subject-<h>` | right-click → message menu | — | UITests/AttachmentChipContextMenuUITests.swift:88 |
| testLeftClickOnPendingChipOpensThePendingPopover | pending popover · pending chip | click → `attachment-pending-explanation` | — | UITests/AttachmentChipContextMenuUITests.swift:109 |
| testQuittingWithAnUnsavedNoteAsksAndSalvaWritesIt | quit review dialog/sheet · dirty `note-save-chip` | `quit-prompt-cancel`, `quit-prompt-save`, `quit-prompt-discard` | Cmd+Q | UITests/QuitReviewUITests.swift:54 |
| testQuittingWithAConflictedDiaryDayAsksAndWritesNothing | quit review · `diary-conflict-banner` | Salva → banner revealed, nothing written | Cmd+Q | UITests/QuitReviewUITests.swift:92 |
| testQuittingWithAConflictedBoardOffScreenAsksAndWritesNothing | quit review · board `Lavagna.canvas` conflict | corner drag, `board-conflict-keep-local`, `pane-notes`, Salva reveals the board | Cmd+Q | UITests/QuitReviewUITests.swift:148 |
| testDeletingANoteFromTheContextMenuRemovesItFromTheTreeAndTheVault | note row context menu → trash sheet | «Elimina…» → `sidebar-trash-confirm` | — | UITests/SidebarDeleteUITests.swift:28 |
| testMovingABoardRowViaTheMenuMovesTheFile… | Workspace row context menu · `workspace-filter` | «Sposta in» → destination / «(radice)» | — | UITests/SidebarMoveUITests.swift:63 |
| testMovingIntoAFolderThatAlreadyHoldsTheName… | move conflict alert | text `Collide/Board.canvas`, `sidebar-move-conflict-ok` | — | UITests/SidebarMoveUITests.swift:110 |
| testUndoAfterAMenuMoveRestoresBoth…_R12 | multi-select move | Cmd-click two rows, «Sposta in», undo, redo | Cmd+click, Cmd+Z, Cmd+Shift+Z | UITests/SidebarMoveUITests.swift:133 |
| testTheCategoriesSectionShowsARegisteredAndAnImplicitRow… | Tasks categories · `pane-tasks` | `category-row-collaudi`, `category-implicit-row-fantasma`, `category-view-collaudi`, `task-row` | — | UITests/TaskCategoriesUITests.swift:81 |
| testLinkingANoteFromTheCategoryViewMakesItTheHome | category view note picker | `category-view-link-note` → `category-note-picker-row-Piano.md` → `category-view-go-to-note` | — | UITests/TaskCategoriesUITests.swift:112 |
| testCommandClickOnAWikilinkNavigatesToTheLinkedNote | editor wikilink `Destinazione` | Cmd-click navigates | Cmd+click | UITests/WikilinkNavigationUITests.swift:85 |
| testFollowingTheLinkAtTheCaretAndComingBack | editor | follow the link at the caret, back (`history-back`) | Cmd+Opt+Return, Cmd+[ | UITests/WikilinkNavigationUITests.swift:130 |
| testCommandHoverShowsThePreviewAndReleaseHidesIt | link preview popover | hold Cmd and hover → `link-preview`, release hides | Cmd held | UITests/WikilinkNavigationUITests.swift:167 |
| testACornerGripResizesTheCard | Workspace board · root board row | `canvas-node-aaaa000000000001` corner drag (+160,+90) → `.canvas` node grows, origin fixed | — | UITests/WorkspaceBoardUITests.swift:47 |
| testThePaneOpensEmptyAndFillsInOnlyAfterAClick | Workspace pane | `workspace-empty`, click → `workspace-tree`, `workspace-expand-all` | — | UITests/WorkspaceOpenStateUITests.swift:103 |
| testSelectingANestedBoardLightsExactlyOneRow…_R02_R03 | Workspace tree | nested `workspace-board-Vibrofer/Dettaglio/Dettaglio.canvas`, labels `, aperta` / `, selezionata` | — | UITests/WorkspaceOpenStateUITests.swift:116 |
| testSendingANoteFromAnAmbiguousFolderToTheWorkspaceSelectsTheFolder… | menu bar «Apri nel Workspace» from a `note-filter` row; Settings «Avanzate» | send to Workspace → `workspace-folder-Ambiguo` selected; the Settings tab lists the problem path | Cmd+, | UITests/WorkspaceIntegrationUITests.swift:44 |

Second table: WCAG 2.1 contrast of text tokens on ground tokens (from `x01-theme-contrast.py`). `!` means under 4.5:1, `!!` under 3:1. Key sets are identical (84 tokens each), and no colour token is identical across the two themes. `accent.onAccent` on `accent.primary`: light 5.40, dark 8.42.

Light (179 pairs ≥4.5, 87 at 3–4.5, 82 under 3, of 348)

| text token | bg.primary | bg.secondary | bg.tertiary | sf.card | sf.raised | sf.sunken | sf.received | sf.sent | sf.entry | sf.entryNote | sf.entryCall | code.inlineBg |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| text.primary / task.open `#1C1B18` | 17.22 | 15.82 | 14.49 | 17.22 | 17.22 | 15.01 | 14.99 | 14.73 | 15.42 | 15.24 | 14.72 | 14.25 |
| text.secondary `#6B665D` | 5.70 | 5.24 | 4.80 | 5.70 | 5.70 | 4.97 | 4.96 | 4.87 | 5.10 | 5.05 | 4.87 | 4.72 |
| text.tertiary / task.done / task.cancelled / code.comment `#9C968B` | 2.94!! | 2.70!! | 2.47!! | 2.94!! | 2.94!! | 2.56!! | 2.56!! | 2.51!! | 2.63!! | 2.60!! | 2.51!! | 2.43!! |
| accent.primary `#9A5B1F` | 5.40 | 4.96 | 4.54 | 5.40 | 5.40 | 4.70 | 4.70 | 4.62 | 4.83 | 4.78 | 4.61 | 4.47! |
| task.scheduled / callout.note / code.type `#3B6EA5` | 5.30 | 4.87 | 4.46! | 5.30 | 5.30 | 4.62 | 4.62 | 4.54 | 4.75 | 4.69 | 4.53 | 4.39! |
| task.overdue / callout.caution / calendar.festive `#B3261E` | 6.54 | 6.00 | 5.50 | 6.54 | 6.54 | 5.70 | 5.69 | 5.59 | 5.85 | 5.79 | 5.59 | 5.41 |
| callout.tip `#3F7A45` | 5.15 | 4.73 | 4.33! | 5.15 | 5.15 | 4.48! | 4.48! | 4.40! | 4.61 | 4.55 | 4.40! | 4.26! |
| callout.important / code.keyword `#7E4B7A` | 6.62 | 6.08 | 5.57 | 6.62 | 6.62 | 5.76 | 5.76 | 5.66 | 5.92 | 5.85 | 5.65 | 5.47 |
| callout.warning `#94600F` | 5.33 | 4.90 | 4.49! | 5.33 | 5.33 | 4.65 | 4.64 | 4.56 | 4.77 | 4.72 | 4.56 | 4.41! |
| code.string `#4B7A4F` | 5.00 | 4.60 | 4.21! | 5.00 | 5.00 | 4.36! | 4.36! | 4.28! | 4.48! | 4.43! | 4.28! | 4.14! |
| code.number `#2F6E6B` | 5.89 | 5.41 | 4.96 | 5.89 | 5.89 | 5.13 | 5.13 | 5.04 | 5.28 | 5.22 | 5.04 | 4.88 |
| calendar.prefestive `#C98B84` | 2.80!! | 2.57!! | 2.35!! | 2.80!! | 2.80!! | 2.44!! | 2.43!! | 2.39!! | 2.50!! | 2.47!! | 2.39!! | 2.31!! |
| calendar.holiday `#D62828` | 5.01 | 4.60 | 4.21! | 5.01 | 5.01 | 4.36! | 4.36! | 4.28! | 4.48! | 4.43! | 4.28! | 4.14! |
| category.yellow `#D99A00` | 2.45!! | 2.25!! | 2.06!! | 2.45!! | 2.45!! | 2.13!! | 2.13!! | 2.09!! | 2.19!! | 2.17!! | 2.09!! | 2.03!! |
| category.green `#2E9E4F` | 3.43! | 3.15! | 2.89!! | 3.43! | 3.43! | 2.99!! | 2.99!! | 2.93!! | 3.07! | 3.04! | 2.93!! | 2.84!! |
| category.blue `#1F6FEB` | 4.63 | 4.26! | 3.90! | 4.63 | 4.63 | 4.04! | 4.03! | 3.96! | 4.15! | 4.10! | 3.96! | 3.83! |
| category.pink `#DB3F6F` | 4.24! | 3.89! | 3.57! | 4.24! | 4.24! | 3.69! | 3.69! | 3.63! | 3.80! | 3.75! | 3.62! | 3.51! |
| category.grey `#6E7378` | 4.79 | 4.40! | 4.03! | 4.79 | 4.79 | 4.17! | 4.17! | 4.09! | 4.29! | 4.24! | 4.09! | 3.96! |
| rail.received `#8F897C` | 3.48! | 3.19! | 2.93!! | 3.48! | 3.48! | 3.03! | 3.03! | 2.97!! | 3.11! | 3.08! | 2.97!! | 2.88!! |
| rail.sent `#6189B4` | 3.65! | 3.36! | 3.08! | 3.65! | 3.65! | 3.18! | 3.18! | 3.13! | 3.27! | 3.23! | 3.12! | 3.02! |

Dark (267 pairs ≥4.5, 56 at 3–4.5, 25 under 3, of 348)

| text token | bg.primary | bg.secondary | bg.tertiary | sf.card | sf.raised | sf.sunken | sf.received | sf.sent | sf.entry | sf.entryNote | sf.entryCall | code.inlineBg |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| text.primary / task.open `#F2EFE9` | 15.31 | 14.01 | 12.47 | 13.69 | 12.47 | 16.18 | 12.51 | 11.76 | 10.56 | 9.91 | 10.67 | 12.65 |
| text.secondary `#A8A398` | 6.99 | 6.40 | 5.69 | 6.25 | 5.69 | 7.39 | 5.71 | 5.37 | 4.82 | 4.53 | 4.88 | 5.78 |
| text.tertiary / task.done / task.cancelled / code.comment `#77726A` | 3.68! | 3.37! | 3.00!! | 3.29! | 3.00!! | 3.89! | 3.01! | 2.83!! | 2.54!! | 2.38!! | 2.57!! | 3.04! |
| accent.primary `#E0A96D` | 8.42 | 7.70 | 6.86 | 7.53 | 6.86 | 8.90 | 6.88 | 6.47 | 5.81 | 5.45 | 5.87 | 6.96 |
| task.scheduled / callout.note / code.type `#8AB4E8` | 8.18 | 7.48 | 6.66 | 7.31 | 6.66 | 8.64 | 6.68 | 6.28 | 5.64 | 5.29 | 5.70 | 6.76 |
| task.overdue `#F2B8B5` | 10.29 | 9.41 | 8.38 | 9.20 | 8.38 | 10.87 | 8.41 | 7.90 | 7.10 | 6.66 | 7.17 | 8.50 |
| callout.tip / code.string `#9CC49B` | 9.02 | 8.25 | 7.35 | 8.07 | 7.35 | 9.53 | 7.37 | 6.93 | 6.22 | 5.84 | 6.29 | 7.45 |
| callout.important / code.keyword `#C79BC4` | 7.46 | 6.82 | 6.07 | 6.67 | 6.07 | 7.88 | 6.09 | 5.73 | 5.14 | 4.83 | 5.20 | 6.16 |
| callout.warning `#E0B060` | 8.82 | 8.07 | 7.19 | 7.89 | 7.19 | 9.33 | 7.21 | 6.78 | 6.09 | 5.71 | 6.15 | 7.29 |
| callout.caution `#F2867E` | 7.10 | 6.50 | 5.78 | 6.35 | 5.78 | 7.50 | 5.80 | 5.45 | 4.90 | 4.60 | 4.95 | 5.87 |
| code.number `#79BDB8` | 8.19 | 7.49 | 6.67 | 7.32 | 6.67 | 8.65 | 6.69 | 6.29 | 5.65 | 5.30 | 5.71 | 6.76 |
| calendar.prefestive `#A8837D` | 5.19 | 4.75 | 4.23! | 4.65 | 4.23! | 5.49 | 4.24! | 3.99! | 3.58! | 3.36! | 3.62! | 4.29! |
| calendar.festive `#EE9A94` | 8.10 | 7.41 | 6.60 | 7.25 | 6.60 | 8.56 | 6.62 | 6.22 | 5.59 | 5.25 | 5.65 | 6.70 |
| calendar.holiday `#FF8A80` | 7.70 | 7.04 | 6.27 | 6.88 | 6.27 | 8.13 | 6.29 | 5.91 | 5.31 | 4.98 | 5.37 | 6.36 |
| category.yellow `#F5C542` | 10.83 | 9.91 | 8.82 | 9.69 | 8.82 | 11.45 | 8.85 | 8.32 | 7.47 | 7.01 | 7.55 | 8.95 |
| category.green `#4CC26A` | 7.72 | 7.07 | 6.29 | 6.91 | 6.29 | 8.16 | 6.31 | 5.93 | 5.33 | 5.00 | 5.39 | 6.38 |
| category.blue `#5A9EFF` | 6.50 | 5.95 | 5.29 | 5.81 | 5.29 | 6.87 | 5.31 | 4.99 | 4.48! | 4.21! | 4.53 | 5.37 |
| category.pink `#FF6B8A` | 6.46 | 5.91 | 5.26 | 5.78 | 5.26 | 6.83 | 5.28 | 4.96 | 4.46! | 4.18! | 4.50 | 5.34 |
| category.grey `#9AA0A6` | 6.65 | 6.09 | 5.42 | 5.95 | 5.42 | 7.03 | 5.44 | 5.11 | 4.59 | 4.31! | 4.64 | 5.50 |
| rail.received `#857F73` | 4.42! | 4.04! | 3.60! | 3.95! | 3.60! | 4.67 | 3.61! | 3.39! | 3.05! | 2.86!! | 3.08! | 3.65! |
| rail.sent `#5F8DB8` | 5.01 | 4.58 | 4.08! | 4.48! | 4.08! | 5.30 | 4.09! | 3.85! | 3.46! | 3.24! | 3.49! | 4.14! |

Font tokens (identical in both themes): title 22/600, heading 16/600, body 13/400, caption 11/400, mono 12/400, prose Avenir Next 16/400, proseTitle Avenir Next 24/700, icon.small **10**/500, icon.badge **7**/400, icon.display 32/400, control.label **9**/600.

# Theme contrast tables (X01, WCAG 2.1)

## 1. Key sets
- tokens: light 84, dark 84
- only in light: none
- only in dark: none

## 2. WCAG 2.1 contrast (text token on background/surface token)
Cell = ratio; `!` under 4.5:1 (normal text), `!!` under 3:1 (large text / UI).

### light
| text token | bg.primary | bg.secondary | bg.tertiary | sf.card | sf.raised | sf.sunken | sf.received | sf.sent | sf.entry | sf.entryNote | sf.entryCall | code.inlineBg |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| text.primary `#1C1B18` | 17.22 | 15.82 | 14.49 | 17.22 | 17.22 | 15.01 | 14.99 | 14.73 | 15.42 | 15.24 | 14.72 | 14.25 |
| text.secondary `#6B665D` | 5.70 | 5.24 | 4.80 | 5.70 | 5.70 | 4.97 | 4.96 | 4.87 | 5.10 | 5.05 | 4.87 | 4.72 |
| text.tertiary `#9C968B` | 2.94!! | 2.70!! | 2.47!! | 2.94!! | 2.94!! | 2.56!! | 2.56!! | 2.51!! | 2.63!! | 2.60!! | 2.51!! | 2.43!! |
| accent.primary `#9A5B1F` | 5.40 | 4.96 | 4.54 | 5.40 | 5.40 | 4.70 | 4.70 | 4.62 | 4.83 | 4.78 | 4.61 | 4.47! |
| task.open `#1C1B18` | 17.22 | 15.82 | 14.49 | 17.22 | 17.22 | 15.01 | 14.99 | 14.73 | 15.42 | 15.24 | 14.72 | 14.25 |
| task.done `#9C968B` | 2.94!! | 2.70!! | 2.47!! | 2.94!! | 2.94!! | 2.56!! | 2.56!! | 2.51!! | 2.63!! | 2.60!! | 2.51!! | 2.43!! |
| task.scheduled `#3B6EA5` | 5.30 | 4.87 | 4.46! | 5.30 | 5.30 | 4.62 | 4.62 | 4.54 | 4.75 | 4.69 | 4.53 | 4.39! |
| task.overdue `#B3261E` | 6.54 | 6.00 | 5.50 | 6.54 | 6.54 | 5.70 | 5.69 | 5.59 | 5.85 | 5.79 | 5.59 | 5.41 |
| task.cancelled `#9C968B` | 2.94!! | 2.70!! | 2.47!! | 2.94!! | 2.94!! | 2.56!! | 2.56!! | 2.51!! | 2.63!! | 2.60!! | 2.51!! | 2.43!! |
| callout.note `#3B6EA5` | 5.30 | 4.87 | 4.46! | 5.30 | 5.30 | 4.62 | 4.62 | 4.54 | 4.75 | 4.69 | 4.53 | 4.39! |
| callout.tip `#3F7A45` | 5.15 | 4.73 | 4.33! | 5.15 | 5.15 | 4.48! | 4.48! | 4.40! | 4.61 | 4.55 | 4.40! | 4.26! |
| callout.important `#7E4B7A` | 6.62 | 6.08 | 5.57 | 6.62 | 6.62 | 5.76 | 5.76 | 5.66 | 5.92 | 5.85 | 5.65 | 5.47 |
| callout.warning `#94600F` | 5.33 | 4.90 | 4.49! | 5.33 | 5.33 | 4.65 | 4.64 | 4.56 | 4.77 | 4.72 | 4.56 | 4.41! |
| callout.caution `#B3261E` | 6.54 | 6.00 | 5.50 | 6.54 | 6.54 | 5.70 | 5.69 | 5.59 | 5.85 | 5.79 | 5.59 | 5.41 |
| code.keyword `#7E4B7A` | 6.62 | 6.08 | 5.57 | 6.62 | 6.62 | 5.76 | 5.76 | 5.66 | 5.92 | 5.85 | 5.65 | 5.47 |
| code.string `#4B7A4F` | 5.00 | 4.60 | 4.21! | 5.00 | 5.00 | 4.36! | 4.36! | 4.28! | 4.48! | 4.43! | 4.28! | 4.14! |
| code.comment `#9C968B` | 2.94!! | 2.70!! | 2.47!! | 2.94!! | 2.94!! | 2.56!! | 2.56!! | 2.51!! | 2.63!! | 2.60!! | 2.51!! | 2.43!! |
| code.number `#2F6E6B` | 5.89 | 5.41 | 4.96 | 5.89 | 5.89 | 5.13 | 5.13 | 5.04 | 5.28 | 5.22 | 5.04 | 4.88 |
| code.type `#3B6EA5` | 5.30 | 4.87 | 4.46! | 5.30 | 5.30 | 4.62 | 4.62 | 4.54 | 4.75 | 4.69 | 4.53 | 4.39! |
| calendar.prefestive `#C98B84` | 2.80!! | 2.57!! | 2.35!! | 2.80!! | 2.80!! | 2.44!! | 2.43!! | 2.39!! | 2.50!! | 2.47!! | 2.39!! | 2.31!! |
| calendar.festive `#B3261E` | 6.54 | 6.00 | 5.50 | 6.54 | 6.54 | 5.70 | 5.69 | 5.59 | 5.85 | 5.79 | 5.59 | 5.41 |
| calendar.holiday `#D62828` | 5.01 | 4.60 | 4.21! | 5.01 | 5.01 | 4.36! | 4.36! | 4.28! | 4.48! | 4.43! | 4.28! | 4.14! |
| category.yellow `#D99A00` | 2.45!! | 2.25!! | 2.06!! | 2.45!! | 2.45!! | 2.13!! | 2.13!! | 2.09!! | 2.19!! | 2.17!! | 2.09!! | 2.03!! |
| category.green `#2E9E4F` | 3.43! | 3.15! | 2.89!! | 3.43! | 3.43! | 2.99!! | 2.99!! | 2.93!! | 3.07! | 3.04! | 2.93!! | 2.84!! |
| category.blue `#1F6FEB` | 4.63 | 4.26! | 3.90! | 4.63 | 4.63 | 4.04! | 4.03! | 3.96! | 4.15! | 4.10! | 3.96! | 3.83! |
| category.pink `#DB3F6F` | 4.24! | 3.89! | 3.57! | 4.24! | 4.24! | 3.69! | 3.69! | 3.63! | 3.80! | 3.75! | 3.62! | 3.51! |
| category.grey `#6E7378` | 4.79 | 4.40! | 4.03! | 4.79 | 4.79 | 4.17! | 4.17! | 4.09! | 4.29! | 4.24! | 4.09! | 3.96! |
| rail.received `#8F897C` | 3.48! | 3.19! | 2.93!! | 3.48! | 3.48! | 3.03! | 3.03! | 2.97!! | 3.11! | 3.08! | 2.97!! | 2.88!! |
| rail.sent `#6189B4` | 3.65! | 3.36! | 3.08! | 3.65! | 3.65! | 3.18! | 3.18! | 3.13! | 3.27! | 3.23! | 3.12! | 3.02! |

- accent.onAccent `#FFFFFF` on accent.primary `#9A5B1F`: 5.40
- text.inverted `#FFFFFF` on accent.primary: 5.40
- pairs: 179 at or above 4.5:1, 87 between 3:1 and 4.5:1, 82 under 3:1 (of 348)

### dark
| text token | bg.primary | bg.secondary | bg.tertiary | sf.card | sf.raised | sf.sunken | sf.received | sf.sent | sf.entry | sf.entryNote | sf.entryCall | code.inlineBg |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| text.primary `#F2EFE9` | 15.31 | 14.01 | 12.47 | 13.69 | 12.47 | 16.18 | 12.51 | 11.76 | 10.56 | 9.91 | 10.67 | 12.65 |
| text.secondary `#A8A398` | 6.99 | 6.40 | 5.69 | 6.25 | 5.69 | 7.39 | 5.71 | 5.37 | 4.82 | 4.53 | 4.88 | 5.78 |
| text.tertiary `#77726A` | 3.68! | 3.37! | 3.00!! | 3.29! | 3.00!! | 3.89! | 3.01! | 2.83!! | 2.54!! | 2.38!! | 2.57!! | 3.04! |
| accent.primary `#E0A96D` | 8.42 | 7.70 | 6.86 | 7.53 | 6.86 | 8.90 | 6.88 | 6.47 | 5.81 | 5.45 | 5.87 | 6.96 |
| task.open `#F2EFE9` | 15.31 | 14.01 | 12.47 | 13.69 | 12.47 | 16.18 | 12.51 | 11.76 | 10.56 | 9.91 | 10.67 | 12.65 |
| task.done `#77726A` | 3.68! | 3.37! | 3.00!! | 3.29! | 3.00!! | 3.89! | 3.01! | 2.83!! | 2.54!! | 2.38!! | 2.57!! | 3.04! |
| task.scheduled `#8AB4E8` | 8.18 | 7.48 | 6.66 | 7.31 | 6.66 | 8.64 | 6.68 | 6.28 | 5.64 | 5.29 | 5.70 | 6.76 |
| task.overdue `#F2B8B5` | 10.29 | 9.41 | 8.38 | 9.20 | 8.38 | 10.87 | 8.41 | 7.90 | 7.10 | 6.66 | 7.17 | 8.50 |
| task.cancelled `#77726A` | 3.68! | 3.37! | 3.00!! | 3.29! | 3.00!! | 3.89! | 3.01! | 2.83!! | 2.54!! | 2.38!! | 2.57!! | 3.04! |
| callout.note `#8AB4E8` | 8.18 | 7.48 | 6.66 | 7.31 | 6.66 | 8.64 | 6.68 | 6.28 | 5.64 | 5.29 | 5.70 | 6.76 |
| callout.tip `#9CC49B` | 9.02 | 8.25 | 7.35 | 8.07 | 7.35 | 9.53 | 7.37 | 6.93 | 6.22 | 5.84 | 6.29 | 7.45 |
| callout.important `#C79BC4` | 7.46 | 6.82 | 6.07 | 6.67 | 6.07 | 7.88 | 6.09 | 5.73 | 5.14 | 4.83 | 5.20 | 6.16 |
| callout.warning `#E0B060` | 8.82 | 8.07 | 7.19 | 7.89 | 7.19 | 9.33 | 7.21 | 6.78 | 6.09 | 5.71 | 6.15 | 7.29 |
| callout.caution `#F2867E` | 7.10 | 6.50 | 5.78 | 6.35 | 5.78 | 7.50 | 5.80 | 5.45 | 4.90 | 4.60 | 4.95 | 5.87 |
| code.keyword `#C79BC4` | 7.46 | 6.82 | 6.07 | 6.67 | 6.07 | 7.88 | 6.09 | 5.73 | 5.14 | 4.83 | 5.20 | 6.16 |
| code.string `#9CC49B` | 9.02 | 8.25 | 7.35 | 8.07 | 7.35 | 9.53 | 7.37 | 6.93 | 6.22 | 5.84 | 6.29 | 7.45 |
| code.comment `#77726A` | 3.68! | 3.37! | 3.00!! | 3.29! | 3.00!! | 3.89! | 3.01! | 2.83!! | 2.54!! | 2.38!! | 2.57!! | 3.04! |
| code.number `#79BDB8` | 8.19 | 7.49 | 6.67 | 7.32 | 6.67 | 8.65 | 6.69 | 6.29 | 5.65 | 5.30 | 5.71 | 6.76 |
| code.type `#8AB4E8` | 8.18 | 7.48 | 6.66 | 7.31 | 6.66 | 8.64 | 6.68 | 6.28 | 5.64 | 5.29 | 5.70 | 6.76 |
| calendar.prefestive `#A8837D` | 5.19 | 4.75 | 4.23! | 4.65 | 4.23! | 5.49 | 4.24! | 3.99! | 3.58! | 3.36! | 3.62! | 4.29! |
| calendar.festive `#EE9A94` | 8.10 | 7.41 | 6.60 | 7.25 | 6.60 | 8.56 | 6.62 | 6.22 | 5.59 | 5.25 | 5.65 | 6.70 |
| calendar.holiday `#FF8A80` | 7.70 | 7.04 | 6.27 | 6.88 | 6.27 | 8.13 | 6.29 | 5.91 | 5.31 | 4.98 | 5.37 | 6.36 |
| category.yellow `#F5C542` | 10.83 | 9.91 | 8.82 | 9.69 | 8.82 | 11.45 | 8.85 | 8.32 | 7.47 | 7.01 | 7.55 | 8.95 |
| category.green `#4CC26A` | 7.72 | 7.07 | 6.29 | 6.91 | 6.29 | 8.16 | 6.31 | 5.93 | 5.33 | 5.00 | 5.39 | 6.38 |
| category.blue `#5A9EFF` | 6.50 | 5.95 | 5.29 | 5.81 | 5.29 | 6.87 | 5.31 | 4.99 | 4.48! | 4.21! | 4.53 | 5.37 |
| category.pink `#FF6B8A` | 6.46 | 5.91 | 5.26 | 5.78 | 5.26 | 6.83 | 5.28 | 4.96 | 4.46! | 4.18! | 4.50 | 5.34 |
| category.grey `#9AA0A6` | 6.65 | 6.09 | 5.42 | 5.95 | 5.42 | 7.03 | 5.44 | 5.11 | 4.59 | 4.31! | 4.64 | 5.50 |
| rail.received `#857F73` | 4.42! | 4.04! | 3.60! | 3.95! | 3.60! | 4.67 | 3.61! | 3.39! | 3.05! | 2.86!! | 3.08! | 3.65! |
| rail.sent `#5F8DB8` | 5.01 | 4.58 | 4.08! | 4.48! | 4.08! | 5.30 | 4.09! | 3.85! | 3.46! | 3.24! | 3.49! | 4.14! |

- accent.onAccent `#1A1917` on accent.primary `#E0A96D`: 8.42
- text.inverted `#1A1917` on accent.primary: 8.42
- pairs: 267 at or above 4.5:1, 56 between 3:1 and 4.5:1, 25 under 3:1 (of 348)

### Pairs under 3:1, worst first

**light**
- category.yellow on code.inlineBg: 2.03
- category.yellow on bg.tertiary: 2.06
- category.yellow on sf.entryCall: 2.09
- category.yellow on sf.sent: 2.09
- category.yellow on sf.received: 2.13
- category.yellow on sf.sunken: 2.13
- category.yellow on sf.entryNote: 2.17
- category.yellow on sf.entry: 2.19
- category.yellow on bg.secondary: 2.25
- calendar.prefestive on code.inlineBg: 2.31
- calendar.prefestive on bg.tertiary: 2.35
- calendar.prefestive on sf.entryCall: 2.39
- calendar.prefestive on sf.sent: 2.39
- text.tertiary on code.inlineBg: 2.43
- task.done on code.inlineBg: 2.43
- task.cancelled on code.inlineBg: 2.43
- code.comment on code.inlineBg: 2.43
- calendar.prefestive on sf.received: 2.43
- calendar.prefestive on sf.sunken: 2.44
- category.yellow on bg.primary: 2.45
- category.yellow on sf.card: 2.45
- category.yellow on sf.raised: 2.45
- text.tertiary on bg.tertiary: 2.47
- task.done on bg.tertiary: 2.47
- task.cancelled on bg.tertiary: 2.47
- code.comment on bg.tertiary: 2.47
- calendar.prefestive on sf.entryNote: 2.47
- calendar.prefestive on sf.entry: 2.50
- text.tertiary on sf.entryCall: 2.51
- task.done on sf.entryCall: 2.51
- task.cancelled on sf.entryCall: 2.51
- code.comment on sf.entryCall: 2.51
- text.tertiary on sf.sent: 2.51
- task.done on sf.sent: 2.51
- task.cancelled on sf.sent: 2.51
- code.comment on sf.sent: 2.51
- text.tertiary on sf.received: 2.56
- task.done on sf.received: 2.56
- task.cancelled on sf.received: 2.56
- code.comment on sf.received: 2.56
- text.tertiary on sf.sunken: 2.56
- task.done on sf.sunken: 2.56
- task.cancelled on sf.sunken: 2.56
- code.comment on sf.sunken: 2.56
- calendar.prefestive on bg.secondary: 2.57
- text.tertiary on sf.entryNote: 2.60
- task.done on sf.entryNote: 2.60
- task.cancelled on sf.entryNote: 2.60
- code.comment on sf.entryNote: 2.60
- text.tertiary on sf.entry: 2.63
- task.done on sf.entry: 2.63
- task.cancelled on sf.entry: 2.63
- code.comment on sf.entry: 2.63
- text.tertiary on bg.secondary: 2.70
- task.done on bg.secondary: 2.70
- task.cancelled on bg.secondary: 2.70
- code.comment on bg.secondary: 2.70
- calendar.prefestive on bg.primary: 2.80
- calendar.prefestive on sf.card: 2.80
- calendar.prefestive on sf.raised: 2.80
- category.green on code.inlineBg: 2.84
- rail.received on code.inlineBg: 2.88
- category.green on bg.tertiary: 2.89
- rail.received on bg.tertiary: 2.93
- category.green on sf.entryCall: 2.93
- category.green on sf.sent: 2.93
- text.tertiary on bg.primary: 2.94
- text.tertiary on sf.card: 2.94
- text.tertiary on sf.raised: 2.94
- task.done on bg.primary: 2.94
- task.done on sf.card: 2.94
- task.done on sf.raised: 2.94
- task.cancelled on bg.primary: 2.94
- task.cancelled on sf.card: 2.94
- task.cancelled on sf.raised: 2.94
- code.comment on bg.primary: 2.94
- code.comment on sf.card: 2.94
- code.comment on sf.raised: 2.94
- rail.received on sf.entryCall: 2.97
- rail.received on sf.sent: 2.97
- category.green on sf.received: 2.99
- category.green on sf.sunken: 2.99

**dark**
- text.tertiary on sf.entryNote: 2.38
- task.done on sf.entryNote: 2.38
- task.cancelled on sf.entryNote: 2.38
- code.comment on sf.entryNote: 2.38
- text.tertiary on sf.entry: 2.54
- task.done on sf.entry: 2.54
- task.cancelled on sf.entry: 2.54
- code.comment on sf.entry: 2.54
- text.tertiary on sf.entryCall: 2.57
- task.done on sf.entryCall: 2.57
- task.cancelled on sf.entryCall: 2.57
- code.comment on sf.entryCall: 2.57
- text.tertiary on sf.sent: 2.83
- task.done on sf.sent: 2.83
- task.cancelled on sf.sent: 2.83
- code.comment on sf.sent: 2.83
- rail.received on sf.entryNote: 2.86
- text.tertiary on bg.tertiary: 3.00
- text.tertiary on sf.raised: 3.00
- task.done on bg.tertiary: 3.00
- task.done on sf.raised: 3.00
- task.cancelled on bg.tertiary: 3.00
- task.cancelled on sf.raised: 3.00
- code.comment on bg.tertiary: 3.00
- code.comment on sf.raised: 3.00

## 3. Tokens identical across light and dark
- colour tokens identical (0): 
- colour tokens that differ (58)
- non-colour tokens identical (22), differing (4): meta.appearance, meta.name, shadow.card, shadow.raised

## 4. Font tokens
| token | family | size | weight | lineHeight | same in dark |
|---|---|---|---|---|---|
| font.body | system | 13 | 400 | 1.5 | yes |
| font.caption | system | 11 | 400 | 1.35 | yes |
| font.control.label | system | 9 **<11pt** | 600 | 1.0 | yes |
| font.heading | system | 16 | 600 | 1.3 | yes |
| font.icon.badge | system | 7 **<11pt** | 400 | 1.0 | yes |
| font.icon.display | system | 32 | 400 | 1.0 | yes |
| font.icon.small | system | 10 **<11pt** | 500 | 1.0 | yes |
| font.mono | monospace | 12 | 400 | 1.45 | yes |
| font.prose | Avenir Next | 16 | 400 | 1.4 | yes |
| font.proseTitle | Avenir Next | 24 | 700 | 1.2 | yes |
| font.title | system | 22 | 600 | 1.2 | yes |

