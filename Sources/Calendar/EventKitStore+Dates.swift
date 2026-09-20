import Foundation

extension EventKitStore {
    /// Midnight to midnight for a calendar date, in the user's own time zone.
    ///
    /// `nonisolated`: pure date arithmetic that touches no EventKit state, so binding
    /// it to the main actor would only force callers to hop for nothing.
    nonisolated static func dayRange(_ day: CalendarDate) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        return (start, end)
    }

    /// A `Date` at a given hour and minute on a calendar date.
    nonisolated static func date(_ day: CalendarDate, hour: Int, minute: Int) -> Date? {
        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)
    }
}
