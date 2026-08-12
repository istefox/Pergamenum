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
final class ReminderScheduler: NSObject, UNUserNotificationCenterDelegate {
    private(set) var access: CalendarAccess = .notDetermined
    /// Identifiers currently scheduled, so a rescan replaces rather than duplicates.
    private(set) var scheduledIDs: Set<String> = []

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Shows the notification even when Pergamenum is the app in front.
    ///
    /// Without this macOS delivers it and displays nothing, which for this app is the
    /// worst possible case: a `@remind` is most likely to fire precisely while you are
    /// working in the note that set it. It looked like a notification that never
    /// arrived - it had arrived, silently, because the app was frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Whether an authorised notification will actually be seen.
    ///
    /// Authorisation and visibility are two different switches, and the app used to
    /// show only the first: with alerts turned off in Impostazioni di Sistema the
    /// status reads "concesso", the notification is delivered on time, and nothing
    /// appears on screen. That is the one failure a user cannot diagnose, because
    /// every indicator the app offered said it was fine.
    private(set) var isSilent = false

    /// What the system says, in the words of its own settings.
    private(set) var deliverySummary = ""

    func refreshAccessStatus() async {
        let settings = await center.notificationSettings()
        access = switch settings.authorizationStatus {
        case .authorized, .provisional: .granted
        case .denied: .denied
        default: .notDetermined
        }

        let banners = settings.alertSetting == .enabled && settings.alertStyle != UNAlertStyle.none
        let centre = settings.notificationCenterSetting == .enabled
        isSilent = access.isGranted && !banners
        deliverySummary = access.isGranted
            ? "avvisi \(banners ? "attivi" : "disattivati"), centro notifiche \(centre ? "attivo" : "disattivato")"
            : ""
    }

    /// Why the last request failed, when it failed. Kept rather than swallowed, for the
    /// same reason as `EventKitStore.lastAccessError`: a refusal by the system to even
    /// ask is otherwise indistinguishable from a button nobody pressed.
    private(set) var lastAccessError: String?

    func requestAccess() async {
        lastAccessError = nil
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            lastAccessError = error.localizedDescription
        }
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
            do {
                try await center.add(request)
                scheduledIDs.insert(request.identifier)
            } catch {
                lastAccessError = "\(request.identifier): \(error.localizedDescription)"
            }
        }
        await refreshPending()
    }

    /// How many notifications the system actually holds for this app.
    ///
    /// Asked of the notification centre rather than counted from `scheduledIDs`, which
    /// is only what this object believes it scheduled. The two differ exactly when
    /// something went wrong - a request the system refused, or one already delivered -
    /// which is the moment a count is worth showing at all.
    private(set) var pendingCount = 0

    func refreshPending() async {
        pendingCount = await center.pendingNotificationRequests().count
    }

    /// Sends one notification a few seconds from now, to see it arrive.
    ///
    /// Exists because "it is scheduled" and "you saw it" are different claims, and the
    /// gap between them - Focus, alert style, notification centre off - is invisible
    /// from inside the app. A few seconds rather than immediately: a notification
    /// posted while its own app is frontmost is not shown by macOS.
    @discardableResult
    func sendTestNotification(after seconds: TimeInterval = 8) async -> String? {
        guard access.isGranted else { return "accesso alle notifiche non concesso" }

        let content = UNMutableNotificationContent()
        content.title = "Pergamenum"
        content.body = "Notifica di prova: i promemoria @remind arrivano così."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "pergamenum.test.\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        do {
            try await center.add(request)
            await refreshPending()
            return nil
        } catch {
            return error.localizedDescription
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
