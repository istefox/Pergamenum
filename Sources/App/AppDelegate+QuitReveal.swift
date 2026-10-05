import AppKit

/// What a cancelled quit brings back on screen. The coordinator decides that a quit is
/// cancelled and over what; these spell the answer in panes and windows.
extension AppDelegate {
    /// What a cancelled quit shows (ADR-0073 §D7): the main window, reopened if the red
    /// button had closed it, the Note pane, and the first unresolved tab in front of its
    /// column.
    /// Internal, not private: read by `PergamenumApp.swift`'s `quit` (ADR-0045 §D3).
    func revealAfterCancelledQuit(_ id: NoteTab.ID?) {
        revealPaneAfterCancelledQuit(.notes, thenReveal: id)
    }

    /// A quit cancelled by a scheda edit that could not be written brings the Contenitore back
    /// on that scheda (ADR-0073 §D7's twin for the pane).
    /// Internal, not private: read by `PergamenumApp.swift`'s `quit` (ADR-0045 §D3).
    func revealContenitoreAfterCancelledQuit(_ schedaPath: String?) {
        revealPaneAfterCancelledQuit(.contenitore)
        if let schedaPath { contenitore?.selection = schedaPath }
    }

    /// A quit cancelled over a conflicted board shows the Workspace, where its banner already is
    /// (PG-336, ADR-0089 §D6).
    /// Internal, not private: read by `PergamenumApp.swift`'s `quit` (ADR-0045 §D3).
    func revealBoardAfterCancelledQuit() {
        revealPaneAfterCancelledQuit(.workspace)
    }

    /// A quit cancelled over a conflicted diary day shows the Diario and its banner (PG-336,
    /// ADR-0089 §D6).
    /// Internal, not private: read by `PergamenumApp.swift`'s `quit` (ADR-0045 §D3).
    func revealDiaryAfterCancelledQuit() {
        revealPaneAfterCancelledQuit(.diary)
    }

    /// Every cancelled quit's reveal, in the one order that works (ADR-0089 §D6): the main
    /// window, reopened if the red button had closed it, then the pane, then the keyboard back
    /// where `commitEditing` took it from (departure 14), and only then the tab - the other
    /// order lets the restore pull the focus back to the column the reveal had just left
    /// (`QuitFocus.restore(thenReveal:in:)`).
    private func revealPaneAfterCancelledQuit(_ pane: Navigation.Pane, thenReveal id: NoteTab.ID? = nil) {
        vault?.reopenMainWindow?()
        navigation?.pane = pane
        quitFocus.restore(thenReveal: id, in: vault)
    }
}
