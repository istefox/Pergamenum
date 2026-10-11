import SwiftUI

/// What a tap on the empty board makes, and the sheet the two-step tools ask through.
extension WorkspaceView {
    /// What the user is about to create, once they have typed its name or URL.
    ///
    /// The kind is the sheet's own, rather than a second enum of the same three cases
    /// that has to be mapped onto it at the point of presentation.
    struct NewItemDraft: Identifiable {
        let id = UUID()
        var kind: NewCanvasItemSheet.Kind
        var point: CGPoint
        var value = ""
    }

    /// Acts on a tap on empty board with the selected tool.
    ///
    /// The classification is `Tool.tapBehaviour`'s (`WorkspaceController+Tools.swift`), not this
    /// view's: the eleven tools used to be spelled out here and then restated, in the
    /// trailing reset condition, as "all of them except two".
    func handleTap(at point: CGPoint) {
        switch workspace.tool.tapBehaviour {
        case .selectNothing:
            workspace.selection = []
        case .createSticky(let text):
            let id = workspace.addStickyNote(text, at: point)
            workspace.beginTextEdit(nodeID: id)
        case .createFreeText:
            let id = workspace.addFreeText("", at: point)
            workspace.beginTextEdit(nodeID: id)
        case .sheet(let kind):
            newItemDraft = NewItemDraft(kind: kind, point: point)
        case .importPanel:
            if let urls = VaultOpenPanel.chooseFiles(
                title: "Importa immagini",
                message: "Le immagini vengono copiate nella cartella della board."
            ) {
                importProposals = workspace.importFiles(urls, at: point)
            }
        case .dragDriven, .unavailable:
            break
        }
        // Back to Seleziona after one use (SPEC §6.4), except for the tools that are used
        // by dragging rather than by tapping: resetting those would end the gesture the
        // user is in the middle of.
        if !workspace.tool.isDragDriven { workspace.finishToolUse() }
    }

    /// The sheet closes once a folder or a link is made, stays open on its confirmation once a
    /// document is (note-workflow R-05), and stays open with the sentence and the typed value
    /// when the creation failed (n1-seams R-18, note-workflow R-11). Closed only if it is still
    /// this draft's sheet after the write (ADR-0043 §D7). Every failure is already in the problem
    /// list by then, recorded where it happened, so a sheet closed during the write loses nothing.
    func newItemSheet(_ draft: NewItemDraft) -> some View {
        NewCanvasItemSheet(
            kind: draft.kind,
            onCancel: { newItemDraft = nil },
            onConfirm: { value in
                let confirmation = await create(draft.kind, value: value, at: draft.point)
                if newItemDraft?.id == draft.id, confirmation == .editing { newItemDraft = nil }
                return confirmation
            },
            onOpen: { path in
                if let commandActions {
                    commandActions.showInNotePane(path)
                } else {
                    // A host that forgot to inject `CommandActions` would make «Apri» do nothing in
                    // silence: loud in Debug, and a problem in the list everywhere.
                    assertionFailure("WorkspaceView hosted without CommandActions: «Apri» cannot open \(path)")
                    vault.recordProblem("Impossibile aprire \(path) nel pannello Note")
                }
                newItemDraft = nil
            }
        )
    }

    /// Makes what the sheet asked for. Answers what the sheet shows next: `.editing` when it
    /// can close, the document's confirmation, or the sentence to show in place.
    private func create(
        _ kind: NewCanvasItemSheet.Kind, value: String, at point: CGPoint
    ) async -> NewCanvasItemSheet.Confirmation {
        switch kind {
        case .folder:
            // In place and in the problem list, the note kind's route (note-workflow R-11): the
            // board is still usable and the name can be retried.
            return workspace.createFolderFromSheet(named: value, at: point).map { .failed($0) } ?? .editing
        case .link:
            _ = workspace.addLink(value, at: point)
            return .editing
        case .note:
            // Awaited, so the sheet waits for the write (n1-seams R-18): the note and its card,
            // and no tab, since the person is working on the board (R-10).
            let creation = await workspace.createDocument(titled: value, at: point, through: vault)
            return NewCanvasItemSheet.confirmation(after: creation, title: value)
        }
    }
}
