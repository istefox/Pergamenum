import Foundation

/// The Italian calendar's red days, computed rather than fetched.
///
/// "Import the holidays every year" cannot mean download them: no feature of this app
/// makes a network call (principle 2). It does not need to. Eleven of the twelve
/// national holidays are fixed dates, and the twelfth follows Easter, which is
/// arithmetic - the Gregorian computus, unchanged since 1582 and correct for any year
/// this app will ever be asked about. A calendar that had to be updated once a year is
/// a calendar that is wrong the year nobody remembers to update it.
///
/// The local patron saint is the one day no algorithm knows: it is a setting, empty
/// until somebody fills it in.
enum ItalianHolidays {
    /// A day off, and what it is called.
    struct Holiday: Equatable, Sendable {
        let day: CalendarDate
        let name: String
    }

    /// What a day is worth on an Italian calendar.
    ///
    /// `holiday` beats `festive`: the 1st of November 2026 falls on a Sunday and is
    /// still Ognissanti, and a calendar that called it "domenica" would be dropping the
    /// only information the colour was added to carry.
    enum DayKind: Equatable, Sendable {
        case ordinary
        /// Saturday: not a holiday, but not a working day either for most of the
        /// country - which is exactly the distinction an Italian calendar draws.
        case prefestive
        case festive
        case holiday
    }

    /// Easter Sunday, by the Gregorian computus (Meeus/Jones/Butcher).
    ///
    /// Integer arithmetic only, no `Calendar` and no `Date`: this is the one date in
    /// the year that cannot be looked up in a table, and it is also the one a timezone
    /// could silently move by a day.
    static func easter(inYear year: Int) -> CalendarDate {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        // The formula cannot produce an impossible date; the fallback is there because
        // `CalendarDate` is failable, not because this can fail.
        return CalendarDate(year: year, month: month, day: day)
            ?? CalendarDate(year: year, month: 4, day: 1)!
    }

    /// Every holiday of a year, in date order.
    static func holidays(inYear year: Int, patron: PatronSaint? = nil) -> [Holiday] {
        let easterSunday = easter(inYear: year)
        var days: [Holiday] = [
            Holiday(day: date(year, 1, 1), name: "Capodanno"),
            Holiday(day: date(year, 1, 6), name: "Epifania"),
            Holiday(day: easterSunday, name: "Pasqua"),
            Holiday(day: easterSunday.adding(days: 1), name: "Lunedì dell'Angelo"),
            Holiday(day: date(year, 4, 25), name: "Liberazione"),
            Holiday(day: date(year, 5, 1), name: "Festa del lavoro"),
            Holiday(day: date(year, 6, 2), name: "Festa della Repubblica"),
            Holiday(day: date(year, 8, 15), name: "Ferragosto"),
            Holiday(day: date(year, 11, 1), name: "Ognissanti"),
            Holiday(day: date(year, 12, 8), name: "Immacolata"),
            Holiday(day: date(year, 12, 25), name: "Natale"),
            Holiday(day: date(year, 12, 26), name: "Santo Stefano"),
        ]
        if let patron, let day = CalendarDate(year: year, month: patron.month, day: patron.day) {
            days.append(Holiday(day: day, name: patron.name))
        }
        return days.sorted { $0.day < $1.day }
    }

    /// The name of the holiday a day is, if it is one.
    static func name(of day: CalendarDate, patron: PatronSaint? = nil) -> String? {
        holidays(inYear: day.year, patron: patron).first { $0.day == day }?.name
    }

    /// What to colour a day as.
    static func kind(of day: CalendarDate, patron: PatronSaint? = nil) -> DayKind {
        if name(of: day, patron: patron) != nil { return .holiday }
        switch DateEntry.weekday(of: day) {
        case 1: return .festive      // `Calendar` numbers Sunday 1.
        case 7: return .prefestive
        default: return .ordinary
        }
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
        // Every call site here is a fixed, existing date; the fallback keeps the
        // function non-failable rather than covering a case that can occur.
        CalendarDate(year: year, month: month, day: day)
            ?? CalendarDate(year: year, month: 1, day: 1)!
    }
}

/// The local patron saint's day, which is a holiday where you live and a Tuesday
/// everywhere else.
///
/// A month and a day rather than a date: it comes back every year, and storing 2026 in
/// a settings file would make it a holiday that expires.
struct PatronSaint: Codable, Equatable, Sendable {
    var month: Int
    var day: Int
    var name: String
}
