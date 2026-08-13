import SwiftUI

/// The Oggi pane's toolbar: the Calendario menu's commands, where the hand can reach
/// them.
///
/// Every one of these is also a menu item with a shortcut the user can change - the
/// toolbar is the discoverable copy, not a second implementation. Its own type rather
/// than a property on `TodayView` because that view is already over the size SwiftLint
/// warns at, and a toolbar is a self-contained piece of it.
struct DayToolbar: ToolbarContent {
    let controller: DayController
    let calendar: EventKitStore

    private var day: CalendarDate { controller.day }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { controller.move(by: -1) } label: {
                Label("Giorno precedente", systemImage: "chevron.left")
            }
            .help("Giorno precedente")

            Button { controller.show(.today) } label: {
                Label("Oggi", systemImage: "smallcircle.filled.circle")
            }
            .help("Torna a oggi")
            .disabled(day == .today)

            Button { controller.move(by: 1) } label: {
                Label("Giorno successivo", systemImage: "chevron.right")
            }
            .help("Giorno successivo")

            Button { controller.isChoosingDate = true } label: {
                Label("Vai a data", systemImage: "calendar")
            }
            .help("Vai a una data")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Shown disabled rather than hidden when the grant is missing: a control
            // that vanishes leaves the user looking for a feature they were told
            // exists, and the Impostazioni pane is where the grant is explained.
            Button { controller.isCreatingEvent = true } label: {
                Label("Nuovo evento", systemImage: "calendar.badge.plus")
            }
            .help(calendar.eventAccess.isGranted
                ? "Nuovo evento"
                : "Serve l'accesso al Calendario, da Impostazioni")
            .disabled(!calendar.eventAccess.isGranted)

            Button { controller.isCreatingReminder = true } label: {
                Label("Nuovo promemoria", systemImage: "bell.badge")
            }
            .help(calendar.reminderAccess.isGranted
                ? "Nuovo promemoria"
                : "Serve l'accesso a Promemoria, da Impostazioni")
            .disabled(!calendar.reminderAccess.isGranted)

            Button { Task { await controller.load() } } label: {
                Label("Aggiorna da EventKit", systemImage: "arrow.clockwise")
            }
            .help("Rilegge eventi e promemoria")
        }
    }
}
