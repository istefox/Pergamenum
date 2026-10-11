import Foundation

/// Opens that show a note the person was not looking at, in the Note pane (note-workflow R-05).
extension CommandActions {
    /// Opens `path` in a new tab of the focused column, switches to the Note pane and asks the
    /// editor for the caret: «Apri» on the Workspace sheet's confirmation.
    func showInNotePane(_ path: String) {
        vault.openNoteInNewTab(at: path)
        navigation.pane = .notes
        vault.requestEditorFocus()
    }
}
