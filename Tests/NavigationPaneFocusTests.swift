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

// `Navigation.isFocusedPane` (ADR-0053 §D2 seam #5, moved here from `RootView`'s own
// private `isFocusedPane` - `WorkspaceFocusUITests.swift:49`/`:74`'s replacement coverage):
// a flag counts only when the pane it belongs to is the one on screen, never the other one.

@MainActor
@Test func focusedPaneIsTrueOnlyWhenItsOwnFlagAndItsOwnPaneBothMatch() {
    let navigation = Navigation()
    navigation.pane = .workspace
    navigation.isWorkspaceFocused = true
    #expect(navigation.isFocusedPane == true)

    // Leaving the pane without touching the flag - a `Concentrazione` still armed for
    // Workspace must not read as focused while looking at Note.
    navigation.pane = .notes
    #expect(navigation.isFocusedPane == false)

    navigation.pane = .workspace
    navigation.isWorkspaceFocused = false
    #expect(navigation.isFocusedPane == false)
}

@MainActor
@Test func focusedPaneIgnoresAFlagBelongingToNeitherPane() {
    let navigation = Navigation()
    navigation.pane = .tasks
    navigation.isNotesFocused = true
    navigation.isWorkspaceFocused = true

    #expect(navigation.isFocusedPane == false)
}
