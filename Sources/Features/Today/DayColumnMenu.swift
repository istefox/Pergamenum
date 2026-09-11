import SwiftUI

/// The context menu a day cell carries, in one view the week grid and the month grid both
/// place on their own column (ADR-0023 §D1: a command is named once and rendered twice).
///
/// The two grids had a byte-for-byte identical `menu(for:)` each, comment included, which is
/// the shape a reworded title silently drifts out of. The navigation half lives here; the
/// «Nuovo evento» / «Nuovo promemoria» pair stays in `CalendarDayMenuItems`, which the date
/// picker also uses and which is not part of this menu's own vocabulary.
struct DayColumnMenu: View {
    let column: DayColumn
    let controller: DayController

    var body: some View {
        Button("Vai a questo giorno") { controller.show(column.day) }
        Button("Apri nella scala Giorno") {
            controller.show(column.day)
            controller.scale = .day
        }
        Button(column.hasNote ? "Apri la daily note" : "Crea la daily note") {
            controller.show(column.day)
            controller.openDailyNote()
        }
        Divider()
        // The day first, then the flag, in both closures: the composer reads
        // `controller.day`, so setting the flag on the anchor day would open a sheet about
        // a different date than the one right-clicked.
        CalendarDayMenuItems(
            day: column.day,
            onNewEvent: { day in
                controller.show(day)
                controller.isCreatingEvent = true
            },
            onNewReminder: { day in
                controller.show(day)
                controller.isCreatingReminder = true
            }
        )
    }
}
