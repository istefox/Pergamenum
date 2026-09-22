import SwiftUI

extension WorkspaceView {
    /// The board's window-level commands.
    ///
    /// Undo and redo keep the shortcuts they had in the top bar. They are not in the
    /// shortcut catalogue: the standard Modifica menu already shows Annulla and
    /// Ripeti, they do not reach the board, and reconciling the two is a change to
    /// the undo architecture rather than to a toolbar.
    @ToolbarContentBuilder
    func toolbar(previewURLs: [URL]) -> some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { workspace.undo() } label: {
                Label("Annulla", systemImage: "arrow.uturn.backward")
            }
            .help("Annulla")
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!workspace.canUndo)

            Button { workspace.redo() } label: {
                Label("Ripeti", systemImage: "arrow.uturn.forward")
            }
            .help("Ripeti")
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!workspace.canRedo)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button { isShowingQuickLook = true } label: {
                Label("Anteprima", systemImage: "eye")
            }
            .help("Anteprima rapida del file selezionato (barra spaziatrice)")
            .disabled(previewURLs.isEmpty)

            // The same state the Vista menu's «Pannello Workspace» drives, now that it
            // lives on `Navigation`: one toggle, two places to reach it.
            // Label left as it was: `UITests/SectionToolbarsUITests.swift:132` finds this
            // toggle by its words, and renaming it to match the menu entry would break a
            // suite this task does not own. The identifier below is what a new test uses.
            Toggle(isOn: Bindable(navigation).isShowingTray) {
                Label("Nuovi elementi", systemImage: "tray")
            }
            .help("Nuovi elementi, task collegati e assegnati, note referenziate")
            .accessibilityIdentifier("workspace-tray-toggle")

            // Hides the app sidebar, the board list and the tray, leaving only the
            // tool column and the board. Same reach pattern as the tray toggle above:
            // one piece of state on `Navigation`, a toolbar toggle and a Vista entry.
            Toggle(isOn: Bindable(navigation).isWorkspaceFocused) {
                Label("Concentrazione", systemImage: "rectangle.expand.vertical")
            }
            .help("Nasconde la sidebar, l'elenco board e il tray per lasciare più spazio alla board")
            .accessibilityIdentifier("workspace-focus-toggle")

            // Same reach pattern again, one pane narrower: only the board-list tree,
            // never the tray. Independent of «Concentrazione» above - the two flags
            // are read with `&&` at the call site, so either one hides the tree.
            //
            // The binding is negated on purpose (2026-08-28): `isWorkspaceTreeCollapsed`
            // itself is unchanged - `WorkspaceView.swift:133`'s `&&` and MenuCommands.swift's
            // own checkbox still read it directly, "checked = hidden", the ordinary macOS
            // menu convention. This toolbar icon is not a menu row, it is one of four glyphs
            // with no words on them, and the other two here (Anteprima, Concentrazione) are
            // lit exactly when the thing they name is showing. A toggle lit while its own
            // tree is hidden read backwards next to them - lit now means "the tree is on
            // screen", matching the pattern rather than the flag's own polarity.
            Toggle(isOn: Binding(
                get: { !navigation.isWorkspaceTreeCollapsed },
                set: { navigation.isWorkspaceTreeCollapsed = !$0 }
            )) {
                Label("Albero", systemImage: "sidebar.left")
            }
            .help("Mostra o nasconde l'albero delle cartelle e delle board")
            .accessibilityIdentifier("workspace-tree-toggle")

            themeToggleToolbarItem(themeEngine)
        }
    }
}
