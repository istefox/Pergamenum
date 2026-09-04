import SwiftUI

/// The Diario pane's toolbar: which day, and one button that blocks out time.
///
/// It used to carry a third thing, a picker choosing between the editor, the rendering
/// and both. There is one editor now and nothing to choose between (ADR-0029 §D15).
///
/// The same shape as the Oggi pane's: day navigators on the left, the pane's own
/// controls on the right, so the two sections of the app that are about a day are
/// driven the same way.
struct DiaryToolbar: ToolbarContent {
    @Bindable var controller: DiaryController
    let themeEngine: ThemeEngine

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

            themeToggleToolbarItem(themeEngine)
        }
    }
}
