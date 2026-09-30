import SwiftUI

/// Hands the app delegate a way to bring the main window back after a cancelled quit
/// (ADR-0073 §D5 step 7).
///
/// `openWindow` is an environment value, readable only from a view inside a scene, and the
/// delegate that needs it has no view of its own.
struct MainWindowReopener: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    let delegate: AppDelegate

    func body(content: Content) -> some View {
        content.onAppear {
            delegate.showMainWindow = { [openWindow] in openWindow(id: "main") }
        }
    }
}
