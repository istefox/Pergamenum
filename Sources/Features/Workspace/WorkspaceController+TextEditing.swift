import CoreGraphics
import Foundation

/// Inline editing sessions on a card's own text, title and fold state - split out of
/// `WorkspaceController.swift` (`type_body_length` error, > 350 lines) as a size-only move,
/// same convention as `+Crop`/`+Gestures`/`+Nodes`. Distinct from geometry gestures
/// (`+Gestures`) and node-mutation primitives (`+Nodes`): this is about a card's own inline
/// editing state, not where it sits or what it is.
extension WorkspaceController {
    /// Enters inline editing on a `.text` node - a double click, the «Modifica testo»
    /// command, or straight after Testo/To Do creates one (SPEC §6.3).
    func beginTextEdit(nodeID: String) {
        guard case .text(let text) = document.node(id: nodeID)?.kind else { return }
        // No two editors of different kinds open at once, the same rule `beginCrop` follows.
        if croppingNodeID != nil { endCrop(confirm: true) }
        select(nodeID: nodeID, adding: false)
        editingTextNodeID = nodeID
        editingTextDraft = text
    }

    /// Leaves inline editing. `commit` writes `editingTextDraft` through the existing
    /// `setText`; `false` discards it (Esc is the only caller that ever does).
    func endTextEdit(commit: Bool) {
        guard let id = editingTextNodeID else { return }
        if commit {
            setText(editingTextDraft, forNodeID: id)
        }
        editingTextNodeID = nil
    }

    /// Enters inline editing on a `.link` node's title - the «Rinomina» command, the only
    /// trigger (double click is already spoken for: `NSWorkspace.open(URL)`, SPEC §6.4 row 7).
    func beginTitleEdit(nodeID: String) {
        guard case .link = document.node(id: nodeID)?.kind else { return }
        // No two editors of different kinds open at once, the same rule `beginCrop`/
        // `beginTextEdit` already follow for each other - a `.link` node is never a `.text`
        // node, so the two sessions can never legitimately overlap, but a stale
        // `editingTextNodeID` left over from a different card still has to be closed cleanly.
        if croppingNodeID != nil { endCrop(confirm: true) }
        if editingTextNodeID != nil { endTextEdit(commit: true) }
        select(nodeID: nodeID, adding: false)
        editingTitleNodeID = nodeID
        editingTitleDraft = LinkCardTitle.read(from: document.node(id: nodeID)!) ?? ""
    }

    /// Leaves title editing. `commit` writes `editingTitleDraft` through `setTitle`; `false`
    /// discards it (Esc is the only caller that ever does).
    func endTitleEdit(commit: Bool) {
        guard let id = editingTitleNodeID else { return }
        if commit {
            setTitle(editingTitleDraft, forNodeID: id)
        }
        editingTitleNodeID = nil
    }

    /// «Ripiega titoli» (ADR-0028 §D8): folds or unfolds one heading of one `.text` card,
    /// the card-side mirror of `VaultController.toggleFold(_:)`.
    ///
    /// Deliberately **not** through `mutate`: a fold changes no node, writes no file and
    /// records no history step (R-12). It is a way of looking at a card, so it must not make
    /// the board dirty, must not schedule a save, and must not put a step between the person
    /// and the board undo they meant.
    func toggleFold(_ entry: Int, forNodeID id: String) {
        var folded = foldedHeadings[id] ?? []
        if folded.contains(entry) {
            folded.remove(entry)
        } else {
            folded.insert(entry)
        }
        // Removed rather than left as an empty set: "this card folds nothing" and "this card
        // is not in the table" are the same state, and keeping only one of them spelled means
        // a rebuilt card cannot read a stale empty entry as anything else.
        if folded.isEmpty {
            foldedHeadings.removeValue(forKey: id)
        } else {
            foldedHeadings[id] = folded
        }
    }
}
