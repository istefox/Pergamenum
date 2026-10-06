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

    /// The sheet closes only once its creation is done, and stays open with the sentence and
    /// the typed value when it failed (n1-seams R-18). Closed only if it is still this draft's
    /// sheet after the write (ADR-0043 §D7).
    func newItemSheet(_ draft: NewItemDraft) -> some View {
        NewCanvasItemSheet(
            kind: draft.kind,
            onCancel: { newItemDraft = nil },
            onConfirm: { value in
                let failure = await create(draft.kind, value: value, at: draft.point)
                if newItemDraft?.id == draft.id {
                    if failure == nil { newItemDraft = nil }
                    return failure
                }
                // The sheet is no longer this draft's (closed by other means during the
                // write): its sentence has nowhere to show, so the workspace reports it.
                if let failure { workspace.recordProblem(failure) }
                return failure
            }
        )
    }

    /// Makes what the sheet asked for. Answers the sentence to show in the sheet, or nil when
    /// the sheet can close.
    private func create(_ kind: NewCanvasItemSheet.Kind, value: String, at point: CGPoint) async -> String? {
        switch kind {
        case .folder:
            do {
                _ = try workspace.createFolder(named: value, at: point)
            } catch {
                // Reported through the workspace's own problem list rather than a
                // modal: the board is still usable and the name can be retried.
                workspace.recordProblem("\(error)")
            }
            return nil
        case .link:
            _ = workspace.addLink(value, at: point)
            return nil
        case .note:
            // Awaited, so the sheet waits for the write (n1-seams R-18): the note and its card,
            // and no tab, since the person is working on the board (R-10).
            switch await workspace.createDocument(titled: value, at: point, through: vault) {
            case .created: return nil
            case .failed(let sentence): return sentence
            }
        }
    }
}
