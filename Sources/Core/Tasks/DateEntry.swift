import Foundation

/// The dates a task panel offers, and the reading of a date typed into its field.
///
/// Kept out of the views because it is arithmetic and parsing, both of which are worth
/// testing without a window: "fra un mese" on the 31st and "la prossima settimana" on a
/// Sunday are the cases a picker gets wrong.
enum DateEntry {
    struct Option: Identifiable, Equatable, Sendable {
        /// Stable across days, so a test and an accessibility identifier can name a row
        /// without knowing what today is.
        var id: String
        var title: String
        var date: CalendarDate
    }

    /// The quick choices, in the order the panel lists them.
    static func options(from today: CalendarDate, calendar: Calendar = .gregorianUTC) -> [Option] {
        [
            Option(id: "today", title: "Oggi", date: today),
            Option(id: "tomorrow", title: "Domani", date: today.adding(days: 1)),
            Option(id: "next-week", title: "La prossima settimana", date: nextMonday(after: today, calendar: calendar)),
            Option(id: "two-weeks", title: "Fra 2 settimane", date: today.adding(days: 14)),
            Option(id: "three-weeks", title: "Fra 3 settimane", date: today.adding(days: 21)),
            Option(id: "one-month", title: "Fra un mese", date: adding(months: 1, to: today, calendar: calendar)),
        ]
    }

    /// The Monday after a day, never the same day: "la prossima settimana" chosen on a
    /// Monday means the next one, not today.
    static func nextMonday(after day: CalendarDate, calendar: Calendar = .gregorianUTC) -> CalendarDate {
        var candidate = day.adding(days: 1)
        while weekday(of: candidate, calendar: calendar) != 2 {
            candidate = candidate.adding(days: 1)
        }
        return candidate
    }

    /// Whole months through the calendar, so 31 January plus a month is 28 February
    /// rather than a date that does not exist.
    static func adding(months: Int, to day: CalendarDate, calendar: Calendar = .gregorianUTC) -> CalendarDate {
        guard let start = date(of: day, calendar: calendar),
              let moved = calendar.date(byAdding: .month, value: months, to: start)
        else { return day }
        return CalendarDate(moved, in: calendar)
    }

    /// A date typed by hand, in the forms someone actually types.
    ///
    /// Deliberately narrow: `2026-08-20`, `20/08`, `20/08/2026` and their `-` and `.`
    /// spellings, plus oggi, domani and dopodomani. Anything else is refused rather
    /// than guessed, because a capture panel that silently picks the wrong day is worse
    /// than one that picks none.
    static func parse(_ text: String, today: CalendarDate, calendar: Calendar = .gregorianUTC) -> CalendarDate? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        switch trimmed {
        case "oggi": return today
        case "domani": return today.adding(days: 1)
        case "dopodomani": return today.adding(days: 2)
        default: break
        }

        if let iso = CalendarDate(iso: trimmed) { return iso }
        return parseNumeric(trimmed, today: today)
    }

    /// `20/08`, `20-08-2026`, `20.8.26`.
    private static func parseNumeric(_ trimmed: String, today: CalendarDate) -> CalendarDate? {
        let parts = trimmed.split(whereSeparator: { "/-.".contains($0) })
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }

        switch numbers.count {
        case 2:
            // Day and month, in this year - or the next one if that day has gone by,
            // since a date typed into a task panel is almost never in the past.
            guard let thisYear = CalendarDate(year: today.year, month: numbers[1], day: numbers[0]) else {
                return nil
            }
            return thisYear < today
                ? CalendarDate(year: today.year + 1, month: numbers[1], day: numbers[0])
                : thisYear
        case 3:
            let year = numbers[2] < 100 ? 2000 + numbers[2] : numbers[2]
            return CalendarDate(year: year, month: numbers[1], day: numbers[0])
        default:
            return nil
        }
    }

    /// `gio 13 ago`, the hint the panel shows beside each choice.
    static func hint(for day: CalendarDate, calendar: Calendar = .gregorianUTC) -> String {
        guard let date = date(of: day, calendar: calendar) else { return day.description }
        return Self.hintFormatter.string(from: date)
    }

    /// `giovedì`, in the same fixed zone as everything else here: formatted through the
    /// machine's zone a day built at midday can come out as the day before.
    static func weekdayName(of day: CalendarDate, calendar: Calendar = .gregorianUTC) -> String {
        guard let date = date(of: day, calendar: calendar) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    /// The month a calendar page is showing, as `agosto`.
    static func monthName(month: Int, year: Int, calendar: Calendar = .gregorianUTC) -> String {
        guard let day = CalendarDate(year: year, month: month, day: 1),
              let date = date(of: day, calendar: calendar)
        else { return "\(month)" }
        return Self.monthFormatter.string(from: date)
    }

    static func weekday(of day: CalendarDate, calendar: Calendar = .gregorianUTC) -> Int {
        guard let date = date(of: day, calendar: calendar) else { return 1 }
        return calendar.component(.weekday, from: date)
    }

    static func date(of day: CalendarDate, calendar: Calendar = .gregorianUTC) -> Date? {
        DateComponents(
            calendar: calendar, year: day.year, month: day.month, day: day.day, hour: 12
        ).date
    }

    /// Italian, like every other string the interface shows. When the app is localised
    /// this becomes the current locale along with the rest of the UI.
    private static let uiLocale = Locale(identifier: "it_IT")

    private static let hintFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = uiLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = uiLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = uiLocale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "LLLL"
        return formatter
    }()
}

extension CalendarDate {
    /// The date some whole days later, through the calendar so month ends behave.
    func adding(days: Int) -> CalendarDate {
        let calendar = Calendar.gregorianUTC
        guard let start = DateEntry.date(of: self, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: start)
        else { return self }
        return CalendarDate(moved, in: calendar)
    }
}

extension Calendar {
    /// The calendar every date computation here uses: dates in this app are days, not
    /// instants, so the zone has to be fixed or "today" changes with the machine.
    static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "it_IT")
        return calendar
    }
}
