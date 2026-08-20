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
    case readingMode
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

    case previousDay
    case nextDay
    case newEvent
    case newReminder

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
        case .newNote, .dailyNote, .quickTask, .globalCapture, .quickLook, .globalSearch,
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
             .paneDiary, .paneViews, .paneStarred, .readingMode, .toggleInspector,
             .runConformanceCheck, .foldSection, .unfoldAll:
            .view
        case .taskToggle, .taskToday, .taskTomorrow, .taskPlusTwo, .taskNextWeek:
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
        case .paneNotes: "Vai a Note"
        case .paneWorkspace: "Vai a Workspace"
        case .paneToday: "Vai a Oggi"
        case .paneTasks: "Vai ad Attività"
        case .paneConformance: "Vai a Conformità"
        case .paneDiary: "Vai a Diario"
        case .paneTags: "Vai a Tag"
        case .paneViews: "Vai a Viste"
        case .paneStarred: "Vai a Preferite"
        case .readingMode: "Modalità lettura"
        case .toggleInspector: "Ispettore"
        case .runConformanceCheck: "Verifica conformità"
        case .foldSection: "Ripiega la sezione"
        case .unfoldAll: "Espandi tutto"
        case .taskToggle: "Completa o riapri il task"
        case .taskToday: "Pianifica il task oggi"
        case .taskTomorrow: "Pianifica il task domani"
        case .taskPlusTwo: "Pianifica il task fra 2 giorni"
        case .taskNextWeek: "Pianifica il task la settimana prossima"
        case .previousDay: "Giorno precedente"
        case .nextDay: "Giorno successivo"
        case .newEvent: "Nuovo evento"
        case .newReminder: "Nuovo promemoria"
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
        case .readingMode: KeyBinding("m", [.command, .shift])
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
        case .previousDay: KeyBinding("left", .command)
        case .nextDay: KeyBinding("right", .command)
        case .newEvent: KeyBinding("e", .command)
        case .newReminder: KeyBinding("e", [.command, .shift])
        }
    }
}
