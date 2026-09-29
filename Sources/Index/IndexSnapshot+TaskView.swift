import Foundation

/// The task views of SPEC §7.4 over the snapshot's stored task list, moved out of
/// `IndexSnapshot.swift` when the list became stored (ADR-0072 §D6). One membership predicate
/// per view, `belongs(_:to:on:)`, is what a list filters on and what its badge counts on, so the
/// two cannot drift.
extension IndexSnapshot {
    /// The five views of SPEC §7.4.
    enum TaskView: String, CaseIterable, Identifiable, Sendable {
        case inbox, today, upcoming, byProject, all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: "Inbox"
            case .today: "Oggi"
            case .upcoming: "Prossimi"
            case .byProject: "Per progetto"
            case .all: "Tutti"
            }
        }

        /// How the view opens before anybody touches its controls (ADR-0013 §D6).
        ///
        /// Each one reproduces what that view already did, which is why they differ: the
        /// controls are a way to change the list, not a reason to arrive at a different one.
        /// The single exception is *Oggi*, which the ADR asks for flat and in hour order -
        /// what slipped is still red, because that is the row's colour and not a heading.
        var defaultListOptions: TaskListOptions {
            switch self {
            case .inbox: TaskListOptions(grouping: .none, sorting: .text)
            case .today: TaskListOptions(grouping: .none, sorting: .schedule)
            case .upcoming: TaskListOptions(grouping: .schedule, sorting: .schedule)
            case .byProject: TaskListOptions(grouping: .project, sorting: .deadline)
            case .all: TaskListOptions(grouping: .note, sorting: .text)
            }
        }

        /// The view a captured task lands in, given the day it carries (ADR-0053 §D2 seam
        /// #6). `TasksView.followLastCapture` calls this so the pane the composer worked
        /// from ends up showing the task it just wrote.
        ///
        /// No date lands in Inbox, which is where SPEC §7.4 puts an undated task. A day
        /// today or earlier lands in Oggi - a task that slipped is exactly what that view
        /// exists to surface (SPEC §7.3). Anything later is Prossimi.
        ///
        /// Foundation-only: this file is in `sharedSources` (`Project.swift`) and compiles
        /// into `perg` and `pergamenum-mcp` as well as the app (ADR-0001 §D1), and
        /// `CalendarDate` is the only type this signature touches.
        static func landing(forCapturedDay day: CalendarDate?, today: CalendarDate) -> TaskView {
            switch day {
            case .none: .inbox
            case .some(let day) where day <= today: .today
            default: .upcoming
            }
        }
    }

    /// Tasks for one view on a given day.
    ///
    /// `today` includes overdue tasks, because a task that slipped is exactly what the
    /// day view has to surface; SPEC §7.3 rules out moving it silently.
    /// `includingCompleted` widens every view to the tasks already done, which is what
    /// the "mostra completati" filter turns on: what got finished today is part of the
    /// day, and a list that hides it reads as a day where nothing happened.
    func tasks(
        for view: TaskView, on day: CalendarDate, includingCompleted: Bool = false
    ) -> [TaskItem] {
        let listed = allTasks.filter { (includingCompleted || $0.state.isOpen) && belongs($0, to: view, on: day) }
        guard view == .upcoming else { return listed }
        return listed.sorted { ($0.scheduled ?? day) < ($1.scheduled ?? day) }
    }

    /// The unfinished tasks of the days before this one, most recent first (ADR-0013 §D1).
    ///
    /// **Nothing here is rewritten and nothing is stored.** A rolled-over task is a task whose
    /// `>date` still says Monday, computed on Thursday; the marker the row draws says which day
    /// it belongs to, and that marker is the whole difference between surfacing a task and the
    /// silent move SPEC §7.3 refuses.
    ///
    /// What `tasks(for: .today, on:)` already shows is excluded, and that exclusion is the
    /// reason this is a separate list rather than a wider filter: a task late by its `!` date is
    /// already on the day, and drawing it twice under two headings would make one list read as
    /// two problems.
    ///
    /// - Parameter daysBack: how far back to look, from `VaultSettings.rolloverDays`. A window
    ///   and not "everything before today", because a quiet fortnight would otherwise open on a
    ///   list nobody reads - which is the failure mode that makes rollover unpopular elsewhere.
    func rolledOverTasks(on day: CalendarDate, daysBack: Int) -> [TaskItem] {
        guard daysBack > 0 else { return [] }
        return allTasks
            .filter { isRolledOver($0, on: day, daysBack: daysBack) }
            // Most recent first: yesterday's is the one likely to be moved, and the oldest is
            // the one likely to be reconsidered.
            .sorted { ($0.scheduled ?? day, $0.id) > ($1.scheduled ?? day, $1.id) }
    }

    /// Open tasks carrying a `!` date on or after a day, soonest first.
    ///
    /// The day view's bell shows these: a deadline is the one date that matters before
    /// it arrives, and until now the only way to see the next one was to page the
    /// calendar until it turned up.
    func dueTasks(from day: CalendarDate, within days: Int = 30) -> [TaskItem] {
        allTasks
            .filter(\.state.isOpen)
            .filter { task in
                guard let due = task.due else { return false }
                return due >= day && daysBetween(day, due) <= days
            }
            .sorted { lhs, rhs in
                let left = (lhs.due ?? day, lhs.dueTime?.minutes ?? -1)
                let right = (rhs.due ?? day, rhs.dueTime?.minutes ?? -1)
                return left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
            }
    }

    /// Every day an open task is due on, for the marks on the month grid.
    var dueDays: Set<CalendarDate> {
        Set(allTasks.filter(\.state.isOpen).compactMap(\.due))
    }

    /// Open task counts per view, for the sidebar badges.
    ///
    /// One pass over the stored list (ADR-0072 §D6), counting on the same predicates the lists
    /// filter on, so a badge always equals the length of its list.
    ///
    /// - Parameter rolloverDays: the window `.today` also surfaces (ADR-0013 §D1), or 0 when the
    ///   setting is off. It is a parameter because the badge has to agree with the list: with
    ///   rollover on and nothing scheduled for today, *Oggi* draws seven rows and a badge
    ///   counting only what belongs to the day would leave them next to a blank number.
    func taskCounts(on day: CalendarDate, rolloverDays: Int = 0) -> [TaskView: Int] {
        var counts = Dictionary(uniqueKeysWithValues: TaskView.allCases.map { ($0, 0) })
        for task in allTasks where task.state.isOpen {
            for view in TaskView.allCases where belongs(task, to: view, on: day) {
                counts[view, default: 0] += 1
            }
            if rolloverDays > 0, isRolledOver(task, on: day, daysBack: rolloverDays) {
                counts[.today, default: 0] += 1
            }
        }
        return counts
    }

    /// Whether a task belongs in a view on a day, whatever its state: the one membership rule
    /// `tasks(for:on:includingCompleted:)` filters on and `taskCounts` counts on.
    private func belongs(_ task: TaskItem, to view: TaskView, on day: CalendarDate) -> Bool {
        switch view {
        case .inbox:
            return task.scheduled == nil && task.due == nil && task.project == nil
        case .today:
            return task.isScheduled(on: day) || task.isOverdue(on: day) || task.completed == day
        case .upcoming:
            guard let scheduled = task.scheduled else { return false }
            return scheduled > day && daysBetween(day, scheduled) <= 7
        case .byProject:
            return task.project != nil
        case .all:
            return true
        }
    }

    /// The rollover rule `rolledOverTasks` filters on and `taskCounts` counts on.
    private func isRolledOver(_ task: TaskItem, on day: CalendarDate, daysBack: Int) -> Bool {
        guard task.state.isOpen, let scheduled = task.scheduled, scheduled < day else { return false }
        guard daysBetween(scheduled, day) <= daysBack else { return false }
        // Already on the day under its own heading: a deadline that has passed is what
        // `.today` calls overdue, and this list is about the `>` marker, not the `!`.
        return !task.isOverdue(on: day)
    }

    /// The calendar `daysBetween` measures in, built once: it is called from inside the
    /// filter closures of the task views, so once per task per pass.
    private static let dayCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// Whole days from one date to another, both at midnight.
    private func daysBetween(_ from: CalendarDate, _ to: CalendarDate) -> Int {
        let calendar = Self.dayCalendar
        let start = DateComponents(calendar: calendar, year: from.year, month: from.month, day: from.day).date
        let end = DateComponents(calendar: calendar, year: to.year, month: to.month, day: to.day).date
        guard let start, let end else { return .max }
        return calendar.dateComponents([.day], from: start, to: end).day ?? .max
    }
}
