import Foundation

/// Undo and redo for one board (SPEC §6.1, "annulla/ripeti" in the top bar).
///
/// Whole-document snapshots rather than per-operation inverses: a board is a small
/// JSON structure, and an inverse operation written by hand for each of the eleven
/// tools is where an undo stack quietly starts producing a board that no longer
/// matches what the user saw.
struct BoardHistory: Sendable {
    /// One reversible point, holding the board as it was *before* a change.
    struct Step: Sendable {
        var document: CanvasDocument
        /// Set when the change that followed also created something on disk, naming
        /// it. Such a step cannot be undone: see `undo(current:)`.
        var createdOnDisk: String?
    }

    /// Deep enough to cover a working session of dragging and typing, shallow enough
    /// that a board of many cards does not sit in memory fifty times over.
    static let limit = 50

    private(set) var undoStack: [Step] = []
    private(set) var redoStack: [Step] = []

    var canUndo: Bool { undoStack.last?.createdOnDisk == nil && !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// The name of the file that blocks the next undo, when one does.
    var blockedBy: String? { undoStack.last?.createdOnDisk }

    /// Records the board as it is, immediately before a change is applied.
    ///
    /// `creatingOnDisk` is the name of the folder or file the change is about to
    /// create in the vault, when it creates one.
    mutating func record(before document: CanvasDocument, creatingOnDisk name: String? = nil) {
        undoStack.append(Step(document: document, createdOnDisk: name))
        if undoStack.count > Self.limit { undoStack.removeFirst() }
        // A new change makes the redo branch unreachable, which is what every editor
        // does: keeping it would let redo jump to a board that never existed.
        redoStack.removeAll()
    }

    enum Outcome: Equatable, Sendable {
        case restored(CanvasDocument)
        case nothingToDo
        /// The step created something on disk, named here.
        case blocked(String)
    }

    /// Steps back one change.
    ///
    /// Refuses when the change created a folder or a note in the vault. Undoing it
    /// would remove the card and leave the file, so the board would stop matching the
    /// folder it is a view of - and deleting the file instead is not something an
    /// undo may decide on its own (SPEC §6.1, "file over app").
    mutating func undo(current: CanvasDocument) -> Outcome {
        guard let step = undoStack.last else { return .nothingToDo }
        if let name = step.createdOnDisk { return .blocked(name) }

        undoStack.removeLast()
        redoStack.append(Step(document: current, createdOnDisk: nil))
        return .restored(step.document)
    }

    mutating func redo(current: CanvasDocument) -> Outcome {
        guard let step = redoStack.popLast() else { return .nothingToDo }
        undoStack.append(Step(document: current, createdOnDisk: nil))
        return .restored(step.document)
    }

    /// Clears both stacks, for when a different board is opened.
    mutating func reset() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
