import Foundation

/// What a view compares a date against (ADR-0014).
///
/// Either a day written out, which is what the grammar accepted until now, or one of three
/// words that resolve against the day the view is read on. A block saying
/// `modified >= 2026-08-17` is correct for six days and then narrows, quietly, to a list that
/// empties out; `modified >= week-start` asks the question the person meant.
///
/// **Three words and no more, and the shape of the set is the decision.** Days only, because
/// every field a view may compare is a `CalendarDate` carrying no time: `7d`, `2w`, `1m` would
/// be three spellings of a unit the data does not have, and a month has no fixed length. No
/// forward bound, because `+` is not in the lexer's word set and the forward question anybody
/// actually asks is about `deadline.next`, which is not comparable yet - when it is, `+` arrives
/// with the question that justifies it.
enum ViewDateBound: Equatable, Sendable {
    /// `2026-08-17`, exactly as it was.
    case day(CalendarDate)
    /// `today`.
    case today
    /// `today-7`: whole days before the day the view is read on.
    case daysBeforeToday(Int)
    /// `week-start`: the Monday of the week the view is read in.
    ///
    /// Its own case rather than `daysBeforeToday` computed at parse time, because how far back
    /// Monday is depends on the day being asked about and the parser does not know it.
    case weekStart

    static let todayKeyword = "today"
    static let weekStartKeyword = "week-start"

    /// Reads a bound, or nothing when the text is neither a date nor one of the three words.
    ///
    /// Nil rather than a throw: the caller is the one place that knows the line number, and
    /// ADR-0009 §D1 requires the error to name it. What must never happen is the third
    /// behaviour - a bound that fails to parse and is treated as absent, leaving a `where`
    /// that quietly lost half its expression.
    static func parse(_ raw: String) -> ViewDateBound? {
        if let day = CalendarDate(iso: raw) { return .day(day) }

        let lowered = raw.lowercased()
        if lowered == todayKeyword { return .today }
        if lowered == weekStartKeyword { return .weekStart }

        // `today-7`, and nothing else shaped like it: a negative or absent count is a typo, and
        // `today-0` is `today` written the long way, which is allowed rather than refused -
        // refusing it would be a rule to explain for no gain.
        guard lowered.hasPrefix(todayKeyword + "-") else { return nil }
        let digits = lowered.dropFirst(todayKeyword.count + 1)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber), let days = Int(digits) else {
            return nil
        }
        return .daysBeforeToday(days)
    }

    /// The day this bound means, on a given day.
    ///
    /// The day is handed in and never read from the clock here (ADR-0014 §D3): a test that
    /// cannot fix the day is a test that fails one day a year and passes the other three
    /// hundred and sixty-four.
    func resolved(on today: CalendarDate) -> CalendarDate {
        switch self {
        case .day(let day): day
        case .today: today
        case .daysBeforeToday(let days): today.adding(days: -days)
        case .weekStart: today.adding(days: -ViewDateBound.mondayOffset(of: today))
        }
    }

    /// How many days back Monday is.
    ///
    /// `DateEntry.weekday` numbers Sunday 1, as `Calendar` does. The same conversion
    /// `WeekPlan` and `MonthGrid` make, and Monday rather than Sunday because that is the week
    /// every grid in this app draws (ADR-0013 §D4).
    private static func mondayOffset(of day: CalendarDate) -> Int {
        (DateEntry.weekday(of: day) + 5) % 7
    }

    /// How the bound is written, so a block rendered back out is the block that was read.
    var text: String {
        switch self {
        case .day(let day): day.description
        case .today: ViewDateBound.todayKeyword
        case .daysBeforeToday(let days): "\(ViewDateBound.todayKeyword)-\(days)"
        case .weekStart: ViewDateBound.weekStartKeyword
        }
    }
}
