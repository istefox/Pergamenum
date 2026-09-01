import SwiftUI

/// The two `List`s (tree and filtered), one row's wiring, and the move a row's drag or drop
/// carries. Split out of `WorkspaceBrowser.swift` to keep its `type_body_length` under the
/// configured warning threshold (PG-055) - a location split only, not a behavioural one.
extension WorkspaceBrowser {
    // MARK: Rows
    //
    // Flat recursive rows inside `List(selection:)`, `NoteListPane`'s shape rather than a
    // `DisclosureGroup` tree (ADR-0024 §D1): a `DisclosureGroup`'s label is not a row of
    // the enclosing `List`, so a `.tag` on it satisfies no binding - the list lights
    // nothing and swallows every click, silently, which is what `RootView.swift:205-208`
    // records this repository having already paid twenty minutes for once.

    /// The `List`'s selection: the whole lit **set** since ADR-0026 §D4, not the one open
    /// row it used to be. The tag is still the row's own id - a board's file path or a
    /// folder's folder path (ADR-0025 §D3) - so the strings travelling through this
    /// binding are row ids and nothing has to be derived from anything.
    ///
    /// A set rather than a `String?` is the whole of Cmd-click and Shift-click: AppKit's
    /// list already does both, so this repository reads no modifier flag and adds no
    /// gesture to a row (ADR-0026 A4). What is *open* is not this set - it is derived from
    /// it by `opening(from:to:currently:in:)`, whose double optional says which of "open
    /// that row", "deselect" and "leave what is open alone" a new set means.
    var treeSelection: Binding<Set<String>> {
        Binding(
            get: { selectedRows },
            set: { ids in
                let previous = selectedRows
                selectedRows = ids
                // A `.tag`ed row only ever hands this setter an id it drew itself, so a
                // miss here means the tree and the click disagree - almost always a
                // rebuild (rename/delete/rescan) racing the click - not an ordinary
                // click. Recorded, not silent: without this the row still resolves as
                // `.folder`, so a desync reads identically to a legitimate folder row and
                // leaves no trace to find it by (ADR-0024 Gate 5.06 finding).
                for id in ids where WorkspaceTree.node(withID: id, in: workspaceTree) == nil {
                    actions.recordDesync("workspace-tree: selected id \(id) resolved to no row")
                }
                // `.none` - the outer case - is "leave what is open alone", so `onSelect`
                // is not called at all: a two-row selection must not close the board on
                // screen (R-10).
                guard let opened = Self.opening(
                    from: previous, to: ids, currently: selection, in: workspaceTree
                ) else { return }
                onSelect(opened)
            }
        )
    }

    var folderTree: some View {
        List(selection: treeSelection) {
            ForEach(workspaceTree, id: \.id) { node in
                row(node, depth: 0)
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("workspace-tree")
        .dropDestination(for: VaultItemDrag.self) { drops, _ in dropOnRoot(drops) }
        // No `.onTapGesture` here any more: deselecting by clicking the blank area below
        // the last row is `List(selection:)`'s own behaviour under ADR-0024 §D7/R-07, and
        // the gesture that used to stand in for it was written when this list had no
        // selection binding at all.
        .contextMenu {
            Button("Espandi tutto") { expanded = expandableFolders }
            Button("Comprimi tutto") { expanded = [] }
        }
    }

    /// Every matching row in one list while a filter is typed: a match three folders down
    /// is easier to see flat than as a tree opened around it - the note sidebar's rule,
    /// and the reason the filter field behaves the same in both places.
    ///
    /// The same row view and the same binding as the tree above, which is R-09 read as
    /// "not a second implementation". `rows(matching:in:)` hands back detached rows, so
    /// every match is drawn at depth 0 - there is no nesting left to flatten, and asking
    /// `WorkspaceTree.flattened` about it (as this did) was a second recursion whose only
    /// possible answer was the list it was handed, at depth 0, in a fresh tuple array.
    ///
    /// The matching itself happens in `refreshFilteredRows()`, not here: a `body` is
    /// evaluated far more often than the filter is typed into.
    var flatList: some View {
        List(selection: treeSelection) {
            ForEach(filteredRows, id: \.id) { node in
                row(node, depth: 0)
            }
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("workspace-flat-list")
        .dropDestination(for: VaultItemDrag.self) { drops, _ in dropOnRoot(drops) }
    }

    /// R-05's destination, on both lists: the tree's own empty area means the vault root,
    /// spelled `""` everywhere this feature computes a path.
    ///
    /// The rows sit *inside* this destination, and SwiftUI hit-tests the innermost one
    /// first - so a drop on a folder row reaches that row's and only a drop on the
    /// background reaches this. That mechanism is the one part of ADR-0026 §D11 asserted
    /// by hand rather than by construction, which is also why «Sposta in ▸ (radice)»
    /// exists as a second, certain surface for the same move.
    func dropOnRoot(_ drops: [VaultItemDrag]) -> Bool {
        guard let items = drops.first?.items else { return false }
        return performMove(items, into: "")
    }

    /// One row, wired the same way in both lists.
    func row(_ node: WorkspaceTree.Node, depth: Int) -> some View {
        WorkspaceRow(
            node: node,
            depth: depth,
            expanded: $expanded,
            selection: selection,
            onSelect: onSelect,
            onRename: { requestRename(of: $0) },
            onDelete: { confirmDelete(of: $0) },
            onRenameBoard: { requestRenameBoard(of: $0) },
            onDeleteBoard: { confirmDeleteBoard(of: $0) },
            move: moveContext
        )
    }

    /// Everything a row's drag, its drop and its «Sposta in» menu need, rebuilt with the
    /// body so the lit set and the drag in flight it carries are the current ones
    /// (ADR-0026 §D4, §D5, §D9).
    ///
    /// One value rather than six more parameters on a row that already passes nine down
    /// its own recursion - and one *place*, so the drag and the menu cannot end up asking
    /// different questions about the same drop.
    var moveContext: WorkspaceMoveContext {
        WorkspaceMoveContext(
            folders: folders,
            multiSelection: selectedRows,
            dragging: dragging,
            resolve: { Self.items(for: $0, in: workspaceTree) },
            onDragStart: { dragging = $0 },
            perform: { performMove($0, into: $1) }
        )
    }

    /// The move both surfaces call - a folder row's `.dropDestination`, the list's own
    /// root-area destination, and «Sposta in» in every row's context menu (ADR-0026 §D9:
    /// a command is named once and rendered twice).
    ///
    /// `false` for a refused drop, which is what `.dropDestination`'s `action` owes the
    /// drag. Two refusals, and they are deliberately not alike (§D5): a cycle is string
    /// arithmetic that already declined to light the row up and says nothing more, while a
    /// collision is named in a dialog because R-07 requires the conflicting name to be
    /// shown and a row that stayed dark shows nothing.
    func performMove(_ items: [VaultItemRef], into destination: String) -> Bool {
        dragging = []
        guard !items.isEmpty, Self.canDrop(items, onFolder: destination) else { return false }
        let refusals = actions.move(items, FolderPath(destination))
        guard refusals.isEmpty else {
            moveConflict = WorkspaceMoveConflict(reasons: refusals)
            return false
        }
        return true
    }
}
