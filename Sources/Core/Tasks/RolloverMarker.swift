import Foundation

/// The day a rolled-over task belongs to, written the way a row shows it (ADR-0013 §D1).
///
/// **This string is the whole amendment.** SPEC §7.3 refuses rollover because a task must not
/// silently change the day its file says; §D1 allows it back only on the condition that the row
/// says where the task actually is. A rolled-over row without this marker would look like an
/// ordinary one, which is the silent move drawn instead of written - so the marker is not
/// decoration and it is not optional.
///
/// One function rather than two call sites formatting a date each: the day view and the
/// Attività pane draw the same list, and a marker that read differently in the two would make
/// them look like two facts about the same task.
enum RolloverMarker {
    /// `lunedì 17/08` - the weekday, because that is how a person remembers which day they
    /// meant, and the date without the year, because a rollover window measured in days never
    /// crosses one far enough for it to matter.
    static func text(for day: CalendarDate) -> String {
        String(format: "%@ %02d/%02d", DateEntry.weekdayName(of: day), day.day, day.month)
    }
}
