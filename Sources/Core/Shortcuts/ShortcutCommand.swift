import Foundation

/// Every command whose keyboard shortcut the user may change (SPEC §12, Impostazioni).
///
/// The catalogue is the single place a shortcut is declared. A menu asks it for the
/// binding rather than writing one inline, so the settings pane cannot drift out of
/// step with the menu bar: a command missing here would simply have no shortcut, which
/// is visible, instead of having one nobody can find or change.
///
/// The raw values are persisted as the keys of the overrides file. They are identity,
/// not text: renaming one silently drops the user's binding for that command.
enum ShortcutCommand: String, CaseIterable, Identifiable, Sendable {
    case newNote
    /// File → "Nuova board" (SPEC §10): switches to the Workspace and opens the
    /// "Cartella" tool's naming sheet on the current board, since a folder is what
    /// SPEC §6.1 calls a board into being.
    case newBoard
    case dailyNote
    case quickTask
    /// The only command here that is not a menu key: it is registered with the system
    /// and fires while another application is in front (ADR-0008 §D1). It lives in the
    /// same catalogue anyway, so it is remappable in the same pane as everything else.
    case globalCapture
    case quickLook
    case globalSearch
    case quickSwitcher
    case save
    case openVault
    case copyLink
    case revealInFinder
    case noteHistory
    /// The star of ADR-0012 D6, on the note that is open. It could only be set from the
    /// note list's context menu, so the note you were reading was the one note you could
    /// not star.
    case toggleStar
    /// Writes a template into the note already open (ADR-0011 D5): until now a template
    /// could only start a new note.
    case applyTemplate

    /// The tabs of the Note pane (ADR-0012 D5). Cmd+1…Cmd+9 chooses one and is
    /// deliberately *not* here: a positional key is not a command, it is nine of them, and
    /// nine rows in the settings list to remap "the third tab" is a worse pane for a
    /// binding no application lets you change anyway.
    case newTab
    case closeTab
    case reopenTab

    case pastePlain
    case findInNote
    case replaceInNote
    /// The two the standard Find submenu carried before it was replaced (M8). They exist
    /// because that submenu is being taken away, not because they are new: Cmd+G and
    /// Cmd+Shift+G work today through AppKit's own find bar, and a find of ours that dropped
    /// them would be a smaller feature wearing a bigger one's name.
    case findNext
    case findPrevious

    case insertWikilink
    case insertRelated

    case paneNotes
    case paneWorkspace
    case paneToday
    case paneTasks
    case paneConformance
    case paneDiary
    case paneTags
    case paneViews
    case paneStarred
    // `readingMode` was here, with a `Cmd+Shift+M` default (ADR-0029 §D13). Removing a case
    // is not the same operation as moving one, which ADR-0005 §D8 forbids: the raw values are
    // the keys of the overrides file, and `ShortcutStore.decode` already skips a key it does
    // not recognise, so a rebound `Cmd+Shift+M` becomes an orphan entry rather than a crash -
    // which is correct, because the command it named no longer exists.
    /// Backlinks, «task collegati» and the unlinked mentions of ADR-0012 D9 all live in
    /// the inspector, which had a toolbar button and nothing else.
    case toggleInspector
    case runConformanceCheck
    case foldSection
    case unfoldAll

    case taskToggle
    case taskToday
    case taskTomorrow
    case taskPlusTwo
    case taskNextWeek
    /// "Aggiungi sotto-task" (ADR-0021 D9, A9; UX blueprint's menu bar map): opens the
    /// composer with `TaskDraft.parent` set to the selected task, so `captureTask`
    /// routes through `TaskParser.insertingSubtask(in:below:draft:)` instead of
    /// appending an ordinary top-level task.
    case taskAddSubtask

    /// The window's history (ADR-0015). Appended at the end rather than placed beside the
    /// pane commands they sit with in the menu: these rawValues are the keys of the overrides
    /// file, so a new case may be added anywhere but an existing one must not move.
    case goBack
    case goForward

    case previousDay
    case nextDay
    case newEvent
    case newReminder

    // ADR-0032 (Plaud recording import into Pergamenum), plan
    // docs/superpowers/plans/2026-09-05-plaud-recording-import-into-pergamenum.md, Task 8 -
    // R-01, R-11, R-15; ADR §D15. Appended at the end, never inserted: the raw values are the
    // keys of the overrides file (ADR-0005 §D8).
    /// The tenth pane: jumps to "Registrazioni", the sidebar row this chain adds
    /// (`Navigation.Pane.recordings`, wired in Task 8's coder step - not yet a case of that
    /// enum, so nothing here resolves it to a pane yet).
    case paneRecordings
    /// Re-fetches `/recordings` for the current vault (R-01) - the toolbar's
    /// `arrow.clockwise` button and this menu entry are wired to the same action (UX
    /// blueprint). Enabled only while `navigation.pane == .recordings`
    /// (`CommandActions+CanRun.swift`, Task 8's coder step).
    case refreshRecordings

    // ADR-0036 (Pratiche), plan docs/superpowers/plans/2026-09-09-pratiche.md, Task 6 -
    // R-33; ADR §D8. Appended at the end, never inserted (ADR-0005 §D8: raw values are
    // the overrides-file keys). The case is a declaration this batch owns; Task 8 still
    // does the `com.apple.symbolichotkeys` measurement before the binding below ships -
    // it may change `defaultBinding` below, never remove or move this case.
    /// The eleventh pane: jumps to "Pratiche" (`Navigation.Pane.pratiche`).
    case panePratiche

    var id: String { rawValue }

    /// Which menu the command lives in, so the settings pane can group the list the
    /// same way the menu bar does.
    enum Section: String, CaseIterable, Identifiable, Sendable {
        case file, tab, edit, insert, view, task, calendar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .file: "File"
            case .tab: "Tab"
            case .edit: "Modifica"
            case .insert: "Inserisci"
            case .view: "Vista"
            case .task: "Task"
            case .calendar: "Calendario"
            }
        }
    }

    var section: Section {
        switch self {
        case .newNote, .newBoard, .dailyNote, .quickTask, .globalCapture, .quickLook, .globalSearch,
             .quickSwitcher, .save, .openVault, .copyLink, .revealInFinder, .noteHistory,
             .toggleStar, .applyTemplate:
            .file
        case .newTab, .closeTab, .reopenTab:
            .tab
        case .pastePlain, .findInNote, .replaceInNote, .findNext, .findPrevious:
            .edit
        case .insertWikilink, .insertRelated:
            .insert
        case .paneNotes, .paneWorkspace, .paneToday, .paneTasks, .paneConformance, .paneTags,
             .paneDiary, .paneViews, .paneStarred, .toggleInspector,
             .runConformanceCheck, .foldSection, .unfoldAll, .goBack, .goForward,
             .paneRecordings, .refreshRecordings, .panePratiche:
            .view
        case .taskToggle, .taskToday, .taskTomorrow, .taskPlusTwo, .taskNextWeek, .taskAddSubtask:
            .task
        case .previousDay, .nextDay, .newEvent, .newReminder:
            .calendar
        }
    }

    /// The label the menu shows, repeated in the settings list so the two are
    /// recognisably the same command.
    var title: String {
        switch self {
        case .newNote: "Nuova nota"
        case .newBoard: "Nuova board"
        case .dailyNote: "Nota di oggi"
        case .newTab: "Nuova tab"
        case .closeTab: "Chiudi tab"
        case .reopenTab: "Riapri l'ultima tab chiusa"
        case .quickTask: "Nuovo task rapido"
        case .globalCapture: "Cattura rapida (da qualsiasi app)"
        case .quickLook: "Anteprima rapida"
        case .globalSearch: "Ricerca globale"
        case .quickSwitcher: "Vai alla nota"
        case .save: "Salva"
        case .openVault: "Apri cartella note"
        case .copyLink: "Copia link Pergamenum"
        case .revealInFinder: "Rivela nel Finder"
        case .noteHistory: "Cronologia…"
        case .toggleStar: "Preferita"
        case .applyTemplate: "Applica un template…"
        case .pastePlain: "Incolla come testo puro"
        case .findInNote: "Trova nella nota"
        case .replaceInNote: "Sostituisci"
        case .findNext: "Trova successivo"
        case .findPrevious: "Trova precedente"
        case .insertWikilink: "Inserisci wikilink"
        case .insertRelated: "Inserisci nota correlata"
        case .goBack: "Indietro"
        case .goForward: "Avanti"
        case .paneNotes: "Vai a Note"
        case .paneWorkspace: "Vai a Workspace"
        case .paneToday: "Vai a Oggi"
        case .paneTasks: "Vai ad Attività"
        case .paneConformance: "Vai a Conformità"
        case .paneDiary: "Vai a Diario"
        case .paneTags: "Vai a Tag"
        case .paneViews: "Vai a Viste"
        case .paneStarred: "Vai a Preferite"
        case .toggleInspector: "Ispettore"
        case .runConformanceCheck: "Verifica conformità"
        case .foldSection: "Ripiega la sezione"
        case .unfoldAll: "Espandi tutto"
        case .taskToggle: "Completa o riapri il task"
        case .taskToday: "Pianifica il task oggi"
        case .taskTomorrow: "Pianifica il task domani"
        case .taskPlusTwo: "Pianifica il task fra 2 giorni"
        case .taskNextWeek: "Pianifica il task la settimana prossima"
        case .taskAddSubtask: "Aggiungi sotto-task"
        case .previousDay: "Giorno precedente"
        case .nextDay: "Giorno successivo"
        case .newEvent: "Nuovo evento"
        case .newReminder: "Nuovo promemoria"
        case .paneRecordings: "Vai a Registrazioni"
        case .refreshRecordings: "Aggiorna registrazioni"
        case .panePratiche: "Vai a Pratiche"
        }
    }

    /// The binding used until the user changes it.
    ///
    /// These are the keys SPEC §10 assigns, with two departures recorded in
    /// ADR-0002: the panes take Control-Command-digit, which §10 leaves unassigned,
    /// and reading mode keeps Cmd+Shift+M because §10's Cmd+Shift+E is already the
    /// Calendario menu's "Nuovo promemoria".
    var defaultBinding: KeyBinding {
        switch self {
        case .newNote: KeyBinding("n", .command)
        // Not Cmd+Shift+C: it collides with a global hotkey Paste registers, found on
        // screen (the app's own hotkey wins, and Pergamenum's menu equivalent never
        // fires). Checked the same way ⌃Space was for `globalCapture`.
        case .newBoard: KeyBinding("b", [.command, .shift])
        // Cmd+T is the tab key in every application that has tabs, so «Nota di oggi»
        // gives it up rather than making Cmd+T mean something else here (ADR-0012 D5).
        // Cmd+Shift+T is not free either: it is «riapri l'ultima tab chiusa», by the same
        // convention. Cmd+Shift+D was checked and is unused, by this app and by the system.
        case .dailyNote: KeyBinding("d", [.command, .shift])
        case .newTab: KeyBinding("t", .command)
        // Cmd+W closes the tab and Cmd+Shift+W the window, as in Safari, Xcode and the
        // Finder. The window command is AppKit's own and is rebound in the menu, not here.
        case .closeTab: KeyBinding("w", .command)
        case .reopenTab: KeyBinding("t", [.command, .shift])
        case .quickTask: KeyBinding("n", [.command, .shift])
        // Not ⌃Space, which was the first choice and is Craft's: Craft holds it
        // without asking for exclusivity, so Pergamenum's exclusive registration
        // *succeeds* and the event still goes to Craft. Tried on 2026-08-17 and only
        // Craft's panel opened. ⌃⌥Space instead: the system entry that would use it
        // (id 61, next input source) is disabled on this Mac.
        case .globalCapture: KeyBinding("space", [.control, .option])
        case .quickLook: KeyBinding("space")
        case .globalSearch: KeyBinding("f", [.command, .shift])
        case .quickSwitcher: KeyBinding("o", .command)
        case .save: KeyBinding("s", .command)
        case .openVault: KeyBinding("o", [.command, .shift])
        case .copyLink: KeyBinding("l", [.command, .shift])
        case .revealInFinder: KeyBinding("r", [.command, .shift])
        // Not ⌥⌘H, which the mockup drew: that is the system's own "Nascondi altre",
        // so the app would either lose the key or shadow a command every Mac has.
        // Checked rather than assumed, the same way ⌃Space was for `globalCapture`.
        case .noteHistory: KeyBinding("h", [.command, .shift])
        // All three checked against `com.apple.symbolichotkeys` before being bound, as
        // the Tag pane's key was: the system holds Opt+Cmd+D, Shift+Cmd+- and a family of
        // Ctrl+arrow combinations on this Mac, and none of these three.
        case .toggleStar: KeyBinding("s", [.command, .shift])
        case .applyTemplate: KeyBinding("t", [.command, .control])
        case .pastePlain: KeyBinding("v", [.command, .shift, .option])
        case .findInNote: KeyBinding("f", .command)
        case .replaceInNote: KeyBinding("f", [.command, .option])
        case .findNext: KeyBinding("g", .command)
        case .findPrevious: KeyBinding("g", [.command, .shift])
        case .insertWikilink: KeyBinding("[", [.command, .shift])
        case .insertRelated: KeyBinding("k", [.command, .shift])
        // The system-wide keys for this, and both free here: `Cmd+Shift+[` is «Inserisci
        // wikilink» and nothing binds the unshifted brackets (ADR-0015 §D5).
        case .goBack: KeyBinding("[", .command)
        case .goForward: KeyBinding("]", .command)
        case .paneNotes: KeyBinding("1", [.command, .control])
        case .paneWorkspace: KeyBinding("2", [.command, .control])
        case .paneToday: KeyBinding("3", [.command, .control])
        case .paneTasks: KeyBinding("4", [.command, .control])
        case .paneConformance: KeyBinding("5", [.command, .control])
        case .paneDiary: KeyBinding("6", [.command, .control])
        // Checked against the system's own before it was bound, which is the M9 lesson:
        // `com.apple.symbolichotkeys` defines nothing on Ctrl+Cmd+7.
        case .paneTags: KeyBinding("7", [.command, .control])
        // Eighth pane, eighth digit. The pane list is numbered in the order the panes
        // were built, not in the order the sidebar draws them: the raw values here are
        // the keys of the overrides file, so renumbering would move a binding somebody
        // had changed.
        case .paneViews: KeyBinding("8", [.command, .control])
        case .paneStarred: KeyBinding("9", [.command, .control])
        case .toggleInspector: KeyBinding("i", [.command, .option])
        case .runConformanceCheck: KeyBinding("l", [.command, .control])
        // The keys Xcode uses for the same thing. ⌘← and ⌘→ are already the
        // Calendario menu's day navigation, so the option key is what keeps them apart.
        case .foldSection: KeyBinding("left", [.command, .option])
        case .unfoldAll: KeyBinding("right", [.command, .option])
        case .taskToggle: KeyBinding("return", .command)
        // Opt+Cmd+digit, not Cmd+digit: Cmd+1…Cmd+9 chooses a tab now (ADR-0012 D5), and
        // choosing a tab is a gesture of every minute against scheduling a task for the week
        // after next. Four defaults moved at once, which is the whole cost of that decision.
        case .taskToday: KeyBinding("0", [.command, .option])
        case .taskTomorrow: KeyBinding("1", [.command, .option])
        case .taskPlusTwo: KeyBinding("2", [.command, .option])
        case .taskNextWeek: KeyBinding("3", [.command, .option])
        // Checked against the catalogue (`noTwoCommandsShipOnTheSameKeys`) and against
        // the app's own map before being bound: `taskToggle` is Cmd+Return, `newBoard`
        // is Cmd+Shift+B, `quickTask` is Cmd+Shift+N, and the board's bare `Return` is
        // scoped to an open crop, so Cmd+Shift+Return collides with none of them
        // (UX blueprint's keyboard table).
        case .taskAddSubtask: KeyBinding("return", [.command, .shift])
        case .previousDay: KeyBinding("left", .command)
        case .nextDay: KeyBinding("right", .command)
        case .newEvent: KeyBinding("e", .command)
        case .newReminder: KeyBinding("e", [.command, .shift])
        // Measured free against `com.apple.symbolichotkeys` (58 entries parsed, no match for
        // keycode 29 with Cmd+Ctrl, ADR §D15): the digit after the nine already bound.
        case .paneRecordings: KeyBinding("0", [.command, .control])
        // Measured free both in this app (`revealInFinder` holds Cmd+Shift+R; nothing holds
        // the unshifted form) and in the system map (ADR §D15).
        case .refreshRecordings: KeyBinding("r", .command)
        // Ctrl+Cmd+P: the digits are exhausted (Ctrl+Cmd+0 is `.paneRecordings`),
        // so the eleventh pane takes the next free letter on the same modifier pair
        // (plan Task 6; Task 8 still measures it against `com.apple.symbolichotkeys`
        // before this ships, ADR §D8).
        case .panePratiche: KeyBinding("p", [.command, .control])
        }
    }
}
