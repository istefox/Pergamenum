import Foundation

/// `TaskCommand`'s three actions, in one callable place (ADR-0036 §D3) — the same pattern
/// `CommandActions.run(_:on:)`/`canRun(_:on:)` already use for the note-row context menu
/// (`CommandActions.swift:117-126`, `CommandActions+CanRun.swift:92-95`), so the row's
/// context menu, the Attività toolbar, the Task menu and the "Task collegati" panel's row
/// all read the same behaviour instead of four hand-kept copies.
extension CommandActions {
    /// Performs `command` on `task`. `.goToNote`/`.goToBoard` both bring the destination
    /// pane forward themselves rather than relying on a view to notice — the breadcrumb's
    /// old defect (ADR-0036 §D1) was exactly a navigation that changed state nobody was
    /// watching.
    func run(_ command: TaskCommand, on task: TaskItem) {
        switch command {
        case .linkBoard:
            navigation.taskPickingBoard = task
        case .goToNote:
            vault.openNote(at: task.sourcePath)
            navigation.pane = .notes
        case .goToBoard:
            goToBoard(assignedTo: task)
        }
    }

    /// Whether `command` does anything useful for `task` right now — `.goToBoard` needs a
    /// board that actually resolves; `.linkBoard`/`.goToNote` are always available, the same
    /// as `TaskCommand.available(for:)` already decides for which commands are offered at
    /// all.
    func canRun(_ command: TaskCommand, on task: TaskItem) -> Bool {
        switch command {
        case .linkBoard, .goToNote:
            true
        case .goToBoard:
            task.workspacePath != nil
        }
    }

    /// `.goToBoard`'s three outcomes, matching what the row's own board chip already does
    /// (`TasksView+Row.swift`'s `workspaceSegment(_:)`) — unique resolves straight to the
    /// board, an ambiguous file name opens the picker to disambiguate, and an orphaned
    /// marker is reported rather than silently doing nothing.
    private func goToBoard(assignedTo task: TaskItem) {
        guard let root = vault.root else { return }
        let boards = CanvasStore(root: root).allBoards()
        switch WorkspaceBoardResolver.resolve(task.workspacePath, in: boards) {
        case .unique(let path):
            vault.routeState.pendingCanvas = (path.value, nil)
        case .ambiguous:
            navigation.taskPickingBoard = task
        case .notFound:
            vault.recordProblem("board non trovata: \(task.workspacePath ?? "")")
        }
    }
}
