import Foundation
import Testing
@testable import Pergamenum

// `Navigation.isNotesFocused`/`isNoteTreeCollapsed` (2026-08-28, Note/Workspace toolbar
// parity chain): the Note pane's own mirror of `isWorkspaceFocused`/`isWorkspaceTreeCollapsed`.
// Two flags per section rather than one pair shared across both, so switching sections never
// carries one section's chrome state into the other's toolbar.

@MainActor
@Test func focusFlagsStartFalseAndAreIndependentPerSection() {
    let navigation = Navigation()
    #expect(navigation.isNotesFocused == false)
    #expect(navigation.isWorkspaceFocused == false)

    navigation.isNotesFocused = true

    #expect(navigation.isNotesFocused == true)
    #expect(navigation.isWorkspaceFocused == false)
}

@MainActor
@Test func treeCollapseFlagsStartFalseAndAreIndependentPerSection() {
    let navigation = Navigation()
    #expect(navigation.isNoteTreeCollapsed == false)
    #expect(navigation.isWorkspaceTreeCollapsed == false)

    navigation.isNoteTreeCollapsed = true

    #expect(navigation.isNoteTreeCollapsed == true)
    #expect(navigation.isWorkspaceTreeCollapsed == false)
}

@MainActor
@Test func notesFocusIsIndependentFromItsOwnTreeCollapse() {
    let navigation = Navigation()

    navigation.isNotesFocused = true

    #expect(navigation.isNoteTreeCollapsed == false)
}
