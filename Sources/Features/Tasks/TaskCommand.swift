import Foundation

/// One command a task offers about its relation to a board (ADR-0036), named once so the
/// row's context menu, the Attività toolbar, the Task menu and the "Task collegati" panel's
/// row read the same catalogue instead of four hand-kept lists that had already drifted
/// apart — one of them missing the pane switch that makes navigation actually visible, one
/// of them missing the board destination entirely. Mirrors `CardCommand`
/// (`Sources/Features/Workspace/CardCommand.swift`) and `CalendarDayCommand`
/// (`Sources/Features/Today/CalendarDayCommand.swift`).
///
/// `import Foundation` only, deliberately: a pure catalogue a test can read without pulling
/// in SwiftUI. Not in `sharedSources` — the connectors have no task-menu surface.
///
/// The note side of the old "Collega nota o board…" is gone on purpose (ADR-0036 §D2): a
/// task's note is the file it was captured into (`TaskComposer`'s `DestinationPicker`), so
/// there is nothing left to "link" — only a board is ever a separate, optional relation.
enum TaskCommand: String, CaseIterable, Sendable {
    /// Assigns the task's `^[[<board>.canvas]]` marker via `WorkspacePicker` (ADR-0021 D9).
    case linkBoard
    /// Opens the note the task line lives in.
    case goToNote
    /// Opens the board the task is assigned to.
    case goToBoard

    var title: String {
        switch self {
        case .linkBoard: "Collega una board…"
        case .goToNote: "Vai alla nota di origine"
        case .goToBoard: "Vai alla board collegata"
        }
    }

    var symbol: String {
        switch self {
        case .linkBoard: "rectangle.3.group"
        case .goToNote: "doc.text.magnifyingglass"
        case .goToBoard: "arrow.up.forward.square"
        }
    }

    /// The one stable AX identifier for this command's control, derived from `rawValue` the
    /// same way `CardCommand.identifier` is — a command cannot ship without one and two
    /// commands cannot collide on one.
    var identifier: String {
        "task-command-\(rawValue)"
    }

    /// `task`'s own commands, in menu order. `.goToBoard` only when a board is actually
    /// assigned — offering it unconditionally would be the same "promises what it cannot
    /// do" defect this catalogue replaces. `.linkBoard` and `.goToNote` are always offered:
    /// a task with no board yet can still gain one, and a task always has a source note.
    static func available(for task: TaskItem) -> [TaskCommand] {
        var commands: [TaskCommand] = [.linkBoard, .goToNote]
        if task.workspacePath != nil {
            commands.append(.goToBoard)
        }
        return commands
    }
}
