import SwiftUI

// The move half of the Workspace row: what a drag carries, what a folder row accepts, and
// the «Sposta in ▸» menu that is that same drag's second rendering (ADR-0026 §D4, §D5, §D9).
//
// In a file of its own for the reason `NoteListPane+FolderVerbs.swift` and
// `NoteListPane+Footer.swift` are, and at the seam ADR-0026 itself drew: the drag, the drop
// and the menu are one command asked of one context value, while what stays behind in
// `WorkspaceRow.swift` is the row as a row - its label, its chevron, its selection and the
// two folder verbs it had before this chain. Adding this half took that file past the 400
// lines SwiftLint warns at. Nothing about the behaviour changed in the move.

/// Everything a Workspace row's drag, its drop and its «Sposta in» menu need, in one value
/// (ADR-0026 §D4, §D5, §D9).
///
/// A value rather than six more parameters, because the row passes every parameter it has
/// down its own recursion; and one value rather than a closure per surface, because the
/// drag and the menu are two renderings of one command (ADR-0023 §D1) and must ask the
/// same questions of the same state.
struct WorkspaceMoveContext {
    /// Every folder of the vault, for «Sposta in». `CanvasStore.allFolders()`, which is
    /// what the browser holds, and **never** `VaultController.folders` (ADR-0026 §D9,
    /// ADR-0022 §D11): the latter derives folders from note paths and therefore omits a
    /// folder holding only boards, which is precisely the folder a Workspace user makes.
    let folders: [String]
    /// Every lit row's id (ADR-0026 §D4). Read for one thing only: whether the row a drag
    /// or a menu started from is part of the set, and therefore whether the move carries
    /// the set or that row alone (R-11).
    let multiSelection: Set<String>
    /// What the drag in flight carries, remembered by the source row at drag start.
    /// A folder row's drop affordance is asked of this and of nothing else, because
    /// `.dropDestination`'s `isTargeted` closure never sees the payload (§D5).
    let dragging: [VaultItemRef]
    /// Turns ids into refs against the browser's own tree - a board by its `.canvas`
    /// path, a folder by its folder path (ADR-0025 §D3).
    let resolve: (Set<String>) -> [VaultItemRef]
    /// Remembers what this drag carries, for every folder row's `canDrop` (§D5).
    let onDragStart: ([VaultItemRef]) -> Void
    /// The move itself, performed by the browser and answered `false` when refused -
    /// which is what a `.dropDestination`'s `action` owes the drag.
    let perform: ([VaultItemRef], String) -> Bool
}

extension WorkspaceRow {
    /// This row's own reference: a board by its `.canvas` path, a folder by its folder
    /// path (ADR-0025 §D3).
    var reference: VaultItemRef {
        switch node.kind {
        case .folder: VaultItemRef(path: node.id, kind: .folder)
        case .board(let path): VaultItemRef(path: path, kind: .board)
        }
    }

    /// What a move started on this row carries (ADR-0026 §D4, R-11): the whole lit set
    /// when this row is part of it, this row alone when it is not - the SPEC's own rule,
    /// and AppKit's.
    ///
    /// Read by both surfaces, which is what makes «Sposta in» with two rows selected move
    /// both of them exactly as a drag of either one would (§D9).
    var effectiveItems: [VaultItemRef] {
        move.resolve(move.multiSelection.contains(node.id) ? move.multiSelection : [node.id])
    }

    /// A folder row's drop target, and a board row left exactly as it was.
    ///
    /// The stroke is `TaskDropTarget`'s own shape and the same accent token
    /// (`TaskDrag.swift:69-72`) - a second drop affordance in this app looks like the
    /// first, and no colour is written here that is not a token (`CLAUDE.md`'s binding
    /// design-system rule).
    ///
    /// `isTargeted` lights the row only when the drag could actually land: a folder
    /// dragged onto itself or into its own descendant gives no affordance at all (§D5,
    /// R-06), which is pure string arithmetic against what the source stored and costs
    /// nothing per hover.
    @ViewBuilder
    func accepting(_ row: some View) -> some View {
        switch node.kind {
        case .folder:
            row
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius(.card), style: .continuous)
                        .stroke(isDropTarget ? theme.color(.accentPrimary) : .clear, lineWidth: 1)
                )
                .dropDestination(for: VaultItemDrag.self) { drops, _ in
                    guard let items = drops.first?.items else { return false }
                    return move.perform(items, node.id)
                } isTargeted: { targeted in
                    isDropTarget = targeted && WorkspaceBrowser.canDrop(move.dragging, onFolder: node.id)
                }
        case .board:
            row
        }
    }

    /// What this drag carries, and the record of it the folder rows read while it is in
    /// flight (ADR-0026 §D5): the payload is on the pasteboard, but `isTargeted` never
    /// sees it, so the source side is the only place that can know.
    ///
    /// `dragName` is the row's own name, which is what `ProxyRepresentation(exporting:
    /// \.dragName)` puts on the pasteboard as a plain `String` (§D3) - the representation
    /// that keeps the editor's note-title drop working without touching the file that
    /// implements it.
    func beginDrag() -> VaultItemDrag {
        let items = effectiveItems
        move.onDragStart(items)
        return VaultItemDrag(items: items, dragName: node.name)
    }

    /// «Sposta in ▸», the second rendering of the drag (ADR-0026 §D9) - and the one that
    /// is keyboard-reachable, VoiceOver-reachable and deterministically testable, which is
    /// why it exists at all: no test in this repository has ever driven a `.draggable` →
    /// `.dropDestination` pasteboard drag.
    ///
    /// The destinations are the browser's own `folders`, which is `CanvasStore
    /// .allFolders()` and never `VaultController.folders` - the latter omits a folder
    /// holding only boards (ADR-0022 §D11), which is exactly the folder this pane makes.
    ///
    /// Two things are disabled rather than hidden, so the menu's shape does not change
    /// from row to row: the folder this row already sits in (a move that moves nothing)
    /// and any destination the cycle rule refuses - this row, if it is a folder, and
    /// everything under it (R-06).
    @ViewBuilder
    var moveMenu: some View {
        Menu("Sposta in") {
            Button("(radice)") { requestMove(to: "") }
                .disabled(!canMove(to: ""))
            ForEach(move.folders, id: \.self) { folder in
                Button(folder) { requestMove(to: folder) }
                    .disabled(!canMove(to: folder))
            }
        }
        .accessibilityIdentifier("workspace-move-menu")
    }

    /// The folder this row sits in - `""` at the vault root, the same spelling every path
    /// rule in this feature uses.
    private var parentFolder: String {
        (reference.path as NSString).deletingLastPathComponent
    }

    private func canMove(to destination: String) -> Bool {
        WorkspaceBrowser.canMove(effectiveItems, to: destination, from: parentFolder)
    }

    /// The menu's move, which is the drop's move: the same effective set, through the same
    /// closure, refused for the same reasons and reported in the same dialog.
    ///
    /// The selection is **not** set first, unlike `requestRename()`/`requestDelete()`:
    /// selecting this row would collapse a multi-row set to one (R-11's whole point) and,
    /// for a board row, open it - a move is not a reason to change what is on screen.
    private func requestMove(to destination: String) {
        _ = move.perform(effectiveItems, destination)
    }
}
