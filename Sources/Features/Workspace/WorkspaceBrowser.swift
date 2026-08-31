import SwiftUI

/// The vault's boards arranged the way they sit on disk, for the Workspace pane.
///
/// ADR-0021 D10: `.canvas` files are not in the index and are not going into it, so the
/// list comes from `CanvasStore.allBoards()` and the shape comes from
/// `NoteTree.build(fromPaths:)` - the same tree the note sidebar is built from, reached
/// through its second entry point rather than reimplemented here. That is the UX
/// blueprint's *"reuse the existing folder-tree view component ... not a parallel tree
/// implementation"* made true at the level of the code.
///
/// `NoteTree.Node.Kind` is not extended for boards (D10), and the sidebar does not read a
/// `NoteTree` at all: `WorkspaceTree.build(folders:boards:)` walks the two flat lists
/// `CanvasStore` gives it into one row per folder **and** one row per `.canvas`, two
/// different things and never one folded into the other (ADR-0025 §D2). This view renders
/// those rows; it does not decide them.
struct WorkspaceBrowser: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// The row currently selected in the tree, whichever kind it is - a `.canvas` by its
    /// own file path or a folder by its folder path (ADR-0025 §D3). Owned by
    /// `WorkspaceController.current`, handed down whole: the case is what the two verbs
    /// dispatch on (§D8), so a view handed only the folder would have to recover it.
    var selection: WorkspaceSelection?
    /// The three verbs, performed by `WorkspaceView` because all three need the
    /// `WorkspaceController` this view has no business holding (ADR-0022 §D10).
    var actions: WorkspaceFolderActions
    /// Fired with the new selection - `nil` for "nothing selected" (what `onDeselect`
    /// used to mean), `.folder`/`.board` for a row the tree's own binding resolved
    /// (ADR-0024 §D6). Replaces `onOpen`/`onDeselect`: which case a click means is
    /// decided against this view's own tree, because only this view holds it.
    var onSelect: (WorkspaceSelection?) -> Void

    @State private var filter = ""
    /// The folders currently open, by path. View state rather than a preference, for
    /// the same reason the note tree's is.
    @State private var expanded: Set<String> = []
    /// The boards folded one row per folder - what the rows below are drawn from, what the
    /// selection binding resolves a clicked id against (ADR-0024 §D2), what the
    /// stale-selection drop is asked (§D7), and what "Espandi tutto" expands.
    ///
    /// The only tree this view holds. The `NoteTree` that used to sit beside it existed
    /// solely so a `NoteTree`-shaped `allFolders(in:)` could walk it for the expand-all
    /// set, and `WorkspaceTree.folders(in:)` answers that from the rows actually drawn -
    /// one tree, so the set of expandable ids cannot be a different set from the ids the
    /// rows carry.
    @State private var workspaceTree: [WorkspaceTree.Node] = []
    /// What `flatList` draws: the matches for the filter as it stands, computed once per
    /// change of an input rather than once per `body` evaluation. `rows(matching:in:)`
    /// walks the whole tree and runs two locale-aware comparisons on every node of it,
    /// and a body is re-evaluated by a scroll and by a selection, neither of which can
    /// change the answer. Kept current by `refreshFilteredRows()`, called where each of
    /// the two inputs changes: `filter` (`.onChange` on the body) and `workspaceTree`
    /// (the end of `rebuild()`).
    ///
    /// The rows arrive **detached** (`children: []`), which is what lets the list draw
    /// every one of them at depth 0.
    @State private var filteredRows: [WorkspaceTree.Node] = []
    /// Every folder of the vault, as the last scan found them - what the create sheet's
    /// parent picker offers (ADR-0025 §D1). The board list beside it is a local of
    /// `rebuild()`: the tree is the only thing that reads it, and the picker no longer
    /// infers folders from board paths.
    @State private var folders: [String] = []
    /// The board rules over the open vault's root, kept for the same reason
    /// `folderOperations` below is: `CanvasStore.init` resolves symlinks and standardizes
    /// the URL, and `boardNameIsAvailable` is asked live, on every keystroke of the create
    /// sheet.
    @State private var canvasStore: CanvasStore?
    /// The folder rules over the open vault's root, built once per scan rather than once
    /// per call. `NoteStore.init` resolves symlinks and standardizes the URL - filesystem
    /// syscalls, not string work - and `nameIsAvailable` is asked live, on every keystroke
    /// of both sheets, so deriving this in a getter spent a symlink resolution and an
    /// allocation per typed character on top of the `fileExists` the check is actually
    /// for. Nil with no vault open, which is also when the toolbar has nothing to act on.
    ///
    /// Assigned in `rebuild()`, whose trigger is `vault.scanGeneration`, and the root is
    /// this value's only input: a vault switch bumps that counter (`VaultController.open`
    /// awaits `rescan()`), and a close takes this whole view down rather than leaving it
    /// on screen (`RootView.workspacePane` draws it only with a root), so the stored
    /// value cannot outlive the root it was built from.
    @State private var folderOperations: FolderFileOperations?
    /// Which creation is waiting for the sheet, `nil` for none - the presentation *is*
    /// the kind, so the two toolbar buttons cannot both be answered by one boolean that
    /// has forgotten which of them was pressed (ADR-0025 §D7).
    @State private var creating: WorkspaceItemKind?
    /// The rename waiting for its sheet, carrying the row it is about - `pendingDelete`'s
    /// shape below, for the same reason. Whoever asks names the row: the row's context
    /// menu knows which one was right-clicked, while the selection it also sets travels up
    /// to the controller and back down as a prop, so seeding the sheet from `targetFolder`
    /// made it depend on that round trip having landed first.
    @State private var renameTarget: PendingWorkspaceRename?
    /// The delete waiting to be confirmed, with a folder's counts already read (R-10).
    @State private var pendingDelete: PendingWorkspaceDelete?
    /// Every lit row, which is `List(selection:)`'s own set and the whole of ADR-0026
    /// §D4: Cmd-click and Shift-click come from AppKit for free, so nothing here reads
    /// `NSEvent.modifierFlags` and no recognizer is added to a row body - the one thing
    /// that ever starved this list's own tap (ADR-0025 §D9, ADR-0026 A4).
    ///
    /// It answers **one** question, "what does a drag carry" (R-11). What is *open* stays
    /// the single `WorkspaceSelection?` handed down as a prop, derived from this set by
    /// `opening(from:to:currently:in:)` - a row can be lit without being open, and two lit
    /// rows open nothing (R-10).
    ///
    /// Kept in step with the prop by the `.onChange(of: selection)` below (something
    /// opened from the breadcrumb, a route or a card lights exactly its own row) and
    /// pruned of ids no row carries by `rebuild()`.
    @State private var selectedRows: Set<String> = []
    /// What the drag that is in flight carries, stored by the source row at drag start.
    ///
    /// `.dropDestination` has no payload-aware validation - its `isTargeted` closure is
    /// handed a `Bool` and never the payload (ADR-0026 §D5) - so the only way a folder row
    /// can decline to light up for a cycle is for the source side to have remembered what
    /// it started dragging. Empty between drags.
    @State private var dragging: [VaultItemRef] = []
    /// The refused batch waiting to be named (R-07). A collision is accepted visually and
    /// then reported, because a row that stays dark shows no conflicting name (§D5).
    @State private var moveConflict: WorkspaceMoveConflict?

    var body: some View {
        VStack(spacing: 0) {
            header
            // A second row *beside* the header, never inside it: the header groups its
            // children with `.accessibilityElement(children: .contain)` under its own
            // identifier, and a button placed in there risks answering to
            // `workspace-browser-header` rather than to its own (ADR-0022 §D8, §F9).
            toolbar
            Divider()
            if filter.isEmpty {
                folderTree
            } else {
                flatList
            }
        }
        .background(theme.color(.backgroundSecondary))
        // The same trigger the note tree rebuilds on: a scan is what changes the set of
        // files on disk, and a board list is tens of entries beside it.
        .task(id: vault.scanGeneration) { rebuild() }
        // The lit set follows what is open, never the other way round (ADR-0026 §D4): a
        // board opened from the breadcrumb, a route, a card or the editor lights exactly
        // its own row and drops whatever multi-row set was standing, because the one thing
        // that is open is also one row.
        .onChange(of: selection) { _, new in
            selectedRows = new.map { Set([$0.path]) } ?? []
            reveal(new?.path)
        }
        // The filter's other input is the tree, refreshed at the end of `rebuild()`.
        .onChange(of: filter) { _, _ in refreshFilteredRows() }
        // One sheet for both creations, told which one it is (ADR-0025 §D7): the parent
        // picker, the name rules and the three identifiers are the same question either
        // way, and `kind` is what picks the collision it asks about and the verb it calls.
        .sheet(item: $creating) { kind in
            NewWorkspaceSheet(
                kind: kind,
                parents: WorkspaceFolderSheets.parentOptions(from: folders),
                initialParent: targetFolder,
                isNameAvailable: { name, parent in
                    nameIsAvailable(name, in: parent, for: kind)
                },
                onConfirm: { name, parent in
                    creating = nil
                    switch kind {
                    case .board: actions.createBoard(name, parent)
                    case .folder: actions.createFolder(name, parent)
                    }
                },
                onCancel: { creating = nil }
            )
        }
        // One sheet for both renames, told which one it is - the create sheet's decision
        // (ADR-0025 §D7) applied to the other verb that asks for a name. The collision it
        // asks about is the kind's own, through the same predicate the create sheet reads.
        .sheet(item: $renameTarget) { pending in
            RenameWorkspaceSheet(
                kind: pending.kind,
                path: pending.seed,
                isNameAvailable: { name, parent in
                    nameIsAvailable(name, in: parent, for: pending.kind)
                },
                onConfirm: { newName in
                    renameTarget = nil
                    switch pending.kind {
                    case .board: actions.renameBoard(pending.path, newName)
                    case .folder: actions.rename(pending.path, newName)
                    }
                },
                onCancel: { renameTarget = nil }
            )
        }
        // No delete verb here is journalled (ADR-0022 §D6, ADR-0025 §D6), so this dialog
        // is the whole of the "are you sure" this feature has: the recovery afterwards is
        // the Finder's Trash, not an undo. It says what is inside before it goes there
        // (R-10), and a board - one file, nothing inside - says that instead.
        .confirmationDialog(
            "Eliminare «\(pendingDelete?.name ?? "")»?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { pending in
            Button("Sposta nel Cestino", role: .destructive) {
                pendingDelete = nil
                switch pending {
                case .board(let path): actions.deleteBoard(path)
                case .folder(let path, _): actions.delete(path)
                }
            }
            .accessibilityIdentifier("workspace-delete-confirm")
            Button("Annulla", role: .cancel) { pendingDelete = nil }
        } message: { pending in
            Text(pending.message)
        }
        // R-07: nothing moved, nothing was renamed and nothing was overwritten - and the
        // name that stopped it is on screen. A dialog rather than a problem line because
        // the drop is a gesture with an expectation: a batch that refuses silently reads
        // as a drag that missed (ADR-0026 §D5).
        .alert(
            "Spostamento rifiutato",
            isPresented: Binding(
                get: { moveConflict != nil },
                set: { if !$0 { moveConflict = nil } }
            ),
            presenting: moveConflict
        ) { _ in
            Button("OK", role: .cancel) { moveConflict = nil }
                .accessibilityIdentifier("sidebar-move-conflict-ok")
        } message: { conflict in
            Text(conflict.message)
                .accessibilityIdentifier("sidebar-move-conflict")
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        WorkspaceBrowserToolbar(
            selection: selection,
            onNew: { creating = .board },
            onNewFolder: { creating = .folder },
            // Dispatched on the selection's case, onto the very entry points the row's
            // context menu calls (ADR-0025 §D8, ADR-0023 §D1) - the toolbar and the menu
            // are two renderings of one command, never two code paths.
            onRename: { renameSelection() },
            onDelete: { deleteSelection() },
            // The same `expanded` binding the tree's context menu drives: two places to
            // reach one piece of state, never two pieces of state (ADR-0022 §D8).
            onExpandAll: { expanded = expandableFolders },
            onCollapseAll: { expanded = [] }
        )
    }

    /// The folder a **creation** lands in: the selected row's own folder, which for a
    /// board row is the folder holding it, so a new board or folder is made *beside* what
    /// is selected rather than inside it (ADR-0025 §D7). `""` - the vault root - with
    /// nothing selected.
    ///
    /// The rule is asked here rather than restated: `selection?.folder ?? ""` would be a
    /// second spelling of `target(for:)` below, and two spellings of one rule are what
    /// R-06 is about in the first place.
    private var targetFolder: String {
        Self.target(for: selection)
    }

    /// ADR-0025 §D7 / R-06: where a creation lands, read as one expression with no branch
    /// on which case the selection is - the whole content of "the toolbar cannot aim
    /// anywhere the visible row is not."
    ///
    /// `""` for nothing selected is the vault root, which is where a new board or folder
    /// belongs when no row says otherwise. Whether the two *mutating* verbs are offered
    /// at all is a different question with a different rule
    /// (`WorkspaceBrowserToolbar.canMutate(_:)`, §D8), asked of the selection rather than
    /// of this string - so nothing selected disables them there rather than aiming them
    /// here.
    static func target(for selection: WorkspaceSelection?) -> String {
        selection?.folder ?? ""
    }

    /// The collision predicate both sheets block on, live, so a name that is already
    /// taken is refused before anything is created rather than reported afterwards
    /// (ADR-0022 §D11, R-03).
    ///
    /// The same function the performing code guards with
    /// (`FolderFileOperations.nameIsAvailable`), reached through the vault's root - not a
    /// second spelling of the rule for the sheet to disagree with.
    private func nameIsAvailable(_ name: String, in parent: String) -> Bool {
        folderOperations?.nameIsAvailable(name, in: parent) ?? true
    }

    /// The same predicate asked about the kind of thing being named (ADR-0025 §D7):
    /// `CanvasStore.boardNameIsAvailable` for a board, the folder rule above for a folder.
    /// Read by both sheets - a rename collides with exactly what a creation collides with.
    ///
    /// Two rules and not one, because the two collisions are different ones: a board is
    /// refused by a `.canvas` of that name and by nothing else, so a *folder* called
    /// `prova` does not stop a `prova.canvas` beside it (R-04) - a file and a directory
    /// may share a name in one directory, and the old fold is what made that look like a
    /// clash. A folder is still refused by anything of that name, file or directory,
    /// which is what `FolderFileOperations.nameIsAvailable` asks the file system.
    ///
    /// Each is the very function the performing verb guards with, so the sheet cannot
    /// enable a «Crea» that `createBoard`/`createFolder` will then refuse (ADR-0022 §D11).
    private func nameIsAvailable(
        _ name: String, in parent: String, for kind: WorkspaceItemKind
    ) -> Bool {
        switch kind {
        case .board: canvasStore?.boardNameIsAvailable(name, in: parent) ?? true
        case .folder: nameIsAvailable(name, in: parent)
        }
    }

    // MARK: Verbs
    //
    // The browser decides, `WorkspaceView` performs (ADR-0022 §D10): create and rename
    // hand the sheet's answer straight to `actions`, which is where `flushPendingSave()`
    // and `open(board:)` bracket the vault call. Rename and delete both stop here first,
    // and for the row each one is about rather than for a decision - delete because how
    // much is inside a folder is a walk of its subtree, rename because the row is
    // whatever the click named. Each has a board arm and a folder arm, and the two never
    // share a verb: a board rename repoints nodes and rewrites markers where a folder
    // rename does neither (ADR-0025 §D6).

    /// Opens the rename sheet on the folder the caller names - the toolbar's target, or
    /// the row a context menu was opened on. Nothing here reads the selection back.
    private func requestRename(of folder: String) {
        renameTarget = PendingWorkspaceRename(kind: .folder, path: folder)
    }

    /// The same, for a board row: the `.canvas` path the row drew (ADR-0025 §D6).
    private func requestRenameBoard(of board: String) {
        renameTarget = PendingWorkspaceRename(kind: .board, path: board)
    }

    /// Reads the counts once, at the click, and shows the dialog (R-10). Once, rather
    /// than in the dialog's own body: `contentCounts` enumerates the whole subtree and a
    /// view body is evaluated as often as SwiftUI likes.
    private func confirmDelete(of folder: String) {
        pendingDelete = .folder(path: folder, counts: folderOperations?.contentCounts(at: folder))
    }

    /// The same dialog for a board, with nothing to count: deleting one removes one file
    /// and leaves the folder holding it exactly as it was (ADR-0025 §D6).
    private func confirmDeleteBoard(of board: String) {
        pendingDelete = .board(path: board)
    }

    /// The toolbar's «Rinomina», dispatched on the selection's case onto the same two
    /// entry points a row's context menu calls (ADR-0025 §D8).
    ///
    /// The `nil` arm is unreachable while the button is disabled by `canMutate(_:)`, and
    /// is written rather than forced: the two surfaces share the rule, not the guarantee
    /// that it was asked.
    private func renameSelection() {
        switch selection {
        case .folder(let folder): requestRename(of: folder)
        case .board(let path): requestRenameBoard(of: path)
        case .none: break
        }
    }

    /// The toolbar's «Elimina», the same dispatch as `renameSelection()` above.
    private func deleteSelection() {
        switch selection {
        case .folder(let folder): confirmDelete(of: folder)
        case .board(let path): confirmDeleteBoard(of: path)
        case .none: break
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: theme.spacing(.xs)) {
            Image(systemName: "rectangle.3.group")
                .foregroundStyle(theme.color(.textTertiary))
            Text("WORKSPACE").themedText(.caption, color: .textTertiary)
            Spacer()
            Image(systemName: "magnifyingglass").foregroundStyle(theme.color(.textTertiary))
            TextField("Filtra", text: $filter)
                .textFieldStyle(.plain)
                .themedText(.body)
                .accessibilityIdentifier("workspace-filter")
        }
        .padding(theme.spacing(.s))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace del vault")
        .accessibilityIdentifier("workspace-browser-header")
    }

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
    private var treeSelection: Binding<Set<String>> {
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

    private var folderTree: some View {
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
    private var flatList: some View {
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
    private func dropOnRoot(_ drops: [VaultItemDrag]) -> Bool {
        guard let items = drops.first?.items else { return false }
        return performMove(items, into: "")
    }

    /// One row, wired the same way in both lists.
    private func row(_ node: WorkspaceTree.Node, depth: Int) -> some View {
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
    private var moveContext: WorkspaceMoveContext {
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
    private func performMove(_ items: [VaultItemRef], into destination: String) -> Bool {
        dragging = []
        guard !items.isEmpty, Self.canDrop(items, onFolder: destination) else { return false }
        let refusals = actions.move(items, destination)
        guard refusals.isEmpty else {
            moveConflict = WorkspaceMoveConflict(reasons: refusals)
            return false
        }
        return true
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

    private func rebuild() {
        // The two file rules, rebuilt here with the rest of what the root decides rather
        // than on every access (see their declarations).
        canvasStore = vault.root.map { CanvasStore(root: $0) }
        folderOperations = vault.root.map { FolderFileOperations(store: NoteStore(root: $0)) }
        let boards = canvasStore?.allBoards() ?? []
        folders = canvasStore?.allFolders() ?? []
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
    private func refreshFilteredRows() {
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
    private func reveal(_ path: String?) {
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
    private var expandableFolders: Set<String> {
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
}

/// A board or a folder waiting for its rename sheet.
///
/// A wrapper rather than a bare `String` because `.sheet(item:)` asks for `Identifiable`,
/// and `.sheet(item:)` rather than `.sheet(isPresented:)` because the sheet is about one
/// named row: `RenameWorkspaceSheet` seeds its text field from the path at init, so a
/// presentation that had to read it back out of the selection would seed it from whatever
/// was selected when the sheet's body happened to be evaluated.
private struct PendingWorkspaceRename: Identifiable {
    let kind: WorkspaceItemKind
    /// What the verb is called with: a board's real `.canvas` path, or the folder's own.
    let path: String

    var id: String { path }

    /// What the sheet seeds its field from - the same path with a board's extension
    /// dropped, since the sheet asks for a name and `BoardFileOperations` puts the
    /// extension back (ADR-0025 §D6).
    var seed: String {
        switch kind {
        case .board: (path as NSString).deletingPathExtension
        case .folder: path
        }
    }
}

/// A board or a folder waiting for its delete to be confirmed, and what the dialog says
/// about it.
///
/// A folder's counts travel with it rather than being read from the dialog: they are a
/// walk of its subtree, and by the time the dialog is on screen the answer is already
/// known. A board has none to carry - it is one file - which is why this is a case rather
/// than a struct with two integers a board would have to spell as zero.
private enum PendingWorkspaceDelete {
    case board(path: String)
    /// `counts` is `nil` when `FolderFileOperations.contentCounts` could not read the
    /// folder (PG-048) - a stale selection, or no operations object at all - and must
    /// never be defaulted to zero: zero is the answer for a folder that is genuinely
    /// empty, not for one nobody could count.
    case folder(path: String, counts: (notes: Int, subfolders: Int)?)

    var path: String {
        switch self {
        case .board(let path): path
        case .folder(let path, _): path
        }
    }

    var name: String { (path as NSString).lastPathComponent }

    /// R-10's sentence for a folder, with the two nouns agreeing with their numbers - «1
    /// nota e 2 sottocartelle» rather than «1 note e 2 sottocartelle» - and the board's
    /// own, which has nothing to count and says what it costs instead. A folder whose
    /// content could not be read (PG-048) gets its own sentence naming that, rather than
    /// silently claiming "0 e 0".
    var message: String {
        switch self {
        case .board:
            "La board va nel Cestino del Finder, ma l'app non può annullare l'operazione."
        case .folder(_, .none):
            "Non è stato possibile leggere il contenuto della cartella. Va nel Cestino "
                + "del Finder, ma l'app non può annullare l'operazione."
        case .folder(_, .some(let counts)):
            "Verranno eliminate \(counts.notes) \(counts.notes == 1 ? "nota" : "note") e "
                + "\(counts.subfolders) \(counts.subfolders == 1 ? "sottocartella" : "sottocartelle"). "
                + "La cartella va nel Cestino del Finder, ma l'app non può annullare l'operazione."
        }
    }
}

/// A batch the vault refused, and the sentence the dialog says about it (R-07).
///
/// The reasons are `VaultMoveBatch.plan`'s own strings, carried up verbatim rather than
/// reworded here: they already name the conflicting path (`esiste già: 01 Progetti/b/b
/// .canvas`), which is the whole of what R-07 asks to be shown, and a second wording of
/// them here would be a second answer to "what went wrong".
///
/// Every reason, not the first: a batch of six can collide on two of them, and a dialog
/// naming one leaves the user to discover the other by trying again.
private struct WorkspaceMoveConflict {
    let reasons: [String]

    var message: String { reasons.joined(separator: "\n") }
}
