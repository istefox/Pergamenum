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
/// `NoteTree.Node.Kind` is not extended for boards (D10). What the sidebar draws is one
/// fold further on: `WorkspaceTree.build(boards:boardPath:)` turns that tree into one row
/// per folder, with the board named after a folder drawn *on* that folder's row rather
/// than beside it (ADR-0024 §D2). This view renders the fold; it does not decide it.
struct WorkspaceBrowser: View {
    @Environment(\.theme) private var theme
    @Environment(VaultController.self) private var vault

    /// The folder currently selected in the tree - the lit row, and (through
    /// `WorkspaceTree.node(withID:in:)`) whether a board is drawn on it (ADR-0024 §D6).
    /// Owned by `WorkspaceController.current`, handed down as a value: this view no
    /// longer keeps a selection of its own that could drift from it (ADR-0024 §D4/F1).
    var selectedFolder: String?
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
    @State private var boards: [String] = []
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
    @State private var isCreatingWorkspace = false
    /// The rename waiting for its sheet, carrying the folder it is about - `pendingDelete`'s
    /// shape below, for the same reason. Whoever asks names the folder: the row's context
    /// menu knows which one was right-clicked, while the selection it also sets travels up
    /// to the controller and back down as a prop, so seeding the sheet from `targetFolder`
    /// made it depend on that round trip having landed first.
    @State private var renameTarget: PendingFolderRename?
    /// The delete waiting to be confirmed, with its counts already read (R-10).
    @State private var pendingDelete: PendingFolderDelete?

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
        .onChange(of: selectedFolder) { _, path in reveal(path) }
        // The filter's other input is the tree, refreshed at the end of `rebuild()`.
        .onChange(of: filter) { _, _ in refreshFilteredRows() }
        .sheet(isPresented: $isCreatingWorkspace) {
            NewWorkspaceSheet(
                parents: WorkspaceFolderSheets.parentOptions(from: boards),
                initialParent: targetFolder,
                isNameAvailable: nameIsAvailable,
                onConfirm: { name, parent in
                    isCreatingWorkspace = false
                    actions.create(name, parent)
                },
                onCancel: { isCreatingWorkspace = false }
            )
        }
        .sheet(item: $renameTarget) { pending in
            RenameWorkspaceSheet(
                folder: pending.folder,
                isNameAvailable: nameIsAvailable,
                onConfirm: { newName in
                    renameTarget = nil
                    actions.rename(pending.folder, newName)
                },
                onCancel: { renameTarget = nil }
            )
        }
        // Neither verb is journalled (ADR-0022 §D6), so this dialog is the whole of the
        // "are you sure" this feature has: the recovery afterwards is the Finder's
        // Trash, not an undo. It says what is inside before it goes there (R-10).
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
                actions.delete(pending.folder)
            }
            .accessibilityIdentifier("workspace-delete-confirm")
            Button("Annulla", role: .cancel) { pendingDelete = nil }
        } message: { pending in
            Text(pending.message)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        WorkspaceBrowserToolbar(
            target: targetFolder,
            onNew: { isCreatingWorkspace = true },
            onRename: { requestRename(of: targetFolder) },
            onDelete: { confirmDelete(of: targetFolder) },
            // The same `expanded` binding the tree's context menu drives: two places to
            // reach one piece of state, never two pieces of state (ADR-0022 §D8).
            onExpandAll: { expanded = expandableFolders },
            onCollapseAll: { expanded = [] }
        )
    }

    /// The folder the toolbar's verbs act on: the selected row, with no fallback
    /// (ADR-0024 §D7 withdraws ADR-0022 §D9's fallback onto the open board's folder -
    /// with nothing selected, Rinomina/Elimina are now disabled rather than aiming at a
    /// row the user cannot see).
    ///
    /// The rule is asked here rather than restated: `selectedFolder ?? ""` would be a
    /// second spelling of `target(for:)` below, and two spellings of one rule are what
    /// R-06 is about in the first place.
    ///
    /// Constructing `.folder` is not a claim that no board is drawn on that row. This
    /// view is handed the folder path rather than the selection (§D6), and
    /// `target(for:)` does not branch on the case - so recovering the case from this
    /// view's own tree would be a walk whose answer the toolbar immediately discards.
    private var targetFolder: String {
        Self.target(for: selectedFolder.map { WorkspaceSelection.folder($0) })
    }

    /// ADR-0024 §D7 / R-06: the toolbar's target read as one expression, with no branch
    /// on which case the selection is - the whole content of "the toolbar cannot aim
    /// anywhere the visible row is not."
    ///
    /// `""` for nothing selected is what leaves «Rinomina» and «Elimina» disabled, and
    /// it leaves them disabled through the enablement rule that already exists rather
    /// than through a second one: `WorkspaceBrowserToolbar.canMutate(folder:)` refuses
    /// the vault root, and nothing selected reads as the root here (ADR-0023 §D1, one
    /// rule and two surfaces).
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

    // MARK: Verbs
    //
    // The browser decides, `WorkspaceView` performs (ADR-0022 §D10): create and rename
    // hand the sheet's answer straight to `actions`, which is where `flushPendingSave()`
    // and `open(folder:)` bracket the vault call. Rename and delete both stop here first,
    // and for the folder each one is about rather than for a decision - delete because
    // how much is inside is a walk of the subtree, rename because the folder is whatever
    // the click named.

    /// Opens the rename sheet on the folder the caller names - the toolbar's target, or
    /// the row a context menu was opened on. Nothing here reads the selection back.
    private func requestRename(of folder: String) {
        renameTarget = PendingFolderRename(folder: folder)
    }

    /// Reads the counts once, at the click, and shows the dialog (R-10). Once, rather
    /// than in the dialog's own body: `contentCounts` enumerates the whole subtree and a
    /// view body is evaluated as often as SwiftUI likes.
    private func confirmDelete(of folder: String) {
        let counts = folderOperations?.contentCounts(at: folder) ?? (notes: 0, subfolders: 0)
        pendingDelete = PendingFolderDelete(
            folder: folder, notes: counts.notes, subfolders: counts.subfolders
        )
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

    /// The `List`'s selection: derived from the value handed down, never stored beside it
    /// (ADR-0024 §D6).
    ///
    /// The setter resolves the clicked id against this view's own tree, which is the only
    /// place that knows whether a folder owns a board and therefore whether the click
    /// means `.board` or `.folder`. A `.foreignBoard` row carries no `.tag` (§D3), so the
    /// lookup cannot land on one.
    private var treeSelection: Binding<String?> {
        Binding(
            get: { selectedFolder },
            set: { id in
                guard let id else { return onSelect(nil) }
                // A `.tag`ed row only ever hands this setter an id it drew itself, so a
                // miss here means the tree and the click disagree - almost always a
                // rebuild (rename/delete/rescan) racing the click - not an ordinary
                // click. Recorded, not silent: without this the row still resolves as
                // `.folder`, so a desync reads identically to a legitimate board-less
                // folder and leaves no trace to find it by (ADR-0024 Gate 5.06 finding).
                guard let node = WorkspaceTree.node(withID: id, in: workspaceTree) else {
                    actions.recordDesync("workspace-tree: selected id \(id) resolved to no row")
                    return onSelect(.folder(id))
                }
                // `Self.selection(for:)` returns `nil` only for `.foreignBoard`, which
                // carries no `.tag` (§D3) and so cannot reach this setter through a click
                // at all - reachable only if that invariant regresses, which is worth
                // recording rather than silently opening nothing.
                guard let picked = Self.selection(for: node) else {
                    actions.recordDesync("workspace-tree: selected id \(id) resolved to a foreignBoard row")
                    return onSelect(.folder(id))
                }
                onSelect(picked)
            }
        )
    }

    /// Which case a row means: `.board` when the folder owns one, `.folder` when it only
    /// groups (ADR-0024 §D5), `nil` for a `.foreignBoard`, which is not in the selection's
    /// namespace at all (§D3).
    ///
    /// One expression, read by the `List`'s binding above and by the row's context menu,
    /// so a click and a right-click cannot disagree about what was selected (ADR-0023 §D4).
    ///
    /// `nonisolated` for the reason spelled out at `rows(matching:in:)`: these three
    /// statics are pure functions of their arguments, and a pure function that carries
    /// the view's actor isolation is a trap waiting for the first caller that is not on
    /// the main actor.
    nonisolated static func selection(for node: WorkspaceTree.Node) -> WorkspaceSelection? {
        switch node.kind {
        case .workspace(let board):
            return board == nil ? .folder(node.id) : .board(folder: node.id)
        case .foreignBoard:
            return nil
        // ADR-0025 §D3: the row's own id, whichever kind it is - a board names itself by
        // its file path and a folder by its folder path, so nothing here derives one from
        // the other. TODO(ADR-0025 Task 5): the two ADR-0024 arms above go with their
        // cases and this function stops being optional (every row is selectable now).
        case .folder:
            return .folder(node.id)
        case .board(let path):
            return .board(path: path)
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
    }

    /// One row, wired the same way in both lists.
    private func row(_ node: WorkspaceTree.Node, depth: Int) -> some View {
        WorkspaceRow(
            node: node,
            depth: depth,
            expanded: $expanded,
            selectedFolder: selectedFolder,
            onSelect: onSelect,
            onRename: { requestRename(of: $0) },
            onDelete: { confirmDelete(of: $0) }
        )
    }

    // MARK: Tree state

    private func rebuild() {
        let store = vault.root.map { CanvasStore(root: $0) }
        // The folder verbs' file rules, rebuilt here with the rest of what the root
        // decides rather than on every access (see the declaration).
        folderOperations = vault.root.map { FolderFileOperations(store: NoteStore(root: $0)) }
        boards = store?.allBoards() ?? []
        // Folders and boards, two lists and two kinds of row (ADR-0025 §D2). No naming
        // rule is asked any more: a board is a row because it is a file, not because a
        // folder is named after it. With no vault open there is nothing to draw.
        workspaceTree = store.map { WorkspaceTree.build(folders: $0.allFolders(), boards: boards) } ?? []
        // A selection is a path, and a rename or a delete has just moved or removed the
        // folder it names - this runs on `scanGeneration`, which both of them bump.
        // `selectedFolder` is owned by the controller now (ADR-0024 §D6), so dropping a
        // stale one means asking for `nil` through `onSelect` rather than assigning
        // local state - there no longer is any to assign.
        //
        // Asked of the tree the rows are actually drawn from, and that is the whole of
        // it: `NoteTree` has no node for the vault root (ADR-0024 F7), so a check made
        // against a `NoteTree` walk would find a root board's selection - spelled `""` -
        // missing and drop it on every single rescan (§D7).
        if let selectedFolder, !WorkspaceTree.folders(in: workspaceTree).contains(selectedFolder) {
            onSelect(nil)
        }
        reveal(selectedFolder)
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

    /// Opens the folders above a selected **folder**, so a board opened from somewhere
    /// that is not this list - the breadcrumb, a route, a folder card, the editor - is
    /// visible here rather than merely selected inside a closed folder.
    ///
    /// The path is a folder now rather than a board file (ADR-0024 §D2), and
    /// `NoteTree.ancestors(of:)` is already right for it: it drops the last component,
    /// which for a folder is the folder itself, leaving its strict ancestors - the set to
    /// open, without opening the selected row itself.
    private func reveal(_ path: String?) {
        guard let path else { return }
        expanded.formUnion(NoteTree.ancestors(of: path))
    }

    /// What "Espandi tutto" opens, from both surfaces that offer it (the toolbar button
    /// and the tree's context menu, ADR-0022 §D8): every `.workspace` row's id of the tree
    /// the rows are drawn from.
    ///
    /// Asked of `WorkspaceTree.folders(in:)` rather than of a walk of this view's own -
    /// the fold already answers "which ids are folder rows" for the stale-selection drop
    /// and the selection setter, and an expand-all built on a second walk is a second
    /// answer to the same question. The root row (`""`) is in the set and its being there
    /// draws nothing: `WorkspaceTree.build` synthesises it with no children.
    private var expandableFolders: Set<String> {
        Set(WorkspaceTree.folders(in: workspaceTree))
    }

    /// The filtered list's input (ADR-0024 Task 3, R-09): every `.workspace` row of
    /// `tree` whose `id` or `name` contains `filter`, case-insensitively. `.workspace`
    /// only - a `.foreignBoard` carries no `.tag` and can never be a search result a
    /// click could act on (ADR-0024 §D3).
    ///
    /// Matching on `id` alone is a path-only filter and loses the root: its `id` is
    /// `""`, which never contains a non-empty `filter`. `name` is what makes the root
    /// row ("Labs" today) reachable while a filter is typed.
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
            guard case .workspace = row.node.kind else { return nil }
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
    /// TODO(ADR-0025 Task 5): the two ADR-0024 arms go with their cases.
    nonisolated static func identifier(for node: WorkspaceTree.Node) -> String {
        switch node.kind {
        case .workspace(let board):
            if let board { return "workspace-board-\(board)" }
            return "workspace-folder-\(node.id)"
        case .foreignBoard(let path), .board(let path):
            return "workspace-board-\(path)"
        case .folder:
            return "workspace-folder-\(node.id)"
        }
    }
}

/// A folder waiting for its rename sheet.
///
/// A wrapper rather than a bare `String` because `.sheet(item:)` asks for `Identifiable`,
/// and `.sheet(item:)` rather than `.sheet(isPresented:)` because the sheet is about one
/// named folder: `RenameWorkspaceSheet` seeds its text field from `folder` at init, so a
/// presentation that had to read the folder back out of the selection would seed it from
/// whatever was selected when the sheet's body happened to be evaluated.
private struct PendingFolderRename: Identifiable {
    let folder: String

    var id: String { folder }
}

/// A folder waiting for its delete to be confirmed, and what the dialog says about it.
///
/// The counts travel with it rather than being read from the dialog: they are a walk of
/// the folder's subtree, and by the time the dialog is on screen the answer is already
/// known.
private struct PendingFolderDelete {
    let folder: String
    let notes: Int
    let subfolders: Int

    var name: String { (folder as NSString).lastPathComponent }

    /// R-10's sentence, with the two nouns agreeing with their numbers - «1 nota e 2
    /// sottocartelle» rather than «1 note e 2 sottocartelle».
    var message: String {
        let notesText = "\(notes) \(notes == 1 ? "nota" : "note")"
        let subfoldersText = "\(subfolders) \(subfolders == 1 ? "sottocartella" : "sottocartelle")"
        return "Verranno eliminate \(notesText) e \(subfoldersText). "
            + "La cartella va nel Cestino del Finder, ma l'app non può annullare l'operazione."
    }
}

/// One row of the Workspace tree, and its subtree.
///
/// Flat and recursive, `NoteTreeRow`'s shape (`NoteListPane.swift:290-322`): the row, and
/// then - as a **sibling**, never as its content - the expanded children (ADR-0024 §D1).
/// The chevron is drawn by hand and the depth is paid for in padding, so every row of the
/// tree is a row of the one enclosing `List` and can carry a `.tag` the selection binding
/// is able to satisfy. A `DisclosureGroup`'s label is not such a row, which is why there
/// is none left in this file.
///
/// `expanded` is the browser's shared set rather than state of this row's own: "Espandi
/// tutto" and a board revealed from outside both have to be able to open a folder this row
/// did not open itself.
private struct WorkspaceRow: View {
    @Environment(\.theme) private var theme

    let node: WorkspaceTree.Node
    let depth: Int
    @Binding var expanded: Set<String>
    /// The lit row, read one way only (ADR-0024 §D9). Nothing drawn here is conditioned
    /// on it - the system draws the selected row's fill - except what VoiceOver is told.
    let selectedFolder: String?
    let onSelect: (WorkspaceSelection?) -> Void
    /// The two folder verbs, by folder path. The row does not perform them: it hands the
    /// path to the same closures the toolbar's buttons call, so the context menu is a
    /// second entry point rather than a second code path (ADR-0023 §D4).
    let onRename: (String) -> Void
    let onDelete: (String) -> Void

    /// One indent step. The rows are drawn flat inside a `List`, so the depth has to be
    /// paid for in padding rather than by nesting the views - `NoteTreeRow`'s constant,
    /// because the two sidebars indent by the same amount or they read as two designs.
    private static let indent: CGFloat = 14

    private var isExpanded: Bool { expanded.contains(node.id) }
    private var isSelected: Bool { selectedFolder == node.id }
    private var hasChildren: Bool { !node.children.isEmpty }
    private var isForeign: Bool {
        if case .foreignBoard = node.kind { true } else { false }
    }

    @ViewBuilder
    var body: some View {
        taggedRow
        if isExpanded {
            ForEach(node.children, id: \.id) { child in
                WorkspaceRow(
                    node: child,
                    depth: depth + 1,
                    expanded: $expanded,
                    selectedFolder: selectedFolder,
                    onSelect: onSelect,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
        }
    }

    /// `.tag` **last in the chain**, and only on a `.workspace` node.
    ///
    /// Last, because a modifier applied after it drops it and the failure is silent - the
    /// list lights nothing and swallows every click (`RootView.swift:205-208`). Only on a
    /// `.workspace`, because a `.canvas` not named after the folder holding it is not
    /// something this app can open at all: no tag makes its row structurally
    /// unselectable rather than disabled by a rule somebody has to remember to apply
    /// (ADR-0024 §D3).
    @ViewBuilder
    private var taggedRow: some View {
        switch node.kind {
        case .workspace: content.tag(node.id)
        case .foreignBoard: content
        // TODO(ADR-0025 Task 5): placeholder exhaustiveness arm for the two new `Kind`
        // cases - this view still draws exclusively from the old `.workspace`/
        // `.foreignBoard` tree (`rebuild()`'s temporary `build(boards:boardPath:)` call),
        // so this branch is unreachable until Task 5's rewrite, which is where every row
        // gets a `.tag` (nothing is unselectable any more).
        case .folder, .board: content
        }
    }

    private var content: some View {
        HStack(spacing: theme.spacing(.xs)) {
            chevron
            Image(systemName: icon)
                .foregroundStyle(theme.color(isForeign ? .textTertiary : .textSecondary))
            Text(node.name)
                .themedText(.body, color: isForeign ? .textSecondary : .textPrimary)
                .lineLimit(1)
            Spacer(minLength: theme.spacing(.xs))
            // Only where one was shown before the fold: the rows that have something
            // under them (ADR-0024 §D2).
            if hasChildren {
                Text("\(node.boardCount)").themedText(.caption, color: .textTertiary)
            }
        }
        .padding(.leading, CGFloat(depth) * Self.indent)
        .contentShape(Rectangle())
        // `.contain`, never `.combine`, and the difference is the whole of R-02/R-03.
        // `.combine` folds the row's texts into a single element whose macOS role is
        // `StaticText`, and a `StaticText` carries its words in `AXValue`: the label
        // below arrived in XCUITest's `value` while its `label` stayed empty, so no
        // assertion on the ", aperta"/", selezionata" suffix could ever match. Read out
        // of a failing run's exported UI hierarchy rather than guessed - `StaticText,
        // identifier: 'workspace-board-…', value: Workspace Dettagli…, Selected` - and
        // it is the same trap `UITests/WorkspaceIntegrationUITests.swift:176-181` already
        // wrote down for a plain `Text`. `.contain` makes the row a `Group`, which is the
        // shape that puts the words in `label`: `TaskPanelRow` (`LinkedTasksPanel.swift`)
        // and this pane's own `workspace-browser-header` are both already that.
        //
        // The second half costs more than the label and is the reason this is not a
        // cosmetic choice: `.combine` swallowed the chevron's own `.onTapGesture` into
        // the one merged element, and the merged element's activation point became the
        // triangle's - so a click on a row *with children* landed on the triangle and
        // expanded the folder instead of selecting it, while a childless row selected
        // normally. Measured, not inferred: the failing run's synthesized event drove the
        // pointer to x=218 (the triangle) on `Progetti`, against x=319 (the row's centre)
        // on the root board's row one click earlier. Under `.contain` the triangle is an
        // element of its own again and the row's hit point is the row's - which is
        // «the triangle expands, the row selects» (ADR-0024 §D5) holding for the
        // accessibility tree, not only for a mouse aimed by a person.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        // Belt and braces beside the label: whether this trait reaches XCUITest's
        // `isSelected` for custom `List` row content on macOS is unverified here, so the
        // label above carries the state in words and is what a test may depend on
        // (ADR-0024 §D9, R-13).
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(WorkspaceBrowser.identifier(for: node))
        // Outside the combined accessibility element, the order the row carried before
        // this rewrite - and still ahead of the `.tag` that `taggedRow` applies last of
        // all, which is the one modifier nothing may follow.
        .contextMenu { menu }
    }

    /// The state said in words, because the colour that used to say it is gone (R-02) and
    /// was never something a screen reader could read anyway (ADR-0024 §D9).
    private var accessibilityLabel: String {
        switch node.kind {
        case .workspace(let board) where board != nil:
            return isSelected ? "Workspace \(node.name), aperta" : "Workspace \(node.name)"
        case .workspace:
            let base = "Cartella \(node.name), \(node.boardCount) Workspace"
            return isSelected ? "\(base), selezionata" : base
        case .foreignBoard:
            return "Board \(node.name), non apribile da Pergamenum"
        // TODO(ADR-0025 Task 5): placeholder exhaustiveness arm, same reasoning as
        // `taggedRow` above - unreachable until Task 5's rewrite.
        case .folder, .board:
            return ""
        }
    }

    /// A board on a row that owns one, a folder on a row that does not, and the board
    /// symbol dimmed for a `.canvas` this app cannot open. Nothing here is conditioned on
    /// the selection (R-02).
    private var icon: String {
        switch node.kind {
        case .workspace(let board):
            return board == nil ? (isExpanded ? "folder" : "folder.fill") : "rectangle.3.group"
        case .foreignBoard:
            return "rectangle.3.group"
        // TODO(ADR-0025 Task 5): placeholder exhaustiveness arm, same reasoning as
        // `taggedRow` above - unreachable until Task 5's rewrite.
        case .folder, .board:
            return "rectangle.3.group"
        }
    }

    /// Its own hit target, which is what keeps «the triangle expands, the row selects»
    /// implementable at all (ADR-0024 §D5). A row with nothing under it keeps the space
    /// so the names line up.
    @ViewBuilder
    private var chevron: some View {
        if hasChildren {
            triangle
                .contentShape(Rectangle())
                .onTapGesture { toggle() }
        } else {
            triangle.hidden()
        }
    }

    private var triangle: some View {
        Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isExpanded && hasChildren ? 90 : 0))
            .themedText(.caption, color: .textTertiary)
    }

    /// On the row's own `HStack`, where ADR-0023 §D2 put it - and §D2's warning now has
    /// nothing left to warn about: there is no `DisclosureGroup` in this file for a
    /// modifier to leak out of onto every disclosed descendant, so its conclusion holds by
    /// construction rather than by care (ADR-0024 §D1).
    ///
    /// Plain titles, no SF Symbols: the toolbar keeps its `pencil`/`trash` and this menu
    /// keeps the absence of one, which is what «the same symbol» means for a surface that
    /// draws none (ADR-0023 §D1).
    @ViewBuilder
    private var menu: some View {
        // Two gates, neither of them restated here: `selection(for:)` is nil for a
        // `.foreignBoard`, whose id is a file path rather than a folder and which the
        // folder verbs have no business acting on (ADR-0024 §D3), and
        // `canMutate(folder:)` is the same rule the toolbar's two buttons are enabled by,
        // asked in the second place it is rendered (ADR-0023 §D1, §D3).
        if let picked = WorkspaceBrowser.selection(for: node),
           WorkspaceBrowserToolbar.canMutate(folder: node.id) {
            // The selection first, now for what it shows rather than for what it seeds:
            // both verbs hand `node.id` on and neither reads the selection back, but a
            // secondary click selects nothing by itself, and a sheet or a dialog opened
            // over a row the list has not lit reads as acting on another one
            // (ADR-0023 §D4).
            Button("Rinomina…") {
                onSelect(picked)
                onRename(node.id)
            }
            Button("Elimina…", role: .destructive) {
                onSelect(picked)
                onDelete(node.id)
            }
        }
    }

    private func toggle() {
        if isExpanded {
            expanded.remove(node.id)
        } else {
            expanded.insert(node.id)
        }
    }
}
