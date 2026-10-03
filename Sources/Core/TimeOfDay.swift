import Foundation

/// The one spelling of a time of day the app writes and draws: `07:30`, `06:00`, `24:00`.
///
/// One place, so a task's `@remind`, a time block's heading, an hour in the day grid and a
/// picker row cannot drift into two conventions (PG-263). Fixed rather than locale-derived:
/// the interface is Italian, which is 24-hour, and several of these strings are file
/// formats a parser reads back.
///
/// No range checks: an hour of 24 is written as given, which is how the end of the day is
/// spelled (`DiaryEntry.timeText`, `HourWindow.label`), and validating a time is the
/// parser's job (`TaskTime.init?(text:)`), not the writer's.
enum TimeOfDay {
    /// `07:30`.
    static func formatted(hour: Int, minute: Int = 0) -> String {
        "\(twoDigits(hour)):\(twoDigits(minute))"
    }

    /// `07:30` for 450 minutes from midnight. 1440 reads `24:00`, not `00:00`.
    static func formatted(minutes: Int) -> String {
        formatted(hour: minutes / 60, minute: minutes % 60)
    }

    /// `07`: one clock field, zero-padded to two digits - a picker row, the `HHMM` of a
    /// file name, the minutes of a duration.
    static func twoDigits(_ value: Int) -> String {
        (0..<10).contains(value) ? "0\(value)" : "\(value)"
    }
}
