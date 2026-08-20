import SwiftUI

/// The task a row carries while it is being dragged, and the day that takes it
/// (ADR-0013 §D5).
///
/// A string rather than a `Transferable` type of its own, the shape `BoardDragPayload`
/// took for the same reason: a drag inside one window needs no declared uniform type,
/// and one would have to be registered in the app's Info.plist to be worth anything
/// outside it.
///
/// The file and the line, and nothing else. Carrying the task's text as well would give
/// the drop something to write without going back to the index, which is exactly the
/// stale write the pair exists to prevent: a row drawn before the last scan resolves to
/// no task at all, and is refused by name.
struct TaskDragPayload {
    let path: String
    /// Zero-based, as `TaskItem.lineIndex` is.
    let lineIndex: Int

    private static let separator: Character = "\u{1}"

    var text: String { "\(path)\(Self.separator)\(lineIndex)" }

    init(path: String, lineIndex: Int) {
        self.path = path
        self.lineIndex = lineIndex
    }

    init?(text: String) {
        let parts = text.split(separator: Self.separator, maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let path = parts.first, !path.isEmpty,
              let lineIndex = Int(parts[1]), lineIndex >= 0
        else { return nil }
        self.path = String(path)
        self.lineIndex = lineIndex
    }
}

extension WeekEntry {
    /// What this row would carry, or nil for a row that does not move.
    ///
    /// **Only a scheduled task.** An event belongs to EventKit and a block to the daily
    /// note, so neither is a task line to rewrite. A deadline is the harder no: it is a
    /// task line, but it is on the day because of its `!` marker, and a drag rewrites
    /// `>`. Moving it would leave the row where it was and put a second, silent copy of
    /// it on the day the drag ended, which is not what dragging something means.
    var dragPayload: TaskDragPayload? {
        guard kind == .task, let sourcePath, let lineIndex else { return nil }
        return TaskDragPayload(path: sourcePath, lineIndex: lineIndex)
    }
}

/// A day, an hour or a cell that takes a task, and says so while the task is over it.
///
/// Wrapped rather than applied inline because `dropDestination` has to sit on the whole
/// frame that should accept the drop, and the accent border it draws while targeted is
/// the only thing that tells you where the task will land.
struct TaskDropTarget<Content: View>: View {
    @Environment(\.theme) private var theme

    var cornerRadius: CGFloat?
    let onDrop: (TaskDragPayload) -> Bool
    @ViewBuilder let content: Content

    @State private var isTargeted = false

    var body: some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius ?? theme.radius(.card), style: .continuous)
                    .stroke(isTargeted ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
            )
            .dropDestination(for: String.self) { payloads, _ in
                guard let payload = payloads.first.flatMap(TaskDragPayload.init(text:)) else { return false }
                return onDrop(payload)
            } isTargeted: { isTargeted = $0 }
    }
}
