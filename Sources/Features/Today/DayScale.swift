import Foundation

/// The three scales of the day view (ADR-0013 §D4).
///
/// Giorno, Settimana and Mese are three scales of one thing rather than three places:
/// all three are anchored on `DayController.day`, so moving in the week and switching
/// back to the day lands on the day the week had highlighted. A fourth item in the
/// sidebar was refused for the same reason - the sidebar names places in the vault,
/// and a second calendar entry would make the day and the week look like two sources
/// of truth about the same four things.
enum DayScale: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Giorno"
        case .week: "Settimana"
        case .month: "Mese"
        }
    }

    var symbol: String {
        switch self {
        case .day: "rectangle.portrait"
        case .week: "rectangle.split.3x1"
        case .month: "square.grid.3x3"
        }
    }

    /// What the two navigators move by at this scale: a day, a week, a month.
    ///
    /// Here rather than in the toolbar because the menu's `Cmd+←` runs the same
    /// command, and a chevron that moved a week while the shortcut moved a day would
    /// be two navigations wearing one name.
    func anchor(_ day: CalendarDate, movedBy steps: Int) -> CalendarDate {
        switch self {
        case .day: day.adding(days: steps)
        case .week: day.adding(days: steps * 7)
        case .month: MonthGrid.month(day, offsetBy: steps)
        }
    }

    /// What the navigators are called at this scale, for the tooltip.
    var previousTitle: String {
        switch self {
        case .day: "Giorno precedente"
        case .week: "Settimana precedente"
        case .month: "Mese precedente"
        }
    }

    var nextTitle: String {
        switch self {
        case .day: "Giorno successivo"
        case .week: "Settimana successiva"
        case .month: "Mese successivo"
        }
    }
}
