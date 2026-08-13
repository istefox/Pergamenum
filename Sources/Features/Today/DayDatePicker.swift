import SwiftUI

/// The "Vai a data" sheet of the Calendario menu.
///
/// Its own type rather than a property on `TodayView`, which is over the size
/// SwiftLint warns at: the sheet needs nothing from that view but the controller, and
/// the day being typed belongs to the sheet rather than outliving it there.
struct DayDatePicker: View {
    @Environment(\.theme) private var theme
    let controller: DayController
    @State private var draftDate = CalendarDate.today

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing(.m)) {
            Text("Vai a data").themedText(.title)
            DatePicker(
                "Giorno",
                selection: Binding(
                    get: { EventKitStore.date(draftDate, hour: 12, minute: 0) ?? Date() },
                    set: { draftDate = CalendarDate($0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)

            HStack {
                Spacer()
                Button("Annulla") { controller.isChoosingDate = false }
                    .keyboardShortcut(.cancelAction)
                Button("Vai") {
                    controller.show(draftDate)
                    controller.isChoosingDate = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(theme.spacing(.l))
        .background(theme.color(.surfaceCard))
        // Starts on the day being shown rather than on today: "vai a data" from the
        // 14th usually means somewhere near the 14th.
        .onAppear { draftDate = controller.day }
    }
}
