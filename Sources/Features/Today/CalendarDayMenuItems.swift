import SwiftUI

/// The «Nuovo evento» / «Nuovo promemoria» pair as a day cell draws it, in one view the
/// month grid, the week grid and the date picker all place at the bottom of their own
/// context menu (ADR-0023 §D1, §D10; R-09, R-13).
///
/// One view rather than three copies is the whole point: R-09 asks for the two entries to
/// be identical on all three surfaces, and identical-by-construction is the only version of
/// that which survives an edit. The titles come from `CalendarDayCommand`, which takes them
/// from `ShortcutCommand`, so the Calendario menu and the day cell cannot be reworded apart
/// either.
///
/// **The day is a parameter, and the action opens that day before it opens the composer.**
/// `CommandActions.run(.newEvent)` is the menu bar's version of this command and is
/// deliberately not reused: it switches to the Oggi pane and acts on the day the view is
/// already anchored on, which is right for a menu item that names no day and wrong for a
/// cell that names its own. The caller's closure is expected to `controller.show(day)`
/// first and set `isCreatingEvent`/`isCreatingReminder` after, so the sheet opens on the
/// day that was right-clicked.
///
/// The access check reads `EventKitStore` from the environment rather than taking it as a
/// parameter: it is injected once at the window (`PergamenumApp.swift:142`), and a
/// permission is a fact about the machine rather than about the cell.
struct CalendarDayMenuItems: View {
    @Environment(EventKitStore.self) private var calendar

    let day: CalendarDate
    let onNewEvent: (CalendarDate) -> Void
    let onNewReminder: (CalendarDate) -> Void

    var body: some View {
        ForEach(entries) { entry in
            // Greyed, never dropped, when EventKit has not been granted (ADR-0023 §D10):
            // an entry that disappears teaches nobody the command exists, and Impostazioni
            // is where the grant is explained.
            Button(entry.title) { run(entry.command) }
                .disabled(!entry.isEnabled)
        }
    }

    private var entries: [CalendarDayCommand.Entry] {
        CalendarDayCommand.entries(
            eventAccess: calendar.eventAccess.isGranted,
            reminderAccess: calendar.reminderAccess.isGranted
        )
    }

    private func run(_ command: CalendarDayCommand) {
        switch command {
        case .newEvent: onNewEvent(day)
        case .newReminder: onNewReminder(day)
        }
    }
}
