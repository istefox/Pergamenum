import Foundation

/// What a day can hold on the week and the month grids (ADR-0013 §D4). Four kinds and
/// no fifth, each recognisable without a legend: the colour is the one the rest of the
/// app already uses for that thing.
///
/// Declared by the mockup first and moved here when the mockup became a view, so there
/// is one vocabulary rather than a drawn one and a built one.
enum WeekEntryKind: Sendable {
    case event
    case block
    case task
    case deadline

    var symbol: String {
        switch self {
        case .event: "calendar"
        case .block: "rectangle.fill"
        case .task: "square"
        case .deadline: "exclamationmark.circle"
        }
    }

    var token: ColorToken {
        switch self {
        case .event: .accentPrimary
        case .block: .taskScheduled
        case .task: .taskOpen
        case .deadline: .taskOverdue
        }
    }
}

/// One line in a day of the week or the month.
///
/// A value rather than the event, block or task itself: the four sources have nothing
/// in common except that they happen on a day, and a column that switched on the type
/// of each row would be four columns drawn on top of each other.
struct WeekEntry: Identifiable, Equatable, Sendable {
    let id: String
    let kind: WeekEntryKind
    let title: String
    /// `09:30`, drawn as a prefix. A list ordered by time says the same thing a grid
    /// does about *when*, and says it in a ninety-point column.
    let timeText: String?
    /// Minutes from midnight, for the ordering. Nil for something with no hour.
    let minutes: Int?
    /// The note the row comes from, when there is one: a task row opens its own note,
    /// an EventKit row has no file to open.
    let sourcePath: String?
    /// The line the task is written on, so a click lands on it rather than at the top of
    /// a note the reader then has to search.
    let lineIndex: Int?
}

/// A day as the week and the month draw it.
struct DayColumn: Identifiable, Equatable, Sendable {
    let day: CalendarDate
    let entries: [WeekEntry]
    /// Whether the vault already holds the note for the day. A dot in the header rather
    /// than a row, because the note is the column's subject and not one of the things
    /// in it.
    let hasNote: Bool

    var id: String { day.compactForm }
}

/// The arithmetic of the two new scales, and what fills their cells.
///
/// Pure and apart from the views for the reason `MonthGrid` gives: a calendar that is
/// wrong on one month in twelve is not something to notice by looking at it.
enum WeekPlan {
    /// The seven days of the week a day falls in, Monday first as the Italian week is
    /// read.
    static func week(containing day: CalendarDate) -> [CalendarDate] {
        let monday = day.adding(days: -mondayOffset(of: day))
        return (0..<7).map { monday.adding(days: $0) }
    }

    /// The month laid out in weeks of seven, with the neighbouring months kept rather
    /// than padded with holes.
    ///
    /// `MonthGrid.weeks` pads with nil, which is right for a date picker: an empty cell
    /// there is a cell nobody can click. The month *scale* draws what happens on those
    /// days, so the last days of the previous month stay visible in grey - and the same
    /// seven-column arithmetic as the week, so the two line up when you switch.
    static func monthWeeks(of month: CalendarDate) -> [[CalendarDate]] {
        guard let first = CalendarDate(year: month.year, month: month.month, day: 1)
        else { return [] }
        let last = lastDay(of: month)

        var weeks: [[CalendarDate]] = []
        var cursor = first.adding(days: -mondayOffset(of: first))
        while cursor <= last {
            weeks.append((0..<7).map { cursor.adding(days: $0) })
            cursor = cursor.adding(days: 7)
        }
        return weeks
    }

    /// The four sources of one day, in the one order they are drawn in everywhere
    /// (ADR-0013 §D4): events with their hour, then time blocks, then the tasks
    /// scheduled that day, then the deadlines.
    ///
    /// A task scheduled on a day it is also due on appears once, as a task: two rows
    /// for one line of markdown would make the week say the day holds more than it
    /// does.
    static func entries(
        on day: CalendarDate,
        events: [CalendarEvent],
        blocks: [TimeBlock],
        tasks: [TaskItem]
    ) -> [WeekEntry] {
        let scheduled = tasks.filter { $0.isScheduled(on: day) }
        let scheduledIDs = Set(scheduled.map(\.id))
        let due = tasks.filter { $0.due == day && !scheduledIDs.contains($0.id) }

        return eventEntries(events) + blockEntries(blocks)
            + taskEntries(scheduled) + deadlineEntries(due)
    }

    /// What a column shows and how many it could not, never truncating in silence: a
    /// week that quietly showed four of eleven would be a week that lies about how full
    /// it is.
    static func split(_ entries: [WeekEntry], limit: Int) -> (shown: [WeekEntry], hidden: Int) {
        guard limit > 0, entries.count > limit else { return (entries, 0) }
        return (Array(entries.prefix(limit)), entries.count - limit)
    }

    // MARK: The four sources

    private static func eventEntries(_ events: [CalendarEvent]) -> [WeekEntry] {
        events
            .map { event in
                let minutes = event.isAllDay ? nil : minutes(from: event.start)
                return WeekEntry(
                    id: "event-\(event.id)",
                    kind: .event,
                    title: event.title,
                    timeText: minutes.map(text(ofMinutes:)),
                    minutes: minutes,
                    sourcePath: nil,
                    lineIndex: nil
                )
            }
            // An all-day event first: it is the frame the rest of the day sits in.
            .sorted { ($0.minutes ?? -1) < ($1.minutes ?? -1) }
    }

    private static func blockEntries(_ blocks: [TimeBlock]) -> [WeekEntry] {
        blocks
            .sorted { $0.startMinutes < $1.startMinutes }
            .map { block in
                WeekEntry(
                    id: "block-\(block.id)",
                    kind: .block,
                    title: block.title,
                    timeText: block.startText,
                    minutes: block.startMinutes,
                    sourcePath: nil,
                    lineIndex: nil
                )
            }
    }

    private static func taskEntries(_ tasks: [TaskItem]) -> [WeekEntry] {
        tasks
            .sorted { lhs, rhs in
                let left = lhs.scheduledTime?.minutes ?? Int.max
                let right = rhs.scheduledTime?.minutes ?? Int.max
                return left == right ? lhs.text < rhs.text : left < right
            }
            .map { task in
                WeekEntry(
                    id: "task-\(task.id)",
                    kind: .task,
                    title: task.text,
                    timeText: task.scheduledTime?.text,
                    minutes: task.scheduledTime?.minutes,
                    sourcePath: task.sourcePath,
                    lineIndex: task.lineIndex
                )
            }
    }

    private static func deadlineEntries(_ tasks: [TaskItem]) -> [WeekEntry] {
        tasks
            .sorted { lhs, rhs in
                let left = lhs.dueTime?.minutes ?? Int.max
                let right = rhs.dueTime?.minutes ?? Int.max
                return left == right ? lhs.text < rhs.text : left < right
            }
            .map { task in
                WeekEntry(
                    id: "deadline-\(task.id)",
                    kind: .deadline,
                    title: task.text,
                    timeText: task.dueTime?.text,
                    minutes: task.dueTime?.minutes,
                    sourcePath: task.sourcePath,
                    lineIndex: task.lineIndex
                )
            }
    }

    // MARK: Days and hours

    /// How many days back Monday is. `DateEntry.weekday` numbers Sunday 1, as
    /// `Calendar` does, and this is the same conversion `MonthGrid` makes.
    private static func mondayOffset(of day: CalendarDate) -> Int {
        (DateEntry.weekday(of: day) + 5) % 7
    }

    private static func lastDay(of month: CalendarDate) -> CalendarDate {
        guard let first = CalendarDate(year: month.year, month: month.month, day: 1)
        else { return month }
        var cursor = first
        while true {
            let next = cursor.adding(days: 1)
            if next.month != month.month { return cursor }
            cursor = next
        }
    }

    /// The zone here is the machine's, unlike everywhere else in this file: an event is
    /// an instant, and the hour a person reads on it is the hour their Mac shows.
    private static func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func text(ofMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
