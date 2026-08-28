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
    /// The classification is `Tool.tapBehaviour`'s (WorkspaceController.swift), not this
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

    func newItemSheet(_ draft: NewItemDraft) -> some View {
        NewCanvasItemSheet(
            kind: draft.kind,
            onCancel: { newItemDraft = nil },
            onConfirm: { value in
                create(draft.kind, value: value, at: draft.point)
                newItemDraft = nil
            }
        )
    }

    private func create(_ kind: NewCanvasItemSheet.Kind, value: String, at point: CGPoint) {
        switch kind {
        case .folder:
            do {
                _ = try workspace.createFolder(named: value, at: point)
            } catch {
                // Reported through the workspace's own problem list rather than a
                // modal: the board is still usable and the name can be retried.
                workspace.recordProblem("\(error)")
            }
        case .link:
            _ = workspace.addLink(value, at: point)
        case .note:
            do {
                let path = try vault.createNote(
                    title: value, in: workspace.folder, date: .today
                )
                _ = workspace.placeFile(path, at: point, creatingOnDisk: path)
            } catch {
                workspace.recordProblem(ConformanceText.creationFailure(error))
            }
        }
    }
}
