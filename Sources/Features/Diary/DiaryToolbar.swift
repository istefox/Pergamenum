import SwiftUI

/// The Diario pane's toolbar: which day, what to write it with, and one button that
/// blocks out time.
///
/// The same shape as the Oggi pane's: day navigators on the left, the pane's own
/// controls on the right, so the two sections of the app that are about a day are
/// driven the same way.
struct DiaryToolbar: ToolbarContent {
    @Bindable var controller: DiaryController

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { controller.move(by: -1) } label: {
                Label("Giorno precedente", systemImage: "chevron.left")
            }
            .help("Giorno precedente")
            .accessibilityIdentifier("diary-previous-day")

            Button { controller.show(.today) } label: {
                Label("Oggi", systemImage: "smallcircle.filled.circle")
            }
            .help("Torna a oggi")
            .disabled(controller.day == .today)

            Button { controller.move(by: 1) } label: {
                Label("Giorno successivo", systemImage: "chevron.right")
            }
            .help("Giorno successivo")
            .accessibilityIdentifier("diary-next-day")

            Button { controller.isChoosingDate = true } label: {
                Label("Vai a data", systemImage: "calendar")
            }
            .help("Vai a una data")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { controller.compose() } label: {
                Label("Nuovo blocco", systemImage: "plus.circle")
            }
            .help("Blocca del tempo sulla giornata")
            .accessibilityIdentifier("diary-new-entry")

            // A picker rather than a toggle: three states, and the one in the middle is
            // the point of this pane - the note and its resa, side by side, live.
            Picker("Vista", selection: $controller.layout) {
                ForEach(DiaryController.Layout.allCases) { layout in
                    Label(layout.title, systemImage: layout.symbol).tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Editor, anteprima, o entrambi")
            .accessibilityIdentifier("diary-layout")
        }
    }
}
