import Foundation

/// ADR-0023 §D1, §D10 (plan 2026-08-25-universal-command-surface-parity, Task 7): the
/// single naming site for the calendar day cell's «Nuovo evento» / «Nuovo promemoria»
/// pair, read by `MonthView`, `WeekView` and `MiniCalendar` alike (R-09) so the three
/// surfaces cannot be reworded, re-symboled or reordered apart, and read from the same
/// strings the Calendario menu already shows (R-13) rather than retyped.
enum CalendarDayCommand: Equatable {
    case newEvent
    case newReminder

    /// Taken from `ShortcutCommand` by identity, not retyped — the menu bar's own
    /// wording, so the two cannot drift apart at a future rewording of either.
    var title: String {
        switch self {
        case .newEvent: ShortcutCommand.newEvent.title
        case .newReminder: ShortcutCommand.newReminder.title
        }
    }

    /// `calendar.badge.plus` / `bell.badge`, recorded here as the one place either
    /// symbol is chosen for this cluster (ADR-0023 §D1).
    ///
    /// `calendar.badge.plus` is not a choice made here: it is the glyph the day view's
    /// own «Nuovo evento» toolbar button already draws (`DayToolbar.swift:96`), so R-13's
    /// "same command, same icon" holds by reading rather than by review. «Nuovo
    /// promemoria» has no toolbar button to inherit from - it left that toolbar for the
    /// bell to become a filter (`DayToolbar.swift:9`) - so `bell.badge` is a first choice,
    /// taken from the bell this app already draws for what is coming up
    /// (`DayToolbar.swift:81`) and recorded here rather than left to the next surface.
    ///
    /// Neither is drawn by the three day-cell menus: they sit beside «Vai a questo
    /// giorno» and the daily-note entry, which carry no symbol, and ADR-0023 §D1 counts
    /// the absence of a symbol as part of what the surfaces have to keep identical.
    var symbol: String {
        switch self {
        case .newEvent: "calendar.badge.plus"
        case .newReminder: "bell.badge"
        }
    }

    /// One entry as a day cell draws it: the command, the two strings that name it, and
    /// whether it can be invoked at all right now.
    ///
    /// A struct rather than the four-member tuple this started as: SwiftLint reports a
    /// tuple that wide as an error, and this codebase restructures rather than writing its
    /// first `swiftlint:disable` (CLAUDE.md). `Identifiable` on the command, so the menu
    /// iterates the catalogue directly - a key path into a tuple is not a thing Swift has.
    struct Entry: Equatable, Identifiable {
        let command: CalendarDayCommand
        let title: String
        let symbol: String
        let isEnabled: Bool

        var id: CalendarDayCommand { command }
    }

    /// Disabled, not omitted, without EventKit access (ADR-0023 §D10) — a day cell that
    /// silently drops «Nuovo evento» teaches nobody Pergamenum can make one.
    ///
    /// No `CalendarDate` parameter: the same two entries render on every day, which is
    /// what makes R-09's "identici tra loro" a property of the three call sites sharing
    /// this one function rather than three careful copies.
    ///
    /// Both entries, always, in the order the Calendario menu lists them
    /// (`MenuCommands.swift:123-129`): each carries the access its own command needs and
    /// nothing else decides whether it appears.
    static func entries(eventAccess: Bool, reminderAccess: Bool) -> [Entry] {
        [
            entry(.newEvent, isEnabled: eventAccess),
            entry(.newReminder, isEnabled: reminderAccess),
        ]
    }

    /// An entry built from its own command, written once so a case cannot ship with its
    /// neighbour's title or symbol pasted onto it.
    private static func entry(_ command: CalendarDayCommand, isEnabled: Bool) -> Entry {
        Entry(command: command, title: command.title, symbol: command.symbol, isEnabled: isEnabled)
    }
}
