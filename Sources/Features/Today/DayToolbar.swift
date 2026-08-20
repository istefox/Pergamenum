import SwiftUI

/// The Oggi pane's toolbar: the Calendario menu's commands, where the hand can reach
/// them.
///
/// The navigators and the two creation buttons are also menu items with a shortcut the
/// user can change - the toolbar is the discoverable copy, not a second implementation.
/// The two toggles are the day view's own filters and belong to the view, not to the
/// menu bar. "Nuovo promemoria" left this toolbar for the bell to become a filter; it
/// is still in the Calendario menu, keys and all. Its own type rather
/// than a property on `TodayView` because that view is already over the size SwiftLint
/// warns at, and a toolbar is a self-contained piece of it.
struct DayToolbar: ToolbarContent {
    @Bindable var controller: DayController
    let calendar: EventKitStore
    let vault: VaultController

    private var day: CalendarDate { controller.day }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            // One unit of whatever scale is showing: a day, a week, a month. The
            // tooltip says which, because a chevron that means three different things
            // has to say the one it means now.
            Button { controller.moveSpan(by: -1) } label: {
                Label(controller.scale.previousTitle, systemImage: "chevron.left")
            }
            .help(controller.scale.previousTitle)

            Button { controller.show(.today) } label: {
                Label("Oggi", systemImage: "smallcircle.filled.circle")
            }
            .help("Torna a oggi")
            .disabled(day == .today)

            Button { controller.moveSpan(by: 1) } label: {
                Label(controller.scale.nextTitle, systemImage: "chevron.right")
            }
            .help(controller.scale.nextTitle)

            Button { controller.isChoosingDate = true } label: {
                Label("Vai a data", systemImage: "calendar")
            }
            .help("Vai a una data")
        }

        ToolbarItem(placement: .principal) {
            // Three scales of one thing, not three views: whichever is chosen, the day
            // underneath does not move (ADR-0013 §D4).
            Picker("Scala", selection: $controller.scale) {
                ForEach(DayScale.allCases) { scale in
                    Label(scale.title, systemImage: scale.symbol).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Giorno, settimana o mese")
            .accessibilityIdentifier("day-scale")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            // Quick capture, from the day one is looking at. The composer is presented
            // at window level, so this is the same panel Cmd+Shift+N opens.
            Button { vault.beginTaskCapture() } label: {
                Label("Nuovo task", systemImage: "plus.circle")
            }
            .help("Nuovo task")
            .disabled(vault.root == nil)
            .accessibilityIdentifier("day-new-task")

            // The bell used to create a reminder, which the Calendario menu already
            // does. As a filter it answers the question the day view could not: what
            // falls due next.
            Toggle(isOn: $controller.showsDueTasks) {
                Label("Scadenze in arrivo", systemImage: "bell.badge")
            }
            .help("Mostra i prossimi task con scadenza")
            .accessibilityIdentifier("day-due-filter")

            Toggle(isOn: $controller.showsCompleted) {
                Label("Mostra completati", systemImage: "checkmark.circle")
            }
            .help("Mostra anche i task completati")
            .accessibilityIdentifier("day-completed-filter")

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

            Button { Task { await controller.load() } } label: {
                Label("Aggiorna da EventKit", systemImage: "arrow.clockwise")
            }
            .help("Rilegge eventi e promemoria")
        }
    }
}
