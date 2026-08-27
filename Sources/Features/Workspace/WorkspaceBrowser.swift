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
        .onChange(of: selection) { _, new in reveal(new?.path) }
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
            selection: selection,
            onNew: { isCreatingWorkspace = true },
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

    /// The toolbar's «Rinomina», dispatched on the selection's case onto the same two
    /// entry points a row's context menu calls (ADR-0025 §D8).
    ///
    /// The `nil` arm is unreachable while the button is disabled by `canMutate(_:)`, and
    /// is written rather than forced: the two surfaces share the rule, not the guarantee
    /// that it was asked.
    private func renameSelection() {
        switch selection {
        case .folder(let folder): requestRename(of: folder)
        case .board(let path): actions.renameBoard(path)
        case .none: break
        }
    }

    /// The toolbar's «Elimina», the same dispatch as `renameSelection()` above.
    private func deleteSelection() {
        switch selection {
        case .folder(let folder): confirmDelete(of: folder)
        case .board(let path): actions.deleteBoard(path)
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

    /// The `List`'s selection: derived from the value handed down, never stored beside it
    /// (ADR-0024 §D6). The tag is the row's own id - a board's file path or a folder's
    /// folder path (ADR-0025 §D3) - so the string travelling through this binding is the
    /// selection's `path` and nothing has to be derived from anything.
    private var treeSelection: Binding<String?> {
        Binding(
            get: { selection?.path },
            set: { id in
                guard let id else { return onSelect(nil) }
                // A `.tag`ed row only ever hands this setter an id it drew itself, so a
                // miss here means the tree and the click disagree - almost always a
                // rebuild (rename/delete/rescan) racing the click - not an ordinary
                // click. Recorded, not silent: without this the row still resolves as
                // `.folder`, so a desync reads identically to a legitimate folder row and
                // leaves no trace to find it by (ADR-0024 Gate 5.06 finding).
                guard let node = WorkspaceTree.node(withID: id, in: workspaceTree) else {
                    actions.recordDesync("workspace-tree: selected id \(id) resolved to no row")
                    return onSelect(.folder(id))
                }
                onSelect(Self.selection(for: node))
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
            selection: selection,
            onSelect: onSelect,
            onRename: { requestRename(of: $0) },
            onDelete: { confirmDelete(of: $0) },
            onRenameBoard: { actions.renameBoard($0) },
            onDeleteBoard: { actions.deleteBoard($0) }
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
    let selection: WorkspaceSelection?
    let onSelect: (WorkspaceSelection?) -> Void
    /// The two folder verbs, by folder path. The row does not perform them: it hands the
    /// path to the same closures the toolbar's buttons call, so the context menu is a
    /// second entry point rather than a second code path (ADR-0023 §D4).
    let onRename: (String) -> Void
    let onDelete: (String) -> Void
    /// The same two verbs for a board, by the `.canvas` file's own path (ADR-0025 §D6).
    /// Separate closures rather than one that branches, because the two file operations
    /// are different ones - a board rename repoints nodes and rewrites markers, a folder
    /// rename does neither - and this row already knows which kind it is.
    let onRenameBoard: (String) -> Void
    let onDeleteBoard: (String) -> Void

    /// One indent step. The rows are drawn flat inside a `List`, so the depth has to be
    /// paid for in padding rather than by nesting the views - `NoteTreeRow`'s constant,
    /// because the two sidebars indent by the same amount or they read as two designs.
    private static let indent: CGFloat = 14

    private var isExpanded: Bool { expanded.contains(node.id) }
    private var isSelected: Bool { selection?.path == node.id }
    private var hasChildren: Bool { !node.children.isEmpty }
    private var isFolder: Bool {
        if case .folder = node.kind { true } else { false }
    }

    /// What selecting this row means, asked of the one function the `List`'s binding also
    /// asks, so a click and a right-click cannot disagree (ADR-0023 §D4).
    private var picked: WorkspaceSelection { WorkspaceBrowser.selection(for: node) }

    @ViewBuilder
    var body: some View {
        taggedRow
        if isExpanded {
            ForEach(node.children, id: \.id) { child in
                WorkspaceRow(
                    node: child,
                    depth: depth + 1,
                    expanded: $expanded,
                    selection: selection,
                    onSelect: onSelect,
                    onRename: onRename,
                    onDelete: onDelete,
                    onRenameBoard: onRenameBoard,
                    onDeleteBoard: onDeleteBoard
                )
            }
        }
    }

    /// `.tag` **last in the chain**, on every row without exception.
    ///
    /// Last, because a modifier applied after it drops it and the failure is silent - the
    /// list lights nothing and swallows every click (`RootView.swift:205-208`). On every
    /// row, because ADR-0024 §D3's «foreign» board - the one kind that carried no tag and
    /// was therefore structurally unselectable - is gone with the concept: a `.canvas` is
    /// an ordinary, openable row wherever it lives and whatever it is called
    /// (ADR-0025 §D2), so the switch that used to decide this has nothing left to decide.
    private var taggedRow: some View {
        doubleClickable(content).tag(node.id)
    }

    /// R-05 / ADR-0025 §D9: a double click on a **folder** row expands or collapses it,
    /// and opens nothing - not even when the folder holds exactly one board.
    ///
    /// `.simultaneousGesture` and never `.onTapGesture(count: 2)`: the latter consumes the
    /// click, so `List(selection:)` would never see it and the row would stop selecting.
    /// Applied here, ahead of the `.tag` above, which stays the one modifier nothing may
    /// follow.
    ///
    /// Only where there is something to toggle, which is the same condition the chevron is
    /// drawn under - a double click on a childless row would otherwise write an id into
    /// `expanded` that no disclosure ever reads.
    ///
    /// This behaviour rests on a SwiftUI interaction this repository has not exercised
    /// before, so it is a manual-verification item rather than a unit-tested one, with a
    /// stated fallback (ADR-0025 §D9): if the simultaneous gesture does not fire, or fires
    /// at the cost of single-click selection, move the double click onto the chevron's
    /// existing hit target and record the finding here.
    @ViewBuilder
    private func doubleClickable(_ row: some View) -> some View {
        if isFolder && hasChildren {
            row.simultaneousGesture(TapGesture(count: 2).onEnded { toggle() })
        } else {
            row
        }
    }

    private var content: some View {
        HStack(spacing: theme.spacing(.xs)) {
            chevron
            // One weight for every row: the dimmed pair ADR-0024 §D3 drew a «foreign»
            // board in is gone with the concept it stood for (ADR-0025 §D2). A board is
            // openable wherever it lives, so nothing here is drawn as if it were not.
            Image(systemName: icon)
                .foregroundStyle(theme.color(.textSecondary))
            Text(node.name)
                .themedText(.body, color: .textPrimary)
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
        case .board:
            return isSelected ? "Workspace \(node.name), aperta" : "Workspace \(node.name)"
        case .folder:
            let base = "Cartella \(node.name), \(node.boardCount) Workspace"
            return isSelected ? "\(base), selezionata" : base
        }
    }

    /// The board symbol on a board row, the folder pair on a folder row - a direct read of
    /// the kind, since a row is one thing or the other and no longer both at once
    /// (ADR-0025 §D2). Nothing here is conditioned on the selection (R-02).
    private var icon: String {
        switch node.kind {
        case .board: return "rectangle.3.group"
        case .folder: return isExpanded ? "folder" : "folder.fill"
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
        // One gate now, and not restated here: `canMutate(_:)` is the same rule the
        // toolbar's two buttons are enabled by, asked of the same value in the second
        // place it is rendered (ADR-0023 §D1, §D3, ADR-0025 §D8). ADR-0024's second gate -
        // `selection(for:) != nil`, which refused a «foreign» board - went with the
        // concept: both kinds of row are renamed and deleted here (R-08).
        if WorkspaceBrowserToolbar.canMutate(picked) {
            Button("Rinomina…") { requestRename() }
            Button("Elimina…", role: .destructive) { requestDelete() }
        }
    }

    /// The selection first, for what it shows rather than for what it seeds: both verbs
    /// are handed this row's own path and neither reads the selection back, but a
    /// secondary click selects nothing by itself, and a sheet or a dialog opened over a
    /// row the list has not lit reads as acting on another one (ADR-0023 §D4).
    private func requestRename() {
        onSelect(picked)
        switch node.kind {
        case .folder: onRename(node.id)
        case .board(let path): onRenameBoard(path)
        }
    }

    /// `requestRename()`'s shape for the destructive verb, and the same reason for setting
    /// the selection first.
    private func requestDelete() {
        onSelect(picked)
        switch node.kind {
        case .folder: onDelete(node.id)
        case .board(let path): onDeleteBoard(path)
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
