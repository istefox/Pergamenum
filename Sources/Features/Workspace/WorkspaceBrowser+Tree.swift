import SwiftUI

/// Rebuilding the tree from a scan, the filter and expand-all state, and the pure lookups
/// (`opening`, `canDrop`, `identifier`, `rows(matching:)`) tests call directly. Split out of
/// `WorkspaceBrowser.swift` to keep its `type_body_length` under the configured warning
/// threshold (PG-055) - a location split only, not a behavioural one.
extension WorkspaceBrowser {
    /// Which case a row means: the row's own id, whichever kind it is - a board names
    /// itself by its file path and a folder by its folder path, so nothing here derives
    /// one from the other (ADR-0025 §D3).
    ///
    /// Not optional: every row is selectable now that ADR-0024 §D3's «foreign» board is
    /// gone (§D2), so there is no row a click can land on that this cannot answer for.
    ///
    /// One expression, read by the `List`'s binding above and by the row's context menu,
    /// so a click and a right-click cannot disagree about what was selected (ADR-0023 §D4).
    ///
    /// `nonisolated` for the reason spelled out at `rows(matching:in:)`: these three
    /// statics are pure functions of their arguments, and a pure function that carries
    /// the view's actor isolation is a trap waiting for the first caller that is not on
    /// the main actor.
    nonisolated static func selection(for node: WorkspaceTree.Node) -> WorkspaceSelection {
        switch node.kind {
        case .folder: return .folder(node.id)
        case .board(let path): return .board(path: path)
        }
    }

    /// The rows behind a set of ids, in the tree's own depth-first order - a `Set` has
    /// none, and a batch whose order changed between two identical drags would make
    /// `VaultMoveBatch`'s answers unrepeatable.
    ///
    /// A board carries its `.canvas` file's own path and a folder its folder path
    /// (ADR-0025 §D3), which is exactly what `VaultItemRef` wants: nothing here derives one
    /// kind of path from the other. An id no row carries is dropped rather than guessed at.
    ///
    /// `nonisolated` for the reason `rows(matching:in:)` spells out below (`:543-550`): the
    /// closure handed to `compactMap` would otherwise carry this `View`'s main-actor
    /// isolation into a non-isolated function type.
    nonisolated static func items(
        for ids: Set<String>, in tree: [WorkspaceTree.Node]
    ) -> [VaultItemRef] {
        WorkspaceTree.flattened(tree).compactMap { row in
            guard ids.contains(row.node.id) else { return nil }
            switch row.node.kind {
            case .folder: return VaultItemRef(path: row.node.id, kind: .folder)
            case .board(let path): return VaultItemRef(path: path, kind: .board)
            }
        }
    }

    // MARK: Tree state

    func rebuild() {
        // The two file rules, rebuilt here with the rest of what the root decides rather
        // than on every access (see their declarations).
        canvasStore = vault.root.map { CanvasStore(root: $0) }
        // One call, not `allBoards()` then `allFolders()`: those two are the same walk
        // (`CanvasStore.walk()`'s own header says so), and asking each in turn enumerated
        // the whole vault twice per scan for a pair the walk already returns together.
        let contents = canvasStore?.foldersAndBoards() ?? (folders: [], boards: [])
        let boards = contents.boards
        folders = contents.folders
        // Folders and boards, two lists and two kinds of row (ADR-0025 §D2). No naming
        // rule is asked any more: a board is a row because it is a file, not because a
        // folder is named after it. With no vault open both lists are empty and the
        // builder draws nothing.
        workspaceTree = WorkspaceTree.build(folders: folders, boards: boards)
        // A selection is a path, and a rename or a delete has just moved or removed the
        // row it names - this runs on `scanGeneration`, which both of them bump. The
        // selection is owned by the controller (ADR-0024 §D6), so dropping a stale one
        // means asking for `nil` through `onSelect` rather than assigning local state -
        // there no longer is any to assign.
        //
        // Asked of the tree the rows are actually drawn from, through the lookup that
        // answers for **every** row rather than through `folders(in:)`, which yields
        // folder ids only (ADR-0025 §D2): a board selection checked against that list
        // would be missing from it on every single rescan and dropped every time.
        if let selection, WorkspaceTree.node(withID: selection.path, in: workspaceTree) == nil {
            onSelect(nil)
        }
        // The same drop for the lit set, which the controller does not own (ADR-0026 §D4):
        // a rename, a delete or a move has just taken rows away, and an id kept here after
        // its row has gone is an id a drag would still carry.
        selectedRows = selectedRows.filter {
            WorkspaceTree.node(withID: $0, in: workspaceTree) != nil
        }
        // With nothing lit, the open row is (ADR-0024's invariant, in the form §D4 keeps):
        // this is the first scan of a pane drawn with a board already open - navigating
        // back to the Workspace, or a vault reopened on one - where no `.onChange(of:
        // selection)` has fired because the value did not change.
        if selectedRows.isEmpty, let selection,
           WorkspaceTree.node(withID: selection.path, in: workspaceTree) != nil {
            selectedRows = [selection.path]
        }
        reveal(selection?.path)
        // Last, because it reads `workspaceTree`: a rescan that added, renamed or removed
        // a board changes what the filter matches, and the filtered list is not redrawn
        // from the tree - it is redrawn from `filteredRows`.
        refreshFilteredRows()
    }

    /// Recomputes what `flatList` draws, from the filter and the tree it matches against.
    /// One place, called from the two events that can change either - never from a `body`,
    /// which is the point of the cache.
    ///
    /// An empty filter short-circuits to nothing rather than walking the tree: `flatList`
    /// is not on screen then (the body draws `folderTree` instead), and
    /// `rows(matching: "", in:)` answers `[]` regardless, because
    /// `localizedCaseInsensitiveContains("")` is `false` - so this is the same value for
    /// less work, not a different one.
    func refreshFilteredRows() {
        filteredRows = filter.isEmpty ? [] : Self.rows(matching: filter, in: workspaceTree)
    }

    /// Opens the folders above the selected row, so a board opened from somewhere that is
    /// not this list - the breadcrumb, a route, a folder card, the editor - is visible
    /// here rather than merely selected inside a closed folder.
    ///
    /// The path is the selection's own (ADR-0025 §D3), and `NoteTree.ancestors(of:)` is
    /// already right for **both** kinds: it drops the last component, which for a board
    /// path is the `.canvas` file and for a folder path is the folder itself, leaving in
    /// each case the strict ancestors - the set to open, without opening the selected row
    /// itself (which for a board would mean nothing anyway: a board row has no children).
    func reveal(_ path: String?) {
        guard let path else { return }
        expanded.formUnion(NoteTree.ancestors(of: path))
    }

    /// What "Espandi tutto" opens, from both surfaces that offer it (the toolbar button
    /// and the tree's context menu, ADR-0022 §D8): every **folder** row's id of the tree
    /// the rows are drawn from, and no board path at all - a board row has nothing under
    /// it to open (ADR-0025 §D2).
    ///
    /// Asked of `WorkspaceTree.folders(in:)` rather than of a walk of this view's own -
    /// the tree already answers "which ids are folder rows", and an expand-all built on a
    /// second walk is a second answer to the same question. There is no root row in the
    /// set because there is no root row: the top level is the vault root's contents.
    var expandableFolders: Set<String> {
        Set(WorkspaceTree.folders(in: workspaceTree))
    }

    /// The filtered list's input (R-09): every row of `tree` - folder **and** board
    /// alike, they are both openable rows now (ADR-0025 §D2) - whose `id` or `name`
    /// contains `filter`, case-insensitively. The kind guard ADR-0024 had here is gone
    /// rather than widened: with `Kind` reduced to `.folder` and `.board` it would admit
    /// every node it was asked about, and a guard that cannot refuse is a guard that only
    /// looks like one.
    ///
    /// Matching on `id` alone is a path-only filter, and `name` is what makes a board
    /// findable by what it is called rather than by where it sits - «altro» finds
    /// `01 Progetti/b/altro.canvas` (R-03).
    ///
    /// The rows come back **detached** - each one's `children` emptied - because they are
    /// drawn flat: a folder and a descendant of it can both match, and a match kept with
    /// its subtree would draw that descendant twice, once on its own and once under its
    /// parent.
    ///
    /// `nonisolated`, and that word is load-bearing rather than tidy: a `View` is
    /// `@MainActor`, so a static member of one is too, and the closure below would be
    /// handed to `compactMap` as an isolated closure converted to a non-isolated function
    /// type - which the concurrency runtime checks at the call rather than at compile
    /// time. Called from a test (a nonisolated synchronous context) that check is a
    /// `dispatch_assert_queue` **trap**, not a warning: the whole test process dies mid
    /// run and the suite reports a crashed test with no assertion to read.
    /// `identifier(for:)` beside it never crashed because it passes no closure anywhere.
    nonisolated static func rows(matching filter: String, in tree: [WorkspaceTree.Node]) -> [WorkspaceTree.Node] {
        WorkspaceTree.flattened(tree).compactMap { row in
            guard row.node.id.localizedCaseInsensitiveContains(filter)
                || row.node.name.localizedCaseInsensitiveContains(filter)
            else { return nil }
            return WorkspaceTree.Node(
                id: row.node.id,
                name: row.node.name,
                kind: row.node.kind,
                children: [],
                boardCount: row.node.boardCount
            )
        }
    }

    /// The **two** identifier spellings a row can carry, and the only place they are
    /// spelled (ADR-0024 §D10, re-cased by ADR-0025): `workspace-board-<boardPath>` for a
    /// board row, `workspace-folder-<folderPath>` for a folder row. ADR-0024's third
    /// spelling, the one for a «foreign» board, is gone with the concept and its prefix
    /// is not written anywhere in this file any more: a `.canvas` this app used to call
    /// foreign is an ordinary board row now (§D2) and carries the ordinary board
    /// identifier.
    ///
    /// Both forms are spelled from the row's own path, which is what keeps the board form
    /// byte-identical to what a board row carried before this chain - the UI tests'
    /// `workspace-board-<boardPath>` still resolves.
    ///
    nonisolated static func identifier(for node: WorkspaceTree.Node) -> String {
        switch node.kind {
        case .board(let path): return "workspace-board-\(path)"
        case .folder: return "workspace-folder-\(node.id)"
        }
    }

    /// ADR-0026 §D4's collapse rule, read by the `Binding<Set<String>>` `treeSelection`
    /// becomes in the code step: what AppKit's own Cmd/Shift-click resolves `new` to,
    /// answered against `currently` (what is open today) rather than against `old`. The
    /// double optional is the vocabulary the ADR names: `.none` (the outer case) means
    /// "leave `currently` alone" - the answer for a set of two-or-more ids (R-10) and for
    /// a set of exactly one id that is already the open one (the Note pane's
    /// `leaveComposer()` case, preserved verbatim in shape though this tree has no
    /// composer); `.some(nil)` means deselect - the answer for an empty set; `.some(.some(
    /// x))` means open `x` - the answer for exactly one id different from what is open,
    /// resolved against `tree` the way `treeSelection`'s setter resolves a click today.
    ///
    /// `old` is part of the signature and is deliberately not read: what a new set means
    /// is a question about what is **open**, not about what was lit a moment ago, and the
    /// two differ precisely in the case this rule exists for - a Shift-click extending the
    /// set past one row leaves the open board open whether or not it is in either set
    /// (R-10). It stays in the signature because the caller has it and a later rule that
    /// needs the transition (a range's anchor, say) would have nowhere to read it from.
    ///
    /// `nonisolated` for the reason `rows(matching:in:)` above is (`:543-550`): a pure
    /// function of its arguments, callable from a test's nonisolated, synchronous context
    /// with no `@MainActor` hop to trap.
    nonisolated static func opening(
        from old: Set<String>, to new: Set<String>, currently: WorkspaceSelection?,
        in tree: [WorkspaceTree.Node]
    ) -> WorkspaceSelection?? {
        // Two or more: nothing opens and nothing closes. The set answers "what does a drag
        // carry" and only that (§D4 row 3, R-10).
        guard new.count <= 1 else { return .none }
        // Empty: deselect, which is what clicking the blank area below the rows already
        // means (§D4 row 4, ADR-0024 §D7).
        guard let id = new.first else { return .some(nil) }
        // The same single row again: nothing. Re-opening the board already on screen would
        // reset the zoom and pan of the very thing being looked at (§D4 row 2, and
        // `WorkspaceController.select`'s own guard for the same reason).
        guard id != currently?.path else { return .none }
        // Exactly one id, different from what is open: that row opens (§D4 row 1). An id no
        // row carries answers `.folder(id)`, the behaviour this rule inherited from the
        // binding it was extracted out of - the desync itself is recorded by the setter,
        // which is the side that has somewhere to record it.
        guard let node = WorkspaceTree.node(withID: id, in: tree) else {
            return .some(.some(.folder(id)))
        }
        return .some(.some(selection(for: node)))
    }

    /// ADR-0026 §D5's cycle rule for a folder row's own drop highlight: pure string
    /// arithmetic against the drag set the source stored at drag start, asked on every
    /// hover with no filesystem read - `VaultMoveBatch.plan`'s step 3 asks the same
    /// question, once, after the drop has already happened; this is the same rule asked
    /// before it, for the affordance rather than the write.
    ///
    /// Only a folder can contain the destination, so a board in the drag set is never
    /// asked about: a board dropped onto the folder that already holds it is a no-op the
    /// batch drops (`VaultMoveBatch.plan` rule 2), not a cycle this has to catch.
    ///
    /// The prefix is `"\(folder)/"` and **never** the bare path - the rule
    /// `FolderFileOperations.repointing` and `VaultMoveBatch.plan` both already follow: a
    /// sibling called `01 Progetti-altro` starts with the same characters as `01 Progetti`
    /// and is not inside it.
    nonisolated static func canDrop(_ dragging: [VaultItemRef], onFolder folder: String) -> Bool {
        !dragging.contains { item in
            item.kind == .folder && (folder == item.path || folder.hasPrefix("\(item.path)/"))
        }
    }

    /// The disabled state of a «Sposta in ▸» entry (ADR-0053 §D2 #7): a destination is
    /// offered only when it is not the folder the item already sits in - a move that
    /// would move nothing - and `canDrop` above does not refuse it for the cycle rule.
    ///
    /// One function replacing two copies, `WorkspaceRow+Move.swift`'s own
    /// `canMove(to:)` (over the row's `effectiveItems`, its multi-selection) and
    /// `NoteTreeRow.swift`'s (over `[reference]`, a folder row's own single item) -
    /// `destination != parentFolder && canDrop(items, onFolder: destination)` written
    /// out twice, word for word, over a different `items` and a different derivation of
    /// `parentFolder`. Each call site keeps computing its own `items` and
    /// `parentFolder` and hands both in; nothing about either site's answer changes.
    nonisolated static func canMove(
        _ items: [VaultItemRef], to destination: String, from parentFolder: String
    ) -> Bool {
        destination != parentFolder && canDrop(items, onFolder: destination)
    }
}
