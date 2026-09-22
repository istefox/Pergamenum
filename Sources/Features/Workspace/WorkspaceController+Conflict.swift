import Foundation

/// The two verbs that resolve a conflicted board (ADR-0054 §D5), split from
/// `WorkspaceController.swift` itself: that file is at 607 lines before this chain and
/// `PG-202` is the open ticket for the same `type_body_length` limit on a neighbouring
/// Workspace file. Both call `replaceDocument(_:origin:)` and set `saveState` directly,
/// which is why both gained module-wide access in `WorkspaceController.swift` rather than
/// staying `private` there.
extension WorkspaceController {
    /// «Mantieni le mie modifiche»: reads disk, adopts its hash as the expectation without
    /// touching `document` - the person's in-memory version wins deliberately - then
    /// saves.
    func keepLocalBoard() {
        guard let store else { return }
        let theirs: (document: CanvasDocument, hash: String)
        do {
            theirs = try store.read(board: board)
        } catch {
            recordProblem("«\(board)»: \(error)")
            return
        }
        replaceDocument(document, origin: .loaded(board: board, hash: theirs.hash, document: theirs.document))
        saveState = .pending
        flushPendingSave()
    }

    /// «Ricarica dal disco»: replaces `document` and the origin with what is on disk,
    /// dropping the in-memory edit by explicit choice, and drops selected ids that no
    /// longer exist - the shape `apply(_:)`'s undo/redo branch already uses.
    func reloadBoardFromDisk() {
        guard let store else { return }
        let theirs: (document: CanvasDocument, hash: String)
        do {
            theirs = try store.read(board: board)
        } catch {
            recordProblem("«\(board)»: \(error)")
            return
        }
        replaceDocument(theirs.document, origin: .loaded(board: board, hash: theirs.hash, document: theirs.document))
        saveState = .saved
        let liveIDs = Set(document.nodes.map(\.id))
        selection = selection.intersection(liveIDs)
        refreshContents()
    }
}
