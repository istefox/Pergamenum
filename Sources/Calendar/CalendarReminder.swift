import Foundation

/// One reminder from the Reminders app.
struct CalendarReminder: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var due: CalendarDate?
    var isCompleted: Bool
    var listTitle: String
}
