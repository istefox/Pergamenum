import EventKit
import Foundation

/// One calendar event, as the timeline needs it.
///
/// A value type rather than an `EKEvent`: the timeline compares, sorts and diffs
/// these, and an `EKEvent` is a live object whose properties change under you when
/// the store reloads.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarTitle: String
    /// Whether the app may edit it. A subscribed or delegated calendar is read-only.
    var isEditable: Bool
    /// Who is invited, by name, in the order EventKit gives them (ADR-0013 §D3).
    ///
    /// Names and not addresses: the event note stamps these into a line a person reads, and
    /// a list of mail addresses is a list nobody reads. Defaulted, so the many places
    /// building an event for a test need not say "nobody" to mean it.
    var attendees: [String] = []
}

extension CalendarEvent {
    /// Who is invited, by name (ADR-0013 §D3).
    ///
    /// `name` is nil for an invitee EventKit knows only by address; the URL carries
    /// `mailto:someone@example.com`, and the local part is a better thing to write into a note
    /// a person reads than the whole address.
    ///
    /// Outside `EventKitStore` rather than inside its fetch, because that class is at the size
    /// SwiftLint stops at and this is about an event rather than about the store.
    static func attendeeNames(of event: EKEvent) -> [String] {
        (event.attendees ?? []).compactMap { participant in
            participant.name
                ?? participant.url.absoluteString
                    .replacingOccurrences(of: "mailto:", with: "")
                    .split(separator: "@").first.map(String.init)
        }
    }
}

extension [CalendarEvent] {
    /// The day's events split by whether they have an hour of their own.
    ///
    /// The timeline draws its grid from 06:00 to 22:00 and places an entry by its start
    /// time. An all-day event starts at midnight, so drawn that way it lands above the
    /// first line and disappears: holidays, deadlines and birthdays were missing from
    /// every day that had them. Kept here rather than inside the view so the split is
    /// something a test can hold.
    var splitByAllDay: (allDay: [CalendarEvent], timed: [CalendarEvent]) {
        (filter(\.isAllDay), filter { !$0.isAllDay })
    }
}
