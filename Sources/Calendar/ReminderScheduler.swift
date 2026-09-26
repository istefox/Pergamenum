import Foundation
import Observation
import OSLog
import UserNotifications

/// What a tap on a delivered notification asks the app to do.
enum ReminderTap: Equatable, Sendable {
    case open(PergamenumRoute)
    case notDefaultAction   // dismissed, or a custom action: not a request to open anything
    case noRoute            // no route key, or an empty one - the test notification's shape
    case unreadableRoute    // not a String, not a URL, or not a route this app answers
}

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

    /// Where a tapped notification's route goes. Wired once by `PergamenumApp.init` to
    /// `VaultController.handle(_:)`, the app's one route door; `nil` in tests, where a tap
    /// is classified by `tap(actionIdentifier:userInfo:)` and delivered nowhere.
    @ObservationIgnored var openRoute: (@MainActor (PergamenumRoute) async -> Void)?

    /// The `userInfo` key a scheduled notification carries its route under.
    nonisolated static let routeKey = "route"

    private static let log = Logger(subsystem: AppInfo.bundleIdentifier, category: "reminders")

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

    /// Opens the note a tapped reminder came from (PG-243).
    ///
    /// The non-Sendable `response` is read here, on the nonisolated side, and only the
    /// `Sendable` classification crosses to the main actor. Awaited rather than spawned,
    /// so the system's completion fires after the route has been handled.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let tap = Self.tap(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        await deliver(tap)
    }

    /// Hands an opened route to the app and logs every other outcome (R-03: a log line,
    /// never a problem banner). The raw route string is never logged: it carries note
    /// paths (PG-125). No `NSApp.activate`: a default-action tap already brings the app
    /// forward.
    private func deliver(_ tap: ReminderTap) async {
        switch tap {
        case .open(let route):
            Self.log.notice("tap su notifica: \(route.kind, privacy: .public)")
            guard let openRoute else {
                Self.log.notice("tap su notifica: nessun destinatario per la route")
                return
            }
            await openRoute(route)
        case .notDefaultAction:
            Self.log.notice("tap su notifica: notDefaultAction")
        case .noRoute:
            Self.log.notice("tap su notifica: noRoute")
        case .unreadableRoute:
            Self.log.notice("tap su notifica: unreadableRoute")
        }
    }

    /// What a notification response asks for, as a pure function of the two values the
    /// response carries - testable without `UNUserNotificationCenter` (R-04).
    ///
    /// A route naming a `.canvas` file through `note?file=` becomes the board route: a
    /// notification scheduled before board tasks carried their own route must not open
    /// the board's JSON in a note tab.
    nonisolated static func tap(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> ReminderTap {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return .notDefaultAction }
        guard let value = userInfo[routeKey] else { return .noRoute }
        if let text = value as? String, text.isEmpty { return .noRoute }
        guard let text = value as? String, let url = URL(string: text),
              let route = PergamenumRoute(url) else { return .unreadableRoute }
        if case .note(let path) = route, (path as NSString).pathExtension.lowercased() == "canvas" {
            return .open(.canvas(path: path, nodeID: nil))
        }
        return .open(route)
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
    ///
    /// `session` mints a stable note id for each task's source note (ADR-0059 §D2)
    /// before the route is built, the same id-first-then-path pattern
    /// `VaultController.pergamenumLink(toNoteAt:)` already uses - so a note renamed
    /// in-app between scheduling and firing is still found (PG-237). `nil` (no vault
    /// open) falls back to the path route unchanged; a board task gets the board route,
    /// whatever `mintNoteID` answers for it (PG-243).
    func reschedule(for tasks: [TaskItem], session: VaultSession?, now: Date = Date()) async {
        guard access.isGranted else { return }

        center.removePendingNotificationRequests(withIdentifiers: Array(scheduledIDs))
        scheduledIDs.removeAll()

        var noteIDs: [String: String] = [:]
        if let session {
            for path in Set(tasks.map(\.sourcePath)) {
                if let id = session.mintNoteID(for: path) { noteIDs[path] = id }
            }
        }

        for request in Self.requests(for: tasks, after: now, noteIDs: noteIDs) {
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
    /// notification centre, which needs a permission dialog. `noteIDs` (path → stable
    /// id, ADR-0059) is likewise a plain value the caller minted beforehand, not a
    /// `VaultSession` reached from here, for the same testability reason.
    nonisolated static func requests(
        for tasks: [TaskItem], after now: Date, noteIDs: [String: String] = [:]
    ) -> [UNNotificationRequest] {
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
            // from rather than just the app. The id route (PG-237) survives a rename
            // between scheduling and firing; the path route is the fallback when no
            // id was minted (no vault open). A board task gets the board route, never
            // an id or a note route: a note route would open the board's JSON in a tab.
            let isBoard = (task.sourcePath as NSString).pathExtension.lowercased() == "canvas"
            let route = isBoard
                ? PergamenumLink.canvas(path: task.sourcePath, nodeID: task.nodeID)
                : noteIDs[task.sourcePath].flatMap(PergamenumLink.note(id:))
                    ?? PergamenumLink.note(path: task.sourcePath)
            content.userInfo = [Self.routeKey: route?.absoluteString ?? ""]

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
