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
    @Environment(VaultController.self) var vault

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

    @State var filter = ""
    /// The folders currently open, by path. View state rather than a preference, for
    /// the same reason the note tree's is.
    @State var expanded: Set<String> = []
    /// The boards folded one row per folder - what the rows below are drawn from, what the
    /// selection binding resolves a clicked id against (ADR-0024 §D2), what the
    /// stale-selection drop is asked (§D7), and what "Espandi tutto" expands.
    ///
    /// The only tree this view holds. The `NoteTree` that used to sit beside it existed
    /// solely so a `NoteTree`-shaped `allFolders(in:)` could walk it for the expand-all
    /// set, and `WorkspaceTree.folders(in:)` answers that from the rows actually drawn -
    /// one tree, so the set of expandable ids cannot be a different set from the ids the
    /// rows carry.
    @State var workspaceTree: [WorkspaceTree.Node] = []
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
    @State var filteredRows: [WorkspaceTree.Node] = []
    /// Every folder of the vault, as the last scan found them - what the create sheet's
    /// parent picker offers (ADR-0025 §D1). The board list beside it is a local of
    /// `rebuild()`: the tree is the only thing that reads it, and the picker no longer
    /// infers folders from board paths.
    @State var folders: [String] = []
    /// The board rules over the open vault's root: `CanvasStore.init` resolves symlinks
    /// and standardizes the URL, and `boardNameIsAvailable` is asked live, on every
    /// keystroke of the create sheet, so this is built once per scan in `rebuild()` rather
    /// than once per call. The folder-side equivalent no longer lives here (PG-051):
    /// `nameIsAvailable`/`contentCounts` are read through `vault`, which owns the
    /// write-capable `FolderFileOperations` this view used to hold directly.
    @State var canvasStore: CanvasStore?
    /// Which creation is waiting for the sheet, `nil` for none - the presentation *is*
    /// the kind, so the two toolbar buttons cannot both be answered by one boolean that
    /// has forgotten which of them was pressed (ADR-0025 §D7).
    @State private var creating: WorkspaceItemKind?
    /// The rename waiting for its sheet, carrying the row it is about - `pendingDelete`'s
    /// shape below, for the same reason. Whoever asks names the row: the row's context
    /// menu knows which one was right-clicked, while the selection it also sets travels up
    /// to the controller and back down as a prop, so seeding the sheet from `targetFolder`
    /// made it depend on that round trip having landed first.
    @State var renameTarget: PendingWorkspaceRename?
    /// The delete waiting to be confirmed, with a folder's counts already read (R-10).
    @State var pendingDelete: PendingWorkspaceDelete?
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
    @State var selectedRows: Set<String> = []
    /// What the drag that is in flight carries, stored by the source row at drag start.
    ///
    /// `.dropDestination` has no payload-aware validation - its `isTargeted` closure is
    /// handed a `Bool` and never the payload (ADR-0026 §D5) - so the only way a folder row
    /// can decline to light up for a cycle is for the source side to have remembered what
    /// it started dragging. Empty between drags.
    @State var dragging: [VaultItemRef] = []
    /// The refused batch waiting to be named (R-07). A collision is accepted visually and
    /// then reported, because a row that stays dark shows no conflicting name (§D5).
    @State var moveConflict: WorkspaceMoveConflict?

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
                parents: WorkspaceFolderSheets.parentOptions(from: folders.map { FolderPath($0) }),
                initialParent: FolderPath(targetFolder),
                isNameAvailable: { name, parent in
                    nameIsAvailable(name.value, in: parent.value, for: kind)
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
                    nameIsAvailable(name.value, in: parent.value, for: pending.kind)
                },
                onConfirm: { newName in
                    renameTarget = nil
                    switch pending.kind {
                    case .board: actions.renameBoard(FolderPath(pending.path), newName)
                    case .folder: actions.rename(FolderPath(pending.path), newName)
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
                case .board(let path): actions.deleteBoard(FolderPath(path))
                case .folder(let path, _): actions.delete(FolderPath(path))
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
}

/// A board or a folder waiting for its rename sheet.
///
/// A wrapper rather than a bare `String` because `.sheet(item:)` asks for `Identifiable`,
/// and `.sheet(item:)` rather than `.sheet(isPresented:)` because the sheet is about one
/// named row: `RenameWorkspaceSheet` seeds its text field from the path at init, so a
/// presentation that had to read it back out of the selection would seed it from whatever
/// was selected when the sheet's body happened to be evaluated.
struct PendingWorkspaceRename: Identifiable {
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
enum PendingWorkspaceDelete {
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
struct WorkspaceMoveConflict {
    let reasons: [String]

    var message: String { reasons.joined(separator: "\n") }
}
