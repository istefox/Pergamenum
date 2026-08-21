import Foundation

/// The one place a red day becomes a colour.
///
/// Here and not in `Core`, which the two connectors compile: a command-line tool has no
/// design tokens, and `ItalianHolidays` importing `ColorToken` would break both builds -
/// ADR-0001 §D1 enforcing itself, as it does every time something in `Core` reaches for
/// the interface.
///
/// Nil for an ordinary day, so a surface keeps whatever colour it already had rather
/// than being told what an ordinary Tuesday looks like: the week draws its numbers in
/// one colour, the mini calendar in another, and neither is wrong.
extension ItalianHolidays.DayKind {
    var token: ColorToken? {
        switch self {
        case .ordinary: nil
        case .prefestive: .calendarPrefestive
        case .festive: .calendarFestive
        case .holiday: .calendarHoliday
        }
    }
}
