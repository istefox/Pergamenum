import Foundation

/// The stretch of a day a timeline draws: the first hour with a line, and the last.
///
/// One type for both timelines. The Oggi pane and the Diario pane show a different part
/// of the day - a working day against a day that includes the evening it is written in -
/// and each keeps its own window in `settings.json`, but the rules about what a window
/// may say are the same for both and live here.
struct HourWindow: Codable, Equatable, Sendable {
    /// 0 to 23. The hour whose line is drawn at the top of the grid.
    var first: Int
    /// 1 to 24, always after `first`. 24 is midnight at the end of the day, which is a
    /// line on the grid and never a start.
    var last: Int

    /// The diary reaches midnight: it is written in the evening, about the evening.
    static let diaryDefault = HourWindow(first: 6, last: 24)
    /// The day view is a plan for a working day, and SPEC §8.3 spells it 06:00 to 22:00.
    static let dayDefault = HourWindow(first: 6, last: 22)

    /// The hours a picker may offer for each end.
    static let firstChoices = Array(0...22)
    static let lastChoices = Array(2...24)

    /// How many hours the grid draws.
    var hours: Int { last - first }

    /// Keeps a window usable however it was written.
    ///
    /// Applied on decode as well as on every change, because `settings.json` is meant
    /// to be editable by hand: a window of `{first: 20, last: 6}` would otherwise give
    /// a grid of negative height, which draws nothing at all and cannot be undone from
    /// inside the app.
    static func clamped(first: Int, last: Int) -> HourWindow {
        let start = min(max(0, first), 22)
        return HourWindow(first: start, last: min(max(last, start + 1), 24))
    }

    var clamped: HourWindow { HourWindow.clamped(first: first, last: last) }

    /// The window widened to hold what is drawn on it.
    ///
    /// A setting says which hours are always shown; it must not decide which hours
    /// *exist*. A block at 05:30 in a window that starts at eight would otherwise be
    /// drawn above the grid, where nothing is - invisible, and impossible to move back.
    func covering(startMinutes: [Int], endMinutes: [Int]) -> HourWindow {
        var widened = self
        if let earliest = startMinutes.min() {
            widened.first = min(widened.first, max(0, earliest / 60))
        }
        if let latest = endMinutes.max() {
            // Rounded up to the hour above, so a block ending at 21:30 gets the 22:00
            // line it needs to stop against.
            widened.last = max(widened.last, min(24, (latest + 59) / 60))
        }
        return widened
    }

    /// `06:00`, and `24:00` for the end of the day.
    static func label(_ hour: Int) -> String { String(format: "%02d:00", hour) }
}
