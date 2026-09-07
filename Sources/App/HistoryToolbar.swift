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

/// The theme picker, appended as the trailing-most item of a pane's own `.primaryAction`
/// group (ADR-0015-adjacent: same reasoning as `HistoryToolbar`, but this one cannot itself
/// live in the single global attachment point `.windowHistory` uses - SwiftUI merges every
/// `.primaryAction` contribution from an outer `.toolbar` call before the pane's own,
/// regardless of which one is textually declared first in source, so a `ToolbarItem` placed
/// there always lands to the pane group's *left*, never its right. Each pane calls this once,
/// last, inside its own `ToolbarItemGroup(placement: .primaryAction)` - a plain view, not a
/// nested `ToolbarContent`, since that group's own placement already covers it.
///
/// A real popup menu, not a cycling button: it lists Sistema/Chiaro/Scuro plus every
/// vault-discovered theme by name, mirroring `ThemeCommands`' Vista > Tema submenu
/// (`MenuCommands.swift`) and Settings' own theme list - a theme reachable from the menu bar
/// and from Settings but not from the toolbar was the gap.
@MainActor
@ViewBuilder
func themeToggleToolbarItem(_ engine: ThemeEngine) -> some View {
    Picker("Tema", selection: Binding(
        get: { engine.selection },
        set: { engine.selection = $0 }
    )) {
        Text("Sistema").tag(ThemeEngine.Selection.followSystem)
        Text("Chiaro").tag(ThemeEngine.Selection.light)
        Text("Scuro").tag(ThemeEngine.Selection.dark)
        ForEach(engine.selectableThemes.filter { !$0.id.hasPrefix("pergamenum-") }) { theme in
            Text(theme.name).tag(ThemeEngine.Selection.named(theme.id))
        }
    }
    .pickerStyle(.menu)
    .help("Tema: cambia l'aspetto della finestra")
    .accessibilityIdentifier("theme-toggle-button")
    // The toolbar strips the Picker's own title from the AXPopUpButton's accessibility
    // label, leaving only its current value ("Sistema") - confirmed empty in a captured
    // accessibility snapshot. Set explicitly so `popUpButtons["Tema"]` can find it.
    .accessibilityLabel("Tema")
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
