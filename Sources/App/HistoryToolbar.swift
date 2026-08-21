import SwiftUI

/// Indietro and Avanti, at the leading edge of every pane's toolbar (ADR-0015 §D5).
///
/// Where Finder and Safari put them, and global rather than per pane: the history crosses
/// panes, so a pair that only existed in one of them would be a pair that could not take you
/// out of it. Both are also menu items with a key the user can change - the toolbar is the
/// discoverable copy, not a second implementation, which is the rule every other toolbar in
/// this app already follows.
///
/// Its own type rather than a property on `RootView` for the reason `DayToolbar` is one: that
/// view is close enough to SwiftLint's file limit that a toolbar written inside it would be
/// the thing that pushes it over, and a toolbar is a self-contained piece.
struct HistoryToolbar: ToolbarContent {
    let history: NavigationHistory
    let place: WindowPlace

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { move { history.goBack(reachable: place.isReachable) } } label: {
                Label("Indietro", systemImage: "chevron.backward")
            }
            .help("Torna al punto precedente")
            .disabled(!history.canGoBack)
            .accessibilityIdentifier("history-back")

            Button { move { history.goForward(reachable: place.isReachable) } } label: {
                Label("Avanti", systemImage: "chevron.forward")
            }
            .help("Torna avanti")
            .disabled(!history.canGoForward)
            .accessibilityIdentifier("history-forward")
        }
    }

    /// Takes the step and puts the window where it lands.
    ///
    /// Nothing happens when the walk finds nowhere left to reach: every entry it passed named
    /// a note that is gone, and it dropped them on the way rather than leaving the button
    /// enabled over an empty promise.
    private func move(_ step: () -> Destination?) {
        guard let destination = step() else { return }
        place.apply(destination)
    }
}

extension View {
    /// The two arrows, and the one observer that fills the history behind them (ADR-0015 §D2).
    ///
    /// Written as a modifier rather than inline in `RootView` because that view is at
    /// SwiftLint's type-body limit, and because these three belong together: a toolbar that
    /// walks a history nothing is recording is two features that only look like one.
    func windowHistory(_ history: NavigationHistory, place: WindowPlace) -> some View {
        toolbar { HistoryToolbar(history: history, place: place) }
            .onChange(of: place.destination) { from, moved in
                history.record(moved, as: place.isDrift(from: from, to: moved) ? .drift : .step)
            }
            // The window is somewhere the moment it opens, and that first place is what
            // «indietro» has to be able to return to.
            .task { history.record(place.destination, as: .step) }
    }
}
