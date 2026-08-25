import CoreGraphics
import Foundation

/// Duplica (ADR-0023 §D11, R-10/R-11): a new node per target, offset by one grid step
/// (`WorkspaceController.gridStep`) on both axes, referencing the same file. No file on
/// disk is touched - `mutate` alone, no `creatingOnDisk`, since nothing is created
/// (`WorkspaceController.swift:231-233` would otherwise block the undo on a claimed
/// creation that never happened).
///
/// Plan `docs/superpowers/plans/2026-08-25-universal-command-surface-parity.md`, Task 2
/// (R-10, R-11).
extension WorkspaceController {
    /// Appends a copy of every target node and returns the new ids, in `document.nodes`
    /// order.
    ///
    /// Everything but `id`, `x` and `y` is copied verbatim, `unknown` included - which is
    /// why ADR-0020's `pergamenum-crop` travels with the copy for free and a card whose
    /// file vanished duplicates as the same broken pointer, with no special path (R-11).
    ///
    /// Three things this deliberately does not do (§D11): it does not duplicate edges (an
    /// edge joins two nodes and says nothing about whether the connection was meant to be
    /// doubled), it does not duplicate the cards a group spatially contains (a group is
    /// hollow - containment is geometry, not ownership), and it writes nothing outside the
    /// `.canvas` file (CLAUDE.md principle 1: the card is a pointer, and duplicating a
    /// view of something must not duplicate the something).
    @discardableResult
    func duplicate(nodeIDs: Set<String>) -> [String] {
        guard !nodeIDs.isEmpty else { return [] }

        // Nodes and edges are one id namespace: a strict JSON Canvas reader is entitled to
        // treat them as one, so a new node id must miss both. An id minted earlier in this
        // same call is taken too, which is why `taken` grows as we go.
        var taken = Set(document.nodes.map(\.id)).union(document.edges.map(\.id))

        // Iterating `document.nodes` rather than `nodeIDs` gives the copies a defined
        // order: a `Set`'s iteration order is not one.
        var copies: [CanvasNode] = []
        for node in document.nodes where nodeIDs.contains(node.id) {
            var copy = node
            copy.id = CanvasID.generate(avoiding: taken)
            // One cell down-right. The grid the board draws and the grid it snaps to are
            // the same constant (`WorkspaceController.swift:265-268`), so the copy lands
            // aligned whether or not snapping is on.
            copy.x += Self.gridStep
            copy.y += Self.gridStep
            taken.insert(copy.id)
            copies.append(copy)
        }
        guard !copies.isEmpty else { return [] }

        // One `mutate` for the whole call, so duplicating five cards is one Cmd+Z.
        mutate { $0.nodes.append(contentsOf: copies) }

        // The copies become the selection, so a second Duplica cascades from them instead
        // of making a second copy of the original (ADR-0023 §D8).
        selection = Set(copies.map(\.id))
        refreshContents()
        return copies.map(\.id)
    }
}
