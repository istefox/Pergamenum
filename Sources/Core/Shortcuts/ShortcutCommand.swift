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

    case pastePlain
    case findInNote
    case replaceInNote

    case insertWikilink
    case insertRelated

    case paneNotes
    case paneWorkspace
    case paneToday
    case paneTasks
    case paneConformance
    case paneDiary
    case readingMode
    case runConformanceCheck

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
        case file, edit, insert, view, task, calendar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .file: "File"
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
             .quickSwitcher, .save, .openVault, .copyLink, .revealInFinder:
            .file
        case .pastePlain, .findInNote, .replaceInNote:
            .edit
        case .insertWikilink, .insertRelated:
            .insert
        case .paneNotes, .paneWorkspace, .paneToday, .paneTasks, .paneConformance,
             .paneDiary, .readingMode, .runConformanceCheck:
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
        case .quickTask: "Nuovo task rapido"
        case .globalCapture: "Cattura rapida (da qualsiasi app)"
        case .quickLook: "Anteprima rapida"
        case .globalSearch: "Ricerca globale"
        case .quickSwitcher: "Vai alla nota"
        case .save: "Salva"
        case .openVault: "Apri cartella note"
        case .copyLink: "Copia link Pergamenum"
        case .revealInFinder: "Rivela nel Finder"
        case .pastePlain: "Incolla come testo puro"
        case .findInNote: "Trova nella nota"
        case .replaceInNote: "Sostituisci"
        case .insertWikilink: "Inserisci wikilink"
        case .insertRelated: "Inserisci nota correlata"
        case .paneNotes: "Vai a Note"
        case .paneWorkspace: "Vai a Workspace"
        case .paneToday: "Vai a Oggi"
        case .paneTasks: "Vai ad Attività"
        case .paneConformance: "Vai a Conformità"
        case .paneDiary: "Vai a Diario"
        case .readingMode: "Modalità lettura"
        case .runConformanceCheck: "Verifica conformità"
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
        case .dailyNote: KeyBinding("t", .command)
        case .quickTask: KeyBinding("n", [.command, .shift])
        // Craft's own combination, and free on this machine: the system table has
        // ids 60, 61 and 64 all disabled. A third-party launcher does not appear
        // there, which is why the registration reports what it actually got.
        case .globalCapture: KeyBinding("space", .control)
        case .quickLook: KeyBinding("space")
        case .globalSearch: KeyBinding("f", [.command, .shift])
        case .quickSwitcher: KeyBinding("o", .command)
        case .save: KeyBinding("s", .command)
        case .openVault: KeyBinding("o", [.command, .shift])
        case .copyLink: KeyBinding("l", [.command, .shift])
        case .revealInFinder: KeyBinding("r", [.command, .shift])
        case .pastePlain: KeyBinding("v", [.command, .shift, .option])
        case .findInNote: KeyBinding("f", .command)
        case .replaceInNote: KeyBinding("f", [.command, .option])
        case .insertWikilink: KeyBinding("[", [.command, .shift])
        case .insertRelated: KeyBinding("k", [.command, .shift])
        case .paneNotes: KeyBinding("1", [.command, .control])
        case .paneWorkspace: KeyBinding("2", [.command, .control])
        case .paneToday: KeyBinding("3", [.command, .control])
        case .paneTasks: KeyBinding("4", [.command, .control])
        case .paneConformance: KeyBinding("5", [.command, .control])
        case .paneDiary: KeyBinding("6", [.command, .control])
        case .readingMode: KeyBinding("m", [.command, .shift])
        case .runConformanceCheck: KeyBinding("l", [.command, .control])
        case .taskToggle: KeyBinding("return", .command)
        case .taskToday: KeyBinding("0", .command)
        case .taskTomorrow: KeyBinding("1", .command)
        case .taskPlusTwo: KeyBinding("2", .command)
        case .taskNextWeek: KeyBinding("3", .command)
        case .previousDay: KeyBinding("left", .command)
        case .nextDay: KeyBinding("right", .command)
        case .newEvent: KeyBinding("e", .command)
        case .newReminder: KeyBinding("e", [.command, .shift])
        }
    }
}
