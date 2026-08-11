import Foundation
import Observation
import UserNotifications

/// Local notifications for `@remind(...)` markers (SPEC §7.1).
///
/// Only local notifications: the app makes no network call anywhere, and a reminder
/// that had to reach a server would break that. Recurrences beyond a finite
/// `@repeat(n/N)` are delegated to Apple Reminders (SPEC §14).
@MainActor
@Observable
final class ReminderScheduler {
    private(set) var access: CalendarAccess = .notDetermined
    /// Identifiers currently scheduled, so a rescan replaces rather than duplicates.
    private(set) var scheduledIDs: Set<String> = []

    private let center = UNUserNotificationCenter.current()

    func refreshAccessStatus() async {
        let settings = await center.notificationSettings()
        access = switch settings.authorizationStatus {
        case .authorized, .provisional: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    func requestAccess() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAccessStatus()
    }

    /// Replaces every scheduled notification with the ones the vault currently asks
    /// for.
    ///
    /// Replacing wholesale rather than diffing: the source of truth is the set of
    /// tasks on disk, and a diff that drifted would leave a notification firing for a
    /// task the user deleted.
    func reschedule(for tasks: [TaskItem], now: Date = Date()) async {
        guard access.isGranted else { return }

        center.removePendingNotificationRequests(withIdentifiers: Array(scheduledIDs))
        scheduledIDs.removeAll()

        for request in Self.requests(for: tasks, after: now) {
            try? await center.add(request)
            scheduledIDs.insert(request.identifier)
        }
    }

    /// The notification requests a task set implies.
    ///
    /// Separated from the scheduling so the selection rules are testable without the
    /// notification centre, which needs a permission dialog.
    nonisolated static func requests(for tasks: [TaskItem], after now: Date) -> [UNNotificationRequest] {
        tasks.compactMap { task in
            // A completed or cancelled task must not still ring.
            guard task.state.isOpen, let reminder = task.reminder else { return nil }
            guard let fireDate = EventKitStore.date(
                reminder.date, hour: reminder.hour, minute: reminder.minute
            ), fireDate > now else { return nil }

            let content = UNMutableNotificationContent()
            content.title = task.text.isEmpty ? "Promemoria" : task.text
            content.body = NoteName.title(
                fromFileName: (task.sourcePath as NSString).lastPathComponent
            )
            content.sound = .default
            // Carries the route so tapping the notification opens the note it came
            // from rather than just the app.
            content.userInfo = ["route": PergamenumLink.note(path: task.sourcePath)?.absoluteString ?? ""]

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate
            )
            return UNNotificationRequest(
                identifier: task.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        }
    }
}
