import Foundation

/// A wikilink target - a note title or a `^[[board.canvas]]` marker - resolved and navigated
/// to, in the one place every clickable surface now reaches through `@Environment
/// (CommandActions.self)` (issue #188): the note editor's Cmd+click (`EditorColumnView.
/// follow(title:)`), the Workspace `.text` card's Cmd+click (`StickyTextCard`), and the
/// "Task collegati" panel's link chip, which is where this body lived before
/// (`TasksView+Row.swift`) and now delegates to this one instead of keeping a second copy
/// ADR-0036 exists specifically to avoid.
extension CommandActions {
    func open(link target: String) {
        // A link ending in .canvas points at a board; anything else is a note.
        if target.lowercased().hasSuffix(".canvas") {
            guard let root = vault.root else { return }
            let boards = CanvasStore(root: root).allBoards()
            switch WorkspaceBoardResolver.resolve(target, in: boards) {
            case .unique(let path):
                vault.routeState.pendingCanvas = (path.value, nil)
            case .ambiguous, .notFound:
                vault.recordProblem("board non trovata: \(target)")
            }
            return
        }
        if let path = vault.index.resolve(title: target).first {
            vault.openNote(at: path)
            // A click from outside the Note pane (a Workspace card's wikilink) must switch to
            // it too, or the note opens "underneath" a pane that still shows the Workspace -
            // the board-link branch above gets this for free from `RootView`'s own
            // `pendingCanvas` observer; a note has no such observer to lean on.
            navigation.pane = .notes
        }
    }
}
